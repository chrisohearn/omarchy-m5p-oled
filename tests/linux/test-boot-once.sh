#!/bin/bash
# Tests of linux/r3a-trial/k114s-boot-once in a fake ESP and a fake efivarfs. No real system file is touched.
# The saver is a stand-in for omarchy-mac-efi-vars' efi-vars-save (it copies the variable into a fake U-Boot file),
# so this proves the tool's logic and the bytes it writes, not U-Boot or Limine: that is the self-test on the Mac.
#   usage: test-boot-once.sh [PATH-TO-k114s-boot-once]
set -u
H=$(cd "$(dirname "$0")" && pwd); T=${1:-$H/../../linux/r3a-trial/k114s-boot-once}
W=$(mktemp -d "${TMPDIR:-/tmp}/k114s-boot-once-test.XXXXXX"); trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: got [$2] want [$3]"; fi; }
has() { if printf '%s' "$2" | grep -q -- "$3"; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: lacks [$3]: $(printf '%s' "$2" | tail -2)"; fi; }
BLI=4a67b082-0a4c-41cf-b6c7-440b29bb8c4f; RT=b2ac5fc9-92b7-4acd-aeac-11e818c3130c

mk() {  # a fake machine in $W/$1
  d=$W/$1; mkdir -p "$d/esp/EFI/Linux" "$d/efivars" "$d/etc" "$d/state"; echo "ok boot=x id=x" > "$d/state/boot-once-selftest-ok"
  head -c 3000 /dev/urandom > "$d/esp/EFI/Linux/omarchy_linux-aurora-k114s.efi"
  head -c 3000 /dev/urandom > "$d/esp/EFI/Linux/omarchy_linux-k114s.efi"
  rh=$(b2sum "$d/esp/EFI/Linux/omarchy_linux-aurora-k114s.efi" | cut -d' ' -f1); nh=$(b2sum "$d/esp/EFI/Linux/omarchy_linux-k114s.efi" | cut -d' ' -f1)
  cat > "$d/esp/limine.conf" <<CONF
timeout: 5
default_entry: 1
interface_branding: Omarchy Bootloader
### K114s repair (added from macOS; remove this block to undo)
/Omarchy K114s repair r1 (trackpad fix B)
  comment: Repair kernel.
  protocol: efi
  path: boot():/EFI/Linux/omarchy_linux-aurora-k114s.efi
  cmdline: root=UUID=00000000-0000-0000-0000-000000000000 rw

/+Omarchy
comment: machine-id=00000000000000000000000000000000
  //linux-k114s
  comment: Kernel version: 7.3.0-17.v272-11-k114s-r3b-ARCH
  protocol: efi
  path: boot():/EFI/Linux/omarchy_linux-k114s.efi#$nh
  cmdline: root=UUID=00000000-0000-0000-0000-000000000000 rw
CONF
  printf 'spent\nm1n1/boot-ctxr-r3-gpu.bin\n' > "$d/esp/aura-try"
  { printf '\007\000\000\000'; printf 'ubootefi.var\0'; } > "$d/efivars/RTStorageVolatile-$RT"
  : > "$d/esp/ubootefi.var"
  cat > "$d/save" <<'SAVE'
#!/bin/sh
# stand-in for efi-vars-save: U-Boot's file holds the variable as a UTF-16 name and a UTF-16 value
f=$K114S_ESP/ubootefi.var; : > "$f"
v=$K114S_EFIVARS/LoaderEntryOneShot-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f
[ -e "$v" ] && { printf 'LoaderEntryOneShot' | iconv -t UTF-16LE >> "$f"; printf '\0\0' >> "$f"; tail -c +5 "$v" >> "$f"; }
exit 0
SAVE
  cat > "$d/systemctl" <<'SYSCTL'
#!/bin/sh
# FAKE_SLEEP=open: every target open. FAKE_SUSPEND / FAKE_HIB: what suspend.target / hibernate.target read (default masked)
[ "$FAKE_SLEEP" = open ] && { echo disabled; exit 0; }
case $2 in suspend.target) echo "${FAKE_SUSPEND:-masked}" ;; hibernate.target) echo "${FAKE_HIB:-masked}" ;; *) echo masked ;; esac
SYSCTL
  chmod +x "$d/save" "$d/systemctl"
}
run() { d=$W/$1; shift; K114S_LIDSLEEP=$d/lidsleep K114S_STATE=$d/state K114S_BOOTID=$(cat $d/bootid 2>/dev/null || echo boot1) K114S_PREVBOOT=$(cat $d/prev 2>/dev/null) K114S_BOOT_EPOCH=$(cat $d/epoch 2>/dev/null || echo 0) K114S_EFIVARS=$d/efivars K114S_ESP=$d/esp K114S_ETC=$d/etc K114S_SAVE=$d/save K114S_SYSTEMCTL=$d/systemctl sh "$T" "$@" 2>&1; }

