-- local ji = require 'intonation'
-- local gam = ji.gamut()
-- local gamc = {1,17,28,43,52,65,78,100,118,128,136,151}

local lk_grid = {}

lk_grid.Key = {}
function lk_grid.Key:new()
    local k = setmetatable({},{__index=lk_grid.Key})
    k.type="short"
    k.state="unpressed"
    k.long_press_ix=nil
    k.led_target=0
    k.led_current=0
    return k
end

--------------------------------------------------
--- init function
--------------------------------------------------
function lk_grid.init()
    lk_grid.g = grid.connect()

    lk_grid.key_data = {}
    lk_grid.key_data.long_presses = {}

    lk_grid.key_data.reflector_selector = nil
    lk_grid.key_data.lag = nil

    lk_grid.key_data.selected_reflectors = {}

    lk_grid.g.key = function(x,y,z)
        lk_grid.key(x,y,z)
    end
    
    for col=1,16 do
        lk_grid.key_data[col] = {}
        for row=1,8 do
            lk_grid.key_data[col][row] = lk_grid.Key:new()
        end
    end
    
    for col=1,MAX_REFLECTORS_PER_SCENE do
        lk_grid.key_data.selected_reflectors[col] = nil
        lk_grid.ui_groups["reflector"..col] = {
            led_on=10,
            led_off=3,
            col_start=col,
            col_end=col,
            row_start=1,
            row_end=7,
            k_type="group_single",
            on_release=lk_grid.set_reflector,
            direction="v"
        }
    end
end

--------------------------------------------------
--- grid key function
--------------------------------------------------
lk_grid.key = function(x,y,z)
    if z == 1 then --pressed
        lk_grid.key_data[x][y].long_press = clock.run(function() 
            lk_grid.key_data[x][y].state="pressed"
            clock.sleep(0.5)
            if lk_grid.key_data[x][y].state=="pressed" then
                lk_grid.key_data[x][y].type="long"
            end
            -- check for long press buttons
            lk_grid:set_long_presses()
        end)

        for group_name, group_data in pairs(lk_grid.ui_groups) do
            local is_temp = group_data.k_type == "group_single_temp" 
            if is_temp and group_data.on_press then
                local col_start    = group_data.col_start
                local col_end      = group_data.col_end
                local row_start    = group_data.row_start
                local row_end      = group_data.row_end
                if x >= col_start and x <= col_end and y >= row_start and y <= row_end then
                    if group_data.k_type == "group_multi_temp" then
                        group_data.on_press(x - col_start + 1,y - row_start + 1,x,y)
                    else
                        group_data.on_press(x - col_start + 1,y - row_start + 1,x,y)
                    end
                end
            end    
        end    
    elseif z == 0 then -- released
        lk_grid.key_data[x][y].state="unpressed"

        -- check for long press buttons
        lk_grid:set_long_presses()

        -- short and temp press processing
        for group_name, group_data in pairs(lk_grid.ui_groups) do
            local is_short = lk_grid.key_data[x][y].type=="short"
            local is_temp = group_data.k_type == "group_single_temp"
            if (is_short or is_temp) and group_data.on_release then
                local col_start    = group_data.col_start
                local col_end      = group_data.col_end
                local row_start    = group_data.row_start
                local row_end      = group_data.row_end
                local selector     = group_data.p_selector and group_data.p_selector or group_data.k_selector
                if x >= col_start and x <= col_end and y >= row_start and y <= row_end then
                    if group_data.k_type == "group_multi" then
                        group_data.on_release(x - col_start + 1,y - row_start + 1,x,y,selector)
                    else
                        group_data.on_release(x - col_start + 1,y - row_start + 1,x,y,selector)
                    end
                end
            end            
        end    

        if lk_grid.key_data[x][y].long_press then 
            clock.cancel(lk_grid.key_data[x][y].long_press)
            lk_grid.key_data[x][y].long_press=nil
            lk_grid.key_data[x][y].type="short"
        end

    end
end

--------------------------------------------------
--- getters/setters for each grid ui group
--------------------------------------------------

