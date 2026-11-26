# r3b.c1: the panel colour description and an EDR brightness cap (issue #92)

2026-11-16. Evidence labels as in `docs/r3b-kernel.md`: **agent-run** (run on this Mac or in its build area),
**emulator/replica** (QEMU, stand-in headers), **read from source**, **owner-observed**. Sections 1 to 6 were written
before the boot. Section 7 records the owner session of 2026-11-16 that installed and booted r3b.c1 and ran the colour test.

## 1. What was wrong

Two things, both in `appledrm`, both found while explaining the black screens of the first DCP boots
(`docs/r3-display-d5-d9.md`, betizzel/omarchy-m5#21, aurora-silicon/linux#2060):

1. **The panel EDID had zero primaries.** The driver builds the internal panel's EDID itself. Firmware 27 publishes no
   chromaticities, so the primaries come from the colour target the ADT's `/product` `artwork-display-gamut` names. The
   driver knows only `P3` and `sRGB`. This Mac's ADT says `Rec2020` (agent-run, read-only, with a valid version-1
   `primary-calibration-matrix`), so there was no target and the EDID carried red, green and blue at (0, 0) with only the
   D65 white. Hyprland's colour management built a singular matrix from that, and every frame came out black
   (owner-observed; root cause read from source). The workaround on this Mac is colour management off, with the eDP-1
   preset `srgb` (`linux/display/k114s-dcp-colour`).
2. **Nothing capped EDR.** The ADT gives this panel a 2000-nit peak (`LmaxProduct`) and an EDR headroom up to 16
   (agent-run: kernel log `panel peak luminance 2000 nits (ADT)`, `panel EDR headroom up to 16.000`). Firmware 27 shows
   PQ content as EDR: each swap asks for SDR white times the headroom, up to that peak. The first PQ frame a compositor
   presents would start a ramp towards 2000 nits on the OLED. The path was validated upstream on the J714s (mini-LED)
   only. Today nothing on this Mac asks for PQ (colour management is off), so this is a guard for later, not a fix of
   something seen.

## 2. The fix: three patches on r3b.b1 (`patches/linux/r3b-c1.series`)

