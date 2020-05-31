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
      _start_pos = 0,
      _end_pos = 1,
      _loop = 1,
      _loop_point = 0,
      _speed = 1.0,
      _vol = -10.0,
      _vol_env_atk = 0.001,
      _pan = 0.0,
      _filter_cutoff = 20000,
      _filter_res = 0,
      _filter_env_atk = 0.001,
      _filter_env_rel = 0,
      _filter_env_mod = 0.0,
      _dist = 0
    }
    return o
end

function SubBeat:toggle()
    self.on = not self.on
end

return SubBeat