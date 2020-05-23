local Cycle = include 'ekombi-v2/lib/Cycle'
local SubBeat = include 'ekombi-v2/lib/SubBeat'

local Beat = {class_name = "Beat", editing = false, on = true, speed = 1, subs = {}, sub_beat = nil}
function Beat:new(p, n)
    local o = {}
    self.__index = self
    setmetatable(o, self)
    o.parent = p
    o.class_name = "Beat"
    o.editing = false
    o.on = true
    o.num = n
    o.speed = 1
    o.subs = Cycle:new(o, SubBeat, 1)
    o.sub_beat = o.subs:next()
    return o
end

function Beat:toggle()
    self.on = not self.on
end

function Beat:get_track()
  return self.parent.parent
end

function Beat:track_num()
  return self.parent.parent.num
end

function Beat:x_pos()
  return self.num
end

function Beat:y_pos()
  return self:track_num() * 2
end

return Beat