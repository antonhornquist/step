-- scriptname: step
-- v2.0.0 @jah

local ControlSpec = require 'controlspec'

local Ack = require 'ack/lib/ack'

local grid_width

local ui_dirty = false

local refresh_rate = 60

local event_flash_duration = 0.15
local show_event_indicator = false
local event_flash_frame_counter = nil

local arc_led_x_spec = ControlSpec.new(1, 64, ControlSpec.WARP_LIN, 1, 0, "")
local arc_led_l_spec = ControlSpec.new(0, 15, ControlSpec.WARP_LIN, 1, 0, "")
local tempo_spec = ControlSpec.new(20, 300, ControlSpec.WARP_LIN, 0.1, 120, "BPM")
local swing_amount_spec = ControlSpec.new(0, 100, ControlSpec.WARP_LIN, 0.1, 0, "%")

local hi_level = 15
local lo_level = 4

local enc1_x = 1
local enc1_y = 13

local enc2_x = 8
local enc2_y = 32

local enc3_x = enc2_x+50
local enc3_y = enc2_y

local key2_x = 1
local key2_y = 64

local key3_x = key2_x+45
local key3_y = key2_y

local num_patterns = 99
local steps_per_pattern = 16
local num_tracks = 8

local pattern_file = "step.data"

local trig_level = 15
local playpos_level = 7
local clear_level = 0

local playing = false
local queued_playpos
local playpos = -1 -- TODO ?
local sequencer_metro

local ppqn = 24 
local ticks_to_next
local odd_ppqn
local even_ppqn

local trigs = {}

local
cutting_is_enabled =
function()
  return params:get("last_row_cuts") == 2
end

local
get_trigs_index =
function(patternno, stepnum, tracknum)
    return patternno*steps_per_pattern*num_tracks + tracknum*steps_per_pattern + stepnum
end

local
set_trig =
function(patternno, stepnum, tracknum, value)
  trigs[get_trigs_index(patternno, stepnum, tracknum)] = value
end

local
trig_is_set =
function(patternno, stepnum, tracknum)
  return trigs[get_trigs_index(patternno, stepnum, tracknum)]
end

local
init_trigs =
function()
  for patternno=1,num_patterns do
    for stepnum=1,steps_per_pattern do
      for tracknum=1,num_tracks do
        set_trig(patternno, stepnum, tracknum, false)
      end
    end
  end
end

local
get_pattern_length =
function()
  if params:get("pattern_length") == 1 then
    return 8
  else
    return 16
  end
end

local
set_pattern_length =
function(pattern_length)
  local opt
  if pattern_length == 8 then
    opt = 1
  else
    opt = 2
  end
  params:set("pattern_length", opt)
end

local
save_patterns =
function()
  local fd=io.open(norns.state.data .. pattern_file,"w+")
  io.output(fd)
  for patternno=1,num_patterns do
    for tracknum=1,num_tracks do
      for stepnum=1,steps_per_pattern do
        local int
        if trig_is_set(patternno, stepnum, tracknum) then
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

local
load_patterns =
function()
  local fd=io.open(norns.state.data .. pattern_file,"r")
  if fd then
    io.input(fd)
    for patternno=1,num_patterns do
      for tracknum=1,num_tracks do
        for stepnum=1,steps_per_pattern do
          set_trig(patternno, stepnum, tracknum, tonumber(io.read()) == 1)
        end
      end   
    end
    io.close(fd)
  end
end  

local
tick =
function()
  local function is_even(number)
    return number % 2 == 0
  end

  if queued_playpos and params:get("cut_quant") == 1 then
    ticks_to_next = 0
  end

  if (not ticks_to_next) or ticks_to_next == 0 then
    local trigs = {}
    local previous_playpos = playpos
    if queued_playpos then
      playpos = queued_playpos
      queued_playpos = nil
    else
      playpos = (playpos + 1) % get_pattern_length()
    end
    for tracknum=1,num_tracks do
      if trig_is_set(params:get("pattern"), playpos+1, tracknum) and not (cutting_is_enabled() and tracknum == 8) then
        trigs[tracknum] = 1
      else
        trigs[tracknum] = 0
      end
    end
    engine.multiTrig(trigs[1], trigs[2], trigs[3], trigs[4], trigs[5], trigs[6], trigs[7], trigs[8])

    if is_even(playpos) then
      ticks_to_next = even_ppqn
    else
      ticks_to_next = odd_ppqn
    end
    ui_dirty = true
  end
  ticks_to_next = ticks_to_next - 1
