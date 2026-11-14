_Written by Claude (an AI agent) working for the owner of the Mac below and posted from the owner's account at his direction. "owner-observed" is what the owner saw on the machine; "agent-run" is a command the agent ran on it; "source read" is a file read in the named repository, with no hardware claim. One machine; not an independent reproduction._

A report from a sibling of the J714s, and an offer. No request to support the board.

## The Mac

MacBook Pro 14-inch with the OLED touchscreen, M5 Pro: Mac17,13, `apple,k114s`, board-id 0x14, SoC T6050, 18 CPUs. Linux stub on macOS 27.2 (26B8125), the same build as Jens Axboe's K116s. System firmware is 27.3 beta.

## What your release 3 does on it

Installed from macOS with an installer built from your release 3 sources with `apple,k114s` (`k114sap`, board 0x14) admitted; what that build needed is in the last section. First boot 2026-11-14. Release 3's own packages: kernel `7.3.0-17.v272-4-ARCH`, Aura `22b71758` with your 27.2 patch, set `j714s-dev-runtime-7cd4572ff7ef`. Release 4 has not been tried.

Stage 2 carried one device tree: `a34d26c2`'s `t6050-k114s.dts` plus the PCIe host `iommu-map` and `bus-range` of aurora-silicon/linux `b0d53446f84d`. That commit's message says Aura's T6050 hand-off refuses the boot without them.

| | Result | Evidence |
| --- | --- | --- |
| Install from macOS, then boot through Aura, U-Boot, Limine and the UKI to the Hyprland desktop on the encrypted NVMe root | pass | owner-observed |
| Built-in keyboard | pass | owner-observed |
| Trackpad | fail: `hid-generic 0019:05AC:0361.0002: invalid report_size 524288`, then `magicmouse 0019:05AC:0361.0002: probe with driver magicmouse failed with error -22`; no pointer. Works on a rebuild of the same kernel with aurora-silicon/linux #1568 (head `1e065585d3da`) added, on three boots. #1830 gates on product 0x0362 and this pad is 0x0361; a build of #1830 with 0x0361 admitted exists and has not been booted | owner-observed (no pointer, then pointer and clicks); agent-run (log lines, driver bound on three boots) |
| Wi-Fi, Bluetooth | absent with that tree: upstream's K114s tree keeps the PCIe host disabled. With a K114s copy of the K116s N1 node, platform ID `0x00146050` and a `k114s-ftab.bin` built with the parsing functions of your `omarchy_centauri.py`: Wi-Fi connects on 5 GHz; the Bluetooth controller registers as `hci0` and powers on, nothing paired yet | agent-run |
| `aurora-peripheral-firmware.sh` | admits only `apple,j714s`, as its comment says, so it never probes the N1 on a K114s. Here that did not matter: `apple_centauri_t6050` loaded by its PCI alias once the tree described the N1 (`aurora-firmware-order.conf` blacklists `apple_centauri`, not `apple_centauri_t6050`) | source read; agent-run (`lsmod`) |
| Display | boot framebuffer only (simpledrm, connector `Unknown-1`), Hyprland on llvmpipe | agent-run |
| Sound | no sound card: the K114s tree has no sound node. Each `speakerguardd-gate` call (aurora-silicon/speakerguardd's file, unchanged in the image) then waited its full 15 s, about 30 s before logins were allowed, on each of three boots | agent-run |
| USB-C | not tested with a device | |

The first boot is also reported in upstream's format: https://github.com/aurora-silicon/linux/discussions/142#discussioncomment-19618807

## On offer: `apple,k114s` in the installer build

Three patches, in https://github.com/chrisohearn/omarchy-m5p-oled/tree/main/installer:

- `omarchy-m5/0001`: `make-release-inputs.py --board apple,k114s` (a `BOARDS` table beside `BOARD`).
- `omarchy-m5/0002`: `check-app.sh` takes the one enabled board from `CHECK_APP_BOARD`.
- `omarchy-mac-installer/0001`: the engine's `k114sap` device, the 26B8125 stub row, the board 0x14 gate, the K114s Stage 1 name and collection of the K-board trackpad firmware, with engine tests.

Status: an installer built with these on release 3, with the image changes listed below, installed this one K114s, and it boots (owner-observed, once). All three still apply (`git apply --check`): the two `omarchy-m5` patches at `42edf84`, the engine patch on omacom/omarchy-mac-installer `c07e54c` with your patch sets as of `42edf84` (tree `7530a7b9`). Nothing was built or tested on your current tree. The patches' comments still say "never booted"; they were written before the trial. The engine patch's `source-lock.json` hunk pins an engine archive built here, so it needs a rebuild and a new pin on your side.

What the patches do not cover (source read):

- **The image.** The engine's K114s row accepts only an image whose metadata allows `k114sap` and which carries `esp/aurora/stage1-k114s.bin`, `stage1-k114s.macho` and a K114s `esp/m1n1/boot-ctxr.bin`. It refuses the J714s image, and `make-release-inputs.py --board apple,k114s` checks the same metadata. `image-builder/builder/stage1_qualification.py` knows only `j714sap`, and none of the three patches touches the image builder. The trial's image was release 3's with those members; the steps that produced it are not in the repository.
- **The Stage 2 device tree.** See above. Your v272-6 pin `a5ebec5fd092` already contains `b0d53446f84d`, and #1830.
- **Updates.** The image's `96-omarchy-j714s-boot-ctxr.hook` rewrites `m1n1/boot-ctxr.bin` from `m1n1/boot.bin` after a kernel, U-Boot or m1n1 package change, which replaces a K114s-only Stage 2. This Mac uses `linux/update-boot-ctxr-k114s` from the repository in its place.
- **N1 firmware.** `omarchy_centauri.py` collects it for `j714sap` only.

Admission alone gives a K114s owner a keyboard-only system, per the table, so it only makes sense as an experimental developer board.

The K114s device tree sources, the two trackpad patch series as used and the update guards are in the same repository (`dts/`, `patches/linux/`, `linux/`). Take anything useful; authorship of the upstream pieces is in its `NOTICE.md`. If a pull request is easier for you than patches by link, say so.
