#!/bin/bash
# READ-ONLY fan and temperature logger for the K114s (macsmc_hwmon). Issue #55.
#
#   k114s-thermal-log.sh [SECONDS_BETWEEN_SAMPLES [SAMPLES]]    default: every 5 s, until Ctrl-C
#
# Per sample: fan tach and min/max, the five hottest SMC temperature channels (labels shown), the
# macsmc-battery temperature, and the SMC power rails. Channels reading <= -100 C or exactly 0 are
# listed as ABSENT once at the start (the TAO* keys of #55) and left out of the hottest list.
# It writes nothing, in particular no fanN_target; to spin the fans, start your own load in
# another terminal (for example `yes > /dev/null` on a few cores) while this runs.
# Redirect to a file: ./k114s-thermal-log.sh 5 > thermal.log
set -u
sys=${K114S_SYSFS:-/sys}
interval=${1:-5}; samples=${2:-0}

rd() { cat "$1" 2>/dev/null || echo "?"; }
hw=""
for h in "$sys"/class/hwmon/hwmon*; do [[ $(rd "$h/name") == macsmc_hwmon ]] && hw=$h; done
[[ -n $hw ]] || { echo "no macsmc_hwmon found" >&2; exit 1; }

temps() { # "label milli-C" for every channel
  local f
  for f in "$hw"/temp*_input; do
    printf '%s %s\n' "$(rd "${f%_input}_label")" "$(rd "$f")"
  done
}

echo "# $(uname -r); absent channels (<= -100 C or 0): $(temps | awk '$2 ~ /^-?[0-9]+$/ && ($2 <= -100000 || $2 == 0) { printf "%s(%s) ", $1, $2 / 1000 }')"
echo "# time fan1_rpm(min-max) fan2_rpm(min-max) | top5 temps C | battery_C | total_W"
n=0
while :; do
  fans=""
  for f in "$hw"/fan*_input; do
    [[ -e $f ]] || continue
    b=${f%_input}; fans+="$(rd "$f")($(rd "${b}_min")-$(rd "${b}_max")) "
  done
  top=$(temps | awk '$2 ~ /^-?[0-9]+$/ && $2 > -100000 && $2 != 0 { print $2, $1 }' | sort -rn | head -5 | awk '{ printf "%s=%.1f ", $2, $1 / 1000 }')
  total=$(for f in "$hw"/power*_label; do [[ $(rd "$f") == "Total System Power" ]] && awk -v v="$(rd "${f%_label}_input")" 'BEGIN { printf "%.1f", v / 1e6 }'; done)
  bt=$(awk -v v="$(rd "$sys/class/power_supply/macsmc-battery/temp")" 'BEGIN { if (v ~ /^-?[0-9]+$/) printf "%.1f", v / 10; else print "?" }')
  echo "$(date +%T) $fans| $top| bat=$bt | ${total:-?}W"
  n=$((n + 1)); [[ $samples -gt 0 && $n -ge $samples ]] && break
  sleep "$interval"
done