end

local
update_sequencer_metro_time =
function()
  sequencer_metro.time = 60/params:get("tempo")/ppqn/params:get("beats_per_pattern")
end

local
update_even_odd_ppqn =
function(swing_amount)
  local swing_ppqn = ppqn*swing_amount/100*0.75
  even_ppqn = util.round(ppqn+swing_ppqn)
  odd_ppqn = util.round(ppqn-swing_ppqn)
end

local
init_sequencer_metro =
function()
  sequencer_metro = metro.init()
  update_sequencer_metro_time()
  sequencer_metro.event = tick
end

local
init_pattern_length_param =
function()
  params:add {
    type="option",
    id="pattern_length",
    name="Pattern Length",
    options={8, 16},
    default=16
  }
end

local
init_pattern_param =
function()
  params:add {
    type="number",
    id="pattern",
    name="Pattern",
    min=1,
    max=num_patterns,
    default=1,
    action=function()
      ui_dirty = true
    end
  }
end

local
init_last_row_cuts_param =
function()
  params:add {
    type="option",
    id="last_row_cuts",
    name="Last Row Cuts",
    options={"No", "Yes"},
    default=1
  }
end

local
init_cut_quant_param =
function()
  params:add {
    type="option",
    id="cut_quant",
    name="Quantize Cutting",
    options={"No", "Yes"},
    default=1
  }
end

local
init_beats_per_pattern =
function()
  params:add {
    type="number",
    id="beats_per_pattern",
    name="Beats Per Pattern",
    min=1,
    max=8,
    default=4,
    action=function(val)
      update_sequencer_metro_time()
    end
  }
end

local
init_tempo_param =
function()
  params:add {
    type="control",
    id="tempo",
    name="Tempo",
    controlspec=tempo_spec,
    action=function(val)
      update_sequencer_metro_time()
      ui_dirty = true
    end
  }
end

local
init_swing_amount_param =
function()
  params:add {
    type="control",
    id="swing_amount",
    name="Swing Amount",
    controlspec=swing_amount_spec,
    action=function(val)
      update_even_odd_ppqn(val)
      ui_dirty = true
    end
  }
end

local
init_params =
function()
  init_pattern_length_param()
  init_pattern_param()
  init_last_row_cuts_param()
  init_cut_quant_param()
  init_beats_per_pattern()
  init_tempo_param()
  init_swing_amount_param()
  params:add_separator()
  Ack.add_params()
end

flash_event =
function()
  event_flash_frame_counter = event_flash_duration/refresh_rate
  ui_dirty = true
end
  
local
update_event_indicator =
function()
  if event_flash_frame_counter then
    event_flash_frame_counter = event_flash_frame_counter - 1
    if event_flash_frame_counter == 0 then
      event_flash_frame_counter = nil
      show_event_indicator = false
      ui_dirty = true
    else
      if not show_event_indicator then
        show_event_indicator = true
        ui_dirty = true
      end
    end
  end
end

local
refresh_grid =
function()
  local
  refresh_grid_button =
  function(x, y)
    if cutting_is_enabled() and y == 8 then
      if x-1 == playpos then
        grid_device:led(x, y, playpos_level)
      else
        grid_device:led(x, y, clear_level)
      end
    else
      if trig_is_set(params:get("pattern"), x, y) then
        grid_device:led(x, y, trig_level)
      elseif x-1 == playpos then
        grid_device:led(x, y, playpos_level)
      else
        grid_device:led(x, y, clear_level)
      end
    end
  end

  local
  refresh_grid_column =
  function(x)
    for tracknum=1,num_tracks do
      refresh_grid_button(x, tracknum)
    end
  end

  for stepnum=1,steps_per_pattern do
    refresh_grid_column(stepnum)
  end

  grid_device:refresh()
end

local
update_grid_width =
function()
  if grid_device.device then
    if grid_width ~= grid_device.cols then
      grid_width = grid_device.cols
    end
  end
end

local
refresh_arc =
function()
  arc_device:all(0)
  arc_device:led(1, arc_led_x_spec:map(params:get_raw("tempo")), arc_led_l_spec.maxval)
  arc_device:led(2, arc_led_x_spec:map(params:get_raw("swing_amount")), arc_led_l_spec.maxval)
  arc_device:refresh()
