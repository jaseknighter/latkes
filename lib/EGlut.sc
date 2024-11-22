//EGlut: grandchild of Glut, parent of ZGlut

EGlut {
  classvar ngvoices = 4;
  
  var s;
  var context;
  var pg;
	var <effect;
  var <live_buffers;
	var <file_buffers;
	var <gvoices;
  var active_voice;
	var <effectBus;
	var <phases;
  var <density_phases;
  var <density_phasor_bufenvs;
  var <reset_density_phases;
  var <reset_density_phases_one_shot;
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
  var default_sample_length=10;
  var max_size=5;
    
  var waveformer;

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
      // \pos,rec_phase,
      // \t_reset_pos, 1
    );
    recorders[voice + ngvoices].set(
      \buf_pos_start, start, 
      \buf_pos_end, end,  
      // \pos,rec_phase,
      // \t_reset_pos, 1
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
      var mode = 2;
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

    
    reset_density_phases = Array.fill(ngvoices, { 0 });
    reset_density_phases_one_shot = Array.fill(ngvoices, { 0 });
    density_phases = Array.fill(ngvoices, { Bus.control(context.server) });
    density_phasor_bufenvs = Array.fill(ngvoices, { nil });

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

    s.sync;

    SynthDef("live_recorder", {
      arg voice=0,out=0,in=0, 
          buf=0, rate=1,
          pos=0,buf_pos_start=0,buf_pos_end=1,t_reset_pos=0,
          rec_level=1,pre_level=0,
          rec_phase;
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

      // SendReply.kr(Impulse.kr(30), "/eglut_rec_phases", [voice,buf_pos]);
      Out.kr(rec_phase, buf_pos);
    }).add;

    s.sync;

    recorders = Array.fill(ngvoices*2, { arg i;
      var chan;
      if(i < ngvoices,{chan=0},{chan=1});
      (["add recorder",ngvoices,i,chan]).postln;
      Synth(\live_recorder, [\voice, i,\buf,live_buffers[i],\in,chan,\rec_phase,rec_phases[i].index]);
    });
    s.sync;
    recorders.postln;

    SynthDef("grain_synth", {
      arg voice, out, effectBus, phase_out, level_out, buf, buf2,
      mode=0,
      gate=0, pos=0, 
      buf_pos_start=0, 
      rec_phase_bus=0,
      buf_pos_end=1, 
      sample_length=default_sample_length/max_buffer_length,
      density_phasor_bus=0, density_phasor_env, 
      density_phasor_trig = -1, 
      speed=1, jitter=0, spread_sig=0, voice_pan=0,	
      size=0.1, size_jitter=0, 
      pitch=1, spread_pan=0, gain=1, envscale=1,
      t_reset_pos=0, cutoff=20000, q, send=0, 
      ptr_delay=0.2,sync_to_rec_head=1,
      subharmonics=0,overtones=0, gr_envbuf = -1,
      spread_sig_offset1=0, spread_sig_offset2=0, spread_sig_offset3=0;

      var rec_phase;
      var rec_phase_trig = 0;
      var grain_trig=1;
      var grain_jitter_trig=1;
      var trig_rnd;
      var size_jitter_sig;
      var density=0;
      var density_phasor=0;
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
      var window_start, window_end; 
      var localin;
      var switch=0,switch1,switch2,switch3,switch4;
      var reset_sig_ix=0,crossfade;
      var win_size, win_frames;
      var win_trigger_size=1024;
      var rec_phase_frame,rec_phase_win_start,rec_phase_win_end;
      

      pos = pos.linlin(0,1,buf_pos_start,buf_pos_end);
      win_size = buf_pos_end - buf_pos_start;
      win_frames = BufFrames.kr(buf);
      
      // size_jitter_sig = TRand.kr(trig: Impulse.kr(density, [0,density_phase]),
      size_jitter_sig = TRand.kr(trig: density_phasor.floor,
        lo: size_jitter.neg,
        hi: size_jitter);

      // make sure size+size jitter is greater than 0, otherwise ignore the jitter
      size = ((size+size_jitter_sig > 0) * (size+size_jitter_sig)) + ((1-(size+size_jitter_sig > 0)) * size);
      size = ((size+size_jitter_sig < max_size) * (size+size_jitter_sig)) + ((1-(size+size_jitter_sig < max_size)) * size);
      size = Lag.kr(size);

      density_phasor=PlayBuf.kr(1,bufnum:density_phasor_env,trigger:density_phasor_trig, startPos: 0, loop:1);
      Out.kr(density_phasor_bus,[density_phasor]);
      density = density_phasor;

      spread_pan = Lag.kr(spread_pan);

      cutoff = Lag.kr(cutoff);
      q = Lag.kr(q);
      send = Lag.kr(send);
      pitch = Lag.kr(pitch,0.25);
      
      grain_trig = density.floor;
      SendReply.kr(grain_trig, "/density_phase_completed", [voice,density_phasor_trig]);
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


      // position to jump to when the synth receives a reset trigger
      reset_pos = pos;

      buf_pos = Phasor.kr(trig: t_reset_pos,
        rate: buf_dur.reciprocal / ControlRate.ir * speed,
        start:buf_pos_start, end:buf_pos_end, resetPos: reset_pos);

      sig_pos = buf_pos;

      //In.kr collects the current position of the voice's record head
      rec_phase = In.kr(rec_phase_bus);

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

      SendReply.kr(Impulse.kr(30), "/eglut_sigs_pos", [voice,window_sig_pos1, window_sig_pos2, window_sig_pos3, window_sig_pos4]);
      // constantly queue waveform generation if mode is "off" or "live" (but not "recorded")
      SendReply.kr(Impulse.kr(10), "/queue_waveform_generation", [mode,voice,buf_pos_start,buf_pos_end-buf_pos_start]);
      
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
            maxGrains:16,//96,
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
            maxGrains:16,//96,
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
            maxGrains:16,//72,
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
            maxGrains:16,//72,
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
            maxGrains:16,//32,
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
            maxGrains:16,//32,
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
            maxGrains:16,
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
            maxGrains:16,
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
            maxGrains:16,//72,
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
            maxGrains:16,//72,
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
            maxGrains:16,//32,
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
            maxGrains:16,//32,
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
            maxGrains:16,
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
            maxGrains:16,
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
            maxGrains:16,//96,
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
            maxGrains:16,//96,
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
            maxGrains:16,//72,
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
            maxGrains:16,//72,
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
            maxGrains:16,//32,
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
            maxGrains:16,//32,
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
            maxGrains:16,
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
            maxGrains:16,
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
            maxGrains:16,//72,
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
            maxGrains:16,//72,
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
            maxGrains:16,//32,
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
            maxGrains:16,//32,
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
            maxGrains:16,
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
            maxGrains:16,
            mul:overtone_vol*0.3,
      );

      // set the start/end points
			// posStart = Clip.kr(LinLin.kr(posStart,0,1,0,frames),1024,frames-10240);
			// posEnd = Clip.kr(LinLin.kr(posEnd,0,1,0,frames),posStart+1024,frames-1024);
			
      //create a window for the rec_phase in frames, 
      // 1024 frames before the start of the rec_phase
      // and 1024 frames + the size of the grains in frames after the end of the rec_phase
      //then convert the window values to a 0-1 scale based on the length of the buffer in seconds
      rec_phase_frame = LinLin.kr(rec_phase,0,1,0,win_frames);

      rec_phase_win_start = rec_phase_frame-win_trigger_size;
      rec_phase_win_start = Clip.kr(rec_phase_win_start,win_trigger_size,win_frames-(win_trigger_size*10));
      
      rec_phase_win_end = (rec_phase_frame+size+win_trigger_size);
      rec_phase_win_end = Clip.kr(rec_phase_win_end,rec_phase_win_start+win_trigger_size,win_frames-win_trigger_size);
      
      rec_phase_win_start = rec_phase_win_start/max_buffer_length/BufSampleRate.kr(buf);
      rec_phase_win_end = rec_phase_win_end/max_buffer_length/BufSampleRate.kr(buf);

      //check if the recorder position is passing over the active signal positions
      rec_phase_trig = ((rec_phase_win_start < active_sig_pos1) * (rec_phase_win_end > active_sig_pos1) > 0);
      rec_phase_trig = (rec_phase_trig + ((rec_phase_win_start < active_sig_pos2) * (rec_phase_win_end > active_sig_pos2)) > 0);
      rec_phase_trig = (rec_phase_trig + ((rec_phase_win_start < active_sig_pos3) * (rec_phase_win_end > active_sig_pos3)) > 0);
      rec_phase_trig = (rec_phase_trig + ((rec_phase_win_start < active_sig_pos4) * (rec_phase_win_end > active_sig_pos4)) > 0);
      
      // rec_phase_trig = ((rec_phase + 0.0001 > active_sig_pos1) * (rec_phase - 0.0001 < active_sig_pos1) > 0);
      // rec_phase_trig = (rec_phase_trig + ((rec_phase + 0.0001 > active_sig_pos2) * (rec_phase - 0.0001 < active_sig_pos2)) > 0);
      // rec_phase_trig = (rec_phase_trig + ((rec_phase + 0.0001 > active_sig_pos3) * (rec_phase - 0.0001 < active_sig_pos3)) > 0);
      // rec_phase_trig = (rec_phase_trig + ((rec_phase + 0.0001 > active_sig_pos4) * (rec_phase - 0.0001 < active_sig_pos4)) > 0);
      
      //combine the position checks for out of window + the record head passing over the playheads
      // switch = (switch + rec_phase_trig) > 0;
      // switch = (rec_phase_trig) > 0;
      SendReply.kr(switch, "/recorder_over_sigpos", [voice,rec_phase,1,active_sig_pos1]);
  		
      // crossfade bewteen the two sounds over 50 milliseconds
      sig=SelectX.ar(Lag.kr(switch,0.05),[sig,sig2]);
      // sig=SelectX.ar(Lag.kr(Changed.kr(switch),1),[sig,sig2]);
      // sig=XFade2.ar(sig, sig2, LFTri.kr(0.1) );

      // ([voice < 1 * active_sig_pos1,voice < 1 * (active_sig_pos1 + 0.001 > window_end)]).poll;
      // SendReply.kr(Changed.kr((active_sig_pos1 > phasor_end) + (active_sig_pos1 < window_start)), "/recorder_over_sigpos", [voice,rec_phase,1,active_sig_pos1]);
  		
      //create a window in frames, slightly smaller than the current sample window
      // so we know when the playhead leaves the sample window frame
      // 1024 frames before the start of the rec_phase
      // and 1024 frames + the size of the grains in frames after the end of the rec_phase
      //then convert the window values to a 0-1 scale based on the length of the buffer in seconds
      window_start = LinLin.kr(buf_pos_start,0,1,0,win_frames);
      window_start = window_start+win_trigger_size;
      window_start = Clip.kr(window_start,win_trigger_size,win_frames-(win_trigger_size*10));
      
      window_end = LinLin.kr(buf_pos_end,0,1,0,win_frames);
      window_end = window_end-win_trigger_size;
      window_end = Clip.kr(window_end,window_start+win_trigger_size,win_frames-win_trigger_size);

      window_start = window_start/max_buffer_length/BufSampleRate.kr(buf);
      window_end = window_end/max_buffer_length/BufSampleRate.kr(buf);

      // ([voice < 1 * active_sig_pos1,voice < 1 * window_start,voice < 1 * window_end]).poll;


  		// window_start = buf_pos_start;
  		// window_end = Clip.kr(buf_pos_start+buf_pos_end,0,buf_pos_end);
      

      //determine if any of the four "active" playheads are outside the buffer window
      out_of_window = ((1*((active_sig_pos1 > window_end) + (active_sig_pos1 < window_start))) +
                       (10*((active_sig_pos2 > window_end) + (active_sig_pos2 < window_start))) +
                       (100*((active_sig_pos3 > window_end) + (active_sig_pos3 < window_start))) +
                       (1000*((active_sig_pos4 > window_end) + (active_sig_pos4 < window_start))));

      LocalOut.kr(out_of_window);
      
      sig = BLowPass4.ar(sig, cutoff, q);
      sig = Compander.ar(sig,sig,0.25)/envscale;

      sig = Balance2.ar(sig[0],sig[1],voice_pan);
      
      env = EnvGen.kr(Env.asr(1, 1, 1), gate: gate, timeScale: envscale);
      level = env;
      Out.ar(out, sig * level * gain);
      Out.kr(phase_out, sig_pos);
      // ignore gain for effect and level out
      Out.ar(effectBus, sig * level * send );
      Out.kr(level_out, level);
    }).add;

    SynthDef(\effect, {
      arg in, out, echoVol=1.0, echoTime=2.0, damp=0.1, size=4.0, diff=0.7, feedback=0.2, modDepth=0.1, modFreq=0.1;
      var sig = In.ar(in, 2), gsig;
      
      gsig = Greyhole.ar(sig, echoTime, damp, size, diff, feedback, modDepth, modFreq);
      Out.ar(out, gsig * echoVol);
      
    }).add;

    s.sync;

    // echo bus
    effectBus = Bus.audio(context.server, 2);
    s.sync;
    // effect = Synth.tail(\effect, [\in, effectBus.index, \out, context.out_b.index], target: context.xg);
    // (["echo on",effect,effectBus.index,context.out_b.index]).postln;
    phases = Array.fill(ngvoices, { arg i; Bus.control(context.server); });
    levels = Array.fill(ngvoices, { arg i; Bus.control(context.server); });
    gr_envbufs = Array.fill(ngvoices, { arg i; 
      var winenv = Env([0, 1, 0], [0.5, 0.5], [\wel, \wel]);
      Buffer.sendCollection(s, winenv.discretize, 1);
    });

    pg = ParGroup.head(context.xg);

    gvoices = Array.fill(ngvoices, { arg i;
    	var winenv = Env([0, 1], [default_sample_length]);
    	var density_phasor_bufenv = Buffer.sendCollection(s, winenv.discretize, 1);

      Synth.new(\grain_synth, [
        \voice, i,
        \out, context.out_b.index,
        \rec_phase_bus,rec_phases[i].index,
        \density_phasor_env, density_phasor_bufenv,
        \density_phasor_bus, density_phases[i],
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

    waveformer = Waveformer.new([live_buffers,file_buffers]);


    "second eglut init sync".postln;
    thisEngine.addCommand("effects_on", "i", { arg msg; 
      if((msg[1]==1).and(effect.notNil),{
        effect.free;
        // effect.release;
        effect = nil;
        (["echo off",effect,effectBus.index,context.out_b.index]).postln;
      });
      if((msg[1]==2).and(effect.isNil),{
        // effect = Synth.tail(\effect, [\in, effectBus.index, \out, context.out_b.index], target: context.xg);
        effect = Synth.tail(s,\effect, [\in, effectBus.index, \out, context.out_b.index]);
        (["echo on",effect,effectBus.index,context.out_b.index]).postln;
      });
    });
    thisEngine.addCommand("echo_volume", "f", { arg msg; if(effect.notNil,{effect.set(\echoVol, msg[1])}); });
    thisEngine.addCommand("echo_time", "f", { arg msg; if(effect.notNil,{effect.set(\echoTime, msg[1])}); });
    thisEngine.addCommand("echo_damp", "f", { arg msg; if(effect.notNil,{effect.set(\damp, msg[1])}); });
    thisEngine.addCommand("echo_size", "f", { arg msg; if(effect.notNil,{effect.set(\size, msg[1])}); });
    thisEngine.addCommand("echo_diff", "f", { arg msg; if(effect.notNil,{effect.set(\diff, msg[1])}); });
    thisEngine.addCommand("echo_fdbk", "f", { arg msg; if(effect.notNil,{effect.set(\feedback, msg[1])}); });
    thisEngine.addCommand("echo_mod_depth", "f", { arg msg; if(effect.notNil,{effect.set(\modDepth, msg[1])}); });
    thisEngine.addCommand("echo_mod_freq", "f", { arg msg; if(effect.notNil,{effect.set(\modFreq, msg[1])}); });

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
      var density = msg[2];
      var winenv = Env([0, 1], [density.reciprocal]);
      var oldbuf=density_phasor_bufenvs[voice];
      var density_phasor_bufenv=density_phasor_bufenvs[voice];
      density_phasor_bufenvs[voice] = Buffer.sendCollection(s, winenv.discretize(n:1024*density.reciprocal.softRound(resolution:0.00390625,margin:0)), 1, action:{
        arg buf;
        gvoices[voice].set(\density_phasor_env, density_phasor_bufenvs[voice]);    
        // gvoices[voice].set(\density, msg[2]);
        // gvoices[voice].set(\density_phasor_env, buf);    
        oldbuf.free;
      });
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
      var shape = msg[5]-1;
      var size = msg[6];
      // var attack_shape = msg[5]-1;
      // var decay_shape = msg[6]-1;
      // var size = msg[7];
      var oldbuf;
      var curve_types=["exp","squared","lin","sin","wel","cubed"];
      // var attack_curve_types=["exp","squared","lin","sin","wel","cubed"];
      // var decay_curve_types=["exp","squared","lin","sin","wel","cubed"];
      var winenv = Env(
        [0.001, attack_level, 0.001], 
        [attack_time*size, decay_time*size], 
        [curve_types[shape].asSymbol,curve_types[shape].asSymbol]
      );

      if (updating_gr_envbufs == false,{
        updating_gr_envbufs = true;
        Buffer.sendCollection(s, winenv.discretize(n:(1024*size).softRound(resolution:0.00390625,margin:0)), 1,action:{
          arg buf;
          Routine({
            "change env".postln;
            gvoices[voice].set(\gr_envbuf, buf);
            // 0.1.wait;
            // gr_envbufs[voice].free;
            // 0.1.wait;
            gr_envbufs[voice] = buf;
            updating_gr_envbufs = false;

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

    osc_funcs.put("init_completed",
      OSCFunc.new({ |msg,time,addr,recvPort|
        "script and engine all loaded".postln;   
      },"/sc_osc/init_completed");
    );   

    osc_funcs.put("set_active_voice",
      OSCFunc.new({ |msg,time,addr,recvPort|
        (["active_voice",msg[1]]).postln;
        active_voice=msg[1];
      },"/sc_eglut/set_active_voice");
    );

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
        // (["recorders set sample_start,sample_length: ", sample_start, sample_length]).postln;
        this.setBufStartEnd(voice,live_buffers[voice],2,sample_start,sample_length);
        // this.setBufStartEnd(voice,live_buffers[voice],2,sample_start,sample_length,rec_phase);
      },"/sc_osc/set_sample_position");
    );   

    osc_funcs.put("clear_samples",
      OSCFunc.new({ |msg,time,addr,recvPort|
        var voice=msg[1];
        var sample_mode=msg[2];
        var pct=msg[3];
        (["clear samples",voice,sample_mode,pct]).postln;
      },"/sc_osc/clear_samples");
    );   

    osc_funcs.put("set_mode",
      OSCFunc.new({ |msg,time,addr,recvPort|
        var voice=msg[1];
        var mode=msg[2]; // 0: off, 1: live, 2: recorded
        (["set mode",voice,mode]);
        gvoices[voice].set(\mode, mode);
      },"/sc_osc/set_mode");
    );   

    osc_funcs.put("granulate_live",
      OSCFunc.new({ |msg,time,addr,recvPort|
        var voice=msg[1];
        var sample_start=msg[2];
        var sample_length=msg[3];
        // var rec_phase=msg[4];
        gvoices[voice].set(\buf, live_buffers[voice]);
        gvoices[voice].set(\buf2, live_buffers[voice+ngvoices]);
        gvoices[voice].set(\mode, 1);
        this.setBufStartEnd(voice,live_buffers[voice],2,sample_start,sample_length);
        // this.setBufStartEnd(voice,live_buffers[voice],2,sample_start,sample_length,rec_phase);
      },"/sc_osc/granulate_live");
    );   

    osc_funcs.put("sync_density_phases",
      OSCFunc.new({ |msg,time,addr,recvPort|
        var voice=msg[1];
        var sync=msg[2];
        // (["sync grain phases",voice,sync]).postln;
        ngvoices.do({ arg i; 
          if ((sync==1).and(i != voice).and(gvoices[i].notNil),{
            gvoices[i].set(\density_phasor_trig, -1);
          })
        });
        reset_density_phases[voice]=sync;
      },"/sc_osc/sync_density_phases");
    );   

    osc_funcs.put("sync_density_phases_one_shot",
      OSCFunc.new({ |msg,time,addr,recvPort|
        var voice=msg[1];
        ngvoices.do({ arg i; 
          if ((i != voice).and(gvoices[i].notNil),{
            gvoices[i].set(\density_phasor_trig, -1);
            // (["sync grain phases one shot",voice,i]).postln;
          })
        });
        reset_density_phases_one_shot[voice]=1;
      },"/sc_osc/sync_density_phases_one_shot");
    );   


    // osc.send( { "localhost", 57120 }, "/sc_osc/sync_density_phases_one_shot",{0})
    OSCdef(\density_phase_completed, {|msg| 
      var voice = msg[3].asInteger;
      var density_phasor_trig = msg[4];
      // if (voice < 2,{ (["grain phase completed",voice,density_phasor_trig]).postln; });
      if (reset_density_phases[voice] == 1,{ 
        ngvoices.do({ arg i; 
          if ((i != voice).and(gvoices[i].notNil),{
            // (["sync voice phase,from/to", voice, i]).postln;
            gvoices[i].set(\density_phasor_trig,1);
          })
        });
      });

      if (reset_density_phases_one_shot[voice] == 1,{ 
        reset_density_phases_one_shot[voice]=0;
        ngvoices.do({ arg i; 
          if ((i != voice).and(gvoices[i].notNil),{
            Routine({
              (["one shot sync voice phase,from/to", voice, i,gvoices[i]]).postln;
              gvoices[i].set(\density_phasor_trig,1);
              (["one shot done", voice, i,gvoices[i]]).postln;
            }).play;
          })
        });
      });
    }, "/density_phase_completed");

    OSCdef(\recorder_over_sigpos, {|msg| 
      var voice = msg[3].asInteger;
      var recorder_pos = msg[4];
      var sig_pos_ix = msg[5];
      var sig_pos = msg[6];
      (["recorder_over_sigpos",voice,recorder_pos,sig_pos_ix,sig_pos]).postln;
      // if (voice < 1,{ (["recorder_over_sigpos",voice,recorder_pos,sig_pos_ix,sig_pos]).postln; });
    }, "/recorder_over_sigpos");


    // OSCdef(\eglut_rec_phases, {|msg| 
    //   var voice = msg[3];
    //   var rec_phase = msg[4];
    //   // if (voice < 1,{ (["eglut_rec_phases 0",rec_phase]).postln; });
    //   rec_phases[voice].setnAt(voice, [rec_phase]);
    //   gvoices[voice].set(\rec_phase,rec_phase);
    // }, "/eglut_rec_phases");

    OSCdef(\queue_waveform_generation, {|msg| 
      var mode = msg[3];
      var voice = msg[4];
      var sample_start = msg[5];
      var sample_length = msg[6];
      var buf_array_ix;
      if (mode < 2, { buf_array_ix = 0 }, { buf_array_ix = 1 });
      if (voice == active_voice,{
        // (["waveformer.queueWaveformGeneration",mode,live_buffers[0],buf_array_ix, mode,voice]).postln;
        waveformer.queueWaveformGeneration(buf_array_ix,voice,sample_start,sample_length);        
      });
    }, "/queue_waveform_generation");

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
    Routine({
      s.queryAllNodes;
      0.1.wait;
      osc_funcs.keysValuesDo({ arg k,val;
        val.free;
      });
      waveformer.waveformRoutine.stop();
      gvoices.do({ arg voice; voice.free; });
      recorders.do({ arg recorder; recorder.free; });
      gr_envbufs.do({ arg b; b.free; });
      file_buffers.do({ arg b; b.free; });
      live_buffers.do({ arg b; b.free; });
      phases.do({ arg bus; bus.free; });
      levels.do({ arg bus; bus.free; });
      // reset_density_phases_one_shot.free;
      // reset_density_phases.free;
      rec_phases.free;
      // effect.free;
      // effectBus.free;
      waveformer.free;
      0.1.wait;
      "free done!!!".postln;
      s.queryAllNodes;

    }).play;
  }
}