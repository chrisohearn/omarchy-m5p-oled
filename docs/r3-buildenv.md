# r3 build environment: the K114s builds its own kernel

2026-11-14. Worker key `buildenv`. Everything below was run by an agent on the K114s itself
(**agent-run**) or in QEMU on it (**emulator/replica**). Nothing built here has been booted on the
Mac: no kernel, module, device tree or Stage 2 from this build area is installed.

## What exists now

A user-local build area, `~/k114s-build`, that needs no root and installs nothing system-wide:

| Piece | Version | Where it comes from |
| --- | --- | --- |
| clang, lld, llvm | 23.1.3 | the official LLVM `Linux-ARM64` release; sha256 `1154f37e...` equals the digest GitHub publishes for the release asset. The Arch Linux ARM mirror is already at 23.1.5, so the distribution package would not match the running kernel |
| Rust | 1.98.1 (kernel), 1.89.0 + `aarch64-unknown-none-softfloat` (Aura) | rustup with `RUSTUP_HOME`/`CARGO_HOME` inside the build area; `rust-src`, `rustfmt` |
| bindgen | 0.73.2 | built by the kernel tree's own `tools/aurora-bindgen/build.py` (pinned source, two patches, compile tests), as betizzel's PKGBUILD does |
| bc, dtc, pahole | 1.08.2, 1.8.1, 1.32 | Arch Linux ARM packages, sha256 from the repository database, extracted under `tools/alarm` |
| QEMU | 11.1.3 | the same way, under `tools/qemu` |
| make, gcc (host tools), flex, bison, perl, python 3.14, cpio, openssl and libelf headers | as installed | already on the Omarchy image |

`build/native/` in this repository holds the scripts: `setup.sh` (creates the area from nothing),
`env.sh`, `kmake`, `fetch-alarm-pkg`, `k114s-dtb`, `k114s-cmp-modules`, `k114s-qemu-smoke`,
`k114s-build-stage2`, `qemu-system-aarch64` (wrapper) and `README-build.md` (the instructions
the other r3 workers follow; `setup.sh` installs it as `~/k114s-build/README-build.md`).

`setup.sh` is the record of the steps that were first run by hand on 2026-11-14. It was then run
from nothing into a second, empty root (only the 1.1 GB LLVM archive was copied in instead of
downloaded again; its sha256 is checked either way): 465 s, and the `base`, `r1` and Aura `base`
trees it produced have the same git tree ids as the hand-made ones (`d920e4f4ddf6`, `ccb7d81cf70c`,
`a708dc464293`). Run against the finished area it verifies and skips every step. It does not
build a kernel; it prints the baseline commands.

## Sources, at the pins of `pins/sources.json`

| Tree | Content | Check |
| --- | --- | --- |
| `src/linux.git` | aurora-silicon/linux `integration/aurora` since 2026-10-01 (head `b9ac02af54da` when fetched) and 28 pull request heads | all 88 kernel commits named in `docs/upstream-applicability.md` and `docs/matrix.md` resolve |
| `src/base` | `a34d26c255c2` + `linux-j714s-27.2.patch` (19 patches, `git am`, authors kept) + `localversion.10-pkgrel` | tree of pin + series equals `git apply` of the patch file from release 3 (`cfbe533c8b`, sha256 `a3140b09...` as in its PKGBUILD) on the pin: tree `8ab0355a1d01` |
| `src/r1` | `base` + `patches/linux/pr1568.patch` | applied with `patch -Np1` as the running kernel was built; `git am` refuses it (one hunk of patch 4 needs fuzz 1) |
| `aura/base` | aurora-silicon/aura `22b71758dfd0` + `aura-j714s-27.2.patch` (7 patches, `git am`) | patch sha256 `37d12316...` as in the PKGBUILD |
| `recipe/release3` | betizzel/omarchy-m5 `cfbe533c8b`: `installer/recipes/{linux-aurora-j714s,m1n1-aurora-j714s,uboot-aurora}`, `patches/j714s-27.2` | sha256 of the kernel recipe files equal the PKGBUILD's `sha256sums` |

aurora-silicon/m1n1 is not needed: the Stage 2 this stack boots is Aura (packaged as
`m1n1-aurora`, installed as `/usr/lib/asahi-boot/m1n1.bin`).

## Baseline: the running kernel, rebuilt natively (agent-run)

`src/r1`, configured from `zcat /proc/config.gz` of the running `7.3.0-17.v272-4-ARCH` (K114S-R1),
`olddefconfig`, `Image modules`, then `dtbs`. Label `K114S-R1-NATIVE`.

