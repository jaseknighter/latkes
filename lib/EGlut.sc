//EGlut: grandchild of Glut, parent of ZGlut
//mostly, this adds grain envelopes to the ZGlut engine

EGlut {
  classvar ngvoices = 4;
  
  var s;
  var context;
  var pg;
	var effect;
  var grain_modes; //grain_mode 0=live grain_mode; 1=file grain_mode
	var <buffers;
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
  var live_buffer;
  var live_buffer_length = 120;
    

	*new {
		arg argServer, context, eng;
		^super.new.init(argServer,context,eng);

	}

	setGrainMode { arg voice,mode;
    grain_modes[voice]=mode;
  }

	// read from an existing buffer into the granulation buffsers
	readBuf { arg i, buf, mode,sample_duration;
    ["readBuf set voices and buffers",i,buf,buffers, mode].postln;
    // if(buffers[i].sampleRate!=nil, {
    //   buffers[i].zero;
    //   buffers[i+ngvoices].zero;
    // });

    if (mode.notNil,{
      this.setGrainMode(mode);
    });
    // duplicate GrainBuf for stereo granulation
    gvoices[i].set(\buf, buf);
    gvoices[i].set(\buf_pos_end, sample_duration/live_buffer_length);
    // buffers[i] = buf;
    gvoices[i].set(\buf2, buf);
    gvoices[i].set(\buf_pos_end, sample_duration/live_buffer_length);
    // buffers[i+ngvoices] = buf;

    
    ["readBuf done i,modem,sample_duration,live_buffer_length",i,mode,sample_duration,live_buffer_length].postln;
	}

  // disk read
	readDisk { arg i, path;
		if(buffers[i].notNil, {
      grain_modes[i]=1;
			if (File.exists(path), {
				// load stereo files and duplicate GrainBuf for stereo granulation
        var newbuf,newbuf2;
        var buflen=60;
        ["read disk"].postln;
        // newbuf = Buffer.readChannel(context.server, path, 0, -1, [0], {
        newbuf = Buffer.readChannel(context.server, path, 0, s.sampleRate * buflen, [0], {
          // if (buffers[i].sampleRate!=nil,{
          //   buffers[i].free;
          // });
					gvoices[i].set(\buf, newbuf);
					buffers[i] = newbuf;
          ["newbuf",i,buffers[i]].postln;
				});
				// newbuf2 = Buffer.readChannel(context.server, path, 0, -1, [1], {
				newbuf2 = Buffer.readChannel(context.server, path, 0, -1, [0], {
					// if (buffers[i+ngvoices].sampleRate!=nil,{
          //   buffers[i+ngvoices].free;
          //   });
				  gvoices[i].set(\buf2, newbuf2);
					buffers[i+ngvoices] = newbuf2;
				});
			});
		});
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
    recorders=Dictionary.new();
    
    lua_sender = NetAddr.new("127.0.0.1",10111);   
    sc_sender=NetAddr.new("127.0.0.1",57120);   
    
		s=argServer;
    context = engContext;
    thisEngine = eng;
    
    grain_modes = Array.fill(ngvoices, { arg i;
      1;
    });

    buffers = Array.fill(ngvoices*2, { arg i;
      Buffer.alloc(
        s,
        s.sampleRate * live_buffer_length,
      );
    });

    // live streamer position bus
    rec_phase=Bus.control(context.server);
    ["rec_phase",rec_phase].postln;
    
    SynthDef("live_streamer", {
      arg in=0,out=0,phase,
          buf=0, rate=1,
          pos=0,buf_pos_start=0,buf_pos_end=1,t_reset_pos=1,
          // pos=0,buf_pos_start=0,sample_duration=10,t_reset_pos=1,
          // pos=0,buf_pos_start=0,buf_pos_end=1,sample_duration=10,t_reset_pos=1,
          // dry_wet=1,
          write_live_stream_enabled=1,
          rec_level=1,pre_level=0;
      var buf_dur,buf_pos;
      var sig=SoundIn.ar(in);
	    // var dry_sig=LinLin.kr(dry_wet,1,0,0,1);
      // var wet_sig=LinLin.kr(dry_wet,0,1,0,1);
      var rec_pos;
      // var rec_buf_reset = Impulse.kr(1);
      var rec_buf_reset = Impulse.kr((buf_pos_end*live_buffer_length).reciprocal);

      buf_dur = BufDur.kr(buf);
      buf_pos = Phasor.kr(trig: t_reset_pos,
        rate: buf_dur.reciprocal / ControlRate.ir * rate,
        start:buf_pos_start, end:buf_pos_end, resetPos: pos);
      
      // dry_sig=min(1,dry_sig);
      // wet_sig=max(0,wet_sig);
      // RecordBuf.ar(sig*wet_sig, buf, offset: 0, recLevel: rec_level, preLevel: pre_level, run: 1.0, loop: 1.0, trigger: write_live_stream_enabled, doneAction: 0);
      // [rec_buf_reset,buf_pos].poll;
      
      RecordBuf.ar(sig, buf, offset: 0, recLevel: rec_level, preLevel: pre_level, run: 1.0, loop: 1.0, trigger: rec_buf_reset * write_live_stream_enabled, doneAction: 0);
      // RecordBuf.ar(sig, buf, offset: 0, recLevel: rec_level, preLevel: pre_level, run: 1.0, loop: 1.0, trigger: write_live_stream_enabled, doneAction: 0);
      
      Out.kr(rec_phase.index, buf_pos);
      // Out.ar(out,sig*dry_sig);
    }).add;

    SynthDef(\synth, {
      arg voice, out, effectBus, phase_out, level_out, buf, buf2,
      gate=0, pos=0, 
      buf_pos_start=0, 
      buf_pos_end=1, 
      sample_duration=10/120,
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
      var sig_pos, sig_pos1, sig_pos2, sig_pos3, sig_pos4;
      var buf_dur;
      var pan_sig;
      var pan_sig2;
      var buf_pos;
      var sig;

      var env;
      var level=1;
      var grain_env;
      var main_vol=1.0/(1.0+subharmonics+overtones);
      var subharmonic_vol=subharmonics/(1.0+subharmonics+overtones);
      var overtone_vol=overtones/(1.0+subharmonics+overtones);
      var maxgraindur=ptr_delay/speed.abs;
      var ptr;
      var reset_pos=1;


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

      jitter_sig = TRand.kr(trig: grain_trig,
        lo: buf_dur.reciprocal.neg * jitter,
        hi: buf_dur.reciprocal * jitter);
      jitter_sig2 = TRand.kr(trig: grain_trig,
        lo: buf_dur.reciprocal.neg * jitter,
        hi: buf_dur.reciprocal * jitter);
      jitter_sig3 = TRand.kr(trig: grain_trig,
        lo: buf_dur.reciprocal.neg * jitter,
        hi: buf_dur.reciprocal * jitter);
      jitter_sig4 = TRand.kr(trig: grain_trig,
        lo: buf_dur.reciprocal.neg * jitter,
        hi: buf_dur.reciprocal * jitter);



      reset_pos = pos;
      buf_pos = Phasor.kr(trig: t_reset_pos,
        rate: buf_dur.reciprocal / ControlRate.ir * speed,
        start:buf_pos_start, end:buf_pos_end, resetPos: reset_pos);

      sig_pos = buf_pos;
      sig_pos = (sig_pos*(1-sync_to_rec_head)) + (rec_phase.kr.asInteger*sync_to_rec_head);
      sig_pos = (sig_pos - ((ptr_delay * SampleRate.ir)/ BufFrames.kr(buf))).wrap(0,buf_pos_end);
      // sig_pos = max(sig_pos,0);
      // sig_pos = min(sig_pos,1);
      // sig_pos = (sig_pos * ((pos/buf_pos_end) < 1)) + (not((pos/buf_pos_end)<1));
      spread_sig = (spread_sig*buf_pos_end)/4;
      sig_pos1=(sig_pos+jitter_sig).wrap(0,buf_pos_end);
      sig_pos2=(sig_pos+jitter_sig2+(spread_sig)+spread_sig_offset1).wrap(0,buf_pos_end);
      sig_pos3=(sig_pos+jitter_sig3+(spread_sig*2)+spread_sig_offset2).wrap(0,buf_pos_end);
      sig_pos4=(sig_pos+jitter_sig4+(spread_sig*3)+spread_sig_offset3).wrap(0,buf_pos_end);

      ([sig_pos <= buf_pos_start, sig_pos >= buf_pos_end]).poll;

      // scale sig_pos sent to lua to be proportional to the variable sample duration value,
      // not the entire buffer value
      SendReply.kr(Impulse.kr(10), "/eglut_sigs_pos", [voice, sig_pos1/buf_pos_end, sig_pos2/buf_pos_end, sig_pos3/buf_pos_end, sig_pos4/buf_pos_end]);

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
            maxGrains:96,//96/2,//96,
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
            maxGrains:96,//96/2,//96,
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
            maxGrains:72,//24,//72,
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
            maxGrains:72,//24,//72,
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
            maxGrains:32,//24,//32,
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
            maxGrains:32,//24,//32,
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
            maxGrains:24,//24,
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
            maxGrains:24,//24,
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
            maxGrains:24,//72,
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
            maxGrains:24,//72,
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
            maxGrains:24,//32,
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
            maxGrains:24,//32,
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
            maxGrains:24,//24,
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
            maxGrains:24,//24,
            mul:overtone_vol*0.3,
      );
      // maxGrains:24,//[128,256,64,128,64]/2,
      // mul:[0.125,0.625,0.05,0.15,0.05]/2,
      
      

      
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

      sig = Greyhole.ar(sig, echoTime, damp, size, diff, feedback, modDepth, modFreq);
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
        \buf, buffers[i],
        \buf2, buffers[i+ngvoices],
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

    thisEngine.addCommand("read", "is", { arg msg;
      this.readDisk(msg[1] - 1, msg[2]);
    });

    thisEngine.addCommand("seek", "if", { arg msg;
      var voice = msg[1] - 1;
      var lvl, pos;
      
      // seek_tasks[voice].stop;

      // TODO: async get
      lvl = levels[voice].getSynchronous();

      pos = msg[2];
      gvoices[voice].set(\pos, pos);
      // gvoices[voice].set(\t_reset_pos, 1 + 110/120);
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

    // 	thisEngine.addPoll(("level_" ++ (i+1)).asSymbol, {
    // 		var val = levels[i].getSynchronous;
    // 		val
    // 	});
    });

    // seek_tasks = Array.fill(ngvoices, { arg i;
    //   Routine {}
    // });

    // osc_funcs.put("eglut_sig_pos",
      // OSCFunc.new({ |msg,time,addr,recvPort|
        // var pos=msg[3];
        // msg[3].postln;
        // recorders.at(\live_streamer).set(\pos,pos)
      // },"/sc_eglut/grain_sig_pos");
    // );
    // osc_funcs.put("live_audio_dry_wet",
    //   OSCFunc.new({ |msg,time,addr,recvPort|
    //     recorders.at(\live_streamer).set(\dry_wet,msg[1]);
    //   },"/sc_eglut/live_audio_dry_wet");
    // );     
    osc_funcs.put("live_rec_level",
      OSCFunc.new({ |msg,time,addr,recvPort|
        recorders.at(\live_streamer).set(\rec_level,msg[1]);
      },"/sc_eglut/live_rec_level");
    );
    osc_funcs.put("live_pre_level",
      OSCFunc.new({ |msg,time,addr,recvPort|
        recorders.at(\live_streamer).set(\pre_level,msg[1]);
      },"/sc_eglut/live_pre_level");
    );     
    osc_funcs.put("granulate_live",
      OSCFunc.new({ |msg,time,addr,recvPort|
        var voice=msg[1];
        // var live_buffer;
        var sample_duration=msg[2];
        ["live_buffer_length,voice",sample_duration,live_buffer == nil, live_buffer_length,voice].postln;
        // live_buffer.zero;
        live_streamer.free;
        recorders.add(\live_streamer ->
          live_streamer=Synth(\live_streamer, [\buf,live_buffer,\sample_duration, sample_duration, \buf_pos_end, sample_duration/live_buffer_length,  \phase,rec_phase]);
        );
        lua_sender.sendMsg("/lua_osc/on_granulate_live",1);
        this.readBuf(voice,live_buffer,2,sample_duration);
        // live_buffer = Buffer.alloc(s, s.sampleRate * live_buffer_length,completionMessage:{      
        //   ["live streamer add at/phase",live_buffer,rec_phase.index,s.sampleRate].postln;
        //   recorders.add(\live_streamer ->
        //     live_streamer=Synth(\live_streamer, [\buf,live_buffer,\sample_duration, sample_duration, \phase,rec_phase]);
        //   );
        //   lua_sender.sendMsg("/lua_osc/on_granulate_live",1);
        //   this.readBuf(voice,live_buffer,2);
        //   // ["gran_live",voice,live_buffer].postln;
        // });
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
    osc_funcs.keysValuesDo({ arg k,val;
      val.free;
    });
    recorders.keysValuesDo({ arg k,val;
      val.free;
    });

    gvoices.do({ arg voice; voice.free; });
    phases.do({ arg bus; bus.free; });
    levels.do({ arg bus; bus.free; });
    buffers.do({ arg b; b.free; });
    gr_envbufs.do({ arg b; b.free; });
    effect.free;
    effectBus.free;
    rec_phase.free;
  }
}