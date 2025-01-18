// Engine_Latkes

// thanks to infinite digits for using envelopes to loop buffers writeup 
// https://infinitedigits.co/tinker/sampler/


// Inherit methods from CroneEngine
Engine_Latkes : CroneEngine {
  
  // var s;
  var osc_funcs;
  var eglut;
  var s;

	*new { arg context,doneCallback;
		^super.new(context,doneCallback);
	}


  alloc {
    s=context.server;

    s.options.memSize_(65536 * 4);
    ["increasing memsize",s.options.memSize].postln;
    eglut=EGlut.new(s,context,this);

    "eglut inited".postln;
  }

  free {
    "free latkes!!!!".postln;  
    eglut.free;
    eglut = nil;
    s.options.memSize=8192; 
  }
}
