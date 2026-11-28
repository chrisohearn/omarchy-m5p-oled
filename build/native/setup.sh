#!/bin/bash
# Set up the native (aarch64, on the K114s itself) kernel build area, user-local, no root.
# usage: build/native/setup.sh            root: ${K114S_BUILD_ROOT:-$HOME/k114s-build}
# Idempotent: a step whose result is already there is verified and skipped. Needs: bash, git,
# curl, bsdtar, zstd, python3, make, gcc (host tools), flex, bison, perl, openssl and libelf
# headers, cpio; all present on the Omarchy image. About 25 GB with one full build.
#
# What it pins (see pins/sources.json for the sources, docs/r3-buildenv.md for why):
#   clang/lld/llvm 23.1.3   official LLVM release (the Arch Linux ARM mirror has 23.1.5 by now)
#   Rust 1.98.1             rustup, minimal profile + rust-src + rustfmt (kernel); 1.89.0 for Aura
#   bindgen 0.73.2          built by the kernel tree's own tools/aurora-bindgen/build.py
#   bc, dtc, pahole         Arch Linux ARM packages, extracted (fetch-alarm-pkg)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); repo=$(cd "$here/../.." && pwd)
export B="${K114S_BUILD_ROOT:-$HOME/k114s-build}"
LLVM_VER=23.1.3
LLVM_SHA256=1154f37ec15b5654fcb8cc3a8a2352a4cc4eef44bdff7ddd47fb10ea85c82f01   # the release asset's digest on GitHub
RUSTUP_INIT_SHA256=9f608c142e0e38a78957d0661ba1dfaf0b6fb37184cfaa4b9a0aa57af6184282  # rustup-init aarch64, as fetched 2026-11-14
KERNEL_PIN=a34d26c255c29bdd5548ace985d0d9c8e083aab1
KERNEL_SINCE=2026-10-01
KERNEL_PRS="1173 1568 1605 1607 1615 1645 1646 1647 1648 1650 1688 1696 1714 1719 1725 1737 1787 1789 1791 1830 1841 1844 1856 1859 1868 1873 1885 1921"
RECIPE_COMMIT=cfbe533c8b5fadf9600bd0145b56883130f11ce6      # betizzel/omarchy-m5, release omarchy-j714s-3
SERIES_SHA256=a3140b092b5d68543bc89d261682f577ef52341499bbe58416a80ae999329230   # linux-j714s-27.2.patch
BASE_TREE=8ab0355a1d01edb824747f38e7c6de44239ad55f           # git tree of pin + series
AURA_PIN=22b71758dfd048f6a874073db55fbe6bd1d17f44
AURA_SERIES_SHA256=37d1231652b96fce4d00fc84452ac74743b69d132bbf80eee9b3699e1fc07c78
AURA_BASE_TREE=a708dc46429358b16e84a8852e3397f029981c11      # git tree of Aura pin + series
say() { echo "setup: $*"; }
mkdir -p "$B"/{bin,tools,pkgcache,logs,recipe,src,build,out,aura}

# 0. scripts
install -m644 "$here/env.sh" "$B/env.sh"
for f in kmake fetch-alarm-pkg qemu-system-aarch64 k114s-qemu-smoke k114s-dtb k114s-build-stage2 k114s-cmp-modules; do install -m755 "$here/$f" "$B/bin/$f"; done
install -m644 "$here/README-build.md" "$B/README-build.md"
source "$B/env.sh"

# 1. LLVM
if [[ ! -x $K114S_LLVM/bin/clang ]]; then
  t=$B/pkgcache/LLVM-$LLVM_VER-Linux-ARM64.tar.zst
  [[ -s $t ]] || curl -fL --retry 3 -o "$t" "https://github.com/llvm/llvm-project/releases/download/llvmorg-$LLVM_VER/LLVM-$LLVM_VER-Linux-ARM64.tar.zst"
  echo "$LLVM_SHA256  $t" | sha256sum -c --quiet -
  # long-window zstd: bsdtar refuses it ("Frame requires too much memory"), zstd --long=31 reads it
  mkdir -p "$K114S_LLVM" && zstd -dc --long=31 "$t" | tar -x -C "$K114S_LLVM" --strip-components 1
