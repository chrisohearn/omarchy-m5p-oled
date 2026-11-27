# r3h kernel candidate

r3h rebases the K114s r3g patch series onto Aurora Silicon's Linux `main` at
[`e070a17ceb8d`](https://github.com/aurora-silicon/linux/commit/e070a17ceb8d9bf1b5e23718449988b7c5288722).
The 34-patch series produces source tree
`9e74dda851ecc96bca4d295cc5dbc65d35667093`.

This candidate is for the Backup slot, `linux-k114s 7.3.0.r3h-1`. The current
Main remains r3g as `linux-k114s-r3b 7.3.0.r3g-1`, and the current Backup remains
r3f as `linux-k114s 7.3.0.r3f-1`. r3h has not been installed or booted on the
K114s.

## Patch disposition

Upstream now contains the shared K114 and K116 N1 and USB descriptions, the G17S
GPU description, and the K114s jack-pin description. r3h drops those three local
patches. It adapts the remaining board changes to upstream's shared device-tree
files and keeps the owner's camera behavior: the camera does not describe or
drive a light, and the indicator is a 32-pixel square under the notch.

The kernel uses upstream's panel EDR value. It has no 500-nit cap by default.
Apple SoC deep sleep stays disabled in the kernel config.

The K114s device tree has the QSPI controller but no SPI NOR device or NVRAM
partition. The QSPI driver defaults to read-only and has no K114s write row.
The package tests verify these policy paths. The candidate never writes SPI
NOR or NVRAM.

## Upstream changes since r3g

The new base adds shared T6050 descriptions for K114 and K116 USB, N1, GPU, AOP,
and Neural Engine hardware. It adds the K114s to those common descriptions.
Upstream also changes G17 recovery behavior, DCP display and HDCP paths, and
USB-C power and router handling. The r3h series keeps the local camera policy,
the small camera indicator, and the K114s boot NOR write gates on that base.

## Reproduce the build

Start with a clean Linux source worktree at the fetched `origin/main` commit.
Apply `patches/linux/r3h.series`, then build with the native K114s toolchain.

```bash
	source "$HOME/k114s-build/env.sh"
	repo="$PWD"
	base=e070a17ceb8d9bf1b5e23718449988b7c5288722
	src="$B/src/r3h-repro"
	out="$B/out/r3h-repro"
	git -C "$B/src/linux.git" fetch origin main
	git -C "$B/src/linux.git" worktree add --detach "$src" "$base"
	mapfile -t series < <(sed '/^#/d; /^$/d' "$repo/patches/linux/r3h.series")
	for index in "${!series[@]}"; do
		series[$index]="$repo/patches/linux/r3h/${series[index]}"
	done
	git -C "$src" am "${series[@]}"
	printf -- '-17.v272-19-k114s-r3h' > "$src/localversion.10-pkgrel"
	mkdir -p "$out"
	cp "$B/out/r3g/.config" "$out/.config"
	cd "$src"
	kmake O="$out" olddefconfig
	python3 "$repo/build/validate-config.py" "$out/.config" \
		"$repo/patches/linux/config/k114s-required.config" \
		"$repo/patches/linux/config/k114s-r3.config"
	K114S_LABEL=K114S-R3H kmake O="$out" Image modules dtbs
```

The `linux-k114s` `PKGBUILD` pins the source tree and release string. To package
the finished build, run `K114S_CAND=r3h makepkg -f --nodeps --skipinteg` with
`K114S_SRC="$src"` and `K114S_OUT="$out"`. Run `check-package.sh` once against
`linux-aurora` and once against `linux-k114s-r3b`.

## Build checks

| Check | Result |
| --- | --- |
| `olddefconfig` from r3g config | Passed. It enabled the two new upstream HDCP config symbols. |
| `build/validate-config.py` | Passed. 385 requirements met, 0 unmet, and 21 requested modules were built in. |
| `CHECK_DTBS=1 apple/t6050-k114s.dtb` | Passed with dtschema 2026.9 and no diagnostics. |
| QEMU shell smoke | Passed for `7.3.0-17.v272-19-k114s-r3h-ARCH`. |
| QEMU all-module smoke | Harness passed. 1,966 modules loaded; the same seven modules failed under QEMU as on prior candidates: `tcrypt`, `ipmi_si`, `cppc_cpufreq`, `sun50i-cpufreq-nvmem`, `stratix10-soc`, `apple-pmp-j613-hwmon`, and `xen-pciback`. |
| QSPI NVRAM policy tests | 37 passed, 0 failed. |
| Camera indicator userspace tests | 11 passed. |
| `check-package.sh` against `linux-aurora` | Passed. 1,973 modules have the candidate vermagic; `depmod -a -e` found no unresolved symbols or file collisions. |
| `check-package.sh` against `linux-k114s-r3b` | Passed with the same module, symbol, DTB and collision checks. |

The package's K114s DTB includes the QSPI controller. It contains no NVRAM
partition or SPI NOR device. The package checks decompiled the archived DTB and
confirmed those absences.

## Build record

Build environment: Clang 23.1.3 and Rust 1.98.1. The package is
`linux-k114s-7.3.0.r3h-1-aarch64.pkg.tar.xz`.

| Item | Value |
| --- | --- |
| Package SHA-256 | `8c55cfaa92373d6b2eb6f0d0eeb4aca7e296c5bd562d30a54acea657cf72449b` |
| Image SHA-256 | `deb98335bdaf23f2f3739351ede0191b1ad41a54244659e999e4ffde393ea7af` |
| Config SHA-256 | `19e2136cdac8caf49af39ca0faacee271644492465b85bf7ad0cd7980317550e` |
| Packaged K114s DTB SHA-256 | `edb35d21cebfbc548dc51d11f77ce45d73bd232c8331dacc88cbc65f7fbfd964` |

The candidate has build and emulator evidence only. Its attended Backup-slot
trial, hardware comparisons, P9 check, and promotion remain pending under
[`nightly-rollout.md`](nightly-rollout.md). Do not reboot while the owner is
active or the adoption unit is running.
