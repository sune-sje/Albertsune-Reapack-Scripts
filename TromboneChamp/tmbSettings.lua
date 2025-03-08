-- @noindex
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local imgui = require 'imgui' '0.9.3'


local json = dofile(reaper.GetResourcePath() ..
"/Scripts/Albertsune Reapack Scripts/TromboneChamp/BonerViewer/dkjson.lua")



-- Define persistent storage key
local EXT_STATE_SECTION = "TmbSettings"


-- Default settings
local settings = {
    file_path = "",
    folder_path = "",
    note_color_start = imgui.ColorConvertDouble4ToU32(1.0, 1.0, 0.0, 0.0),
    note_color_end = imgui.ColorConvertDouble4ToU32(1.0, 0.0, 0.0, 1.0),
    checkbox = false,
    bendrange = 12,
    name = "",
    shortName = "",
    author = "",
    year = 2000,
    genre = "",
    description = "",
    timesig = 4,
    difficulty = 5,
    savednotespacing = 280,
    trackRef = "",
    endpoint = "",
    tempo = "",
    exportpath = reaper.GetProjectPath() .. "\\song.tmb",
    importpath = " "
}

local bend_ranges = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }
local ctx = imgui.CreateContext("Edit TMB Values")
local open = true
local visible = true

-- Load settings from external state
local function loadSettings()
    for key, _ in pairs(settings) do
        local _, value = reaper.GetProjExtState(0, EXT_STATE_SECTION, key)
        if value ~= "" then
            if key == "checkbox" then
                settings[key] = value == "true"
            else
                settings[key] = value
            end
        end
    end
end

-- Save settings to external state
local function saveSettings()
    for key, value in pairs(settings) do
        reaper.SetProjExtState(0, EXT_STATE_SECTION, key, tostring(value), true)
    end
end



-- Import settings from a file
local function importSettings()
    local filepath = settings.importpath
    local retval, filepath = reaper.GetUserFileNameForRead(filepath, "Import TMB", ".tmb")
    if not retval then return end
    local file = io.open(filepath, "r")
    if not file then return end
    local data = json.decode(file:read("*a"))
    for key, value in pairs(data) do
        if key and value then
            if key == "note_color_start" or key == "note_color_end" then
                value = imgui.ColorConvertDouble4ToU32(1, value[1], value[2], value[3])
            end
            settings[key] = value
        end
    end
    file:close()
    saveSettings()
end


-- GUI function
local function loop()
    -- Open window
    imgui.SetNextWindowSize(ctx, 452, 678, imgui.Cond_FirstUseEver)
    imgui.SetNextWindowPos(ctx, 50, 50, imgui.Cond_FirstUseEver)
    visible, open = imgui.Begin(ctx, "Edit TMB Values", true,
        imgui.WindowFlags_NoCollapse + imgui.WindowFlags_NoResize + imgui.WindowFlags_NoSavedSettings) -- + imgui.WindowFlags_NoResize)

    if not visible then
        reaper.SetExtState("BonerViewer", "isSetting", "false", false)
        return
    end
    if not open then
        reaper.SetExtState("BonerViewer", "isSetting", "false", false)
        imgui.End(ctx)
        return
    end

    if reaper.GetExtState("BonerViewer", "isSetting") == "false" then
        imgui.End(ctx)
        return
    end




    -- Draw the actual GUI
    imgui.SeparatorText(ctx, "Fields with a (*) indicator can be autofilled")
    imgui.SeparatorText(ctx, "Song Info")
    _, settings.name = imgui.InputText(ctx, "Song Name", settings.name)

    _, settings.shortName = imgui.InputText(ctx, "Short Name", settings.shortName)

    _, settings.author = imgui.InputText(ctx, "Artist", settings.author)

    _, settings.year = imgui.InputText(ctx, "Release Year", settings.year, imgui.InputTextFlags_CharsDecimal)

    _, settings.genre = imgui.InputText(ctx, "Genre", settings.genre)

    _, settings.description = imgui.InputTextMultiline(ctx, "Description", settings.description)




    imgui.SeparatorText(ctx, "Chart Info")

    _, settings.note_color_start = imgui.ColorEdit3(ctx, "Note Start Color", settings.note_color_start)

    _, settings.note_color_end = imgui.ColorEdit3(ctx, "Note End Color", settings.note_color_end)

    _, settings.tempo = imgui.InputText(ctx, "BPM (*)", settings.tempo, imgui.InputTextFlags_CharsDecimal)

    _, settings.timesig = imgui.InputText(ctx, "Beats Per Bar", settings.timesig, imgui.InputTextFlags_CharsDecimal)

    _, settings.difficulty = imgui.InputText(ctx, "Difficulty", settings.difficulty, imgui.InputTextFlags_CharsDecimal)

    _, settings.savednotespacing = imgui.InputText(ctx, "Note Spacing", settings.savednotespacing,
        imgui.InputTextFlags_CharsDecimal)

    _, settings.endpoint = imgui.InputText(ctx, "Endpoint (*)", settings.endpoint, imgui.InputTextFlags_CharsDecimal)

    _, settings.trackRef = imgui.InputText(ctx, "Track Ref", settings.trackRef)


    imgui.SeparatorText(ctx, "Export settings")





    if imgui.BeginCombo(ctx, "Pitch Bend Range", settings.bendrange) then
        for _, option in ipairs(bend_ranges) do
            if imgui.Selectable(ctx, option, settings.bendrange == option) then
                settings.bendrange = option
            end
        end
        imgui.EndCombo(ctx)
    end


    _, settings.exportpath = imgui.InputText(ctx, "Export As", settings.exportpath)
    if imgui.Button(ctx, "Select File") then
        local retval, filePath = reaper.GetUserFileNameForRead("", "Select File", "*")
        if retval then settings.exportpath = filePath end
    end



    imgui.SeparatorText(ctx, "")


    if imgui.Button(ctx, "Import Existing Tmb") then
        importSettings()
    end

    if imgui.Button(ctx, "Save") then
        saveSettings()
        reaper.SetExtState("BonerViewer", "isSetting", "false", false)
        imgui.End(ctx)
        return
    end

    imgui.End(ctx)
    reaper.defer(loop)
end


-- Initialize
loadSettings()
loop()
