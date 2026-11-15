#!/bin/bash
# Checks of a built linux-k114s package that need no root and change nothing:
#   - one release directory under usr/lib/modules, ending in -ARCH, different from linux-aurora's
#   - vmlinuz, pkgbase (= linux-k114s), modules.dep, dtbs/t6050-k114s.dtb present; no build/source links
#   - dtbs are exactly the names in dtbs.list (update-m1n1 puts all of them into m1n1/boot.bin)
#   - every .ko has the vermagic of the release; modinfo reads it with the package's own depmod data
#   - depmod -a over the package tree reports no error and no unresolved symbol (-e)
#   - no file in common with an installed package of the other kernel (pacman -Qlq linux-aurora), only directories
#   - the kernel inside vmlinuz carries the same release string
# usage: check-package.sh PACKAGE.pkg.tar.zst [OTHER-KERNEL-PACKAGE=linux-aurora] [Module.symvers]
# The symbol check needs the build's Module.symvers (default $K114S_BUILD_ROOT/build/r3a/Module.symvers); without it only plain depmod -a runs.
set -u
pkg=${1:?usage: check-package.sh PACKAGE.pkg.tar.zst [other kernel package] [Module.symvers]}; other=${2:-linux-aurora}
symvers=${3:-${K114S_BUILD_ROOT:-$HOME/k114s-build}/build/r3a/Module.symvers}
here=$(cd "$(dirname "$0")" && pwd); w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
fail=0; ok() { echo "ok   $*"; }; no() { echo "FAIL $*"; fail=1; }
bsdtar -xf "$pkg" -C "$w" || { echo "cannot unpack $pkg"; exit 2; }
n=$(ls "$w/usr/lib/modules" | wc -l); [ "$n" = 1 ] && ok "one module directory" || no "$n module directories"
rel=$(ls "$w/usr/lib/modules"); m=$w/usr/lib/modules/$rel
case $rel in *-ARCH) ok "release $rel ends in -ARCH" ;; *) no "release $rel does not end in -ARCH" ;; esac
if pacman -Q "$other" >/dev/null 2>&1; then
  orel=$(pacman -Qlq "$other" | sed -n 's|^/usr/lib/modules/\([^/]*\)/$|\1|p' | head -1)
  [ -n "$orel" ] && [ "$orel" != "$rel" ] && ok "release differs from $other's ($orel)" || no "release equals $other's"
  comm -12 <(bsdtar -tf "$pkg" | grep -v '^\.' | sed 's|^|/|' | grep -v '/$' | sort) <(pacman -Qlq "$other" | grep -v '/$' | sort) > "$w/common"
  [ ! -s "$w/common" ] && ok "no file in common with $other" || { no "files in common with $other:"; head "$w/common"; }
fi
[ -f "$m/vmlinuz" ] && ok "vmlinuz $(stat -c %s "$m/vmlinuz") bytes" || no "no vmlinuz"
[ "$(cat "$m/pkgbase" 2>/dev/null)" = linux-k114s ] && ok "pkgbase is linux-k114s" || no "pkgbase"
[ -s "$m/modules.dep" ] && [ -s "$m/modules.builtin" ] && ok "modules.dep and modules.builtin present" || no "modules.dep / modules.builtin"
[ -z "$(find "$w" -type l)" ] && ok "no symbolic links (no build/source)" || { no "symbolic links:"; find "$w" -type l; }
diff <(ls "$m/dtbs") "$here/dtbs.list" >/dev/null && ok "dtbs are exactly dtbs.list ($(wc -l < "$here/dtbs.list"))" || no "dtbs differ from dtbs.list"
[ -s "$m/dtbs/t6050-k114s.dtb" ] && ok "t6050-k114s.dtb present" || no "t6050-k114s.dtb missing"
# The packaged tree is the kernel tree's own preliminary t6050-k114s.dts, not the r3a tree of dts/ (which the Stage 2 carries).
# Printed so nobody takes it for the r3a tree: it lacks the N1, USB and SMC sensor nodes.
echo "info packaged t6050-k114s.dtb sha256 $(sha256sum "$m/dtbs/t6050-k114s.dtb" | cut -c1-64) (the preliminary kernel tree, NOT the r3a tree 154568fe...)"
bad=$(find "$m" -name '*.ko' -print0 | xargs -0 -n200 modinfo -F vermagic | grep -vc "^$rel ")
total=$(find "$m" -name '*.ko' | wc -l)
[ "$bad" = 0 ] && ok "$total modules, all with vermagic $rel" || no "$bad of $total modules have another vermagic"
if [ -s "$symvers" ]; then sv=(-e -E "$symvers"); what="depmod -a -e"; else sv=(); what="depmod -a (no Module.symvers, symbols not checked)"; fi
# the duplicate alias spi:tpm_tis_spi warning is the same on the installed linux-aurora tree
out=$(depmod -b "$w/usr" -a "${sv[@]}" -w "$rel" 2>&1 | grep -v 'duplicate module alias\|^spi:tpm_tis_spi')
[ -z "$out" ] && ok "$what: no error, no unresolved symbol" || { no "$what:"; echo "$out" | head; }
strings -a "$m/vmlinuz" | grep -q "Linux version $rel " && ok "vmlinuz banner names $rel" || no "vmlinuz banner"
[ $fail = 0 ] && echo "check-package: all passed" || echo "check-package: FAILED"
exit $fail
