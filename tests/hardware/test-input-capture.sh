#!/bin/bash
# Software test of k114s-input-capture.sh against made-up /proc, /dev/input, logind and binds
# files. No hardware, no root, no real input device is opened.
set -u
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d) || exit 2
trap 'rm -rf "$t"' EXIT
fail=0
# every logind value is pinned so no test reads the real system
export K114S_SUSPEND_VALUE=ignore K114S_SUSPEND_LP_VALUE=ignore K114S_POWER_LP_VALUE=ignore
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
cap() { K114S_NO_SUDO=1 K114S_PROC_INPUT=$t/devices K114S_DEV_DIR=$t/dev K114S_BINDS_JSON=$t/binds.json K114S_HYPR_LUA_DIRS=$t/lua \
        K114S_LOGIND_VALUE=${LV:-ignore} K114S_LOGIND_DIRS="$t/ld" K114S_LEDS=$t/leds K114S_PWM_DT=$t/dt "$here/k114s-input-capture.sh" "$@" 2>&1; }

mkdir -p "$t/lua" "$t/dev" "$t/ld" "$t/leds" "$t/dt"
cat >"$t/devices" <<'D'
N: Name="Apple MTP multi-touch"
H: Handlers=event0
B: ABS=67f800001000003

N: Name="Apple MTP keyboard"
H: Handlers=sysrq kbd leds event1
B: KEY=10000 0 0 0 0 0

N: Name="Apple SMC power/lid events"
H: Handlers=kbd event2
B: KEY=10000000000000 0
D
echo '[{"key":"XF86AudioMute","modmask":0,"description":"Mute"},{"key":"XF86PowerOff","modmask":0,"description":"Power menu"}]' >"$t/binds.json"
# ev TYPE CODE VALUE -> one 24-byte input_event (aarch64/x86_64 layout)
ev() { python3 -I -c 'import struct,sys;sys.stdout.buffer.write(struct.pack("@llHHi",0,0,*map(int,sys.argv[1:])))' "$@"; }
{ ev 1 113 1; ev 1 113 0; ev 1 116 1; ev 1 29 1; ev 1 225 1; } >"$t/dev/event1"   # mute, ctrl+brightness up
{ ev 1 116 1; ev 1 116 0; } >"$t/dev/event2"
{ ev 3 47 0; ev 3 57 5; ev 3 47 1; ev 3 57 6; ev 3 48 900; ev 3 58 3000; ev 3 55 2; ev 1 272 1; } >"$t/dev/event0"

out=$(cap keys 2); rc=$?
[[ $rc -eq 0 && $out == *"SEEN     KEY_MUTE"* && $out == *"MISSING  KEY_VOLUMEDOWN"* && $out == *"KEY_BRIGHTNESSUP XF86MonBrightnessUp presses=1 (with Ctrl: 1)"* ]] && ok "keys: seen, missing and Ctrl chord" || { bad "keys (rc=$rc)"; echo "$out"; }
[[ $out == *"XF86AudioLowerVolume"*"NOT BOUND"* || $out == *"bind XF86AudioLowerVolume"*"NOT BOUND"* ]] && ok "keys: unbound key is reported" || bad "unbound key not reported"

out=$(cap power 2); rc=$?
[[ $rc -eq 0 && $out == *"SEEN     KEY_POWER XF86PowerOff presses=1"* && $out == *"POWER-KEY POLICY: ok"* ]] && ok "power: press seen, policy ok" || { bad "power (rc=$rc)"; echo "$out"; }

out=$(cap gestures 2); rc=$?
[[ $rc -eq 0 && $out == *"max simultaneous 2"* && $out == *"values seen: [2]"* && $out == *"max touch major 900"* && $out == *"BTN_LEFT click x1"* ]] && ok "gestures: contacts, tool type, size, click" || { bad "gestures (rc=$rc)"; echo "$out"; }

out=$(LV=suspend cap status); rc=$?
[[ $rc -eq 1 && $out == *"POWER-KEY POLICY: FAIL"* ]] && ok "policy fails when logind would suspend" || { bad "suspend policy (rc=$rc)"; echo "$out"; }

: >"$t/ld/50-aurora-sep.conf"
out=$(cap status); rc=$?
[[ $rc -eq 1 && $out == *"aurora-sep drop-in present"* && $out == *"POLICY: FAIL"* ]] && ok "policy fails when an aurora-sep drop-in is installed" || { bad "aurora-sep drop-in (rc=$rc)"; echo "$out"; }
rm "$t/ld/50-aurora-sep.conf"

rm "$t/dev/event2"; : >"$t/dev/event2"
out=$(cap power 1); [[ $out == *"MISSING  KEY_POWER"* ]] && ok "power: no press is MISSING" || bad "no-press case"

