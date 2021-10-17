local SubBeat = {
  class_name = "SubBeat",
  editing = false,
  on = true,
  params = {}
}

function SubBeat:new(n)
    local o = {}
    self.__index = self
    setmetatable(o, self)
    o.class_name = "SubBeat"
    o.editing = false
    o.on = true
    o.num = n
    o.params = {
      _midi_note = 64,
    }
    return o
end

function SubBeat:toggle()
    self.on = not self.on
end

function SubBeat:__tostring()
  return self.on and "x" or "_"
end

function SubBeat:__print()
  print(tostring(self))
end

return SubBeat