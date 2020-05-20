local SubBeat = {class_name = "SubBeat", on = true, params = {}}
function SubBeat:new()
    local o = {}
    self.__index = self
    setmetatable(o, self)
    o.class_name = "SubBeat"
    o.on = true
    o.params = {}
    return o
end

function SubBeat:toggle()
    self.on = not self.on
end

return SubBeat