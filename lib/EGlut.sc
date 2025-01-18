//EGlut: grandchild of Glut, parent of ZGlut

EGlut {
  classvar ngvoices = 4;
  
  var s;
  var context;
  var pg;
	var <effect;
  var <pre_live_buffers;
  var <live_buffers;
	var <file_buffers;
	var <gvoices;
  var active_voice;
	var <grainVoiceOutBusses;
	var <effectSendBus;
	var <effectReturnBusL;
	var <effectReturnBusR;
	var <phases;
  var <reset_density_phases;
  var <reset_density_phases_one_shot;
	var <rec_phases;
	var <rec_play_overlaps;
	var <levels;
	var <gr_envbufs;
  var updating_buffers=false;
  var prev_sig_pos1=0,prev_sig_pos2=0,prev_sig_pos3=0,prev_sig_pos4=0;

  var lua_sender;
  var sc_sender;

  var osc_funcs;
  var recorders;
  var max_buffer_length = 15;
  var default_sample_length=10;
  var max_size=5;
    
  var <waveformer;

	*new {
		arg argServer,context,eng;
		^super.new.init(argServer,context,eng);

	}

	// read from an existing buffer into the granulation buffers
	setBufStartEnd { arg voice, buf, mode,sample_start, sample_length, rec_phase;
    var start = sample_start/max_buffer_length;
    var end = (sample_start + sample_length)/max_buffer_length;
    recorders[voice].set(
      \buf_win_start, start, 
      \buf_win_end, end
    );
    recorders[voice + ngvoices].set(
      \buf_win_start, start, 
      \buf_win_end, end
    );
    
    gvoices[voice].set(
      \buf_win_start, start,
      \buf_win_end, end,
    );    
    // Routine({
    //   0.1.wait;
    //   gvoices[voice].set(
    //     \sync_to_rec_head, 0,
    //     \pos,rec_phases[voice].getSynchronous,
    //     \sync_to_rec_head, 1  
    //   );
    //   0.1.wait;
    //   gvoices[voice].set(
    //     \sync_to_rec_head, 0,
    //   );
    // }).play;

	}

  // disk read
	readDisk { arg voice, path, sample_start, sample_length;
    var startframe = 0;
    // if (File.exists(path), {
    if (path.notNil, {
      // load stereo files and duplicate GrainBuf for stereo granulation
      var newbuf,newbuf2;
      var file, numChannels, soundfile_duration;
      var soundfile = SoundFile.new;
      var mode = 1;
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
        file_buffers[voice].path = path;
        gvoices[voice].set(\buf, file_buffers[voice]);
        gvoices[voice].set(\buf_win_start, sample_start/max_buffer_length);
        gvoices[voice].set(\buf_win_end, (sample_start + sample_length)/max_buffer_length);

        ["newbuf",voice,file_buffers[voice]].postln;
        
        if (numChannels > 1,{
          "stereo file: read 2nd channel into buffer's 2nd channel".postln;
          newbuf2 = Buffer.readChannel(context.server, path, channels:[1], action:{
            arg newbuf2;
            file_buffers[voice+ngvoices].zero;
            newbuf2.copyData(file_buffers[voice+ngvoices]);
            file_buffers[voice+ngvoices].path = path;
            gvoices[voice].set(\buf2, file_buffers[voice+ngvoices]);
            ["newbuf2",voice,file_buffers[voice+ngvoices]].postln;
          });
        },{
          "mono file: read 1st channel into buffer's 2nd channel".postln;
          newbuf2 = Buffer.readChannel(context.server, path, channels:[0], action:{

            arg newbuf2;
            file_buffers[voice+ngvoices].zero;
            newbuf2.copyData(file_buffers[voice+ngvoices]);
            file_buffers[voice+ngvoices].path = path;
            gvoices[voice].set(\buf2, file_buffers[voice+ngvoices]);
            ["newbuf2",voice,file_buffers[voice+ngvoices]].postln;
          });
        });
      });
    
    },{
        //if path is nil, assume the file_buffers array already has the buffer
        //and it just needs to be set to the voices
        gvoices[voice].set(\buf, file_buffers[voice]);
        gvoices[voice].set(\buf2, file_buffers[voice+ngvoices]);
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
    
    rec_phases = Array.fill(ngvoices*2, { arg i;
      Bus.control(context.server)
    });
    
    
    rec_play_overlaps = Array.fill(ngvoices, { arg i;
      Bus.control(context.server,4)
    });
    
    pre_live_buffers = Array.fill(ngvoices*2, { arg i;
      Buffer.alloc(s,s.sampleRate * max_buffer_length,1);
    });
    
    live_buffers = Array.fill(ngvoices*2, { arg i;
      Buffer.alloc(s,s.sampleRate * max_buffer_length,1);
    });

    s.sync;

    file_buffers = Array.fill(ngvoices*2, { arg i;
      Buffer.alloc(s,s.sampleRate * max_buffer_length);
    });

    s.sync;

    waveformer = Waveformer.new([live_buffers,file_buffers]);

    s.sync;

    SynthDef("live_recorder", {
      arg voice=0,out=0,
          in=0, //bus for external audio
          mode=0, //0=use external audio, 1=use internal audio from internal_in
          internal_in, //audio bus to use use eglut voices/effects as the audio source
          buf=0,  rate=1,
          pos=0, buf_win_start=0,buf_win_end=1,t_reset_pos=0,
          rec_level=1,pre_level=0,
          rec_phase,
          rec_play_overlap;
      var buf_dur,buf_pos;
      var sig = (mode < 1 * SoundIn.ar(in)) + (mode > 0 * In.ar(internal_in));

      var rec_buf_reset = Impulse.kr(
            freq:((buf_win_end-buf_win_start)*max_buffer_length).reciprocal,
            phase:pos
          );

      var recording_offset = buf_win_start*max_buffer_length*SampleRate.ir;
      
      var overlaps = In.kr(rec_play_overlap,5);
      var overlap0 = overlaps[0];
      var overlap1 = overlaps[1];
      var overlap2 = overlaps[2];
      var overlap3 = overlaps[3];
      var overlaps_trig = (overlap0 + overlap1 + overlap2 + overlap3) > 0;

      var direction = overlaps[4];
      
      SendReply.kr(overlaps_trig, "/recorder_over_sigpos", [voice,overlap0,overlap1,overlap2,overlap3,direction]);

      buf_dur = BufDur.ir(buf);

      buf_pos = Phasor.kr(trig: rec_buf_reset,
        rate: buf_dur.reciprocal / ControlRate.ir * rate,
        start:buf_win_start, end:buf_win_end, resetPos: pos);
      
      // RecordBuf.ar(sig, buf, offset: 1024, 
      RecordBuf.ar(sig, buf, offset: recording_offset, 
                   recLevel: rec_level, preLevel: pre_level, run: 1.0, loop: 1.0, 
                   trigger: rec_buf_reset, doneAction: 0);
      
      Out.kr(rec_phase, buf_pos);
    }).add;

    s.sync;

    SynthDef("grain_synth", {
      arg voice, out, grainVoiceOutL, grainVoiceOutR, effectSendBus, phase_out, level_out, buf, buf2,
      mode=0,
      gate=0, pos=0, 
      rec_play_overlap,
      buf_win_start=0, 
      rec_phase_bus=0,
      buf_win_end=1, 
      sample_length=default_sample_length/max_buffer_length,
      density=1, 
      density_phase_reset=0, 
      speed=1, jitter=0, sig_spread=0, voice_pan=0,	
      size=0.1,
      pitch=1, spread_pan=0, gain=1, dry_wet=1, envscale=1,
      t_reset_pos=0, cutoff=20000, q=0.2, send=0, 
      rec_play_sync=0,sync_to_rec_head=0,
      subharmonics=0,
      overtones=0, overtone1=2, overtone2=4,
      gr_envbuf = -1,
      sig_spread_offset2=0, sig_spread_offset3=0, sig_spread_offset4=0,
      density_lag=0.1, density_lag_curve=0,
      size_lag=0.1,size_lag_curve=0,
      spread_pan_lag=0.1,spread_pan_lag_curve=0,
      cutoff_lag=0.1,cutoff_lag_curve=0,
      send_lag=0.1,send_lag_curve=0,
      pitch_lag=0.1,pitch_lag_curve=0,
      speed_lag=0.1,speed_lag_curve=0,
      pan_lag=0.1,pan_lag_curve=0;

      var rec_phase;
      var grain_trig=1;
      var rec_phase_trig;
      var rec_phase_trig1,rec_phase_trig2,rec_phase_trig3,rec_phase_trig4;
      var grain_jitter_trig=1;
      var trig_rnd;
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
      var reset_pos=1;
      var sig,sig2;
      var buf_pos, buf_pos2, out_of_window=0;
      var window_start, window_end; 
      var switch=0,switch1,switch2,switch3,switch4;
      var reset_sig_ix=0,crossfade;
      var win_size, b_frames;

      // IMPORTANT: win_boundary_size is used to determine if the playhead is leaving the play window, or crossing the recordhead
      // in theory, both require crosfading to prevent pops
      // NOTE: pops still occur so the code needs more work
      var win_boundary_size=1024;

      var rec_phase_frame,rec_phase_win_start,rec_phase_win_end;
      
      // reset_grain_trig triggers whenever the grain_trig phasor completes its cycle
      // out_of_window_trig triggers whenever the playheads leave the buffer window.
    	var localin = LocalIn.kr(2);
      var reset_grain_trig = localin[0];
      var out_of_window_trig = localin[1];

      pos = ((t_reset_pos < 1) * pos) + ((t_reset_pos > 0) * pos.linlin(0,1,buf_win_start,buf_win_end));
      win_size = buf_win_end-buf_win_start-(size/max_buffer_length);
      b_frames = BufFrames.ir(buf);
      
      reset_grain_trig = ((reset_grain_trig >= 1) + (density_phase_reset >= 1)) >= 1;

      density = VarLag.kr(density,density_lag,density_lag_curve);

      grain_trig = Sweep.kr(reset_grain_trig, density).linlin(0, 1, 0, 1, \minmax);
      grain_trig = grain_trig >= 1;
      
      SendReply.kr(grain_trig, "/density_phase_completed", [voice,density_phase_reset]);
      
      size = VarLag.kr(size,size_lag,size_lag_curve);

      spread_pan = VarLag.kr(spread_pan,spread_pan_lag,spread_pan_lag_curve);

      cutoff = VarLag.kr(cutoff,cutoff_lag,cutoff_lag_curve);
      q = Lag.kr(q,0.2);
      send = VarLag.kr(send,send_lag,send_lag_curve);
      pitch = VarLag.kr(pitch,pitch_lag,pitch_lag_curve);

      speed = VarLag.kr(speed,speed_lag,speed_lag_curve);
      voice_pan = VarLag.kr(voice_pan,pan_lag,pan_lag_curve);

      buf_dur = BufDur.ir(buf);

      pan_sig = TRand.kr(trig: grain_trig,lo:-1,hi:(2*spread_pan)-1);

      pan_sig2 = TRand.kr(trig: grain_trig,lo:1-(2*spread_pan),hi:1);

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

  	  // find all the playhead positions outside the window
      switch1 = (BinaryOpUGen('==', out_of_window_trig, 1)) + (BinaryOpUGen('==', out_of_window_trig, 11)) + (BinaryOpUGen('==', out_of_window_trig, 111)) + (BinaryOpUGen('==', out_of_window_trig, 1111));
      switch1 = switch1 > 0;
      switch2 = (BinaryOpUGen('==', out_of_window_trig, 10)) + (BinaryOpUGen('==', out_of_window_trig, 11)) + (BinaryOpUGen('==', out_of_window_trig, 110)) + (BinaryOpUGen('==', out_of_window_trig, 111)) + (BinaryOpUGen('==', out_of_window_trig, 1010)) + (BinaryOpUGen('==', out_of_window_trig, 1011)) + (BinaryOpUGen('==', out_of_window_trig, 1111)) ;
      switch2 = switch2 > 0;
      switch3 = (BinaryOpUGen('==', out_of_window_trig, 100)) + (BinaryOpUGen('==', out_of_window_trig, 101)) + (BinaryOpUGen('==', out_of_window_trig, 110)) + (BinaryOpUGen('==', out_of_window_trig, 111)) + (BinaryOpUGen('==', out_of_window_trig, 1100)) + (BinaryOpUGen('==', out_of_window_trig, 1110)) + (BinaryOpUGen('==', out_of_window_trig, 1111)) ;
      switch3 = switch3 > 0;
      switch4 = (BinaryOpUGen('==', out_of_window_trig, 1000)) + (BinaryOpUGen('==', out_of_window_trig, 1001)) + (BinaryOpUGen('==', out_of_window_trig, 1010)) + (BinaryOpUGen('==', out_of_window_trig, 1011)) + (BinaryOpUGen('==', out_of_window_trig, 1100)) + (BinaryOpUGen('==', out_of_window_trig, 1101)) + (BinaryOpUGen('==', out_of_window_trig, 1110)) + (BinaryOpUGen('==', out_of_window_trig, 1111));
      switch4 = switch4 > 0;      

      // find the first playhead outside the window
      reset_sig_ix = (switch1 > 0) * 1;
      reset_sig_ix = reset_sig_ix + ((reset_sig_ix < 1) * (switch2 > 0 * 2));
      reset_sig_ix = reset_sig_ix + ((reset_sig_ix < 1) * (switch3 > 0 * 3));
      reset_sig_ix = reset_sig_ix + ((reset_sig_ix < 1) * (switch4 > 0 * 4));

      switch = reset_sig_ix > 0;


      // position to jump to when the synth receives a reset trigger
      reset_pos = pos;

      buf_pos = Phasor.kr(trig: t_reset_pos + sync_to_rec_head,
        rate: buf_dur.reciprocal / ControlRate.ir * speed,
        start:buf_win_start, end:buf_win_end, resetPos: (t_reset_pos * reset_pos) + (sync_to_rec_head * reset_pos));

      sig_pos = buf_pos;
      sig_pos = (sig_pos - (((rec_play_sync+0.2) * SampleRate.ir)/ BufFrames.ir(buf))).wrap(buf_win_start,buf_win_end);
      
      // add jitter and spread to each signal position
      sig_spread = (sig_spread*win_size)/4;
      sig_pos1 = (sig_pos+jitter_sig).wrap(buf_win_start,buf_win_end);
      sig_pos2 = (sig_pos+jitter_sig2+(sig_spread)+sig_spread_offset2).wrap(buf_win_start,buf_win_end);
      sig_pos3 = (sig_pos+jitter_sig3+(sig_spread*2)+sig_spread_offset3).wrap(buf_win_start,buf_win_end);
      sig_pos4 = (sig_pos+jitter_sig4+(sig_spread*3)+sig_spread_offset4).wrap(buf_win_start,buf_win_end);
      
      sig2_pos1 = sig_pos1;
      sig2_pos2 = sig_pos2;
      sig2_pos3 = sig_pos3;
      sig2_pos4 = sig_pos4;
      
      ////////////////////////////////////////////////////////////////////////
      // start click prevention code for playheads passing through the start and end points of the loop window
      // note: this isn't working yet fully (or maybe not even partly)

      // if a switch var is < 1 use its existing sig position
      // if a switch var is > 0 set its sig position to the start or end 
      //    of the buffer window, depending on the direction the playhead is moving      
      sig_pos1 = (sig_pos1 * (switch1 < 1)) + ((switch1 > 0) * (speed > 0) * buf_win_end) + ((switch1 > 0) * (speed <= 0) * buf_win_start); 
      sig_pos2 = (sig_pos2 * (switch2 < 1)) + ((switch2 > 0) * (speed > 0) * buf_win_end) + ((switch2 > 0) * (speed <= 0) * buf_win_start); 
      sig_pos3 = (sig_pos3 * (switch3 < 1)) + ((switch3 > 0) * (speed > 0) * buf_win_end) + ((switch3 > 0) * (speed <= 0) * buf_win_start); 
      sig_pos4 = (sig_pos4 * (switch4 < 1)) + ((switch4 > 0) * (speed > 0) * buf_win_end) + ((switch4 > 0) * (speed <= 0) * buf_win_start); 

      // if a switch var is > 0 use its existing sig position
      // if a switch var is < 1 set its sig position to the start or end 
      //    of the buffer window , depending on the direction the playhead is moving      
      sig2_pos1 = (sig2_pos1 * (switch1 > 0)) + ((switch1 < 1) * (speed > 0) * buf_win_end) + ((switch1 < 1) * (speed <= 0) * buf_win_start); 
      sig2_pos2 = (sig2_pos2 * (switch2 > 0)) + ((switch2 < 1) * (speed > 0) * buf_win_end) + ((switch2 < 1) * (speed <= 0) * buf_win_start); 
      sig2_pos3 = (sig2_pos3 * (switch3 > 0)) + ((switch3 < 1) * (speed > 0) * buf_win_end) + ((switch3 < 1) * (speed <= 0) * buf_win_start); 
      sig2_pos4 = (sig2_pos4 * (switch4 > 0)) + ((switch4 < 1) * (speed > 0) * buf_win_end) + ((switch4 < 1) * (speed <= 0) * buf_win_start); 

      // end click prevention code 
      ////////////////////////////////////////////////////////////////////////

      active_sig_pos1 = ((switch1 < 1) * sig_pos1) + ((switch1 > 0) * sig2_pos1);
      active_sig_pos2 = ((switch2 < 1) * sig_pos2) + ((switch2 > 0) * sig2_pos2);
      active_sig_pos3 = ((switch3 < 1) * sig_pos3) + ((switch3 > 0) * sig2_pos3);
      active_sig_pos4 = ((switch4 < 1) * sig_pos4) + ((switch4 > 0) * sig2_pos4);


      //In.kr collects the current position of the voice's record head
      rec_phase = In.kr(rec_phase_bus);

      //create a window for the rec_phase in frames, 
      // 1024 frames before the start of the rec_phase
      // and 1024 frames + the size of the grains in frames after the end of the rec_phase
      //then convert the window values to a 0-1 scale based on the length of the buffer in seconds
      rec_phase_frame = rec_phase * b_frames;

      rec_phase_win_start = rec_phase_frame-(win_boundary_size);
      rec_phase_win_start = Clip.kr(rec_phase_win_start,win_boundary_size,b_frames-(win_boundary_size*10));
      
      // rec_phase_win_end = (rec_phase_frame+(size*BufSampleRate.ir(buf))+(win_boundary_size/2));
      rec_phase_win_end = (rec_phase_frame)+(win_boundary_size);
      rec_phase_win_end = Clip.kr(rec_phase_win_end,rec_phase_win_start+win_boundary_size,b_frames-win_boundary_size);
      
      rec_phase_win_start = rec_phase_win_start/b_frames;
      rec_phase_win_end = rec_phase_win_end/b_frames;

      //check if the recorder position is passing over the active signal positions
      rec_phase_trig1 = ((rec_phase_win_start < active_sig_pos1) * (rec_phase_win_end > active_sig_pos1) > 0);
      rec_phase_trig2 = (((rec_phase_win_start < active_sig_pos2) * (rec_phase_win_end > active_sig_pos2)) > 0);
      rec_phase_trig3 = (((rec_phase_win_start < active_sig_pos3) * (rec_phase_win_end > active_sig_pos3)) > 0);
      rec_phase_trig4 = (((rec_phase_win_start < active_sig_pos4) * (rec_phase_win_end > active_sig_pos4)) > 0);
      
      rec_phase_trig = (rec_phase_trig1 + rec_phase_trig2 + rec_phase_trig3 + rec_phase_trig4) > 0;
  		

      ////////////////////////////////////////////////////////////////////////
      // start click prevention code for rec head passing over the play head
      // note: this isn't working yet fully (or maybe not even partly)

      // if a rec_phase_trig var is < 1 use the sig's existing position
      // if a rec_phase_trig var is > 0, move the sig a bit before the record head:
      
      sig_pos1 = (sig_pos1 * (rec_phase_trig1 < 1)) + ((switch1 < 1) * (rec_phase_trig1 > 0) * ((rec_phase_frame - (win_boundary_size*3))/b_frames)); 
      sig_pos2 = (sig_pos2 * (rec_phase_trig2 < 1)) + ((switch2 < 1) * (rec_phase_trig2 > 0) * ((rec_phase_frame - (win_boundary_size*3))/b_frames)); 
      sig_pos3 = (sig_pos3 * (rec_phase_trig3 < 1)) + ((switch3 < 1) * (rec_phase_trig3 > 0) * ((rec_phase_frame - (win_boundary_size*3))/b_frames)); 
      sig_pos4 = (sig_pos4 * (rec_phase_trig4 < 1)) + ((switch4 < 1) * (rec_phase_trig4 > 0) * ((rec_phase_frame - (win_boundary_size*3))/b_frames)); 

      sig2_pos1 = (sig2_pos1 * (rec_phase_trig1 < 1)) + ((switch1 > 0) * (rec_phase_trig1 > 0) * ((rec_phase_frame - (win_boundary_size*3))/b_frames)); 
      sig2_pos2 = (sig2_pos2 * (rec_phase_trig2 < 1)) + ((switch2 > 0) * (rec_phase_trig2 > 0) * ((rec_phase_frame - (win_boundary_size*3))/b_frames)); 
      sig2_pos3 = (sig2_pos3 * (rec_phase_trig3 < 1)) + ((switch3 > 0) * (rec_phase_trig3 > 0) * ((rec_phase_frame - (win_boundary_size*3))/b_frames)); 
      sig2_pos4 = (sig2_pos4 * (rec_phase_trig4 < 1)) + ((switch4 > 0) * (rec_phase_trig4 > 0) * ((rec_phase_frame - (win_boundary_size*3))/b_frames)); 

      // end click prevention code 
      ////////////////////////////////////////////////////////////////////////




      active_sig_pos1 = ((switch1 < 1) * sig_pos1) + ((switch1 > 0) * sig2_pos1);
      active_sig_pos2 = ((switch2 < 1) * sig_pos2) + ((switch2 > 0) * sig2_pos2);
      active_sig_pos3 = ((switch3 < 1) * sig_pos3) + ((switch3 > 0) * sig2_pos3);
      active_sig_pos4 = ((switch4 < 1) * sig_pos4) + ((switch4 > 0) * sig2_pos4);
      
      //calculate the signal position relative to the window of the active buffer (buf_win_start/buf_win_end)
      window_sig_pos1 = active_sig_pos1.linlin(buf_win_start,buf_win_end,0,1);
      window_sig_pos2 = active_sig_pos2.linlin(buf_win_start,buf_win_end,0,1);
      window_sig_pos3 = active_sig_pos3.linlin(buf_win_start,buf_win_end,0,1);
      window_sig_pos4 = active_sig_pos4.linlin(buf_win_start,buf_win_end,0,1);

      SendReply.kr(Impulse.kr(15), "/eglut_sigs_pos", [voice,window_sig_pos1, window_sig_pos2, window_sig_pos3, window_sig_pos4]);
      // constantly queue waveform generation if mode "live" (but not "recorded")
      SendReply.kr(Impulse.kr(5), "/queue_waveform_generation", [mode,voice,buf_win_start,buf_win_end-buf_win_start]);

      sig = 0.25 * (GrainBuf.ar(
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
            rate:pitch/3,
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
            rate:pitch*overtone1,
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
            rate:pitch*overtone1,
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
            rate:pitch*overtone2,
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
            rate:pitch*overtone2,
            envbufnum:gr_envbuf,
            maxGrains:16,
            mul:overtone_vol*0.3,
      ));

      sig2 = 0.25 * (GrainBuf.ar(
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
            rate:pitch/3,
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
            rate:pitch*overtone1,
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
            rate:pitch*overtone1,
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
            rate:pitch*overtone2,
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
            rate:pitch*overtone2,
            envbufnum:gr_envbuf,
            maxGrains:16,
            mul:overtone_vol*0.3,
      ));
  		

      //create a window in frames, slightly smaller than the current sample window
      // so we know when the playhead leaves the sample window frame
      // 1024 frames (win_boundary_size) after the start of the buffer window (buf_win_start)
      // and 1024 frames before the end of the buffer window (buf_win_end)
      //then convert the window values to a 0-1 scale based on the length of the buffer in seconds
      window_start = buf_win_start * b_frames;
      window_start = window_start+win_boundary_size;
      window_start = Clip.kr(window_start,win_boundary_size,b_frames-(win_boundary_size*10));
      
      window_end = buf_win_end * b_frames;
      window_end = window_end-win_boundary_size;
      window_end = Clip.kr(window_end,window_start+win_boundary_size,b_frames-win_boundary_size);

      window_start = window_start/b_frames;
      window_end = window_end/b_frames;      

      //determine if any of the four "active" playheads are outside the buffer window
      out_of_window = ((1*(( (active_sig_pos1 + (size/b_frames)) > window_end) + (active_sig_pos1 < window_start))) +
                       (10*(( (active_sig_pos2 + (size/b_frames)) > window_end) + (active_sig_pos2 < window_start))) +
                       (100*(( (active_sig_pos3 + (size/b_frames)) > window_end) + (active_sig_pos3 < window_start))) +
                       (1000*(( (active_sig_pos4 + (size/b_frames)) > window_end) + (active_sig_pos4 < window_start))));

      
      // crossfade bewteen the two sounds over 1000 milliseconds
      // when a playhead is looping between the start and end points
      // or when the record head passes over one of the playheads
      switch = switch > 0;
      sig=SelectX.ar(Lag.kr((Changed.kr(switch+rec_phase_trig > 0)),0.05),[sig,sig2]);
      // sig=SelectX.ar(Lag.kr(switch,0.05),[sig,sig2]);
      SendReply.kr(switch, "/switch", [voice,speed]);

      sig = BLowPass4.ar(sig, cutoff, q);
      sig = Compander.ar(sig,sig,0.25)/envscale;
      sig = Balance2.ar(sig[0],sig[1],voice_pan);
      
      env = EnvGen.kr(Env.asr(1, 1, 1), gate: gate, timeScale: envscale);
      level = env;
    
      //control outs
      Out.kr(rec_play_overlap,[rec_phase_trig1, rec_phase_trig2, rec_phase_trig3, rec_phase_trig4, speed > 0]);
      Out.kr(phase_out, sig_pos);
      Out.kr(level_out, level);
      LocalOut.kr([grain_trig,out_of_window]);
    
      //audio outs
      Out.ar(grainVoiceOutL, sig[0] * level * 4); // ignore gain for grainVoiceOut
      Out.ar(grainVoiceOutR, sig[1] * level * 4); // ignore gain for grainVoiceOut
      Out.ar(effectSendBus, sig * level * 2 * send); // ignore gain for effect
      Out.ar(out, sig * level * gain); 
      
    }).add;

    SynthDef(\effect, {
      arg in, out, returnL, returnR, effectVol=0, echoTime=2.0, damp=0.1, size=4.0, diff=0.7, feedback=0.2, modDepth=0.1, modFreq=0.1;
      var sig = In.ar(in, 2), gsig;      
      gsig = Greyhole.ar(sig, echoTime, damp, size, diff, feedback, modDepth, modFreq);
      Out.ar(returnL, gsig);
      Out.ar(returnR, gsig);
      Out.ar(out, gsig * effectVol);
    }).add;

    s.sync;

    // grain out bus
    grainVoiceOutBusses = Array.fill(ngvoices*2, { arg i;
      Bus.audio(context.server, 1);
    });
    
    // effect busses
    effectSendBus = Bus.audio(context.server, 2);
    effectReturnBusL = Bus.audio(context.server, 1);
    effectReturnBusR = Bus.audio(context.server, 1);
    s.sync;

    phases = Array.fill(ngvoices, { arg i; Bus.control(context.server); });
    levels = Array.fill(ngvoices, { arg i; Bus.control(context.server); });
    gr_envbufs = Array.fill(ngvoices, { arg i; 
      var winenv = Env([0, 1, 0], [0.5, 0.5], [\wel, \wel]);
      Buffer.sendCollection(s, winenv.discretize, 1);
    });

    pg = ParGroup.head(context.xg);
    
    //instantiate the live recorders and grain voices
    s.bind({ 
      recorders = Array.newClear(ngvoices*2);
      gvoices = Array.newClear(ngvoices);
      ngvoices.do({ arg i;
        recorders.put(i,
          Synth.tail(pg,\live_recorder, [
            \voice, i,
            \pre_buf,pre_live_buffers[i],
            \buf,live_buffers[i],
            \in,0,
            \rec_phase,rec_phases[i].index,
            \rec_play_overlap,rec_play_overlaps[i].index
          ])
        );
        recorders.put(i+ngvoices,
          Synth.after(recorders[i],\live_recorder, [
            \voice, i,
            \pre_buf,pre_live_buffers[i+ngvoices],
            \buf,live_buffers[i+ngvoices],
            \in,1,
            \rec_phase,rec_phases[i+ngvoices].index,
            \rec_play_overlap,rec_play_overlaps[i].index
          ])
        );
        gvoices.put(i,
          Synth.after(recorders[i+ngvoices],\grain_synth, [
            \voice, i,
            \out, context.out_b.index,
            \grainVoiceOutL, grainVoiceOutBusses[i].index,
            \grainVoiceOutR, grainVoiceOutBusses[i+ngvoices].index,
            \rec_phase_bus,rec_phases[i].index,
            \rec_play_overlap,rec_play_overlaps[i].index,
            \effectSendBus, effectSendBus.index,
            \phase_out, phases[i].index,
            \level_out, levels[i].index,
            \buf, live_buffers[i],
            \buf2, live_buffers[i+ngvoices],
            // \gr_envbuf, -1
            \gr_envbuf, gr_envbufs[i]
          ])
        );
      });
    });

    context.server.sync;

    // Routine({ 1.wait; "print nodes".postln;context.server.queryAllNodes.postln; }).play;

    (["second eglut init sync",grainVoiceOutBusses]).postln;
    thisEngine.addCommand("effects_on", "i", { arg msg; 
      if((msg[1]==1).and(effect.notNil),{
        effect.free;
        // effect.release;
        effect = nil;
        (["echo off",effect]).postln;
      });
      if((msg[1]==2).and(effect.isNil),{
        s.bind({ 
          effect = Synth.before(recorders[ngvoices-1],\effect, [
            \in, effectSendBus.index, 
            \returnL, effectReturnBusL.index,
            \returnR, effectReturnBusR.index,
            \out, context.out_b.index
          ]);
        });
        (["echo on",effect,effectReturnBusL.index,effectReturnBusR.index]).postln;
        // Routine({ 1.wait; "print nodes".postln; context.server.queryAllNodes.postln; }).play;
      });
    });

    thisEngine.addCommand("echo_volume", "f", { arg msg; if(effect.notNil,{effect.set(\effectVol, msg[1])}); });
    thisEngine.addCommand("echo_time", "f", { arg msg; if(effect.notNil,{effect.set(\echoTime, msg[1])}); });
    thisEngine.addCommand("echo_damp", "f", { arg msg; if(effect.notNil,{effect.set(\damp, msg[1])}); });
    thisEngine.addCommand("echo_size", "f", { arg msg; if(effect.notNil,{effect.set(\size, msg[1])}); });
    thisEngine.addCommand("echo_diff", "f", { arg msg; if(effect.notNil,{effect.set(\diff, msg[1])}); });
    thisEngine.addCommand("echo_fdbk", "f", { arg msg; if(effect.notNil,{effect.set(\feedback, msg[1])}); });
    thisEngine.addCommand("echo_mod_depth", "f", { arg msg; if(effect.notNil,{effect.set(\modDepth, msg[1])}); });
    thisEngine.addCommand("echo_mod_freq", "f", { arg msg; if(effect.notNil,{effect.set(\modFreq, msg[1])}); });

    thisEngine.addCommand("live_source", "is", { arg msg;
      var voice = msg[1] - 1;
      var source = msg[2].asString;
      var sourceBusses = Array.newClear(2);
      var rec1_old,rec2_old;
      if (source == "in", { 
        recorders[voice].set(\mode, 0);
        recorders[voice+ngvoices].set(\mode, 0);
        (["set live source mode external: mode 0"]).postln;
      },{
        ngvoices.do({ arg i; 
          if (source == ("voice" ++ i), { 
            sourceBusses[0] = grainVoiceOutBusses[i].index; 
            sourceBusses[1] = grainVoiceOutBusses[i+ngvoices].index; 
          });
        });
        if (source == "effect", { sourceBusses[0] = effectReturnBusL.index; sourceBusses[1] = effectReturnBusR.index });
        
        (["set live source mode internal: mode 1",source]).postln;
        // (["update live source", voice, source, sourceBusses,grainVoiceOutBusses]).postln;
        recorders[voice].set(\mode, 1);
        recorders[voice].set(\internal_in, sourceBusses[0]);
        recorders[voice+ngvoices].set(\mode, 1);
        recorders[voice+ngvoices].set(\internal_in, sourceBusses[1]);
      });
    });

    thisEngine.addCommand("read", "isff", { arg msg;
      var voice = msg[1]-1;
      var path = msg[2];
      var sample_start = msg[3];
      var sample_length = msg[4];
      var bpath = file_buffers[voice].path;
      if((bpath.notNil).and(bpath == path),{
        (["file already loaded",path]).postln;
        this.readDisk(voice,nil,sample_start,sample_length);
      },{
        (["new file to load",path,bpath]).postln;
        this.readDisk(voice,path,sample_start,sample_length);
      });
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

    thisEngine.addCommand("rec_play_sync", "if", { arg msg;
      var voice = msg[1] - 1;
      var rec_phase;
        rec_phase=rec_phases[voice].getSynchronous;
        gvoices[voice].set(\speed,1,\pos, rec_phase/2,\rec_play_sync, msg[2], \sync_to_rec_head, 1);
        recorders[voice].set(\t_reset_pos, 1);
        recorders[voice+ngvoices].set(\t_reset_pos, 1);

        ["set rec_play_sync",rec_phase/2].postln;
        Routine({
          0.1.wait;
          gvoices[voice].set(\sync_to_rec_head, 0);
          recorders[voice].set(\t_reset_pos, 0);
          recorders[voice+ngvoices].set(\t_reset_pos, 0);
        }).play;
    });

    OSCdef(\eglut_rec_phases, {|msg| 
      var voice = msg[3];
      var t_reset_pos = msg[4];
      var rec_buf_reset = msg[5];
      var buf_pos = msg[6];
      var buf_win_start = msg[7];
      var buf_win_end = msg[8];
      // ([voice,t_reset_pos,rec_buf_reset,buf_pos,buf_win_start,buf_win_end]).postln;
    }, "/eglut_rec_phases");


    thisEngine.addCommand("speed", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\speed, msg[2]);
      gvoices[voice].set(\sync_to_rec_head, 0);
    });

    thisEngine.addCommand("speed_lag", "if", { arg msg;
      var voice = msg[1] - 1;
      var speed_lag = msg[2];
      gvoices[voice].set(
        \speed_lag, speed_lag
      );    
    });

    thisEngine.addCommand("speed_lag_curve", "if", { arg msg;
      var voice = msg[1] - 1;
      var speed_lag_curve = msg[2];
      gvoices[voice].set(
        \speed_lag_curve, speed_lag_curve
      );    
    });


    thisEngine.addCommand("sig_spread", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\sig_spread, msg[2]);
    });

    thisEngine.addCommand("sig_spread_offset2", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\sig_spread_offset2, msg[2]);
    });

    thisEngine.addCommand("sig_spread_offset3", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\sig_spread_offset3, msg[2]);
    });

    thisEngine.addCommand("sig_spread_offset4", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\sig_spread_offset4, msg[2]);
    });

    thisEngine.addCommand("jitter", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\jitter, msg[2]);
    });

    thisEngine.addCommand("size", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\size, msg[2]);
    });

    thisEngine.addCommand("size_lag", "if", { arg msg;
      var voice = msg[1] - 1;
      var size_lag = msg[2];
      gvoices[voice].set(
        \size_lag, size_lag
      );    
    });
    
    thisEngine.addCommand("size_lag_curve", "if", { arg msg;
      var voice = msg[1] - 1;
      var size_lag_curve = msg[2];
      gvoices[voice].set(
        \size_lag_curve, size_lag_curve
      );    
    });

    thisEngine.addCommand("pan", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\voice_pan, msg[2]);
    });

    thisEngine.addCommand("pan_lag", "if", { arg msg;
      var voice = msg[1] - 1;
      var voice_pan_lag = msg[2];
      gvoices[voice].set(
        \voice_pan_lag, voice_pan_lag
      );    
    });

    thisEngine.addCommand("pan_lag_curve", "if", { arg msg;
      var voice = msg[1] - 1;
      var voice_pan_lag_curve = msg[2];
      gvoices[voice].set(
        \voice_pan_lag_curve, voice_pan_lag_curve
      );    
    });
    
    thisEngine.addCommand("pitch", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\pitch, msg[2]);
    });

    thisEngine.addCommand("pitch_lag", "if", { arg msg;
      var voice = msg[1] - 1;
      var pitch_lag = msg[2];
      gvoices[voice].set(
        \pitch_lag, pitch_lag
      );    
    });

    thisEngine.addCommand("pitch_lag_curve", "if", { arg msg;
      var voice = msg[1] - 1;
      var pitch_lag_curve = msg[2];
      gvoices[voice].set(
        \pitch_lag_curve, pitch_lag_curve
      );    
    });


    thisEngine.addCommand("spread_pan", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\spread_pan, msg[2]);
    });

    thisEngine.addCommand("spread_pan_lag", "if", { arg msg;
      var voice = msg[1] - 1;
      var spread_pan_lag = msg[2];
      gvoices[voice].set(
        \spread_pan_lag, spread_pan_lag
      );    
    });

    thisEngine.addCommand("spread_pan_lag_curve", "if", { arg msg;
      var voice = msg[1] - 1;
      var spread_pan_lag_curve = msg[2];
      gvoices[voice].set(
        \spread_pan_lag_curve, spread_pan_lag_curve
      );    
    });

    thisEngine.addCommand("dry_wet", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\dry_wet, msg[2]);
    });

    thisEngine.addCommand("gain", "if", { arg msg;
      var voice = msg[1] - 1;
      var gain_mul = 4;
      gvoices[voice].set(\gain, msg[2]*gain_mul);
    });
    

    thisEngine.addCommand("density", "if", { arg msg;
      var voice = msg[1] - 1;
      var density = msg[2];
      gvoices[voice].set(
        \density, density
      );    
    });
    
    thisEngine.addCommand("density_lag", "if", { arg msg;
      var voice = msg[1] - 1;
      var density_lag = msg[2];
      gvoices[voice].set(
        \density_lag, density_lag
      );    
    });
    
    thisEngine.addCommand("density_lag_curve", "if", { arg msg;
      var voice = msg[1] - 1;
      var density_lag_curve = msg[2];
      gvoices[voice].set(
        \density_lag_curve, density_lag_curve
      );    
    });
    
    thisEngine.addCommand("gr_envbuf", "ifffff", { arg msg;
      var voice = msg[1] - 1;
      var attack_level = msg[2];
      var attack_time = msg[3];
      var decay_time = msg[4];
      var shape = msg[5]-1;
      var size = msg[6];

      var oldbuf;
      var curve_types=["exp","squared","lin","sin","cubed","wel","wel"];
      var winenv = Env(
        [0.001, attack_level, 0.001], 
        [attack_time*size, decay_time*size], 
        [curve_types[shape].asSymbol,curve_types[shape].asSymbol]
      );

      if (updating_buffers == false,{
        updating_buffers = true;
        Buffer.sendCollection(s, winenv.discretize(n:(1024*size).softRound(resolution:0.00390625,margin:0)), action:{
          arg buf;
          var oldbuf = gr_envbufs[voice];
          Routine({
            gvoices[voice].set(\gr_envbuf, buf);
            gr_envbufs[voice] = buf;
            0.1.wait;
            updating_buffers = false;
            2.wait;
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
    
    thisEngine.addCommand("cutoff_lag", "if", { arg msg;
      var voice = msg[1] - 1;
      var cutoff_lag = msg[2];
      gvoices[voice].set(
        \cutoff_lag, cutoff_lag
      );    
    });

    thisEngine.addCommand("cutoff_lag_curve", "if", { arg msg;
      var voice = msg[1] - 1;
      var cutoff_lag_curve = msg[2];
      gvoices[voice].set(
        \cutoff_lag_curve, cutoff_lag_curve
      );    
    });

    thisEngine.addCommand("q", "if", { arg msg;
    var voice = msg[1] -1;
    gvoices[voice].set(\q, msg[2]);
    });
    
    thisEngine.addCommand("send", "if", { arg msg;
    var voice = msg[1] -1;
    gvoices[voice].set(\send, msg[2]);
    });

    thisEngine.addCommand("send_lag", "if", { arg msg;
      var voice = msg[1] - 1;
      var send_lag = msg[2];
      gvoices[voice].set(
        \send_lag, send_lag
      );    
    });

    thisEngine.addCommand("send_lag_curve", "if", { arg msg;
      var voice = msg[1] - 1;
      var send_lag_curve = msg[2];
      gvoices[voice].set(
        \send_lag_curve, send_lag_curve
      );    
    });

    
    thisEngine.addCommand("volume", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\gain, msg[2]);
    });
    
    thisEngine.addCommand("overtones", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\overtones, msg[2]);
    });
    
    thisEngine.addCommand("overtone1", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\overtone1, msg[2]);
    });
    
    thisEngine.addCommand("overtone2", "if", { arg msg;
      var voice = msg[1] - 1;
      gvoices[voice].set(\overtone2, msg[2]);
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
      },"/sc_osc/set_sample_position");
    );   

    osc_funcs.put("set_mode",
      OSCFunc.new({ |msg,time,addr,recvPort|
        var voice=msg[1];
        var mode=msg[2]; // 0: live, 1: recorded
        var buf_array_ix;
        (["set mode",voice,mode]);
        gvoices[voice].set(\mode, mode);

        if (mode < 1, { buf_array_ix = 0 }, { buf_array_ix = 1 });
        waveformer.stopWaveformGeneration(buf_array_ix,voice);        
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
        gvoices[voice].set(\mode, 0);
        this.setBufStartEnd(voice,live_buffers[voice],2,sample_start,sample_length);
      },"/sc_osc/granulate_live");
    );   

    osc_funcs.put("sync_density_phases",
      OSCFunc.new({ |msg,time,addr,recvPort|
        var voice=msg[1];
        var sync=msg[2];
        reset_density_phases[voice]=sync;
      },"/sc_osc/sync_density_phases");
    );   

    osc_funcs.put("sync_density_phases_one_shot",
      OSCFunc.new({ |msg,time,addr,recvPort|
        var voice=msg[1];
        reset_density_phases_one_shot[voice]=1;
      },"/sc_osc/sync_density_phases_one_shot");
    );   


    // osc.send( { "localhost", 57120 }, "/sc_osc/sync_density_phases_one_shot",{0})
    OSCdef(\density_phase_completed, {|msg| 
      var voice = msg[3].asInteger;
      var density_phase = msg[4].asInteger;
      // if (voice < 2,{ (["grain phase completed",voice, density_phase]).postln; });
      // if (density_phase == 1, { gvoices[voice].set(\density_phase_reset,0) });

      if (reset_density_phases[voice] == 1,{ 
        ngvoices.do({ arg i; 
          if ((i != voice).and(gvoices[i].notNil),{
            Routine({
              (["sync voice phase,from/to", voice, i]).postln;
              gvoices[i].set(\density_phase_reset,1);
              0.001.wait;
              gvoices[i].set(\density_phase_reset,0);
            }).play;
          })
        });
      });

      if (reset_density_phases_one_shot[voice] == 1,{ 
        reset_density_phases_one_shot[voice]=0;
        ngvoices.do({ arg i; 
          if ((i != voice).and(gvoices[i].notNil),{
            Routine({
              (["one shot sync voice phase,from/to", voice, i,gvoices[i]]).postln;
              gvoices[i].set(\density_phase_reset,1);
              0.001.wait;
              gvoices[i].set(\density_phase_reset,0);
            }).play;
          })
        });
      });
    }, "/density_phase_completed");

    OSCdef(\recorder_over_sigpos, {|msg| 
      var voice = msg[3].asInteger;
      var pos1 = msg[4].asInteger;
      var pos2 = msg[5].asInteger;
      var pos3 = msg[6].asInteger;
      var pos4 = msg[7].asInteger;
      var direction = msg[8];
      if (voice < 1,{ (["recorder_over_sigpos",voice,direction]).postln; });
    }, "/recorder_over_sigpos");

    OSCdef(\switch, {|msg| 
      var voice = msg[3].asInteger;
      if (voice < 1,{ (["switch",msg]).postln; });
    }, "/switch");

    OSCdef(\queue_waveform_generation, {|msg| 
      var mode = msg[3];
      var voice = msg[4];
      var sample_start = msg[5];
      var sample_length = msg[6];
      var buf_array_ix;
      if (mode < 1, { buf_array_ix = 0 }, { buf_array_ix = 1 });
      if (voice == active_voice,{
      // (["waveformer.queueWaveformGeneration",voice,mode,live_buffers[0],buf_array_ix]).postln;
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
          // (msg).postln; 
          // if (voice < 1,{([sig_pos1, sig_pos2, sig_pos3, sig_pos4]).postln}) ; 
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
    osc_funcs.keysValuesDo({ arg k,val; val.free; });
    waveformer.waveformRoutine.stop();
    gvoices.do({ arg val; val.free; });
    recorders.do({ arg val; val.free; });
    gr_envbufs.do({ arg val; val.free; });
    file_buffers.do({ arg val; val.free; });
    live_buffers.do({ arg val; val.free; });
    phases.do({ arg val; val.free; });
    levels.do({ arg val; val.free; });
    rec_phases.free;
    effect.free;
    effectSendBus.free;
    waveformer.free;
    pg.free;     
    "eglut cleanup done".postln; 
  }
}
