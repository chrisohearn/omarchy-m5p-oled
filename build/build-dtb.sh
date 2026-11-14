#!/bin/bash
# usage: [DTC=/path/to/dtc] build-dtb.sh KTREE NAME OUTDIR  -> OUTDIR/NAME.dtb (kernel-style cpp + dtc)
set -euo pipefail
K=$1; N=$2; O=$3; DTC=${DTC:-dtc}
mkdir -p "$O"
clang -E -Wp,-MMD,"$O/$N.d" -nostdinc -I "$K/scripts/dtc/include-prefixes" -I "$K/include" -I "$K/arch/arm64/boot/dts/apple" -undef -D__DTS__ -x assembler-with-cpp -o "$O/$N.dts.tmp" "$K/arch/arm64/boot/dts/apple/$N.dts"
"$DTC" -O dtb -o "$O/$N.dtb" -b 0 -i "$K/arch/arm64/boot/dts/apple" -Wno-unit_address_vs_reg -Wno-avoid_unnecessary_addr_size -Wno-alias_paths -Wno-graph_child_address -Wno-simple_bus_reg -Wno-unique_unit_address -Wno-interrupt_provider "$O/$N.dts.tmp"
