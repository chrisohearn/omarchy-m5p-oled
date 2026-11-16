#!/bin/bash
# Software test of k114s-gpu-qualify.sh against a fake sysfs and /proc (no root, no GPU).
set -u
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d) || exit 2
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
echo "boot ok" >"$t/klog"; export K114S_KLOG=$t/klog
mkdir -p "$t/sys/class/drm/card1/device/power" "$t/sys/class/hwmon/hwmon0" "$t/proc"
d=$t/sys/class/drm/card1/device
printf 'utilisation_status valid\nutil_device_percent 7\nutil_renderer_percent 5\npstate unsupported\npower_mw unsupported\nbusy_ns 1000000\n' >"$d/agx_stats"
echo unsupported >"$d/power/runtime_status"; echo 2 >"$d/idle_off_delay_ms"
echo macsmc_hwmon >"$t/sys/class/hwmon/hwmon0/name"; echo 61000 >"$t/sys/class/hwmon/hwmon0/temp1_input"; echo 2200 >"$t/sys/class/hwmon/hwmon0/fan1_input"
echo " 67: 100 200 AIC2 1 Level 2302600000.mailbox-recv" >"$t/proc/interrupts"
( for k in 1 2 3; do sleep 0.3; echo " 67: $((k*500)) 200 AIC2 1 Level 2302600000.mailbox-recv" >"$t/proc/interrupts"; done ) &
out=$(K114S_SYSFS=$t/sys K114S_PROC=$t/proc "$here/k114s-gpu-qualify.sh" 0.4 2 2>&1); rc=$?
[[ $rc -eq 0 && $out == *"RESULT: PASS"* ]] && ok "moving interrupt, readable stats: PASS" || { bad "pass case rc=$rc"; echo "$out"; }
[[ $out == *"unsupported GPU telemetry: pstate power_mw"* ]] && ok "unsupported telemetry listed, not failed" || bad "unsupported list"
wait
out=$(K114S_SYSFS=$t/sys K114S_PROC=$t/proc "$here/k114s-gpu-qualify.sh" 0.1 2 2>&1); rc=$?
[[ $rc -eq 1 && $out == *"RESULT: FAIL"* ]] && ok "frozen interrupt: FAIL" || bad "frozen case rc=$rc"
out=$(K114S_SYSFS=$t/none K114S_PROC=$t/proc "$here/k114s-gpu-qualify.sh" 0.1 1 2>&1); rc=$?
[[ $rc -eq 2 ]] && ok "no agx_stats: exit 2" || bad "missing stats rc=$rc"
( sleep 0.3; echo "aurora: GPU fault" >>"$t/klog" ) &
( for k in 4 5 6; do sleep 0.2; echo " 67: $((k*500)) 200 AIC2 1 Level 2302600000.mailbox-recv" >"$t/proc/interrupts"; done ) &
out=$(K114S_SYSFS=$t/sys K114S_PROC=$t/proc "$here/k114s-gpu-qualify.sh" 0.4 2 2>&1); rc=$?
wait
[[ $rc -eq 1 && $out == *"RESULT: FAIL (fault lines 1"* ]] && ok "fault line between samples: FAIL" || { bad "fault case rc=$rc"; echo "$out"; }
echo "x" >"$t/klog"; mkdir -p "$t/sys/class/drm/card2/device"; mv "$d" "$t/sys/class/drm/card2/"; rmdir "$t/sys/class/drm/card1"
echo " 67: 1 200 AIC2 1 Level 2302600000.mailbox-recv" >"$t/proc/interrupts"
out=$(K114S_SYSFS=$t/sys K114S_PROC=$t/proc "$here/k114s-gpu-qualify.sh" 0.1 1 2>&1)
[[ $out == *"unsupported GPU telemetry"* ]] && ok "GPU found on card2 by glob" || { bad "glob"; echo "$out"; }
exit $fail