function lk_grid.set_playing(col_ix,row_ix)
    local voice = params:get("active_voice")
    local scene = params:get("active_scene")
    local playing = col_ix
    local lp = lk_grid.key_data.long_presses
    if lp.voices then
        local voices = lk_grid.get_multipress('voices')
        for mvoice=1,#voices do
            local scene = screens.p2ui.scenes[mvoice]
            params:set(voices[mvoice][2] .. "play" .. scene,playing)
        end
    elseif lp.scenes then
        local scenes = lk_grid.get_multipress('scenes')
        for mscene=1,#scenes do
            params:set(voice .. "play" .. scenes[mscene][2],playing)
        end
    else 
        params:set(voice .. "play" .. scene,playing)
    end
end

function lk_grid.set_mode(col_ix,row_ix,selector)
    local voice = params:get("active_voice")
    local mode = col_ix
    local lp = lk_grid.key_data.long_presses
    if lp.voices then
        local voices = lk_grid.get_multipress('voices')
        for mvoice=1,#voices do
            params:set(voices[mvoice][2] .. "sample_mode" ,mode)
        end
    else
        params:set(voice .. "sample_mode",mode)
    end
end

function lk_grid.set_voice(col_ix,row_ix,x,y)
    local voice = row_ix
    params:set("active_voice",voice)
    
end

function lk_grid.set_scene(col_ix,row_ix,x,y)
    local scene = row_ix
    params:set("active_scene",scene)
end

function lk_grid.set_screen(col_ix,row_ix)
    local scene = col_ix
    params:set("active_screen",scene)
end

function lk_grid.set_reflector_states(col_ix,row_ix,x,y,selector)
    local voice = params:get("active_voice")
    local scene = params:get("active_scene")
    local reflector_ix = lk_grid.key_data.reflector_selector

    
    local selectors_rs = lk_grid.get_multipress('reflector_selector')
    local selectors_vc = lk_grid.get_multipress('voices')
    if selectors_rs then
        local selectors = selectors_rs
        for sel=1,#selectors do
            reflector_ix = selectors[sel][1]
            local reflector_id = voice.."-"..reflector_ix..selector..scene
            local state = params:get(reflector_id)
            params:set(reflector_id,state == 1 and 2 or 1)
        end    
    elseif selectors_vc then
        local selectors = selectors_vc
        for sel=1,#selectors do
            local voice = selectors[sel][2]
            for ref_ix=1,get_num_reflectors(voice,scene) do
                local scene = screens.p2ui.scenes[voice]
                local reflector_id = voice.."-"..ref_ix..selector..scene
                local state = params:get(reflector_id)
                params:set(reflector_id,state == 1 and 2 or 1)
            end
        end    
    elseif reflector_ix then
        local reflector_id = voice.."-"..reflector_ix..selector..scene
        local state = params:get(reflector_id)
        params:set(reflector_id,state == 1 and 2 or 1)
    end
end

function lk_grid.get_reflector_selector()
    return lk_grid.key_data.reflector_selector
end

function lk_grid.set_reflector_selector(col_ix,row_ix)
    lk_grid.key_data.reflector_selector = col_ix
    screens:set_selected_ui_area(col_ix*4,2)
    screens:set_active_reflector()
end

function lk_grid.clear_reflector_selector()
    print("clear reflector selector")
    lk_grid.key_data.reflector_selector = nil
end

function lk_grid.set_reflector_param(voice,scene,reflector, row_ix)
    --set grid display data
    --set reflector param
    local reflector_name = reflector.name
    local reflector_id = reflector.id
    local override = grid_overrides[reflector_name]
    if override == nil then
        if params:t(reflector_id) ~= 3 and params:t(reflector_id) ~= 5 then
            local reflector_range = params:get_range(reflector_id)
            if reflector_range[1] and reflector_range[2] then
                local reflector_val = util.linlin(1,7,reflector_range[2], reflector_range[1],row_ix)
                params:set(reflector_id,reflector_val)
            end
        else
            local reflector_val = util.linlin(1,7,1, 0,row_ix)
            params:set_raw(reflector_id,reflector_val)
        end
    else
        local reflector_val = override[reflector_id][row_ix]
        params:set(reflector_id,reflector_val)
    end
