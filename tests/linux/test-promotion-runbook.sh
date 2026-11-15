#!/bin/bash
# The blocks of steps P0e, P1, P2 and P5 of docs/r3a-promotion.md and their undos, cut out of the runbook itself and run as a
# normal user against a fake ESP. sudo is a no-op wrapper, the system paths are rewritten to a throwaway folder, the
# real hashes are rewritten to the fake files' hashes, and the real linux/r3a-trial/k114s-boot-once does the checks.
# So this proves the order of the writes, the STOP paths and what the files hold afterwards, not that anything boots.
#   usage: test-promotion-runbook.sh [LINUX_DIR]
set -u
. "$(dirname "$0")/r3-lib.sh" "${1:-}"
have flock b2sum || { echo "promotion runbook tests: SKIPPED (flock and b2sum are needed)"; exit 0; }
DOC=$T/../../docs/r3a-promotion.md
REPO_DIR=$(cd "$L/.." && pwd)
W=$BASE/pr; BIN=$W/bin
block() { # block ANCHOR: the first ( ... ) code block after the line starting with ANCHOR
  awk -v a="$1" 'index($0, a) == 1 { f = 1 } f && $0 == "    (" { c = 1; next } c && $0 == "    )" { exit } c { print }' "$DOC"
}
R1=45a5dbef19c14898e73e79a42af360def638c319d14e2bae97a79f7962e4bfb4; GPU=9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc
R1T=2ea22d26b2a1c81526e77e7f29eaff46def5310a9512be769ff3ed50465f4dd2; GPUT=2c870ba9f5963f5ae1ed18a7effa520daa234583997470d9552a795b4aafcda5
RP=51148ff7005d2986cfedbad3aaaedf3371a60fd0b1097daeddb0bf4e6a5f60f3
rewrite() { # the block with the system paths and the real hashes of this Mac rewritten to the fake machine
  sed "s#/boot/efi#$W/esp#g; s#/etc/omarchy-k114s#$W/etc#g; s#/usr/local/lib/omarchy-k114s#$W/lib#g; s#/var/lib/k114s-recovery#$W/rec#g
       s#/etc/pacman.conf#$W/etc/pacman.conf#g; s#/etc/default/update-m1n1#$W/etc/update-m1n1#g; s#/etc/systemd/system#$W/systemd#g
       s#/etc/omarchy-mac-boot#$W/omb#g; s#/etc/systemd/logind.conf.d#$W/logind#g; s#/etc/systemd/sleep.conf.d#$W/sleep#g
       s#/run/lock#$W/lock#g; s#/sys/firmware/efi/efivars#$W/efivars#g; s#/proc/device-tree/chosen#$W/chosen#g; s#/usr/lib/modules#$W/modules#g
       s#$R1#$(sum "$W/fake/r1.bin")#g; s#$GPU#$(sum "$W/fake/gpu.bin")#g; s#$R1T#$(sum "$W/fake/r1.dtb")#g; s#$GPUT#$(sum "$W/fake/gpu.dtb")#g
       s#$RP#$(sum "$W/fake/repair.efi")#g"
}
mkdir -p "$BIN" "$W/fake"
printf '#!/bin/sh\nexit 0\n' > "$BIN/findmnt"
# systemctl as far as the blocks use it. mask behaves as systemd does with a unit that is a plain file in
# /etc/systemd/system: it refuses ("already exists"), which is why P6c moves that file away first (D9)
cat > "$BIN/systemctl" <<'SH'
#!/bin/sh
echo "$@" >> "$FAKE_W/calls"; d=$FAKE_W/systemd
case $1 in
  is-enabled) shift; for u; do
      if [ -L "$d/$u" ]; then echo masked; else case $u in *.target) echo masked ;; k114s-trial-default-revert.service) echo disabled ;; *) echo enabled ;; esac; fi
    done ;;
  mask) [ -f "$d/$2" ] && ! [ -L "$d/$2" ] && { echo "Failed to mask unit: File $d/$2 already exists." >&2; exit 1; }
    ln -sf /dev/null "$d/$2"; echo "Created symlink $d/$2 -> /dev/null" ;;
  unmask) [ -L "$d/$2" ] && rm -f "$d/$2" ;;
