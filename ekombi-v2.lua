-- key 2: Shift
--
-- key 3: play/pause
-- 
-- hold a key to change the
--   length of the beats/subs
--
-- press a key on an even row
--   to select a beat for editing
--
-- press a key on an odd row
--   to toggle a sub on/off
--
-- hold shift and press a key
--   to add to edit group.
--
-- step-components via
--   edit group.

engine.name = 'Ack'

local ack = include 'ack/lib/ack'
 pp = include 'ekombi-v2/lib/ParamsPage'
local g = grid.connect()

local Pattern = include 'ekombi-v2/lib/Pattern'

local GRID_HEIGHT = g.rows
local GRID_WIDTH = g.cols
local MAX_TRACKS = g.rows/2 -- 2 rows per track required
local BEAT_PARAMS = params.new("Beats", "step-components")
local SUBBEAT_PARAMS = params.new("Subs", "step-components")
local BUF = {}
local BUF_TYPE = nil
local BUF_SUB_PATTERN = false

local RUNNING = true
local SHIFT = false

local GRID_KEYS = {}
for x=1, GRID_WIDTH do
  GRID_KEYS[x] = {}
  for y=1, GRID_HEIGHT do 
    GRID_KEYS[x][y] = {down = false, last_down = 0, last_up = 0}
  end
end

function grid_key_held(x,y)
  GRID_KEYS[x][y].down = true
  GRID_KEYS[x][y].last_down = util.time()
end

function grid_key_released(x,y)
  GRID_KEYS[x][y].down = false
  GRID_KEYS[x][y].last_up = util.time()
  return GRID_KEYS[x][y].last_up - GRID_KEYS[x][y].last_down
end

local midi_out_device = {}
local midi_out_channel = {}
local midi_out_note = {}
local midi_notes_on = {}
for i=1, MAX_TRACKS do
  midi_out_device[i] = 1
  midi_out_channel[i] = 1
  midi_out_note[i] = 64
  midi_notes_on[i] = {}
end

----------------
-- initilization
----------------
function init()
  p = Pattern:new(4, 4)
  
  params:add_separator("EKOMBI")

  -- parameters
  params:add_group("ack", 22*MAX_TRACKS)
  for channel=1,MAX_TRACKS do
    params:add_separator(channel)
    params:add{
      type = "option",
      id = channel.. "_random",
      name = channel..": random sample",
      options = {"off", "on"}
    }
    ack.add_channel_params(channel)
  end
  params:add_group("midi",4*MAX_TRACKS)
  for channel=1,MAX_TRACKS do
    params:add_separator(channel)
    params:add{
      type = "number",
      id = channel.. "_midi_out_device",
      name = channel .. ": MIDI device",
      min = 1, max = 4, default = 1,
      action = function(value) 
        midi_out_device[channel] = value
        connect_midi() 
        end
    }
    params:add{type = "number",
      id = channel.. "_midi_out_channel",
      name = channel ..": MIDI channel",
      min = 1, max = 16, default = 1,
      action = function(value)
        midi_out_channel[channel] = value 
        end
    }
    params:add{type = "number",
      id = channel.. "_midi_note",
      name = channel .. ": MIDI note",
      min = 0, max = 127, default = 64,
      action = function(value)
        midi_out_note[channel] = value
        end
    }
  end
  for channel=1,MAX_TRACKS do
    crow.output[channel].action = "{to(10,0.001),to(0,0.001)}"
  end

  -- sub-beat parameters for step components
  SUBBEAT_PARAMS:add{
    type = "option",
    id = "_on",
    name = "note on",
    options = {"off", "on"},
    default = 2,
    action = function(value)
      if value == 1 then 
        value = false 
      else 
        value = true 
      end
      for key,v in pairs(BUF) do
        BUF[key].on = value
      end
    end
  }
  SUBBEAT_PARAMS:add{type = "number", id = "_midi_note", name = ": MIDI note",
    min = 0, max = 127, default = 64}
  SUBBEAT_PARAMS:add{type = "option", id = "_random", name = ": random sample",
    options = {"off", "on"}}
  -- ack adds to global params, switch temporarily
  local temp = params
  params = SUBBEAT_PARAMS
  ack.add_start_pos_param('')
  ack.add_end_pos_param('')
  ack.add_loop_param('')
  ack.add_loop_point_param('')
  ack.add_speed_param('')
  ack.add_vol_param('')
  ack.add_vol_env_atk_param('')
  ack.add_vol_env_rel_param('')
  ack.add_pan_param('')
  ack.add_filter_cutoff_param('')
  ack.add_filter_res_param('')
  ack.add_filter_env_atk_param('')
  ack.add_filter_env_rel_param('')
  ack.add_filter_env_mod_param('')
  ack.add_dist_param('')
  for i=1, #SUBBEAT_PARAMS.params do
    -- action is sending parameter info to 
    -- every sub-beat in BUF for step components
    SUBBEAT_PARAMS:set_action(i, 
      function (value) 
        local id = SUBBEAT_PARAMS:get_id(i)
        local func = function(t) t.params[id] = value end
        tab.apply(BUF, func)
      end
    )
  end
  params = temp

  -- beat paramaters for step components
  BEAT_PARAMS:add{type = "option", id = "_on", name = "note on",
    options = {"off", "on"},
    default = 2,
    action = function(value)
      if value == 1 then 
        value = false 
      else 
        value = true 
      end
      for key,v in pairs(BUF) do
        BUF[key].on = value
      end
    end
  }
  BEAT_PARAMS:add{type = "number", id = "_speed", name = "steps per beat",
    min = 1, max = 16, default = 1,
    action = function(value)
      for key,v in pairs(BUF) do
        BUF[key].speed = value
      end
    end
  }

  params:read(norns.state.data.."ekombi-v2-01.pset")

  connect_midi()
