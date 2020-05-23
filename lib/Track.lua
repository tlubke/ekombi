local Cycle = include 'ekombi-v2/lib/Cycle'
local Beat = include 'ekombi-v2/lib/Beat'
local SubBeat = include 'ekombi-v2/lib/SubBeat'
local g = grid.connect()

local Track = {num = 1, beat = nil, beats = {}, clk = nil }

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

function Track:new(p, num, default_beats)
  local o = {}
  self.__index = self
  setmetatable(o, self)
  o.parent = p
  o.num = num
  o.editing = nil
  o.editing_subs = nil
  o.beats = Cycle:new(o, Beat, default_beats)
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
    self.editing_subs = Cycle:new(self, SubBeat, x)
  end
end

function Track:draw()
    local s_row = (self.num * 2) - 1
    local b_row = s_row + 1

    ----------------
    -- special cases
    ----------------
    if self.editing then
      --------
      -- beats
      --------
      for x=1, self.beats.length do
        -- highlight beats if
        -- in group edit
        if self.beats[x].editing then
          g:led(x, b_row, 15)
        else
          if self.editing == "Beat" then
            -- don't show "current" beat
            -- when editing beats
            g:led(x, b_row, 8)
            if not self.beats[x].on then
              g:led(x, b_row, 4)
            end
          end
          if self.editing == "SubBeat" then
            -- show selected beat
            -- when editing subs
            if self.beats[x] == self.beat then
              g:led(x, b_row, 12)
              if not self.beats[x].on then
                g:led(x, b_row, 6)
              end
            else
              g:led(x, b_row, 8)
              if not self.beats[x].on then
                g:led(x, b_row, 4)
              end
            end
          end
        end
      end
      -- clear any
      -- invalid beats
      for x=(self.beats.length + 1), 16 do
        g:led(x, b_row, 0)
      end
      -------
      -- subs
      -------
      for x=1, self.beat.subs.length do
        g:led(x, s_row, 8)
        if not self.beat.subs[x].on then
          g:led(x, s_row, 6)
        end
        if self.beat.subs[x].editing then
          g:led(x, s_row, 15)
        end
      end
      for x=(self.beat.subs.length + 1), 16 do
        g:led(x, s_row, 0)
      end
      if self.editing == "Beat" and self.editing_subs == nil then
        for x=1, 16 do
          g:led(x, s_row, 0)
        end
      end
      g:refresh()
      return
    end
    
    -----------------------
    -- draw beats as normal
    -----------------------
    for x=1, self.beats.length do
      if self.beats[x] == self.beat then
        g:led(x, b_row, 12)
        if not self.beats[x].on then
          g:led(x, b_row, 6)
        end
      else
        g:led(x, b_row, 8)
        if not self.beats[x].on then
          g:led(x, b_row, 4)
        end
      end
      if self.beats[x].editing then
        g:led(x, b_row, 15)
      end
    end
    for x=(self.beats.length + 1), 16 do
      g:led(x, b_row, 0)
    end
    --------------------
    -- draw subdivisions
    --------------------
    for x=1, self.beat.subs.length do
      if self.beat.subs[x] == self.beat.sub_beat then
        g:led(x, s_row, 12)
        if not self.beat.subs[x].on then
          g:led(x, s_row, 6)
        end
      else
        g:led(x, s_row, 8)
        if not self.beat.subs[x].on then
          g:led(x, s_row, 6)
        end
      end
      if self.beat.subs[x].editing then
        g:led(x, b_row, 15)
      end
    end
    for x=(self.beat.subs.length + 1), 16 do
      g:led(x, s_row, 0)
    end
    g:refresh()
end

return Track