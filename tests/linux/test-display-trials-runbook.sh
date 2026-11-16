#!/bin/bash
# The writing blocks of docs/r3-display-trials.md (W0, W1, block X, Xs, I0, I1, S, T1a, T2a, C1, C2, C4, D3), block P, and the
# checks of the trial boots (F, T1b, T1b-D1, T2b, D3b, A, C, C5), cut out
# of the runbook itself and run as a normal user against a fake ESP. sudo is a no-op wrapper, the system paths are rewritten
# to a throwaway folder, the real hashes are rewritten to the fake files' hashes, and the real linux/r3a-trial/k114s-boot-once
# does the checks and the arming. pacman, limine-entry-tool, the Limine hook and the Stage 2 hook are stand-ins that do what
# the installed ones were read to do. So this proves the order of the writes, the STOP paths and what the files hold
# afterwards, not that anything boots.
#   usage: test-display-trials-runbook.sh [LINUX_DIR]
set -u
. "$(dirname "$0")/r3-lib.sh" "${1:-}"
have flock b2sum iconv || { echo "display trials runbook tests: SKIPPED (flock, b2sum and iconv are needed)"; exit 0; }
DOC=$T/../../docs/r3-display-trials.md
. "$(dirname "$0")/display-fake-lib.sh"
D=$W/rec/display
bP=$(block '### Block P:' | rewrite); bW0=$(block '**W0.' | rewrite); bW1=$(block '**W1.' | rewrite); bX=$(block '**Block X:' | rewrite)
bI0=$(block '**I0.' | rewrite); bI1=$(block '**I1.' | rewrite); bS=$(block '### S.' | rewrite); bT1=$(block '**T1a.' | rewrite)
bT2=$(block '**T2a.' | rewrite); bC1=$(block '**C1.' | rewrite); bC2=$(block '**C2.' | rewrite); bC4=$(block '**C4.' | rewrite)
bD3=$(block '### D3 (conditional)' | rewrite); bXs=$(block '**Block Xs:' | rewrite); bF=$(block '**Block F:' | rewrite)
bT1b=$(block '**T1b.' | rewrite); bT1bD1=$(block '**T1b-D1.' | rewrite); bT2b=$(block '**T2b.' | rewrite); bD3b=$(block '**D3b.' | rewrite)
bA=$(block '**Block A:' | rewrite); bC=$(block '**Block C (' | rewrite); bC5=$(block '**C5.' | rewrite)
ok "every block is found and no real hash is left in it" \
  "$(for b in "$bP" "$bW0" "$bW1" "$bX" "$bI0" "$bI1" "$bS" "$bT1" "$bT2" "$bC1" "$bC2" "$bC4" "$bD3" "$bXs" "$bF" "$bT1b" "$bT1bD1" "$bT2b" "$bD3b" "$bA" "$bC" "$bC5"; do [ -n "$b" ] && echo y; done | wc -l) $(printf '%s' "$bP$bW0$bW1$bX$bXs$bI1$bS$bT1$bT2$bC$bC2$bD3$bT2b$bD3b" | grep -c -e "$GPU" -e "$AUR" -e "$R3A" -e "$PIN" -e "$OLD" -e "$GPIN")" "22 0"
setup() { # the session-0 steps up to the stage given: w0 w1 i0 i1 s
  fresh; gates; run <<< "$bW0"; [ "$1" = w0 ] && return; run <<< "$bW1"; [ "$1" = w1 ] && return
  run <<< "$bI0"; [ "$1" = i0 ] && return; run <<< "$bI1"; [ "$1" = i1 ] && return; run <<< "$bS"
}
gates() { mkdir -p "$D"; printf 'G0 confirmed: test\nG4 accepted: test\n' > "$D/gates.txt"; }

# --- block P, read-only, in the three window states -------------------------------------------------------------------
fresh; before=$(state); run <<< "$bP"; ok "P: holds on the promoted layout (window closed), changes nothing" "$rc $(echo "$out" | grep -c 'P: the proven configuration holds (window closed)') $(state)" "0 1 $before"
fresh; printf 'armed\nm1n1/x.bin\n' > "$W/esp/aura-try"; run <<< "$bP"; ok "P: an armed aura-try stops" "$rc" 1
fresh; printf '\n/Snapshots\n  //1\n' >> "$W/esp/limine.conf"; run <<< "$bP"; ok "P: an extra menu entry (Snapshots) stops" "$rc $(echo "$out" | grep -c 'a Snapshots entry')" "1 1"