end

function tab.apply(tab, func)
  local i, v = next(tab, nil)
  while i do
    func(v)
    i, v = next(tab, i)
  end
end

function connect_midi()
  for channel=1, MAX_TRACKS do
    midi_out_device[channel] = midi.connect(params:get(channel.. "_midi_out_device"))
  end
end

function all_notes_off(channel)
  for i = 1, tab.count(midi_notes_on[channel]) do
    midi_out_device[channel]:note_off(midi_notes_on[i])
  end
  midi_notes_on[channel] = {}
end

function g.key(x, y, z)
  local track = track_from_key(x, y)
  local b_or_s = beats_or_subs(track, x, y)
  local selectable = b_or_s:selectable_at(x)
  if z == 1 then
    grid_key_held(x,y)
    if selectable then
      p:stop()
      if SHIFT then 
        if BUF_SUB_PATTERN then
          -- toggle sub-beat of all beats in step-component group
          -- if in the same row and lengths were changed already.
          for k, v in pairs(BUF) do
            if tab.contains(track.beats, v) then
              v.subs[x]:toggle()
            end
          end
        else
          add_to_buf(b_or_s, x)
          pp.open()
        end
      else
        track:select(b_or_s, x)
      end
      track:draw()
    end
  elseif z == 0 then
    local hold_time = grid_key_released(x,y)
    if hold_time > 0.5 then
      p:stop()
      if SHIFT and BUF_TYPE == "Beat" then
        -- set sub-beats of all beats in step-component group
        -- if also in the same row
        for k, v in pairs(BUF) do
          if tab.contains(track.beats, v) then
            v.subs:set_length(x)
          end
        end
        BUF_SUB_PATTERN = true
      else
        -- nothing in step-component group
        -- only set length of selected beat/sub-beat
        b_or_s:set_length(x)
      end
      track:draw()
    end
  end
  redraw()
  g_redraw()
end

function beats_or_subs(track, x, y)
  local m = y % 2
  if m == 1 then
    return track.beat.subs
  else 
    return track.beats
  end
end

function track_from_key(x, y)
  local n = (y // 2) + (y % 2)
  return p.tracks[n]
end

function key(n,z)
  if pp.visible then
    pp.key(n,z)
    redraw()
    return
  end
  
  if z == 1 then
    if n == 3 then
      if RUNNING then
        p:stop()
        RUNNING = false
      else
        p:start()
        RUNNING = true
      end
    elseif n==2 then
      SHIFT = true
    end
  elseif z == 0 then
    if n == 2 then
      SHIFT = false
    end
  end
end

function enc(n, d)
  if pp.visible then
    pp.enc(n, d)
    redraw()
    return
  end
end

function g_redraw()
  for x=1, g.cols do
    for y=1, g.rows do
      local track = track_from_key(x,y)
      local b_or_s = beats_or_subs(track, x, y)
      if tab.contains(BUF, b_or_s[x]) then 
        g:led(x, y, 15) 
      end
    end
  end
  g:refresh()
end

function redraw()
  -- draw step component param page
  if pp.visible then 
    pp.redraw() 
    return
  end
  screen.clear()
  screen.update()
end

function load_random(track)
  local files
  local filepath = params:get(track.."_sample")
  local filename = params:string(track.."_sample")
  local dir = string.gsub(filepath, escape(filename), "")
  if filename ~= "-" then
    files = util.scandir(dir)
    engine.loadSample(track-1, dir..files[math.random(1, #files)])
  end
end

function escape (s)
  s = string.gsub(s, "[%p%c]", function (c)
    return string.format("%%%s", c) end)
  return s
end

function pp.opened()
  redraw()
end

function pp.closed()
  SHIFT = false
  BUF = {}
  BUF_TYPE = nil
  BUF_SUB_PATTERN = false
  p:redraw()
  redraw()
end

function add_to_buf(beats_or_subs, x)
  -- assure that BUF contains either
  -- only Beats OR only SubBeats
  if BUF_TYPE == nil then
    BUF_TYPE = beats_or_subs.type.class_name
    table.insert(BUF, beats_or_subs[x])
    if BUF_TYPE == "Beat" then
      pp.set_params(BEAT_PARAMS)
    elseif BUF_TYPE == "SubBeat" then
      pp.set_params(SUBBEAT_PARAMS)
    end
    return
  elseif BUF_TYPE == beats_or_subs.type.class_name then
    local key = tab.key(BUF, beats_or_subs[x])
    if key then
      table.remove(BUF, key)
      print('r')
    else
      table.insert(BUF, beats_or_subs[x])
      print('i')
    end
  end
end

function trig(track)
  -- set step params
  for k, v in pairs(track.beat.sub_beat.params) do
    params:set(track.num..k, v)
  end

  -- last midi notes off
  all_notes_off(track.num)

  -- ack trig
  engine.trig(track.num-1)

  -- crow trig
  crow.output[track.num].execute()

  -- midi trig
  midi_out_device[track.num]:note_on(midi_out_note[track.num], 96, midi_out_channel[track.num])
  table.insert(midi_notes_on[track.num], {midi_out_note[track.num], 96, midi_out_channel[track.num]})

  -- load random sample for next trig
  -- 1 == "off", 2 == "on"
  if params:get(track.num.."_random") == 2 then
    load_random(track.num)
  end
end

-- if beat buf
-- and all subs in each row are the same length
-- should be toggleable

-- if beat added to beat buf, and beat lengths in row are different
-- sub-beat row should be undrawn.