end

function lk_grid.set_reflector(col_ix,row_ix,x,y)
    -- print("set reflector",col_ix,row_ix,x,y)
    local voice = params:get("active_voice")
    local scene = params:get("active_scene")    
    local reflector = reflectors_selected_params[voice][scene][x]
    
    if reflector then
        local lp = lk_grid.key_data.long_presses
        if lp.voices then
            local voices = lk_grid.get_multipress('voices')
            for mvoice=1,#voices do
                local voice = voices[mvoice][2]
                local scene = screens.p2ui.scenes[mvoice]
                local reflector = reflectors_selected_params[voice][scene][x]
                if reflector then 
                    lk_grid.set_reflector_param(voice,scene,reflector,row_ix)
                end
            end
        elseif lp.scenes then
            local scenes = lk_grid.get_multipress('scenes')
            for mscene=1,#scenes do
                local scene = scenes[mscene][2]
                local reflector = reflectors_selected_params[voice][scene][x]
                if reflector then 
                    lk_grid.set_reflector_param(voice,scene,reflector,row_ix)
                end
            end
        else
            lk_grid.set_reflector_param(voice,scene,reflector,row_ix)
        end

        lk_grid.key_data.selected_reflectors[reflector] = row_ix
        lk_grid.key_data[x][y].fader_val=10

        screens:set_selected_ui_area(x*4,2)
        screens:set_active_reflector()
        lk_grid.set_reflector_selector(x,row_ix)
    end
end

function lk_grid.clear_lag(col_ix,row_ix)
    lk_grid.key_data.lag_selected = nil
end

function lk_grid.get_lag(col_ix,row_ix)
    local voice = params:get("active_voice")
    local scene = params:get("active_scene")
    local selector = lk_grid.get_reflector_selector()
    local multi_selectors = lk_grid.key_data.long_presses.reflector_selector
    local param = reflectors_selected_params[voice][scene][selector]
    local plag_name = param and eglut.find_param_name(param.name..'_lag')
    if plag_name and selector and param and not multi_selectors then
        local plag_id = voice..plag_name..scene
        local kval, pval
        if params:t(plag_id) ~= 3 and params:t(plag_id) ~= 5 then
            local range = params:get_range(plag_id)
            pval = params:get(plag_id)
            kval = util.linlin(range[1], range[2],4,1,pval)
            kval = util.round(kval)
        else
            pval = params:get_raw(plag_id)
            kval = util.linlin(0,1,4,1,pval)
            kval = util.round(kval)
        end
        return kval
    end
end

function lk_grid.set_lag(col_ix,row_ix)
    local voice = params:get("active_voice")
    local scene = params:get("active_scene")    
    local selector = lk_grid.get_reflector_selector()
    local multi_selectors = lk_grid.key_data.long_presses.reflector_selector
    local selectors = {}
    if multi_selectors then
        selectors = multi_selectors
    elseif selector then
        table.insert(selectors,selector)
    end

    for i=1,#selectors do
        local param = reflectors_selected_params[voice][scene][selectors[i]].name
        local plag_name =  eglut.find_param_name(param..'_lag')
        local plag_id = voice..plag_name..scene
        if params:t(plag_id) ~= 3 and params:t(plag_id) ~= 5 then
            local range = params:get_range(plag_id)
            local val = util.linlin(1,4,range[2], range[1],row_ix)
            params:set(plag_id,val)
            print(reflector_range[1], reflector_range[2],row_ix,reflector_val)
        else
            local val = util.linlin(1,4,1, 0,row_ix)
            params:set_raw(plag_id,val)
        end
    end
end

function lk_grid.get_density_phase_sync_one_shot(col_ix,row_ix)
    return lk_grid.key_data.density_phase_sync_one_shot 
end

