local pages={}

local reflector_button_letters={"R","L","P"}
local reflector_button_labels={"rec","loop","play"}
local alt_key = false
local screen_recording = false
-- function 
function pages:init(args)
  local args=args==nil and {} or args
  for k,v in pairs(args) do
    self[k]=v
  end
  self.frame_width = self.composition_right-self.composition_left
  self.frame_height = self.composition_bottom-self.composition_top
  
  self.p1ui={}
  self.p1ui.selected_ui_area_ix=2
  self.p1ui.selected_voice=1
  self.p1ui.selected_scene=1
  self.p1ui.prev_scenes = {1,1,1,1}
  self.p1ui.ui_areas = {"mode","voice","scene"}
  self.p1ui.num_ui_areas=#self.p1ui.ui_areas
  self.p1ui.selected_ui_area=self.p1ui.ui_areas[self.p1ui.selected_ui_area_ix]      
  
  
  self.p2ui={}
  self.p2ui.selected_ui_area_ix=2
  self.p2ui.selected_voice=1
  self.p2ui.selected_scene=1
  self.p2ui.prev_scenes = {1,1,1,1}
  self.p2ui.selected_reflector=nil  
  self.p2ui.ui_areas = {"mode","voice","scene"}
  for i=1,self.max_reflectors_per_scene do
    table.insert(self.p2ui.ui_areas,"reflector"..i)
    for j=1,3 do
      selected_voice = self.p2ui.selected_voice
      selected_scene = self.p2ui.selected_scene
      table.insert(self.p2ui.ui_areas,"reflectorbutton"..i.."-"..j)
    end
  end
  self.p2ui.num_ui_areas=#self.p1ui.ui_areas+(self.max_reflectors_per_scene*4)
  self.p2ui.selected_ui_area=self.p2ui.ui_areas[self.p2ui.selected_ui_area_ix]      

end

function pages:display_frame()  
  screen.move(self.composition_left,self.composition_top)
  screen.rect(self.composition_left,self.composition_top,self.composition_right-self.composition_left,self.composition_bottom-self.composition_top)
  screen.level(1)
  screen.fill()
  screen.move(self.composition_left,self.composition_top)
  screen.rect(self.composition_left,self.composition_top,self.composition_right-self.composition_left,self.composition_bottom-self.composition_top)
  screen.stroke()
end

function pages:get_selected_ui_elements()
  local active_page = params:get("active_page")
  if active_page == 1 then
    local voice = self.p1ui.selected_voice
    local scene = self.p1ui.selected_scene
    return voice, scene
  elseif active_page == 2 then
    local voice = self.p2ui.selected_voice
    local scene = self.p2ui.selected_scene
    local reflector = self.p2ui.selected_reflector
    return voice, scene, reflector
  end
end

function pages:get_active_ui_area()
  local active_page = params:get("active_page")
  if active_page == 1 then
    return self.p1ui.selected_ui_area
  elseif active_page == 2 then
    return self.p2ui.selected_ui_area
  end
end

function pages:get_active_ui_area_type()
  local active_ui_area_type
  local ui_area = self:get_active_ui_area()
  if ui_area == "mode" then
    active_ui_area_type = "mode"
  elseif ui_area == "voice" then
    active_ui_area_type = "voice"
  elseif ui_area == "scene" then
    active_ui_area_type = "scene"
  elseif string.sub(ui_area,1,15) == "reflectorbutton" then
    active_ui_area_type = "reflectorbutton"
  elseif string.sub(ui_area,1,9) == "reflector" then
    active_ui_area_type = "reflector"
  end
  return active_ui_area_type
end

function pages:get_active_reflector()
  local active_reflector
  local ui_area = self:get_active_ui_area()
  local active_ui_area = pages:get_active_ui_area_type()
  if active_ui_area == "reflectorbutton" then
    active_reflector=tonumber(string.sub(ui_area,-3,-3))
  elseif active_ui_area == "reflector" then
    active_reflector=tonumber(string.sub(ui_area,-1))
  end
  return active_reflector
end

function pages:get_active_reflector_button()
  local active_reflector_button
  local ui_area = self:get_active_ui_area()
  local active_ui_area = pages:get_active_ui_area_type()
  if active_ui_area == "reflectorbutton" then
    active_reflector_button=tonumber(string.sub(ui_area,-1))
  end
  return active_reflector_button
end

