#!/bin/bash
# Attended check for a K114s camera trial. The default reports device state.
# --capture saves one local frame from the Apple ISP after the activity light is described.
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
  if [[ -s $isp/apple,cil-config ]] &&
    grep -zFxq cil "$isp/reg-names" 2>/dev/null; then
    ok "physical camera activity light described"
  else
    bad "physical camera activity light description is missing (cil and apple,cil-config)"
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
frames=$(mktemp -d) || exit 1
if ! timeout 20s ffmpeg -nostdin -hide_banner -loglevel error -f v4l2 \
  -i "${devices[0]}" -frames:v 1 "$frames/frame.png" || [[ ! -s $frames/frame.png ]]; then
  bad "no frame saved from ${devices[0]}"
  exit 1
fi
ok "one local frame saved to $frames/frame.png"
info "owner checks the physical light during capture and the framing in the saved image"