fi
clang --version | head -1 | grep -q "clang version $LLVM_VER " || { echo "clang is not $LLVM_VER" >&2; exit 1; }
say "clang: $(clang --version | head -1)"

# 2. Rust
if [[ ! -x $CARGO_HOME/bin/rustup ]]; then
  r=$B/pkgcache/rustup-init
  [[ -s $r ]] || curl -fL --retry 3 -o "$r" https://static.rust-lang.org/rustup/dist/aarch64-unknown-linux-gnu/rustup-init
  echo "$RUSTUP_INIT_SHA256  $r" | sha256sum -c --quiet - || { echo "rustup-init changed upstream: check it against https://static.rust-lang.org/rustup/dist/aarch64-unknown-linux-gnu/rustup-init.sha256 and update the pin" >&2; exit 1; }
  chmod +x "$r"; "$r" -y --no-modify-path --profile minimal --default-toolchain none
fi
rustup toolchain install 1.98.1 --profile minimal --component rust-src,rustfmt >/dev/null
rustup default 1.98.1 >/dev/null
say "rustc: $(rustc --version)"

# 3. bc, dtc, pahole
[[ -x $K114S_ALARM/bin/bc && -x $K114S_ALARM/bin/dtc && -x $K114S_ALARM/bin/pahole ]] || fetch-alarm-pkg "$B/tools/alarm" bc dtc pahole
say "dtc: $(dtc --version)  pahole: $(pahole --version)"

# 4. kernel source mirror: integration/aurora since $KERNEL_SINCE and the pull request heads the plan names
if [[ ! -d $B/src/linux.git ]]; then
  git init -q --bare "$B/src/linux.git"
  git -C "$B/src/linux.git" remote add origin https://github.com/aurora-silicon/linux.git
fi
if ! git -C "$B/src/linux.git" cat-file -e "$KERNEL_PIN^{commit}" 2>/dev/null; then
  git -C "$B/src/linux.git" fetch --shallow-since="$KERNEL_SINCE" origin '+refs/heads/integration/aurora:refs/remotes/origin/integration/aurora'
  for n in $KERNEL_PRS; do
    git -C "$B/src/linux.git" fetch -q --shallow-since="$KERNEL_SINCE" origin "+refs/pull/$n/head:refs/remotes/origin/pr/$n" || say "pull request $n not fetched"
  done
fi

# 5. recipe: betizzel/omarchy-m5 at release 3
[[ -d $B/recipe/omarchy-m5/.git ]] || git clone -q https://github.com/betizzel/omarchy-m5.git "$B/recipe/omarchy-m5"
rec=$B/recipe/release3/installer/recipes
if [[ ! -s $rec/linux-aurora-j714s/linux-j714s-27.2.patch ]]; then
  mkdir -p "$B/recipe/release3"
  git -C "$B/recipe/omarchy-m5" archive "$RECIPE_COMMIT" installer/recipes/linux-aurora-j714s installer/recipes/m1n1-aurora-j714s installer/recipes/uboot-aurora patches/j714s-27.2 | tar -x -C "$B/recipe/release3"
fi
echo "$SERIES_SHA256  $rec/linux-aurora-j714s/linux-j714s-27.2.patch" | sha256sum -c --quiet -
echo "$AURA_SERIES_SHA256  $rec/m1n1-aurora-j714s/aura-j714s-27.2.patch" | sha256sum -c --quiet -

# 6. src/base = pin + series (git am keeps each patch's author) + the package's localversion file
if [[ ! -d $B/src/base/.git ]]; then
  git init -q "$B/src/base"; cd "$B/src/base"
  git remote add origin https://github.com/aurora-silicon/linux.git
  git config user.name k114s-build; git config user.email k114s-build@localhost; git config advice.detachedHead false
  git fetch -q --update-shallow "$B/src/linux.git" '+refs/remotes/origin/*:refs/remotes/origin/*'
  git checkout -q -b base "$KERNEL_PIN"
  git am -q "$rec/linux-aurora-j714s/linux-j714s-27.2.patch"
  [[ $(git rev-parse 'HEAD^{tree}') == "$BASE_TREE" ]] || { echo "src/base is not pin + series" >&2; exit 1; }
  echo "-17.v272-4" > localversion.10-pkgrel
  git add localversion.10-pkgrel
  git commit -q -m "k114s-build: localversion.10-pkgrel (-17.v272-4), as betizzel's PKGBUILD prepare() writes it"
