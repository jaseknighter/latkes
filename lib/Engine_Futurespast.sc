// Engine_Futurespast

// thanks to infinite digits for using envelopes to loop buffers writeup 
// https://infinitedigits.co/tinker/sampler/


// Inherit methods from CroneEngine
Engine_Futurespast : CroneEngine {
  
  // var s;
  var osc_funcs;
  var eglut;
  var s;

	*new { arg context,doneCallback;
		^super.new(context,doneCallback);
	}


  alloc {
    s=context.server;

    // ["memsize",s.options.memSize].postln;
    // s.options.memSize=2**15; //65536
    // s.options.memSize=1024*256; 
    // s.options.memSize=1024*128; 
    ["increasing memsize and numbuffers",s.options.memSize,s.options.numBuffers].postln;
    eglut=EGlut.new(s,context,this);

    "eglut inited".postln;
  }

  free {
    "free Futurespast".postln;  
    ">>>>>>>>>>>>>>".postln;
    s.queryAllNodes;

    eglut.free;
    s.options.memSize=8192; 
    // s.options.numBuffers=1024; 
    
  }
}
