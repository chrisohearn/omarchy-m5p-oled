# Lid close: lock on the K114s (issue #51)

Checked 2026-11-15 on the Mac, read-only, on the promoted r3a kernel with the GPU Stage 2 tree.
Evidence labels: agent-run (a command run on this Mac today), source-read.

## Findings

| Fact | Value | Evidence |
| --- | --- | --- |
| Connector today | `card0-Unknown-1`, connected, 3024x1986 (panel still `simpledrm`) | agent-run, `/sys/class/drm` |
| Live framebuffer node | `/chosen/framebuffer@10fd41b4000` has no `apple,internal-panel` property | agent-run, `/proc/device-tree` |
| Why | The promoted Stage 2 is the GPU tree (`t6050-k114s-r3-gpu.dts`). It includes `display-gpu.dtsi`, which sets the property only under `K114S_R3_EDP` (that is `t6050-k114s-r3-edp.dts`). The `sleep.dtsi` that sets it unconditionally is included by r3a only, not by the GPU tree | source-read, `dts/` |
| Kernel side | `/boot/vmlinuz-linux-k114s` contains the string `apple,internal-panel`, so the simpledrm eDP patch (sleep-lid/0004) is in the installed r3a kernel | agent-run, `grep -c` on the image |
| Inhibitor | `systemd-inhibit --list` shows Omarchy holding `handle-lid-switch` ("External display in use") | agent-run |
| logind | `HandleLidSwitch=lock`, `HandleLidSwitchExternalPower=lock`, `HandleLidSwitchDocked=ignore` (the suspend-blocked drop-in) | agent-run |

So the kernel is ready and the tree is the missing piece: with `apple,internal-panel` on the
framebuffer node the connector becomes `eDP-1`, Omarchy stops counting it as an external monitor,
the inhibitor is released, and a lid close locks (Omarchy script and logind `lock`). Suspend stays
blocked by design (masked targets), so the lid locks but does not suspend until the sleep row opens.

## Headless proof of the Omarchy side

`tests/hardware/test-lid-edp.sh` runs the installed `omarchy-hw-external-monitors`,
`omarchy-system-lid-close` and `omarchy-system-lid-inhibit` against fake DRM trees (their own
`OMARCHY_DRM_PATH` hook; no desktop or logind is touched). 8 of 8 pass on omarchy-dev r7906:
Unknown-1 is external, no lock, inhibitor is taken (today's bug); eDP-1 is internal, lock,
no inhibitor; eDP-1 plus a DP output stays clamshell.

## What is left

1. A Stage 2 tree with the property: `t6050-k114s-r3-edp` (or the display Stage 2 from the D-series,
   where `apple-drm` names the connector `eDP-1` itself and makes this moot). A trial boot is needed,
   one separate attended r3-edp trial outside the display window, or skip it if D9b lands first
   (apple-drm then names eDP-1). The display plan's stages are unchanged.
2. The owner's `monitors.lua` already has an `eDP-1` rule (added for the display trials), which
   is what `docs/r3-sleep-lid.md`, "What it changes for the desktop", point 3 asks for.
3. Owner check after that boot: `tests/hardware/k114s-sleep-check.sh status` shows `connector: eDP-1
   connected` and no `handle-lid-switch` block inhibitor; then close the lid: the session locks.
4. Suspend on lid stays with the sleep row (gates in `docs/r3-sleep-lid.md`).
