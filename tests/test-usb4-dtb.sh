#!/bin/bash
# Build the K114s USB4 tree and check it against this Mac's ADT. Software test only.
#
#   tests/test-usb4-dtb.sh KTREE      KTREE: aurora-silicon/linux with #1791 and #1841 (it is copied; not written to)
#
# Needs clang and dtc on PATH. The ADT check needs root (the "adt" MTD partition) and is skipped without it.
set -euo pipefail
K=$(readlink -f "${1:?usage: test-usb4-dtb.sh KTREE}"); here=$(cd "$(dirname "$0")/.." && pwd)
out=$(mktemp -d); trap 'rm -rf "$out"' EXIT
mkdir -p "$out/k"; cp -r "$K/arch" "$K/include" "$K/scripts" "$out/k/" 2>/dev/null || cp -r "$K/arch" "$K/include" "$K/scripts" "$out/k/"
chmod -R u+w "$out/k"
for f in t6050-j714s-left-usb4.dtsi t6050-max-atc2-router.dtsi; do
  [ -f "$out/k/arch/arm64/boot/dts/apple/$f" ] || { echo "FAIL KTREE lacks $f (needs #1791 and #1841)"; exit 1; }
done
(cd "$out/k" && patch -p1 -s < "$here/patches/linux/usb4/0001-t6050-k114s-router-guards.patch" 2>/dev/null || patch -p1 -s < <(sed '1,/^---$/d' "$here/patches/linux/usb4/0001-t6050-k114s-router-guards.patch"))
"$here/build/build-r3a-dtb.sh" "$out/k" t6050-k114s-r3-usb4 "$out/o" | sed 's/^/built /'
python3 -I "$here/tests/lint-dtb.py" "$out/o/t6050-k114s-r3-usb4.dtb" || { echo "FAIL lint"; exit 1; }
# The patch must not break K114s trees that lack the router files: the r3a tree and upstream's own.
"$here/build/build-r3a-dtb.sh" "$out/k" t6050-k114s-r3a "$out/o" | sed 's/^/built /'
"$here/build/build-dtb.sh" "$out/k" t6050-k114s "$out/o" && echo "built upstream t6050-k114s (patched tree)"
if [ "$(id -u)" = 0 ] || sudo -n true 2>/dev/null; then
  sudo python3 -I "$here/tests/k114s-adt-usb4-facts.py" "$out/o/t6050-k114s-r3-usb4.dtb"
  echo "ok   usb4 tree builds, lints and matches the ADT; r3a and upstream k114s still build"
else echo "ok   usb4 tree builds and lints; r3a and upstream k114s still build (ADT facts SKIPPED: needs root)"; fi
