--[[
@description BonerViewer
@about
    Allows you to preview, edit, and export Trombone Champ charts directly from reaper.
@author Albertsune
@version 2.0
@changelog
    Huge backend refactor. Should work the same, but faster and more stable.
    ** features **
    added a diffcalc button. Shows you the difficulty of the chart, alongside rating criteria requirements. Click an error to jump to it.
    Added tap support
    Added a "set to edit cursor" button for the endpoint in tmbSettings
    Added support for bgEvents. You still have to make them in unity yourself, but you can mark them in reaper and they'll be exported.
    ** changes **
    changed the visuals of the notes to be more similar to trombone champ
    Actually draws the correct slide shape (prev a bezier curve approximation)
    the audio preview can now play out of range notes
    audio preview will no longer run out of breath
    audio preview should also now sound better, especially for short notes
    textevent of type marker is now assumed to be bgevents
    ** fixes **
    now properly keeps track of tracks to mute
    tmbSettings and ExportTmb should now work properly when run standalone
    BonerViewer will now exit when changing project
    Will also no longer overwrite tmbSettings when changing project
    The volume of the preview track is now persistent and no longer depends on the tracks it is copying from
    Preview track actually now copies items instead of emulating them
    ** optimizations **
    drawing:
    - Now only draws notes actually on screen, massive performance increase.
    - Slider segments should now all have about the same pixel length, reducing draw calls for small slides.
    - Straight notes are now using rectFilledMulitcolor which automatically interpolates the color through gpu. Also means it doesn't do the curve interpolation for horizontal lines.
    - added taps to start of long notes
    - now caches the drawing primitives and only recalculates them them when the window moves
    ** misc **
    now uses an OOP implementation to handle events through tcUtils
    made modules actually be modules and not run through doFile (why tf didn't i do that in the first place)
    combined common functions into the tcUtils module, see more here: --TODO: add link
    beefed up error handling
    cleaned up code (thank god)
@provides
    [main] BonerViewer.lua
    [main=main] ExportTmb.lua
    [main=main] tmbSettings.lua
    BonerViewer/SlideAudio.lua
    BonerViewer/TcUtils.lua
    BonerViewer/MIDIUtils.lua https://raw.githubusercontent.com/jeremybernstein/ReaScripts/main/MIDI/MIDIUtils.lua
    BonerViewer/dkjson.lua https://raw.githubusercontent.com/LuaDist/dkjson/refs/heads/master/dkjson.lua
    BonerViewer/Samples/*.wav

--]]
local r = reaper
if not pcall(r.ImGui_GetBuiltinPath) then
    r.ShowMessageBox("Error: ReaImGui is not installed.\n\nPlease install it via ReaPack.", "Missing Dependency", 0)
    return
end
if not r.APIExists("JS_ReaScriptAPI_Version") then
    r.ShowMessageBox("Error: js_ReaScriptAPI is not installed.\n\nPlease install it via ReaPack.", "Missing Dependency", 0)
    return
end
local script_path = "/Scripts/Albertsune Reapack Scripts"
package.path = r.ImGui_GetBuiltinPath() .. "/?.lua" .. ";" .. package.path
package.path = r.GetResourcePath() .. script_path .. "/TromboneChamp/BonerViewer/?.lua" .. ";" .. package.path
package.path = r.GetResourcePath() .. script_path .. "/TromboneChamp/?.lua" .. ";" .. package.path
local function prequire(module)
    local success, result = pcall(require, module)
    if not success then
        r.ShowConsoleMsg(result .. "\n" .. debug.traceback() .. "\n")
        r.ShowMessageBox("Couldn't find " .. module,                  "Missing dependency", 0)
        return nil
    end
    return result
end

local imgui = require("imgui")("0.9.3")
if not imgui then return end
local tmb = prequire("ExportTmb")
if not tmb then return end
local tcutils = prequire("TcUtils")
if not tcutils then return end
local tmbsettings = prequire("tmbSettings")
if not tmbsettings then return end
local slideaudio = prequire("SlideAudio")
if not slideaudio then return end

-- TODO: remove
local mu = prequire("MIDIUtils")
if not mu then return end

local function onError(err)
    r.ShowConsoleMsg(err .. "\n" .. debug.traceback() .. "\n")
end

local function switch(value)
    -- Handing `cases` to the returned function allows the `switch()` function to be used with a syntax closer to c code (see the example below).
    -- This is because lua allows the parentheses around a table type argument to be omitted if it is the only argument.
    return function(cases)
        -- The default case is achieved through the metatable mechanism of lua tables (the `__index` operation).
        setmetatable(cases, cases)
        local f = cases[value]
        if f then
            f()
        end
    end
end

local function round(number, digit_position)
    local precision = 10 ^ (digit_position or 0)
    return math.floor(number * precision + 0.5) / precision
end

local function compareTables(o1, o2, ignore_mt)
    if o1 == o2 then return true end
    if type(o1) ~= type(o2) then return false end
    if type(o1) ~= "table" then return false end

    if not ignore_mt then
        local mt1 = getmetatable(o1)
        if mt1 and mt1.__eq then
            -- compare using built in method
            return o1 == o2
        end
    end

    local key_set = {}
    for key1, value1 in pairs(o1) do
        local value2 = o2[key1]
        if value2 == nil or compareTables(value1, value2, ignore_mt) == false then
            return false
        end
        key_set[key1] = true
    end

    for key2, _ in pairs(o2) do
        if not key_set[key2] then return false end
    end

    return true
end

-- get the start of the arrange window (fuck this so much)
local function getTcpWidth()
    local main_hwnd = r.GetMainHwnd()
    local arrange_view_hwnd = r.JS_Window_FindChildByID(main_hwnd, 1000) -- Arrange View ID is 1000
    if arrange_view_hwnd then
        local _, main_left, main_top, main_right, main_bottom = r.JS_Window_GetRect(main_hwnd)
        local _, left, top, right, bottom = r.JS_Window_GetRect(arrange_view_hwnd)
        return left - main_left
    else
        r.ShowConsoleMsg("Could not find Arrange View window.\n")
    end
end





-- Create imgui context
local ctx = imgui.CreateContext("BonerViewer")
r.Main_OnCommand(41598, 0) -- move dock to bottom
-- globals--
-- items
local splitter
local boner_track
local active_tracks = {}
local active_takes = {}
local lines = {}
local lyrics = {}
local improv_zones = {}
local bg_events = {}
local rv
local audio_preview = false
local rating_diff, errors, warnings, notices = {}, {}, {}, {}
local first_track = r.GetTrack(0, 0)
-- note properties
local line_thickness
local outline_thickness
local outline_color
local color_start
local color_end
-- window properties
local horizontal_zoom
local horizontal_scale
local arrange_start, arrange_end
local tcp_width
local window_pos_x, window_pos_y
local region_avail_x, region_avail_y
local scroll_x
local content_width
-- drawing
local draw_list
local draw_cache =
{
    window_pos_x = window_pos_x,
    window_pos_y = window_pos_y,
    horizontal_scale = horizontal_scale,
    scroll_x = scroll_x,
    region_avail_x = region_avail_x,
    region_avail_y = region_avail_y,
    primitives = {},
}
local function setGlobals()
    -- note properties
    line_thickness = 10
    outline_thickness = 14
    outline_color = imgui.ColorConvertDouble4ToU32(1.0, 1.0, 1.0, 1.0) -- Black
    color_start = tmbsettings.note_color_start
    color_start = imgui.ColorConvertDouble4ToU32(color_start[1], color_start[2], color_start[3], 1)
    color_end = tmbsettings.note_color_end
    color_end = imgui.ColorConvertDouble4ToU32(color_end[1], color_end[2], color_end[3], 1)
    -- window properties
    horizontal_zoom = r.GetHZoomLevel()
    horizontal_scale = horizontal_zoom /
        (r.TimeMap2_GetDividedBpmAtTime(0, 0) * (4 / select(2, r.TimeMap_GetTimeSigAtTime(0, 0))) / 1.2)
    arrange_start, arrange_end = r.GetSet_ArrangeView2(0, false, 0, 0)
    tcp_width = getTcpWidth()
    scroll_x = (arrange_start * horizontal_zoom) - tcp_width + 15
    content_width = 0
    for _, line in ipairs(lines) do
        local line_end_x = (line.start_pos + line.length) * horizontal_scale
        if line_end_x > content_width then
            content_width = line_end_x
        end
    end

    content_width = content_width + 20
    -- drawing
    draw_list = imgui.GetWindowDrawList(ctx)
end



local function checkSetMute()
    for _, track in ipairs(active_tracks) do
        local muted = r.GetMediaTrackInfo_Value(track, "B_MUTE") == 1
        if audio_preview ~= muted then
            r.SetMediaTrackInfo_Value(track, "B_MUTE", audio_preview and 1 or 0)
        end
    end

    local muted = r.GetMediaTrackInfo_Value(boner_track, "B_MUTE") == 1
    if audio_preview == muted then
        r.SetMediaTrackInfo_Value(boner_track, "B_MUTE", audio_preview and 0 or 1)
    end
end
local function doReload()
    setGlobals()
    -- TODO: error handling
    local mute = audio_preview
    if audio_preview then
        audio_preview = false
    end
    if boner_track then
        checkSetMute()
    end
    local takes, _, t = tcutils.getActive()
    active_tracks = t
    active_takes = takes
    rv, boner_track = slideaudio.main()
    if not rv then return end
    rv, lines, lyrics, improv_zones, bg_events = tcutils.midiToTmb(takes)
    if not rv then
        r.ShowMessageBox("Can't convert midi takes to tmb", "Error", 0)
        return
    end
    for _, lyric in pairs(lyrics) do lyric.bar = lyric.bar * 50 end

    for _, zone in pairs(improv_zones) do
        zone.start_pos = zone.start_pos * 50
        zone.end_pos = zone.end_pos * 50
    end

    for _, line in pairs(lines) do
        line.start_pos = line.start_pos * 50
        line.length = line.length * 50
        line.pitch_start = 1 - (line.pitch_start + 200) / 400
        line.pitch_end = 1 - (line.pitch_end + 200) / 400
    end

    for _, event in pairs(bg_events) do
        event.pos2 = event.pos2 * 50
    end

    rating_diff = tcutils.diffCalc(active_takes)
    rating_diff.name = nil
    rating_diff.track_ref = nil
    rating_diff.name = nil
    rating_diff.short_name = nil
    rating_diff.note_hash = nil
    rating_diff.file_hash = nil
    rating_diff.uploaded_at = nil
    rating_diff.is_official = nil
    rating_diff.acc = nil
    errors, warnings, notices = {}, {}, {}
    for _, err in ipairs(rating_diff.chart_errors) do
        if err.error_level == "Error" then
            table.insert(errors, err)
        elseif err.error_level == "Warning" then
            table.insert(warnings, err)
        elseif err.error_level == "Notice" then
            table.insert(notices, err)
        end
    end

    rating_diff.chart_errors = nil
    if mute then
        audio_preview = true
        checkSetMute()
    end
    r.UpdateArrange()
end






local function lerp(a, b, t)
    return a + (b - a) * t
end

-- Helper: Linear color interpolation
local function colorLerp(c1, c2, t)
    local r1, g1, b1, a1 = imgui.ColorConvertU32ToDouble4(c1)
    local r2, g2, b2, a2 = imgui.ColorConvertU32ToDouble4(c2)
    return imgui.ColorConvertDouble4ToU32(
        lerp(r1, r2, t),
        lerp(g1, g2, t),
        lerp(b1, b2, t),
        lerp(a1, a2, t)
    )
end



-- Utility: Ease In-Out
local function ease(t) return t < 0.5 and 2 * t * t or -1 + (4 - 2 * t) * t end



-- Visibility Check
local function onScreen(x1, x2)
    x2 = x2 or x1
    return (x2 >= window_pos_x and x1 <= window_pos_x + region_avail_x)
end




-- TODO: merge next two
local function convertXPos(pos)
    return window_pos_x + pos * horizontal_scale - scroll_x
end

local function convertYPos(pos)
    return window_pos_y + pos * region_avail_y
end

-- Drawing Primitives
local function cacheTap(x, y, col)
    table.insert(draw_cache.primitives, function()
        imgui.DrawListSplitter_SetCurrentChannel(splitter, 0)
        imgui.DrawList_AddCircleFilled(draw_list, x, y, outline_thickness / 2, outline_color)
        imgui.DrawListSplitter_SetCurrentChannel(splitter, 2)
        imgui.DrawList_AddCircleFilled(draw_list, x, y, line_thickness / 2, col)
    end)
end

-- TODO: lines ends up
local function cacheNote(x1, y, x2, col_start, col_end, overlap)
    table.insert(draw_cache.primitives, function()
        imgui.DrawListSplitter_SetCurrentChannel(splitter, 0)
        imgui.DrawList_AddRectFilled(draw_list, x1, y - outline_thickness / 2, x2, y + outline_thickness / 2, outline_color)
        imgui.DrawList_PathArcTo(draw_list, x1, y, outline_thickness / 2, math.pi / 2, 3 * math.pi / 2)
        imgui.DrawList_PathFillConvex(draw_list, outline_color)
        imgui.DrawList_PathArcTo(draw_list, x2, y, outline_thickness / 2, 0 - math.pi / 2, math.pi / 2)
        imgui.DrawList_PathFillConvex(draw_list, outline_color)
        imgui.DrawListSplitter_SetCurrentChannel(splitter, 1)
        imgui.DrawList_PathArcTo(draw_list, x1, y, line_thickness / 2, math.pi / 2, 3 * math.pi / 2)
        imgui.DrawList_PathFillConvex(draw_list, col_start)
        imgui.DrawList_PathArcTo(draw_list, x2, y, line_thickness / 2, 0 - math.pi / 2, math.pi / 2)
        imgui.DrawList_PathFillConvex(draw_list, col_end)
        imgui.DrawListSplitter_SetCurrentChannel(splitter, 2)
        imgui.DrawList_AddRectFilledMultiColor(draw_list, x1, y - line_thickness / 2, x2, y + line_thickness / 2, col_start,
            col_end, col_end, col_start)
        -- draw start tap
        if not overlap then
            imgui.DrawListSplitter_SetCurrentChannel(splitter, 2)
            imgui.DrawList_AddCircleFilled(draw_list, x1, y, outline_thickness / 2, outline_color)
            imgui.DrawListSplitter_SetCurrentChannel(splitter, 2)
            imgui.DrawList_AddCircleFilled(draw_list, x1, y, line_thickness / 2, col_start)
        end
    end)
end

-- TODO: line ends up
-- TODO: maybe smooth segment overlap?
-- TODO: proper segment length
local function cacheSlide(x1, y1, x2, y2, col_start, col_end, overlap)
    -- TODO: fix
    -- reverse imgui tesselation calc?
    local function getSegments(x1, x2, y1, y2, pixels_per_segment)
        local function asinh(x)
            return math.log(x + math.sqrt(x ^ 2 + 1))
        end
        local dx, dy = x2 - x1, y2 - y1
        if dy == 0 then
            return math.abs(dx) / pixels_per_segment
        end
        local m, n = dx, dy
        local dist1 = (asinh(2 * math.abs(n) / m) * m ^ 2) / 4
        local dist2 = (math.sqrt(m ^ 2 + 4 * n ^ 2) * math.abs(n)) / 2
        local dist = (dist1 + dist2) / math.abs(n)
        return math.max(16, round(dist / pixels_per_segment))
    end
    local function drawSegments(note_cache, outline)
        outline = outline or false
        imgui.DrawListSplitter_SetCurrentChannel(splitter, outline and 0 or 2)
        for i = #note_cache, 1, -1 do
            if note_cache[i - 2] then
                imgui.DrawList_PathLineTo(draw_list, note_cache[i - 2].x, note_cache[i - 2].y)
            else
                imgui.DrawList_PathLineTo(draw_list, x1, y1)
            end
            if note_cache[i - 1] then
                imgui.DrawList_PathLineTo(draw_list, note_cache[i - 1].x, note_cache[i - 1].y)
            else
                imgui.DrawList_PathLineTo(draw_list, x1, y1)
            end
            imgui.DrawList_PathLineTo(draw_list, note_cache[i].x, note_cache[i].y)
            imgui.DrawList_PathStroke(draw_list, outline and outline_color or note_cache[i].col, 0,
                outline and outline_thickness or line_thickness)
        end
    end

    local curve_length = getSegments(x1, x2, y1, y2, 1)
    -- TODO: dynamic step size
    local STEPSIZE = 4
    local prev_x, prev_y = x1, y1
    local dt = 1 / curve_length
    local note_cache = {}
    local t = 0
    while t <= 1 do
        local x = lerp(x1, x2, t)
        local y = lerp(y1, y2, ease(t))
        if math.sqrt((x - prev_x) ^ 2 + (y - prev_y) ^ 2) >= STEPSIZE then
            local col = colorLerp(col_start, col_end, t)
            table.insert(note_cache, {x = x, y = y, col = col})
            prev_x, prev_y = x, y
        end
        t = t + dt
    end

    table.insert(note_cache, {x = x2, y = y2, col = col_end})
    table.insert(draw_cache.primitives, function()
        -- draw notes
        drawSegments(note_cache, false)
        drawSegments(note_cache, true)
        -- draw ends
        imgui.DrawListSplitter_SetCurrentChannel(splitter, 1)
        imgui.DrawList_AddCircleFilled(draw_list, x1, y1, line_thickness / 2, col_start)
        imgui.DrawList_AddCircleFilled(draw_list, x2, y2, line_thickness / 2, col_end)
        imgui.DrawListSplitter_SetCurrentChannel(splitter, 0)
        imgui.DrawList_AddCircleFilled(draw_list, x1, y1, outline_thickness / 2, outline_color)
        imgui.DrawList_AddCircleFilled(draw_list, x2, y2, outline_thickness / 2, outline_color)
        -- draw start tap
        if not overlap then
            imgui.DrawListSplitter_SetCurrentChannel(splitter, 2)
            imgui.DrawList_AddCircleFilled(draw_list, x1, y1, outline_thickness / 2, outline_color)
            imgui.DrawListSplitter_SetCurrentChannel(splitter, 2)
            imgui.DrawList_AddCircleFilled(draw_list, x1, y1, line_thickness / 2, col_start)
        end
    end)
end

-- Main Cache Update
local function updateDrawcache(force)
    if not force then
        if draw_cache.window_pos_x == window_pos_x and
            draw_cache.window_pos_y == window_pos_y and
            draw_cache.horizontal_scale == horizontal_scale and
            draw_cache.scroll_x == scroll_x and
            draw_cache.region_avail_x == region_avail_x and
            draw_cache.region_avail_y == region_avail_y then
            return
        end
    end
    draw_cache.window_pos_x = window_pos_x
    draw_cache.window_pos_y = window_pos_y
    draw_cache.horizontal_scale = horizontal_scale
    draw_cache.scroll_x = scroll_x
    draw_cache.region_avail_x = region_avail_x
    draw_cache.region_avail_y = region_avail_y
    draw_cache.primitives = {}
    local prev_end = -1
    for _, line in ipairs(lines) do
        local x1, x2 = round(convertXPos(line.start_pos)), round(convertXPos(line.start_pos + line.length))
        local y1, y2 = round(convertYPos(line.pitch_start)), round(convertYPos(line.pitch_end))
        local overlap = prev_end >= x1
        if not onScreen(x1, x2) then
            goto continue
        end
        -- TODO: check if round is needed
        if round(line.length - 3.125) <= 0 and y1 == y2 and (tonumber(tmbsettings.tempo) or tcutils.getProjectTempo()) > 55 then
            -- Small and flat → Tap
            cacheTap(x1, y1, color_start)
        elseif y1 == y2 then
            -- Flat → Horizontal line
            cacheNote(x1, y1, x2, color_start, color_end, overlap)
        else
            -- Slide → Eased line
            cacheSlide(x1, y1, x2, y2, color_start, color_end, overlap)
        end

        ::continue::
        prev_end = x2
    end

    -- Draw improv zones
    for _, zone in ipairs(improv_zones) do
        local x_start = window_pos_x + zone.start_pos * horizontal_scale - scroll_x
        local x_end = window_pos_x + zone.end_pos * horizontal_scale - scroll_x
        if not onScreen(x_start, x_end) then
            goto continue
        end
        table.insert(draw_cache.primitives, function()
            imgui.DrawList_AddRectFilled(draw_list,
                x_start,
                window_pos_y,
                x_end,
                window_pos_y + region_avail_y,
                imgui.ColorConvertDouble4ToU32(0.0, 0.0, 0.0, 0.5))
            imgui.DrawList_AddText(draw_list,
                x_start + (x_end - x_start) / 2 - 20, window_pos_y + 0.1 * region_avail_y,
                imgui.ColorConvertDouble4ToU32(1.0, 1.0, 1.0, 1.0),
                "Improv")
        end)
        ::continue::
    end

    -- Draw background events
    for _, event in ipairs(bg_events) do
        local x = window_pos_x + event.pos2 * horizontal_scale - scroll_x
        if not onScreen(x) then
            goto continue
        end
        table.insert(draw_cache.primitives, function()
            imgui.DrawList_AddText(draw_list,
                x + 8, window_pos_y + 0.05 * region_avail_y,
                imgui.ColorConvertDouble4ToU32(1.0, 1.0, 1.0, 1.0),
                "BgEvent " .. event.event_id)
            imgui.DrawList_AddLine(draw_list, x, window_pos_y, x, window_pos_y + region_avail_y,
                imgui.ColorConvertDouble4ToU32(0.7, 1, 0.0, 0.5), 5.0)
        end)
        ::continue::
    end

    -- Draw lyrics
    for _, lyric in ipairs(lyrics) do
        local x = window_pos_x + lyric.bar * horizontal_scale - scroll_x
        local y = window_pos_y + 0.9 * region_avail_y
        if not onScreen(x) then
            goto continue
        end
        table.insert(draw_cache.primitives, function()
            imgui.DrawList_AddText(draw_list, x, y, imgui.ColorConvertDouble4ToU32(1.0, 1.0, 1.0, 1.0), lyric.text)
        end)
        ::continue::
    end
end

-- Drawing
local function renderCache()
    if not imgui.ValidatePtr(splitter, "ImGui_DrawListSplitter*") then
        splitter = imgui.CreateDrawListSplitter(draw_list)
    end
    imgui.DrawListSplitter_Split(splitter, 3)
    for _, fn in ipairs(draw_cache.primitives) do
        fn()
    end

    imgui.DrawListSplitter_Merge(splitter)
end

local function sortRatingChecks(a, b)
    for next_id = 0, math.huge do
        local rv, col_idx, col_user_id, sort_direction = imgui.TableGetColumnSortSpecs(ctx, next_id)
        if not rv then break end

        local key
        switch(col_idx)
        {
            [0] = function() key = "error_type" end,
            [1] = function() key = "timing" end,
            [2] = function() key = "value" end,
            __index = function() -- invalid key
                error("unknown column ID", 3)
                return false
            end,

        }
        local is_ascending = sort_direction == imgui.SortDirection_Ascending
        if a[key] < b[key] then
            return is_ascending
        elseif a[key] > b[key] then
            return not is_ascending
        end
    end

    return a.timing < b.timing
end

local function ratingPopup()
    if imgui.CollapsingHeader(ctx, "tmb information") then
        imgui.Text(ctx, ("%s: %0.2f*"):format("Star Rating", rating_diff.difficulty))
        imgui.Text(ctx, ("%s: %0.2f*"):format("Aim Diff", rating_diff.aim))
        imgui.Text(ctx, ("%s: %0.2f*"):format("Tap Diff", rating_diff.tap))
        imgui.Text(ctx, ("%s: %0.2f"):format("Base TT", rating_diff.base_tt))
    end
    if imgui.CollapsingHeader(ctx, "Rating Criteria Checks") then
        if imgui.TreeNode(ctx, "Errors") then
            if imgui.BeginTable(ctx, "Errors", 3, imgui.TableFlags_Sortable + imgui.TableFlags_SortMulti) then
                imgui.TableSetupColumn(ctx, "Error Type")
                imgui.TableSetupColumn(ctx, "Timing")
                imgui.TableSetupColumn(ctx, "Value")
                imgui.TableHeadersRow(ctx)
                if imgui.TableNeedSort(ctx) then
                    table.sort(errors, sortRatingChecks)
                end
                for _, err in ipairs(errors) do
                    imgui.TableNextRow(ctx)
                    imgui.TableNextColumn(ctx)
                    imgui.Text(ctx, err.error_type)
                    imgui.TableNextColumn(ctx)
                    if imgui.Selectable(ctx, tostring(round(err.timing, 3)), nil, imgui.SelectableFlags_SpanAllColumns) then
                        r.SetEditCurPos(err.timing, true, false)
                    end
                    imgui.TableNextColumn(ctx)
                    imgui.Text(ctx, tostring(round(err.value, 3)))
                end

                imgui.EndTable(ctx)
            end
            imgui.TreePop(ctx)
        end

        if imgui.TreeNode(ctx, "Warnings") then
            if imgui.BeginTable(ctx, "Warnings", 3, imgui.TableFlags_Sortable + imgui.TableFlags_SortMulti) then
                imgui.TableSetupColumn(ctx, "Error Type")
                imgui.TableSetupColumn(ctx, "Timing")
                imgui.TableSetupColumn(ctx, "Value")
                imgui.TableHeadersRow(ctx)
                if imgui.TableNeedSort(ctx) then
                    table.sort(warnings, sortRatingChecks)
                end
                for _, err in ipairs(warnings) do
                    imgui.TableNextRow(ctx)
                    imgui.TableNextColumn(ctx)
                    imgui.Text(ctx, err.error_type)
                    imgui.TableNextColumn(ctx)
                    if imgui.Selectable(ctx, tostring(round(err.timing, 3)), nil, imgui.SelectableFlags_SpanAllColumns) then
                        r.SetEditCurPos(err.timing, true, false)
                    end
                    imgui.TableNextColumn(ctx)
                    imgui.Text(ctx, tostring(round(err.value, 3)))
                end

                imgui.EndTable(ctx)
            end
            imgui.TreePop(ctx)
        end

        if imgui.TreeNode(ctx, "Notices") then
            if imgui.BeginTable(ctx, "Notices", 3, imgui.TableFlags_Sortable + imgui.TableFlags_SortMulti) then
                imgui.TableSetupColumn(ctx, "Error Type")
                imgui.TableSetupColumn(ctx, "Timing")
                imgui.TableSetupColumn(ctx, "Value")
                imgui.TableHeadersRow(ctx)
                if imgui.TableNeedSort(ctx) then
                    table.sort(notices, sortRatingChecks)
                end
                for _, err in ipairs(notices) do
                    imgui.TableNextRow(ctx)
                    imgui.TableNextColumn(ctx)
                    imgui.Text(ctx, err.error_type)
                    imgui.TableNextColumn(ctx)
                    if imgui.Selectable(ctx, tostring(round(err.timing, 3)), nil, imgui.SelectableFlags_SpanAllColumns) then
                        r.SetEditCurPos(err.timing, true, false)
                    end
                    imgui.TableNextColumn(ctx)
                    imgui.Text(ctx, tostring(round(err.value, 3)))
                end

                imgui.EndTable(ctx)
            end
            imgui.TreePop(ctx)
        end
    end
    imgui.EndPopup(ctx)
end

local visible, open
-- Main GUI loop
local function main()
    setGlobals()
    imgui.SetNextWindowSize(ctx, 400, 300, imgui.Cond_FirstUseEver)
    imgui.SetNextWindowDockID(ctx, -1, imgui.Cond_FirstUseEver)
    visible, open = imgui.Begin(ctx, "BonerViewer", true, imgui.WindowFlags_NoSavedSettings)
    if not visible then
        if tmbsettings.open then tmbsettings.toggleWindow() end
        return
    end
    if not open then
        if tmbsettings.open then tmbsettings.toggleWindow() end
        imgui.End(ctx)
        return
    end

    window_pos_x, window_pos_y = imgui.GetCursorScreenPos(ctx)
    region_avail_x, region_avail_y = imgui.GetContentRegionAvail(ctx)
    local retval = imgui.BeginChild(ctx, "ScrollableRegion", region_avail_x, region_avail_y, 1, imgui.WindowFlags_NoMouseInputs)
    if not retval then
        imgui.End(ctx)
        return
    end
    -- Create an invisible dummy with the width of the notes
    imgui.SetNextItemAllowOverlap(ctx)
    imgui.Dummy(ctx, content_width, 0)
    updateDrawcache()
    renderCache()
    local play_position = r.GetPlayPosition()
    local bpm = r.TimeMap2_GetDividedBpmAtTime(0, 0)
    local _, timesig_denom = r.TimeMap_GetTimeSigAtTime(0, 0)
    local pixels_per_beat = 5 * bpm / 6 * (4 / timesig_denom)
    local play_cursor_x = window_pos_x + play_position * pixels_per_beat * horizontal_scale - scroll_x
    if onScreen(play_cursor_x) then
        imgui.DrawList_AddLine(draw_list, play_cursor_x, window_pos_y, play_cursor_x, window_pos_y + region_avail_y,
            imgui.ColorConvertDouble4ToU32(0.0, 0.0, 0.0, 1.0), 5.0) -- Black vertical line
    end
    imgui.EndChild(ctx)
    -- Draw buttons
    imgui.SetCursorScreenPos(ctx, window_pos_x + 10, window_pos_y + 10)
    if imgui.Button(ctx, "Reload Preview") then
        doReload()
        updateDrawcache(true)
    end

    imgui.SameLine(ctx)
    if imgui.Button(ctx, "Edit tmb values") then
        tmbsettings.toggleWindow()
    end

    imgui.SameLine(ctx)
    if imgui.Button(ctx, "Export Tmb") then
        local mute = audio_preview
        if audio_preview then
            audio_preview = false
        end
        if boner_track then
            checkSetMute()
        end
        tmb.export()
        if mute then
            audio_preview = true
            checkSetMute()
        end
    end

    imgui.SameLine(ctx)
    if imgui.Button(ctx, "Rating Check") then
        imgui.OpenPopup(ctx, "Rating Check")
    end
    imgui.SameLine(ctx)
    imgui.SetNextWindowSizeConstraints(ctx, 100, 100, math.huge, 500)
    imgui.SetNextWindowBgAlpha(ctx, 1)
    if imgui.BeginPopup(ctx, "Rating Check", imgui.WindowFlags_MenuBar) then
        ratingPopup()
    end

    imgui.SetCursorScreenPos(ctx, window_pos_x + 10, window_pos_y + 40)
    if imgui.Checkbox(ctx, "Slide audio", audio_preview) then
        audio_preview = not audio_preview
        checkSetMute()
    end

    if audio_preview then
        imgui.PushItemWidth(ctx, 200)
        local changed, new_volume_db = imgui.SliderDouble(ctx, "Volume (dB)", slideaudio.volume, -12, 12)
        if changed then
            slideaudio.setVolume(new_volume_db)
        end
    end
    imgui.End(ctx)
end


local function catchError()
    local ok, err = xpcall(main, onError)
    if not ok then
        r.ShowConsoleMsg("Script error: " .. tostring(err) .. "\n")
        -- Note: on_exit still runs since reaper.atexit was already set up
        return
    end
    if not visible or not open then return end
    if r.GetTrack(0, 0) ~= first_track then
        open = false
        if tmbsettings.open then tmbsettings.toggleWindow(true) end
        return
    end
    r.defer(catchError)
end

-- Makes sure to reset track mutes when the script exits
r.atexit(function()
    if ctx and imgui.ValidatePtr(ctx, "ImGui_Context*") and open then pcall(imgui.End, ctx) end
    audio_preview = false
    checkSetMute()
end)
setGlobals()
doReload()
catchError()
