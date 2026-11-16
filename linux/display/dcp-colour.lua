-- k114s-dcp-colour begin (omarchy-m5p-oled, linux/display/k114s-dcp-colour; remove with --undo)
-- On the K114s OLED driven by the display coprocessor, Hyprland colour management (render:cm_enabled) makes every frame black.
-- The generator 60-aurora-m5-display sets ASAHI_M5_BRINGUP=1 only when the DCP card exists, so a simpledrm boot is untouched.
if os.getenv("ASAHI_M5_BRINGUP") == "1" then hl.config({ render = { cm_enabled = false } }) end
-- k114s-dcp-colour end
