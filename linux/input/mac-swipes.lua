-- k114s-mac-swipes begin (omarchy-m5p-oled, linux/input/k114s-mac-swipes; remove with --undo)
-- Mac-style workspace swipes (the owner's preference, 2026-11-16): the desktop follows the fingers, so a swipe left goes to
-- the next workspace and a swipe right to the previous one, as on macOS. Omarchy's defaults (default/hypr/gestures.lua,
-- omacom/omarchy#16891) go the other way on purpose. Four fingers carry the active window the same way. Each default is
-- unset first, because Hyprland rejects a second gesture on the same fingers and direction.
for _, f in ipairs({ 3, 4 }) do
  hl.gesture({ fingers = f, direction = "left", action = "unset" })
  hl.gesture({ fingers = f, direction = "right", action = "unset" })
end
hl.gesture({ fingers = 3, direction = "left", action = function() hl.dispatch(hl.dsp.focus({ workspace = "r+1" })) end })
hl.gesture({ fingers = 3, direction = "right", action = function() hl.dispatch(hl.dsp.focus({ workspace = "r-1" })) end })
hl.gesture({ fingers = 4, direction = "left", action = function() hl.dispatch(hl.dsp.window.move({ workspace = "r+1" })) end })
hl.gesture({ fingers = 4, direction = "right", action = function() hl.dispatch(hl.dsp.window.move({ workspace = "r-1" })) end })
-- k114s-mac-swipes end
