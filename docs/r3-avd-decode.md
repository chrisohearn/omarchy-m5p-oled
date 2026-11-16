# Hardware video decode (AVD) on the K114s: trial plan and mpv decision (issue #30)

Status 2026-11-15. The device-tree fragment `dts/t6050-k114s-avd.dtsi` and its ADT check are in
[r3-parity-drafts.md](r3-parity-drafts.md) (PR #83). This page adds the decode test and the mpv decision.

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
