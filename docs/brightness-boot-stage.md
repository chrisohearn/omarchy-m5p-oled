# Brightness while the panel is the boot framebuffer (K114s)

Tracking issue: #2. State on 2026-11-14, kernel `7.3.0-17.v272-4-ARCH` (K114S-R1), loader
`1.0.0b13-g22b71758` plus the J714s 27.2 patches. Evidence labels: **agent-run** (a command or a
source read on this Mac), **upstream** (someone else's report or source), **owner-observed**.
Nothing here is owner-observed yet.

## Short answer

- Nothing in Linux or in the loader sets the panel's level today. The level is whatever Apple's
  boot stage (iBoot) gave the display coprocessor at power-on, and it stays there until a driver
  takes the coprocessor over.
- Upstream says iBoot takes that level from the NVRAM variable `backlight-nits`, which macOS keeps
  at the user's level. If that holds on this model, setting the brightness in macOS and then
  starting Omarchy carries the level over. **This is not yet tested on a K114s or on any OLED
  model.** The test below costs one restart and writes nothing from Linux.
- Linux cannot read `backlight-nits` on this Mac today (no NVRAM device in the K114s device tree).
- A compositor-side control can only dim below the boot level. `tools/brightness/k114s-soft-dim`
  is such a control, clearly not a brightness control, and not yet run on the compositor.

## What decides the level

1. **iBoot.** Upstream, `aurora-silicon/aurora-bless` (`aurora-panel-nits`, commit `64cac60e2f`):
   "The boot loader lights the built-in panel at the NVRAM system:backlight-nits level (ASCII hex
   16.16 nits), and macOS keeps that variable at the user's level." `0x008c0000` is 140 nits.
   Tested there on the MacBook Neo (J700, LCD), Linux side. `aurora-silicon/linux` #1696 (J813,
   LCD) reports the same variable and value and a panel that reads 140 nits. xnu lists
   `backlight-nits` as a user-writable NVRAM variable (`iokit/Kernel/IONVRAM.cpp`). The Asahi
   documentation only says "presumably the screen backlight strength". (upstream)
2. **The loader (Aura, an m1n1 fork) does not touch it.** (agent-run, source and installed binary)
   - `src/display.c` `display_init()`: an internal panel with a real framebuffer takes the
     "Display is already initialized" path and returns. No coprocessor call is made.
   - `src/dcp_iboot.c`: the only commands the loader can send are set surface, set power, get
     hot-plug state, get timing modes, get colour modes, set mode, and the three swap calls. There
     is no brightness command. `AsahiLinux/m1n1` `main` has the same list.
   - No source file under `src/` mentions backlight or brightness, apart from
     `kboot_display_handoff.c`, which copies the panel's maximum (`user-accessible-max-nits`) into
     the device tree for a later driver. `strings` of the installed `m1n1.bin` shows the same
     and nothing more: `/backlight-override`, `user-accessible-max-nits`, `apple,max-brightness`.
   - `display=` in `/etc/m1n1.conf` carries a mode only: `auto`, `max`, or `WxH[@fps][,retina]`
     (`display_parse_mode()`). It cannot carry a level. On this Mac it would also start the
     loader's generic M1 modeset against a coprocessor nobody has qualified it for (the T6030
     guard in the same file exists for that reason; T6050 has none). **Do not set `display=`.**
3. **Linux does not touch it.** (agent-run)
   - `/sys/class/backlight/` is empty.
   - The DRM device has no colour or brightness property at all
     (`tools/brightness/drm-props.py`): CRTC `ACTIVE, MODE_ID, OUT_FENCE_PTR, VRR_ENABLED`;
     connector `EDID, DPMS, link-status, non-desktop, TILE, CRTC_ID`; one primary plane. No `CTM`,
     no `GAMMA_LUT`.
   - `simpledrm.c` in the running kernel's source has no gamma, colour-matrix or backlight code.

## Reading the level from Linux

Not possible today. (agent-run)

