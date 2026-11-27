#!/bin/sh
# Assemble a K114s Stage 2 file the way update-m1n1 and linux/update-boot-ctxr-k114s do:
#   <Aura Stage 2 = /usr/lib/asahi-boot/m1n1.bin> <ONE K114s device tree> <gzip of u-boot-nodtb.bin>
# No root needed (the inputs are world-readable). Writes the file and prints its sha256, the prefix
# and trailer hashes and the device tree's. Never writes to the ESP.
#   build/make-stage2.sh TREE.dtb OUT.bin [ASAHI_BOOT_DIR]
# The gzip header carries the name and mtime of u-boot-nodtb.bin, exactly as update-m1n1's own
# `gzip -c "$U_BOOT"` does, so the trailer equals the one in the live boot.bin when the package
# is the same (the Stage 2 file of the proven r1 tree is reproduced byte for byte this way).
set -eu
dtb=${1:?usage: make-stage2.sh TREE.dtb OUT.bin [DIR]}; out=${2:?OUT.bin}; dir=${3:-/usr/lib/asahi-boot}
m1n1=$dir/m1n1.bin; uboot=$dir/u-boot-nodtb.bin
[ -s "$m1n1" ] && [ -s "$uboot" ] || { echo "make-stage2: $m1n1 or $uboot missing" >&2; exit 1; }
magic=$(od -An -tx1 -N4 "$dtb" | tr -d ' \n')
[ "$magic" = d00dfeed ] || { echo "make-stage2: $dtb is not a device tree blob" >&2; exit 1; }
size=$(od -An -tu1 -j4 -N4 "$dtb" | awk '{print (($1*256+$2)*256+$3)*256+$4}')
[ "$size" -eq "$(stat -c %s "$dtb")" ] || { echo "make-stage2: $dtb is not exactly one device tree" >&2; exit 1; }
grep -aq 'apple,k114s' "$dtb" || { echo "make-stage2: $dtb is not an apple,k114s tree" >&2; exit 1; }
tmp=$(mktemp "$out.XXXXXX"); trap 'rm -f "$tmp"' EXIT
{ cat "$m1n1"; cat "$dtb"; gzip -c "$uboot"; } > "$tmp"
total=$(stat -c %s "$tmp")
[ "$total" -le 16777216 ] || { echo "make-stage2: $total bytes exceed Aura's 16 MiB slot" >&2; exit 1; }
mv -f "$tmp" "$out"; trap - EXIT
p=$(stat -Lc %s "$m1n1")
echo "stage2   $(sha256sum "$out" | cut -c1-64)  $total bytes  $out"
echo "prefix   $(head -c "$p" "$out" | sha256sum | cut -c1-64)  ($p bytes, Aura)"
echo "tree     $(sha256sum "$dtb" | cut -c1-64)  ($size bytes)"
echo "trailer  $(tail -c +$((p + size + 1)) "$out" | sha256sum | cut -c1-64)  (gzip U-Boot)"
