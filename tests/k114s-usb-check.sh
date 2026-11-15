#!/bin/bash
# State of the USB-C host ports, read from sysfs and the kernel log. No root, read-only.
#
#   tests/k114s-usb-check.sh              one report
#   tests/k114s-usb-check.sh --watch 60   report, then print every change for 60 seconds
#                                         (start it, then plug a device in)
#
# On Apple Silicon the USB host controller of a Type-C port (dwc3-apple) is started only when the
# port's controller reports an attached device, and stopped again when the cable goes. An idle
# port therefore has no xHCI and no root hub, and /sys/bus/usb/devices is empty with nothing
# plugged in. This script tells that idle state from a fault.
#
# Per port it prints one verdict:
#   NOT-PROBED   a driver in the chain (port controller, PHY, dwc3-apple) is not bound
#   IDLE         everything is bound, nothing is attached: ready, and no xHCI by design
#   NOT-A-HOST   something is attached but this Mac is the USB device on the cable (a charger,
#                another computer): T6050 ports are host-only, the port stays off by design
#   NO-HOST      a device is attached, the Mac is the host, and no xHCI came up: a fault
#   HOST-EMPTY   xHCI and root hubs are up, no device enumerated (a fault for a data device)
#   OK           devices enumerated; each is listed with its speed
#
# It prints no serial numbers and no hardware addresses, so the output can go into a report.
# Exit status: 0 no fault seen, 1 a port is NOT-PROBED, NO-HOST or HOST-EMPTY, 2 no ports.
set -u
SYS=${K114S_SYSFS:-/sys}
watch=0
journal=1
while [ $# -gt 0 ]; do
  case "$1" in
    --watch) watch=${2:-60}; shift ;;
    --no-journal) journal=0 ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 64 ;;
  esac
  shift
done

rd() { [ -r "$1" ] && tr -d '\0' < "$1" 2>/dev/null | head -c 200 | tr '\n' ' ' | sed 's/ *$//'; }
drv() { [ -e "$1/driver" ] && basename "$(readlink -f "$1/driver")" || echo "-"; }
cur() { rd "$1" | sed -n 's/.*\[\([^]]*\)\].*/\1/p'; }   # "host [device]" -> device

# -> lines "busnum-devpath speed vid:pid product" for every device below one xHCI, root hubs excluded
usb_devices() {
  local hc=$1 d
  for d in "$hc"/usb*/[0-9]*-[0-9]* "$hc"/usb*/[0-9]*-[0-9]*/[0-9]*-[0-9.]* \
           "$hc"/usb*/[0-9]*-[0-9]*/[0-9]*-[0-9.]*/[0-9]*-[0-9.]*; do
    [ -r "$d/idVendor" ] || continue
    echo "$(basename "$d") $(rd "$d/speed")Mb/s $(rd "$d/idVendor"):$(rd "$d/idProduct") $(rd "$d/product")"
  done | sort -u
}

