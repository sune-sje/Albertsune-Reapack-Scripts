-- @description Autospacing
-- @author Albertsune
-- @version 1.0
-- @about
--      Reaper script for Trombone Champ charters that automatically does the spacing for all notes in selected midi takes.
--      Will skip slides, concur the ending note 



--check for midiUtils
package.path = reaper.GetResourcePath() .. '/Scripts/sockmonkey72 Scripts/MIDI/?.lua'
local mu = require 'MIDIUtils'
if not mu.CheckDependencies('My Script') then return end



function GetBPMAtPPQ(take, ppq)
    if not take or not reaper.ValidatePtr2(0, take, "MediaItem_Take*") then
        return nil, "Invalid take"
    end

    -- Convert PPQ to time position
    --local time_pos = reaper.MIDI_GetProjTimeFromPPQPos(take, ppq)
   
    
    -- Get tempo at the given time position
    --local bpm = reaper.TimeMap2_GetDividedBpmAtTime(0, time_pos)
    local timesig_num, timesig_denom, tempo = reaper.TimeMap_GetTimeSigAtTime(0, reaper.TimeMap2_QNToTime(0, ppq) )
    
    return tempo
end

function PPQToMs(length, bpm, ppq)
    return length*((60000/bpm)/ppq)
end
    
function MsToPPQ(length, bpm, ppq)
    return length*((ppq*bpm)/60000)
end

function FindLength(length, bpm, ppq)

    local function mafs(length)

        return math.min(
                  0.25 + 0.644816/(3.88621/length^1.94328 + 1)^27568.9,
                  4500)
        --return 0.22 + 0.714/((3.47145/length^1.62)+1)^3180
        --return math.min(0.21002*math.log(length)-0.780204,1)
        
    
    end
    
    return MsToPPQ((mafs(length)*length), bpm, ppq)
end
    


local function process_midi_notes(take)
    if not take or not reaper.TakeIsMIDI(take) then
        reaper.ShowMessageBox("No valid MIDI take found!", "Error", 0)
        return
    end
    --initialize take in midiutils and tell it we're gonna write to it
    mu.MIDI_InitializeTake(take)
    mu.MIDI_OpenWriteTransaction(take)
    
    local ppq = mu.MIDI_GetPPQ(take)

    -- Iterate through all MIDI notes
    local i = 0
    while true do
        -- get information on current and next note
        local retval, selected, muted, start_ppqpos, end_ppqpos, chan, pitch, vel = mu.MIDI_GetNote(take, i)
        if not retval then break end
        local Nretval, Nselected, Nmuted, Nstart_ppqpos, Nend_ppqpos, Nchan, Npitch, Nvel = mu.MIDI_GetNote(take, i+1)
        if not Nretval then break end
        
        
        
        local bpm = GetBPMAtPPQ(take, start_ppqpos)
        
        --finds the time between start of two notes in ms
        local length = (reaper.MIDI_GetProjTimeFromPPQPos(take,Nstart_ppqpos) - reaper.MIDI_GetProjTimeFromPPQPos(take,start_ppqpos))*1000
        --converts the length
        local new_length = FindLength(length, bpm, ppq)
        --get the new end pos
        local new_end_ppqpos = start_ppqpos + new_length
        --check if note overlaps, skip if true
        if end_ppqpos >= Nstart_ppqpos then goto continue end
        
        --finally we set the notes new length
        mu.MIDI_SetNote(take, i, selected, muted, start_ppqpos, new_end_ppqpos)
        
        
        ::continue::
        i = i + 1
    end

    -- Finalize changes
    mu.MIDI_CommitWriteTransaction(take)
    reaper.MIDI_Sort(take)
end


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
reaper.Undo_BeginBlock()
local takeList = get_takes()
for _, take in ipairs(takeList) do
    process_midi_notes(take)
end
reaper.Undo_EndBlock("Adjust MIDI note lengths", -1)