| Check | Result |
| --- | --- |
| `kernelrelease` | `7.3.0-17.v272-4-ARCH` |
| Config against the running kernel (all `CONFIG_` lines) | two lines differ: `CONFIG_CC_VERSION_TEXT` (the LLVM release prints its source revision after `clang version 23.1.3`) and `CONFIG_CC_CAN_LINK=y` (the running kernel was cross-built on x86_64; nothing depends on it in this config). With the toolchain probe lines excluded: no difference |
| betizzel's `validate-config.py` against `j714s-required.config` | passes |
| Wall time, `Image modules`, `-j16`, other workers already building (load 30 to 40) | 469 s (7 min 49 s) |
| Wall time, all arm64 `dtbs`, `-j16` | 4 s |
| Wall time, a second full build `Image modules dtbs`, `-j10`, load 40 to 48 | 649 s (10 min 49 s) |
| The two native builds against each other (different output directories, same label) | `Image` differs in 69 bytes: three modification times in the built-in default initramfs (9 bytes; the label is not a date, so `gen_init_cpio` takes the clock) and three copies of the 20-byte build ID, a hash over the linked image. Modules: the same 1725/3 result against the installed tree |
| Modules built | 1728, the same list as `/usr/lib/modules/7.3.0-17.v272-4-ARCH/kernel` |
| `modinfo -F vermagic drivers/hid/hid-magicmouse.ko` | `7.3.0-17.v272-4-ARCH SMP preempt mod_unload aarch64`, identical to the installed `updates/hid-magicmouse.ko` |
| Module contents against the installed modules (`k114s-cmp-modules`: `.text .init.text .exit.text .rodata .data`) | 1725 of 1728 identical byte for byte, including `hid-magicmouse` against the installed `updates/` copy. The other three (`apple-pmp`, `apple-sep`, `snd-soc-t8152-aop-audio`) differ only in `.rodata`: Rust code that embeds the path of the Rust standard library sources on the build machine |
| `Image` | 54086144 bytes, the size of the installed `vmlinuz`; not identical, as expected: the banner carries the longer compiler string and another label, and Rust code carries build paths |
| 137 Apple device trees built | yes (`arch/arm64/boot/dts/apple`) |

So this toolchain generates the same code as the one that built the running kernel. A variant
built here differs from the running kernel by its source changes and nothing else, and
`k114s-cmp-modules` lists exactly which modules a variant changes.

The kernel tree's own `apple/t6050-k114s.dtb` from this build has sha256 `d5c1f1541b21...`, the
same as the packaged `/usr/lib/modules/7.3.0-17.v272-4-ARCH/dtbs/t6050-k114s.dtb`.

### Prebuilt tree for variants

`src/r1-built` is the same source built with the output directory inside the tree (`O=out`).
Kbuild then records relative paths, so a btrfs reflink copy of the whole tree (2 s) is a valid
build tree. Measured in a copy: first `kmake O=out Image modules` 63 s (20 Rust objects, the vDSO
and the link are redone because they carry absolute paths), nothing to do 5 s, one changed driver
file 6 s. The documented flow was run once as written, with a config change
(`CONFIG_BT_RFCOMM=m`, `CONFIG_BT_RFCOMM_TTY=y`): 67 s in total, release unchanged,
`k114s-cmp-modules` reported `NEW net/bluetooth/rfcomm/rfcomm.ko` and the three baseline lines,
`rfcomm.ko` has the running kernel's vermagic, QEMU shell test PASS. (That test tree was deleted;
it is not a deliverable.)

One trap found on the way: the single-module target (`make drivers/hid/hid-magicmouse.ko`) fails
in modpost for a module that imports another module's symbols and leaves a one-line
`modules.order` behind, after which `make modules` keeps failing. `README-build.md` says so and
gives the recovery (`rm modules.order`, `make modules`); `build/r1` was repaired that way and its
`Image` hash is unchanged.

## Device tree (agent-run)

`dts/t6050-k114s-r1.dts` built against `src/base` gives sha256
`2ea22d26b2a1c81526e77e7f29eaff46def5310a9512be769ff3ed50465f4dd2`: the manifest value, and the
hash of the installed `/usr/local/lib/omarchy-k114s/k114s.dtb`. Same result with dtc 1.8.1 (Arch
Linux ARM) and with the kernel tree's own dtc (1.7.2-g53373d13). `r1-gp1c` and `r1-wifi` also
reproduce their manifest hashes (`285baf26...`, `b9ce372f...`).

Two findings:

- `build/build-dtb.sh` failed with both of these dtc builds: `FATAL ERROR: Unrecognized check
  name "graph_child_address"`. The check no longer exists in current dtc. Fixed on this branch:
  the script passes only the `-Wno-` names the dtc knows. They silence warnings; the blob is the
  same.
