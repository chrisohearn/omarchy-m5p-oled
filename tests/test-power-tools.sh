#!/bin/bash
# Software test of the power tooling against fake sysfs trees: no root, no hardware, no writes
# outside a temp dir. It covers (a) the installed omarchy-battery-charge-limit, its udev restore
# script and rules (#53), (b) omarchy-powerprofiles-set's ac/battery choice (#56), and
# (c) the owner-run scripts in tests/hardware (#52, #53, #55, #56, #57, #71).
# It proves script logic only; whether the T6050 SMC honours a threshold is hardware-only.
# The omarchy-mac scripts are read from /usr/bin and /usr/lib/omarchy-mac; without them part (a)
# and (b) are skipped.
set -u
here=$(cd "$(dirname "$0")" && pwd)
hw=$here/hardware
bin=${OMARCHY_MAC_BIN:-/usr/bin}
lib=${OMARCHY_MAC_LIB:-/usr/lib/omarchy-mac}
t=$(mktemp -d) || exit 2
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
is() { [[ $1 == "$2" ]] && ok "$3" || bad "$3 (got '$1', want '$2')"; }

# fake sysfs: a battery at 100/100 and AC online
S=$t/sys; ps=$S/class/power_supply
mkdir -p "$ps/macsmc-battery" "$ps/macsmc-ac" "$t/etc" "$t/stub"
b=$ps/macsmc-battery
echo 100 >"$b/charge_control_end_threshold"; echo 100 >"$b/charge_control_start_threshold"
echo Full >"$b/status"; echo 100 >"$b/capacity"; echo "[auto] inhibit-charge" >"$b/charge_behaviour"
echo 1 >"$ps/macsmc-ac/online"; echo 59800000 >"$ps/macsmc-ac/input_power_limit"; echo Mains >"$ps/macsmc-ac/type"
conf=$t/etc/macsmc-battery.conf
rd() { cat "$1" 2>/dev/null; }

# stubs: sudo runs the command, then mimics the driver (start derives from end; FAKE_STUCK ignores writes)
cat >"$t/stub/sudo" <<STUB
#!/bin/bash
if [[ \${FAKE_STUCK:-} == 1 ]]; then cat >/dev/null; exit 0; fi
"\$@"; rc=\$?
e=\$(cat "$b/charge_control_end_threshold"); [[ \$e == 80 ]] && echo 75 >"$b/charge_control_start_threshold" || echo "\$e" >"$b/charge_control_start_threshold"
exit \$rc
STUB
cat >"$t/stub/omarchy-hw-apple-silicon" <<'STUB'
#!/bin/bash
[[ ${FAKE_NOT_APPLE:-} != 1 ]]
STUB
cat >"$t/stub/upower" <<'STUB'
#!/bin/bash
printf '    state:               %s\n    percentage:          %s\n' "${FAKE_UPOWER_STATE:-fully-charged}" "${FAKE_UPOWER_PCT:-100%}"
STUB
cat >"$t/stub/omarchy-shell" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$t"/stub/*
[[ $EUID -ne 0 ]] || { echo "refusing to run as root" >&2; exit 2; }
rewrite() {
  sed -e "s#/sys/class/power_supply#$ps#g" -e "s#/etc/udev/macsmc-battery.conf#$conf#g" "$1" >"$2"
  if grep -qE "[\"'=( ]/(sys/class/power_supply|etc/udev)" "$2"; then echo "FAIL path rewrite incomplete in $1" >&2; exit 2; fi
  chmod +x "$2"
}
run() { PATH=$t/stub:$PATH "$@"; }

