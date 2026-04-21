-- @noindex
-- load MIDIUtils
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
local mu = prequire("MIDIUtils")
if not mu then return end
local tcutils = prequire("TcUtils")
if not tcutils then return end
local tmbsettings = prequire("tmbSettings")
if not tmbsettings then return end
local rv
--- @diagnostic disable-next-line: name-style-check
local slideAudio = {}
slideAudio.USE_XPCALL = true
rv, slideAudio.volume = r.GetProjExtState(0, "SlideAudio", "volume")
if not rv or slideAudio.volume == "" then
    slideAudio.volume = 0.5
end
slideAudio.active_tracks = {}
local track
local function onError(err)
    r.ShowConsoleMsg(err .. "\n" .. debug.traceback() .. "\n")
end


local bendrange = tmbsettings.bendrange
if not bendrange or bendrange == 0 then bendrange = 12 end
tcutils.BEND_RANGE = bendrange
-- Returns a list of all unmuted MIDI takes on a given track
local function setVolume(volume)
    if volume then
        r.SetMediaTrackInfo_Value(track, "D_VOL", 10 ^ (volume / 20))
        slideAudio.volume = volume
        r.SetProjExtState(0, "SlideAudio", "volume", volume)
    end
end
local function getTrackTakes(track)
    local takes = {}
    local item_count = r.CountTrackMediaItems(track)
    for j = 0, item_count - 1 do
        local item = r.GetTrackMediaItem(track, j)
        if r.GetMediaItemInfo_Value(item, "B_MUTE") == 0 then -- Check if item is unmuted
            local take_count = r.CountTakes(item)
            for k = 0, take_count - 1 do
                local take = r.GetTake(item, k)
                if r.TakeIsMIDI(take) then table.insert(takes, take) end
            end
        end
    end

    return takes
end

local function addTrack(name)
    -- if pitch bent track already exists, delete before duplicating
    for i = 0, r.CountTracks(0) - 1 do
        local existing_track = r.GetTrack(0, i)
        local _, existing_name = r.GetSetMediaTrackInfo_String(existing_track, "P_NAME", "", false)
        if existing_name == name then
            r.DeleteTrack(existing_track)
        end
    end

    -- Create new track
    r.InsertTrackInProject(0, r.CountTracks(0), 0)
    local new_track = r.GetTrack(0, r.CountTracks(0) - 1)
    r.GetSetMediaTrackInfo_String(new_track, "P_NAME", name, true)
    r.SetTrackUIMute(new_track, 1, -1)
    r.SetMediaTrackInfo_Value(new_track, "B_MUTE", 1)
    r.SetMediaTrackInfo_Value(new_track, "D_VOL",  10 ^ (slideAudio.volume / 20))
    return new_track
