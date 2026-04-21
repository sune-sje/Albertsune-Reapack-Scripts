--- @diagnostic disable: duplicate-doc-field, duplicate-set-field
-----------------------------------------------------------------------------
----------------------------------- Init ------------------------------------
local r = reaper
local function addPaths()
    local paths =
    {
        "./?.lua",                                  -- current directory
        "./?/?.lua",                                -- for module folders
        "../?.lua",                                 -- parent directory
        "../?/?.lua",                               -- module folders in parent
        "/Scripts/sockmonkey72 Scripts/MIDI/?.lua", -- default midiutils path
    }
    for _, path in ipairs(paths) do
        if not string.find(package.path, path, 1, true) then
            package.path = path .. ";" .. package.path
        end
    end
end
addPaths()
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
local json = prequire("dkjson")
if not json then return end

local platform = r.GetOS()
--- !doctype module
--- @class tcUtils
--- @field USE_XPCALL boolean By default, calls to tcUtils are wrapped in xpcall to help catch and display errors. This comes with a certain non-zero cost, though. Disable USE_XPCALL to use direct calling.
--- @field ENFORCE_ARGS boolean Flag to enable/disable argument type-checking. When enabled, submitting the wrong argument type(s) to tcUtils functions will cause an error, useful for debugging code. Disable in production code, since the type checking adds some minimal overhead. On by default
--- @field MERGE_PITCH_CHANNELS boolean Whether to merge pitch bend events into a single channel (0). If false, pitch bend events are kept on their original channels. This exists as reaper seems to act like all pitch events are on the same channel, so we merge them to get the same effect. On by default
--- @field BEND_RANGE number The range of pitch bend in semitones. This is used to convert pitch bend values to semitones and vice versa. Default is 12 semitones (1 octave), to emulate Trombone Champ
--- @field PPQ number Assumed PPQ resolution for handling midi.
--- @field CLAMP_NOTES boolean Whether to clamp notes inside the Trombone Champ range. **Off** by default
--- @field EXCLUDE_TEXT_TYPES table<number> A list of text event types to exclude from when converting midi text to tmb. Excludes {89, 3, 33} by default.
--- @field REQUIRED_TMB_SETTINGS table<string> A list of required settings for TMB files. By default only includes the fields absolutely necesarry for the game to load the map, excluding tempo and endpoint which can be autofilled
local tcutils = {}
tcutils.USE_XPCALL = true
tcutils.ENFORCE_ARGS = true
tcutils.MERGE_PITCH_CHANNELS = true
tcutils.BEND_RANGE = 12
tcutils.PPQ = 960
tcutils.CLAMP_NOTES = false
tcutils.EXCLUDE_TEXT_TYPES = {89, 3, 33}
tcutils.REQUIRED_TMB_SETTINGS = {"name", "shortName", "author", "year", "genre", "description", "trackRef", "notes"}
tcutils.ALL_TMB_SETTINGS =
{
    "name",
    "shortName",
    "author",
    "year",
    "genre",
    "description",
    "trackRef",
    "notes",
    "tempo",
    "timesig",
    "difficulty",
    "savednotespacing",
    "endpoint",
    "note_color_start",
    "note_color_end",
    "improv_zones",
    "lyrics",
    "bgdata",
}
local function onError(err)
    r.ShowConsoleMsg(err .. "\n" .. debug.traceback() .. "\n")
end


-----------------------------------------------------------------------------
----------------------------------- Utilities -------------------------------
local function isValidNumber(val)
    if type(val) == "number" then
        if val == math.huge
            or val == -math.huge
            or val ~= val
            or not (val > -math.huge and val < math.huge)
        then
            return false
        end
        return true
    end
    return false
end
local function enforceArgs(...)
    if not tcutils.ENFORCE_ARGS then return true end
    local fn_name = debug.getinfo(2).name
    local args = table.pack(...)
    for i = 1, args.n do
        if args[i].val == nil and not args[i].optional then
            error(fn_name .. ": invalid or missing argument #" .. i, 3)
            return false
        elseif type(args[i].val) ~= args[i].type and not args[i].optional then
            error(fn_name .. ": bad type for argument #" .. i ..
                ", expected \'" .. args[i].type .. "\', got \'" .. type(args[i].val) .. "\'", 3)
            return false
        elseif args[i].reapertype and not r.ValidatePtr(args[i].val, args[i].reapertype) then
            error(fn_name .. ": bad type for argument #" .. i ..
                ", expected \'" .. args[i].reapertype .. "\'", 3)
            return false
        elseif args[i].type == "number" and not ((args[i].optional and args[i].val == nil) or isValidNumber(args[i].val)) then
            error(fn_name .. ": invalid number #" .. i, 3)
            return false
        end
    end

    return true
end

local function makeTypedArg(val, type, optional, reapertype)
    if not tcutils.ENFORCE_ARGS then return nil end
    local typed_arg = {type = type, val = val, optional = optional}
    if reapertype then typed_arg.reapertype = reapertype end
    return typed_arg
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

local function round(number, digit_position)
    local precision = 10 ^ (digit_position or 0)
    return math.floor(number * precision + 0.5) / precision
end

