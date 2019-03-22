-- STEP
--
-- sample based step sequencer
-- controlled by grid
-- 
-- key2 = stop sequencer
-- key3 = play sequencer
--
-- enc1 = main out level
-- enc2 = tempo
-- enc3 = swing amount
-- 
-- grid = edit trigs
-- 

engine.name = 'Ack'

local Ack = require 'we/lib/ack'
local ControlSpec = require 'controlspec'

local PATTERN_FILE = "step.data"

local TRIG_LEVEL = 15
local PLAYPOS_LEVEL = 7
local CLEAR_LEVEL = 0

local screen_dirty = false

local arc = arc.connect()
local arc_connected = false
local arc_dirty = false

local grid = grid.connect()
local grid_connected = false
local grid_dirty = false

local tempo_spec = ControlSpec.new(20, 300, ControlSpec.WARP_LIN, 0, 120, "BPM")
local swing_amount_spec = ControlSpec.new(0, 100, ControlSpec.WARP_LIN, 0, 0, "%")

local NUM_PATTERNS = 99
local MAXWIDTH = 16
local HEIGHT = 8
local gridwidth = MAXWIDTH
local playing = false
local queued_playpos
local playpos = -1
local sequencer_metro

local ppqn = 24 
local ticks
local ticks_to_next
local odd_ppqn
local even_ppqn

local trigs = {}

local function cutting_is_enabled()
  return params:get("last_row_cuts") == 2
end

local function set_trig(patternno, x, y, value)
  trigs[patternno*MAXWIDTH*HEIGHT + y*MAXWIDTH + x] = value
end

local function trig_is_set(patternno, x, y)
  return trigs[patternno*MAXWIDTH*HEIGHT + y*MAXWIDTH + x]
end

local function refresh_grid_button(x, y, refresh)
  if grid.device then
    if cutting_is_enabled() and y == 8 then
      if x-1 == playpos then
        grid:led(x, y, PLAYPOS_LEVEL)
      else
        grid:led(x, y, CLEAR_LEVEL)
      end
    else
      if trig_is_set(params:get("pattern"), x, y) then
        grid:led(x, y, TRIG_LEVEL)
      elseif x-1 == playpos then
        grid:led(x, y, PLAYPOS_LEVEL)
      else
        grid:led(x, y, CLEAR_LEVEL)
      end
    end
    if refresh then
      grid:refresh()
    end
  end
end

local function refresh_grid_column(x, refresh)
  if grid.device then
    for y=1,HEIGHT do
      refresh_grid_button(x, y, false)
    end
    if refresh then
      grid:refresh()
    end
  end
end

local function refresh_arc()
  if arc.device then
    arc:all(0)
    arc:led(1, util.round(params:get_raw("tempo")*64), 15)
    arc:led(2, util.round(params:get_raw("swing_amount")*64), 15)
    arc:refresh()
  end
end

local function refresh_grid()
  if grid.device then
    for x=1,MAXWIDTH do
      refresh_grid_column(x, false)
    end
    grid:refresh()
  end
end

local function refresh_ui()
  if grid.device then
    if gridwidth ~= grid.cols then
      gridwidth = grid.cols
      grid_dirty = true
    end
  end

  local grid_check = grid.device ~= nil
  if grid_connected ~= grid_check then
    grid_connected = grid_check
    grid_dirty = true
  end

  local arc_check = arc.device ~= nil
  if arc_connected ~= arc_check then
    arc_connected = arc_check
    arc_dirty = true
  end

  if grid_dirty then
    refresh_grid()
    grid_dirty = false
  end

  if arc_dirty then
    refresh_arc()
    arc_dirty = false
  end

  if screen_dirty then
    redraw()
  end
end

local function save_patterns()
  local fd=io.open(norns.state.data .. PATTERN_FILE,"w+")
  io.output(fd)
  for patternno=1,NUM_PATTERNS do
    for y=1,HEIGHT do
      for x=1,MAXWIDTH do
        local int
        if trig_is_set(patternno, x, y) then
          int = 1
        else
          int = 0
        end
        io.write(int .. "\n")
      end
    end
  end
  io.close(fd)
end

local function load_patterns()
  local fd=io.open(norns.state.data .. PATTERN_FILE,"r")
  if fd then
    print("found datafile")
    io.input(fd)
    for patternno=1,NUM_PATTERNS do
      for y=1,HEIGHT do
        for x=1,MAXWIDTH do
          set_trig(patternno, x, y, tonumber(io.read()) == 1)
        end
      end   
    end
    io.close(fd)
  end
end  

local function is_even(number)
  return number % 2 == 0
end

local function tick()
  ticks = (ticks or -1) + 1

  if queued_playpos and params:get("cut_quant") == 1 then
    ticks_to_next = 0
  end

  if (not ticks_to_next) or ticks_to_next == 0 then
    local previous_playpos = playpos
    if queued_playpos then
      playpos = queued_playpos
      queued_playpos = nil
    else
      playpos = (playpos + 1) % gridwidth
    end
    local ts = {}
    for y=1,8 do
      if trig_is_set(params:get("pattern"), playpos+1, y) and not (cutting_is_enabled() and y == 8) then
        ts[y] = 1
      else
        ts[y] = 0
      end
    end
    engine.multiTrig(ts[1], ts[2], ts[3], ts[4], ts[5], ts[6], ts[7], ts[8])

    if previous_playpos ~= -1 then
      refresh_grid_column(previous_playpos+1)
    end
    if playpos ~= -1 then
      refresh_grid_column(playpos+1)
    end
    if grid.device then
      grid:refresh()
    end
    if is_even(playpos) then
      ticks_to_next = even_ppqn
    else
      ticks_to_next = odd_ppqn
    end
    redraw()
  else
    ticks_to_next = ticks_to_next - 1
  end
