#!/bin/bash
# OWNER-RUN, READ-ONLY USB-C plug test for both data ports. Issue #60. No root needed.
#
#   tests/hardware/k114s-usb-plug-test.sh            guided: left-front, then right
#   tests/hardware/k114s-usb-plug-test.sh --snapshot one report, no waiting (used by the tests)
#
# For each port it asks you to plug a USB 2/3 device (flash drive, keyboard or a USB Ethernet
# adapter; not a charger, not another computer) straight into that port, waits up to 60 s for the
# state to change, then prints: the verdict from tests/k114s-usb-check.sh, the Type-C partner and
# roles, every USB device with its speed (no serial numbers), and the kernel-log lines of the
# attach. Paste the whole output into issue #60. The left-back port is the debug port: skip it.
# Port names (port0/port1) differ between boots; the verdict lines carry the label, so go by those.
# Nothing is written. Hardware addresses in the log are masked.
set -u
here=$(cd "$(dirname "$0")" && pwd)
chk=$here/../k114s-usb-check.sh
SYS=${K114S_SYSFS:-/sys}
snap=0; [ "${1:-}" = "--snapshot" ] && snap=1

mask() { sed -E 's/\b[0-9a-f]{8,12}\.(usb|phy|iommu)\b/<addr>.\1/g; s/([0-9a-f]{2}:){5}[0-9a-f]{2}/<mac>/g; s/[Ss]erial[^,;]*/serial <hidden>/g'; }

devices() {
  local d n=0
  for d in "$SYS"/bus/usb/devices/[0-9]*-[0-9]*; do
    [ -d "$d" ] || continue
    case "$(basename "$d")" in *:*) continue ;; esac
    n=$((n + 1))
    printf '  %s vid:pid %s:%s speed %s Mb/s class %s product "%s"\n' "$(basename "$d")" \
      "$(cat "$d/idVendor" 2>/dev/null)" "$(cat "$d/idProduct" 2>/dev/null)" "$(cat "$d/speed" 2>/dev/null)" \
      "$(cat "$d/bDeviceClass" 2>/dev/null)" "$(cat "$d/product" 2>/dev/null)"
  done
  [ $n -eq 0 ] && echo "  (no USB device on any bus)"
}
typec() {
  local p
  for p in "$SYS"/class/typec/port*; do
    [ -d "$p" ] || continue
    printf '  %s partner=%s data=%s power=%s mode=%s orientation=%s\n' "${p##*/}" \
      "$(ls -d "$p"/${p##*/}-partner >/dev/null 2>&1 && echo yes || echo no)" \
      "$(tr '\n' ' ' < "$p/data_role" 2>/dev/null)" "$(tr '\n' ' ' < "$p/power_role" 2>/dev/null)" \
      "$(cat "$p/power_operation_mode" 2>/dev/null)" "$(cat "$p/orientation" 2>/dev/null || echo n/a)"
  done
}
report() {
  echo "--- $1 ($(date +%T))"
  bash "$chk" --no-journal 2>&1 | grep -E '^port|usb devices'
  echo "typec:"; typec
  echo "devices:"; devices
}
attach_log() {
  command -v journalctl >/dev/null || return 0
  echo "kernel log since $1 (Type-C, dwc3, xHCI, usb, PHY, tipd, spmi):"
  { journalctl -k --since "$1" --no-pager 2>/dev/null || sudo -n journalctl -k --since "$1" --no-pager 2>/dev/null; } \
    | grep -iE 'dwc3|xhci|usb |usb[0-9]|typec|tipd|sn201202x|apple-spmi|atc|phy|dart' | mask | tail -40 \
    | sed 's/^/  /'
  echo "  (end; an empty list means the drivers logged nothing)"
}

echo "# k114s USB plug test, kernel $(uname -r)"
report "before any plug"
[ $snap -eq 1 ] && { attach_log "5 minutes ago"; exit 0; }

for port in "left-front" "right"; do
  echo
  read -r -p ">> Plug a USB device into the $port port now, then press Enter. " _
  t0=$(date '+%Y-%m-%d %H:%M:%S')
  echo "watching 60 s for changes (Ctrl-C to stop early)..."
  bash "$chk" --no-journal --watch 60 2>&1 | grep -vE '^kernel' | mask
  report "$port plugged"
  attach_log "$t0"
  read -r -p ">> Unplug, turn the plug over, plug in again, then press Enter. " _
  report "$port flipped"
  read -r -p ">> Unplug the device from the $port port, then press Enter. " _
  report "$port unplugged"
done
echo
echo "# done. Paste everything above into issue #60 and say which devices you used."
