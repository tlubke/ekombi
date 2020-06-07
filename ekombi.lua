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

local RUNNING = true
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
  if N_PATTERNS <= 0 then
    p = Pattern:new(MAX_TRACKS, GRID_WIDTH)
    save_pattern(p, 1)
    N_PATTERNS = 1
  else
    p = load_pattern(1)
  end
  p:start()

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
        p:redraw()
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
        p:redraw()
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
          p:redraw()
        end
      end
  }

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
      for _, sub_beat in pairs(BUF) do
        sub_beat.on = value
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

  params:read(norns.state.data.."ekombi-v2-01.pset")

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

function g.key(x, y, z)
  local track = track_from_key(x, y)
  local b_or_s = beats_or_subs(track, x, y)
  local selectable = b_or_s:selectable_at(x)
  local t = b_or_s.type.class_name
  
  if z == 1 then
    grid_key_held(x,y)
    if selectable then
      p:stop()
      if SHIFT == true then
        local added = add_to_buf(b_or_s, x)
        if added then track.editing = t end
        if t == "Beat" then
          if BUF_TYPE == "Beat"then
            track.editing_subs = b_or_s[x].subs
            for _, beat in pairs(BUF) do
              if tab.contains(track.beats, beat) then
                if beat.subs:compare(b_or_s[x].subs) == false then
                  track.editing_subs = nil
                  break
                end
              end
            end
          end
          if BUF_TYPE == "SubBeat" then
            track:select(b_or_s, x)
          end
        end
        if t == "SubBeat" then
          if BUF_TYPE == "Beat" and track.editing_subs then
            track.editing_subs[x]:toggle()
            for _, beat in pairs(BUF) do
              if tab.contains(track.beats, beat) then
                beat.subs[x].on = track.editing_subs[x].on
              end
            end
          end
          if BUF_TYPE == "SubBeat" then
            -- step already added or removed 
            -- in add_to_buf()
            -- nothing to do in this case.
          end
        end
      end
      if SHIFT == false then
        track:select(b_or_s, x)
      end
      track:draw()
    end
  elseif z == 0 then
    local hold_time = grid_key_released(x,y)
    if hold_time > 0.5 then
      p:stop()
      if SHIFT == true then
        if t == "Beat" then
          -- holding won't affect beats
          -- when editing groups of steps
          if BUF_TYPE == "Beat" then end
          if BUF_TYPE == "SubBeat" then end
        end
        if t == "SubBeat" then
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
      if SHIFT == false then
        -- nothing in step-component group
        -- only set length of selected beat/sub-beat
        b_or_s:set_length(x)
      end
      track:draw()
    end
  end
  redraw()
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
  redraw()
end

function enc(n, d)
  if pp.visible then
    pp.enc(n, d)
    redraw()
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
  redraw()
end



----------
-- display
----------
function redraw()
  -- draw step component param page
  if pp.visible then 
    pp.redraw() 
    return
  end
  screen.clear()
  screen.move(0,5)
  screen.text(string.format("%02d",PNUM)..'/'..N_PATTERNS)
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
  screen.update()
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

function add_to_buf(beats_or_subs, x)
  -- returns a boolean of whether or not
  -- beats_or_subs was added to BUF.
  -- BUF should contain only Beats 
  -- OR only SubBeats
  
  if BUF_TYPE == nil then
    BUF_TYPE = beats_or_subs.type.class_name
    beats_or_subs[x].editing = true
    table.insert(BUF, beats_or_subs[x])
    if BUF_TYPE == "Beat" then
      pp.set_params(BEAT_PARAMS)
    elseif BUF_TYPE == "SubBeat" then
      pp.set_params(SUBBEAT_PARAMS)
    end
    pp.open()
    return true
  elseif BUF_TYPE == beats_or_subs.type.class_name then
    local key = tab.key(BUF, beats_or_subs[x])
    if key then
      beats_or_subs[x].editing = false
      table.remove(BUF, key)
    else
      beats_or_subs[x].editing = true
      table.insert(BUF, beats_or_subs[x])
    end
    return true
  end
  return false
end

pp.opened = function()
  redraw()
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
  p:redraw()
  redraw()
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

function load_random(track)
  local function escape (s)
    s = string.gsub(s, "[%p%c]", function (c)
      return string.format("%%%s", c) end)
    return s
  end
  local files
  local filepath = params:get(track.."_sample")
  local filename = params:string(track.."_sample")
  local dir = string.gsub(filepath, escape(filename), "")
  if filename ~= "-" then
    files = util.scandir(dir)
    engine.loadSample(track-1, dir..files[math.random(1, #files)])
  end
end

function trig(track)
  -- set step params
  for id, value in pairs(track.beat.sub_beat.params) do
    params:set(track.num..id, value)
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