#!/bin/bash
# READ-ONLY GPU soak sampler for the K114s (aurora driver). Issue #34.
#
#   k114s-gpu-qualify.sh [SECONDS_BETWEEN_SAMPLES [SAMPLES]]     default: every 5 s, 12 samples
#
# Per sample: GPU utilisation and busy_ns (agx_stats), the GPU mailbox receive interrupt rate
# (/proc/interrupts), the hottest SMC temperature, fan tach, total system power, and the count of
# aurora fault/timeout/hang kernel lines since the first sample. A header lists which GPU power
# telemetry the driver reports as "unsupported" (pstate, frequency, power, temperature, runtime PM).
# The end line is RESULT: PASS only if no fault line appeared, the mailbox interrupt kept arriving,
# and no sample read an unreadable agx_stats. "unsupported" telemetry is reported, never a failure:
# it is the finding that blocks "qualified" (no GPU frequency scaling or power figure yet).
#
# It writes nothing. To load the GPU, start your own load in another terminal while this runs
# (a WebGL page, scrolling Hyprland workspaces, or vkmark/glmark2 once installed; neither is in the
# default install, and ffmpeg software encoding does not load the GPU).
# Needs root only to read agx_stats and the kernel log: sudo k114s-gpu-qualify.sh 5 24 | tee gpu.log
set -u
sys=${K114S_SYSFS:-/sys}
proc=${K114S_PROC:-/proc}
dev=${K114S_GPU_DEV:-$sys/class/drm/card1/device}
interval=${1:-5}; samples=${2:-12}
rd() { cat "$1" 2>/dev/null || echo "?"; }
stat() { awk -v k="$1" '$1 == k { print $2 }' "$dev/agx_stats" 2>/dev/null; }

[[ -r $dev/agx_stats ]] || { echo "no readable $dev/agx_stats (run as root, on the aurora GPU tree)" >&2; exit 2; }
hw=""
for h in "$sys"/class/hwmon/hwmon*; do [[ $(rd "$h/name") == macsmc_hwmon ]] && hw=$h; done

irq() { awk '/2302600000\.mailbox-recv/ { s = 0; for (i = 2; i <= NF && $i ~ /^[0-9]+$/; i++) s += $i; print s }' "$proc/interrupts"; }
faults() { { journalctl -k -b --no-pager 2>/dev/null || dmesg 2>/dev/null; } | grep -c -i -E 'aurora.*(fault|timeout|hang|error)'; }
hottest() { [[ -n $hw ]] || { echo "?"; return; }
  for f in "$hw"/temp*_input; do rd "$f"; done | awk '$1 ~ /^-?[0-9]+$/ && $1 > -100000 && $1 != 0 && $1 > m { m = $1 } END { if (m) printf "%.1f", m / 1000; else print "?" }'; }
fan() { [[ -n $hw ]] || { echo "?"; return; }; local o="" f; for f in "$hw"/fan*_input; do [[ -e $f ]] && o+="$(rd "$f") "; done; echo "${o:-?}"; }
power() { [[ -n $hw ]] || return 0
  for f in "$hw"/power*_label; do [[ $(rd "$f") == "Total System Power" ]] && awk -v v="$(rd "${f%_label}_input")" 'BEGIN { printf "%.1f", v / 1e6 }'; done; }

echo "# $(uname -r)"
echo "# unsupported GPU telemetry: $(awk '$2 == "unsupported" || $2 == "unavailable" { printf "%s ", $1 }' "$dev/agx_stats"); runtime_status=$(rd "$dev/power/runtime_status"); idle_off_delay_ms=$(rd "$dev/idle_off_delay_ms")"
echo "# time util_dev% util_rend% busy_ms_delta mbox_irq/s hottest_C fans_rpm | total_W aurora_faults"
i0=$(irq); [[ -n $i0 ]] || { echo "no 2302600000.mailbox-recv in $proc/interrupts: GPU mailbox not interrupt-driven here" >&2; exit 1; }
f0=$(faults); b0=$(stat busy_ns); t0=$(date +%s.%N)
n=0; bad=0; irqmoved=0; ip=$i0; bp=$b0; tp=$t0
while [[ $n -lt $samples ]]; do
  sleep "$interval"
  ic=$(irq); bc=$(stat busy_ns); tc=$(date +%s.%N)
  ud=$(stat util_device_percent); ur=$(stat util_renderer_percent)
  [[ -n $ud && -n $bc ]] || bad=1
  rate=$(awk -v a="$ip" -v b="$ic" -v t0="$tp" -v t1="$tc" 'BEGIN { printf "%.0f", (b - a) / (t1 - t0) }')
  bms=$(awk -v a="${bp:-0}" -v b="${bc:-0}" 'BEGIN { printf "%.0f", (b - a) / 1e6 }')
  [[ $ic -gt $ip ]] && irqmoved=1
  fc=$(( $(faults) - f0 ))
  echo "$(date +%T) ${ud:-?} ${ur:-?} $bms $rate $(hottest) $(fan)| $(power)W $fc"
  ip=$ic; bp=$bc; tp=$tc; n=$((n + 1))
done
fc=$(( $(faults) - f0 ))
if [[ $fc -eq 0 && $irqmoved -eq 1 && $bad -eq 0 ]]; then echo "RESULT: PASS (no aurora fault line, mailbox interrupt arrived, agx_stats readable)"
else echo "RESULT: FAIL (fault lines $fc, mailbox interrupt moved $irqmoved, unreadable stats $bad)"; exit 1; fi
