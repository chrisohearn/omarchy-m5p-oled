# Draft, not posted: issue for betizzel/omarchy-m5

**Title:** Hyprland colour management blacks out the K114s (MacBook Pro 14" M5 Pro OLED) after the DCP hand-off

**Body:**

On a K114s (`apple,k114s`, T6050) with the display coprocessor hand-off published, the desktop was black on every boot until
Hyprland's colour management was turned off. The hand-off itself works.

Evidence (kernel `7.3.0-17.v272-11`, r3 loader, `appledrm` driving the panel at 3024x1986, 120 Hz):

- With `render:cm_enabled` on (monitor preset `edid`, which Omarchy's `default/hypr/wide-gamut.lua` gives every rule without a `cm` on `aarch64-apple`), every frame is black. The connector shows `Colorspace BT2020_RGB`.
- `modetest` test patterns in `XR24` and `AR24` light the panel, so scanout and the panel are fine (owner-observed).
- Backlight writes reach the panel: a stepped ladder read back correctly and the panel dimmed and recovered, so this is not a
  zero-brightness panel.
- With `render = { cm_enabled = false }` the desktop lights up: colours normal, text sharp, movement smooth (owner-observed).
  DPMS off and on three times worked, and night light on and off gave no DCP crash line.

Workaround, in `~/.config/hypr/monitors.lua`:

```lua
if os.getenv("ASAHI_M5_BRINGUP") == "1" then hl.config({ render = { cm_enabled = false } }) end
```

`ASAHI_M5_BRINGUP=1` is printed by `60-aurora-m5-display` only when `/dev/dri/by-path/platform-display-subsystem-card`
exists, so the line does nothing on a simpledrm boot.

Suggestion: let the same generator, or the `hyprland-m5` default config, turn colour management off on a DCP boot, so a user
does not get a black screen. We have not read the Hyprland side, so the mechanism (why `edid` colour management produces
black here) is unknown; we only know the switch that avoids it. Happy to test a narrower setting (for example a different
monitor colour preset) on the K114s; `cm = "srgb"` on the eDP-1 rule is what we use, and it also silences Hyprland's "wide color gamut is enabled but the display is not in 10-bit mode" warning (the driver's EDID has zero primaries). The fix may belong in Omarchy's wrapper rather than in omarchy-m5.
