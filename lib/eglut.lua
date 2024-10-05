Lattice = require "lattice"
Sequins = require "sequins"
local e={}
e.inited = false
e.all_param_ids   = {} 
e.all_param_names = {}
e.speed_magnets={-2,-1.5,-1,-0.5,0,0.5,1,1.5,2}

e.start_scene_params_at = 7

e.param_list={
  "sample_length",
  "sample_mode",
  "sample",
  "live_rec_level",
  "live_pre_level",
  "grain_params",
  "play",
  "volume","send","ptr_delay","speed","seek",
  "size","density","density_beat_divisor","density_jitter","density_jitter_mult",
  "pitch","spread_sig",
  "spread_sig_offset1","spread_sig_offset2","spread_sig_offset3",
  "jitter",
  "fade","attack_level","attack_time","decay_time","env_shape",
  "cutoff","q","pan","spread_pan",
  "subharmonics","overtones",
}
e.param_list_echo={"echo_volume","echo_mod_freq","echo_mod_depth","echo_fdbk","echo_diff","echo_damp","echo_size","echo_time"}
e.num_voices=4
e.num_scenes=4
e.scene_labels={"a","b","c","d"}
e.active_scenes={}
for i=1,e.num_voices do
  e.active_scenes[i]=1
end

-- morphing function
-- note: the last two parameters (steps_remaining and next_val) are "private" to the function and don't need to included in the inital call to the function
-- example code for initiating a morph: `morph(my_callback_function,1,10,2,10,"log")`
function morph(callback,s_val,f_val,duration,steps,shape, id, steps_remaining, next_val)
  local start_val = s_val < f_val and s_val or f_val
  local finish_val = s_val < f_val and f_val or s_val
  local increment = (finish_val-start_val)/steps
  if next_val and steps_remaining < steps then
    local delay = duration/steps
    clock.sleep(delay)
    local return_val = next_val
    if s_val ~= f_val then
      callback(return_val, id)
    else
      callback(s_val, id)
    end
  end
  local steps_remaining = steps_remaining and steps_remaining - 1 or steps 
  
  if steps_remaining >= 0 then
    local value_to_convert
    if next_val == nil then
      value_to_convert = start_val
    elseif s_val < f_val then
      -- value_to_convert = next_val and s_val + ((steps-steps_remaining) * increment) 
      value_to_convert = next_val and start_val + ((steps-steps_remaining) * increment) 
    else
      value_to_convert = next_val and finish_val - ((steps-steps_remaining) * increment) 
    end 

    if shape == "exp" then
      next_val = util.linexp(start_val,finish_val,start_val,finish_val, value_to_convert)
    elseif shape == "log" then
      next_val = util.explin(start_val,finish_val,start_val,finish_val, value_to_convert)
    else
      next_val = util.linlin(start_val,finish_val,start_val,finish_val, value_to_convert)
    end
    clock.run(morph,callback,s_val,f_val,duration,steps,shape, id, steps_remaining,next_val)
  end
end

function e.table_concat(t1,t2,t1_start,t2_start)
  local concat_table={}
  t1_start = t1_start or 1
  t1_end = #t1 - (t1_start-1)
  for i=1,t1_end do
    concat_table[i] = t1[i+(t1_start-1)]
  end
  t2_start = t2_start or 1
  t2_end = #t2 - (t2_start-1)
  local concat_table_size = #concat_table
  for i=t1_end+1,t2_end do
    concat_table[concat_table_size+i] = t2[i+(t2_start-1)]
  end
  return concat_table
end

--note: this is not a generic function
--      it is specific to the eglut params
function e.id_to_name(id_table)
  local name_table={}
  for i=1,#id_table do
    local param=params:lookup_param("1"..id_table[i].."1")
    local name=param.name
    name_table[i] = name
  end
  return name_table
end


-- deep copy code that handles recursive tables here:
--  http://lua-users.org/wiki/CopyTable
function deep_copy(orig, copies)
  copies = copies or {}
  local orig_type = type(orig)
  local copy
  if orig_type == 'table' then
      if copies[orig] then
          copy = copies[orig]
      else
          copy = {}
          copies[orig] = copy
          for orig_key, orig_value in next, orig, nil do
              copy[deep_copy(orig_key, copies)] = deep_copy(orig_value, copies)
          end
          setmetatable(copy, deep_copy(getmetatable(orig), copies))
      end
  else -- number, string, boolean, etc
      copy = orig
  end
  return copy
end

