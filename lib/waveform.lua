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


function Waveform:get_samples()
  return self.samples
end

function Waveform:display_sigs_pos(sigs_pos, playing, sig_size)
  --show signal position(s)
  if #sigs_pos > 0 then
    sig_size = sig_size+1 or 2
    screen.level(playing == 1 and 5 or 15)
    local center = self.composition_bottom-((self.composition_bottom-self.composition_top)/2)
    for i=1,#sigs_pos do
      local sig_pos = sigs_pos[i]
      -- print(sig_pos)
      local height = util.round(self.composition_top-self.composition_bottom+6)
      local xloc = util.linlin(1,127,self.composition_left,self.composition_right,sig_pos*127)
      local yloc = center - (height/2)
      screen.blend_mode(12)  
      -- screen.move(xloc, yloc)
      local off_edge = math.ceil(self.composition_right - xloc)
      if sig_size-off_edge > 0 then
        screen.rect(xloc,yloc, off_edge, height)
        screen.fill()
        screen.rect(self.composition_left,yloc, sig_size - off_edge, height)
        screen.fill()

      else
        screen.rect(xloc,yloc, sig_size, height)
        screen.fill()
      end
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
    screen_level = 5
  else
    screen_level = util.round((active_rec_level + active_pre_level) * 5)
  end
  
  screen.level(screen_level)
  local center = self.composition_bottom-((self.composition_bottom-self.composition_top)/2)
  for i,s in ipairs(self.samples) do
    local height = util.round(math.abs(s[2]) * ((self.composition_top-self.composition_bottom)))
    screen.move(util.linlin(0,127,self.composition_left,self.composition_right,x_pos), center - (height/2))
    screen.line_rel(0, height)
    x_pos = x_pos + 1
  end
  screen.stroke()
end

function Waveform:redraw(sigs_pos, playing, sig_size)
  if self.active==false then
    do return end
  end

  if redraw_waveform then 
    self:display_waveform()
  end

  --show signal(s) positions
  if sigs_pos then
    self:display_sigs_pos(sigs_pos, playing, sig_size)
  end
  screen.stroke()
  screen.blend_mode(0)   

end

return Waveform
