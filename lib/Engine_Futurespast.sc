// Engine_Futurespast

// thanks to infinite digits for using envelopes to loop buffers writeup 
// https://infinitedigits.co/tinker/sampler/


// Inherit methods from CroneEngine
Engine_Futurespast : CroneEngine {
  
  // var s;
  var osc_funcs;
  var recorders;
  var players;
  var writebuf;
  var eglut;

	*new { arg context,doneCallback;
		^super.new(context,doneCallback);
	}


  alloc {
    var s=context.server;
    var livewritebufdone;
    var lua_sender,sc_sender;
    var buf_recording=0;
    var buf_writing=0;
    var server_sample_rate=48000;
    
    var session_name;
    var audio_path;
    var data_path;
    var session_data_path;
    var next_file_num;

    ["memsize",s.options.memSize].postln;
    // s.options.memSize=2.pow(14); 
    s.options.memSize=8192*4; 
    ["memsize post",s.options.memSize].postln;
    
    // s.sync;

    lua_sender=NetAddr.new("127.0.0.1",10111);   
    sc_sender=NetAddr.new("127.0.0.1",57120);   
    // lua_sender.sendMsg("/lua_osc/sc_inited");

    osc_funcs=Dictionary.new();
    recorders=Dictionary.new();
    players=Dictionary.new();
    "dictionaries created".postln;
    s.sync;

    

    ////
    "initial buffers and arrays allocated".postln;
    s.sync;
    ////


    livewritebufdone={
      arg path,type;
      // arg sample, path;
      lua_sender.sendMsg("/lua_osc/livebuffer_written",path);
      buf_writing=0;
    };

    writebuf={
      arg buf,path,header_format,sample_format,numFrames,msg,voice;
      // if ((buf_writing==0),{
      // ["starting writebuf",buf.bufnum,buf_writing,buf_recording].postln;
      
      if ((buf.sampleRate!=nil).and(buf_recording==0).and(buf_writing==0),{
        Routine({
          
          buf.normalize();
          s.sync;
          buf_writing=1;
          if (msg=="live stream",{
            buf.write(path,header_format,sample_format,numFrames,completionMessage:{livewritebufdone.(path)});
          });
        }).play;
      },{
        "buf writing already".postln;
      });
    };

    SynthDef("live_recorder",{ 
      arg buf,rate=1,dur=10.0;
      // var dur=s.sampleRate * dur;
      var in=SoundIn.ar(0);
      RecordBuf.ar(in,buf,loop:0,doneAction:2);
      0.0 //quiet
    }).add;


    eglut=EGlut.new(s,context,this);
    "eglut inited".postln;
    
    // osc_funcs.put("record_live",
    //   OSCFunc.new({ |msg,time,addr,recvPort|
    //     // var liveBuf;
    //     var dur=msg[1];
    //     var file_num=next_file_num.(PathName.new(session_audio_path ++ "slice_buffers/").files.size);
    //     var path=session_audio_path ++ "slice_buffers/record_live" ++ file_num ++ ".wav";
    //     var header_format="WAV";
    //     var sample_format="int24";
    //     players.keysValuesDo({ arg k,val;
    //       val.set(\gate,0);
    //     });

    //     sliceBuf=Buffer.alloc(s,s.sampleRate * dur,1);

    //     recorders.add(\live_recorder ->
    //       Synth(\live_recorder,[\dur,dur,\buf,sliceBuf]);
    //     );
        
    //     Routine{
    //       dur.wait;
    //       ["recording completed",sliceBuf].postln;
    //       writebuf.(sliceBuf,path,header_format,sample_format,-1,"compose live");
    //     }.play;

    //   },"/sc_osc/record_live");
    // );

    osc_funcs.put("init_completed",
      OSCFunc.new({ |msg,time,addr,recvPort|
        audio_path              = msg[1];
        data_path               = msg[2];
        ["paths set: ",audio_path,data_path].postln;

      },"/sc_osc/init_completed");
    );   

    "engine all loaded".postln;   
  }

  free {
    "free Futurespast".postln;  
    osc_funcs.keysValuesDo({ arg k,val;
      val.free;
    });
    recorders.keysValuesDo({ arg k,val;
      val.free;
    });
    players.keysValuesDo({ arg k,val;
      val.free;
    });
    eglut.free();
  }
}