if [[ -x $bin/omarchy-battery-charge-limit && -x $lib/battery-charge-limit-restore ]]; then
  rewrite "$bin/omarchy-battery-charge-limit" "$t/limit"
  rewrite "$lib/battery-charge-limit-restore" "$t/restore"

  # 1. omarchy-battery-charge-limit
  out=$(run "$t/limit" 2>&1); is "$out" "Charge limit: 100% (restart charging at 100%)" "status reads the thresholds"
  [[ ! -e $conf ]] && ok "status writes nothing" || bad "status wrote the saved file"
  run "$t/limit" 80 >/dev/null 2>&1; rc=$?
  is "$rc/$(rd "$b/charge_control_end_threshold")/$(rd "$b/charge_control_start_threshold")" "0/80/75" "80 sets end 80, start reads 75"
  is "$(rd "$conf")" "CHARGE_CONTROL_END_THRESHOLD=80" "80 is saved for boot"
  run "$t/limit" 100 >/dev/null 2>&1; rc=$?
  is "$rc/$(rd "$b/charge_control_end_threshold")/$(rd "$b/charge_control_start_threshold")" "0/100/100" "100 restores end and start"
  is "$(rd "$conf")" "CHARGE_CONTROL_END_THRESHOLD=100" "100 is saved"
  rm -f "$conf"; FAKE_STUCK=1 run "$t/limit" 80 >/dev/null 2>&1; rc=$?
  is "$rc" 1 "a driver that ignores the write is an error"
  [[ ! -e $conf ]] && ok "nothing saved when the write did not stick" || bad "saved a limit the SMC refused"
  for a in 50 abc; do run "$t/limit" $a >/dev/null 2>&1; is "$?" 2 "argument $a refused"; done
  FAKE_NOT_APPLE=1 run "$t/limit" 80 >/dev/null 2>&1; is "$?" 1 "refused off Apple Silicon"

  # 2. the udev restore script
  r() { echo 100 >"$b/charge_control_end_threshold"; [[ -n ${1:-} ]] && printf '%s\n' "$1" >"$conf" || rm -f "$conf"; run "$t/restore"; echo "$?/$(rd "$b/charge_control_end_threshold")"; }
  is "$(r CHARGE_CONTROL_END_THRESHOLD=80)" "0/80" "restore applies a saved 80"
  is "$(r CHARGE_CONTROL_END_THRESHOLD=100)" "0/100" "restore applies a saved 100"
  is "$(r CHARGE_CONTROL_END_THRESHOLD=55)" "0/100" "restore ignores a value other than 80 or 100"
  is "$(r 'CHARGE_CONTROL_END_THRESHOLD=80; reboot')" "0/100" "restore ignores a malformed value"
  is "$(r)" "0/100" "restore with no saved file leaves the SMC alone"
  echo 100 >"$b/charge_control_end_threshold"; printf 'CHARGE_CONTROL_END_THRESHOLD=80\n' >"$conf"; chmod a-w "$b/charge_control_end_threshold"
  run "$t/restore"; is "$?" 0 "restore never fails the udev event"; chmod u+w "$b/charge_control_end_threshold"
  echo 100 >"$b/charge_control_end_threshold"; FAKE_NOT_APPLE=1 run "$t/restore"
  is "$(rd "$b/charge_control_end_threshold")" 100 "restore does nothing off Apple Silicon"

  # 3. the udev rules: syntax, and the shape the dry run relies on
  rules=${OMARCHY_MAC_RULES:-/usr/lib/udev/rules.d}
  if [[ -r $rules/94-omarchy-mac-battery-charge-limit.rules ]]; then
    grep -q "RUN+=\"$lib/battery-charge-limit-restore\"" "$rules/94-omarchy-mac-battery-charge-limit.rules" && ok "rule 94 runs the restore script on add" || bad "rule 94 does not call $lib/battery-charge-limit-restore"
    grep -q 'ENV{CHARGE_CONTROL_END_THRESHOLD}=="\[0-9\]\[0-9\]"' "$rules/93-macsmc-battery-charge-control.rules" && ok "rule 93 matches two-digit values only (100 is left to the driver default)" || bad "rule 93 match changed"
    if udevadm verify --help >/dev/null 2>&1; then
      udevadm verify "$rules/93-macsmc-battery-charge-control.rules" "$rules/94-omarchy-mac-battery-charge-limit.rules" >/dev/null 2>&1 && ok "udevadm verify accepts both rules" || bad "udevadm verify rejects a rule"
    fi
  else echo "skip udev rules (not installed)"; fi
  echo 100 >"$b/charge_control_end_threshold"; echo 100 >"$b/charge_control_start_threshold"; rm -f "$conf"

  # 4. owner-run charge-limit test against the fake tree
  export K114S_SYSFS=$S K114S_CONF=$conf K114S_LIMIT_TOOL=$t/limit K114S_SETTLE=0 K114S_ALLOW_USER=1
  out=$(run "$hw/k114s-charge-limit-test.sh" status); [[ $out == *"end=100 start=100"* ]] && ok "owner test: status is read-only" || bad "owner test status: $out"
  [[ ! -e $conf ]] && ok "owner test: status wrote nothing" || bad "owner test status wrote the saved file"
  out=$(run "$hw/k114s-charge-limit-test.sh" run 2>&1); rc=$?
  [[ $rc -eq 0 && $out == *"RESULT: PASS"* && $out == *"limit 80 read back (end 80, start 75)"* ]] && ok "owner test: 80 read back, 100 restored" || bad "owner test run rc=$rc: $out"
  is "$(rd "$b/charge_control_end_threshold")/$(rd "$conf")" "100/" "owner test leaves 100 and no saved file (as found)"
  run "$t/limit" 80 >/dev/null 2>&1
  run "$hw/k114s-charge-limit-test.sh" run >/dev/null 2>&1
  is "$(rd "$b/charge_control_end_threshold")/$(rd "$conf")" "80/CHARGE_CONTROL_END_THRESHOLD=80" "owner test puts back a starting 80 and its saved file"
  run "$t/limit" 100 >/dev/null 2>&1; rm -f "$conf"
  out=$(FAKE_STUCK=1 run "$hw/k114s-charge-limit-test.sh" run 2>&1); rc=$?
  [[ $rc -eq 1 && $out == *"FAIL limit 80 read back"* ]] && ok "owner test: a refused write fails" || bad "owner test stuck rc=$rc: $out"
  echo 0 >"$ps/macsmc-ac/online"; run "$hw/k114s-charge-limit-test.sh" run >/dev/null 2>&1; is "$?" 2 "owner test refuses off AC"; echo 1 >"$ps/macsmc-ac/online"
  K114S_ALLOW_USER= run "$hw/k114s-charge-limit-test.sh" run >/dev/null 2>&1; is "$?" 2 "owner test refuses without root"
  unset K114S_ALLOW_USER K114S_LIMIT_TOOL K114S_CONF K114S_SETTLE

  # 5. power profile choice (#56): omarchy-powerprofiles-set autodetect against stub busctl and powerprofilesctl
  if [[ -x $bin/omarchy-powerprofiles-set && -x $bin/omarchy-powerprofiles-list ]]; then
    cat >"$t/stub/busctl" <<'STUB'
