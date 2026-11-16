# VRR on the K114s OLED: why D6 crashed the DCP, and the next test (r3b.c3)

2026-11-16. Evidence labels as in `docs/r3b-kernel.md`: **agent-run**, **read from source**, **from the log** (the kernel
log of the D6 boot, kept root-only as `$D/D6-dcp-crash-20261116-123243.log`), **owner-observed**, **inference**. The D6 run
itself is in `docs/r3-display-d5-d9.md` 4c. Nothing in sections 2 to 4 has been booted.

## 1. What happened (D6, r3b.c1, 2026-11-16)

With the mask out (`fw27_panel_vrr=1`) the boot was clean: `vrr_capable` 1, and the DCP's `set_digital_out_mode() ...
vrr:1` at boot answered `Already set to timingID: 2 colorID: 1` (no real modeset). Turning `misc:vrr` on in Hyprland
blacked the panel at once (owner-observed). From the log:

1. The driver: `VRR_ENABLED 1: selecting "3024x1986": 120 ... again`, then `set_digital_out_mode` with vrr:1 and
   `IOMFBParameter_adaptive_sync Req minRR = 0x180000` (24.0 Hz in 16.16).
2. The firmware did a full modeset this time: power on to off, link shut down, `mode_set_gated: 3024x1986@120 Hz DSC=NO
   VRR=YES`, power off to on, then the M3 HALs reloaded (LTM, RCA, APT). `ERB ... v_blank = 3`, against 862 at boot. A
   `DPTXController ... FIFO error interrupt` came during the relink.
3. About 0.6 s later, right after `UPTSQManager ... clearing M3 reset`: `RTKit: co-processor has crashed`, with the
   crashlog line **`apt firmware: video_mode_main_init.c:288 main_init()`**. Then `DCP has crashed`, `a reboot is required
   to restore the display`, and the timeouts.

So the APT M3 firmware (adaptive pixel timing) asserts in its own init during the modeset that applies the new minimum.

## 2. What the driver does (read from source, `drivers/gpu/drm/apple`, r3b.c2)

- `dcp_fw27_vrr_switch()` (`iomfb.c`) handles `VRR_ENABLED` on the firmware 27 panel by invalidating the mode and
  selecting it again (`dcp_crtc_atomic_modeset()` → `iomfb_modeset_v27`). That sends `IOMFBParameter_adaptive_sync`
  (parameter 15) with the mode's minimum, and then `set_digital_out_mode`. The source comment says firmware 27 writes the
  adaptive-sync range into the timing generator when a mode is selected. That was measured on the J716s LCD, not here.
- **The 24 Hz minimum is the driver's guess.** The firmware reports this panel's 120 Hz timing with both range fields
  zero. `dcp_refresh_range()` (`dcp-refresh.h`) then substitutes 24 Hz to the mode's rate for an internal ProMotion timing.
  The connector's `monitor_range` and parameter 15 both come from that.
- The K114s ADT has no refresh-range, VRR or ProMotion property for the panel (agent-run, read-only). It does have
  `/arm-io/disp0 supports-apt = 1` and `/product oled-display = 1`.
- A Hyprland DPMS off and on is not a firmware power cycle here. In D7's boot (2026-11-15 23:08) each DPMS on logged
  `Already set to timingID: 2` and no power on to off or APT reload (agent-run, journal). So D7's three off/on cycles
  say nothing about a runtime modeset.

## 3. Two explanations left

| | Hypothesis | For it | Against it, or open |
| --- | --- | --- | --- |
| H1 | No real runtime modeset survives on this OLED with firmware 27.2, VRR or not | aurora-silicon/linux#1868: a K114c (OLED) 60 Hz modeset with `VRR=NO` also crashed the DCP; no runtime `mode_set_gated` has been seen to work on a K-board | #1868 has no crashlog line, so it is not tied to the same assertion |
| H2 | The OLED's APT firmware rejects the 24 Hz minimum | 24 Hz is a constant from an LCD; the crash is in the VRR-timing init; the firmware never offered a minimum | Not yet separated from H1 |

The double APT DMem load (0x68d0 then 0x60b8) is not the cause: the boot load has the same pair and that boot works.

## 4. The test kernel: r3b.c3

`patches/linux/r3b-c3.series` adds `vrr/0001` to r3b.c2: `appledrm.fw27_panel_vrr_min`.
- It is read-only, takes Hz, and defaults to 24, so behaviour is unchanged by default.
- It sets the fallback minimum, which reaches both the connector's range and parameter 15. At or above the mode's rate no
  range is offered, so `vrr_capable` stays 0.
- KUnit covers it (`dcp_refresh_range_test`: 48, 1, 120 and a reported range winning over the fallback), and every
  Apple display suite passes in QEMU (`docs/r3b-kernel.md` section 11).

r3b.c3 also carries `hdr/0004`, the EDR cap in the form offered upstream (no change on this Mac). The package is
`$K114S_BUILD_ROOT/integrate/release-r3b-c3/`, with `SHA256SUMS`.

## 5. The next owner session: one watched VRR test (not unattended)

A DCP crash costs one reboot, with the panel black until it. **The owner watches every step.** Variables as in
`docs/r3-display-d5-d9.md` section 3 (`D`, `REPO`).

**V1. Install r3b.c3 and arm the test in one boot.** Today's D6 boot shows that a boot with `fw27_panel_vrr=1` is clean;
only the runtime toggle crashed. So install and arm, then reboot once:
1. Block P9.
2. Install the package as r3b.c2 was installed: `sha256sum` against `SHA256SUMS`, `check-package.sh` with
   `K114S_CAND=r3b-c3` against `linux-aurora` and `linux-k114s`, `pacman -U`. Expect exactly one `Building UKI for
   linux-k114s-r3b` line, `boot-ctxr.bin` still the display file, the r3a image unchanged.
3. Block P9 again.
4. Arm (a subshell: any STOP leaves the mask in place and changes nothing):
   ```
   (
   m=/etc/modprobe.d/aurora-m5-vrr.conf; c="$D/aurora-m5-vrr.conf.masked"
   stop() { echo "STOP: $*"; exit 1; }
   grep -q -x 'options appledrm fw27_panel_vrr=0' $m || stop "$m is not the mask (read it); nothing changed"
   sudo cp -p $m "$c" && sudo cmp -s $m "$c" || stop "no verified copy of the mask in $c; nothing changed"
   printf '%s\n' '# K114s VRR test (docs/r3-vrr.md V1): one boot, the owner watching' 'options appledrm fw27_panel_vrr=1 fw27_panel_vrr_min=48' | sudo tee $m >/dev/null
   [ "$(modprobe -c | grep -c -E '^options appledrm fw27_panel_vrr=1 fw27_panel_vrr_min=48$')" = 1 ] && [ "$(modprobe -c | grep -c -E '^options appledrm fw27_panel_vrr=0')" = 0 ] ||
     { sudo cp -p "$c" $m; stop "modprobe does not read the test options: the mask is back"; }
   echo "V1 armed: the next boot offers VRR with a 48 Hz minimum; the way back is V3"
   )
   ```
   Expect the last line.
5. Reboot with the owner watching.

**V2. After the boot.**
- `cat /sys/module/appledrm/parameters/fw27_panel_vrr_min` reads 48.
- `modetest -M apple -c` shows `vrr_capable` value 1.
- Hyprland reports eDP-1 at 120 Hz with `vrr` false.
- Then run the D6 block of `docs/r3-display-d5-d9.md`, without its `T4-booted` guard: the brightness ladder, `misc:vrr`
  on under mpv for 20 s, then off, the watchdog and crash lines. The owner says whether the panel stayed lit and whether it
  flickered.

| Result | Reading | Next |
| --- | --- | --- |
| Lit, no crash, `VRR_ENABLED` line, no watchdog line | H2: 24 Hz was the problem | Keep 48 (the mask file stays as V1 wrote it), report on betizzel/omarchy-m5#25 and aurora; later try lower minimums, one boot each |
| `DCP has crashed` again with `video_mode_main_init.c:288` | H1 is likely: no runtime modeset survives | Reboot with the mask back (V3). VRR needs a live switch with no modeset (F2 below), or stays off |
| Crash with a different line | New evidence | Mask back (V3), keep the log root-only in `$D`, compare |

**V3. The way back** (after any crash, or to end the test):
`sudo cp -p "$D/aurora-m5-vrr.conf.masked" /etc/modprobe.d/aurora-m5-vrr.conf`, check that `modprobe -c` shows
`fw27_panel_vrr=0`, then reboot. The r3b.c2 package (`integrate/release-r3b-c2/`) or the r3a entry is the kernel way back.

## 6. If H1 holds: what would come next (not built)

- **F2.** In `dcp_fw27_vrr_switch()`, send parameter 15 live without the reselect, as the desktop 26.6 panel's
  `dcp_vrr_update` does. Install the VRR timing at the first modeset instead. The risk: firmware 27.2 may ignore a live
  minimum.
- **F3.** Send the full sequence a macOS 27 trace shows around a VRR modeset (aurora-silicon/linux#1613: parameter 0x1f,
  A449, parameters 3 and 6, A453). That trace is from an external display.
- **Containment upstream:** offer VRR on LCD boards only, or refuse it on OLED panels (`supports-apt` with
  `oled-display`). Suggested on betizzel/omarchy-m5#25.
