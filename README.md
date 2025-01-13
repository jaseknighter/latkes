# latkes
live and recorded quantized granulation

latkes expands upon @infinitedigits granchild script and includes these key features:

* four voices/four scenes per voice
* four playheads per voice
* four 30s buffers per voice
* eight gesture recorders per voice/scene
* attack decay grain envelopes

* IMPORTANT NOTE ABOUT ECHO (GREYHOLE)....and memory 
the greyhole effect uses quite a bit of processing power (e.g.average CPU use will go up by ~10% or more) and may not work well in all situations. using the effect with the size param set high in particular may cause issues.

you can prevent the echo from taking up CPU cycles by turning the `echo on` param to `off`.

# requirements
* norns
* 128 grid (optional)
* midi-controller (optional)

# documentation
* E1: switch between waveform and gesture recorder screens
* E2: select control
* K2/K3 (screen 1) or E3 (screen 2): change control value
* K1+E3: record param (2nd screen only)

[laktes user guide](doc/latkes_user_guide_v_0.1.0.pdf)

## quickstart

### process live sounds
the first voice is set to play live sounds upon script load by default.

### process live sounds
select a file using the `sample` file selector in one of the `voice[x]` PARAMETERS submenus, set `mode` to `recorded`, and set `play` to `on`.

### screen 1 controls (waveform)
params controllable from the waveform screen:
* modes: live (*lv*) and recorded (*rec*)
* voice (*1-4*)
* scene (*a-d*)
* sample start and sample length (graphical controls at the bottom of the screen)
* play (P)
* live audio flip rec and pre settings (F)

### screen 2 controls gesture recorders (aka *reflectors*)

reflectors need to be setup in the PARAMETERS menu before gesture recorders will appear on the 2nd screen:
* open a recorder configuration sub-menu (e.g. `voice1-refl config`)
* select the scene to configure (`a`-`d`)
* set up to eight parameters to the "on" position

after setting up params, to record a gesture:

* with E1, go to the gesture recorder screen
* with E2, select one of the params that have been configured
* with K1+E3, record a gesture
  * recording starts when E3 is turned for the first time
  * recording stops when K1 is released

after a gesture has been recorded, loop (L) and play (P) controls appear in the ui below the record (R) control. 

# install
from maiden:

;install https://github.com/jaseknighter/latkes

after installing, restart norns and reload the script again. 