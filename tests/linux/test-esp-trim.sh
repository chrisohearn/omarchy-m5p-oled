#!/bin/bash
# linux/esp-trim in a replica ESP (a folder), as a normal user. No real file is touched; the tool is not run on the Mac by this.
#   usage: test-esp-trim.sh [LINUX_DIR]
set -u
. "$(dirname "$0")/r3-lib.sh" "${1:-}"
TOOL=$L/esp-trim
ok "tool parses" "$(bash -n "$TOOL" 2>&1)" ""
ok "tool is executable in the repository" "$(test -x "$TOOL"; echo $?)" 0
mk() { # a replica of the real layout (sizes shrunk)
  X=$(mktemp -d "$BASE/esp.XXXXXX"); e=$X/boot/efi
  mkdir -p "$e"/{EFI/Linux,EFI/BOOT,m1n1,vendorfw,asahi,aurora,k114s-repair/backup-before-r1,.Spotlight-V100/Store-V2,.Trashes/501} "$X/etc/omarchy-k114s" "$X/var/lib/k114s-recovery"
  for f in EFI/Linux/omarchy_linux-aurora.efi EFI/Linux/omarchy_linux-aurora-k114s.efi EFI/BOOT/BOOTAA64.EFI m1n1/boot.bin m1n1/boot.bin.old m1n1/boot-ctxr.bin m1n1/boot-ctxr-r3-gpu.bin \
      vendorfw/firmware.cpio vendorfw/firmware.tar asahi/all_firmware.tar.gz aurora/stage1-k114s.bin k114s-repair/backup-before-r1/limine.conf limine.conf aura-try \
      .Spotlight-V100/Store-V2/store.db .Spotlight-V100/VolumeConfiguration.plist .Trashes/501/x; do head -c 2000 /dev/urandom > "$e/$f"; done
}
snap() { (cd "$X/boot/efi" && find . -type f | sort | xargs -d '\n' sha256sum | sha256sum | cut -c1-16); }
run() { out=$(K114S_TEST=1 K114S_ROOT=$X K114S_NO_MOUNTCHECK=1 bash "$TOOL" "$@" 2>&1); rc=$?; }

mk; s0=$(snap); run
ok "dry run: exit 0, says nothing was changed, lists both items" "$rc $(echo "$out" | grep -c 'dry run: nothing was changed') $(echo "$out" | grep -c -E '^  (macos-junk|m1n1-old): [0-9]+ bytes')" "0 1 2"
ok "dry run: the ESP is byte for byte as it was" "$(snap)" "$s0"
ok "dry run: no backup folder made" "$(ls "$X/var/lib/k114s-recovery" | wc -l | tr -d ' ')" 0
run --apply macos-junk bogus; ok "an unknown item stops the run before anything happens" "$rc $(snap)" "1 $s0"
run --apply vendorfw; ok "firmware cannot be named" "$rc $(snap)" "1 $s0"
run --apply /boot/efi/EFI/Linux/omarchy_linux-aurora.efi; ok "a path cannot be named" "$rc $(snap)" "1 $s0"
mk; : > "$X/boot/efi/m1n1/boot.bin"; run
ok "m1n1-old refused when boot.bin is empty" "$(echo "$out" | grep -c 'm1n1-old: REFUSED, m1n1/boot.bin is missing or empty')" 1
run --apply; ok "apply with that refusal still trims macos-junk only, and keeps boot.bin.old" "$rc $(test -e "$X/boot/efi/.Trashes"; echo $?) $(test -e "$X/boot/efi/m1n1/boot.bin.old"; echo $?)" "0 1 0"
mk; touch "$X/etc/omarchy-k114s/stage2-frozen"; run; ok "m1n1-old refused while a Stage 2 switch is pending" "$(echo "$out" | grep -c 'REFUSED, a Stage 2 switch is pending')" 1

mk; s0=$(snap); run --apply
ok "apply: exit 0, names the backup and the undo" "$rc $(echo "$out" | grep -c '^deleted:  *macos-junk m1n1-old. Backup: .*--restore')" "0 1"
bk=$(ls -d "$X"/var/lib/k114s-recovery/esp-trim-*)
ok "apply: the items are gone from the ESP" "$(for p in .Spotlight-V100 .Trashes m1n1/boot.bin.old; do test -e "$X/boot/efi/$p"; echo -n $?; done)" 111
ok "apply: everything else is untouched (kernels, firmware, Stage 2 files, repair bundle, limine.conf, aura-try)" \
  "$(cd "$X/boot/efi" && for f in EFI/Linux/omarchy_linux-aurora.efi EFI/Linux/omarchy_linux-aurora-k114s.efi EFI/BOOT/BOOTAA64.EFI m1n1/boot.bin m1n1/boot-ctxr.bin m1n1/boot-ctxr-r3-gpu.bin vendorfw/firmware.cpio vendorfw/firmware.tar asahi/all_firmware.tar.gz aurora/stage1-k114s.bin k114s-repair/backup-before-r1/limine.conf limine.conf aura-try; do test -s "$f" || echo "$f"; done)" ""
