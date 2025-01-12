# latkes
live and recorded quantized granulation

latkes expands upon @infinitedigits granchild script. 

* four voices
* greyhole echo effect
* quantized size and density
* position jitter

key features:
* four voices/four scenes per voice
* four playheads per voice
* four 30s buffers per voice
* eight gesture recorders per voice/scene
* processes live and recorded audio
* attack decay grain envelopes

* IMPORTANT NOTE ABOUT ECHO (GREYHOLE)....and memory 
the effect uses quite a bit of processing power (e.g.average CPU use will go up by ~10% or more) and may not work well in all situations. using the effect with the size param set high in particular may cause issues.

you can prevent the echo from taking up CPU cycles by turning the `echo on` param to `off`.

# requirements
* norns
* 128 grid (optional)
* midi-controller (optional)

# documentation
* E1: switch between waveform and gesture recorder screens
* E2: select control
* E3: change control value
* K1+E3: record a param (2nd screen only)

see the doc on github for detailed instructions.

## quickstart

### process sounds
* live sounds: since the first voice is set to play live sounds upon script load by default, send live audio to norns to hear the script process audio 
* recorded audio: in one of the `voice[x]` PARAMETERS submenus, select a file using the `sample` file selector, set `mode` to `recorded`, and set `play` to `on`.

### setup gesture recorders

in the PARAMETERS menu:
* open a recorder configuration sub-menu (e.g. `voice1-refl config`)
* select the scene to configure (a-d)
* set up to eight parameters to the "on" position

after setting up params, to record a gesture:

* with E1, go to the gesture recorder screen (use E1 to switch screeens)
* with E2, select one of the params that have been configured
* with K1+E3, record a gesture
  * recording starts when E3 is turned for the first time
  * recording stops when K1 is released

after a gesture has been recorded, loop (L) and play (P) controls appear in the ui below the record (R) control. 

# install
from maiden:

;install https://github.com/jaseknighter/latkes

after installing, restart norns and reload the script again. 

