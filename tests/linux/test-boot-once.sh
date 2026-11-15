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
  comment: Kernel version: 7.3.0-17.v272-4-k114s-r3a-ARCH
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
  printf '#!/bin/sh\n[ "$FAKE_SLEEP" = open ] && echo disabled || echo masked\n' > "$d/systemctl"
  chmod +x "$d/save" "$d/systemctl"
}
run() { d=$W/$1; shift; K114S_STATE=$d/state K114S_BOOTID=$(cat $d/bootid 2>/dev/null || echo boot1) K114S_PREVBOOT=$(cat $d/prev 2>/dev/null) K114S_BOOT_EPOCH=$(cat $d/epoch 2>/dev/null || echo 0) K114S_EFIVARS=$d/efivars K114S_ESP=$d/esp K114S_ETC=$d/etc K114S_SAVE=$d/save K114S_SYSTEMCTL=$d/systemctl sh "$T" "$@" 2>&1; }

mk a
out=$(run a entries)
has "entries lists the repair entry with Limine's id" "$out" " 1  Omarchy-K114s-repair-r1--trackpad-fix-B- *boot():/EFI/Linux/omarchy_linux-aurora-k114s.efi"
has "entries lists the directory" "$out" " 2  Omarchy  *(directory)"
has "entries lists the child with the dotted id" "$out" " 3  Omarchy.linux-k114s *boot():/EFI/Linux/omarchy_linux-k114s.efi#"
out=$(run a check); has "check passes on the fixture" "$out" "ok    default_entry is 1"; has "check names the repair image hash" "$out" "info  repair image sha256 $(sha256sum $W/a/esp/EFI/Linux/omarchy_linux-aurora-k114s.efi | cut -c1-64)"

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
mk d; sed -i 's/^default_entry: 1/default_entry: 3/' $W/d/esp/limine.conf; EXP="default_entry is '3'"; refuse "default_entry changed" d arm Omarchy/linux-k114s
mk e; echo x >> $W/e/esp/EFI/Linux/omarchy_linux-k114s.efi; EXP="does not match the hash"; refuse "UKI hash mismatch" e arm Omarchy/linux-k114s
mk f; rm $W/f/esp/EFI/Linux/omarchy_linux-k114s.efi; EXP="is not on the ESP"; refuse "UKI missing" f arm Omarchy/linux-k114s
mk g; EXP="no entry 'Omarchy/linux-nothing'"; refuse "unknown entry" g arm Omarchy/linux-nothing
mk h; EXP="is a directory"; refuse "directory" h arm Omarchy
mk i; out=$(FAKE_SLEEP=open run i arm Omarchy/linux-k114s); has "unmasked sleep target" "$out" "is 'disabled', not masked"; ok "unmasked sleep: no variable" "$(ls $W/i/efivars | grep -c LoaderEntryOneShot)" 0
mk j; mv $W/j/esp/EFI/Linux/omarchy_linux-aurora-k114s.efi $W/j/esp/EFI/Linux/x.efi; EXP="repair image"; refuse "repair image missing" j arm Omarchy/linux-k114s
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
echo "k114s-boot-once tests: $pass passed, $fail failed"
[ "$fail" = 0 ]