mk a
out=$(run a entries)
has "entries lists the repair entry with Limine's id" "$out" " 1  Omarchy-K114s-repair-r1--trackpad-fix-B- *boot():/EFI/Linux/omarchy_linux-aurora-k114s.efi"
has "entries lists the directory" "$out" " 2  Omarchy  *(directory)"
has "entries lists the child with the dotted id" "$out" " 3  Omarchy.linux-k114s *boot():/EFI/Linux/omarchy_linux-k114s.efi#"
out=$(run a check); has "check passes on the fixture" "$out" "ok    default_entry is 1 (entry 1, id Omarchy-K114s-repair-r1--trackpad-fix-B-, boots boot():/EFI/Linux/omarchy_linux-aurora-k114s.efi)"
has "check names the hash of a default entry that has no #hash" "$out" "info  the default entry's file has no #hash in limine.conf; its sha256 is $(sha256sum $W/a/esp/EFI/Linux/omarchy_linux-aurora-k114s.efi | cut -c1-64)"
ok "check prints no BAD on the fixture" "$(printf '%s' "$out" | grep -c '^BAD')" 0

out=$(run a arm Omarchy/linux-k114s); rc=$?
has "arm succeeds" "$out" "armed: the next boot starts 'Omarchy/linux-k114s' (id Omarchy.linux-k114s) once"
ok "the variable holds attributes NV|BS|RT, the UTF-16 id and a UTF-16 NUL" "$(od -An -tx1 $W/a/efivars/LoaderEntryOneShot-$BLI | tr -d ' \n')" "07000000$(printf 'Omarchy.linux-k114s' | iconv -t UTF-16LE | od -An -tx1 | tr -d ' \n')0000"
ok "U-Boot's file holds the id" "$(strings -a -e l $W/a/esp/ubootefi.var | grep -cx Omarchy.linux-k114s)" 1
ok "default_entry is untouched" "$(grep default_entry $W/a/esp/limine.conf)" "default_entry: 1"
out=$(run a status); has "status shows the request" "$out" "efivarfs: LoaderEntryOneShot = Omarchy.linux-k114s"; has "status shows it in U-Boot's file" "$out" "holds LoaderEntryOneShot"
out=$(run a clear); has "clear" "$out" "cleared"; out=$(run a status); has "after clear: gone from efivarfs" "$out" "no LoaderEntryOneShot (none requested"; has "after clear: gone from U-Boot's file" "$out" "no LoaderEntryOneShot"

# Limine erases the variable when it reads it: what Linux then sees
run a arm Omarchy/linux-k114s >/dev/null; rm -f $W/a/efivars/LoaderEntryOneShot-$BLI; : > $W/a/esp/ubootefi.var
out=$(run a status); has "consumed: nothing left in either place" "$out" "U-Boot file .*: no LoaderEntryOneShot"

