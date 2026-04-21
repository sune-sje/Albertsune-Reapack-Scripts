-- @noindex
local r = reaper
if not pcall(r.ImGui_GetBuiltinPath) then
    r.ShowMessageBox("Error: ReaImGui is not installed.\n\nPlease install it via ReaPack.", "Missing Dependency", 0)
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
local tcutils = prequire("TcUtils")
if not tcutils then return end

local tmbsettings = {}
tmbsettings.EXT_STATE_SECTION = "TmbSettings"
tmbsettings.USE_XPCALL = true
tmbsettings.ENFORCE_ARGS = true
tmbsettings.open = false
-- Default settings
tmbsettings.note_color_start = {1.0, 0.0, 0.0}
tmbsettings.note_color_end = {0.0, 0.0, 1.0}
tmbsettings.bendrange = 12
tmbsettings.name = ""
tmbsettings.shortName = ""
tmbsettings.author = ""
tmbsettings.year = 2000
tmbsettings.genre = ""
tmbsettings.description = ""
tmbsettings.timesig = 4
tmbsettings.difficulty = 5
tmbsettings.savednotespacing = 280
tmbsettings.trackRef = ""
tmbsettings.endpoint = ""
tmbsettings.tempo = ""
tmbsettings.exportpath = r.GetProjectPath() .. "\\song.tmb"
tmbsettings.importpath = ""
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


local bend_ranges = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 24}
local ctx = imgui.CreateContext("Edit TMB Values")
local visible = false
local function u32ToRgb(u32)
    local a, r, g, b = imgui.ColorConvertU32ToDouble4(u32)
    return {r, g, b}
end
local function rgbToU32(rgb)
    return imgui.ColorConvertDouble4ToU32(1, rgb[1], rgb[2], rgb[3])
end


-- Load settings from external state
local function loadSettings()
    for key, _ in pairs(tmbsettings) do
        if type(tmbsettings[key]) == "function" or type(key) == "function" then
            goto continue
        end
        local _, value = r.GetProjExtState(0, tmbsettings.EXT_STATE_SECTION, key)
        if value ~= "" then
            switch(type(tmbsettings[key]))
            {
                ["number"] = function()
                    value = tonumber(value)
                end,
                ["string"] = function()
                    value = tostring(value)
                end,
                ["boolean"] = function()
                    value = (value == "true")
                end,
            }
            if key == "note_color_start" or key == "note_color_end" then
                value = u32ToRgb(value)
            end
            tmbsettings[key] = value
        end
        ::continue::
    end
end

-- Save settings to external state
local function saveSettings()
    for key, value in pairs(tmbsettings) do
        if type(value) ~= "function" then
            if key == "note_color_start" or key == "note_color_end" then
                value = rgbToU32(value)
            end
            if type(value) ~= "string" and type(value) ~= "number" and type(value) ~= "boolean" then
                r.ShowConsoleMsg("Weird tmbsettings value: " .. tostring(key) .. ": " .. tostring(value) .. "\n")
            end
            r.SetProjExtState(0, tmbsettings.EXT_STATE_SECTION, key, tostring(value))
        end
    end
end



-- Import settings from a file
local function importSettings()
    local filepath = tmbsettings.importpath
    local rv, filepath = r.GetUserFileNameForRead(filepath, "Import TMB", ".tmb")
    if not rv then return end
    local rv, tmb = tcutils.importTmb(filepath)
    if not rv then return end

    for key, value in pairs(tmb) do
        if key and value then
            for _, k in ipairs(tcutils.ALL_TMB_SETTINGS) do
                if key == k and key ~= "notes" and key ~= "lyrics" and key ~= "improv_zones" and key ~= "bgdata" then
                    -- if key == "note_color_start" or key == "note_color_end" then
                    -- value = rgbToU32(value)
                    -- end
                    tmbsettings[key] = value
                end
            end
        end
    end
end




