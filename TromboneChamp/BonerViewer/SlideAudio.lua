-- @noindex


--load MIDIUtils
package.path = reaper.GetResourcePath() .. '/Scripts/Albertsune Reapack Scripts/TromboneChamp/BonerViewer/MIDIUtils.lua'
local mu = require 'MIDIUtils'
if not mu.CheckDependencies('ExportTmb') then return end

-- Get the bend depth setting from the project state, default to 12 if not set
local retval, bend_depth = reaper.GetProjExtState(0, "TmbSettings", "bendrange")
bend_depth = tonumber(bend_depth)
if not retval or not bend_depth or bend_depth == 0 then
  bend_depth = 12
end


-- Returns a list of all unmuted MIDI takes on a given track
local function get_track_takes(track)
  local takes = {}
  local item_count = reaper.CountTrackMediaItems(track)
  for j = 0, item_count - 1 do
    local item = reaper.GetTrackMediaItem(track, j)
    if reaper.GetMediaItemInfo_Value(item, "B_MUTE") == 0 then -- Check if item is unmuted
      local take_count = reaper.CountTakes(item)
      for k = 0, take_count - 1 do
        local take = reaper.GetTake(item, k)
        if reaper.TakeIsMIDI(take) then
          table.insert(takes, take)
        end
      end
    end
  end

  return takes
end


-- Adds a new track with copied FX from unmuted tracks and sets it up
local function AddTrackWithBonerFX(new_track_name)
  --if pitch bent track already exists, delete before duplicating
  for i = 0, reaper.CountTracks(0) - 1 do
    local existing_track = reaper.GetTrack(0, i)
    local _, existing_name = reaper.GetSetMediaTrackInfo_String(existing_track, "P_NAME", "", false)
    if existing_name == new_track_name then
      reaper.DeleteTrack(existing_track)
      break
    end
  end


  -- Create new track
  reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
  local new_track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
  reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", new_track_name, true)
  reaper.SetTrackUIMute(new_track, 1, -1)
  reaper.SetMediaTrackInfo_Value(new_track, "B_MUTE", 1)

  
  
  local sample_folder = reaper.GetResourcePath() .. "/Scripts/Albertsune Reapack Scripts/TromboneChamp/BonerViewer/Samples/" -- Change this to your sample directory
local sample_map = {
    [48] = "t2_tromboneC1.wav", [50] = "t2_tromboneD1.wav", [52] = "t2_tromboneE1.wav", 
    [53] = "t2_tromboneF1.wav", [55] = "t2_tromboneG1.wav", [57] = "t2_tromboneA1.wav", [59] = "t2_tromboneB1.wav", 
    [60] = "t2_tromboneC2.wav", [62] = "t2_tromboneD2.wav", [64] = "t2_tromboneE2.wav", [65] = "t2_tromboneF2.wav", 
    [67] = "t2_tromboneG2.wav", [69] = "t2_tromboneA2.wav", [71] = "t2_tromboneB2.wav", [72] = "t2_tromboneC3.wav"
}

local function find_nearest_higher(note)
    for i = note, 72 do
        if sample_map[i] then return i end
    end
    return 72
end

local function add_rs5k_instance(note, sample_file, transpose, track)
    local fx_idx = reaper.TrackFX_AddByName(track, "ReaSamplomatic5000", false, -1)
    local normal_note = note/127 
    transpose = (transpose+80)/160
    
    reaper.TrackFX_SetParam(track, fx_idx, 3, normal_note) -- Note start
    reaper.TrackFX_SetParam(track, fx_idx, 4, normal_note) -- Note end
    reaper.TrackFX_SetParam(track, fx_idx, 5, transpose) -- Pitch start
    reaper.TrackFX_SetParam(track, fx_idx, 9, 0) -- attack
    reaper.TrackFX_SetParam(track, fx_idx, 11, 1) -- Obey Note offs
    reaper.TrackFX_SetParam(track, fx_idx, 16, 0) -- pitch bend range
    
    local sample_path = sample_folder .. sample_file
    reaper.TrackFX_SetNamedConfigParm(track, fx_idx, "FILE0", sample_path)
    reaper.TrackFX_SetNamedConfigParm(track, fx_idx, "MODE", 2)

    reaper.TrackFX_SetNamedConfigParm(new_track, fx_idx, "param.15.mod.active", 1)
    reaper.TrackFX_SetNamedConfigParm(new_track, fx_idx, "param.15.plink.active", 1)
    reaper.TrackFX_SetNamedConfigParm(new_track, fx_idx, "param.15.plink.midi_msg", 224)
    reaper.TrackFX_SetNamedConfigParm(new_track, fx_idx, "param.15.plink.effect", -100)
    reaper.TrackFX_SetNamedConfigParm(new_track, fx_idx, "param.15.plink.scale", 0.15)
    reaper.TrackFX_SetNamedConfigParm(new_track, fx_idx, "param.15.plink.offset", 8.5/3)

