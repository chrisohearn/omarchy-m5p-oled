#!/bin/bash
# Read-only check of the USB4/Thunderbolt routers on the K114s, run AFTER booting the r3-usb4 tree
# with a USB4/Thunderbolt device or dock plugged into a USB-C port (docs/r3-usb4.md). Writes nothing.
#   bash tests/hardware/k114s-usb4-check.sh
set -u
echo "== kernel";                 uname -r
echo "== routers bound";          ls /sys/bus/platform/drivers/thunderbolt-apple-acio/ 2>&1 | grep -E 'acio|bind' || echo "none bound"
echo "== NHI bound (appears only after a USB4 link is negotiated)"
ls /sys/bus/platform/drivers/thunderbolt-apple-nhi/ 2>&1 | grep -E 'nhi' || echo "no NHI yet"
echo "== thunderbolt devices";    ls /sys/bus/thunderbolt/devices/ 2>&1
for d in /sys/bus/thunderbolt/devices/*; do
  [ -d "$d" ] || continue
  printf '%s: vendor=%s device=%s authorized=%s rx=%s tx=%s\n' "$(basename "$d")" "$(cat "$d/vendor_name" 2>/dev/null)" \
    "$(cat "$d/device_name" 2>/dev/null)" "$(cat "$d/authorized" 2>/dev/null)" "$(cat "$d/rx_speed" 2>/dev/null)" "$(cat "$d/tx_speed" 2>/dev/null)"
done
echo "== typec ports";            for p in /sys/class/typec/port?; do echo "$p: $(cat "$p/data_role" 2>/dev/null) $(cat "$p/power_role" 2>/dev/null)"; ls "$p" | grep -E 'partner|usb' | tr '\n' ' '; echo; done
echo "== kernel log (thunderbolt, acio, nhi, usb4)"
sudo -n dmesg 2>/dev/null | grep -i -E 'thunderbolt|acio|nhi|usb4|pcie-tunnel' | tail -40
echo "== failed units";           systemctl --failed --no-legend
