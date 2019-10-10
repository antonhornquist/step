-- small utility library for single-grid, single-arc, single-midi device script UIs
-- written to track dirty states of UI, provide a generic refresh function
-- written to not be directly dependent on norns global variables

local UI = {}

-- refresh logic

function UI.refresh()
  UI.update_event_indicator()

  if UI.arc_inited then
    UI.check_arc_connected()
      
    if UI.arc_dirty then
      if UI.refresh_arc_callback then
        UI.refresh_arc_callback(UI.my_arc)
      end
      UI.my_arc:refresh()
      UI.arc_dirty = false
    end
  end

  if UI.grid_inited then
    UI.check_grid_connected()
    UI.update_grid_width()

    if UI.grid_dirty then
      if UI.refresh_grid_callback then
        UI.refresh_grid_callback(UI.my_grid)
      end
      UI.my_grid:refresh()
      UI.grid_dirty = false
    end
  end

  if UI.midi_inited then
    UI.check_midi_connected()
  end

  if UI.screen_dirty then
    if UI.refresh_screen_callback then
      UI.refresh_screen_callback()
    end
    screen.update()
    UI.screen_dirty = false
  end
end

function UI.set_dirty()
  UI.arc_dirty = true
  UI.grid_dirty = true
  UI.screen_dirty = true
end

-- event flash

local EVENT_FLASH_FRAMES = 10
UI.show_event_indicator = false
local event_flash_frame_counter = nil

function UI.flash_event()
  event_flash_frame_counter = EVENT_FLASH_FRAMES
end
  
function UI.update_event_indicator()
  if event_flash_frame_counter then
    event_flash_frame_counter = event_flash_frame_counter - 1
    if event_flash_frame_counter == 0 then
      event_flash_frame_counter = nil
      UI.show_event_indicator = false
      UI.screen_dirty = true -- TODO: hmmm, should this be here? indicator assumed to be on screen, why not grid?
    else
      if not UI.show_event_indicator then
        UI.show_event_indicator = true
        UI.screen_dirty = true -- TODO: hmmm, should this be here? indicator assumed to be on screen, why not grid?
      end
    end
  end
end

-- arc

UI.arc_connected = false
UI.arc_dirty = false

function UI.init_arc(config)
  local my_arc = config.device
  my_arc.delta = config.delta_callback
  UI.my_arc = my_arc
  UI.refresh_arc_callback = config.refresh_callback
  UI.arc_inited = true
end

function UI.check_arc_connected()
  local arc_check = UI.my_arc.device ~= nil
  if UI.arc_connected ~= arc_check then
    UI.arc_connected = arc_check
    UI.arc_dirty = true
  end
end
  
-- grid

UI.grid_connected = false
UI.grid_dirty = false
UI.grid_width = 16

function UI.init_grid(config)
  local my_grid = config.device
  my_grid.key = config.key_callback
  UI.my_grid = my_grid
  UI.refresh_grid_callback = config.refresh_callback
  UI.grid_inited = true
end

function UI.update_grid_width()
  if UI.my_grid.device then
    if UI.grid_width ~= UI.my_grid.cols then
      UI.grid_width = UI.my_grid.cols
      UI.grid_dirty = true
      if UI.grid_width_changed_callback then
        UI.grid_width_changed_callback(UI.grid_width)
      end
    end
  end
end

function UI.check_grid_connected()
  local grid_check = UI.my_grid.device ~= nil
  if UI.grid_connected ~= grid_check then
    UI.grid_connected = grid_check
    UI.grid_dirty = true
  end
end

-- midi

function UI.init_midi(config)
  local my_midi_device = config.device
  my_midi_device.event = config.event_callback
  UI.my_midi_device = my_midi_device
  UI.midi_inited = true
end

function UI.check_midi_connected()
  local midi_device_check = UI.my_midi_device.device ~= nil
  if UI.midi_device_connected ~= midi_device_check then
    UI.midi_device_connected = midi_device_check
  end
end

-- screen

function UI.init_screen(config)
  UI.refresh_screen_callback = config.refresh_callback
end

return UI