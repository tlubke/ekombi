engine.name = 'Ack'

local ack = require 'ack/lib/ack'

local g = grid.connect()

local GRID_HEIGHT = g.rows
local GRID_WIDTH = g.cols
local MAX_TRACKS = g.rows/2 -- 2 rows per track required
local MAX_BEATS = g.cols -- last column is meta-button
local GRID_KEYS = {}
for x=1, GRID_WIDTH do
  GRID_KEYS[x] = {}
  for y=1, GRID_HEIGHT do 
    GRID_KEYS[x][y] = {down = false, last_down = 0, last_up = 0}
  end
end

local RUNNING = true
-- beat and subbeat are both cycle type tables
-- build a cycle class that puts itself on the end of the table
-- through iterations, keeps track of index of item.
-- e.g. {a, b, c} => a {b, c, a} => b {c, a, b} => c ...
-- calls a function anytime a cycle is complete
-- 
-- beat should notify pattern when a cycle is complete
-- if it is an 'independent track' in order to know
-- when to switch to the next pattern.
-- 
-- or, Cycle has a 'complete' boolean attribute, that can be reset.

-- controls behavior
--
-- 1 | 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, meta
--   | 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16
-- 2 | 1, 2. 3, ... , meta
--   | ...
--
-- holding 'meta' brings up a mini-param menu for track options,
-- e.g. mute, steps per beat, "copy-track"/"paste-track" (could copy track pattern to others),
-- dependent/independent track.
-- 
-- a quick press to a 'beat' key will select that beat if it is valid, and change the sub-beat
-- row to display the sub-beats of selected. Refreshes a timer for 5 or so seconds every time an 
-- action on the given beat takes place, when that timer is reached ekombi goes back to displaying
-- the current beat of the pattern if it is playing.
--
-- a long press to a 'beat' key will change the amount of beats in the track, either extended it
-- or truncating it.
--
-- key 2 acts as a 'shift key' for selecting beats/sub-beats to edit parameters.
-- can only select more of the first type that was selected in one go.
-- i.e. if the first key 'selected' for parameter changing is a sub-beat,
-- the user can not then also select a 'beat' as they have different parameters.

function has_one_type(tab)
  local i, v = next(tab, nil)
  local A = type(v)
  repeat
    if type(v) ~= A then
      print("table "..self.." contains more than one type:", type(v), A)
      return false
    end
    i, v = next(tab, i)
  until(i == nil)
  return true
end

local Cycle = {length = 0, index = 0, cycled = false}
function Cycle:new(t, length)
  local o = {}
  self.__index = self
  setmetatable(o, self)
  o.type = t
  o.length = length
  o.index = 0
  o.cycled = false
  for i=1, o.length do
    o[i] = o.type:new()
  end
  return o
end

function Cycle:from_table(t)
  if has_one_type(t) then
    local o = t
    self.__index = self
    setmetatable(o, self)
    o.length = #o
    o.index = 0
    o.cycled = false
    o.type = type(o[1])
    return o
  end
end

function Cycle:reset()
  self.index = 0
  self.cycled = false
end

function Cycle:next()
  self.index = self.index + 1
  if self.index > self.length then 
    self.cycled = true
    self.index = 1
  else
    self.cycled = false
  end
  return self[self.index]
end

function Cycle:set_length(l)
  if l <= 0 then
    print("cannot change length of a cycle to 0 or a negative number")
    return
  end
  while self.length < l do
    self.length = self.length + 1
    table.insert(self, self.length, self.type:new())
  end
  while self.length > l do
    self.length = self.length - 1
    table.remove(self, self.length)
  end
end

function Cycle:selectable_at(x)
  return self.length >= x
end

local SubBeat = {on = true, StepParams = {}}
function SubBeat:new()
  local o = {}
  self.__index = self
  setmetatable(o, self)
  o.on = true
  o.StepParams = {}
  return o
end

function SubBeat:toggle()
  self.on = not self.on
end

local Beat = {on = true, subs = {}}
function Beat:new()
  local o = {}
  self.__index = self
  setmetatable(o, self)
  o.on = true
  o.subs = Cycle:new(SubBeat, 1)
  o.sub_beat = o.subs[1]
  return o
end

function Beat:toggle()
  self.on = not self.on
end

