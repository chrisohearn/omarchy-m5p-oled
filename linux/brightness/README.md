# Omarchy side of K114s panel brightness

Tracking issue: #2. Full picture: `docs/r3-brightness.md`. Nothing in this directory is installed
by anything; each file says where it would go.

## Once the panel is on the display coprocessor: nothing to install

The brightness keys and the display panel's slider need no Omarchy change. Agent-run reads of the
installed Omarchy on this Mac (2026-11-14), not yet seen working:

| Omarchy piece | What it needs | What the K114s gives once the candidate boots |
| --- | --- | --- |
| `omarchy-brightness-display` (keys through the script, the slider, `omarchy brightness display N%`) | the focused monitor named `eDP-*`, `LVDS-*` or `DSI-*` | the coprocessor's connector is eDP, so `eDP-1` (today: `Unknown-1`, which is why the script exits 1) |
| `omarchy-hw-display` | a device in `/sys/class/backlight`; `/usr/share/omarchy-platform/displays.conf` already says `backlight-prefer apple-panel-bl` | the kernel names the device `apple-panel-bl` |
| the shell's key handler (`shell/services/BrightnessKeys.qml`) | the same device, found when the shell starts; without one it falls back to the script | either path works; the device can appear a few seconds after the desktop |
| `brightnessctl` 0.5 | permission to write | none needed: it asks logind, as it already does for the keyboard backlight |
| `systemd-backlight@backlight:apple-panel-bl` | nothing | saves the level at shutdown and writes it back at boot, clamped to at least 5 % of the maximum (`systemd-backlight@.service(8)`, `ID_BACKLIGHT_CLAMP`; not run here) |

The device's type is `platform` and its scale is `linear`, in nits; Omarchy does not look at
either. Omarchy's own paths never ask for less than 1 %: the keys stop at 1 %, Shift + brightness
down is 1 %, and the slider clamps to 1..100. Screen-off (`omarchy-brightness-display off`, which the
lock screen uses) is display power management, not a level.
Only a direct write (`brightnessctl set 0`, another tool) can ask for 0, and the kernel floor in
`patches/linux/brightness` (0005, 0006) with `dts/t6050-k114s-brightness.dtsi` is there for that.

## `k114s-backlight-check`: the owner's first hardware check

Run it in a terminal on the first boot with the panel on the coprocessor. No sudo, no install:

    linux/brightness/k114s-backlight-check --read-only     # what the kernel registered; writes nothing
    linux/brightness/k114s-backlight-check                 # the stepped check, with questions

It writes a short series of levels and asks after each what you see. No answer within 20 s puts
back the last level you confirmed you could read, so a dark screen recovers by waiting. It never
writes 0 and never goes below the larger of 10 nits, 1 % of the maximum and the kernel's floor.
`tests/brightness/test-backlight-check.sh` exercises those rules against a stand-in directory
(emulator/replica; 15 checks pass).

## `interim/`: software dimming for today (optional, dimming only, not yet run)

While the panel is the boot framebuffer nothing can raise its level from Linux. `interim/` can
only **dim below the level the boot stage left**: Hyprland multiplies every pixel in its last
render pass (`decoration:screen_shader`). "Maximum" there is the boot level, not the panel's.
For 100 % today see the macOS procedure in `docs/brightness-boot-stage.md`.

Status: the scripts' dry runs behave, the generated shader compiles (`glslangValidator`), and the
option exists in the running Hyprland 0.57.2. **Not run against the compositor on this Mac**, and
the cost on the software renderer is not measured. Whether to install it is the owner's call.

Files and where they would go (the owner copies them; nothing here does):

| File | Destination | Mode |
| --- | --- | --- |
| `interim/k114s-soft-dim` | `~/.config/hypr/k114s-brightness/k114s-soft-dim` | 755 |
| `interim/k114s-brightness-key` | `~/.config/hypr/k114s-brightness/k114s-brightness-key` | 755 |
| the four `o.rebind` lines of `interim/bindings-k114s-soft-dim.lua` | appended to `~/.config/hypr/bindings.lua` | |

    mkdir -p ~/.config/hypr/k114s-brightness
    install -m 755 linux/brightness/interim/k114s-soft-dim linux/brightness/interim/k114s-brightness-key ~/.config/hypr/k114s-brightness/

Try it from a terminal before binding any key:

    ~/.config/hypr/k114s-brightness/k114s-soft-dim 60     # dim to about 60 % of the boot level
    ~/.config/hypr/k114s-brightness/k114s-soft-dim off    # back

If the picture looks wrong: `k114s-soft-dim off`; or `hyprctl reload`; or log out. Nothing is
saved, so a new session always starts undimmed. The floor is 10 %, so it cannot dim to black.

With the bindings appended (Hyprland picks a saved configuration file up by itself by default;
otherwise `hyprctl reload`):

| Keys | Without a real backlight (today) | With `apple-panel-bl` (after the port) |
| --- | --- | --- |
| brightness up / down | software dim 10 points up / down, 10..100 | Omarchy's own `+5%` / `5%-` |
| Shift + brightness up | software dim off (the boot level) | Omarchy's 100 % |
| Shift + brightness down | software dim 10 % | Omarchy's 1 % |

The on-screen note says "Software dim 60%", not a brightness bar, so it is not mistaken for the
panel's level. `k114s-brightness-key` hands over to Omarchy by itself as soon as a real backlight
exists and turns the software dimming off first; remove the four lines and the directory then.

To remove: delete the four lines from `~/.config/hypr/bindings.lua` and
`rm -r ~/.config/hypr/k114s-brightness`.
