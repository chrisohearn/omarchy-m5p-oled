#!/bin/bash
# Static guards for the s2idle work (issue 50): the pieces that must stay true until the first suspend is proven.
#   - the K114s is admitted by patch 0003 (and only the K114c, J716c and the K116s besides)
#   - the sleep series is in the documented order
#   - the r3a tree includes the sleep fragment
#   - the boot-once tool still refuses a trial unless hibernate, hybrid-sleep and suspend-then-hibernate are masked and
#     suspend.target is masked in /etc or held by the k114s-lid-sleep gate, never by a runtime mask alone (the lid drop-ins are what the owner decided 2026-11-17)
#   usage: test-sleep-gates.sh
set -u
H=$(cd "$(dirname "$0")" && pwd); R=$H/../..
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: got [$2] want [$3]"; fi; }
S=$R/patches/linux/sleep-lid
p3=$(ls "$S"/0003-*.patch)
ok "0003 adds exactly one machine: apple,k114s" "$(grep -E '^\+.*of_machine_is_compatible' "$p3" | grep -o 'apple,[a-z0-9]*' | tr '\n' ' ')" "apple,k114s "
ok "0003 keeps the K114c line" "$(grep -c 'apple,k114c' "$p3")" 1
ok "0003 admits exactly j716c, k114c, k114s, k116s" "$(grep -E '^[ +].*of_machine_is_compatible' "$p3" | grep -o 'apple,[a-z0-9]*' | sort | tr '\n' ' ')" "apple,j716c apple,k114c apple,k114s apple,k116s "
order=$(grep -E '^[0-9]{4}-' "$S/series" | cut -c1-4 | tr '\n' ' ')
ok "series order 0001..0010" "$order" "0001 0002 0003 0004 0005 0006 0007 0008 0009 0010 "
ok "every series file exists" "$(grep -E '^[0-9]{4}-' "$S/series" | awk '{print $1}' | while read -r f; do [ -f "$S/$f" ] || echo "$f"; done | wc -l)" 0
ok "r3a tree includes the sleep fragment" "$(grep -c '#include "t6050-k114s-sleep.dtsi"' "$R/dts/t6050-k114s-r3a.dts")" 1
ok "sleep fragment sets apple,internal-panel" "$(grep -c 'apple,internal-panel' "$R/dts/t6050-k114s-sleep.dtsi")" 1
ok "sleep fragment keeps the three PMP domains always on" "$(grep -c 'apple,always-on' "$R/dts/t6050-k114s-sleep.dtsi")" 3
bo=$R/linux/r3a-trial/k114s-boot-once
ok "boot-once checks the three targets that stay masked" "$(grep -c 'for t in hibernate.target hybrid-sleep.target suspend-then-hibernate.target; do' "$bo")" 1
ok "boot-once refuses a non-masked target" "$(grep -c "bad \"\$t is '\$s', not masked\"" "$bo")" 1
ok "boot-once leaves suspend.target open only through k114s-lid-sleep check" "$(grep -c '"\$LIDSLEEP" check' "$bo")" 1
lg=$R/linux/r3a-trial/k114s-lid-sleep
ok "lid-sleep check also covers exactly the three that stay masked" "$(grep -c 'for t in hibernate.target hybrid-sleep.target suspend-then-hibernate.target; do' "$lg")" 1
ok "boot-once accepts only an /etc mask for the three targets (never masked-runtime)" "$(grep -c "\[ \"\$s\" = masked \] || bad \"\$t is" "$bo")" 1
ok "boot-once never lists masked-runtime as enough" "$(grep -c 'masked | masked-runtime' "$bo")" 0
ok "lid-sleep check accepts only an /etc mask for the three targets" "$(grep -c "\[ \"\$s\" = masked \] || bad \"\$t is" "$lg")" 1
ok "lid-sleep check never lists masked-runtime as a mask" "$(grep -c 'masked | masked-runtime' "$lg")" 1   # the one left is the trial-boot clause: a trial must be masked or masked-runtime
ok "lid-sleep check wants the gate, the tool, both 40 files and both 30 locks when suspend is not masked in /etc" "$(grep -c -E 'GATE is|the tool is not in|lid-sleep/\$f is missing|AllowSuspend=no\) is missing|HandleLidSwitch=lock\) is missing' "$lg")" 5
ok "lid-sleep open refuses on a trial boot unless --force" "$(grep -c 'not opening it (open --force overrides)' "$lg")" 1
ok "r3a-check does not accept masked-runtime and runs the lid-sleep check by its full path with sudo -n" "$(grep -c 'masked-runtime' "$R/tests/hardware/k114s-r3a-check.sh") $(grep -c 'sudo -n "\$LS" check' "$R/tests/hardware/k114s-r3a-check.sh") $(grep -c '^LS=/usr/local/lib/omarchy-k114s/k114s-lid-sleep$' "$R/tests/hardware/k114s-r3a-check.sh")" "0 1 1"
ok "no doc or script runs a bare 'sudo k114s-lid-sleep'" "$(grep -rn 'sudo k114s-lid-sleep' "$R/docs" "$R/linux" "$R/tests" "$R/README.md" | grep -v 'test-sleep-gates.sh' | wc -l | tr -d ' ')" 0
ok "no runbook accepts masked-runtime for suspend.target" "$(grep -rn 'masked | masked-runtime' "$R/docs" | wc -l | tr -d ' ')" 0
ok "the 40 sleep drop-in never allows hibernate or hybrid sleep" "$(grep -c -E '^Allow(Hibernation|HybridSleep|SuspendThenHibernate)=yes' "$R"/linux/r3a-trial/sleep-40-k114s-lid-sleep.conf)" 0
ok "the 30 sleep drop-in (the fail-closed lock) still refuses suspend" "$(grep -c '^AllowSuspend=no' "$R/linux/r3a-trial/sleep-30-k114s-r3a-trial.conf")" 1
ok "the lid action: suspend on battery, lock on external power, ignore docked" "$(grep -E '^HandleLidSwitch' "$R/linux/r3a-trial/logind-40-k114s-lid-sleep.conf" | tr '\n' ' ')" "HandleLidSwitch=suspend HandleLidSwitchExternalPower=lock HandleLidSwitchDocked=ignore "
echo "test-sleep-gates: $pass passed, $fail failed"; [ "$fail" = 0 ]
