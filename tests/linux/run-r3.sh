#!/bin/bash
# Run every r3 update-tooling test as a normal user and print one summary.
#   usage: tests/linux/run-r3.sh [LINUX_DIR]
# No fixtures are needed and no real system file is touched. A test that lacks a tool on this
# host says SKIPPED and does not count as a failure (see the head of each test for what it needs).
T=$(cd "$(dirname "$0")" && pwd)
status=0; total_pass=0; total_fail=0; skipped=0
for f in "$T"/k114s-syntax.sh "$T"/test-r3-guard.sh "$T"/test-r3-recovery.sh "$T"/test-r3-check.sh "$T"/test-r3-release.sh "$T"/test-r3-install.sh "$T"/test-r3-pacman.sh "$T"/test-r3-pacman-sig.sh "$T"/test-runbook-stop.sh "$T"/test-esp-trim.sh \
    "$T"/test-boot-once.sh "$T"/test-gpu-guard.sh "$T"/test-promotion-runbook.sh "$T"/test-sleep-gates.sh; do
  [ -f "$f" ] || continue
  # the r3a-trial tests take the path of their one file, not LINUX_DIR
  case ${f##*/} in
    test-boot-once.sh) args=(${1:+"$1/r3a-trial/k114s-boot-once"}) ;;
    test-gpu-guard.sh) args=(${1:+"$1/r3a-trial/70-k114s-gpu-desktop"}) ;;
    *) args=("$@") ;;
  esac
  out=$(bash "$f" "${args[@]}" 2>&1); code=$?
  line=$(printf '%s\n' "$out" | tail -n 1)
  printf '%s\n' "$out" | grep '^FAIL' || true
  echo "$line"
  case $line in *SKIPPED*) skipped=$((skipped + 1)) ;; esac
  pass=$(printf '%s\n' "$line" | sed -n 's/.*: \([0-9][0-9]*\) passed, \([0-9][0-9]*\) failed$/\1/p'); fail=$(printf '%s\n' "$line" | sed -n 's/.*: \([0-9][0-9]*\) passed, \([0-9][0-9]*\) failed$/\2/p')
  total_pass=$((total_pass + ${pass:-0})); total_fail=$((total_fail + ${fail:-0}))
  [ "$code" = 0 ] || status=1
done
echo "r3 update tooling: $total_pass passed, $total_fail failed, $skipped test file(s) skipped"
exit $status
