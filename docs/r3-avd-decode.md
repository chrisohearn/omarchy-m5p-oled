# Hardware video decode (AVD) on the K114s: trial plan and mpv decision (issue #30)

Status 2026-11-17: the trial tree is built and checked offline (section "The trial tree"); the one-boot trial has
not run yet. Before that (2026-11-15): the device-tree fragment `dts/t6050-k114s-avd.dtsi` and its ADT check are in
[r3-parity-drafts.md](r3-parity-drafts.md) (PR #83). This page adds the decode test and the mpv decision.

## The trial tree (2026-11-17)

`dts/t6050-k114s-r3b-avd.dts` is the configured sound tree (`t6050-k114s-r3b-sound.dts`, docs/r3-mics.md) plus the
AVD fragment switched on (`K114S_R3_AVD`). It replaces the 2026-11-15 plan of an AVD-only tree on the old GPU tree,
because the configured boot is now the sound tree and a trial should differ from it by the fragment alone. The
fragment touches no pin, so the sound tree's pins and speaker barriers stand.

| Check | Result | Label |
| --- | --- | --- |
| Control: the sound tree on P's includes, with this Mac's PMP values | `de9fa4b6…`, the pinned tree, byte for byte | agent-run |
| The AVD tree on the same includes | `ee8ec11a296017443095a59a4df942ac794519b2cf5f770c79c93d9bfa62307e`, 148,208 bytes, no dtc warning | agent-run |
| `tests/dtb-node-diff.py` sound against AVD | no node added; status okay on `avd@2309080000`, its DART `iommu@2309020000`, `pmgr4` (`power-management@2380600000`) and its power states `1b0` (FAB1_SOC, now `apple,always-on`) and `1d8` (AVD_SYS) | agent-run |
| `lint-sound-dtb.py`, `lint-dtb.py`, `lint-display-gpu-dtb.py` | all pass (AP pins 80, 134, 138, 139 as in the sound tree) | agent-run |
| `sudo python3 -I tests/k114s-adt-parity-facts.py avd=…` | every fact holds (registers, interrupts, power-state offsets and parents); the psreg-to-reg[46] step stays upstream's | agent-run |
| `sudo python3 -I tests/k114s-adt-touchid-facts.py` on the AVD tree | every fact holds | agent-run |
| Drivers in the running kernel (r3b.c4) | `apple_avd` (`apple,t6050-avd`); the DART and the power states are built in | agent-run |
| `build/make-stage2.sh` with the pin loader (control: sound tree) | `0990b168…`, the configured `m1n1/boot-ctxr.bin`, byte for byte | agent-run |
| The same with the AVD tree | `boot-ctxr-avd.bin` `7fa59a2a8edd010b5bc710323be726eb7eedee1f5149101994d3ee7f156c1f37`, 4,545,450 bytes | agent-run |

**The VA-API driver name.** libva chooses its driver from the DRM driver's name. On the M5 GPU that is `aurora`, and
no `aurora_drv_video.so` exists: `libva-v4l2_request-avd` installs `asahi_drv_video.so` and
`v4l2_request_drv_video.so` (agent-run: `/usr/lib/dri`). A VA-API client without `LIBVA_DRIVER_NAME` therefore finds
no driver, even with the decoder up. betizzel/omarchy-m5 fixed this with a symlink inside
`omarchy-aurora-firmware` j714s14 (tested on the J714s: 60 of 60 frames bit-identical). That package is held here at
an older release, and an unowned file of the same name would make its update fail. So `linux/media/k114s-vaapi`
installs `/etc/environment.d/50-k114s-vaapi.conf` with `LIBVA_DRIVER_NAME=asahi` instead; the user manager reads it
at login (`tests/linux/test-vaapi.sh`, 10 checks, replica). `tests/hardware/k114s-avd-decode-test.sh` sets its own
variable (default `v4l2_request`); the trial runs it with both names.

**Not in the installed kernel:** aurora-silicon/linux #1936 (merged 2026-11-15, ring-wrap arithmetic). By its own
estimate it matters after about 20 hours of 60 fps playback, or 1.7 hours of flat-out 4K decoding, with no idle
autosuspend in between (the counters restart at each firmware boot). It is not reproduced on any device. It goes
into the next kernel candidate.

## Facts read today (agent-run, read-only)

| Fact | Result |
|---|---|
| Running kernel config | `CONFIG_VIDEO_APPLE_AVD=m` |
| Booted tree | has the `avd@2309080000` node under the SoC bus (the base's disabled node); no `/dev/video*`, no `/dev/media*` |
| Userland | `avd-fw` 0.1-1 and `libva-v4l2_request-avd` 1.3.r11 installed; the driver file `v4l2_request_drv_video.so` is in the libva directory |
| ffmpeg 9.0.2 | lists the `vaapi` hwaccel; encoders libx264, libx265 and libvpx-vp9 exist, so the test can build its own clips |
| `/etc/mpv/mpv.conf` | byte-identical (`cmp`) to `/usr/share/omarchy-mac/mpv/mpv.conf` (`hwdec=vaapi-copy`, `hwdec-codecs=h264,hevc,vp9`, `vo=gpu`, `gpu-api=opengl`, `gpu-sw=yes`); no package owns it |
| mpv 0.41 with that file, no decoder | prints `[vaapi] Failed to initialize VAAPI`, decodes in software, plays to the end, exit 0 |

## mpv default: decision

The issue text (and the audit row for #63) say the file is `hwdec=auto-safe`. That is out of date: the file on this
Mac is now the omarchy-mac Apple default, so no change is needed to ship it. Because mpv falls back to software when
VAAPI does not initialise, the default is harmless on a boot without the decoder. Decision: keep the Apple default
as it is. Do not add anything of ours to it. `hwdec=vaapi-copy` only becomes true hardware decode once the AVD tree is
the default boot and the test below passes. Zero-copy `hwdec=vaapi` stays off (omarchy-mac documents the green-frame
problem with gpu-next on Asahi; unverified on the M5).

## Owner steps (the boot trial is the owner's)

1. Build a trial tree from the proven configuration P's `t6050-k114s-r3-gpu.dts` with `K114S_R3_AVD` defined (AVD
   alone), with `build/make-stage2.sh`, in its own worktree. Boot it as one `aura-try` boot, with the checks of
   [r3-display-plan.md](r3-display-plan.md) section 4.2 and the way back of 4.3. No standing `stage2-trial` re-arm
   exists (4.1 rule 3). Run it only before the display window opens (D1) or after it closes (4.4), never inside it.
   Its Stage 2 file counts against the two-trial-file ESP budget (G2).
2. After the boot, no root needed:
   `bash tests/hardware/k114s-parity-check.sh avd` (node okay, `/dev/video*`, `/dev/media*`, driver, dmesg).
   If the module is not loaded, `sudo modprobe apple_avd` (check `modinfo` for the exact name first).
3. `bash tests/hardware/k114s-avd-decode-test.sh` prints PASS per codec when hardware frames equal software
   frames at 1080p. Optional: `AVD_SIZE=3024x1964 ...` for a size above 1080p (upstream: untested; the ring-wrap fix #1936 merged 2026-11-15 and is not in the installed base).
4. Play one real H.264 or HEVC file in mpv and say whether it looks right and does not stutter.
5. Report the outcome on #30. A pass moves the matrix row to "boot-tested"; only then is the AVD fragment a
   candidate for the default tree.

`bash tests/hardware/k114s-avd-decode-test.sh --software-only` runs on any boot and proves the script itself
(clip, software md5). It was run today at 640x360: all three codecs produce an md5, exit 0. On the current boot
without `--software-only` it prints SKIP (no `/dev/media*`) and exits 3.

## Not done and why

- Boot trial and playback judgement: owner at the Mac.
- The base's psreg-to-reg[46] mapping for pmgr4: upstream's step, not derivable from the ADT.
- 10-bit HEVC (#1995) and above 1080p: untested upstream.
