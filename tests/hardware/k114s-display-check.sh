#!/bin/bash
# Read-only report for the K114s display trial boots (docs/r3-display-trials.md). Changes nothing: it never writes to
# sysfs, the backlight, the ESP or a DRM device. Prints "ok", "BAD" or "info" lines and a last summary line.
#   tests/hardware/k114s-display-check.sh --expect refused|published|none [--loader-log FILE] [--wait SECONDS] [--hypr] [--vrr on|off] [--floor]
#     refused    the display tree on the installed loader (trial T1): the loader must refuse the hand-off
#     published  the display tree on the loader with the K114s pin (trial T2): the hand-off must be published
#     none       a tree without the display section (P, or the conditional loader-only boot D3)
#   --loader-log FILE   this boot's loader log, saved first thing (sudo cat /dev/mtd1ro | tr -d '\0' > FILE)
#   --wait SECONDS      the gap between the two GPU mailbox samples (default 10)
#   --hypr              also read Hyprland's monitors (run it as the desktop user, in the session)
#   --vrr on|off        published only: whether this boot offers VRR (D6: fw27_panel_vrr Y and vrr_capable 1); default off
#   --floor             published only: this boot carries the brightness build (D5: the floor line in the kernel log, apple,min-brightness 10)
# Root makes the kernel-log lines complete (dmesg is root-only here); the rest needs none.
# It never prints the kernel command line: every kernel-log line it shows has passed a filter that drops it.
# Test hooks: K114S_DT K114S_SYS K114S_DEV K114S_DMESG_FILE K114S_INTERRUPTS K114S_HYPRCTL K114S_SYSTEMCTL K114S_BACKLIGHT_STATE
set -u
DT=${K114S_DT:-/proc/device-tree}; SYS=${K114S_SYS:-/sys}; DEV=${K114S_DEV:-/dev}
IRQ=${K114S_INTERRUPTS:-/proc/interrupts}; HYPRCTL=${K114S_HYPRCTL:-hyprctl}; SYSTEMCTL=${K114S_SYSTEMCTL:-systemctl}
BLSTATE=${K114S_BACKLIGHT_STATE:-/var/lib/systemd/backlight}
expect=; log=; wait_s=10; hypr=0; vrr=off; floor=0
while [ $# -gt 0 ]; do
  case $1 in
    --expect) expect=${2:-}; shift ;; --loader-log) log=${2:-}; shift ;; --wait) wait_s=${2:-10}; shift ;; --hypr) hypr=1 ;;
    --vrr) vrr=${2:-}; shift ;; --floor) floor=1 ;;
    *) echo "usage: $0 --expect refused|published|none [--loader-log FILE] [--wait SECONDS] [--hypr] [--vrr on|off] [--floor]" >&2; exit 2 ;;
  esac; shift
done
case $expect in refused | published | none) ;; *) echo "usage: $0 --expect refused|published|none ..." >&2; exit 2 ;; esac
case $vrr in on | off) ;; *) echo "usage: $0 --vrr on|off" >&2; exit 2 ;; esac
vcap=0; vpar=N; [ "$vrr" = on ] && { vcap=1; vpar=Y; }
nok=0; nbad=0
ok() { echo "ok    $*"; nok=$((nok + 1)); }; bad() { echo "BAD   $*"; nbad=$((nbad + 1)); }; info() { echo "info  $*"; }
prop() { [ -e "$DT/$1" ] && tr -d '\0' < "$DT/$1"; }
nocmd() { grep -v -i -E 'command line|cmdline|bootargs|luks|root=' ; }   # nothing it prints can carry the command line
K116S_IMAGE=3D6C8857-E6F1-3D2E-9DFF-587028AE0C6E; J714S_IMAGE=C51FB0C8-C45D-39B0-85BC-520E600FC950

info "kernel $(uname -r 2>/dev/null); Stage 2: $(prop chosen/aurora,trial || echo 'the configured m1n1/boot-ctxr.bin')"
info "loader $(prop chosen/asahi,m1n1-stage2-version) (the installed loader and the K114s-pin loader both report this string)"

# 1. the loader's decision: the marker it leaves in /chosen, and its own log
marker=$(prop chosen/asahi,t6050-dcp-handoff); want=$expect; [ "$expect" = none ] && want=
[ "$marker" = "$want" ] && ok "/chosen/asahi,t6050-dcp-handoff: ${marker:-absent} (expected for '$expect')" ||
  bad "/chosen/asahi,t6050-dcp-handoff is '${marker:-absent}', expected '${want:-absent}'"
