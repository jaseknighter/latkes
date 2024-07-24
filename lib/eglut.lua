Lattice = require "lattice"
Sequins = require "sequins"
local e={}
e.inited = false
e.divisions={1,2,4,6,8,12,16}
e.division_names={"2 wn","wn","hn","hn-t","qn","qn-t","eighth"}
e.all_param_ids   = {} 
e.all_param_names = {}
e.speed_magnets={-2,-1.5,-1,-0.5,0,0.5,1,1.5,2}

-- e.param_list_old={
--   "lfos","param_value","config_lfo","config_lfo_status",
--   "lfo_period","lfo_range_min_number","lfo_range_min_control","lfo_range_max_number",
--   "lfo_range_max_control","grain_params",
--   "overtoneslfo","subharmonicslfo","cutofflfo","sizelfo","densitylfo","speedlfo","volumelfo",
--   "spread_panlfo","spread_siglfo","jitterlfo",
--   "overtones","subharmonics","spread_sig_offset1","spread_sig_offset2","spread_sig_offset3",
--   "spread_pan","jitter","spread_sig","size","density_sync_external",
--   "pos","q","division","speed","send","cutoff","env_shape","decay_time","attack_time",
--   "attack_level","fade","pitch","pitch_sync_external","density","density_beat_divisor","pan","volume","seek","play"}

e.param_list={
  "lfos","param_value","config_lfo","config_lfo_status",
  "lfo_period","lfo_range_min_number","lfo_range_min_control","lfo_range_max_number",
  "lfo_range_max_control","grain_params",
  -- "pos",
  "play","volume","volumelfo","ptr_delay","speed","speedlfo","seek","seeklfo",
  "size","sizelfo","density","density_beat_divisor","density_sync_external","densitylfo",
  "pitch","pitch_sync_external","spread_sig","spread_siglfo",
  "spread_sig_offset1","spread_sig_offset2","spread_sig_offset3",
  "jitter","jitterlfo",
  "fade","attack_level","attack_time","decay_time","env_shape",
  "cutoff","cutofflfo","q","send","division","pan","spread_pan","spread_panlfo",
  "subharmonics","subharmonicslfo","overtones","overtoneslfo",
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
      e.sequins["density"][i][j]=Sequins{1,2,4,8}
      e.sprockets["density"][i][j] = e.lattice:new_sprocket{
        action = function(t)
          local next_seq=e.sequins["density"][i][j]()
          -- if i==1 and j==1 then
          if j==1 then
            params:set(i.."density"..j,next_seq)
            -- print("density",i,j,next_seq)
          end
        end,
        division = 1/4,
        enabled = i==1 and true or false
      }
    end
  end
  self.lattice.enabled=true
  self.lattice:start()
end


function e:init(sample_selected_callback)
  self.sample_selected_callback = sample_selected_callback
  
end

function e:on_sample_selected(voice,scene,file)
  self.sample_selected_callback(voice,file)
end

function e:bang(scene, bangscope)
  bangscope = bangscope or 1
  if bangscope < 3 then
    for i=1,e.num_voices do
      for _,param_name in ipairs(e.param_list) do
        local p=params:lookup_param(i..param_name..scene)
        if p.t~=6 then p:bang() end
      end
      -- local p=params:lookup_param(i.."pattern"..scene)
      -- p:bang()
    end
  end
  if bangscope ~= 2 then
    for _,param_name in ipairs(e.param_list_echo) do
      local p=params:lookup_param(param_name..scene)
      if p.t~=6 then p:bang() end
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

-- lfo stuff

-- lfo refreshing
e.lfo_refresh=metro.init()
e.lfo_refresh.time=0.1
e.lfo_refresh.event=function()
  e:update_lfos() -- use this metro to update lfos
end
 
mod_parameters={
  {p_type="control",id="size",name="size",range={0.2,4,0.2,4},lfo=24/58},
  {p_type="number",id="density",name="density",range={3,16,3,16},lfo=16/24},
  {p_type="control",id="speed",name="speed",range={-2.0,2.0,-2.0,2.0},lfo=16/24},
  {p_type="control",id="seek",name="seek",range={0,1,0,1},lfo=16/24},
  {p_type="number",id="jitter",name="jitter",range={15,200,15,200},lfo=32/64},
  {p_type="control",id="volume",name="volume",range={0,1,0,1},lfo=16/24},
  {p_type="number",id="spread_pan",name="spread pan",range={0,100,0,100},lfo=16/24},
  {p_type="number",id="spread_sig",name="spread sig",range={0,500,0,500},lfo=16/24},
  {p_type="number",id="cutoff",name="filter cutoff",range={500,2000,500,2000},lfo=16/24},
  {p_type="control",id="subharmonics",name="subharmonics",range={0,1,0,1},lfo=24/70},
  {p_type="control",id="overtones",name="overtones",range={0,0.2,0,0.2},lfo=36/60},
}


mod_param_names={}
for i,mod in ipairs(mod_parameters) do
  table.insert(mod_param_names,mod.name)
end

e.mod_param_vals={}
e.mod_params_dyn={}
e.active_mod_param_ix={}

for i=1,e.num_voices do
  e.mod_params_dyn[i]={}
  e.active_mod_param_ix[i]={}
  for j=1,e.num_scenes do
    e.active_mod_param_ix[i][j]=1
    e.mod_params_dyn[i][j]=deep_copy(mod_parameters)
  end
end
dyn=e.mod_params_dyn

function e:update_lfos()
  if e.inited == true then
    for i=1,e.num_voices do
      e.mod_param_vals[i]={}
      for j=1,e.num_scenes do
        e.mod_param_vals[i][j]={}
        for k,mod in ipairs(e.mod_params_dyn[i][j]) do
          local range={mod.range[3],mod.range[4]}
          local period=params:get(i.."lfo_period"..j)
          e.mod_param_vals[i][j][k]={id=mod.id,minmax=minmax,range=range,period=period,offset=1}--math.random()*30}

          local active_ix=e.active_mod_param_ix[i][j]
          if k==active_ix then
            local lfo_val = params:get(i..mod.id..j)
            params:set(i.."param_value"..j,lfo_val)
          end
        end
      end
      local scene=params:get(i.."scene")
      if params:get(i.."play"..scene)==2 then
        for j,k in ipairs(e.mod_param_vals[i][scene]) do
          if params:get(i..k.id.."lfo"..scene)==2 then
            local lfo_raw_val=self:calculate_lfo(k.period,k.offset)
            local lfo_scaled_val=util.clamp(
              util.linlin(
                -1,1,
                k.range[1],
                k.range[2],
                lfo_raw_val
              ), 
              k.range[1],k.range[2]
            )
            params:set(i..k.id..scene,lfo_scaled_val)
          end
        end
      end
    end
  end
