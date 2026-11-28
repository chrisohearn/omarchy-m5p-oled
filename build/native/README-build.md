# Building the K114s kernel on the K114s itself

Everything here is user-local under `~/k114s-build` (called `$B` below). Nothing needs root and
nothing is installed system-wide. Installing a result (kernel, module, device tree, Stage 2) is a
root step: hand the lead the exact commands, do not try them.

The toolchain is checked: `build/r1` is the running kernel (K114S-R1) rebuilt here, and 1725 of
its 1728 modules are byte-identical in code and data to the installed ones (the other three embed
a build path). So a variant differs from the running kernel by its source changes only.

## TL;DR (fast path: about 1 minute to the first build, seconds after that)

```bash
source ~/k114s-build/env.sh                        # PATH, toolchain, $B; once per shell (bash)
cp -a --reflink=auto $B/src/r1-built $B/src/NAME   # NAME = your worker key (usb, sound, ...); 2 s on btrfs
cd $B/src/NAME && git checkout -b NAME             # a git repository WITH a finished build in ./out
#   ... git cherry-pick -x <upstream sha> / git am / edit / scripts/config --file out/.config ...
export K114S_LABEL=K114S-R3-NAME                   # shows up in `uname -v`
kmake O=out olddefconfig                           # only needed after a config change
kmake -s O=out kernelrelease                       # must print 7.3.0-17.v272-4-ARCH
kmake O=out Image modules > $B/logs/NAME.log 2>&1  # incremental; -j10 by default, do not go higher
kmake O=out apple/t6050-k114s.dtb                  # device trees: only what you need
k114s-cmp-modules out                              # which modules now differ from the installed kernel
k114s-qemu-smoke shell out                         # emulator boot test, 7 s
```