if [ -n "$log" ]; then
  if [ -r "$log" ]; then
    has() { grep -q -F -- "$1" "$log"; }
    info "loader log: $(grep -c -F '__OS_LOG' "$log") '__OS_LOG ... overlaps /memreserve/' line(s) (five are expected and benign, aura #226)"
    case $expect in
      refused)
        has "DCP image $K116S_IMAGE is not $J714S_IMAGE" && ok "loader: DCP image $K116S_IMAGE is not $J714S_IMAGE (the installed loader's pin)" || bad "loader: no 'DCP image $K116S_IMAGE is not $J714S_IMAGE' line"
        has "internal display handoff refused; the boot framebuffer keeps the panel" && ok "loader: internal display handoff refused" || bad "loader: no 'internal display handoff refused' line" ;;
      published)
        has "internal display handed off: firmware 27.2" && ok "loader: internal display handed off: firmware 27.2" || bad "loader: no 'internal display handed off: firmware 27.2' line"
        has "external display engines not handed off on firmware 27.2" && ok "loader: external display engines not handed off (Aura 0008, internal panel only)" || bad "loader: no 'external display engines not handed off on firmware 27.2' line (is this the K114s-pin loader?)"
        has "handoff refused" && bad "loader: a refusal line: $(grep -F 'handoff refused' "$log" | head -1 | nocmd)" ;;
      none)
        has "the device tree does not describe the internal display: no handoff" && ok "loader: the device tree does not describe the internal display: no handoff" || bad "loader: no 'does not describe the internal display' line" ;;
    esac
    grep -E 'GPU:|WDT' "$log" | nocmd | sort -u | head -12 | sed 's/^/info  loader: /'
  else bad "cannot read the loader log $log"; fi
else info "no --loader-log: the loader's own lines are not checked"; fi

# 2. the device-tree nodes the loader enables only when it publishes the hand-off
st() { prop "$1/status" || echo absent; }
dcp=$(ls -d "$DT"/soc/dcp@48ae00000 2>/dev/null); dcp=${dcp#"$DT"/}
if [ -z "$dcp" ]; then bad "no soc/dcp@48ae00000 node"
elif [ "$expect" = published ]; then
  [ "$(st "$dcp")" = okay ] && ok "$dcp: okay" || bad "$dcp is $(st "$dcp"), not okay"
  [ "$(st display-subsystem)" = okay ] && ok "display-subsystem: okay" || bad "display-subsystem is $(st display-subsystem)"
  [ "$(prop "$dcp/apple,firmware-uuid")" = "$K116S_IMAGE" ] && ok "$dcp apple,firmware-uuid $K116S_IMAGE" || bad "$dcp apple,firmware-uuid is '$(prop "$dcp/apple,firmware-uuid")'"
  compat=$(od -An -tu4 --endian=big "$DT/$dcp/apple,firmware-compat" 2>/dev/null | tr -s ' ' | sed 's/^ //; s/ $//')
  [ "$compat" = "27 2 0" ] && ok "$dcp apple,firmware-compat 27 2 0" || bad "$dcp apple,firmware-compat is '$compat'"
else
  [ "$(st "$dcp")" = disabled ] && ok "$dcp: disabled" || bad "$dcp is $(st "$dcp"), not disabled"
  ds=$(st display-subsystem)
  case $expect:$ds in refused:disabled | none:absent) ok "display-subsystem: $ds" ;; *) bad "display-subsystem is $ds (expected $([ "$expect" = refused ] && echo disabled || echo absent))" ;; esac
fi

