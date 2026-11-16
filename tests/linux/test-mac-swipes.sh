#!/bin/bash
# linux/input/k114s-mac-swipes against a throw-away Hyprland folder: install, idempotence, backup, undo, check, the refusal of
# hand-written duplicates, and what the snippet registers (with a stand-in for Hyprland's Lua API, when lua is installed).
#   usage: test-mac-swipes.sh [LINUX_DIR]
set -u
. "$(dirname "$0")/r3-lib.sh" "${1:-}"
S=$L/input/k114s-mac-swipes; H=$BASE/hypr; mkdir -p "$H"; export K114S_HYPR_DIR=$H
M=$H/input.lua; printf -- '-- input\nhl.config({ input = { touchpad = { natural_scroll = true } } })\n-- hl.gesture({ fingers = 3, direction = "left", action = "workspace" })\n' > "$M"; orig=$(sum "$M")
bash -n "$S"; ok "the script parses" $? 0
bash "$S" --check >/dev/null 2>&1; ok "check before install fails" $? 1
out=$(bash "$S" 2>&1); ok "install exits 0 and --check passes (a commented-out gesture is not a duplicate)" "$? $(bash "$S" --check >/dev/null 2>&1; echo $?)" "0 0"
ok "the backup is the file as it was" "$(sum "$M.k114s-mac-swipes.bak")" "$orig"
ok "the original lines are still first" "$(head -n 3 "$M" | sha256sum | cut -c1-64)" "$(head -n 3 "$M.k114s-mac-swipes.bak" | sha256sum | cut -c1-64)"
s1=$(sum "$M"); bash "$S" >/dev/null 2>&1; ok "a second install changes nothing" "$(sum "$M") $(ls "$H" | wc -l)" "$s1 2"
sed -i 's/workspace = "r+1" })) end })$/workspace = "r-1" })) end })/' "$M"; bash "$S" --check >/dev/null 2>&1; ok "an edited block is not 'installed'" $? 1
bash "$S" >/dev/null 2>&1; ok "install replaces an edited block, one copy" "$(bash "$S" --check >/dev/null 2>&1; echo $?) $(grep -c 'k114s-mac-swipes begin' "$M")" "0 1"
bash "$S" --undo >/dev/null 2>&1; ok "undo restores the original bytes" "$(sum "$M")" "$orig"
out=$(bash "$S" --undo 2>&1); ok "undo twice is a no-op" "$? $(sum "$M")" "0 $orig"
printf 'hl.gesture({ fingers = 3, direction = "left", action = function() end })\n' >> "$M"; d=$(sum "$M")
out=$(bash "$S" 2>&1); ok "install refuses a hand-written 3-finger left gesture and changes nothing" "$? $(sum "$M") $(echo "$out" | grep -c 'outside the marked block')" "1 $d 1"
printf -- '-- input\n' > "$M"; printf 'hl.gesture({ direction = "right", fingers = 4, action = "fullscreen" })\n' >> "$M"; d=$(sum "$M")
out=$(bash "$S" 2>&1); ok "install refuses a clashing gesture written with direction before fingers" "$? $(sum "$M")" "1 $d"
printf -- "-- input\nhl.gesture({ fingers = 3, direction = 'left', action = 'workspace' })\n" > "$M"; d=$(sum "$M")
out=$(bash "$S" 2>&1); ok "install refuses a clashing gesture with a single-quoted direction (#160)" "$? $(sum "$M")" "1 $d"
printf -- '-- input\nhl.gesture({\n  fingers = 3,\n  direction = "horizontal",\n  action = "workspace",\n})\n' > "$M"; d=$(sum "$M")
out=$(bash "$S" 2>&1); ok "install refuses a clashing gesture spread over several lines (horizontal)" "$? $(sum "$M")" "1 $d"
printf -- '-- input\nhl.gesture({ fingers = 2, direction = "left", action = "workspace" })\nhl.gesture({ fingers = 3, direction = "up", action = "special" })\n' > "$M"
out=$(bash "$S" 2>&1); ok "install accepts gestures that do not clash (2 fingers left, 3 fingers up)" "$? $(bash "$S" --check >/dev/null 2>&1; echo $?)" "0 0"
bash "$S" --undo >/dev/null 2>&1
printf -- '-- input\n-- k114s-mac-swipes begin (half-deleted)\nkeep = 1\nhl.config({})\n' > "$M"; d=$(sum "$M")
out=$(bash "$S" 2>&1); r1=$?; out2=$(bash "$S" --undo 2>&1); r2=$?
ok "a begin line with no end line: install and undo refuse and the lines below it stay" "$r1 $r2 $(sum "$M") $(grep -c 'keep = 1' "$M")" "1 1 $d 1"
T=$BASE/dotfiles; mkdir -p "$T"; printf -- '-- input\n' > "$T/input.lua"; rm -f "$M" "$M.k114s-mac-swipes.bak"; ln -s "$T/input.lua" "$M"
out=$(bash "$S" 2>&1); ok "a symlinked input.lua stays a link and its target gets the block" "$? $(test -L "$M"; echo $?) $(grep -c 'k114s-mac-swipes begin' "$T/input.lua")" "0 0 1"
bash "$S" --undo >/dev/null 2>&1; ok "undo through the link too" "$(test -L "$M"; echo $?) $(grep -c 'k114s-mac-swipes begin' "$T/input.lua")" "0 0"
rm -f "$M"; bash "$S" >/dev/null 2>&1; ok "no input.lua: refuses, creates nothing" "$? $(test -e "$M"; echo $?)" "1 1"
bash "$S" --bogus >/dev/null 2>&1; ok "an unknown option fails" $? 1
if command -v lua >/dev/null; then
  r=$(lua -e 'hl = { gesture = function(t) local a = type(t.action) == "function" and "fn" or t.action; io.write(t.fingers, t.direction, ":", a, " ") end, dispatch = function() end, dsp = {} }' "$L/input/mac-swipes.lua" 2>&1)
  ok "snippet: unsets 3/4 left/right first, then sets the four swipes" "$r" "3left:unset 3right:unset 4left:unset 4right:unset 3left:fn 3right:fn 4left:fn 4right:fn "
  w=$(lua -e 'local got = {} hl = { gesture = function(t) if type(t.action) == "function" then t.action() end end, dispatch = function(x) io.write(x, " ") end, dsp = { focus = function(o) return "focus:" .. o.workspace end, window = { move = function(o) return "move:" .. o.workspace end } } }' "$L/input/mac-swipes.lua" 2>&1)
  ok "snippet: left is the next workspace, right the previous, for focus and for the window" "$w" "focus:r+1 focus:r-1 move:r+1 move:r-1 "
else echo "SKIPPED the snippet run (no lua here)"; fi
finish "mac swipes tests"