esac
exit 0
SH
printf '#!/bin/sh\n[ "$1" = -r ] && { echo "${FAKE_UNAME:-7.3.0-17.v272-4-k114s-r3a-ARCH}"; exit 0; }\nexec /usr/bin/uname "$@"\n' > "$BIN/uname"
printf '#!/bin/sh\necho "Avail"; echo "${FAKE_FREE:-190300000}"\n' > "$BIN/df"
printf '#!/bin/sh\n[ "$1 $2" = "-Q linux-aurora" ] && { echo "linux-aurora 7.3.0.aurora17.v272-4"; exit 0; }\nexit 1\n' > "$BIN/pacman"
# the Limine hook for linux-aurora: its image, and its entry first in the folder (BOOT_ORDER); FAKE_HOOK=default also
# rewrites default_entry, the case P5b must catch
cat > "$BIN/limine-mkinitcpio" <<'SH'
#!/bin/sh
[ "$1" = linux-aurora ] || exit 2
c=$FAKE_W/esp/limine.conf; img=$FAKE_W/esp/EFI/Linux/omarchy_linux-aurora.efi
head -c 1500 /dev/urandom > "$img"; hs=$(b2sum "$img" | cut -d' ' -f1)
cmd=$(awk '/^[ \t]*\/\/linux-k114s/ {f=1} f && /^[ \t]*cmdline:/ {print; exit}' "$c")
awk -v hs="$hs" -v cmd="$cmd" '/^[ \t]*\/\/linux-k114s/ && !d { print "  //linux-aurora"; print "  comment: kernel-id=linux-aurora"; print "  protocol: efi"
  print "  path: boot():/EFI/Linux/omarchy_linux-aurora.efi#" hs; print cmd; d = 1 } { print }' "$c" > "$c.tmp" && mv "$c.tmp" "$c"