# refusals: each writes nothing
refuse() { name=$1; shift; out=$(run "$@"); r=$?; has "refused: $name" "$out" "$EXP"; ok "refused: $name wrote no variable" "$(ls $W/$1/efivars | grep -c LoaderEntryOneShot)" 0; }
mk b; printf 'armed\nm1n1/boot-ctxr-r3-gpu.bin\n' > $W/b/esp/aura-try; EXP="a Stage 2 trial is armed"; refuse "armed Stage 2 trial" b arm Omarchy/linux-k114s
out=$(run b arm Omarchy/linux-k114s --with-stage2-trial); has "armed trial allowed with --with-stage2-trial" "$out" "armed: the next boot"
mk c; printf 'm1n1/boot-ctxr-r3-gpu.bin\nabc\n' > $W/c/etc/stage2-trial; EXP="would re-arm a Stage 2 trial"; refuse "configured Stage 2 re-arm" c arm Omarchy/linux-k114s
mk d; sed -i 's/^default_entry: 1/default_entry: 2/' $W/d/esp/limine.conf; EXP="names a directory"; refuse "default_entry names the Omarchy directory" d arm Omarchy/linux-k114s
mk d2; sed -i 's/^default_entry: 1/default_entry: 9/' $W/d2/esp/limine.conf; EXP="is past the last entry"; refuse "default_entry past the last entry" d2 arm Omarchy/linux-k114s
mk e; echo x >> $W/e/esp/EFI/Linux/omarchy_linux-k114s.efi; EXP="does not match the hash"; refuse "UKI hash mismatch" e arm Omarchy/linux-k114s
mk f; rm $W/f/esp/EFI/Linux/omarchy_linux-k114s.efi; EXP="is not on the ESP"; refuse "UKI missing" f arm Omarchy/linux-k114s
mk g; EXP="no entry 'Omarchy/linux-nothing'"; refuse "unknown entry" g arm Omarchy/linux-nothing
mk h; EXP="is a directory"; refuse "directory" h arm Omarchy
mk i; out=$(FAKE_SLEEP=open run i arm Omarchy/linux-k114s); has "unmasked sleep target" "$out" "is 'disabled', not masked"; ok "unmasked sleep: no variable" "$(ls $W/i/efivars | grep -c LoaderEntryOneShot)" 0
mk i2; out=$(FAKE_HIB=masked-runtime run i2 arm Omarchy/linux-k114s); has "hibernate masked only in /run is refused" "$out" "hibernate.target is 'masked-runtime', not masked"; ok "hibernate masked-runtime: no variable" "$(ls $W/i2/efivars | grep -c LoaderEntryOneShot)" 0
mk i3; out=$(FAKE_SUSPEND=masked-runtime run i3 arm Omarchy/linux-k114s); has "suspend masked only in /run, no lid-sleep tool: refused" "$out" "suspend.target is 'masked-runtime', not masked in /etc, and there is no"; ok "suspend masked-runtime, no tool: no variable" "$(ls $W/i3/efivars | grep -c LoaderEntryOneShot)" 0
printf '#!/bin/sh\necho "BAD   the gate is disabled"; exit 1\n' > $W/i3/lidsleep; chmod +x $W/i3/lidsleep
out=$(FAKE_SUSPEND=masked-runtime run i3 arm Omarchy/linux-k114s); has "suspend masked-runtime, the lid-sleep check fails: refused" "$out" "the lid-sleep gate does not hold it: BAD   the gate is disabled"
printf '#!/bin/sh\nexit 0\n' > $W/i3/lidsleep
out=$(FAKE_SUSPEND=masked-runtime run i3 arm Omarchy/linux-k114s); has "suspend masked-runtime, the lid-sleep check passes: armed" "$out" "armed: the next boot"
mk i4; out=$(FAKE_SUSPEND=static run i4 arm Omarchy/linux-k114s); has "suspend open, no lid-sleep tool: refused" "$out" "suspend.target is 'static', not masked in /etc, and there is no"
mk j; mv $W/j/esp/EFI/Linux/omarchy_linux-aurora-k114s.efi $W/j/esp/EFI/Linux/x.efi; EXP="omarchy_linux-aurora-k114s.efi is not on the ESP"; refuse "the default entry's image missing" j arm Omarchy/linux-k114s
mk k; printf '#!/bin/sh\nexit 0\n' > $W/k/save; out=$(run k arm Omarchy/linux-k114s); has "a saver that does not persist the request: taken back" "$out" "not hang-safe; taken back"; ok "not hang-safe: variable removed" "$(ls $W/k/efivars | grep -c LoaderEntryOneShot)" 0
mk l; printf '#!/bin/sh\nexit 1\n' > $W/l/save; out=$(run l arm Omarchy/linux-k114s); has "a failing saver: taken back" "$out" "efi-vars-save failed"; ok "failing saver: variable removed" "$(ls $W/l/efivars | grep -c LoaderEntryOneShot)" 0
out=$(run a arm); has "arm without a target" "$out" "arm needs an entry path"
# remember_last_entry: yes is flagged
mk r; sed -i '1i remember_last_entry: yes' $W/r/esp/limine.conf; out=$(run r check); has "check flags remember_last_entry: yes" "$out" "BAD   remember_last_entry is yes"
mk r2; sed -i '1i Remember_Last_Entry:   YES' $W/r2/esp/limine.conf; out=$(run r2 check); has "check flags it case-insensitively" "$out" "BAD   remember_last_entry is yes"
out=$(run a check); ok "check does not flag it when absent" "$(printf '%s' "$out" | grep -c remember_last_entry)" 0