- `dts/t6050-k114s-trial1.dts` gives `592c0c0c...`, not the manifest's `a8c82b27...`. The sources
  in `dts/` and `releases/r1/src/` are the same files, so the delivered trial-1 blob (the tree
  booted on 2026-11-13) was built from something else. Not investigated further; r1 is what the
  Mac boots now.

## QEMU (emulator/replica)

QEMU 11.1.3, machine `virt`, `-cpu max`, 4 CPUs, TCG, the baseline `Image`, an initramfs made on
the spot by `k114s-qemu-smoke`:

```
qemu-system-aarch64 -machine virt,gic-version=3 -accel tcg,thread=multi -cpu max -smp 4 -m 2G \
  -nographic -no-reboot -nodefaults -serial mon:stdio \
  -kernel build/r1/arch/arm64/boot/Image -initrd initramfs.cpio.zst \
  -append "console=ttyAMA0 panic=-1 rdinit=/init loglevel=7"
```

| Run | Result |
| --- | --- |
| `k114s-qemu-smoke shell build/r1` (busybox userspace, banner, power off) | PASS in 7 s: `release=7.3.0-17.v272-4-ARCH version=#1 SMP PREEMPT K114S-R1-NATIVE Sat Nov 14 2026` |
| `k114s-qemu-smoke console build/r1` (interactive shell on the serial console) | reached the shell; `uname -r` typed into it answered `7.3.0-17.v272-4-ARCH` |
| `k114s-qemu-smoke modules build/r1` with `build/qemu-test-init` (all 1728 modules installed stripped into the initramfs, `modprobe` each) | 243 s. `modprobe ok=1721 failed=7`: `tcrypt ipmi_si cppc_cpufreq sun50i-cpufreq-nvmem stratix10-soc apple-pmp-j613-hwmon xen-pciback` (a self-test module and hardware-specific ones; the individual reasons were not examined). `hid_magicmouse` loaded, taint 1024 (a staging driver), no Oops, BUG or panic in the log |

This shows the natively built kernel boots, runs userspace and loads its modules in an emulator.
The `virt` machine has none of the Mac's hardware.

## Stage 2 and U-Boot

- `k114s-build-stage2` builds Aura as the PKGBUILD does (`RELEASE=1 CHAINLOADING=1 USE_CLANG=1
  ESP_STAGE2=1`, Omarchy logo): `aura/base/build/aura.bin`, 3997696 bytes, the size of the
  installed `/usr/lib/asahi-boot/m1n1.bin`. It is not byte-identical to the installed file, also
  with the installed version tag (`AURA_VERSION_TAG=1.0.0b13-g22b71758-dirty`): the reason was not
  investigated (the package was built on another host, probably with a different compiler
  build). Built only; not run anywhere.
- Aura's Makefile reads `ARCH` as a cross prefix. `env.sh` exports `ARCH=arm64` for Kbuild, so
  the script unsets it.
- Stage 1 is not built (never replaced by this project).
- U-Boot is not built: `boot-ctxr.bin` reuses the installed gzip U-Boot byte for byte
  (`linux/update-boot-ctxr-k114s`). Recipe: `recipe/release3/installer/recipes/uboot-aurora/PKGBUILD`
  (edimoldovan/u-boot `70e990818a89` + `quiet-console.patch`, `apple_m1_defconfig`); it would
  need `swig` and `python-pyelftools` fetched user-locally.

## Not verified

- Nothing from this build area has run on the Mac.
- `setup.sh`'s download of the LLVM archive itself (the test reused the cached file) and its
  behaviour once upstream moves `rustup-init` (the script stops and says so).
- KVM was not tried, on purpose: a guest under an experimental hypervisor port is not worth a
  host hang while other work runs. All QEMU runs are TCG.
- Whether the natively built `Image` behaves like the installed one on hardware. The module
  comparison says the compiler output is the same; the `Image` itself cannot be compared that way.

## Risks and notes for the lead

- Rust code embeds absolute paths of the Rust standard library sources, so kernels and the three
  Rust modules above built here contain the build area's path, including the user name. Binaries
  are not published from this repository; if a bundle is ever shared, build with the area under a
  neutral path (`K114S_BUILD_ROOT`) first.
- `CONFIG_CC_CAN_LINK=y` is new compared with the running kernel. No option in this config
  depends on it today; a config change that enables something behind `CC_CAN_LINK` (samples,
  userspace helpers) would build host programs.
- The area holds about 60 GB with the other workers' trees (toolchain 6 GB, each full build
  output about 9 GB; btrfs reflinks make copies cheap until they diverge). 416 GB were free after.
- The prebuilt tree is only as good as Kbuild's dependency tracking. It held in the tests above;
  for a release candidate, a full build from `src/<variant>` into a fresh output directory
  (11 minutes) removes the question.
- No root step is needed for anything here.