[ "${FAKE_HOOK:-}" = default ] && sed -i 's#^default_entry: .*#default_entry: 2#' "$c"
echo "Building UKI for linux-aurora (stand-in)"
SH
cat > "$BIN/limine-entry-tool" <<'SH'
#!/bin/sh
[ "$1 $2" = "--remove-uki linux-aurora" ] || exit 2
c=$FAKE_W/esp/limine.conf
awk '{ s = $0; sub(/^[ \t]+/, "", s) } s ~ /^\// { skip = (s == "//linux-aurora") } !skip { print }' "$c" > "$c.tmp" && mv "$c.tmp" "$c"
rm -f "$FAKE_W/esp/EFI/Linux/omarchy_linux-aurora.efi"
SH
chmod +x "$BIN"/*
head -c 4000 /dev/urandom > "$W/fake/r1.bin"; head -c 4001 /dev/urandom > "$W/fake/gpu.bin"
head -c 300 /dev/urandom > "$W/fake/r1.dtb"; head -c 301 /dev/urandom > "$W/fake/gpu.dtb"; head -c 3000 /dev/urandom > "$W/fake/repair.efi"
fresh() { # the Mac as P0 leaves it: the trial window's layout, the P0c backups
  rm -rf "$W/esp" "$W/etc" "$W/lib" "$W/rec" "$W/lock" "$W/efivars" "$W/chosen" "$W/calls" "$W/home" "$W/modules" "$W/systemd" "$W/omb" "$W/logind" "$W/sleep"
  mkdir -p "$W/systemd" "$W/omb" "$W/logind" "$W/sleep"
  printf '[Unit]\nDescription=stand-in\n' > "$W/systemd/k114s-trial-default-revert.service"; echo 'K114s: r2c' > "$W/omb/owner-boot-chain"
  : > "$W/logind/30-k114s-r3a-trial.conf"; : > "$W/sleep/30-k114s-r3a-trial.conf"
  mkdir -p "$W/modules/7.3.0-17.v272-4-ARCH" && : > "$W/modules/7.3.0-17.v272-4-ARCH/modules.builtin"
  mkdir -p "$W/esp/EFI/Linux" "$W/esp/m1n1" "$W/esp/k114s-repair" "$W/etc" "$W/lib" "$W/rec/promotion" "$W/rec/uki" "$W/lock" "$W/efivars" "$W/chosen" "$W/home/.config"
  cp "$W/fake/r1.bin" "$W/esp/m1n1/boot-ctxr.bin"; cp "$W/fake/gpu.bin" "$W/esp/m1n1/boot-ctxr-r3-gpu.bin"
  cp "$W/fake/r1.dtb" "$W/esp/k114s-repair/k114s.dtb"; cp "$W/fake/r1.dtb" "$W/lib/k114s.dtb"
  cp "$W/fake/repair.efi" "$W/esp/EFI/Linux/omarchy_linux-aurora-k114s.efi"; cp "$W/fake/repair.efi" "$W/rec/uki/omarchy_linux-aurora-k114s.efi"
  head -c 2000 /dev/urandom > "$W/esp/EFI/Linux/omarchy_linux-k114s.efi"
  printf 'spent\nm1n1/boot-ctxr-r3-gpu.bin\n' > "$W/esp/aura-try"; printf 'm1n1/boot-ctxr-r3-gpu.bin\n%s\n' "$GPU" > "$W/etc/stage2-trial"
  cp "$W/fake/r1.bin" "$W/rec/promotion/boot-ctxr.bin.r1"; cp "$W/fake/gpu.dtb" "$W/rec/promotion/k114s.dtb.gpu"
  cp "$W/fake/r1.dtb" "$W/rec/promotion/k114s.dtb.esp-pin.r1"; cp "$W/fake/r1.dtb" "$W/rec/promotion/k114s.dtb.linux-pin.r1"
  cat > "$W/esp/limine.conf" <<CONF
timeout: 5
quiet: no
default_entry: 1
hash_mismatch_panic: no
### K114s repair (added from macOS; remove this block to undo)
/Omarchy K114s repair r1 (trackpad fix B)
  comment: Repair kernel.
  protocol: efi
  path: boot():/EFI/Linux/omarchy_linux-aurora-k114s.efi
  cmdline: root=UUID=00000000-0000-0000-0000-000000000000 rw

/+Omarchy
comment: machine-id=00000000000000000000000000000000
  //linux-k114s
  comment: kernel-id=linux-k114s
  protocol: efi
  path: boot():/EFI/Linux/omarchy_linux-k114s.efi#$(b2sum "$W/esp/EFI/Linux/omarchy_linux-k114s.efi" | cut -d' ' -f1)
  cmdline: root=UUID=00000000-0000-0000-0000-000000000000 rw
CONF
}
run() { # stdin: the block, rewritten -> $out, $rc
  out=$(cd "$W" && FAKE_W=$W K114S_ROOT=$W K114S_HOLDS_LIST=$W/lib/holds.list HOME=$W/home PATH=$BIN:$PATH K=$L/r3a-trial/k114s-boot-once P=$W/rec/promotion REPO=$REPO_DIR \
    K114S_ESP=$W/esp K114S_ETC=$W/etc K114S_EFIVARS=$W/efivars K114S_STATE=$W/rec K114S_SYSTEMCTL=$BIN/systemctl \
    bash -c 'sudo() { "$@"; }; '"$(cat)" 2>&1); rc=$?
}
state() { (cd "$W" && find esp etc lib rec systemd omb -type f -exec sha256sum {} + 2>/dev/null | sort -k2 | sha256sum | cut -c1-16); }
def() { sed -n 's/^default_entry: //p' "$W/esp/limine.conf"; }

# --- P0e: the exact repair block kept on the ESP for macOS (D11) -------------------------------------------------------
bP0e=$(block '**P0e.' | rewrite)
fresh; run <<< "$bP0e"
ok "P0e: exit 0, 7 lines saved" "$rc $(echo "$out" | grep -c 'repair block saved: 7 lines')" "0 1"
ok "P0e: the saved file is the repair block, line for line" \
  "$(sed -n '/^### K114s repair/,/^\/+Omarchy/p' "$W/esp/limine.conf" | sed '$d' | cmp -s - "$W/esp/k114s-repair/promotion/repair-block.conf"; echo $?)" 0
ok "P0e: the changed macOS tool is beside it" "$(cmp -s "$REPO_DIR/macos/tools/k114s_repair.py" "$W/esp/k114s-repair/promotion/k114s_repair.py"; echo $?)" 0
ok "P0e: the command line is never printed" "$(echo "$out" | grep -c 'root=UUID')" 0
before=$(state); run <<< "$bP0e"; ok "P0e: a second run stops, nothing changed" "$rc $(state)" "1 $before"
fresh; sed -i 's#^  cmdline: root=.*#  comment: no command line#' "$W/esp/limine.conf"; before=$(state); run <<< "$bP0e"
ok "P0e: a repair block without a command line stops, nothing written" "$rc $(state)" "1 $before"

# --- P1a --------------------------------------------------------------------------------------------------------------
fresh; bP1=$(block '**P1a.' | rewrite); bU1=$(block '**Undo of P1**' | rewrite)
ok "P1a and its undo are found, the real hashes rewritten" "$(echo "$bP1" | grep -c 'known-good') $(echo "$bP1$bU1" | grep -c -e "$R1" -e "$GPU")" "4 0"
run <<< "$bP1"
ok "P1a: done, exit 0" "$rc $(echo "$out" | grep -c 'P1a: done')" "0 1"
ok "P1a: the configured Stage 2 is the GPU file" "$(sum "$W/esp/m1n1/boot-ctxr.bin")" "$(sum "$W/fake/gpu.bin")"
ok "P1a: both pins are the GPU tree" "$(sum "$W/esp/k114s-repair/k114s.dtb") $(sum "$W/lib/k114s.dtb")" "$(sum "$W/fake/gpu.dtb") $(sum "$W/fake/gpu.dtb")"
ok "P1a: the r1 file and tree are kept in known-good" "$(sum "$W/esp/k114s-repair/known-good/boot-ctxr.bin") $(sum "$W/esp/k114s-repair/known-good/k114s.dtb")" "$(sum "$W/fake/r1.bin") $(sum "$W/fake/r1.dtb")"
ok "P1a: the standing trial is retired: stage2-trial moved to the backup, the re-arm unit disabled, aura-try spent" \
  "$(test -e "$W/etc/stage2-trial"; echo $?) $(test -s "$W/rec/promotion/stage2-trial.retired"; echo $?) $(grep -c 'disable k114s-stage2-rearm.service' "$W/calls") $(sed -n 1p "$W/esp/aura-try")" "1 0 1 spent"
ok "P1a: no temporary file is left on the ESP" "$(find "$W/esp" "$W/lib" -name '*.k114s-new' | wc -l)" 0
ok "P1a: the check ran clean (no Stage 2 trial configured to re-arm)" "$(echo "$out" | grep -c 'ok    no Stage 2 trial is configured to re-arm') $(echo "$out" | grep -c '^BAD')" "1 0"
run <<< "$bU1"
ok "undo of P1: back to r1, both pins r1, the trial file and unit back, aura-try armed for the GPU file" \
  "$rc $(sum "$W/esp/m1n1/boot-ctxr.bin") $(sum "$W/esp/k114s-repair/k114s.dtb") $(sum "$W/lib/k114s.dtb") $(test -s "$W/etc/stage2-trial"; echo $?) $(grep -c 'enable k114s-stage2-rearm.service' "$W/calls") $(sed -n 1p "$W/esp/aura-try")" \
  "0 $(sum "$W/fake/r1.bin") $(sum "$W/fake/r1.dtb") $(sum "$W/fake/r1.dtb") 0 1 armed"
fresh; echo changed >> "$W/esp/m1n1/boot-ctxr-r3-gpu.bin"; before=$(state); run <<< "$bP1"
ok "P1a: a GPU file that is not the proven one stops before any write" "$rc $(state) $(echo "$out" | grep -c 'nothing was changed')" "1 $before 1"
fresh; printf 'armed\nm1n1/boot-ctxr-r3-gpu.bin\n' > "$W/esp/aura-try"; before=$(state); run <<< "$bP1"
ok "P1a: an armed aura-try stops before any write" "$rc $(state)" "1 $before"
fresh; echo x >> "$W/rec/promotion/k114s.dtb.gpu"; before=$(state); run <<< "$bP1"
ok "P1a: a GPU tree backup that does not verify stops before any write" "$rc $(state)" "1 $before"

# --- P2a ----------------------------------------------------------------------------------------------------------------
bP2=$(block '**P2a.' | rewrite); bU2=$(block '**Undo of P2**' | rewrite)
fresh; run <<< "$bP2"; ok "P2a: refused while P1 is not in place, nothing written" "$rc $(def)" "1 1"
fresh; run <<< "$bP1"; cp "$W/esp/limine.conf" "$W/fake/conf.before-p2"; run <<< "$bP2"
ok "P2a: exit 0, default_entry is the path" "$rc $(def)" "0 Omarchy/linux-k114s"
ok "P2a: the check resolves it to entry 3 and prints no BAD" "$(echo "$out" | grep -c 'ok    default_entry is Omarchy/linux-k114s (entry 3, id Omarchy.linux-k114s') $(echo "$out" | grep -c '^BAD')" "1 0"
ok "P2a: only that line changed, nothing left beside it" "$(diff "$W/fake/conf.before-p2" "$W/esp/limine.conf" | grep -c '^[<>]') $(test -e "$W/esp/limine.conf.k114s-new"; echo $?)" "2 1"
run <<< "$bU2"; ok "undo of P2: default_entry 1 again, check clean" "$rc $(def) $(echo "$out" | grep -c 'ok    default_entry is 1 (entry 1')" "0 1 1"
fresh; run <<< "$bP1"; sed -i 's#^  //linux-k114s$#  //linux-k114s #' "$W/esp/limine.conf"; before=$(sum "$W/esp/limine.conf"); run <<< "$bP2"
ok "P2a: a trailing blank on the entry line (Limine would not match the path) stops, nothing written" "$rc $(sum "$W/esp/limine.conf")" "1 $before"
fresh; run <<< "$bP1"; printf '/Omarchy\n  protocol: efi\n  path: boot():/EFI/Linux/omarchy_linux-k114s.efi\n' >> "$W/esp/limine.conf"; before=$(sum "$W/esp/limine.conf"); run <<< "$bP2"
ok "P2a: a second top-level entry named Omarchy stops, nothing written" "$rc $(sum "$W/esp/limine.conf")" "1 $before"
fresh; run <<< "$bP1"; sed -i 's#^default_entry: 1#default_entry: 3#' "$W/esp/limine.conf"; before=$(sum "$W/esp/limine.conf"); run <<< "$bP2"
ok "P2a: a default that is not 1 stops, nothing written" "$rc $(sum "$W/esp/limine.conf")" "1 $before"

# --- P5a ----------------------------------------------------------------------------------------------------------------
bP5=$(block '**P5a.' | rewrite); bU5=$(block '**Undo of P5**' | rewrite)
p2() { fresh; run <<< "$bP0e"; run <<< "$bP1"; run <<< "$bP2"; }
p2; before=$(state); FAKE_UNAME=7.3.0-17.v272-4-ARCH run <<< "$bP5"; ok "P5a: refused from a boot that is not r3a, nothing changed" "$rc $(state)" "1 $before"
p2; run <<< "$bP5"
ok "P5a: exit 0" "$rc" 0
ok "P5a: the repair block and image are gone, its copy on the Linux disk stays" \
  "$(grep -c -e 'aurora-k114s' -e 'K114s repair' "$W/esp/limine.conf") $(test -e "$W/esp/EFI/Linux/omarchy_linux-aurora-k114s.efi"; echo $?) $(sum "$W/rec/uki/omarchy_linux-aurora-k114s.efi")" "0 1 $(sum "$W/fake/repair.efi")"
ok "P5a: the default is still the path, and it resolves to entry 2 (no renumbering)" "$(def) $(echo "$out" | grep -c 'ok    default_entry is Omarchy/linux-k114s (entry 2')" "Omarchy/linux-k114s 1"
ok "P5a: exactly the 7 lines of the block went" "$(diff "$W/rec/promotion/limine.conf.before-p5" "$W/esp/limine.conf" | grep -c '^<') $(diff "$W/rec/promotion/limine.conf.before-p5" "$W/esp/limine.conf" | grep -c '^>')" "7 0"
run <<< "$bU5"
ok "undo of P5: the repair image and its block are back, the default resolves to entry 3" \
  "$rc $(sum "$W/esp/EFI/Linux/omarchy_linux-aurora-k114s.efi") $(cmp -s "$W/esp/limine.conf" "$W/rec/promotion/limine.conf.before-p5"; echo $?) $(echo "$out" | grep -c 'ok    default_entry is Omarchy/linux-k114s (entry 3')" "0 $(sum "$W/fake/repair.efi") 0 1"
p2; echo x >> "$W/rec/uki/omarchy_linux-aurora-k114s.efi"; before=$(state); run <<< "$bP5"
ok "P5a: a Linux-disk copy that does not match stops before any write" "$rc $(state)" "1 $before"
fresh; run <<< "$bP0e"; run <<< "$bP1"; before=$(state); run <<< "$bP5"
ok "P5a: refused while the default is still 1 (P2 not done), nothing changed" "$rc $(state)" "1 $before"
p2; sed -i 's#rw$#rw quiet#' "$W/esp/k114s-repair/promotion/repair-block.conf"; before=$(state); run <<< "$bP5"
ok "P5a: a cut that is not the block saved in P0e stops before any write" "$rc $(state) $(echo "$out" | grep -c 'not the block saved in P0e')" "1 $before 1"
p2; rm "$W/esp/k114s-repair/promotion/repair-block.conf"; before=$(state); run <<< "$bP5"
ok "P5a: no saved block, no cut" "$rc $(state)" "1 $before"
p2; run <<< "$bP5"; head -c 100 /dev/urandom > "$W/esp/EFI/Linux/omarchy_linux-aurora.efi"; before=$(state); run <<< "$bU5"
ok "undo of P5: refused while omarchy_linux-aurora.efi is on the ESP (undo P6a first), nothing changed" "$rc $(state)" "1 $before"
# --- P5b: the hook-built linux-aurora image, in the same sitting as P5a ----------------------------------------------------
bP5b=$(block '**P5b.' | rewrite); bU5b=$(block '**Undo of P5b**' | rewrite)
p2; before=$(state); run <<< "$bP5b"; ok "P5b: refused while the repair entry is still there (P5a not done), nothing changed" "$rc $(state)" "1 $before"
p2; run <<< "$bP5"; run <<< "$bP5b"
ok "P5b: exit 0, the second image and its entry are there, in front of linux-k114s" \
  "$rc $(test -s "$W/esp/EFI/Linux/omarchy_linux-aurora.efi"; echo $?) $(grep -n -E '^[[:blank:]]*//linux-(aurora|k114s)$' "$W/esp/limine.conf" | sed 's/^[0-9]*:[[:blank:]]*//' | tr '\n' ' ')" "0 0 //linux-aurora //linux-k114s "
