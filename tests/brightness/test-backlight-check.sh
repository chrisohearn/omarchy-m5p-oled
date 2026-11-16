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

# 10. A failing write is reported as failed, never as "wrote N nits", and stops the run.
s=$(fake ro2 1000 500)
chmod a-w "$s/apple-panel-bl/brightness"
rc=0; printf 's\nb\n' | run "$s" >"$tmp/ro2.out" 2>&1 || rc=$?
check "failed write: exit 1, says WRITE FAILED" "(( rc == 1 )) && grep -q 'WRITE FAILED' '$tmp/ro2.out'"
check "failed write: no 'wrote N nits' line" "! grep -q 'wrote [0-9]' '$tmp/ro2.out'"
check "failed write: restore failure is reported" "grep -q 'RESTORE OF' '$tmp/ro2.out'"

# 11. The kernel floor is reported from the kernel log line, not from the device tree alone.
s=$(fake kl 1000 500)
run "$s" --read-only </dev/null >"$tmp/kl0.out"
check "no kernel log line: says the floor is not seen" "grep -q 'NOT SEEN' '$tmp/kl0.out'"
echo '[    5.1] apple-dcp x: brightness requests below 10 nits are raised to 10 nits' >"$tmp/klog"
K114S_BL_KLOG=$tmp/klog run "$s" --read-only </dev/null >"$tmp/kl1.out"
check "kernel log line present: says yes" "grep -q 'kernel applies it   yes' '$tmp/kl1.out'"

echo '[    5.2] apple-dcp x: brightness floor 10 ignored for a ceiling of 5' >>"$tmp/klog"
K114S_BL_KLOG=$tmp/klog run "$s" --read-only </dev/null >"$tmp/kl2.out"
check "floor dropped after probe: says NOT APPLIED, not yes" "grep -q 'NOT APPLIED' '$tmp/kl2.out' && ! grep -q 'applies it   yes' '$tmp/kl2.out'"

# 12. The systemd drop-in holds the unit off until the marker file exists.
conf=$here/../../linux/brightness/systemd/k114s-first-boot.conf
check "drop-in: unit conditional on the marker file" "grep -qx 'ConditionPathExists=/var/lib/k114s-backlight/restore-enabled' '$conf'"

# 13. --auto (the agent's check): no questions, down to the floor and back up, never above the start, never 0.
s=$(fake auto 1000 500)
run "$s" --auto </dev/null >"$tmp/auto.out"
check "--auto: the ladder, down to 10 and back to the start" "[[ \"\$(writes $s)\" == '500 250 100 50 20 10 20 50 100 250 500 ' ]]"
check "--auto: ends at the start level and says done" "[[ \$(<$s/apple-panel-bl/brightness) == 500 ]] && grep -q 'agent ladder done' '$tmp/auto.out'"
check "--auto: nothing above the start or below 10, no 0" "! tr ' ' '\n' <<<\"\$(writes $s)\" | grep -q -x -e 0 -e 1000 -e '[1-9]'"
s=$(fake autolow 1000 40)
run "$s" --auto </dev/null >"$tmp/autolow.out"
check "--auto from a start of 40 nits: 25 % and 10 % are above it and skipped" "[[ \"\$(writes $s)\" == '40 20 10 20 40 ' ]]"
# a write that reads back another level stops the ladder and puts the start level back (a copy of the tool whose
# actual_brightness reads 77 after a write of 100)
s=$(fake autobad 1000 500)
sed 's#echo "$1" >"$p/actual_brightness"#echo "$(( $1 == 100 ? 77 : $1 ))" >"$p/actual_brightness"#' "$tool" > "$tmp/tool-bad"
rc=0; K114S_BL_SYSFS=$s K114S_BL_SETTLE=0 XDG_STATE_HOME=$tmp/state bash "$tmp/tool-bad" --auto </dev/null >"$tmp/autobad.out" 2>&1 || rc=$?
check "--auto: an actual_brightness that differs from the write stops the ladder at 100 and puts 500 back" "(( rc == 1 )) && [[ \"\$(writes $s)\" == '500 250 100 500 ' ]] && grep -q 'agent ladder stopped at 100' '$tmp/autobad.out'"
# a failing write in --auto restores the start level, not the maximum
s=$(fake autoro 1000 500)
chmod a-w "$s/apple-panel-bl/brightness"
rc=0; run "$s" --auto </dev/null >"$tmp/autoro.out" 2>&1 || rc=$?
check "--auto: a failing write exits 1 and never tries the maximum" "(( rc == 1 )) && grep -q 'WRITE FAILED' '$tmp/autoro.out' && ! grep -q 'restored 1000' '$tmp/autoro.out' && [[ ! -s $s/apple-panel-bl/writes.log ]]"

# a device that reports less than the floor: --auto starts at the floor (10), not at half the maximum, and stays within 10..start
s=$(fake autobelow 1000 5)
run "$s" --auto </dev/null >"$tmp/autobelow.out"
check "--auto: a reported level below the floor starts at the floor, never at max/2" "[[ \"\$(writes $s)\" == '10 ' ]] && grep -q 'agent ladder done' '$tmp/autobelow.out'"
# a TERM in the middle of the ladder puts the start level back, not the last level written (a copy that sends itself TERM after the write of 50)
s=$(fake autoterm 1000 500)
sed 's#&& echo "$1" >>"$p/writes.log"#\&\& echo "$1" >>"$p/writes.log"; [[ $1 != 50 ]] || kill -TERM $$#' "$tool" > "$tmp/tool-term"
rc=0; K114S_BL_SYSFS=$s K114S_BL_SETTLE=0 XDG_STATE_HOME=$tmp/state bash "$tmp/tool-term" --auto </dev/null >"$tmp/autoterm.out" 2>&1 || rc=$?
check "--auto: a TERM mid-ladder puts the start level (500) back" "(( rc == 130 )) && [[ \"\$(writes $s)\" == '500 250 100 50 500 ' ]]"

echo "# backlight-check replica: $fails failed"
exit $(( fails > 0 ))