# --- W0 and W1: the window opens; block X closes it byte for byte ---------------------------------------------------------
fresh; run <<< "$bW0"
ok "W0: exit 0, the record and copies in \$D" "$rc $(test -s "$D/before-window.txt"; echo $?) $(sum "$D/omarchy_linux-aurora.efi") $(cmp -s "$D/limine.conf.before-window" "$W/esp/limine.conf"; echo $?)" "0 0 $(sum "$W/fake/aurora.efi") 0"
ok "W0: the ESP is untouched" "$(test -e "$W/esp/EFI/Linux/omarchy_linux-aurora.efi"; echo $?) $(grep -c //linux-aurora "$W/esp/limine.conf")" "0 1"
ok "W0: the command line is never printed" "$(echo "$out" | grep -c 'root=UUID')" 0
before=$(state); run <<< "$bW0"; ok "W0: a second run stops, nothing changed" "$rc $(state)" "1 $before"
fresh; printf '  //Snapshots\n' >> "$W/esp/limine.conf"; run <<< "$bW0"; ok "W0: an extra entry stops, nothing written" "$rc $(test -e "$D"; echo $?)" "1 1"
fresh; run <<< "$bW0"; espb=$(espstate); run <<< "$bW1"
ok "W1: exit 0, DISPLAY WINDOW OPEN, the marker written" "$rc $(echo "$out" | grep -c 'W1: DISPLAY WINDOW OPEN: 8 lines') $(test -e "$D/window-open"; echo $?)" "0 1 0"
ok "W1: the linux-aurora image and entry are gone, r3a's stays" "$(test -e "$W/esp/EFI/Linux/omarchy_linux-aurora.efi"; echo $?) $(grep -c linux-aurora "$W/esp/limine.conf") $(grep -c -x '  //linux-k114s' "$W/esp/limine.conf")" "1 0 1"
ok "W1: the check resolves the path default to entry 2" "$(echo "$out" | grep -c 'ok    default_entry is Omarchy/linux-k114s (entry 2')" 1
ok "W1: the after-window copy is the live file" "$(cmp -s "$D/limine.conf.after-window" "$W/esp/limine.conf"; echo $?)" 0
run <<< "$bP"; ok "P: holds in the open window (no r3b)" "$rc $(echo "$out" | grep -c 'window open, r3b not installed')" "0 1"
run <<< "$bX"
ok "X: exit 0, the window marker gone" "$rc $(test -e "$D/window-open"; echo $?)" "0 1"
ok "X: the ESP is byte for byte as before W1" "$(espstate)" "$espb"
run <<< "$bX"; ok "X: a second run is a no-op" "$rc $(espstate)" "0 $espb"
fresh; run <<< "$bW0"; espb=$(espstate); FAKE_TOOL=extra run <<< "$bW1"
ok "W1: a removal that changes more than the entry stops" "$rc $(echo "$out" | grep -c 'changed more than the linux-aurora entry')" "1 1"
run <<< "$bX"; ok "X: then puts the ESP back byte for byte" "$rc $(espstate)" "0 $espb"
fresh; run <<< "$bW0"; FAKE_FREE=150000000 run <<< "$bW1"; ok "W1: less free space than expected stops" "$rc $(echo "$out" | grep -c 'less free space than expected')" "1 1"
fresh; run <<< "$bW0"; run <<< "$bW1"; echo '# rebuilt' >> "$W/esp/limine.conf"; before=$(state); run <<< "$bX"
ok "X: a limine.conf that is neither W0's nor W1's stops, nothing changed" "$rc $(state)" "1 $before"

# --- I0 and I1: what D1-D4 need, and r3b beside r3a -------------------------------------------------------------------------
fresh; run <<< "$bI0"; ok "I0: refused while the window is closed" "$rc $(test -e "$W/modprobe/aurora-m5-vrr.conf"; echo $?)" "1 1"
setup w1; run <<< "$bI0"
ok "I0: exit 0" "$rc $(echo "$out" | grep -c '^I0: ')" "0 1"
ok "I0: fw27_panel_vrr=0 in the /etc file of the same name" "$(grep -c -x 'options appledrm fw27_panel_vrr=0' "$W/modprobe/aurora-m5-vrr.conf")" 1
ok "I0: the brightness drop-in is the repository's file" "$(cmp -s "$REPO_DIR/linux/brightness/systemd/k114s-first-boot.conf" "$W/systemd/systemd-backlight@backlight:apple-panel-bl.service.d/k114s-first-boot.conf"; echo $?)" 0
ok "I0: one eDP-1 and one eDP-2 rule, scale 2, the old file kept" \
  "$(grep -c '"eDP-1".*scale = 2' "$W/home/.config/hypr/monitors.lua") $(grep -c '"eDP-2".*scale = 2' "$W/home/.config/hypr/monitors.lua") $(test -s "$W/home/.config/hypr/monitors.lua.bak.display-trials"; echo $?)" "1 1 0"
