-- midi helper global variables and functions 
--  including sysex code for the 16n faderbank

midi_helper = {}

local midi_devices = {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1}

local function update_midi_device_options()
  print("get midi devices")
  local devices = {}
  for i=1,#midi.vports,1
  do
    table.insert(devices, i .. ". " .. midi.vports[i].name)
  end
  midi_devices = devices
  local midi_in = params:lookup_param("midi_device")
  midi_in.options = midi_devices
  
  -- tab.print(midi_devices)
end

-------------------------------
-- code for the 16n faderbank
--
-- sysex handling code from from: https://llllllll.co/t/how-do-i-send-midi-sysex-messages-on-norns/34359/15
--
-- important hex values (with decimal equivalent:
-- `0xF0` - "start byte" (240) - midi_event_index table 1[1]
-- `0x7d` - "manufacturer is 16n" (125) - midi_event_index table 1[2]
-- `0x0F` - "c0nFig" (15) - midi_event_index table 2[2]
-- `0xf7` - "stop byte" (247) -- midi_event_index table 30[1] QUESTION: why is this sent in the middle of the message, before current slider cc values are sent
-- current usb midi channel values: midi_event_index  table 7[2] - 12[2]
-- current trs midi channel values: midi_event_index  table 12[3] - 17[3]
-- current usb cc values: midi_event_index table 20[1] - 27[3]
-- current usb channel/cc/value  midi_event_index table 29[1] - 43[3] QUESTION: why don't all 16 channels show up?
--------------------------------

local function send_16n_sysex(m,d) 
  m.send(device_16n,{0xf0})
  for i,v in ipairs(d) do
    -- print("send 16n sysex", i,d[i])
    m.send(device_16n,{d[i]})
  end
  m.send(device_16n,{0xf7})
end

local function update16n(channel_vals_16n,cc_vals_16n,skip_exclusions)
  local data_table = {0x7d,0x00,0x00,0x0c}
  local exclusion_cc_channel = params:get("exclusion_cc_channel")
  for i=1,16,1
  do
    local exclusion = params:get("midi_control_exclusion"..i)
    if exclusion == 1 or skip_exclusions == false then
      local hex_val = "0x"..string.format("%x",channel_vals_16n[i])
      table.insert(data_table,hex_val)
    else
      local hex_val = "0x"..string.format("%x",exclusion_cc_channel)
      table.insert(data_table,hex_val)
      print("excluding control#/exclusion_cc_channel", i, exclusion_cc_channel)
    end
  end

  for i=1,16,1
  do
    local hex_val = "0x"..string.format("%x",cc_vals_16n[i])
    -- print("cc val",i,hex_val,cc_vals_16n[i])
    table.insert(data_table,hex_val)
  end
  send_16n_sysex(midi, data_table)
end

function set_16n_channel_and_cc_values(channel, skip_exclusions)
  local channel_vals_16n = {}
  local cc_vals_16n = {}
  local midi_cc_starting_value = params:get("midi_cc_starting_value")
  skip_exclusions = skip_exclusions or false
  for i=1,16,1
  do
    table.insert(channel_vals_16n, channel)
    table.insert(cc_vals_16n, (midi_cc_starting_value-1)+i) 
  end
  print("set_16n_channel_and_cc_values", channel, skip_exclusions)
  -- tab.print(cc_vals_16n)  
  update16n(channel_vals_16n,cc_vals_16n,skip_exclusions)
end

function midi_helper.update_midi_devices(channel, skip_exclusions)
  print("update_midi_devices: set midi channel", channel)
  -- print("device_16n",device_16n)
  if device_16n then set_16n_channel_and_cc_values(channel, skip_exclusions) end
end

-------------------------------
-- midi handler functions
-------------------------------
local midi_event = function(data) 
  -- tab.print(data)
  local msg = midi.to_msg(data)
  if msg.type == "stop" or msg.type == "start" then
    print("stopping/starting:", msg.type)
  end

  if data[1] == 240 and data[2] == 125 then        --- this is the start byte with a a message from the 16n faderbank 
    midi_event_index = 2
    print("received start byte from the 16n faderbank")
  end
end



function midi_helper:init(num_voices,num_scenes)
  midi.add = function(device)
    
    print("midi device add ", device.id, device.name)
    update_midi_device_options()
  end
  
  -- setup midi_helper params
  params:add_separator("midi")
  midi_in_device = {}
  
  params:add{
    type = "option", id = "midi_device", name = "midi in device", options = midi_devices, 
    min = 1, max = 16, default = 1, 
    action = function(value)
      midi_in_device = {}
      midi_in_device = midi.connect(value)
      midi_in_device.event = midi_event

      print("select midi device", midi.vports[value].name)
      local device_name = midi.vports[value].name
      if device_name == "16n" then
        device_16n = midi.vports[value].device
      end
    end
  }
  update_midi_device_options()

  params:add_number("midi_cc_starting_value","midi cc starting value",1,127,32)

  params:add_group("midi cc channels", num_voices * num_scenes)
  local default_val = 1
  for voice = 1, num_voices do
    for scene = 1, num_scenes do
      params:add{
        type = "number", id = "voice" .. voice .. "scene" .. scene .. "_cc_channel", name = "voice" .. voice .. " scene" .. scene .. " cc channel",
        min = 1, max = 16, default = default_val, action = function(value) 
      end }
      default_val = default_val + 1
    end
  end

  params:add_group("midi control exclusions", 17)
  params:add{
    type = "number", id = "exclusion_cc_channel", name = "exclusion cc channel",
    min = 1, max = 16, default = 1, action = function(value) 
  end }

  for control = 1, 16 do
    params:add_option("midi_control_exclusion"..control,"control"..control.." exclusion",{"off","on"},1)
  end

  local param=params:lookup_param("midi_device")
  param:bang()
end

return midi_helper