function make(track)
  while true do
    clock.sync(track.speed/(#track.beat.subs))
    if track.beat.on and track.beat.sub_beat.on then
      engine.trig(track.num)
    end
    track:advance()
    track:draw()
  end
end

local Track = {num = 1, speed = 1, beat = nil, beats = {}, clk = nil}
function Track:new(num, default_beats)
  local o = {}
  self.__index = self
  setmetatable(o, self)
  o.num = num
  o.speed = 1
  o.beats = Cycle:new(Beat, default_beats)
  o.beat = o.beats[1]
  o.clk = clock.run(make, o)
  return o
end

function Track:advance()
  self.beat.sub_beat = self.beat.subs:next()
  if self.beat.subs.cycled then
    self.beat = self.beats:next()
  end
end

function Track:reset()
  self.beats:reset()
  self.beat = self.beats[1]
  self.beat.subs:reset()
  self.beat.sub_beat = self.beat.subs[1]
  self:draw()
end

function Track:update_clock()
  -- print("Track:updateClock()")
  clock.cancel(self.clk)
  self.clk = clock.run(make, self)
end

function Track:start_clock()
  if self.clk == nil then
    self.clk = clock.run(make, self)
  end
end

function Track:stop_clock()
  if self.clk then
    clock.cancel(self.clk)
    self.clk = nil
  end
end

function Track:select(beats_or_subs, x)
  if beats_or_subs.type == Beat then
    self.beat = beats_or_subs[x]
  elseif beats_or_subs.type == SubBeat then
    self.beat.subs[x]:toggle()
  end
end

function Track:toggle_beat(n)
  -- print("Track:toggleBeat()")
  self.beats[n].on = not self.beats[n].on
end

function Track:draw()
  local s_row = (self.num * 2) - 1 
  local b_row = s_row + 1
  -- draw beats
  for x=1, self.beats.length do
    if self.beats[x] == self.beat then
      g:led(x, b_row, 12)
    else
      g:led(x, b_row, 8)
    end
    if not self.beats[x].on then
      g:led(x, b_row, 4)
    end
  end
  for x=(self.beats.length + 1), 16 do
    g:led(x, b_row, 0)
  end
  -- draw subdivisions
  for x=1, self.beat.subs.length do
    if self.beat.subs[x] == self.beat.sub_beat then
      g:led(x, s_row, 12)
    else
      g:led(x, s_row, 8)
    end
    if not self.beat.subs[x].on then
      g:led(x, s_row, 4)
    end
  end
  for x=(self.beat.subs.length + 1), 16 do
    g:led(x, s_row, 0)
  end
  g:refresh()
end

local Pattern = {tracks = {}, max_width = 0}
function Pattern:new(n_tracks, max_beats)
  local o = {}
  self.__index = self
  setmetatable(o, self)
  o.tracks = {}
  o.max_width = max_beats
  for i=1, n_tracks do
    o.tracks[i] = Track:new(i, max_beats)
  end
  return o
end

function Pattern:start()
  for i=1, 4 do
    self.tracks[i]:reset()
    self.tracks[i]:start_clock()
  end
  RUNNING = true
end

function Pattern:stop()
  for i=1, 4 do
    self.tracks[i]:stop_clock()
  end
  RUNNING = false
end

----------------
-- initilization
----------------
function init()
  engine.loadSample(1, "/home/we/dust/audio/common/606/606-BD.wav")
  engine.loadSample(2, "/home/we/dust/audio/common/606/606-SD.wav")
  engine.loadSample(3, "/home/we/dust/audio/common/606/606-CH.wav")
  p = Pattern:new(4, 5)
  --t = Track:new(1, 4)
end

function g.key(x, y, z)
  local track = track_from_key(x, y)
  local beats_or_subs = beat_or_sub(track, x, y)
  if z == 1 then
    grid_key_held(x,y)
    if beats_or_subs:selectable_at(x) then
      p:stop()
      track:select(beats_or_subs, x)
      track:draw()
    end
  elseif z == 0 then
    local hold_time = grid_key_released(x,y)
    if hold_time > 1 then
      p:stop()
      beats_or_subs:set_length(x)
      track:draw()
    end
  end
end

function grid_key_held(x,y)
  GRID_KEYS[x][y].down = true
  GRID_KEYS[x][y].last_down = util.time()
end

function grid_key_released(x,y)
  GRID_KEYS[x][y].down = false
  GRID_KEYS[x][y].last_up = util.time()
  return GRID_KEYS[x][y].last_up - GRID_KEYS[x][y].last_down
end

function beat_or_sub(track, x, y)
  local m = y % 2
  if m == 1 then
    return track.beat.subs
  else 
    return track.beats
  end
end

function track_from_key(grid_x, grid_y)
  local n = (grid_y // 2) + (grid_y % 2)
  return p.tracks[n]
end

function key(n,z)
  if z == 1 then
    if n == 3 then
      if RUNNING then
        p:stop()
      else
        p:start()
      end
    end
  elseif z == 0 then
    
  end
end