fi
[[ $(git -C "$B/src/base" rev-parse 'base~1^{tree}') == "$BASE_TREE" ]] || { echo "src/base: branch base is not pin + series + localversion" >&2; exit 1; }
say "src/base: $(git -C "$B/src/base" log --oneline -1 base)"

# 7. bindgen 0.73.2, the kernel tree's own recipe (pinned source, two patches, compile tests)
if [[ ! -x $K114S_BINDGEN ]]; then
  ( cd "$B/src/base" && python3 tools/aurora-bindgen/build.py --output-dir "$B/tools/private-bindgen" ) > "$B/logs/private-bindgen.log" 2>&1
fi
say "bindgen: $("$K114S_BINDGEN" --version)"

# 8. src/r1 = base + pull request 1568 as the running kernel has it (patch, not git am: one hunk needs fuzz)
if [[ ! -d $B/src/r1/.git ]]; then
  cp -a --reflink=auto "$B/src/base" "$B/src/r1"; cd "$B/src/r1"
  git checkout -q -b r1
  patch -Np1 --no-backup-if-mismatch < "$repo/patches/linux/pr1568.patch"
  git add -A
  git commit -q --author='Joshua Warren <816217+joshuaswarren@users.noreply.github.com>' \
    -m 'HID: K114c/K114s trackpad: aurora-silicon/linux pull request 1568 (4 patches, one commit)' \
    -m 'Applied with patch -Np1 from patches/linux/pr1568.patch, as the running K114S-R1 kernel was built. Source: https://github.com/aurora-silicon/linux/pull/1568 head 1e065585d3da, GPL-2.0.'
fi
say "src/r1: $(git -C "$B/src/r1" log --oneline -1 r1)"

# 9. Aura (Stage 2 source) = pin + betizzel's 7 patches
aura_base_recovery() {
  printf 'setup: could not prepare the pinned Aura base tree at %s/aura/base.\n' "$B" >&2
  echo 'setup: if that path exists, move it to an unused backup path, then rerun setup.' >&2
  exit 1
}
if [[ ! -d $B/aura/base/.git ]]; then
  git clone -q https://github.com/aurora-silicon/aura.git "$B/aura/base" || aura_base_recovery
  cd "$B/aura/base"
  git config user.name k114s-build; git config user.email k114s-build@localhost
  git checkout -q -b base "$AURA_PIN" || aura_base_recovery
  git am -q "$rec/m1n1-aurora-j714s/aura-j714s-27.2.patch" || aura_base_recovery
fi
[[ $(git -C "$B/aura/base" rev-parse --verify 'refs/heads/base^{tree}' 2>/dev/null) == "$AURA_BASE_TREE" ]] || aura_base_recovery
say "aura/base: $(git -C "$B/aura/base" log --oneline -1 refs/heads/base)"
cat <<MSG
setup: done. Not done by this script (commands as run on 2026-11-14, see docs/r3-buildenv.md):
  QEMU:      fetch-alarm-pkg \$B/tools/qemu qemu-system-aarch64 qemu-common capstone rdma-core libslirp vde2 libxdp ndctl libaio
  baseline:  cd \$B/src/r1 && mkdir -p \$B/build/r1 && zcat /proc/config.gz > \$B/recipe/running-K114S-R1.config \\
             && cp \$B/recipe/running-K114S-R1.config \$B/build/r1/.config && export K114S_LABEL=K114S-R1-NATIVE \\
             && kmake O=\$B/build/r1 olddefconfig && kmake O=\$B/build/r1 Image modules dtbs
  prebuilt:  cp -a --reflink=auto \$B/src/r1 \$B/src/r1-built && cd \$B/src/r1-built && echo /out/ >> .git/info/exclude \\
             && mkdir out && cp \$B/recipe/running-K114S-R1.config out/.config && kmake O=out olddefconfig \\
             && kmake O=out Image modules dtbs
Then read $B/README-build.md.
MSG
