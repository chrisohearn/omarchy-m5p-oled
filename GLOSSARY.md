# Glossary

The words these docs use for the K114s boot chain and its checks. Each entry says where it is defined in full.

## Boot roles

- **Main**: the Limine entry `default_entry` names. Every ordinary boot starts it. `k114s-boot status` shows which
  entry it is ([k114s-boot.md](docs/k114s-boot.md)).
- **Backup**: the other kernel entry, the way back. Reached by a one-shot from Linux or by the macOS repair tool.
- **Test**: the entry a pending Limine one-shot names (`k114s-boot-once arm`). The next boot starts it once, then Main
  again.
- The menu keeps the package names (`Omarchy/linux-k114s`, `Omarchy/linux-k114s-r3b`), because the built-in keyboard does not work in the menu and the repair tool and checks find entries by those names. Each kernel update swaps which name is Main, so ask `k114s-boot status`, not the name.

## Boots

- **Ordinary boot**: a boot of Main through the configured Stage 2, with no one-shot and no armed `aura-try`.
- **Trial boot** (also **one-boot trial**): a boot that takes a test file once, either a Stage 2 test file through
  `aura-try`, a Test kernel through a Limine one-shot, or both. The next boot is ordinary again. Linux sees a Stage 2
  trial as `/proc/device-tree/chosen/aurora,trial`, which names the test file ([r3-gpu-result.md](docs/r3-gpu-result.md#how-it-was-tried-aura-try)).
- **Promote**: make a tested file or kernel the configured one after its trial boot passes its check.

## Stage 2

- **Stage 2**: `m1n1/boot-ctxr.bin` on the EFI partition, which the first loader stage boots. It is three parts in order:
  the loader prefix, one K114s device tree, and the gzip U-Boot trailer.
- **Configured Stage 2**: the `m1n1/boot-ctxr.bin` every ordinary boot uses. `update-boot-ctxr` rebuilds it from the
  loader file, the pinned tree and the trailer of `m1n1/boot.bin` ([bundle-r2c.md](docs/bundle-r2c.md)).
- **Stage 2 test file**: a candidate beside the configured one (for example `m1n1/boot-ctxr-r3d-b.bin`), booted once
  through `aura-try`. The configured file stays the fallback.
- **`aura-try`**: a file at the root of the EFI partition. `armed` plus a path makes the next boot take that path
  once; the loader marks it `spent` before reading the image.
- **Loader override** (`/usr/lib/asahi-boot/m1n1-ctxr.bin`): when this file exists, `update-boot-ctxr` builds the
  Stage 2 from it instead of the aura package's `m1n1.bin`. While it stands, a new aura package does not reach the
  Stage 2, so a pacman hook flags every aura change ([r3d-stage2.md](docs/r3d-stage2.md)).
- **Pinned tree**: the K114s device tree `update-boot-ctxr` uses, kept on the EFI partition and in
  `/usr/local/lib/omarchy-k114s/`.

## Checks and gates

- **P9**: the local display-configuration safety check, run before and after every boot-chain change. It pins the
  configured Stage 2, the pinned trees, the loader files and the default entry, and fails if any of them changed
  without being promoted. It is not in this repository ([r3-lid-sleep-battery.md](docs/r3-lid-sleep-battery.md#p9-patch-for-the-root-p9-is-not-in-the-repo)).
- **Speaker gate**: `linux/audio/speaker-readiness.sh` and the WirePlumber tree check. The K114s speakers stay off; the
  gate fails if anything would enable them ([r3-audio-protection.md](docs/r3-audio-protection.md)).
- **Hold guard**: the pacman hook that stops any transaction changing the boot-chain packages unless
  `/etc/omarchy-k114s/allow-coupled-update` exists.
- **Lid-sleep gate**: `k114s-lid-sleep-gate.service`, run early on every boot. On an ordinary boot it opens lid-close
  sleep (suspend on battery, lock on external power). On a trial boot it keeps suspend masked, so a trial never
  sleeps ([r3-lid-sleep-battery.md](docs/r3-lid-sleep-battery.md)).
