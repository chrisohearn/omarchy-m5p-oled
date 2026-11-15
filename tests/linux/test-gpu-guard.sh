#!/bin/bash
# Test of linux/r3a-trial/70-k114s-gpu-desktop (the session guard, version 2) with a fake /sys and a fake home.
# Not for a machine that has /dev/dri/by-path/platform-display-subsystem-card (the guard then prints nothing by design).
#   usage: test-gpu-guard.sh [PATH-TO-GUARD]
set -u
H=$(cd "$(dirname "$0")" && pwd); G=${1:-$H/../../linux/r3a-trial/70-k114s-gpu-desktop}
W=$(mktemp -d "${TMPDIR:-/tmp}/k114s-guard-test.XXXXXX"); trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: got [$2] want [$3]"; fi; }
[ -e /dev/dri/by-path/platform-display-subsystem-card ] && { echo "skipped: this machine has the display card"; exit 0; }
mkdir -p "$W/home/.config" "$W/sys/bus/platform/drivers/aurora/2300000000.gpu/drm/renderD128" "$W/sys0"
g() { HOME=$W/home K114S_SYS_ROOT=$1 K114S_UNAME_R=$2 sh "$G" | tr '\n' ' '; }
CPU="LIBGL_ALWAYS_SOFTWARE=1 GBM_ALWAYS_SOFTWARE=1 ASAHI_M5_BRINGUP=0 "
R1=7.3.0-17.v272-4-ARCH; R3=7.3.0-17.v272-4-k114s-r3a-ARCH
ok "no render node (the r1 tree): prints nothing, on either kernel" "$(g $W/sys0 $R1)$(g $W/sys0 $R3)" ""
ok "render node, no opt-in: CPU" "$(g $W/sys $R1)" "$CPU"
touch $W/home/.config/k114s-gpu-desktop
ok "render node, opt-in, running kernel: GPU (nothing printed)" "$(g $W/sys $R1)" ""
ok "render node, opt-in, r3a kernel: CPU" "$(g $W/sys $R3)" "$CPU"
touch $W/home/.config/k114s-gpu-desktop-r3a
ok "render node, both opt-ins, r3a kernel: GPU" "$(g $W/sys $R3)" ""
echo zink > $W/home/.config/k114s-gpu-desktop
ok "zink request still honoured with both opt-ins" "$(g $W/sys $R3)" "MESA_LOADER_DRIVER_OVERRIDE=zink "
rm $W/home/.config/k114s-gpu-desktop
ok "only the r3a opt-in: CPU" "$(g $W/sys $R3)" "$CPU"
echo "gpu guard tests: $pass passed, $fail failed"; [ "$fail" = 0 ]
