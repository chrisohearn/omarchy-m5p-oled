#!/bin/bash
# Software tests for the three disabled draft fragments (video decode, SD reader, AOP sensors).
# Replica and compile tests only: nothing here is hardware proof and nothing here touches the Mac.
#
#   tests/test-parity-dtb.sh KTREE [--real]
#
# KTREE   a kernel tree at the installed base (aurora-silicon/linux a34d26c2 + linux-j714s-27.2.patch);
#         it is only read. KEEP=DIR keeps the compiled trees there. Needs python3, a C preprocessor (CPP, default "clang -E") and dtc (DTC).
# --real  also compare the trees with THIS Mac's ADT (tests/k114s-adt-parity-facts.py). Reading
#         /dev/mtd*ro takes root, so this one read-only step runs under sudo; nothing is written.
#
# 1. each fragment, included without its macro, leaves the r1 tree byte-identical (disabled by default)
# 2. with its macro each compiles; only the nodes the fragment names change (tests/test-adt-parity-facts.py)
# 3. a replica ADT built from the K116s values agrees with the compiled trees, and the checker fails
#    on trees with a wrong pin, interrupt, offset, window or an enabled amplifier
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
K=${1:?usage: test-parity-dtb.sh KTREE [--real]}; real=${2:-}
CPP=${CPP:-clang -E}; DTC=${DTC:-dtc}
A="$K/arch/arm64/boot/dts/apple"
[ -f "$A/t6050-k114-k116.dtsi" ] || { echo "not a kernel tree with the T6050 K-board files: $K"; exit 2; }
if [ -n "${KEEP:-}" ]; then W=$KEEP; mkdir -p "$W"; else W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; fi
dtcw=""
for c in unit_address_vs_reg avoid_unnecessary_addr_size alias_paths graph_child_address simple_bus_reg unique_unit_address interrupt_provider; do
  if echo '/dts-v1/; / { };' | "$DTC" -Wno-$c -O dtb -o /dev/null - 2>/dev/null; then dtcw="$dtcw -Wno-$c"; fi
done
build() { # build NAME 'dts text'  -> $W/NAME.dtb   (kernel-style cpp + dtc; our dts directory first)
  printf '%s\n' "$2" > "$W/$1.dts"
  $CPP -nostdinc -I "$W" -I "$here/dts" -I "$K/scripts/dtc/include-prefixes" -I "$K/include" -I "$A" \
    -undef -D__DTS__ -x assembler-with-cpp -o "$W/$1.pp" "$W/$1.dts"
  "$DTC" -O dtb -o "$W/$1.dtb" -b 0 -i "$A" $dtcw "$W/$1.pp"
}
head='#define K114S_R1_N1
#define K114S_R1_USB
#include "t6050-k114s-common.dtsi"'
frag() { printf '%s\n#include "t6050-k114s-%s.dtsi"\n' "$head" "$1"; }
on()   { printf '%s\n#define %s\n#include "t6050-k114s-%s.dtsi"\n' "$head" "$2" "$1"; }