# 3. DRM: which driver owns the panel
cards=$(ls "$SYS/class/drm" 2>/dev/null | grep -E '^card[0-9]+-' | tr '\n' ' ')
info "DRM connectors: ${cards:-none}; fb0 $(cat "$SYS/class/graphics/fb0/name" 2>/dev/null || echo absent)"
dsc=$DEV/dri/by-path/platform-display-subsystem-card
if [ "$expect" = published ]; then
  [ -e "$dsc" ] && ok "the DCP card exists ($(readlink "$dsc" 2>/dev/null))" || bad "no $dsc"
  edp=$(ls -d "$SYS"/class/drm/card*-eDP-* 2>/dev/null | head -1)
  if [ -n "$edp" ]; then
    ok "connector ${edp##*/}: $(cat "$edp/status" 2>/dev/null)"
    modes=$(sort -u "$edp/modes" 2>/dev/null | tr '\n' ' ')
    [ -n "$modes" ] && ! sort -u "$edp/modes" | grep -v -q -x -E '3024x(1986|1964)' && ok "modes: $modes(3024 wide, 1986 or 1964 high)" || bad "modes: ${modes:-none}"
    [ -e "$edp/vrr_capable" ] && { [ "$(cat "$edp/vrr_capable")" = $vcap ] && ok "vrr_capable $vcap" || bad "vrr_capable $(cat "$edp/vrr_capable"), expected $vcap (--vrr $vrr)"; }
  else bad "no eDP connector"; fi
  case $(cat "$SYS/class/graphics/fb0/name" 2>/dev/null) in *appledrm*) ok "fb0 is appledrm's" ;; *) info "fb0 is not appledrm's" ;; esac
  p=$SYS/module/appledrm/parameters/fw27_panel_vrr
  [ "$(cat "$p" 2>/dev/null)" = $vpar ] && ok "appledrm.fw27_panel_vrr = $vpar (--vrr $vrr)" || bad "appledrm.fw27_panel_vrr is '$(cat "$p" 2>/dev/null)', not $vpar (--vrr $vrr)"
  bl=$SYS/class/backlight/apple-panel-bl
  if [ -d "$bl" ]; then
    [ "$(cat "$bl/max_brightness" 2>/dev/null)" = 1000 ] && ok "apple-panel-bl max_brightness 1000" || bad "apple-panel-bl max_brightness $(cat "$bl/max_brightness" 2>/dev/null)"
    info "apple-panel-bl brightness $(cat "$bl/brightness" 2>/dev/null), actual_brightness $(cat "$bl/actual_brightness" 2>/dev/null) (read only)"
  else bad "no apple-panel-bl backlight"; fi
else
  [ -e "$dsc" ] && bad "a DCP card exists: the panel left simpledrm" || ok "no DCP card"
  ls -d "$SYS"/class/drm/card*-Unknown-1 >/dev/null 2>&1 && ok "simpledrm keeps the panel ($(ls -d "$SYS"/class/drm/card*-Unknown-1 | head -1 | sed 's#.*/##'))" || bad "no simpledrm connector (card*-Unknown-1)"
  ls "$SYS/class/backlight" 2>/dev/null | grep -q . && bad "a backlight exists: $(ls "$SYS/class/backlight" | tr '\n' ' ')" || ok "no backlight device"
fi
# systemd-backlight must not write the level (the first-boot drop-in): it is skipped, and nothing is saved
c=$("$SYSTEMCTL" show -p ConditionResult --value 'systemd-backlight@backlight:apple-panel-bl.service' 2>/dev/null)
case $expect:$c in
  published:no) ok "systemd-backlight for apple-panel-bl was skipped (ConditionResult=no): nothing wrote the level" ;;
  published:*) bad "systemd-backlight for apple-panel-bl ran or did not report (ConditionResult='$c'): the drop-in is missing?" ;;
  *) info "systemd-backlight for apple-panel-bl: ConditionResult='${c:-}' (no device on this boot)" ;;
esac
ls "$BLSTATE" 2>/dev/null | grep -q apple-panel-bl && info "a saved systemd-backlight level exists for apple-panel-bl" || ok "no saved systemd-backlight level for apple-panel-bl"

# 4. the kernel log: crashes are BAD, the bring-up lines are shown (filtered)
if [ -n "${K114S_DMESG_FILE:-}" ]; then klog=$(cat "$K114S_DMESG_FILE"); else klog=$(dmesg 2>/dev/null); fi
if [ -z "$klog" ]; then info "the kernel log is root-only: run this with sudo for those lines"
else
  crash=$(printf '%s\n' "$klog" | nocmd | grep -E 'DCP has crashed|co-processor has crashed|DCP_FIRMWARE_UNKNOWN|present dropped|SError|Oops|BUG:|Unable to handle' | head -5)
  [ -z "$crash" ] && ok "kernel log: no DCP or RTKit crash, SError, Oops or BUG" || bad "kernel log: $crash"
  printf '%s\n' "$klog" | nocmd | grep -E 'simpledrm|DCP booted|Initialized apple|appledrm|no loader brightness reported|panel ADT|apple-panel-bl|aurora .*Initialized|GPU firmware' |
    sed 's/^\[ *\([0-9.]*\)\] /\1 /' | cut -c1-160 | head -20 | sed 's/^/info  kernel: /'
  if [ "$expect" = published ]; then
    printf '%s\n' "$klog" | grep -q 'Initialized apple .* for display-subsystem' && ok "kernel: [drm] Initialized apple for display-subsystem" || bad "kernel: no '[drm] Initialized apple ... for display-subsystem' line"
    if [ "$floor" = 1 ]; then
      printf '%s\n' "$klog" | grep -q 'brightness requests below 10 nits are raised to 10 nits' && ok "kernel: brightness requests below 10 nits are raised to 10 nits (the floor, patch 0006)" || bad "kernel: no 'brightness requests below 10 nits are raised to 10 nits' line (not the brightness build or tree)"
      printf '%s\n' "$klog" | grep -q 'brightness floor .* ignored' && bad "kernel: the brightness floor was dropped after probe"
      printf '%s\n' "$klog" | grep -q 'unqualified IOMFB callback 590' && bad "kernel: unqualified IOMFB callback 590 (brightness 0003 is the first patch to drop)"
      [ "$(od -An -tu4 --endian=big "$DT/$dcp/panel/apple,min-brightness" 2>/dev/null | tr -d ' ')" = 10 ] && ok "$dcp/panel apple,min-brightness 10" || bad "$dcp/panel apple,min-brightness is not 10 (not the brightness tree)"
    fi
  fi