ok "I0: the r3b GPU-desktop opt-in" "$(test -e "$W/home/.config/k114s-gpu-desktop-r3b"; echo $?)" 0
before=$(state); run <<< "$bI0"; ok "I0: a second run stops (the file exists), nothing changed" "$rc $(state)" "1 $before"
setup i0; run <<< "$bI1"
ok "I1: exit 0, G3 and G6 pass" "$rc $(echo "$out" | grep -c '^I1: r3b installed beside r3a; G3 and G6 pass')" "0 1"
ok "I1: the r3b image and entry, the r3a ones unchanged, the default unchanged" \
  "$(test -s "$W/esp/EFI/Linux/omarchy_linux-k114s-r3b.efi"; echo $?) $(sum "$W/esp/EFI/Linux/omarchy_linux-k114s.efi") $(grep -c -x '  //linux-k114s-r3b' "$W/esp/limine.conf") $(sed -n 's/^default_entry: //p' "$W/esp/limine.conf")" \
  "0 $(sum "$W/fake/r3a.efi") 1 Omarchy/linux-k114s"
ok "I1: the package is kept in \$D, the install log is root-only there" "$(sum "$D/linux-k114s-r3b-7.3.0.r3b-1-aarch64.pkg.tar.zst") $(test -s "$D/install-r3b.log"; echo $?)" "$(sum "$W/fake/r3b.pkg") 0"
ok "I1: the command line is never printed" "$(echo "$out" | grep -c 'root=UUID')" 0
run <<< "$bP"; ok "P: holds with r3b installed" "$rc $(echo "$out" | grep -c 'window open, r3b installed')" "0 1"
setup i0; FAKE_HOOK=full run <<< "$bI1"; ok "I1: a hook that builds two images stops before any arm" "$rc $(echo "$out" | grep -c 'did not build exactly one image')" "1 1"
setup i0; FAKE_INITRD=appledrm run <<< "$bI1"; ok "I1: appledrm in r3b's initramfs stops (G6)" "$rc $(echo "$out" | grep -c 'appledrm is in r3b')" "1 1"
setup i0; FAKE_CHECK=FAILED run <<< "$bI1"; ok "I1: check-package that does not pass stops before the install" "$rc $(test -e "$W/state/r3b"; echo $?)" "1 1"
setup w0; run <<< "$bI1"; ok "I1: refused before W1" "$rc $(test -e "$W/state/r3b"; echo $?)" "1 1"

# --- S, T1a, T2a: the trial files and the two arms ------------------------------------------------------------------------
setup i1; run <<< "$bS"
ok "S: two trial files on the ESP, all three in \$D, each by hash" \
  "$rc $(sum "$W/esp/m1n1/boot-ctxr-disp-oldldr.bin") $(sum "$W/esp/m1n1/boot-ctxr-disp-pinldr.bin") $(test -e "$W/esp/m1n1/boot-ctxr-gpu-pinldr.bin"; echo $?) $(sum "$D/boot-ctxr-gpu-pinldr.bin")" \
  "0 $(sum "$W/fake/oldldr.bin") $(sum "$W/fake/pinldr.bin") 1 $(sum "$W/fake/gpinldr.bin")"
ok "S: no temporary file left on the ESP" "$(find "$W/esp" -name '*.k114s-new' | wc -l)" 0
setup s; rm "$D/gates.txt"; run <<< "$bT1"; ok "T1a: without the gates record nothing is armed" "$rc $(ls "$W/efivars" | grep -c LoaderEntryOneShot) $(sed -n 1p "$W/esp/aura-try")" "1 0 spent"
setup s; printf 'G0 confirmed: x\n' > "$D/gates.txt"; run <<< "$bT1"; ok "T1a: without G4 accepted nothing is armed" "$rc $(ls "$W/efivars" | grep -c LoaderEntryOneShot)" "1 0"
setup s; run <<< "$bT1"
ok "T1a: exit 0, the one-shot names r3b, aura-try armed for the T1 file, the reboot called" \
  "$rc $(tail -c +5 "$W/efivars/LoaderEntryOneShot-$BLI" | iconv -f UTF-16LE -t UTF-8 | tr -d '\0') $(sed -n 1,2p "$W/esp/aura-try" | tr '\n' ' ')$(grep -c '^reboot' "$W/calls")" \
  "0 Omarchy.linux-k114s-r3b armed m1n1/boot-ctxr-disp-oldldr.bin 1"
