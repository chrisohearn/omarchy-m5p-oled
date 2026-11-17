#!/bin/bash
# Software test for the disabled Touch ID fragment dts/t6050-k114s-touchid.dtsi (issue #49).
# Compile tests only: nothing here is hardware proof and nothing here touches the Mac.
#
#   tests/test-touchid-dtb.sh KTREE
#
# KTREE  a kernel tree with the T6050 K-board files (src/r3b); it is only read. Needs python3,
#        a C preprocessor (CPP, default "clang -E") and dtc (DTC): source ~/k114s-build/env.sh.
# 1. included without K114S_R3_TOUCHID, the tree is byte-identical to the r1 tree
# 2. with it, the tree compiles, in all three pin variants
# 3. the sensor, controller, power, interrupt, SEP and pin values are the ones in the file header
# 4. pin 112 stays reserved in every variant, pin 138 is exposed, no variant exposes more than documented
# 5. a tree with a wrong sensor pin is told apart (the value checks are not vacuous)
# 6. the ADT fact checker itself passes a replica and fails on a wrong ADT or tree pin (test-adt-touchid-facts.py)
# 7. the trial tree t6050-k114s-r3b-touchid.dts differs from the brightness tree it is built on by the fragment alone
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
K=${1:?usage: test-touchid-dtb.sh KTREE}
CPP=${CPP:-clang -E}; DTC=${DTC:-dtc}
A="$K/arch/arm64/boot/dts/apple"
[ -f "$A/t6050-k114-k116.dtsi" ] || { echo "not a kernel tree with the T6050 K-board files: $K"; exit 2; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
dtcw=""
for c in unit_address_vs_reg avoid_unnecessary_addr_size alias_paths graph_child_address simple_bus_reg unique_unit_address interrupt_provider; do
  if echo '/dts-v1/; / { };' | "$DTC" -Wno-$c -O dtb -o /dev/null - 2>/dev/null; then dtcw="$dtcw -Wno-$c"; fi
done
build() { # build NAME 'dts text'
  printf '%s\n' "$2" > "$W/$1.dts"
  $CPP -nostdinc -I "$W" -I "$here/dts" -I "$K/scripts/dtc/include-prefixes" -I "$K/include" -I "$A" \
    -undef -D__DTS__ -x assembler-with-cpp -o "$W/$1.pp" "$W/$1.dts"
  "$DTC" -O dtb -o "$W/$1.dtb" -b 0 -i "$A" $dtcw "$W/$1.pp"
}
dump() { "$DTC" -I dtb -O dts "$W/$1.dtb" 2>/dev/null; }
head='#define K114S_R1_N1
#define K114S_R1_USB
#include "t6050-k114s-common.dtsi"'
inc() { printf '%s\n%s\n#include "t6050-k114s-touchid.dtsi"\n%s\n' "$head" "$1" "${2:-}"; }
fail() { echo "FAIL $*"; exit 1; }

build r1 "$head"
build off "$(inc "")"
cmp -s "$W/r1.dtb" "$W/off.dtb" && echo "ok   without K114S_R3_TOUCHID the tree is byte-identical to r1" || fail "fragment changes the tree while off"
build on "$(inc '#define K114S_R3_TOUCHID')"
# the pin variants sit after the SD fragment whose pins they carry (the later gpio-reserved-ranges wins)
build on-sd "$(printf '%s\n#define K114S_R3_SD\n#include "t6050-k114s-sd.dtsi"\n#define K114S_R3_TOUCHID\n#define K114S_TOUCHID_WITH_SD\n#include "t6050-k114s-touchid.dtsi"\n' "$head")"
build on-sound "$(printf '%s\n#define K114S_SD_WITH_SOUND\n#define K114S_R3_SD\n#include "t6050-k114s-sd.dtsi"\n#define K114S_R3_TOUCHID\n#define K114S_TOUCHID_WITH_SOUND\n#include "t6050-k114s-touchid.dtsi"\n' "$head")"
echo "ok   compiles with K114S_R3_TOUCHID (default, WITH_SD, WITH_SOUND)"

d=$(dump on)
has() { grep -Eq "$1" <<<"$d" || fail "tree lacks: $2"; echo "ok   $2"; }
has 'sep = &?"?/.*sep@502600000|sep = "/soc.*sep@502600000"' "sep alias resolves to sep@502600000"
has 'fingerprint@0 \{' "fingerprint@0 node"
has 'compatible = "apple,mesa-fingerprint"' "compatible apple,mesa-fingerprint"
has 'spi-max-frequency = <0x7a1200>' "8 MHz (0x7a1200)"
has 'interrupts = <0x8a 0x01>' "data ready on pin 138 (0x8a), rising edge"
has 'enable-gpios = <0x[0-9a-f]+ 0x15 0x00>' "power enable on pin 21 (0x15), active high"

# the ordinary nodes the ADT facts need: spi2, nub gpio and the SEP chain are on, sep and sep_dart stay off
python3 -I - "$W/on.dtb" <<'PY'
import struct, sys
b = open(sys.argv[1], "rb").read()
_m, _t, off_s, off_str, _r, _v, _l, _b, size_str, _ss = struct.unpack_from(">10I", b)
strs = b[off_str:off_str + size_str]
pos, path, nodes = off_s, [], {}
while True:
    tok = struct.unpack_from(">I", b, pos)[0]; pos += 4
    if tok == 1:
        e = b.index(b"\0", pos); path.append(b[pos:e].decode()); pos = (e + 4) & ~3
        nodes["/".join(path[1:])] = {}
    elif tok == 3:
        ln, no = struct.unpack_from(">II", b, pos); pos += 8
        nodes["/".join(path[1:])][strs[no:strs.index(b"\0", no)].decode()] = b[pos:pos + ln]; pos = (pos + ln + 3) & ~3
    elif tok == 2: path.pop()
    elif tok == 9: break
def status(suffix):
    hit = [p for p in nodes if p.endswith(suffix)]
    assert len(hit) == 1, (suffix, hit)
    return nodes[hit[0]].get("status", b"okay\0").rstrip(b"\0").decode()
for suffix, want in (("spi@505108000", "okay"), ("pinctrl@2881e4000", "okay"), ("mailbox@502608000", "okay"),
                     ("sep@502600000", "disabled"), ("iommu@500b80000", "disabled")):
    assert status(suffix) == want, (suffix, status(suffix), want)
# reserved pin ranges of the AP bank in every variant are checked by lint-dtb.py (below)
print("ok   spi2, nub-gpio0 and the SEP mailbox on; sep and sep-dart stay off")
PY
python3 -I "$here/tests/lint-dtb.py" "$W/r1.dtb" "$W/on.dtb" "$W/on-sd.dtb" || fail "pin lint"
# the sound variant is built without the sound file (it needs a generated PMP file), so the lint's
# "expected" list does not apply; the exposed pins must be the sound pins plus 138 and the SD reader's 81
out=$(python3 -I "$here/tests/lint-dtb.py" "$W/on-sound.dtb" 2>&1 || true)
grep -q 'exposed \[80, 81, 134, 138, 139\]' <<<"$out" || fail "sound variant pins"
echo "ok   pins exposed: 80+138 | +81 with the SD reader | 80,81,134,138,139 with sound; 112 stays reserved"

# a wrong pin must change the compiled value the checks above read
build neg "$(inc '#define K114S_R3_TOUCHID' '&mesa { enable-gpios = <&nub_gpio0 22 GPIO_ACTIVE_HIGH>; };')"
if "$DTC" -I dtb -O dts "$W/neg.dtb" 2>/dev/null | grep -Eq 'enable-gpios = <0x[0-9a-f]+ 0x15 0x00>'; then fail "wrong pin not detected"; fi
echo "ok   a wrong power pin is detected"
python3 -I "$here/tests/test-adt-touchid-facts.py" || exit 1

# the trial tree (phase 3): the brightness tree plus the fragment, and nothing else. Node and property names only,
# so the check holds on any include tree that has the T6050 K-board nodes.
build bl '#include "t6050-k114s-r3b-brightness.dts"'
build trial '#include "t6050-k114s-r3b-touchid.dts"'
got=$(python3 -I "$here/tests/dtb-node-diff.py" "$W/bl.dtb" "$W/trial.dtb" | sed -E 's/^(ADDED|REMOVED) +([^ ]+).*/\1 \2/; s/^(PROP[+~-]) +([^ ]+) +([^ =:]+).*/\1 \2 \3/' | sed -E 's|power-controller@[0-9a-f]+|power-controller@N|' | sort)
want=$(sort <<'EOF2'
ADDED /soc/spi@505108000/fingerprint@0
PROP+ /aliases sep
PROP+ /soc@200000000/power-management@280600000/power-controller@N apple,firmware-owned
PROP+ /soc@200000000/power-management@280900000/power-controller@N apple,firmware-owned
PROP~ /soc/pinctrl@2881e4000 status
PROP~ /soc/spi@505108000 clocks
PROP~ /soc/spi@505108000 status
PROP~ /soc@200000000/mailbox@502608000 status
PROP~ /soc@200000000/pinctrl@29c000000 gpio-reserved-ranges
PROP~ /soc@200000000/power-management@280600000/power-controller@N status
PROP~ /soc@200000000/power-management@280900000/power-controller@N status
PROP~ /soc@200000000/power-management@280900000/power-controller@N status
PROP~ /soc@200000000/power-management@280900000/power-controller@N status
PROP~ /soc@200000000/power-management@288300000/power-controller@N status
summary: 1 nodes added, 0 removed
EOF2
)
[ "$got" = "$want" ] || { diff <(echo "$want") <(echo "$got"); fail "the trial tree differs from the brightness tree by more than the fragment"; }
python3 -I "$here/tests/lint-dtb.py" "$W/trial.dtb" | grep -q 'exposed \[80, 138\]' || fail "trial tree pins"
echo "ok   the trial tree is the brightness tree plus the fragment (14 node or property changes, pins 80 and 138)"
echo "test-touchid-dtb: all passed"
