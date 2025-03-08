-- @noindex


package.path = reaper.GetResourcePath() .. '/Scripts/Albertsune Reapack Scripts/TromboneChamp/BonerViewer/MIDIUtils.lua'
local mu = require 'MIDIUtils'
if not mu.CheckDependencies('ExportTmb') then return end
local json = dofile(reaper.GetResourcePath() ..
"/Scripts/Albertsune Reapack Scripts/TromboneChamp/BonerViewer/dkjson.lua")


--import imgui (used for one single function lmaoo)
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local imgui = require 'imgui' '0.9.3'

--import dkjson for exporting. I use dofile here instead because why tf not. Variation is good LMAO

local exportTmb = {}
local retval, bend_range = reaper.GetProjExtState(0, "TmbSettings", "bendrange")
bend_range = tonumber(bend_range)
if not retval or not bend_range or bend_range == 0 then
    bend_range = 12
end




--converts pitch from midi to tmb format, clamps out of bound notes
local function convert_pitch(pitch)
    pitch = math.min(math.max(pitch, 47), 73)
    return (pitch - 60) * 13.75
end


--get pitch shift at certain time
local function get_pitch_shift(take, chan, time)
    local retval, pitch_shift = mu.MIDI_GetCCValueAtTime(take, 0xE0, 0, _, time)
    if retval then
        return pitch_shift
    else
        return 8192
    end
end


--merges all pitch shifts into channel 0
local function merge_pitch_shifts(take)
    local _, _, evtCount = reaper.MIDI_CountEvts(take)
    for i = 0, evtCount - 1 do
        local _, _, _, _, msg = mu.MIDI_GetCC(take, i)
        if msg == "0xE0" then
            mu.MIDI_SetCC(take, i, _, _, _, _, 0)
        end
    end
end

local function process_midi_text(take)
    if not take or not reaper.TakeIsMIDI(take) then
        reaper.ShowMessageBox("No valid MIDI take found!", "Error", 0)
        return
    end
    --initialize take in midiutils
    mu.MIDI_InitializeTake(take)
    mu.MIDI_OpenWriteTransaction(take)
    if select(4, mu.MIDI_CountEvts(take)) == 0 then
        return
    end

    local item = reaper.GetMediaItemTake_Item(take)
    local loop = reaper.GetMediaItemInfo_Value(item, "B_LOOPSRC")
    local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local source_length = reaper.GetMediaSourceLength(reaper.GetMediaItemTake_Source(take), false) * mu.MIDI_GetPPQ(take) /
    reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")

    --get ready for loopinggg
    local bpm = reaper.TimeMap2_GetDividedBpmAtTime(0, 0) * (4 / select(2, reaper.TimeMap_GetTimeSigAtTime(0, 0)))
    local lyrics = {}
    local improv_zones = {}
    local loopNum = 0
    local currentPos = 0
    local lyricIdx = 1
    local improvIdx = 1

    --first loop only if the take loops; will add up loop offset every iteration which will later be added to the notes ppq position
    while true do
        --exit early if we're past the media items end
        if reaper.MIDI_GetProjTimeFromPPQPos(take, currentPos) >= item_start + item_length then
            break
        end
        local midiIdx = 0
        local loop_offset = loopNum * source_length



        local skipped = 0
        --second loop loops through the midi take itself and formats all notes as in tmb
        while true do
            ::continue::
            -- get information on current note
            local retval, selected, muted, ppqpos, type, msg = mu.MIDI_GetTextSysexEvt(take, midiIdx)
            if not retval then break end

            currentPos = ppqpos + loop_offset
            if reaper.MIDI_GetProjTimeFromPPQPos(take, currentPos) >= item_start + item_length - 0.001 then
                break
            end


            if type == 89 then
                midiIdx = midiIdx + 1
                goto continue
            end

            if not msg then
                midiIdx = midiIdx + 1
                goto continue
            end
            if reaper.MIDI_GetProjTimeFromPPQPos(take, ppqpos) < item_start then
                midiIdx = midiIdx + 1
                skipped = skipped + 1
                goto continue
            end




            ppqpos = currentPos

            local pos = reaper.MIDI_GetProjTimeFromPPQPos(take, ppqpos)
            pos = pos * (bpm / 60)


            if msg:find("improv_start") then
                improv_zones[improvIdx] = {}
                improv_zones[improvIdx][1] = pos
            elseif msg:find("improv_end") then
                improv_zones[improvIdx][2] = pos
                improvIdx = improvIdx + 1
            else
                lyrics[lyricIdx] = { bar = pos, text = msg }
                lyricIdx = lyricIdx + 1
            end

            midiIdx = midiIdx + 1
        end
        loopNum = loopNum + 1
    end
    return lyrics, improv_zones
end


