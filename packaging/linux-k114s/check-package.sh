#!/bin/bash
# Checks of a built linux-k114s package that need no root and change nothing:
#   - one release directory under usr/lib/modules, ending in -ARCH, different from linux-aurora's
#   - the package name matches the candidate of the release (linux-k114s for -k114s-r3a-ARCH, linux-k114s-r3b
#     for -k114s-r3b-ARCH, linux-k114s-r3b-t1 for the touch trial); pkgbase in .PKGINFO and the module directory's pkgbase file equal it, and the
#     config lies under usr/share/<that name>/
#   - vmlinuz, modules.dep, dtbs/t6050-k114s.dtb present; no build/source links
#   - dtbs are exactly the names in dtbs.list (update-m1n1 puts all of them into m1n1/boot.bin)
#   - every .ko has the vermagic of the release; modinfo reads it with the package's own depmod data
#   - depmod -a over the package tree reports no error and no unresolved symbol (-e)
#   - no file in common with an installed package of the other kernel (pacman -Qlq linux-aurora), only directories
#   - the kernel inside vmlinuz carries the same release string
#   - a brightness build (version ...r3b.b<N>, linux-k114s-r3b) carries the floor of patches/linux/brightness 0006 in appledrm
#   - an HDR build (version ...r3b.c<N>) also carries the floor, and hdr 0001-0003: the Display P3 default and the 500-nit EDR cap
#     (r3f: the Display P3 default and a cap parameter whose default is 0, as upstream's EDR value #2694 wants)
#   - from r3b.c3, appledrm also has fw27_panel_vrr_min with its default of 24 (vrr 0001)
#   - from r3b.c4, apple-sep admits the K114s to its T6050 profile (sep 0001, Touch ID)
# usage: check-package.sh PACKAGE.pkg.tar.zst [OTHER-KERNEL-PACKAGE=linux-aurora] [Module.symvers]
# Run it once per other kernel (linux-aurora, and linux-k114s for an r3b package): each must be installed.
# The symbol check needs the build's Module.symvers (default $K114S_BUILD_ROOT/build/${K114S_CAND:-r3a}/Module.symvers); without it only plain depmod -a runs.
set -u
pkg=${1:?usage: check-package.sh PACKAGE.pkg.tar.zst [other kernel package] [Module.symvers]}; other=${2:-linux-aurora}
symvers=${3:-${K114S_BUILD_ROOT:-$HOME/k114s-build}/build/${K114S_CAND:-r3a}/Module.symvers}
here=$(cd "$(dirname "$0")" && pwd); w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
fail=0; skipped=0; ok() { echo "ok   $*"; }; no() { echo "FAIL $*"; fail=1; }
bsdtar -xf "$pkg" -C "$w" || { echo "cannot unpack $pkg"; exit 2; }
n=$(ls "$w/usr/lib/modules" | wc -l); [ "$n" = 1 ] && ok "one module directory" || no "$n module directories"
rel=$(ls "$w/usr/lib/modules"); m=$w/usr/lib/modules/$rel
case $rel in *-ARCH) ok "release $rel ends in -ARCH" ;; *) no "release $rel does not end in -ARCH" ;; esac
if pacman -Q "$other" >/dev/null 2>&1; then
  orel=$(pacman -Qlq "$other" | sed -n 's|^/usr/lib/modules/\([^/]*\)/$|\1|p' | head -1)
  [ -n "$orel" ] && [ "$orel" != "$rel" ] && ok "release differs from $other's ($orel)" || no "release equals $other's"
  comm -12 <(bsdtar -tf "$pkg" | grep -v '^\.' | sed 's|^|/|' | grep -v '/$' | sort) <(pacman -Qlq "$other" | grep -v '/$' | sort) > "$w/common"
  [ ! -s "$w/common" ] && ok "no file in common with $other" || { no "files in common with $other:"; head "$w/common"; }
else
  # Said, not passed silently: without the other kernel installed, the two checks against it did not run.
  echo "SKIP $other is not installed: the release-differs and no-common-file checks against it did not run"
  skipped=2