ok "P5b: the path default follows linux-k114s to entry 3" "$(def) $(echo "$out" | grep -c 'ok    default_entry is Omarchy/linux-k114s (entry 3')" "Omarchy/linux-k114s 1"
run <<< "$bU5b"
ok "undo of P5b: exit 0, the image and entry gone, limine.conf is the file from before P5b" \
  "$rc $(test -e "$W/esp/EFI/Linux/omarchy_linux-aurora.efi"; echo $?) $(echo "$out" | grep -c 'is again the file from before P5b')" "0 1 1"
run <<< "$bU5"; ok "then the undo of P5 brings the repair entry back" "$rc $(grep -c 'K114s repair' "$W/esp/limine.conf")" "0 2"
p2; run <<< "$bP5"; FAKE_HOOK=default run <<< "$bP5b"
ok "P5b: a hook that rewrites default_entry is caught before any reboot" "$rc $(echo "$out" | grep -c 'the hook changed default_entry')" "1 1"
run <<< "$bU5b"
ok "undo of P5b after that: the path is back by the locked one-line edit, and the file is the one from before P5b" \
  "$rc $(def) $(echo "$out" | grep -c 'is again the file from before P5b') $(test -e "$W/esp/limine.conf.k114s-new"; echo $?)" "0 Omarchy/linux-k114s 1 1"

