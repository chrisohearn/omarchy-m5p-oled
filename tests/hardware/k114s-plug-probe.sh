#!/bin/bash
# READ-ONLY plug-change probe: macsmc-ac, typec and tps6598x. Issues #57 and #71.
#
#   k114s-plug-probe.sh [SECONDS [LABEL]]     default: 120 s; LABEL is free text for your notes
#
# It prints a full snapshot, then one line whenever anything changes (polled every 0.25 s).
# While it runs, per the checklist:  1. note which connector the charger is on (MagSafe, left-front,
# right, left-back);  2. unplug and replug it;  3. plug a charger or device into each USB-C port;
# 4. note the MagSafe LED (amber charging, green full).  Paste the output into the issue.
# Fields: macsmc-ac online and input_power_limit, battery status, per typec port the partner,
# power_operation_mode, power_role and data_role, the tps6598x source supplies, UPower OnBattery
# and the power profile. Nothing is written; no root needed. No serials or addresses are printed.
set -u
sys=${K114S_SYSFS:-/sys}
dur=${1:-120}; label=${2:-}
ps=$sys/class/power_supply

rd() { cat "$1" 2>/dev/null || echo "?"; }
state() {
  local p x line="ac=$(rd "$ps/macsmc-ac/online") limit_W=$(awk -v v="$(rd "$ps/macsmc-ac/input_power_limit")" 'BEGIN { if (v ~ /^[0-9]+$/) printf "%.1f", v / 1e6; else print "?" }')"
  line+=" bat=$(rd "$ps/macsmc-battery/status")"
  for p in "$sys"/class/typec/port*; do
    [[ -d $p && ${p##*/} =~ ^port[0-9]+$ ]] || continue
    x=none; ls -d "$p"/${p##*/}-partner >/dev/null 2>&1 && x=present
    line+=" ${p##*/}[partner=$x mode=$(rd "$p/power_operation_mode") pwr=$(rd "$p/power_role") data=$(rd "$p/data_role")]"
  done
  for p in "$ps"/tps6598x-source-psy-*; do
    [[ -d $p ]] && line+=" ${p##*psy-}=$(rd "$p/online")"
  done
  line+=" onbattery=$(busctl get-property org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower OnBattery 2>/dev/null | cut -d' ' -f2)"
  echo "$line profile=$(powerprofilesctl get 2>/dev/null || echo ?) platform=$(rd "$sys/class/platform-profile/platform-profile-0/profile") governor=$(rd "$sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")"
}

echo "# probe start $(date +%T) label=${label:-none} kernel=$(uname -r)"
prev=$(state); echo "$(date +%T) $prev"
end=$((SECONDS + dur))
while [[ $SECONDS -lt $end ]]; do
  cur=$(state)
  [[ $cur != "$prev" ]] && { echo "$(date +%T) $cur"; prev=$cur; }
  sleep 0.25
done
echo "# probe end $(date +%T)"