fi
[ -f "$m/vmlinuz" ] && ok "vmlinuz $(stat -c %s "$m/vmlinuz") bytes" || no "no vmlinuz"
info() { sed -n "s/^$1 = //p" "$w/.PKGINFO"; }
case $rel in
  *-k114s-r3b-t1-ARCH) want=linux-k114s-r3b-t1 ;;
  *-k114s-r3b-ARCH) want=linux-k114s-r3b ;;
  *-k114s-r3a-ARCH) want=linux-k114s ;;
  *-k114s-r3c-ARCH) want=linux-k114s ;;   # r3c takes the r3a slot (docs/r3c-kernel.md)
  *-k114s-r3d-ARCH) want=linux-k114s ;;   # r3d replaces r3c in that slot (docs/r3d-kernel.md)
  *-k114s-r3e-ARCH) want=linux-k114s-r3b ;;   # r3e takes the r3b slot, the Backup beside r3d (docs/r3e-kernel.md)
  *-k114s-r3e1-ARCH) want=linux-k114s ;;   # r3e1 takes the linux-k114s slot, the Backup beside r3e (docs/r3e-kernel.md)
  *-k114s-r3f-ARCH) want=linux-k114s-r3b ;;   # r3f takes the linux-k114s-r3b slot, the Backup beside r3e1 (docs/r3f-kernel.md)
  *) want= ;;
esac
name=$(info pkgname); base=$(info pkgbase)
[ -n "$want" ] && [ "$name" = "$want" ] && ok "package name $name fits release $rel" || no "package name '$name' for release $rel (want '${want:-a k114s r3a, r3b, r3b-t1, r3c, r3d, r3e, r3e1 or r3f release}')"
[ "$base" = "$name" ] && ok "pkgbase $base equals the package name" || no "pkgbase '$base' is not the package name '$name'"
[ "$(cat "$m/pkgbase" 2>/dev/null)" = "$name" ] && ok "module directory pkgbase file is $name" || no "module directory pkgbase file is '$(cat "$m/pkgbase" 2>/dev/null)', not '$name'"
[ -f "$w/usr/share/$name/config-$rel" ] && [ "$(ls "$w/usr/share")" = "$name" ] && ok "config at usr/share/$name/config-$rel" || no "config not (only) at usr/share/$name/config-$rel"
[ "$other" != "$name" ] || no "the other kernel package is this package's own name ($name)"
[ -s "$m/modules.dep" ] && [ -s "$m/modules.builtin" ] && ok "modules.dep and modules.builtin present" || no "modules.dep / modules.builtin"
[ -z "$(find "$w" -type l)" ] && ok "no symbolic links (no build/source)" || { no "symbolic links:"; find "$w" -type l; }
diff <(ls "$m/dtbs") "$here/dtbs.list" >/dev/null && ok "dtbs are exactly dtbs.list ($(wc -l < "$here/dtbs.list"))" || no "dtbs differ from dtbs.list"
[ -s "$m/dtbs/t6050-k114s.dtb" ] && ok "t6050-k114s.dtb present" || no "t6050-k114s.dtb missing"
# The packaged tree is the kernel tree's own preliminary t6050-k114s.dts, not a tree of dts/ (which the Stage 2 carries).
# Printed so nobody takes it for an r3 tree: it lacks the N1, USB and SMC sensor nodes.
echo "info packaged t6050-k114s.dtb sha256 $(sha256sum "$m/dtbs/t6050-k114s.dtb" | cut -c1-64) (the preliminary kernel tree, NOT an r3 tree from dts/)"
bad=$(find "$m" -name '*.ko' -print0 | xargs -0 -n200 modinfo -F vermagic | grep -vc "^$rel ")
total=$(find "$m" -name '*.ko' | wc -l)
[ "$bad" = 0 ] && ok "$total modules, all with vermagic $rel" || no "$bad of $total modules have another vermagic"
if [[ $want == linux-k114s-r3b-t1 ]]; then
  kiwi=$m/kernel/drivers/hid/hid-apple-mtp-kiwi.ko
  [[ -s $kiwi ]] && ok "touchscreen Kiwi module present" || no "touchscreen Kiwi module missing"