function pages.update_waveform_display(voice)
  local active_mode = params:get(voice.."sample_mode")
  local waveform_ix
  if active_mode < 3 then
    waveform_ix = voice+(voice-1)
    params:set("show_waveform",waveform_ix)
  else
    waveform_ix = voice+voice
    params:set("show_waveform",waveform_ix)
  end
end

function pages:set_selected_ui_area(ix)
  local active_page = params:get("active_page")
  if active_page==1 then
    self.p1ui.selected_ui_area_ix=ix
    self.p1ui.selected_ui_area=self.p1ui.ui_areas[ix]
    self.p2ui.selected_ui_area_ix=ix
    self.p2ui.selected_ui_area=self.p2ui.ui_areas[ix]
  elseif active_page==2 then
    self.p2ui.selected_ui_area_ix=ix
    self.p2ui.selected_ui_area=self.p2ui.ui_areas[ix]
  end
end

function pages:key(k,z)
  if k==1 then
    if z==1 then
      alt_key=true
      print("true")
    else
      alt_key=false
      if screen_recording == true then
        screen_recording = false
        local voice = self.p2ui.selected_voice
        local scene = self.p2ui.selected_scene
        local reflector = self.p2ui.selected_reflector
        local reflector_record_id=voice.."-"..reflector.."record"..scene
        params:set(reflector_record_id, 1)  

      end
    end
  end
end

