-- k114s-dcp-colour begin (omarchy-m5p-oled, linux/display/k114s-dcp-colour; remove with --undo)
-- The K114s OLED on the display coprocessor: Hyprland colour management on. The preset is HDR (hdredid) when the kernel offers
-- EDR, otherwise Display P3 (dp3). EDR is on when appledrm's fw27_panel_edr_max_nits is above the panel's 1000-nit SDR maximum
-- (linux/display/k114s-edr-cap sets 1200) or 0 (the panel's own peak). The owner saw both look normal on r3b.c3 (2026-11-16):
-- dp3 with the 500-nit default cap, and hdredid with a 1200-nit cap, including a PQ clip (docs/r3-hdr.md sections 7 and 8).
-- dp3 does not use the EDID's primaries, so it is the safe preset on kernels without EDR, and on r3b.b1, whose EDID has zero
-- primaries; there the edid preset blacked the panel. Omarchy's wide-gamut.lua keeps a rule that names cm.
-- The generator 60-aurora-m5-display sets ASAHI_M5_BRINGUP=1 only when the DCP card exists, so a simpledrm boot is untouched.
if os.getenv("ASAHI_M5_BRINGUP") == "1" then
  local f = io.open(os.getenv("K114S_EDR_PARAM") or "/sys/module/appledrm/parameters/fw27_panel_edr_max_nits")
  local cap = f and tonumber(f:read("*l"))
  if f then f:close() end
  local hdr = cap ~= nil and (cap == 0 or cap > 1000)
  hl.config({ render = { cm_enabled = true } })
  hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 2, cm = hdr and "hdredid" or "dp3" })
end
-- k114s-dcp-colour end
