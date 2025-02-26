--[[
@description Autospacing
@about
    Reaper script for Trombone Champ charters that automatically does the spacing for all notes in selected midi takes.
    Will skip slides, concur the ending note
@author Albertsune
@version 1.1
@changelog
    Made self contained, no longer needs sockmonkey72's midi util api
@provides
    Autospacing/MIDIUtils.lua https://raw.githubusercontent.com/jeremybernstein/ReaScripts/main/MIDI/MIDIUtils.lua
    Autospacing.lua
--]]



--check for midiUtils
package.path = reaper.GetResourcePath() .. '/Scripts/Albertsune Reapack Scripts/TromboneChamp/Autospacing/?.lua'
local mu = require 'MIDIUtils'
if not mu.CheckDependencies('AutoSpacing') then return end




--finds new notelength from the length between the start of two notes
function FindLength(length)
    --fancy math
    return math.min(
        0.25 + 0.644816 / (3.88621 / length ^ 1.94328 + 1) ^ 27568.9,
        4500
    ) * length
end

local function process_midi_notes(take)
    if not take or not reaper.TakeIsMIDI(take) then
        reaper.ShowMessageBox("No valid MIDI take found!", "Error", 0)
        return
    end

    --initialize take in midiutils and tell it we're gonna write to it
    mu.MIDI_InitializeTake(take)
    mu.MIDI_OpenWriteTransaction(take)

    -- Iterate through all MIDI notes
    local i = 0
    while true do
        -- get information on current and next note
        local retval, selected, muted, start_ppqpos, end_ppqpos, chan, pitch, vel = mu.MIDI_GetNote(take, i)
        local Nretval, Nselected, Nmuted, Nstart_ppqpos, Nend_ppqpos, Nchan, Npitch, Nvel = mu.MIDI_GetNote(take, i + 1)

        --break if there is no next note
        if not Nretval then break end

        --convert to proj time
        local start_ppqposMS = reaper.MIDI_GetProjTimeFromPPQPos(take, start_ppqpos) * 1000
        local end_ppqposMS = reaper.MIDI_GetProjTimeFromPPQPos(take, end_ppqpos) * 1000
        local Nstart_ppqposMS = reaper.MIDI_GetProjTimeFromPPQPos(take, Nstart_ppqpos) * 1000
        local Nend_ppqposMS = reaper.MIDI_GetProjTimeFromPPQPos(take, Nend_ppqpos) * 1000


        --find length in ms and convert it to ppq
        local new_length = FindLength(Nstart_ppqposMS - start_ppqposMS)
        local new_end_ppqpos = reaper.MIDI_GetPPQPosFromProjTime(take, (start_ppqposMS + new_length) / 1000)

        --check if note overlaps, skip if true
        if end_ppqpos >= Nstart_ppqpos then goto continue end

        --finally we set the notes new length
        mu.MIDI_SetNote(take, i, selected, muted, start_ppqpos, new_end_ppqpos)


        ::continue::
        i = i + 1
    end

    -- commit changes
    mu.MIDI_CommitWriteTransaction(take)
    reaper.MIDI_Sort(take)
end

--loops through selected items and returns all takes found in those
local function get_takes()
    local midi_takes = {}
    local num_selected_items = reaper.CountSelectedMediaItems(0)
    for i = 0, num_selected_items - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        if item then
            local num_takes = reaper.CountTakes(item)
            for j = 0, num_takes - 1 do
                local take = reaper.GetMediaItemTake(item, j)
                if take and reaper.TakeIsMIDI(take) then
                    table.insert(midi_takes, take)
                end
            end
        end
    end
    return midi_takes
end



-- Main function call
-- finds all selected takes and processes each separatly
reaper.Undo_BeginBlock()
local takeList = get_takes()
for _, take in ipairs(takeList) do
    process_midi_notes(take)
end
reaper.Undo_EndBlock("Adjust MIDI note lengths", -1)