build r1 "$head"
for f in avd:K114S_R3_AVD sd:K114S_R3_SD aop-sensors:K114S_R3_AOP_SENSORS; do
  n=${f%%:*}; m=${f##*:}
  build "off-$n" "$(frag "$n")"
  if cmp -s "$W/r1.dtb" "$W/off-$n.dtb"; then echo "ok   $n: without $m the tree is byte-identical to r1"
  else echo "FAIL $n: included without $m it changes the tree"; exit 1; fi
  build "$n" "$(on "$n" "$m")"
  echo "ok   $n: compiles with $m"
done
build sd-with-sound "$(printf '%s\n#define K114S_SD_WITH_SOUND\n#define K114S_R3_SD\n#include "t6050-k114s-sd.dtsi"\n' "$head")"
build aop-with-audio "$(printf '%s\n#define K114S_AOP_WITH_AUDIO\n#define K114S_R3_AOP_SENSORS\n#include "t6050-k114s-aop-sensors.dtsi"\n' "$head")"
# an SD tree without the N1 host is refused: the fragment extends it
if build sd-no-n1 '#include "t6050-k114s-common.dtsi"
#define K114S_R3_SD
#include "t6050-k114s-sd.dtsi"' 2>/dev/null; then echo "FAIL sd: accepted without K114S_R1_N1"; exit 1; else echo "ok   sd: refused without K114S_R1_N1"; fi

# trees with one wrong value each: the checker must fail on every one
neg() { # neg GROUP NAME FRAGMENT MACRO 'dts text appended'
  build "neg-$1-$2" "$(printf '%s\n#define %s\n#include "t6050-k114s-%s.dtsi"\n%s\n' "$head" "$4" "$3" "$5")"
}
neg avd irq avd K114S_R3_AVD '&avd { interrupts = <AIC_IRQ 0 2419 IRQ_TYPE_LEVEL_HIGH>, <AIC_IRQ 0 2418 IRQ_TYPE_LEVEL_HIGH>; };'
neg avd dart avd K114S_R3_AVD '&avd_dart { reg = <0x23 0x09040000 0x0 0x20000>; };'
neg avd offset avd K114S_R3_AVD '&ps_avd_sys { reg = <0x1e0 4>; };'
neg avd parent avd K114S_R3_AVD '&ps_avd_sys { /delete-property/ power-domains; };'
neg avd off avd K114S_R3_AVD '&avd { status = "disabled"; };'
neg sd pin sd K114S_R3_SD '&port01 { reset-gpios = <&pinctrl_ap 82 GPIO_ACTIVE_LOW>; };'
neg sd irq sd K114S_R3_SD '&pcie0 { interrupts = <AIC_IRQ 0 1523 IRQ_TYPE_LEVEL_HIGH>, <AIC_IRQ 0 1530 IRQ_TYPE_LEVEL_HIGH>; };'
neg sd power sd K114S_R3_SD '&port01 { pwren-gpios = <&smc_pcio 2 GPIO_ACTIVE_HIGH>; };'
neg sd polarity sd K114S_R3_SD '&sdhci0 { /delete-property/ cd-inverted; };'
neg sd tunable sd K114S_R3_SD '&port01 { apple,pcie-rc-tunables = <0x78 4 0x7000 0x1>; };'
neg sd dartirq sd K114S_R3_SD '&dart_apcie1 { interrupts = <AIC_IRQ 0 1533 IRQ_TYPE_LEVEL_HIGH>; };'
neg sd pin112 sd K114S_R3_SD '&pinctrl_ap { gpio-reserved-ranges = <0 80>, <82 30>, <113 108>; };'
neg aop mbox aop-sensors K114S_R3_AOP_SENSORS '&aop_mbox { interrupts = <AIC_IRQ 0 578 IRQ_TYPE_LEVEL_HIGH>, <AIC_IRQ 0 579 IRQ_TYPE_LEVEL_HIGH>, <AIC_IRQ 0 580 IRQ_TYPE_LEVEL_HIGH>, <AIC_IRQ 0 582 IRQ_TYPE_LEVEL_HIGH>; };'
neg aop audio aop-sensors K114S_R3_AOP_SENSORS '&aop_audio { status = "okay"; };'
neg aop amp aop-sensors K114S_R3_AOP_SENSORS '&i2c1 { amp: codec@38 { compatible = "ti,sn012776", "ti,tas2764"; reg = <0x38>; }; };'
neg aop dart aop-sensors K114S_R3_AOP_SENSORS '&aop_dart { reg = <0x2 0x90f80000 0x0 0xc000>; };'

python3 -I "$here/tests/lint-dtb.py" "$W/r1.dtb" "$W/avd.dtb" "$W/sd.dtb" "$W/aop-sensors.dtb" || exit 1   # pin ranges fit; SD adds pin 81 only
python3 -I "$here/tests/test-adt-parity-facts.py" "$W" || exit 1

if [ "$real" = --real ]; then
  echo "-- this Mac's ADT (root)"
  sudo python3 -I "$here/tests/k114s-adt-parity-facts.py" avd="$W/avd.dtb" sd="$W/sd.dtb" aop="$W/aop-sensors.dtb"
fi
echo "test-parity-dtb: all passed"