ok "apply: the backup has a SHA256SUMS that matches its files" "$(cd "$bk/files" && sha256sum -c --quiet ../SHA256SUMS; echo $?) $(wc -l < "$bk/SHA256SUMS" | tr -d ' ')" "0 4"
run --apply; ok "apply again: nothing to do, stops without making a second backup" "$rc $(ls -d "$X"/var/lib/k114s-recovery/esp-trim-* | wc -l | tr -d ' ')" "1 1"
run --restore "$bk"; ok "restore: exit 0" "$rc" 0
ok "restore: the ESP's files are byte for byte the originals" "$(snap)" "$s0"
run --restore "$bk"; ok "restore again: nothing is overwritten" "$rc $(echo "$out" | grep -c '^kept (exists)') $(echo "$out" | grep -c 'restored 0 file')" "0 4 1"
echo tampered >> "$bk/files/m1n1/boot.bin.old"; rm -f "$X/boot/efi/m1n1/boot.bin.old"
run --restore "$bk"; ok "restore: a backup that does not match its SHA256SUMS restores nothing" "$rc $(test -e "$X/boot/efi/m1n1/boot.bin.old"; echo $?)" "1 1"
run --restore "$X/nothing"; ok "restore: a folder that is not a backup is refused" "$rc" 1
mk; run --apply; bk2=$(ls -d "$X"/var/lib/k114s-recovery/esp-trim-* | head -1); s1=$(snap)
mkdir -p "$bk2/files/vendorfw"; cp "$X/boot/efi/limine.conf" "$bk2/files/vendorfw/foreign"; cp "$bk2/SHA256SUMS" "$X/sums.orig"; (cd "$bk2/files" && sha256sum vendorfw/foreign) >> "$bk2/SHA256SUMS"
run --restore "$bk2"; ok "restore: a backup holding a path the tool never saves restores nothing" "$rc $(echo "$out" | grep -c 'never saves')" "1 1"
rm -rf "$bk2/files/vendorfw"; cp "$X/sums.orig" "$bk2/SHA256SUMS"; echo x > "$bk2/files/.Trashes/unlisted"
run --restore "$bk2"; ok "restore: an unlisted file in an allowed folder restores nothing" "$rc $(echo "$out" | grep -c 'does not list')" "1 1"
ok "restore refusals left the ESP as the apply left it" "$(snap)" "$s1"
# failures after the backup: the tool must say how to undo and stop non-zero (stubbed rm, sync and cp first in PATH)
stub() { mkdir -p "$X/stub"; printf '#!/bin/sh\nexit 1\n' > "$X/stub/$1"; chmod +x "$X/stub/$1"; }
frun() { out=$(PATH=$X/stub:$PATH K114S_TEST=1 K114S_ROOT=$X K114S_NO_MOUNTCHECK=1 bash "$TOOL" "$@" 2>&1); rc=$?; }
mk; stub rm; frun --apply m1n1-old; ok "apply: a failed delete stops with the undo command" "$rc $(echo "$out" | grep -c 'delete of m1n1/boot.bin.old failed.*--restore')" "1 1"
mk; stub sync; frun --apply m1n1-old; ok "apply: a failed sync stops with the undo command" "$rc $(echo "$out" | grep -c 'sync failed after the delete.*--restore')" "1 1"
mk; run --apply m1n1-old; bk3=$(ls -d "$X"/var/lib/k114s-recovery/esp-trim-*); stub cp; frun --restore "$bk3"
ok "restore: a failed copy stops and leaves no partial file" "$rc $(echo "$out" | grep -c 'copy of m1n1/boot.bin.old failed') $(test -e "$X/boot/efi/m1n1/boot.bin.old"; echo $?)" "1 1 1"
rm -f "$X/stub/cp"; stub sync; frun --restore "$bk3"; ok "restore: a failed sync is reported" "$rc $(echo "$out" | grep -c 'sync failed after the restore')" "1 1"
mk; run --apply m1n1-old; bk4=$(ls -d "$X"/var/lib/k114s-recovery/esp-trim-*)
mkdir -p "$X/stub"
printf '#!/bin/sh\nprintf "Avail\\n1\\n"\n' > "$X/stub/df"; printf '#!/bin/sh\necho 99999999\n' > "$X/stub/du"; chmod +x "$X/stub/df" "$X/stub/du"
frun --restore "$bk4"; ok "restore: too little room on the ESP restores nothing" "$rc $(echo "$out" | grep -c 'too little room') $(test -e "$X/boot/efi/m1n1/boot.bin.old"; echo $?)" "1 1 1"
mk; unset K114S_NO_MOUNTCHECK; out=$(K114S_TEST=1 K114S_ROOT=$X bash "$TOOL" --apply 2>&1); rc=$?
ok "a folder that is not a mount point is refused (no K114S_NO_MOUNTCHECK)" "$rc $(echo "$out" | grep -c 'not a mount point')" "1 1"
ok "the ESP is untouched by that" "$(test -e "$X/boot/efi/.Trashes"; echo $?)" 0
ok "outside the tests, K114S_ROOT is ignored: the tool aims at the real /boot/efi and stops without root" "$(K114S_ROOT=$X bash "$TOOL" --apply 2>&1 | grep -c -E 'need root|not readable|not a mount point|does not exist')" 1
finish "esp-trim tests"
