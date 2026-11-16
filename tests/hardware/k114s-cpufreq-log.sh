#!/bin/bash
# READ-ONLY CPU frequency, governor and profile sampler for the K114s. Issue #54.
#
#   k114s-cpufreq-log.sh [SECONDS_BETWEEN_SAMPLES [SAMPLES]]    default: every 2 s, until Ctrl-C
#
# Per sample: the power profile (power-profiles-daemon), the apple-clpc platform profile, AC or
# battery (UPower), and for each cpufreq policy the governor and current frequency in MHz.
# Start a load in another terminal (for example `yes > /dev/null` on a few cores) to see the
# frequency rise; run it on battery and on AC, and after `powerprofilesctl set balanced`.
# It writes nothing. Redirect to a file: ./k114s-cpufreq-log.sh 2 30 > cpufreq.log
set -u
sys=${K114S_SYSFS:-/sys}
interval=${1:-2}; samples=${2:-0}
[[ $interval =~ ^[0-9]+$ && $samples =~ ^[0-9]+$ ]] || { echo "usage: $0 [SECONDS [SAMPLES]] (whole numbers)" >&2; exit 2; }

rd() { cat "$1" 2>/dev/null || echo "?"; }
mhz() { [[ $1 =~ ^[0-9]+$ ]] && echo $(($1 / 1000)) || echo "?"; }
profile() { powerprofilesctl get 2>/dev/null || echo "?"; }
onbat() {
  case $(busctl get-property org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower OnBattery 2>/dev/null) in
    "b true") echo battery ;; "b false") echo ac ;; *) echo "?" ;;
  esac
}

mapfile -t policies < <(printf "%s\n" "$sys"/devices/system/cpu/cpufreq/policy* | sort -V)
[[ -d ${policies[0]} ]] || { echo "no cpufreq policies found" >&2; exit 1; }

echo "# $(uname -r); driver $(rd "${policies[0]}/scaling_driver")"
for p in "${policies[@]}"; do
  echo "# $(basename "$p"): cpus $(rd "$p/related_cpus") range $(mhz "$(rd "$p/cpuinfo_min_freq")")-$(mhz "$(rd "$p/cpuinfo_max_freq")") MHz governors: $(rd "$p/scaling_available_governors")"
done
echo "# time source ppd_profile platform_profile | per policy: governor cur_MHz (scaling_max_MHz)"
n=0
while :; do
  line="$(date +%H:%M:%S) $(onbat) $(profile) $(rd "$sys/class/platform-profile/platform-profile-0/profile")"
  for p in "${policies[@]}"; do
    f=$(rd "$p/cpuinfo_cur_freq"); [[ $f =~ ^[0-9]+$ ]] || f=$(rd "$p/scaling_cur_freq")
    m=$(rd "$p/scaling_max_freq")
    line+=" | $(rd "$p/scaling_governor") $([[ $f =~ ^[0-9]+$ ]] && echo $((f / 1000)) || echo "?") ($([[ $m =~ ^[0-9]+$ ]] && echo $((m / 1000)) || echo "?"))"
  done
  echo "$line"
  n=$((n + 1)); (( samples > 0 && n >= samples )) && break
  sleep "$interval"
done
