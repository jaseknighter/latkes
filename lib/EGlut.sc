//EGlut: grandchild of Glut, parent of ZGlut

EGlut {
  classvar ngvoices = 4;
  
  var s;
  var context;
  var pg;
	var effect;
  var <live_buffers;
	var <file_buffers;
	var <gvoices;
	var effectBus;
	var <phases;
	var <rec_phases;
	var <levels;
	var <gr_envbufs;
  var updating_gr_envbufs=false;
  var prev_sig_pos1=0,prev_sig_pos2=0,prev_sig_pos3=0,prev_sig_pos4=0;

  var lua_sender;
  var sc_sender;

  var osc_funcs;
  var recorders;
  var max_buffer_length=80;
  var max_size=5;
    

	*new {
		arg argServer,context,eng;
		^super.new.init(argServer,context,eng);

	}

	// read from an existing buffer into the granulation buffsers
	setBufStartEnd { arg voice, buf, mode,sample_start, sample_length, rec_phase;
    var start = sample_start/max_buffer_length;
    var end = (sample_start + sample_length)/max_buffer_length;
    // var rec_phase=rec_phases[voice].getSynchronous;
    // (["rec_phase new/current",rec_phase,rec_phases[voice].getSynchronous]).postln;
    recorders[voice].set(
      \buf_pos_start, start, 
      \buf_pos_end, end,  
      \pos,rec_phase,
      \t_reset_pos, 1
    );
    recorders[voice + ngvoices].set(
      \buf_pos_start, start, 
      \buf_pos_end, end,  
      \pos,rec_phase,
      \t_reset_pos, 1
    );
    
    gvoices[voice].set(\buf_pos_start, start);
    gvoices[voice].set(\buf_pos_end, end);    
	}

  // disk read
	readDisk { arg voice, path, sample_start, sample_length;
    var startframe = 0;
    if (File.exists(path), {
      // load stereo files and duplicate GrainBuf for stereo granulation
      var newbuf,newbuf2;
      var file, numChannels, soundfile_duration;
      var soundfile = SoundFile.new;
      soundfile.openRead(path.asString.standardizePath);
      numChannels = soundfile.numChannels;
      soundfile_duration = soundfile.duration;
      soundfile.close;
      ["file read into buffer...soundfile_duration,sample_start,sample_length",soundfile_duration,sample_start, sample_length].postln;
      lua_sender.sendMsg("/lua_eglut/on_eglut_file_loaded",voice);

       newbuf = Buffer.readChannel(context.server, path, channels:[0], action:{
        arg newbuf;
        file_buffers[voice].zero;
        newbuf.copyData(file_buffers[voice]);
        gvoices[voice].set(\buf, file_buffers[voice]);
        gvoices[voice].set(\buf_pos_start, sample_start/max_buffer_length);
        gvoices[voice].set(\buf_pos_end, (sample_start + sample_length)/max_buffer_length);

        ["newbuf",voice,file_buffers[voice]].postln;

        if (numChannels > 1,{
          "stereo file: read 2nd channel into buffer's 2nd channel".postln;
          newbuf2 = Buffer.readChannel(context.server, path, channels:[1], action:{
            arg newbuf2;
            file_buffers[voice+ngvoices].zero;
            newbuf2.copyData(file_buffers[voice+ngvoices]);
            gvoices[voice].set(\buf2, file_buffers[voice+ngvoices]);
            ["newbuf2",voice,file_buffers[voice+ngvoices]].postln;
          });
        },{
          "mono file: read 1st channel into buffer's 2nd channel".postln;
          newbuf2 = Buffer.readChannel(context.server, path, channels:[0,0], action:{

            arg newbuf2;
            file_buffers[voice+ngvoices].zero;
            newbuf2.copyData(file_buffers[voice+ngvoices]);
            gvoices[voice].set(\buf2, file_buffers[voice+ngvoices]);
            ["newbuf2",voice,file_buffers[voice+ngvoices]].postln;
          });
        });
      });
    });
	}


  ///////////////////////////////////
  //init 
	init {
		arg argServer, engContext, eng;
    var thisEngine;

    "init eglut".postln;
    osc_funcs=Dictionary.new();
    
    lua_sender = NetAddr.new("127.0.0.1",10111);   
    sc_sender=NetAddr.new("127.0.0.1",57120);   
    
		s=argServer;
    context = engContext;
    thisEngine = eng;

    // rec_phases=Bus.control(context.server,ngvoices*2);
    rec_phases = Array.fill(ngvoices*2, { arg i;
      Bus.control(context.server)
    });

    live_buffers = Array.fill(ngvoices*2, { arg i;
      var num_samples=s.sampleRate * max_buffer_length;
      Buffer.alloc(s,num_samples,1);
    });

    s.sync;

    file_buffers = Array.fill(ngvoices*2, { arg i;
      Buffer.alloc(
        s,
        s.sampleRate * max_buffer_length,
      );
    });
    
    SynthDef("live_recorder", {
      arg voice=0,out=0,in=0, 
          buf=0, rate=1,
          pos=0,buf_pos_start=0,buf_pos_end=1,t_reset_pos=0,
          rec_level=1,pre_level=0;
      var buf_dur,buf_pos;
      var sig=SoundIn.ar(in);
      var rec_buf_reset = Impulse.kr(
            freq:((buf_pos_end-buf_pos_start)*max_buffer_length).reciprocal,
            phase:pos
          );
      var recording_offset = buf_pos_start*max_buffer_length*SampleRate.ir;
      
      // var ff=ToggleFF.kr(rec_buf_reset);
      // (voice < 1 * ff).poll;
      
      buf_dur = BufDur.kr(buf);
      // buf_pos = Phasor.kr(trig: t_reset_pos + rec_buf_reset,
      buf_pos = Phasor.kr(trig: t_reset_pos,
        rate: buf_dur.reciprocal / ControlRate.ir * rate,
        start:buf_pos_start, end:buf_pos_end, resetPos: pos);

      RecordBuf.ar(sig, buf, offset: recording_offset + (t_reset_pos * pos), 
                   recLevel: rec_level, preLevel: pre_level, run: 1.0, loop: 1.0, 
                   trigger: t_reset_pos + rec_buf_reset, doneAction: 0);
                  //  trigger: rec_buf_reset, doneAction: 0);

      
      // (voice < 1 * t_reset_pos).poll;
      // (voice < 1 * pos).poll;
      // (voice < 1 * pos).poll;
      // (buf_pos).poll;
      // (voice < 1 * buf_pos_start*max_buffer_length).poll;
      // (voice < 1 * buf_pos).poll;
      // (voice < 1 * buf_pos*max_buffer_length).poll;
      // (voice < 1 * (((buf_pos_end-buf_pos_start)*max_buffer_length).reciprocal)).poll;
      // (voice < 1 * rec_buf_reset).poll;
      // (voice < 1 * t_reset_pos).poll;
      // (voice < 1 * buf_pos_start).poll;
      // (voice < 1 * buf_pos_end).poll;



      SendReply.kr(Impulse.kr(30), "/eglut_rec_phases", [voice,buf_pos]);

    }).add;

    s.sync;
    recorders = Array.fill(ngvoices*2, { arg i;
      var chan;
      if(i < ngvoices,{chan=0},{chan=1});
      (["add recorder",ngvoices,i,chan]).postln;
      Synth(\live_recorder, [\voice, i,\buf,live_buffers[i],\in,chan]);
    });
    s.sync;
    recorders.postln;

    SynthDef("grain_synth", {
      arg voice, out, effectBus, phase_out, level_out, buf, buf2,
      gate=0, pos=0, 
      buf_pos_start=0, 
      rec_phase=0,
      buf_pos_end=1, 
      sample_length=10/max_buffer_length,
      speed=1, jitter=0, spread_sig=0, voice_pan=0,	
      size=0.1, size_jitter=0, density=20, density_jitter=0,pitch=1, spread_pan=0, gain=1, envscale=1,
      t_reset_pos=0, cutoff=20000, q, send=0, 
      ptr_delay=0.2,sync_to_rec_head=1,
      subharmonics=0,overtones=0, gr_envbuf = -1,
      spread_sig_offset1=0, spread_sig_offset2=0, spread_sig_offset3=0;

      var grain_trig=1;
      var grain_jitter_trig=1;
      var trig_rnd;
      var size_jitter_sig;
      var density_jitter_sig;
      var jitter_sig, jitter_sig2, jitter_sig3, jitter_sig4;
      var sig_pos;
      var sig_pos1, sig_pos2, sig_pos3, sig_pos4;
      var sig2_pos1, sig2_pos2, sig2_pos3, sig2_pos4;
      var active_sig_pos1, active_sig_pos2, active_sig_pos3, active_sig_pos4;
      var window_sig_pos1, window_sig_pos2, window_sig_pos3, window_sig_pos4;
      var buf_dur;
      var pan_sig;
      var pan_sig2;
      var env;
      var level=1;
      var grain_env;
      var main_vol=1.0/(1.0+subharmonics+overtones);
      var subharmonic_vol=subharmonics/(1.0+subharmonics+overtones);
      var overtone_vol=overtones/(1.0+subharmonics+overtones);
      var ptr;
      var reset_pos=1;
      var sig,sig2;
      var buf_pos, buf_pos2, out_of_window=0;
      var phasor_start, phasor_end; 
      var localin;
      var switch=0,switch1,switch2,switch3,switch4;
      var reset_sig_ix=0,crossfade;
      
      pos = pos.linlin(0,1,buf_pos_start,buf_pos_end);
      // pos.poll;
      size_jitter_sig = TRand.kr(trig: Impulse.kr(density),
        lo: size_jitter.neg,
        hi: size_jitter);

      // make sure size+size jitter is greater than 0, otherwise ignore the jitter
      size = ((size+size_jitter_sig > 0) * (size+size_jitter_sig)) + ((1-(size+size_jitter_sig > 0)) * size);
      size = ((size+size_jitter_sig < max_size) * (size+size_jitter_sig)) + ((1-(size+size_jitter_sig < max_size)) * size);
      size = Lag.kr(size);



      density_jitter_sig = TRand.kr(trig: Impulse.kr(density),
        lo: density_jitter.neg,
        hi: density_jitter);

      density = Lag.kr(density+density_jitter_sig);

      spread_pan = Lag.kr(spread_pan);

      cutoff = Lag.kr(cutoff);
      q = Lag.kr(q);
      send = Lag.kr(send);
      pitch = Lag.kr(pitch,0.25);
      
      grain_trig = Impulse.kr(density);
      buf_dur = BufDur.kr(buf);

      pan_sig = TRand.kr(trig: grain_trig,
        lo: -1,
        hi: (2*spread_pan)-1);

      pan_sig2 = TRand.kr(trig: grain_trig,
        lo: 1-(2*spread_pan),
        hi: 1);

      // set the jitter signal and make sure it is only jittering
      // in the direction of the playhead.
      //      note: this is required for getting rid of clicks 
      //      when the playhead is outside the window)
      jitter_sig = TRand.kr(trig: grain_trig,
        lo: (speed < 0) * buf_dur.reciprocal.neg * jitter,
        hi: (speed >= 0) * buf_dur.reciprocal * jitter);
      jitter_sig2 = TRand.kr(trig: grain_trig,
        lo: (speed < 0) * buf_dur.reciprocal.neg * jitter,
        hi: (speed >= 0) * buf_dur.reciprocal * jitter);
      jitter_sig3 = TRand.kr(trig: grain_trig,
        lo: (speed < 0) * buf_dur.reciprocal.neg * jitter,
        hi: (speed >= 0) * buf_dur.reciprocal * jitter);
      jitter_sig4 = TRand.kr(trig: grain_trig,
        lo: (speed < 0) * buf_dur.reciprocal.neg * jitter,
        hi: (speed >= 0) * buf_dur.reciprocal * jitter);



      reset_pos = pos;

      // modulate the start/stop
  		phasor_start = buf_pos_start;
  		phasor_end = Clip.kr(buf_pos_start+buf_pos_end,0,buf_pos_end);
  		// phasor_start = buf_pos_start+((size)/max_buffer_length);
  		// phasor_end = Clip.kr(buf_pos_start+buf_pos_end,0,buf_pos_end-(size/max_buffer_length));

  		// LocalIn collects a trigger whenever the playheads leave the buffer window.
    	localin = LocalIn.kr(1);

  	  // find all the playhead positions outside the window
      switch1 = (BinaryOpUGen('==', localin, 1)) + (BinaryOpUGen('==', localin, 11)) + (BinaryOpUGen('==', localin, 111)) + (BinaryOpUGen('==', localin, 1111));
      switch1 = switch1 > 0;
      switch2 = (BinaryOpUGen('==', localin, 10)) + (BinaryOpUGen('==', localin, 11)) + (BinaryOpUGen('==', localin, 110)) + (BinaryOpUGen('==', localin, 111)) + (BinaryOpUGen('==', localin, 1010)) + (BinaryOpUGen('==', localin, 1011)) + (BinaryOpUGen('==', localin, 1111)) ;
      switch2 = switch2 > 0;
      switch3 = (BinaryOpUGen('==', localin, 100)) + (BinaryOpUGen('==', localin, 101)) + (BinaryOpUGen('==', localin, 110)) + (BinaryOpUGen('==', localin, 111)) + (BinaryOpUGen('==', localin, 1100)) + (BinaryOpUGen('==', localin, 1110)) + (BinaryOpUGen('==', localin, 1111)) ;
      switch3 = switch3 > 0;
      switch4 = (BinaryOpUGen('==', localin, 1000)) + (BinaryOpUGen('==', localin, 1001)) + (BinaryOpUGen('==', localin, 1010)) + (BinaryOpUGen('==', localin, 1011)) + (BinaryOpUGen('==', localin, 1100)) + (BinaryOpUGen('==', localin, 1101)) + (BinaryOpUGen('==', localin, 1110)) + (BinaryOpUGen('==', localin, 1111));
      switch4 = switch4 > 0;      

      // find the first playhead outside the window
      reset_sig_ix = (switch1 > 0) * 1;
      reset_sig_ix = reset_sig_ix + ((reset_sig_ix < 1) * (switch2 > 0 * 2));
      reset_sig_ix = reset_sig_ix + ((reset_sig_ix < 1) * (switch3 > 0 * 3));
      reset_sig_ix = reset_sig_ix + ((reset_sig_ix < 1) * (switch4 > 0 * 4));

      switch = reset_sig_ix > 0;

      buf_pos = Phasor.kr(trig: t_reset_pos,
        rate: buf_dur.reciprocal / ControlRate.ir * speed,
        start:buf_pos_start, end:buf_pos_end, resetPos: reset_pos);

      sig_pos = buf_pos;
      // sig_pos = (sig_pos*(1-sync_to_rec_head)) + (rec_phase[voice].kr().asInteger*sync_to_rec_head);
      sig_pos = (rec_phase*sync_to_rec_head) + (sig_pos*(1-sync_to_rec_head));
      sig_pos = (sig_pos - ((ptr_delay * SampleRate.ir)/ BufFrames.kr(buf))).wrap(buf_pos_start,buf_pos_end);
      spread_sig = (spread_sig*(buf_pos_end-buf_pos_start))/4;

      // add jitter and spread to each signal position
      sig_pos1 = (sig_pos+jitter_sig).wrap(buf_pos_start,buf_pos_end);
      sig_pos2 = (sig_pos+jitter_sig2+(spread_sig)+spread_sig_offset1).wrap(buf_pos_start,buf_pos_end);
      sig_pos3 = (sig_pos+jitter_sig3+(spread_sig*2)+spread_sig_offset2).wrap(buf_pos_start,buf_pos_end);
      sig_pos4 = (sig_pos+jitter_sig4+(spread_sig*3)+spread_sig_offset3).wrap(buf_pos_start,buf_pos_end);
      
      sig2_pos1 = sig_pos1;
      sig2_pos2 = sig_pos2;
      sig2_pos3 = sig_pos3;
      sig2_pos4 = sig_pos4;


      // if a switch var is < 1 use the correspoinding sig position
      // if a switch var is > 0:
      //     set the corresponding sig position to the start or end 
      //     of the buffer currently being used,
      //     depending on the direction the playhead is moving
      sig_pos1 = (sig_pos1 * (switch1 < 1)) + (sig_pos1 * (switch1 > 0) * (speed > 0) * buf_pos_end) + (sig_pos1 * (switch1 > 0) * (speed <= 0) * buf_pos_start); 
      sig_pos2 = (sig_pos2 * (switch2 < 1)) + (sig_pos2 * (switch2 > 0) * (speed > 0) * buf_pos_end) + (sig_pos2 * (switch2 > 0) * (speed <= 0) * buf_pos_start); 
      sig_pos3 = (sig_pos3 * (switch3 < 1)) + (sig_pos3 * (switch3 > 0) * (speed > 0) * buf_pos_end) + (sig_pos3 * (switch3 > 0) * (speed <= 0) * buf_pos_start); 
      sig_pos4 = (sig_pos4 * (switch4 < 1)) + (sig_pos4 * (switch4 > 0) * (speed > 0) * buf_pos_end) + (sig_pos4 * (switch4 > 0) * (speed <= 0) * buf_pos_start); 

      // if a switch var is > 1 use the correspoinding sig position
      // if a switch var is < 0:
      //     set the corresponding sig position to the start or end 
      //     of the buffer currently being used,
      //     depending on the direction the playhead is moving
      sig2_pos1 = (sig2_pos1 * (switch1 > 0)) + (sig2_pos1 * (switch1 < 1) * (speed > 0) * buf_pos_end) + (sig2_pos1 * (switch1 < 1) * (speed <= 0) * buf_pos_start); 
      sig2_pos2 = (sig2_pos2 * (switch2 > 0)) + (sig2_pos2 * (switch2 < 1) * (speed > 0) * buf_pos_end) + (sig2_pos2 * (switch2 < 1) * (speed <= 0) * buf_pos_start); 
      sig2_pos3 = (sig2_pos3 * (switch3 > 0)) + (sig2_pos3 * (switch3 < 1) * (speed > 0) * buf_pos_end) + (sig2_pos3 * (switch3 < 1) * (speed <= 0) * buf_pos_start); 
      sig2_pos4 = (sig2_pos4 * (switch4 > 0)) + (sig2_pos4 * (switch4 < 1) * (speed > 0) * buf_pos_end) + (sig2_pos4 * (switch4 < 1) * (speed <= 0) * buf_pos_start); 

      active_sig_pos1 = ((switch1 < 1) * sig_pos1) + ((switch1 > 0) * sig2_pos1);
      active_sig_pos2 = ((switch2 < 1) * sig_pos2) + ((switch2 > 0) * sig2_pos2);
      active_sig_pos3 = ((switch3 < 1) * sig_pos3) + ((switch3 > 0) * sig2_pos3);
      active_sig_pos4 = ((switch4 < 1) * sig_pos4) + ((switch4 > 0) * sig2_pos4);

      //calculate the signal position relative to the window of the active buffer (buf_pos_start/buf_pos_end)
      window_sig_pos1 = active_sig_pos1.linlin(buf_pos_start,buf_pos_end,0,1);
      window_sig_pos2 = active_sig_pos2.linlin(buf_pos_start,buf_pos_end,0,1);
      window_sig_pos3 = active_sig_pos3.linlin(buf_pos_start,buf_pos_end,0,1);
      window_sig_pos4 = active_sig_pos4.linlin(buf_pos_start,buf_pos_end,0,1);
      // ([voice,rec_phase.kr.asInteger]).poll;
      // (voice < 1 * window_sig_pos1).poll;
      // (voice < 1 * active_sig_pos1).poll;
      // (voice < 1 * buf_pos_start).poll;
      // (voice < 1 * buf_pos_end).poll;
      SendReply.kr(Impulse.kr(30), "/eglut_sigs_pos", [voice,window_sig_pos1, window_sig_pos2, window_sig_pos3, window_sig_pos4]);
      // SendReply.kr(Impulse.kr(10), "/eglut_sigs_pos", [voice, active_sig_pos1/buf_pos_end, active_sig_pos2/buf_pos_end, active_sig_pos3/buf_pos_end, active_sig_pos4/buf_pos_end]);

      sig = GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf, 
            pos: sig_pos1,
            interp: 2, 
            pan: pan_sig,
            rate:pitch,
            envbufnum:gr_envbuf,
            maxGrains:96/2,//96,
            mul:main_vol*0.5,
          )+
          GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf2, 
            pos: sig_pos1, 
            interp: 2, 
            pan: pan_sig2,
            rate:pitch,
            envbufnum:gr_envbuf,
            maxGrains:96/2,//96,
            mul:main_vol*0.5,
          )+


          GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf, 
            pos: sig_pos2, 
            interp: 2, 
            pan: pan_sig,
            rate:pitch,
            envbufnum:gr_envbuf,
            maxGrains:72/2,//72,
            mul:main_vol*0.5,
          )+
          GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf2, 
            pos: sig_pos2, 
            interp: 2, 
            pan: pan_sig2,
            rate:pitch,
            envbufnum:gr_envbuf,
            maxGrains:72/2,//72,
            mul:main_vol*0.5,
          )+
        GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf, 
            pos: sig_pos3, 
            interp: 2, 
            pan: pan_sig,
            rate:pitch,
            envbufnum:gr_envbuf,
            maxGrains:32/2,//32,
            mul:main_vol*0.5,
          )+
          GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf2, 
            pos: sig_pos3, 
            interp: 2, 
            pan: pan_sig2,
            rate:pitch,
            envbufnum:gr_envbuf,
            maxGrains:32/2,//32,
            mul:main_vol*0.5,
          )+
        GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf, 
            pos: sig_pos4, 
            interp: 2, 
            pan: pan_sig,
            rate:pitch,
            envbufnum:gr_envbuf,
            maxGrains:24/2,//24,
            mul:main_vol*0.5,
          )+
          GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf2, 
            pos: sig_pos4, 
            interp: 2, 
            pan: pan_sig2,
            rate:pitch,
            envbufnum:gr_envbuf,
            maxGrains:24/2,//24,
            mul:main_vol*0.5,
          )



          +
          GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf, 
            pos: sig_pos2, 
            interp: 2, 
            pan: pan_sig,
            rate:pitch/2,
            envbufnum:gr_envbuf,
            maxGrains:72/2,//72,
            mul:subharmonic_vol,
          )+
          GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf2, 
            pos: sig_pos2, 
            interp: 2, 
            pan: pan_sig2,
            rate:pitch/2,
            envbufnum:gr_envbuf,
            maxGrains:72/2,//72,
            mul:subharmonic_vol,
          )+
        GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf, 
            pos: sig_pos3, 
            interp: 2, 
            pan: pan_sig,
            rate:pitch*2,
            envbufnum:gr_envbuf,
            maxGrains:32/2,//32,
            mul:overtone_vol*0.7,
          )+
          GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf2, 
            pos: sig_pos3, 
            interp: 2, 
            pan: pan_sig2,
            rate:pitch*2,
            envbufnum:gr_envbuf,
            maxGrains:32/2,//32,
            mul:overtone_vol*0.7,
          )+
        GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf, 
            pos: sig_pos4, 
            interp: 2, 
            pan: pan_sig,
            rate:pitch*4,
            envbufnum:gr_envbuf,
            maxGrains:24/2,//24,
            mul:overtone_vol*0.3,
          )+
          GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf2, 
            pos: sig_pos4, 
            interp: 2, 
            pan: pan_sig2,
            rate:pitch*4,
            envbufnum:gr_envbuf,
            maxGrains:24/2,//24,
            mul:overtone_vol*0.3,
      );

      sig2 = GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf, 
            pos: sig2_pos1,
            interp: 2, 
            pan: pan_sig,
            rate:pitch,
            envbufnum:gr_envbuf,
            maxGrains:96/2,//96,
            mul:main_vol*0.5,
          )+
          GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf2, 
            pos: sig2_pos1, 
            interp: 2, 
            pan: pan_sig2,
            rate:pitch,
            envbufnum:gr_envbuf,
            maxGrains:96/2,//96,
            mul:main_vol*0.5,
          )+


          GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf, 
            pos: sig2_pos2, 
            interp: 2, 
            pan: pan_sig,
            rate:pitch,
            envbufnum:gr_envbuf,
            maxGrains:72/2,//72,
            mul:main_vol*0.5,
          )+
          GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf2, 
            pos: sig2_pos2, 
            interp: 2, 
            pan: pan_sig2,
            rate:pitch,
            envbufnum:gr_envbuf,
            maxGrains:72/2,//72,
            mul:main_vol*0.5,
          )+
        GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf, 
            pos: sig2_pos3, 
            interp: 2, 
            pan: pan_sig,
            rate:pitch,
            envbufnum:gr_envbuf,
            maxGrains:32/2,//32,
            mul:main_vol*0.5,
          )+
          GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf2, 
            pos: sig2_pos3, 
            interp: 2, 
            pan: pan_sig2,
            rate:pitch,
            envbufnum:gr_envbuf,
            maxGrains:32/2,//32,
            mul:main_vol*0.5,
          )+
        GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf, 
            pos: sig2_pos4, 
            interp: 2, 
            pan: pan_sig,
            rate:pitch,
            envbufnum:gr_envbuf,
            maxGrains:24/2,//24,
            mul:main_vol*0.5,
          )+
          GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf2, 
            pos: sig2_pos4, 
            interp: 2, 
            pan: pan_sig2,
            rate:pitch,
            envbufnum:gr_envbuf,
            maxGrains:24/2,//24,
            mul:main_vol*0.5,
          )



          +
          GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf, 
            pos: sig2_pos2, 
            interp: 2, 
            pan: pan_sig,
            rate:pitch/2,
            envbufnum:gr_envbuf,
            maxGrains:72/2,//72,
            mul:subharmonic_vol,
          )+
          GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf2, 
            pos: sig2_pos2, 
            interp: 2, 
            pan: pan_sig2,
            rate:pitch/2,
            envbufnum:gr_envbuf,
            maxGrains:72/2,//72,
            mul:subharmonic_vol,
          )+
        GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf, 
            pos: sig2_pos3, 
            interp: 2, 
            pan: pan_sig,
            rate:pitch*2,
            envbufnum:gr_envbuf,
            maxGrains:32/2,//32,
            mul:overtone_vol*0.7,
          )+
          GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf2, 
            pos: sig2_pos3, 
            interp: 2, 
            pan: pan_sig2,
            rate:pitch*2,
            envbufnum:gr_envbuf,
            maxGrains:32/2,//32,
            mul:overtone_vol*0.7,
          )+
        GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf, 
            pos: sig2_pos4, 
            interp: 2, 
            pan: pan_sig,
            rate:pitch*4,
            envbufnum:gr_envbuf,
            maxGrains:24/2,//24,
            mul:overtone_vol*0.3,
          )+
          GrainBuf.ar(
            numChannels: 2, 
            trigger:grain_trig, 
            dur:size, 
            sndbuf:buf2, 
            pos: sig2_pos4, 
            interp: 2, 
            pan: pan_sig2,
            rate:pitch*4,
            envbufnum:gr_envbuf,
            maxGrains:24/2,//24,
            mul:overtone_vol*0.3,
      );
      
      //determine if any of the four "active" playheads are outside the buffer window
      out_of_window = ((1*((active_sig_pos1 > phasor_end) + (active_sig_pos1 < phasor_start))) +
                       (10*((active_sig_pos2 > phasor_end) + (active_sig_pos2 < phasor_start))) +
                       (100*((active_sig_pos3 > phasor_end) + (active_sig_pos3 < phasor_start))) +
                       (1000*((active_sig_pos4 > phasor_end) + (active_sig_pos4 < phasor_start))));


      LocalOut.kr(out_of_window);

      // crossfade bewteen the two sounds over 50 milliseconds
      sig=SelectX.ar(Lag.kr(Changed.kr(switch),0.01),[sig,sig2]);

      
      sig = BLowPass4.ar(sig, cutoff, q);
      sig = Compander.ar(sig,sig,0.25)/envscale;
      // sig = Compander.ar(sig,sig,0.25)/8;

      sig = Balance2.ar(sig[0],sig[1],voice_pan);
      env = EnvGen.kr(Env.asr(1, 1, 1), gate: gate, timeScale: envscale);
      level = env;
      Out.ar(out, sig * level * gain);
      Out.kr(phase_out, sig_pos);
      Out.ar(effectBus, sig * level * send );
      // ignore gain for effect and level out
      Out.kr(level_out, level);
    }).add;

    SynthDef(\effect, {
      arg in, out, echoVol=1.0, echoTime=2.0, damp=0.1, size=4.0, diff=0.7, feedback=0.2, modDepth=0.1, modFreq=0.1;
      var sig = In.ar(in, 2);

      // sig = CombL.ar(in: sig, maxechotime: 1, echotime: 0.01, decaytime: damp, mul: 1.0, add: 0.0);
      // sig = CombL.ar(in: sig, maxechotime: 1, echotime: echoTime, decaytime: damp, mul: 1.0, add: 0.0);

      // sig = Greyhole.ar(sig, echoTime, damp, size, diff, feedback, modDepth, modFreq);
      Out.ar(out, sig * 4 * echoVol);
      
    }).add;
    
    s.sync;

    // echo bus
    effectBus = Bus.audio(context.server, 2);
    
    effect = Synth.new(\effect, [\in, effectBus.index, \out, context.out_b.index], target: context.xg);
    phases = Array.fill(ngvoices, { arg i; Bus.control(context.server); });
    levels = Array.fill(ngvoices, { arg i; Bus.control(context.server); });
    gr_envbufs = Array.fill(ngvoices, { arg i; 
      var winenv = Env([0, 1, 0], [0.5, 0.5], [\wel, \wel]);
      Buffer.sendCollection(s, winenv.discretize, 1);
    });

    pg = ParGroup.head(context.xg);

    gvoices = Array.fill(ngvoices, { arg i;
      Synth.new(\grain_synth, [
        \voice, i,
        \out, context.out_b.index,
        \effectBus, effectBus.index,
        \phase_out, phases[i].index,
        \level_out, levels[i].index,
        \buf, live_buffers[i],
        \buf2, live_buffers[i+ngvoices],
        // \gr_envbuf, -1
        \gr_envbuf, gr_envbufs[i]
      ], target: pg);
    });

    context.server.sync;
    "second eglut init sync".postln;
    thisEngine.addCommand("echo_volume", "f", { arg msg; effect.set(\echoVol, msg[1]); });
    thisEngine.addCommand("echo_time", "f", { arg msg; effect.set(\echoTime, msg[1]); });
    thisEngine.addCommand("echo_damp", "f", { arg msg; effect.set(\damp, msg[1]); });
    thisEngine.addCommand("echo_size", "f", { arg msg; effect.set(\size, msg[1]); });
    thisEngine.addCommand("echo_diff", "f", { arg msg; effect.set(\diff, msg[1]); });
    thisEngine.addCommand("echo_fdbk", "f", { arg msg; effect.set(\feedback, msg[1]); });
    thisEngine.addCommand("echo_mod_depth", "f", { arg msg; effect.set(\modDepth, msg[1]); });
    thisEngine.addCommand("echo_mod_freq", "f", { arg msg; effect.set(\modFreq, msg[1]); });

    thisEngine.addCommand("read", "isff", { arg msg;
      var voice = msg[1]-1;
      var path = msg[2];
      var sample_start = msg[3];
      var sample_length = msg[4];
      this.readDisk(voice,path,sample_start,sample_length);
    });

    thisEngine.addCommand("seek", "if", { arg msg;
      var voice = msg[1] - 1;
      var lvl, pos;
      
      // TODO: async get
      lvl = levels[voice].getSynchronous();

      pos = msg[2];
      gvoices[voice].set(\pos, pos);
      gvoices[voice].set(\t_reset_pos, 1);
      gvoices[voice].set(\sync_to_rec_head, 0);
    });

    thisEngine.addCommand("gate", "ii", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\gate, msg[2]);
    });

    thisEngine.addCommand("ptr_delay", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\ptr_delay, msg[2]);
      gvoices[voice].set(\sync_to_rec_head, 1);
    });

    thisEngine.addCommand("speed", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\speed, msg[2]);
      gvoices[voice].set(\sync_to_rec_head, 0);
    });

    thisEngine.addCommand("spread_sig", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\spread_sig, msg[2]);
    });

    thisEngine.addCommand("spread_sig_offset1", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\spread_sig_offset1, msg[2]);
    });

    thisEngine.addCommand("spread_sig_offset2", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\spread_sig_offset2, msg[2]);
    });

    thisEngine.addCommand("spread_sig_offset3", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\spread_sig_offset3, msg[2]);
    });

    thisEngine.addCommand("jitter", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\jitter, msg[2]);
    });

    thisEngine.addCommand("size", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\size, msg[2]);
    });

    thisEngine.addCommand("size_jitter", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\size_jitter, msg[2]);
    });

    thisEngine.addCommand("density", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\density, msg[2]);
    });

    thisEngine.addCommand("density_jitter", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\density_jitter, msg[2]);
    });

    thisEngine.addCommand("pan", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\voice_pan, msg[2]);
    });

    thisEngine.addCommand("pitch", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\pitch, msg[2]);
    });

    thisEngine.addCommand("spread_pan", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\spread_pan, msg[2]);
    });

    thisEngine.addCommand("gain", "if", { arg msg;
      var voice = msg[1] - 1;
      var gain_mul = 4;
      gvoices[voice].set(\gain, msg[2]*gain_mul);
    });

    thisEngine.addCommand("gr_envbuf", "ifffff", { arg msg;
      var voice = msg[1] - 1;
      var attack_level = msg[2];
      var attack_time = msg[3];
      var decay_time = msg[4];
      var attack_shape = msg[5]-1;
      var decay_shape = msg[6]-1;
      var oldbuf;
      var attack_curve_types=["step","lin","sin","wel","squared","cubed"];
      var decay_curve_types=["step","lin","sin","wel","squared","cubed"];
      var winenv = Env(
        [0, attack_level, 0], 
        [attack_time, decay_time], 
        [attack_curve_types[attack_shape].asSymbol, decay_curve_types[decay_shape].asSymbol]
      );

      if (updating_gr_envbufs == false,{
        updating_gr_envbufs = true;
        oldbuf = gr_envbufs[voice];
        gr_envbufs[voice] = Buffer.sendCollection(s, winenv.discretize, 1,action:{
          Routine({
            0.1.wait;
            gvoices[voice].set(\gr_envbuf, gr_envbufs[voice]);
            1.wait;
            updating_gr_envbufs = false;
            oldbuf.free;
          }).play;
        });
      })
    });

    thisEngine.addCommand("envscale", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\envscale, msg[2]);
    });
    
    thisEngine.addCommand("cutoff", "if", { arg msg;
    var voice = msg[1] -1;
    gvoices[voice].set(\cutoff, msg[2]);
    });
    
    thisEngine.addCommand("q", "if", { arg msg;
    var voice = msg[1] -1;
    gvoices[voice].set(\q, msg[2]);
    });
    
    thisEngine.addCommand("send", "if", { arg msg;
    var voice = msg[1] -1;
    gvoices[voice].set(\send, msg[2]);
    });
    
    thisEngine.addCommand("volume", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\gain, msg[2]);
    });
    
    thisEngine.addCommand("overtones", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\overtones, msg[2]);
    });
    
    thisEngine.addCommand("subharmonics", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\subharmonics, msg[2]);
    });

    ngvoices.do({ arg i;
      thisEngine.addPoll(("phase_" ++ (i+1)).asSymbol, {
        var val = phases[i].getSynchronous;
        val
      });

    });

    osc_funcs.put("live_rec_level",
      OSCFunc.new({ |msg,time,addr,recvPort|
        var rec_level = msg[1];
        var voice = msg[2];
        if(recorders.at(voice).notNil,{
          recorders.at(voice).set(\rec_level,rec_level);
          recorders.at(voice+ngvoices).set(\rec_level,rec_level);
        })
      },"/sc_eglut/live_rec_level");
    );
    osc_funcs.put("live_pre_level",
      OSCFunc.new({ |msg,time,addr,recvPort|
        var pre_level = msg[1];
        var voice = msg[2];
        if(recorders.at(voice).notNil,{
          recorders.at(voice).set(\pre_level,pre_level);
          recorders.at(voice+ngvoices).set(\pre_level,pre_level);
        })
      },"/sc_eglut/live_pre_level");
    );     
    
    osc_funcs.put("set_sample_position",
      OSCFunc.new({ |msg,time,addr,recvPort|
        var voice=msg[1];
        var sample_start=msg[2];
        var sample_length=msg[3];
        var rec_phase=msg[4];
        // (["recorders set sample_start,sample_length: ", sample_start, sample_length]).postln;
        this.setBufStartEnd(voice,live_buffers[voice],2,sample_start,sample_length,rec_phase);


      },"/sc_osc/set_sample_position");
    );   

    osc_funcs.put("granulate_live",
      OSCFunc.new({ |msg,time,addr,recvPort|
        var voice=msg[1];
        var sample_start=msg[2];
        var sample_length=msg[3];
        var rec_phase=msg[4];
        
        gvoices[voice].set(\buf, live_buffers[voice]);
        gvoices[voice].set(\buf2, live_buffers[voice+ngvoices]);
        this.setBufStartEnd(voice,live_buffers[voice],2,sample_start,sample_length,rec_phase);
      },"/sc_osc/granulate_live");
    );   



    OSCdef(\eglut_rec_phases, {|msg| 
      var voice = msg[3];
      var rec_phase = msg[4];
      // if (voice < 1,{ (["eglut_rec_phases 0",rec_phase]).postln; });
      rec_phases[voice].setnAt(voice, [rec_phase]);
      gvoices[voice].set(\rec_phase,rec_phase);
    }, "/eglut_rec_phases");

    OSCdef(\eglut_sigs_pos, {|msg| 
      var voice = msg[3];
      var sig_pos1 = msg[4];
      var sig_pos2 = msg[5];
      var sig_pos3 = msg[6];
      var sig_pos4 = msg[7];
      if(
        sig_pos1 != prev_sig_pos1 || 
        sig_pos2 != prev_sig_pos2 || 
        sig_pos3 != prev_sig_pos3 || 
        sig_pos4 != prev_sig_pos4, {
        lua_sender.sendMsg("/lua_eglut/grain_sig_pos",voice,sig_pos1, sig_pos2, sig_pos3, sig_pos4);
        // ["eglut_sigs_pos",voice,sig_pos1, sig_pos2, sig_pos3, sig_pos4].postln;
      });
      prev_sig_pos1 = sig_pos1;
      prev_sig_pos2 = sig_pos2;
      prev_sig_pos3 = sig_pos3;
      prev_sig_pos4 = sig_pos4;
    }, "/eglut_sigs_pos");

  }

  ///////////////////////////////////

  free{
    "eglut beeeee freeeeee".postln;
    osc_funcs.keysValuesDo({ arg k,val;
      val.free;
    });

    recorders.do({ arg recorder; recorder.free; });
    gvoices.do({ arg voice; voice.free; });
    phases.do({ arg bus; bus.free; });
    levels.do({ arg bus; bus.free; });
    live_buffers.do({ arg b; b.free; });
    file_buffers.do({ arg b; b.free; });
    gr_envbufs.do({ arg b; b.free; });
    effect.free;
    effectBus.free;
    rec_phases.free;
  }
}