end

reaper.PreventUIRefresh(1)

for note = 47, 73 do -- B2 to C5
    local base_note = find_nearest_higher(note)
    if base_note then
        local transpose = note - base_note
        add_rs5k_instance(note, sample_map[base_note], transpose, new_track)
    end
end

reaper.PreventUIRefresh(-1)


  local used_tracks = {}
  -- Iterate through existing tracks
  for i = 0, reaper.CountTracks(0) - 2 do -- Exclude new track
    local track = reaper.GetTrack(0, i)
    local track_muted = reaper.GetMediaTrackInfo_Value(track, "B_MUTE")

    if track_muted == 0 then -- Track is not muted
      local has_unmuted_midi = false

      -- Iterate through media items on the track
      for j = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, j)
        local take = reaper.GetActiveTake(item)

        if take and reaper.TakeIsMIDI(take) then
          local item_muted = reaper.GetMediaItemInfo_Value(item, "B_MUTE")
          if item_muted == 0 then
            has_unmuted_midi = true
            break
          end
        end
      end

      -- If track has unmuted MIDI take, copy its FX and volume to new track
      if has_unmuted_midi then
        table.insert(used_tracks, i)
        for fx = 0, reaper.TrackFX_GetCount(track) - 1 do
          --reaper.TrackFX_CopyToTrack(track, fx, new_track, fx, false)
          reaper.SetMediaTrackInfo_Value(new_track, "D_VOL", reaper.GetMediaTrackInfo_Value(track, "D_VOL"))
        end
      end
    end
  end

  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
  local extTracks = ""
  for i = 1, #used_tracks do
    extTracks = extTracks .. used_tracks[i] .. ","
  end
  reaper.SetExtState("BonerViewer", "activeTracks", extTracks, false)
  return new_track
end


-- Adds a new track with copied FX from unmuted tracks and sets it up
local function AddTrackWithCopiedFX(new_track_name)
  --if pitch bent track already exists, delete before duplicating
  for i = 0, reaper.CountTracks(0) - 1 do
    local existing_track = reaper.GetTrack(0, i)
    local _, existing_name = reaper.GetSetMediaTrackInfo_String(existing_track, "P_NAME", "", false)
    if existing_name == new_track_name then
      reaper.DeleteTrack(existing_track)
      break
    end
  end


  -- Create new track
  reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
  local new_track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
  reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", new_track_name, true)
  reaper.SetTrackUIMute(new_track, 1, -1)
  reaper.SetMediaTrackInfo_Value(new_track, "B_MUTE", 1)

  local used_tracks = {}
  -- Iterate through existing tracks
  for i = 0, reaper.CountTracks(0) - 2 do -- Exclude new track
    local track = reaper.GetTrack(0, i)
    local track_muted = reaper.GetMediaTrackInfo_Value(track, "B_MUTE")

    if track_muted == 0 then -- Track is not muted
      local has_unmuted_midi = false

      -- Iterate through media items on the track
      for j = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, j)
        local take = reaper.GetActiveTake(item)

        if take and reaper.TakeIsMIDI(take) then
          local item_muted = reaper.GetMediaItemInfo_Value(item, "B_MUTE")
          if item_muted == 0 then
            has_unmuted_midi = true
            break
          end
        end
      end

      -- If track has unmuted MIDI take, copy its FX and volume to new track
      if has_unmuted_midi then
        table.insert(used_tracks, i)
        for fx = 0, reaper.TrackFX_GetCount(track) - 1 do
          reaper.TrackFX_CopyToTrack(track, fx, new_track, fx, false)
          reaper.SetMediaTrackInfo_Value(new_track, "D_VOL", reaper.GetMediaTrackInfo_Value(track, "D_VOL"))
        end
      end
    end
  end

  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
  local extTracks = ""
  for i = 1, #used_tracks do
    extTracks = extTracks .. used_tracks[i] .. ","
  end
  reaper.SetExtState("BonerViewer", "activeTracks", extTracks, false)
  return new_track
