#!/bin/bash
# OWNER-AT-THE-MAC. Read-only report after a boot of a tree that includes one of the draft fragments
# (dts/t6050-k114s-avd.dtsi, -sd.dtsi, -aop-sensors.dtsi; docs/r3-parity-drafts.md). Changes nothing.
# No root needed (dmesg lines are better with it and say so). Prints "ok", "BAD" or "info" lines.
#   tests/hardware/k114s-parity-check.sh [avd] [sd] [sensors]      (default: all three)
# It cannot judge playback, a card or a hand over the sensor: the lines tell you what to do next.
ok() { echo "ok    $*"; }; bad() { echo "BAD   $*"; }; info() { echo "info  $*"; }
groups=${*:-avd sd sensors}
dm=$(dmesg 2>/dev/null) || { dm=$(journalctl -k -b --no-pager 2>/dev/null); info "dmesg needs root; used the kernel journal"; }
st() { tr -d '\0' < "$1" 2>/dev/null; }
for g in $groups; do case $g in
avd)
  echo "== video decode (issue #30)"
  n=/proc/device-tree/soc@2308000000/avd@2309080000
  case "$(st $n/status)" in okay) ok "avd node in the booted tree, status okay" ;; *) bad "avd node missing or disabled (status: $(st $n/status)): this boot is not the AVD tree" ;; esac
  ls /dev/video* >/dev/null 2>&1 && ok "video nodes: $(ls /dev/video* | tr '\n' ' ')" || bad "no /dev/video*"
  ls /dev/media* >/dev/null 2>&1 && ok "media nodes: $(ls /dev/media* | tr '\n' ' ')" || bad "no /dev/media*"
  lsmod | grep -qi avd && ok "driver loaded: $(lsmod | awk '/avd/{print $1}' | tr '\n' ' ')" || info "no avd module loaded (modprobe is a root step: apple_avd or similar, see modinfo)"
  grep -i 'avd' <<<"$dm" | tail -15 | sed 's/^/info  dmesg: /'
  grep -iE 'avd.*(fail|error|timeout|fault)' <<<"$dm" | head -5 | sed 's/^/BAD   dmesg: /'
  info "next: vaapi decode needs libva-v4l2_request-avd; compare md5 of ffmpeg software and vaapi output of one short clip (docs/r3-parity-drafts.md)"
  ;;
sd)
  echo "== SD card reader (issue #62)"
  lspci 2>/dev/null | grep -qi genesys && ok "GL9755 on the bus: $(lspci | grep -i genesys)" || bad "no Genesys device in lspci (port 1 did not train, or this boot is not the SD tree)"
  ls -d /sys/class/mmc_host/mmc* >/dev/null 2>&1 && ok "mmc host: $(ls /sys/class/mmc_host | tr '\n' ' ')" || bad "no mmc host"
  lsmod | grep -q sdhci_pci && ok "sdhci_pci loaded" || info "sdhci_pci not loaded"
  grep -iE 'apple-pcie|pcie.*port ?1|sdhci|mmc' <<<"$dm" | tail -12 | sed 's/^/info  dmesg: /'
  grep -iE 'port ?1.*(fail|timeout)|PERST' <<<"$dm" | head -5 | sed 's/^/BAD   dmesg: /'
  info "next: insert an SD card, then lsblk (read-only); write only to a card you can lose"
  ;;
sensors)
  echo "== ambient light and lid angle (issue #67)"
  [ -d /sys/bus/platform/devices/290c00000.aop ] && ok "aop device present, driver: $(basename "$(readlink /sys/bus/platform/devices/290c00000.aop/driver 2>/dev/null)")" || bad "no aop device"
  ls /sys/bus/iio/devices/ 2>/dev/null | grep -q . && ok "iio devices: $(for d in /sys/bus/iio/devices/iio:device*; do echo -n "$(cat $d/name 2>/dev/null) "; done)" || bad "no iio device (the sensors are not up)"
  for d in /sys/bus/iio/devices/iio:device*; do
    case "$(cat $d/name 2>/dev/null)" in *als*) info "als illuminance: $(cat $d/in_illuminance_input $d/in_illuminance_raw 2>/dev/null | head -1) (cover the sensor with a hand and run again)";;
    *las*|*lid*) info "lid angle: $(cat $d/in_angl_raw $d/in_angl_input 2>/dev/null | head -1) (move the lid and run again)";; esac
  done
  grep -iE 'aop' <<<"$dm" | tail -15 | sed 's/^/info  dmesg: /'
  grep -iE 'aop.*(fail|error|timeout|crash|panic)' <<<"$dm" | head -5 | sed 's/^/BAD   dmesg: /'
  [ -d /sys/class/sound ] && ls /sys/class/sound | grep -q '^card' && info "a sound card exists: speakers stay muted, never play unprotected" || ok "no sound card from this tree"
  info "known open (docs/r3-parity-drafts.md): the ALS may stay silent without the calibration drivers (#1983, #1929); no ADT las node"
  ;;
esac; done
