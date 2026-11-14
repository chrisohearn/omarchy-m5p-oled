#!/bin/bash
# Tests of the macOS apply/rollback tool against a replica of the K114s trial-1 ESP (no root, no disks).
#   usage: test-macos-tool.sh BUNDLE IMAGE_ZIP [R1_BUNDLE]
# BUNDLE     an assembled bundle (build/make-bundle.py)
# IMAGE_ZIP  the installed image's package zip; its esp/ folder is the replica
# R1_BUNDLE  optional: the delivered r1 bundle, to test applying this bundle on top of it
set -u
B=$(cd "$1" && pwd); Z=$2; B1=${3:-}; HERE=$(cd "$(dirname "$0")" && pwd)
R="/usr/bin/python3 -I $B/tools/k114s_repair.py"; pass=0; fail=0
ok(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: got [$2] want [$3]"; fi; }
has(){ if echo "$2" | grep -q -- "$3"; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: output lacks [$3]: $(echo "$2" | tail -2)"; fi; }
treesum(){ (cd "$1" && find . -type f ! -path './k114s-repair/*' -exec shasum -a 256 {} + | sort -k2 | shasum -a 256 | cut -c1-16); }
mkesp(){ d=$(mktemp -d); unzip -q -o "$Z" 'esp/*' -d $d; mkdir -p $d/esp/vendorfw
  /usr/bin/python3 -I - $d/esp/vendorfw $B "${1:-with}" <<'PY'
import sys,os; sys.path.insert(0,sys.argv[2]+'/tools')
from asahi_firmware.core import FWPackage, FWFile
p=FWPackage(sys.argv[1])
files=[('apple/aop-als-cal.bin',b'cal'*100),('apple/kernel-fw-a.bin',os.urandom(4096)),('apple/kernel-fw-b.bin',b'same'*500),('apple/kernel-fw-c.bin',b'same'*500)]
if sys.argv[3]=='with': files.insert(0,('apple/tpmtfw-k114s.bin',open(sys.argv[2]+'/payload/tpmtfw-k114s.bin','rb').read()))
for n,d in files: p.add_file(n,FWFile(n,d))
p.close()
PY
  echo $d/esp; }
E=$(mkesp); before=$(treesum $E)
out=$($R status --esp-dir $E 2>&1); has "status: original kernel" "$out" "original v272-4"; has "status: trial1 Stage 2" "$out" "boot-ctxr):   trial1"; has "status: trackpad firmware present" "$out" "trackpad firmware present; N1 firmware absent"
out=$($R check --esp-dir $E 2>&1); has "check passes" "$out" "Check passed"; ok "check writes nothing to the ESP" "$(treesum $E)" "$before"; ok "check leaves no repair dir" "$(ls $E | grep -c k114s-repair)" 0
out=$($R stage2 gp1c --esp-dir $E 2>&1); has "stage2 switch refused before apply" "$out" "apply the repair first"; ok "refused switch wrote nothing" "$(treesum $E)" "$before"
out=$($R apply --yes --esp-dir $E 2>&1); has "apply verifies" "$out" "Applied and verified"
out=$($R status --esp-dir $E 2>&1); has "after apply: Stage 2 r1" "$out" "boot-ctxr):   r1"; has "after apply: N1 firmware present" "$out" "N1 firmware present"; has "after apply: repair entries" "$out" "repair UKI on ESP:     yes; Limine repair entry: yes"; has "after apply: default is r1" "$out" "1 -> Omarchy K114s repair r1 (trackpad fix B)"
/usr/bin/python3 -I - $E $B <<'PY' && pass=$((pass+1)) && echo "PASS applied files are exactly as intended" || { fail=$((fail+1)); echo "FAIL applied file content"; }
import sys,hashlib,json,io,tarfile,gzip; E,B=sys.argv[1:3]; sys.path.insert(0,B+'/tools'); import k114s_esp_tool as t
rd=lambda p: open(p,'rb').read(); m=json.load(open(B+'/manifest.json')); h=lambda b: hashlib.sha256(b).hexdigest()
old=t.Uki(rd(E+'/EFI/Linux/omarchy_linux-aurora.efi'))
for ident in ('r1','r1a'):
    new=t.Uki(rd(E+'/EFI/Linux/omarchy_linux-aurora-k114s-%s.efi'%ident))
    assert new.content('.linux')==rd(B+'/payload/Image-k114s-'+ident)
    oi,ni=old.content('.initrd'),new.content('.initrd'); assert ni.startswith(oi) and len(ni)>len(oi)
    ex=ni[len(oi)+(-len(oi)%4):]; ents,_=t.newc_parse(ex); names=[e[0] for e in ents]
    assert names==['usr/lib/modules/7.3.0-17.v272-4-ARCH/kernel/drivers/hid/hid-magicmouse.ko','TRAILER!!!'], names
    assert ents[0][1]==0o100644
    assert ex[ents[0][4]:ents[0][4]+ents[0][2]]==rd(B+'/payload/hid-magicmouse-%s.ko'%ident)
    for s in ('.cmdline','.osrel','.uname','.text','.sbat'): assert new.content(s)==old.content(s)
    assert gzip.decompress(rd(E+'/k114s-repair/r2/vmlinuz-k114s-%s.gz'%ident))==rd(B+'/payload/Image-k114s-'+ident)
assert h(rd(E+'/m1n1/boot-ctxr.bin'))==m['stage2_sha256']['r1'] and h(rd(E+'/k114s-repair/k114s.dtb'))==m['payload']['t6050-k114s-r1.dtb']
lim=rd(E+'/limine.conf').decode(); lines=lim.split('\n'); ents=[l for l in lines if l.startswith('/')]
assert ents[0]=='/Omarchy K114s repair r1 (trackpad fix B)' and ents[1]=='/Omarchy K114s repair r1a (trackpad fix A)' and 'default_entry: 1' in lines and 'timeout: 5' in lines and 'quiet: no' in lines and 'quiet: yes' not in lines
orig=rd(E+'/k114s-repair/backup-before-r1/limine.conf').decode()
assert [l for l in orig.split('\n') if l.startswith('/')]==ents[2:]
oc=[l.strip() for l in orig.split('\n') if l.strip().startswith('cmdline:')][0]; assert lim.count(oc)==3
tf=tarfile.open(fileobj=io.BytesIO(rd(E+'/vendorfw/firmware.tar'))); n=[x.name for x in tf.getmembers()]
assert n[-1]=='apple/centauri/k114s-ftab.bin' and tf.extractfile(n[-1]).read()==rd(B+'/payload/k114s-ftab.bin')
assert 'FILE apple/centauri/k114s-ftab.bin SHA256 '+m['payload']['k114s-ftab.bin'] in rd(E+'/vendorfw/manifest.txt').decode()
PY
(cd $E/k114s-repair/r2 && shasum -a 256 -c SHA256SUMS >/dev/null 2>&1); ok "Linux-side files match their SHA256SUMS" "$?" 0
ok "Linux-side files are the bundle's" "$(cd $E/k114s-repair/r2 && for f in linux-persist.sh update-boot-ctxr-k114s apply-holds hold-guard 00-k114s-hold-guard.hook k114s-booted-esp k114s-edge-check README-linux.txt; do cmp -s $f $B/linux/$f || echo "$f differs"; done)" ""
out=$($R status --esp-dir $E 2>&1); has "status names the Linux-side revision" "$out" "Linux-side files:      r2"
ok "applied record names the revision and mode" "$(/usr/bin/python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["revision"], d["mode"])' $E/k114s-repair/applied-r2.json)" "r2 full"
out=$($R apply --yes --esp-dir $E 2>&1); has "second apply refused" "$out" "already applied"
out=$($R default r1a --esp-dir $E 2>&1); has "default r1a" "$out" "2 -> Omarchy K114s repair r1a (trackpad fix A)"
out=$($R default original --esp-dir $E 2>&1); has "default original" "$out" "4 -> linux-aurora"
out=$($R default r1 --esp-dir $E 2>&1); has "default r1" "$out" "1 -> Omarchy K114s repair r1 (trackpad fix B)"
for v in gp1c wifi trial1 r1; do out=$($R stage2 $v --esp-dir $E 2>&1); want=$v; [ $v = wifi ] && want=r1-wifi; [ $v = gp1c ] && want=r1-gp1c; has "stage2 $v" "$out" "boot-ctxr):   $want"; done
ok "pinned tree follows the Stage 2" "$(shasum -a 256 $E/k114s-repair/k114s.dtb | cut -c1-16)" "$(shasum -a 256 $B/payload/t6050-k114s-r1.dtb | cut -c1-16)"
out=$($R rollback stage2 --esp-dir $E 2>&1); has "rollback stage2" "$out" "boot-ctxr):   trial1"; has "rollback stage2 keeps kernel entries" "$out" "Limine repair entry: yes"
out=$($R rollback all --esp-dir $E 2>&1); has "rollback all" "$out" "Limine repair entry: no"; ok "rollback all restores every original boot file" "$(treesum $E)" "$before"
ok "rollback all resets the pinned tree to trial 1" "$(shasum -a 256 $E/k114s-repair/k114s.dtb | cut -c1-16)" "$(shasum -a 256 $B/payload/t6050-k114s-trial1.dtb | cut -c1-16)"
out=$($R apply --yes --esp-dir $E 2>&1); has "apply again after rollback all" "$out" "Applied and verified"; $R rollback all --esp-dir $E >/dev/null 2>&1; ok "second rollback all restores originals again" "$(treesum $E)" "$before"
out=$($R rollback kernel --esp-dir $E 2>&1); has "unknown rollback target refused cleanly" "$out" "rollback takes  stage2  or  all"
out=$($R apply --stage2 2>&1); has "missing option value refused cleanly" "$out" "needs a value"
for v in wifi gp1c keep; do E2=$(mkesp); b2=$(treesum $E2); out=$($R apply --yes --stage2 $v --esp-dir $E2 2>&1); has "apply --stage2 $v" "$out" "Applied and verified"; $R rollback all --esp-dir $E2 >/dev/null 2>&1; ok "rollback after --stage2 $v restores originals" "$(treesum $E2)" "$b2"; done
E3=$(mkesp without); out=$($R apply --yes --esp-dir $E3 2>&1); has "missing trackpad firmware is added" "$out" "trackpad firmware present"
E4=$(mkesp); cp $E4/m1n1/boot.bin $E4/m1n1/boot-ctxr.bin; out=$($R status --esp-dir $E4 2>&1); has "hook-overwritten Stage 2 recognised" "$out" "image-combined"; out=$($R apply --yes --esp-dir $E4 2>&1); has "hook-overwritten Stage 2 is repaired" "$out" "boot-ctxr):   r1"
E5=$(mkesp); printf 'X' | dd of=$E5/EFI/Linux/omarchy_linux-aurora.efi bs=1 seek=2000000 conv=notrunc 2>/dev/null; b5=$(treesum $E5); out=$($R apply --yes --esp-dir $E5 2>&1); has "foreign kernel refused" "$out" "does not carry the original v272-4 kernel"; ok "foreign kernel: nothing written" "$(treesum $E5)" "$b5"
E6=$(mkesp); head -c 4000000 /dev/urandom > $E6/m1n1/boot-ctxr.bin; b6=$(treesum $E6); out=$($R apply --yes --esp-dir $E6 2>&1); has "unknown Stage 2 refused" "$out" "not one this bundle knows"; ok "unknown Stage 2: nothing written" "$(treesum $E6)" "$b6"; out=$($R apply --yes --stage2 keep --esp-dir $E6 2>&1); has "unknown Stage 2 with keep: kernel-only apply" "$out" "Applied and verified"; out=$($R stage2 r1 --esp-dir $E6 2>&1); has "unknown live Stage 2 is never replaced by a switch" "$out" "not one this bundle knows"
E7=$(mkesp); rm $E7/vendorfw/firmware.tar; out=$($R check --esp-dir $E7 2>&1); has "missing vendor firmware refused" "$out" "STOPPED"
E8=$(mkesp); b8=$(treesum $E8); cp $B/payload/hid-magicmouse-r1.ko /tmp/k114s-mm.bak; printf 'Z' >> $B/payload/hid-magicmouse-r1.ko; out=$($R apply --yes --esp-dir $E8 2>&1); cp /tmp/k114s-mm.bak $B/payload/hid-magicmouse-r1.ko; has "tampered bundle refused" "$out" "does not match manifest.json"; ok "tampered bundle: nothing written" "$(treesum $E8)" "$b8"
E9=$(mkesp); b9=$(treesum $E9); out=$(echo no | $R apply --esp-dir $E9 2>&1); has "declined confirmation writes nothing" "$out" "nothing written"; ok "declined: ESP unchanged" "$(treesum $E9)" "$b9"
# an earlier run that stopped while making the backup: the next apply must make a real backup
EA=$(mkesp); bA=$(treesum $EA); mkdir -p $EA/k114s-repair/backup-before-r1; cp $EA/limine.conf $EA/k114s-repair/backup-before-r1/limine.conf
out=$($R status --esp-dir $EA 2>&1); has "partial backup directory is not reported as a backup" "$out" "backup on ESP:         no"
out=$($R apply --yes --esp-dir $EA 2>&1); has "apply after a partial backup" "$out" "Applied and verified"; ok "backup.json exists afterwards" "$(ls $EA/k114s-repair/backup-before-r1/backup.json 2>/dev/null | wc -l | tr -d ' ')" 1
out=$($R rollback all --esp-dir $EA 2>&1); ok "rollback after a partial-backup apply restores originals" "$(treesum $EA)" "$bA"
# an apply interrupted after the backup, mid-write: rollback all recovers
EB=$(mkesp); bB=$(treesum $EB); $R apply --yes --esp-dir $EB >/dev/null 2>&1; cp $EB/k114s-repair/backup-before-r1/limine.conf $EB/limine.conf; rm $EB/EFI/Linux/omarchy_linux-aurora-k114s-r1a.efi
out=$($R apply --yes --esp-dir $EB 2>&1); has "half-applied state: apply refuses" "$out" "use  rollback all  first"; $R rollback all --esp-dir $EB >/dev/null 2>&1; ok "half-applied state: rollback all restores originals" "$(treesum $EB)" "$bB"
# full partition: the write fails cleanly and nothing is left half-written
EC=$(mkesp); out=$(/usr/bin/python3 -I - $B $EC <<'PY'
import sys,os; sys.path.insert(0,sys.argv[1]+'/tools'); import k114s_repair as r
e=r.Esp(sys.argv[2]).open(True)
real=open
def boom(path,mode='r',*a,**k):
    if str(path).endswith('.k114s-new') and 'w' in mode:
        f=real(path,mode,*a,**k); f.write(b'partial'); f.close(); raise OSError(28,'No space left on device')
    return real(path,mode,*a,**k)
import builtins; builtins.open=boom
try: e.put('m1n1/boot-ctxr.bin',b'x'*100); print('NO-STOP')
except r.Stop as s: print('STOP:',s)
builtins.open=real
print('leftover:',[f for f in os.listdir(sys.argv[2]+'/m1n1') if f.endswith('.k114s-new')])
PY
); has "full partition stops cleanly" "$out" "STOP: writing m1n1/boot-ctxr.bin failed"; has "no half-written file left" "$out" "leftover: \[\]"; ok "target untouched after failed write" "$(shasum -a 256 $EC/m1n1/boot-ctxr.bin | cut -c1-16)" "2bf4d5f3e1f744e7"
/usr/bin/python3 $HERE/../lint-dtb.py $B/payload/t6050-k114s-r1.dtb $B/payload/t6050-k114s-r1-wifi.dtb $B/payload/t6050-k114s-r1-gp1c.dtb $B/payload/t6050-k114s-trial1.dtb >/dev/null 2>&1; ok "device tree lint (pin ranges fit, only pin 80 exposed)" "$?" 0
for v in r1 r1-wifi r1-gp1c trial1; do /usr/bin/python3 -I - $B $v <<'PY' && pass=$((pass+1)) && echo "PASS Stage 2 $v holds its payload tree" || { fail=$((fail+1)); echo "FAIL Stage 2 $v tree"; }
import sys,hashlib,json; B,v=sys.argv[1:3]; sys.path.insert(0,B+'/tools'); import k114s_esp_tool as t
m=json.load(open(B+'/manifest.json')); d=open(B+'/payload/boot-ctxr-k114s-%s.bin'%v,'rb').read()
p,trees,tr=t.stage2_split(d,m['aura_prefix_bytes']); name={'r1':'t6050-k114s-r1.dtb','r1-wifi':'t6050-k114s-r1-wifi.dtb','r1-gp1c':'t6050-k114s-r1-gp1c.dtb','trial1':'t6050-k114s-trial1.dtb'}[v]
assert len(trees)==1 and trees[0]==open(B+'/payload/'+name,'rb').read() and t.sha256(p)==m['aura_prefix_sha256'] and t.sha256(tr)==m['uboot_trailer_sha256'] and t.fdt_root_compatible(trees[0])[0]=='apple,k114s'
PY
done
# a changed Linux-side file in the bundle is refused before anything is written
ED=$(mkesp); bD=$(treesum $ED); cp $B/linux/hold-guard /tmp/k114s-hg.bak; echo '# x' >> $B/linux/hold-guard; out=$($R apply --yes --esp-dir $ED 2>&1); cp /tmp/k114s-hg.bak $B/linux/hold-guard; rm -f /tmp/k114s-hg.bak
has "tampered Linux-side file refused" "$out" "linux/hold-guard does not match manifest.json"; ok "tampered Linux-side file: nothing written" "$(treesum $ED)" "$bD"
# the copy of the boot files kept on the Mac is complete and checked
EE=$(mkesp); out=$($R apply --yes --esp-dir $EE 2>&1); W=$(echo "$out" | sed -n 's/^  \(.*work\/.*-apply-.*\)$/\1/p' | head -1)
ok "off-ESP copy of the boot files exists" "$(ls "$W/live/EFI/Linux/omarchy_linux-aurora.efi" "$W/live/m1n1/boot-ctxr.bin" "$W/live/m1n1/boot.bin" "$W/live/limine.conf" "$W/live/vendorfw/firmware.cpio" 2>/dev/null | wc -l | tr -d ' ')" 5
ok "off-ESP Stage 2 copy is the pre-apply one" "$(shasum -a 256 "$W/live/m1n1/boot-ctxr.bin" | cut -c1-16)" "2bf4d5f3e1f744e7"
# on top of r1: only the Linux-side files are added
if [ -n "$B1" ]; then
  R1="/usr/bin/python3 -I $B1/tools/k114s_repair.py"
  EF=$(mkesp); $R1 apply --yes --esp-dir $EF >/dev/null 2>&1; mid=$(treesum $EF); mids=$(cd $EF && find k114s-repair -type f ! -path 'k114s-repair/r2/*' ! -name applied-r2.json -exec shasum -a 256 {} + | sort -k2 | shasum -a 256 | cut -c1-16)
  out=$($R apply --yes --esp-dir $EF 2>&1); has "on top of r1: applies" "$out" "Applied and verified"; has "on top of r1: says only Linux-side files" "$out" "only the Linux-side files are added"
  ok "on top of r1: no boot file rewritten" "$(treesum $EF)" "$mid"
  ok "on top of r1: r1's files and the backup untouched" "$(cd $EF && find k114s-repair -type f ! -path 'k114s-repair/r2/*' ! -name applied-r2.json -exec shasum -a 256 {} + | sort -k2 | shasum -a 256 | cut -c1-16)" "$mids"
  (cd $EF/k114s-repair/r2 && shasum -a 256 -c SHA256SUMS >/dev/null 2>&1); ok "on top of r1: r2 Linux-side files verify" "$?" 0
  ok "on top of r1: record says linux-files-only" "$(/usr/bin/python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["mode"])' $EF/k114s-repair/applied-r2.json)" "linux-files-only"
  out=$($R status --esp-dir $EF 2>&1); has "on top of r1: both revisions listed" "$out" "Linux-side files:      r1, r2"
  out=$($R apply --yes --esp-dir $EF 2>&1); has "on top of r1: second apply refused" "$out" "already applied"
  out=$($R rollback all --esp-dir $EF 2>&1); has "on top of r1: r2 tool rolls back to the original" "$out" "Limine repair entry: no"
  EG=$(mkesp); bG=$(treesum $EG); $R1 apply --yes --esp-dir $EG >/dev/null 2>&1; rm $EG/k114s-repair/backup-before-r1/backup.json; g=$(treesum $EG); out=$($R apply --yes --esp-dir $EG 2>&1)
  has "repair files without a backup record: refused" "$out" "without a backup record"; ok "no backup record: nothing written" "$(treesum $EG)$(ls $EG/k114s-repair | grep -c '^r2$')" "${g}0"
fi
echo "macOS tool tests: $pass passed, $fail failed"
[ "$fail" = 0 ]
