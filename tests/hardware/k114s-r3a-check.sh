#!/bin/bash
# Read-only report of what the r3a (or r3b) kernel changed, for the first boot of linux-k114s. No root needed
# (a few lines are better with root and say so). Changes nothing. Prints "ok", "BAD" or "info" lines.
#   tests/hardware/k114s-r3a-check.sh [--expect-tree r1|r3a] [--allow-gpu]
# --allow-gpu is for the separate r3a + GPU step only. Otherwise a boot on the GPU Stage 2 trial is a BAD line: the r3a
# kernel changes the GPU mailbox path that was proven on this Mac with the running kernel (docs/r3-integration.md).
want=r1; allow_gpu=0
while [ $# -gt 0 ]; do case $1 in --expect-tree) want=${2:-r1}; shift ;; --allow-gpu) allow_gpu=1 ;; esac; shift; done
ok() { echo "ok    $*"; }; bad() { echo "BAD   $*"; }; info() { echo "info  $*"; }
rel=$(uname -r)
case $rel in *k114s-r3[ab]-ARCH) ok "running kernel $rel" ;; *) bad "running kernel is $rel, not an r3a or r3b kernel" ;; esac
case $rel in *k114s-r3b-ARCH) info "r3b: the GPU mailboxes receive by interrupt only and the connector stays Unknown-1 (docs/r3b-kernel.md, section 3)" ;; esac
trial=$(tr -d '\0' < /proc/device-tree/chosen/aurora,trial 2>/dev/null)
info "Stage 2: ${trial:-the configured m1n1/boot-ctxr.bin}"
gpu_node=$(ls -d /sys/bus/platform/drivers/aurora/*/drm/renderD* 2>/dev/null | head -1)
if [ $allow_gpu = 0 ]; then
  case $trial in *gpu*) bad "this boot is the GPU Stage 2 trial ($trial): the r3a kernel must not run on the GPU tree in this step" ;; *) ok "not the GPU Stage 2 trial" ;; esac
  [ -n "$gpu_node" ] && bad "the GPU render node exists ($gpu_node): this is the GPU tree" || ok "no GPU render node (the GPU tree is not booted)"
else
  info "GPU step: render node ${gpu_node:-none}; mailbox interrupts: $(grep -i mailbox /proc/interrupts 2>/dev/null | awk '{print $NF": "$2}' | tr '\n' ' ')"
fi
os=/sys/firmware/efi/efivars/LoaderEntryOneShot-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f
[ -e "$os" ] && info "LoaderEntryOneShot is still set (a request for the next boot): $(tail -c +5 "$os" | iconv -f UTF-16LE -t UTF-8 2>/dev/null | tr -d '\0')" || ok "no LoaderEntryOneShot left over: Limine consumed the request"
for t in suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target; do [ "$(systemctl is-enabled $t 2>/dev/null)" = masked ] || bad "$t is not masked"; done
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
