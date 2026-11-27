# Glossary

The words these docs use for the K114s rollout, boot chain and checks.

- **Daily-driver closeout**: acceptance of the owner's current workflows on a verified configuration,
  including ordinary updates and a verified backup boot. Upstream adoption and features outside those
  workflows retain their own release criteria.

## Boot roles

Defined in [k114s-boot.md](docs/k114s-boot.md), and shown by `k114s-boot status`.

- **Main**: the Limine entry `default_entry` names. Every ordinary boot starts it.
- **Backup**: the other kernel entry, the way back. Reached with a Limine one-shot from Linux.
- **Test**: the entry a pending Limine one-shot names (`k114s-boot-once arm`). The next boot starts it once, then Main
  again.
- The menu keeps the package names (`Omarchy/linux-k114s`, `Omarchy/linux-k114s-r3b`), because the built-in keyboard
  does not work in the menu and the repair tool and checks find entries by those names. A kernel update can swap which
  name is Main, so ask `k114s-boot status`, not the name.

## Boots

- **Ordinary boot**: a boot of Main through the configured Stage 2, with no one-shot and no armed `aura-try`.
- **Trial boot** (also **one-boot trial**): a boot that takes a test file once: a Stage 2 test file through `aura-try`,
  a Test kernel through a Limine one-shot, or both. Linux sees a Stage 2 trial as `/proc/device-tree/chosen/aurora,trial`,
  which names the test file ([r3-integration.md](docs/r3-integration.md), [r3-touchid.md](docs/r3-touchid.md)). The
  next boot is ordinary again unless something re-arms the trial. The standing re-arm (`linux/gpu-desktop/stage2-rearm`)
  did that boot after boot; it is retired ([r3-display-plan.md](docs/r3-display-plan.md)).
- **Promote**: make a tested file or kernel the configured one after its trial boot passed its check.

## Stage 2

- **Stage 2**: `m1n1/boot-ctxr.bin` on the EFI partition, which the first loader stage boots. It is three parts in
  order: the loader prefix, one K114s device tree, and the gzip U-Boot trailer (`linux/update-boot-ctxr-k114s`,
  [bundle-r2c.md](docs/bundle-r2c.md)).
- **Configured Stage 2**: the `m1n1/boot-ctxr.bin` every ordinary boot uses. `update-boot-ctxr` builds it from the
  loader file, the pinned tree and the trailer of `m1n1/boot.bin`. Once the update tooling is installed
  (`/etc/omarchy-k114s/stage2-managed`), the pacman hook no longer rewrites it: only `k114s-release` replaces it, after
  a candidate has booted as a trial ([r3-update-tooling.md](docs/r3-update-tooling.md)).
- **Stage 2 test file**: a candidate beside the configured one (for example `m1n1/boot-ctxr-r3d-b.bin`), booted once
  through `aura-try`. The configured file stays the fallback ([r3d-stage2.md](docs/r3d-stage2.md)).
- **`aura-try`**: a file at the root of the EFI partition. `armed` plus a path makes the next boot take that path
  once; the loader marks it `spent` before reading the image
  ([r3-gpu-result.md](docs/r3-gpu-result.md#how-it-was-tried-aura-try)).
- **Loader override** (`/usr/lib/asahi-boot/m1n1-ctxr.bin`): when this file exists, `update-boot-ctxr` builds the
  Stage 2 from it instead of the aura package's `m1n1.bin` (`linux/update-boot-ctxr-k114s`,
  [bundle-r2c.md](docs/bundle-r2c.md)). While it stands, a new aura package does not reach the Stage 2.
- **Pinned tree**: the K114s device tree `update-boot-ctxr` uses, kept at `k114s-repair/k114s.dtb` on the EFI partition
  and at `/usr/local/lib/omarchy-k114s/k114s.dtb` ([r3-display-plan.md](docs/r3-display-plan.md)).

## Checks and gates

- **P9**: the read-only check that the promoted configuration holds, run before and after every update and boot-chain
  change. It pins the configured Stage 2, the pinned trees, the loader files and the default entry, and fails if any
  of them changed without being promoted. It is described as Block P9 in
  [r3-display-d5-d9.md](docs/r3-display-d5-d9.md); the script that runs it on the Mac is kept outside this repository
  ([r3-lid-sleep-battery.md](docs/r3-lid-sleep-battery.md#p9-patch-for-the-root-p9-is-not-in-the-repo)).
- **Speaker gate**: `linux/audio/speaker-readiness.sh` and the WirePlumber tree check (`linux/audio/tree-check`). The
  K114s speakers stay off, and the gate fails if anything would enable them
  ([r3-audio-protection.md](docs/r3-audio-protection.md)).
- **Package guard**: `linux/k114s-guard`, run by the pacman hooks the update tooling installs. It stops a transaction
  that would change a held package (from `holds.list`: the boot chain plus pinned packages such as `mesa-aurora` and
  `omarchy-mac`) unless a release permit or
  `/etc/omarchy-k114s/allow-coupled-update` allows it ([r3-update-tooling.md](docs/r3-update-tooling.md)). Earlier
  installs carry its predecessor, `00-k114s-hold-guard.hook`.
- **Lid-sleep gate**: `k114s-lid-sleep-gate.service`, which runs early on every boot once lid sleep is installed
  (`k114s-lid-sleep install`). On an ordinary boot it opens lid-close sleep (suspend on battery, lock on external
  power). On a trial boot it keeps suspend masked, so a trial never sleeps
  ([r3-lid-sleep-battery.md](docs/r3-lid-sleep-battery.md)).