end


function e:calculate_lfo(period_in_beats,offset)
  if period_in_beats==0 then
    return 1
  else
    local lfo_calc=math.sin(2*math.pi*clock.get_beats()/period_in_beats+offset)
    return lfo_calc
  end
end

-- param stuff
function e:rebuild_params()
  -- if _menu.rebuild_params~=nil then
  if self.inited then
    _menu.rebuild_params()
  end
end

function e:load_file(voice,scene,file)
  engine.read(voice,file)
  e:on_sample_selected(voice,scene,file)
end

function e:granulate_live(voice)
  osc.send( { "localhost", 57120 }, "/sc_osc/granulate_live",{voice-1})
end

function e:update_scene(voice,scene)
  e.active_scenes[voice]=scene
  for _,param_id in ipairs(e.param_list) do
    for i=1,e.num_scenes do
      if i~=scene then
        params:hide(voice..param_id..(i))
        -- params:hide(voice..param_id..(3-scene))
      end
    end
    params:show(voice..param_id..scene)
    -- local p=params:lookup_param(i..param_id..scene)
    -- p:bang()
    local lfo_ix = e.active_mod_param_ix[voice][scene]
    local lfo = mod_parameters[lfo_ix]
    if lfo.p_type=="number" then
      params:hide(voice.."lfo_range_min_control"..scene)
      params:hide(voice.."lfo_range_max_control"..scene)
    else
      params:hide(voice.."lfo_range_min_number"..scene)
      params:hide(voice.."lfo_range_max_number"..scene)
    end
