#!/bin/bash
# OWNER-RUN, READ-ONLY. Reports what Bluetooth looks like on the K114s after pairing a device by hand
# (issue #59). It pairs, connects, plays and changes nothing. Pair first, yourself:
#   bluetoothctl   then:  power on, agent on, scan on, pair <addr>, trust <addr>, connect <addr>
# Then run:  bash tests/hardware/k114s-bluetooth-check.sh
# Overlaps the Bluetooth sections of k114s-r3a-audio-check.sh (section 4), which a full audio run covers too.
# Device addresses are replaced by XX:XX:XX:XX:XX:XX and device names are dropped, so the output can be
# pasted into the issue. Lines: ok / BAD / info / ASK (needs your hands or ears; owner-observed).
exec > >(sed -u -E 's/([0-9A-Fa-f]{2}[:_-]){5}[0-9A-Fa-f]{2}/XX:XX:XX:XX:XX:XX/g') 2>&1
ok() { echo "ok      $*"; }; bad() { echo "BAD     $*"; nbad=$((nbad+1)); }; info() { echo "info    $*"; }; ask() { echo "ASK     $*"; }
nbad=0
bt() { timeout 10 bluetoothctl "$@"; }   # bluetoothctl waits forever when bluetoothd is down
have() { command -v "$1" >/dev/null 2>&1; }
echo "== K114s Bluetooth check, $(date -u +%Y-%m-%dT%H:%M:%SZ), kernel $(uname -r)"
case $(uname -r) in *k114s-r3[ab]-ARCH) ok "r3a or r3b kernel" ;; *) bad "not an r3a or r3b kernel: RFCOMM is only in those" ;; esac
drv=$(basename "$(readlink /sys/class/bluetooth/hci0/device/driver 2>/dev/null)" 2>/dev/null)
[ "$drv" = btcentauri_t6050 ] && ok "hci0 bound to btcentauri_t6050" || bad "hci0 driver is '${drv:-none}'"
grep -q '^rfcomm ' /proc/modules && ok "rfcomm loaded" || info "rfcomm not loaded yet (bluetoothd autoloads it through the bt-proto-3 alias)"
if have journalctl && journalctl -b -u bluetooth --no-pager -n 1 >/dev/null 2>&1; then
  if journalctl -b -u bluetooth --no-pager 2>/dev/null | grep -qi 'RFCOMM server failed\|Protocol not supported'; then
    bad "bluetoothd reports an RFCOMM failure this boot"
  else ok "no RFCOMM failure in bluetoothd's journal"; fi
else info "bluetoothd journal not readable here (sudo or the systemd-journal group)"; fi
have bluetoothctl || { bad "bluetoothctl missing"; exit 1; }
bt show | grep -q 'Handsfree Audio Gateway' && ok "Handsfree Audio Gateway UUID present" || bad "no HFP gateway UUID"
n=$(bt devices Paired | wc -l); info "paired devices: $n"
if [ "$n" -eq 0 ]; then ask "Nothing is paired. Pair a device by hand (see the top of this script), then run again."; echo "== done: $nbad BAD line(s)"; [ "$nbad" = 0 ]; exit; fi
i=0
for a in $(bt devices Paired | awk '{print $2}'); do
  i=$((i+1)); echo "-- device $i $a"
  bt info "$a" | grep -E 'Paired|Trusted|Connected|Icon|UUID' | sed -E 's/^\s+//'
done
if have pactl; then
  echo "-- PipeWire bluez cards: profiles and active profile"
  pactl list cards 2>/dev/null | awk '/Name: bluez_card/ {p=1} /^Card #/ {p=0} p && /(a2dp|headset-head-unit|handsfree|Active Profile)/ {print}'
fi
ask "Music: play audio over A2DP for 60 s. Any dropouts, stutter or crackle?"
ask "Keyboard or mouse: does it type or move, and reconnect after power-cycling the device?"
ask "Hands-free: switch the card to headset-head-unit yourself. Is the profile listed, and does call audio or the headset microphone work? Expected to fail: the btcentauri driver has no SCO yet (docs/r3-config.md)."
echo "== done: $nbad BAD line(s)"; [ "$nbad" = 0 ]
