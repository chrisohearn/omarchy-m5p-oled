#!/bin/bash
# Software test of tests/k114s-usb-check.sh against made-up sysfs trees. No hardware involved.
set -u
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

# mkport ROOT N CTL USB PHY [bound-ctl bound-usb bound-phy]
mkport() {
  local r=$1 n=$2 ctl=$3 usb=$4 phy=$5 bc=${6:-1} bu=${7:-1} bp=${8:-1}
  mkdir -p "$r/devices/spmi/$ctl/typec/port$n" "$r/class/typec" "$r/bus/platform/devices/$usb" \
           "$r/bus/platform/devices/$phy" "$r/drivers/sn201202x" "$r/drivers/dwc3-apple" \
           "$r/drivers/apple-t6050-dp-phy" "$r/bus/usb/devices" "$r/devices/spmi/$ctl/of_node/connector"
  printf 'USB-C Test %s\0' "$n" > "$r/devices/spmi/$ctl/of_node/connector/label"
  ln -sfn "../../devices/spmi/$ctl/typec/port$n" "$r/class/typec/port$n"
  ln -sfn "../.." "$r/devices/spmi/$ctl/typec/port$n/device"
  [ "$bc" = 1 ] && ln -sfn "../../../drivers/sn201202x" "$r/devices/spmi/$ctl/driver"
  [ "$bu" = 1 ] && ln -sfn "../../../../drivers/dwc3-apple" "$r/bus/platform/devices/$usb/driver"
  [ "$bp" = 1 ] && ln -sfn "../../../../drivers/apple-t6050-dp-phy" "$r/bus/platform/devices/$phy/driver"
  : > "$r/devices/spmi/$ctl/typec/port$n/supplier:platform:$usb"
  : > "$r/devices/spmi/$ctl/typec/port$n/supplier:platform:$phy"
  echo "host [device]" > "$r/devices/spmi/$ctl/typec/port$n/data_role"
  echo "source [sink]" > "$r/devices/spmi/$ctl/typec/port$n/power_role"
}
partner() { mkdir -p "$1/devices/spmi/$3/typec/port$2/port$2-partner"; echo "$4" > "$1/devices/spmi/$3/typec/port$2/data_role"; }
xhci() { mkdir -p "$1/bus/platform/devices/$2/xhci-hcd.1.auto/usb1" "$1/bus/platform/devices/$2/xhci-hcd.1.auto/usb2"; }
device() {
  local d="$1/bus/platform/devices/$2/xhci-hcd.1.auto/usb1/1-1"; mkdir -p "$d"
  echo 0bda > "$d/idVendor"; echo 8156 > "$d/idProduct"; echo 480 > "$d/speed"
  echo "USB 10/100/1G/2.5G LAN" > "$d/product"; echo "SECRETSERIAL0001" > "$d/serial"
}
run() { K114S_SYSFS=$1 bash "$here/k114s-usb-check.sh" --no-journal; }
expect() { # NAME ROOT WANT-RC PATTERN...
  local name=$1 root=$2 rc=$3 out got; shift 3
  out=$(run "$root"); got=$?
  [ "$got" = "$rc" ] || { bad "$name: exit $got, want $rc"; echo "$out"; return; }
  for pat in "$@"; do echo "$out" | grep -q -E "$pat" || { bad "$name: no line matches /$pat/"; echo "$out"; return; }; done
  echo "$out" | grep -q SECRETSERIAL && { bad "$name: a serial number was printed"; return; }
  ok "$name"
}

r=$tmp/idle; mkport "$r" 0 1-0a 2aa280000.usb 2ab000000.phy; mkport "$r" 1 2-0c 382280000.usb 383000000.phy
expect "two idle ports" "$r" 0 '^port0 IDLE .*"USB-C Test 0", controller 1-0a \[sn201202x\]' '^port1 IDLE ' 'partner no'

r=$tmp/charger; mkport "$r" 0 1-0a 2aa280000.usb 2ab000000.phy; partner "$r" 0 1-0a "host [device]"
expect "charger or other host attached" "$r" 0 '^port0 NOT-A-HOST '

r=$tmp/nohost; mkport "$r" 0 1-0a 2aa280000.usb 2ab000000.phy; partner "$r" 0 1-0a "[host] device"
expect "device attached, no xHCI" "$r" 1 '^port0 NO-HOST .*data host'

r=$tmp/empty; mkport "$r" 0 1-0a 2aa280000.usb 2ab000000.phy; partner "$r" 0 1-0a "[host] device"; xhci "$r" 2aa280000.usb
expect "xHCI up, nothing enumerated" "$r" 1 '^port0 HOST-EMPTY .*2 root hub\(s\), 0 device'

r=$tmp/ok; mkport "$r" 0 1-0a 2aa280000.usb 2ab000000.phy; mkport "$r" 1 2-0c 382280000.usb 383000000.phy
partner "$r" 0 1-0a "[host] device"; xhci "$r" 2aa280000.usb; device "$r" 2aa280000.usb
expect "device enumerated" "$r" 0 '^port0 OK .*1 device' '1-1 480Mb/s 0bda:8156 USB 10/100/1G/2.5G LAN' '^port1 IDLE '

r=$tmp/unbound; mkport "$r" 0 1-0a 2aa280000.usb 2ab000000.phy 1 0 1
expect "dwc3-apple not bound" "$r" 1 '^port0 NOT-PROBED .*usb 2aa280000.usb \[-\]'

r=$tmp/phyunbound; mkport "$r" 0 1-0a 2aa280000.usb 2ab000000.phy 1 1 0
expect "PHY not bound" "$r" 1 '^port0 NOT-PROBED .*phy 2ab000000.phy \[-\]'

r=$tmp/none; mkdir -p "$r/class/typec" "$r/bus/usb/devices"
expect "no ports" "$r" 2 'no Type-C ports registered'

[ $fail = 0 ] && echo "test-usb-check: all passed"
exit $fail