fi
if [ -s "$symvers" ]; then sv=(-e -E "$symvers"); what="depmod -a -e"; else sv=(); what="depmod -a (no Module.symvers, symbols not checked)"; fi
# the duplicate alias spi:tpm_tis_spi warning is the same on the installed linux-aurora tree
out=$(depmod -b "$w/usr" -a "${sv[@]}" -w "$rel" 2>&1 | grep -v 'duplicate module alias\|^spi:tpm_tis_spi')
[ -z "$out" ] && ok "$what: no error, no unresolved symbol" || { no "$what:"; echo "$out" | head; }
strings -a "$m/vmlinuz" | grep -q "Linux version $rel " && ok "vmlinuz banner names $rel" || no "vmlinuz banner"
# The brightness build (version ...r3b.b<N>, docs/r3-display-plan.md D5a) must carry the floor of
# patches/linux/brightness 0006 in appledrm; any other build only reports whether it does.
ver=$(info pkgver); drm=$(find "$m" -name appledrm.ko | head -1)
if [ -n "$drm" ] && strings -a "$drm" | grep -q 'brightness requests below %u nits are raised to %u nits'; then floor=yes; else floor=no; fi
case $ver in
  *.b[0-9]*|*.c[0-9]*|*.r3c*|*.r3d*|*.r3e*|*.r3f*) [ $floor = yes ] && ok "version $ver: appledrm carries the brightness floor (brightness 0006)" || no "version $ver: appledrm lacks the brightness floor (brightness 0006)" ;;
  *) echo "info version $ver: appledrm brightness floor $floor" ;;
esac
# The HDR build (version ...r3b.c<N>, docs/r3-hdr.md) must carry the Display P3 default and the EDR cap at 500 nits;
# r3c (docs/r3c-kernel.md) carries the same series. r3f (docs/r3f-kernel.md) takes upstream's EDR value (#2694) and
# drops the K114s cap: its parameter is still there, with a default of 0 (the panel's own peak).
case $ver in
  *.c[0-9]*|*.r3c*|*.r3d*|*.r3e*|*.r3f*)
    if [ -n "$drm" ] && strings -a "$drm" | grep -q 'EDID primaries default to Display P3'; then ok "version $ver: appledrm carries the Display P3 default (hdr 0001)"
    else no "version $ver: appledrm lacks the Display P3 default (hdr 0001)"; fi ;;
esac
case $ver in
  *.r3f*)
    if [ -n "$drm" ] && modinfo -F parm "$drm" | grep -q '^fw27_panel_edr_max_nits:.*(default: 0)'; then ok "version $ver: appledrm has no EDR cap by default (the parameter's default is 0; upstream's EDR value, #2694)"
    else no "version $ver: appledrm still caps panel EDR by default, or lacks the cap parameter"; fi ;;
  *.c[0-9]*|*.r3c*|*.r3d*|*.r3e*)
    if [ -n "$drm" ] && modinfo -F parm "$drm" | grep -q '^fw27_panel_edr_max_nits:.*(default: 500)'; then ok "version $ver: appledrm caps panel EDR at 500 nits by default (hdr 0002, 0003)"
    else no "version $ver: appledrm lacks the 500-nit EDR cap (hdr 0002, 0003)"; fi ;;
esac
# From r3b.c3 (docs/r3-hdr.md, hdr 0004) appledrm offers no EDR when a cap is set and the SDR maximum is unknown; r3c too.
case $ver in
  *.c[3-9]*|*.r3c*|*.r3d*|*.r3e*|*.r3f*)
    if [ -n "$drm" ] && strings -a "$drm" | grep -q 'panel EDR off: cap %u nits set and the SDR maximum is unknown'; then ok "version $ver: appledrm turns EDR off for a cap with an unknown SDR maximum (hdr 0004)"
    else no "version $ver: appledrm lacks the unknown-SDR EDR guard (hdr 0004)"; fi ;;