`src/r1-built` is `src/r1` (the running kernel's source) with a complete build in `out/`.
Because the output directory sits directly inside the source tree, Kbuild records relative paths,
so a copy of the tree is a valid build tree: the first `kmake` in a copy recompiles the Rust
objects and the vDSO and relinks (63 s measured), a run with nothing to do takes 5 s, and a
one-file driver change took 6 s. **Always `O=out` from the top of your tree** (`O=$PWD/out` is the
same). Any other output directory starts a full build.

`kmake` is `make LLVM=1 ARCH=arm64 BINDGEN=<private bindgen> RUSTFMT=<1.98.1> LOCALVERSION=` with
`KBUILD_BUILD_HOST=archlinux KBUILD_BUILD_USER=linux-aurora`, default `-j$K114S_JOBS` (10). It
works from any shell (it sources `env.sh` itself): `~/k114s-build/bin/kmake ...`.

## Full build from clean sources (about 11 minutes at -j10 with other builds running)

```bash
cp -a --reflink=auto $B/src/r1 $B/src/NAME && cd $B/src/NAME && git checkout -b NAME
mkdir -p $B/build/NAME && cp $B/recipe/running-K114S-R1.config $B/build/NAME/.config
kmake O=$B/build/NAME olddefconfig && kmake -s O=$B/build/NAME kernelrelease
kmake O=$B/build/NAME Image modules
```

Use this when you want an output directory outside the tree, or to prove a result does not
depend on the prebuilt objects. Measured: 469 s (`Image modules`, -j16) and 649 s
(`Image modules dtbs`, -j10), both with the machine at load 30 to 48.

## What is where

| Path | What | Rule |
| --- | --- | --- |
| `env.sh`, `bin/` | environment, `kmake` and the helpers below | do not edit; ask buildenv |
| `tools/llvm-23.1.3` | clang/lld/llvm 23.1.3, the official LLVM Linux-ARM64 release (sha256 equals the release's published digest) | read-only |
| `rustup/`, `cargo/` | rustup with Rust 1.98.1 (+ rust-src, rustfmt) for the kernel and 1.89.0 (+ `aarch64-unknown-none-softfloat`) for Aura | read-only |
| `tools/private-bindgen` | bindgen 0.73.2 built by the kernel tree's `tools/aurora-bindgen/build.py` | read-only |
| `tools/alarm/usr` | bc 1.08.2, dtc 1.8.1, pahole 1.32 (Arch Linux ARM packages, extracted) | add packages with `bin/fetch-alarm-pkg` |
| `tools/qemu` | qemu-system-aarch64 11.1.3 and its libraries; use `bin/qemu-system-aarch64` | read-only |
| `src/linux.git` | bare mirror of aurora-silicon/linux: `integration/aurora` since 2026-10-01 and 28 pull request heads as `refs/remotes/origin/pr/N` | fetch only |
| `src/base` | pin `a34d26c255c2` + betizzel's 19 patches (release omarchy-j714s-3) + `localversion.10-pkgrel`. Branch `base`. | **never edit or build in it** |
| `src/r1` | `base` + `patches/linux/pr1568.patch` = the source of the running kernel (K114S-R1). Branch `r1`. Clean, no build. | **never edit**; copy it |
| `src/r1-built` | the same source with a complete build in `out/` | **never edit, never run kmake in it**; copy it |
| `build/r1` | the baseline build of `src/r1` (out-of-tree) | **read-only reference** |
| `src/NAME` (and `build/NAME`) | your variant | yours; prefix extra ones with your key (`usb-try2`) |
| `recipe/release3` | betizzel/omarchy-m5 at `cfbe533c8b` (release 3): `installer/recipes/{linux-aurora-j714s,m1n1-aurora-j714s,uboot-aurora}` and `patches/j714s-27.2` | read-only |
| `recipe/omarchy-m5` | full clone of betizzel/omarchy-m5 (newer recipes, e.g. v272-5/-6) | read-only |
| `recipe/running-K114S-R1.config` | `zcat /proc/config.gz` of the running kernel | read-only; the start for every `.config` |
| `aura/base` | aurora-silicon/aura `22b71758` + betizzel's 7 patches. Branch `base`. | copy before changing |
| `pkgcache/`, `logs/` | downloads, build logs | |
| `<key>/` | each worker's own scratch and `STATUS.md` | |

## Sources and patches

- Start from `src/r1-built` (or `src/r1`) unless you have a reason to start from `src/base`. To
  use PR 1830 instead of PR 1568: `git revert` the top commit of `r1` in your copy, then apply 1830.
- The trees are git repositories (shallow since 2026-10-01) with the upstream refs already there:
  `git log origin/integration/aurora`, `git cherry-pick -x <sha>`, `git show origin/pr/1648`.
  Every kernel commit named in `docs/upstream-applicability.md` and `docs/matrix.md` is present.
  To refresh: `git -C $B/src/linux.git fetch origin` then, in your tree,
  `git fetch --update-shallow $B/src/linux.git '+refs/remotes/origin/*:refs/remotes/origin/*'`.
  A pull request head that is missing (in your tree, straight from GitHub; keep the shallow limit or
  git downloads the whole history): `git fetch --shallow-since=2026-10-01 origin pull/N/head:refs/remotes/origin/pr/N`.
- `patches/linux/pr1568.patch` does not apply with `git am`/`git apply` (one hunk needs fuzz);
  `patch -Np1 --no-backup-if-mismatch` is how the running kernel got it and how `src/r1` has it.
- Commit as you go (`git commit`; identity is preset to `k114s-build`). To hand a change to the
  integration repo: `git format-patch r1..HEAD` (or `base..HEAD`) and keep the upstream author,
  source PR/commit and license with each patch, as `NOTICE.md` does.

## Configuration

- The `.config` in `out/` (and `recipe/running-K114S-R1.config`) is the running kernel's. Change
  options with `scripts/config --file out/.config -e FOO -m BAR -d BAZ`, then
  `kmake O=out olddefconfig`, then check that Kconfig kept what you asked for
  (`grep CONFIG_FOO out/.config`): `olddefconfig` drops options silently when a dependency is missing.
- Expected differences from the running config on this toolchain, and nothing else:
  `CONFIG_CC_VERSION_TEXT` (the official LLVM build prints its source revision) and
  `CONFIG_CC_CAN_LINK=y` (the running kernel was cross-built; here the compiler can link
  userspace). Compare with:
  `diff <(grep -v '^#' $B/recipe/running-K114S-R1.config | sort) <(grep -v '^#' out/.config | sort)`
- The release must stay `7.3.0-17.v272-4-ARCH` if modules are to load into the running kernel or
  the result is to replace it in place (there is no MODVERSIONS; vermagic is the only check).
  It comes from `Makefile` (7.3.0) + `localversion.10-pkgrel` (`-17.v272-4`) + `CONFIG_LOCALVERSION="-ARCH"`.
  A deliberately different release (so `/usr/lib/modules/<release>` does not collide): change
  `localversion.10-pkgrel` in your tree; it must still end in `-ARCH` (boot bundle discovery).
  Changing the release rebuilds a lot.
- betizzel's required-options check:
  `python3 $B/recipe/release3/installer/recipes/linux-aurora-j714s/validate-config.py $B/recipe/release3/installer/recipes/linux-aurora-j714s/j714s-required.config out/.config`

## Building

- After any change: `kmake O=out Image modules` again (or only `modules` when nothing built-in
  changed). Only what changed is recompiled.
- **Do not use the single-module target** (`kmake ... drivers/hid/hid-magicmouse.ko`). For a module
  that uses another module's symbols it fails in modpost (`symbol 'apple_taptic_send' undefined!`)
  and leaves a one-line `modules.order` behind, after which `modules` keeps failing the same way.
  Recovery: `rm out/modules.order && kmake O=out modules`.
  Compiling one object to check syntax is fine: `kmake O=out drivers/hid/hid-magicmouse.o`.
- Device trees: `kmake O=out apple/t6050-k114s.dtb` (any `apple/<name>.dtb`), or all: `kmake O=out dtbs`
  (4 s). The kernel tree's own `t6050-k114s.dtb` is not what this Mac boots; see the next point.
- The K114s tree of the integration repository (`dts/` there), built against a kernel tree
  without touching it: `k114s-dtb REPO/dts t6050-k114s-r1 OUTDIR [KTREE]` (prints the sha256; KTREE
  defaults to `src/base`; give your tree when your dts needs newer `.dtsi` files). The r1 tree
  must give `2ea22d26b2a1c81526e77e7f29eaff46def5310a9512be769ff3ed50465f4dd2`, and does.
- `-j`: the default is 10. Several workers build at once on 18 cores; do not raise it.
- The label: `export K114S_LABEL=K114S-R3-NAME` (or `KBUILD_BUILD_TIMESTAMP` for the whole string).
  Changing it relinks `vmlinux` only.
- There is no `/usr/bin/time` here; use the shell's `time` or `$SECONDS`.

## Outputs (`out/` = your output directory)

| File | Where |
| --- | --- |
| kernel image | `out/arch/arm64/boot/Image` (uncompressed; the package installs it as `vmlinuz`) |
| modules | `out/**/*.ko` (unstripped, with debug info); strip one with `llvm-strip --strip-debug -o x.ko out/path/x.ko` |
| module tree | `kmake O=out INSTALL_MOD_PATH=$B/out/NAME/usr INSTALL_MOD_STRIP=1 DEPMOD=/usr/bin/depmod modules_install` -> `$B/out/NAME/usr/lib/modules/<release>/` |
| device trees | `out/arch/arm64/boot/dts/apple/*.dtb` |
| config, symbols | `out/.config`, `out/System.map`, `out/vmlinux`, `out/Module.symvers` |
| release string | `out/include/config/kernel.release` |

Checks before you report a build:

- `modinfo -F vermagic out/drivers/hid/hid-magicmouse.ko` prints
  `7.3.0-17.v272-4-ARCH SMP preempt mod_unload aarch64` (the running kernel's).
- `k114s-cmp-modules out` lists the modules whose code or data differ from the installed kernel's
  (`/usr/lib/modules/<release>`), `NEW` and `GONE` ones included. The baseline answer is three
  `DIFF(.rodata)` lines: `apple-pmp`, `apple-sep`, `snd-soc-t8152-aop-audio` (Rust build paths).
  Everything else in your list is your change. It cannot see changes to built-in code: if
  anything built into `Image` changed, the Image has to be replaced, not just modules.

## QEMU smoke test (emulator evidence only)

```bash
k114s-qemu-smoke shell   out      # boots to a busybox userspace, prints the banner, powers off; exit 0 = PASS (7 s)
k114s-qemu-smoke console out      # interactive shell on the serial console (Ctrl-A X quits)
K114S_QEMU_TEST_INIT=REPO/build/qemu-test-init k114s-qemu-smoke modules out   # modprobe every built module (4 min)
```

Shell and modules modes pass only when QEMU exits successfully within the timeout, `tee` records
the serial log successfully, and the log contains the expected markers. A modules pass means the
test run completed. Read the `K114S-TEST modprobe` lines for individual module failures.

Machine `virt`, `-cpu max`, 4 CPUs, TCG (pure emulation; KVM is deliberately not used on this
machine). Baseline results: shell PASS; modules `ok=1721 failed=7` (`tcrypt ipmi_si cppc_cpufreq
sun50i-cpufreq-nvmem stratix10-soc apple-pmp-j613-hwmon xen-pciback`), no Oops. A variant should
give the same seven. This proves the Image boots and runs userspace and that modules load in an
emulator. It proves nothing about K114s hardware: label it `emulator/replica`.

## Stage 2 (Aura, the m1n1-derived loader) and U-Boot

- Recipe: `recipe/release3/installer/recipes/m1n1-aurora-j714s/PKGBUILD`. Source `aura/base`.
  `k114s-build-stage2 [VARIANT]` builds `aura/VARIANT/build/aura.bin` (the file packaged as
  `/usr/lib/asahi-boot/m1n1.bin`): Rust 1.89.0 with `aarch64-unknown-none-softfloat`, clang 23.1.3,
  `make RELEASE=1 CHAINLOADING=1 USE_CLANG=1 LOGO_DIR=... BUILTIN_LOGO=omarchy ESP_STAGE2=1`
  (under a minute). For a variant: `cp -a --reflink=auto $B/aura/base $B/aura/NAME`.
  Aura's Makefile reads `ARCH` as a cross prefix, so the script unsets the `ARCH=arm64` that
  `env.sh` exports; do the same if you call its `make` yourself (`env -u ARCH make ...`).
  `aura/base` also has upstream `origin/main` for cherry-picks (for example aura #226).
- Stage 1 is never rebuilt or enrolled by this project. aurora-silicon/m1n1 is not used.
- `m1n1/boot-ctxr.bin` on the ESP is `<Aura Stage 2><one K114s device tree><gzip U-Boot>`; the
  repository's `linux/update-boot-ctxr-k114s` assembles it (root).
- U-Boot recipe: `recipe/release3/installer/recipes/uboot-aurora/PKGBUILD` (edimoldovan/u-boot
  `70e990818a89` + `quiet-console.patch`, `apple_m1_defconfig`, output `u-boot-nodtb.bin`). Not
  built here: the installed one is reused byte for byte from `boot.bin`. It would need `swig` and
  `python-pyelftools` fetched with `bin/fetch-alarm-pkg`.

## More tools

`bin/fetch-alarm-pkg PREFIX PKG...` downloads Arch Linux ARM packages from the mirror this
machine uses, checks the sha256 from the repository database and extracts them under PREFIX
(use `$B/tools/alarm` for build tools: it is already on `PATH` and `LD_LIBRARY_PATH`). It does
not resolve dependencies: run `ldd` on what you fetched and add what is missing.
After a transfer failure, rerun the same command. It fetches incomplete cache entries again
and reuses complete entries.

The whole area can be recreated from nothing with `build/native/setup.sh` of the integration
repository (branch `r3/buildenv`); `docs/r3-buildenv.md` there has the evidence behind the
numbers above.
