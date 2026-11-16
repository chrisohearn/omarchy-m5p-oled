#!/bin/bash
# Build the K114s USB-C trees and lint them. Software test only: nothing here runs on the Mac's ports.
#
#   tests/test-usb-dtb.sh KTREE [K116S_KTREE [J716C_KTREE]]
#
# KTREE        kernel source the K114s tree is built against (aurora-silicon/linux a34d26c255c2
#              or the installed kernel's source)
# K116S_KTREE  optional: aurora-silicon/linux at or after 377b2a2decf1 (it has t6050-k116s.dts).
#              With it every USB-C node of the K114s trees is compared with the K116s tree.
# J716C_KTREE  optional: aurora-silicon/linux at integration/aurora (it has t6050-j716c.dts). With it
#              the draft left-back (ATC0) tree is also compared with the J716c's ATC0 nodes.
# Needs clang (or CPP="gcc -E") and dtc on PATH.
set -euo pipefail
K=${1:?usage: test-usb-dtb.sh KTREE [K116S_KTREE]}; R=${2:-}; J=${3:-}
here=$(cd "$(dirname "$0")" && pwd); dts=$here/../dts
CPP=${CPP:-clang -E}; DTC=${DTC:-dtc}
out=$(mktemp -d); trap 'rm -rf "$out"' EXIT
fail=0
build() { # KTREE DTSDIR NAME [extra dts text]
  local k=$1 d=$2 n=$3 src=$2/$3.dts
  if [ -n "${4:-}" ]; then src=$out/$n.dts; { cat "$d/${n%%+*}.dts"; printf '%s\n' "$4"; } > "$src"; fi
  $CPP -nostdinc -I "$k/scripts/dtc/include-prefixes" -I "$k/include" -I "$d" -I "$k/arch/arm64/boot/dts/apple" \
    -undef -D__DTS__ -x assembler-with-cpp -o "$out/$n.pp" "$src"
  $DTC -q -O dtb -o "$out/$n.dtb" -b 0 -i "$d" -i "$k/arch/arm64/boot/dts/apple" "$out/$n.pp"
}
for n in t6050-k114s-r1 t6050-k114s-r3-usb t6050-k114s-r3-usb-faults t6050-k114s-r3-usb-atc0; do build "$K" "$dts" $n; done

if cmp -s "$out/t6050-k114s-r1.dtb" "$out/t6050-k114s-r3-usb.dtb"; then echo "ok   r3-usb is byte-identical to r1"
else echo "FAIL r3-usb differs from r1"; fail=1; fi

python3 -I "$here/lint-usb-dtb.py" "$out"/t6050-k114s-r1.dtb "$out"/t6050-k114s-r3-usb.dtb \
  "$out"/t6050-k114s-r3-usb-faults.dtb || fail=1

# the draft left-back tree (issue #72): three ports complete with --atc0, and rejected without it
# because the default lint keeps the left-back port undescribed
python3 -I "$here/lint-usb-dtb.py" --atc0 "$out"/t6050-k114s-r3-usb-atc0.dtb || fail=1
got=$(python3 -I "$here/lint-usb-dtb.py" "$out"/t6050-k114s-r3-usb-atc0.dtb || true)
if grep -q 'left-back port is described' <<< "$got"; then
  echo "ok   the default lint rejects the ATC0 tree (left-back is the debug port there)"
else echo "FAIL the default lint accepts the ATC0 tree"; fail=1; fi
got=$(python3 -I "$here/lint-usb-dtb.py" --atc0 "$out"/t6050-k114s-r1.dtb || true)
if grep -q 'left-back: .* is missing or disabled' <<< "$got"; then
  echo "ok   --atc0 rejects the r1 tree"
else echo "FAIL --atc0 accepts the r1 tree"; fail=1; fi
if [ -n "$J" ]; then
  build "$J" "$J/arch/arm64/boot/dts/apple" t6050-j716c
  python3 -I "$here/lint-usb-dtb.py" --atc0 --atc0-reference "$out/t6050-j716c.dtb" \
    "$out"/t6050-k114s-r3-usb-atc0.dtb || fail=1
fi
[ ! -f "$here/lint-dtb.py" ] || python3 -I "$here/lint-dtb.py" "$out"/t6050-k114s-r3-usb.dtb "$out"/t6050-k114s-r3-usb-faults.dtb || fail=1

if [ -n "$R" ]; then
  build "$R" "$R/arch/arm64/boot/dts/apple" t6050-k116s
  python3 -I "$here/lint-usb-dtb.py" "$out"/t6050-k114s-r1.dtb "$out"/t6050-k114s-r3-usb.dtb \
    --reference "$out/t6050-k116s.dtb" || fail=1
  # the diagnostic tree differs from the K116s in the two bus reg properties, and only there
  d=$(python3 -I "$here/lint-usb-dtb.py" "$out"/t6050-k114s-r3-usb-faults.dtb --reference "$out/t6050-k116s.dtb" |
      grep -c -E '^FAIL .*spmi@28a1[8a]8000 reg differs' || true)
  if [ "$d" = 2 ]; then echo "ok   faults tree differs from the K116s in the two bus reg properties only"
  else echo "FAIL faults tree: $d differences from the K116s, expected 2"; fail=1; fi
fi

# the lint must notice a broken description
neg() { # NAME DTS-TEXT PATTERN
  build "$K" "$dts" "t6050-k114s-r3-usb+$1" "$2"
  local got; got=$(python3 -I "$here/lint-usb-dtb.py" "$out/t6050-k114s-r3-usb+$1.dtb" || true)
  if grep -q -E "$3" <<< "$got"; then echo "ok   lint catches: $1"
  else echo "FAIL lint misses: $1"; echo "$got"; fail=1; fi
}
neg dart-off '&usb_drd1_dart_0 { status = "disabled"; };' 'left-front: .*iommu@2aaf00000 is missing or disabled'
neg domain-off '&ps_atc2_usb { status = "disabled"; };' 'right: supplier .* is disabled'
neg bus-irq '&nub_spmi_a1 { interrupts = <AIC_IRQ 0 763 IRQ_TYPE_LEVEL_HIGH>; };' 'right: the bus has an interrupt'
neg no-role-switch '&usb_drd2 { /delete-property/ usb-role-switch; };' 'right: dwc3 has no usb-role-switch'
neg graph-open '&typec1_ss { remote-endpoint = <&atc2_phy_typec>; };' 'left-front: SuperSpeed/mux graph is not closed'
neg debug-port '&nub_spmi_a0 { usb-pd@c { compatible = "apple,sn201202x"; reg = <0xc SPMI_USID>; }; };' 'left-back port is described'

[ $fail = 0 ] && echo "test-usb-dtb: all passed"
exit $fail
