#!/bin/bash
# Attended check for a K114s camera trial. The default reports device state.
# --capture saves one local frame from the Apple ISP once the activity light is described, or the tree opts in to
# apple,camera-light-undescribed (the K114s: on-screen indicator only).
set -uo pipefail

capture=0
case ${1:-} in
  '') ;;
  --capture) capture=1 ;;
  *) echo "usage: k114s-camera-check.sh [--capture]" >&2; exit 2 ;;
esac
if (( $# > 1 )); then
  echo "usage: k114s-camera-check.sh [--capture]" >&2
  exit 2
fi

failed=0
ok() { printf 'ok   %s\n' "$*"; }
bad() { printf 'BAD  %s\n' "$*"; failed=1; }
info() { printf 'info %s\n' "$*"; }

dt=/proc/device-tree
if IFS= read -r -d '' compatible 2>/dev/null < "$dt/compatible" &&
  [[ $compatible == apple,k114s ]]; then
  ok "K114s device tree"
else
  bad "expected a K114s device tree"
fi

isp="$dt/soc/isp@580000000"
if [[ -d $isp ]]; then
  status=$(tr -d '\0' 2>/dev/null < "$isp/status" || true)
  if [[ $status == okay ]]; then
    ok "ISP node enabled by the loader"
  else
    bad "ISP node status: ${status:-absent}"
  fi
  platform_id=$(od -An -tx1 -v "$isp/apple,platform-id" 2>/dev/null | tr -d ' \n' || true)
  if [[ $platform_id == 000000ba ]]; then
    ok "K114s ISP platform ID 0xba"
  else
    bad "ISP platform ID: ${platform_id:-absent} (expected 0xba)"
  fi
  if [[ -e $isp/apple,camera-light-undescribed ]] && [[ -s $isp/apple,cil-config ]]; then
    # The driver lets the opt-in win and drives no light, so a described light here would be misleading.
    bad "the tree both describes a camera light and opts in to apple,camera-light-undescribed: the driver drives no light"
  elif [[ -s $isp/apple,cil-config ]] &&
    grep -zFxq cil "$isp/reg-names" 2>/dev/null; then
    ok "physical camera activity light described"
  elif [[ -e $isp/apple,camera-light-undescribed ]]; then
    # The owner's choice (2026-11-24): no light is described on the K114s; the r3e driver (patches/linux/r3e/0075)
    # runs the camera without light control and the display's best-effort indicator (#2561) is the only signal.
    info "no camera light described: the tree opts in to apple,camera-light-undescribed (on-screen indicator only)"
  else
    bad "physical camera activity light description is missing (cil and apple,cil-config), and the tree does not opt in to apple,camera-light-undescribed"
  fi
else
  bad "ISP node absent"
fi

# AVD also creates video and media nodes. Only the ISP driver's capture node counts here.
devices=()
for node in /sys/class/video4linux/video[0-9]*; do
  [[ -e $node ]] || continue
  driver=$(readlink -- "$node/device/driver") || continue
  device="/dev/${node##*/}"
  if [[ ${driver##*/} == apple-isp && -c $device ]]; then
    devices+=("$device")
  fi
done
case ${#devices[@]} in
  1) ok "Apple ISP capture device: ${devices[0]}" ;;
  0) bad "Apple ISP capture device absent" ;;
  *) bad "expected one Apple ISP capture device, found ${#devices[@]}" ;;
esac

info "recent ISP kernel messages (if readable)"
dmesg 2>/dev/null | grep -Ei 'apple[-_]isp|isp0|imx958' | tail -25 || true
(( failed == 0 )) || exit 1
(( capture == 1 )) || exit 0

if ! command -v ffmpeg >/dev/null; then
  bad "ffmpeg required for capture"
  exit 1
fi
umask 077
if ! frames=$(mktemp -d); then
  bad "could not create a private frame directory"
  exit 1
fi
trap 'rm -f -- "$frames/frame.png"; rmdir -- "$frames"' EXIT
trap 'exit 1' HUP INT TERM
if ! timeout 20s ffmpeg -nostdin -hide_banner -loglevel error -f v4l2 \
  -i "${devices[0]}" -frames:v 1 "$frames/frame.png" || [[ ! -s $frames/frame.png ]]; then
  bad "no frame saved from ${devices[0]}"
  exit 1
fi
trap - EXIT HUP INT TERM
ok "one local frame saved to $frames/frame.png"
info "owner checks the physical light during capture and the framing in the saved image"
