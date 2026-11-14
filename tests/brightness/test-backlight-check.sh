#!/bin/bash
# Replica test of linux/brightness/k114s-backlight-check against a stand-in sysfs directory.
# Evidence class: emulator/replica. It proves the script's own rules (never below the lowest
# level, never 0, no answer puts the last confirmed level back); it says nothing about the
# kernel, the display coprocessor or the panel.
#
#     tests/brightness/test-backlight-check.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tool=$here/../../linux/brightness/k114s-backlight-check
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }

fake() { # fake NAME MAX START
  local d=$tmp/$1/apple-panel-bl
  mkdir -p "$d"
  echo "$2" >"$d/max_brightness"; echo "$3" >"$d/brightness"; echo "$3" >"$d/actual_brightness"
  echo platform >"$d/type"; echo linear >"$d/scale"; : >"$d/writes.log"
  echo "$tmp/$1"
}
run() { # run SYSFS ARGS... (answers on stdin)
  local s=$1; shift
  K114S_BL_SYSFS=$s K114S_BL_SETTLE=0 XDG_STATE_HOME=$tmp/state bash "$tool" "$@"
}
writes() { tr '\n' ' ' <"$1/apple-panel-bl/writes.log"; }

# 1. No device: says so, exits 1, writes nothing.
mkdir -p "$tmp/none"
rc=0; run "$tmp/none" </dev/null >"$tmp/none.out" 2>&1 || rc=$?
check "no device: exit 1" "(( rc == 1 ))"
check "no device: explains" "grep -q 'has not registered' '$tmp/none.out'"

# 2. Read-only prints and writes nothing.
s=$(fake ro 1000 500)
run "$s" --read-only </dev/null >"$tmp/ro.out"
check "read-only: no write" "[[ ! -s $s/apple-panel-bl/writes.log ]]"
check "read-only: shows the maximum" "grep -q 'max_brightness      1000 nits' '$tmp/ro.out'"

# 3. Every step confirmed: full series on a 1000-nit scale, lowest 10, back to the start.
s=$(fake full 1000 500)
printf 's\nb\nd\nd\nd\nd\nd\nd\n' | run "$s" >"$tmp/full.out"
check "full run: the series" "[[ \"\$(writes $s)\" == '500 1000 250 100 50 20 10 500 ' ]]"
check "full run: ends at the start level" "[[ \$(<$s/apple-panel-bl/brightness) == 500 ]]"

# 4. No answer at 100 nits (the screen is unreadable): the last confirmed level, 250, comes back
#    and nothing lower is written.
s=$(fake dark 1000 500)
{ printf 's\nb\nd\n'; sleep 3; } | run "$s" --timeout 1 >"$tmp/dark.out" || true
check "no answer: stops and restores" "[[ \"\$(writes $s)\" == '500 1000 250 100 250 500 ' ]]"
check "no answer: said so" "grep -q 'owner: no answer' '$tmp/dark.out'"

# 5. No answer at the very first write: nothing was confirmed, so the maximum is written.
s=$(fake first 1000 500)
rc=0; { sleep 3; } | run "$s" --timeout 1 >"$tmp/first.out" || rc=$?
check "first write unanswered: maximum, exit 1" "(( rc == 1 )) && [[ \"\$(writes $s)\" == '500 1000 ' ]]"

# 6. 'n' (hard to read) counts as unreadable.
s=$(fake n 1000 500)
printf 's\nb\nd\nn\n' | run "$s" >"$tmp/n.out" || true
check "'n': restores the last confirmed level" "[[ \"\$(writes $s)\" == '500 1000 250 100 250 500 ' ]]"

# 7. A device that reports 0 (or anything below the lowest level) is never written back as 0.
s=$(fake zero 600 0)
printf 's\nb\nd\nd\nd\nd\nd\nd\n' | run "$s" >"$tmp/zero.out"
check "start reading 0: first write is half the maximum" "[[ \"\$(writes $s)\" == 300\\ * ]]"
check "nothing below 10 nits on a 600-nit scale" "! tr ' ' '\n' <<<\"\$(writes $s)\" | grep -qx '[0-9]'"

# 8. --lowest 0 and a nonsense scale are refused.
s=$(fake args 1000 500)
rc=0; run "$s" --lowest 0 </dev/null >/dev/null 2>&1 || rc=$?
check "--lowest 0 refused" "(( rc == 2 )) && [[ ! -s $s/apple-panel-bl/writes.log ]]"
s=$(fake tiny 15 7)
rc=0; run "$s" </dev/null >/dev/null 2>&1 || rc=$?
check "a 15-step scale is refused" "(( rc == 1 )) && [[ ! -s $s/apple-panel-bl/writes.log ]]"

# 9. Interrupted mid-run: the last confirmed level comes back.
s=$(fake int 1000 500)
( printf 's\nb\nd\n'; sleep 30 ) | K114S_BL_SYSFS=$s K114S_BL_SETTLE=0 XDG_STATE_HOME=$tmp/state \
  bash "$tool" --timeout 30 >"$tmp/int.out" 2>&1 &
pid=$!
for _ in $(seq 50); do grep -q '^100$' "$s/apple-panel-bl/writes.log" && break; sleep 0.1; done
kill -TERM "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
check "SIGTERM: restores the last confirmed level" "[[ \"\$(writes $s)\" == '500 1000 250 100 250 ' ]]"
pkill -P $$ sleep 2>/dev/null || true

echo "# backlight-check replica: $fails failed"
exit $(( fails > 0 ))
