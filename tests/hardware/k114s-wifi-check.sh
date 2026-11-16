#!/bin/bash
# K114s Wi-Fi checks for the owner. See docs/wifi-n1.md. Read-only: nothing is written, no network
# is joined or changed. The output holds no network names, addresses or serial numbers.
#
#   k114s-wifi-check.sh status      what iwd is configured to do and which bands the radio and the
#                                   scan cache see (no root needed for most lines)
#   k114s-wifi-check.sh 6ghz        PASS only when the current link is on a 6 GHz channel, the
#                                   gateway answers and there is no join failure since boot.
#                                   Join a 6 GHz network first (nmcli or the Wi-Fi menu).
#   k114s-wifi-check.sh resume      after a suspend/resume: PASS when the link is up, the gateway
#                                   answers and the kernel logged no Wi-Fi firmware failure since
#                                   the last resume
set -u
dev=${K114S_WIFI_DEV:-wlan0}

band() { # MHz -> band name
  local f=$1
  if ((f >= 5925)); then echo 6; elif ((f >= 4900)); then echo 5; else echo 2.4; fi
}

link_freq() { iw dev "$dev" link 2>/dev/null | awk '/freq:/ {print int($2)}'; }

gateway_ok() {
  local gw
  gw=$(ip -4 route show default dev "$dev" 2>/dev/null | awk '{print $3; exit}')
  [[ -n $gw ]] && ping -c 3 -W 2 -q "$gw" >/dev/null 2>&1
}

fail_lines() { # kernel and iwd lines that mean a join or firmware failure
  journalctl -b --no-pager -k -u iwd "${@}" 2>/dev/null |
    grep -i -E 'firmware.*(dead|crash|timeout)|assoc.*fail|auth.*fail|sae.*fail|join.*fail|wlan.*reset' || true
}

status() {
  echo "iwd config dirs: $(systemctl show iwd -p Environment --value 2>/dev/null | sed 's/.*CONFIGURATION_DIRECTORY=//')"
  local cfg v
  for cfg in /etc/iwd/main.conf /usr/lib/omarchy-aurora/iwd-n1/main.conf /usr/lib/omarchy-mac/iwd/main.conf; do
    [[ -e $cfg ]] || continue
    v=$(awk -F= '/^BandModifier6GHz/ {print $2}' "$cfg")
    echo "  $cfg: BandModifier6GHz=${v:-unset (iwd default 1.0, 6 GHz on)}"
  done
  echo "6 GHz channels the radio offers: $(iw phy 2>/dev/null | grep -c -E '^\s+\* (59[5-9][0-9]|[6-7][0-9]{3})\.[0-9] MHz')"
  echo "scan cache BSS by band:"
  iw dev "$dev" scan dump 2>/dev/null | awk '/^\s+freq:/ {f=int($2); b=(f>=5925)?"6":(f>=4900)?"5":"2.4"; c[b]++} END {for (k in c) printf "  %s GHz: %d\n", k, c[k]}'
  local f; f=$(link_freq)
  [[ -n $f ]] && echo "current link: $f MHz (band $(band "$f") GHz)" || echo "current link: none"
  echo "resume-fix unit: $(systemctl is-enabled omarchy-wifi-resume-fix.service 2>&1)"
  echo "wifi-supported gate: $(/usr/lib/omarchy-mac/wifi-supported && echo passes || echo "fails (expected on the N1)")"
}

case ${1:-status} in
  status) status ;;
  6ghz)
    f=$(link_freq); rc=0
    [[ -n $f ]] || { echo "FAIL: not connected"; exit 1; }
    [[ $(band "$f") == 6 ]] && echo "ok   link on 6 GHz ($f MHz)" || { echo "FAIL link on $(band "$f") GHz ($f MHz), not 6 GHz"; rc=1; }
    gateway_ok && echo "ok   gateway answers 3/3 pings" || { echo "FAIL gateway does not answer (the BCM4388 6 GHz symptom: joined, no traffic)"; rc=1; }
    n=$(fail_lines | wc -l); ((n == 0)) && echo "ok   no join or firmware failure logged this boot" || { echo "FAIL $n failure line(s) this boot:"; fail_lines | sed -E 's/([0-9a-f]{2}:){5}[0-9a-f]{2}/<mac>/g' | tail -5; rc=1; }
    ((rc == 0)) && echo "RESULT: PASS" || echo "RESULT: FAIL"
    exit $rc ;;
  resume)
    rc=0
    [[ -n $(link_freq) ]] && echo "ok   link is up ($(band "$(link_freq)") GHz)" || { echo "FAIL no link after resume"; rc=1; }
    gateway_ok && echo "ok   gateway answers 3/3 pings" || { echo "FAIL gateway does not answer"; rc=1; }
    n=$(fail_lines | wc -l); ((n == 0)) && echo "ok   no Wi-Fi failure logged this boot" || { echo "FAIL $n failure line(s):"; fail_lines | sed -E 's/([0-9a-f]{2}:){5}[0-9a-f]{2}/<mac>/g' | tail -5; rc=1; }
    ((rc == 0)) && echo "RESULT: PASS" || echo "RESULT: FAIL"
    exit $rc ;;
  *) echo "usage: $0 status|6ghz|resume" >&2; exit 2 ;;
esac
