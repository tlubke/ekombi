local Cycle = include 'ekombi-v2/lib/Cycle'
local Beat = include 'ekombi-v2/lib/Beat'
local SubBeat = include 'ekombi-v2/lib/SubBeat'
local g = grid.connect()

local Track = {
  num = 1, 
  beat = nil,
  beats = {},
  clk = nil,
  editing = nil,
  editing_subs = nil
}

local function make(track)
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
      trig(track)
    end
    track:advance()
  end
end

function Track:new(num, default_beats)
  local o = {}
  self.__index = self
  setmetatable(o, self)
  o.num = num
  o.editing = nil
  o.editing_subs = nil
  o.beats = Cycle:new(Beat, default_beats)
  o.beat = o.beats:next()
  o.clk = clock.run(make, o)
  return o
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
    if beats_or_subs.type.class_name == "Beat" then
      self.beat = beats_or_subs[x]
    elseif beats_or_subs.type.class_name == "SubBeat" then
      self.beat.subs[x]:toggle()
    end
end

function Track:edit_subs(x)
  if self.editing_subs == nil then
    self.editing_subs = Cycle:new(SubBeat, x)
  end
end

function Track:draw()
  local s_row = (self.num * 2) - 1
  local b_row = s_row + 1
  local brightness = 0
  local MAX = 15
  local HIGH = 12
  local MED = 8
  local LOW = 4
  
  -- 0 out the track
  for x=1, self.max_beats do -- max beats should be in track
    g:led(x, b_row, brightness)
    g:led(x, s_row, brightness)
  end
  
  for _, beat in pairs(self.beats:get()) do
    if     beat == self.beat then
      if beat.on == true then
        brightness = HIGH
        else 
        brightness = HIGH/2 
      end
    elseif beat ~= self.beat then
      if beat.on == true then
        brightness = MED
        else 
        brightness = MED/2 
      end
    end
    g:led(beat.num, b_row, brightness)
  end
  
  for _, sub_beat in pairs(self.beat.subs:get()) do
    if     sub_beat == self.beat.sub_beat then
      if sub_beat.on then
        brightness = HIGH
        else 
        brightness = HIGH/2 
      end
    elseif sub_beat ~= self.beat.sub_beat then
      if sub_beat.on then
        brightness = MED
        else 
        brightness = MED/2 
      end
    end
    g:led(sub_beat.num, s_row, brightness)
  end
  
  if     self.editing == "Beat" then
    for _, beat in pairs(self.beats:get()) do
      if     beat.editing then
        brightness = MAX
      elseif beat.on then
        brightness = MED
        else 
        brightness = MED/2 
      end
      g:led(beat.num, b_row, brightness)
    end
    for _, sub_beat in pairs(self.beat.subs:get()) do
      if self.editing_subs == nil then
        brightness = 0
        g:led(sub_beat.num, s_row, brightness)
      end
    end
  elseif self.editing == "SubBeat" then
    for _, beat in pairs(self.beats:get()) do
    end
    for _, sub_beat in pairs(self.beat.subs:get()) do
      if     sub_beat.editing then
        brightness = MAX
      elseif sub_beat.on then
        brightness = MED
        else 
        brightness = MED/2 
      end
      g:led(sub_beat.num, s_row, brightness)
    end
  end
  g:refresh()
end

return Track