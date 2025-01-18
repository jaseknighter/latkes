-- latkes
--
-- llllllll.co/t/latkes
--
-- v0.1.0_250118 (beta)
--
--    ▼ instructions below ▼
--
-- screen 1 (waveform)
-- * E1: switch between screens
-- * E2: select control
-- * K2/K3: change control value
--
-- screen 2 (gesture recorder)
-- * E1: switch between screens
-- * E2: select control
-- * E3: change control value
-- * K1+E3: record param 


----------------------------
-- documentation:
-- be careful when setting different filter cutoff and rq between scenes or popping can occur when switching, esp. if rq is set low
-- 
-- notes about overriding paramset (og_pset_write, etc.)
-- 
-- bugs to fix:
-- fix record/play head sync: pops when playhead wraps around
-- fix record/play head sync: the record head position needs to be divided by 2 when setting the rec/playhead (related to sending buffer position data from two instances to a single bus channel)
-- fix reported bugs
-- figure out why we need to flip rec_scene and active voice to get params to show...something to do with show_hide loop at the start?

-- features, performance improvements:
-- add screen/grid dirty code
-- add jitter for grain size
-- code cleanup
--
-- credits:
-- eigen, fourhoarder, 24franks, infinitedigits, alanza, dani_derks
-- infinitedigits for code to remove clicks in looping buffers:
--         https://infinitedigits.co/tinker/sampler/
--         https://github.com/schollz/workshops/tree/main/2023-03-ceti-supercollider

----------------------------

engine.name='Latkes'

reflection = require 'reflection'

eglut=include("lib/eglut")
waveform=include("lib/waveform")
screens=include("lib/screens")
midi_helper=include("lib/midi_helper")
lk_grid=include("lib/grid")
grid_overrides=include("lib/grid_overrides")

max_buffer_length = 15

local inited=false

local composition_top = 20
local composition_bottom = 64-10
local composition_left = 23--16
local composition_right = 127-16

local num_voices = 4
local num_scenes = 4

MAX_REFLECTORS_PER_SCENE=8

active_positions = {}

voice1scene1_cc_channel = 1
voice1scene2_cc_channel = 2
voice1scene3_cc_channel = 3
voice1scene4_cc_channel = 4
voice2scene1_cc_channel = 5
voice2scene2_cc_channel = 6
voice2scene3_cc_channel = 7
voice2scene4_cc_channel = 8
voice3scene1_cc_channel = 9
voice3scene2_cc_channel = 10
voice3scene3_cc_channel = 11
voice3scene4_cc_channel = 12 
voice4scene1_cc_channel = 13 
voice4scene2_cc_channel = 14
voice4scene3_cc_channel = 15
voice4scene4_cc_channel = 16

waveforms = {}
buffer_fill_amounts = {}
waveform_names = {}
waveform_sig_positions = {}
composition_slice_positions = {}
redraw_waveform = false

local audio_path            =   _path.audio..norns.state.name.."/"
local data_path             =   _path.data..norns.state.name.."/"
local reflection_data_path  =   data_path.."reflectors/"

buffer_loop_points = {}
for i=1,num_voices do
  buffer_loop_points[i] = {}
  buffer_loop_points[i].last_loop_start = 0
  buffer_loop_points[i].last_loop_end = 10
end

--------------------------
-- waveform rendering
--------------------------

local function store_waveform(voice, sample_mode, offset, padding, waveform_blob)
  local waveform_ix = sample_mode < 2 and (voice * 2 - 1) or (voice * 2)
  local waveform_name = waveform_names[waveform_ix]
  waveforms[waveform_name]:set_samples(offset, padding, waveform_blob)
  --clear area of waveform samples if amount of buffer used is increasing
  local sample_start = params:get(voice .. "sample_start")
  local sample_length = params:get(voice .. "sample_length")
  local pct_buffer_fill = (sample_start + sample_length)/max_buffer_length
  if pct_buffer_fill > buffer_fill_amounts[waveform_name] then
    buffer_fill_amounts[waveform_name] = pct_buffer_fill
  end
  redraw_waveform = true
end

--------------------------
-- osc functions
--------------------------

function on_eglut_file_loaded(voice)
  -- print("on eglut file loaded")
end

