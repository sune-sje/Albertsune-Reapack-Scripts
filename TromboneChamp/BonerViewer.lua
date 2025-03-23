--[[
@description BonerViewer
@about
    Allows you to preview, edit, and export Trombone Champ charts directly from reaper.
@author Albertsune
@version 1.4.4
@changelog
    Fixed slides in continous pitch bends not being registered
    Fixed one note overlapping multiple screwing up slides
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