# --- P6c: close the window: holds, update-m1n1 off, the trial-default unit masked (D7, D8, D9) ---------------------------
bP6c=$(block '**P6c.' | rewrite)
p6() { fresh; cp "$L/apply-holds" "$W/lib/apply-holds"; chmod +x "$W/lib/apply-holds"
  printf '%s\n' asahi-fwextract hyprland-m5 limine linux-aurora m1n1-aurora uboot-aurora > "$W/lib/holds.list"
  printf '[options]\nHoldPkg = pacman\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n' > "$W/etc/pacman.conf"; printf 'export LC_ALL=C\n' > "$W/etc/update-m1n1"; }
p6; run <<< "$bP6c"
ok "P6c: exit 0, the last line says masked" "$rc $(echo "$out" | grep -c 'trial-default-revert masked')" "0 1"
ok "P6c: linux-k114s, limine-mkinitcpio-hook and limine-snapper-sync are held, with the boot stack" \
  "$(grep -m1 '^IgnorePkg = ' "$W/etc/pacman.conf" | tr ' ' '\n' | grep -c -x -e linux-k114s -e limine-mkinitcpio-hook -e limine-snapper-sync -e linux-aurora -e m1n1-aurora -e uboot-aurora)" 6
ok "P6c: update-m1n1 is off" "$(grep -c -x 'export M1N1_UPDATE_DISABLED=1' "$W/etc/update-m1n1")" 1
ok "P6c: the unit's plain file went to the backup folder and the mask is a link to /dev/null" \
  "$(test -s "$W/rec/promotion/k114s-trial-default-revert.service"; echo $?) $(readlink "$W/systemd/k114s-trial-default-revert.service")" "0 /dev/null"
