local Cycle = {length = 0, index = 0, cycled = false }

local function has_one_type(tab)
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

return Cycle