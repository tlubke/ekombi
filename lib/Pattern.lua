local Track = include 'ekombi/lib/Track'

local Pattern = {
  tracks = {},
  max_beats = 0
}

function Pattern:new(n_tracks, max_beats)
  local o = {}
  self.__index = self
  setmetatable(o, self)
  o.tracks = {}
  o.n_tracks = n_tracks
  o.max_beats = max_beats
  for i=1, n_tracks do
    o.tracks[i] = Track:new(i, 4)
    -- pass down
    getmetatable(o.tracks[i]).max_beats = max_beats
  end
  return o
end

function Pattern:block_drawing(interfaces)
  local map = {}
  map["screen"] = function() for _, t in pairs(self.tracks) do t.drawable_on_screen = false end end
  map[  "grid"] = function() for _, t in pairs(self.tracks) do t.drawable_on_grid   = false end end
  for _, interface in pairs(interfaces) do
    if map[interface] ~= nil then map[interface]() end
  end
end

function Pattern:allow_drawing(interfaces)
  local map = {}
  map["screen"] = function() for _, t in pairs(self.tracks) do t.drawable_on_screen = true end end
  map[  "grid"] = function() for _, t in pairs(self.tracks) do t.drawable_on_grid   = true end end
  for _, interface in pairs(interfaces) do
    if map[interface] ~= nil then map[interface]() end
  end
end

function Pattern:draw_screen()
  for i=1, self.n_tracks do
    self.tracks[i]:draw_screen()
  end
end

function Pattern:draw_grid()
  for i=1, self.n_tracks do
    self.tracks[i]:draw_grid()
  end
end

function Pattern:start()
  for i=1, self.n_tracks do
    self.tracks[i]:reset()
    self.tracks[i]:start_clock()
  end
end

function Pattern:stop()
  for i=1, self.n_tracks do
    self.tracks[i]:stop_clock()
  end
end

function Pattern:__tostring()
  local s = ""
  for i=1, self.n_tracks do
    s = s .. i .. ": " .. tostring(self.tracks[i].beats) .. '\n'
  end
  return s
end

return Pattern