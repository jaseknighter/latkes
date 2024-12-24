Lattice = require "lattice"
Sequins = require "sequins"

local e={}

e.inited = false
e.all_param_ids   = {} 
e.all_param_names = {}
e.speed_magnets={-2,-1.5,-1,-0.5,0,0.5,1,1.5,2}

-- IMPORTANT: start_scene_params_at should be equal to the number
-- of voice-only params
MIN_SAMPLE_LENGTH = 1
MAX_GRAIN_SIZE = 5
e.start_scene_params_at = 10
e.param_list={
  "voice_params",
  "sample_start",
  "sample_length",
  "sample_mode",
  "sample",
  "live_rec_level",
  "live_pre_level",
  "mix_live_rec",
  "scene_params",
  "play",
  "volume","send","ptr_delay","speed","seek","size",
  "density","density_beat_divisor","density_phase_sync","density_phase_sync_one_shot",
  "pitch","spread_sig",
  "spread_sig_offset1","spread_sig_offset2","spread_sig_offset3",
  "jitter",
  "fade","attack_time","decay_time","env_shape",
  "cutoff","q","pan","spread_pan",
  "subharmonics","overtones","overtone1","overtone2"
}
e.param_list_echo={"echo_volume","echo_mod_freq","echo_mod_depth","echo_fdbk","echo_diff","echo_damp","echo_size","echo_time"}
e.num_voices=4
e.num_scenes=4
e.scene_labels={"a","b","c","d"}
e.active_scenes={}
for i=1,e.num_voices do
  e.active_scenes[i]=1
end

function e.enc_debouncer(callback,debounce_time)
  -- if debounce_time then print("deb",debounce_time) end
  callback()
  -- debounce_time = debounce_time or 0.1
  -- if enc_debouncing == false then
  --   enc_debouncing = true
  --   callback()
  --   clock.sleep(debounce_time)
  --   enc_debouncing = false
  -- else
  --   -- print("debouncing...skip...")
  -- end
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


function e:init(sample_selected_callback, num_voices, num_scenes,min_live_buffer_length,max_buffer_length)
  self.sample_selected_callback = sample_selected_callback
  self.num_voices = num_voices or self.num_voices
  self.num_scenes = num_scenes or self.num_scenes
  self.min_live_buffer_length = min_live_buffer_length or 0.1
  self.max_buffer_length = max_buffer_length or 80
  
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
        else
          p=params:lookup_param(i..param_name)
        end
        if p and p.t~=6 then p:bang() end
      end
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
  -- local attack_level = params:get(voice.."attack_level"..scene)
  local attack_level = 1
  local attack_time = params:get(voice.."attack_time"..scene)
  local decay_time = params:get(voice.."decay_time"..scene)
  local shape = params:get(voice.."env_shape"..scene)
  -- local attack_shape = params:get(voice.."env_shape_attack"..scene)
  -- local decay_shape = params:get(voice.."env_shape_decay"..scene)
  local size = params:get(voice.."size"..scene)
  return {attack_level, attack_time, decay_time, shape, size}
  -- return {attack_level, attack_time, decay_time, attack_shape, decay_shape, size}
end

local function update_grain_envelope(i,scene)
  local function callback_func()
    engine.gr_envbuf(i,table.unpack(e:get_gr_env_values(i,scene))) 
  end
  clock.run(e.enc_debouncer,callback_func,0.1)
end 



-- param stuff
function e:rebuild_params()
  -- if _menu.rebuild_params~=nil then
  if self.inited then
    _menu.rebuild_params()
  end
end

function e:load_file(voice,scene,file)
  local sample_start = params:get(voice.."sample_start")
  local sample_length = params:get(voice.."sample_length")
  engine.read(voice,file,sample_start,sample_length)
  local mix_live_rec = params:get(voice.."mix_live_rec")
  if mix_live_rec == 1 then
    osc.send( { "localhost", 57120 }, "/sc_eglut/live_rec_level",{0,voice-1})
  end

  e:on_sample_selected(voice,scene,file)
end

