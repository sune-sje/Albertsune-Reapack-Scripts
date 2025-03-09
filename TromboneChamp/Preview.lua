-- @noindex


package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local imgui = require 'imgui' '0.9.3'
local tmb = dofile(reaper.GetResourcePath() .. '/Scripts/Albertsune Reapack Scripts/TromboneChamp/exportTmb.lua')



local boner_track = reaper.CountTracks(0) - 1
local mute_tracks = {}
for str in string.gmatch(reaper.GetExtState("BonerViewer", "activeTracks"), "([^,]+)") do
    table.insert(mute_tracks, tonumber(str))
end
local check_state = false



--get notes from tmb script and format values
local function getNotes()
    local notesTest = tmb.getNotes()
    local LinesTest = notesTest()
    for i, dict in pairs(LinesTest) do
        dict.x_start = dict.x_start * 50
        dict.x_end = dict.x_end * 50
        dict.length = dict.x_end - dict.x_start
        dict.y_start = 1 - (dict.y_start + 200) / 400
        dict.delta_pitch = 1 - (dict.delta_pitch + 200) / 400
        dict.y_end = 1 - (dict.y_end + 200) / 400
    end
    return LinesTest
end

-- Get text (lyrics) from tmb script and format values
local function getText()
    local lyricsR = tmb.getText()
    local lyrics, improv_zones = lyricsR()
    for i, dict in pairs(lyrics) do
        dict.bar = dict.bar * 50
    end
    for i, dict in pairs(improv_zones) do
        dict[1] = dict[1] * 50
        dict[2] = dict[2] * 50
    end
    return lyrics, improv_zones
end


-- Create imgui context
local ctx = imgui.CreateContext('BonerViewer')
reaper.Main_OnCommand(41598, 0) -- move dock to bottom


-- Utility function to interpolate between two colors
local function interpolate_color(color_start, color_end, t)
    local r1, g1, b1, a1 = imgui.ColorConvertU32ToDouble4(color_start)
    local r2, g2, b2, a2 = imgui.ColorConvertU32ToDouble4(color_end)
    local r = r1 + (r2 - r1) * t
    local g = g1 + (g2 - g1) * t
    local b = b1 + (b2 - b1) * t
    local a = a1 + (a2 - a1) * t
    return imgui.ColorConvertDouble4ToU32(r, g, b, a)
end

-- Utility function to calculate a point on a cubic bezier curve
local function bezier_cubic_calc(t, p0, p1, p2, p3)
    local u = 1 - t
    return u ^ 3 * p0 + 3 * u ^ 2 * t * p1 + 3 * u * t ^ 2 * p2 + t ^ 3 * p3
end




--get the start of the arrange window (fuck this so much)
local function get_tcp_width()
    local main_hwnd = reaper.GetMainHwnd()

    
    local arrange_view_hwnd = reaper.JS_Window_FindChildByID(main_hwnd, 1000) -- Arrange View ID is 1000

    if arrange_view_hwnd then
        local _, mainLeft, mainTop, mainRight, mainBottom = reaper.JS_Window_GetRect(main_hwnd)
        local _, left, top, right, bottom = reaper.JS_Window_GetRect(arrange_view_hwnd)

        return left - mainLeft
    else
        reaper.ShowConsoleMsg("Could not find Arrange View window.\n")
    end
end


-- Mute or unmute tracks based on check_state
local function muteUnmute_tracks()
    for _, track_idx in ipairs(mute_tracks) do
        local track = reaper.GetTrack(0, track_idx)  -- Convert to 0-based index
        if track then
            reaper.SetMediaTrackInfo_Value(track, "B_MUTE", check_state and 1 or 0)
        end
    end
    local track = reaper.GetTrack(0, boner_track)
    if track then
        reaper.SetMediaTrackInfo_Value(track, "B_MUTE", check_state and 0 or 1)
    end
    reaper.UpdateArrange()
end

-- Set exit state for the script to let BonerViewer.lua know to exit/reload
local function setExitState()
    reaper.SetExtState("BonerViewer", "exitState", "true", false)
end


-- Global variables to store content
local lines = getNotes()
local lyrics, improv_zones = getText()


