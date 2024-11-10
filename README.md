# futurespast
live and recorded quantized granulation

futurespast represents a modest set of enhancements to @infinitedigits granchild script. grid controls and lfos have been removed but just about everything else remains:

* four voices
* greyhole echo effect
* quantized size and density
* position jitter

key new features:
* waveform and playhead position visualizer 
* process live and recorded audio
* four scenes per voice
* eight configurable parameter gesture recorders per voice
* attack decay grain envelopes with six curve types: step,linear,sine ,welches?,squared, cubed
* four individually spreadable play heads per voice
* per voice effect send (to the greyhole echo effect)
* position and density jitter
* per voice low pass filter
* 16n support build-in 

# requirements
* norns
* midi-controller (optional)

# documentation
* E1: switch between pages
* E2: select control
* E3: change control
* K1+E3: record a param (2nd page only)

the script has two pages: waveform view and a gesture recorder view

## waveform view
five parameters can be controlled from this view:

* mode: off (o), live (lv), recorded (rc)
* voice: select which voice (1-4) to view
* scene: select which scene (a-d) to view
* sample start: change the granulation player's starting loop point within the live or recorded buffer 
* sample length: change the length of the granulation player's loop within the live or recorded buffer

while most voice parameters can be set per voice and per scene, a few are only configurable per voice: 

* sample start: start point of the buffer area to sample
* sample length: length of the buffer area to sample
* sample mode
* sample: path to file 
* live rec level: amount of live audio to sample/retain
* live pre level: amount of pre-recorded live audio to sample/retain
* mix live+rec: include live buffer when sampling recorded audio

## gesture recorder view

### setup
each scene of each voice has can have its own gesture recorder settings. before using the gesture recorder, params need to be configured in the PARAMs menu. 

to setup the gesture recorders for a voice/scene:

* open a recorder configuration sub-menu (e.g. `voice1-rec config`)
* select the scene to configure (a-d)
* set up to eight parameters to the "on" position

then, the selected parameters can be controlled from the 2nd page of the script's ui or from the PARAMS menu.

after setting up params, to record a gesture:

* go to the gesture recorder page
* select one of the eight param's 
* with K1+E3, record a gesture
  * recording starts when E3 is turned for the first time
  * recording stops when K1 is released

after a gesture has been recorded, loop (L) and play (P) controls appear in the ui below the record (R) control. 

# install
from maiden:

;install https://github.com/jaseknighter/futurespast

after installing, restart norns and reload the script again. 