#!/bin/bash
[[ ${FAKE_ON_BATTERY:-0} == 1 ]] && echo "b true" || echo "b false"
STUB
    cat >"$t/stub/powerprofilesctl" <<STUB
#!/bin/bash
case \$1 in
  list) printf '  performance:\n    CpuDriver: cpufreq\n\n* balanced:\n    CpuDriver: cpufreq\n\n  power-saver:\n    CpuDriver: cpufreq\n' | { [[ \${FAKE_NO_PERF:-} == 1 ]] && grep -v performance || cat; } ;;
  set) echo "\$2" >"$t/profile" ;;
esac
STUB
    chmod +x "$t/stub/busctl" "$t/stub/powerprofilesctl"
    pp() { rm -rf "$t/state" "$t/profile"; [[ -n ${2:-} ]] && { mkdir -p "$t/state"; echo "$2" >"$t/state/${3:-ac}"; }
      OMARCHY_POWERPROFILES_STATE_DIR=$t/state FAKE_ON_BATTERY=$1 run "$bin/omarchy-powerprofiles-set" autodetect >/dev/null 2>&1; rd "$t/profile"; }
    is "$(pp 0)" performance "no saved choice on AC picks performance"
    is "$(pp 1)" balanced "no saved choice on battery picks balanced"
    is "$(pp 1 power-saver battery)" power-saver "a saved battery choice wins"
    is "$(pp 0 power-saver battery)" performance "a battery choice does not leak onto AC"
    is "$(FAKE_NO_PERF=1 pp 0)" balanced "AC without a performance profile falls back to balanced"
    is "$(pp 0 nonsense ac)" performance "an unknown saved profile is ignored"
  else echo "skip power profiles (not installed)"; fi
