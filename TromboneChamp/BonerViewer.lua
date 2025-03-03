--[[ 
@description BonerViewer
@about
    Allows you to preview, edit, and export Trombone Champ charts directly from reaper.
@author Albertsune
@version 1.0
@changelog
    Initial release
@provides
    [main] BonerViewer.lua
    [main] exportTmb.lua
    [main] tmbSettings.lua
    MIDIUtils.lua https://raw.githubusercontent.com/jeremybernstein/ReaScripts/main/MIDI/MIDIUtils.lua
    dkjson.lua

--]]



package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local imgui = require 'imgui' '0.9.3'
local tmb = dofile(reaper.GetResourcePath() .. '/Scripts/Albertsune Reapack Scripts/TromboneChamp/exportTmb.lua')





--get notes from tmb script and format values
local function getNotes()
    local notesTest = tmb.getNotes("bwa")
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


-- Create imgui context
local ctx = imgui.CreateContext('Dockable Window')


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


--[[
local function get_tcp_width2()
    track = reaper.GetTrack(0, 0)
    retval, stringNeedBig = reaper.GetSetMediaTrackInfo_String(track, "P_UI_RECT:tcp.size", "", false)
    --tcp = reaper.JS_Window_GetLongPtr(reaper.JS_Window_FindChildByID(reaper.GetMainHwnd(), 1000), "ID") -- TCP window
    tcpTable = {}
    for str in string.gmatch(stringNeedBig, "([^%s]+)") do
        table.insert(tcpTable, str)
    end
    --stringNeedBig = table.pack(string.gmatch(tcpTable[3], "([^%s]+)"))
    reaper.ShowConsoleMsg("tcp: " .. tcpTable[3] .. "\n")
    if not retval then return 0 end

    local l, _, r, _ = reaper.JS_Window_GetClientRect(tcp)
    return tonumber(tcpTable[3]) -- TCP width
end
--]]




--get the start of the arrange window (fuck this so much)
local function get_tcp_width()
    -- Get REAPER's main window
    local main_hwnd = reaper.GetMainHwnd()

    -- Arrange View ID is 1000
    local arrange_view_hwnd = reaper.JS_Window_FindChildByID(main_hwnd, 1000)

    if arrange_view_hwnd then
        -- Get Arrange View position
        local left, top, right, bottom = reaper.JS_Window_GetRect(arrange_view_hwnd)


        return top
    else
        reaper.ShowConsoleMsg("Could not find Arrange View window.\n")
    end

    return top
end


-- Global variable to store lines
local lines = getNotes()

local function main()
    --get arrange view size and zoom level, don't mind the magic numbers
    local horizontal_zoom = reaper.GetHZoomLevel()
    local arrange_start, arrange_end = reaper.GetSet_ArrangeView2(0, false, 0, 0)
    local horizontal_scale = horizontal_zoom /
    (reaper.TimeMap2_GetDividedBpmAtTime(0, 0) * (4 / select(2, reaper.TimeMap_GetTimeSigAtTime(0, 0))) / 1.2)
    local tcp_width = get_tcp_width()


    --create window
    imgui.SetNextWindowSize(ctx, 400, 300, imgui.Cond_FirstUseEver)
    imgui.SetNextWindowDockID(ctx, 0, imgui.Cond_FirstUseEver)
    local visible, open = imgui.Begin(ctx, 'Dockable Window', true, imgui.WindowFlags_None) -- imgui.WindowFlags_TopMost)
    if visible then
        --make a child window for the actual preview
        local window_pos_x, window_pos_y = imgui.GetCursorScreenPos(ctx)
        local region_avail_x, region_avail_y = imgui.GetContentRegionAvail(ctx)
        imgui.BeginChild(ctx, 'ScrollableRegion', region_avail_x, region_avail_y, 1, imgui.WindowFlags_NoMouseInputs) -- imgui.WindowFlags_HorizontalScrollbar)--+imgui.WindowFlags_TopMost)-- + imgui.WindowFlags_NoFocusOnAppearing + imgui.WindowFlags_NoBackground)-- + imgui.WindowFlags_NoMouseInputs)

        -- Get the horizontal scroll offset
        local scroll_x = (arrange_start * horizontal_zoom) - tcp_width + 10



        --create an invisible dummy with the width of the notes
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
        local color_start = imgui.ColorConvertDouble4ToU32(1.0, 0.0, 0.0, 1.0)   -- Red
        local color_end = imgui.ColorConvertDouble4ToU32(0.0, 0.0, 1.0, 1.0)     -- Blue
        local outline_color = imgui.ColorConvertDouble4ToU32(0.0, 0.0, 0.0, 1.0) -- Black
        local line_thickness = 7
        local outline_thickness = 11
        local radius = line_thickness / 2
        local outline_radius = outline_thickness / 2



        --split drawlist in 3: outline, ends, and note
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
            imgui.ColorConvertDouble4ToU32(0.0, 0.0, 0.0, 1.0), 5.0)                                                                                                          -- Green vertical line

        imgui.EndChild(ctx)


        -- Draw buttons
        imgui.SetCursorScreenPos(ctx, window_pos_x + 10, window_pos_y + 10)
        if imgui.Button(ctx, "Reload Preview") then
            lines = getNotes()
        end
        imgui.SameLine(ctx)
        if imgui.Button(ctx, "Edit tmb values") then
            dofile(reaper.GetResourcePath() .. '/Scripts/tmbSettings.lua')
        end
        imgui.SameLine(ctx)
        if imgui.Button(ctx, "Export Tmb") then
            tmb.export()
        end



        imgui.End(ctx)
    end

    if open then
        reaper.defer(main)
    else
        imgui.DestroyContext(ctx)
    end
end

reaper.defer(main)