local function mergeTables(t1, t2)
    for i = 1, #t2 do
        t1[#t1 + 1] = t2[i]
    end

    return t1
end

local function removeDuplicates(t)
    local seen = {}
    local result = {}
    for _, v in ipairs(t) do
        if not seen[v] then
            seen[v] = true
            table.insert(result, v)
        end
    end

    return result
end

-- Cross-platform safe temp file creation
local function write_temp_file(data)
    local path
    if package.config:sub(1, 1) == "\\" then
        -- Windows
        local tmpdir = os.getenv("TEMP") or os.getenv("TMP") or "."
        path = tmpdir .. "\\bonerviewer.json"
    else
        -- Unix-like
        path = "/tmp/bonerviewer.json"
    end

    local f, err = io.open(path, "w")
    if not f then
        return nil, "Failed to open temp file: " .. (err or "unknown error")
    end

    f:write(data)
    f:close()
    return path
end
local function httpPost(url, data)
    local tmp_path, err = write_temp_file(data)
    if not tmp_path then
        r.ShowMessageBox("Temp file error: \n" .. err, "Failed to write temp file", 0)
        return
    end

    local cmd = string.format('curl -s -X POST -H "Content-Type: application/json" --data-binary "@%s" "%s"', tmp_path, url)
    -- Execute the command and capture output
    local result = r.ExecProcess(cmd, 0)
    if result then
        -- Remove exit code (first line)
        result = result:gsub("^.-\n", "")
        -- Remove Windows network drive error (fix by jkooks)
        result = result:gsub(".+CMD%.EXE.-UNC.+%.", "")
        -- Remove all newlines
        result = result:gsub("[\r\n]", "")
    end
    return result
end

-----------------------------------------------------------------------------
----------------------------------- Primitives ------------------------------
local function ensureMidiInit(take, check_trans)
    check_trans = check_trans or false
    local mu_state = mu.MIDI_GetState()
    if mu_state["activeTake"] ~= take then
        mu.MIDI_InitializeTake(take)
    end

    if check_trans and mu_state["openTransaction"] ~= take then
        mu.MIDI_OpenWriteTransaction(take)
    end
end

local function mergePitchShifts(take)
    ensureMidiInit(take, false)
    local _, _, evt_count = mu.MIDI_CountEvts(take)
    for i = 0, evt_count - 1 do
        local _, _, _, _, msg = mu.MIDI_GetCC(take, i)
        if msg == "0xE0" then
            mu.MIDI_SetCC(take, i, _, _, _, _, 0)
        end
    end
end

local function getTakeInfo(take)
    local item = r.GetMediaItemTake_Item(take)
    local item_start = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
    local source_length = r.GetMediaSourceLength(r.GetMediaItemTake_Source(take)) * mu.MIDI_GetPPQ(take) /
        r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
    return item_start, item_length, source_length
end


local function midiToTmbPitch(pitch, clamp)
    clamp = clamp or tcutils.CLAMP_NOTES
    pitch = (pitch - 60) * 13.75
    if clamp then
        pitch = math.min(math.max(pitch, -178.75), 178.75)
    end
    return pitch
end



local function tmbToMidiPitch(pitch, clamp)
    clamp = clamp or tcutils.CLAMP_NOTES
    pitch = (pitch / 13.75) + 60
    if clamp then
        pitch = math.min(math.max(pitch, 47), 73)
    end
    return pitch
end




local function getProjectTempo()
    local bpm                                 = r.TimeMap2_GetDividedBpmAtTime(0, 0)
    local time_sig_num, time_sig_denom, tempo = r.TimeMap_GetTimeSigAtTime(0, 0)
    time_sig_denom                            = time_sig_denom or 4 -- Default if error
    local effective_bpm                       = bpm * (4 / time_sig_denom)
    return effective_bpm
end



local function timeToBeats(time_secs, bpm)
    bpm = bpm or getProjectTempo()
    return time_secs * (bpm / 60)
end



local function beatsToTime(beats, bpm)
    bpm = bpm or getProjectTempo()
    if bpm == 0 then return 0 end
    return beats / (bpm / 60)
end

local function timeToPPQ(ppq, time_secs)
    local effective_bpm, _ = getProjectTempo()
    if effective_bpm == 0 then return nil end
    return ppq * (effective_bpm / 60) * time_secs
end

-- TODO: implement
local function ppqToBeats(ppq, ppqpos, bpm)
    bpm = bpm or getProjectTempo()
end

-- TODO: implement
local function beatsToPPQ(beats, ppq, bpm)
    bpm = bpm or getProjectTempo()
end




local function convertPitchRange(pitch_shift, old_range, new_range)
    local pitch_shift = round((pitch_shift - 8192) * (old_range / new_range) + 8192)
    return math.min(math.max(pitch_shift, 0), 16383)
end

local function pitchBendToSemitones(pitch, range)
    range = range or tcutils.BEND_RANGE
    return (pitch - 8192) / (8192 / range)
end


local function semitonesToPitchBend(pitch, range)
    range = range or tcutils.BEND_RANGE
    return round((pitch * (8192 / range)) + 8192)
end


-- NOTE: will only work fully if the note is fully within the repeated section.
-- If note start is before the first repeat, or end is after the last repeat, but it is partially in, it will not work correctly.
local function getRepeats(take, ppqpos)
    local item = r.GetMediaItemTake_Item(take)
    local item_start = round(r.MIDI_GetPPQPosFromProjTime(take, r.GetMediaItemInfo_Value(item, "D_POSITION")))
    -- TODO check if always 0
    if item_start ~= 0 then
        mu.p("Item start is not 0, check getRepeats function in tcUtils")
        mu.p("Item start: " .. item_start)
        mu.p("pos: " .. r.MIDI_GetProjTimeFromPPQPos(take, ppqpos))
        -- r.ShowMessageBox("Item start is not 0, check getRepeats function in tcUtils", "Warning", 0)
    end
    local item_end = r.MIDI_GetPPQPosFromProjTime(take,
            r.GetMediaItemInfo_Value(item, "D_POSITION") + r.GetMediaItemInfo_Value(item, "D_LENGTH"))
        - 1 -- subtract one to not count the immediate end
    if not select(2, r.GetMediaSourceLength(r.GetMediaItemTake_Source(take))) then error("midi is not beat based??") end
    local source_length = r.GetMediaSourceLength(r.GetMediaItemTake_Source(take)) * mu.MIDI_GetPPQ(take) /
        r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
    -- Find the offset from known_marker to region_start
    local delta = item_start - ppqpos
    -- Find how many full spacings we need to get from known_marker to >= region_start
    local first_marker = ppqpos + math.ceil(delta / source_length) * source_length
    -- If the first marker is already past the end of the region, no markers are inside
    if first_marker > item_end then
        return 0
    end

    -- Now calculate how many markers fit from first_marker to region_end
    local count = math.floor((item_end - first_marker) / source_length) + 1
    return count, source_length
end






-----------------------------------------------------------------------------
----------------------------------- OOP -------------------------------------
-- === Class Definition ===
local class =
{
    _VERSION     = "middleclass v4.1.1",
    _DESCRIPTION = "Object Orientation for Lua",
    _URL         = "https://github.com/kikito/middleclass",
    _LICENSE     = [[
    MIT LICENSE

    Copyright (c) 2011 Enrique García Cota

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the
    "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish,
    distribute, sublicense, and/or sell copies of the Software, and to
    permit persons to whom the Software is furnished to do so, subject to
    the following conditions:

    The above copyright notice and this permission notice shall be included
    in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
    OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
    CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
    TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
  ]],
}
local function _createIndexWrapper(aClass, f)
    if f == nil then
        return aClass.__instanceDict
    elseif type(f) == "function" then
        return function(self, name)
            local value = aClass.__instanceDict[name]
            if value ~= nil then
                return value
            else
                return (f(self, name))
            end
        end
    else -- if  type(f) == "table" then
        return function(self, name)
            local value = aClass.__instanceDict[name]
            if value ~= nil then
                return value
            else
                return f[name]
            end
        end
    end
end

local function _propagateInstanceMethod(aClass, name, f)
    f = name == "__index" and _createIndexWrapper(aClass, f) or f
    aClass.__instanceDict[name] = f
    for subclass in pairs(aClass.subclasses) do
        if rawget(subclass.__declaredMethods, name) == nil then
            _propagateInstanceMethod(subclass, name, f)
        end
    end
end

local function _declareInstanceMethod(aClass, name, f)
    aClass.__declaredMethods[name] = f
    if f == nil and aClass.super then
        f = aClass.super.__instanceDict[name]
    end

    _propagateInstanceMethod(aClass, name, f)
end

local function _tostring(self) return "class " .. self.name end
local function _call(self, ...) return self:new(...) end

local function _createClass(name, super)
    local dict = {}
    dict.__index = dict
    local aClass =
    {
        name = name,
        super = super,
        static = {},
        __instanceDict = dict,
        __declaredMethods = {},
        subclasses = setmetatable({}, {__mode = "k"}),
    }
    if super then
        setmetatable(aClass.static,
            {
                __index = function(_, k)
                    local result = rawget(dict, k)
                    if result == nil then
                        return super.static[k]
                    end
                    return result
                end,
            })
    else
        setmetatable(aClass.static, {__index = function(_, k) return rawget(dict, k) end})
    end

    setmetatable(aClass,
        {__index = aClass.static, __tostring = _tostring, __call = _call, __newindex = _declareInstanceMethod,
        })
    return aClass
end


local function _includeMixin(aClass, mixin)
    assert(type(mixin) == "table", "mixin must be a table")
    for name, method in pairs(mixin) do
        if name ~= "included" and name ~= "static" then aClass[name] = method end
    end

    for name, method in pairs(mixin.static or {}) do
        aClass.static[name] = method
    end

    if type(mixin.included) == "function" then mixin:included(aClass) end
    return aClass
end

local function _deepCopy(orig, copies)
    copies = copies or {}
    if copies[orig] then
        return copies[orig]
    end

    local origType = type(orig)
    if origType == "table" then
        local copy = {}
        copies[orig] = copy
        for key, value in next, orig, nil do
            copy[_deepCopy(key, copies)] = _deepCopy(value, copies)
        end

        setmetatable(copy, _deepCopy(getmetatable(orig), copies))
        return copy
    else
        return orig
    end
end

local DefaultMixin =
{
    __tostring   = function(self) return "instance of " .. tostring(self.class) end,

    initialize   = function(self, ...) end,

    isInstanceOf = function(self, aClass)
        return type(aClass) == "table"
            and type(self) == "table"
            and (self.class == aClass
                or type(self.class) == "table"
                and type(self.class.isSubclassOf) == "function"
                and self.class:isSubclassOf(aClass))
    end,

    clone        = function(self)
        return _deepCopy(self)
    end,

    static       =
    {
        allocate = function(self)
            assert(type(self) == "table", "Make sure that you are using 'Class:allocate' instead of 'Class.allocate'")
            return setmetatable({class = self}, self.__instanceDict)
        end,

        new = function(self, ...)
            assert(type(self) == "table", "Make sure that you are using 'Class:new' instead of 'Class.new'")
            local instance = self:allocate()
            instance:initialize(...)
            return instance
        end,

        subclass = function(self, name)
            assert(type(self) == "table",  "Make sure that you are using 'Class:subclass' instead of 'Class.subclass'")
            assert(type(name) == "string", "You must provide a name(string) for your class")
            local subclass = _createClass(name, self)
            for methodName, f in pairs(self.__instanceDict) do
                if not (methodName == "__index" and type(f) == "table") then
                    _propagateInstanceMethod(subclass, methodName, f)
                end
            end

            subclass.initialize = function(instance, ...) return self.initialize(instance, ...) end
            self.subclasses[subclass] = true
            self:subclassed(subclass)
            return subclass
        end,

        subclassed = function(self, other) end,

        isSubclassOf = function(self, other)
            return type(other) == "table" and
                type(self.super) == "table" and
                (self.super == other or self.super:isSubclassOf(other))
        end,

        include = function(self, ...)
            assert(type(self) == "table", "Make sure you that you are using 'Class:include' instead of 'Class.include'")
            for _, mixin in ipairs({...}) do _includeMixin(self, mixin) end

            return self
        end,
    },
}
function class.class(name, super)
    assert(type(name) == "string", "A name (string) is needed for the new class")
    return super and super:subclass(name) or _includeMixin(_createClass(name), DefaultMixin)
end

setmetatable(class, {__call = function(_, ...) return class.class(...) end})
-- === MidiNote ===
local MidiNote = class("MidiNote")
function MidiNote:initialize(
    take,
    idx,
    selected,
    muted,
    ppqpos,
    endppqpos,
    chan,
    pitch,
    vel,
    endvel,
    pitchshift,
    pitchshiftend,
    repeats,
    repeat_offset)
    if r.ValidatePtr(take, "MediaItem_Take*") and idx then
        -- Construct from take + note index
        self:_loadFromTake(take, idx)
    end
    -- Construct from explicit fields
    self.source_take = take or nil
    self.idx = idx or nil
    self.selected = selected or self.selected or false
    self.muted = muted or self.muted or false
    self.start_ppqpos = ppqpos or self.start_ppqpos or 0
    self.end_ppqpos = endppqpos or self.end_ppqpos or 0
    self.channel = chan or self.channel or 0
    self.pitch = pitch or self.pitch or 0
    self.velocity = vel or self.velocity or 0
    self.end_velocity = endvel or self.end_velocity or 0
    self.pitch_shift_start = pitchshift or self.pitch_shift_start or 8192
    self.pitch_shift_end = pitchshiftend or self.pitch_shift_end or 8192
    self.pitch_channel = ((not tcutils.MERGE_PITCH_CHANNELS) and chan) or 0
    self.repeats = repeats or self.repeats or 1
    self.repeat_offset = repeat_offset or self.repeat_offset or 0
end

function MidiNote:_loadFromTake(take, note_idx)
    local ok, selected, muted, startppq, endppq, chan, pitch, vel, endvel = mu.MIDI_GetNote(take, note_idx)
    if not ok then error("Invalid note index or take") end
    self.selected = selected
    self.muted = muted
    self.start_ppqpos = startppq
    self.end_ppqpos = endppq
    self.channel = chan
    self.pitch = pitch
    self.velocity = vel
    self.end_velocity = endvel
    local rv, pitch_cc = mu.MIDI_GetCCValueAtTime(take, 0xE0, ((not tcutils.MERGE_PITCH_CHANNELS) and chan) or 0, 0, startppq, true)
    self.pitch_shift_start = rv and pitch_cc
    local rv, pitch_cc = mu.MIDI_GetCCValueAtTime(take, 0xE0, ((not tcutils.MERGE_PITCH_CHANNELS) and chan) or 0, 0, endppq, true)
    self.pitch_shift_end = rv and pitch_cc
    self.repeats, self.repeat_offset = getRepeats(take, startppq)
end

-- todo: maybe convert between ppq resolution of source take and target take?
function MidiNote:insertIntoTake(take, commit)
    if commit then
        ensureMidiInit(take, true)
    else
        ensureMidiInit(take, false)
    end
    local note_rv, note_idx = mu.MIDI_InsertNote(
        take,
        self.selected,
        self.muted,
        self.start_ppqpos,
        self.end_ppqpos,
        self.channel,
        self.pitch,
        self.velocity,
        self.end_velocity
    )
    local cc1_rv, cc1_idx = mu.MIDI_InsertCC(
        take,
        false,
        false,
        self.start_ppqpos,
        0xE0,
        self.pitch_channel,
        0,
        self.pitch_shift_start & 0x7F,
        (self.pitch_shift_start >> 7) & 0x7F

    )
    local cc2_rv, cc2_idx = mu.MIDI_InsertCC(
        take,
        false,
        false,
        self.end_ppqpos,
        0xE0,
        self.pitch_channel,
        0,
        self.pitch_shift_end & 0x7F,
        (self.pitch_shift_end >> 7) & 0x7F
    )
    if not note_rv and cc1_rv and not cc2_rv then return false end
    if commit then mu.MIDI_CommitWriteTransaction(take) end
    return true, note_idx, cc1_idx, cc2_idx
end

-- === MidiCC ===
local MidiCC = class("MidiCC")
function MidiCC:initialize(take, idx, selected, muted, ppqpos, chanmsg, chan, msg2, msg3, repeats, repeat_offset
)
    if r.ValidatePtr(take, "MediaItem_Take*") and idx then
        -- Construct from take + note index
        self:_loadFromTake(take, idx)
    end
    -- Construct from explicit fields
    self.source_take = take or nil
    self.idx = idx or nil
    self.selected = selected or self.selected or false
    self.muted = muted or self.muted or false
    self.ppqpos = ppqpos or self.ppqpos or 0
    self.chanmsg = chanmsg or self.chanmsg or 0
    self.channel = chan or self.channel or 0
    self.msg2 = msg2 or self.msg2 or 0
    self.msg3 = msg3 or self.msg3 or 0
    self.repeats = repeats or self.repeats or 1
    self.repeat_offset = repeat_offset or self.repeat_offset or 0
end

function MidiCC:_loadFromTake(take, note_idx)
    local ok, selected, muted, ppqpos, chanmsg, chan, msg2, msg3 = mu.MIDI_GetCC(take, note_idx)
    if not ok then error("Invalid CC index or take") end
    self.selected = selected
    self.muted = muted
    self.ppqpos = ppqpos
    self.chanmsg = chanmsg
    self.channel = chan
    self.msg2 = msg2
    self.msg3 = msg3
    self.repeats, self.repeat_offset = getRepeats(take, ppqpos)
end

-- todo: maybe convert between ppq resolution of source take and target take?
function MidiCC:insertIntoTake(take, commit)
    if commit then
        ensureMidiInit(take, true)
    else
        ensureMidiInit(take, false)
    end
    local rv, idx = mu.MIDI_InsertCC(
        take,
        self.selected,
        self.muted,
        self.ppqpos,
        self.chanmsg,
        self.channel,
        self.msg2,
        self.msg3

    )
    if not rv then return false end
    if commit then mu.MIDI_CommitWriteTransaction(take) end
    return true, idx
end

-- === MidiText ===
local MidiText = class("MidiText")
function MidiText:initialize(take, idx, selected, muted, ppqpos, type, msg, repeats, repeat_offset
)
    if r.ValidatePtr(take, "MediaItem_Take*") and idx then
        -- Construct from take + note index
        self:_loadFromTake(take, idx)
    end
    -- Construct from explicit fields
    self.source_take = take or nil
    self.idx = idx or nil
    self.selected = selected or self.selected or false
    self.muted = muted or self.muted or false
    self.ppqpos = ppqpos or self.ppqpos or 0
    self.type = type or self.type or 0
    self.msg = msg or self.msg or ""
    self.repeats = repeats or self.repeats or 1
    self.repeat_offset = repeat_offset or self.repeat_offset or 0
end

function MidiText:_loadFromTake(take, idx)
    local ok, selected, muted, ppqpos, type, msg = mu.MIDI_GetTextSysexEvt(take, idx)
    if not ok then error("Invalid text index or take") end
    self.selected = selected
    self.muted = muted
    self.ppqpos = ppqpos
    self.type = type or self.type or 0
    self.msg = msg or self.msg or ""
    self.repeats, self.repeat_offset = getRepeats(take, ppqpos)
end

-- todo: maybe convert between ppq resolution of source take and target take?
function MidiText:insertIntoTake(take, commit)
    if commit then
        ensureMidiInit(take, true)
    else
        ensureMidiInit(take, false)
    end
    local rv, idx = mu.MIDI_InsertTextSysexEvt(
        take,
        self.selected,
        self.muted,
        self.ppqpos,
        self.type,
        self.channel,
        self.msg
    )
    if not rv then return false end
    if commit then mu.MIDI_CommitWriteTransaction(take) end
    return true, idx
end

-- === TmbNote ===
local TmbNote = class("TmbNote")
function TmbNote:initialize(start_pos, length, pitch_start, pitch_end, source_notes)
    if not start_pos or not length or not pitch_start or not pitch_end then
        error("TmbNote: missing required arguments")
    end
    self.start_pos = start_pos
    self.length = length
    self.pitch_start = pitch_start
    self.pitch_end = pitch_end
    self.source_notes = source_notes or {}
end

function TmbNote:toTable()
    local tmb_note = {self.start_pos, self.length, self.pitch_start, self.pitch_end - self.pitch_start, self.pitch_end}
    return tmb_note
end

-- TODO bweh
function TmbNote:convertToMidiNote(take, commit)
    if #self.source_notes ~= 0 then
        -- TODO: implement
    end
    local note = MidiCC:new(nil, nil, false, false, beatsToTime(self.start_pos), beatsToTime(self.start_pos + self.length), 0, 0,
        0, 0, 8192, 8192)
    note.pitch = tmbToMidiPitch(self.pitch_start)
    note.pitch_shift_start = semitonesToPitchBend(self.pitch_start)
    note.pitch_shift_end = semitonesToPitchBend(self.pitch_end)
    return note:insertIntoTake(take, commit)
end

-- === Lyric ===
local Lyric = class("Lyric")
function Lyric:initialize(pos, text)
    if not pos or not text then
        error("Lyric: missing required arguments")
    end
    self.bar = pos
    self.text = text
end

function Lyric:toTable()
    local lyric = {bar = self.bar, text = self.text}
    return lyric
end

-- === Improv Zone ===
local ImprovZone = class("ImprovZone")
function ImprovZone:initialize(start_pos, end_pos)
    if not start_pos or not end_pos then
        error("ImprovZone: missing required arguments")
    end
    self.start_pos = start_pos
    self.end_pos = end_pos
end

function ImprovZone:toTable()
    local improv_zone = {self.start_pos, self.end_pos}
    return improv_zone
end

-- === Background Event ===
-- TODO: maybe let missing one pos be okay
local BgEvent = class("BgEvent")
function BgEvent:initialize(pos1, pos2, event_id)
    if not event_id or not pos1 or not pos2 then
        error("BgEvent: missing required arguments")
    end
    self.pos1 = pos1
    self.pos2 = pos2
    self.event_id = event_id
end

function BgEvent:toTable()
    local bg_event = {self.pos1, self.pos2, self.event_id}
    return bg_event
end

-----------------------------------------------------------------------------
----------------------------------- Functions -------------------------------------
local function getTakeNotes(take, explicit_repeats)
    ensureMidiInit(take, false)
    local rv, note_count = mu.MIDI_CountEvts(take)
    if not rv then return false end
    if tcutils.MERGE_PITCH_CHANNELS then mergePitchShifts(take) end
    if r.GetMediaItemInfo_Value(r.GetMediaItemTake_Item(take), "B_LOOPSRC") == 0 then
        explicit_repeats = false
    end
    -- get all notes
    local midi_notes = {}
    for i = 0, note_count - 1 do
        local note = MidiNote(take, i)
        for j = 0, note.repeats - 1 do
            local new_note = note:clone()
            new_note.start_ppqpos = note.start_ppqpos + (note.repeat_offset * j)
            new_note.end_ppqpos = note.end_ppqpos + (note.repeat_offset * j)
            new_note.repeats = 1
            table.insert(midi_notes, new_note)
            if not explicit_repeats then
                break
            end
        end

        note.repeats = 1
    end

    table.sort(midi_notes, function(a, b) return a.start_ppqpos < b.start_ppqpos end)
    return midi_notes
end
local function getTakesNotes(takes)
    local all_midi_notes = {}
    for _, take in ipairs(takes) do
        local rv, midi_notes = getTakeNotes(take)
        if rv then
            all_midi_notes = mergeTables(all_midi_notes, midi_notes)
        end
    end

    -- sort notes
    table.sort(all_midi_notes, function(a, b) return a.start_ppqpos < b.start_ppqpos end)
    return true, all_midi_notes
end



local function splitMidiNotes(notes)
    local notes = notes or {}
    table.sort(notes, function(a, b) return a.start_ppqpos < b.start_ppqpos end)
    local split_notes = {}
    local prev_note_end = 0
    local group = {}
    for _, note in ipairs(notes) do
        if note.start_ppqpos > prev_note_end then
            if #group > 0 then
                table.insert(split_notes, group)
            end
            group = {}
        end
        table.insert(group, note)
        prev_note_end = note.end_ppqpos
    end

    table.insert(split_notes, group)
    return split_notes
end


local function splitSlides(notes)
    switch(#notes)
    {
        [0] = function() return {} end,
        [1] = function() return {notes} end,
        [2] = function() return {notes[1], notes[2]} end,
    }
    local segments = {}
    table.sort(notes, function(a, b) return a.start_ppqpos < b.start_ppqpos end)
    while #notes > 1 do
        if notes[1].pitch == notes[2].pitch then
            table.insert(segments, {table.remove(notes, 1)})
        else
            table.insert(segments, {table.remove(notes, 1), table.remove(notes, 1)})
        end
    end

    if #notes == 1 then
        table.insert(segments, {table.remove(notes, 1)})
    end
    return segments
end

local function midiTakeNotesToTmb(take)
    local midi_notes = getTakeNotes(take, true)
    table.sort(midi_notes, function(a, b) return a.start_ppqpos < b.start_ppqpos end)
    local bpm = getProjectTempo()
    -- convert notes to tmb format
    local tmbnotes = {}
    for _, group in ipairs(splitMidiNotes(midi_notes)) do
        for _, segment in ipairs(splitSlides(group)) do
            table.insert(tmbnotes, TmbNote(
                round(timeToBeats(r.MIDI_GetProjTimeFromPPQPos(take, segment[1].start_ppqpos)), 5),
                round(timeToBeats(r.MIDI_GetProjTimeFromPPQPos(take, segment[#segment].end_ppqpos))
                    - timeToBeats(r.MIDI_GetProjTimeFromPPQPos(take, segment[1].start_ppqpos)), 5),
                midiToTmbPitch(segment[1].pitch + pitchBendToSemitones(segment[1].pitch_shift_start)),
                midiToTmbPitch(segment[#segment].pitch + pitchBendToSemitones(segment[#segment].pitch_shift_end)),
                segment
            ))
        end
    end

    return tmbnotes
end

local function midiTakesNotesToTmb(takes)
    local all_tmbnotes = {}
    for _, take in ipairs(takes) do
        local tmbnotes = midiTakeNotesToTmb(take)
        all_tmbnotes = mergeTables(all_tmbnotes, tmbnotes)
    end

    -- sort tables
    table.sort(all_tmbnotes, function(a, b) return a.start_pos < b.start_pos end)
    return true, all_tmbnotes
end


-- TODO: no ppq reference, this be goofy
local function tmbToMidi(notes)
    local midi_notes = {}
    for _, note in ipairs(notes) do
        local raw_pitch = tmbToMidiPitch(note.pitch_start)
        local midi_note1 =
        {
            pitch = math.floor(raw_pitch),
            start_ppqpos = beatsToTime(note.start_pos),
            end_ppqpos = beatsToTime(note.end_pos),
            channel = 0,
            pitch_shift_start = semitonesToPitchBend(raw_pitch - math.floor(raw_pitch)),

        }
        local raw_pitch = tmbToMidiPitch(note.pitch_end)
        local midi_note2 =
        {
            pitch = math.floor(raw_pitch),
            start_pos = beatsToTime(note.end_pos) - 10,
            end_pos = beatsToTime(note.end_pos),
            channel = 0,
            pitch_shift_start = semitonesToPitchBend(raw_pitch - math.floor(raw_pitch)),
        }
        table.insert(midi_notes, midi_note1)
        if note.pitch_start ~= note.pitch_end then
            table.insert(midi_notes, midi_note2)
        end
    end

    return midi_notes
end



local function getTakeText(take, explicit_repeats)
    ensureMidiInit(take, false)
    local all_text = {}
    local take_start, take_length, source_length = getTakeInfo(take)
    local rv, _, _, text_count = mu.MIDI_CountEvts(take)
    if not rv then return false end
    for i = 0, text_count - 1 do
        local text = MidiText(take, i)
        for _, ignore_type in ipairs(tcutils.EXCLUDE_TEXT_TYPES) do
            if text.type == ignore_type then goto continueNote end
        end

        table.insert(all_text, text)
        ::continueNote::
    end

    if explicit_repeats then
        for _, text in ipairs(all_text) do
            if text.repeats <= 1 then goto continue end
            for i = 1, text.repeats - 1 do
                local new_note = text
                new_note.start_ppqpos = text.start_ppqpos + (text.repeat_offset * i)
                new_note.end_ppqpos = text.end_ppqpos + (text.repeat_offset * i)
                table.insert(all_text, new_note)
            end

            text.repeats = 1
            ::continue::
        end
    end

    table.sort(all_text, function(a, b) return a.ppqpos < b.ppqpos end)
    return true, all_text
end

local function getAllTakesText(takes)
    local all_text = {}
    for _, take in ipairs(takes) do
        local rv, text = getTakeText(take)
        if rv then
            all_text = mergeTables(all_text, text)
        end
    end

    -- sort tables
    table.sort(all_text, function(a, b) return a.ppqpos < b.ppqpos end)
    return true, all_text
end



local function midiTakeTextToTmb(take)
    local rv, midi_text = getTakeText(take)
    if not rv then return false end
    local lyrics = {}
    local improv_zones = {}
    local bg_events = {}
    local improv_start = nil
    --- @diagnostic disable-next-line: param-type-mismatch
    for _, text in ipairs(midi_text) do
        local pos = timeToBeats(r.MIDI_GetProjTimeFromPPQPos(take, text.ppqpos))
        if text.type == 6 then
            local bg_event = tonumber(text.msg:match("[0-9]+"))
            if not bg_event then
                r.ShowMessageBox(
                    "Text marker without bgevent ID at " .. r.MIDI_GetProjTimeFromPPQPos(take, text.ppqpos) .. " seconds. Skipping",
                    "Error", 0)
                goto continue
            end
            table.insert(bg_events, BgEvent(r.MIDI_GetProjTimeFromPPQPos(take, text.ppqpos), pos, bg_event))
            goto continue
        end

        if text.msg:find("improv_start") then
            improv_start = pos
        elseif text.msg:find("improv_end") then
            if improv_start then
                table.insert(improv_zones, ImprovZone(improv_start, pos))
                improv_start = nil
            else
                r.ShowMessageBox("Improv end without start at " .. r.MIDI_GetProjTimeFromPPQPos(take, text.ppqpos) .. " seconds",
                    "Error", 0)
                error("Improv end without start at " .. r.MIDI_GetProjTimeFromPPQPos(take, text.ppqpos) .. " seconds", 3)
            end
        elseif text.msg:lower():find("bgevent") then
            local bg_event = tonumber(text.msg:match("[0-9]+"))
            if bg_event then
                table.insert(bg_events, BgEvent(r.MIDI_GetProjTimeFromPPQPos(take, text.ppqpos), pos, bg_event))
            end
        else
            table.insert(lyrics, Lyric(pos, text.msg))
        end

        ::continue::
    end

    return true, lyrics, improv_zones, bg_events
end
local function midiTakesTextToTmb(takes)
    local all_lyrics = {}
    local all_improv_zones = {}
    local all_bg_events = {}
    for _, take in ipairs(takes) do
        local rv, lyrics, improv_zones, bg_events = midiTakeTextToTmb(take)
        if rv then
            all_lyrics = mergeTables(all_lyrics, lyrics)
            all_improv_zones = mergeTables(all_improv_zones, improv_zones)
            all_bg_events = mergeTables(all_bg_events, bg_events)
        end
    end

    -- sort tables
    table.sort(all_lyrics,       function(a, b) return a.bar < b.bar end)
    table.sort(all_improv_zones, function(a, b) return a.start_pos < b.start_pos end)
    table.sort(all_bg_events,    function(a, b) return a.pos1 < b.pos1 end)
    return true, all_lyrics, all_improv_zones, all_bg_events
end


local function midiToTmb(takes)
    if not takes or #takes == 0 then
        r.ShowMessageBox("No MIDI takes found in the project", "Error", 0)
        return false
    end
    local rv, notes = midiTakesNotesToTmb(takes)
    if not rv then return false end
    local rv, text, lyrics, bgevents = midiTakesTextToTmb(takes)
    notes = notes or {}
    text = text or {}
    lyrics = lyrics or {}
    bgevents = bgevents or {}
    return true, notes, text, lyrics, bgevents
end



local function getActive()
    local function isTrackAudible(track)
        if not track then return false end
        local solo = r.GetMediaTrackInfo_Value(track, "I_SOLO")
        local muted = r.GetMediaTrackInfo_Value(track, "B_MUTE")
        local vol = r.GetMediaTrackInfo_Value(track, "D_VOL")
        if solo > 0 then
            return vol > 0
        end

        return muted == 0 and vol > 0
    end

    local function isItemAudible(item)
        if not item then return false end
        local mute = r.GetMediaItemInfo_Value(item, "B_MUTE")
        local mute_actual = r.GetMediaItemInfo_Value(item, "B_MUTE_ACTUAL")
        local mute_solo = r.GetMediaItemInfo_Value(item, "B_MUTE_SOLO")
        local vol = r.GetMediaItemInfo_Value(item, "D_VOL")
        local track = r.GetMediaItem_Track(item)
        local lane_mode = r.GetMediaTrackInfo_Value(track, "I_FREEMODE")
        local lane_active = true
        if lane_mode == 2 then
            lane_active = r.GetMediaItemInfo_Value(item, "C_LANEPLAYS ") > 0
        end
        return mute == 0 and mute_actual == 0 and mute_solo == 0 and vol > 0 and lane_active
    end

    local function isTakeActive(take, item)
        if not take or not r.TakeIsMIDI(take) then return false end
        local active_take = r.GetActiveTake(item)
        return take == active_take
    end

    local function isTrackSoloAudible(track, all_tracks)
        local solo = r.GetMediaTrackInfo_Value(track, "I_SOLO")
        local solo_defeat = r.GetMediaTrackInfo_Value(track, "B_SOLO_DEFEAT")
        local any_solo = false
        for _, t in ipairs(all_tracks) do
            if r.GetMediaTrackInfo_Value(t, "I_SOLO") > 0 then
                any_solo = true
                break
            end
        end

        if not any_solo then
            return true -- everything is audible
        end
        if solo > 0 then
            return true -- this track is soloed
        end
        if solo_defeat == 1 then
            return true -- this track is solo defeated, so it's included during solos
        end
        return false
    end

    local all_tracks = {}
    for i = 0, r.CountTracks(0) - 1 do
        table.insert(all_tracks, r.GetTrack(0, i))
    end

    local active_takes = {}
    local active_items = {}
    local active_tracks = {}
    for i = 0, #all_tracks do
        local track = all_tracks[i]
        if isTrackAudible(track) and isTrackSoloAudible(track, all_tracks) then
            for j = 0, r.CountTrackMediaItems(track) - 1 do
                local item = r.GetTrackMediaItem(track, j)
                if isItemAudible(item) then
                    local take = r.GetActiveTake(item)
                    if isTakeActive(take, item) then
                        table.insert(active_takes,  take)
                        table.insert(active_items,  item)
                        table.insert(active_tracks, track)
                    end
                end
            end
        end
    end

    return active_takes, removeDuplicates(active_items), removeDuplicates(active_tracks)
end



local function getAllTakes()
    local takes = {}
    local track_count = r.CountTracks(0) -- Get number of tracks in current project
    for i = 0, track_count - 1 do
        local track = r.GetTrack(0, i)
        local item_count = r.CountTrackMediaItems(track)
        for j = 0, item_count - 1 do
            local item = r.GetTrackMediaItem(track, j)
            local take_count = r.CountTakes(item)
            for k = 0, take_count - 1 do
                local take = r.GetTake(item, k)
                if r.TakeIsMIDI(take) then
                    table.insert(takes, take)
                end
            end
        end
    end

    return takes
end

local function filterTmbData(data)
    -- check if all required settings are present
    local filtered_data = {}
    local missing_keys = {}
    for _, key in ipairs(tcutils.REQUIRED_TMB_SETTINGS) do
        if data[key] ~= "" then
            filtered_data[key] = data[key]
        else
            table.insert(missing_keys, key)
        end
    end

    -- find the non-required settings
    local optional_keys = {}
    for _, key in ipairs(tcutils.ALL_TMB_SETTINGS) do
        if not tcutils.REQUIRED_TMB_SETTINGS[key] then
            table.insert(optional_keys, key)
        end
    end

    -- format note data
    data.endpoint = tonumber(data.endpoint) or 0
    for i = 1, #data["notes"] do
        data.endpoint = math.max(data.endpoint, math.ceil(data["notes"][i].start_pos + data["notes"][i].length) + 4)
        filtered_data["notes"][i] = filtered_data["notes"][i]:toTable()
    end

    for _, key in ipairs(optional_keys) do
        if data[key] ~= "" then
            filtered_data[key] = data[key]
        else
            switch(key)
            {
                ["tempo"] = function() filtered_data.tempo = getProjectTempo() end,
                ["timesig"] = function() filtered_data.timesig = 4 end,
                ["difficulty"] = function() filtered_data.difficulty = 5 end,
                ["savednotespacing"] = function() filtered_data.savednotespacing = 200 end,
                ["note_color_start"] = function() filtered_data.note_color_start = {1.0, 0.0, 0.0} end,
                ["note_color_end"] = function() filtered_data.note_color_end = {0.0, 0.0, 1.0} end,
            }
        end
    end

    if #missing_keys > 0 then
        local missing_keys_str = table.concat(missing_keys, ", ")
        r.ShowMessageBox("Missing required settings: " .. missing_keys_str, "Error", 0)
        return false
    end

    return true, filtered_data
end



-- @param mode: int
-- 0: insert, 1: insert in duplicate item, 2: insert in duplicate take in same item
local function emulateSlidesInMidiTake(take, pitchbend_range, mode)
    mode = mode or 0
    switch(mode)
    {
        [0] = function() end,          -- insert in current take
        [1] = function()               -- insert in duplicated item
            r.Main_OnCommand(40289, 0) -- Deselect all items
            local item = r.GetMediaItemTake_Item(take)
            local take_id = r.GetMediaItemTakeInfo_Value(take, "I_TAKENUMBER")
            local track = r.GetMediaItem_Track(item)
            r.SetMediaItemSelected(item, true)
            r.Main_OnCommand(40698, 0) -- Copy items
            r.SetMediaItemSelected(item, false)
            r.SetEditCurPos(r.GetMediaItemInfo_Value(item, "D_POSITION"), false, false)
            r.SetOnlyTrackSelected(track)
            r.Main_OnCommand(42398, 0) -- Paste items
            local new_item = r.GetSelectedMediaItem(0, 0)
            r.SetMediaItemSelected(new_item, false)
            take = r.GetMediaItemTake(new_item, take_id)
        end,
        [2] = function() -- insert in duplicated take in same item
            r.Main_OnCommand(40289, 0)
            local item = r.GetMediaItemTake_Item(take)
            local active_take = r.GetActiveTake(item)
            r.SetActiveTake(take)
            r.SetMediaItemSelected(item, true)
            r.Main_OnCommand(40639, 0) -- duplicate active take
            r.SetMediaItemSelected(item, false)
            r.SetActiveTake(active_take)
        end,
        __index = function() -- invalid mode
            error("Invalid mode for emulateSlidesInMidiTake", 3)
            return false
        end,
    }
    local notes = getTakeNotes(take)
    if not notes then return false end
    pitchbend_range = pitchbend_range or tcutils.BEND_RANGE
    local function insertPitchBend(take, base_note, note, shape, start)
        local _, idx
        if start then
            local pitchbend = math.min(math.max(
                semitonesToPitchBend(note.pitch - base_note.pitch, pitchbend_range)
                + convertPitchRange(note.pitch_shift_start, tcutils.BEND_RANGE, pitchbend_range)
                - 8192,
                0), 16383)
            _, idx = mu.MIDI_InsertCC(take, false, false, note.start_ppqpos, 0xE0, 0,
                round((pitchbend), 0) & 0x7F,
                (round(pitchbend) >> 7) & 0x7F
            )
        else
            local pitchbend = math.min(math.max(
                semitonesToPitchBend(note.pitch - base_note.pitch, pitchbend_range)
                + convertPitchRange(note.pitch_shift_end, tcutils.BEND_RANGE, pitchbend_range)
                - 8192,
                0), 16383)
            _, idx = mu.MIDI_InsertCC(take, false, false, note.end_ppqpos, 0xE0, 0,
                round((pitchbend), 0) & 0x7F,
                (round(pitchbend) >> 7) & 0x7F
            )
        end

        mu.MIDI_SetCCShape(take, idx, shape, 0)
    end

    mu.MIDI_InitializeTake(take)
    mu.MIDI_OpenWriteTransaction(take)
    -- iterate through notes sorted descending from their start position
    table.sort(notes, function(a, b) return a.start_ppqpos < b.start_ppqpos end)
    for i = #notes, 1, -1 do
        mu.MIDI_DeleteNote(take, notes[i].idx)
    end

    for i = select(3, mu.MIDI_CountEvts(take)) - 1, 0, -1 do
        if select(5, mu.MIDI_GetCC(take, i)) == 0xE0 then
            mu.MIDI_DeleteCC(take, i)
        end
    end

    for _, group in ipairs(splitMidiNotes(notes)) do
        local base_note = group[1]
        mu.MIDI_InsertNote(take, false, false, group[1].start_ppqpos, group[#group].end_ppqpos, group[1].channel, group[1].pitch,
            100, 100)
        insertPitchBend(take, base_note, base_note, 2, true)
        while #group > 1 do
            local note1 = group[1]
            local note2
            if group[2] then
                note2 = group[2]
            end
            if not note2 then break end
            if note1.pitch == note2.pitch and note1.pitch_shift_start == note2.pitch_shift_start then
                table.remove(group, 1)
            else
                insertPitchBend(take, base_note, note1, 2, true)
                insertPitchBend(take, base_note, note2, 2, false)
                table.remove(group, 1)
                table.remove(group, 1)
            end
        end

        if #group == 1 then
            insertPitchBend(take, base_note, group[1], 0, false)
        end
    end

    mu.MIDI_CommitWriteTransaction(take)
    return true
end

local function emulateSlidesInMidiTakes(takes, pitchbend_range, mode)
    for _, take in ipairs(takes) do
        local rv = emulateSlidesInMidiTake(take, pitchbend_range, mode)
        if not rv then return false end
    end

    return true
end

local function writeTmb(path, data)
    local rv, data = filterTmbData(data)
    if not rv then
        r.ShowMessageBox("Failed to filter TMB data!", "Error", 0)
        return false
    end

    local file = io.open(path, "w")
    local json_string = json.encode(data,
        {
            indent = true,
            keyorder =
            {
                "name",
                "shortName",
                "author",
                "year",
                "genre",
                "description",
                "tempo",
                "timesig",
                "difficulty",
                "savednotespacing",
                "endpoint",
                "trackRef",
                "note_color_start",
                "note_color_end",
                "improv_zones",
                "lyrics",
                "bgdata",
                "notes",
            },
        })
    if file then
        file:write(json_string)
        file:close()
        r.ShowMessageBox("TMB exported to " .. path, "Success", 0)
    else
        r.ShowMessageBox("Failed to save TMB!", "Error", 0)
        error("Failed to save TMB!", 3)
        return false
    end
    return true
end



-- TODO: format read keys
local function importTmb(path)
    local tmb = {}
    local file = io.open(path, "r")
    if not file then
        r.ShowMessageBox("Failed to open TMB file!", "Error", 0)
        error("Failed to open TMB file!", 3)
        return false
    end

    local json_string = file:read("*a")
    file:close()
    local data, _, err = json.decode(json_string)
    if err then
        r.ShowMessageBox("Failed to parse TMB data: " .. err, "Error", 0)
        error("Failed to parse TMB data: " .. err, 3)
        return false
    end

    for key, value in pairs(data) do
        if key == "notes" then
            local notes = {}
            for _, note in ipairs(value) do
                table.insert(notes, {start_pos = note[1], end_pos = note[1] + note[2], pitch_start = note[3], pitch_end = note[5]})
            end

            -- tmb[key] = notes
        else
            tmb[key] = value
        end
    end

    return true, tmb
end

local function convertToTmb(notes, lyrics, improv_zones, bg_events, settings)
    if notes then
        for i, note in ipairs(notes) do
            notes[i] = note:toTable()
        end
    end
    if lyrics then
        for i, lyric in ipairs(lyrics) do
            lyrics[i] = lyric:toTable()
        end
    end
    if improv_zones then
        for i, zone in ipairs(improv_zones) do
            improv_zones[i] = zone:toTable()
        end
    end
    if bg_events then
        for i, event in ipairs(bg_events) do
            bg_events[i] = event:toTable()
        end
    end

    local tmb = {}
    tmb.notes = notes or {}
    tmb.lyrics = lyrics or {}
    tmb.improv_zones = improv_zones or {}
    tmb.bgdata = bg_events or {}
    if settings then
        for k, v in pairs(settings) do
            tmb[k] = v
        end
    end
    return tmb
end
local function diffCalc(takes)
    local rv, lyrics, improv_zones, bg_events = midiTakesTextToTmb(takes)
    if not rv then return end
    local rv, notes = midiTakesNotesToTmb(takes)
    if not rv then return end
    local settings =
    {
        note_color_start = {1.0, 0.0, 0.0},
        note_color_end = {0.0, 0.0, 1.0},
        name = "BonerViewer",
        shortName = "BonerViewer",
        author = "BonerViewer",
        year = 2025,
        genre = "BonerViewer",
        description = "BonerViewer",
        timesig = 4,
        difficulty = 10,
        savednotespacing = 200,
        trackRef = "BonerViewer",
        tempo = getProjectTempo(),
        endpoint = 0,
    }
    settings.endpoint = math.ceil(notes[#notes].start_pos + notes[#notes].length) + 4
    local tmb = convertToTmb(notes, lyrics, improv_zones, bg_events, settings)
    local url = "https://toottally.com/api/upload/"
    local data = json.encode({skip_save = true, tmb = json.encode(tmb)})
    local response = httpPost(url, data)
    return json.decode(response)
end


-----------------------------------------------------------------------------
----------------------------------- Interface -------------------------------
-- Converts a MIDI pitch to a TMB pitch.
function tcutils.midiToTmbPitch(pitch, clamp)
    enforceArgs(
        makeTypedArg(pitch, "number", false),
        makeTypedArg(clamp, "boolean", true)

    )
    if not tcutils.USE_XPCALL then
        return midiToTmbPitch(pitch, clamp)
    else
        return select(2, xpcall(midiToTmbPitch, onError, pitch, clamp))
    end
end

-- Converts a TMB pitch to a MIDI pitch.
function tcutils.tmbToMidiPitch(pitch, clamp)
    enforceArgs(
        makeTypedArg(pitch, "number", false),
        makeTypedArg(clamp, "boolean", true)
    )
    if not tcutils.USE_XPCALL then
        return tmbToMidiPitch(pitch, clamp)
    else
        return select(2, xpcall(tmbToMidiPitch, onError, pitch, clamp))
    end
end

-- Gets the starting project tempo
function tcutils.getProjectTempo()
    if not tcutils.USE_XPCALL then
        return getProjectTempo()
    else
        return select(2, xpcall(getProjectTempo, onError))
    end
end

-- Converts a project time to beats, calculated from the project tempo.
function tcutils.timeToBeats(time_secs)
    enforceArgs(
        makeTypedArg(time_secs, "number", false)
    )
    if not tcutils.USE_XPCALL then
        return timeToBeats(time_secs)
    else
        return select(2, xpcall(timeToBeats, onError, time_secs))
    end
end

-- Converts beats to project time, calculated from the project tempo.
function tcutils.beatsToTime(beats)
    enforceArgs(
        makeTypedArg(beats, "number", false)
    )
    if not tcutils.USE_XPCALL then
        return beatsToTime(beats)
    else
        return select(2, xpcall(beatsToTime, onError, beats))
    end
end

-- Returns all notes from midi takes
function tcutils.getMidiNotes(takes)
    if type(takes) ~= "table" then
        takes = {takes}
    end
    enforceArgs(
        makeTypedArg(takes, "table")
    )
    for _, take in ipairs(takes) do
        enforceArgs(
            makeTypedArg(take, "userdata", false, "MediaItem_Take*")
        )
    end

    if not tcutils.USE_XPCALL then
        return getTakesNotes(takes)
    else
        return select(2, xpcall(getTakesNotes, onError, takes))
    end
end

-- Converts midi take notes to tmb format.
function tcutils.midiTakeNotesToTmb(takes)
    if type(takes) ~= "table" then
        takes = {takes}
    end
    enforceArgs(
        makeTypedArg(takes, "table")
    )
    for _, take in ipairs(takes) do
        enforceArgs(
            makeTypedArg(take, "userdata", false, "MediaItem_Take*")
        )
    end

    if not tcutils.USE_XPCALL then
        return midiTakesNotesToTmb(takes)
    else
        return select(2, xpcall(midiTakesNotesToTmb, onError, takes))
    end
end

function tcutils.midiToTmb(takes)
    if type(takes) ~= "table" then
        takes = {takes}
    end
    enforceArgs(
        makeTypedArg(takes, "table")
    )
    for _, take in ipairs(takes) do
        enforceArgs(
            makeTypedArg(take, "userdata", false, "MediaItem_Take*")
        )
    end

    if not tcutils.USE_XPCALL then
        return midiToTmb(takes)
    else
        return select(2, xpcall(midiToTmb, onError, takes))
    end
end

-- Converts a list of tmb notes to midi format.
function tcutils.tmbToMidi(notes)
    enforceArgs(
        makeTypedArg(notes, "table", false)
    )
    for _, note in ipairs(notes) do
        enforceArgs(
            makeTypedArg(note.start_pos, "number", false),
            makeTypedArg(note.end_pos, "number", false),
            makeTypedArg(note.pitch_start, "number", false),
            makeTypedArg(note.pitch_end, "number", false)
        )
    end

    if not tcutils.USE_XPCALL then
        return tmbToMidi(notes)
    else
        return select(2, xpcall(tmbToMidi, onError, notes))
    end
end

-- Gets all text events from midi takes
function tcutils.getTakeText(takes)
    if type(takes) ~= "table" then
        takes = {takes}
    end
    enforceArgs(
        makeTypedArg(takes, "table")
    )
    for _, take in ipairs(takes) do
        enforceArgs(
            makeTypedArg(take, "userdata", false, "MediaItem_Take*")
        )
    end

    if not tcutils.USE_XPCALL then
        return getAllTakesText(takes)
    else
        return select(2, xpcall(getAllTakesText, onError, takes))
    end
end

-- Converts midi take notes to tmb format.
-- TODO: combine text and notes into one function
function tcutils.midiTakeTextToTmb(takes)
    if type(takes) ~= "table" then
        takes = {takes}
    end
    enforceArgs(
        makeTypedArg(takes, "table")
    )
    for _, take in ipairs(takes) do
        enforceArgs(
            makeTypedArg(take, "userdata", false, "MediaItem_Take*")
        )
    end

    if not tcutils.USE_XPCALL then
        return midiTakesTextToTmb(takes)
    else
        return select(2, xpcall(midiTakesTextToTmb, onError, takes))
    end
end

-- Gets all active midi takes in the project, alongside their items and tracks.
function tcutils.getActive()
    if not tcutils.USE_XPCALL then
        return getActive()
    else
        return select(2, xpcall(getActive, onError))
    end
end

-- writes a tmb file to the given path
function tcutils.writeTmb(path, data)
    enforceArgs(
        makeTypedArg(path, "string", false),
        makeTypedArg(data, "table", false)
    )
    if not tcutils.USE_XPCALL then
        return writeTmb(path, data)
    else
        return select(2, xpcall(writeTmb, onError, path, data))
    end
end

-- imports a tmb file from the given path
function tcutils.importTmb(path)
    enforceArgs(
        makeTypedArg(path, "string", false)
    )
    if not r.file_exists(path) then
        r.ShowMessageBox("File does not exist: " .. path, "Error", 0)
        error("File does not exist: " .. path, 3)
        return false
    end
    if not tcutils.USE_XPCALL then
        return importTmb(path)
    else
        return select(2, xpcall(importTmb, onError, path))
    end
end

function tcutils.diffCalc(takes)
    if type(takes) ~= "table" then
        takes = {takes}
    end
    enforceArgs(
        makeTypedArg(takes, "table")
    )
    for _, take in ipairs(takes) do
        enforceArgs(
            makeTypedArg(take, "userdata", false, "MediaItem_Take*")
        )
    end

    if not tcutils.USE_XPCALL then
        return diffCalc(takes)
    else
        return select(2, xpcall(diffCalc, onError, takes))
    end
end

-- Emulates slides in midi takes.
function tcutils.emulateSlidesInMidiTakes(takes, pitchbend_range, mode)
    if type(takes) ~= "table" then
        takes = {takes}
    end
    enforceArgs(
        makeTypedArg(takes, "table"),
        makeTypedArg(pitchbend_range, "number", true),
        makeTypedArg(pitchbend_range, "number", true)
    )
    for _, take in ipairs(takes) do
        enforceArgs(
            makeTypedArg(take, "userdata", false, "MediaItem_Take*")
        )
    end

    if not tcutils.USE_XPCALL then
        return emulateSlidesInMidiTakes(takes, pitchbend_range, mode)
    else
        return select(2, xpcall(emulateSlidesInMidiTakes, onError, takes, pitchbend_range, mode))
    end
end

-- set an optional error callback for xpcall(), otherwise a traceback will be posted to the REAPER console window by default.
function tcutils.setOnError(fn)
    --- @diagnostic disable-next-line: name-style-check
    onError = fn
end

tcutils.MidiNote = MidiNote
tcutils.MidiCC = MidiCC
tcutils.MidiText = MidiText
tcutils.TmbNote = TmbNote
tcutils.ImprovZone = ImprovZone
tcutils.Lyric = Lyric
tcutils.BgEvent = BgEvent
return tcutils
