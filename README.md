# omarchy-m5p-oled

Omarchy (Arch Linux with Hyprland) on the **MacBook Pro 14-inch with the OLED touchscreen and
M5 Pro**: Mac17,13, `apple,k114s`, board-id 0x14, SoC T6050.

This is the integration repository for one owner's machine. It collects what upstream already
has for this model and its siblings, adds the few K114s-specific pieces, and turns them into
versioned bundles that are applied in place to an existing install. Scope is the whole machine:
boot, input, radios, display, graphics, media, sound, power, updates.

## Where it stands (2026-11-14)

- **Boots.** A K114s booted this stack to the Hyprland desktop from its encrypted NVMe root, with
  the built-in keyboard working (owner-observed, 2026-11-14). At that boot the trackpad failed
  ("invalid report_size 524288") and there was no network: that trial's device tree left the
  radio and USB ports off on purpose.
- **Bundle r1** (2026-11-14): two repair kernels for the trackpad, a K114s device tree with
  Wi-Fi/Bluetooth, two USB-C host ports and sensors, the K114s Wi-Fi firmware, and an apply and
  rollback tool that runs from macOS. Kept as delivered in `releases/r1/`.
- **Bundle r2** (2026-11-14): r1's boot files unchanged, plus update handling that keeps the K114s
  boot chain intact through `omarchy update` and a channel refresh.
- **Not yet proven on hardware:** everything in r1 and r2. The first test is the next Linux boot.
- Everything else (display coprocessor, GPU, sound, camera, sleep, ...) is tracked per subsystem
  in [docs/matrix.md](docs/matrix.md), with the next candidate planned there.

`ledger/checkpoints.json` records each change's state separately: evaluated, integrated,
built/tested, staged, applied, awaiting reboot, hardware-verified.

## What is and is not in here

In: device tree sources, kernel patches with their upstream authorship, the macOS apply/rollback
tool, the Linux-side update scripts, tests, build scripts, installer patches, source pins,
manifests (hashes only), notes.

Not in: kernel, module, loader and installer binaries (build them from the pins), and anything
of Apple's: firmware, tickets, device tree dumps, calibration data. The Wi-Fi and trackpad
firmware are extracted on the owner's side from Apple's own restore image by
`build/make_k114s_ftab.py` and the installer. No serial numbers, logs or backups either.
`build/check-publishable.sh` enforces this before every push.

## Built on

- [betizzel/omarchy-m5](https://github.com/betizzel/omarchy-m5): the J714s (14-inch M5 Pro, LCD)
  installer, image and kernel patch series this stack starts from. Primary reference.
- [aurora-silicon/linux](https://github.com/aurora-silicon/linux),
  [aurora-silicon/aura](https://github.com/aurora-silicon/aura): kernel and loader, including the
  preliminary K114/K116 device trees and the K116s and K114c bring-up by Jens Axboe (sithglan) and
  Joshua Warren.
- [omacom/omarchy](https://github.com/omacom/omarchy),
  [omacom/omarchy-mac-pkgs](https://github.com/omacom/omarchy-mac-pkgs),
  [omacom/omarchy-mac-installer](https://github.com/omacom/omarchy-mac-installer).
- [AsahiLinux](https://github.com/AsahiLinux): the installer firmware tooling
  (`macos/tools/asahi_firmware`) and everything underneath.
- [nickfoy/omarchy-m3-max](https://github.com/nickfoy/omarchy-m3-max): the read-only update
  preflight method and the recovery-set discipline. Not hardware support for this machine.

Exact revisions are in `pins/sources.json`; who wrote what is in [NOTICE.md](NOTICE.md).

## Layout

| Path | What |
| --- | --- |
| `docs/matrix.md` | subsystem by subsystem: upstream fix, K114s applicability, state, next step |
| `docs/upstream-applicability.md` | the detailed source review behind the matrix |
| `docs/edge-update-path.md` | how updates on the Edge channel are kept safe, and how that was tested |
| `docs/bundle-r2.md` | the bundle's own instructions |
| `dts/` | K114s device tree sources (trial 1, r1 and its variants) |
| `patches/linux/` | the two upstream trackpad series as used |
| `installer/` | the patches that admit `apple,k114s` in betizzel's installer build |
| `macos/` | apply/rollback tool for the Linux EFI partition; runs from macOS |
| `linux/` | update handling installed inside Linux |
| `tests/` | replica tests for the macOS tool, fake-root tests for `linux/`, the image isolation run |
| `build/` | bundle assembly, device tree and kernel build scripts, the publish check |
| `releases/r1/` | bundle r1's text files as delivered, with its test evidence |
| `manifests/`, `pins/`, `ledger/` | hashes, source revisions, per-change state and the upstream report registry |

## Safety rules this repository keeps

- In place only: no reinstall, no repartitioning, no change to macOS, Apple boot policy, Stage 1
  or firmware. The encrypted Linux root is never opened from macOS.
- Every write to the Linux EFI partition is backed up first, verified after, and has a rollback
  that runs from macOS. The device tree is shared by all boot entries, so the original kernel
  entry alone is not a fallback; `rollback stage2` is.
- A delivered bundle is never rebuilt. A change makes a new revision.
- No automatic reboot. Hardware acceptance is the owner's.
- No sibling's firmware, calibration or identity is reused. Speakers are never driven without
  protection data for this model.
- Edge channel only. No Dev checkout.

## Reporting upstream

Hardware results and fixes for this model go back to the projects they belong to. The rules and
the registry of what was sent are in [UPSTREAM.md](UPSTREAM.md).

## Who writes this

Most of the code and text here is written by an AI agent (Claude) working for the machine's owner,
who directs it and performs the hardware tests. Hardware results are the owner's observations
unless a line says otherwise. Emulator and replica tests are labelled as such.

## License

This repository's own files are MIT ([LICENSE](LICENSE)). Kernel patches are GPL-2.0, device tree
sources are GPL-2.0+ OR MIT, and imported tooling keeps its license; see [NOTICE.md](NOTICE.md).
