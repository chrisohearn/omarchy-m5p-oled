#!/bin/bash
# OWNER-RUN. Battery charge-limit test for the K114s. See issue #53.
#
#   k114s-charge-limit-test.sh status      no root, writes nothing: what the SMC reports now
#   sudo k114s-charge-limit-test.sh run    WRITES SMC STATE: sets 80, reads it back, then sets 100, then restores what it found
#
# Run with the Mac on AC. `run` goes through omarchy-battery-charge-limit, so it also writes
# /etc/udev/macsmc-battery.conf (80, then 100). The starting limit and saved file are put back on every exit path,
# including Ctrl-C. Reboot with the limit at 80 by hand to check the boot restore: run
# `omarchy battery charge limit 80`, reboot, `status` here, then `omarchy battery charge limit 100`.
# Output holds no serial numbers or addresses.
set -u

sys=${K114S_SYSFS:-/sys}
bat=$sys/class/power_supply/macsmc-battery
ac=$sys/class/power_supply/macsmc-ac
conf=${K114S_CONF:-/etc/udev/macsmc-battery.conf}
tool=${K114S_LIMIT_TOOL:-omarchy-battery-charge-limit}

rd() { cat "$1" 2>/dev/null || echo "?"; }
show() {
  echo "$1: end=$(rd "$bat/charge_control_end_threshold") start=$(rd "$bat/charge_control_start_threshold")" \
    "behaviour=$(rd "$bat/charge_behaviour") status=$(rd "$bat/status") capacity=$(rd "$bat/capacity")" \
    "ac_online=$(rd "$ac/online") saved=$(cat "$conf" 2>/dev/null | tr '\n' ' ')"
}

mode=${1:-status}
case $mode in
  status) show "now"; exit 0 ;;
  run) ;;
  *) echo "usage: $0 status | run (run needs sudo)" >&2; exit 2 ;;
esac
[[ ${K114S_ALLOW_USER:-} == 1 || $EUID -eq 0 ]] || { echo "run needs sudo: sudo $0 run" >&2; exit 2; }
[[ $(rd "$ac/online") == 1 ]] || { echo "refusing: the Mac is not on AC (macsmc-ac online != 1)" >&2; exit 2; }

fail=0
check() { # label want-end want-start
  local e s; e=$(rd "$bat/charge_control_end_threshold"); s=$(rd "$bat/charge_control_start_threshold")
  if [[ $e == "$2" && $s == "$3" ]]; then echo "PASS $1 (end $e, start $s)"; else echo "FAIL $1 (end $e want $2, start $s want $3)"; fail=1; fi
}
# Put back what was found: the starting end threshold and the saved file (or its absence).
orig_end=$(rd "$bat/charge_control_end_threshold")
if [[ -e $conf ]]; then orig_conf=$(cat "$conf"); had_conf=1; else orig_conf=; had_conf=0; fi
[[ $orig_end == 80 ]] && want_end=80 || want_end=100   # the tool accepts only 80 and 100
restore() {
  "$tool" "$want_end" >/dev/null 2>&1
  if [[ $had_conf == 1 ]]; then printf '%s\n' "$orig_conf" >"$conf" 2>/dev/null; else rm -f "$conf" 2>/dev/null; fi
  if [[ $(rd "$bat/charge_control_end_threshold") != "$want_end" || $orig_end != "$want_end" ]] \
     || [[ $had_conf == 0 && -e $conf ]]; then
    echo "WARNING: could not restore exactly (started at end $orig_end, now $(rd "$bat/charge_control_end_threshold"), saved file $([[ $had_conf == 1 ]] && echo kept || echo absent)); run: omarchy battery charge limit $want_end" >&2
  fi
}
trap restore EXIT

show "before"
"$tool" 80 || fail=1
check "limit 80 read back" 80 75
sleep "${K114S_SETTLE:-5}"
show "after 80 (status should not be Charging; at <=80% it may still charge)"
grep -qx 'CHARGE_CONTROL_END_THRESHOLD=80' "$conf" 2>/dev/null && echo "PASS saved for boot" || { echo "FAIL saved file lacks 80"; fail=1; }
"$tool" 100 || fail=1
check "limit 100 read back" 100 100
grep -qx 'CHARGE_CONTROL_END_THRESHOLD=100' "$conf" 2>/dev/null && echo "PASS saved 100" || { echo "FAIL saved file lacks 100"; fail=1; }
show "after"
[[ $fail -eq 0 ]] && echo "RESULT: PASS" || echo "RESULT: FAIL"
exit $fail