out=$(cap keys 1); [[ $out == *"the moon key"* && $out != *"Do NOT press the moon"* ]] && ok "keys prompt names the moon key by default" || bad "default keys prompt"
out=$(K114S_NO_MOON=1 cap keys 1); [[ $out == *"Do NOT press the moon key"* && $out != *"Ctrl+brightness down/up, the moon key"* ]] && ok "K114S_NO_MOON omits the moon key from the prompt" || { bad "no-moon prompt"; echo "$out"; }
out=$(cap keypolicy); rc=$?
[[ $rc -eq 0 && $out == *"KEY POLICY: ok"* ]] && ok "keypolicy ok when all are ignore" || { bad "keypolicy ok (rc=$rc)"; echo "$out"; }
out=$(K114S_SUSPEND_VALUE=suspend K114S_SUSPEND_LP_VALUE=ignore cap keypolicy); rc=$?
[[ $rc -eq 1 && $out == *"KEY POLICY: FAIL"* ]] && ok "keypolicy fails on HandleSuspendKey=suspend" || { bad "keypolicy suspend (rc=$rc)"; echo "$out"; }
out=$(K114S_SUSPEND_LP_VALUE=hibernate cap keypolicy); rc=$?
[[ $rc -eq 1 ]] && ok "keypolicy fails on a long-press hibernate" || bad "keypolicy long press (rc=$rc)"
out=$(LV=poweroff cap keypolicy); rc=$?
[[ $rc -eq 1 ]] && ok "keypolicy fails on HandlePowerKey=poweroff" || bad "keypolicy power key (rc=$rc)"
out=$(K114S_POWER_LP_VALUE=poweroff cap keypolicy); rc=$?
[[ $rc -eq 1 ]] && ok "keypolicy fails on HandlePowerKeyLongPress=poweroff" || bad "keypolicy power long press (rc=$rc)"
echo '[{"key":"XF86Sleep","modmask":0,"dispatcher":"exec","arg":"true"}]' >"$t/binds.json"
out=$(cap keypolicy); rc=$?
[[ $rc -eq 1 && $out == *"bind can suspend: XF86Sleep"* ]] && ok "keypolicy fails when Hyprland binds XF86Sleep" || { bad "XF86Sleep bind (rc=$rc)"; echo "$out"; }
echo '[{"key":"XF86PowerOff","modmask":0,"dispatcher":"exec","arg":"systemctl hibernate"}]' >"$t/binds.json"
out=$(cap keypolicy); rc=$?
[[ $rc -eq 1 && $out == *"bind can suspend: XF86PowerOff"* ]] && ok "keypolicy fails on a bind that runs hibernate" || { bad "hibernate bind (rc=$rc)"; echo "$out"; }
# real Hyprland 0.57 (Lua) shape: opaque numeric arg, keycode instead of key
echo '[{"key":"","keycode":150,"modmask":0,"dispatcher":"HL.Dispatcher(exec_cmd)","arg":"430"}]' >"$t/binds.json"
out=$(cap keypolicy); rc=$?
[[ $rc -eq 1 && $out == *"bind can suspend"* ]] && ok "keypolicy fails on a keycode-150 Lua bind" || { bad "keycode 150 (rc=$rc)"; echo "$out"; }
echo '[{"key":"F12","keycode":0,"modmask":0,"description":"Suspend now","dispatcher":"HL.Dispatcher(exec_cmd)","arg":"431"}]' >"$t/binds.json"
out=$(cap keypolicy); rc=$?
[[ $rc -eq 1 && $out == *"bind can suspend"* ]] && ok "keypolicy fails on a Lua bind whose description suspends" || { bad "description bind (rc=$rc)"; echo "$out"; }
echo '[{"key":"F12","keycode":0,"modmask":0,"description":"x","dispatcher":"HL.Dispatcher(exec_cmd)","arg":"432"}]' >"$t/binds.json"
echo 'hl.bind("F12", hl.dsp.exec_cmd("systemctl suspend"))' >"$t/lua/b.lua"
out=$(cap keypolicy); rc=$?
[[ $rc -eq 1 && $out == *"lua can suspend: b.lua:1"* ]] && ok "keypolicy fails when a Lua source runs suspend" || { bad "lua source (rc=$rc)"; echo "$out"; }
echo '-- systemctl suspend is not bound' >"$t/lua/b.lua"
out=$(cap keypolicy); rc=$?
[[ $rc -eq 0 ]] && ok "keypolicy ignores Lua comments" || { bad "lua comment (rc=$rc)"; echo "$out"; }
echo 'not json' >"$t/binds.json"
out=$(cap keypolicy); rc=$?
[[ $rc -eq 1 && $out == *"binds: unavailable"* ]] && ok "keypolicy fails when hyprctl gives no binds" || { bad "no binds (rc=$rc)"; echo "$out"; }
echo '[{"key":"XF86AudioMute","modmask":0,"description":"Mute"}]' >"$t/binds.json"
out=$(K114S_SUSPEND_VALUE=suspend cap keys 1); rc=$?
[[ $rc -eq 0 && $out == *"KEY POLICY: FAIL"* && $out == *"Do NOT press the moon key"* ]] && ok "keys run directly: a failed policy drops the moon key" || { bad "keys gate (rc=$rc)"; echo "$out"; }
out=$(cap keys 1); [[ $out == *"KEY POLICY: ok"* && $out == *"the moon key, Fn"* ]] && ok "keys run directly: a passing policy keeps the moon key" || { bad "keys gate ok"; echo "$out"; }

exit $fail
