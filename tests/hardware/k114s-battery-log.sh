#!/bin/bash
# READ-ONLY battery, UPower and power-draw logger for the K114s. Issues #52 and #56.
#
#   k114s-battery-log.sh [SECONDS_BETWEEN_SAMPLES [SAMPLES]]    default: every 30 s, until Ctrl-C
#
# Start it, then unplug AC for a discharge log (and plug it back in). One line per sample:
#   time, ac, sysfs status/capacity, UPower state/percentage, agree?, battery power_now (W),
#   SMC "Total System Power" and "AC Input Power" (W), energy_now (Wh), power profile,
#   platform_profile and CPU governor (do they change on unplug?)
# `agree` is MISMATCH when sysfs and UPower disagree on charging/discharging (the suspected
# synthetic-uevent failure of #52). The macsmc-battery sign of power_now is recorded as read;
# compare it with the SMC totals before trusting it. Nothing is written; no root needed.
# Redirect to a file: ./k114s-battery-log.sh 30 > battery.log
set -u
sys=${K114S_SYSFS:-/sys}
bat=$sys/class/power_supply/macsmc-battery
ac=$sys/class/power_supply/macsmc-ac
interval=${1:-30}; samples=${2:-0}

rd() { cat "$1" 2>/dev/null || echo "?"; }
w() { awk -v v="$1" 'BEGIN { if (v ~ /^-?[0-9]+$/) printf "%.2f", v / 1e6; else print "?" }'; }
wh() { awk -v v="$1" 'BEGIN { if (v ~ /^-?[0-9]+$/) printf "%.2f", v / 1e6; else print "?" }'; }
hw=""
for h in "$sys"/class/hwmon/hwmon*; do [[ $(rd "$h/name") == macsmc_hwmon ]] && hw=$h; done
hwpower() { # label -> watts
  local f
  for f in "$hw"/power*_label; do
    [[ -e $f && $(rd "$f") == "$1" ]] && { w "$(rd "${f%_label}_input")"; return; }
  done
  echo "?"
}
upower_field() { upower -i /org/freedesktop/UPower/devices/battery_macsmc_battery 2>/dev/null | awk -F: -v k="$1" '$1 ~ k { gsub(/^[ \t]+|[ \t%]+$/, "", $2); print $2; exit }'; }

echo "# $(uname -r); kernel log lines 'failed to report manufacture_year' this boot: $(journalctl -k -b --no-pager 2>/dev/null | grep -c 'manufacture_year' || true)"
echo "# time ac sysfs_status sysfs_pct upower_state upower_pct agree power_now_W smc_total_W smc_acin_W energy_now_Wh profile platform_profile governor"
n=0
while :; do
  s=$(rd "$bat/status"); u=$(upower_field state); u=${u:-?}
  case "$s/$u" in
    Charging/charging | Discharging/discharging | Full/fully-charged | "Not charging"/pending-charge | Full/pending-charge) a=ok ;;
    */\?) a=no-upower ;;
    *) a=MISMATCH ;;
  esac
  echo "$(date +%T) ac=$(rd "$ac/online") $s $(rd "$bat/capacity") $u $(upower_field percentage) $a" \
    "$(w "$(rd "$bat/power_now")") $(hwpower "Total System Power") $(hwpower "AC Input Power") $(wh "$(rd "$bat/energy_now")")" \
    "$(powerprofilesctl get 2>/dev/null || echo ?)" \
    "platform=$(rd "$sys/class/platform-profile/platform-profile-0/profile") governor=$(rd "$sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")"
  n=$((n + 1)); [[ $samples -gt 0 && $n -ge $samples ]] && break
  sleep "$interval"
done