end

local function update_metro_time()
  sequencer_metro.time = 60/params:get("tempo")/ppqn/params:get("beats_per_pattern")
end

local function update_swing(swing_amount)
  local swing_ppqn = ppqn*swing_amount/100*0.75
  even_ppqn = util.round(ppqn+swing_ppqn)
  odd_ppqn = util.round(ppqn-swing_ppqn)
end

function init()
  for patternno=1,NUM_PATTERNS do
    for x=1,MAXWIDTH do
      for y=1,HEIGHT do
        set_trig(patternno, x, y, false)
      end
    end
  end

  params:add {
    type="number",
    id="pattern",
    name="Pattern",
    min=1,
    max=NUM_PATTERNS,
    default=1,
    action=function()
      grid_dirty = true
    end
  }

  params:add {
    type="option",
    id="last_row_cuts",
    name="Last Row Cuts",
    options={"no", "yes"},
    default=1
  }

  params:add {
    type="option",
    id="cut_quant",
    name="Quantize Cutting",
    options={"no", "yes"},
    default=1
  }

  params:add {
    type="number",
    id="beats_per_pattern",
    name="Beats Per Pattern",
    min=1,
    max=8,
    default=4,
    action=update_metro_time
  }

  params:add {
    type="control",
    id="tempo",
    name="Tempo",
    controlspec=tempo_spec,
    action=function(val)
      update_metro_time(val)
      screen_dirty = true
      arc_dirty = true
    end
  }

  params:add {
    type="control",
    id="swing_amount",
    name="Swing Amount",
    controlspec=swing_amount_spec,
    action=function(val)
      update_swing(val)
      screen_dirty = true
      arc_dirty = true
    end
  }

  params:add_separator()

  Ack.add_params()

  arc.delta = function(n, delta)
    if n == 1 then
      local val = params:get_raw("tempo")
      params:set_raw("tempo", val+delta/500)
      screen_dirty = true
      arc_dirty = true
    elseif n == 2 then
      local val = params:get_raw("swing_amount")
      params:set_raw("swing_amount", val+delta/500)
      screen_dirty = true
      arc_dirty = true
    end
  end

  grid.key = function(x, y, state)
    if state == 1 then
      if cutting_is_enabled() and y == 8 then
        queued_playpos = x-1
      else
        set_trig(
          params:get("pattern"),
          x,
          y,
          not trig_is_set(params:get("pattern"), x, y)
        )
        refresh_grid_button(x, y, true)
      end
      if grid.device then
        grid:refresh()
      end
    end
    redraw()
  end

  refresh_ui_metro = metro.init()
  refresh_ui_metro.event = refresh_ui
  refresh_ui_metro.time = 1/60

  sequencer_metro = metro.init()
  sequencer_metro.event = tick

  update_metro_time()

  params:read(1)

  load_patterns()

  params:bang()

  playing = true

  refresh_ui_metro:start()
  sequencer_metro:start()
end

function cleanup()
  params:write(1)

  save_patterns()

  refresh_ui_metro:stop()
  sequencer_metro:stop()

  if grid.device then
    grid:all(0)
    grid:refresh()
  end
end

function enc(n, delta)
  if n == 1 then
    mix:delta("output", delta)
  elseif n == 2 then
    params:delta("tempo", delta)
  elseif n == 3 then
    params:delta("swing_amount", delta)
  end
  redraw()
end

function key(n, s)
  if n == 2 and s == 1 then
    if playing == false then
      playpos = -1
      queued_playpos = 0
      redraw()
      refresh_grid()
    else
      playing = false
      sequencer_metro:stop()
    end
  elseif n == 3 and s == 1 then
    playing = true
    sequencer_metro:start()
  end
  redraw()
end

function redraw()
  local hi_level = 15
  local lo_level = 4

  local show_level = true

  local enc1_x = 0
  local enc1_y = 12

  local enc2_x = 16
  local enc2_y = 32

  local enc3_x = enc2_x+45
  local enc3_y = enc2_y

  local key2_x = 0
  local key2_y = 63

  local key3_x = key2_x+45
  local key3_y = key2_y

  screen.font_size(16)
  screen.clear()

  if show_level then
    screen.move(enc1_x, enc1_y)
    screen.level(lo_level)
    screen.text("LEVEL")
    screen.move(enc1_x+45, enc1_y)
    screen.level(hi_level)
    screen.text(util.round(mix:get_raw("output")*100, 1))
    --screen.text(util.round(mix:get("output"), 1).."dB")
  end

  screen.move(enc2_x, enc2_y)
  screen.level(lo_level)
  screen.text("BPM")
  screen.move(enc2_x, enc2_y+12)
  screen.level(hi_level)
  screen.text(util.round(params:get("tempo"), 1))

  screen.move(enc3_x, enc3_y)
  screen.level(lo_level)
  screen.text("SWING")
  screen.move(enc3_x, enc3_y+12)
  screen.level(hi_level)
  screen.text(util.round(params:get("swing_amount"), 1))
  screen.text("%")

  screen.move(key2_x, key2_y)
  if playing then
    screen.level(lo_level)
  else
    screen.level(hi_level)
  end
  screen.text("STOP")

  screen.move(key3_x, key3_y)

  if playing then
    screen.level(hi_level)
  else
    screen.level(lo_level)
  end
  screen.text("PLAY")

  if playing then
    screen.move(key3_x+44, key3_y)
    screen.level(hi_level)
    screen.text(playpos+1)
  end

  screen.update()
end
