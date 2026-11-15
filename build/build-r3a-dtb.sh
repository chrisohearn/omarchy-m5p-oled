#!/bin/bash
# usage: build-r3a-dtb.sh KTREE NAME OUTDIR
# Builds dts/NAME.dts of this repository against the device tree includes of the kernel source tree
# KTREE (the r3a tree), without writing into KTREE: a scratch tree of links and copies is made under
# OUTDIR, then build/build-dtb.sh runs on it. Prints the sha256 of OUTDIR/NAME.dtb.
set -euo pipefail
K=$(readlink -f "$1"); N=$2; O=$3; here=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$O"; S=$(mktemp -d "$O/stage.XXXXXX"); trap 'rm -rf "$S"' EXIT
mkdir -p "$S/scripts/dtc" "$S/arch/arm64/boot/dts"
ln -s "$K/scripts/dtc/include-prefixes" "$S/scripts/dtc/include-prefixes"
ln -s "$K/include" "$S/include"
cp -r "$K/arch/arm64/boot/dts/apple" "$S/arch/arm64/boot/dts/apple"
for f in "$here"/dts/t6050-k114s-*; do cp -f "$f" "$S/arch/arm64/boot/dts/apple/"; done
[[ ! -e ${K114S_PMP_TUNABLES:-/nonexistent} ]] || cp -f "$K114S_PMP_TUNABLES" "$S/arch/arm64/boot/dts/apple/t6050-k114s-pmp-tunables.dtsi"
"$here/build/build-dtb.sh" "$S" "$N" "$O"
sha256sum "$O/$N.dtb"