function osc.event(path,args,from)
  if inited == false then return end  
  if path == "/lua_eglut/engine_waveform" then
    --args: voice, sample_mode, offset, padding, waveform
    store_waveform(args[1]+1, args[2]+1, args[3], args[4], args[5]);
  elseif path == "/lua_eglut/grain_sig_pos" then
    local voice=math.floor(args[1]+1)
    table.remove(args,1)
    local active_voice = params:get("active_voice")
    if voice == active_voice then
      active_positions = args
      waveform_sig_positions[voice.."granulated"]=args
    else
      waveform_sig_positions[voice.."granulated"] = nil
    end
    screen_dirty = true
  elseif path == "/lua_eglut/on_eglut_file_loaded" then
    local voice = args[1]+1
    local duration = args[2]
    on_eglut_file_loaded(voice, duration)
  end
end

function setup_waveforms()
  for i=1,#waveform_names do
    waveforms[waveform_names[i]] = waveform:new({
      name=waveform_names[i],
      composition_top=composition_top,
      composition_bottom=composition_bottom,
      composition_left=composition_left,
      composition_right=composition_right
    })
  end
end

function setup_buffer_fill_amounts()
  for i=1,#waveform_names do
    -- setup variables to track when a waveform buffer needs to be cleared
    -- (i.e., when the amount of audio recorded in the buffer changes)
    local ix = math.ceil(i/2)
    local sample_start = params:get(ix .. "sample_start")
    local sample_length = params:get(ix .. "sample_length")
    local pct_buffer_fill = (sample_start + sample_length)/max_buffer_length
    buffer_fill_amounts[waveform_names[i]] = pct_buffer_fill
  end
end

function setup_params()
  params:add_separator("screens/voices/scenes")
  params:add_number("active_screen","active screen",1,2,1)
  params:set_action("active_screen", function(x) 
    local voice, scene, channel
    if params:get("active_screen") == 1 then 
      voice = screens.p1ui.selected_voice
      scene = screens.p1ui.selected_scene
    elseif params:get("active_screen") == 2 then 
      voice = screens.p2ui.selected_voice
      scene = screens.p2ui.selected_scene
    end
    channel = params:get("voice"..voice.."scene"..scene.."_cc_channel")
    midi_helper.update_midi_devices(channel,true)
  end)
  params:add_number("active_voice","active voice",1,num_voices,1)
  params:set_action("active_voice", function(x) 
    screen.clear()
    screens.p1ui.selected_voice = x
    screens.p2ui.selected_voice = x
    local voice, scene, channel
    if params:get("active_screen") == 1 then 
      voice = screens.p1ui.selected_voice
      scene = screens.p1ui.scenes[voice]
    elseif params:get("active_screen") == 2 then 
      voice = screens.p2ui.selected_voice
      scene = screens.p2ui.scenes[voice]
    end
    osc.send( { "localhost", 57120 }, "/sc_eglut/set_active_voice",{x-1})
    params:set("active_scene",scene)
    -- eglut:update_scene(voice,scene)
    channel = params:get("voice"..voice.."scene"..scene.."_cc_channel")
    midi_helper.update_midi_devices(channel,true)
  end)
  params:add_number("active_scene","active scene",1,num_scenes,1)
  params:set_action("active_scene", function(x) 
    screen.clear()
    screens.p1ui.selected_scene = x
    screens.p2ui.selected_scene = x
    screens.p1ui.scenes[screens.p1ui.selected_voice] = x
    screens.p2ui.scenes[screens.p2ui.selected_voice] = x
    local voice, scene, channel
    if params:get("active_screen") == 1 then 
      voice = screens.p1ui.selected_voice
      scene = screens.p1ui.selected_scene
    elseif params:get("active_screen") == 2 then 
      voice = screens.p2ui.selected_voice
      scene = screens.p2ui.selected_scene
    end
    params:set(voice.."scene",scene)
    channel = params:get("voice"..voice.."scene"..scene.."_cc_channel")
    midi_helper.update_midi_devices(channel,true)
  end)
end