| Patch | What | Upstream |
| --- | --- | --- |
| `hdr/0001` | An internal panel whose ADT names no known gamut is described as **Display P3**: the space the driver already tags every untagged eDP RGB surface with (`iomfb_template.c`, P3-D65). The EDID and the surface tag then agree. `Rec2020` is not mapped to BT.2020 primaries, because the firmware is handed P3-tagged surfaces. One log line says so: `panel ADT: no known colour gamut, EDID primaries default to Display P3`. | offered (aurora-silicon/linux#2060) |
| `hdr/0002` | `fw27_panel_edr_max_nits`, a read-only `appledrm` parameter read when the DCP binds. It lowers the peak the driver accepts from the ADT. A cap at or below the panel's SDR maximum leaves no headroom: no peak, so the EDID advertises no PQ, PQ commits are refused and no swap carries an EDR step. Default 0 = the panel's own peak (unchanged behaviour). | offered, with 0001 |
| `hdr/0003` | K114s only: the default is **500**. With the SDR maximum of 1000 nits that means no EDR at all. SDR brightness is not affected. Raising it later: `appledrm.fw27_panel_edr_max_nits=N` on the command line or `options appledrm fw27_panel_edr_max_nits=N` in modprobe.d. | not for upstream |

With the cap in place, any EDR swap asks for at most SDR white or the capped peak, whichever is higher (KUnit
`edr_peak_bound_test`, below). On this Mac the cap turns EDR off rather than limiting it: the panel node of the running
device tree is enabled and carries `apple,max-brightness` 1000 (agent-run), and the driver reads it before the ADT peak
(`dcp.c`, the panel block of the probe; read from source), so `dcp_edr_peak(2000, 1000, 500)` is 0.

What changes for Hyprland after the boot (read from source, not seen): the EDID has Display P3 primaries, and no HDR
static metadata or BT.2020 colorimetry, because the panel has no peak. With colour management on, the `edid` preset then
converts into P3 instead of producing NaNs, so the panel should light. The `edid` preset is still labelled BT.2020 inside
Hyprland, so its "not 10-bit" warning can stay. The workaround in `monitors.lua` stays until the owner has seen the
panel with colour management on (section 6).

## 3. Proof (all offline)

| Check | Result | Label |
| --- | --- | --- |
| Build: `K114S_LABEL=K114S-R3B-C1 kmake O=build/r3b-c1 Image modules dtbs` from `src/r3b-c1` (r3b-b1 + hdr 0001-0003), the r3b.b1 `.config` unchanged | clean, no warning in `drivers/gpu/drm/apple` | agent-run |
| `k114s-cmp-modules build/r3b-c1` against the installed r3b.b1 | `DIFF(.text) appledrm.ko`, 1971 of 1972 SAME | agent-run |
| The three patch files reproduce the built tree (`git am` on r3b-b1's head `c492e07e75`) | same tree `ca972036c40e` | agent-run |
| `tests/brightness/run-dcp-backlight-host.sh src/r3b-c1` (the driver's own `dcp_backlight_test.c` compiled for the host) | 30 cases pass, including `edr_peak_test` and `edr_peak_bound_test`; both new cases fail with the cap removed | emulator/replica |
| KUnit in QEMU (section 4) | all 32 Apple display suites pass, 0 `not ok` in the whole run; without the P3 fallback `parser_panel_adt_color_target` fails | emulator/replica |
| `K114S_CAND=r3b-c1 makepkg`, then `check-package.sh` | all passed, including the brightness floor, the Display P3 default and the 500-nit cap (read from `appledrm.ko`) | agent-run |

Package (outside the repository, `$K114S_BUILD_ROOT/integrate/release-r3b-c1/`, with `SHA256SUMS`):
`linux-k114s-r3b-7.3.0.r3b.c1-1-aarch64.pkg.tar.zst`, sha256 `2d215627dd09f51689154f5ca9b140969cd9f0ceb828b00370cfcf35bf20e69c`.
The r3b.b1 package for the way back is `release-display-d5/pkg/linux-k114s-r3b-7.3.0.r3b.b1-1-aarch64.pkg.tar.zst`.

## 4. KUnit in QEMU

`build/r3b-c1-kunit` is the same tree with `CONFIG_KUNIT=y`, `DRM_APPLE_KUNIT_TEST=m`, `DRM_APPLE_DISPLAY_KUNIT_TEST=y`
and `DRM_APPLE_PARSER_KUNIT_TEST=y`. Loading `appledrm` and `dcp_backlight_test` in `k114s-qemu-smoke` runs their suites
(no Apple hardware is needed by these cases). Run with `k114s-qemu-smoke modules build/r3b-c1-kunit INIT`, where INIT
mounts the pseudo file systems, runs `modprobe appledrm` and `modprobe dcp_backlight_test`, and powers off (agent-run,
emulator/replica, 2026-11-16):

- All 32 suites of the Apple display driver pass, among them `apple-display-parser` 43 of 43 (with
  `parser_panel_color_target` and the extended `parser_panel_adt_color_target`) and `apple-dcp-backlight` 30 of 30 (with
  `edr_peak_test` and `edr_peak_bound_test`). The serial log has no `not ok` line at all (632 cases across the kernel's
  suites).
- Mutation: with `dcp_panel_color_target()` returning only the ADT's own space (the old behaviour), the same run gives
  `apple-display-parser: pass:42 fail:1`, `not ok 12 parser_panel_adt_color_target`. The cap's two cases fail without
  the cap in the host run (section 3).

## 5. Not verified

- Anything on the hardware: the new EDID on the panel, Hyprland with colour management on, the log lines. (Verified since,
  section 7.)
- Whether the firmware's P3-D65 surface tag means "shown unconverted" on this OLED. If the factory target is wider than
  P3, user space slightly under-uses the gamut, which is no worse than today.
- EDR itself on this panel, at any cap. The cap only removes or limits it.

## 6. For a session with the owner at the Mac (not before)

One install and one reboot, after the D6 VRR boot or instead of it, never unattended:

1. `sudo pacman -U .../release-r3b-c1/linux-k114s-r3b-7.3.0.r3b.c1-1-aarch64.pkg.tar.zst`: upgrades r3b.b1 in place and
   rebuilds `omarchy_linux-k114s-r3b.efi` (the default entry). Check G6 on the new image as after every UKI rebuild
   (`docs/r3-display-d5-d9.md`, F16): no `appledrm` in its initramfs.
2. Reboot with the owner watching. Expected: the desktop as today (colour management is still off).
3. Read-only: `journalctl -k -b | grep -E 'EDID primaries default|panel EDR off|panel peak'` shows the P3 line and
   `panel EDR off: cap 500 nits is not above the SDR maximum 1000 nits`; the connector EDID decodes with P3 primaries
   (about 0.680/0.320, 0.265/0.690, 0.150/0.060) and no HDR static metadata block.
4. Then the colour test the owner asked to watch, one preset at a time, each with the owner saying whether the panel
   stayed lit and how colours look: `bash linux/display/k114s-cm-trial edid`, then `dp3`, then `srgb` (TripleU613's
   question in betizzel/omarchy-m5#21). The script turns colour management on at runtime and schedules its own revert
   (20 s, a transient systemd user unit, so a black panel comes back even if the terminal goes) before it changes
   anything, then checks that the revert happened. If a preset stays lit and colours look right, make it the managed
   default through a repository PR and retire the workaround. On r3b.b1 (before step 1) only `srgb` and `dp3` are worth
   trying: `edid` is the zero-primaries case that blacks the panel.

Way back: the Limine menu's r3a entry (`Omarchy/linux-k114s`) boots as before; from there,
`sudo pacman -U .../release-display-d5/pkg/linux-k114s-r3b-7.3.0.r3b.b1-1-aarch64.pkg.tar.zst` restores r3b.b1.

## 7. The owner session, 2026-11-16: booted, and the colour test

The owner was at the Mac and watched every boot.

| Step | Result | Label |
| --- | --- | --- |
| Before: block P9 of `docs/r3-display-d5-d9.md` | holds | agent-run |
| `pacman -U` of the c1 package (sha256 `2d215627...`, `check-package.sh` all passed against `linux-aurora` and `linux-k114s`) | upgraded r3b.b1 in place; one UKI built (`linux-k114s-r3b`); the Stage 2 hook rewrote `boot-ctxr.bin` byte for byte (still the display file `90b35137...`); the r3a image unchanged; only the r3b image's hash and its `path:` line changed in `limine.conf` | agent-run |
| After: block P9, with G6 on both images | holds | agent-run |
| Reboot | the desktop came back at 3024x1986@120 (`uname -v` `K114S-R3B-C1`) | owner-observed |
| Kernel log | `panel ADT: no known colour gamut, EDID primaries default to Display P3` and `panel EDR off: cap 500 nits is not above the SDR maximum 1000 nits` | agent-run |
| eDP-1 EDID (`edid-decode`) | red 0.6796/0.3203, green 0.2646/0.6904, blue 0.1503/0.0595, white 0.3125/0.3291; no HDR static metadata, no colorimetry block | agent-run |
| `k114s-cm-trial edid`, then `dp3`, then `srgb` (colour management on, 20 s each) | all three: the panel stayed lit, colours normal; every revert verified | owner-observed |

So the zero-primaries black panel is fixed by `hdr/0001`, and colour management works on this panel with each preset.
The owner chose **colour management on with the eDP-1 preset `dp3`** as the managed default
(`linux/display/dcp-colour.lua`, installed by `k114s-dcp-colour`). `dp3` and not `edid`: `dp3` does not use the EDID's
primaries, so it does not depend on this kernel; `edid` blacks the panel on r3b.b1 (zero primaries), the way back of
section 6. `dp3` on r3b.b1 has not been watched. The greeter keeps its own guard (colour management off); it shows only the
login screen. HDR (PQ, EDR) stays off: the cap is in place and the EDID advertises no PQ.

Still open: EDR itself (a cap above 1000 nits, then a PQ test), and whether the firmware shows P3-tagged surfaces
unconverted on this OLED (section 5).

## 8. The next owner session: a watched EDR test (not unattended)

Goal: the first HDR (PQ) picture on this OLED, with the peak held well under the panel's 2000 nits. Every step is
watched by the owner. The way back is one file and one reboot. It runs on r3b.c2 or r3b.c3 (they carry the same cap);
`linux/display/k114s-cm-trial` has the `hdr` and `hdredid` presets for it since r3b.c3's PR.

**E1. Raise the cap to 1200 nits (one boot).**
```
printf '%s\n' '# K114s EDR test (docs/r3-hdr.md section 8): remove after the test' 'options appledrm fw27_panel_edr_max_nits=1200' | sudo tee /etc/modprobe.d/k114s-edr-trial.conf >/dev/null
modprobe -c | grep fw27_panel_edr_max_nits       # options appledrm fw27_panel_edr_max_nits=1200
```
appledrm is not in the initramfs (G6), so this applies at the next boot. Reboot with the owner watching. SDR should look
as before.

**E2. Read-only, after the boot.**
- `journalctl -k -b | grep -E 'panel peak|EDR capped|EDR off|EDR headroom'` should show `panel peak luminance 2000 nits
  (ADT)` and `panel EDR capped at 1200 nits`.
- `edid-decode` of the eDP-1 EDID should now have an HDR static metadata block (PQ, a maximum near 1200 nits) beside the
  P3 primaries.
- `cat /sys/module/appledrm/parameters/fw27_panel_edr_max_nits` reads 1200.

**E3. Hyprland HDR, 20 s at a time, each with its revert scheduled first.**
1. `bash linux/display/k114s-cm-trial hdredid 20`: the desktop with HDR output, using the EDID's luminance. The owner
   watches whether the panel stays lit, whether SDR content keeps its brightness and colours, and whether there is a flash
   or a slow ramp in brightness.
2. If step 1 is fine, make a real PQ test clip first. Relabelling an SDR pattern with mpv's `format` filter only changes
   its tags, so it says nothing about EDR (#163). Instead, encode one with known levels: `testsrc2`'s white mapped to
   1000 nits, inside the 1200-nit cap:
   ```
   ffmpeg -f lavfi -i testsrc2=size=1280x720:rate=60:duration=20 \
     -vf "zscale=transferin=bt709:primariesin=bt709:matrixin=bt709:transfer=smpte2084:primaries=bt2020:matrix=bt2020nc:npl=1000,format=yuv420p10le" \
     -c:v ffv1 -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc "$(mktemp -d)/pq-1000.mkv"
   ```
   (FFV1 because this Mac's libx265 is 8-bit only. `ffprobe` of the file says `yuv420p10le`, `smpte2084`, `bt2020`;
   agent-run, 2026-11-16.)
   Then run `bash linux/display/k114s-cm-trial hdredid 60`, and while it runs play that file in a window (not full screen)
   with `mpv --no-config --vo=gpu-next --target-colorspace-hint=yes <file>`.
   The clip's white should look clearly brighter than the desktop's SDR white, and nothing else on the
   panel should change.
3. `bash linux/display/k114s-cm-trial hdr 20`, the same as step 1 with Hyprland's own HDR luminance.

Stop at the first black panel, flicker, brightness pumping or `DCP has crashed`. The revert brings colour management
off and sRGB. After a DCP crash a reboot restores the panel; then do E4.

**E4. The way back:** `sudo rm /etc/modprobe.d/k114s-edr-trial.conf` and reboot. The log then says `panel EDR off: cap
500 nits is not above the SDR maximum 1000 nits` again.

What the test cannot show: the panel's real luminance (no meter), or whether the firmware tone-maps above the cap. Write
down only what the owner saw.

## 9. The EDR test, 2026-11-16: run, and HDR made the default

Run on r3b.c3 with the owner watching. The boot combined E1 with the VRR way back (`docs/r3-vrr.md` section 7); the cap
was the only new setting.

| Step | Result | Label |
| --- | --- | --- |
| E1: `/etc/modprobe.d/k114s-edr-trial.conf` with `fw27_panel_edr_max_nits=1200`, one reboot | the desktop came back at 3024x1986@120 | owner-observed |
| E2: kernel log | `panel peak luminance 2000 nits (ADT)`, `panel EDR capped at 1200 nits`, `panel EDR headroom up to 16.000`, and the P3 line | agent-run |
| E2: `edid-decode` of the eDP-1 EDID | an HDR static metadata block: SDR and SMPTE ST2084, desired content maximum 147 (1207.332 cd/m²), beside the P3 primaries | agent-run |
| E3.1: `k114s-cm-trial hdredid 20` | the trial took effect (`colorManagementPreset hdredid`). The first run went unwatched; on the second the owner saw it stay lit and look normal. Every revert was verified | owner-observed |
| E3.2: the 10-bit PQ clip (white at 1000 nits) in a window during `k114s-cm-trial hdredid 45` | "Test looks good"; mpv `VO: [gpu-next] 1280x720 yuv420p10`; no DCP crash | owner-observed |

The owner asked to keep `hdredid` after E3.2, so **HDR became the default on 2026-11-16**.
The local override below later switched the desktop back to SDR Display P3.

- `linux/display/k114s-edr-cap` installs `/etc/modprobe.d/k114s-edr-cap.conf` (the 1200-nit cap) and removes the
  one-boot test file. It refuses while any other modprobe file sets the cap. `--check` also fails then, and on this Mac it
  requires `modprobe -c` to read exactly one cap, 1200. `--undo` is there too.
- The managed colour block (`dcp-colour.lua`) picks `hdredid` when appledrm's cap is above the 1000-nit SDR maximum or 0, and
  `dp3` otherwise. It reads the cap from `/sys/module/appledrm/parameters/fw27_panel_edr_max_nits`. That works in Hyprland's
  Lua (agent-run: `io.open` read 1200). So the same block is right on a kernel without EDR, and on r3b.b1.
- The way back: `sudo bash linux/display/k114s-edr-cap --undo`, then a reboot. The block then falls back to `dp3` by
  itself.

Not measured: the panel's real luminance (no meter), whether the firmware tone-maps above the cap, and the power cost of
HDR output.


### Local SDR Display P3 override

The live `~/.config/hypr/monitors.lua` has a rule after the managed block that sets `eDP-1`
to 10-bit `dp3` and disables automatic HDR (`render:cm_auto_hdr=0`). Its comment records the
reason: fullscreen HDR washed out the panel. The file's last modification was 2026-11-23.
Its Git history is unavailable, so the exact activation time is unverified. Pacman's log
records Omarchy updates that day. The display settings code saves mode, position, scale and
rotation, and the local monitor rule sets colour.

On 2026-11-26, `hyprctl monitors -j` reported `dp3` and `XRGB2101010` on `eDP-1`, and
`hyprctl getoption render:cm_auto_hdr` returned 0. `bash linux/display/k114s-edr-cap --check`
reported a running `appledrm` cap of 1200 nits. The boot journal confirmed active EDR
headroom in the driver. Hyprland sends SDR Display P3 on the built-in panel.


## 10. 10-bit output, 2026-11-16

With either wide-gamut preset on an 8-bit framebuffer, Hyprland showed "Monitor eDP-1: wide color gamut is enabled but the
display is not in 10-bit mode" at every session start (owner report). Hyprland has no option that silences it, and the
driver can do better: on firmware 27 appledrm offers `XR30` and `AR30` (XRGB/ARGB2101010) on the primary plane
(`modetest -M apple -p`, agent-run; `drivers/gpu/drm/apple/plane.c`, `supports_l10r` is false only for 12.x firmware).

| Check | Result | Label |
| --- | --- | --- |
| A 45-second self-reverting runtime trial on r3b.c4: eDP-1 with `cm = "hdredid", bitdepth = 10` through `hyprctl eval`, the revert (`hyprctl reload`) scheduled first as its own user unit | `currentFormat: XRGB2101010`; aquamarine allocated `XR30` buffers; no DCP crash or error line in the kernel log | agent-run |
| The owner watching the panel during the trial | "Looked normal, keep it" | owner-observed |

So `linux/display/dcp-colour.lua` now asks for `bitdepth = 10` on the eDP-1 rule, for both presets. The trial covered
hdredid only. dp3 changes Hyprland's colour transform, not the scanout format. Install it with
`bash "$REPO/linux/display/k114s-dcp-colour"`, then `hyprctl reload`; the warning is gone at the next session start.
The way back is the previous block (the script replaces a changed block) or a rule without `bitdepth`.