--Main GUI loop
local function main()
    --get arrange view size and zoom level, don't mind the magic numbers
    local horizontal_zoom = reaper.GetHZoomLevel()
    local arrange_start, arrange_end = reaper.GetSet_ArrangeView2(0, false, 0, 0)
    local horizontal_scale = horizontal_zoom /
    (reaper.TimeMap2_GetDividedBpmAtTime(0, 0) * (4 / select(2, reaper.TimeMap_GetTimeSigAtTime(0, 0))) / 1.2)
    local tcp_width = get_tcp_width()


    -- Create window
    imgui.SetNextWindowSize(ctx, 400, 300, imgui.Cond_FirstUseEver)
    imgui.SetNextWindowDockID(ctx, -1, imgui.Cond_FirstUseEver)
    local visible, open = imgui.Begin(ctx, 'BonerViewer', true, imgui.WindowFlags_NoSavedSettings) --imgui.WindowFlags_NoMove)--imgui.WindowFlags_NoSavedSettings) -- imgui.WindowFlags_TopMost)
    if not visible then 
        setExitState()
        return 
    end
    if not open then
        imgui.End(ctx)
        setExitState()
        return
    end


    -- Create a child window for the actual preview
    local window_pos_x, window_pos_y = imgui.GetCursorScreenPos(ctx)
    local region_avail_x, region_avail_y = imgui.GetContentRegionAvail(ctx)
    imgui.BeginChild(ctx, 'ScrollableRegion', region_avail_x, region_avail_y, 1, imgui.WindowFlags_NoMouseInputs) -- imgui.WindowFlags_HorizontalScrollbar)--+imgui.WindowFlags_TopMost)-- + imgui.WindowFlags_NoFocusOnAppearing + imgui.WindowFlags_NoBackground)-- + imgui.WindowFlags_NoMouseInputs)

    -- Get the horizontal scroll offset
    local scroll_x = (arrange_start * horizontal_zoom) - tcp_width + 15



    -- Create an invisible dummy with the width of the notes
    local content_width = 0
    for _, line in ipairs(lines) do
        local line_end_x = line.x_end * horizontal_scale
        if line_end_x > content_width then
            content_width = line_end_x
        end
    end
    content_width = content_width + 20
    imgui.SetNextItemAllowOverlap(ctx)
    imgui.Dummy(ctx, content_width, 0)



    -- Draw the lines with gradient colors, customizable outlines, and rounded edges
    local draw_list = imgui.GetWindowDrawList(ctx)
    local retval, color_start = reaper.GetProjExtState(0, "TmbSettings", "note_color_start")
    if retval and tonumber(color_start) then
        color_start = { imgui.ColorConvertU32ToDouble4(tonumber(color_start)) }
        color_start = imgui.ColorConvertDouble4ToU32(color_start[2], color_start[3], color_start[4], color_start[1])
    else
        color_start = imgui.ColorConvertDouble4ToU32(1.0, 0.0, 0.0, 1.0) -- Red
    end
    local retval, color_end = reaper.GetProjExtState(0, "TmbSettings", "note_color_end")
    if retval and tonumber(color_end) then
        color_end = { imgui.ColorConvertU32ToDouble4(tonumber(color_end)) }
        color_end = imgui.ColorConvertDouble4ToU32(color_end[2], color_end[3], color_end[4], color_end[1])
    else
        color_end = imgui.ColorConvertDouble4ToU32(0.0, 0.0, 1.0, 1.0)       -- Blue
    end
    local outline_color = imgui.ColorConvertDouble4ToU32(0.0, 0.0, 0.0, 1.0) -- Black
    local line_thickness = 7
    local outline_thickness = 11
    local radius = line_thickness / 2
    local outline_radius = outline_thickness / 2



    --split drawlist in 3: outline, ends, and notes
    if not imgui.ValidatePtr(splitter, 'ImGui_DrawListSplitter*') then
        splitter = imgui.CreateDrawListSplitter(draw_list)
    end
    imgui.DrawListSplitter_Split(splitter, 3)


    -- Draw each line
    for _, line in ipairs(lines) do
        local x_start = window_pos_x + line.x_start * horizontal_scale - scroll_x
        local x_end = window_pos_x + line.x_end * horizontal_scale - scroll_x
        local y_start = window_pos_y + line.y_start * region_avail_y
        local y_end = window_pos_y + line.y_end * region_avail_y

        -- Control points for bezier curve
        local cp1_x = x_start + (x_end - x_start) / 2
        local cp1_y = y_start
        local cp2_x = x_start + (x_end - x_start) / 2
        local cp2_y = y_end


        -- Draw the outline of the note
        imgui.DrawListSplitter_SetCurrentChannel(splitter, 0)
        imgui.DrawList_AddBezierCubic(draw_list, x_start, y_start, cp1_x, cp1_y, cp2_x, cp2_y, x_end, y_end,
            outline_color, outline_thickness)

        -- Draw ends
        imgui.DrawList_AddCircleFilled(draw_list, x_start, y_start + 0.5, outline_radius, outline_color)
        imgui.DrawList_AddCircleFilled(draw_list, x_end, y_end + 0.2, outline_radius, outline_color)

        imgui.DrawListSplitter_SetCurrentChannel(splitter, 1)
        imgui.DrawList_AddCircleFilled(draw_list, x_start, y_start + 0.5, radius, color_start)
        imgui.DrawList_AddCircleFilled(draw_list, x_end, y_end + 0.2, radius, color_end)

        -- Draw the note with an interpolated color gradient
        imgui.DrawListSplitter_SetCurrentChannel(splitter, 2)
        local num_segments = math.floor((((x_end - x_start) ^ 0.8) / 2) + 2.5)
        for j = 0, num_segments - 1 do
            local t1 = j / num_segments
            local t2 = (j + 1) / num_segments
            local x1 = bezier_cubic_calc(t1, x_start, cp1_x, cp2_x, x_end)
            local y1 = bezier_cubic_calc(t1, y_start, cp1_y, cp2_y, y_end)
            local x2 = bezier_cubic_calc(t2, x_start, cp1_x, cp2_x, x_end)
            local y2 = bezier_cubic_calc(t2, y_start, cp1_y, cp2_y, y_end)
            local color1 = interpolate_color(color_start, color_end, t1)
            local color2 = interpolate_color(color_start, color_end, t2)
            imgui.DrawList_AddLine(draw_list, x1, y1, x2, y2, color1, line_thickness)
        end
    end
    imgui.DrawListSplitter_Merge(splitter)


    -- Add a moving vertical line mimicking Reaper's play cursor
    local play_position = reaper.GetPlayPosition()
    local bpm = reaper.TimeMap2_GetDividedBpmAtTime(0, 0)
    local _, timesig_denom = reaper.TimeMap_GetTimeSigAtTime(0, 0)
    local pixels_per_beat = 5 * bpm / 6 * (4 / timesig_denom)
    local play_cursor_x = window_pos_x + play_position * pixels_per_beat * horizontal_scale - scroll_x
    imgui.DrawList_AddLine(draw_list, play_cursor_x, window_pos_y, play_cursor_x, window_pos_y + region_avail_y,
        imgui.ColorConvertDouble4ToU32(0.0, 0.0, 0.0, 1.0), 5.0) -- Green vertical line

    

    -- Draw lyrics
    for _, lyric in ipairs(lyrics) do
        local x = window_pos_x + lyric.bar * horizontal_scale - scroll_x
        local y = window_pos_y + 0.9* region_avail_y
        imgui.DrawList_AddText(draw_list, x, y, imgui.ColorConvertDouble4ToU32(1.0, 1.0, 1.0, 1.0), lyric.text)
    end

    -- Draw improv zones
    for _, zone in ipairs(improv_zones) do
        local x_start = window_pos_x + zone[1] * horizontal_scale - scroll_x
        local x_end = window_pos_x + zone[2] * horizontal_scale - scroll_x
        imgui.DrawList_AddText(draw_list, x_start+(x_end-x_start)/2-20, window_pos_y + 0.1 * region_avail_y, imgui.ColorConvertDouble4ToU32(1.0, 1.0, 1.0, 1.0), "Improv")
        imgui.DrawList_AddRectFilled(draw_list, x_start, window_pos_y, x_end, window_pos_y + region_avail_y,
            imgui.ColorConvertDouble4ToU32(0.0, 0.0, 0.0, 0.5))
    end

    imgui.EndChild(ctx)


    -- Draw buttons
    imgui.SetCursorScreenPos(ctx, window_pos_x + 10, window_pos_y + 10)
    if imgui.Button(ctx, "Reload Preview") then
        -- Sets external state to reload the script, then exits
        reaper.SetExtState("BonerViewer", "doReload", "true", false)
        imgui.End(ctx)
        setExitState()
        return
    end

    imgui.SameLine(ctx)
    if imgui.Button(ctx, "Edit tmb values") then
        if reaper.GetExtState("BonerViewer", "isSetting") ~= "true" then
            reaper.SetExtState("BonerViewer", "isSetting", "true", false)
            dofile(reaper.GetResourcePath() .. '/Scripts/Albertsune Reapack Scripts/TromboneChamp/tmbSettings.lua')
        else
            reaper.SetExtState("BonerViewer", "isSetting", "false", false)
        end
    end

    imgui.SameLine(ctx)
    if imgui.Button(ctx, "Export Tmb") then
        tmb.export()
    end

    imgui.SetCursorScreenPos(ctx, window_pos_x + 10, window_pos_y + 40)

    if imgui.Checkbox(ctx, 'Slide audio', check_state) then
        check_state = not check_state
        muteUnmute_tracks()
    end

    if check_state then
        imgui.PushItemWidth(ctx, 200)
        local changed, new_volume_db = imgui.SliderDouble(ctx, "Volume (dB)", 20 * math.log(reaper.GetMediaTrackInfo_Value(reaper.GetTrack(0, boner_track), "D_VOL"), 10), -60, 12)
        if changed then
            reaper.SetMediaTrackInfo_Value(reaper.GetTrack(0, boner_track), "D_VOL", 10^(new_volume_db/ 20))
        end
    end



    imgui.End(ctx)


    reaper.defer(main)
end

-- Makes sure to reset track mutes when the script exits
reaper.atexit(function ()
    check_state = false
    muteUnmute_tracks()
end)
main()



