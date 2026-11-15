# Provenance and licenses

This repository's own files (the macOS tool, the Linux-side scripts, tests, build scripts and
documents) are MIT, see `LICENSE`. The files below come from, or are derived from, other projects
and keep their authors and licenses.

| Path | Origin | Author | License |
| --- | --- | --- | --- |
| `patches/linux/pr1568.patch` | aurora-silicon/linux pull request 1568, head `1e065585d3da` | Joshua Warren (joshuaswarren) | GPL-2.0 (Linux kernel) |
| `patches/linux/pr1830.patch` | aurora-silicon/linux pull request 1830, commits `07687621d1ce`, `a68b43218e41` | Jens Axboe | GPL-2.0 (Linux kernel) |
| `patches/linux/usb/0001-usb-typec-tipd-sn201202x-probe-asynchronously.patch` | aurora-silicon/linux commit `218e3f8550ba`, pull request 1671 | Roberto Dantas | GPL-2.0 (Linux kernel) |
| `dts/*.dts`, `dts/*.dtsi` | built on aurora-silicon/linux `t6050-k114s.dts` and `t6050-k114-k116.dtsi` (pull request 1025) with sections ported from `t6050-k116s.dts` (pull request 1648, Jens Axboe) and the J714s tree | The Asahi Linux Contributors, Aurora Silicon contributors; K114s port here | GPL-2.0+ OR MIT (SPDX line in each file) |
| `macos/tools/asahi_firmware/` | AsahiLinux/asahi-installer `asahi_firmware` (as used by the Omarchy installer engine) | Asahi Linux contributors | MIT |
| `installer/omarchy-m5/` | patches against betizzel/omarchy-m5 | this repository; base by betizzel and omarchy-m5 contributors | MIT |
| `installer/omarchy-mac-installer/` | patch against omacom/omarchy-mac-installer `c07e54c` with betizzel/omarchy-m5's installer patch sets applied | this repository; base by Omarchy and betizzel | as the files it changes |
| `linux/update-boot-ctxr-k114s` | derived from betizzel/omarchy-m5's J714s `update-boot-ctxr` hook | betizzel and omarchy-m5 contributors; K114s changes here | MIT |
| `linux/k114s-booted-esp` | the identity test of betizzel/omarchy-m5 `aurora-boot-mounts-generator` (`0abeef96`) | betizzel and omarchy-m5 contributors; adapted here | MIT |
| `linux/k114s-edge-check` | method of nickfoy/omarchy-m3-max `lib/update_preflight.py` (`8c16310`), rewritten | nickfoy (method) | MIT |
| `patches/omarchy/0001-claude-account-by-user-and-organization.patch` | omacom/omarchy pull request 18681, head `0d6d7c27a790` (`bin/` only), carrying pull request 16144 | Michele Di Giovanni (mikjkd); Omarchybot | MIT (Omarchy) |
| `build/make_k114s_ftab.py` | calls betizzel/omarchy-m5's `omarchy_centauri.py` unchanged | this repository | MIT |
| `build/validate-config.py` | method of betizzel/omarchy-m5 `installer/recipes/linux-aurora-j714s/validate-config.py` (`886269a`), rewritten and extended | betizzel and omarchy-m5 contributors (method) | MIT |
| `patches/linux/config/k114s-required.config` | this repository; the lines marked `[recipe]` restate betizzel/omarchy-m5 `j714s-required.config` | this repository; betizzel and omarchy-m5 contributors for those lines | MIT |
| `patches/linux/config/k114s-r3.config` | this repository; option names and help texts are the Linux kernel's, and the selection was compared with aurora-silicon/alarm-aurora's `linux-aurora` configuration (kernel pin `d89d8c0c`) | this repository | MIT |
| `patches/linux/sleep-lid/0001`, `0002` | aurora-silicon/linux pull request 1647, commits `aa16d423cf8a`, `70bf8ed1867b` | Jens Axboe; Thomas Glanzmann | GPL-2.0 (Linux kernel) |
| `patches/linux/sleep-lid/0003` | this repository (K114s admission, six lines) | this repository | GPL-2.0 (Linux kernel) |
| `patches/linux/sleep-lid/0004` | aurora-silicon/linux pull request 1688, commit `1006491abe42`; first in omacom/linux-aurora `9dee12b1266c` | ed (edimoldovan) | GPL-2.0 (Linux kernel) |
| `patches/linux/sleep-lid/0005`, `0006` | aurora-silicon/linux pull request 1688, commits `76c5ea390d74`, `67e63a577af4` | Joshua Warren | GPL-2.0 (Linux kernel); device tree GPL-2.0+ OR MIT |
| `patches/linux/sleep-lid/0007` | aurora-silicon/linux pull request 1615, commit `089b082fa329` | Joshua Warren | GPL-2.0 (Linux kernel) |
| `patches/linux/sleep-lid/0008` | aurora-silicon/linux pull request 1789, commit `f61eb4550a95` | Jens Axboe; Thomas Glanzmann | GPL-2.0+ OR MIT (device tree) |
| `patches/linux/sleep-lid/0009`, `0010` | aurora-silicon/linux pull request 1844, commits `41c359da8175`, `788441e0890e` | Erik Bourget; Diljit Singh | GPL-2.0 (Linux kernel) |
| `patches/linux/sound/0001` | aurora-silicon/linux commit `45f4de446485`, pull request 1648 | Jens Axboe | GPL-2.0 (Linux kernel) |
| `patches/linux/sound/0002`, `0003` | aurora-silicon/linux commits `ad10208a01c6`, `48243e8f3d32`, pull request 1787 | Jens Axboe | GPL-2.0 (Linux kernel) |
| `patches/linux/sound/0004` | this repository (the K114 card, speakers off) | this repository | GPL-2.0 (Linux kernel) |
| `patches/linux/display-gpu/0003`-`0006` | aurora-silicon/linux pull request 1868, commits `a4a0fb67bfe8`, `10f14b7ff802`, `3176918ba21e`, `84b3b93c04e6` | Joshua Warren (joshuaswarren) | GPL-2.0 (Linux kernel) |
| `patches/linux/display-gpu/0009`, `0010` | aurora-silicon/linux pull request 1648, commits `3adc985b5a61`, `8f418a490a97` | Thomas Glanzmann | GPL-2.0 (Linux kernel; the binding files' own SPDX lines) |
| `dts/t6050-k114s-sleep.dtsi`, `dts/t6050-k114s-sound.dtsi`, `dts/t6050-k114s-usb.dtsi`, `dts/t6050-k114s-r3*.dts` | K114s ports of nodes of `t6050-k116s.dts` (pull requests 1648, 1688, 1789) | Jens Axboe, Joshua Warren, The Asahi Linux Contributors; K114s port here | GPL-2.0+ OR MIT |

Nothing of Apple's is in this repository. Firmware is read from Apple's own restore image on the
owner's machine and never redistributed.

Commit trailers name the AI model that co-wrote a change. No `Signed-off-by` or `Tested-by` line
is added on anyone's behalf.

In `patches/linux/sleep-lid/` and `patches/linux/display-gpu/`, some upstream authors' e-mail addresses in the `From:`
and `Signed-off-by:` lines are replaced by placeholders, because this repository publishes no personal e-mail
addresses (`build/check-publishable.sh`). Names are unchanged and each patch names the upstream commit that
carries the address. `packaging/linux-k114s/` and `build/make-stage2.sh` are this repository's own (MIT).
