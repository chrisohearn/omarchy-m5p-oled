#!/bin/bash
# Static guards for the s2idle work (issue 50): the pieces that must stay true until the first suspend is proven.
#   - the K114s is admitted by patch 0003 (and only the K114c, J716c and the K116s besides)
#   - the sleep series is in the documented order
#   - the r3a tree includes the sleep fragment
#   - the boot-once tool still refuses a trial unless the four sleep targets are masked
#   usage: test-sleep-gates.sh
set -u
H=$(cd "$(dirname "$0")" && pwd); R=$H/../..
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: got [$2] want [$3]"; fi; }
S=$R/patches/linux/sleep-lid
p3=$(ls "$S"/0003-*.patch)
ok "0003 adds exactly one machine: apple,k114s" "$(grep -E '^\+.*of_machine_is_compatible' "$p3" | grep -o 'apple,[a-z0-9]*' | tr '\n' ' ')" "apple,k114s "
ok "0003 keeps the K114c line" "$(grep -c 'apple,k114c' "$p3")" 1
order=$(grep -E '^[0-9]{4}-' "$S/series" | cut -c1-4 | tr '\n' ' ')
ok "series order 0001..0010" "$order" "0001 0002 0003 0004 0005 0006 0007 0008 0009 0010 "
ok "every series file exists" "$(grep -E '^[0-9]{4}-' "$S/series" | awk '{print $1}' | while read -r f; do [ -f "$S/$f" ] || echo "$f"; done | wc -l)" 0
ok "r3a tree includes the sleep fragment" "$(grep -c '#include "t6050-k114s-sleep.dtsi"' "$R/dts/t6050-k114s-r3a.dts")" 1
ok "sleep fragment sets apple,internal-panel" "$(grep -c 'apple,internal-panel' "$R/dts/t6050-k114s-sleep.dtsi")" 1
ok "sleep fragment keeps the three PMP domains always on" "$(grep -c 'apple,always-on' "$R/dts/t6050-k114s-sleep.dtsi")" 3
bo=$R/linux/r3a-trial/k114s-boot-once
ok "boot-once refuses a non-masked target" "$(grep -c 'not masked' "$bo")" 1
echo "test-sleep-gates: $pass passed, $fail failed"; [ "$fail" = 0 ]
