local SubBeat = {class_name = "SubBeat", editing = false, on = true, params = {}}
function SubBeat:new(p, n)
    local o = {}
    self.__index = self
    setmetatable(o, self)
    o.parent = p
    o.class_name = "SubBeat"
    o.editing = false
    o.on = true
    o.num = n
    o.params = {}
    return o
end

function SubBeat:toggle()
    self.on = not self.on
end

function SubBeat:track_num()
  return self.parent.parent:track_num()
end

function SubBeat:x_pos()
  return self.num
end

function SubBeat:y_pos()
  return (self:track_num() * 2) - 1
end

return SubBeat