function lk_grid.set_density_phase_sync_one_shot(col_ix,row_ix,x,y)
    local voice = params:get("active_voice")
    local scene = params:get("active_scene")
    
    params:set(voice .. 'density_phase_sync_one_shot' .. scene,voice-1)
    lk_grid.key_data.density_phase_sync_one_shot = col_ix

end

function lk_grid.clear_density_phase_sync_one_shot(col_ix,row_ix)
    lk_grid.key_data.density_phase_sync_one_shot = nil
end

function lk_grid.get_rec_play_sync(col_ix,row_ix)
    return lk_grid.key_data.rec_play_sync
end

function lk_grid.set_rec_play_sync(col_ix,row_ix)
    local voice = params:get("active_voice")
    local scene = params:get("active_scene")


    local lp = lk_grid.key_data.long_presses
    if lp.voices then
        local voices = lk_grid.get_multipress('voices')
        for mvoice=1,#voices do
            local scene = screens.p2ui.scenes[mvoice]
            params:set(voices[mvoice][2] .. 'rec_play_sync' .. scene,playing)
        end
    elseif lp.scenes then
        local scenes = lk_grid.get_multipress('scenes')
        for mscene=1,#scenes do
            params:set(voice .. 'rec_play_sync' .. scenes[mscene][2],playing)
        end
    else 
        params:set(voice .. 'rec_play_sync' .. scene,1)        
    end
    lk_grid.key_data.rec_play_sync = col_ix
end

function lk_grid.clear_rec_play_sync(col_ix,row_ix)
    lk_grid.key_data.rec_play_sync = nil
end


function lk_grid.get_volume_send(col_ix,row_ix,x,y)
    local voice = params:get("active_voice")
    local scene = params:get("active_scene")    
    local param = col_ix == 11 and "volume" or "send"
    local pval = params:get(voice..param..scene)
    pval = util.linlin(0,1,8,1,pval)
    return util.round(pval)
    
end

function lk_grid.set_volume_send(col_ix,row_ix,x,y)
    local pval = util.linlin(1,8,1,0,row_ix)
    local param = x == 11 and "volume" or "send"

    local lp = lk_grid.key_data.long_presses
    if lp["voices"] then
        local voices = lp["voices"]
        for mvoice=1,#voices do
            local scene = screens.p2ui.scenes[mvoice]
            params:set(voices[mvoice][2]..param..scene,pval)
        end
    elseif lp["scenes"] then
        local voice = params:get("active_voice")
        local scenes = lp["scenes"]
        for mscene=1,#scenes do
            params:set(voice..param..scenes[mscene][2],pval)
        end
    else
        local voice = params:get("active_voice")
        local scene = params:get("active_scene")    
        params:set(voice..param..scene,pval)
    end
end

function lk_grid.get_rec_pre_levels(col_ix,row_ix,x,y)
    local voice = params:get("active_voice")
    local param = col_ix == 13 and "live_rec_level" or "live_pre_level"
    local pval = params:get(voice..param)
    pval = util.linlin(0,1,6,1,pval)
    return util.round(pval)
end

function lk_grid.set_rec_pre_levels(col_ix,row_ix,x,y)
    local pval = util.linlin(1,6,1,0,row_ix)
    local param = x == 13 and "live_rec_level" or "live_pre_level"

    local lp = lk_grid.key_data.long_presses
    if lp["voices"] then
        local voices = lp["voices"]
        for mvoice=1,#voices do
            local scene = screens.p2ui.scenes[mvoice]
            params:set(voices[mvoice][2]..param..scene,pval)
        end
    else
        local voice = params:get("active_voice")
        params:set(voice..param,pval)
    end
end

--------------------------------------------------
--- define ui groups
--------------------------------------------------