# the self-test gate: no marker, only entry 1 may be armed
REPAIR='Omarchy K114s repair r1 (trackpad fix B)'; RID=Omarchy-K114s-repair-r1--trackpad-fix-B-
mk s; rm $W/s/state/boot-once-selftest-ok; EXP="has not been measured"; refuse "real target without the self-test marker" s arm Omarchy/linux-k114s
out=$(run s arm "$REPAIR"); has "the repair entry itself can be armed without the marker" "$out" "armed: the next boot starts"
ok "arm records the arming boot and id" "$(cat $W/s/state/boot-once-armed)" "boot1 $RID"
# no arming record, no one-shot: the lid-sleep gate needs the record to keep the trial boot from sleeping
mk u; rm -rf $W/u/state; : > $W/u/state; EXP="cannot write the arming record"; refuse "arm without a writable arming record" u arm "$REPAIR"
ok "and no one-shot was written" "$(ls $W/u/efivars 2>/dev/null | grep -c LoaderEntryOneShot || true)" 0
# reboot simulation: Limine consumed the request, U-Boot kept nothing, the file is older than this boot
reboot() { d=$W/$1; echo "$2" > $d/bootid; echo boot1 > $d/prev; echo $(( $(date +%s) + 1000 )) > $d/epoch; rm -f $d/efivars/LoaderEntryOneShot-$BLI; : > $d/esp/ubootefi.var
  { printf '\007\000\000\000'; printf '%s' "$RID" | iconv -t UTF-16LE; printf '\0\0'; } > $d/efivars/LoaderEntrySelected-$BLI; }
reboot s boot2; out=$(run s status); has "self-test passes when the erase reached U-Boot's file" "$out" "self-test: PASSED"
has "self-test wrote the marker" "$(cat $W/s/state/boot-once-selftest-ok)" "^ok boot=boot2"
out=$(run s arm Omarchy/linux-k114s); has "after the marker a real target arms" "$out" "armed: the next boot starts 'Omarchy/linux-k114s'"
mk s2; rm $W/s2/state/boot-once-selftest-ok; run s2 arm "$REPAIR" >/dev/null; reboot s2 boot2
{ printf 'LoaderEntryOneShot' | iconv -t UTF-16LE; printf '\0\0'; } > $W/s2/esp/ubootefi.var      # the erase did not reach disk
out=$(run s2 status); has "self-test fails when U-Boot's file still holds the request" "$out" "self-test: FAILED"; ok "failed self-test: no marker" "$(ls $W/s2/state | grep -c selftest-ok)" 0
mk s3; rm $W/s3/state/boot-once-selftest-ok; run s3 arm "$REPAIR" >/dev/null; reboot s3 boot2; echo boot0 > $W/s3/prev
out=$(run s3 status); has "self-test is not measured when this is not the boot after arming" "$out" "NOT MEASURED: this is not the boot right after arming"; ok "not measured: no marker" "$(ls $W/s3/state | grep -c selftest-ok)" 0
mk s4; rm $W/s4/state/boot-once-selftest-ok; run s4 arm "$REPAIR" >/dev/null; reboot s4 boot2; echo 0 > $W/s4/epoch
out=$(run s4 status); has "self-test is not measured when a save ran during this boot" "$out" "written during this boot"
# clear between arm and reboot voids the self-test: no PASSED, no marker, no real target
mk cl; rm $W/cl/state/boot-once-selftest-ok; has "clear test: the self-test arm succeeds" "$(run cl arm "$REPAIR")" "armed"; run cl clear >/dev/null; ok "clear removes the arming record" "$(ls $W/cl/state | grep -c boot-once-armed)" 0
reboot cl boot2; out=$(run cl status); ok "a cleared request never gives PASSED" "$(printf '%s' "$out" | grep -c 'self-test: PASSED')" 0; ok "cleared: no marker" "$(ls $W/cl/state | grep -c selftest-ok)" 0
EXP="has not been measured"; refuse "cleared: a real target still refuses" cl arm Omarchy/linux-k114s
mk t; rm $W/t/state/boot-once-selftest-ok; run t arm "$REPAIR" >/dev/null; reboot t boot2; echo 0 > $W/t/epoch
out=$(run t status); has "NOT MEASURED prints the mtime and the boot start" "$out" "mtime [0-9]*, boot start 0"
# store_has checks the value of LoaderEntryOneShot, not the id anywhere in the file
mk v; printf '#!/bin/sh\nf=$K114S_ESP/ubootefi.var; : > "$f"; { printf "LoaderEntries" | iconv -t UTF-16LE; printf "\\0\\0Omarchy.linux-k114s\\0\\0"; } >> "$f"\nexit 0\n' > $W/v/save
out=$(run v arm Omarchy/linux-k114s); has "an id held by another variable does not satisfy the post-save check" "$out" "not hang-safe; taken back"
# mark-not-durable is sticky: arm refuses real targets, status never re-passes, clear keeps it
mk nd; run nd arm "$REPAIR" >/dev/null; out=$(run nd mark-not-durable); has "mark-not-durable writes the marker" "$out" "marked:"
ok "mark-not-durable removes the self-test marker and the arming record" "$(ls $W/nd/state | sort | tr '\n' ' ')" "boot-once-not-durable "
run nd clear >/dev/null
EXP="durability check failed"; refuse "real target after mark-not-durable" nd arm Omarchy/linux-k114s
out=$(run nd arm "$REPAIR"); has "the repair entry itself can still be armed" "$out" "armed: the next boot starts"
reboot nd boot2; out=$(run nd status); ok "status never gives PASSED after mark-not-durable" "$(printf '%s' "$out" | grep -c 'self-test: PASSED')" 0; has "status says why" "$out" "self-test: not run"
ok "no self-test marker is written" "$(ls $W/nd/state | grep -c selftest-ok)" 0
run nd clear >/dev/null; ok "clear leaves the marker" "$(ls $W/nd/state | grep -c boot-once-not-durable)" 1
EXP="durability check failed"; refuse "real target still refused after clear" nd arm Omarchy/linux-k114s

