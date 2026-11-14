# Provenance and licenses

This repository's own files (the macOS tool, the Linux-side scripts, tests, build scripts and
documents) are MIT, see `LICENSE`. The files below come from, or are derived from, other projects
and keep their authors and licenses.

| Path | Origin | Author | License |
| --- | --- | --- | --- |
| `patches/linux/pr1568.patch` | aurora-silicon/linux pull request 1568, head `1e065585d3da` | Joshua Warren (joshuaswarren) | GPL-2.0 (Linux kernel) |
| `patches/linux/pr1830.patch` | aurora-silicon/linux pull request 1830, commits `07687621d1ce`, `a68b43218e41` | Jens Axboe | GPL-2.0 (Linux kernel) |
| `dts/*.dts`, `dts/*.dtsi` | built on aurora-silicon/linux `t6050-k114s.dts` and `t6050-k114-k116.dtsi` (pull request 1025) with sections ported from `t6050-k116s.dts` (pull request 1648, Jens Axboe) and the J714s tree | The Asahi Linux Contributors, Aurora Silicon contributors; K114s port here | GPL-2.0+ OR MIT (SPDX line in each file) |
| `macos/tools/asahi_firmware/` | AsahiLinux/asahi-installer `asahi_firmware` (as used by the Omarchy installer engine) | Asahi Linux contributors | MIT |
| `installer/omarchy-m5/` | patches against betizzel/omarchy-m5 | this repository; base by betizzel and omarchy-m5 contributors | MIT |
| `installer/omarchy-mac-installer/` | patch against omacom/omarchy-mac-installer `c07e54c` with betizzel/omarchy-m5's installer patch sets applied | this repository; base by Omarchy and betizzel | as the files it changes |
| `linux/update-boot-ctxr-k114s` | derived from betizzel/omarchy-m5's J714s `update-boot-ctxr` hook | betizzel and omarchy-m5 contributors; K114s changes here | MIT |
| `linux/k114s-booted-esp` | the identity test of betizzel/omarchy-m5 `aurora-boot-mounts-generator` (`0abeef96`) | betizzel and omarchy-m5 contributors; adapted here | MIT |
| `linux/k114s-edge-check` | method of nickfoy/omarchy-m3-max `lib/update_preflight.py` (`8c16310`), rewritten | nickfoy (method) | MIT |
| `build/make_k114s_ftab.py` | calls betizzel/omarchy-m5's `omarchy_centauri.py` unchanged | this repository | MIT |
| `packaging/omarchy-hyprland-titlebars-m5/PKGBUILD` | the recipe of omacom/omarchy-pkgs `pkgbuilds/omarchy-hyprland-titlebars` (`062536c`), changed to build against hyprland-m5; it downloads omacom/omarchy-hyprland-titlebars `v0.4.0`, which is not copied here | recipe: Ryan Hughes and Omarchy contributors; plugin: Hypr Development (hyprbars) and Omarchy; M5 changes here | recipe MIT; plugin BSD-3-Clause and MIT |
| `packaging/omarchy-hyprland-titlebars-m5/nested-test.sh` | runs omacom/omarchy-hyprland-titlebars `tools/verify.py` (from a checkout or the release tarball, not copied here) with two additions made at run time | this repository; verifier by Omarchy | MIT |

Nothing of Apple's is in this repository. Firmware is read from Apple's own restore image on the
owner's machine and never redistributed.

Commit trailers name the AI model that co-wrote a change. No `Signed-off-by` or `Tested-by` line
is added on anyone's behalf.
