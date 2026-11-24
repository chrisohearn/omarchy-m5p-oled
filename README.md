# omarchy-m5p-oled

Omarchy (Arch Linux with Hyprland) on the **MacBook Pro 14-inch with the OLED touchscreen and
M5 Pro**: Mac17,13, `apple,k114s`, board-id 0x14, SoC T6050.

This is the integration repository for one owner's machine. It collects what upstream already
has for this model and its siblings, adds the few K114s-specific pieces, and turns them into
versioned bundles that are applied in place to an existing install. Scope is the whole machine:
boot, input, radios, display, graphics, media, sound, power, updates.

## Where it stands (2026-11-15)

Omarchy runs natively on this Mac from its encrypted NVMe, with the desktop composited on the
Apple GPU. Evidence labels: *owner-observed* (seen by the owner on the Mac), *agent-run* (checked
on the Mac by the AI agent). States not yet on the Mac (*integrated*, *built*, *staged*) are as defined in [docs/matrix.md](docs/matrix.md).

| Area | State |
| --- | --- |
| Boot from encrypted NVMe, Limine, keyboard | working (owner-observed) |
| Trackpad | working with aurora-silicon/linux #1568 (owner-observed) |
| Wi-Fi | working (agent-run) |
| Bluetooth controller | up (agent-run); RFCOMM and BNEP verified on r3a (agent-run); HFP call audio blocked on SCO upstream; pairing and A2DP are owner-pending |
| GPU (G17S): OpenGL, Hyprland on the GPU | working (owner-observed, agent-run); Vulkan device enumerates, Vulkan clients not tested: [docs/r3-gpu-result.md](docs/r3-gpu-result.md) |
| Battery, voltages, fans | reading (agent-run); fans read about 2200 and 2375 RPM at desktop load on r3a (agent-run); sustained-load run still open |
| Updates on Omarchy's Edge channel | guarded after one bad refresh; updates run under the holds, and the space guard passes with 111 MB free against its 88 MB minimum (agent-run, 2026-11-15, after the r3a promotion): [incident](docs/incident-2026-11-14-edge-refresh.md), [what fills the partition](docs/esp-space.md) |
| Microphones | working since 2026-11-17: dictation through the built-in microphones (owner-observed); the sound tree is the configured Stage 2, with no path to the speakers ([docs/r3-mics.md](docs/r3-mics.md)). The headphone jack's card exists, untested |
| Native panel mode, 120 Hz, brightness | designed, not run (display coprocessor step: [docs/r3-display-gpu.md](docs/r3-display-gpu.md)) |
| Suspend and lid | r3c admits this model for suspend-to-idle. Two attended suspend-to-idle passes on r3d (2026-11-24) passed. Lid close sleeps on battery and locks on external power on ordinary boots, never on a trial boot: written and tested in fake roots, not yet installed ([docs/r3-lid-sleep-battery.md](docs/r3-lid-sleep-battery.md)) |
| Speakers | blocked upstream: no protection data for this model ([why](docs/r3-audio-protection.md)) |
| USB-C data ports | in the booted device tree; both controllers bind to `dwc3-apple`, but no USB bus has appeared and no device has been plugged in yet (agent-run, re-checked on r3a 2026-11-15) |
| Touch ID | working since 2026-11-16: the right index finger unlocks sudo, the lock screen and admin prompts (kernel r3b.c4; the Touch ID tree, and since 2026-11-17 the sound tree that carries it, in the Stage 2; [docs/r3-touchid.md](docs/r3-touchid.md)) |
| Hardware video decode | working since 2026-11-17: H.264, HEVC and VP9 on the Apple Video Decoder, used by mpv by default (owner-observed playback; [docs/r3-avd-decode.md](docs/r3-avd-decode.md)); the browser stays on software decode |
| Light sensor | working since 2026-11-17: reports lux with the factory calibration on both the trial and the normal r3c boot (agent-run). The cover test is pending ([docs/r3c-kernel.md](docs/r3c-kernel.md)) |
| Startup disk (NVRAM) | the complete NVRAM partition reads on r3c (agent-run). Writes are disabled, and startup-disk selection is pending ([#64](https://github.com/chrisohearn/omarchy-m5p-oled/issues/64)) |
| Camera, touchscreen, SD reader, Thunderbolt, external displays | drafted or ADT-checked offline, never booted (see [docs/matrix.md](docs/matrix.md)) |

Per-subsystem detail, sources and next steps are in [docs/matrix.md](docs/matrix.md).

### What got it here

1. **Bundle r2c**, applied from macOS: a repair kernel with the trackpad fix and the K114s Wi-Fi
   firmware, and a K114s device tree with Wi-Fi, Bluetooth, two USB-C ports and sensors
   ([docs/bundle-r2c.md](docs/bundle-r2c.md)).
2. **Update guards** in Linux (`linux/linux-persist.sh`), installed after an Edge channel refresh
   downgraded the boot chain ([docs/incident-2026-11-14-edge-refresh.md](docs/incident-2026-11-14-edge-refresh.md)).
3. **The GPU**: a device tree that adds only the GPU, booted through the loader's own one-boot
   trial (`aura-try`) so the proven boot file is never overwritten, and a session guard that
   moves the desktop onto the GPU only after an explicit opt-in.
4. **A native build environment** on the Mac ([docs/r3-buildenv.md](docs/r3-buildenv.md)) and the
   next kernel candidate, r3a (Bluetooth hands-free, firewall matches, sleep pieces, the 120 Hz
   gate), built and under review.

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
| `docs/r3-gpu-result.md` | the GPU on the K114s: what ran, what was measured, how to install and undo it |
| `docs/r3-display-gpu.md` | the display coprocessor and GPU design (only the GPU step has run) |
| `docs/edge-update-path.md` | how updates on the Edge channel are kept safe, and how that was tested |
| `docs/bundle-r2.md` | the bundle's own instructions |
| `dts/` | K114s device tree sources (trial 1, r1 and its variants, the r3 GPU and display trees) |
| `patches/linux/` | kernel patches as used, with their upstream authorship |
| `installer/` | the patches that admit `apple,k114s` in betizzel's installer build |
| `macos/` | apply/rollback tool for the Linux EFI partition; runs from macOS |
| `linux/` | update handling installed inside Linux; `omarchy-patches-install` for `patches/omarchy/` |
| `patches/omarchy/` | open upstream fixes to Omarchy's own scripts, kept across updates by a pacman hook ([docs/omarchy-patches.md](docs/omarchy-patches.md)) |
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
- A new Stage 2 is tried through the loader's one-boot trial (`aura-try`): the loader marks the trial
  spent before it reads the image, so after a failed try (a forced power-off if it hangs: the trial
  watchdog does not arm on this Mac) the next boot uses the proven one. The GPU tree is re-armed
  only after a clean shutdown of a boot that came up through it.
  Hardware acceptance is the owner's.
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
