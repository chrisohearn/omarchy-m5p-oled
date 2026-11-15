#!/bin/bash
# Software test of k114s-sleep-check.sh against a fake /sys/power (no root, no suspend).
# It proves the script's own logic only: argument handling, the pass/fail decision from the
# suspend_stats counters, and that pm_test is always put back to "none".
set -u
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d) || exit 2
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

fake() { # success fail -> a fresh fake tree
  local d=$t/$RANDOM
  mkdir -p "$d/suspend_stats"
  echo "freeze mem" >"$d/state"; echo "[s2idle]" >"$d/mem_sleep"; echo "[none] freezer devices platform" >"$d/pm_test"
  echo "$1" >"$d/suspend_stats/success"; echo "$2" >"$d/suspend_stats/fail"
  echo 0 >"$d/suspend_stats/failed_suspend_noirq"; echo "" >"$d/suspend_stats/last_failed_dev"
  echo 0 >"$d/suspend_stats/last_failed_errno"; echo "" >"$d/suspend_stats/last_failed_step"
  echo "$d"
}

# 1. counters that do not move are a FAIL, and pm_test is restored
d=$(fake 3 0)
out=$(K114S_SYS_POWER=$d "$here/k114s-sleep-check.sh" pm-test platform 2>&1); rc=$?
[[ $rc -eq 1 && $out == *"RESULT: FAIL (success 3 -> 3, fail 0 -> 0)"* ]] && ok "unchanged counters fail" || bad "unchanged counters: rc=$rc"
[[ $(<"$d/pm_test") == none ]] && ok "pm_test restored after a failure" || bad "pm_test left at $(<"$d/pm_test")"
[[ $(<"$d/state") == freeze ]] && ok "freeze was written to state" || bad "state holds $(<"$d/state")"

# 2. a success counter that moves by one with fail unchanged is a PASS
d=$(fake 3 0)
( while [[ $(<"$d/pm_test") != devices ]]; do sleep 0.05; done; echo 4 >"$d/suspend_stats/success" ) &
bg=$!
# hold the write to state until the counter moved: state is a FIFO here
rm "$d/state"; mkfifo "$d/state"
( wait_n=0; while [[ $(<"$d/suspend_stats/success") != 4 && $wait_n -lt 100 ]]; do sleep 0.05; wait_n=$((wait_n + 1)); done; cat "$d/state" >/dev/null ) &
out=$(K114S_SYS_POWER=$d timeout 20 "$here/k114s-sleep-check.sh" pm-test devices 2>&1); rc=$?
wait "$bg" 2>/dev/null
[[ $rc -eq 0 && $out == *"RESULT: PASS (success 3 -> 4, fail stays 0)"* ]] && ok "one more success passes" || bad "pass case: rc=$rc out=$out"
[[ $(<"$d/pm_test") == none ]] && ok "pm_test restored after a pass" || bad "pm_test left at $(<"$d/pm_test")"

# 3. a moved fail counter is a FAIL even when success moved
d=$(fake 1 0); rm "$d/state"; mkfifo "$d/state"
( while [[ $(<"$d/pm_test") != none || ! -p "$d/state" ]]; do sleep 0.05; done; echo 2 >"$d/suspend_stats/success"; echo 1 >"$d/suspend_stats/fail"; cat "$d/state" >/dev/null ) &
out=$(K114S_SYS_POWER=$d timeout 20 "$here/k114s-sleep-check.sh" cycle 2>&1); rc=$?
[[ $rc -eq 1 && $out == *"RESULT: FAIL (success 1 -> 2, fail 0 -> 1)"* ]] && ok "a failure is not hidden by a success" || bad "fail case: rc=$rc out=$out"

# 4. arguments
"$here/k114s-sleep-check.sh" pm-test core >/dev/null 2>&1; [[ $? -eq 2 ]] && ok "unknown level refused" || bad "unknown level accepted"
K114S_SYS_POWER= "$here/k114s-sleep-check.sh" nonsense >/dev/null 2>&1; [[ $? -eq 2 ]] && ok "unknown mode refused" || bad "unknown mode accepted"
if [[ $EUID -ne 0 ]]; then
  "$here/k114s-sleep-check.sh" cycle >/dev/null 2>&1; [[ $? -eq 2 ]] && ok "real /sys/power needs root" || bad "cycle ran without root"
fi
out=$("$here/k114s-sleep-check.sh" status 2>&1) && [[ $out == *"suspend_stats:"* ]] && ok "status runs without root" || bad "status"

[[ $fail -eq 0 ]] && echo "sleep-check test: passed" || echo "sleep-check test: FAILED"
exit $fail