end



-- Copies media item settings from source item to target item
local function copyMediaSettings(source_item, target_item)
  local values = {
    "B_MUTE",
    "B_MUTE_ACTUAL",
    "C_MUTE_SOLO",
    "B_LOOPSRC",
    "B_ALLTAKESPLAY",
    "B_UISEL",
    "C_BEATATTACHMODE",
    "C_AUTOSTRETCH",
    "C_LOCK",
    "D_VOL",
    "D_POSITION",
    "D_LENGTH",
    "D_SNAPOFFSET",
    "D_FADEINLEN",
    "D_FADEOUTLEN",
    "D_FADEINDIR",
    "D_FADEOUTDIR",
    "D_FADEINLEN_AUTO",
    "D_FADEOUTLEN_AUTO",
    "C_FADEINSHAPE",
    "C_FADEOUTSHAPE",
    "I_CUSTOMCOLOR",
    "I_CURTAKE"

    --[[
      "D_POSITION",
      "D_LENGTH",
      "B_LOOPSRC",
      "B_ALLTAKESPLAY",
      "B_UISEL",
      "B_MUTE",
      "B_LOOPSRC",
      "B_LOOPT"
      --]]
  }

  for _, value in ipairs(values) do
    local val = reaper.GetMediaItemInfo_Value(source_item, value)
    reaper.SetMediaItemInfo_Value(target_item, value, val)
  end
end

-- Copies take settings from source take to target take
local function copyTakeSettings(source_take, target_take)
  local values = {
    "D_STARTOFFS",
    "D_VOL",
    "D_PAN",
    "D_PANLAW",
    "D_PLAYRATE",
    "D_PITCH",
    "B_PPITCH",
    "I_CHANMODE",
    "I_PITCHMODE",
    "I_STRETCHFLAGS",
    "F_STRETCHFADESIZE",
    "I_CUSTOMCOLOR"
  }

  for _, value in ipairs(values) do
    local val = reaper.GetMediaItemTakeInfo_Value(source_take, value)
    reaper.SetMediaItemTakeInfo_Value(target_take, value, val)
  end
end

-- Copies all unmuted MIDI items from existing tracks to the target track
local function CopyUnmutedMIDIItemsToTrack(target_track)
  if not target_track then return end

  -- Iterate through existing tracks
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    if track == target_track then goto continue end -- Skip target track

    local track_muted = reaper.GetMediaTrackInfo_Value(track, "B_MUTE")

    if track_muted == 0 then -- Track is not muted
      -- Iterate through media items on the track
      for j = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, j)
        local take = reaper.GetActiveTake(item)

        if take and reaper.TakeIsMIDI(take) then
          local item_muted = reaper.GetMediaItemInfo_Value(item, "B_MUTE")
          if item_muted == 0 then
            -- Copy the entire media item
            local new_item = reaper.AddMediaItemToTrack(target_track)

            -- Copy all media item properties
            copyMediaSettings(item, new_item)

            -- Copy takes
            for t = 0, reaper.GetMediaItemNumTakes(item) - 1 do
              local src_take = reaper.GetMediaItemTake(item, t)
              local new_take = reaper.AddTakeToMediaItem(new_item)

              copyTakeSettings(src_take, new_take)
              local _, take_name = reaper.GetSetMediaItemTakeInfo_String(src_take, "P_NAME", "", false)
              reaper.GetSetMediaItemTakeInfo_String(new_take, "P_NAME", take_name, true)

              -- Copy source media
              local src_pcm = reaper.GetMediaItemTake_Source(src_take)
              reaper.SetMediaItemTake_Source(new_take, src_pcm)
            end

            -- Ensure item is visible
            reaper.SetMediaItemSelected(new_item, true)
          end
        end
      end
    end

    ::continue::
  end

  reaper.UpdateArrange()
end



-- Sets the CC shape for a given take and CC index
local function set_cc_shape(take, cc_index, shape, tension)
  mu.MIDI_SetCCShape(take, cc_index, shape, tension)