function pages:enc(n,d)
  local active_page = params:get("active_page")
  if n==1 then
    active_page=util.clamp(d+active_page,1,2)
    params:set("active_page",active_page)
  end

  if active_page==1 then
    if n==2 then
      local ix=util.clamp(self.p1ui.selected_ui_area_ix+d,1,self.p1ui.num_ui_areas)
      self:set_selected_ui_area(ix)
    elseif n==3 then
      local voice
      if self.p1ui.selected_ui_area=="mode" then
        voice = self.p1ui.selected_voice
        local smode = params:get(voice .. "sample_mode") + d
        params:set(voice .. "sample_mode", smode)
      elseif self.p1ui.selected_ui_area=="voice" then
        voice = util.clamp(self.p1ui.selected_voice+d,1,eglut.num_voices)
        self.p1ui.selected_voice = voice
        params:set("active_voice",self.p1ui.selected_voice)
      elseif self.p1ui.selected_ui_area=="scene" then
        voice = self.p1ui.selected_voice
        local selected_scene = util.clamp(params:get("rec_scene"..voice)+d,1,eglut.num_scenes)
        params:set("rec_scene"..voice,selected_scene)
        self.p1ui.selected_scene = selected_scene
        params:set("active_scene",self.p1ui.selected_scene)
      end
    end
  elseif active_page==2 then
    if alt_key == true then
      if n==3 then
        local voice, scene, reflector = self:get_selected_ui_elements()

        local reflector_active = string.find(self:get_active_ui_area_type(),"reflector")
        if reflector_active then
          if screen_recording == false then screen_recording = true end
          local reflector_record_id=voice.."-"..reflector.."record"..scene
          if params:get(reflector_record_id) == 1  then
            params:set(reflector_record_id, 2)  
          end
          local reflector_id=reflectors_selected_params[voice][scene][reflector].id
          params:delta(reflector_id,d)
        end
      end
    elseif n==1 then

    elseif n==2 then
      local ix=util.clamp(self.p2ui.selected_ui_area_ix+d,1,self.p2ui.num_ui_areas)
      self:set_selected_ui_area(ix)
      local ui_area_type = self:get_active_ui_area_type()
      if ui_area_type == "reflectorbutton" then
        local reflector_button = self:get_active_reflector_button()
        self.p2ui.selected_reflector_button = reflector_button
        if self.p2ui.selected_reflector_button > 1 then
          local voice, scene, reflector = self:get_selected_ui_elements()
          local play_visible = reflector and params:visible(voice.."-"..reflector.."play"..scene)
          if play_visible ~= true then
            if self.p2ui.selected_reflector_button == 2 then
              d = d > 0 and 2 or -1
            else 
              d = d > 0 and 1 or -2
            end
            self.p2ui.selected_ui_area_ix=util.clamp(self.p2ui.selected_ui_area_ix+d,1,self.p2ui.num_ui_areas)
            self.p2ui.selected_ui_area=self.p2ui.ui_areas[self.p2ui.selected_ui_area_ix]
          end 
        end
        local reflector = tonumber(string.sub(self.p2ui.selected_ui_area,16,16))
        self.p2ui.selected_reflector = reflector
      elseif ui_area_type == "reflector" then
        local reflector = self:get_active_reflector()
        self.p2ui.selected_reflector = reflector
        local reflector = self:get_active_reflector()
        self.p2ui.selected_reflector = reflector
        self.p2ui.selected_reflector_button = nil
      else
        self.p2ui.selected_reflector = nil
        self.p2ui.selected_reflector_button = nil
      end
    elseif n==3 then
      if self.p2ui.selected_ui_area=="mode" then
        local voice = self.p2ui.selected_voice
        local smode = params:get(voice .. "sample_mode") + d
        params:set(voice .. "sample_mode", smode)
      elseif self.p2ui.selected_ui_area=="voice" then
        local selected_voice = util.clamp(self.p2ui.selected_voice+d,1,eglut.num_voices)
        self.p2ui.selected_voice = selected_voice
        params:set("active_voice",self.p2ui.selected_voice)
      elseif self.p2ui.selected_ui_area=="scene" then
        local voice = self.p2ui.selected_voice
        local selected_scene = util.clamp(params:get("rec_scene"..voice)+d,1,eglut.num_scenes)
        params:set("rec_scene"..voice,selected_scene)
        self.p2ui.selected_scene = selected_scene
        params:set("active_scene",self.p2ui.selected_scene)
      elseif self.p2ui.selected_reflector_button then
        local voice, scene, reflector = self:get_selected_ui_elements()
        local reflector_button = self.p2ui.selected_reflector_button
        if reflector_button == 1 then
          local reflector_record_id=voice.."-"..reflector.."record"..scene
          local state = params:get(reflector_record_id) == 1 and 1 or 2  
          if state + d > 0 and state + d < 3 then 
            params:set(reflector_record_id, state+d)  
          end
        elseif reflector_button == 2 then
          local reflector_loop_id=voice.."-"..reflector.."loop"..scene
          local state = params:get(reflector_loop_id) == 1 and 1 or 2  
          if state + d > 0 and state + d < 3 then 
            params:set(reflector_loop_id, state+d)  
          end
        elseif reflector_button == 3 then
          local reflector_play_id=voice.."-"..reflector.."play"..scene
          local state = params:get(reflector_play_id)
          if state + d > 0 and state + d < 3 then 
            params:set(reflector_play_id, state+d)  
          end
        end
      else -- update param
        local voice = self.p2ui.selected_voice
        local scene = self.p2ui.selected_scene
        local reflector = self.p2ui.selected_reflector
        local reflector_record_id=voice.."-"..reflector.."record"..scene
        if params:visible(reflector_record_id) == true then
          local reflector_id=reflectors_selected_params[voice][scene][reflector].id
          params:delta(reflector_id,d)
        end

      end
    end
  end
  if params:get("sync_waveform") == 2 then
    self.update_waveform_display(params:get("active_voice"))
  end
end

function pages:draw_mode_voice_scene_buttons(ui_area, voice, scene)
  local button_letters={"m","v","sc"}
  local button_size=((self.composition_bottom-self.composition_top)/3)
  local button_left = self.composition_left - button_size - 1
  screen.font_size(8)
  for button=1,3 do

    local button_top=self.composition_top+(button_size*(button-1))
    screen.rect(button_left,button_top,button_size-1,button_size-1)
    if button == 1 then
      screen.level(ui_area=="mode" and 15 or 5)
      screen.fill()
      screen.stroke()
      screen.move(button_left+5,button_top+8)
      local mode_ix = params:get(voice.."sample_mode")
      local p = params:lookup_param(voice.."sample_mode")
      local mode = p.options[mode_ix]
      local pval 
      if mode == "off" then 
        pval = "o"
      elseif mode == "live stream" then 
        pval = "lv" or "rc"
      else
        pval = "rc"
      end
      screen.level(0)
      screen.text_center(pval)    
    elseif button == 2 then
      screen.level(ui_area=="voice" and 15 or 5)
      screen.fill()
      screen.stroke()
      screen.move(button_left+5,button_top+8)
      screen.level(0)
      screen.text_center(voice)    
    elseif button == 3 then
      screen.level(ui_area=="scene" and 15 or 5)
      screen.fill()
      screen.stroke()
      screen.move(button_left+5,button_top+8)
      screen.level(0)
      screen.text_center(eglut.scene_labels[scene])    
    end
    -- screen.move(self.composition_right+button_size+4,button_top+6)
    -- screen.level(0)
    screen.stroke()
    screen.move(button_left-11,button_top+8)
    screen.text(button_letters[button])
    screen.stroke()
  end