end

local
refresh_ui =
function()
  update_event_indicator()
  update_grid_width()

  if prev_grid_width ~= grid_width then
    set_pattern_length(grid_width)
    prev_grid_width = grid_width
    ui_dirty = true
  end

  if ui_dirty then
    redraw()
    refresh_arc()
    refresh_grid()
    ui_dirty = false
  end
end

local
init_60_fps_ui_refresh_metro =
function()
  local ui_refresh_metro = metro.init()
  ui_refresh_metro.event = refresh_ui
  ui_refresh_metro.time = 1/60
  ui_refresh_metro:start()
end

local
init_arc =
function()
  arc_device = arc.connect()
  arc_device.delta = function(n, delta)
    if n == 1 then
      local val = params:get_raw("tempo")
      params:set_raw("tempo", val+delta/500)
    elseif n == 2 then
      local val = params:get_raw("swing_amount")
      params:set_raw("swing_amount", val+delta/500)
    end
    flash_event()
    ui_dirty = true
  end
end

local
init_grid =
function()
  grid_device = grid.connect()
  grid_device.key = function(x, y, state)
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
      end
    end
    flash_event()
    ui_dirty = true
  end
end

local
init_ui =
function()
  init_arc()
  init_grid()
  init_60_fps_ui_refresh_metro()
end

local
get_play_label =
function()
  if playing then
    return "PLAY " .. (playpos+1)
  else
    return "PLAY"
  end
end

engine.name = 'Ack'

init =
function()
  init_trigs()
  init_params()
  init_sequencer_metro()
  load_patterns()
  init_ui()

  params:read()
  params:bang()
end

cleanup =
function()
  params:write()
  save_patterns()

  if grid_device.device then
    grid_device:all(0)
    grid_device:refresh()
  end
end

redraw_event_flash_widget =
function()
  screen.level(lo_level)
  screen.rect(122, enc1_y-7, 5, 5)
  screen.fill()
end

redraw =
function()
  local
  redraw_enc1_widget =
  function()
    screen.move(enc1_x, enc1_y)
    screen.level(lo_level)
    screen.text("LEVEL")
    screen.move(enc1_x+45, enc1_y)
    screen.level(hi_level)
    screen.text(util.round(params:get_raw("main_level")*100, 1))
  end

  local
  redraw_param_widget =
  function(x, y, label, value)
    screen.move(x, y)
    screen.level(lo_level)
    screen.text(label)
    screen.move(x, y+12)
    screen.level(hi_level)
    screen.text(value)
  end

  local
  redraw_enc2_widget =
  function()
    redraw_param_widget(enc2_x, enc2_y, "BPM", params:get("tempo"))
  end

  local
  redraw_enc3_widget =
  function()
    redraw_param_widget(enc3_x, enc3_y, "SWING", tostring(params:get("swing_amount")) .. "%")
  end

  local
  redraw_key2_widget =
  function()
    screen.move(key2_x, key2_y)
    if playing then
      screen.level(lo_level)
    else
      screen.level(hi_level)
    end
    screen.text("STOP")
  end

  local
  redraw_key3_widget =
  function()
    screen.move(key3_x, key3_y)
    if playing then
      screen.level(hi_level)
    else
      screen.level(lo_level)
    end
    screen.text(get_play_label())
  end

  screen.font_size(16)
  screen.clear()

  redraw_enc1_widget()

  if show_event_indicator then
    redraw_event_flash_widget()
  end

  redraw_enc2_widget()
  redraw_enc3_widget()
  redraw_key2_widget()
  redraw_key3_widget()
  screen.update()
end

enc =
function(n, delta)
  if n == 1 then
    params:delta("main_level", delta)
    ui_dirty = true
  elseif n == 2 then
    params:delta("tempo", delta)
  elseif n == 3 then
    params:delta("swing_amount", delta)
  end
end

key =
function(n, s)
  if n == 2 and s == 1 then
    if playing == false then
      playpos = -1
      queued_playpos = 0
    else
      playing = false
      sequencer_metro:stop()
    end
  elseif n == 3 and s == 1 then
    playing = true
    sequencer_metro:start()
  end
  ui_dirty = true
end