ok "T1a: the configured Stage 2 and default_entry are untouched" "$(sum "$W/esp/m1n1/boot-ctxr.bin") $(sed -n 's/^default_entry: //p' "$W/esp/limine.conf")" "$(sum "$W/fake/gpu.bin") Omarchy/linux-k114s"
before=$(espstate); run <<< "$bT1"; ok "T1a: a second arm while aura-try is armed stops (the arm refuses), aura-try unchanged" "$rc $(sed -n 1p "$W/esp/aura-try")" "1 armed"
setup s; printf '' > "$W/esp/m1n1/boot-ctxr-disp-oldldr.bin"; run <<< "$bT1"; ok "T1a: a T1 file that is not the built one stops, nothing armed" "$rc $(ls "$W/efivars" | grep -c LoaderEntryOneShot)" "1 0"
setup s; FAKE_UNAME=$REL run <<< "$bT1"; ok "T1a: refused from a boot that is not r3a on P" "$rc" 1
# the T1 boot: Limine took the request, the loader spent aura-try
t1boot() { rm -f "$W/efivars/LoaderEntryOneShot-$BLI"; : > "$W/esp/ubootefi.var"; printf 'spent\nm1n1/boot-ctxr-disp-oldldr.bin\n' > "$W/esp/aura-try"; }
setup s; run <<< "$bT1"; t1boot; FAKE_UNAME=$REL run <<< "$bT2"; ok "T2a: without T1-passed nothing is armed" "$rc $(ls "$W/efivars" | grep -c LoaderEntryOneShot)" "1 0"
echo "T1 passed" > "$D/T1-passed"; sed -i '/eDP-2/d' "$W/home/.config/hypr/monitors.lua"; FAKE_UNAME=$REL run <<< "$bT2"
ok "T2a: without the eDP-2 rule nothing is armed" "$rc $(echo "$out" | grep -c 'eDP-1 and eDP-2 rules')" "1 1"
cp "$W/home/.config/hypr/monitors.lua.bak.display-trials" "$W/home/.config/hypr/monitors.lua"; run <<< "$bI0" >/dev/null 2>&1
printf 'hl.monitor({ output = "eDP-2", mode = "preferred", position = "auto", scale = 2 })\n' >> "$W/home/.config/hypr/monitors.lua"
FAKE_UNAME=$REL run <<< "$bT2"
ok "T2a: from the T1 boot, exit 0, the one-shot names r3b, aura-try armed for the hand-off file" \
  "$rc $(tail -c +5 "$W/efivars/LoaderEntryOneShot-$BLI" | iconv -f UTF-16LE -t UTF-8 | tr -d '\0') $(sed -n 1,2p "$W/esp/aura-try" | tr '\n' ' ')" \
  "0 Omarchy.linux-k114s-r3b armed m1n1/boot-ctxr-disp-pinldr.bin "
setup s; run <<< "$bT1"; t1boot; echo "T1 passed" > "$D/T1-passed"; rm -r "$W/systemd/systemd-backlight@backlight:apple-panel-bl.service.d"; FAKE_UNAME=$REL run <<< "$bT2"
ok "T2a: without the brightness drop-in nothing is armed (E7)" "$rc $(echo "$out" | grep -c 'brightness drop-in is not installed') $(ls "$W/efivars" | grep -c LoaderEntryOneShot)" "1 1 0"

# --- D3 (conditional) ------------------------------------------------------------------------------------------------------
setup s; run <<< "$bD3"
ok "D3: the loader-only file goes on the ESP by hash and the arm names it" "$rc $(sum "$W/esp/m1n1/boot-ctxr-gpu-pinldr.bin") $(sed -n 2p "$W/esp/aura-try")" "0 $(sum "$W/fake/gpinldr.bin") m1n1/boot-ctxr-gpu-pinldr.bin"

# --- the close: C1, C2, X, C4 ----------------------------------------------------------------------------------------------
close_from() { setup s; espb0=$(cat "$D/before-window.txt" | sha256sum); run <<< "$bT1"; t1boot; echo ok > "$D/T1-passed"; FAKE_UNAME=$REL run <<< "$bT2"
  rm -f "$W/efivars/LoaderEntryOneShot-$BLI"; : > "$W/esp/ubootefi.var"; printf 'spent\nm1n1/boot-ctxr-disp-pinldr.bin\n' > "$W/esp/aura-try"
  rm -f "$W/state/sync-stopped"; FAKE_REPO=$W/repo run <<< "$bC"; }   # boot 3: the reboot started the snapshot sync again; block C stops it
