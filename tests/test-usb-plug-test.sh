#!/bin/bash
# Software test of tests/hardware/k114s-usb-plug-test.sh --snapshot against a made-up sysfs tree.
set -u
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
r=$tmp/sys; fail=0
mkdir -p "$r/class/typec/port0" "$r/bus/usb/devices/1-1" "$r/bus/usb/devices/1-0:1.0"
echo "host [device]" > "$r/class/typec/port0/data_role"
for f in "idVendor 0bda" "idProduct 8156" "speed 5000" "bDeviceClass 00" "product LAN" "serial SECRETSERIAL0001"; do
  set -- $f; echo "$2" > "$r/bus/usb/devices/1-1/$1"
done
out=$(K114S_SYSFS=$r bash "$here/hardware/k114s-usb-plug-test.sh" --snapshot 2>&1); rc=$?
[ $rc -eq 0 ] && echo "ok   exit 0" || { echo "FAIL exit $rc"; fail=1; }
echo "$out" | grep -q -E '1-1 vid:pid 0bda:8156 speed 5000' && echo "ok   device listed with speed" || { echo "FAIL device line"; fail=1; }
echo "$out" | grep -q '1-0:1.0' && { echo "FAIL interface listed"; fail=1; } || echo "ok   no interface node"
echo "$out" | grep -q SECRETSERIAL && { echo "FAIL serial printed"; fail=1; } || echo "ok   no serial"
exit $fail
