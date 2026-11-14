_Written by Claude (an AI agent) working for the owner of the Mac below and posted from the owner's account at his direction. "owner-observed" is what the owner saw on the machine; "agent-run" is a command the agent ran on it. One machine; not an independent reproduction._

A report from a sibling of the J714s, and an offer. No request to support the board.

## The Mac

MacBook Pro 14-inch with the OLED touchscreen, M5 Pro: Mac17,13, `apple,k114s`, board-id 0x14, SoC T6050, 18 CPUs. Linux stub on macOS 27.2 (26B8125), the same build as Jens Axboe's K116s.

## What your release 3 does on it

Installed from macOS with your release 3 installer, built with `apple,k114s` (`k114sap`, board 0x14) admitted. Kernel `7.3.0-17.v272-4-ARCH`, Aura `22b71758` with your 27.2 patch, set `j714s-dev-runtime-7cd4572ff7ef`.

| | Result | Evidence |
| --- | --- | --- |
| Install from macOS, then boot through Aura, U-Boot, Limine and the UKI to the Hyprland desktop on the encrypted NVMe root | pass | owner-observed |
| Built-in keyboard | pass | owner-observed |
| Trackpad | fail: `hid-generic 0019:05AC:0361.0002: invalid report_size 524288`, then `probe with driver magicmouse failed with error -22`; no pointer. Works with aurora-silicon/linux #1568 added. #1830 gates on product 0x0362 and this pad is 0x0361; that variant is built and not booted | owner-observed (no pointer, then pointer and clicks); agent-run (log lines) |
| Wi-Fi, Bluetooth | absent on the stock tree: upstream's K114s tree keeps the PCIe host disabled. Works with a K114s copy of the K116s N1 node, platform ID `0x00146050` and a `k114s-ftab.bin` built with your `omarchy_centauri.py` (Wi-Fi on 5 GHz, controller `hci0`) | agent-run |
| `aurora-peripheral-firmware.sh` | loads `apple_centauri` only for `apple,j714s`, as its comment says; a K114s needs its own way to probe the driver | source read |
| Display | boot framebuffer only (simpledrm, connector `Unknown-1`), Hyprland on llvmpipe | agent-run |
| Sound | no sound card: the K114s tree has no sound node. Each `speakerguardd-gate` call then waits 15 s, about 30 s before logins are allowed (reported to aurora-silicon/speakerguardd: LINK-SPEAKERGUARDD) | agent-run |
| USB-C | not tested with a device | |

Details and the same results in upstream's format: https://github.com/aurora-silicon/linux/discussions/142#discussioncomment-19618807 and the follow-up below it.

## On offer: `apple,k114s` in the installer build

Three small patches, in https://github.com/chrisohearn/omarchy-m5p-oled/tree/main/installer:

- `omarchy-m5/0001`: `make-release-inputs.py --board apple,k114s` (a `BOARDS` table beside `BOARD`).
- `omarchy-m5/0002`: `check-app.sh` takes the one enabled board from `CHECK_APP_BOARD`.
- `omarchy-mac-installer/0001`: the engine's `k114sap` device, the 26B8125 stub row, the board 0x14 gate, the K114s Stage 1 name and collection of the K-board trackpad firmware, with engine tests. It applies on omacom/omarchy-mac-installer `c07e54c` with your patch sets.

Status: an installer built with these on release 3 installed this one K114s, and it boots (owner-observed, once). The two `omarchy-m5` patches still apply at `42edf84` (`git apply --check`); the engine patch was not checked against your current tree. Admission alone gives a K114s owner a keyboard-only system, per the table, so it only makes sense as an experimental developer board.

The K114s device tree, the two trackpad kernels and the update guards are in the same repository (`dts/`, `patches/linux/`, `linux/`). Take anything useful; authorship of the upstream pieces is in its `NOTICE.md`. If a pull request is easier for you than patches by link, say so.
