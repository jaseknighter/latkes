-- flucoma 2d corpus explorer
--
-- llllllll.co/t/futurespast
--
-- 2d corpus explorer for norns
-- v0.1
--
--    ▼ instructions below ▼
-- k2/k3 navigates the sounds
-- e2 select new sounds

-- adapted from: https://learn.flucoma.org/learn/2d-corpus-explorer/
-- FluCoMa installer code from @infiniteigits (schoolz) graintopia

-- check for requirements
installer_=include("lib/scinstaller/scinstaller")
installer=installer_:new{install_all="true",folder="FluidCorpusManipulation",requirements={"FluidCorpusManipulation"},zip="https://github.com/jaseknighter/flucoma-sc/releases/download/1.0.6-RaspberryPi/FluCoMa-SC-RaspberryPi.zip"}
engine.name=installer:ready() and 'Futurespast' or nil

-- textentry=require("textentry")

fileselect=include("lib/fileselect")
eglut=include("lib/eglut")
waveform=include("lib/waveform")
gridcontrol=include("lib/gridcontrol")
pages=include("lib/pages")

-- what is this code doing here?????
if not string.find(package.cpath,"/home/we/dust/code/graintopia/lib/") then
  package.cpath=package.cpath..";/home/we/dust/code/graintopia/lib/?.so"
end

json = require ("futurespast/lib/json/json")

-- modes
--  start
--  loading audio
--  composition loaded
--  analysing
--  points data generated
--  show composition

mode = "start"
-- local composition_loaded = false
-- local analysis_in_progress = false
-- local points_data_generated=false
-- local show_composition = false

local inited=false
local alt_key=false
-- local selecting_file = false
points_data=nil
local cursor_x = 64
local cursor_y = 32
local slice_played_ix = nil
local slice_played_x = nil
local slice_played_y = nil
local transport_src_left_ix = nil
local transport_src_left_x = nil
local transport_src_left_y = nil
local transport_src_right_ix = nil
local transport_src_right_x = nil
local transport_src_right_y = nil

-- local scale = 30
composition_top = 16
local composition_bottom = 64-12
composition_left = 23--16
local composition_right = 127-16

local slices_analyzed
local total_slices
local transporting_audio = false
local transport_gate = 1
local enc_debouncing=false

local record_live_duration = 10

local softcut_loop_start = 1
local softcut_loop_end = 4

waveforms = {}
waveform_names = {"composed","transported"}
waveform_sig_positions = {}
composition_slice_positions = {}
waveform_render_queue={}
-- local waveform_rendering=false

local max_analysis_length = 60 * 3
local gslice_generated=false

local session_name=os.date('%Y-%m-%d-%H%M%S')
local audio_path = _path.audio..norns.state.name.."/"
local session_audio_path=audio_path.."sessions_audio/"..session_name.."/"
local data_path=_path.data..norns.state.name.."/"
local reflection_data_path=data_path.."reflectors/"
local session_data_path=data_path.."sessions_data/"..session_name.."/"
-- local datasets_path=data_path.."datasets/"



--------------------------
-- waveform rendering
--------------------------
function show_waveform(waveform_name)
  for i=1,#waveform_names do
    if waveform_name==waveform_names[i] and waveform_names[i].waveform_samples then
      params:set("show_waveform",i)
    end
  end
end

function waveform_render_queue_add(waveform_name, waveform_path)
  table.insert(waveform_render_queue,{name=waveform_name, path=waveform_path})
  if #waveform_render_queue>0 then
    -- print("waveform_render_queue_add",waveform_name, waveform_path)
    waveforms[waveform_name].load(waveform_path,max_analysis_length)
  end
end

-- render_softcut_buffer(1,1,2,128)
function render_softcut_buffer(buffer,winstart,winend,samples)
  softcut.render_buffer(buffer, winstart, winend - winstart, 128)
end

function on_waveform_render(ch, start, i, s)
  local waveform_name=waveform_names[params:get("show_waveform")]
  local is_gran_live = string.sub(waveform_name,-9)=="gran-live"
  if is_gran_live then
    -- print("granlive:on_waveform_render", ch, start, i, s)
    set_waveform_samples(ch, start, i, s, waveform_name)
  elseif waveform_render_queue and waveform_render_queue[1] then
    local waveform_name=waveform_render_queue[1].name
    set_waveform_samples(ch, start, i, s, waveform_name)
    table.remove(waveform_render_queue,1)
    if #waveform_render_queue>0 then
      local next_waveform_name=waveform_render_queue[1].name
      local next_waveform_path=waveform_render_queue[1].path
      waveforms[next_waveform_name].load(next_waveform_path,max_analysis_length)
    else
    end
  end
end

