//Waveformer: create waveforms from buffers
//from: @markeats timber: https://github.com/markwheeler/timber/blob/master/lib/Engine_Timber.sc

Waveformer {
  var lua_sender;
	var waveformDisplayRes = 127;
  var buffers; //one or more arrays of buffers
	var loadQueue;
	var waveformQueue;
  var waveform_queue_size = 1;
	var <waveformRoutine;
	var generatingWaveform = "-1"; // -1 not running
	var abandonCurrentWaveform = false;
  var waveform_scalar = 1.25;

	*new {
    arg buf_arrays;
		^super.new.init(buf_arrays);
	}

	init {
    arg buf_arrays;
    buffers=buf_arrays;
    lua_sender = NetAddr.new("127.0.0.1",10111);   

    //create the slots for the waveformQueue
    waveformQueue = Array.new(waveform_queue_size);
    (["init waveformer",buffers]).postln;
	}

  queueWaveformGeneration {
    arg buf_array_ix,buf_ix,sample_start,sample_length;
    var item;
    
    if(buffers[buf_array_ix][buf_ix].notNil, {
      item = (
        buf_array_ix: 0,
        buf_ix: 0,
        buf_array_ix: buf_array_ix.asInteger,
        buf_ix: buf_ix.asInteger,
        sample_start: sample_start,
        sample_length: sample_length
      );
      waveformQueue.addFirst(item);
      if(generatingWaveform == "-1", {
        this.generateWaveforms(buf_array_ix);
      },{
        this.stopWaveformGeneration(buf_array_ix,buf_ix);
      });
    });
	}

	stopWaveformGeneration {
		arg buf_array_ix, firstId, lastId = firstId;

		// Clear from queue
		firstId.for(lastId, {
			arg i;
			var removeQueueIndex;

			// Remove any existing with same ID
			removeQueueIndex = waveformQueue.detectIndex({
				arg item,i;
        item.buf_ix == i;
			});
      if((removeQueueIndex.notNil).and( waveformQueue.size > 1), {
        waveformQueue.removeAt(removeQueueIndex);
        // (["remove wfqueue",buf_array_ix,removeQueueIndex,waveformQueue]).postln;
        abandonCurrentWaveform = true;
        generatingWaveform = "-1";
			});
		});
	}

	generateWaveforms {
    arg buf_array_ix;
		var samplesPerSlice = 5; //original: 1000; // Changes the fidelity of each 'slice' of the waveform (number of samples it checks peaks of)
		var sendEvery = 3;
		var totalStartSecs = Date.getDate.rawSeconds;

		generatingWaveform = buf_array_ix.asInteger.asString ++ "-" ++ waveformQueue.last.buf_ix.asInteger.asString;

    waveformRoutine = Routine.new({
      if (waveformQueue.isEmpty,{ "wfq is empty".postln });
			while({ waveformQueue.notEmpty }, {
				var buf, buf_size, buf_segment_start, buf_segment_length;
        var startSecs = Date.getDate.rawSeconds;
				var buf_segment;
        var rawData, waveform;
        var numFramesRemaining, numChannels, chunkSize, numSlices, sliceSize, stride, framesInSliceRemaining;
				var frame = 0, slice = 0, offset = 0;
				var item = waveformQueue.pop;
				var sampleId = buf_array_ix.asString ++ "-" ++ item.buf_ix.asString;
				generatingWaveform = sampleId;

				buf = buffers[item.buf_array_ix][item.buf_ix];
        buf_size = buf.numFrames;
        buf_segment_start = item.sample_start * buf_size;
        buf_segment_length = item.sample_length * buf_size;
        if(buf.isNil, {
					("buffer could not be found for waveform generation:" + item).postln;
				}, {          
					numFramesRemaining = buf_segment_length;
					numChannels = buf.numChannels;
					chunkSize = (1048576 / numChannels).floor * numChannels;
					numSlices = waveformDisplayRes.min(buf_segment_length);
					sliceSize = buf_segment_length / waveformDisplayRes;
					framesInSliceRemaining = sliceSize;
					stride = (sliceSize / samplesPerSlice).max(1);

					waveform = Int8Array.new((numSlices * numChannels) + (numSlices % 4));
					
          // Process in chunks
					while({
            (numFramesRemaining > 0).and
              (abandonCurrentWaveform == false)
						// (numFramesRemaining > 0).and({
						// 	// rawData = FloatArray.newClear(min(numFramesRemaining * numChannels, chunkSize));
						//  // rawData.size > 0; 	
            // file.readData(rawData);
						// }).and(abandonCurrentWaveform == false)
					}, {
            var count = min((numFramesRemaining * numChannels), chunkSize);
            
            buf.loadToFloatArray(index: buf_segment_start, count: count, action:
            {
              arg rawData;
              var min = 0, max = 0;
              while({ (frame.round * numChannels + numChannels - 1 < rawData.size).and
                (abandonCurrentWaveform == false).and
                (rawData.size > 0) 
              }, {
                for(0, numChannels.min(2) - 1, {
                  arg c;
                  var sample = rawData[frame.round.asInteger * numChannels + c];
                  min = sample.min(min)*waveform_scalar;
                  max = sample.max(max)*waveform_scalar;
                });

                frame = frame + stride;
                framesInSliceRemaining = framesInSliceRemaining - stride;

                // Slice done
                if(framesInSliceRemaining < 1, {

                  framesInSliceRemaining = framesInSliceRemaining + sliceSize;

                  // 0-126, 63 is center (zero)
                  min = min.linlin(-1, 0, 0, 63).round.asInteger;
                  max = max.linlin(0, 1, 63, 126).round.asInteger;
                  waveform = waveform.add(min);
                  waveform = waveform.add(max);
                  min = 0;
                  max = 0;
                  
                  if(((slice + 1) % sendEvery == 0).and(abandonCurrentWaveform == false), {
                    this.sendWaveform(sampleId, offset, waveform);
                    offset = offset + sendEvery;
                    waveform = Int8Array.new(((numSlices - offset) * 2) + (numSlices % 4));
                  });
                  slice = slice + 1;
                });

                // Let other sclang work happen if it's a long buffer
                if(buf_segment_length > 1000000, {
                  0.004.yield;
                });
              });
            });
            frame = frame - (rawData.size / numChannels);
            numFramesRemaining = numFramesRemaining - (rawData.size / numChannels);
              
          
					});

					// file.close;

					if(abandonCurrentWaveform, {
						abandonCurrentWaveform = false;
						// ("Waveform" + sampleId + "abandoned after" + (Date.getDate.rawSeconds - startSecs).round(0.001) + "s" + "qs:" + waveformQueue.size).postln;
					}, {
						if(waveform.size > 0, {
							this.sendWaveform(sampleId, offset, waveform);
							(["sendWaveform",sampleId, offset, waveform]).postln;
						});
					});
				});

				// Let other sclang work happen
				0.002.yield;
				// 0.1.yield;
			});

			("Finished generating waveforms in" + (Date.getDate.rawSeconds - totalStartSecs).round(0.001) + "s").postln;
			generatingWaveform = "-1";

		}).play;
	}

  sendWaveform {
		arg sampleId, offset, waveform;
		var padding = 0;
    var mode = sampleId.split($-)[0].asInteger;
    var voice = sampleId.split($-)[1].asInteger;
		// Pad to work around https://github.com/supercollider/supercollider/issues/2125
		while({ waveform.size % 4 > 0 }, {
			waveform = waveform.add(0);
			padding = padding + 1;
		});

    lua_sender.sendMsg("/lua_eglut/engine_waveform",voice, mode, offset, padding, waveform);
	}

	free {
    loadQueue.do({ arg b; b.free; });
    waveformQueue.do({ arg b; b.free; });
	}
}