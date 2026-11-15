#!/bin/bash
# usage: [DTC=/path/to/dtc] [K114S_DTS_DEFINES="MACRO ..."] build-dtb.sh KTREE NAME OUTDIR  -> OUTDIR/NAME.dtb
# (kernel-style cpp + dtc). K114S_DTS_DEFINES names macros to define for cpp (-DMACRO each); unset, the
# command is the kernel's and the blob is unchanged.
# The -Wno-* check names are the kernel's (scripts/Makefile.dtbs over the years). A dtc that no longer
# has a check aborts on its name ("Unrecognized check name": graph_child_address is gone from dtc 1.8
# and from the dtc inside the 7.3 tree), so only the names this dtc knows are passed. They silence
# warnings and do not change the blob.
set -euo pipefail
K=$1; N=$2; O=$3; DTC=${DTC:-dtc}
mkdir -p "$O"
flags=()
for w in unit_address_vs_reg avoid_unnecessary_addr_size alias_paths graph_child_address simple_bus_reg unique_unit_address interrupt_provider; do
  if echo '/dts-v1/; / { };' | "$DTC" -Wno-"$w" -O dtb -o /dev/null - 2>/dev/null; then flags+=(-Wno-"$w"); fi
done
defines=()
for d in ${K114S_DTS_DEFINES:-}; do
  [[ $d =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "build-dtb: bad macro name '$d'" >&2; exit 1; }
  defines+=(-D"$d")
done
clang -E -Wp,-MMD,"$O/$N.d" -nostdinc -I "$K/scripts/dtc/include-prefixes" -I "$K/include" -I "$K/arch/arm64/boot/dts/apple" -undef -D__DTS__ "${defines[@]}" -x assembler-with-cpp -o "$O/$N.dts.tmp" "$K/arch/arm64/boot/dts/apple/$N.dts"
"$DTC" -O dtb -o "$O/$N.dtb" -b 0 -i "$K/arch/arm64/boot/dts/apple" "${flags[@]}" "$O/$N.dts.tmp"
