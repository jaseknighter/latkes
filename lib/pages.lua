local pages={}

local reflector_button_letters={"R","L","P"}
local reflector_button_labels={"rec","loop","play"}

-- function 
function pages:init(args)
  local args=args==nil and {} or args
  for k,v in pairs(args) do
    self[k]=v
  end
  self.frame_width = self.composition_right-self.composition_left
  self.frame_height = self.composition_bottom-self.composition_top
  
  self.active_page=1
  self.p2ui={}
  self.p2ui.selected_ui_area_ix=1
  self.p2ui.selected_voice=1
  self.p2ui.selected_scene=1
  self.p2ui.selected_reflector=1  
  
  self.p2ui.ui_areas = {"voice","scene"}
  for i=1,self.max_reflectors_per_scene do
    table.insert(self.p2ui.ui_areas,"reflector"..i)
    for j=1,3 do
      selected_voice = self.p2ui.selected_voice
      selected_scene = self.p2ui.selected_scene
      table.insert(self.p2ui.ui_areas,"reflectorbutton"..i.."-"..j)
    end
  end
  
  self.p2ui.num_ui_areas=2+(self.max_reflectors_per_scene*4)
  self.p2ui.selected_ui_area=self.p2ui.ui_areas[self.p2ui.selected_ui_area_ix]      

end

function pages:display_frame()  
  screen.level(1)
  screen.move(self.composition_left,self.composition_top)
  screen.rect(self.composition_left,self.composition_top,self.composition_right-self.composition_left,self.composition_bottom-self.composition_top)
  screen.fill()
  screen.stroke()
end


function pages:enc(n,d)
  if pages.active_page==2 then
    if n==2 then
      self.p2ui.selected_ui_area_ix=util.clamp(self.p2ui.selected_ui_area_ix+d,1,self.p2ui.num_ui_areas)
      self.p2ui.selected_ui_area=self.p2ui.ui_areas[self.p2ui.selected_ui_area_ix]
      local ui_area = self.p2ui.selected_ui_area
      if string.sub(ui_area,1,15) == "reflectorbutton" then
        local reflector = tonumber(string.sub(ui_area,16,16))
        self.p2ui.selected_reflector = reflector
        local reflector_button = tonumber(string.sub(ui_area,-1))
        self.p2ui.selected_reflector_button = reflector_button
        if self.p2ui.selected_reflector_button > 1 then
          local voice = self.p2ui.selected_voice
          local scene = self.p2ui.selected_scene
          local reflector = self.p2ui.selected_reflector
          local reflector_play_id=voice.."-"..reflector.."play"..scene
          local play_visible = params:visible(reflector_play_id)
          if play_visible == false then
            if self.p2ui.selected_reflector_button == 2 then
              d = d > 0 and 2 or -1
            else 
              d = d > 0 and 1 or -2
            end
            self.p2ui.selected_ui_area_ix=util.clamp(self.p2ui.selected_ui_area_ix+d,1,self.p2ui.num_ui_areas)
            self.p2ui.selected_ui_area=self.p2ui.ui_areas[self.p2ui.selected_ui_area_ix]
          end 
        end

      elseif string.sub(ui_area,1,9) == "reflector" then
        local reflector = tonumber(string.sub(ui_area,-1))
        self.p2ui.selected_reflector = reflector
        self.p2ui.selected_reflector_button = nil
      else
        self.p2ui.selected_reflector = nil
        self.p2ui.selected_reflector_button = nil
      end
    elseif n==3 then
      if self.p2ui.selected_ui_area=="voice" then
        local selected_voice = util.clamp(self.p2ui.selected_voice+d,1,eglut.num_voices)
        self.p2ui.selected_voice = selected_voice
      elseif self.p2ui.selected_ui_area=="scene" then
        local voice = self.p2ui.selected_voice
        local selected_scene = util.clamp(params:get("rec_scene"..voice)+d,1,eglut.num_scenes)
        params:set("rec_scene"..voice,selected_scene)
        self.p2ui.selected_scene = selected_scene
      elseif self.p2ui.selected_reflector_button then
        local voice = self.p2ui.selected_voice
        local scene = self.p2ui.selected_scene
        local reflector = self.p2ui.selected_reflector
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
            print(d, state,d+state)
            -- print("button on/off",state+d == 1 and "off" or "on",reflector_play_id )
            params:set(reflector_play_id, state+d)  
          end
        end
      end
    end
  end
