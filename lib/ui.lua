-- utility library for single-grid, single-arc, single-midi device script UIs
-- prerequisites: metro, midi, arc, grid globals defined

local UI = {}

-- refresh logic

local function tick()
  UI.update_arc_connected()
  UI.update_grid_width()
  UI.update_grid_connected()
  UI.update_event_indicator()
    
  if UI.arc_dirty then
    if UI.refresh_arc_callback then
      UI.refresh_arc_callback(UI.my_arc)
    end
    UI.my_arc:refresh()
    UI.arc_dirty = false
  end

  if UI.grid_dirty then
    if UI.refresh_grid_callback then
      UI.refresh_grid_callback(UI.my_grid)
    end
    UI.my_grid:refresh()
    UI.grid_dirty = false
  end

  if UI.screen_dirty then
    if UI.refresh_screen_callback then
      UI.refresh_screen_callback()
    end
    screen.update()
    UI.screen_dirty = false
  end
end

function UI.init(rate)
  UI.refresh_metro = metro.init()
  UI.refresh_metro.event = tick
  UI.refresh_metro.time = 1/(rate or 60)
  UI.refresh_metro:start()
end

function UI.setup(config)
  UI.setup_midi(config.midi_event_callback)
  UI.setup_grid(config.grid_key_callback, config.grid_refresh_callback)
  UI.setup_arc(config.arc_delta_callback, config.arc_refresh_callback)
  UI.setup_screen(config.screen_refresh_callback)

  UI.init()
end

-- event flash

local EVENT_FLASH_LENGTH = 10
UI.show_event_indicator = false
local event_flash_counter = nil

function UI.flash_event()
  event_flash_counter = EVENT_FLASH_LENGTH
end
  
function UI.update_event_indicator()
  if event_flash_counter then
    event_flash_counter = event_flash_counter - 1
    if event_flash_counter == 0 then
      event_flash_counter = nil
      UI.show_event_indicator = false
      UI.set_screen_dirty()
    else
      if not UI.show_event_indicator then
        UI.show_event_indicator = true
        UI.set_screen_dirty()
      end
    end
  end
end

-- arc

UI.arc_connected = false
UI.arc_dirty = false

function UI.set_arc_dirty()
  UI.arc_dirty = true
end

function UI.setup_arc(delta_callback, refresh_callback)
  local my_arc = arc.connect()
  my_arc.delta = delta_callback
  UI.my_arc = my_arc
  UI.refresh_arc_callback = refresh_callback
end

function UI.update_arc_connected()
  local arc_check = UI.my_arc.device ~= nil
  if UI.arc_connected ~= arc_check then
    UI.arc_connected = arc_check
    UI.set_arc_dirty()
  end
end
  
-- grid

UI.grid_connected = false
UI.grid_dirty = false
UI.grid_width = 16

function UI.set_grid_dirty()
  UI.grid_dirty = true
end

function UI.setup_grid(key_callback, refresh_callback)
  local my_grid = grid.connect()
  my_grid.key = key_callback
  UI.my_grid = my_grid
  UI.refresh_grid_callback = refresh_callback
end

function UI.update_grid_width()
  if UI.my_grid.device then
    if UI.grid_width ~= UI.my_grid.cols then
      UI.grid_width = UI.my_grid.cols
      UI.set_grid_dirty()
      if UI.grid_width_changed_callback then
        UI.grid_width_changed_callback(UI.grid_width)
      end
    end
  end
end

function UI.update_grid_connected()
  local grid_check = UI.my_grid.device ~= nil
  if UI.grid_connected ~= grid_check then
    UI.grid_connected = grid_check
    UI.set_grid_dirty()
  end
end

-- midi

function UI.setup_midi(event_callback)
  local my_midi_device = midi.connect()
  my_midi_device.event = event_callback
  UI.my_midi_device = my_midi_device
end

-- screen

function UI.set_screen_dirty()
  UI.screen_dirty = true
end

function UI.setup_screen(refresh_callback)
  UI.refresh_screen_callback = refresh_callback
end

return UI
