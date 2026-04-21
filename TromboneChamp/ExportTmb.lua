-- @noindex
local r = reaper
local script_path = "/Scripts/Albertsune Reapack Scripts"
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
local tcutils = prequire("TcUtils")
if not tcutils then return end
local tmbsettings = prequire("tmbSettings")
if not tmbsettings then return end

local exporttmb = {}
exporttmb.USE_XPCALL = true
local function onError(err)
    r.ShowConsoleMsg(err .. "\n" .. debug.traceback() .. "\n")
end

local function export()
    local bendrange = tmbsettings.bendrange
    if not bendrange or bendrange == 0 then
        bendrange = 12
    end
    tcutils.BEND_RANGE = bendrange
    local takes = tcutils.getActive()
    if not takes or #takes == 0 then
        r.ShowMessageBox("No active MIDI takes found.", "Error", 0)
        return
    end
    local rv, notes, lyrics, improv_zones, bg_events = tcutils.midiToTmb(takes)
    if not rv then return end
    local settings =
    {
        note_color_start = tmbsettings.note_color_start,
        note_color_end = tmbsettings.note_color_end,
        name = tmbsettings.name,
        shortName = tmbsettings.shortName,
        author = tmbsettings.author,
        year = tmbsettings.year,
        genre = tmbsettings.genre,
        description = tmbsettings.description,
        timesig = tmbsettings.timesig,
        difficulty = tmbsettings.difficulty,
        savednotespacing = tmbsettings.savednotespacing,
        trackRef = tmbsettings.trackRef,
        endpoint = tmbsettings.endpoint,
        tempo = tmbsettings.tempo,
    }
    local exportpath = tmbsettings.exportpath
    local tmb = {notes = notes, lyrics = lyrics, improv_zones = improv_zones, bgdata = bg_events}
    for k, v in pairs(settings) do
        tmb[k] = v
    end

    tcutils.writeTmb(exportpath, tmb)
end

function exporttmb.export()
    if not exporttmb.USE_XPCALL then
        return export()
    else
        return select(2, xpcall(export, onError))
    end
end

-- check if script is module or main file, only exports if main
if pcall(debug.getlocal, 4, 1) then
    return exporttmb
else
    export()
end
