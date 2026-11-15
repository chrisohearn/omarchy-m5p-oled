#!/bin/bash
# K114s suspend-to-idle checks for the owner to run on the Mac. See docs/r3-sleep-lid.md.
#
#   k114s-sleep-check.sh status             no root: what the machine would do on a lid close
#   sudo k114s-sleep-check.sh pm-test LEVEL  LEVEL = freezer | devices | platform
#                                            runs the suspend path up to LEVEL, waits 5 s and
#                                            comes back by itself; the machine never idles
#   sudo k114s-sleep-check.sh cycle          one real suspend-to-idle; wake it with a key, the
#                                            power button or by opening the lid
#
# pm-test and cycle write to /sys/power directly: logind, its inhibitors and the lock screen are
# not involved, so the session comes back unlocked. Nothing is written anywhere else, and the
# output holds no serial numbers, addresses or network names.
set -u

# K114S_SYS_POWER points the script at a copy of /sys/power; only tests/hardware/test-sleep-check.sh
# sets it.
power=${K114S_SYS_POWER:-/sys/power}
stats=$power/suspend_stats

stat() { cat "$stats/$1" 2>/dev/null || echo "?"; }

show_stats() {
  printf 'suspend_stats: success=%s fail=%s failed_suspend_noirq=%s last_failed_dev=%s last_failed_errno=%s last_failed_step=%s\n' \
    "$(stat success)" "$(stat fail)" "$(stat failed_suspend_noirq)" \
    "$(stat last_failed_dev)" "$(stat last_failed_errno)" "$(stat last_failed_step)"
}

status() {
  local c name
  echo "kernel: $(uname -r) $(uname -v)"
  echo "machine: $(tr '\0' ' ' </proc/device-tree/compatible 2>/dev/null)"
  echo "sleep states: $(cat "$power/state" 2>/dev/null) / mem_sleep: $(cat "$power/mem_sleep" 2>/dev/null)"
  show_stats
  for c in /sys/class/drm/card*-*; do
    [[ -e $c/status ]] || continue
    name=${c##*/}
    echo "connector: ${name#card*-} $(cat "$c/status")"
  done
  echo "lid switch devices: $(grep -l '^1$' /sys/class/input/input*/capabilities/sw 2>/dev/null | wc -l)"
  if command -v busctl >/dev/null; then
    echo "logind: $(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
      org.freedesktop.login1.Manager HandleLidSwitch HandleLidSwitchDocked LidClosed BlockInhibited 2>/dev/null | tr '\n' ' ')"
  fi
  if command -v systemd-inhibit >/dev/null && command -v jq >/dev/null; then
    echo "block inhibitors (a handle-lid-switch one means a lid close does nothing):"
    systemd-inhibit --list --no-pager --json=short 2>/dev/null |
      jq -r '.[] | select(.mode == "block") | "  \(.who): \(.what) (\(.why))"' 2>/dev/null
  fi
  echo "wakeup sources: $(cat /sys/class/wakeup/*/name 2>/dev/null | tr '\n' ' ')"
  echo "battery uevent lines: $(grep -c . /sys/class/power_supply/macsmc-battery/uevent 2>/dev/null || true)"
}

need_root() {
  [[ $EUID -eq 0 || $power != /sys/power ]] || { echo "run this mode with sudo" >&2; exit 2; }
}

# The kernel lines of this boot from the last "suspend entry" on, with MAC-like strings cut.
suspend_log() {
  journalctl -b -k --no-pager -o short-monotonic 2>/dev/null |
    awk '/PM: suspend entry/ { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }' |
    grep -E 'PM:|pcie-apple|adopted link|apple_centauri|btcentauri|nvme|RTKit|macsmc-input|SError|simple-framebuffer|Freezing|Restarting' |
    sed -E 's/([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/xx:xx:xx:xx:xx:xx/g' | tail -n 60
}

run() {
  local level=$1 s0 f0 s1 f1 rc=0 t0 t1
  s0=$(stat success); f0=$(stat fail)
  trap 'echo none >"$power/pm_test" 2>/dev/null' EXIT
  echo "$level" >"$power/pm_test" || { echo "pm_test=$level refused" >&2; exit 1; }
  sync
  t0=$(date +%s)
  echo freeze >"$power/state" || rc=$?
  t1=$(date +%s)
  echo none >"$power/pm_test"
  s1=$(stat success); f1=$(stat fail)
  echo "pm_test=$level: write returned $rc after $((t1 - t0)) s"
  show_stats
  suspend_log
  if [[ $rc -eq 0 && $s1 == "$((s0 + 1))" && $f1 == "$f0" ]]; then
    echo "RESULT: PASS (success $s0 -> $s1, fail stays $f0)"
  else
    echo "RESULT: FAIL (success $s0 -> $s1, fail $f0 -> $f1)"
    exit 1
  fi
}

case ${1:-status} in
  status) status ;;
  pm-test)
    need_root
    case ${2:-} in
      freezer | devices | platform) run "$2" ;;
      *) echo "usage: $0 pm-test freezer|devices|platform" >&2; exit 2 ;;
    esac ;;
  cycle) need_root; run none ;;
  *) sed -n '2,13p' "$0"; exit 2 ;;
esac
