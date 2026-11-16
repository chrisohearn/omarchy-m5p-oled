#!/bin/bash
# linux/display/k114s-dcp-colour against a throw-away Hyprland folder: install, idempotence, backup, undo, check, and that the snippet
# is a no-op unless ASAHI_M5_BRINGUP=1 (checked with a stand-in for Hyprland's Lua API, when lua is installed).
#   usage: test-dcp-colour.sh [LINUX_DIR]
set -u
. "$(dirname "$0")/r3-lib.sh" "${1:-}"
S=$L/display/k114s-dcp-colour; H=$BASE/hypr; mkdir -p "$H"; export K114S_HYPR_DIR=$H
M=$H/monitors.lua; printf -- '-- rules\nhl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 2 })\n' > "$M"; orig=$(sum "$M")
bash -n "$S"; ok "the script parses" $? 0
bash "$S" --check >/dev/null 2>&1; ok "check before install fails" $? 1
out=$(bash "$S" 2>&1); ok "install exits 0 and --check passes" "$? $(bash "$S" --check >/dev/null 2>&1; echo $?)" "0 0"
ok "the backup is the file as it was" "$(sum "$M.k114s-dcp-colour.bak")" "$orig"
ok "the original lines are still first" "$(head -n 2 "$M" | sha256sum | cut -c1-64) $(grep -c 'cm_enabled = true' "$M")" "$(head -n 2 "$M.k114s-dcp-colour.bak" | sha256sum | cut -c1-64) 1"
ok "the block sets the eDP-1 rule to hdredid with EDR, else dp3" "$(grep -c 'output = "eDP-1".*cm = hdr and "hdredid" or "dp3"' "$M")" 1
s1=$(sum "$M"); bash "$S" >/dev/null 2>&1; ok "a second install changes nothing" "$(sum "$M") $(ls "$H" | wc -l)" "$s1 2"
sed -i 's/cm_enabled = true/cm_enabled = false/' "$M"; bash "$S" --check >/dev/null 2>&1; ok "an edited block is not 'installed'" $? 1
bash "$S" >/dev/null 2>&1; ok "install replaces an edited block, one copy" "$(grep -c 'cm_enabled = true' "$M") $(grep -c 'cm_enabled = false' "$M") $(grep -c 'k114s-dcp-colour begin' "$M")" "1 0 1"
sed -i '/hl.monitor/s/or "dp3"/or "edid"/' "$M"; bash "$S" --check >/dev/null 2>&1; ok "a block with another cm preset is not 'installed'" $? 1
bash "$S" >/dev/null 2>&1; ok "install puts the hdredid/dp3 rule back, one copy" "$(grep -c 'hl.monitor.*or "dp3"' "$M") $(grep -c 'hl.monitor.*or "edid"' "$M")" "1 0"
bash "$S" --undo >/dev/null 2>&1; ok "undo restores the original bytes" "$(sum "$M")" "$orig"
out=$(bash "$S" --undo 2>&1); ok "undo twice is a no-op" "$? $(sum "$M")" "0 $orig"
printf -- '-- rules\n-- k114s-dcp-colour begin (half-deleted)\nkeep = 1\n' > "$M"; d=$(sum "$M")
out=$(bash "$S" 2>&1); r1=$?; out2=$(bash "$S" --undo 2>&1); r2=$?
ok "a begin line with no end line: install and undo refuse and the lines below it stay (#158)" "$r1 $r2 $(sum "$M") $(grep -c 'keep = 1' "$M")" "1 1 $d 1"
T=$BASE/dotfiles; mkdir -p "$T"; printf -- '-- rules\n' > "$T/monitors.lua"; rm -f "$M" "$M.k114s-dcp-colour.bak"; ln -s "$T/monitors.lua" "$M"
out=$(bash "$S" 2>&1); ok "a symlinked monitors.lua stays a link and its target gets the block (#158)" "$? $(test -L "$M"; echo $?) $(grep -c 'k114s-dcp-colour begin' "$T/monitors.lua")" "0 0 1"
bash "$S" --undo >/dev/null 2>&1; ok "undo through the link too" "$(test -L "$M"; echo $?) $(grep -c 'k114s-dcp-colour begin' "$T/monitors.lua")" "0 0"
rm "$M"; bash "$S" >/dev/null 2>&1; ok "no monitors.lua: refuses, creates nothing" "$? $(test -e "$M"; echo $?)" "1 1"
bash "$S" --bogus >/dev/null 2>&1; ok "an unknown option fails" $? 1
if command -v lua >/dev/null; then
  stub='hl = { config = function(t) print("cm=" .. tostring(t.render.cm_enabled)) end, monitor = function(t) print("mon=" .. t.output .. "/" .. t.cm) end }'
  run_snip() { ASAHI_M5_BRINGUP=$1 K114S_EDR_PARAM=$2 lua -e "$stub" "$L/display/dcp-colour.lua" 2>&1 | tr '\n' ' ' | sed 's/ $//'; }
  P=$BASE/edr-cap; rm -f "$P"
  for v in "" 0; do ok "snippet with ASAHI_M5_BRINGUP='$v' does nothing" "$(echo 1200 > "$P"; run_snip "$v" "$P")" ""; done
  ok "no EDR parameter (an older kernel): dp3" "$(rm -f "$P"; run_snip 1 "$P")" "cm=true mon=eDP-1/dp3"
  ok "the K114s default cap 500 (EDR off): dp3" "$(echo 500 > "$P"; run_snip 1 "$P")" "cm=true mon=eDP-1/dp3"
  ok "a cap of 1000 (not above the SDR maximum): dp3" "$(echo 1000 > "$P"; run_snip 1 "$P")" "cm=true mon=eDP-1/dp3"
  ok "the k114s-edr-cap cap 1200 (EDR on): hdredid" "$(echo 1200 > "$P"; run_snip 1 "$P")" "cm=true mon=eDP-1/hdredid"
  ok "cap 0 (the panel's own peak, EDR on): hdredid" "$(echo 0 > "$P"; run_snip 1 "$P")" "cm=true mon=eDP-1/hdredid"
  ok "an unreadable value: dp3" "$(echo x > "$P"; run_snip 1 "$P")" "cm=true mon=eDP-1/dp3"
else echo "SKIPPED the snippet run (no lua here)"; fi
finish "dcp colour tests"