-- GUI function
local function main()
    local function closeWindow()
        imgui.End(ctx)
        tmbsettings.open = false
        saveSettings()
    end

    if not tmbsettings.open then
        return
    end
    -- Open window
    imgui.SetNextWindowSize(ctx, 452, 678, imgui.Cond_FirstUseEver)
    imgui.SetNextWindowPos(ctx, 50, 50, imgui.Cond_FirstUseEver)
    visible, tmbsettings.open = imgui.Begin(ctx, "Edit TMB Values", true,
        imgui.WindowFlags_NoCollapse + imgui.WindowFlags_NoResize + imgui.WindowFlags_NoSavedSettings)
    if not visible then
        return
    end
    if not tmbsettings.open then
        closeWindow()
        return
    end

    -- Draw the actual GUI
    imgui.TextColored(ctx, imgui.ColorConvertDouble4ToU32(1, 0.5, 0, 1), "Fields with a (*) indicator can be autofilled") -- Highlighted in orange
    imgui.SeparatorText(ctx, "Song Info")
    tmbsettings.name = select(2, imgui.InputText(ctx, "Song Name", tmbsettings.name))
    tmbsettings.shortName = select(2, imgui.InputText(ctx, "Short Name", tmbsettings.shortName))
    tmbsettings.author = select(2, imgui.InputText(ctx, "Artist", tmbsettings.author))
    tmbsettings.year = select(2, imgui.InputText(ctx, "Release Year", tmbsettings.year, imgui.InputTextFlags_CharsDecimal))
    tmbsettings.genre = select(2, imgui.InputText(ctx, "Genre", tmbsettings.genre))
    tmbsettings.description = select(2, imgui.InputTextMultiline(ctx, "Description", tmbsettings.description))
    imgui.SeparatorText(ctx, "Chart Info")
    local u32_color = rgbToU32(tmbsettings.note_color_start)
    u32_color = select(2, imgui.ColorEdit3(ctx, "Note Start Color", u32_color))
    tmbsettings.note_color_start = u32ToRgb(u32_color)
    local u32_color = rgbToU32(tmbsettings.note_color_end)
    u32_color = select(2, imgui.ColorEdit3(ctx, "Note End Color", u32_color))
    tmbsettings.note_color_end = u32ToRgb(u32_color)
    tmbsettings.tempo = select(2, imgui.InputText(ctx, "BPM (*)", tmbsettings.tempo, imgui.InputTextFlags_CharsDecimal))
    tmbsettings.timesig = select(2, imgui.InputText(ctx, "Beats Per Bar", tmbsettings.timesig, imgui.InputTextFlags_CharsDecimal))
    tmbsettings.difficulty = select(2,
        imgui.InputText(ctx, "Difficulty", tmbsettings.difficulty, imgui.InputTextFlags_CharsDecimal))
    tmbsettings.savednotespacing = select(2, imgui.InputText(ctx, "Note Spacing", tmbsettings.savednotespacing,
        imgui.InputTextFlags_CharsDecimal))
    imgui.SetNextItemAllowOverlap(ctx)
    tmbsettings.endpoint = select(2, imgui.InputText(ctx, "Endpoint (*)", tmbsettings.endpoint, imgui.InputTextFlags_CharsDecimal))
    imgui.SameLine(ctx, 167)
    if imgui.Button(ctx, "Set to edit cursor") then
        r.ShowConsoleMsg("Set to edit cursor\n")
        tmbsettings.endpoint = tcutils.timeToBeats(r.GetCursorPosition())
    end
    tmbsettings.trackRef = select(2, imgui.InputText(ctx, "Track Ref", tmbsettings.trackRef))
    imgui.SeparatorText(ctx, "Export settings")
    if imgui.BeginCombo(ctx, "Pitch Bend Range", tostring(tmbsettings.bendrange)) then
        for _, option in ipairs(bend_ranges) do
            if imgui.Selectable(ctx, tostring(option), tmbsettings.bendrange == option) then
                tmbsettings.bendrange = option
            end
        end

        imgui.EndCombo(ctx)
    end

    tmbsettings.exportpath = select(2, imgui.InputText(ctx, "Export As", tmbsettings.exportpath))
    if imgui.Button(ctx, "Select File") then
        local retval, file_path = r.GetUserFileNameForRead("", "Select File", "*")
        if retval then tmbsettings.exportpath = file_path end
    end

    imgui.SeparatorText(ctx, "")
    if imgui.Button(ctx, "Import Existing Tmb") then
        importSettings()
    end

    if imgui.Button(ctx, "Save") then
        closeWindow()
        return
    end

    imgui.End(ctx)
    r.defer(main)
end


local function toggleWindow(skip_save)
    if not tmbsettings.open then
        ctx = imgui.CreateContext("Edit TMB Values")
        tmbsettings.open = true
        main()
    else
        tmbsettings.open = false
        if not skip_save then
            saveSettings()
        end
    end
end



function tmbsettings.toggleWindow(skip_save)
    if not tmbsettings.USE_XPCALL then
        return toggleWindow()
    else
        return select(2, xpcall(toggleWindow, onError, skip_save))
    end
end

function tmbsettings.saveSettings()
    if not tmbsettings.USE_XPCALL then
        return saveSettings()
    else
        return select(2, xpcall(saveSettings, onError))
    end
end

-- Initialize
loadSettings()
if pcall(debug.getlocal, 4, 1) then
    return tmbsettings
else
    ctx = imgui.CreateContext("Edit TMB Values")
    tmbsettings.open = true
    main()
end
