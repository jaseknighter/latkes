local gc = {}
local grid = grid.connect() -- 'grid' represents a connected grid

grid_dirty = false -- script initializes with no LEDs drawn
local momentary = {} -- meta-table to track the state of all the grid keys
-- keys = {} -- meta-table to track the keys that should be lit
transport_keys={}
transport_pages={}

------------------------------------
gc.key_area={}
function gc.key_area:new ()
  ka = {}
  setmetatable(ka, self)
  self.__index = self


  function ka:set_area(starting_key,num_keys,keys_per_row,keys_per_col,max_sets,col_spacing,brightness,col_offset,row_offset) 
    print("set area start",starting_key,num_keys,keys_per_row,keys_per_col,max_sets,col_spacing,brightness)
    print("col_offset,row_offset",col_offset,row_offset)
    local key_counter=num_keys-(starting_key-1)
    local key_area_size=keys_per_row*keys_per_col
    local num_key_areas = math.ceil(num_keys/key_area_size)
    self.brightness = brightness or 10
    self.keys={}
    self.ids={}
    for x = 1,16 do -- for each x-column (16 on a 128-sized grid)...
      self.keys[x] = {} -- create a table that holds...
      self.ids[x] = {} -- create a table that holds...
      for y = 1,8 do -- each y-row (8 on a 128-sized grid)!
        self.keys[x][y] = false -- the state of each key is 'off'
      end
    end
    local keys_out_of_bounds
    for i=1,num_key_areas do
      for x=1,keys_per_row do
        for y=1,keys_per_col do
          local col=x+col_spacing+((i-1)*1)+((i-1)*keys_per_col)
          local keyset=math.ceil((col-1)/keys_per_row)
          if key_counter > 0 and keyset<=max_sets then 
            self.keys[col+col_offset][y+row_offset]=true
            self.ids[col+col_offset][y+row_offset]=num_keys-key_counter+1
            -- self.prev_id=self.ids[col][y]
            key_counter=key_counter-1
            -- print(col,y,"true",keyset,max_sets)
          elseif col<=16 and keyset<=max_sets then
            -- print(col,y,"empty")
            self.keys[col+col_offset][y+row_offset]="empty"
          elseif keys_out_of_bounds==nil then
            -- keys_out_of_bounds=key_counter
            keys_out_of_bounds=true
            print("out of bounds with num remaining:",i,x,y,key_counter)
            local num_pages=math.ceil(num_keys/(keys_per_row*keys_per_col))
            print("total pages:",num_pages)
            if self.pages == nil then 
              local current_page = 1
              self:set_pages(num_pages,current_page,num_keys,keys_per_row,keys_per_col,max_sets,col_spacing,brightness,col_offset,row_offset)
            end
            grid_dirty = true -- flag for redraw
            return
          end
        end
      end
    end
    grid_dirty = true -- flag for redraw
  end

  function ka.key(x,y,z) end

  function ka:set_pages(num_pages) end
  
  return ka

-- function gc.key_area.key(x,y,z) end

end

------------------------------------