end
-- Adds a new track with copied FX from unmuted tracks and sets it up
local function addBonerFx(track)
    local sample_folder = r.GetResourcePath() ..
        "/Scripts/Albertsune Reapack Scripts/TromboneChamp/BonerViewer/Samples/" -- Change this to your sample directory
    local sample_map =
    {
        [48] = "t2_tromboneC1.wav",
        [50] = "t2_tromboneD1.wav",
        [52] = "t2_tromboneE1.wav",
        [53] = "t2_tromboneF1.wav",
        [55] = "t2_tromboneG1.wav",
        [57] = "t2_tromboneA1.wav",
        [59] = "t2_tromboneB1.wav",
        [60] = "t2_tromboneC2.wav",
        [62] = "t2_tromboneD2.wav",
        [64] = "t2_tromboneE2.wav",
        [65] = "t2_tromboneF2.wav",
        [67] = "t2_tromboneG2.wav",
        [69] = "t2_tromboneA2.wav",
        [71] = "t2_tromboneB2.wav",
        [72] = "t2_tromboneC3.wav",
    }
    local function getNearestSample(note)
        for i = note, 72 do
            if sample_map[i] then return i end
        end

        return 72
    end

    local function addSampler(note, sample_file, transpose, track)
        local fx_idx = r.TrackFX_AddByName(track, "ReaSamplomatic5000", false, -1)
        local normal_note = note / 127
        transpose = (transpose + 80) / 160
        local sample_path = sample_folder .. sample_file
        r.TrackFX_SetParam(track, fx_idx, 3,  note ~= 47 and normal_note or 1 / 127)              -- Note start
        r.TrackFX_SetParam(track, fx_idx, 4,  note ~= 73 and normal_note or 1)                    -- Note end
        r.TrackFX_SetParam(track, fx_idx, 5,  note ~= 47 and transpose or 0.20625)                -- Pitch start
        r.TrackFX_SetParam(track, fx_idx, 9,  0)                                                  -- attack
        -- r.TrackFX_SetParam(track, fx_idx, 10, 0.0278)                                             -- Release
        r.TrackFX_SetParam(track, fx_idx, 10, 0)                                                  -- Release
        r.TrackFX_SetParam(track, fx_idx, 11, 1)                                                  -- Obey Note offs
        r.TrackFX_SetParam(track, fx_idx, 12, 1)                                                  -- Loop
        r.TrackFX_SetParam(track, fx_idx, 14, 0.85)                                               -- End offset
        r.TrackFX_SetParam(track, fx_idx, 16, 0)                                                  -- pitch bend range
        r.TrackFX_SetParam(track, fx_idx, 22, 0.003)                                              -- Xfade
        r.TrackFX_SetParam(track, fx_idx, 23, 0.15)                                               -- Loop start
        -- r.TrackFX_SetParam(track, fx_idx, 26, 0.0139)                                             -- note off release
        r.TrackFX_SetParam(track, fx_idx, 26, 0.0075)                                             -- note off release
        r.TrackFX_SetParam(track, fx_idx, 27, 1)                                                  -- note off release override
        r.TrackFX_SetNamedConfigParm(track, fx_idx, "FILE0",                   sample_path)       -- Sample file
        r.TrackFX_SetNamedConfigParm(track, fx_idx, "MODE",                    "2")               -- General mode
        r.TrackFX_SetNamedConfigParm(track, fx_idx, "param.15.mod.active",     "1")               -- activate modulation for pitch
        r.TrackFX_SetNamedConfigParm(track, fx_idx, "param.15.plink.active",   "1")               -- activate linked param
        r.TrackFX_SetNamedConfigParm(track, fx_idx, "param.15.plink.midi_msg", "224")             -- link to midi pitch cc
        r.TrackFX_SetNamedConfigParm(track, fx_idx, "param.15.plink.effect",   "-100")            -- since rs5k middle is 0 and midi pitch is 8192, scale by -100%
        r.TrackFX_SetNamedConfigParm(track, fx_idx, "param.15.plink.scale",    "0.15")            -- we need to scale a value of 0-16384 to (-12)-12
        r.TrackFX_SetNamedConfigParm(track, fx_idx, "param.15.plink.offset",   tostring(8.5 / 3)) -- the numbers are magic but work lol
    end



    r.PreventUIRefresh(1)
    for note = 47, 73 do -- B2 to C#5
        local base_note = getNearestSample(note)
        if base_note then
            local transpose = note - base_note
            addSampler(note, sample_map[base_note], transpose, track)
        end
    end

    r.PreventUIRefresh(-1)
    return true
end

-- Copies all unmuted MIDI items from existing tracks to the target track
local function copyMidiToTrack(target_track)
    if not target_track then return end
    local _, items = tcutils.getActive()
    r.Main_OnCommand(40769, 0) -- Deselect all
    for _, item in ipairs(items) do
        r.SetMediaItemSelected(item, true)
        r.Main_OnCommand(40698, 0) -- Copy items
        r.SetMediaItemSelected(item, false)
        r.SetEditCurPos(r.GetMediaItemInfo_Value(item, "D_POSITION"), false, false)
        r.SetOnlyTrackSelected(target_track)
        r.Main_OnCommand(42398, 0) -- Paste items
        local new_item = r.GetSelectedMediaItem(0, 0)
        r.SetMediaItemSelected(new_item, false)
    end
end




local function main()
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    -- TODO: move window pos not just cursor pos
    local cursorpos = r.GetCursorPosition()
    local window_start, window_end = r.GetSet_ArrangeView2(0, false, 0, 0)
    track = addTrack("BonerViewer")
    addBonerFx(track)
    copyMidiToTrack(track)
    local takes = getTrackTakes(track)
    tcutils.emulateSlidesInMidiTakes(takes, 12)
    r.SetEditCurPos(cursorpos, false, false)
    r.GetSet_ArrangeView2(0, true, 0, 0, window_start, window_end)
    r.Undo_EndBlock("Added Bonerviewer track", 0)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    return true, track
end

function slideAudio.main()
    if not slideAudio.USE_XPCALL then
        return main()
    else
        return select(2, xpcall(main, onError))
    end
end

function slideAudio.setVolume(volume)
    if not slideAudio.USE_XPCALL then
        return setVolume(volume)
    else
        return select(2, xpcall(setVolume, onError, volume))
    end
end

if pcall(debug.getlocal, 4, 1) then
    return slideAudio
else
    main()
end
