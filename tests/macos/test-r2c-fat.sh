#!/bin/bash
# Bundle r2c against a faithful copy of the K114s ESP: a real FAT32 disk image the size of the
# Mac's partition (524,288,000 bytes, 4 KB clusters), holding every file read from the live ESP,
# topped up to the live free space. macOS, no root (hdiutil), nothing touches a real disk.
#   usage: test-r2c-fat.sh BUNDLE_R2C SNAPSHOT_DIR [BUNDLE_R2]
# SNAPSHOT_DIR is an esp_inventory.py output (inventory.json + esp/). Private: it holds Apple
# firmware, so it is never part of this repository. BUNDLE_R2, if given, must reproduce r2's
# refusal on the same layout.
set -u
B=$(cd "$1" && pwd); SNAP=$(cd "$2" && pwd); B2=${3:-}
HERE=$(cd "$(dirname "$0")" && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/k114s-fat.XXXXXX"); M=$W/mnt; mkdir -p "$M"
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: got [$2] want [$3]"; fi; }
has() { if echo "$2" | grep -q -- "$3"; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: output lacks [$3]: $(echo "$2" | tail -3)"; fi; }
T="/usr/bin/python3 -I $B/tools/k114s_repair.py"
cleanup() { hdiutil detach -quiet -force "$M" 2>/dev/null; rm -rf "$W"; }
trap cleanup EXIT
free_now() { /usr/bin/python3 -I -c 'import os,sys; s=os.statvfs(sys.argv[1]); print(s.f_bavail*s.f_frsize)' "$M"; }
treesum() { (cd "$M" && find . -type f ! -path './k114s-repair/*' ! -path './.fseventsd/*' ! -name '.k114s-filler*' -exec shasum -a 256 {} + | sort -k2 | shasum -a 256 | cut -c1-16); }
# '._NAME' files this test's own copying makes (macOS tags files this session creates); the
# ESP's own ones are in the inventory and stay
strip_ours() { /usr/bin/python3 -I - "$M" "$SNAP/inventory.json" <<'PY'
import json, os, sys
M, inv = sys.argv[1:3]; keep = set(json.load(open(inv))["files"])
for d, dirs, files in os.walk(M):
    for f in files:
        rel = os.path.relpath(os.path.join(d, f), M)
        if f.startswith("._") and rel not in keep:
            os.remove(os.path.join(d, f))
PY
}

want_free=$(/usr/bin/python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["free_bytes"])' "$SNAP/inventory.json")
make_esp() { # a fresh copy of the live ESP layout at $M
  hdiutil detach -quiet -force "$M" 2>/dev/null; rm -f "$W/esp.dmg"
  hdiutil create -quiet -sectors 1024000 -fs "MS-DOS FAT32" -layout NONE -volname EFIOMARC "$W/esp.dmg" || exit 1
  hdiutil attach -quiet -nobrowse -readwrite -mountpoint "$M" "$W/esp.dmg" || exit 1
  (cd "$SNAP/esp" && find . -type d ! -path './.fseventsd*' -exec mkdir -p "$M/{}" \; && find . -type f ! -path './.fseventsd/*' -exec cp -X {} "$M/{}" \;)
  strip_ours
  local have; have=$(free_now)
  if [ "$have" -gt "$want_free" ]; then mkfile -n $((have - want_free)) "$M/.k114s-filler"; strip_ours; fi
}
make_esp
ok "image cluster size is the live ESP's (4096)" "$(/usr/bin/python3 -I -c 'import os,sys; print(os.statvfs(sys.argv[1]).f_frsize)' "$M")" 4096
ok "image free space equals the live ESP's" "$(free_now)" "$want_free"
before=$(treesum)
ok "image holds the live ESP's files" "$(cd "$M" && find . -type f ! -path './.fseventsd/*' ! -name '.k114s-filler*' | wc -l | tr -d ' ')" \
  "$(/usr/bin/python3 -I -c 'import json,sys; print(len([f for f in json.load(open(sys.argv[1]))["files"] if not f.startswith(".fseventsd")]))' "$SNAP/inventory.json")"

# --- the failure seen on the Mac, reproduced --------------------------------------------------
if [ -n "$B2" ]; then
  out=$(/usr/bin/python3 -I "$B2/tools/k114s_repair.py" check --esp-dir "$M" 2>&1)
  has "r2 refuses this layout as it did on the Mac" "$out" "need about 477 MB, have 139 MB"
  ok "r2's refusal wrote nothing" "$(treesum)" "$before"
  rm -rf "$B2/work"
fi

# --- r2c check and apply ----------------------------------------------------------------------
out=$($T status --esp-dir "$M" 2>&1); has "status: original kernel, trial-1 Stage 2" "$out" "boot-ctxr):   trial1"
out=$($T check --esp-dir "$M" 2>&1); has "r2c check passes on this layout" "$out" "Check passed"
has "check prints the space plan" "$out" "the writes need"
ok "check writes nothing" "$(treesum)$(ls "$M" | grep -c k114s-repair)" "${before}0"
plan=$(ls -d "$B"/work/*-check-*/plan.json | tail -1)
read -r peak final after later < <(/usr/bin/python3 -I -c 'import json,sys; b=json.load(open(sys.argv[1]))["space"]; print(b["peak_bytes"], b["final_bytes"], b["free_after_bytes"], b["later_commands_need_bytes"])' "$plan")
echo "      plan: peak $peak, final $final, free after $after, later commands $later (free before $want_free)"
out=$($T apply --yes --esp-dir "$M" 2>&1); has "apply verifies" "$out" "Applied and verified"
got_after=$(free_now)
ok "free space after apply is at least the plan's, and within 128 KB of it" "$(( got_after >= after && got_after - after <= 131072 ))" 1
/usr/bin/python3 -I - "$M" "$B" "$SNAP" <<'PY' && { pass=$((pass+1)); echo "PASS applied files are exactly as intended"; } || { fail=$((fail+1)); echo "FAIL applied file content"; }
import sys, hashlib, json, os
M, B, SNAP = sys.argv[1:4]; sys.path.insert(0, B + '/tools'); import k114s_esp_tool as t
rd = lambda p: open(p, 'rb').read(); h = lambda b: hashlib.sha256(b).hexdigest()
m = json.load(open(B + '/manifest.json')); inv = json.load(open(SNAP + '/inventory.json'))
uki = rd(M + '/EFI/Linux/omarchy_linux-aurora-k114s.efi'); u = t.Uki(uki); o = t.Uki(rd(M + '/EFI/Linux/omarchy_linux-aurora.efi'))
assert h(u.content('.linux')) == m['payload']['Image-k114s-r1']
oi, ni = o.content('.initrd'), u.content('.initrd'); assert ni.startswith(oi)
ents, _ = t.newc_parse(ni[len(oi) + (-len(oi) % 4):]); names = [e[0] for e in ents]
assert names == ['vendorfw', 'vendorfw/apple', 'vendorfw/apple/centauri', 'vendorfw/apple/centauri/k114s-ftab.bin',
                 'usr/lib/modules/7.3.0-17.v272-4-ARCH/kernel/drivers/hid/hid-magicmouse.ko', 'TRAILER!!!'], names
assert [oct(e[1]) for e in ents[:3]] == ['0o40755'] * 3
for s in ('.cmdline', '.osrel', '.uname', '.text', '.sbat'): assert u.content(s) == o.content(s)
# the record's byte ranges, as Linux will read them
rec = dict((l.split(' ', 1)[0], l.split(' ', 1)[1]) for l in rd(M + '/k114s-repair/r2c/repair-uki.txt').decode().splitlines() if l and not l.startswith('#'))
assert rec['variant'] == 'r1'
path, size, digest = rec['uki'].split(); assert path == 'EFI/Linux/omarchy_linux-aurora-k114s.efi' and int(size) == len(uki) and digest == h(uki)
for key, name in (('kernel', 'Image-k114s-r1'), ('ftab', 'k114s-ftab.bin'), ('module', 'hid-magicmouse-r1.ko')):
    off, ln, dg = rec[key].split(); off, ln = int(off), int(ln)
    assert h(uki[off:off + ln]) == dg == m['payload'][name], key
assert h(rd(M + '/m1n1/boot-ctxr.bin')) == m['stage2_sha256']['r1'] and h(rd(M + '/k114s-repair/k114s.dtb')) == m['payload']['t6050-k114s-r1.dtb']
lim = rd(M + '/limine.conf').decode(); lines = lim.split('\n'); ents = [l for l in lines if l.lstrip().startswith('/')]
assert ents[0] == '/Omarchy K114s repair r1 (trackpad fix B)' and 'default_entry: 1' in lines and 'timeout: 5' in lines and 'quiet: no' in lines
orig = rd(M + '/k114s-repair/backup-before-r1/limine.conf').decode()
assert [l for l in orig.split('\n') if l.lstrip().startswith('/')] == ents[1:], 'original entries, snapshot entries included, kept in order'
assert lim.count('/EFI/Linux/omarchy_linux-aurora-k114s.efi') == 1
# untouched: everything that was there except limine.conf and the Stage 2
for rel, f in inv['files'].items():
    if rel in ('limine.conf', 'm1n1/boot-ctxr.bin') or rel.startswith('.fseventsd') or 'sha256' not in f: continue
    assert h(rd(M + '/' + rel)) == f['sha256'], rel
assert sorted(os.listdir(M + '/k114s-repair/r2c')) == sorted(['00-k114s-hold-guard.hook', '01-k114s-esp-space.hook', 'README-linux.txt', 'SHA256SUMS',
    'apply-holds', 'esp-space-guard', 'hid-magicmouse-r1.ko', 'hold-guard', 'k114s-booted-esp', 'k114s-edge-check', 'linux-persist.sh', 'repair-uki.txt', 'update-boot-ctxr-k114s'])
PY
(cd "$M/k114s-repair/r2c" && shasum -a 256 -c SHA256SUMS >/dev/null 2>&1); ok "Linux-side files match their SHA256SUMS" "$?" 0
out=$($T status --esp-dir "$M" 2>&1); has "status after apply: repair kernel r1" "$out" "repair UKI on ESP:     r1; Limine repair entry: yes"
out=$($T apply --yes --esp-dir "$M" 2>&1); has "second apply refused" "$out" "already applied"

# --- kernel swap, default, Stage 2 -------------------------------------------------------------
out=$($T kernel r1a --esp-dir "$M" 2>&1); has "kernel r1a" "$out" "Repair kernel is now: r1a"
/usr/bin/python3 -I - "$M" "$B" <<'PY' && { pass=$((pass+1)); echo "PASS after kernel r1a: image, menu and record are r1a's"; } || { fail=$((fail+1)); echo "FAIL kernel r1a content"; }
import sys, hashlib, json, os
M, B = sys.argv[1:3]; sys.path.insert(0, B + '/tools'); import k114s_esp_tool as t
rd = lambda p: open(p, 'rb').read(); h = lambda b: hashlib.sha256(b).hexdigest(); m = json.load(open(B + '/manifest.json'))
uki = rd(M + '/EFI/Linux/omarchy_linux-aurora-k114s.efi'); assert h(t.Uki(uki).content('.linux')) == m['payload']['Image-k114s-r1a']
rec = dict((l.split(' ', 1)[0], l.split(' ', 1)[1]) for l in rd(M + '/k114s-repair/r2c/repair-uki.txt').decode().splitlines() if l and not l.startswith('#'))
assert rec['variant'] == 'r1a' and rec['uki'].split()[2] == h(uki)
off, ln, dg = rec['module'].split(); assert h(uki[int(off):int(off) + int(ln)]) == m['payload']['hid-magicmouse-r1a.ko']
lim = rd(M + '/limine.conf').decode(); assert '/Omarchy K114s repair r1a (trackpad fix A)' in lim.split('\n') and 'trackpad fix B' not in lim
files = os.listdir(M + '/k114s-repair/r2c'); assert 'hid-magicmouse-r1a.ko' in files and 'hid-magicmouse-r1.ko' not in files
PY
(cd "$M/k114s-repair/r2c" && shasum -a 256 -c SHA256SUMS >/dev/null 2>&1); ok "after the swap the Linux-side files match their SHA256SUMS" "$?" 0
out=$($T kernel r1a --esp-dir "$M" 2>&1); has "swap to the same kernel refused" "$out" "already r1a"
out=$($T kernel r1 --esp-dir "$M" 2>&1); has "kernel r1 again" "$out" "Repair kernel is now: r1"
ok "free space after two swaps is as after apply (within 16 KB)" "$(( $(free_now) - got_after <= 16384 && got_after - $(free_now) <= 16384 ))" 1
out=$($T default original --esp-dir "$M" 2>&1); has "default original" "$out" "3 -> linux-aurora"
out=$($T default repair --esp-dir "$M" 2>&1); has "default repair" "$out" "1 -> Omarchy K114s repair r1"
out=$($T stage2 gp1c --esp-dir "$M" 2>&1); has "stage2 gp1c" "$out" "boot-ctxr):   r1-gp1c"
out=$($T rollback stage2 --esp-dir "$M" 2>&1); has "rollback stage2" "$out" "boot-ctxr):   trial1"; has "rollback stage2 keeps the repair kernel" "$out" "Limine repair entry: yes"
out=$($T rollback all --esp-dir "$M" 2>&1); has "rollback all" "$out" "Limine repair entry: no"
ok "rollback all restores every original file" "$(treesum)" "$before"
ok "rollback all gives the space back (the k114s-repair folder stays)" "$(( ($(free_now) - want_free) / -1048576 < 6 ))" 1
out=$($T apply --yes --esp-dir "$M" 2>&1); has "apply works again after rollback all" "$out" "Applied and verified"
$T rollback all --esp-dir "$M" >/dev/null 2>&1; ok "second rollback all restores originals again" "$(treesum)" "$before"

# --- too little space -------------------------------------------------------------------------
make_esp; before=$(treesum)
mkfile -n $(( want_free - peak - (8 << 20) + (1 << 20) )) "$M/.k114s-filler2"; strip_ours
out=$($T check --esp-dir "$M" 2>&1); has "1 MB short of the plan: check refuses" "$out" "not enough free space on the ESP"
out=$($T apply --yes --esp-dir "$M" 2>&1); has "1 MB short: apply refuses" "$out" "not enough free space on the ESP"
ok "refusal wrote nothing" "$(treesum)$(ls "$M" | grep -c k114s-repair)" "${before}0"
rm -f "$M/.k114s-filler2"

# --- interrupted while writing the repair kernel ------------------------------------------------
before=$(treesum); free0=$(free_now)
out=$(/usr/bin/python3 -I - "$B" "$M" <<'PY'
import sys, os, builtins
B, M = sys.argv[1:3]; sys.path.insert(0, B + '/tools'); import k114s_repair as r
real = builtins.open
def boom(path, mode='r', *a, **k):
    if str(path).endswith('omarchy_linux-aurora-k114s.efi.k114s-new') and 'w' in mode:
        f = real(path, mode, *a, **k); f.write(b'partial' * 100000); f.close(); raise OSError(5, 'Input/output error')
    return real(path, mode, *a, **k)
builtins.open = boom
try:
    r.main(['k114s-repair', 'apply', '--yes', '--esp-dir', M]); print('NO-STOP')
except r.Stop as s:
    print('STOP:', s)
builtins.open = real
print('leftover:', [f for f in os.listdir(M + '/EFI/Linux') if f.endswith('.k114s-new')])
PY
)
has "interrupted write stops" "$out" "STOP: writing EFI/Linux/omarchy_linux-aurora-k114s.efi failed"
has "no half-written file left" "$out" "leftover: \[\]"
ok "no repair kernel, menu unchanged" "$(ls "$M/EFI/Linux" | grep -c k114s)$(grep -c 'K114s repair' "$M/limine.conf")" "00"
ok "Stage 2 unchanged (it is written after the kernel)" "$(shasum -a 256 "$M/m1n1/boot-ctxr.bin" | cut -c1-16)" "2bf4d5f3e1f744e7"
out=$($T rollback all --esp-dir "$M" 2>&1); has "rollback all after the interruption" "$out" "Rolled back"
ok "after the interruption and rollback every original file is back" "$(treesum)" "$before"
out=$($T apply --yes --esp-dir "$M" 2>&1); has "apply after the interruption" "$out" "Applied and verified"

# --- tampered bundle --------------------------------------------------------------------------
make_esp; before=$(treesum)
cp "$B/payload/k114s-ftab.bin" "$W/ftab.bak"; printf 'Z' >> "$B/payload/k114s-ftab.bin"
out=$($T apply --yes --esp-dir "$M" 2>&1); cp "$W/ftab.bak" "$B/payload/k114s-ftab.bin"
has "tampered firmware refused" "$out" "does not match manifest.json"; ok "tampered: nothing written" "$(treesum)$(ls "$M" | grep -c k114s-repair)" "${before}0"
out=$($T apply --kernel r2 --esp-dir "$M" 2>&1); has "unknown kernel option refused" "$out" "kernel must be r1 or r1a"

rm -rf "$B/work"
ok "the tool left no '._' files of its own" "$(cd "$M" && find . -name '._*' ! -path './omarchy/._install.conf' | wc -l | tr -d ' ')" 0
echo "r2c FAT-image tests: $pass passed, $fail failed"
[ "$fail" = 0 ]