-- SEQUENCER FOR GRAIN PARAMS: WORK IN PROGRESS
function e:init_lattice()
  e.lattice = Lattice:new{
    auto = false,
    meter = 4,
    ppqn = 96
  }
  e.sprockets={}
  e.sprockets["density"]={}
  e.sequins={}
  e.sequins["density"]={}
  for i=1,e.num_voices do
    e.sprockets["density"][i]={}
    e.sequins["density"][i]={}
    for j=1,e.num_scenes do
      -- eglut.sequins["density"][2][1]=Sequins{8}
      -- e.sequins["density"][i][j]=Sequins{1,2,4,8}
      e.sequins["density"][i][j]=Sequins{10,20,40,30,30,30,20,20,20,20,20}
      e.sprockets["density"][i][j] = e.lattice:new_sprocket{
        action = function(t)
          local next_seq=e.sequins["density"][i][j]()
          -- if i==1 and j==1 then
          if j==1 then
            params:set(i.."density"..j,next_seq)
          end
          print("density",i,j,next_seq)
        end,
        division = 1/4,
        enabled = i==1 and true or false
      }
    end
  end
  self.lattice.enabled=true
  self.lattice:start()
end


function e:init(sample_selected_callback, num_voices, num_scenes)
  self.sample_selected_callback = sample_selected_callback
  self.num_voices = num_voices or self.num_voices
  self.num_scenes = num_scenes or self.num_scenes
  
end

function e:on_sample_selected(voice,scene,file)
  self.sample_selected_callback(voice,file)
end

function e:bang(voice, scene, bangscope)
  bangscope = bangscope or 1
  if bangscope == 1 then
    local start_voice=1
    local end_voice = e.num_voices
    if self.inited then 
      start_voice = voice
      end_voice = voice
    end

    for i=start_voice,end_voice do
      for k,param_name in ipairs(e.param_list) do
        local p
        if k >= e.start_scene_params_at then
          p=params:lookup_param(i..param_name..scene)
        -- else
        --   p=params:lookup_param(i..param_name)
        end
        if p and p.t~=6 then p:bang() end
      end
      -- local p=params:lookup_param(i.."pattern"..scene)
      -- p:bang()
    end
  end
  if bangscope ~= 2 then
    for _,param_name in ipairs(e.param_list_echo) do
      local p=params:lookup_param(param_name..scene)
      if p.t~=6 then 
        p:bang() 
      end
    end
  end
end

function e:get_gr_env_values(voice, scene)
  local attack_level = params:get(voice.."attack_level"..scene)
  local attack_time = params:get(voice.."attack_time"..scene)
  local decay_time = params:get(voice.."decay_time"..scene)
  local attack_shape = params:get(voice.."env_shape"..scene)
  local decay_shape = params:get(voice.."env_shape"..scene)
  return {attack_level, attack_time, decay_time, attack_shape, decay_shape}
end


-- param stuff
function e:rebuild_params()
  -- if _menu.rebuild_params~=nil then
  if self.inited then
    _menu.rebuild_params()
  end
end

function e:load_file(voice,scene,file)
  local sample_length = params:get(voice.."sample_length")
  engine.read(voice,file,sample_length)
  e:on_sample_selected(voice,scene,file)
end

function e:granulate_live(voice)
  local sample_length = params:get(voice.."sample_length")
  osc.send( { "localhost", 57120 }, "/sc_osc/granulate_live",{voice-1, sample_length})
end

function e:update_scene(voice,scene)
  e.active_scenes[voice]=scene
  for p_ix,param_id in ipairs(e.param_list) do
    for i=1,e.num_scenes do
      if i~=scene and p_ix >= e.start_scene_params_at then
        params:hide(voice..param_id..(i))
      end
    end
    if p_ix >= e.start_scene_params_at then
      params:show(voice..param_id..scene)
    end
  end

  e:bang(voice,scene)      
  e:rebuild_params()
end

function e:sync_scenes(params_name, sync_all)
  for i=1,e.num_voices do
    for _,param_name in ipairs(e.param_list) do
      params:hide(i..param_name..e.num_scenes)
    end
  end
  for _,param_name in ipairs(e.param_list_echo) do
    for i=2,e.num_scenes do
      params:hide(param_name..i)
    end
  end
end