end


-- Inserts a pitch bend event at a given position
local function insert_pitch_bend(take, ppq_pos, pitch_bend_value, shape)
  pitch_bend_value = math.floor(pitch_bend_value + 0.5)
  pitch_bend_value = math.max(0, math.min(16383, pitch_bend_value))
  local pitch_bend_lsb = pitch_bend_value & 0x7F
  local pitch_bend_msb = (pitch_bend_value >> 7) & 0x7F
  local _, idx = mu.MIDI_InsertCC(take, false, false, ppq_pos, 0xE0, 0, pitch_bend_lsb, pitch_bend_msb)
  set_cc_shape(take, idx, shape, 0.5)
end







-- Gets the pitch shift value at a certain time
local function get_pitch_shift(take, time)
  local retval, pitch_shift = mu.MIDI_GetCCValueAtTime(take, 0xE0, 0, _, time)
  if retval then
    return pitch_shift
  else
    return 8192
  end
end

-- Calculates the pitch difference between two notes
local function get_pitch_diff(note1, note2)
  local diff = note2.pitch - note1.pitch
  return diff * (8192 / 12)
end


-- Merges all pitch shifts into channel 0
local function merge_pitch_shifts(take)
  local _, _, evtCount = reaper.MIDI_CountEvts(take)
  for i = 0, evtCount - 1 do
    local _, _, _, _, msg = mu.MIDI_GetCC(take, i)
    if msg == "0xE0" then
      mu.MIDI_SetCC(take, i, _, _, _, _, 0)
    end
  end
end


-- Gets a note from a take at a given index
local function get_note(take, i)
  local retval, selected, muted, startppq, endppq, chan, pitch, vel = mu.MIDI_GetNote(take, i)
  local note = {
    retval = retval,
    selected = selected,
    muted = muted,
    startppq = startppq,
    endppq = endppq,
    chan = chan,
    pitch = pitch,
    vel = vel
  }
  return note
end




