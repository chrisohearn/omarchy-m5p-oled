-- k114s-dcp-colour begin (omarchy-m5p-oled, linux/display/k114s-dcp-colour; remove with --undo)
-- The K114s OLED on the display coprocessor: Hyprland colour management on, with the eDP-1 preset Display P3 (dp3). The panel's
-- surfaces are P3-tagged by the driver, and since r3b.c1 its EDID says P3 too (docs/r3-hdr.md). The owner saw edid, dp3 and srgb
-- lit with normal colours on r3b.c1 (2026-11-16). dp3 is the default because it does not use the EDID's primaries: the edid preset
-- blacked the panel on r3b.b1, whose EDID has zero primaries (dp3 on r3b.b1 was not watched). Omarchy's wide-gamut.lua keeps a
-- rule that names cm.
-- The generator 60-aurora-m5-display sets ASAHI_M5_BRINGUP=1 only when the DCP card exists, so a simpledrm boot is untouched.
if os.getenv("ASAHI_M5_BRINGUP") == "1" then
  hl.config({ render = { cm_enabled = true } })
  hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 2, cm = "dp3" })
end
-- k114s-dcp-colour end
