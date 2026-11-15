#!/bin/bash
# Read-only report of what the r3a kernel changed, for the first boot of linux-k114s. No root needed
# (a few lines are better with root and say so). Changes nothing. Prints "ok", "BAD" or "info" lines.
#   tests/hardware/k114s-r3a-check.sh [--expect-tree r1|r3a]
want=r1; [ "${1:-}" = --expect-tree ] && want=${2:-r1}
ok() { echo "ok    $*"; }; bad() { echo "BAD   $*"; }; info() { echo "info  $*"; }
rel=$(uname -r)
case $rel in *k114s-r3a-ARCH) ok "running kernel $rel" ;; *) bad "running kernel is $rel, not the r3a kernel" ;; esac
trial=$(tr -d '\0' < /proc/device-tree/chosen/aurora,trial 2>/dev/null)
info "Stage 2: ${trial:-the configured m1n1/boot-ctxr.bin}"
tree=r1; for f in /proc/device-tree/chosen/framebuffer@*/apple,internal-panel; do [ -e "$f" ] && tree=r3a; done
[ "$tree" = "$want" ] && ok "device tree is the $tree tree (apple,internal-panel property: $([ $tree = r3a ] && echo present || echo absent))" || bad "expected the $want tree, the booted tree looks like $tree"
conf=$(zcat /proc/config.gz 2>/dev/null)
for o in BT_RFCOMM BT_BNEP PSI BINFMT_MISC TCP_CONG_BBR NET_SCH_FQ IP_ADVANCED_ROUTER IPV6_MULTIPLE_TABLES PKCS8_PRIVATE_KEY_PARSER NETFILTER_XT_MATCH_HL IP6_NF_MATCH_RT; do
  v=$(grep -E "^CONFIG_$o=" <<<"$conf" | cut -d= -f2); [ -n "$v" ] && ok "CONFIG_$o=$v" || bad "CONFIG_$o is not set"
done
[ -d /sys/class/net/wlan0 ] && ok "wlan0 present" || bad "no wlan0"
[ -d /sys/class/bluetooth/hci0 ] && ok "hci0 present" || bad "no hci0"
ls /sys/class/power_supply/ 2>/dev/null | grep -q . && ok "power supplies: $(ls /sys/class/power_supply | tr '\n' ' ')" || bad "no power supply"
ls /sys/class/hwmon/*/name >/dev/null 2>&1 && ok "hwmon: $(cat /sys/class/hwmon/*/name | sort -u | tr '\n' ' ')" || bad "no hwmon"
ls /dev/input/event* >/dev/null 2>&1 && ok "input devices present" || bad "no input devices"
failed=$(systemctl --failed --no-legend 2>/dev/null | awk '{print $2}' | tr '\n' ' ')
[ -z "$failed" ] && ok "no failed system units" || info "failed system units: $failed"
for u in ufw systemd-oomd systemd-binfmt tailscaled bluetooth; do
  printf 'info  %-16s %s\n' "$u" "$(systemctl is-active $u 2>/dev/null)"
done
info "default qdisc / tcp: $(sysctl -n net.core.default_qdisc 2>/dev/null) / $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
bad_log=$(dmesg 2>/dev/null | grep -E 'Oops|BUG:|WARNING:|Call trace|SError|panic' | head -5)
if [ -z "$(dmesg 2>/dev/null | head -1)" ]; then info "dmesg is root-only here: run  sudo dmesg | grep -E 'Oops|BUG:|WARNING:|SError'"
elif [ -z "$bad_log" ]; then ok "no Oops, BUG, WARNING or SError in dmesg"; else bad "dmesg: $bad_log"; fi
info "USB: $(ls /sys/bus/usb/devices 2>/dev/null | tr '\n' ' ') (idle ports have no host by design; docs/r3-usb.md)"
info "sound cards: $(grep -c . /proc/asound/cards 2>/dev/null || echo 0) lines in /proc/asound/cards (expected none until the sound step)"
info "connector: $(ls /sys/class/drm 2>/dev/null | grep -E 'card[0-9]+-' | tr '\n' ' ') (Unknown-1 on the r1 tree, eDP-1 on the r3a tree)"