fi

# 5. the GPU, as in every trial since the promotion: a render node and a receive interrupt that keeps firing
ls "$SYS"/bus/platform/drivers/aurora/*/drm/renderD* >/dev/null 2>&1 && ok "GPU render node present" || bad "no GPU render node"
irqsum() { # the per-CPU counts only: as many columns after the "NN:" label as the header has CPUs
  awk -v n="$1" 'NR == 1 { ncpu = NF; next } $NF == n { s = 0; for (i = 2; i <= ncpu + 1; i++) s += $i; print s; exit }' "$IRQ"; }
a1=$(irqsum 2302600000.mailbox-recv); b1=$(irqsum 2302e00000.mailbox-recv); sleep "$wait_s"; a2=$(irqsum 2302600000.mailbox-recv); b2=$(irqsum 2302e00000.mailbox-recv)
[ -n "$a1" ] && [ -n "$a2" ] && [ "$a2" -gt "$a1" ] && ok "2302600000.mailbox-recv rises: $a1 -> $a2 in ${wait_s}s (about $(((a2 - a1) / (wait_s > 0 ? wait_s : 1)))/s)" ||
  bad "2302600000.mailbox-recv does not rise: '${a1:-none}' -> '${a2:-none}'"
info "2302e00000.mailbox-recv: ${b1:-none} -> ${b2:-none}; DCP mailbox: $(awk '$NF ~ /^48ae08000\.mailbox/ {print $NF}' "$IRQ" | tr '\n' ' ')"

# 6. Hyprland (as the desktop user)
if [ "$hypr" = 1 ]; then
  j=$("$HYPRCTL" -j monitors 2>/dev/null)
  if ! printf '%s' "$j" | python3 -I -c 'import json, sys; json.load(sys.stdin)' 2>/dev/null; then
    bad "hyprctl -j monitors gave no JSON (run --hypr as the desktop user, in the session, not with sudo)"
  else
    printf '%s' "$j" | python3 -I -c '
import json, sys
for m in json.load(sys.stdin):
    print("info  hyprland: %s %dx%d@%.2f scale %s vrr %s format %s" % (m.get("name"), m.get("width", 0), m.get("height", 0),
          m.get("refreshRate", 0), m.get("scale"), m.get("vrr"), m.get("currentFormat")))'
    verdict=$(printf '%s' "$j" | EXPECT=$expect VRR=$vrr python3 -I -c '
import json, os, sys
ms = json.load(sys.stdin)
if os.environ["EXPECT"] == "published":
    m = [m for m in ms if str(m.get("name", "")).startswith("eDP-")]
    good = len(m) == 1 and m[0].get("width") == 3024 and m[0].get("height") in (1986, 1964) \
        and 119 <= m[0].get("refreshRate", 0) <= 121 and float(m[0].get("scale", 0)) == 2 and (os.environ["VRR"] == "on" or not m[0].get("vrr"))
    print("ok" if good else "bad", m[0]["name"] if m else "no eDP monitor")
else:
    m = [m for m in ms if m.get("name") == "Unknown-1"]
    print("ok" if len(m) == 1 and float(m[0].get("scale", 0)) == 2 else "bad", "Unknown-1" if m else "no Unknown-1 monitor")')
    case $verdict in
      ok*) ok "hyprland: ${verdict#ok } as expected (published: 3024x1986 or 1964, about 120 Hz, scale 2, vrr off unless --vrr on; else Unknown-1 at scale 2)" ;;
      *) bad "hyprland: ${verdict#bad }: not as expected for '$expect'" ;;
    esac
  fi
fi
echo "display-check ($expect): $nok ok, $nbad BAD"
[ "$nbad" = 0 ]