# --- after promotion (docs/r3a-promotion.md): the repair entry is gone, default_entry is the path Omarchy/linux-k114s ----------
mkp() {  # the promoted layout: the hook-built linux-aurora entry sorts first in the folder (BOOT_ORDER), the default is a path
  mk "$1"; d=$W/$1; rm "$d/esp/EFI/Linux/omarchy_linux-aurora-k114s.efi"; head -c 3000 /dev/urandom > "$d/esp/EFI/Linux/omarchy_linux-aurora.efi"
  ah=$(b2sum "$d/esp/EFI/Linux/omarchy_linux-aurora.efi" | cut -d' ' -f1); nh=$(b2sum "$d/esp/EFI/Linux/omarchy_linux-k114s.efi" | cut -d' ' -f1)
  cat > "$d/esp/limine.conf" <<CONF
timeout: 5
quiet: no
default_entry: Omarchy/linux-k114s
hash_mismatch_panic: no

/+Omarchy
comment: machine-id=00000000000000000000000000000000
  //linux-aurora
  comment: kernel-id=linux-aurora
  protocol: efi
  path: boot():/EFI/Linux/omarchy_linux-aurora.efi#$ah
  cmdline: root=UUID=00000000-0000-0000-0000-000000000000 rw
  //linux-k114s
  comment: kernel-id=linux-k114s
  protocol: efi
  path: boot():/EFI/Linux/omarchy_linux-k114s.efi#$nh
  cmdline: root=UUID=00000000-0000-0000-0000-000000000000 rw
CONF
}
KID=Omarchy.linux-k114s
mkp p; out=$(run p check)
has "promoted: check resolves the path default" "$out" "ok    default_entry is Omarchy/linux-k114s (entry 3, id Omarchy.linux-k114s, boots boot():/EFI/Linux/omarchy_linux-k114s.efi#"
has "promoted: the default entry's hash is checked" "$out" "ok    the default entry's file matches limine.conf"
ok "promoted: no BAD without the repair entry" "$(printf '%s' "$out" | grep -c '^BAD')" 0
out=$(run p arm Omarchy/linux-aurora); has "promoted: another entry arms" "$out" "armed: the next boot starts 'Omarchy/linux-aurora' (id Omarchy.linux-aurora) once"
has "promoted: arm names the path default as the fallback" "$out" "default_entry stays Omarchy/linux-k114s. A hang before the root filesystem leaves the default entry (Omarchy/linux-k114s)"
ok "promoted: arm does not touch default_entry" "$(grep '^default_entry' $W/p/esp/limine.conf)" "default_entry: Omarchy/linux-k114s"
run p clear >/dev/null
# the path keeps naming the same entry when the entry in front of it goes (the index does not)
mkp p2; sed -i '/^  \/\/linux-aurora$/,/^  cmdline/d' $W/p2/esp/limine.conf; out=$(run p2 check)
has "promoted: an entry removed in front: the path now resolves to entry 2" "$out" "ok    default_entry is Omarchy/linux-k114s (entry 2, id Omarchy.linux-k114s"
# what Limine 12.9.6 would not boot, refused before anything is armed (each would stop at the menu, where the keyboard does not work)
mkp q1; sed -i 's#^default_entry: .*#default_entry: 1#' $W/q1/esp/limine.conf; EXP="names a directory"; refuse "promoted: index 1 is now the Omarchy directory" q1 arm Omarchy/linux-aurora
mkp q2; sed -i 's#^default_entry: .*#default_entry: Omarchy#' $W/q2/esp/limine.conf; EXP="names a directory (Omarchy)"; refuse "promoted: a path naming the directory" q2 arm Omarchy/linux-aurora
mkp q3; sed -i 's#^default_entry: .*#default_entry: Omarchy/linux-nothing#' $W/q3/esp/limine.conf; EXP="names no entry"; refuse "promoted: a path naming nothing" q3 arm Omarchy/linux-aurora
mkp q4; sed -i 's#^default_entry: .*#default_entry: Omarchy/linux-k114s #' $W/q4/esp/limine.conf; EXP="names no entry"; refuse "promoted: a trailing blank (Limine keeps it, so the path matches nothing)" q4 arm Omarchy/linux-aurora
mkp q5; sed -i '1i default_entry: 2' $W/q5/esp/limine.conf; EXP="2 default_entry lines"; refuse "promoted: two default_entry lines" q5 arm Omarchy/linux-aurora
mkp q6; sed -i 's#^default_entry: .*#default_entry: Omarchy/linux-k114s\#1#' $W/q6/esp/limine.conf; EXP="does not resolve"; refuse "promoted: a '#' suffix is not resolved by this tool" q6 arm Omarchy/linux-aurora
mkp q7; sed -i '/^default_entry/d' $W/q7/esp/limine.conf; EXP="0 default_entry lines"; refuse "promoted: no default_entry line" q7 arm Omarchy/linux-aurora
mkp q8; echo x >> $W/q8/esp/EFI/Linux/omarchy_linux-k114s.efi; EXP="omarchy_linux-k114s.efi does not match the hash"; refuse "promoted: the default entry's image does not match its #hash" q8 arm Omarchy/linux-aurora
mkp q9; sed -i 's#^default_entry: .*#DEFAULT_ENTRY:  Omarchy/linux-k114s#' $W/q9/esp/limine.conf; out=$(run q9 check)
has "promoted: the option name in any case, as Limine reads it" "$out" "ok    default_entry is Omarchy/linux-k114s (entry 3"
# a second entry that boots the default's own file is no fallback
mkp q10; nh=$(b2sum $W/q10/esp/EFI/Linux/omarchy_linux-k114s.efi | cut -d' ' -f1); printf '  //k114s-again\n  protocol: efi\n  path: boot():/EFI/Linux/omarchy_linux-k114s.efi#%s\n' "$nh" >> $W/q10/esp/limine.conf
EXP="boots the same file as the default entry"; refuse "promoted: a target that boots the default's file" q10 arm Omarchy/k114s-again
# the self-test gate follows the default entry
mkp ps; rm $W/ps/state/boot-once-selftest-ok
EXP="Arm the default entry itself (Omarchy/linux-k114s, entry 3)"; refuse "promoted: without the marker only the default entry may be armed" ps arm Omarchy/linux-aurora
out=$(run ps arm Omarchy/linux-k114s); has "promoted: the default entry itself arms without the marker" "$out" "armed: the next boot starts"
RID=$KID; reboot ps boot2; out=$(run ps status); has "promoted: the self-test measures a request for the path default" "$out" "self-test: PASSED"
mkp pn; run pn mark-not-durable >/dev/null; EXP="only the default entry (Omarchy/linux-k114s, entry 3) can be armed"; refuse "promoted: not durable: only the default entry" pn arm Omarchy/linux-aurora
echo "k114s-boot-once tests: $pass passed, $fail failed"
[ "$fail" = 0 ]
