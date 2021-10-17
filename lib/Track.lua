local Cycle = include 'ekombi/lib/Cycle'
local Beat = include 'ekombi/lib/Beat'
local SubBeat = include 'ekombi/lib/SubBeat'
local g = grid.connect()

local MAX = 15
local HIGH = 12
local MED = 8
local LOW = 4

local Track = {
  num = 1, 
  beat = nil,
  beats = {},
  clk = nil,
  drawable_on_grid = true,
  drawable_on_screen = true,
  editing = nil,
  editing_subs = nil
}

local function make(track)
  clock.sync(1)

  while true do
    local n = track.beat.speed
    local d = #track.beat.subs

    if track.beat.on and track.beat.sub_beat.on then
      trig(track)
    end

    if track.beat.sub_beat.num == d then
      clock.sync(1)
    else
      clock.sleep(clock.get_beat_sec() * (n/d))
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

local norns_screen = function(str, x, y, b)
  screen.font_face(2)
  screen.level(0)
  screen.rect(8 + (x - 1) * 7, y * 6 + 5, 3, -6) -- clear out area behind text
  screen.fill()
  screen.level(b)
  screen.move(8 + (x - 1) * 7, y * 6 + 5)
  screen.text(str)
  screen_dirty = true
  screen.font_face(1)
end

function Track:draw_screen()
  if self.drawable_on_screen == false then return end

  local s_row = (self.num * 2) - 1
  local b_row = s_row + 1
  local brightness = 0

  for x=1, self.max_beats do -- max beats should be in track
    norns_screen("_", x, b_row, LOW)
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
        brightness = LOW
        else
        brightness = LOW/2
      end
    end

    norns_screen(string.format("%X", #beat.subs), beat.num, b_row, brightness)
  end
end

function Track:draw_grid()
  local s_row = (self.num * 2) - 1
  local b_row = s_row + 1
  local brightness = 0
  
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