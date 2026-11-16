#!/bin/bash
# K114s Vulkan client check (issue #26). Read-only except for one bounded vkcube run that opens a
# window: run it from a terminal in the desktop session, with the owner watching the panel.
#   k114s-vulkan-check.sh            environment, vulkaninfo summary and queue families (no window)
#   k114s-vulkan-check.sh --vkcube   also run vkcube for 10 s: a spinning cube is the pass
#   k114s-vulkan-check.sh --after-zink  expect the desktop itself to run through zink (procedure in docs/vulkan-clients.md)
# Needs vulkan-tools (pacman -S vulkan-tools). Exit 0 = no FAIL; SKIP means a tool is missing.
# K114S_VK_ENV overrides the environment source (default: the systemd user manager), for tests.
set -u
vkcube=0 zink=0
for a in "$@"; do case $a in --vkcube) vkcube=1 ;; --after-zink) zink=1 ;; *) sed -n '2,8p' "$0"; exit 2 ;; esac; done
fail=0
pass() { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=1; }
have() { command -v "$1" >/dev/null 2>&1; }
if [[ -v K114S_VK_ENV ]]; then env_txt=$K114S_VK_ENV; else env_txt=$(systemctl --user show-environment 2>/dev/null); fi

echo "== session environment (what apps started from the desktop inherit)"
if [[ -z $env_txt ]]; then
  bad "cannot read the user manager environment (no user bus, e.g. over ssh): run this from a terminal in the desktop session"
else
grep -qx 'ASAHI_M5_BRINGUP=1' <<<"$env_txt" && pass "ASAHI_M5_BRINGUP=1" || bad "ASAHI_M5_BRINGUP is not 1: Mesa refuses the M5 device (this is what blacked out the first zink try)"
grep -qE '^(LIBGL_ALWAYS_SOFTWARE|GBM_ALWAYS_SOFTWARE)=1' <<<"$env_txt" && bad "software rendering is forced" || pass "no software rendering forced"
if [[ $zink -eq 1 ]]; then
  grep -qx 'MESA_LOADER_DRIVER_OVERRIDE=zink' <<<"$env_txt" && pass "desktop runs through zink" || bad "MESA_LOADER_DRIVER_OVERRIDE=zink missing: the opt-in file does not say zink, the per-kernel opt-in ~/.config/k114s-gpu-desktop-r3a (or -r3b) is missing (r3 guard version 3), or the user manager was not restarted"
else
  grep -qx 'MESA_LOADER_DRIVER_OVERRIDE=zink' <<<"$env_txt" && echo "INFO desktop is on zink" || echo "INFO desktop is on the native driver"
fi
fi

echo "== Vulkan device"
if have vulkaninfo; then
  out=$(timeout -k 5 60 vulkaninfo --summary 2>&1); rc=$?
  if [[ $rc -eq 0 && $out == *"Apple M5 Pro"* ]]; then
    pass "vulkaninfo lists the Apple M5 Pro device"
    grep -E 'apiVersion|deviceName|driverName|driverInfo|conformanceVersion' <<<"$out" | sed 's/^[[:space:]]*/  /'
  else bad "vulkaninfo rc=$rc, no Apple M5 Pro device"; fi
  q=$(timeout -k 5 60 vulkaninfo 2>/dev/null | grep -E 'queueFlags')
  grep -q 'QUEUE_GRAPHICS_BIT.*QUEUE_COMPUTE_BIT' <<<"$q" && pass "a graphics+compute queue family exists" || bad "no graphics+compute queue family"
else echo "SKIP vulkaninfo missing (pacman -S vulkan-tools)"; fi

if [[ $vkcube -eq 1 ]]; then
  echo "== vkcube (opens a window; LOOK AT THE PANEL)"
  if have vkcube; then
    timeout -k 5 10 vkcube --c 600 >/dev/null 2>&1; rc=$?
    [[ $rc -eq 0 || $rc -eq 124 ]] && echo "INFO vkcube ran 10 s (exit $rc): owner says whether a cube spun" || bad "vkcube crashed, exit $rc"
  else echo "SKIP vkcube missing (vulkan-tools)"; fi
fi
echo "== done: $([[ $fail -eq 0 ]] && echo "no FAIL" || echo "at least one FAIL")"
exit $fail
