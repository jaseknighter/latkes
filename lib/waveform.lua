-- from @infinitedigits graintopia

local Waveform={}

function Waveform:new(args)
  local wf=setmetatable({},{__index=Waveform})
  local args=args==nil and {} or args
  for k,v in pairs(args) do
    wf[k]=v
  end
  return wf
end

function Waveform.load(voice,path,max_len)
  print("waveform.load",voice,path,max_len)
  if path ~= "" then
    local ch, samples = audio.file_info(path)
    if ch > 0 and samples > 0 then
      softcut.buffer_clear()
      clock.run(function()
        softcut.buffer_read_mono(path, 0, 1, -1, 1, 1, 0, 1)
        local len = (samples / 48000)
        local waveform_start = 1
        local waveform_end = max_len and math.min(max_len,len) or len
        print("path,samples,max_len",path,samples,max_len,waveform_start, waveform_end)
        softcut.render_buffer(1, waveform_start, waveform_end, 127)
      end)
    end
  else
    print("not a sound file")
  end

end

function Waveform:set_samples(samples)
  self.waveform_samples = samples
  -- tab.print(samples)
end

function Waveform:get_samples()
  return self.waveform_samples
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
  
  screen.level(10)
  local center = self.composition_bottom-((self.composition_bottom-self.composition_top)/2)
  for i,s in ipairs(self.waveform_samples) do
    local height = util.round(math.abs(s) * ((self.composition_top-self.composition_bottom)))
    screen.move(util.linlin(0,127,self.composition_left,self.composition_right,x_pos), center - (height/2))
    screen.line_rel(0, height)
    x_pos = x_pos + 1
  end
  screen.stroke()
end

function Waveform:redraw(sigs_pos, highlight_sig_positions)
  if self.active==false then
    do return end
  end

  self:display_waveform()


  --show signal(s) positions
  if sigs_pos then
    self:display_sigs_pos(sigs_pos, highlight_sig_positions)
  end
  screen.stroke()
  screen.blend_mode(0)   

end

return Waveform