function set_waveform_samples(ch, start, i, s, waveform_name)
  -- local waveform_name=waveform_names[params:get("show_waveform")]
  if waveform_name == "composed" then
    print("set waveform samples composed",s)
    waveforms["composed"]:set_samples(s)
    print("on waveform render composed: mode, s",mode,#s)
  elseif waveform_name == "transported" then
    waveforms["transported"]:set_samples(s)
    print("on waveform render transported: mode, s",mode,#s)
  elseif waveform_name and string.sub(waveform_name,-8) == "gran-rec" then
    waveforms[waveform_name]:set_samples(s)
  else
    for i=1,eglut.num_voices do
      waveforms[i.."gran-live"]:set_samples(s)
      -- if waveform_name == i.."gran-live" then
      --   waveforms[i.."gran-live"]:set_samples(s)
      -- elseif waveform_name == i.."gran-rec" then
      --   waveforms[i.."gran-rec"]:set_samples(s)
      -- end
    end
  end
  screen_dirty = true
end

--------------------------
-- osc functions
--------------------------
local script_osc_event = osc.event

function on_audio_composed(path)
  if mode ~= "audio composed" and mode ~= "analysing" then
    clock.sleep(0.5)
    mode = "analysing composition"
    waveform_render_queue_add("composed",path)
    if params:get("auto_analyze")==2 then
      mode = "analysing"
      screen_dirty = true
      local slice_threshold = params:get('slice_threshold')
      local min_slice_length = params:get('min_slice_length')
      osc.send( { "localhost", 57120 }, "/sc_osc/analyze_2dcorpus",{slice_threshold,min_slice_length})    
    else
      mode = "audio composed"
    end
  end
  -- end
end

function on_transportslice_written(path)
  if mode == "points generated" then
    clock.sleep(0.01)
    waveform_render_queue_add("transported",path)
    print("transport slice waveform loaded")
  end
end

-- function on_livebuffer_written(path,type)
--   clock.sleep(0.01)
--   for i=1,eglut.num_voices do
--     waveform_render_queue_add(i.."gran-live",path)
--   end
--   -- waveform_render_queue_add(voice.."gran-live",path)
-- end

function on_eglut_file_loaded(voice,file)
  print("on_eglut_file_loaded",voice, file)
  if mode~="points generated" then
    mode="granulated"
  end
  waveform_render_queue_add(voice.."gran-rec",file)  
  waveforms[voice.."gran-rec"].load(file,max_analysis_length)  
end

function set_eglut_sample(file,samplenum,scene)
  print("set_eglut_sample",file,samplenum,scene)
  params:set(samplenum.."sample",file)
  clock.sleep(0.1)
  eglut:update_scene(samplenum,scene)
end

function osc.event(path,args,from)
  if script_osc_event then script_osc_event(path,args,from) end
  
  if path == "/lua_eglut/grain_sig_pos" then
    -- tab.print(args)
    local sample=math.floor(args[1]+1)
    table.remove(args,1)
    waveform_sig_positions[sample.."granulated"]=args
    screen_dirty = true
  elseif path == "/lua_osc/sc_inited" then
    print("fcm 2d corpus sc inited message received")
  elseif path == "/lua_osc/compose_written" then
    local path = args[1]
    clock.run(on_audio_composed,path)
  elseif path == "/lua_osc/composelive_written" then
    local path = args[1]
    clock.run(on_audio_composed,path)
  elseif path == "/lua_osc/analyze_written" then
    print("analysis written", path)
  elseif path == "/lua_osc/analysis_progress" then
    slices_analyzed = args [1]
    total_slices = args[2]
    screen_dirty = true
  elseif path == "/lua_osc/analysis_dumped" then
    local json_path=args[1]
    print("dumped to json",json_path)
    clock.run(load_json,json_path)
  elseif path == "/lua_osc/slice_played" then
    slice_played_ix = tostring(args[1])
    composition_slice_positions[1]=args[2]
    composition_slice_positions[2]=args[3]
    slice_played_ix = args[1]
    slice_played_x = points_data[slice_played_ix][1]
    slice_played_y = points_data[slice_played_ix][2]
    slice_played_x = composition_left + math.ceil(slice_played_x*(127-composition_left-5))
    slice_played_y = composition_top + math.ceil(slice_played_y*(64-composition_top-5))
  elseif path == "/lua_osc/slice_transported" then
    transport_src_left_ix = tostring(args[1])
    transport_src_right_ix = tostring(args[2])
    transport_src_left_x = points_data[transport_src_left_ix][1]
    transport_src_left_y = points_data[transport_src_left_ix][2]
    transport_src_left_x = composition_left + math.ceil(transport_src_left_x*(127-composition_left-5))
    transport_src_left_y = composition_top + math.ceil(transport_src_left_y*(64-composition_top-5))
    if transport_src_right_ix then
      transport_src_right_x = points_data[transport_src_right_ix][1]
      transport_src_right_y = points_data[transport_src_right_ix][2]
      transport_src_right_x = composition_left + math.ceil(transport_src_right_x*(127-composition_left-5))
      transport_src_right_y = composition_top + math.ceil(transport_src_right_y*(64-composition_top-5))
    end
  elseif path == "/lua_osc/transportslice_written" then
    path = args[1]
    print("transportslice_written",path)
    clock.run(on_transportslice_written,path)
    for i=1,eglut.num_voices do
      if params:get(i.."granulate_transport")==2 then
        clock.run(set_eglut_sample,path,i,1)
      end
    end
  -- elseif path == "/lua_osc/start_livebuffer_visualization" then
    -- print("start_livebuffer_visualization")
    -- softcut_reset_pos()
  -- elseif path == "/lua_osc/livebuffer_written" then
  --   local path = args[1]
  --   local type = args[2]
  --   clock.run(on_livebuffer_written,path,type)
  elseif path == "/lua_osc/transport_sig_pos" then
    transport_sig_pos = args[1]
    waveform_sig_positions["transported"]=args
    screen_dirty = true
  elseif path == "/lua_osc/on_granulate_live" then
    -- softcut.rec_offset(1,0);
  end
end

function load_json(json_path)
  clock.sleep(2)
  local data_file=(io.open(json_path, "r"))
  points_data=data_file:read("*all")
  points_data=json.decode(points_data)
  points_data=points_data["data"]
  data_file:close()
  mode = "points generated" 
  local num_points=0
  for k,v in pairs(points_data) do num_points = num_points+1 end
  print("num_points generated",num_points)
  local starting_key = 1
  transport_keys:set_area(starting_key,num_points,4,6,1,1,10,0,1)
  screen_dirty = true
end

--update to save corresponding slice audio (sliceBuf)
--create corresponding trigger to load saved slice data/audio
-- function save_slices_data(name)
--   print("save_slices_data",session_data_path..name)
--   copy_data_file(session_data_path..name,datasets_path..name)
-- end

-- todo: rename to set_composed_audio_path
function set_audio_path(path)
  gslice_generated=false
  composition_slice_positions={}
  print("set_2dcorpus",path)
  -- selecting_file = false
  if path ~= "cancel" then
    mode = "loading audio"
    points_data=nil
    cursor_x = 64
    cursor_y = 32
    transport_src_left_x    = nil
    transport_src_left_y    = nil
    transport_src_right_x   = nil
    transport_src_right_y   = nil
    transport_src_left_ix   = nil
    transport_src_right_ix  = nil


    audio_path = path
    path_type = string.find(audio_path, '/', -1) == #audio_path and "folder" or "file"
    print("path_type",path_type)
    -- os.execute("rm '/temp/normed_fluid_data_set.json'")    
    local max_sample_length = params:get('max_sample_length')
    osc.send( { "localhost", 57120 }, "/sc_osc/set_2dcorpus",{audio_path,path_type,max_sample_length})
    waveforms["composed"]:set_samples(nil)
    gridcontrol:init()
    -- params:set("selected_sample",1)
    screen_dirty = true
  else
    screen_dirty=true
  end
end


function copy_data_file(from,to)
  -- local data_path = _path.data..norns.state.name.."/"
  from=data_path..from
  to=data_path..to
  os.execute("cp " .. from .. " " .. to)
end

function create_data_folders()
  os.execute("mkdir -p " .. data_path)
  os.execute("mkdir -p " .. reflection_data_path)
  os.execute("mkdir -p " .. session_data_path)
  os.execute("mkdir -p " .. session_data_path .. "data_sets")
  -- os.execute("mkdir -p " .. datasets_path)
end

function create_audio_folders()
  
  os.execute("mkdir -p " .. audio_path)
  os.execute("mkdir -p " .. session_audio_path)
  os.execute("mkdir -p " .. session_audio_path .. "/transports")
  os.execute("mkdir -p " .. session_audio_path .. "/slice_buffers")
end

function num_files_in_folder(path)
  local files = util.scandir (path)
  return #files
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

function setup_params()
  params:add_control("live_audio_dry_wet","live audio dry/wet",controlspec.new(0,1,'lin',0.01,1))
  params:set_action("live_audio_dry_wet",function(x)
    osc.send( { "localhost", 57120 }, "/sc_eglut/live_audio_dry_wet",{x})
  end)
  params:add_separator("waveforms")
  params:add_option("show_waveform","show waveform",waveform_names)
  params:set_action("show_waveform",function(x) 
    print("show_waveform",x,waveform_names[x]) 
    local waveform_name=waveform_names[x]
    local is_gran_live = string.sub(waveform_name,-9)=="gran-live"
  
    if is_gran_live then
      print("write_live_stream_enabled",1)
      print("start_livebuffer_visualization")
      -- softcut_reset_pos()
      -- osc.send( { "localhost", 57120 }, "/sc_osc/write_live_stream_enabled",{1})  
    else
      print("write_live_stream_enabled",0)
      -- osc.send( { "localhost", 57120 }, "/sc_osc/write_live_stream_enabled",{0})  
    end
    if waveforms[waveform_names[x]]:get_samples()==nil then
      print("waveform not yet captured")
    end  
  end)
  params:add_separator("slice/transport")
  params:add_control("cursor_x", "cursor x",controlspec.new(0,1,'lin',0.01,0.5,'',0.01))
  params:set_action("cursor_x", function(x)
    cursor_x = util.clamp(x*127,composition_left,127)
    if alt_key == false then play_slice() end
  end)
  params:add_control("cursor_y", "cursor y",controlspec.new(0,1,'lin',0.01,0.5,'',0.01))
  params:set_action("cursor_y", function(x) 
    cursor_y = util.clamp(x*64,composition_top,64)
    if alt_key == false then play_slice() end
  end)

  --------------------------
  --slice params
  --------------------------
  -- params:add_group("slice",6+eglut.num_voices)
  params:add_group("slice",8)
  params:add_trigger("select_folder_file", "select folder/file" )
  params:set_action("select_folder_file", function(x) 
    -- selecting_file = true 
    fileselect.enter(_path.audio, set_audio_path) 
  end)
  params:add_trigger("record_live", "record live")
  params:set_action("record_live", function() 
    mode = "recording"
    screen_dirty = true
    print("record live")
    print("start record live")
    osc.send( { "localhost", 57120 }, "/sc_osc/record_live",{record_live_duration})
  end)
  params:add_option("auto_analyze","auto analyze",{"off","on"},2)
  params:add_control("max_sample_length","max sample length",controlspec.new(1,5,'lin',0.1,1.5,"min"))
  params:add_control("slice_threshold","slice threshold",controlspec.new(0,1,'lin',0.1,0.5))
  params:add_control("min_slice_length","min slice length",controlspec.new(0,100,'lin',0.1,2,"",0.001))
  params:add_control("slice_volume","slice volume",controlspec.new(0,1,'lin',0.1,1))
  params:add_option("show_all_slice_ids","show all slice ids",{"off","on"},1)
  
  --------------------------
  --transport params
  --------------------------
  params:add_group("transport",6+eglut.num_voices)
  params:add_control("transport_volume","transport volume",controlspec.new(0,1,'lin',0.1,1))
  params:set_action("transport_volume", function(vol)         
    show_waveform("transported")
    osc.send( { "localhost", 57120 }, "/sc_osc/set_transport_volume",{vol}) 
  end)

  params:add_control("transport_rate","transport rate",controlspec.new(-10,10,'lin',0.01,1,"",1/20000))
  -- params:add_control("transport_rate","transport rate",controlspec.new(0.01,10,'lin',0.01,1,"",1/10000))
  params:set_action("transport_rate", function()         
    local transport_rate = params:get('transport_rate')
    show_waveform("transported")
    for voice=1,eglut.num_voices do
      for scene=1,eglut.num_scenes do
        if params:get(voice.."pitch_sync_external"..scene) == 2 then
          params:set(voice.."pitch"..scene,params:get('transport_rate'))
        end
      end
    end

    osc.send( { "localhost", 57120 }, "/sc_osc/set_transport_rate",{transport_rate}) 
    -- local function callback_func()
    -- end
    -- clock.run(enc_debouncer,callback_func)
  end)


  params:add_control("transport_trig_rate","transport trig rate",controlspec.new(1,40,'lin',1,4,"/beat",1/40))
  params:set_action("transport_trig_rate", function()  
    show_waveform("transported")       
    local function callback_func()
      for voice=1,eglut.num_voices do
        for scene=1,eglut.num_scenes do
          if params:get(voice.."density_sync_external"..scene) == 2 then
            params:set(voice.."density"..scene,params:get('transport_trig_rate'))
          end
        end
      end

      local trig_rate = params:get('transport_trig_rate')/(params:get("transport_beat_divisor")*clock.get_beat_sec())
      print("ttrigrate",trig_rate)

      osc.send( { "localhost", 57120 }, "/sc_osc/set_transport_trig_rate",{trig_rate}) 
    end
    clock.run(enc_debouncer,callback_func)
  end)
  params:add_control("transport_beat_divisor","transport beat div",controlspec.new(1,16,'lin',1,4,"",1/16))
  params:set_action("transport_beat_divisor",function() 
    local p=params:lookup_param("transport_trig_rate")
    p:bang()
  end)
  params:add_control("transport_reset_pos","transport reset pos",controlspec.new(0,1,'lin',0,0))
  params:set_action("transport_reset_pos", function()  
    show_waveform("transported")       
    local function callback_func()
      osc.send( { "localhost", 57120 }, "/sc_osc/set_transport_reset_pos",{params:get('transport_reset_pos')}) 
    end
    clock.run(enc_debouncer,callback_func)
  end)

  params:add_control("transport_stretch","transport stretch",controlspec.new(0,5,'lin',0.01,0,'',1/1000))
  params:set_action("transport_stretch", function()  
    show_waveform("transported")
    local function callback_func()
      osc.send( { "localhost", 57120 }, "/sc_osc/set_transport_stretch",{params:get('transport_stretch')}) 
    end
    clock.run(enc_debouncer,callback_func)
  end)
  for i=1,eglut.num_voices do
    local default=i==1 and 2 or 1
    params:add_option(i.."granulate_transport","granulate->"..i,{"off","on"},default)
  end
  --------------------------
  --save/load params
  --------------------------
  -- params:add_group("save/load",1)
  -- params:add_trigger("save_slices_data", "save slices data" )
  -- params:set_action("save_slices_data", function(x) 
  --   selecting_file = true 
  --   textentry.enter(save_slices_data) 
  -- end)

end

function setup_params_post_eglut()
  params:add_control("live_rec_level","live rec level",controlspec.new(0,1,"lin",0.01,1))
  params:set_action("live_rec_level",function(value) 
    softcut.rec_level(1,value);
    osc.send( { "localhost", 57120 }, "/sc_eglut/live_rec_level",{value})
  end)
  params:add_control("live_pre_level","live pre level",controlspec.new(0,1,"lin",0.01,0))
  params:set_action("live_pre_level",function(value) 
    softcut.pre_level(1,value)
    osc.send( { "localhost", 57120 }, "/sc_eglut/live_pre_level",{value})
  end)
end

---------------------------------------------------
-- reflection stuff start
-- reflection code from @alanza (https://llllllll.co/t/low-pixel-piano/65705/2)
---------------------------------------------------
local reflection = require 'reflection'
local reflector_scene_labels={'i','ii','iii','iv'}
eglut_params={}
local max_reflectors_per_scene=8
reflector_process_data={}

--[[
-- key reflection functions

mir:stop()
mir:start()
mir:set_rec() - 0 stop,1 start, 2 queue
mir:set_loop() - 0 no loop, 1 loop
mir:watch({event})
mir.end_of_rec_callback=function() --do something end
mir.step_callback=function() --do something end
mir.start_callback=function() --do something end
mir.stop_callback=function() --do something end
mir.endpoint
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
  -- print("init reflector",p_id,voice,scene)
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
    -- print("process reflector",voice,scene,p_id)
    -- tab.print(event)
  end
  reflectors[voice][scene][p_id].start_callback=function() 
    -- print("reflector start callback",voice,scene,p_id)
  end
  reflectors[voice][scene][p_id].end_callback=function() 
    print("reflector end callback",voice,scene,p_id)
    local recorder_ix=reflectors[voice][scene][p_id].recorder_ix
    local reflector_loop=params:get(voice.."-"..recorder_ix.."loop"..scene)
    if reflector_loop==1 then
      local reflector_play=voice.."-"..recorder_ix.."play"..scene
      params:set(reflector_play,1)
    end
  end
  reflectors[voice][scene][p_id].stop_callback=function() 
    print("reflector stop callback",voice,scene,p_id)
  end
  reflectors[voice][scene][p_id].end_of_rec_callback=function() 
    local recorder_ix=reflectors[voice][scene][p_id].recorder_ix
    local rec_id=voice.."-"..recorder_ix.."record"..scene
    local reflector_tab = get_reflector_table(voice,scene,recorder_ix)    
    print("reflector end of rec callback",voice,scene,p_id,recorder_ix,rec_id,reflector_tab)
    tab.print(reflector_tab)
    reflector_tab:save(reflection_data_path .. rec_id)
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

  -- reflectors[voice][scene][p_id]
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
    -- if voice==1 and scene==1 then print("reflector_tab.recorder_ix",reflector_tab.recorder_ix) end

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
      if voice==1 and scene==1 then print(selected_scene,num_reflectors) end
      if scene==selected_scene and num_reflectors==0 then
        params:show(voice.."noreflectors_spacer"..scene)
        params:show(voice.."noreflectors"..scene)
      else
        params:hide(voice.."noreflectors_spacer"..scene)
        params:hide(voice.."noreflectors"..scene)
      end

      for reflector=1,max_reflectors_per_scene do
        local reflector_sep_id=voice.."-"..reflector.."separator"..scene
        local reflector_record_id=voice.."-"..reflector.."record"..scene          
        local reflector_play_id=voice.."-"..reflector.."play"..scene          
        local reflector_loop_id=voice.."-"..reflector.."loop"..scene          
        if scene==selected_scene and reflector <= num_reflectors then
          params:show(reflector_sep_id)
          params:show(reflector_record_id)
          local reflector_tab = get_reflector_table(voice,scene,reflector)
          local reflector_data = reflector_tab and reflector_tab.count or 0
          -- if voice==1 and scene==1 then print("show/hide reflectors",reflector,reflector_data) end
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
          local rec_option_id=voice.."rec_config"..param_id..scene
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
        local rec_option_id=voice.."rec_config"..param_id..scene
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
      for reflector=1,max_reflectors_per_scene do
        reflector_process_data[voice][scene][reflector]={}
      end
    end

  end

  reflectors_param_list={
    "play","volume","volumelfo","ptr_delay","speed","speedlfo","seek","seeklfo",
    -- "pos",
    "size","sizelfo","density","density_beat_divisor","density_sync_external","densitylfo",
    "pitch","pitch_sync_external","spread_sig","spread_siglfo",
    "spread_sig_offset1","spread_sig_offset2","spread_sig_offset3",
    "jitter","jitterlfo",
    "fade","attack_level","attack_time","decay_time","env_shape",
    "cutoff","cutofflfo","q","send","division","pan","spread_pan","spread_panlfo",
    "subharmonics","subharmonicslfo","overtones","overtoneslfo",
  }
  
  --generate a list of non-lfo eglut params
  for i=1,#reflectors_param_list do
    local p_id=reflectors_param_list[i]
    local haslfo = string.find(p_id,"lfo")
    if haslfo==nil then 
      local p_name=params:lookup_param("1"..p_id.."1").name
      table.insert(eglut_params,{id=p_id,name=p_name}) 
    end
  end

  params:add_separator("granular reflectors")
  -- setup reflectors
  for voice=1,eglut.num_voices do
    params:add_group("gran_voice"..voice.."-rec","voice"..voice.."-rec",3+(#reflector_scene_labels*(max_reflectors_per_scene*4)))
    params:add_option("rec_scene"..voice,"scene",reflector_scene_labels,1)
    params:set_action("rec_scene"..voice,function(scene) 
      local prior_scene=reflectors_selected_params[voice].prior_scene
      if prior_scene then
        for k,v in pairs(reflectors_selected_params[voice][prior_scene]) do
          local id=v.id
          print(prior_scene,id)
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
      
      for reflector=1,max_reflectors_per_scene do
        local sep_id=voice.."-"..reflector.."separator"..scene
        params:add_separator(sep_id,"reflector"..reflector)
        local rec_id=voice.."-"..reflector.."record"..scene
        params:add_option(rec_id,"record",{"off","on"})
        params:set_action(rec_id,function(value) 
          local reflector_tab = get_reflector_table(voice,scene,reflector)
          if value==2 then
            print("start reflector",rec_id)
            reflector_tab:clear()
            reflector_tab:set_rec(1)
          else
            print("stop reflector",rec_id,voice,scene,reflector)
            reflector_tab:set_rec(0)
          end
          showhide_reflectors(scene,voice)
        end)
        local loop_id=voice.."-"..reflector.."loop"..scene
        params:add_option(loop_id,"loop",{"off","on"})
        params:set_action(loop_id,function(value) 
          local reflector_tab = get_reflector_table(voice,scene,reflector)
          -- print("loop reflector",value==1 and "off" or "on")
          if reflector_tab then
            if value==1 then
              reflector_tab:set_loop(0)
            else
              reflector_tab:set_loop(1)
            end
          end
        end)

        local play_id=voice.."-"..reflector.."play"..scene
        params:add_option(play_id,"play",{"off","on"})
        params:set_action(play_id,function(value) 
          local reflector_tab = get_reflector_table(voice,scene,reflector)
          print(get_reflector_table,voice,scene,reflector)
          if reflector_tab then
            if value==1 then
              reflector_tab:stop()
            else
              reflector_tab:start()
            end
          end
        end)



      end
        
    end
  end

  -- setup config sub menus
  for voice=1,eglut.num_voices do
    reflectors[voice]={}
    params:add_group("gran_voice"..voice.."-rec config","voice"..voice.."-rec config",1+(eglut.num_voices*#eglut_params))
    params:add_option("rec_config_scene"..voice,"scene",reflector_scene_labels,1)
    params:set_action("rec_config_scene"..voice,function(scene) 
      showhide_reflector_configs(scene,voice.."rec_config")
    end)
    for scene=1,eglut.num_scenes do
      reflectors[voice][scene]={}
      for p_ix=1,#eglut_params do
        local param_id=eglut_params[p_ix].id
        local param_name=eglut_params[p_ix].name
        local rec_option_id=voice.."rec_config"..param_id..scene
        params:add_option(rec_option_id,param_name,{"off","on"})
        params:set_action(rec_option_id,function(state) 
          local param=voice..eglut_params[p_ix].id..scene
          if state==1 then
            print("unenrich param",param)
            unenrich_param_reflector_actions(param,voice,scene)
          else
            print("enrich param",param,p_ix)
            local num_reflectors=get_num_reflectors(voice,scene)
            if num_reflectors<max_reflectors_per_scene then
              enrich_param_reflector_actions(param,voice,scene)
            else
              print("too many reflectors. max is ", max_reflectors_per_scene)
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
  -- hide scenes 2-4 initially
  showhide_reflectors(1)
  showhide_reflector_configs(1)
end

---------------------------------------------------
-- reflector stuff end
---------------------------------------------------

function enc_debouncer(callback,debounce_time)
  if debounce_time then print("deb",debounce_time) end
  debounce_time = debounce_time or 0.1
  if enc_debouncing == false then
    enc_debouncing = true
    clock.sleep(debounce_time)
    callback()
    enc_debouncing = false
  end
end

function softcut_reset_pos()
  softcut.position(1,softcut_loop_start)
end

function softcut_init()
  -- rate = 1.0
  local rec = 1.0
  local pre = 0.0
  
  level = 1.0
  -- params:set("softcut_level",-inf)
    -- send audio input to softcut input
	audio.level_adc_cut(1)  
  softcut.buffer_clear()
  softcut.enable(1,1)
  softcut.buffer(1,1)
  softcut.level(1,1.0)
  softcut.rate(1,1.0)
  softcut.loop(1,1)
  softcut.loop_start(1,softcut_loop_start)
  softcut.loop_end(1,softcut_loop_end) --voice,duration
  softcut.position(1,1)
  softcut.play(1,1)

  -- set input rec level: input channel, voice, level
  softcut.level_input_cut(1,1,1.0)
  softcut.level_input_cut(2,1,1.0)
  -- set voice 1 record level 
  softcut.rec_level(1,rec)
  -- softcut.rec_level(1,0);softcut.pre_level(1,1)
  softcut.rec_level(1,1);softcut.pre_level(1,0)
  -- set voice 1 pre level
  softcut.pre_level(1,pre)
  -- set record state of voice 1 to 1
  softcut.rec(1,1)

  softcut.event_render(on_waveform_render)

end

function init()
  print("init>>>")
  -- os.execute("jack_disconnect crone:output_5 SuperCollider:in_1;")  
  -- os.execute("jack_disconnect crone:output_6 SuperCollider:in_2;")
  -- os.execute("jack_connect softcut:output_1 SuperCollider:in_1;")  
  -- os.execute("jack_connect softcut:output_2 SuperCollider:in_2;")
  -- os.execute("sleep 9;")

  if not installer:ready() then
    return
  end

  pages:init({
    composition_top=composition_top,
    composition_bottom=composition_bottom,
    composition_left=composition_left,
    composition_right=composition_right,
    max_reflectors_per_scene=max_reflectors_per_scene
  })
  
  for i=1,eglut.num_voices do
    table.insert(waveform_names,i.."gran-live")
    table.insert(waveform_names,i.."gran-rec")
  end
  create_audio_folders()
  create_data_folders()
  setup_waveforms()
  setup_params()
  eglut:init(on_eglut_file_loaded)
  eglut:setup_params()
  eglut:init_lattice()
  setup_params_post_eglut()
  init_reflectors()
  
  params:set("transport_volume",0.2)
  gridcontrol:init()
  print("eglut inited and params setup")
  -- params:set("1play1",2)

  screen.aa(0)
  softcut_init()
  
  redrawtimer = metro.init(function() 
    if (norns.menu.status() == false and fileselect.done~=false) then
      if screen_dirty == true then redraw() end
      render_softcut_buffer(1,1,softcut_loop_end,128)
    end
    -- if norns.menu.status() == true and menu_active == false then
    --   menu_active = true
    -- elseif norns.menu.status() == false and fileselect.done~=false then
    --   if menu_active == true then
    --     menu_active = false
    --     screen_dirty = true
    --   end
    --   redraw()
    -- end
  end, 1/15, -1)
  redrawtimer:start()
  screen_dirty = true
  osc.send( { "localhost", 57120 }, "/sc_osc/init_completed",{
      session_name,audio_path,session_audio_path,data_path,session_data_path
  })

  params:read()

  for voice=1,eglut.num_voices do
    for scene=1,eglut.num_scenes do
      for reflector=1, max_reflectors_per_scene do
        local reflector_tab = get_reflector_table(voice,scene,reflector)
        local rec_id=voice.."-"..reflector.."record"..scene
        if reflector_tab then
          print("load reflector",reflection_data_path .. rec_id)
          reflector_tab:load(reflection_data_path .. rec_id)
        end
        showhide_reflectors(scene,voice)
      end
    end
  end

  inited=true
  --todo: figure out why we need to flip rec_scene to get params to show...something to do with show_hide loop at the start?
  params:set('rec_scene1',2)
  params:set('rec_scene1',1)
  params:set("1sample_mode",2)
  params:set("1play1",2)

  for i=1,eglut.num_voices do
    for j=1,eglut.num_scenes do
      params:set(i.."ptr_delay"..j,0.01)
    end
  end
end

function key(k,z)
  if not installer:ready() then
    installer:key(k,z)
    do return end
  end
  
  if k==1 then
    if z==1 then
      alt_key=true
    else
      alt_key=false
    end
  end
  if k==2 and z==0 then
    -- fileselect.enter('/home/we/dust/audio', set_audio_path)   
    if alt_key == false then
      params:set("select_folder_file",1)
    elseif mode == "points generated" and slice_played_x then
      local x = math.ceil(util.linlin(composition_left,127,1,127,cursor_x))
      local y = math.ceil(util.linlin(composition_top,64,1,64,cursor_y))    
      transporting_audio = true
      osc.send( { "localhost", 57120 }, "/sc_osc/transport_slices",{x/127,y/64})
      if composition_slice_positions[3] then
        composition_slice_positions[5]=composition_slice_positions[3]
        composition_slice_positions[6]=composition_slice_positions[4]          
      end
      composition_slice_positions[3]=composition_slice_positions[1]
      composition_slice_positions[4]=composition_slice_positions[2]
    end
  elseif k==3 and z==0 then
    if alt_key == true and mode == "start" then
      params:set("record_live",1)
    elseif alt_key == true then
      transport_gate = transport_gate == 1 and 0 or 1
      osc.send( { "localhost", 57120 }, "/sc_osc/transport_gate",{transport_gate})
      print("transport_gate",transport_gate)
    elseif mode == "audio composed" then
      mode = "analysing"
      screen_dirty = true
      local slice_threshold = params:get('slice_threshold')
      local min_slice_length = params:get('min_slice_length')
      osc.send( { "localhost", 57120 }, "/sc_osc/analyze_2dcorpus",{slice_threshold,min_slice_length})
    elseif gslice_generated == true then
        print("append gslice????")
        -- osc.send( { "localhost", 57120 }, "/sc_osc/append_gslice",{})
    end      
  end
end

function enc(n,d)
  if not installer:ready() then
    do return end
  end
  if n==1 then
    pages.active_page=util.clamp(d+pages.active_page,1,2)
  end
  if pages.active_page==1 then
    if mode == "points generated" and points_data then
      if n==2 then
        params:set("cursor_x",params:get("cursor_x")+(d/127))
        if alt_key == true and transporting_audio == true then
          local function callback_func()
            local x = math.ceil(util.linlin(composition_left,127,0,127,cursor_x))
            local y = math.ceil(util.linlin(composition_top,64,0,64,cursor_y))      
            osc.send( { "localhost", 57120 }, "/sc_osc/transport_x_y",{x/127,y/64})
          end
          clock.run(enc_debouncer,callback_func)
        end
        
      elseif n==3 then
        params:set("cursor_y",params:get("cursor_y")+(d/64))
        if alt_key == true then
          -- engine.volume(1,(y-composition_top)/(64-composition_top-5))
          if transporting_audio == true then 
            local function callback_func()
            local x = math.ceil(util.linlin(composition_left,127,0,127,cursor_x))
            local y = math.ceil(util.linlin(composition_top,64,0,64,cursor_y))      
            osc.send( { "localhost", 57120 }, "/sc_osc/transport_x_y",{x/127,y/64})
          end
          clock.run(enc_debouncer,callback_func)
          end
        end
      end
    end
  elseif pages.active_page==2 then
    pages:enc(n,d)
  end
  screen_dirty = true
end

function play_slice()
  if inited==true then
    local x = math.ceil(util.linlin(composition_left,127,1,127,cursor_x))
    local y = math.ceil(util.linlin(composition_top,64,1,64,cursor_y))
    local retrigger = 0
    osc.send( { "localhost", 57120 }, "/sc_osc/play_slice",{x/127,y/64,params:get("slice_volume"),retrigger})
  end
end

-------------------------------
function redraw()
  if skip then
    screen.clear()
    screen.update()
    do return end
  end  

  screen.level(15)

  if not installer:ready() then
    installer:redraw()
    do return end
  end

  if not inited==true then
    print("not yet inited don't redraw")
    do return end
  end


  screen.clear()

  pages:redraw(pages.active_page)

  -- screen.peek(0, 0, 127, 64)
  screen.stroke()
  screen.update()
  screen_dirty = false
end

function cleanup ()
  -- print("cleanup",redrawtimer)
  -- os.execute("jack_connect crone:output_5 SuperCollider:in_1;")  
  -- os.execute("jack_connect crone:output_6 SuperCollider:in_2;")
  -- os.execute("jack_disconnect softcut:output_1 SuperCollider:in_1;")  
  -- os.execute("jack_disconnect softcut:output_2 SuperCollider:in_2;")

  -- waveform_render_queue=nil
  -- waveforms=nil
  softcut.event_render(nil)

  reflectors=nil
  if redrawtimer then metro.free(redrawtimer) end
  eglut:cleanup()
  gridcontrol:cleanup()
end