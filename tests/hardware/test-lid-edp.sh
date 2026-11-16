#!/bin/bash
# Headless test of Omarchy's lid scripts against fake DRM connector trees (no root, no lid, no
# suspend, nothing on the desktop is touched; isolation checked against omarchy-dev r7906, and a
# command a later release adds to these scripts hits a fail-closed stub, not the live session). It proves how the installed Omarchy scripts
# decide, for the two connector names the K114s can show, and nothing about the kernel.
#   usage: tests/hardware/test-lid-edp.sh [OMARCHY_BIN_DIR]     (default /usr/share/omarchy/bin)
# Prints "SKIPPED" and exits 0 when the Omarchy scripts are not installed.
set -u
bin=${1:-/usr/share/omarchy/bin}
for s in omarchy-hw-external-monitors omarchy-system-lid-close omarchy-system-lid-inhibit; do
  [[ -x $bin/$s ]] || { echo "lid-edp test: SKIPPED ($s not found in $bin)"; exit 0; }
done
t=$(mktemp -d) || exit 2
trap 'rm -rf "$t"' EXIT
pass=0 fail=0
ok() { echo "ok   $1"; pass=$((pass + 1)); }
bad() { echo "FAIL $1"; fail=$((fail + 1)); }

drm() { # name... -> a fake /sys/class/drm with each connector "connected"
  local d n
  d=$(mktemp -d -p "$t" drm.XXXXXX)
  mkdir -p "$d/card0" "$d/renderD128"
  for n in "$@"; do mkdir -p "$d/card0-$n"; echo connected >"$d/card0-$n/status"; done
  echo "$d"
}

# stubs: record what the lid-close script would do
stubs=$t/stubs; mkdir -p "$stubs"
for s in omarchy-system-lock omarchy-hyprland-monitor-clamshell; do
  printf '#!/bin/bash\necho %s >>"$STUB_LOG"\n' "$s" >"$stubs/$s"
done
printf '#!/bin/bash\nexit 0\n' >"$stubs/omarchy-hw-laptop-closed"   # the lid is shut
for s in hyprctl systemctl busctl systemd-run; do
  printf '#!/bin/bash\necho "UNEXPECTED %s" >>"$STUB_LOG"; exit 1\n' "$s" >"$stubs/$s"
done
chmod +x "$stubs"/*

lid_close() { # drm dir -> the stub calls, space separated
  : >"$t/log"
  STUB_LOG=$t/log OMARCHY_DRM_PATH=$1 PATH="$stubs:$bin:$PATH" "$bin/omarchy-system-lid-close" >/dev/null 2>&1
  tr '\n' ' ' <"$t/log"
}

# 1. today: the boot framebuffer is Unknown-1 -> counted as an external monitor, no lock
d=$(drm Unknown-1)
OMARCHY_DRM_PATH=$d "$bin/omarchy-hw-external-monitors" && ok "Unknown-1 counts as an external monitor (today's bug)" || bad "Unknown-1 not counted as external"
[[ $(lid_close "$d") == "omarchy-hyprland-monitor-clamshell " ]] && ok "lid close on Unknown-1 does not lock" || bad "lid close on Unknown-1: $(lid_close "$d")"

# 2. with the apple,internal-panel property: simpledrm names it eDP-1 -> internal, lock
d=$(drm eDP-1)
OMARCHY_DRM_PATH=$d "$bin/omarchy-hw-external-monitors" && bad "eDP-1 counted as external" || ok "eDP-1 is not an external monitor"
[[ $(lid_close "$d") == "omarchy-system-lock omarchy-hyprland-monitor-clamshell " ]] && ok "lid close on eDP-1 locks, then runs clamshell handling" || bad "lid close on eDP-1: $(lid_close "$d")"

# 3. a real external display beside the panel still means clamshell: no lock
d=$(drm eDP-1 DP-2)
[[ $(lid_close "$d") == "omarchy-hyprland-monitor-clamshell " ]] && ok "eDP-1 plus an external DP output: no lock (clamshell)" || bad "docked lid close: $(lid_close "$d")"

# 4. the lid inhibitor: with eDP-1 only it has no uncounted output and never needs hyprctl
inh=$t/inh; mkdir -p "$inh"
printf '#!/bin/bash\necho "hyprctl called" >>"$STUB_LOG"; echo "${STUB_HYPR:-}"; [[ -n ${STUB_HYPR:-} ]]\n' >"$inh/hyprctl"
printf '#!/bin/bash\nexit 0\n' >"$inh/omarchy-hw-laptop"
printf '#!/bin/bash\necho "s \\"ignore\\""\n' >"$inh/busctl"
printf '#!/bin/bash\nexit 3\n' >"$inh/systemctl"      # "unit not active"
printf '#!/bin/bash\necho "systemd-run called" >>"$STUB_LOG"\n' >"$inh/systemd-run"
chmod +x "$inh"/*
inhibit() { : >"$t/log"; STUB_HYPR=${2:-} STUB_LOG=$t/log OMARCHY_DRM_PATH=$1 PATH="$inh:$bin:$PATH" "$bin/omarchy-system-lid-inhibit" >/dev/null 2>&1; tr '\n' ' ' <"$t/log"; }
[[ $(inhibit "$(drm eDP-1)") == "" ]] && ok "eDP-1 only: lid inhibitor not taken, compositor not asked" || bad "inhibitor on eDP-1: $(inhibit "$(drm eDP-1)")"
[[ $(inhibit "$(drm Unknown-1)") == "hyprctl called " ]] && ok "Unknown-1: the inhibitor logic engages (asks Hyprland whether it is in use)" || bad "inhibitor on Unknown-1: $(inhibit "$(drm Unknown-1)")"
hypr='[{"name":"Unknown-1","disabled":false}]'
[[ $(inhibit "$(drm Unknown-1)" "$hypr") == "hyprctl called systemd-run called " ]] && ok "Unknown-1 enabled in Hyprland: the inhibitor is taken (today's bug)" || bad "inhibitor taken on Unknown-1: $(inhibit "$(drm Unknown-1)" "$hypr")"

echo "lid-edp test: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
