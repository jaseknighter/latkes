-- from @infinitedigits graintopia

local Waveform={}

function Waveform:new(args)
  local wf=setmetatable({},{__index=Waveform})
  local args=args==nil and {} or args
  for k,v in pairs(args) do
    wf[k]=v
  end
  self.samples = {}
  return wf
end

function Waveform.load(voice,path,sample_start,sample_length)

end

function Waveform:set_samples(offset, padding, waveform_blob)
  for i = 1, string.len(waveform_blob) - padding do    
    local value = string.byte(string.sub(waveform_blob, i, i + 1))
    value = util.linlin(0, 126, -1, 1, value)
    
    local frame_index = math.ceil(i / 2) + offset
    if i % 2 > 0 then
      self.samples[frame_index] = {}
      self.samples[frame_index][1] = value -- Min
    else
      self.samples[frame_index][2] = value -- Max
    end
  end
end

function Waveform:clear_samples(clear_from)
  if clear_from then
    local clear_sample_from = math.floor(clear_from * #self.samples)
    
    for frame = clear_sample_from, #self.samples do
      self.samples[frame] = {0,0}
    end
  else
    self.samples = {}
  end
end

function Waveform:get_samples()
  return self.samples
end

function Waveform:display_sigs_pos(sigs_pos, highlight_sig_positions)
  --show signal position(s)
  if #sigs_pos > 0 then
    -- if highlight_sig_positions == true then print("highlight_sig_positions",highlight_sig_positions) end
    if highlight_sig_positions == true then screen.level(15) else screen.level(1) end
    -- screen.level(15)
    screen.blend_mode(blend_mode or 11)   
    local center = self.composition_bottom-((self.composition_bottom-self.composition_top)/2)
    for i=1,#sigs_pos do
      local sig_pos = sigs_pos[i]
      -- print(sig_pos)
      screen.blend_mode(blend_mode or 11)   
      local height = util.round(self.composition_top-self.composition_bottom+6)
      local xloc = util.linlin(1,127,self.composition_left,self.composition_right,sig_pos*127)
      -- local xloc = util.linlin(1,127,self.composition_left,self.composition_right,math.floor(sig_pos*127))
      local yloc = center - (height/2)
      screen.move(xloc, yloc)
      screen.line_rel(0, height)
      -- screen.stroke()
    end
  end
end

function Waveform:display_waveform()
  local x_pos = 0
  local active_voice = params:get("active_voice")
  local screen_level
  local sample_mode = params:get(active_voice.."sample_mode")
  local active_rec_level = params:get(active_voice.."live_rec_level")
  local active_pre_level = params:get(active_voice.."live_pre_level")
  
  if sample_mode == 1 then 
    screen_level = 0 
  elseif sample_mode == 2 then 
    screen_level = 10 
  else
    screen_level = util.round((active_rec_level + active_pre_level) * 7)
  end
  
  screen.level(screen_level)
  local center = self.composition_bottom-((self.composition_bottom-self.composition_top)/2)
  for i,s in ipairs(self.samples) do
    local height = util.round(math.abs(s[2]) * ((self.composition_top-self.composition_bottom)))
    screen.move(util.linlin(0,127,self.composition_left,self.composition_right,x_pos), center - (height/2))
    screen.line_rel(0, height)
    -- screen.move(util.linlin(0,127,self.composition_left,self.composition_right,x_pos+1), center - (height/2))
    -- screen.line_rel(0, height)
    x_pos = x_pos + 1
  end
  screen.stroke()
end

function Waveform:redraw(sigs_pos, highlight_sig_positions)
  if self.active==false then
    do return end
  end

  if redraw_waveform then 
    self:display_waveform()
  end

  --show signal(s) positions
  if sigs_pos then
    self:display_sigs_pos(sigs_pos, highlight_sig_positions)
  end
  screen.stroke()
  screen.blend_mode(0)   

end

return Waveform
