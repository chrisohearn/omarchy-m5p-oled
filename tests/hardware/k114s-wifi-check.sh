#!/bin/bash
# K114s Wi-Fi checks for the owner. See docs/wifi-n1.md. Read-only: nothing is written, no network
# is joined or changed. Journal lines are redacted (MACs, IPs, quoted names) before they are shown.
#
#   k114s-wifi-check.sh status      what iwd is configured to do and which bands the radio and the
#                                   scan cache see (no root needed for most lines)
#   k114s-wifi-check.sh 6ghz        PASS only when the current link is on a 6 GHz channel, the
#                                   gateway answers and there is no join failure since boot.
#                                   Join a 6 GHz network first (nmcli or the Wi-Fi menu).
#   k114s-wifi-check.sh resume      after a suspend/resume: PASS when a resume happened this boot, the
#                                   link is up, the gateway answers and no Wi-Fi firmware or join
#                                   failure was logged since that resume
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

fail_lines() { # kernel and iwd lines (optional journalctl args, e.g. --since) that mean a join or firmware failure
  # -k and -u are ANDed by journalctl, so the two sources are queried separately.
  { journalctl -b --no-pager -o cat -k "$@"; journalctl -b --no-pager -o cat -u iwd "$@"; } 2>/dev/null |
    grep -i -E 'firmware.*(dead|crash|timeout)|assoc.*fail|auth.*fail|sae.*fail|join.*fail|wlan.*reset' || true
}

redact() { sed -E 's/([0-9a-f]{2}:){5}[0-9a-f]{2}/<mac>/gI; s/[0-9]{1,3}(\.[0-9]{1,3}){3}/<ip>/g; s/([0-9a-f]{1,4}:){3,}[0-9a-f]{0,4}/<ip>/gI; s/"[^"]*"/"<name>"/g'; }

report_fails() { # args: journalctl args; prints ok/FAIL, returns 1 on failure
  local out n
  out=$(fail_lines "$@"); n=$(grep -c . <<<"$out")
  if ((n == 0)); then echo "ok   no join or firmware failure logged ${when}"; return 0; fi
  echo "FAIL $n failure line(s) ${when}:"; redact <<<"$out" | tail -5; return 1
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
    f=$(link_freq); rc=0; when="this boot"
    [[ -n $f ]] || { echo "FAIL: not connected"; exit 1; }
    [[ $(band "$f") == 6 ]] && echo "ok   link on 6 GHz ($f MHz)" || { echo "FAIL link on $(band "$f") GHz ($f MHz), not 6 GHz"; rc=1; }
    gateway_ok && echo "ok   gateway answers 3/3 pings" || { echo "FAIL gateway does not answer (the BCM4388 6 GHz symptom: joined, no traffic)"; rc=1; }
    report_fails || rc=1
    ((rc == 0)) && echo "RESULT: PASS" || echo "RESULT: FAIL"
    exit $rc ;;
  resume)
    rc=0
    # Last resume this boot: the kernel's "PM: suspend exit" line. No such line means no resume to check.
    t=$(journalctl -b --no-pager -k -o short-unix 2>/dev/null | awk '/PM: suspend exit/ {t=$1} END {print int(t)}')
    if [[ ${t:-0} -gt 0 ]]; then
      echo "ok   a resume happened this boot"; when="since the last resume"
    else
      echo "FAIL no suspend/resume logged this boot, nothing to check"; rc=1; when="this boot"
    fi
    [[ -n $(link_freq) ]] && echo "ok   link is up ($(band "$(link_freq)") GHz)" || { echo "FAIL no link after resume"; rc=1; }
    gateway_ok && echo "ok   gateway answers 3/3 pings" || { echo "FAIL gateway does not answer"; rc=1; }
    if [[ ${t:-0} -gt 0 ]]; then report_fails --since "@$t" || rc=1; fi
    ((rc == 0)) && echo "RESULT: PASS" || echo "RESULT: FAIL"
    exit $rc ;;
  *) echo "usage: $0 status|6ghz|resume" >&2; exit 2 ;;
esac