- `/sys/firmware/efi/efivars` holds only U-Boot's own variables; Apple's NVRAM is not there.
- Apple's NVRAM is a partition of the boot flash. The kernel exposes it as the MTD partition
  `nvram` when the device tree enables the flash controller and the loader fills in the
  partition. In this kernel only `t6050-j775d.dts` does that. The K114s tree leaves the
  controller (`spi@505118000`) disabled, so `/proc/mtd` lists only the loader's two logs and its
  copy of Apple's device tree, all readable by root only.
- `aurora-bless` is installed and looks for `/dev/mtd/by-name/nvram`, which does not exist here.
  `aurora-nvram` and `aurora-panel-nits` are not installed.

Follow-up, not done here: enabling that partition for the K114s (as `t6050-j775d.dts` does) would
let Linux read `backlight-nits`. It is device-tree work that needs a rebuilt tree and a test boot,
and that controller also allows writes inside the partition, so it should be reviewed on its own.

## The test (owner, about ten minutes, nothing written from Linux)

The aim is to learn whether iBoot applies the macOS level on this model, and to end at maximum.

1. Start macOS (hold the power button at start-up, pick the macOS volume).
2. System Settings > Displays: turn off "Automatically adjust brightness". Keep the Mac on its
   charger, or turn off "Slightly dim the display on battery" in Battery > Options.
3. Set the brightness slider to the **minimum that is still clearly readable** (not zero). Wait
   ten seconds. In Terminal, run `nvram backlight-nits` and note the value. This only reads.
4. Shut down, start Omarchy, and note how bright the desktop is. Very dim means the level came
   across.
5. Start macOS again, set the slider to **maximum**, wait ten seconds, run `nvram backlight-nits`
   again and note the value, shut down, start Omarchy.
6. Compare the two Omarchy sessions.

Reading the result:

| Observation | Meaning |
|---|---|
| The two `nvram` values differ and Omarchy was dim, then bright | iBoot applies the macOS level on the K114s. Maximum in macOS is the stopgap for 100 %. |
| The two `nvram` values differ but Omarchy looked the same both times | iBoot does not apply it on this model (or clamps it). No stopgap; the coprocessor port is the only way. |
| The `nvram` value did not change | macOS does not store the level this way here. Same conclusion. |

The value is ASCII hex, 16.16 fixed point, in nits: the top four hex digits are whole nits
(`0x008c0000` = 140, `0x03e80000` = 1000). Do not edit it by hand.

Why step 3 uses a readable minimum: if the level does carry over, a zero level could leave
Omarchy with a black panel. Recovery in that case is to hold the power button, start macOS and
raise the brightness.

## Interim dimming (software only)

`tools/brightness/k114s-soft-dim` asks Hyprland to scale every pixel in its final render pass
(`decoration:screen_shader`). On an OLED panel that does lower the light each pixel emits, but:

- 100 % is the boot level. It can never go above it.
- Output is 8-bit, so low levels show banding.
- Hyprland's night-light route (`hyprsunset`) cannot be used instead: it needs the display
  driver's `CTM` property, which the boot framebuffer does not have (aquamarine 0.16.0 logs
  "failed to commit ctm: no ctm prop support").
- Status: the shader compiles (`glslangValidator`), the script's dry run works, and the option
  exists in the running Hyprland (`hyprctl getoption decoration:screen_shader`). It has **not**
  been run against the compositor on this Mac.

It is not bound to the brightness keys. Binding them would make the keys look as if they work
while the upper limit stays wherever the boot stage left it; that choice is the owner's.

## Could not determine

- Whether this model's iBoot (system firmware 27.3 beta, stub 27.2) applies `backlight-nits` to
  the OLED panel, and whether it clamps the value. No upstream report covers an OLED Mac.
- What level the panel is at now. Linux has no way to read it in this state.
- Whether the coprocessor changes the level by itself over time (temperature, content) while no
  driver talks to it.
- Whether macOS on this model writes `backlight-nits` at once or only at shutdown; hence the wait
  and the clean shutdown in the test.