lk_grid.ui_groups = {
    voices = {
        led_on=15,
        led_off=5,
        col_start=15,
        col_end=15,
        row_start=1,
        row_end=4,
        k_type="group_multi",
        p_selector="active_voice",
        on_release=lk_grid.set_voice,
        direction="v"
    },
    scenes = {
        led_on=15,
        led_off=5,
        col_start=16,
        col_end=16,
        row_start=1,
        row_end=4,
        k_type="group_multi",
        p_selector="active_scene",
        on_release=lk_grid.set_scene,
        direction="v"
    },
    playing = {
        led_on=15,
        led_off=5,
        col_start=15,
        col_end=16,
        row_start=6,
        row_end=6,
        k_type="group_single",
        p_selector="play",
        p_type="voice_scene",
        on_release=lk_grid.set_playing,
        direction=nil
    },
    mode = {
        led_on=15,
        led_off=5,
        col_start=15,
        col_end=16,
        row_start=7,
        row_end=7,
        k_type="group_single",
        p_selector="sample_mode",
        p_type="voice",
        on_release=lk_grid.set_mode,
        direction="h"
    },
    screens = {
        led_on=15,
        led_off=5,
        col_start=15,
        col_end=16,
        row_start=8,
        row_end=8,
        k_type="group_single",
        p_selector="active_screen",
        on_release=lk_grid.set_screen,
        direction="h"
    },
    reflector_record = {
        led_on=15,
        led_off=5,
        col_start=9,
        col_end=9,
        row_start=6,
        row_end=6,
        k_type="single",
        p_selector="record",
        p_type="voice_reflector_scene",
        on_release=lk_grid.set_reflector_states,
        direction=nil
    },
    reflector_loop = {
        led_on=15,
        led_off=5,
        col_start=9,
        col_end=9,
        row_start=7,
        row_end=7,
        k_type="single",
        p_selector="loop",
        p_type="voice_reflector_scene",
        on_release=lk_grid.set_reflector_states,
        direction=nil
    },
    reflector_play = {
        led_on=15,
        led_off=5,
        col_start=9,
        col_end=9,
        row_start=8,
        row_end=8,
        k_type="single",
        p_selector="play",
        p_type="voice_reflector_scene",
        on_release=lk_grid.set_reflector_states,
        direction=nil
    },        
    reflector_selector = {
        led_on=15,
        led_off=6,
        col_start=1,
        col_end=8,
        row_start=8,
        row_end=8,
        k_type="group_multi",
        -- p_selector="active_screen",
        k_selector=lk_grid.get_reflector_selector,
        on_release=lk_grid.set_reflector_selector,
        -- on_release=lk_grid.clear_reflector_selector,
        direction="h"
    },
    -- lag = {
    --     led_on=15,
    --     led_off=3,
    --     col_start=9,
    --     col_end=9,
    --     row_start=1,
    --     row_end=4,
    --     k_type="group_single_temp",
    --     k_selector=lk_grid.get_lag,
    --     on_press=lk_grid.set_lag,
    --     on_release=lk_grid.clear_lag,
    --     direction="v"
    -- },        
    density_phase_sync_one_shot = {
        led_on=15,
        led_off=8,
        col_start=13,
        col_end=13,
        row_start=8,
        row_end=8,
        k_type="group_single_temp",
        k_selector=lk_grid.get_density_phase_sync_one_shot,
        on_press=lk_grid.set_density_phase_sync_one_shot,
        on_release=lk_grid.clear_density_phase_sync_one_shot,
        direction=nil
    },
    rec_play_sync = {
        led_on=15,
        led_off=5,
        col_start=14,
        col_end=14,
        row_start=8,
        row_end=8,
        k_type="group_single_temp",
        k_selector=lk_grid.get_rec_play_sync,
        on_press=lk_grid.set_rec_play_sync,
        on_release=lk_grid.clear_rec_play_sync,
        direction=nil
    },
    volume = {
        led_on=15,
        led_off=5,
        col_start=11,
        col_end=11,
        row_start=1,
        row_end=8,
        k_type="group_single",
        k_selector=lk_grid.get_volume_send,
        on_release=lk_grid.set_volume_send,
        direction="v"
    },
    send = {
        led_on=15,
        led_off=5,
        col_start=12,
        col_end=12,
        row_start=1,
        row_end=8,
        k_type="group_single",
        k_selector=lk_grid.get_volume_send,
        on_release=lk_grid.set_volume_send,
        direction="v"
    },
    live_rec_level = {
        led_on=15,
        led_off=5,
        col_start=13,
        col_end=13,
        row_start=1,
        row_end=6,
        k_type="group_single",
        k_selector=lk_grid.get_rec_pre_levels,
        on_release=lk_grid.set_rec_pre_levels,
        direction="v"
    },
    live_pre_level = {
        led_on=15,
        led_off=5,
        col_start=14,
        col_end=14,
        row_start=1,
        row_end=6,
        k_type="group_single",
        k_selector=lk_grid.get_rec_pre_levels,
        on_release=lk_grid.set_rec_pre_levels,
        direction="v"
    },
   
}
--------------------------------------------------
--- generic grid functions
--------------------------------------------------
function lk_grid:get_ui_group(col,row)
    for group_name, group_data in pairs(lk_grid.ui_groups) do
        local col_start    = group_data.col_start
        local col_end      = group_data.col_end
        local row_start    = group_data.row_start
        local row_end      = group_data.row_end            
        if col >= col_start and col <= col_end and row >= row_start and row <= row_end then
            return group_name
        end
    end
