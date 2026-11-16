#!/bin/bash
# linux/display/k114s-greeter-colour against a throw-away root: install, idempotence, check, a changed stock file, undo, refusals.
#   usage: test-greeter-colour.sh [LINUX_DIR]
set -u
. "$(dirname "$0")/r3-lib.sh" "${1:-}"
S=$L/display/k114s-greeter-colour; export K114S_SDDM_ROOT=$BASE/sddm
mkdir -p "$K114S_SDDM_ROOT/usr/share/sddm" "$K114S_SDDM_ROOT/etc/sddm.conf.d"
ST=$K114S_SDDM_ROOT/usr/share/sddm/hyprland.lua; MY=$K114S_SDDM_ROOT/etc/sddm/hyprland-k114s.lua; C=$K114S_SDDM_ROOT/etc/sddm.conf.d/70-k114s-greeter-software.conf
printf -- '-- stock greeter\nhl.config({ general = {} })\n' > "$ST"; stock=$(sum "$ST")
cp "$L/gpu-desktop/70-k114s-greeter-software.conf" "$C"; conf0=$(sum "$C")
bash -n "$S"; ok "the script parses" $? 0
bash "$S" --check >/dev/null 2>&1; ok "check before install fails" $? 1
out=$(bash "$S" 2>&1); ok "install exits 0 and --check passes" "$? $(bash "$S" --check >/dev/null 2>&1; echo $?)" "0 0"
ok "the copy is the stock file plus the guard" "$(head -n 2 "$MY" | sha256sum | cut -c1-64) $(grep -c 'cm_enabled = false' "$MY") $(grep -c 'ASAHI_M5_BRINGUP' "$MY")" "$(head -n 2 "$ST" | sha256sum | cut -c1-64) 1 1"
ok "the conf points at the copy only, and keeps its software-rendering variables" "$(grep -c -F -- '--config /etc/sddm/hyprland-k114s.lua' "$C") $(grep -c -F -- '--config /usr/share/sddm/hyprland.lua' "$C") $(grep -c 'LIBGL_ALWAYS_SOFTWARE=1' "$C")" "1 0 1"
ok "the backup is the conf as it was; the stock file is untouched" "$(sum "$C.k114s-greeter-colour.bak") $(sum "$ST")" "$conf0 $stock"
s1=$(sum "$C")$(sum "$MY"); bash "$S" >/dev/null 2>&1; ok "a second install changes nothing" "$(sum "$C")$(sum "$MY")" "$s1"
printf -- '-- stock greeter, new version\n' > "$ST"; bash "$S" --check >/dev/null 2>&1; ok "a changed stock file makes --check fail (the copy is stale)" $? 1
bash "$S" >/dev/null 2>&1; ok "install refreshes the copy from the new stock file" "$(bash "$S" --check >/dev/null 2>&1; echo $?) $(head -n 1 "$MY") $(grep -c ASAHI_M5_BRINGUP "$MY")" "0 -- stock greeter, new version 1"
printf -- '-- stock greeter\nhl.config({ general = {} })\n' > "$ST"; bash "$S" >/dev/null 2>&1
echo '-- hand edit' >> "$MY"; bash "$S" --check >/dev/null 2>&1; ok "an edited copy is not 'installed'" $? 1; bash "$S" >/dev/null 2>&1
sed -i 's#/etc/sddm/hyprland-k114s.lua#/usr/share/sddm/hyprland.lua#' "$C"; bash "$S" --check >/dev/null 2>&1; ok "a conf that no longer points at the copy is not 'installed'" $? 1
bash "$S" >/dev/null 2>&1; ok "install points it again" "$(bash "$S" --check >/dev/null 2>&1; echo $?)" 0
bash "$S" --undo >/dev/null 2>&1; ok "undo restores the conf bytes and removes the copy" "$(sum "$C") $(test -e "$MY"; echo $?)" "$conf0 1"
out=$(bash "$S" --undo 2>&1); ok "undo twice is a no-op" "$? $(sum "$C")" "0 $conf0"
rm "$C"; bash "$S" >/dev/null 2>&1; ok "no conf: refuses and creates nothing" "$? $(ls "$K114S_SDDM_ROOT/etc/sddm" 2>/dev/null | wc -l)" "1 0"
cp "$L/gpu-desktop/70-k114s-greeter-software.conf" "$C"; rm "$ST"; bash "$S" >/dev/null 2>&1; ok "no stock file: refuses, the conf is unchanged" "$? $(sum "$C")" "1 $conf0"
bash "$S" --bogus >/dev/null 2>&1; ok "an unknown option fails" $? 1
# the state the root left by hand on 2026-11-15: the copy (stock plus the exact guard) in place, the conf already pointed at it, no .bak
printf -- '-- stock greeter\nhl.config({ general = {} })\n' > "$ST"; rm -rf "$K114S_SDDM_ROOT/etc/sddm" "$C".*
mkdir -p "$K114S_SDDM_ROOT/etc/sddm"; { cat "$ST"; printf '\n-- K114s DCP boots: Hyprland colour management blanks the OLED (betizzel/omarchy-m5#21)\nif os.getenv("ASAHI_M5_BRINGUP") == "1" then hl.config({ render = { cm_enabled = false } }) end\n'; } > "$MY"
sed 's#--config /usr/share/sddm/hyprland.lua#--config /etc/sddm/hyprland-k114s.lua#' "$L/gpu-desktop/70-k114s-greeter-software.conf" > "$C"; hand=$(sum "$C")$(sum "$MY")
bash "$S" --check >/dev/null 2>&1; ok "hand-installed state: --check passes" $? 0
out=$(bash "$S" 2>&1); ok "hand-installed state: --install says already installed, changes no byte and makes no .bak" "$? $(echo "$out" | grep -c 'already installed') $(sum "$C")$(sum "$MY") $(ls "$C".* 2>/dev/null | wc -l)" "0 1 $hand 0"
bash "$S" --undo >/dev/null 2>&1; ok "hand-installed state: --undo points the conf back at the stock file and removes the copy" "$(grep -c -F -- '--config /usr/share/sddm/hyprland.lua' "$C") $(grep -c -F -- '--config /etc/sddm/hyprland-k114s.lua' "$C") $(test -e "$MY"; echo $?)" "1 0 1"
finish "greeter colour tests"