---------------------------------------------------
-- reflection code
-- from @alanza (https://llllllll.co/t/low-pixel-piano/65705/2)
---------------------------------------------------
local reflector_scene_labels={'a','b','c','d'}
eglut_params={}
reflector_process_data={}

--[[
-- key reflection functions
    reflector:stop()
    reflector:start()
    reflector:set_rec() - 0 stop,1 start, 2 queue
    reflector:set_loop() - 0 no loop, 1 loop
    reflector:watch({event})
    reflector.end_of_rec_callback=function() --do something end
    reflector.step_callback=function() --do something end
    reflector.start_callback=function() --do something end
    reflector.stop_callback=function() --do something end
    reflector.endpoint
]]

-- utility to clone function (from @eigen)
function clone_function(fn)
  local dumped=string.dump(fn)
  local cloned=load(dumped)
  local i=1
  while true do
    local name=debug.getupvalue(fn,i)
    if not name then
      break
    end
    debug.upvaluejoin(cloned,i,fn,i)
    i=i+1
  end
  return cloned
end


function sort_num_table(num_table)
  local keys = {}
  for key, _ in pairs(num_table) do
    table.insert(keys, key)    
  end
  table.sort(keys, function(keyLhs, keyRhs) return num_table[keyLhs] < num_table[keyRhs] end)
  return keys
end


function get_num_reflectors(voice,scene)
  local num_reflectors=0
  for k,v in pairs(reflectors[voice][scene]) do
    num_reflectors=num_reflectors+1
  end
  return num_reflectors
end

function init_reflector(p_id,voice,scene)
  reflectors[voice][scene][p_id]=reflection.new()
  reflectors[voice][scene][p_id].loop=0
  reflectors[voice][scene][p_id].process=function(event)
    -- event structure
    -- {
    --   voice=voice,
    --   scene=scene,
    --   param_id,p_id,
    --   value,params:get(p_id)
    -- }
    params:set(event.param_id,event.value)

    local reflector
    for i=1,#reflectors_selected_params[voice][scene] do
      local id=reflectors_selected_params[voice][scene][i].id
      if id==event.param_id then reflector=i end
    end
    reflector_process_data[voice][scene][reflector]= {
      param_id=event.param_id,
      param_name=event.param_name,
      range=event.range,
      value=event.value,
      reflector=reflector
    }
  end

  reflectors[voice][scene][p_id].start_callback=function() 
    -- print("reflector start callback",voice,scene,p_id)
  end

  reflectors[voice][scene][p_id].end_callback=function() 
    local recorder_ix=reflectors[voice][scene][p_id].recorder_ix
    local reflector_loop=params:get(voice.."-"..recorder_ix.."loop"..scene)
    local recording_completed = reflectors[voice][scene][p_id].recording
    local reflector_play_id =voice.."-"..recorder_ix.."play"..scene
    local reflector_play = params:get(reflector_play_id)
    if reflector_loop==1 and recording_completed == false then
      params:set(reflector_play_id,1)
    end
    if recording_completed == true then 
      reflectors[voice][scene][p_id].recording = false
      if reflector_play == 2 then
        clock.run(function() 
          local play = params:lookup_param(reflector_play_id)
          -- print("restart play")
          play:bang()
        end)
      end
    end
  end

  reflectors[voice][scene][p_id].stop_callback=function() 
    print("reflector stop callback",voice,scene,p_id)
  end

  reflectors[voice][scene][p_id].end_of_rec_callback=function() 
    reflectors[voice][scene][p_id].endpoint_premult = nil
    reflectors[voice][scene][p_id].event_premult = nil
    reflectors[voice][scene][p_id].recording = true
  end
end

function enrich_param_reflector_actions(p_id,voice,scene)
  local p=params:lookup_param(p_id)
  p.og_action = clone_function(p.action)
  p.action = function(value)
    p.og_action(value)
    -- print(p.name,value)
    local p=params:lookup_param(p_id)
    reflectors[voice][scene][p_id]:watch({
      voice=voice,
      scene=scene,
      reflector=reflector,
      param_id=p_id,
      param_name,p.name,
      range=params:get_range(p_id),
      value=params:get(p_id)
    })
  end
  init_reflector(p_id,voice,scene)
end

function unenrich_param_reflector_actions(p_id,voice,scene)
  local p=params:lookup_param(p_id)
  if p.og_action and reflectors[voice][scene][p_id] then
    p.action = p.og_action     
    reflectors[voice][scene][p_id]=nil 
  end
end

function get_reflector_table(voice,scene,reflector)
  local reflector_param=reflectors_selected_params[voice][scene][reflector]
  -- print("get_reflector_table",reflector_param,voice,scene,reflector)
  if reflector_param then
    local reflector_param_id=reflector_param.id
    return reflectors[voice][scene][reflector_param_id]
  else
    return nil
  end
end

--sort the params selected to record by their indices 
function sort_reflectors(voice,scene)
  local selected_params={}
  for k,v in pairs(reflectors[voice][scene]) do 
    local param_id=k
    local param=params:lookup_param(param_id)
    local param_ix=params.lookup[param_id]
    selected_params[param.id]=param_ix
  end

  local sorted_keys=sort_num_table(selected_params)
  reflectors_selected_params[voice][scene]={}
  local reflector_ix=1
  for i, param_id in ipairs(sorted_keys) do
    local param=params:lookup_param(param_id)
    local param_name=param.name
    reflectors_selected_params[voice][scene][i]={id=param_id,name=param_name}

    --add reference to the recorder param index in the reflector table
    local reflector_tab=reflectors[voice][scene][param_id]
    reflector_tab.recorder_ix=reflector_ix

    --update the recorder separator names
    local separator_id=voice.."-"..reflector_ix.."separator"..scene
    local separator_param=params:lookup_param(separator_id)
    separator_param.name=param_name
    reflector_ix=reflector_ix+1
  end
end

function showhide_reflectors(selected_scene,selected_voice)
  local voice_start=selected_voice and selected_voice or 1
  local range=selected_voice and selected_voice or eglut.num_voices
  for voice=voice_start,range do
    for scene=1,#reflector_scene_labels do
      local num_reflectors = get_num_reflectors(voice,scene)
      if scene==selected_scene and num_reflectors==0 then
        params:show(voice.."noreflectors_spacer"..scene)
        params:show(voice.."noreflectors"..scene)
      else
        params:hide(voice.."noreflectors_spacer"..scene)
        params:hide(voice.."noreflectors"..scene)
      end

      for reflector=1,MAX_REFLECTORS_PER_SCENE do
        local reflector_sep_id=voice.."-"..reflector.."separator"..scene
        local reflector_record_id=voice.."-"..reflector.."record"..scene          
        local reflector_play_id=voice.."-"..reflector.."play"..scene          
        local reflector_loop_id=voice.."-"..reflector.."loop"..scene          
        if scene==selected_scene and reflector <= num_reflectors then
          params:show(reflector_sep_id)
          params:show(reflector_record_id)
          local reflector_tab = get_reflector_table(voice,scene,reflector)
          local reflector_data = reflector_tab and reflector_tab.count or 0
          if reflector_data and reflector_data>0 then
            params:show(reflector_play_id)
            params:show(reflector_loop_id)
          else
            params:hide(reflector_play_id)
            params:hide(reflector_loop_id)
          end
        else
          params:hide(reflector_sep_id)
          params:hide(reflector_record_id)
          params:hide(reflector_play_id)
          params:hide(reflector_loop_id)
        end
      end
      sort_reflectors(voice,scene)
    end
  end
  _menu.rebuild_params()
end

function showhide_reflector_configs(selected_scene,voice)
  if rec_voice==nil then --show/hide all reflector params
    for voice=1,eglut.num_voices do
      for p_ix=1,#eglut_params do
        local param_id=eglut_params[p_ix].id
        for scene=1,#reflector_scene_labels do
          local rec_option_id=voice.."refl_config"..param_id..scene
          -- print("rec_option_id",reflector,voice,scene,rec_option_id)
          if scene==selected_scene then
            params:show(rec_option_id)
          else
            params:hide(rec_option_id)
          end
        end
      end
    end
  else --show/hide just the reflector params in the active reflector
    for p_ix=1,#eglut_params do
      local param_id=eglut_params[p_ix].id
      for scene=1,#reflector_scene_labels do
        local rec_option_id=voice.."refl_config"..param_id..scene
        if scene==selected_scene then
          params:show(rec_option_id)
        else
          params:hide(rec_option_id)
        end
      end
    end
  end
  _menu.rebuild_params()
end

function init_reflectors()
  print("init_reflectors")
  reflectors = {}
  reflectors_selected_params = {}

  for voice=1,eglut.num_voices do
    reflectors_selected_params[voice]={}
    reflector_process_data[voice]={}
    reflectors_selected_params[voice].prior_scene=1
    for scene=1,eglut.num_scenes do
      reflector_process_data[voice][scene]={}
      for reflector=1,MAX_REFLECTORS_PER_SCENE do
        reflector_process_data[voice][scene][reflector]={}
      end
    end

  end

  reflectors_param_list={
    "play","volume","send","rec_play_sync","speed","seek",
    "size",
    "density","density_beat_divisor","density_phase_sync",
    "pitch","sig_spread",
    "sig_spread_offset2","sig_spread_offset3","sig_spread_offset4",
    "jitter",
    "fade","attack_time","decay_time","env_shape",
    "cutoff","q","pan","spread_pan",
    "subharmonics","overtones","overtone1","overtone2"
  }
  
  for i=1,#reflectors_param_list do
    local p_id=reflectors_param_list[i]
    local p=params:lookup_param("1"..p_id.."1")
    p=p or params:lookup_param("1"..p_id)
    local p_name=p.name
    table.insert(eglut_params,{id=p_id,name=p_name}) 
  end

  params:add_separator("reflectors")
  params:add_option("reflector_autoloop","auto loop",{"off","on"},2)
  
  -- setup reflectors
  for voice=1,eglut.num_voices do
    params:add_group("gran_voice"..voice.."-refl","voice"..voice.."-refl",1+((#reflector_scene_labels)*(MAX_REFLECTORS_PER_SCENE*4)))
    params:add_option("rec_scene"..voice,"scene",reflector_scene_labels,1)
    params:set_action("rec_scene"..voice,function(scene) 
      local prior_scene=reflectors_selected_params[voice].prior_scene
      if prior_scene then
        for k,v in pairs(reflectors_selected_params[voice][prior_scene]) do
          local id=v.id
          reflectors[voice][prior_scene][id]:stop()
        end
      end
      showhide_reflectors(scene,voice)
      for reflector=1,#reflectors_selected_params[voice][scene] do
        local param=params:lookup_param(voice.."-"..reflector.."play"..scene)
        param:bang()
      end
      reflectors_selected_params[voice].prior_scene=scene
    end)
    
    for scene=1,eglut.num_scenes do
      params:add_text(voice.."noreflectors_spacer"..scene," ")
      params:add_text(voice.."noreflectors"..scene,"   no reflectors configured")
      
      for reflector=1,MAX_REFLECTORS_PER_SCENE do
        local sep_id=voice.."-"..reflector.."separator"..scene
        params:add_separator(sep_id,"reflector"..reflector)
        local rec_id=voice.."-"..reflector.."record"..scene
        params:add_option(rec_id,"record",{"off","on"})
        params:set_save(rec_id, false)
        params:set_action(rec_id,function(value) 
          local reflector_tab = get_reflector_table(voice,scene,reflector)
          if reflector_tab == nil then return
          elseif value==1 then
            print("stop reflector recording",rec_id,voice,scene,reflector)
            reflector_tab:set_rec(0)
          elseif value==2 then
            print("start reflector recording",rec_id)
            reflector_tab:clear()
            if params:get("reflector_autoloop") == 2 then 
              params:set(voice.."-"..reflector.."loop"..scene,2) 
            end
            params:set(voice.."-"..reflector.."play"..scene,2) 
            reflector_tab:set_rec(1)
          end
          lk_grid.set_reflector_selector(reflector)            
          showhide_reflectors(scene,voice)
        end)
        local loop_id=voice.."-"..reflector.."loop"..scene
        params:add_option(loop_id,"loop",{"off","on"})
        params:set_save(loop_id, false)
        params:set_action(loop_id,function(value) 
          local reflector_tab = get_reflector_table(voice,scene,reflector)
          -- print("loop reflector",value==1 and "off" or "on")
          if reflector_tab then
            if value==1 then
              reflector_tab:set_loop(0)
            else
              reflector_tab:set_loop(1)
              local reflector_play=voice.."-"..reflector.."play"..scene
              params:set(reflector_play,2)
            end
            lk_grid.set_reflector_selector(reflector)            
          end
        end)

        local play_id=voice.."-"..reflector.."play"..scene
        params:add_option(play_id,"play",{"off","on"})
        params:set_save(play_id, false)
        params:set_action(play_id,function(value) 
          local reflector_tab = get_reflector_table(voice,scene,reflector)
          if reflector_tab then
            if value==1 then
              reflector_tab:stop()
            else
              reflector_tab:start()
            end
            lk_grid.set_reflector_selector(reflector)
          end
        end)
      end
    end
  end

  -- setup config sub menus
  for voice=1,eglut.num_voices do
    reflectors[voice]={}
    params:add_group("gran_voice"..voice.."-refl config","voice"..voice.."-refl conf",1+(eglut.num_voices*#eglut_params))
    params:add_option("refl_config_scene"..voice,"scene",reflector_scene_labels,1)
    params:set_action("refl_config_scene"..voice,function(scene) 
      showhide_reflector_configs(scene,voice.."refl_config")
    end)

    local default_param_ids = {"speed","size","density","sig_spread","jitter","attack_time","subharmonics","overtones"}
    for scene=1,eglut.num_scenes do
      reflectors[voice][scene]={}
      for p_ix=1,#eglut_params do
        local param_id=eglut_params[p_ix].id
        local param_name=eglut_params[p_ix].name
        local rec_option_id=voice.."refl_config"..param_id..scene
        local default_val
        for def_pid=1,8 do
          default_val = default_param_ids[def_pid] == param_id and 2 or 1
          if default_val > 1 then 
            print("defref found "..default_val, default_param_ids[def_pid],param_id)
            break 
          end
        end 
        
        
        params:add_option(rec_option_id,param_name,{"off","on"}, default_val)
        params:set_action(rec_option_id,function(state) 
          local param=voice..eglut_params[p_ix].id..scene
          if state==1 then
            unenrich_param_reflector_actions(param,voice,scene)
          else
            local num_reflectors=get_num_reflectors(voice,scene)
            if num_reflectors<MAX_REFLECTORS_PER_SCENE then
              enrich_param_reflector_actions(param,voice,scene)
            else
              print("too many reflectors. max is ", MAX_REFLECTORS_PER_SCENE)
              params:set(rec_option_id,1)
            end
          end
          if params:get("rec_scene"..voice) == scene then 
            showhide_reflectors(scene,voice)
          end
        end)
      end
    end
  
  end

  params:add_group("copy reflectors",5)
  params:add_number("copy_reflectors_voice_from","from voice",1,num_voices,1)
  params:add_option("copy_reflectors_scene_from","from scene",reflector_scene_labels,1)
  params:add_number("copy_reflectors_voice_to","to voice",1,num_voices,1)
  params:add_option("copy_reflectors_scene_to","to scene",reflector_scene_labels,1)
  params:add_trigger("copy_reflectors_selected","copy to selected voice/scene")
  params:set_action("copy_reflectors_selected",function() 
    local voice_from=params:get("copy_reflectors_voice_from")
    local scene_from=params:get("copy_reflectors_scene_from")
    local voice_to=params:get("copy_reflectors_voice_to")
    local scene_to=params:get("copy_reflectors_scene_to")
    print("copy reflectors",voice_from,scene_from,voice_to,scene_to)
    for p_ix=1,#eglut_params do
      local param_id=eglut_params[p_ix].id
      local rec_option_id_from=voice_from.."refl_config"..param_id..scene_from
      local rec_option_id_to=voice_to.."refl_config"..param_id..scene_to
      local value_to_sync=params:get(rec_option_id_from)    
      params:set(rec_option_id_to,value_to_sync)
    end
  end)
  
  -- params:add_trigger("copy_reflectors_global","copy to all voices/scenes")
  -- params:set_action("copy_reflectors_global",function() 
  --   local voice_from=params:get("copy_reflectors_voice_from")
  --   local scene_from=params:get("copy_reflectors_scene_from")
  --   print("copy reflectors all",voice_from,scene_from)
  --   for p_ix=1,#eglut_params do
  --     -- sync param values
  --     local param_id=eglut_params[p_ix].id
  --     local rec_option_id_from=voice_from.."refl_config"..param_id..scene_from
  --     local value_to_sync=params:get(rec_option_id_from)    
  --     for voice=1,num_voices do
  --       for scene=1,num_scenes do
  --         if voice ~= voice_from or scene ~= scene_from then
  --           local rec_option_id=voice.."refl_config"..param_id..scene
  --           print("g: ",rec_option_id,value_to_sync)
  --           params:set(rec_option_id,value_to_sync)
  --         end
  --       end
  --     end
  --   end
  -- end)

  --bang the defaults
  for voice=1,eglut.num_voices do
    for scene=1,eglut.num_scenes do
      for p_ix=1,#eglut_params do
        local param_id=eglut_params[p_ix].id
        local rec_option_id=voice.."refl_config"..param_id..scene
        local p = params:lookup_param(rec_option_id)
        p:bang()
      end
    end
  end
  
  -- hide scenes 2-4 initially
  showhide_reflectors(1)
  showhide_reflector_configs(1)
end

--- EXPERIMENTAL: changes the duration of the current loop
--- note: also see the code in the end_of_rec_callback
---       to clear the premult variables when there's a new recording
-- function reflection:lk_mult(mul)
--   clock.run(function() 
--     print(self.event_premult,self.endpoint_premult)
--     if self.event_premult == nil then
--       self.event_premult = deep_copy(self.event)
--       self.endpoint_premult = self.endpoint
--     end
--     local copy = deep_copy(self.event_premult)
--     print("CONTINUE")
--     clock.sleep(0.5)
--     local event_new = {}
--     for i = 1, self.endpoint do
--       event_new[math.ceil(i*mul)] = copy[i]
--       -- print(math.ceil(i*mul))
--     end
--     self.event = event_new
--     self.endpoint = math.ceil(self.endpoint_premult * mul)
--   end)
-- end

---------------------------------------------------
-- reflector stuff end
---------------------------------------------------

function get_selected_voice()
    return screens.p1ui.selected_voice
end

function init()
  print("initialize latkes")
  
  print(">>>>>>>override PSET save/load/delete<<<<<<<<")
  og_pset_write   = paramset.write
  og_pset_read    = paramset.read
  og_pset_delete  = paramset.delete

  function paramset.write(self,filename, name)
    og_pset_write(self,filename, name)
    filename = filename or 1
    local pset_number;
    if type(filename) == "number" then
      local n = filename
      filename = norns.state.data .. norns.state.shortname
      pset_number = string.format("%02d",n)
      local filename_pre = filename .. "-" .. pset_number
      print(">>>>>>>new paramset:write...save reflector data",filename_pre)
      local reflector_data_folder = filename_pre .. "-reflectors/"
      util.make_dir(reflector_data_folder)
      local reflector_data_folder_exists = util.file_exists(reflector_data_folder)
      if reflector_data_folder_exists == true then 
        for voice=1,num_voices do
          for scene=1, num_scenes do
            for k,v in pairs(reflectors[voice][scene]) do
              if v.count and v.count > 0 then
                filename = reflector_data_folder .. k .. ".rdat"
                -- print("save reflector", voice,scene,k,v.count,filename)
                v.save(v,filename)
              end
            end
          end
        end
      end
      
    end
  end

  function paramset.read(self,filename, silent)
    og_pset_read(self,filename, silent)
    filename = filename or norns.state.pset_last
    local pset_number;
    if type(filename) == "number" then
      local n = filename
      filename = norns.state.data .. norns.state.shortname
      pset_number = string.format("%02d",n)
      local filename_pre = filename .. "-" .. pset_number
      local reflector_data_folder = filename_pre .. "-reflectors/"
      print(">>>>>>>new paramset:read...read reflector data",reflector_data_folder)
      local reflector_data_folder_exists = util.file_exists(reflector_data_folder)
      if reflector_data_folder_exists == true then 
        for voice=1,num_voices do
          for scene=1, num_scenes do
            for k,v in pairs(reflectors[voice][scene]) do
              filename = reflector_data_folder .. k .. ".rdat"
              local reflector_data_exists = util.file_exists(filename)
              if reflector_data_exists then
                -- print("load reflector", voice,scene,k,filename)
                v = reflection.load(v,filename)
              end
            end
          end
        end
      end
    end
    --todo: figure out why we need to bang active scenes at the start?
    for i=1,4 do eglut:bang(i, params:get(i.."scene")) end

  end

  function paramset.delete(self,filename, name, pset_number)
    local filename_pre = string.sub(filename,1,-6)
    local reflector_data_folder = filename_pre .. "-reflectors"
    local reflector_data_folder_exists = util.file_exists(reflector_data_folder)
    if reflector_data_folder_exists == true then 
      print(">>>>>>>new paramset:delete...delete reflector data",reflector_data_folder)
      norns.system_cmd("rm -r "..reflector_data_folder)
    end
    og_pset_delete(self,filename, name, pset_number)    
  end

  screens:init({
    composition_top=composition_top,
    composition_bottom=composition_bottom,
    composition_left=composition_left,
    composition_right=composition_right,
    MAX_REFLECTORS_PER_SCENE=MAX_REFLECTORS_PER_SCENE
  })

  lk_grid.init()

  
  for i=1,eglut.num_voices do
    table.insert(waveform_names,i.."gran-live")
    table.insert(waveform_names,i.."gran-rec")
  end
  setup_waveforms()
  setup_params()
  eglut:init(on_eglut_file_loaded, num_voices, num_scenes,min_live_buffer_length, max_buffer_length)
  eglut:setup_params()
  midi_helper:init(num_voices,num_scenes)
  
  params:bang()
  setup_buffer_fill_amounts()

  -- eglut:init_lattice()
  init_reflectors()

  print("eglut inited and params setup")

  screen.aa(0)
  
  redrawtimer = metro.init(function() 
    local active_voice, scene = screens:get_selected_ui_elements()
    
    --check to keep active scene in sync with selected scene of active voice
    if scene ~= params:get(active_voice.."scene") then
      scene = params:get(active_voice.."scene")
      params:set("active_scene",scene)
    end
    
    if (norns.menu.status() == false) then
      redraw()
      -- if screen_dirty == true then redraw() end
    end
    -- if grid_dirty == false then
    lk_grid:redraw(params:get("active_screen"))
    -- end
  
  end, 1/30, -1)

  redrawtimer:start()
  screen_dirty = true
  osc.send( { "localhost", 57120 }, "/sc_osc/init_completed",{audio_path,data_path})

  -- uncomment to use the last pset automatically on script load
  -- params:read()

  for voice=1,eglut.num_voices do
    for scene=1,eglut.num_scenes do
      for reflector=1, MAX_REFLECTORS_PER_SCENE do
        local reflector_tab = get_reflector_table(voice,scene,reflector)
        local rec_id=voice.."-"..reflector.."record"..scene
        if reflector_tab then
          reflector_tab:load(reflection_data_path .. rec_id)
        end
        showhide_reflectors(scene,voice)
      end
    end
  end

  if device_16n then midi_helper.update_midi_devices(1,true) end

  --todo: figure out why we need to flip rec_scene and active voice to get params to show...something to do with show_hide loop at the start?
  params:set('rec_scene1',2)
  params:set('rec_scene1',1)
  params:set('rec_scene2',2)
  params:set('rec_scene2',1)
  params:set('rec_scene3',2)
  params:set('rec_scene3',1)
  params:set('rec_scene4',2)
  params:set('rec_scene4',1)


  local current_active = params:get("active_voice")
  for voice=1, num_voices do 
    if voice ~= current_active then
      params:set('active_voice',voice)
    end
  end
  clock.run(function() 
    clock.sleep(0.1)
    params:set('active_voice',current_active)
  end)

  inited=true
end

function key(k,z)  
  screens:key(k,z)
  screen_dirty = true
end

function enc(n,d)
  screens:enc(n,d)
  screen_dirty = true
end
-------------------------------
function redraw()
  if skip then
    screen.clear()
    screen.update()
    do return end
  end  

  screen.level(15)

  if not inited==true then
    print("not yet inited don't redraw")
    do return end
  end

  screen.clear()
  local voice = params:get("active_voice")
  local scene = params:get("active_scene")
  local playing = params:get(voice .. "play" .. scene)
  screens:redraw(params:get("active_screen"),playing)
  screen.stroke()
  screen.update()
  screen_dirty = false
  -- grid_dirty = false
end

function cleanup ()
  reflectors=nil
  -- if redrawtimer then metro.free(redrawtimer) end
  eglut:cleanup()
  eglut = nil
  --reinstate og params functions
  paramset.write = og_pset_write
  paramset.read = og_pset_read
  paramset.delete = og_pset_delete
end