function e:setup_params()
  params:add_separator("granular")
  local old_volume={0.25,0.25,0.25,0.25}
  
  for i=1,e.num_voices do
    params:add_group("voice "..i,((#e.param_list-e.start_scene_params_at)*e.num_scenes))
    params:add_option(i.."scene","scene",e.scene_labels,1)
    params:set_action(i.."scene",function(scene)
      scene=scene and scene or 1
      e:update_scene(i,scene)
    end)
    params:add_control(i.."sample_length","sample length",controlspec.new(1,120.0,"exp",0.1,10,"s",0.1/120))
    params:set_action(i.."sample_length",function()
      if params:get(i.."sample_mode") == 2 then
        self:granulate_live(i)
      end
    end)

    local sample_modes={"off","live stream","recorded"}
    params:add_option(i.."sample_mode","sample mode",sample_modes,1)
    params:set_action(i.."sample_mode",function(mode)
      local function callback_func()
        if sample_modes[mode]=="off" then
          params:set(i.."play"..params:get(i.."scene"),1)
        elseif sample_modes[mode]=="live stream" then
          params:set(i.."play"..params:get(i.."scene"),1)
          params:set(i.."play"..params:get(i.."scene"),2)
          self:granulate_live(i)
        elseif sample_modes[mode]=="recorded" then
          local recorded_file = params:get(i.."sample")
          if recorded_file ~= "-" then
            e:load_file(i,e.active_scenes[i],recorded_file)            
          else
            print("no file selected to granulate")
            params:set(i.."play"..params:get(i.."scene"),1)
            -- params:set(i.."play"..params:get(i.."scene"),1)
          end
        end
      end
      callback_func()
      -- clock.run(enc_debouncer,callback_func,0.2)
    end)
    params:add_file(i.."sample","sample")
    params:set_action(i.."sample",function(file)
      if params:get(i.."sample_mode") == 3 then
        print("sample ",i,e.active_scenes[i],file)
        if file~="-" then
          e:load_file(i,e.active_scenes[i],file)
        end
      end
    end)
    
    params:add_control(i.."live_rec_level","live rec level",controlspec.new(0,1,"lin",0.01,1))
    params:set_action(i.."live_rec_level",function(value) 
      softcut.rec_level(i,value);
      osc.send( { "localhost", 57120 }, "/sc_eglut/live_rec_level",{value,i-1})
    end)
    params:add_control(i.."live_pre_level","live pre level",controlspec.new(0,1,"lin",0.01,0))
    params:set_action(i.."live_pre_level",function(value) 
      softcut.pre_level(i,value)
      osc.send( { "localhost", 57120 }, "/sc_eglut/live_pre_level",{value,i-1})
    end)
  
    params:add_separator(i.."grain_params","param values")
    for scene=1,e.num_scenes do

      


      params:add_option(i.."play"..scene,"play",{"off","on"},1)
      params:set_action(i.."play"..scene,function(x) 
        if params:get(i.."sample_mode") > 1 then
          engine.gate(i,x-1) 
        else
          engine.gate(i,0) 
        end
      end)

      params:add_control(i.."volume"..scene,"volume",controlspec.new(0,1.0,"lin",0.05,1,"vol",0.05/1))
      -- params:add_control(i.."volume"..scene,"volume",controlspec.new(0,1.0,"lin",0.05,0.25,"vol",0.05/1))
      params:set_action(i.."volume"..scene,function(value)
        engine.volume(i,value)
        
        -- turn off the delay if volume is zero
        -- if value==0 then
        --   engine.send(i,0)
        -- elseif value>0 and old_volume[i]==0 then
        --   engine.send(i,params:get(i.."send"..scene))
        -- end
        -- old_volume[i]=value
      end)

      params:add_control(i.."send"..scene,"echo send",controlspec.new(0.0,1.0,"lin",0.01,1))
      params:set_action(i.."send"..scene,function(value) engine.send(i,value) end)

      params:add_control(i.."ptr_delay"..scene,"delay",controlspec.new(0.005,2,"lin",0.001,0.2,"",0.01/2))
      -- params:add_control(i.."ptr_delay"..scene,"delay",controlspec.new(0.05,2,"lin",0.001,0.2,"",0.05/2))
      params:set_action(i.."ptr_delay"..scene,function(value) engine.ptr_delay(i,value) end)
      
      
      local function speed_check(speed,voice,scene)
        clock.sleep(0.1, speed, voice, scene)
        for i=1,#e.speed_magnets do
          if speed ~= e.speed_magnets[i] and speed-0.05 < e.speed_magnets[i] and speed+0.05 > e.speed_magnets[i] then
            params:set(voice.."speed"..scene,e.speed_magnets[i])
            break
          end
          
        end
      end
      params:add_control(i.."speed"..scene,"speed",controlspec.new(-5.0,5.0,"lin",0.01,1,"",0.01/1))
      -- params:add_control(i.."speed"..scene,"speed",controlspec.new(-2.0,2.0,"lin",0.1,0,"",0.1/4))
      
      params:set_action(i.."speed"..scene,function(value) 
        engine.speed(i,value) 
        clock.run(speed_check,value,i,scene)
      end)

      params:add_control(i.."seek"..scene,"seek",controlspec.new(0,1,"lin",0.001,0,"",0.001/1,true))
      params:set_action(i.."seek"..scene,function(value) engine.seek(i,util.clamp(value,0,1)) end)

      -- params:add_control(i.."size"..scene,"size",controlspec.new(0.1,15,"exp",0.01,1,"",0.01/1))
      params:add_control(i.."size"..scene,"size",controlspec.new(0.1,5,"exp",0.01,1,"",0.01/1))
      params:set_action(i.."size"..scene,function(value)
        engine.size(i,util.clamp(value*clock.get_beat_sec()/10,0.001,util.linlin(1,40,1,0.1,params:get(i.."density"..scene))))
      end)
      params:add_control(i.."density"..scene,"density",controlspec.new(1,40,"lin",1,4,"/beat",1/40))
      params:set_action(i.."density"..scene,function(value) engine.density(i,value/(params:get(i.."density_beat_divisor"..scene)*clock.get_beat_sec())) end)
      params:add_control(i.."density_beat_divisor"..scene,"density beat div",controlspec.new(1,16,'lin',1,4,"",1/16))
      params:set_action(i.."density_beat_divisor"..scene,function() 
        local p=params:lookup_param(i.."density"..scene)
        p:bang()
      end)
      params:add_control(i.."density_jitter"..scene,"density jitter",controlspec.new(0,1,"lin",0.1,0,"",1/100))
      params:set_action(i.."density_jitter"..scene,function(value) engine.density_jitter(i,value*params:get(i.."density_jitter_mult"..scene)) end)
      params:add_control(i.."density_jitter_mult"..scene,"density jitter mult",controlspec.new(1,10,"lin",1,1,"",1/10))
      params:set_action(i.."density_jitter_mult"..scene,function(value) engine.density_jitter(i,value*params:get(i.."density_jitter"..scene)) end)
      
      params:add_control(i.."pitch"..scene,"pitch",controlspec.new(-48,48,"lin",0.1,0,"note",1/960))
      params:set_action(i.."pitch"..scene,function(value) engine.pitch(i,math.pow(0.5,-value/12)) end)
      
      params:add_taper(i.."spread_sig"..scene,"spread sig",0,1,0)
      params:set_action(i.."spread_sig"..scene,function(value) engine.spread_sig(i,-value) end)
      
      params:add_taper(i.."spread_sig_offset1"..scene,"spread sig offset 1",0,500,0,5,"ms")
      params:set_action(i.."spread_sig_offset1"..scene,function(value) engine.spread_sig_offset1(i,-value/1000) end)
      
      params:add_taper(i.."spread_sig_offset2"..scene,"spread sig offset 2",0,500,0,5,"ms")
      params:set_action(i.."spread_sig_offset2"..scene,function(value) engine.spread_sig_offset2(i,-value/1000) end)
      
      params:add_taper(i.."spread_sig_offset3"..scene,"spread sig offset 3",0,500,0,5,"ms")
      params:set_action(i.."spread_sig_offset3"..scene,function(value) engine.spread_sig_offset3(i,-value/1000) end)
      
      params:add_taper(i.."jitter"..scene,"jitter",0,500,0,5,"ms")
      params:set_action(i.."jitter"..scene,function(value) engine.jitter(i,value/1000) end)


      params:add_taper(i.."fade"..scene,"compress",150,9000,1000,1)
      params:set_action(i.."fade"..scene,function(value) engine.envscale(i,value/1000) end)

      params:add_control(i.."attack_level"..scene,"attack level",controlspec.new(0,1,"lin",0.01,1,"",0.01/1))
      params:set_action(i.."attack_level"..scene,function(value) 
        engine.gr_envbuf(i,table.unpack(e:get_gr_env_values(i,scene))) 
      end)

      params:add_control(i.."attack_time"..scene,"attack time",controlspec.new(0.01,0.99,"lin",0.01,0.5,"",0.001/1))
      params:set_action(i.."attack_time"..scene,function(value) 
        if params:get(i.."decay_time"..scene) ~= 1-value then
          params:set(i.."decay_time"..scene,1-value) 
        end
        engine.gr_envbuf(i,table.unpack(e:get_gr_env_values(i,scene))) 
      end)
      -- params:set("1attack_time1",0.4)
      params:add_control(i.."decay_time"..scene,"decay time",controlspec.new(0.01,0.99,"lin",0.01,0.5,"",0.001/1))
      params:set_action(i.."decay_time"..scene,function(value) 
        if params:get(i.."attack_time"..scene) ~= 1-value then
          params:set(i.."attack_time"..scene,1-value) 
        end
        engine.gr_envbuf(i,table.unpack(e:get_gr_env_values(i,scene))) 
      end)

      params:add_option(i.."env_shape"..scene,"envelope shape",{"step","lin","sin","wel","squared","cubed"},4)
      params:set_action(i.."env_shape"..scene,function(value) 
        engine.gr_envbuf(i,table.unpack(e:get_gr_env_values(i,scene))) 
      end)
    
      
      
      params:add_control(i.."cutoff"..scene,"filter cutoff",controlspec.new(20,20000,"exp",0,20000,"hz"))
      params:set_action(i.."cutoff"..scene,function(value) engine.cutoff(i,value) end)
      
      params:add_control(i.."q"..scene,"filter rq",controlspec.new(0.01,1.0,"exp",0.01,0.1,"",0.01/1))
      params:set_action(i.."q"..scene,function(value) engine.q(i,value) end)

      params:add_control(i.."pan"..scene,"pan",controlspec.new(-1,1,"lin",0.01,0,"",0.01/1))
      params:set_action(i.."pan"..scene,function(value) engine.pan(i,value) end)

      params:add_taper(i.."spread_pan"..scene,"spread pan",0,100,0,0,"%")
      params:set_action(i.."spread_pan"..scene,function(value) engine.spread_pan(i,value/100) end)
      
      params:add_control(i.."subharmonics"..scene,"subharmonic vol",controlspec.new(0.00,1.00,"lin",0.01,0))
      params:set_action(i.."subharmonics"..scene,function(value) engine.subharmonics(i,value) end)
      
      params:add_control(i.."overtones"..scene,"overtone vol",controlspec.new(0.00,1.00,"lin",0.01,0))
      params:set_action(i.."overtones"..scene,function(value) engine.overtones(i,value) end)
      
      -- params:add_text(i.."pattern"..scene,"pattern","")
      -- params:hide(i.."pattern"..scene)
      -- params:set_action(i.."pattern"..scene,function(value)
        -- if granchild_grid~=nil then
        --   granchild_grid:set_steps(i,value)
        -- end
      -- end)
    end
  end

  params:add_group("echo",(8*e.num_scenes)+1)
  params:add_option("echoscene","scene",e.scene_labels,1)
  params:set_action("echoscene",function(scene)
    for _,param_name in ipairs(e.param_list_echo) do
      for i=1,e.num_scenes do
        if i~=scene then
          params:hide(param_name..i)
        end
      end
      params:show(param_name..scene)
      local p=params:lookup_param(param_name..scene)
      p:bang()
    end
    e:bang(nil,scene,3)
    eglut:rebuild_params()
  end)
  for scene=1,e.num_scenes do
    -- effect controls
    -- echo output volume
    params:add_control("echo_volume"..scene,"*".."echo output volume",controlspec.new(0.0,1.0,"lin",0,0.5,""))
    params:set_action("echo_volume"..scene,function(value) engine.echo_volume(value) end)
    -- echo time
    params:add_control("echo_time"..scene,"*".."echo time",controlspec.new(0,60.0,"lin",0.01,2.00,"",1/6000))
    params:set_action("echo_time"..scene,function(value) engine.echo_time(value) end)
    -- echo size
    params:add_control("echo_size"..scene,"*".."echo size",controlspec.new(0.1,5.0,"lin",0.01,2.00,"",1/500))
    params:set_action("echo_size"..scene,function(value) engine.echo_size(value) end)
    -- dampening
    params:add_control("echo_damp"..scene,"*".."echo damp",controlspec.new(0.0,1.0,"lin",0.01,0.10,""))
    params:set_action("echo_damp"..scene,function(value) engine.echo_damp(value) end)
    -- diffusion
    params:add_control("echo_diff"..scene,"*".."echo diff",controlspec.new(0.0,1.0,"lin",0.01,0.707,""))
    params:set_action("echo_diff"..scene,function(value) engine.echo_diff(value) end)
    -- feedback
    params:add_control("echo_fdbk"..scene,"*".."echo fdbk",controlspec.new(0.00,1.0,"lin",0.01,0.20,""))
    params:set_action("echo_fdbk"..scene,function(value) engine.echo_fdbk(value) end)
    -- mod depth
    params:add_control("echo_mod_depth"..scene,"*".."echo mod depth",controlspec.new(0.0,1.0,"lin",0.01,0.00,""))
    params:set_action("echo_mod_depth"..scene,function(value) engine.echo_mod_depth(value) end)
    -- mod rate
    params:add_control("echo_mod_freq"..scene,"*".."echo mod freq",controlspec.new(0.0,10.0,"lin",0.01,0.10,"hz"))
    params:set_action("echo_mod_freq"..scene,function(value) engine.echo_mod_freq(value) end)
  end
  
  params:add_group("sync voice/scene params",7)
  e.all_param_ids = e.table_concat(e.param_list,e.param_list_echo,e.start_scene_params_at)
  e.all_param_names=e.id_to_name(e.all_param_ids)
  table.insert(e.all_param_ids,1,"sample_mode")
  table.insert(e.all_param_ids,2,"sample")
  table.insert(e.all_param_names,1,"sample mode")
  table.insert(e.all_param_names,2,"sample")
  params:add_number("sync_voice_selector","sync from voice",1,e.num_voices,1)
  params:add_option("sync_scene_selector","sync from scene",e.scene_labels,1)
  params:add_number("sync_voice_selector_to","sync to voice",1,e.num_voices,1)
  params:add_option("sync_scene_selector_to","sync to scene",e.scene_labels,1)
  params:add_trigger("sync_all","sync all params")
  params:set_action("sync_all",function() 
    local voice_from=params:get("sync_voice_selector")
    local scene_from=params:get("sync_scene_selector")
    local voice_to=params:get("sync_voice_selector_to")
    local scene_to=params:get("sync_scene_selector_to")
    for i=1,#e.all_param_ids do
      local param=e.all_param_ids[i]
      if i >= e.start_scene_params_at then
        local value_to_sync=params:get(voice_from..param..scene_from)    
        params:set(voice_to..param..scene_to,value_to_sync)
        -- print(voice_to..param..scene_to,value_to_sync)
      else
        -- print(voice_to..param,value_to_sync)
        local value_to_sync=params:get(voice_from..param)    
        params:set(voice_to..param,value_to_sync)
      end
    end
  end)
  params:add_option("sync_selector","sync one",e.all_param_names)
  params:add_trigger("sync_selected","sync selected param")
  params:set_action("sync_selected",function() 
    local selected_param=e.all_param_ids[params:get("sync_selector")]
    local voice_from=params:get("sync_voice_selector")
    local scene_from=params:get("sync_scene_selector")
    local voice_to=params:get("sync_voice_selector_to")
    local scene_to=params:get("sync_scene_selector_to")
    if params:get("sync_selector") >= e.start_scene_params_at then
      local value_to_sync=params:get(voice_from..selected_param..scene_from)
      params:set(voice_to..selected_param..scene_to,value_to_sync)
      -- print(selected_param,voice_from,scene_from,voice_to,scene_to,value_to_sync)
    else
      local value_to_sync=params:get(voice_from..selected_param)
      params:set(voice_to..selected_param,value_to_sync)
    end
  end)
  
  params:add_option("e.speed_magnets","speed magnets",{"off","on"},2)
  
  -- hide scenes 2-4 initially
  for i=1,e.num_voices do
    -- print("e.param_list",e.param_list)
    for _,param_name in ipairs(e.param_list) do
      -- print(param_name)
      for j=e.start_scene_params_at,e.num_scenes do
        -- tab.print(i..param_name..j)
        params:hide(i..param_name..j)
      end
    end
  end
  for _,param_name in ipairs(e.param_list_echo) do
    for i=2,e.num_scenes do
      params:hide(param_name..i)
    end
  end

  self:bang(1,1)
  clock.run(e.init_active_echo)
  e.inited=true
end

function e.init_active_echo()
  clock.sleep(0.5)
  local scene=params:get("echoscene")
  for _,param_name in ipairs(e.param_list_echo) do
    local p=params:lookup_param(param_name..scene)
    if p.t~=6 then 
      p:bang() 
    end
  end
end

function e:cleanup()
  print("eglut cleanup")
end


return e


