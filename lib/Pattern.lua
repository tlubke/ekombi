local Track = include 'ekombi-v2/lib/Track'

local Pattern = {tracks = {}, max_width = 0}
function Pattern:new(n_tracks, max_beats)
    local o = {}
    self.__index = self
    setmetatable(o, self)
    o.tracks = {}
    o.n_tracks = n_tracks
    o.max_beats = max_beats
    for i=1, n_tracks do
        o.tracks[i] = Track:new(o, i, max_beats)
    end
    return o
end

function Pattern:redraw()
    for i=1, self.n_tracks do
        self.tracks[i]:draw()
    end
end

function Pattern:start()
    for i=1, self.n_tracks do
        self.tracks[i]:reset()
        self.tracks[i]:start_clock()
        self.tracks[i]:draw()
    end
end

function Pattern:stop()
    for i=1, self.n_tracks do
        self.tracks[i]:stop_clock()
        self.tracks[i]:draw()
    end
end

return Pattern