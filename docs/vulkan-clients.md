# Vulkan clients on the K114s (issue #26)

Parity target: Asahi M1/M2 has conformant Vulkan 1.4 (vulkan-asahi). The K114s has the aurora fork
`vulkan-aurora 26.3.0_devel.20261109.j714s2` (driver "Borealis", derived from Honeykrisp).

## Evidence

| Fact | Label |
|---|---|
| `vulkaninfo --summary` (vulkan-tools 1.4.363.0 unpacked in a scratch directory, nothing installed) with the GPU desktop running: one device, `Apple M5 Pro (G17S B1)`, integrated GPU, apiVersion 1.4.363, driverName `Borealis`, driverInfo `Mesa 26.3.0-devel (git-043a4c5808), Borealis, derived from Honeykrisp`, conformanceVersion `0.0.0.0` (not conformance-tested) | agent-run, 2026-11-15 |
| Full `vulkaninfo`: three queue families (graphics+compute+transfer+sparse, compute+transfer, transfer), 8 queues each; instance extensions include `VK_KHR_wayland_surface`; the Wayland surface lists 4 present modes | agent-run, 2026-11-15 |
| Zink on the native driver, off-screen: `zink Vulkan 1.4(Apple M5 Pro (G17S B1) (AURORA_BOREALIS))` | agent-run, docs/r3-gpu-result.md |
| No Vulkan client has drawn a frame: `vkcube` was not run (it opens a window on the owner's screen) | gap |
| The one zink desktop attempt ended black, run with `ASAHI_M5_BRINGUP=0`, so it proves nothing about zink | owner-observed, see docs/r3-gpu-result.md |
| Jens Axboe ran vkcube on the same stack on a K116s; linux #1173/#1650 are draft | upstream-reported |

`vulkaninfo` and `vkcube` are not installed on the Mac (`pacman -Q vulkan-tools` fails). The image
list should carry `vulkan-tools` (an image decision for the owner; this PR changes no package list).

## Check scripts

- `tests/hardware/k114s-vulkan-check.sh`: session environment, device and queue families without a
  window. `--vkcube` adds a 10 s vkcube run to watch. `--after-zink` expects the desktop on zink.
  Tested without hardware by `tests/hardware/test-vulkan-check.sh`.
- `tests/hardware/media-smoke.sh --vkcube` repeats the vkcube step within the wider media smoke test
  (a ten-line duplicate, left as is: the two scripts have different inputs and exit rules).

## Owner step 1: vkcube on the native desktop (no restart)

```
sudo pacman -S vulkan-tools      # or: run vkcube from a scratch unpack
bash tests/hardware/k114s-vulkan-check.sh --vkcube
```

Pass: all lines PASS and a cube spins on the panel for 10 s. If vkcube crashes or shows a black
window, copy the output and `journalctl --user -b | tail -50` into the issue.

## Owner step 2: the corrected zink retry on the desktop

The first attempt failed because the session still had `ASAHI_M5_BRINGUP=0` (the generator and uwsm
points in docs/r3-gpu-result.md, both fixed since). Today the opt-in file is empty (native driver) and
`ASAHI_M5_BRINGUP=1` comes from `/usr/lib/environment.d/90-omarchy-j714s-gpu.conf`; the generator
adds only `MESA_LOADER_DRIVER_OVERRIDE=zink` for a `zink` opt-in. On an r3 kernel the installed
guard is version 3 (`linux/r3a-trial/70-k114s-gpu-desktop`): it honours the base opt-in only when the
per-kernel opt-in `~/.config/k114s-gpu-desktop-r3a` (or `-r3b`) also exists. Do not run this retry
while a display-plan window (docs/r3-display-plan.md, D1 on) is open: a zink session would muddy
that evidence. Steps, with the owner at the Mac and the keyboard free in case the screen goes black.
The restart ends every process of the user, so save work first and start it from outside the
session, as docs/r3-gpu-result.md does:

```
echo zink > ~/.config/k114s-gpu-desktop
touch ~/.config/k114s-gpu-desktop-r3a            # or -r3b, matching the booted kernel
# timed fallback: empties the opt-in and restarts the desktop unless cancelled after a good login
sudo systemd-run --unit=k114s-zink-revert --on-active=230 sh -c ": > $HOME/.config/k114s-gpu-desktop; /usr/local/lib/omarchy-k114s/gpu-desktop-restart"
sudo systemd-run --no-block /usr/local/lib/omarchy-k114s/gpu-desktop-restart
# after logging in again, if the desktop is up, cancel the fallback:
sudo systemctl stop k114s-zink-revert.timer
bash tests/hardware/k114s-vulkan-check.sh --after-zink --vkcube
```

Rollback by hand: from a text console (Ctrl+Option+Fn+F2), log in, `: > ~/.config/k114s-gpu-desktop`,
then `sudo systemd-run --no-block /usr/local/lib/omarchy-k114s/gpu-desktop-restart`. If no console
answers, hold the power button and boot normally; the default entry is unchanged by this trial. After
a power cycle the opt-in still says `zink`: clear it (`: >`), and re-arm the GPU Stage 2 trial before
any display-plan step, because stage2-rearm skips a boot that was forced off.
Pass: the check ends "no FAIL", the desktop stays up for a few minutes and the cube spins. Zink
sits on Borealis, so a Mesa-side fault is for betizzel/mesa-aurora, not this repo.

## What is left

Owner steps 1 and 2, plus offline items still open for #26: a headless vkcube in a nested or
headless wlroots session, a compute-only Vulkan run (the script only checks that a graphics+compute
queue family exists), and `vulkan-tools` in the image list (owner decision). The upstream K116s comparison needs aurora-silicon's report text, which is
not in this repo. The issue stays open until a client has drawn.