close_from
ok "C: boot 3's first block passes and holds the snapshot sync off again" "$rc $(echo "$out" | grep -c '^C: a clean default boot') $(test -e "$W/state/sync-stopped"; echo $?)" "0 1 0"
run <<< "$bC4"; ok "C4: refused while the window is open" "$rc" 1
run <<< "$bC1"; ok "C1: exit 0, the trial files are off the ESP, their copies stay" "$rc $(ls "$W/esp/m1n1" | grep -c disp) $(test -s "$D/boot-ctxr-disp-pinldr.bin"; echo $?)" "0 0 0"
run <<< "$bC2"; ok "C2: exit 0, r3b removed, limine.conf is W1's file" "$rc $(test -e "$W/state/r3b"; echo $?) $(test -e "$W/esp/EFI/Linux/omarchy_linux-k114s-r3b.efi"; echo $?) $(cmp -s "$W/esp/limine.conf" "$D/limine.conf.after-window"; echo $?)" "0 1 1 0"
run <<< "$bX"; ok "X (C3): exit 0" "$rc" 0
run <<< "$bC4"
ok "C4: no boot file changed, DISPLAY WINDOW CLOSED" "$rc $(echo "$out" | grep -c 'no boot file changed') $(echo "$out" | grep -c 'C4: DISPLAY WINDOW CLOSED')" "0 1 1"
ok "C4: starts the snapshot sync again and drops the hold marker" "$(test -e "$W/state/sync-stopped"; echo $?) $(test -e "$D/sync-held"; echo $?) $(test -s "$D/sync-restarted"; echo $?)" "1 1 0"
run <<< "$bC5"; ok "C5: no sync run yet stops (run it again later)" "$rc $(echo "$out" | grep -c 'no sync run since C4 yet')" "1 1"
printf 'Boot usage limit reached: x\nStopping boot entry creation: Boot partition usage from 78.8%% to 109.3%% (+152.3 MiB) will exceed the 85.0%% limit.\nUpdated: %s/esp/limine.conf\n' "$W" > "$W/since"
FAKE_SINCE=$W/since run <<< "$bC5"; ok "C5: after the sync's run, limine.conf is as before the window" "$rc $(echo "$out" | grep -c '^C5: the snapshot sync ran (1)')" "0 1"
cp -p "$W/esp/limine.conf" "$W/lc"; echo '# rewritten' >> "$W/esp/limine.conf"; FAKE_SINCE=$W/since run <<< "$bC5"; ok "C5: a run that changed limine.conf stops" "$rc $(echo "$out" | grep -c 'changed limine.conf')" "1 1"; mv "$W/lc" "$W/esp/limine.conf"
ok "after the close: the aurora image, limine.conf and the configured Stage 2 are as before the window" \
  "$(sum "$W/esp/EFI/Linux/omarchy_linux-aurora.efi") $(cmp -s "$W/esp/limine.conf" "$D/limine.conf.before-window"; echo $?) $(sum "$W/esp/m1n1/boot-ctxr.bin")" \
  "$(sum "$W/fake/aurora.efi") 0 $(sum "$W/fake/gpu.bin")"
run <<< "$bP"; ok "P: holds again with the window closed" "$rc $(echo "$out" | grep -c 'window closed')" "0 1"
close_from; run <<< "$bX"; ok "X: refused while r3b is installed" "$rc $(echo "$out" | grep -c 'step C2 first')" "1 1"
close_from; echo changed >> "$W/esp/m1n1/boot-ctxr-disp-oldldr.bin"; run <<< "$bC1"
ok "C1: a trial file that differs from its copy stays on the ESP" "$rc $(test -e "$W/esp/m1n1/boot-ctxr-disp-oldldr.bin"; echo $?)" "1 0"
close_from; run <<< "$bC1"; FAKE_UNAME=$REL run <<< "$bC2"; ok "C2: refused from the r3b boot itself" "$rc $(test -e "$W/state/r3b"; echo $?)" "1 0"
close_from; run <<< "$bC1"; rm -f "$W/state/sync-stopped"; run <<< "$bC2"; ok "C2: refused while the snapshot sync runs, r3b stays" "$rc $(test -e "$W/state/r3b"; echo $?) $(echo "$out" | grep -c 'snapshot sync runs')" "1 0 1"
close_from; run <<< "$bC1"; run <<< "$bC2"; run <<< "$bX"; echo x >> "$W/lib/k114s.dtb"; run <<< "$bC4"
ok "C4: a boot file that changed during the window stops the close" "$rc $(echo "$out" | grep -c 'differs from the record')" "1 1"

# --- the snapshot sync is held off from W0 to C4 (E12), and block Xs undoes a Snapshots entry -------------------------------
H=$W/esp/00000000000000000000000000000000/limine_history
fresh; run <<< "$bW0"
ok "W0: stops both sync units and records the hold and limine_history" \
  "$rc $(grep -c -x 'stop snapper-cleanup.timer limine-snapper-sync.service' "$W/calls") $(test -e "$W/state/sync-stopped"; echo $?) $(test -e "$D/sync-held"; echo $?) $(diff -r -q "$D/limine_history.before-window" "$H" >/dev/null; echo $?)" "0 1 0 0 0"