# state of one Type-C port as one line: verdict|detail
port_state() {
  local p=$1 name ctl partner drole prole orient usbdev phydev s hc roots devs n
  name=$(basename "$p")
  ctl=$(readlink -f "$p/device")
  partner=no; [ -d "$p/$name-partner" ] && partner=yes
  drole=$(cur "$p/data_role"); prole=$(cur "$p/power_role"); orient=$(rd "$p/orientation")
  usbdev=; phydev=
  for s in "$p"/supplier:platform:*; do
    [ -e "$s" ] || continue
    case "$s" in *.usb) usbdev=${s##*:} ;; *.phy) phydev=${s##*:} ;; esac
  done
  local label; label=$(rd "$ctl/of_node/connector/label")
  local detail="${label:+\"$label\", }controller $(basename "$ctl") [$(drv "$ctl")]"
  detail="$detail, phy ${phydev:-none} [$( [ -n "$phydev" ] && drv "$SYS/bus/platform/devices/$phydev" || echo - )]"
  detail="$detail, usb ${usbdev:-none} [$( [ -n "$usbdev" ] && drv "$SYS/bus/platform/devices/$usbdev" || echo - )]"
  detail="$detail, partner $partner, data ${drole:-?}, power ${prole:-?}${orient:+, orientation $orient}"
  if [ "$(drv "$ctl")" = "-" ] || [ -z "$usbdev" ] || [ -z "$phydev" ] ||
     [ "$(drv "$SYS/bus/platform/devices/$usbdev")" = "-" ] ||
     [ "$(drv "$SYS/bus/platform/devices/$phydev")" = "-" ]; then
    echo "NOT-PROBED|$detail"; return
  fi
  hc=$(ls -d "$SYS/bus/platform/devices/$usbdev"/xhci-hcd.* 2>/dev/null | head -1)
  if [ -z "$hc" ]; then
    if [ "$partner" = no ]; then echo "IDLE|$detail"
    elif [ "$drole" = device ]; then echo "NOT-A-HOST|$detail"
    else echo "NO-HOST|$detail"; fi
    return
  fi
  roots=$(ls -d "$hc"/usb* 2>/dev/null | wc -l)
  devs=$(usb_devices "$hc")
  n=$(printf '%s' "$devs" | grep -c . || true)
  detail="$detail, xHCI $(basename "$hc") with $roots root hub(s), $n device(s)"
  if [ "$n" -eq 0 ]; then echo "HOST-EMPTY|$detail"
  else echo "OK|$detail$(printf '%s\n' "$devs" | sed 's/^/\n      /' | tr -d '\r')"; fi
}

report() {
  local p st rc=0 any=0
  for p in "$SYS"/class/typec/port[0-9] "$SYS"/class/typec/port[0-9][0-9]; do
    [ -d "$p" ] || continue
    any=1
    st=$(port_state "$p")
    printf '%s %-11s %s\n' "$(basename "$p")" "${st%%|*}" "${st#*|}"
    case "${st%%|*}" in NOT-PROBED|NO-HOST|HOST-EMPTY) rc=1 ;; esac
  done
  if [ "$any" = 0 ]; then
    echo "no Type-C ports registered: the tree describes none, or the port controllers did not probe"
    return 2
  fi
  return $rc
}

echo "kernel: $(uname -r 2>/dev/null) $(uname -v 2>/dev/null | grep -o 'K114S-R[0-9A-Za-z]*')"
[ -r /proc/device-tree/compatible ] && echo "machine: $(tr '\0' ' ' < /proc/device-tree/compatible)"
echo "usb devices on any bus: $(ls "$SYS/bus/usb/devices" 2>/dev/null | wc -l)"
report; rc=$?

if [ "$journal" = 1 ] && command -v journalctl >/dev/null 2>&1; then
  echo "kernel log, this boot (Type-C, PHY, dwc3, xHCI, USB devices):"
  journalctl -b -k --no-pager -o short-monotonic 2>/dev/null |
    grep -E 'sn201202x|tps6598x|apple-spmi|dwc3|xhci|apple-t6050-dp-phy|usb [0-9]+-[0-9.]+|usb usb[0-9]+|hub [0-9]+-' |
    grep -v -E 'registered new (interface|device) driver|SerialNumber' |
    sed -E 's/([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/xx:xx:xx:xx:xx:xx/g' | cut -c1-220 | tail -40 | sed 's/^/  /' |
    grep . || echo "  (no lines: none of these drivers has logged anything, which is what an idle port looks like)"
fi

if [ "$watch" -gt 0 ]; then
  echo "watching for $watch s: plug a device in now"
  last=$(report 2>&1); end=$((SECONDS + watch))
  while [ $SECONDS -lt $end ]; do
    sleep 0.5
    now=$(report 2>&1); r=$?
    if [ "$now" != "$last" ]; then
      echo "--- +$((SECONDS - (end - watch))) s"; echo "$now"; last=$now; rc=$r
    fi
  done
fi
exit $rc