--loops through a take and returns a list of notes in tmb format
local function process_midi_notes(take)
    if not take or not reaper.TakeIsMIDI(take) then
        reaper.ShowMessageBox("No valid MIDI take found!", "Error", 0)
        return
    end
    --initialize take in midiutils
    mu.MIDI_InitializeTake(take)
    --mu.MIDI_OpenWriteTransaction(take)

    if select(2, mu.MIDI_CountEvts(take)) == 0 then
        return
    end

    --since reaper can't differentiate channels for pitch shifts, we merge them all into channel one
    merge_pitch_shifts(take)

    --gets length difference in media item and its source, in case it loops
    local item = reaper.GetMediaItemTake_Item(take)
    local loop = reaper.GetMediaItemInfo_Value(item, "B_LOOPSRC")
    local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local source_length = reaper.GetMediaSourceLength(reaper.GetMediaItemTake_Source(take), false) * mu.MIDI_GetPPQ(take) /
    reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")

    --get ready for loopinggg
    local bpm = reaper.TimeMap2_GetDividedBpmAtTime(0, 0) * (4 / select(2, reaper.TimeMap_GetTimeSigAtTime(0, 0)))
    local notes = {}
    local loopNum = 0
    local currentPos = 0
    local tmbIdx = 1

    --first loop only if the take loops; will add up loop offset every iteration which will later be added to the notes ppq position
    while true do
        --exit early if we're past the media items end
        if reaper.MIDI_GetProjTimeFromPPQPos(take, currentPos) >= item_start + item_length then
            break
        end
        local midiIdx = 0
        local loop_offset = loopNum * source_length


        local skipped = 0

        --second loop loops through the midi take itself and formats all notes as in tmb
        while true do
            ::continue::
            -- get information on current note
            local retval, selected, muted, start_ppqpos, end_ppqpos, chan, pitch, vel = mu.MIDI_GetNote(take, midiIdx)
            if not retval then break end

            currentPos = start_ppqpos + loop_offset
            if reaper.MIDI_GetProjTimeFromPPQPos(take, currentPos) >= item_start + item_length - 0.001 then
                break
            end

            if reaper.MIDI_GetProjTimeFromPPQPos(take, start_ppqpos) < item_start then
                midiIdx = midiIdx + 1
                skipped = skipped + 1
                goto continue
            end



            --update pos to account for loop
            start_ppqpos = currentPos
            end_ppqpos = math.min(end_ppqpos + loop_offset,
                reaper.MIDI_GetPPQPosFromProjTime(take, item_start + item_length))

            --convert to proj time
            local start_pos = reaper.MIDI_GetProjTimeFromPPQPos(take, start_ppqpos)
            local end_pos = reaper.MIDI_GetProjTimeFromPPQPos(take, end_ppqpos)

            --update pitch to include pitch shifts and convert all to tmb format
            local start_pitch_shift = get_pitch_shift(take, chan, start_pos)
            local end_pitch_shift = get_pitch_shift(take, chan, end_pos)
            local start_pitch = convert_pitch((pitch + (start_pitch_shift - 8192) / (8192 / bend_range)))
            local end_pitch = convert_pitch((pitch + (end_pitch_shift - 8192) / (8192 / bend_range)))
            start_pos = start_pos * (bpm / 60)
            end_pos = end_pos * (bpm / 60)



            --oh boy, here come the slides

            --always add first note
            if midiIdx == skipped then
                notes[tmbIdx] = {
                    x_start = start_pos,
                    length = end_pos - start_pos,
                    x_end = end_pos,
                    y_start = start_pitch,
                    delta_pitch = end_pitch - start_pitch,
                    y_end = end_pitch
                }
                tmbIdx = tmbIdx + 1
            else
                --if previous note overlaps and isn't same pitch, set end pos/pitch of prev note to create slide
                if notes[tmbIdx - 1].x_end >= start_pos and notes[tmbIdx - 1].y_end ~= start_pitch then
                    notes[tmbIdx - 1].delta_pitch = end_pitch - notes[tmbIdx - 1].y_start
                    notes[tmbIdx - 1].y_end = start_pitch
                    notes[tmbIdx - 1].length = end_pos - notes[tmbIdx - 1].x_start
                    notes[tmbIdx - 1].x_end = end_pos
                    --default, add note to tmb
                else
                    notes[tmbIdx] = {
                        x_start = start_pos,
                        length = end_pos - start_pos,
                        x_end = end_pos,
                        y_start = start_pitch,
                        delta_pitch = end_pitch - start_pitch,
                        y_end = end_pitch
                    }
                    tmbIdx = tmbIdx + 1
                end
            end
            midiIdx = midiIdx + 1
        end
        loopNum = loopNum + 1
    end
    return notes
end



--returns a list of all unmuted midi takes
local function get_unmuted_takes()
    local unmuted_takes = {}

    local track_count = reaper.CountTracks(0) -- Get number of tracks in current project
    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        if reaper.GetMediaTrackInfo_Value(track, "B_MUTE") == 0 then -- Check if track is unmuted
            local item_count = reaper.CountTrackMediaItems(track)
            for j = 0, item_count - 1 do
                local item = reaper.GetTrackMediaItem(track, j)
                if reaper.GetMediaItemInfo_Value(item, "B_MUTE") == 0 then -- Check if item is unmuted
                    local take_count = reaper.CountTakes(item)
                    for k = 0, take_count - 1 do
                        local take = reaper.GetTake(item, k)
                        if reaper.TakeIsMIDI(take) then
                            table.insert(unmuted_takes, take)
                        end
                    end
                end
            end
        end
    end

    return unmuted_takes