rm "$W/state/sync-stopped"; before=$(state); run <<< "$bW1"; ok "W1: refused while the sync runs (a reboot since W0), nothing changed" "$rc $(state) $(echo "$out" | grep -c 'snapshot sync runs')" "1 $before 1"
run <<< "$bP"; ok "P: the sync running while it is held stops" "$rc $(echo "$out" | grep -c 'snapshot sync runs in the window')" "1 1"
: > "$W/state/sync-stopped"; head -c 300 /dev/urandom > "$H/k.efi"; run <<< "$bP"; ok "P: an image copy in limine_history stops" "$rc $(echo "$out" | grep -c 'limine_history changed')" "1 1"
fresh; run <<< "$bW0"; espb=$(espstate); FAKE_TOOL=fail run <<< "$bW1"
ok "W1: a failing tool still leaves the after-window copy first, and says block X" "$rc $(test -s "$D/limine.conf.after-window"; echo $?) $(echo "$out" | grep -c 'limine-entry-tool failed')" "1 0 1"
run <<< "$bX"; ok "X: then puts the ESP back byte for byte" "$rc $(espstate)" "0 $espb"
snap() { printf '  //Snapshots\n  comment: added by limine-snapper-sync\n    ///4 | 2026-11-15\n    protocol: efi\n    path: boot():/00000000000000000000000000000000/limine_history/x.efi\n\n' >> "$W/esp/limine.conf"
  head -c 300 /dev/urandom > "$H/x.efi"; }
setup w1; espw=$(espstate); snap; before=$(state); run <<< "$bX"; ok "X: a Snapshots entry stops it and names block Xs, nothing changed" "$rc $(echo "$out" | grep -c 'block Xs first') $(state)" "1 1 $before"
run <<< "$bXs"; ok "Xs: limine.conf is W1's file again, the copy is gone, the ESP as after W1" "$rc $(cmp -s "$W/esp/limine.conf" "$D/limine.conf.after-window"; echo $?) $(test -e "$H/x.efi"; echo $?) $(espstate)" "0 0 1 $espw"
run <<< "$bX"; run <<< "$bC4"; ok "X then C4 close the window after Xs" "$rc $(echo "$out" | grep -c 'C4: DISPLAY WINDOW CLOSED')" "0 1"
setup w1; snap; sed -i 's/^timeout: 5/timeout: 3/' "$W/esp/limine.conf"; before=$(state); run <<< "$bXs"; ok "Xs: more than a Snapshots tree changed: stops, nothing changed" "$rc $(state)" "1 $before"
setup w1; snap; rm "$W/state/sync-stopped"; before=$(state); run <<< "$bXs"; ok "Xs: refused while the sync runs" "$rc $(state)" "1 $before"
setup s; espb=$(espstate); snap; run <<< "$bXs"; ok "Xs: with r3b installed, limine.conf is I1's file again" "$rc $(cmp -s "$W/esp/limine.conf" "$D/limine.conf.after-r3b"; echo $?) $(espstate)" "0 0 $espb"
setup w1; run <<< "$bXs"; ok "Xs: no Snapshots entry: not its case, refused" "$rc $(echo "$out" | grep -c 'not this block')" "1 1"

# --- the checks of the trial boots: F, T1b, T1b-D1, T2b, D3b (fake hardware checks that log their --expect) ------------------
boot() { # boot RELEASE TRIAL ENTRY: what a reboot leaves; the snapshot sync is back until block F
  export FAKE_UNAME=$1; rm -f "$W/efivars/LoaderEntryOneShot-$BLI" "$W/state/sync-stopped"; : > "$W/esp/ubootefi.var"
  { printf '\007\000\000\000'; printf '%s' "$3" | iconv -t UTF-16LE; printf '\000\000'; } > "$W/efivars/LoaderEntrySelected-$BLI"
  if [ -n "$2" ]; then printf '%s\0' "$2" > "$W/chosen/aurora,trial"; sed -i 1s/.*/spent/ "$W/esp/aura-try"; else rm -f "$W/chosen/aurora,trial"; fi
  echo "boot-$RANDOM$RANDOM" > "$W/boot_id"; }
FR=$W/repo
setup s; run <<< "$bT1"; boot $REL m1n1/boot-ctxr-disp-oldldr.bin Omarchy.linux-k114s-r3b
FAKE_REPO=$FR run <<< "$bT1b"; ok "T1b: refused before block F has run in this boot" "$rc $(echo "$out" | grep -c 'block F has not run in this boot')" "1 1"
run <<< "$bF"; o=$(cat "$D/last-boot")
ok "F: the logs carry this boot's id, the folder is named for the trial, the sync is held off again" \
  "$rc $(cat "$o/boot_id") ${o##*-disp-} $(test -e "$W/state/sync-stopped"; echo $?)" "0 $(cat "$W/boot_id") oldldr 0"