ok "P6c: the owner's boot-chain declaration names the promotion" "$(grep -c 'promoted 2026-11-15' "$W/omb/owner-boot-chain")" 1
before=$(state); run <<< "$bP6c"; ok "P6c: a second run is a no-op that still ends masked" "$rc $(state) $(grep -c -x linux-k114s "$W/lib/holds.list")" "0 $before 1"
p6; run <<< "$(printf '%s\n' "$bP6c" | sed 's#^\( *\)sudo mv .*/systemd/\$TU .*#\1:#')"
ok "P6c without the move (the earlier draft): the mask fails and the block stops" "$rc $(echo "$out" | grep -c 'the mask failed')" "1 1"
p6; touch "$W/etc/trial-default"; run <<< "$bP6c"; ok "P6c: a trial-default marker stops before the unit is touched" "$rc $(test -L "$W/systemd/k114s-trial-default-revert.service"; echo $?)" "1 1"

# --- every block of the runbook parses, and each one that writes starts with the findmnt guard ------------------------------
n=0; bad=; while IFS= read -r -d '' b; do n=$((n+1)); bash -n <<< "$b" 2>/dev/null || bad="$bad $n"
  printf '%s' "$b" | grep -q -E 'sudo (cp|mv|rm|install|tee|sh|flock|systemctl|limine|mkdir)' && ! printf '%s' "$b" | grep -q '^findmnt /boot/efi' && bad="$bad $n(no-guard)"; done < <(
  awk '$0 == "    (" { c = 1; b = ""; next } c && $0 == "    )" { printf "%s%c", b, 0; c = 0; next } c { b = b substr($0, 5) "\n" }' "$DOC")
ok "all $n blocks of the runbook parse with bash -n and every writing block has the findmnt guard" "${bad:-none} $((n >= 15))" "none 1"
finish "promotion runbook tests"
