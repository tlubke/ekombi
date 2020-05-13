-- key 3: play/pause
-- 
-- hold a key to change the
--   length of the beats/subs
--
-- press a key on an even row
--   to select a beat for editing
--
-- press a key on an odd row
--   to toggle a sub on/off

engine.name = 'Ack'

local ack = require 'ack/lib/ack'

local g = grid.connect()

local GRID_HEIGHT = g.rows
local GRID_WIDTH = g.cols
local MAX_TRACKS = g.rows/2 -- 2 rows per track required
local MAX_BEATS = g.cols -- last column is meta-button

local RUNNING = true

local GRID_KEYS = {}
for x=1, GRID_WIDTH do
  GRID_KEYS[x] = {}
  for y=1, GRID_HEIGHT do 
    GRID_KEYS[x][y] = {down = false, last_down = 0, last_up = 0}
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

local midi_out_device = {}
local midi_out_channel = {}
local midi_out_note = {}
local midi_notes_on = {}
for i=1, MAX_TRACKS do
  midi_out_device[i] = 1
  midi_out_channel[i] = 1
  midi_out_note[i] = 64
  midi_notes_on[i] = {}
end

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

function Cycle:reset()
  self.index = 0
  self.cycled = false
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

local Beat = {on = true, speed = 1, subs = {}, sub_beat = nil}
function Beat:new()
  local o = {}
  self.__index = self
  setmetatable(o, self)
  o.on = true
  o.speed = 1
  o.subs = Cycle:new(SubBeat, 1)
  o.sub_beat = o.subs:next()
  return o
end

function Beat:toggle()
  self.on = not self.on
end

function make(track)
  local n = 1
  local d = 1
  while true do
    clock.sync(n/d)
    -- lazy clock sync updating
    -- for alligned sub-beats when
    -- current beat is advanced.
    n = track.beat.speed
    d = #track.beat.subs
    track:draw()
    if track.beat.on and track.beat.sub_beat.on then
      track:trig()
    end
    track:advance()
  end
end

local Track = {num = 1, beat = nil, beats = {}, clk = nil}
function Track:new(num, default_beats)
  local o = {}
  self.__index = self
  setmetatable(o, self)
  o.num = num
  o.beats = Cycle:new(Beat, default_beats)
  o.beat = o.beats:next()
  o.clk = clock.run(make, o)
  return o
end

function Track:trig()
  -- last midi notes off
  all_notes_off(self.num)
  
  -- ack trig
  engine.trig(self.num-1)
  
  -- crow trig
  crow.output[self.num].execute()
  
  -- midi trig
  midi_out_device[self.num]:note_on(midi_out_note[self.num], 96, midi_out_channel[self.num])
  table.insert(midi_notes_on[self.num], {midi_out_note[self.num], 96, midi_out_channel[self.num]})
  
  -- load random sample for next trig
  -- 1 == "off", 2 == "on"
  if params:get(self.num.."_random") == 2 then
    load_random(self.num)
  end
end

function Track:advance_sub()
  self.beat.sub_beat = self.beat.subs:next()
end

function Track:advance_beat()
  self.beat = self.beats:next()
end

function Track:advance()
  self:advance_sub()
  if self.beat.subs.cycled then
    self:advance_beat()
  end
end

function Track:reset()
  self.beats:reset()
  self.beat = self.beats:next()
  self.beat.subs:reset()
  self.beat.sub_beat = self.beat.subs:next()
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
    self.tracks[i]:draw()
  end
  RUNNING = true
end

function Pattern:stop()
  for i=1, 4 do
    self.tracks[i]:stop_clock()
    self.tracks[i]:draw()
  end
  RUNNING = false
end

----------------
-- initilization
----------------
function init()
  p = Pattern:new(4, 4)
  
  params:add_separator("EKOMBI")

  -- parameters
  params:add_group("ack", 22*MAX_TRACKS)
  for channel=1,MAX_TRACKS do
    params:add_separator(channel)
    params:add{type = "option", id = channel.. "_random", name = channel..": random sample",
      options = {"off", "on"}}
    ack.add_channel_params(channel)
  end

  params:add_group("midi",4*MAX_TRACKS)
  for channel=1,MAX_TRACKS do
    params:add_separator(channel)
    params:add{type = "number", id = channel.. "_midi_out_device", name = channel .. ": MIDI device",
      min = 1, max = 4, default = 1,
      action = function(value) midi_out_device[channel] = value connect_midi() end}
    params:add{type = "number", id = channel.. "_midi_out_channel", name = channel ..": MIDI channel",
      min = 1, max = 16, default = 1,
      action = function(value)
        -- all_notes_off()
        midi_out_channel[channel] = value end}
    params:add{type = "number", id = channel.. "_midi_note", name = channel .. ": MIDI note",
      min = 0, max = 127, default = 64,
      action = function(value)
        midi_out_note[channel] = value end}
  end

  for channel=1,MAX_TRACKS do
    crow.output[channel].action = "{to(10,0.001),to(0,0.001)}"
  end

  params:read("ekombi-v2.pset")

  connect_midi(MAX_TRACKS)
end

function connect_midi(n)
  for channel=1, n do
    midi_out_device[channel] = midi.connect(params:get(channel.. "_midi_out_device"))
  end
end

function all_notes_off(channel)
  for i = 1, tab.count(midi_notes_on[channel]) do
    midi_out_device[channel]:note_off(midi_notes_on[i])
  end
  midi_notes_on[channel] = {}
end

function g.key(x, y, z)
  local track = track_from_key(x, y)
  local b_or_s = beat_or_sub(track, x, y)
  if z == 1 then
    grid_key_held(x,y)
    if b_or_s:selectable_at(x) then
      p:stop()
      track:select(b_or_s, x)
      track:draw()
    end
  elseif z == 0 then
    local hold_time = grid_key_released(x,y)
    if hold_time > 1 then
      p:stop()
      b_or_s:set_length(x)
      track:draw()
    end
  end
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

function load_random(track)
  local files
  local filepath = params:get(track.."_sample")
  local filename = params:string(track.."_sample")
  local dir = string.gsub(filepath, escape(filename), "")
  if filename ~= "-" then
    files = util.scandir(dir)
    engine.loadSample(track-1, dir..files[math.random(1, #files)])
  end
end

function escape (s)
  s = string.gsub(s, "[%p%c]", function (c)
    return string.format("%%%s", c) end)
  return s
end