end

-- is this one needed????
  e:bang(scene)      
  -- local p=params:lookup_param(i.."pattern"..scene)
  -- p:bang()
  -- if params:get(i.."pattern"..scene)=="" or params:get(i.."pattern"..scene)=="[]" then
    -- granchild_grid:toggle_playing_voice(i,false)
  -- end
  e:rebuild_params()
end

function e:sync_scenes(params_name, sync_all)
  local sync_voice = params:get("sync_voice_selector")
  local sync_scene = params:get("sync_scene_selector")
  local sync_param = params:get("sync_selector")
  local sync_all = params:get("sync_all")
  for i=1,e.num_voices do
    for _,param_name in ipairs(e.param_list) do
      params:hide(i..param_name..e.num_scenes)
    end
    for j=1,e.num_scenes do
      if mod_parameters[1].p_type=="number" then
        params:hide(i.."lfo_range_min_control"..j)
        params:hide(i.."lfo_range_max_control"..j)        
      else
        params:hide(i.."lfo_range_min_number"..j)
        params:hide(i.."lfo_range_max_number"..j)
      end
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
    params:add_group("voice "..i,(#e.param_list*e.num_scenes)-1)
    params:add_option(i.."scene","scene",e.scene_labels,1)
    params:set_action(i.."scene",function(scene)
      scene=scene and scene or 1
      e:update_scene(i,scene)
    end)
    local sample_modes={"off","live stream","recorded"}
    params:add_option(i.."sample_mode","sample mode",sample_modes,1)
    params:set_action(i.."sample_mode",function(mode)
      local function callback_func()
        if sample_modes[mode]=="off" then
          params:set(i.."play"..params:get(i.."scene"),1)
        elseif sample_modes[mode]=="live stream" then
          print("gran live",i)
          params:set("show_waveform",math.ceil(i*2)+1)
          params:set(i.."play"..params:get(i.."scene"),1)
          params:set(i.."play"..params:get(i.."scene"),2)
          self:granulate_live(i)
        elseif sample_modes[mode]=="recorded" then
          local recorded_file = params:get(i.."sample")
          if recorded_file ~= "-" then
            print("gran recorded",i,recorded_file)
            e:load_file(i,e.active_scenes[i],recorded_file)
            params:set("show_waveform",math.ceil(i*2)+2)
            -- params:set(i.."sample"..e.active_scenes[i],recorded_file)
            -- self.sample_selected_callback(i,recorded_file)
          else
            print("no file selected to granulate")
            -- params:set(i.."play"..params:get(i.."scene"),1)
          end
        end
      end
      callback_func()
      -- clock.run(enc_debouncer,callback_func,0.2)
    end)
    params:add_file(i.."sample","sample")
    params:set_action(i.."sample",function(file)
      print("sample ",i,e.active_scenes[i],file)
      if file~="-" then
        e:load_file(i,e.active_scenes[i],file)
      end
    end)
             
    for scene=1,e.num_scenes do

      params:add_separator(i.."lfos"..scene,"lfos")
      params:add_option(i.."config_lfo"..scene,"lfo name",mod_param_names,1)
      params:set_action(i.."config_lfo"..scene,function(value) 
        e.active_mod_param_ix[i][scene] = value
        local range_min, range_max
        local mod_type=mod_parameters[value].p_type
        local range_min_val = e.mod_params_dyn[i][scene][value].range[1]
        local range_max_val = e.mod_params_dyn[i][scene][value].range[2]
        if mod_type == "number" then 
          params:show(i.."lfo_range_min_number"..scene) 
          params:show(i.."lfo_range_max_number"..scene) 
          params:hide(i.."lfo_range_min_control"..scene)
          params:hide(i.."lfo_range_max_control"..scene)
          
          range_min=params:lookup_param(i.."lfo_range_min_number"..scene)
          range_max=params:lookup_param(i.."lfo_range_max_number"..scene)
          
          range_min.name=mod_param_names[value].." range min"
          range_max.name=mod_param_names[value].." range max"
          print(i,scene,value,range_min.min,range_min.max)
          range_min.min=range_min_val
          range_min.max=range_max_val
          range_max.min=range_min_val
          range_max.max=range_max_val    
        else
          params:show(i.."lfo_range_min_control"..scene) 
          params:hide(i.."lfo_range_min_number"..scene)
          params:show(i.."lfo_range_max_control"..scene) 
          params:hide(i.."lfo_range_max_number"..scene)
          
          range_min=params:lookup_param(i.."lfo_range_min_control"..scene)
          range_max=params:lookup_param(i.."lfo_range_max_control"..scene)
          range_min.name=mod_param_names[value].." range min"
          range_max.name=mod_param_names[value].." range max"
          
          range_min.controlspec.minval=range_min_val
          range_min.controlspec.maxval=range_max_val
          range_max.controlspec.minval=range_min_val
          range_max.controlspec.maxval=range_max_val
        end
        local min_range_default = e.mod_params_dyn[i][scene][value].range[3]
        -- min_range_default = min_range_default == nil and e.mod_params_dyn[i][scene][value].range[1] or min_range_default
        if mod_type == "number" then 
          params:set(i.."lfo_range_min_number"..scene,min_range_default)
        else
          params:set(i.."lfo_range_min_control"..scene,min_range_default)
        end

        local max_range_default = e.mod_params_dyn[i][scene][value].range[4]
        -- max_range_default = max_range_default == nil and e.mod_params_dyn[i][scene][value].range[2] or max_range_default
        
        if mod_type == "number" then 
          params:set(i.."lfo_range_max_number"..scene,max_range_default)
        else
          params:set(i.."lfo_range_max_control"..scene,max_range_default)
        end



        local value_param=params:lookup_param(i.."param_value"..scene)
        local status_param=params:lookup_param(i.."config_lfo_status"..scene)
        local period_param=params:lookup_param(i.."lfo_period"..scene)
        value_param.name=mod_param_names[value].." value"
        status_param.name=mod_param_names[value].." lfo status"
        period_param.name=mod_param_names[value].." lfo period"
        
        -- print(i,scene,value,"min_range_default,max_range_default",min_range_default,max_range_default)
        local selected_lfo=i..mod_parameters[e.active_mod_param_ix[i][scene]].id.."lfo"..scene
        params:set(i.."config_lfo_status"..scene,params:get(selected_lfo))
        
        local lfo_period=e.mod_params_dyn[i][scene][value].lfo
        params:set(i.."lfo_period"..scene,lfo_period)
        e:rebuild_params()
      end)
      params:add_control(i.."param_value"..scene,mod_param_names[1].." value",controlspec.new(-100000,100000))
      
      params:add_option(i.."config_lfo_status"..scene,mod_param_names[1].." lfo status",{"off","on"},1)
      params:set_action(i.."config_lfo_status"..scene,function(value) 
        params:set(i..mod_parameters[e.active_mod_param_ix[i][scene]].id.."lfo"..scene,value)
      end)
      
      params:add_number(i.."lfo_period"..scene,mod_param_names[1].." lfo period",1,200,50)
      params:set_action(i.."lfo_period"..scene,function(value) 
        local ix = e.active_mod_param_ix[i][scene];
        local dyn_mod_param = e.mod_params_dyn[i][scene][ix]
        dyn_mod_param.lfo=value
      end)
      params:add_number(i.."lfo_range_min_number"..scene,mod_param_names[1].." range min",15,200,15)
      params:set_action(i.."lfo_range_min_number"..scene,function(value) 
        local min=i.."lfo_range_min_number"..scene
        local max=i.."lfo_range_max_number"..scene
        local max_val=params:get(max)
        if value > max_val then
          params:set(min,max_val)
        end
        local ix = e.active_mod_param_ix[i][scene];
        local dyn_mod_param = e.mod_params_dyn[i][scene][ix]
        if e.inited == true then
          dyn_mod_param.range[3]=value 
        end
      end)
      
      params:add_number(i.."lfo_range_max_number"..scene,mod_param_names[1].." range max",15,200,200)
      params:set_action(i.."lfo_range_max_number"..scene,function(value) 
        local min=i.."lfo_range_min_control"..scene
        local max=i.."lfo_range_max_control"..scene
        local min_val=params:get(min)
        if value < min_val then
          params:set(max,min_val)
        end

        local ix = e.active_mod_param_ix[i][scene];
        local dyn_mod_param = e.mod_params_dyn[i][scene][ix]
        if e.inited == true then 
          -- print("set max",i,scene,value)
          dyn_mod_param.range[4]=value 
        end
      end)


      params:add_control(i.."lfo_range_min_control"..scene,mod_param_names[1].." range min",controlspec.new(0,0.25,"lin",0.01,0))
      params:set_action(i.."lfo_range_min_control"..scene,function(value) 
        local min=i.."lfo_range_min_control"..scene
        local max=i.."lfo_range_max_control"..scene
        local max_val=params:get(max)
        if value > max_val then
          params:set(min,max_val)
        end

        local ix = e.active_mod_param_ix[i][scene];
        local dyn_mod_param = e.mod_params_dyn[i][scene][ix]
        if e.inited == true then
          dyn_mod_param.range[3]=value
        end

      end)
      
      params:add_control(i.."lfo_range_max_control"..scene,mod_param_names[1].." range max",controlspec.new(0,0.25,"lin",0.01,0))
      params:set_action(i.."lfo_range_max_control"..scene,function(value) 
        local min=i.."lfo_range_min_control"..scene
        local max=i.."lfo_range_max_control"..scene
        local min_val=params:get(min)
        if value < min_val then
          params:set(max,min_val)
        end

        local ix = e.active_mod_param_ix[i][scene];
        local dyn_mod_param = e.mod_params_dyn[i][scene][ix]
        if e.inited == true then
          dyn_mod_param.range[4]=value
        end
      end)
      

      params:add_separator(i.."grain_params"..scene,"param values")
      


      params:add_option(i.."play"..scene,"play",{"off","on"},1)
      params:set_action(i.."play"..scene,function(x) engine.gate(i,x-1) end)

      params:add_control(i.."volume"..scene,"volume",controlspec.new(0,1.0,"lin",0.05,1,"vol",0.05/1))
      -- params:add_control(i.."volume"..scene,"volume",controlspec.new(0,1.0,"lin",0.05,0.25,"vol",0.05/1))
      params:set_action(i.."volume"..scene,function(value)
        engine.volume(i,value)
        -- turn off the delay if volume is zero
        if value==0 then
          engine.send(i,0)
        elseif value>0 and old_volume[i]==0 then
          engine.send(i,params:get(i.."send"..scene))
        end
        old_volume[i]=value
      end)
      params:add_option(i.."volumelfo"..scene,"volume lfo",{"off","on"},1)
      params:add_control(i.."ptr_delay"..scene,"delay",controlspec.new(0.01,2,"lin",0.001,0.2,"",0.01/2))
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
      params:add_option(i.."speedlfo"..scene,"speed lfo",{"off","on"},1)
      params:add_control(i.."seek"..scene,"seek",controlspec.new(0,1,"lin",0.001,0,"",0.001/1,true))
      params:set_action(i.."seek"..scene,function(value) engine.seek(i,util.clamp(value,0,1)) end)
      -- params:set_action(i.."seek"..scene,function(value) engine.seek(i,util.clamp(value+params:get(i.."pos"..scene),0,1)) end)
      params:add_option(i.."seeklfo"..scene,"speed lfo",{"off","on"},1)
      -- params:add_control(i.."pos"..scene,"pos",controlspec.new(-1/40,1/40,"lin",0.001,0))
      -- params:set_action(i.."pos"..scene,function(value) engine.seek(i,util.clamp(value+params:get(i.."seek"..scene),0,1)) end)

      params:add_control(i.."size"..scene,"size",controlspec.new(0.1,15,"exp",0.01,1,"",0.01/1))
      params:set_action(i.."size"..scene,function(value)
        engine.size(i,util.clamp(value*clock.get_beat_sec()/10,0.001,util.linlin(1,40,1,0.1,params:get(i.."density"..scene))))
      end)
      params:add_option(i.."sizelfo"..scene,"size lfo",{"off","on"},1)
      params:add_control(i.."density"..scene,"density",controlspec.new(1,40,"lin",1,4,"/beat",1/40))
      params:set_action(i.."density"..scene,function(value) engine.density(i,value/(params:get(i.."density_beat_divisor"..scene)*clock.get_beat_sec())) end)
      params:add_control(i.."density_beat_divisor"..scene,"density beat div",controlspec.new(1,16,'lin',1,4,"",1/16))
      params:set_action(i.."density_beat_divisor"..scene,function() 
        local p=params:lookup_param(i.."density"..scene)
        p:bang()
      end)
      params:add_option(i.."density_sync_external"..scene,"density sync ext",{"off","on"},(i==1 and scene ==1) and 2 or 1)
      params:add_option(i.."densitylfo"..scene,"density lfo",{"off","on"},1)

      -- update clock tempo param to reset density 
      -- local old_tempo_action=params:lookup_param("clock_tempo").action
      -- local tempo=params:lookup_param("clock_tempo")
      -- tempo.action = function ()
        
      --   old_tempo_action()
      -- end


      params:add_control(i.."pitch"..scene,"pitch",controlspec.new(-48,48,"lin",1,0,"note",1/96))
      params:set_action(i.."pitch"..scene,function(value) engine.pitch(i,math.pow(0.5,-value/12)) end)
      params:add_option(i.."pitch_sync_external"..scene,"pitch sync ext",{"off","on"},(i==1 and scene ==1) and 2 or 1)

      params:add_taper(i.."spread_sig"..scene,"spread sig",0,500,0,5,"ms")
      params:set_action(i.."spread_sig"..scene,function(value) engine.spread_sig(i,-value/1000) end)
      params:add_option(i.."spread_siglfo"..scene,"spread sig lfo",{"off","on"},1)
      
      params:add_taper(i.."spread_sig_offset1"..scene,"spread sig offset 1",0,500,0,5,"ms")
      params:set_action(i.."spread_sig_offset1"..scene,function(value) engine.spread_sig_offset1(i,-value/1000) end)
      
      params:add_taper(i.."spread_sig_offset2"..scene,"spread sig offset 2",0,500,0,5,"ms")
      params:set_action(i.."spread_sig_offset2"..scene,function(value) engine.spread_sig_offset2(i,-value/1000) end)
      
      params:add_taper(i.."spread_sig_offset3"..scene,"spread sig offset 3",0,500,0,5,"ms")
      params:set_action(i.."spread_sig_offset3"..scene,function(value) engine.spread_sig_offset3(i,-value/1000) end)
      
      params:add_taper(i.."jitter"..scene,"jitter",0,500,0,5,"ms")
      params:set_action(i.."jitter"..scene,function(value) engine.jitter(i,value/1000) end)
      params:add_option(i.."jitterlfo"..scene,"jitter lfo",{"off","on"},1)


      -- params:add_taper(i.."fade"..scene,"att / dec",1,9000,1000,3,"ms")
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

      -- params:add_control(i.."attack_shape"..scene,"attack shape",controlspec.new(-8,8,"lin",0.01,8,"",0.01/1))
      -- local prev

      params:add_option(i.."env_shape"..scene,"envelope shape",{"step","lin","sin","wel","squared","cubed"},4)
      params:set_action(i.."env_shape"..scene,function(value) 
        engine.gr_envbuf(i,table.unpack(e:get_gr_env_values(i,scene))) 
      end)
    
      
      
      params:add_control(i.."cutoff"..scene,"filter cutoff",controlspec.new(20,20000,"exp",0,20000,"hz"))
      params:set_action(i.."cutoff"..scene,function(value) engine.cutoff(i,value) end)
      params:add_option(i.."cutofflfo"..scene,"filter cutoff lfo",{"off","on"},1)
      
      params:add_control(i.."q"..scene,"filter rq",controlspec.new(0.01,1.0,"exp",0.01,0.1,"",0.01/1))
      params:set_action(i.."q"..scene,function(value) engine.q(i,value) end)

      params:add_control(i.."send"..scene,"echo send",controlspec.new(0.0,1.0,"lin",0.01,0.2))
      params:set_action(i.."send"..scene,function(value) engine.send(i,value) end)


      params:add_option(i.."division"..scene,"division",e.division_names,5)
      params:set_action(i.."division"..scene,function(value)
        -- if granchild_grid~=nil then
        --   granchild_grid:set_division(i,e.divisions[value])
        -- end
      end)

      params:add_control(i.."pan"..scene,"pan",controlspec.new(-1,1,"lin",0.01,0,"",0.01/1))
      params:set_action(i.."pan"..scene,function(value) engine.pan(i,value) end)

      params:add_taper(i.."spread_pan"..scene,"spread pan",0,100,0,0,"%")
      params:set_action(i.."spread_pan"..scene,function(value) engine.spread_pan(i,value/100) end)
      params:add_option(i.."spread_panlfo"..scene,"spread pan lfo",{"off","on"},2)

      params:add_control(i.."subharmonics"..scene,"subharmonic vol",controlspec.new(0.00,1.00,"lin",0.01,0))
      params:set_action(i.."subharmonics"..scene,function(value) engine.subharmonics(i,value) end)
      params:add_option(i.."subharmonicslfo"..scene,"subharmonic lfo",{"off","on"},1)

      params:add_control(i.."overtones"..scene,"overtone vol",controlspec.new(0.00,1.00,"lin",0.01,0))
      params:set_action(i.."overtones"..scene,function(value) engine.overtones(i,value) end)
      params:add_option(i.."overtoneslfo"..scene,"overtone lfo",{"off","on"},1)

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
      print(param_name,scene,e.num_scenes)
      for i=1,e.num_scenes do
        if i~=scene then
          params:hide(param_name..i)
        end
      end
      params:show(param_name..scene)
      local p=params:lookup_param(param_name..scene)
      p:bang()
    end
    e:bang(scene,3)
    eglut:rebuild_params()
  end)
  for scene=1,e.num_scenes do
    -- effect controls
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
    -- echo output volume
    params:add_control("echo_volume"..scene,"*".."echo output volume",controlspec.new(0.0,1.0,"lin",0,0.0,""))
    params:set_action("echo_volume"..scene,function(value) engine.echo_volume(value) end)
  end
  
  params:add_group("sync",7)
  e.all_param_ids = e.table_concat(e.param_list,e.param_list_echo,11)
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
      if i > 2 then
        local value_to_sync=params:get(voice_from..param..scene_from)    
        params:set(voice_to..param..scene_to,value_to_sync)
      else
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
    if params:get("sync_selector") > 2 then
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
    for _,param_name in ipairs(e.param_list) do
      for j=2,e.num_scenes do
        params:hide(i..param_name..i)
      end
    end
    for j=1,e.num_scenes do
      if mod_parameters[1].p_type=="number" then
        params:hide(i.."lfo_range_min_control"..j)
        params:hide(i.."lfo_range_max_control"..j)        
      else
        params:hide(i.."lfo_range_min_number"..j)
        params:hide(i.."lfo_range_max_number"..j)
      end
    end
  end
  for _,param_name in ipairs(e.param_list_echo) do
    for i=2,e.num_scenes do
      params:hide(param_name..i)
    end
  end

  -- self:bang(1)
  params:bang()

  --hack to get the lfo config min/max params correct  
  --and get the scene params properly hidden
  for i=1,e.num_voices do
    params:set(i.."config_lfo2",2)
    params:set(i.."config_lfo2",1)
    params:set(i.."scene",2)
    params:set(i.."scene",1)      
  end

  e.inited=true
  self.lfo_refresh:start()
  
end

function e:cleanup()
  print("eglut cleanup")
  if e.lfo_refresh then metro.free(e.lfo_refresh) end
end


return e


