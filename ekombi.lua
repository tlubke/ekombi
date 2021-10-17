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

engine.name = 'TestSine'

local pp = include 'ekombi/lib/ParamsPage'
local saving = include 'ekombi/lib/Saving'
local g = grid.connect()

local Pattern = include 'ekombi/lib/Pattern'

local GRID_HEIGHT = g.rows
local GRID_WIDTH = g.cols
local MAX_TRACKS = g.rows/2 -- 2 rows per track required
local BEAT_PARAMS = params.new("Beats", "step-components")
local SUBBEAT_PARAMS = params.new("Subs", "step-components")
local BUF = {}
local BUF_TYPE = nil
local PNUM = 1
local N_PATTERNS = n_patterns()

local UP = 0
local DOWN = 1

local RUNNING = false
local SHIFT = false

local GRID_KEYS = {}
for x=1, GRID_WIDTH do
  GRID_KEYS[x] = {}
  for y=1, GRID_HEIGHT do
    GRID_KEYS[x][y] = {down = false, last_down = 0, last_up = 0}
  end
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
  metro.init(function(c) redraw(); end, 1/15, -1):start()

  if N_PATTERNS <= 0 then
    p = Pattern:new(MAX_TRACKS, GRID_WIDTH)
    save_pattern(p, 1)
    N_PATTERNS = 1
  else
    p = load_pattern(1)
  end

  params:add_separator("EKOMBI")

  params:add{
    type = "trigger",
    id = "save_pattern",
    name = "save pattern",
    action =
      function()
        save_pattern(p, PNUM)
      end
  }

  params:add{
    type = "trigger",
    id = "clear_pattern",
    name = "clear pattern",
    action =
      function()
        p:stop()
        p = Pattern:new(MAX_TRACKS, GRID_WIDTH)
        p:stop()
        RUNNING = false
      end
  }

  params:add{
    type = "trigger",
    id = "duplicate_pattern",
    name = "duplicate pattern",
    action =
      function()
        p:stop()
        duplicate_pattern(PNUM)
        N_PATTERNS = N_PATTERNS + 1
        PNUM = PNUM + 1
        p = load_pattern(PNUM)
        p:stop()
        RUNNING = false
      end
  }

  params:add{
    type = "trigger",
    id = "delete_pattern",
    name = "delete pattern",
    action =
      function()
        if N_PATTERNS > 1 then
          delete_pattern(PNUM)
          N_PATTERNS = N_PATTERNS - 1
          PNUM = util.clamp(PNUM+1, 1, N_PATTERNS)
          p = load_pattern(PNUM)
        end
      end
  }

  -- parameters
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
    crow.output[channel].action = "pulse(.01,5,1)"
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
      for _, sub_beat in pairs(BUF) do
        sub_beat.on = value
      end
    end
  }
  SUBBEAT_PARAMS:add{type = "number", id = "_midi_note", name = ": MIDI note",
    min = 0, max = 127, default = 64}

  local temp = params
  params = SUBBEAT_PARAMS
  for i=2, #SUBBEAT_PARAMS.params do
    -- action is sending parameter info to
    -- every sub-beat in BUF for step components
    SUBBEAT_PARAMS:set_action(i,
      function (value)
        local id = SUBBEAT_PARAMS:get_id(i)
        for _,  sub_beat in pairs(BUF) do
          sub_beat.params[id] = value
        end
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
      for _, beat in pairs(BUF) do
        beat.on = value
      end
    end
  }
  BEAT_PARAMS:add{type = "number", id = "_speed", name = "steps per beat",
    min = 1, max = 16, default = 1,
    action = function(value)
      for _, beat in pairs(BUF) do
        beat.speed = value
      end
    end
  }

  connect_midi()
end



-----------
-- controls
-----------
function grid_key_held(x,y)
  GRID_KEYS[x][y].down = true
  GRID_KEYS[x][y].last_down = util.time()
end

function grid_key_released(x,y)
  GRID_KEYS[x][y].down = false
  GRID_KEYS[x][y].last_up = util.time()
  return GRID_KEYS[x][y].last_up - GRID_KEYS[x][y].last_down
end

function shifted_key_down(track, cycle, x)
  if add_to_buf(cycle, x) then
    track.editing = cycle.type.class_name
  end

  if cycle.type.class_name == "Beat" then
    if BUF_TYPE == "Beat" then
      track.editing_subs = cycle[x].subs
      for _, beat in pairs(BUF) do
        if tab.contains(track.beats, beat) and (beat.subs == cycle[x].subs) then
          track.editing_subs = nil
          break
        end
      end
    elseif BUF_TYPE == "SubBeat" then
      track:select(cycle, x)
    end
  end

  if cycle.type.class_name == "SubBeat" then
    if BUF_TYPE == "Beat" and track.editing_subs then
      track.editing_subs[x]:toggle()
      for _, beat in pairs(BUF) do
        if tab.contains(track.beats, beat) then
          beat.subs[x].on = track.editing_subs[x].on
        end
      end
    elseif BUF_TYPE == "SubBeat" then
      -- step already added or removed
      -- in add_to_buf()
      -- nothing to do in this case.
    end
  end
end

