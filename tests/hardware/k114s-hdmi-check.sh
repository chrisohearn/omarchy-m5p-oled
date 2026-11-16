#!/bin/bash
# OWNER-AT-THE-MAC. Read-only report on the HDMI port (issue #24). Changes nothing; no root needed
# (the kernel log is better with it). Run it twice: once with nothing in the HDMI port, once with a
# monitor or TV on it, on a boot of a tree that includes dts/t6050-k114s-hdmi.dtsi
# (K114S_R3B_HDMI). On any other boot it says "no HDMI connector", which is the expected answer today.
#   tests/hardware/k114s-hdmi-check.sh
ok() { echo "ok    $*"; }; bad() { echo "BAD   $*"; }; info() { echo "info  $*"; }
dm=$(dmesg 2>/dev/null) || { dm=$(journalctl -k -b --no-pager 2>/dev/null); info "dmesg needs root; used the kernel journal"; }
n=0
for c in /sys/class/drm/card*-HDMI-A-*; do
  [ -e "$c/status" ] || continue; n=$((n+1))
  ok "connector $(basename "$c"): status $(cat "$c/status"), enabled $(cat "$c/enabled" 2>/dev/null)"
  if [ "$(cat "$c/status")" = connected ]; then
    ok "modes: $(head -5 "$c/modes" 2>/dev/null | tr '\n' ' ')"
    ls /sys/class/sound/ 2>/dev/null | grep -qi card && info "sound cards: $(cat /proc/asound/cards 2>/dev/null | grep -i '^ *[0-9]' | tr '\n' ' ') (HDMI audio is not in this check)"
  else
    info "no sink seen: plug a monitor into the HDMI port and run again"
  fi
done
[ "$n" -gt 0 ] || bad "no HDMI connector in /sys/class/drm: this boot is not an HDMI tree (expected until issue #24 is worked)"
for f in /sys/class/drm/card*-eDP-1/status; do [ -e "$f" ] && info "internal panel: $(cat "$f")"; done
grep -iE 'hdmi|dcpext|dptx|atc3|dp2hdmi' <<<"$dm" | tail -20 | sed 's/^/info  dmesg: /'
grep -iE '(hdmi|dcpext|dptx|atc3).*(fail|error|timeout|broken|crash)' <<<"$dm" | head -8 | sed 's/^/BAD   dmesg: /'
info "watch the screen too: the check cannot see a picture. Note monitor model, cable, whether it was asleep at plug-in."