else echo "skip omarchy-mac charge-limit tests (scripts not installed)"; fi

# 6. battery, UPower and power-draw logger (#52, #56)
export K114S_SYSFS=$S
echo Charging >"$b/status"; echo 97 >"$b/capacity"
out=$(FAKE_UPOWER_STATE=discharging FAKE_UPOWER_PCT=92% run "$hw/k114s-battery-log.sh" 0 1 2>&1)
[[ $out == *"Charging 97 discharging 92 MISMATCH"* ]] && ok "logger flags the sysfs/UPower disagreement of #52" || bad "logger mismatch: $out"
out=$(FAKE_UPOWER_STATE=charging FAKE_UPOWER_PCT=97% run "$hw/k114s-battery-log.sh" 0 1 2>&1)
[[ $out == *"Charging 97 charging 97 ok"* ]] && ok "logger sees agreement" || bad "logger agree: $out"

# 7. plug-change probe (#57, #71)
mkdir -p "$S/class/typec/port0" "$S/class/typec/port1" "$ps/tps6598x-source-psy-1-0a"
for p in port0 port1; do echo default >"$S/class/typec/$p/power_operation_mode"; echo "source [sink]" >"$S/class/typec/$p/power_role"; echo "host [device]" >"$S/class/typec/$p/data_role"; done
echo 0 >"$ps/tps6598x-source-psy-1-0a/online"
( sleep 1; mkdir "$S/class/typec/port0/port0-partner"; echo usb_power_delivery >"$S/class/typec/port0/power_operation_mode" ) &
out=$(run "$hw/k114s-plug-probe.sh" 3 test 2>&1); wait
[[ $(grep -c ' ac=' <<<"$out") -eq 2 && $out == *"port0[partner=present mode=usb_power_delivery"* && $out == *"limit_W=59.8"* ]] && ok "probe prints a snapshot and one line per change" || bad "probe: $out"

# 8. fan and temperature logger (#55), and that it writes nothing
mkdir -p "$S/class/hwmon/hwmon3"; h=$S/class/hwmon/hwmon3
echo macsmc_hwmon >"$h/name"; echo 4100 >"$h/fan1_input"; echo 2000 >"$h/fan1_min"; echo 8400 >"$h/fan1_max"; echo 0 >"$h/fan1_target"
echo TAOC >"$h/temp1_label"; echo -127000 >"$h/temp1_input"; echo TCMb >"$h/temp2_label"; echo 71500 >"$h/temp2_input"
echo "Total System Power" >"$h/power1_label"; echo 25000000 >"$h/power1_input"
before=$(cd "$S" && find . -type f -exec sha256sum {} + | sort | sha256sum)
out=$(run "$hw/k114s-thermal-log.sh" 0 1 2>&1)
[[ $out == *"absent channels"*"TAOC(-127)"* && $out == *"4100(2000-8400)"* && $out == *"TCMb=71.5"* && $out == *"25.0W"* ]] && ok "thermal logger reads fan, hottest channel, absent TAOC" || bad "thermal: $out"
[[ $out != *"| TAOC"* ]] && ok "absent channel kept out of the hottest list" || bad "TAOC in the hottest list"
is "$(cd "$S" && find . -type f -exec sha256sum {} + | sort | sha256sum)" "$before" "the read-only loggers changed nothing in the fake tree"
nowrite=1
for f in k114s-battery-log k114s-plug-probe k114s-thermal-log; do grep -nE '(>|tee)[^|]*(/sys|\$sys|\$bat|\$h\b)' "$hw/$f.sh" | grep -vE '>/dev/null|2>&1|2>/dev/null' && { bad "$f.sh may write to sysfs"; nowrite=0; }; done
[[ $nowrite == 1 ]] && ok "no write redirect to sysfs in the three loggers"

[[ $fail -eq 0 ]] && echo "ALL PASS" || echo "SOME FAILED"
exit $fail