end

function pages:redraw(page_num, show_sig_positions)
  
  self:display_frame()
  local ui_area = self:get_active_ui_area()
  local voice, scene = self:get_selected_ui_elements()
  
  -- draw sample mode, voice, and scene ui boxes
  self:draw_mode_voice_scene_buttons(ui_area, voice, scene)
  if page_num == 1 then

    -- draw waveforms
    local show_waveform_name
    local show_waveform_ix = params:get("show_waveform")
    show_waveform_name = waveform_names[show_waveform_ix]
    local show_waveform = waveforms[show_waveform_name]:get_samples()~=nil
    if show_waveform then
      local sig_positions, highlight_sig_positions
      -- local voice=math.ceil((show_waveform_ix)/eglut.num_voices)
      local voice=params:get("active_voice")
      if show_sig_positions[voice] then
        highlight_sig_positions = true
      else
        highlight_sig_positions = false
      end
      sig_positions=waveform_sig_positions[voice.."granulated"]
      -- print(waveform_sig_positions[voice.."granulated"],voice)
      waveforms[show_waveform_name]:redraw(sig_positions,highlight_sig_positions)
    end
    screen.level(10)  
    screen.move(self.composition_left,self.composition_bottom+7)
    screen.line_rel(self.composition_right-self.composition_left,0)
    screen.level(15)  
    -- local sample_used = params:get(self.p1ui.selected_voice.."sample_length")/
    local sample_length = (params:get(voice.."sample_length"))/live_buffer_length
    screen.rect(self.composition_left,self.composition_bottom+5,(self.composition_right-self.composition_left)*sample_length,4)

  elseif page_num == 2 then
        
    -- draw reflector separators, labels, and animated bars
    local bar_width = math.floor(self.frame_width/self.max_reflectors_per_scene)
    screen.level(15)
    screen.move(self.composition_left,self.composition_top)
    screen.rect(self.composition_left,self.composition_top,self.composition_right-self.composition_left,self.composition_bottom-self.composition_top)
    screen.font_size(8)
    for reflector=1,self.max_reflectors_per_scene do
      local bar_x = math.floor(self.composition_left+((reflector-1)*bar_width))
      local bar_y = self.composition_top
      screen.level(5)
      screen.move(bar_x,bar_y)
      screen.line_rel(0,self.frame_height-1)
      screen.stroke()
      local text_x = math.floor(self.composition_left+((reflector-1)*bar_width)+(bar_width/2))
      local text_y = self.composition_bottom + 9
      
      -- draw reflector numbers 
      local reflector_highlighted = ui_area=="reflector"..reflector
      local buttons_highlighted = string.sub(ui_area,1,16) == "reflectorbutton" .. reflector

      if reflector_highlighted or buttons_highlighted then
        screen.level(5)
        screen.move(text_x-4,text_y-7)
        screen.rect(text_x-4,text_y-7,8,8)
        screen.fill()
      end
      screen.level((reflector_highlighted or buttons_highlighted) and 15 or 5)
      screen.move(text_x,text_y)
      screen.text_center(reflector)

      -- set reflector name
      local reflector_name, label
      if ui_area=="reflector"..reflector or string.sub(ui_area,1,16) == "reflectorbutton" .. reflector then
        local reflector_param=reflectors_selected_params[voice][scene][reflector]
        if reflector_param then
          reflector_name=reflector_param.name
          label = reflector_name
          if string.sub(ui_area,1,16) == "reflectorbutton" .. reflector then
            local button_ix = tonumber(string.sub(ui_area,-1))
            local button = reflector_button_labels[button_ix]
            label = label .. "-" .. button
          else 
            reflector_id=reflector_param.id
            local param_value = params:get(reflector_id)
            local param_max = params:get_range(reflector_id)[2]
            param_value = util.round(param_value,0.01)
            -- if param_max > 10 then
            -- end
            label = label .. ": " .. param_value
          end
        else
          label="--"
        end 
        screen.level(5)
        screen.move(self.composition_left,self.composition_top-4)
        screen.text(label)
      
        -- set reflector buttons
        -- if string.sub(ui_area,1,16) == "reflectorbutton" .. reflector and label ~= "--" then
        if label ~= "--" then
          --display reflector record, loop, play buttons
          local reflector_loop_id=voice.."-"..reflector.."loop"..scene
          local looping=params:get(reflector_loop_id)
          local reflector_play_id=voice.."-"..reflector.."play"..scene
          local playing=params:get(reflector_play_id)
          local play_visible = params:visible(reflector_play_id)
          
          for reflector_button=1,3 do
            local reflector_record_id=voice.."-"..reflector.."record"..scene
            local recording=params:get(reflector_record_id)
          
            -- if no recording has occured, don't show the play or loop buttons
            if reflector_button > 1 and not play_visible then break end

            local button_size=((self.composition_bottom-self.composition_top)/3)
            local button_top=self.composition_top+(button_size*(reflector_button-1))
            screen.rect(self.composition_right+2,button_top,button_size-1,button_size-1)
            if reflector_button == tonumber(string.sub(ui_area,-1)) and string.sub(ui_area,1,16) == "reflectorbutton" .. reflector then
              screen.level(15)
              screen.fill()
              screen.stroke()            
            else              
              screen.level(5)
              screen.fill()
              screen.stroke()
            end

            if reflector_button == 1 then
              -- screen.circle(self.composition_right+button_size+3,button_top+4,2)
              screen.level(recording==2 and 15 or 5)
            elseif reflector_button == 2 then
              screen.level(looping==2 and 15 or 5)
            elseif reflector_button == 3 then
              screen.level(playing==2 and 15 or 5)
            end
            -- screen.move(self.composition_right+button_size+4,button_top+6)
            screen.circle(self.composition_right+button_size+4,button_top+6,1)
            screen.stroke()
            screen.level(0)
            screen.move(self.composition_right+6,button_top+8)
            screen.text(reflector_button_letters[reflector_button])
            screen.stroke()
          end
        end
      end

      -- draw animated reflector bars
      -- if num_reflector_selected_params>0 then
      local sel_param=reflectors_selected_params[voice][scene][reflector]
      local sel_param_id=sel_param and sel_param.id
      -- print(sel_param,sel_param_id,voice,scene,reflector) 
      if sel_param and sel_param_id then
        screen.level(self.p2ui.selected_reflector == reflector and 15 or 5)
        local reflector_id=reflectors_selected_params[voice][scene][reflector].id
        -- local reflector=reflectors[voice][scene][reflector_id]
        local param_bar_x = math.floor(self.composition_left+((reflector-1)*bar_width)-2)+3
        local p_type=params:lookup_param(reflector_id).t
        local param_bar_y,param_bar_height
        if p_type==3 or p_type==5 then
          local min=0
          local max=1
          local pval=params:get_raw(reflector_id)
          -- param_bar_y=(self.composition_top-1)+(math.floor(util.linlin(min,max,1,0,pval)*(self.frame_height-2)))
          param_bar_y=(self.composition_top)+(math.floor(util.linlin(min,max,1,0,pval)*(self.frame_height)))
          param_bar_height=self.composition_bottom-param_bar_y
          param_bar_height=param_bar_height>0 and param_bar_height or 0
          -- param_bar_height=math.floor(util.explin(min,max,0,1,pval)*(self.frame_height-4))
        else
          local range=params:get_range(reflector_id)
          local min=range[1]
          local max=range[2]
          local pval=params:get(reflector_id)
          param_bar_y=(self.composition_top)+(math.floor(util.linlin(min,max,1,0,pval)*(self.frame_height)))
          param_bar_height=self.composition_bottom-param_bar_y
          param_bar_height=param_bar_height>0 and param_bar_height or 0
          -- param_bar_height=math.floor(util.linlin(min,max,0,1,pval)*(self.frame_height-4))
          
          -- end
          -- print(i,reflector_id,min,max,pval,param_bar_x,param_bar_y,param_bar_height)
        end
        -- print(i,pval,p_type,min,max,param_bar_y,param_bar_height)
        screen.move(param_bar_x,param_bar_y)
        screen.rect(param_bar_x,param_bar_y,bar_width-3,param_bar_height)
        screen.fill()
        screen.stroke()
      end
    end
  end
end

return pages