function e:granulate_live(voice)
  local sample_start = params:get(voice.."sample_start")
  local sample_length = params:get(voice.."sample_length")
  osc.send( { "localhost", 57120 }, "/sc_osc/granulate_live",{voice-1, sample_start, sample_length})
  local mix_live_rec = params:get(voice.."mix_live_rec")
  if mix_live_rec == 1 then
    local live_rec_level = params:get(voice.."live_rec_level")
    osc.send( { "localhost", 57120 }, "/sc_eglut/live_rec_level",{live_rec_level,voice-1})
  end
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
  params:add_separator("voices")
  
  ------------------- per voice params -------------------
  for i=1,e.num_voices do
    params:add_group("voice "..i,((#e.param_list-e.start_scene_params_at)*e.num_scenes))
    params:add_separator(i.."voice_params","per voice params")
    params:add_option(i.."scene","scene",e.scene_labels,1)
    params:set_action(i.."scene",function(scene)
      scene=scene and scene or 1
      e:update_scene(i,scene)
    end)
    params:add_control(i.."sample_start","sample start",controlspec.new(0,self.max_buffer_length,"lin",0.01,0,"s",0.01/self.max_buffer_length))
    params:set_action(i.."sample_start",function(value)
      if value + params:get(i.."sample_length") > self.max_buffer_length then 
        params:set(i.."sample_start", self.max_buffer_length - params:get(i.."sample_length"))
      end
      -- local sample_mode = params:get(i.."sample_mode")
      -- local show_waveform_ix = sample_mode < 3 and (i * 2 - 1) or (i * 2)
      -- local show_waveform_name = waveform_names[show_waveform_ix]
      -- waveforms[show_waveform_name]:clear_samples()
  
      local function callback_func()
        local sample_start = params:get(i.."sample_start")
        local sample_length = params:get(i.."sample_length")
        osc.send( { "localhost", 57120 }, "/sc_osc/set_sample_position",{i-1, sample_start,sample_length})
        
        if params:get(i.."sample_mode") == 3 then
          -- set_sample_duration(i,)
          on_eglut_file_loaded(i)
        end
      end
      -- callback_func()
      clock.run(e.enc_debouncer,callback_func,0.1)        
    end)
    -- params:add_control(i.."sample_length","sample length",controlspec.new(0.1,self.max_buffer_length,"exp",0.1,10,"s",0.1/self.max_buffer_length))
    params:add_control(i.."sample_length","sample length",controlspec.new(MIN_SAMPLE_LENGTH,self.max_buffer_length,"lin",0.1,10,"s",0.01/self.max_buffer_length))
    params:set_action(i.."sample_length",function(value)
      if value + params:get(i.."sample_start") > self.max_buffer_length then 
        params:set(i.."sample_length", self.max_buffer_length - params:get(i.."sample_start"))
      end
      -- local sample_mode = params:get(i.."sample_mode")
      -- local show_waveform_ix = sample_mode < 3 and (i * 2 - 1) or (i * 2)
      -- local show_waveform_name = waveform_names[show_waveform_ix]
      -- waveforms[show_waveform_name]:clear_samples()
  
      local function callback_func()
        local sample_start = params:get(i.."sample_start")
        local sample_length = params:get(i.."sample_length")
        osc.send( { "localhost", 57120 }, "/sc_osc/set_sample_position",{i-1, sample_start,sample_length})            
        
        if params:get(i.."sample_mode") == 3 then
          -- set_sample_duration(i,)
          on_eglut_file_loaded(i)
        end
      end
      -- callback_func()
      clock.run(e.enc_debouncer,callback_func,0.1)        
    end)
    local sample_modes={"off","live stream","recorded"}
    params:add_option(i.."sample_mode","sample mode",sample_modes,i==1 and 2 or 1)
    params:set_action(i.."sample_mode",function(mode)
      local mode_ix
      if sample_modes[mode]=="off" then
        mode_ix = 0
        params:set(i.."play"..params:get(i.."scene"),1)
        print("off",i,params:get(i.."scene"))
      elseif sample_modes[mode]=="live stream" then
        mode_ix = 1
        params:set(i.."play"..params:get(i.."scene"),2)
        self:granulate_live(i)
      elseif sample_modes[mode]=="recorded" then
        local recorded_file = params:get(i.."sample")
        mode_ix = 2
        if recorded_file ~= "-" then
          e:load_file(i,e.active_scenes[i],recorded_file)            
          params:set(i.."play"..params:get(i.."scene"),2)
        else
          print("no file selected to granulate")
          params:set(i.."play"..params:get(i.."scene"),1)
          -- params:set(i.."play"..params:get(i.."scene"),1)
        end
      end
      osc.send( { "localhost", 57120 }, "/sc_osc/set_mode",{i-1, mode_ix})
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
      osc.send( { "localhost", 57120 }, "/sc_eglut/live_rec_level",{value,i-1})
    end)
    params:add_control(i.."live_pre_level","live pre level",controlspec.new(0,1,"lin",0.01,0))
    params:set_action(i.."live_pre_level",function(value) 
      osc.send( { "localhost", 57120 }, "/sc_eglut/live_pre_level",{value,i-1})
    end)

    params:add_trigger(i.."swap_live_pre","swap live/pre levels")
    params:set_save(i.."swap_live_pre",0)
    params:set_action(i.."swap_live_pre",function(value) 
      local live = params:get(i.."live_rec_level")
      local pre = params:get(i.."live_pre_level")
      params:set(i.."live_rec_level",pre)
      params:set(i.."live_pre_level",live)
    end)

    params:add_option(i.."mix_live_rec","mix live+rec",{"off","on"},1)
  
    ------------------- per scene params -------------------

    params:add_separator(i.."scene_params","per scene params")
    for scene=1,e.num_scenes do
      params:add_option(i.."play"..scene,"play",{"off","on"},i==1 and 2 or 1)
      params:set_action(i.."play"..scene,function(x) 
        if params:get(i.."sample_mode") > 1 then
          engine.gate(i,x-1) 
        else
          engine.gate(i,0) 
        end
      end)

      params:add_control(i.."volume"..scene,"volume",controlspec.new(0,10.0,"lin",0.05,1,"",0.05/10))
      params:set_action(i.."volume"..scene,function(value)
        engine.gain(i,value)
      end)

      -- params:add_control(i.."dry_wet"..scene,"dry-grain",controlspec.new(-1, 1, 'lin', 0, 1, ""))
      -- params:set_action(i.."dry_wet"..scene,function(value)
      --   engine.dry_wet(i,value)        
      -- end)

      params:add_control(i.."send"..scene,"effect send",controlspec.new(0.0,1.0,"lin",0.01,1))
      params:set_action(i.."send"..scene,function(value) engine.send(i,value) end)

      params:add_control(i.."ptr_delay"..scene,"pointer sync-delay",controlspec.new(0,2,"lin",0.001,0.2,"",0.01/2))
      params:set_action(i.."ptr_delay"..scene,function(value) 
        -- params:set(i.."speed"..scene,1)
        engine.ptr_delay(i,value) 
        
      end)
      -- params:add_control(i.."ptr_delay"..scene,"delay",controlspec.new(0.05,2,"lin",0.001,0.2,"",0.05/2))
      -- params:set_action(i.."ptr_delay"..scene,function(value) engine.ptr_delay(i,1.29) end)
      
      
      local function speed_check(speed,voice,scene)
        -- clock.sleep(0.1)
        for i=1,#e.speed_magnets do
          if speed ~= e.speed_magnets[i] and speed-0.1 < e.speed_magnets[i] and speed+0.1 > e.speed_magnets[i] then
            params:set(voice.."speed"..scene,e.speed_magnets[i])
            break
          end
          
        end
      end
      params:add_control(i.."speed"..scene,"speed",controlspec.new(-5.0,5.0,"lin",0.01,1,"",0.01/1))
      -- params:add_control(i.."speed"..scene,"speed",controlspec.new(-2.0,2.0,"lin",0.1,0,"",0.1/4))
      
      params:set_action(i.."speed"..scene,function(value) 
        local function callback_func()
          engine.speed(i,value) 
        end
        clock.run(e.enc_debouncer,callback_func,0.1)        
        -- clock.run(speed_check,value,i,scene)
        speed_check(value,i,scene)
      end)

      params:add_control(i.."seek"..scene,"seek",controlspec.new(0,1,"lin",0.001,0,"",0.001/1,true))
      params:set_action(i.."seek"..scene,function(value) 
        local function callback_func()
          engine.seek(i,util.clamp(value,0,1)) 
        end
        clock.run(e.enc_debouncer,callback_func,0.1)        
      end)

      -- note the size values sent to SuperCollider are  1/10 the value of the parameter
      params:add_control(i.."size"..scene,"size",controlspec.new(0.1,MAX_GRAIN_SIZE,"exp",0.01,1,"",0.01/10))
      params:set_action(i.."size"..scene,function(value)
        local function callback_func()
          local bs = clock.get_beat_sec()
          local max_density = 40/params:get(i.."density_beat_divisor"..scene)
          local current_density = params:get(i.."density"..scene)/params:get(i.."density_beat_divisor"..scene)
          local max_size = util.explin(1,max_density,1,0.1,current_density)
          engine.size(i,util.clamp(
            (value/10)*clock.get_beat_sec(),    -- original size
            bs*0.001,                           --min size
            bs*max_size)                        --max size from 0.1 to 1 based on density
          )
        end
        clock.run(e.enc_debouncer,callback_func,0.1)
      end)

      params:add_control(i.."density"..scene,"density",controlspec.new(1,40,"lin",0.1,4,"/beat",1/400))
      params:set_action(i.."density"..scene,function(value) 
        local function callback_func()
          engine.density(i,value/(params:get(i.."density_beat_divisor"..scene)*clock.get_beat_sec())) 
        end
        clock.run(e.enc_debouncer,callback_func,0.1)        
        local p=params:lookup_param(i.."size"..scene)
        p:bang()
      end)
      params:add_control(i.."density_beat_divisor"..scene,"density beat div",controlspec.new(1,16,'lin',1,1,"",1/16))
      params:set_action(i.."density_beat_divisor"..scene,function() 
        local p=params:lookup_param(i.."density"..scene)
        p:bang()
      end)
      params:add_trigger(i.."density_phase_sync_one_shot"..scene,"density phase sync 1shot")
      params:set_action(i.."density_phase_sync_one_shot"..scene,function() 
        print("sync_density_phases_one_shot",i-1)
        osc.send( { "localhost", 57120 }, "/sc_osc/sync_density_phases_one_shot",{i-1})
      end)

      params:add_option(i.."density_phase_sync"..scene,"density phase sync",{"off","on"},1)
      params:set_action(i.."density_phase_sync"..scene,function(x)
        osc.send( { "localhost", 57120 }, "/sc_osc/sync_density_phases",{i-1,x-1})
      end)
      
      params:add_control(i.."pitch"..scene,"pitch",controlspec.new(-48,48,"lin",0.1,0,"note",1/960))
      params:set_action(i.."pitch"..scene,function(value) 
        local function callback_func()
          engine.pitch(i,math.pow(0.5,-value/12)) 
        end
        clock.run(e.enc_debouncer,callback_func,0.1)        
      end)
      
      params:add_taper(i.."spread_sig"..scene,"spread sig",0,1,0)
      params:set_action(i.."spread_sig"..scene,function(value) 
        local function callback_func()
          engine.spread_sig(i,-value) 
        end
        clock.run(e.enc_debouncer,callback_func,0.1)        
      end)
      
      params:add_taper(i.."spread_sig_offset1"..scene,"spread sig offset 1",0,500,0,5,"ms")
      params:set_action(i.."spread_sig_offset1"..scene,function(value) 
        local function callback_func()
          engine.spread_sig_offset1(i,-value/1000) 
        end
        clock.run(e.enc_debouncer,callback_func,0.1)        
      end)
      
      params:add_taper(i.."spread_sig_offset2"..scene,"spread sig offset 2",0,500,0,5,"ms")
      params:set_action(i.."spread_sig_offset2"..scene,function(value) 
        local function callback_func()
          engine.spread_sig_offset2(i,-value/1000) 
        end
        clock.run(e.enc_debouncer,callback_func,0.1)        
      end)
      
      params:add_taper(i.."spread_sig_offset3"..scene,"spread sig offset 3",0,500,0,5,"ms")
      params:set_action(i.."spread_sig_offset3"..scene,function(value) 
        local function callback_func()
          engine.spread_sig_offset3(i,-value/1000) 
        end
        clock.run(e.enc_debouncer,callback_func,0.1)        
      end)
      
      params:add_taper(i.."jitter"..scene,"jitter",0,500,0,5,"ms")
      params:set_action(i.."jitter"..scene,function(value) 
        local function callback_func()
          engine.jitter(i,value/1000) 
        end
        clock.run(e.enc_debouncer,callback_func,0.1)        
      end)


      params:add_taper(i.."fade"..scene,"compress",150,9000,1000,1)
      params:set_action(i.."fade"..scene,function(value) 
        local function callback_func()
          engine.envscale(i,value/1000) 
        end
        clock.run(e.enc_debouncer,callback_func,0.1)        
      end)
      
      -- params:add_control(i.."attack_level"..scene,"attack level",controlspec.new(0,1,"lin",0.01,1,"",0.01/1))
      -- params:set_action(i.."attack_level"..scene,function(value) 
      --   update_grain_envelope(i,scene)
      -- end)

      params:add_control(i.."attack_time"..scene,"attack time",controlspec.new(0.01,0.99,"lin",0.01,0.5,"",0.001/1))
      params:set_action(i.."attack_time"..scene,function(value) 
        if params:get(i.."decay_time"..scene) ~= 1-value then
          params:set(i.."decay_time"..scene,1-value) 
        end
        -- if params:get(i.."env_shape_attack"..scene)==1 and value > 0.9 then 
        --   params:set(i.."attack_time"..scene,0.9) 
        -- end
        
        local function callback_func()
          update_grain_envelope(i,scene)
        end
        clock.run(e.enc_debouncer,callback_func,0.1)        
      end)
      -- params:set("1attack_time1",0.4)
      params:add_control(i.."decay_time"..scene,"decay time",controlspec.new(0.01,0.99,"lin",0.01,0.5,"",0.001/1))
      params:set_action(i.."decay_time"..scene,function(value) 
        if params:get(i.."attack_time"..scene) ~= 1-value then
          params:set(i.."attack_time"..scene,1-value) 
        end
        
        local function callback_func()
          update_grain_envelope(i,scene)
        end
        clock.run(e.enc_debouncer,callback_func,0.1)        
      end)
      
      params:add_option(i.."env_shape"..scene,"env shape",{"exp","squared","lin","sin","wel","cubed"},4)
      params:set_action(i.."env_shape"..scene,function(value) 
        
        local function callback_func()
          update_grain_envelope(i,scene)
        end
        clock.run(e.enc_debouncer,callback_func,0.1)        
      end)
  
      params:add_control(i.."cutoff"..scene,"filter cutoff",controlspec.new(20,20000,"exp",0,20000,"hz"))
      params:set_action(i.."cutoff"..scene,function(value) 
        local function callback_func()
          engine.cutoff(i,value) 
        end
        clock.run(e.enc_debouncer,callback_func,0.1)        
      end)
      
      params:add_control(i.."q"..scene,"filter rq",controlspec.new(0.01,1.0,"exp",0.01,0.2,"",0.01/1))
      params:set_action(i.."q"..scene,function(value) 
        local function callback_func()
          engine.q(i,value) 
        end
        clock.run(e.enc_debouncer,callback_func,0.1)        
      end)

      params:add_control(i.."pan"..scene,"pan",controlspec.new(-1,1,"lin",0.01,0,"",0.01/1))
      params:set_action(i.."pan"..scene,function(value) engine.pan(i,value) end)

      params:add_taper(i.."spread_pan"..scene,"spread pan",0,100,0,0,"%")
      params:set_action(i.."spread_pan"..scene,function(value) engine.spread_pan(i,value/100) end)
      
      params:add_control(i.."subharmonics"..scene,"subharmonic vol",controlspec.new(0.00,1.00,"lin",0.01,0))
      params:set_action(i.."subharmonics"..scene,function(value) engine.subharmonics(i,value) end)
      
      params:add_control(i.."overtones"..scene,"overtones vol",controlspec.new(0.00,1.00,"lin",0.01,0))
      params:set_action(i.."overtones"..scene,function(value) engine.overtones(i,value) end)

      params:add_control(i.."overtone1"..scene,"overtone 1 pitch",controlspec.new(1.00,4.00,"lin",1,2))
      params:set_action(i.."overtone1"..scene,function(value) engine.overtone1(i,value) end)

      params:add_control(i.."overtone2"..scene,"overtone 2 pitch",controlspec.new(1.00,4.00,"lin",1,4))
      params:set_action(i.."overtone2"..scene,function(value) engine.overtone2(i,value) end)
      
      -- params:add_text(i.."pattern"..scene,"pattern","")
      -- params:hide(i.."pattern"..scene)
      -- params:set_action(i.."pattern"..scene,function(value)
        -- if granchild_grid~=nil then
        --   granchild_grid:set_steps(i,value)
        -- end
      -- end)
    end
  end

  params:add_group("echo",(8*e.num_scenes)+3)
  params:add_option("effects_on","echo on",{"off","on"},1)
  params:set_action("effects_on",function(value) engine.effects_on(value) end)
  params:add_control("global_send","global effect send",controlspec.new(0.0,1.0,"lin",0.01,1))
  params:set_action("global_send",function(value) 
    for voice=1,e.num_voices do
      for scene=1,e.num_scenes do
        params:set(voice.."send"..scene,value)
      end
    end
  end)

  params:add_option("echoscene","echo scene",e.scene_labels,1)
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
  -- clock.run(e.init_active_echo)
  e.inited=true
end

-- function e.init_active_echo()
--   clock.sleep(0.5)
--   local scene=params:get("echoscene")
--   for _,param_name in ipairs(e.param_list_echo) do
--     local p=params:lookup_param(param_name..scene)
--     if p.t~=6 then 
--       p:bang() 
--     end
--   end
-- end

function e:cleanup()
  print("eglut cleanup")
end


return e


