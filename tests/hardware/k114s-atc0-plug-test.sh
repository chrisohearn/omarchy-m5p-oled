#!/bin/bash
# Owner test for the left-back USB-C port (ATC0), issue #72. Read-only, no root.
#
#   tests/hardware/k114s-atc0-plug-test.sh [SECONDS]      default 90
#
# Run it only after a trial boot of the draft tree t6050-k114s-r3-usb-atc0 (docs/r3-usb-atc0.md,
# "What has to change first"). It checks that the left-back port is in the running tree, then
# watches all USB-C ports for SECONDS while you plug a USB device (a flash drive, a keyboard or a
# USB Ethernet adapter; not a charger, not another computer) into the LEFT-BACK port, the one
# nearest the hinge on the left side. Unplug, turn the plug over and plug in again. Paste the
# output into issue #72. It prints no serial numbers and no hardware addresses.
set -u
sys=${K114S_SYSFS:-/sys}
dur=${1:-90}
here=$(cd "$(dirname "$0")" && pwd)

found=0
for d in "$sys"/bus/spmi/devices/*; do
  [ -r "$d/of_node/connector/label" ] || continue
  [ "$(tr -d '\0' < "$d/of_node/connector/label")" = "USB-C Left-back" ] && found=1
done
if [ $found = 0 ]; then
  echo "NOT-BOOTED: no 'USB-C Left-back' connector in this tree. The running device tree is not the ATC0 draft."
  echo "Nothing to test. See docs/r3-usb-atc0.md for the trial boot."
  exit 2
fi
echo "ATC0 tree is running. Plug a device into the LEFT-BACK port now ($dur s)."
echo "uname: $(uname -r)"
exec "$here/../k114s-usb-check.sh" --watch "$dur"
