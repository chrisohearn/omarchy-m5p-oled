#!/bin/bash
# Software test of k114s-click-strength.sh against a fake module directory (no root, no hardware).
set -u
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d) || exit 2
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
S="$here/k114s-click-strength.sh"
mkdir -p "$t/mod/parameters" "$t/dt/a"; echo "0,0" >"$t/mod/parameters/click_strength"
export K114S_HAPTIC_MODULE=$t/mod K114S_HAPTIC_PARAM=$t/mod/parameters/click_strength K114S_DT=$t/dt

out=$("$S" status); [[ $out == *"driver: hid_apple_mtp_haptic loaded"* && $out == *"parameter: 0,0"* && $out == *"properties in the device tree: 0"* ]] && ok "status reads the fake driver" || bad "status: $out"
"$S" set 192 110 >/dev/null; [[ $(<"$K114S_HAPTIC_PARAM") == 192,110 ]] && ok "set writes press,release" || bad "set"
"$S" clear >/dev/null; [[ $(<"$K114S_HAPTIC_PARAM") == 0,0 ]] && ok "clear writes 0,0" || bad "clear"
"$S" set 010 5 >/dev/null; [[ $(<"$K114S_HAPTIC_PARAM") == 10,5 ]] && ok "leading zero is decimal" || bad "leading zero"
"$S" set 08 5 >/dev/null 2>&1; [[ $(<"$K114S_HAPTIC_PARAM") == 8,5 ]] && ok "08 is decimal 8" || bad "08"
"$S" set 0 5 >/dev/null 2>&1; [[ $? -eq 2 ]] && ok "zero refused" || bad "zero accepted"
"$S" set 256 5 >/dev/null 2>&1; [[ $? -eq 2 ]] && ok "256 refused" || bad "256 accepted"
"$S" set x 5 >/dev/null 2>&1; [[ $? -eq 2 ]] && ok "non-number refused" || bad "non-number accepted"
touch "$t/dt/a/apple,click-strength"; [[ $("$S" status) == *"device tree: 1"* ]] && ok "property counted" || bad "property count"
rm "$K114S_HAPTIC_PARAM"; "$S" set 1 1 >/dev/null 2>&1; [[ $? -eq 2 ]] && ok "no parameter: refused, nothing written" || bad "wrote without parameter"
[[ $("$S" status) == *"absent"* ]] && ok "status says #1959 absent" || bad "absent status"
[[ $(K114S_HAPTIC_MODULE=$t/none "$S" status) == *"driver: hid_apple_mtp_haptic NOT loaded"* ]] && ok "missing driver: NOT loaded" || bad "missing driver"
exit $fail
