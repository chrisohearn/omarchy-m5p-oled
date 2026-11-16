-- k114s-dcp-colour begin (omarchy-m5p-oled, linux/display/k114s-dcp-colour; remove with --undo)
-- On the K114s OLED driven by the display coprocessor, Hyprland colour management (render:cm_enabled) makes every frame black, and
-- the driver's EDID has zero primaries, so Omarchy's wide-gamut.lua (cm = "edid" for every rule without cm) warns about a gamut the
-- panel is not in 10-bit mode for. The eDP-1 rule below names cm = "srgb", which wide-gamut.lua keeps.
-- The generator 60-aurora-m5-display sets ASAHI_M5_BRINGUP=1 only when the DCP card exists, so a simpledrm boot is untouched.
if os.getenv("ASAHI_M5_BRINGUP") == "1" then
  hl.config({ render = { cm_enabled = false } })
  hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 2, cm = "srgb" })
end
-- k114s-dcp-colour end