end

function pages:redraw(page_num)
  self:display_frame()
  if page_num == 1 then
    -- draw waveforms
    local show_waveform_name
    local show_waveform_ix = params:get("show_waveform")
    show_waveform_name = waveform_names[show_waveform_ix]
    local show_waveform = waveforms[show_waveform_name]:get_samples()~=nil
    if show_waveform then
      local sig_positions = nil
      if show_waveform_ix-2>0 then
        local voice=math.ceil((show_waveform_ix-2)/eglut.num_voices)
        sig_positions=waveform_sig_positions[voice.."granulated"]
      elseif waveform_names[show_waveform_ix]=="transported" then
        sig_positions=waveform_sig_positions["transported"]
      end
      local slice_pos = show_waveform_name=="composed" and composition_slice_positions or nil
      waveforms[show_waveform_name]:redraw(sig_positions,slice_pos)
    end
    screen.level(15)  


    -- set data points
    if mode == "points generated" then
      if points_data then
        if slices_analyzed then
          slices_analyzed = nil
          total_slices = nil
        end
        local show_all_slice_ids = params:get("show_all_slice_ids")
        for k,point in pairs(points_data) do 
          -- tab.print(k,v) 
          local x = composition_left + math.ceil(point[1]*(127-composition_left-5))
          local y = composition_top + math.ceil(point[2]*(64-composition_top-5))
          screen.level(15)
          screen.move(x,y-1)
          screen.line_rel(0,3)
          if show_all_slice_ids==2 then
            screen.level(5)
            screen.move(x,y-2)
            screen.text_center(tonumber(k) + 1)
            screen.level(15)
          end
        end
        screen.stroke()
          
      else 
        print("no points data")
      end

      --show slice played
      if (slice_played_ix) then
        -- screen.rect(slice_played_x-1,slice_played_y,2,2)
        -- screen.stroke()
        screen.level(5)
        screen.move(slice_played_x-5,slice_played_y-9)
        screen.rect(slice_played_x-5,slice_played_y-9,11,7)
        screen.fill()
        screen.level(15)
        screen.move(slice_played_x,slice_played_y-2)
        screen.text_center(tonumber(slice_played_ix) + 1)

        -- screen.stroke()
      end

      --show left transport slice
      if (transport_src_left_x) then
        screen.move(transport_src_left_x-3,transport_src_left_y)
        screen.line_rel(2,0)
        screen.move(transport_src_left_x,transport_src_left_y-2)
        screen.text_center(tonumber(transport_src_left_ix)+1)
        -- screen.stroke()
      end
      --show right transport slice
      if (transport_src_right_x) then
        screen.move(transport_src_right_x,transport_src_right_y)
        screen.line_rel(2,0)
        screen.move(transport_src_right_x,transport_src_right_y-2)
        screen.text_center(tonumber(transport_src_right_ix)+1)

        -- screen.stroke()
      end
      -- screen.move(cursor_x-4,cursor_y-1)
      screen.rect(cursor_x-2,cursor_y-2,4,4)
      -- screen.circle(cursor_x,cursor_y,5)
      -- screen.line(transport_src_right_x,transport_src_right_y,2)
      -- screen.stroke()
    elseif mode == "start" then
      screen.move(composition_left,8)
      -- screen.text("k2 to select folder/file...")
      -- screen.move(composition_left,16)
      -- screen.text("k1+k3 to record live...")
    elseif mode == "loading audio" then
      -- print("loading audio...")
      screen.move(composition_left,composition_top-6)
      screen.text("loading audio...")
    elseif mode == "audio composed" then
      print("show comp")
      if waveforms["composed"].waveform_samples then
        screen.move(composition_left,composition_top-6)
        -- screen.text("k1+k2 to transport audio...")
        screen.text("k3 to analyze audio...")
        waveforms["composed"]:redraw(composed_sig_pos)
      end
    elseif mode == "recording" then
      print("recording in progress...")
      screen.move(composition_left,composition_top-6)
      screen.text("recording in progress...")
      if waveforms["composed"].waveform_samples then
        waveforms["composed"]:redraw(composed_sig_pos)
      end
    elseif mode == "analysing" then
      screen.move(composition_left,composition_top-6)
      if slices_analyzed then
        screen.text("progress: "..slices_analyzed.."/"..total_slices)
      else
        screen.text("analysis in progress...")
      end
    end
  elseif page_num == 2 then
    local ui_area = self.p2ui.selected_ui_area
    local voice = self.p2ui.selected_voice
    local scene = params:get("rec_scene"..voice)

    -- draw voice and scene ui boxes
    screen.level(ui_area=="voice" and 7 or 3)
    local voicebox_left = 10
    local voicebox_width = self.composition_left-voicebox_left-3
    local voicebox_top = self.composition_top
    local voicebox_height = ((self.composition_bottom-self.composition_top)/2)-1
    local scenebox_left = 10
    local scenebox_width = self.composition_left-scenebox_left-3
    local scenebox_top = voicebox_top+voicebox_height+2
    local scenebox_height = voicebox_height

    screen.move(voicebox_left,voicebox_top)
    screen.rect(voicebox_left,voicebox_top,voicebox_width,voicebox_height)
    screen.fill()
    screen.stroke()
    
    screen.level(12)
    screen.move(scenebox_left-2,scenebox_top-4)
    screen.text_right("v")
    screen.move(scenebox_left+(scenebox_width/2),scenebox_top-4)
    screen.font_size(16)
    screen.text_center(voice)
    screen.stroke()
    
    screen.level(ui_area=="scene" and 7 or 3)
    screen.move(scenebox_left,scenebox_top)
    screen.rect(scenebox_left,scenebox_top,scenebox_width,scenebox_height)
    screen.fill()
    screen.stroke()
            
    screen.level(12)
    screen.font_size(8)
    -- screen.level(7)
    screen.move(scenebox_left-2,scenebox_top+scenebox_height-2)
    screen.text_right("sc")
    screen.move(scenebox_left+(scenebox_width/2),scenebox_top+scenebox_height-2)
    screen.font_size(16)
    screen.text_center(scene)
    screen.stroke()
    screen.stroke()
        
    -- draw reflector separators, labels, and animated bars
    local bar_width = math.floor(self.frame_width/self.max_reflectors_per_scene)
    screen.level(7)
    screen.move(self.composition_left,self.composition_top)
    screen.rect(self.composition_left,self.composition_top,self.composition_right-self.composition_left,self.composition_bottom-self.composition_top)
    screen.font_size(8)
    for reflector=1,self.max_reflectors_per_scene do
      local bar_x = math.floor(self.composition_left+((reflector-1)*bar_width))
      local bar_y = self.composition_top
      screen.level(2)
      screen.move(bar_x,bar_y)
      screen.line_rel(0,self.frame_height-1)
      screen.stroke()
      local text_x = math.floor(self.composition_left+((reflector-1)*bar_width)+(bar_width/2))
      local text_y = self.composition_bottom + 10
      
      -- draw reflector numbers 
      screen.level((ui_area=="reflector"..reflector or string.sub(ui_area,1,16) == "reflectorbutton" .. reflector) and 10 or 3)
      screen.move(text_x,text_y)
      screen.text_center(reflector)
      
      -- set reflector name
      -- if ui_area~="voice" and ui_area~="scene" then
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
          end
        else
          label="--"
        end 
        screen.level(10)
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
              screen.level(7)
              screen.fill()
              screen.stroke()            
            else              
              screen.level(3)
              screen.fill()
              screen.stroke()
            end

            if reflector_button == 1 then
              -- screen.circle(self.composition_right+button_size+3,button_top+4,2)
              screen.level(recording==2 and 12 or 3)
            elseif reflector_button == 2 then
              screen.level(looping==2 and 12 or 3)
            elseif reflector_button == 3 then
              screen.level(playing==2 and 12 or 3)
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
        screen.level(pages.p2ui.selected_reflector == reflector and 10 or 3)
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