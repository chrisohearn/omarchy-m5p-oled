-- K114s interim, software dimming on the brightness keys (omarchy-m5p-oled, issue #2).
--
-- Append these four lines to ~/.config/hypr/bindings.lua. They replace Omarchy's bindings for
-- the plain and Shift brightness keys. Remove them again when the panel has a real backlight
-- (ls /sys/class/backlight shows apple-panel-bl); until you do, the script behind them hands
-- over to Omarchy's own control by itself.
--
-- What the keys do with these lines and no real backlight: they DIM the picture below the level
-- the boot stage left the panel at, in software, down to 10 %. "Maximum" is that boot level, not
-- the panel's maximum. Nothing here can make the panel brighter.
--
-- The Ctrl (keyboard backlight) and Alt (precise) combinations are left as Omarchy has them;
-- the Alt ones keep doing nothing until there is a real backlight.

o.rebind("XF86MonBrightnessUp", "Software dim: brighter", "~/.config/hypr/k114s-brightness/k114s-brightness-key raise", { locked = true, repeating = true })
o.rebind("XF86MonBrightnessDown", "Software dim: darker", "~/.config/hypr/k114s-brightness/k114s-brightness-key lower", { locked = true, repeating = true })
o.rebind("SHIFT + XF86MonBrightnessUp", "Software dim: off", "~/.config/hypr/k114s-brightness/k114s-brightness-key max", { locked = true, repeating = true })
o.rebind("SHIFT + XF86MonBrightnessDown", "Software dim: darkest", "~/.config/hypr/k114s-brightness/k114s-brightness-key min", { locked = true, repeating = true })
