// Engine_Futurespast

// thanks to infinite digits for using envelopes to loop buffers writeup 
// https://infinitedigits.co/tinker/sampler/


// Inherit methods from CroneEngine
Engine_Futurespast : CroneEngine {
  
  // var s;
  var osc_funcs;
  var eglut;

	*new { arg context,doneCallback;
		^super.new(context,doneCallback);
	}


  alloc {
    var s=context.server;

    // ["memsize",s.options.memSize].postln;
    s.options.memSize=8192*4; 
    ["memsize post",s.options.memSize].postln;
    eglut=EGlut.new(s,context,this);

    "eglut inited".postln;
  }

  free {
    "free Futurespast".postln;  
    eglut.free;

  }
}