end

function lk_grid.get_multipress(group)
    local keys = lk_grid.key_data.long_presses[group]
    return keys
end

function lk_grid.set_multipress(group,colrow)
    local lp = lk_grid.key_data.long_presses
    local key_slot = colrow == "col" and 1 or 2
    local keys = {}
    for key=1,#lp[group] do
        table.insert(keys,lp[group][key][key_slot])
    end
end

function lk_grid:set_long_presses()
    local lp = {}
    local group = nil
    for col=1,16 do
        for row=1,8 do
            local key = lk_grid.key_data[col][row]
            -- print(key.type,key.state)
            if key.type == "long" and key.state == "pressed" then
                group = lk_grid:get_ui_group(col,row)
                if group and lp[group] == nil then lp[group] = {} end
                table.insert(lp[group],{col,row})
            end
            lk_grid.key_data.long_presses = lp
        end
    end
    if group then
        local k_type = lk_grid.ui_groups[group].k_type
        local multi = string.find(k_type,"multi")
        if multi then lk_grid.set_multipress(group,group.direction) end
    end

end


function lk_grid:get_num_cols_rows(col_start,col_end,row_start,row_end)
    local num_cols = col_end - col_start + 1
    local num_rows = row_end - row_start + 1
    return num_cols,num_rows
end

