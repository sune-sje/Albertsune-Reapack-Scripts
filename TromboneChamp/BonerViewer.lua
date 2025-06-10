--[[
@description BonerViewer
@about
    Allows you to preview, edit, and export Trombone Champ charts directly from reaper.
@author Albertsune
@version 1.5.2
@changelog
    Added charter field
@provides
    [main] BonerViewer.lua
    [main=main] ExportTmb.lua
    [main=main] tmbSettings.lua
    BonerViewer/Preview.lua
    BonerViewer/SlideAudio.lua
    BonerViewer/MIDIUtils.lua https://raw.githubusercontent.com/jeremybernstein/ReaScripts/main/MIDI/MIDIUtils.lua
    BonerViewer/dkjson.lua https://raw.githubusercontent.com/LuaDist/dkjson/refs/heads/master/dkjson.lua
    BonerViewer/Samples/*.wav

--]]


-- Check for js_ReaScriptAPI
if not reaper.APIExists("JS_ReaScriptAPI_Version") then
    reaper.ShowMessageBox("Error: js_ReaScriptAPI is not installed.\n\nPlease install it via ReaPack.", "Missing Dependency", 0)
    return
end

-- Check for reaImGui
if not pcall(reaper.ImGui_GetBuiltinPath) then
    reaper.ShowMessageBox("Error: ReaImGui is not installed.\n\nPlease install it via ReaPack.", "Missing Dependency", 0)
    return
end



reaper.SetExtState("BonerViewer", "exitState", "false", false)
reaper.SetExtState("BonerViewer", "doReload", "false", false)
dofile(reaper.GetResourcePath() .. '/Scripts/Albertsune Reapack Scripts/TromboneChamp/BonerViewer/SlideAudio.lua')
dofile(reaper.GetResourcePath() .. '/Scripts/Albertsune Reapack Scripts/TromboneChamp/BonerViewer/Preview.lua')





local function check_exit_flag()
    if reaper.GetExtState("BonerViewer", "exitState") == "true" then
        reaper.SetExtState("BonerViewer", "exitState", "false", false) -- Clear the flag
        if reaper.GetExtState("BonerViewer", "doReload") == "true" then
            reaper.SetExtState("BonerViewer", "doReload", "false", false)
            local audioId = reaper.AddRemoveReaScript(true, 0, reaper.GetResourcePath() .. '/Scripts/Albertsune Reapack Scripts/TromboneChamp/BonerViewer/SlideAudio.lua', false)
            local previewId = reaper.AddRemoveReaScript(true, 0, reaper.GetResourcePath() .. '/Scripts/Albertsune Reapack Scripts/TromboneChamp/BonerViewer/Preview.lua', false)
            reaper.Main_OnCommand(audioId, 0)
            reaper.Main_OnCommand(previewId, 0)
            reaper.AddRemoveReaScript(false, 0, reaper.GetResourcePath() .. '/Scripts/Albertsune Reapack Scripts/TromboneChamp/BonerViewer/SlideAudio.lua', false)
            reaper.AddRemoveReaScript(false, 0, reaper.GetResourcePath() .. '/Scripts/Albertsune Reapack Scripts/TromboneChamp/BonerViewer/Preview.lua', false)
            reaper.defer(check_exit_flag)
        end
        return
    else
        reaper.defer(check_exit_flag) -- Keep checking
    end
end

--run_script()
check_exit_flag()
