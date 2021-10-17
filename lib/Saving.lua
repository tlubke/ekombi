local Pattern = include 'ekombi/lib/Pattern'
local Track = include 'ekombi/lib/Track'
local Cycle = include 'ekombi/lib/Cycle'
local Beat = include 'ekombi/lib/Beat'
local SubBeat = include 'ekombi/lib/SubBeat'

local Saving = {}

local pdir = norns.state.data.."patterns/"

local function set_meta_tables(pattern)
  Pattern.__index = Pattern
  Track.__index = Track
  Cycle.__index = Cycle
  Beat.__index = Beat
  SubBeat.__index = SubBeat
  
  setmetatable(pattern, Pattern)
  for _, track in pairs(pattern.tracks) do
    setmetatable(track, Track)
    track.max_beats = pattern.max_beats
    setmetatable(track.beats, Cycle)
    setmetatable(Cycle, track.beats)
    track.beats.type = Beat
    for _, beat in pairs(track.beats:get()) do
      setmetatable(beat, Beat)
      setmetatable(beat.subs, Cycle)
      beat.subs.type = SubBeat
      for _, sub_beat in pairs(beat.subs:get()) do
        setmetatable(sub_beat, SubBeat)
      end
    end
  end
end

local function pattern_files()
  local t = util.scandir(pdir)
  for i, str in pairs(t) do
    local substr = string.gsub(str, '.data', '')
    t[i] = tonumber(substr)
  end
  table.sort(t)
  for i, num in pairs(t) do
    t[i] = num..'.data'
  end
  return t
end

function sl_at(num)
  if num <= 0 then return end
  if num == 1 then num = 2 end
  local files = pattern_files()
  for i=num, #files do
    os.rename(pdir..files[i], pdir..(i-1)..'.data')
  end
  return files
end

local function sr_at(num)
  local files = pattern_files()
  for i=num, #files do
    os.rename(pdir..files[i], pdir..(i+1)..'.data')
  end
  return files
end

local function fill_gaps()
  local files = pattern_files()
  for i, file in pairs(files) do
    local substr = string.gsub(file, '.data', '')
    if tostring(i) ~= substr then
      os.rename(pdir..file, pdir..i..'.data')
    end
  end
  return files
end

local function exists(file)
   local ok, err, code = os.rename(file, file)
   if not ok then
      if code == 13 then
         -- Permission denied, but it exists
         return true
      end
   end
   return ok, err
end

local function isdir(path)
   return exists(path.."/")
end

function save_pattern(pattern, pattern_num)
  pattern:stop()
  if not isdir(pdir) then
    os.execute("mkdir "..pdir)
  end
  local file_path = pdir..pattern_num..".data"
  local err = tab.save(pattern, file_path)
  return err
end

function load_pattern(pattern_num)
  local file_path = pdir..pattern_num..".data"
  local pattern = tab.load(file_path)
  if pattern then
    set_meta_tables(pattern)
    return pattern
  else
    return nil
  end
end

function delete_pattern(pattern_num)
  sl_at(pattern_num)
end

function duplicate_pattern(pattern_num)
  local pattern = load_pattern(pattern_num)
  sr_at(pattern_num)
  save_pattern(pattern, pattern_num)
end

function n_patterns()
  return #fill_gaps()
end

function delete_all()
  os.execute("rm "..pdir.."*.data")
end

return Saving