# Camera (Apple ISP) for the K114s (#33)

Status: **loader row, device-tree fragment and ADT checker written; nothing booted.** Written 2026-11-15 on
the K114s (kernel `7.3.0-17.v272-4-k114s-r3a-ARCH`), owner away. Evidence labels: agent-run,
upstream-reported. Display work (DCP hand-off) is separate and not touched.

## What was found

Live state (agent-run): `CONFIG_VIDEO_APPLE_ISP=m`; `/lib/firmware/apple` has the six `isp_*.dat` files; the
live device tree has `/soc/isp@580000000` (`apple,t6050-isp`) with `status = "disabled"`, no
`memory-region`, no `apple,platform-id`, and no `isp` alias; `/dev/video*` and `/dev/media*` do not exist; the
loader log (`aura_stage2.log`) has no ISP hand-off line at all, only `dapf: Initialized /arm-io/dart-isp0`.
Without an `isp` alias the loader's `dt_set_t6050_isp()` returns silently before it reads the board table.

ADT (agent-run: `sudo python3 -I tests/k114s-adt-camera-facts.py`, read-only: 23 shared facts, the sensor type, and the loader gate, including the OS firmware key):

| | K114s (ADT of the 27.2 stub) | K116s (aura #188, linux #1648) | K114c (linux #1756) |
| --- | --- | --- | --- |
| `isp0` `sensor-type` | **0xba** | 0xbc | 0xb9 |
| firmware uuid | `980F533B-34EA-3FBA-878C-809F6AF57345` | same | not stated |
| `cam-connections-scheme` | 0x10 | 0x10 | 0x10 |
| `isp0` windows, interrupts | `0x580000000` +0x3ff0000, `0x280900000` +0x3f4; 513 to 516, 526 | same | same |
| `dart-isp0` | 3 instances `0x5828c0000/e0000/900000`, dapf `0x5828d0000`, irq 531, sid 0 and 12, exclave 4 5 8 9, remap 1 6 7 10 11 | same | same |
| pmgr | FAB9_SOC 0x398, ISP_SYS 0x3a0, ISPSENS0 0x100 | same | same |
| firmware segments | two: text 0xc1c000 and data 0x13d0000 bytes, iova 0 and 0xc1c000, remap `0x10000000000` and `0x10000c1c000` | same | same layout |
| `isp0` children (sensor nodes) | none | none | none |

So the K114s equals the K116s in everything except the sensor type. The same ADT, replayed through the
loader's gate (the OS firmware key, `t6050_isp_segments_valid` and the layout checks of aura `dt_set_t6050_isp`), passes with a
K114s row of 0xba and is refused with the K114c row (0xb9) or the K116s one (0xbc): that is why a row of
its own is needed. The segment addresses (`0x1000109c000`, `0x100026a0000`) are placed by iBoot and move
after an update, so the loader reads them at boot; no tree here carries them. The ADT has no
camera-light GPIO (`eic` `cil` 1, `mil` 1, no `cil-gpio-offset`), same as the K114c. The table's firmware key is the OS firmware (`/chosen` `firmware-version`, aura `os_firmware`), which must be
`mBoot-20457.41.3` (V27_2); the checker requires it and refuses any other. The system firmware
(`system-firmware-version`, `mBoot-20457.60.65.0.1`, the 27.3 beta 1 system iBoot, V27_3B) is a different
property and is not part of the key; the K116s's value is not recorded upstream, so it is not compared.

## What was added

| File | What |
| --- | --- |
| `patches/aura/camera/0001-kboot-T6050-hand-the-K114s-camera-over-on-27.2.patch` | one table row, `{"apple,k114s", 0xba, V27_2}`, plus comments. Applies with `git am` on the loader base this repository builds: aura `22b71758` + betizzel's seven patches (`build/native/setup.sh`) + `patches/aura/0001-0003`, checked as the whole series; not built (no aarch64 build host here). It lives in its own folder so the display recipe's `git am patches/aura/*.patch` (docs/r3-display-gpu.md) stays the display loader and the D-series binary stays reproducible |
| `dts/t6050-k114s-isp.dtsi` | draft, off by default (`K114S_R3_ISP`), not included by any tree: includes the base tree's `t6050-j716c-isp.dtsi`, as the K116s tree does. Not compiled: this host has no `dtc` and no kernel tree |
| `tests/k114s-adt-camera-facts.py` | reads the ADT (root, read-only, or `--adt FILE`), compares with the K116s values, replays the loader gate |
| `tests/test-adt-camera-facts.py` | replica test: a made-up ADT from the public K116s values passes; wrong sensor type, interrupt, power-state offset, segment address and layout fail. No Apple data |
| `tests/hardware/k114s-camera-check.sh` | read-only report to run after a trial boot; `--capture` takes one libcamera frame |

Tests run: `git am` of betizzel's seven, `patches/aura/0001-0003` and `patches/aura/camera/0001` in order on aura `22b71758` (applies); `python3 tests/test-adt-camera-facts.py` (all ok, with a planted serial number and MAC address), `python3 -I tests/k114s-adt-camera-facts.py` on this Mac (exit 0).
The camera trial loader is the r3 loader (`patches/aura/0001-0003`) plus `patches/aura/camera/0001`, built as its own Stage 2
variant or `aura-try` image, never folded into a display trial. Not run: a DTS compile and `tests/lint-dtb.py` of the new fragment (no `dtc`); the aura build; the KUnit
case of linux #1831 (no build host).

## Open

- **Sensor preset.** `t6050-j716c-isp.dtsi` describes preset 0 as config-index 5, input 1920x2160 (J716c, K116s
  boot-tested by Jens Axboe). The K114c needed config-index 6, input 3040x2880 and a crop (linux #1756, booted). Which one
  the K114s's IMX958 uses is not in the ADT. Expect to try the K116s one first.
- **Kernel 27.2 parser.** linux #1831 (draft, `ISP_FIRMWARE_V_27_2`) is not in our kernel: the driver would read the
  27.2 firmware as UNKNOWN and send the 12.x set-file record. It must be backported with the fragment.
- **Firmware files.** The six `isp_*.dat` files in `/lib/firmware/apple` were not matched against the 27.2 firmware
  (uuid above) here: that needs the owner's extraction step, not done.
- **Camera indicator.** The K114c node sets `apple,camera-indicator = <&dcp>` (linux #1744). That needs the DCP, which is not
  handed over yet; the fragment leaves it out. The indicator light is therefore not expected to work.
- **Order.** The ISP needs a booting tree that arms the loader; the display hand-off trials (D1 to D9) are in other worktrees.
  Do the camera as its own one-boot trial after them, so a coprocessor hang is attributable.

## Needs the owner at the Mac

1. Build a tree with `#define K114S_R3_ISP` and `#include "t6050-k114s-isp.dtsi"` after `t6050-k114s-common.dtsi`, a loader
   with `patches/aura/camera/0001`, and a kernel with linux #1831. Boot it as a one-boot trial (docs/r3-gpu-result.md). A coprocessor
   hang needs a forced power-off.
2. Afterwards: `bash tests/hardware/k114s-camera-check.sh --capture`, then open the frame and say what you see.
3. Say whether the picture is the right way up and framed (the preset question above).

## Proposed index rows (not edited here)

- `docs/matrix.md` Camera row: Status `evaluated` stays. Evidence: "ADT checked (agent-run 2026-11-15): K114s equals the K116s in
  every camera value except the sensor type 0xba; loader row written (patches/aura/camera/0001), DTS fragment drafted
  (dts/t6050-k114s-isp.dtsi), neither booted". Next: "own one-boot trial after the display hand-off; needs linux #1831".
  Note: "Loader row is K116s-gated" becomes "K114s row 0xba in patches/aura/camera/0001".
- Parity map: #33 `offline-ok` part done; `needs-owner-at-mac` part remains.
