#!/bin/bash
# linux/display/k114s-cm-trial against a fake hyprctl and systemd-run: refusals, the revert scheduled before the trial,
# the Lua it sends, and the check after the revert. No Hyprland or systemd is touched.
#   usage: test-cm-trial.sh [LINUX_DIR]
set -u
. "$(dirname "$0")/r3-lib.sh" "${1:-}"
S=$L/display/k114s-cm-trial; F=$BASE/fake; mkdir -p "$F"; export FAKE=$F
cat > "$F/hyprctl" <<'SH'
#!/bin/bash
# state: $FAKE/cm (true|false) and $FAKE/preset; every call is logged to $FAKE/calls
echo "hyprctl $*" >> "$FAKE/calls"
case $1 in
  monitors) [ -e "$FAKE/ext" ] && { echo "Monitor DP-1 (ID 1):"; echo "	colorManagementPreset: $(cat "$FAKE/ext")"; }   # listed first
            [ -e "$FAKE/no-edp" ] || { echo "Monitor eDP-1 (ID 0):"; echo "	colorManagementPreset: $(cat "$FAKE/preset")"; } ;;
  getoption) echo "bool: $(cat "$FAKE/cm")" ;;
  eval) case $2 in *"cm_enabled = false"*) echo false > "$FAKE/cm" ;; *"cm_enabled = true"*) [ -e "$FAKE/cm-stuck" ] || echo true > "$FAKE/cm" ;; esac
        p=$(printf '%s' "$2" | grep -o 'cm = "[a-z0-9]*"' | head -1 | cut -d'"' -f2); [ -z "$p" ] || echo "$p" > "$FAKE/preset" ;;
esac
SH
cat > "$F/systemd-run" <<'SH'
#!/bin/bash
# logs its arguments; fails when $FAKE/srun-fails exists; otherwise runs the command after FAKE_DELAY seconds, in the background
printf 'systemd-run' >> "$FAKE/calls"; printf ' [%s]' "$@" >> "$FAKE/calls"; echo >> "$FAKE/calls"
[ -e "$FAKE/srun-fails" ] && exit 1
while [ $# -gt 0 ]; do case $1 in -E) shift 2 ;; -*) shift ;; *) break ;; esac; done
( sleep "${FAKE_DELAY:-1}"; "$@" ) >/dev/null 2>&1 &
echo $! >> "$FAKE/bg"
exit 0
SH
chmod +x "$F/hyprctl" "$F/systemd-run"
export K114S_HYPRCTL=$F/hyprctl K114S_SYSTEMD_RUN=$F/systemd-run HYPRLAND_INSTANCE_SIGNATURE=test XDG_RUNTIME_DIR=$BASE
reset() { rm -f "$F/calls" "$F/no-edp" "$F/srun-fails" "$F/ext" "$F/cm-stuck"; echo false > "$F/cm"; echo srgb > "$F/preset"; }
bash -n "$S"; ok "the script parses" $? 0
for bad in "" "hdr10" "dp3 3" "dp3 121" "dp3 2x"; do
  reset; bash "$S" $bad >/dev/null 2>&1; ok "refuses '$bad' and calls nothing" "$? $(test -e "$F/calls"; echo $?)" "1 1"
done
reset; touch "$F/no-edp"; bash "$S" dp3 >/dev/null 2>&1; ok "no eDP-1: refuses before scheduling anything" "$? $(grep -c '^systemd-run' "$F/calls")" "1 0"
reset; touch "$F/srun-fails"; bash "$S" dp3 >/dev/null 2>&1; ok "revert not scheduled: refuses and sends no eval" "$? $(grep -c 'hyprctl eval' "$F/calls") $(cat "$F/cm")" "1 0 false"
reset; out=$(FAKE_DELAY=1 K114S_CM_TRIAL_WAIT=3 bash "$S" dp3 20 2>&1); rc=$?
ok "a trial with the revert firing exits 0 and says reverted" "$rc $(echo "$out" | grep -c 'reverted: render:cm_enabled false, eDP-1 preset srgb')" "0 1"
first=$(grep -n -E '^(systemd-run|hyprctl eval)' "$F/calls" | head -1)
ok "the revert is scheduled before the trial command" "$(echo "$first" | grep -c systemd-run)" 1
ok "the revert runs after 20 s, to 100 ms, with the session's variables" "$(grep '^systemd-run' "$F/calls" | grep -c -F '[--on-active=20s] [--timer-property=AccuracySec=100ms] [-E] [XDG_RUNTIME_DIR=')" 1
ok "the revert turns cm off and sets eDP-1 back to srgb" "$(grep '^systemd-run' "$F/calls" | grep -c -F 'cm_enabled = false } }); hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 2, cm = "srgb" })')" 1
ok "the trial sets the eDP-1 preset and turns cm on" "$(grep -c -F 'hyprctl eval hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 2, cm = "dp3" }); hl.config({ render = { cm_enabled = true } })' "$F/calls")" 1
ok "after the revert the fake state is cm off, srgb" "$(cat "$F/cm") $(cat "$F/preset")" "false srgb"
reset; out=$(FAKE_DELAY=30 K114S_CM_TRIAL_WAIT=1 bash "$S" edid 2>&1); rc=$?
ok "a revert that has not happened is reported, exit 1" "$rc $(echo "$out" | grep -c 'REVERT NOT VERIFIED')" "1 1"
# an external output listed before eDP-1 does not decide the check: the eDP-1 block alone does (cm-stuck keeps cm off, so only the preset decides)
reset; echo srgb > "$F/ext"; touch "$F/cm-stuck"; out=$(FAKE_DELAY=30 K114S_CM_TRIAL_WAIT=1 bash "$S" dp3 2>&1); rc=$?
ok "an external srgb output first: eDP-1 still on dp3 is reported, exit 1" "$rc $(echo "$out" | grep -c 'REVERT NOT VERIFIED')" "1 1"
reset; echo dp3 > "$F/ext"; out=$(FAKE_DELAY=1 K114S_CM_TRIAL_WAIT=3 bash "$S" dp3 2>&1); rc=$?
ok "an external dp3 output first: eDP-1 back on srgb passes" "$rc $(echo "$out" | grep -c 'reverted:')" "0 1"
[ -s "$F/bg" ] && kill $(cat "$F/bg") 2>/dev/null   # the fakes' pending reverts
# the HDR presets of the watched EDR test (docs/r3-hdr.md section 8) run and revert like the others
for p in hdr hdredid; do
  reset; out=$(FAKE_DELAY=1 K114S_CM_TRIAL_WAIT=3 bash "$S" $p 20 2>&1); rc=$?
  ok "$p: accepted, set with cm on, and reverted to srgb" "$rc $(grep -c -F "cm = \"$p\" }); hl.config({ render = { cm_enabled = true } })" "$F/calls") $(echo "$out" | grep -c 'reverted:')" "0 1 1"
done
finish "colour-management trial tests"