--------------------------------------------------
--- display functions
--------------------------------------------------
function lk_grid.display_reflectors()
    local voice = params:get("active_voice")
    local scene = params:get("active_scene")    
    for col_ix=1,MAX_REFLECTORS_PER_SCENE do
        local group = lk_grid.ui_groups["reflector"..col_ix]

        local reflector = reflectors_selected_params[voice][scene][col_ix]
        if reflector then
            local reflector_id = reflector.id
            local selected_key, selected_key_rounded
            local reflector_name = reflector.name                
            local override = grid_overrides[reflector_name]
            if override == nil then        
                if params:t(reflector_id) ~= 3 and params:t(reflector_id) ~= 5 then
                    local reflector_val = params:get(reflector_id)
                    local reflector_range = params:get_range(reflector_id)
                    selected_key = util.linlin(reflector_range[1],reflector_range[2],7,1,reflector_val)
                    selected_key_rounded = util.round(selected_key)
                else
                    local reflector_val = params:get_raw(reflector_id)
                    selected_key = util.linlin(0,1,7,1,reflector_val)
                    selected_key_rounded = util.round(selected_key)
                end
            else
                for row_ix=1,7 do
                    if selected_key_rounded then break end
                    local reflector_val = params:get(reflector_id)
                    selected_key = util.linlin(0,1,7,1,reflector_val)
                    if row_ix == 1 and reflector_val >= override[reflector_id][row_ix] then 
                        selected_key_rounded = 1
                    elseif row_ix == 7 and reflector_val <= override[reflector_id][row_ix] then 
                        selected_key_rounded = 7
                    else
                        if reflector_val >= override[reflector_id][row_ix] and reflector_val <= override[reflector_id][row_ix-1] then
                            selected_key_rounded = row_ix
                        end
                    end
                end
            end
            for row_ix=1,7 do
                if row_ix == selected_key_rounded then
                    lk_grid.key_data[col_ix][row_ix].led_target = group.led_on 
                else
                    lk_grid.key_data[col_ix][row_ix].led_target = group.led_off 
                end
                local target = lk_grid.key_data[col_ix][row_ix].led_target
                local current = lk_grid.key_data[col_ix][row_ix].led_current
                local new_current = current
                if current + 0.1 < target or current - 0.1 > target then
                    new_current = target > current and current + 0.05 or current - 0.05
                    lk_grid.key_data[col_ix][row_ix].led_current = new_current
                else
                    lk_grid.key_data[col_ix][row_ix].led_current = target
                    new_current = target
                end
                lk_grid.g:led(col_ix,row_ix,util.round(new_current))
            end

            -- for rows that aren't overrideen check for selected key values that are offset
            if override == nil and selected_key ~= selected_key_rounded then
                local offset_key 
                if selected_key > selected_key_rounded then 
                    offset_key = selected_key_rounded + 1
                else 
                    offset_key = selected_key_rounded - 1
                end 
                local offset_current = lk_grid.key_data[col_ix][offset_key].led_current
                local active_current = lk_grid.key_data[col_ix][selected_key_rounded].led_current
                local diff = math.abs(active_current-offset_current)
                local offset_mult = math.abs(selected_key - selected_key_rounded)
                local offset_led = math.floor((diff * offset_mult) + offset_current)
                lk_grid.g:led(col_ix,offset_key,offset_led)
            end
        else -- reflector not configured, dim the reflector and reflector_selector  keys
            for row_ix=1,7 do
                lk_grid.g:led(col_ix,row_ix,1)
                lk_grid.g:led(col_ix,8,3)
            end
    
        end
    end
end


function lk_grid:pulse(cols,rows,low,hi)
    for i=1,#cols do
        local col_ix=cols[i]
        for j=1,#rows do
            local row_ix = rows[j]
            local first_key =  lk_grid.key_data[cols[1]][rows[1]]
            local key =  lk_grid.key_data[col_ix][row_ix]
            key.pulse_low = low
            key.pulse_hi = hi
            if not key.pulse_current then 
                if first_key.pulse_current then
                    key.pulse_current = first_key.pulse_current
                else
                    key.pulse_current = low 
                end
            end
            
            if key.pulse_current + 0.1 < key.pulse_hi then
                if i==1 and j==1 then
                    key.pulse_current = key.pulse_current + 0.1
                else
                    key.pulse_current = first_key.pulse_current
                end
                lk_grid.g:led(col_ix,row_ix,util.round(key.pulse_current))
            else
                key.pulse_current = key.pulse_low
            end      
        end 
    end
end

function lk_grid:pulse_multis()
    -- lk_grid:pulse(9,1,5,10)
    for group,group_data in pairs(lk_grid.key_data.long_presses) do 
        local k_type = lk_grid.ui_groups[group].k_type
        if k_type == "group_multi" or k_type == "group_multi_temp" then
            local cols = {}
            local rows = {}
            -- local direction = lk_grid.ui_groups.direction
            for i=1,#group_data do 
                local col = group_data[i][1]
                local row = group_data[i][2]
                table.insert(cols,col)
                table.insert(rows,row)
            end
            lk_grid:pulse(cols,rows,5,10)
        end
    end
end

