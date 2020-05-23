local SubBeat = {class_name = "SubBeat", editing = false, on = true, params = {}}
function SubBeat:new(n)
    local o = {}
    self.__index = self
    setmetatable(o, self)
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

return SubBeat