: > "$W/calls"; FAKE_REPO=$FR run <<< "$bT1b"; ok "T1b: passes after F, with --expect refused" "$rc $(grep -c 'display-check --expect refused' "$W/calls") $(echo "$out" | grep -c '^T1b: ')" "0 1 1"
FAKE_REPO=$FR run <<< "$bT1bD1"; ok "T1b-D1: refused on the T1 trial boot" "$rc $(echo "$out" | grep -c 'not r3b on P')" "1 1"
FAKE_REPO=$FR FAKE_DCHECK=BAD run <<< "$bT1b"; ok "T1b: a BAD from the display check stops" "$rc" 1
boot $REL "" Omarchy.linux-k114s-r3b; run <<< "$bF"; : > "$W/calls"; FAKE_REPO=$FR run <<< "$bT1bD1"
ok "T1b-D1: on r3b on P after F (folder -configured), passes with --expect none" "$rc $(grep -c 'display-check --expect none' "$W/calls") $(echo "$out" | grep -c '^T1b-D1: ')" "0 1 1"
FAKE_REPO=$FR run <<< "$bT1b"; ok "T1b: on r3b on P stops and names T1b-D1" "$rc $(echo "$out" | grep -c 'run T1b-D1 instead')" "1 1"
echo boot-later > "$W/boot_id"; FAKE_REPO=$FR run <<< "$bT1bD1"; ok "T1b-D1: the logs of an earlier boot are refused" "$rc $(echo "$out" | grep -c 'block F has not run in this boot')" "1 1"
setup s; run <<< "$bT1"; boot $REL m1n1/boot-ctxr-disp-oldldr.bin Omarchy.linux-k114s-r3b; echo ok > "$D/T1-passed"
run <<< "$bT2"; ok "T2a: refused in a boot whose sync was not stopped (no block F yet)" "$rc $(echo "$out" | grep -c 'snapshot sync runs') $(sed -n 1p "$W/esp/aura-try")" "1 1 spent"
run <<< "$bF"; run <<< "$bT2"; ok "T2a: arms after block F" "$rc" 0
boot $REL m1n1/boot-ctxr-disp-pinldr.bin Omarchy.linux-k114s-r3b; run <<< "$bF"; : > "$W/calls"; FAKE_REPO=$FR run <<< "$bT2b"
ok "T2b: passes with --expect published, and finds T1's loader log to compare" "$rc $(grep -c 'display-check --expect published' "$W/calls") $(echo "$out" | grep -c "ok    the loader's GPU lines equal T1's")" "0 1 1"
boot $REL "" Omarchy.linux-k114s-r3b; run <<< "$bF"; run <<< "$bD3"; ok "D3: armed from r3b on P" "$rc $(sed -n 1,2p "$W/esp/aura-try" | tr '\n' ' ')" "0 armed m1n1/boot-ctxr-gpu-pinldr.bin "
boot $REL m1n1/boot-ctxr-gpu-pinldr.bin Omarchy.linux-k114s-r3b; run <<< "$bF"; : > "$W/calls"; FAKE_REPO=$FR run <<< "$bD3b"
ok "D3b: on the gpu-pinldr boot after F, passes with --expect none and equal GPU lines" "$rc $(grep -c 'display-check --expect none' "$W/calls") $(echo "$out" | grep -c '^D3b: ')" "0 1 1"
FAKE_REPO=$FR run <<< "$bT1bD1"; ok "T1b-D1: refused on the D3 boot" "$rc" 1
FAKE_REPO=$FR run <<< "$bT2b"; ok "T2b: refused on the D3 boot" "$rc" 1
printf '[0.1] FDT: GPU: firmware other\n' > "$W/mtd1ro"; boot $REL m1n1/boot-ctxr-gpu-pinldr.bin Omarchy.linux-k114s-r3b; run <<< "$bF"; FAKE_REPO=$FR run <<< "$bD3b"
ok "D3b: GPU lines that differ from the installed loader's stop" "$rc $(echo "$out" | grep -c "GPU lines differ")" "1 1"
setup s; run <<< "$bT1"; boot $REL m1n1/boot-ctxr-disp-oldldr.bin Omarchy.linux-k114s-r3b; printf '  //Snapshots\n' >> "$W/esp/limine.conf"; run <<< "$bF"
ok "F: a Snapshots entry added before it ran stops and names Xs (the logs are saved first)" "$rc $(echo "$out" | grep -c 'block Xs') $(test -s "$(cat "$D/last-boot")/loader.log"; echo $?)" "1 1 0"