esac
# From r3b.c3 (docs/r3-vrr.md) appledrm also has the VRR minimum parameter, at the old 24 Hz by default. r3c drops it
# on purpose (docs/r3c-kernel.md): nothing sets it and panel VRR is blocked, so r3c is not matched here.
case $ver in
  *.c[3-9]*)
    if [ -n "$drm" ] && modinfo -F parm "$drm" | grep -q '^fw27_panel_vrr_min:.*(default: 24)'; then ok "version $ver: appledrm has fw27_panel_vrr_min, default 24 (vrr 0001)"
    else no "version $ver: appledrm lacks fw27_panel_vrr_min with default 24 (vrr 0001)"; fi ;;
esac
# From r3b.c4 (docs/r3-touchid.md) apple-sep's T6050 profile admits the K114s; without it the driver refuses this Mac. r3c too.
case $ver in
  *.c[4-9]*|*.r3c*)
    sep=$(find "$m" -name apple-sep.ko | head -1)
    if [ -n "$sep" ] && strings -a "$sep" | grep -q 'apple,k114s'; then ok "version $ver: apple-sep admits apple,k114s (sep 0001)"
    else no "version $ver: apple-sep does not admit apple,k114s (sep 0001)"; fi ;;
  # r3d carries aurora-silicon/linux #2631: the T6050 profile is chosen by the SoC compatible, so every apple,t6050
  # board (the K114s too) gets it and the module no longer names the K114s
  *.r3d*|*.r3e*|*.r3f*)
    sep=$(find "$m" -name apple-sep.ko | head -1)
    if [ -n "$sep" ] && grep -a -q 'apple,t6050' "$sep"; then ok "version $ver: apple-sep picks the T6050 profile by SoC (#2631)"
    else no "version $ver: apple-sep has no T6050 SoC selection (#2631)"; fi ;;
esac
# r3c (docs/r3c-kernel.md) also admits the K114s NVRAM row in spi-apple-qspi (r3c 0007) and sends the light sensor's
# 193-byte calibration (r3c 0004, aop.ko).
case $ver in
  *.r3c*|*.r3d*)
    q=$(find "$m" -name spi-apple-qspi.ko | head -1)
    if [ -n "$q" ] && strings -a "$q" | grep -q -x 'apple,k114s'; then ok "version $ver: spi-apple-qspi has the K114s NVRAM row (r3c 0007)"
    else no "version $ver: spi-apple-qspi lacks the K114s NVRAM row (r3c 0007)"; fi ;;
esac
# r3e takes the NVRAM write path of aurora-silicon/linux #2817 instead of the per-board rows: writes need a DT nvram
# partition and a known flash part, and every refusal is logged. The K114s has neither, so it stays read-only and the
# module names no K114s row (the PKGBUILD source guard checks the DT and the part table).
case $ver in
  *.r3e*|*.r3f*)
    q=$(find "$m" -name spi-apple-qspi.ko | head -1)
    if [ -n "$q" ] && strings -a "$q" | grep -q 'NVRAM denied: reason=' && ! strings -a "$q" | grep -q -x 'apple,k114s'; then ok "version $ver: spi-apple-qspi has #2817's fail-closed NVRAM policy and no K114s write row"
    else no "version $ver: spi-apple-qspi is not #2817's NVRAM policy without a K114s row"; fi ;;
esac
case $ver in
  *.r3c*|*.r3d*|*.r3e*|*.r3f*)
    a=$(find "$m" -name 'aop.ko' -path '*soc/apple*' | head -1)
    if [ -n "$a" ] && strings -a "$a" | grep -q 'sensor blob'; then ok "version $ver: aop carries the 193-byte calibration message (r3c 0004)"
    else no "version $ver: aop lacks the 193-byte calibration message (r3c 0004)"; fi ;;
esac
if [ $fail != 0 ]; then echo "check-package: FAILED"
elif [ $skipped != 0 ]; then echo "check-package: all run checks passed; $skipped skipped ($other is not installed)"
else echo "check-package: all passed"; fi
exit $fail
