#!/bin/bash
# Bluetooth audio check for the K114s on the r3a kernel (issue #41). READ-ONLY: it pairs nothing, changes no
# setting, plays nothing, needs no root and never touches the speakers or the jack card, so it also works on
# the GPU-tree Stage 2 where the sound tree is absent (k114s-r3a-audio-check.sh stops there on its speaker
# tripwires and so never reaches its attended Bluetooth part).
#
#   bash tests/hardware/k114s-bt-audio-check.sh [--listen] [--no-save]
#     (no flags)  the read-only report
#     --listen    after you pair a headset yourself (runbook: docs/r3-bluetooth-audio.md), lists the card profiles
#                 and asks the A2DP, Wi-Fi coexistence and hands-free questions (prompts on the terminal)
#     --no-save   do not write the report to ~/k114s-bt-check-DATE.txt
# Device addresses (colon, underscore and dash forms) are replaced by XX:XX:XX:XX:XX:XX and a device's own name is
# dropped, so the report can be pasted into the issue. Lines: ok / BAD / info / ASK (needs your ears) / unknown.
listen=0; save=1
for a in "$@"; do
  case $a in --listen) listen=1 ;; --no-save) save=0 ;;
    *) echo "usage: k114s-bt-audio-check.sh [--listen] [--no-save]" >&2; exit 2 ;; esac
done
if [ $save = 1 ]; then
  out=$HOME/k114s-bt-check-$(date +%Y%m%d-%H%M%S).txt
  exec > >(sed -u -E 's/([0-9A-Fa-f]{2}[:_-]){5}[0-9A-Fa-f]{2}/XX:XX:XX:XX:XX:XX/g' | tee "$out") 2>&1
else
  exec > >(sed -u -E 's/([0-9A-Fa-f]{2}[:_-]){5}[0-9A-Fa-f]{2}/XX:XX:XX:XX:XX:XX/g') 2>&1
fi
nbad=0; ok() { echo "ok      $*"; }; bad() { echo "BAD     $*"; nbad=$((nbad+1)); }; info() { echo "info    $*"; }
unk() { echo "unknown $*"; }; ask() { echo "ASK     $*"; }; have() { command -v "$1" >/dev/null 2>&1; }
pause() { printf '\n>>> %s\n    Press Enter when done (Ctrl-C stops the script; nothing needs undoing).\n' "$1" >/dev/tty; read -r _ </dev/tty; }
cards() { pactl list cards 2>/dev/null | awk '/^Card/ {c=0} /bluez/ {c=1} c && /a2dp|headset-head-unit|handsfree|Active Profile/' | sed 's/^[[:space:]]*/info    profile: /' | head -16; }

echo "== K114s Bluetooth audio check, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
rel=$(uname -r)
case $rel in *k114s-r3[ab]-ARCH) ok "running kernel $rel" ;; *) bad "kernel is $rel, not r3a or r3b: RFCOMM (hands-free) is not expected" ;; esac
[ -d /sys/class/bluetooth/hci0 ] && ok "hci0 present" || bad "no hci0"
drv=$(basename "$(readlink /sys/class/bluetooth/hci0/device/driver 2>/dev/null)" 2>/dev/null)
[ "$drv" = btcentauri_t6050 ] && ok "hci0 is bound to btcentauri_t6050" || bad "hci0 driver is ${drv:-none}, expected btcentauri_t6050"
rfkill list bluetooth 2>/dev/null | grep -q 'blocked: yes' && bad "Bluetooth is blocked in rfkill" || ok "Bluetooth is not blocked in rfkill"
grep -q "^rfcomm " /proc/modules && ok "module rfcomm loaded" || bad "module rfcomm not loaded (bluetoothd loads it at start; hands-free needs it)"
bt() { timeout 5 bluetoothctl "$@"; }  # bounded: bluetoothctl waits forever when bluetoothd is down
if have bluetoothctl && ! systemctl is-active --quiet bluetooth 2>/dev/null; then bad "bluetoothd not running (systemctl is-active bluetooth)"
elif have bluetoothctl; then
  show=$(bt show 2>/dev/null)
  grep -q 'Powered: yes' <<<"$show" && ok "controller powered" || bad "controller not powered"
  for pair in "0000110b:A2DP sink" "0000110a:A2DP source" "0000111e:Hands-Free (HFP)" "0000111f:Hands-Free gateway (HFP AG)" "0000110e:AVRCP"; do
    grep -qi "UUID:.*(${pair%%:*}" <<<"$show" && ok "bluez advertises ${pair#*:}" || bad "bluez does not advertise ${pair#*:}"
  done
  info "paired devices: $(bt devices Paired 2>/dev/null | wc -l)"
else unk "bluetoothctl not installed"; fi
if journalctl -b -u bluetooth --no-pager -n 1 >/dev/null 2>&1; then
  journalctl -b -u bluetooth --no-pager 2>/dev/null | grep -qiE 'RFCOMM server failed|Protocol not supported' \
    && bad "bluetoothd reports an RFCOMM failure this boot" || ok "no RFCOMM failure in this boot's bluetoothd journal"
else unk "bluetoothd journal not readable (add yourself to systemd-journal)"; fi
if have wpctl; then
  systemctl --user is-active wireplumber >/dev/null 2>&1 && ok "wireplumber running" || bad "wireplumber not running"
fi
cards
iw=$(have iw && iw dev 2>/dev/null | awk '/Interface/ {print $2; exit}')
[ -n "$iw" ] && info "Wi-Fi link: $(iw dev "$iw" link 2>/dev/null | grep -E 'signal|tx bitrate|rx bitrate' | tr -s ' \t' ' ' | tr '\n' ';')"

if [ $listen = 1 ]; then
  echo "== attended (owner-observed)"
  [ "$(bt devices Paired 2>/dev/null | wc -l)" = 0 ] && \
    pause "No device is paired. Put the headset in pairing mode; in another terminal: bluetoothctl, then scan on, pair <address>, trust <address>, connect <address>. This script never pairs."
  cards
  ask "Play music over Bluetooth (A2DP) for 60 s. Any dropouts, stutter or crackle?"
  gw=$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}')
  [ -n "$gw" ] && { pause "A 20 s ping to the router runs now; run a download too and listen for dropouts."; ping -c 20 -i 1 "$gw" 2>&1 | tail -2 | sed 's/^/info    ping: /'; }
  ask "Hands-free: run pactl set-card-profile <card> headset-head-unit, then record or call. Does the headset microphone work? Is the profile listed at all?"
fi
echo "== done: $nbad BAD line(s). Paste this into issue #41; answer the ASK lines as owner-observed."
[ "$nbad" = 0 ]
