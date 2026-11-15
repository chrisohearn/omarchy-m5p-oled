#!/bin/bash
# SPDX-License-Identifier: MIT
# omarchy-m5p-oled: install the M5 title-bar plugin package together with the guards that keep the
# channel's build from coming back. One root session, in this order:
#
#   sudo install.sh 'PATH/omarchy-hyprland-titlebars-1:0.4.0+m5-1-aarch64.pkg.tar.xz'
#
#   1. the guard script and both pacman hooks (00 stops a transaction that would change the plugin
#      or hyprland-m5 without the owner's marker; 02 moves a mismatched plugin aside afterwards);
#   2. a permit /run/omarchy-k114s/permit ("install omarchy-hyprland-titlebars", the narrow permit
#      titlebars-abi-check --pre and k114s-guard honor; it does not unlock the boot-chain packages)
#      and allow-low-esp (main's space guard, Target=*, stops on the nearly full EFI partition
#      although this package writes nothing there) for this one transaction, removed again on exit
#      even when pacman fails; refuses to start while pacman's database lock exists;
#   3. pacman -U (it refuses anything that is not the +m5 build), then it requires that
#      titlebars.so was extracted and titlebars-abi-check says "ok:"; otherwise it fails.
# Installing arms the plugin: Omarchy loads it the next time a workspace floats.
set -euo pipefail
root=${K114S_ROOT:-}
pacman=${PACMAN:-pacman}
here=$(cd "$(dirname "$0")" && pwd)
die() { echo "install.sh: $*" >&2; exit 1; }
[[ -n $root || $EUID == 0 ]] || die "run as root: sudo $0 PACKAGE"
[[ $# == 1 && -f $1 ]] || die "usage: install.sh PACKAGE-FILE"
pkg=$1
info=$("$pacman" -Qp "$pkg") || die "pacman cannot read $pkg"
[[ $info == "omarchy-hyprland-titlebars "*+m5-* ]] || die "$pkg is '$info', not the M5 rebuild (omarchy-hyprland-titlebars <epoch>:<ver>+m5-<rel>)"

lib=$root/usr/local/lib/omarchy-k114s etc=$root/etc/omarchy-k114s hooks=$root/etc/pacman.d/hooks
install -d "$lib" "$etc" "$hooks"
install -m755 "$here/titlebars-abi-check" "$lib/titlebars-abi-check"
install -m644 "$here/00-k114s-titlebars-guard.hook" "$hooks/00-k114s-titlebars-guard.hook"
install -m644 "$here/02-k114s-titlebars-abi.hook" "$hooks/02-k114s-titlebars-abi.hook"

[[ ! -e $root/var/lib/pacman/db.lck ]] || die "pacman's database is locked (another transaction runs); try again when it is done"
sha256sum "$pkg"
permit=$root/run/omarchy-k114s/permit
[[ ! -e $permit ]] || die "$permit exists (a release is in progress); not touching it"
made=()
[[ -e $etc/allow-low-esp ]] || { : > "$etc/allow-low-esp"; made+=("$etc/allow-low-esp"); }
install -d "$(dirname "$permit")"
echo 'install omarchy-hyprland-titlebars' > "$permit"
trap 'rm -f "$permit" "${made[@]}"' EXIT

"$pacman" -U --noconfirm "$pkg"
[[ -f $root/usr/lib/omarchy-hyprland-titlebars/titlebars.so ]] || die "titlebars.so was not installed (a noextract list kept it out? lift it for this file: k114s-holds lift-noextract usr/lib/omarchy-hyprland-titlebars/titlebars.so, or install through k114s-release)"
out=$("$lib/titlebars-abi-check") || die "titlebars-abi-check failed: $out"
echo "$out"
[[ $out == *"ok:"* ]] || die "titlebars-abi-check did not say ok:"