# --- the T1 folder lookup runs as root: $D is root-only, so a plain ls never sees into it (a sudo that really changes access) ----
if [ "$(id -u)" != 0 ]; then
  sf=$W/sf; rm -rf "$sf"; mkdir -p "$sf/boot-20261115-000000-disp-oldldr"; chmod 000 "$sf"
  look() { D=$sf bash -c 'sudo() { chmod 700 "$D"; "$@"; r=$?; chmod 000 "$D"; return $r; }; '"$1"'; echo "${t1##*/}"'; }
  r=; for b in "$bT2b" "$bD3b"; do r="$r $(look "$(printf '%s\n' "$b" | grep '^    t1=')")"; done
  ok "T2b and D3b find T1's folder in a root-only \$D" "$r" " boot-20261115-000000-disp-oldldr boot-20261115-000000-disp-oldldr"
  ok "control: the draft's plain ls finds nothing there" "$(look 't1=$(ls -d "$D"/boot-*-disp-oldldr 2>/dev/null | tail -1)')" ""
  chmod 700 "$sf"
fi

# --- block A: only a display-path failure logged after the root mount lets T2's failure skip D3 -------------------------------
fresh; gates; jA=$W/jA; mk() { printf '%s\n' "$@" > "$jA"; }
L0='[    0.390665] archlinux kernel: Linux version 7.3.0-17.v272-11-k114s-r3b-ARCH (x)'; SW='[    4.747905] archlinux systemd[1]: Switching root.'
mk "$L0" "$SW" '[    9.100000] omarchy-mac kernel: apple-dcp 48ae00000.dcp: RTKit: crashed' '[    9.2] omarchy-mac kernel: Kernel command line: secret'
FAKE_JOURNAL=$jA run <<< "$bA"; ok "A: a DCP crash after Switching root: the hand-off, no D3, the lines kept" "$rc $(echo "$out" | grep -c '^A: ') $(test -s "$D/T2-display-failure.txt"; echo $?) $(echo "$out" | grep -c secret)" "0 1 0 0"
: > "$jA"; FAKE_JOURNAL=$jA run <<< "$bA"; ok "A: no T2 journal: D3" "$rc $(echo "$out" | grep -c 'run D3')" "1 1"
mk "$L0" '[    1.000000] archlinux kernel: apple-dcp 48ae00000.dcp: RTKit: crashed'; FAKE_JOURNAL=$jA run <<< "$bA"; ok "A: a journal that ends before the root mount: D3" "$rc $(echo "$out" | grep -c 'before the root mount')" "1 1"
mk "$L0" '[    1.000000] archlinux kernel: apple-dcp 48ae00000.dcp: RTKit: crashed' "$SW"; FAKE_JOURNAL=$jA run <<< "$bA"; ok "A: a DCP line before the root mount only: D3" "$rc $(echo "$out" | grep -c 'run D3')" "1 1"
mk "$L0" "$SW" '[    9.1] omarchy-mac kernel: nvme 0: I/O timeout'; FAKE_JOURNAL=$jA run <<< "$bA"; ok "A: a failure off the display path: D3" "$rc $(echo "$out" | grep -c 'run D3')" "1 1"
FAKE_UNAME=$REL FAKE_JOURNAL=$jA run <<< "$bA"; ok "A: refused on an r3b boot" "$rc" 1

# --- every block of the runbook parses, and each one that writes starts with the findmnt guard and is a subshell -------------
n=0; bad=; while IFS= read -r -d '' b; do n=$((n+1)); bash -n <<< "$b" 2>/dev/null || bad="$bad $n"
  printf '%s' "$b" | grep -q -E 'sudo (cp|mv|rm|install|tee|sh|flock|systemctl|limine|mkdir|pacman|touch|\$K arm)' && ! printf '%s' "$b" | grep -q '^findmnt /boot/efi' && bad="$bad $n(no-guard)"
  printf '%s' "$b" | grep -q 'STOP' && ! printf '%s' "$b" | grep -q 'exit 1' && bad="$bad $n(stop-without-exit)"; done < <(
  awk '$0 == "    (" { c = 1; b = ""; next } c && $0 == "    )" { printf "%s%c", b, 0; c = 0; next } c { b = b substr($0, 5) "\n" }' "$DOC")
ok "all $n blocks of the runbook parse with bash -n, every writing block has the findmnt guard, every STOP exits 1" "${bad:-none} $((n >= 20))" "none 1"
ok "no block prints a limine.conf line that could hold the command line" \
  "$(awk '$0 == "    (" { c = 1; next } c && $0 == "    )" { c = 0 } c' "$DOC" | grep -E "grep[^|]*limine\.conf|grep[^|]*\\\$c( |\$)" | grep -v -E 'grep -(c|q)|grep -[a-zA-Z]*[cq][a-zA-Z]* |default_entry|\^\[\[:blank:\]\]\*/|\^\[\[:blank:\]\]\*path:|path: boot|cmp ' | wc -l)" 0
finish "display trials runbook tests"
