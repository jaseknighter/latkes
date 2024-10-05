//EGlut: grandchild of Glut, parent of ZGlut
//mostly, this adds grain envelopes to the ZGlut engine

EGlut {
  classvar ngvoices = 4;
  
  var s;
  var context;
  var pg;
	var effect;
  var grain_modes; //grain_mode 0=live grain_mode; 1=file grain_mode
	var <live_buffers;
	var <file_buffers;
	var <gvoices;
	var effectBus;
	var <phases;
	var <rec_phase;
	var <levels;
	var <gr_envbufs;
  var updating_gr_envbufs = false;
  var prev_sig_pos1=0, prev_sig_pos2=0, prev_sig_pos3=0, prev_sig_pos4=0;

	// var <seek_tasks;
  var osc_funcs;
  var recorders;
  var live_streamer;
  // var live_buffer;
  var buffer_length = 120;
    

	*new {
		arg argServer, context, eng;
		^super.new.init(argServer,context,eng);

	}

	setGrainMode { arg voice,mode;
    grain_modes[voice]=mode;
  }

	// read from an existing buffer into the granulation buffsers
	setBufStartEnd { arg i, buf, mode,sample_duration;
    // ["setBufStartEnd set voices and live_buffers",i,buf,live_buffers, mode].postln;
    // if(live_buffers[i].sampleRate!=nil, {
    //   live_buffers[i].zero;
    //   live_buffers[i+ngvoices].zero;
    // });

    if (mode.notNil,{
      this.setGrainMode(mode);
    });
    // duplicate GrainBuf for stereo granulation
    // gvoices[i].set(\buf, buf);
    // gvoices[i+ngvoices].set(\buf2, buf);
    gvoices[i].set(\buf_pos_end, sample_duration/buffer_length);
    // live_buffers[i+ngvoices] = buf;

    
    // ["setBufStartEnd done i,modem,sample_duration,buffer_length",i,mode,sample_duration,buffer_length].postln;
	}

  // disk read
	readDisk { arg i, path, sample_duration;
    var startframe = 0;
		// if(file_buffers[i].notNil, {
    grain_modes[i]=1;
    if (File.exists(path), {
      // load stereo files and duplicate GrainBuf for stereo granulation
      var newbuf,newbuf2;
      var file, numChannels;
      var soundfile = SoundFile.new;
      soundfile.openRead(path.asString.standardizePath);
      numChannels = soundfile.numChannels;
      soundfile.close;
      ["file read into buffer...num channels,startframe,numFrames",path.asString.standardizePath,numChannels,startframe,s.sampleRate * sample_duration].postln;
      // file_buffers[i].allocReadChannelMsg(context.server, path, channels:[0], completionMessage:{
       newbuf = Buffer.readChannel(context.server, path, channels:[0], action:{
        arg buf;
        file_buffers[i].free;
        file_buffers[i] = buf;
        gvoices[i].set(\buf, file_buffers[i]);
        gvoices[i].set(\buf_pos_end, sample_duration/buffer_length);

        ["newbuf",i,file_buffers[i]].postln;
      });
      if (numChannels > 1,{
        "stereo file: read 2nd channel into buffer's 2nd channel".postln;
        // file_buffers[i+ngvoices].allocReadChannelMsg(context.server, path, channels:[1], completionMessage:{
         newbuf2 = Buffer.readChannel(context.server, path, channels:[1], action:{
          arg buf;
          file_buffers[i+ngvoices].free;
          file_buffers[i+ngvoices] = buf;
          gvoices[i+ngvoices].set(\buf2, file_buffers[i+ngvoices]);
          gvoices[i+ngvoices].set(\buf_pos_end, sample_duration/buffer_length);
          ["newbuf2",i,file_buffers[i+ngvoices]].postln;
        });
      },{
        arg buf;
        "mono file: read 1st channel into buffer's 2nd channel".postln;
        newbuf2 = file_buffers[i];
        file_buffers[i+ngvoices] = newbuf2;
        gvoices[i+ngvoices].set(\buf2, file_buffers[i+ngvoices]);
        gvoices[i+ngvoices].set(\buf_pos_end, sample_duration/buffer_length);
        ["newbuf2",i,file_buffers[i+ngvoices]].postln;
      });
    });
		// });
	}


  ///////////////////////////////////
  //init 
	init {
		arg argServer, engContext, eng;
    var thisEngine;
    var lua_sender;
    var sc_sender;

    "init eglut".postln;
    osc_funcs=Dictionary.new();
    
    lua_sender = NetAddr.new("127.0.0.1",10111);   
    sc_sender=NetAddr.new("127.0.0.1",57120);   
    
		s=argServer;
    context = engContext;
    thisEngine = eng;
    
    grain_modes = Array.fill(ngvoices, { arg i;
      1;
    });

    live_buffers = Array.fill(ngvoices*2, { arg i;
      Buffer.alloc(
        s,
        s.sampleRate * buffer_length,
      );
    });

    s.sync;

    file_buffers = Array.fill(ngvoices*2, { arg i;
      Buffer.alloc(
        s,
        s.sampleRate * buffer_length,
      );
    });

    // live streamer position bus
    rec_phase=Bus.control(context.server);
    ["rec_phase",rec_phase].postln;
    
    SynthDef("live_streamer", {
      arg out=0, in=0, phase,
          buf=0, rate=1,
          pos=0,buf_pos_start=0,buf_pos_end=1,t_reset_pos=1,
          write_live_stream_enabled=1,
          rec_level=1,pre_level=0;
      var buf_dur,buf_pos;
      var sig=SoundIn.ar(in);
      var rec_buf_reset = Impulse.kr((buf_pos_end*buffer_length).reciprocal);
      buf_dur = BufDur.kr(buf);
      buf_pos = Phasor.kr(trig: t_reset_pos,
        rate: buf_dur.reciprocal / ControlRate.ir * rate,
        start:buf_pos_start, end:buf_pos_end, resetPos: pos);
      
      RecordBuf.ar(sig, buf, offset: 0, recLevel: rec_level, preLevel: pre_level, run: 1.0, loop: 1.0, trigger: rec_buf_reset * write_live_stream_enabled, doneAction: 0);
      
      Out.kr(rec_phase.index, buf_pos);
    }).add;

    s.sync;
    recorders = Array.fill(ngvoices*2, { arg voice;
      (["add recorder",ngvoices,voice]).postln;
      Synth(\live_streamer, [\in,0,\buf,live_buffers[voice]]);
    });
    s.sync;
    recorders.postln;

    SynthDef(\synth, {
      arg voice, out, effectBus, phase_out, level_out, buf, buf2,
      gate=0, pos=0, 
      buf_pos_start=0, 
      buf_pos_end=1, 
      sample_duration=10/buffer_length,
      speed=1, jitter=0, spread_sig=0, voice_pan=0,	
      size=0.1, density=20, density_jitter=0,pitch=1, spread_pan=0, gain=1, envscale=1,
      t_reset_pos=0, cutoff=20000, q, send=0, 
      ptr_delay=0.2,sync_to_rec_head=1,
      // mode=0, 
      subharmonics=0,overtones=0, gr_envbuf = -1,
      spread_sig_offset1=0, spread_sig_offset2=0, spread_sig_offset3=0;

      var grain_trig=1;
      var grain_jitter_trig=1;
      var trig_rnd;
      var density_jitter_sig;
      var jitter_sig, jitter_sig2, jitter_sig3, jitter_sig4;
      var sig_pos;
      var sig_pos1, sig_pos2, sig_pos3, sig_pos4;
      var sig2_pos1, sig2_pos2, sig2_pos3, sig2_pos4;
      var active_sig_pos1, active_sig_pos2, active_sig_pos3, active_sig_pos4;
      var buf_dur;
      var pan_sig;
      var pan_sig2;

      var env;
      var level=1;
      var grain_env;
      var main_vol=1.0/(1.0+subharmonics+overtones);
      var subharmonic_vol=subharmonics/(1.0+subharmonics+overtones);
      var overtone_vol=overtones/(1.0+subharmonics+overtones);
      // var maxgraindur=ptr_delay/speed.abs;
      var ptr;
      var reset_pos=1;
      var sig,sig2;
      var buf_pos, buf_pos2, out_of_window=0;
      var phasor_start, phasor_end; 
      var localin;
      var switch=0,switch1,switch2,switch3,switch4;
      var reset_sig_ix=0,crossfade;
      
      pos = pos * buf_pos_end;

      density_jitter_sig = TRand.kr(trig: Impulse.kr(density),
        lo: density_jitter.neg,
        hi: density_jitter);
      density = Lag.kr(density+density_jitter_sig);
      spread_pan = Lag.kr(spread_pan);
      // size = Lag.kr(min(size,maxgraindur));
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
  		phasor_start = buf_pos_start+((size)/buffer_length);
  		phasor_end = Clip.kr(buf_pos_start+buf_pos_end,0,buf_pos_end-(size/buffer_length));
      // phasor_start = buf_pos_start + 0.001;
      // phasor_end = buf_pos_end - 0.001;

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
      sig_pos = (sig_pos*(1-sync_to_rec_head)) + (rec_phase.kr.asInteger*sync_to_rec_head);
      sig_pos = (sig_pos - ((ptr_delay * SampleRate.ir)/ BufFrames.kr(buf))).wrap(0,buf_pos_end);
      spread_sig = (spread_sig*buf_pos_end)/4;

      // add jitter and spread to each signal position
      sig_pos1 = (sig_pos+jitter_sig).wrap(0,buf_pos_end);
      sig_pos2 = (sig_pos+jitter_sig2+(spread_sig)+spread_sig_offset1).wrap(0,buf_pos_end);
      sig_pos3 = (sig_pos+jitter_sig3+(spread_sig*2)+spread_sig_offset2).wrap(0,buf_pos_end);
      sig_pos4 = (sig_pos+jitter_sig4+(spread_sig*3)+spread_sig_offset3).wrap(0,buf_pos_end);
      
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


      SendReply.kr(Impulse.kr(10), "/eglut_sigs_pos", [voice, active_sig_pos1/buf_pos_end, active_sig_pos2/buf_pos_end, active_sig_pos3/buf_pos_end, active_sig_pos4/buf_pos_end]);

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
      // ([sig[0],sig[1]]).poll;
      sig=SelectX.ar(Lag.kr(Changed.kr(switch),0.01),[sig,sig2]);

      
      sig = BLowPass4.ar(sig, cutoff, q);
      // sig = BPF.ar(sig, cutoff, q);

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
      Synth.new(\synth, [
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

    thisEngine.addCommand("read", "isf", { arg msg;
      this.readDisk(msg[1] - 1, msg[2],msg[3]);
    });

    thisEngine.addCommand("seek", "if", { arg msg;
      var voice = msg[1] - 1;
      var lvl, pos;
      
      // seek_tasks[voice].stop;

      // TODO: async get
      lvl = levels[voice].getSynchronous();

      pos = msg[2];
      gvoices[voice].set(\pos, pos);
      // gvoices[voice].set(\t_reset_pos, 1 + 110/buffer_length);
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
        // [attack_shape, curve_types[decay_shape].asSymbol]
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
          // oldbuf.free;
        });
      })
      // if (updating_gr_envbufs == false,{
      //   updating_gr_envbufs = true;
      //   oldbuf = gr_envbufs[voice];
      //   gr_envbufs[voice] = Buffer.sendCollection(s, winenv.discretize, 1);
      //   Routine({
      //     0.1.wait;
      //     gvoices[voice].set(\gr_envbuf, gr_envbufs[voice]);
      //     1.wait;
      //     updating_gr_envbufs = false;
      //     oldbuf.free;
      //   }).play;
      // })
      
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
    osc_funcs.put("granulate_live",
      OSCFunc.new({ |msg,time,addr,recvPort|
        var voice=msg[1];
        var sample_duration=msg[2];
        var phase=rec_phase.getSynchronous();

        // ["phase",phase].postln;
        [voice,voice+ngvoices,recorders].postln;
        recorders[voice].set(\sample_duration, sample_duration, \buf_pos_end, sample_duration/buffer_length,  \pos,phase);
        recorders[voice + ngvoices].set(\sample_duration, sample_duration, \buf_pos_end, sample_duration/buffer_length,  \pos,phase);
        (["recorders: ",recorders[voice],recorders[voice + ngvoices]]).postln;
        // lua_sender.sendMsg("/lua_osc/on_granulate_live",1);
        this.setBufStartEnd(voice,live_buffers[voice],2,sample_duration);
      },"/sc_osc/granulate_live");
    );   



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
    live_streamer.free;
    effect.free;
    effectBus.free;
    rec_phase.free;
  }
}