-- Loops through a take and returns a list of notes in tmb format
local function process_midi_notes(take)
  if not take or not reaper.TakeIsMIDI(take) then
    reaper.ShowMessageBox("No valid MIDI take found!", "Error", 0)
    return
  end

  -- Initialize take in MIDIUtils
  mu.MIDI_InitializeTake(take)
  mu.MIDI_OpenWriteTransaction(take)

  if select(2, mu.MIDI_CountEvts(take)) == 0 then
    return
  end

  -- Since reaper can't differentiate channels for pitch shifts, we merge them all into channel one
  merge_pitch_shifts(take)

  --get ready for loopinggg
  local prevNote = {}
  local deleteNotes = {}
  local extendNotes = {}
  local pitchEvents = {}

  insert_pitch_bend(take, 0, get_pitch_shift(take, reaper.MIDI_GetProjTimeFromPPQPos(take, 0)), 2)

  local midiIdx = 0
  local sequence = {}
  -- Loop through the MIDI take and format all notes as in tmb
  while true do
    -- get information on current note
    local currentNote = get_note(take, midiIdx)
    if not currentNote.retval then break end

    --[[
    oh boy, here come the slides

    Basically adds notes to a list if they overlap, and reset that list when they don't.
    Before resetting it'll add pitch bend events at start, end, and at every note intersection,
    interpolating from the first note in the sequence. Also adds a pitch even at start of non-slide notes to ensure existing pitch bends stay
    --]]
    
    if prevNote.retval then
      if prevNote.endppq >= currentNote.startppq then
        if #sequence == 0 then
          table.insert(sequence, prevNote)
        end
        table.insert(sequence, currentNote)
      else
        if #sequence > 1 then
          table.insert(pitchEvents, { sequence[1].startppq, get_pitch_shift(take, reaper.MIDI_GetProjTimeFromPPQPos(take, sequence[1].startppq)), 2 })
          for i = 2, #sequence do
            if sequence[i - 1].pitch == sequence[i].pitch then
              table.insert(pitchEvents, { sequence[i - 1].endppq, get_pitch_shift(take, reaper.MIDI_GetProjTimeFromPPQPos(take, sequence[i - 1].endppq)) - get_pitch_diff(sequence[i - 1], sequence[1]), 2 })
            end
            table.insert(deleteNotes, sequence[i].idx)
          end
          table.insert(extendNotes, { sequence[1].idx, sequence[#sequence].endppq })
          table.insert(pitchEvents, { sequence[#sequence].endppq, get_pitch_shift(take, reaper.MIDI_GetProjTimeFromPPQPos(take, sequence[#sequence].endppq)) - get_pitch_diff(sequence[#sequence], sequence[1]), 0 })
          table.insert(pitchEvents, { sequence[#sequence].endppq + (currentNote.startppq - sequence[#sequence].endppq)/2, get_pitch_shift(take, reaper.MIDI_GetProjTimeFromPPQPos(take, sequence[#sequence].endppq + (currentNote.startppq - sequence[#sequence].endppq)/2)), 0 })
        else
          table.insert(pitchEvents, {currentNote.startppq, get_pitch_shift(take, reaper.MIDI_GetProjTimeFromPPQPos(take, currentNote.startppq)), 0})
          --table.insert(pitchEvents, {currentNote.endppq, get_pitch_shift(take, reaper.MIDI_GetProjTimeFromPPQPos(take, currentNote.endppq)), 0})
        end
        sequence = {}
      end
    end
    prevNote = currentNote
    prevNote.idx = midiIdx
    midiIdx = midiIdx + 1
  end


  --do half of the same thing again after exiting loop to make sure slides at the end of takes get included
  if #sequence > 1 then
    table.insert(pitchEvents, { sequence[1].startppq, get_pitch_shift(take, reaper.MIDI_GetProjTimeFromPPQPos(take, sequence[1].startppq)), 2 })
    for i = 2, #sequence do
      if sequence[i - 1].pitch == sequence[i].pitch then
        table.insert(pitchEvents, { sequence[i - 1].endppq, get_pitch_shift(take, reaper.MIDI_GetProjTimeFromPPQPos(take, sequence[i - 1].endppq)) - get_pitch_diff(sequence[i - 1], sequence[1]), 2 })
      end
      table.insert(deleteNotes, sequence[i].idx)
    end
    table.insert(extendNotes, { sequence[1].idx, sequence[#sequence].endppq })
    table.insert(pitchEvents, { sequence[#sequence].endppq, get_pitch_shift(take, reaper.MIDI_GetProjTimeFromPPQPos(take, sequence[#sequence].endppq)) - get_pitch_diff(sequence[#sequence], sequence[1]), 0 })
  end





  -- Remove end notes and extend first note
  for i = 1, #extendNotes do
    mu.MIDI_SetNote(take, extendNotes[i][1], NULL, NULL, NULL, extendNotes[i][2])
  end

  local deleteCC = {}
  local _, _, cc_count = mu.MIDI_CountEvts(take)
  for i = 0, cc_count - 1 do
    local _, _, _, ppqpos, cctype, _, val_lsb, val_msb = mu.MIDI_GetCC(take, i)
    if cctype == 224 then
      for _, note in ipairs(extendNotes) do
        if ppqpos >= select(4,mu.MIDI_GetNote(take, note[1] )) and ppqpos <= note[2] then
          table.insert(deleteCC, i)
        else
          local val = val_msb*128 + val_lsb
          local val = 8192 + (val-8192)*(12/bend_depth)
          val_lsb = val & 0x7F
          val_msb = (val >> 7) & 0x7F
          mu.MIDI_SetCC(take, i, NULL, NULL, NULL, NULL, NULL, val_lsb, val_msb)
        end
      end
    end
  end
  for i = 1, #deleteNotes do
    mu.MIDI_DeleteNote(take, deleteNotes[i])
  end


  for i = 1, #deleteCC do
    mu.MIDI_DeleteCC(take, deleteCC[i])
  end

  for i = 1, #pitchEvents do
    insert_pitch_bend(take, pitchEvents[i][1], pitchEvents[i][2], pitchEvents[i][3])
  end

  mu.MIDI_CommitWriteTransaction(take)
end






local function main()
  local track = AddTrackWithBonerFX("BonerViewer")
  CopyUnmutedMIDIItemsToTrack(track)
  local takes = get_track_takes(track)

  for _, take in ipairs(takes) do
    reaper.Undo_BeginBlock()
    process_midi_notes(take)
    reaper.MIDI_Sort(take)
    reaper.Undo_EndBlock("Add pitch bend for overlapping notes", -1)
  end
end




main()
