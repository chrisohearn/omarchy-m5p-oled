#!/bin/bash
# OWNER-RUN, ATTENDED. After a one-boot trial of a tree that includes dts/t6050-k114s-isp.dtsi (macro
# K114S_R3_ISP) on a loader with patches/aura/0004, this reports whether the camera came up. READ-ONLY:
# changes no setting, loads no module, opens no window, and captures nothing unless you pass --capture.
# Needs no root, but kernel messages and the loader log read better with it (it says so).
#
#   bash tests/hardware/k114s-camera-check.sh [--capture]
#     (no flags)  the report only
#     --capture   runs libcamera's `cam` once, one frame, into a temporary folder, and prints its name
#                 so you can open the image yourself ("seeing a frame" is owner-observed). The camera
#                 light/indicator is not described on this board.
#
# Lines: ok / BAD (a failed expectation) / info / ASK (needs your eyes) / unknown.
# Serial numbers and addresses of the network are never printed.
capture=0
for a in "$@"; do
  case $a in --capture) capture=1 ;; *) echo "usage: k114s-camera-check.sh [--capture]" >&2; exit 2 ;; esac
done
ok() { echo "ok   $*"; }; bad() { echo "BAD  $*"; }; info() { echo "info $*"; }; ask() { echo "ASK  $*"; }
dt=/proc/device-tree
[ "$(tr -d '\0' < $dt/compatible 2>/dev/null | head -c 11)" = "apple,k114s" ] && ok "this is a K114s tree" || bad "device tree is not the K114s"
isp=$(ls -d $dt/soc/isp@* 2>/dev/null | head -1)
if [ -n "$isp" ]; then
  st=$(tr -d '\0' < "$isp/status" 2>/dev/null)
  [ "$st" = okay ] && ok "isp node status: okay (the loader handed the camera over)" || bad "isp node status: ${st:-none} (loader refused or the tree lacks K114S_R3_ISP; read the loader log below)"
  p=$(od -An -tx1 -v "$isp/apple,platform-id" 2>/dev/null | tr -d ' \n'); info "apple,platform-id (expected 000000ba): ${p:-absent}"
  info "memory-region-names: $(tr '\0' ' ' < "$isp/memory-region-names" 2>/dev/null)"
else
  bad "no isp node in the live device tree"
fi
lsmod | grep -q '^apple_isp' && ok "apple_isp module loaded" || info "apple_isp not loaded (modprobe is not run by this script)"
ls /dev/video* /dev/media* >/dev/null 2>&1 && ok "video or media nodes: $(ls /dev/video* /dev/media* 2>/dev/null | tr '\n' ' ')" || bad "no /dev/video* or /dev/media*"
echo "--- kernel messages (isp, camera); root shows more"
(dmesg 2>/dev/null || sudo -n dmesg 2>/dev/null) | grep -i -E "apple-isp|apple_isp|isp0|camera|imx958" | tail -25 || true
echo "--- loader log (camera lines); root only"
for m in /dev/mtd1ro /dev/mtd0ro; do sudo -n strings "$m" 2>/dev/null | grep -i -E "\bISP\b|isp0|camera" | tail -8; done
if command -v cam >/dev/null; then
  echo "--- libcamera"; cam -l 2>&1 | head -8
  if [ $capture = 1 ]; then
    d=$(mktemp -d); (cd "$d" && cam -c1 --capture=1 --file=frame- 2>&1 | tail -5); info "frame folder: $d"
    ask "open the file in $d and say what you see (this is the owner-observed evidence)"
  fi
else
  info "libcamera 'cam' not installed: only the kernel side was checked"
fi
ask "if the screen froze, the Mac rebooted or the keyboard died during the boot, say so: a coprocessor hang needs a forced power-off"
