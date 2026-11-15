# Provenance and licenses

This repository's own files (the macOS tool, the Linux-side scripts, tests, build scripts and
documents) are MIT, see `LICENSE`. The files below come from, or are derived from, other projects
and keep their authors and licenses.

| Path | Origin | Author | License |
| --- | --- | --- | --- |
| `patches/linux/pr1568.patch` | aurora-silicon/linux pull request 1568, head `1e065585d3da` | Joshua Warren (joshuaswarren) | GPL-2.0 (Linux kernel) |
| `patches/linux/pr1830.patch` | aurora-silicon/linux pull request 1830, commits `07687621d1ce`, `a68b43218e41` | Jens Axboe | GPL-2.0 (Linux kernel) |
| `patches/linux/usb/0001-usb-typec-tipd-sn201202x-probe-asynchronously.patch` | aurora-silicon/linux commit `218e3f8550ba`, pull request 1671 | Roberto Dantas | GPL-2.0 (Linux kernel) |
| `patches/linux/brightness/0001`–`0003` | aurora-silicon/linux pull request 1646 (open), commits `50db17f86f92`, `8847a289036a`, `907bb7ec5990` | Jens Axboe; Thomas Glanzmann (notes in 0001, 0002). Their addresses in the `From:` and `Signed-off-by:` lines are replaced by `address-in-upstream-commit@localhost`; names, dates and commit ids are unchanged | GPL-2.0 (Linux kernel) |
| `patches/linux/brightness/0004` | aurora-silicon/linux pull request 1887 (merged), commit `629e81bc2dd6`. The address in its `Signed-off-by:` line is replaced by `address-in-upstream-commit@localhost` (in `patches/linux/brightness`, personal e-mail addresses in imported patch headers are replaced the same way, GitHub noreply addresses are kept; `pr1830.patch` is outside this branch's change and keeps its upstream header); the name is unchanged and the patch names the upstream commit | Ryan Murray (RyanTheTide) | GPL-2.0 (Linux kernel) |
| `patches/linux/brightness/0005`, `0006` | this repository, against aurora-silicon/linux `drivers/gpu/drm/apple` (backlight code by Ryan Murray and the Asahi Linux and Aurora Silicon contributors) and the `apple,dcp` binding | this repository | as the files they change (GPL-2.0-only OR MIT; the binding file's own SPDX line) |
| `tests/brightness/kunit-host/` | this repository; stand-ins for the kernel header names a KUnit suite includes, written here, no kernel code copied | this repository | MIT |
| `dts/*.dts`, `dts/*.dtsi` | built on aurora-silicon/linux `t6050-k114s.dts` and `t6050-k114-k116.dtsi` (pull request 1025) with sections ported from `t6050-k116s.dts` (pull request 1648, Jens Axboe) and the J714s tree | The Asahi Linux Contributors, Aurora Silicon contributors; K114s port here | GPL-2.0+ OR MIT (SPDX line in each file) |
| `patches/linux/display-gpu/0001`, `0002` | aurora-silicon/linux pull request 1844, commits `41c359da8175`, `788441e0890e` | Erik Bourget; DjDeveloperr (Diljit Singh) | GPL-2.0 (Linux kernel) |
| `patches/linux/display-gpu/0003`–`0006` | aurora-silicon/linux pull request 1868, commits `a4a0fb67bfe8`, `10f14b7ff802`, `3176918ba21e`, `84b3b93c04e6` | Joshua Warren (joshuaswarren) | GPL-2.0 (Linux kernel) |
| `patches/linux/display-gpu/0007`, `0008` | aurora-silicon/linux pull request 1688, commits `1006491abe42` (from `9dee12b1266c`), `76c5ea390d74` | ed (Eduard Moldovan); Joshua Warren | GPL-2.0 (Linux kernel) |
| `patches/linux/display-gpu/0009`, `0010` | aurora-silicon/linux pull request 1648, commits `3adc985b5a61`, `8f418a490a97` | Thomas Glanzmann | GPL-2.0 (Linux kernel; the binding files' own SPDX lines) |
| `patches/aura/0001` | aurora-silicon/aura pull request 226, commit `023eb3a01a61`, hand-merged here with betizzel/omarchy-m5's aura patch 0005 (TripleU) as its message says | Jens Axboe; merge here | as the file it changes (`src/kboot_display_handoff.c`, SPDX MIT); aura's LICENSE puts Aurora Silicon contributions under GPL-2.0-only |
| `patches/aura/0002` | aurora-silicon/aura pull request 230, commit `5d2ec8f00e99` | Jens Axboe | as the file it changes (`src/kboot_gpu.c`, SPDX MIT AND GPL-2.0-only) |
| `patches/aura/0003` | this repository (one line in aura's host-test stub `tests/t8122_display_host/firmware.h`, SPDX MIT) | this repository | MIT |
| `dts/t6050-k114s-display-gpu.dtsi`, `dts/t6050-k114s-r3*.dts` | K114s copies of `t6050-k116s.dts` and `t6050-k116s-gpu.dtsi` (aurora-silicon/linux pull requests 1648 and 1859, commits `377b2a2decf1`, `59ea61054b1e`, `e3373ad8f86a`) and of the eDP property of pull request 1688 | Jens Axboe, Joshua Warren, The Asahi Linux Contributors; K114s port here | GPL-2.0+ OR MIT |
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
| `dts/t6050-k114s-sleep.dtsi`, `dts/t6050-k114s-sound.dtsi`, `dts/t6050-k114s-usb.dtsi`, `dts/t6050-k114s-r3*.dts` | K114s ports of nodes of `t6050-k116s.dts` (pull requests 1648, 1688, 1789) | Jens Axboe, Joshua Warren, The Asahi Linux Contributors; K114s port here | GPL-2.0+ OR MIT |
| `packaging/omarchy-hyprland-titlebars-m5/PKGBUILD` | the recipe of omacom/omarchy-pkgs `pkgbuilds/omarchy-hyprland-titlebars` (`062536c`), changed to build against hyprland-m5; it downloads omacom/omarchy-hyprland-titlebars `v0.4.0`, which is not copied here | recipe: Ryan Hughes and Omarchy contributors; plugin: Hypr Development (hyprbars) and Omarchy; M5 changes here | recipe MIT; plugin BSD-3-Clause and MIT |
| `packaging/omarchy-hyprland-titlebars-m5/nested-test.sh` | runs omacom/omarchy-hyprland-titlebars `tools/verify.py` (from a checkout or the release tarball, not copied here) with two additions made at run time | this repository; verifier by Omarchy | MIT |

In `patches/linux/display-gpu/`, three authors' e-mail addresses in the `From:` and `Signed-off-by:`
lines are replaced by `address-in-upstream-commit@localhost`, the addresses the publish check
(`build/check-publishable.sh`) matches. Some upstream kernel authors' addresses that it does not
match stay as they appear in their public upstream commits. The names are unchanged and each patch
names the upstream commit that carries the address.

Nothing of Apple's is in this repository. Firmware is read from Apple's own restore image on the
owner's machine and never redistributed.

Commit trailers name the AI model that co-wrote a change. No `Signed-off-by` or `Tested-by` line
is added on anyone's behalf.

In `patches/linux/sleep-lid/` and `patches/linux/display-gpu/`, some upstream authors' e-mail addresses in the `From:`
and `Signed-off-by:` lines are replaced by placeholders, because this repository publishes no personal e-mail
addresses (`build/check-publishable.sh`). Names are unchanged and each patch names the upstream commit that
carries the address. `packaging/linux-k114s/` and `build/make-stage2.sh` are this repository's own (MIT).