function gc:init()
  grid:rotation(180)
  print("init grid")
  for x = 1,16 do -- for each x-column (16 on a 128-sized grid)...
    momentary[x] = {} -- create a table that holds...
    -- keys[x] = {} -- create a table that holds...
    for y = 1,8 do -- each y-row (8 on a 128-sized grid)!
      momentary[x][y] = false -- the state of each key is 'off'
      -- keys[x][y] = false -- the state of each key is 'off'
    end
  end
  -- define transport_keys
  transport_keys=gc.key_area:new()
  
  function transport_keys.key(x,y,z)  -- define what happens if a grid key is pressed or released
    local transport_key_exists = transport_keys.ids[x][y]
    if points_data and transport_key_exists and z == 1 then 
      print("grid key id ", transport_keys.ids[x][y], " at " .. x,y)
      local key_id = tostring(transport_keys.ids[x][y] - 1)
      local p_x = points_data[key_id][1]
      local p_y = points_data[key_id][2]
      local retrigger = 1
      osc.send( { "localhost", 57120 }, "/sc_osc/play_slice",{p_x,p_y,params:get("slice_volume"),retrigger})
      local c_x = (util.linlin(1,127,composition_left,127,127*p_x))/127
      local c_y = (util.linlin(1,64,composition_top,64,64*p_y))/64
      print(c_x,c_y)
      params:set("cursor_x",c_x)
      params:set("cursor_y",c_y)
    end
  end  

  function transport_keys:set_pages(
      num_pages,current_page,num_keys,
      keys_per_row,keys_per_col,max_sets,
      col_spacing,brightness,col_offset,row_offset) 
    self.pages=gc.key_area:new()
    self.num_pages = num_pages
    self.current_page = current_page
    print("transport_keys:set_pages",num_pages,current_page)
    transport_keys.pages:set_area(1,num_pages,1,num_pages,1,0,5,0,1)
    
    function transport_keys.pages.key(x,y,z)
      local active_page = transport_keys.pages.ids[x][y]
      if active_page and active_page ~= self.current_page and z == 1 then
        print("transport pages key id ", active_page, " at " .. x,y)
        self.current_page = active_page
        print("new current page",self.current_page)
        local total_keys = keys_per_row*keys_per_col
        local new_starting_key = 1+(active_page-1)*total_keys
        self:set_area(
          new_starting_key,num_keys,keys_per_row,keys_per_col,max_sets,
          col_spacing,brightness,col_offset,row_offset)
        self.current_page = active_page

      end
    end
  end
  
  clock.run(self.grid_redraw_clock) -- start the grid redraw clock
  grid_dirty=true
end

function gc.grid_redraw_clock() -- our grid redraw clock
  while true do -- while it's running...
    clock.sleep(1/30) -- refresh at 30fps.
    if grid_dirty then -- if a redraw is needed...
      gc.grid_redraw() -- redraw...
      grid_dirty = false -- then redraw is no longer needed.
    end
  end
end

function gc.grid_redraw() -- how we redraw
  grid:all(0) -- turn off all the LEDs
  for x = 1,16 do -- for each column...
    for y = 1,8 do -- and each row...
      -- if momentary[x][y] then -- if the key is held...
      if transport_keys and transport_keys.pages then
        local current_page = transport_keys.current_page
        local key_id = transport_keys.pages.ids[x][y]
        -- if (current_page==key_id) and transport_keys.pages.keys[x][y]==true and momentary[x][y] then -- if the key is held...
        if (current_page==key_id) or momentary[x][y] then -- page is active
          grid:led(x,y,15) -- turn on that LED!
        elseif transport_keys.pages.keys[x][y]==true then -- if the key is held...
          grid:led(x,y,transport_keys.pages.brightness) -- turn on that LED!
        end
      end
      if transport_keys.keys then
        if transport_keys.keys[x][y]==true and momentary[x][y] then -- if the key is held...
          grid:led(x,y,15) -- turn on that LED!
        elseif transport_keys.keys[x][y]==true then -- if the key is held...
          grid:led(x,y,transport_keys.brightness) -- turn on that LED!
        elseif transport_keys.keys[x][y]=="empty" then -- if the key is held...
          grid:led(x,y,4) -- turn on that LED!
        end
      end
    end
  end
  grid:refresh() -- refresh the hardware to display the LED state
end


function grid.key(x,y,z)  -- define what happens if a grid key is pressed or released
  -- this is cool:
  momentary[x][y] = z == 1 and true or false -- if a grid key is pressed, flip it's table entry to 'on'
  -- what ^that^ did was use an inline condition to assign our momentary state.
  -- same thing as: if z == 1 then momentary[x][y] = true else momentary[x][y] = false end
  transport_keys.key(x,y,z)
  if transport_keys.pages then transport_keys.pages.key(x,y,z) end

  grid_dirty = true -- flag for redraw
end

function gc:cleanup()
  transport_keys=nil
  transport_pages=nil
end
return gc