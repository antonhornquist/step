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

local PSET = "step.pset"
local PATTERN_FILE = "step.data"

local TRIG_LEVEL = 15
local PLAYPOS_LEVEL = 7
local CLEAR_LEVEL = 0

local grid = grid.connect()
local grid_connected = false

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

local function refresh_grid()
  if grid.device then
    for x=1,MAXWIDTH do
      refresh_grid_column(x, false)
    end
    grid:refresh()
  end
end

local function refresh_ui()
  local redraw_screen = false
  local grid_dirty = false

  --[[ TODO
  local arc_check = arc.device ~= nil
  if arc_connected ~= arc_check then
    arc_connected = arc_check
    redraw_screen = true
  end
  ]]

  if redraw_screen then
    redraw()
  end

  if grid.device then
    if gridwidth ~= grid.cols then
      gridwidth = grid.cols
      grid_dirty = true
    end
  end

  if grid_dirty then
    refresh_grid()
    grid_dirty = false
  end
end

local function save_patterns()
  print(norns.state.data)
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
  print(norns.state.data)
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

local function gridkey_event(x, y, state)
  if state == 1 then
    if cutting_is_enabled() and y == 8 then
      queued_playpos = x-1
    else
      set_trig(params:get("pattern"), x, y, not trig_is_set(params:get("pattern"), x, y))
      refresh_grid_button(x, y, true)
    end
    if grid.device then
      grid:refresh()
    end
  end
  redraw()
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
    action=refresh_grid
  }

  params:add {
    type="option",
    id="last_row_cuts",
    name="Last Row Cuts",
    options={"no", "yes"},
    default=1,
    action=refresh_grid
  }

  params:add {
    type="option",
    id="cut_quant",
    name="Quantize Cutting",
    options={"no", "yes"},
    default=1,
    action=refresh_grid
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
    action=update_metro_time
  }

  params:add {
    type="control",
    id="swing_amount",
    name="Swing Amount",
    controlspec=swing_amount_spec,
    action=update_swing
  }

  params:add_separator()

  Ack.add_params()

  grid.key = gridkey_event

  refresh_ui_metro = metro.init()
  refresh_ui_metro.event = refresh_ui
  refresh_ui_metro.time = 1/60

  sequencer_metro = metro.init()
  sequencer_metro.event = tick

  update_metro_time()

  load_patterns()
  params:read(PSET)
  params:bang()

  playing = true

  refresh_ui_metro:start()
  sequencer_metro:start()
end

function cleanup()
  save_patterns()
  print(12414312)
  params:write(PSET)
  -- refresh_ui_metro:stop()
  -- sequencer_metro:stop()
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
  screen.font_size(8)
  screen.clear()
  screen.level(15)
  screen.move(10,30)
  if playing then
    screen.level(3)
    screen.text("[] stop")
  else
    screen.level(15)
    screen.text("[] stopped")
  end
  screen.font_size(8)
  screen.move(70,30)
  if playing then
    screen.level(15)
    screen.text("|> playing")
    screen.text(" "..playpos+1)
  else
    screen.level(3)
    screen.text("|> play")
  end
  screen.level(15)
  screen.move(10,50)
  screen.text(params:string("tempo"))
  screen.move(70,50)
  screen.text(params:string("swing_amount"))
  screen.level(3)
  screen.move(10,60)
  screen.text("tempo")
  screen.move(70,60)
  screen.text("swing")
  screen.update()
end
