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
| `patches/omarchy/0001-claude-account-by-user-and-organization.patch` | omacom/omarchy pull request 18681, head `0d6d7c27a790` (`bin/` only), carrying pull request 16144 | Michele Di Giovanni (mikjkd); Omarchybot | MIT (Omarchy) |
| `build/make_k114s_ftab.py` | calls betizzel/omarchy-m5's `omarchy_centauri.py` unchanged | this repository | MIT |

Nothing of Apple's is in this repository. Firmware is read from Apple's own restore image on the
owner's machine and never redistributed.

Commit trailers name the AI model that co-wrote a change. No `Signed-off-by` or `Tested-by` line
is added on anyone's behalf.