function lk_grid:display_ui_group(group_name,group)
    local voice = params:get("active_voice")
    local scene = params:get("active_scene")
    local k_type = group.k_type
    --display simple button
    if k_type == "single" then
        local num_cols, num_rows = lk_grid:get_num_cols_rows(
            group.col_start, group.col_end, group.row_start, group.row_end
        )
        for col=1, num_cols do
            for row = 1, num_rows do
                local col_ix = col + group.col_start - 1
                local row_ix = row + group.row_start - 1
                local selector
                if group.p_type == "voice_scene" then
                    local scene = params:get("active_scene")
                    selector = params:get(voice .. group.p_selector .. scene)
                    lk_grid.g:led(col_ix,row_ix, selector == 1 and 5 or 15)
                elseif group.p_type == "voice" then
                    selector = params:get(voice .. group.p_selector)
                    lk_grid.g:led(col_ix,row_ix, selector == 1 and 5 or 15)
                elseif group.p_type == "voice_reflector_scene" then
                    local reflector_selector = lk_grid.key_data.reflector_selector
                    local reflector_tab = reflector_tab and reflector_tab.count > 0
                    -- local selector = reflector_count > 0 
                    if reflector_selector then
                        if reflector_tab or 
                        group.p_selector == "record" or 
                        group.p_selector == "loop" or 
                        group.p_selector == "play" then
                            local p_id = voice.."-"..reflector_selector..group.p_selector..scene
                            local selector = params:get(p_id)
                            lk_grid.g:led(col_ix,row_ix, selector == 1 and 5 or 15)
                        else    
                            lk_grid.g:led(col_ix,row_ix, 5)
                        end    
                    else
                        lk_grid.g:led(col_ix,row_ix, 3)
                    end
                end
            end
        end
    end

    --display simple single selector groups
    if k_type == "group_single" or k_type == "group_single_temp" then
        local num_cols, num_rows = lk_grid:get_num_cols_rows(
            group.col_start, group.col_end, group.row_start, group.row_end
        )
        for col=1, num_cols do
            for row = 1, num_rows do
                local col_ix = col + group.col_start - 1
                local row_ix = row + group.row_start - 1
                if group.p_selector then
                    local selector
                    if group.p_type == "voice_scene" then
                        selector = params:get(voice..group.p_selector..scene)
                    elseif group.p_type == "voice" then
                        local voice = params:get("active_voice")
                        selector = params:get(voice..group.p_selector)
                    else
                        selector = params:get(group.p_selector)
                    end
                    if group.direction == "v" then
                        lk_grid.g:led(col_ix,row_ix,row == selector and group.led_on or group.led_off)
                    else
                        lk_grid.g:led(col_ix,row_ix,col == selector and group.led_on or group.led_off)
                    end
                elseif group.k_selector then
                    local selector = group.k_selector(col_ix,row_ix,x,y)
                    if group.direction == "v" then
                        local voice = params:get("active_voice")
                        if group_name == "send" and voice == eglut.num_voices then
                            lk_grid.g:led(col_ix,row_ix,3)
                        else
                            lk_grid.g:led(col_ix,row_ix,row == selector and group.led_on or group.led_off)
                        end
                    else
                        -- if selector ~= nil then 
                            -- print(group_name,col_ix,row_ix,col,row,selector)
                        -- end
                        lk_grid.g:led(col_ix,row_ix,col == selector and group.led_on or group.led_off)
                    end
                end
            end
        end
    end

    --display multi selector groups
    if k_type == "group_multi" or k_type == "group_multi_temp" then
        local num_cols, num_rows = lk_grid:get_num_cols_rows(
            group.col_start, group.col_end, group.row_start, group.row_end
        )
        for col=1, num_cols do
            for row = 1, num_rows do
                local col_ix = col + group.col_start - 1
                local row_ix = row + group.row_start - 1
                local selector
                if group.p_selector then
                    if group.p_type == "voice" then
                        local voice = params:get("active_voice")
                        selector = params:get(voice..group.p_selector)
                    else
                        selector = params:get(group.p_selector)
                    end
                else
                    selector=group.k_selector()
                end
                if group.direction == "v" then
                    lk_grid.g:led(col_ix,row_ix,row == selector and group.led_on or group.led_off)
                else
                    lk_grid.g:led(col_ix,row_ix,col == selector and group.led_on or group.led_off)
                end
            end
        end
    end

    --display reflector groupss
    lk_grid.display_reflectors()

end

function lk_grid:redraw()
    for k,v in pairs(lk_grid.ui_groups) do
        lk_grid:display_ui_group(k,v)
    end
    lk_grid:pulse_multis()
    lk_grid.g:refresh()
    
end

return lk_grid