end

--combines lyrics of all takes in a single sorted list
local function get_text()
    local takeList = get_unmuted_takes()
    local lyrics = {}
    local improv_zones = {}

    for i = 1, #takeList do
        local take_lyrics, take_improv_zones = process_midi_text(takeList[i])
        if not take_lyrics then goto skip end
        for j = 1, #take_lyrics do
            table.insert(lyrics, take_lyrics[j])
        end
        ::skip::
        if not take_improv_zones then goto skip2 end
        for j = 1, #take_improv_zones do
            table.insert(improv_zones, take_improv_zones[j])
        end
        ::skip2::
    end

    table.sort(lyrics, function(a, b)
        return a.bar < b.bar
    end)

    table.sort(improv_zones, function(a, b)
        return a[1] < b[1]
    end)


    return lyrics, improv_zones
end

--combines notes of all takes in a single sorted list
local function get_notes()
    local takeList = get_unmuted_takes()
    local notes = {}

    for i = 1, #takeList do
        local take_notes = process_midi_notes(takeList[i])
        if not take_notes then goto skip end
        for j = 1, #take_notes do
            if take_notes[j].length > 0.0005 then
                table.insert(notes, take_notes[j])
            end
        end
        ::skip::
    end

    table.sort(notes, function(a, b)
        return a.x_start < b.x_start
    end)

    return notes
end



-- Load settings from external state
local function get_tmb_inputs()
    --default settings
    local settings = {
        name = "",
        shortName = "",
        author = "",
        year = 2000,
        genre = "",
        description = "",
        tempo = nil,
        timesig = 4,
        difficulty = 5,
        savednotespacing = 280,
        endpoint = nil,
        trackRef = "",
        note_color_start = { 1, 0.21176471, 0 },
        note_color_end = { 1, 0.8, 0.29803922 },
        bendrange = 2,
        exportpath = reaper.GetProjectPath() .. "\\song.tmb"

    }

    --loop through setting keys and extract from external state
    for key, _ in pairs(settings) do
        local _, value = reaper.GetProjExtState(0, "TmbSettings", key)
        if value ~= "" then
            --type conversion, external states are always stored in string
            --also gotta convert the color from Uint32 to RGB
            if key == "note_color_start" or key == "note_color_end" then
                local color = { imgui.ColorConvertU32ToDouble4(value) }
                table.remove(color, 1)
                settings[key] = color
            elseif tonumber(value) then
                settings[key] = tonumber(value)
            else
                settings[key] = value
            end
        end
    end
    return settings
end


local function saveTmb(notes, lyrics, improv_zones)
    --get data to save
    local data = get_tmb_inputs()
    if not data.tempo then
        data.tempo = reaper.TimeMap2_GetDividedBpmAtTime(0, 0) * (4 / select(2, reaper.TimeMap_GetTimeSigAtTime(0, 0)))
    end
    if not data.endpoint then data.endpoint = 0 end
    local noteList = {}
    for i = 1, #notes do
        data.endpoint = math.max(data.endpoint, math.ceil(notes[i].x_start + notes[i].length) + 4)
        noteList[i] = { notes[i].x_start, notes[i].length, notes[i].y_start, notes[i].delta_pitch, notes[i].y_end }
    end
    data.notes = noteList
    data.lyrics = lyrics
    data.improv_zones = improv_zones


    --remove unneeded data and export as json
    local exportpath = data.exportpath
    data.exportpath = nil
    data.bendrange = nil
    local file = io.open(exportpath, "w")
    local json_string = json.encode(data,
        { indent = true, keyorder = { "name", "shortName", "author", "year", "genre", "description", "tempo", "timesig", "difficulty", "savednotespacing", "endpoint", "trackRef", "note_color_start", "note_color_end", "improv_zones", "lyrics", "notes" } })
    if file then
        file:write(json_string)
        file:close()
        reaper.ShowMessageBox("TMB exported to " .. exportpath, "Success", 0)
    else
        reaper.ShowMessageBox("Failed to save TMB!", "Error", 0)
    end
end



local function main()
    local notes = get_notes()
    --local lyrics, improv_zones = get_lyrics()
    local lyrics, improv_zones = get_text()
    saveTmb(notes, lyrics, improv_zones)
end




--public functions, if used as module
function exportTmb.getNotes()
    return get_notes
end

function exportTmb.getText()
    return get_text
    --return get_lyrics
end

function exportTmb.export()
    main()
end

--check if script is module or main file, only exports if main
if pcall(debug.getlocal, 4, 1) then
    return exportTmb
else
    main()
end