function unshifted_key_down(track, cycle, x)
  track:select(cycle, x)
end

function shifted_key_up(track, cycle, x)
  if cycle.type.class_name == "Beat" then
    -- holding won't affect beats
    -- when editing groups of steps
    if BUF_TYPE == "Beat" then end
    if BUF_TYPE == "SubBeat" then end
  end
  if cycle.type.class_name == "SubBeat" then
    if BUF_TYPE == "Beat" then
      -- set sub-beats of all beats in step-component group
      -- if also in the same row
      for _, beat in pairs(BUF) do
        if tab.contains(track.beats, beat) then
          track:edit_subs(x)
          beat.subs:set_length(x)
        end
      end
    end
    if BUF_TYPE == "SubBeat" then
      -- nothing planned for this case yet
    end
  end
end

function unshifted_key_up(track, cycle, x)
  -- nothing in step-component group
  -- only set length of selected beat/sub-beat
  cycle:set_length(x)
end

function g.key(x, y, z)
  local t = track_from_key(x, y)
  local cycle = beats_or_subs(t, x, y)
  local args = {t, cycle, x}

  p:stop()
  RUNNING = false

  local key_up_action   = function() if (SHIFT == true) then shifted_key_up(table.unpack(args)) else unshifted_key_up(table.unpack(args)) end end
  local key_down_action = function() if (SHIFT == true) then shifted_key_down(table.unpack(args)) else unshifted_key_down(table.unpack(args)) end end

  local key_action = function()
    if (z == UP) then
      return (grid_key_released(x, y) > 0.5), key_up_action
    end
    if (z == DOWN) then
      grid_key_held(x, y)
      return cycle:selectable_at(x), key_down_action
    end
  end

  local ok, action = key_action()

  if ok then
    p:stop()
    action()
  end
end

function key(n,z)
  if pp.visible then
    pp.key(n,z)
    return
  end
  if z == DOWN then
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
  elseif z == UP then
    if n == 2 then
      SHIFT = false
    end
  end
end

function enc(n, d)
  if pp.visible then
    pp.enc(n, d)
    return
  end
  if n == 1 then
    local prev = PNUM
    PNUM = util.clamp(PNUM+d, 1, N_PATTERNS)
    if PNUM == prev then return end
    p:stop()
    p = load_pattern(PNUM)
    p:stop()
    RUNNING = false
  end
end



----------
-- display
----------

function draw_symbols()
  -- PLAY/PAUSE Symbol
  screen.level(15)
  if RUNNING then
    screen.move(123,57)
    screen.line_rel(6,3)
    screen.line_rel(-6,3)
    screen.fill()
  else
    screen.rect(123,57,2,6)
    screen.rect(126,57,2,6)
    screen.fill()
  end
end

function redraw()
  -- draw step component param page
  if pp.visible then
    pp.redraw()
  else
    screen.clear()

    screen.level(15)
    screen.font_face(1)
    screen.move(0,5)
    screen.text(string.format("%02d",PNUM)..'/'..N_PATTERNS)

    p:draw_screen()

    draw_symbols()

    screen.update()
  end

  p:draw_grid()
end

--------------------
-- data manipulation
--------------------
function track_from_key(x, y)
  local n = (y // 2) + (y % 2)
  return p.tracks[n]
end

function beats_or_subs(track, x, y)
  local m = y % 2
  if m == 1 then
    return track.beat.subs
  else
    return track.beats
  end
end

function add_to_buf(cycle, x)
  -- returns a boolean of whether or not
  -- beats_or_subs was added to BUF.
  -- BUF should contain only Beats
  -- OR only SubBeats.

  if BUF_TYPE == nil then
    BUF_TYPE = cycle.type.class_name
    cycle[x].editing = true
    table.insert(BUF, cycle[x])
    if BUF_TYPE == "Beat" then
      pp.set_params(BEAT_PARAMS)
    elseif BUF_TYPE == "SubBeat" then
      pp.set_params(SUBBEAT_PARAMS)
    end
    pp.open()
    return true
  elseif BUF_TYPE == cycle.type.class_name then
    local key = tab.key(BUF, cycle[x])
    if key then
      cycle[x].editing = false
      table.remove(BUF, key)
    else
      cycle[x].editing = true
      table.insert(BUF, cycle[x])
    end
    return true
  end
  return false
end

pp.opened = function()
  -- do nothing.
end

pp.closed = function()
  SHIFT = false
  for _, step in pairs(BUF) do
    step.editing = false
  end
  for _, track in pairs(p.tracks) do
    track.editing = nil
    track.editing_subs = nil
  end
  BUF = {}
  BUF_TYPE = nil
end



----------------
-- sound control
----------------
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

function trig(track)
  -- set step params
  for id, value in pairs(track.beat.sub_beat.params) do
    params:set(track.num..id, value)
  end

  -- last midi notes off
  all_notes_off(track.num)

  -- crow trig
  crow.output[track.num].execute()

  -- midi trig
  midi_out_device[track.num]:note_on(midi_out_note[track.num], 96, midi_out_channel[track.num])
  table.insert(midi_notes_on[track.num], {midi_out_note[track.num], 96, midi_out_channel[track.num]})
end
