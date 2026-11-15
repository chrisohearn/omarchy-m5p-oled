#!/bin/bash
# The macOS tool on an ESP whose original kernel image (EFI/Linux/omarchy_linux-aurora.efi) was removed on purpose,
# as the r3a trial does (docs/r3-integration.md, step D). A synthetic bundle and ESP: no payload, no Apple files, no root.
# It proves what the tool does when that file is absent, not that the real ESP behaves: that is the first
# `status` run on the Mac.   usage: test-no-original-uki.sh
set -u
H=$(cd "$(dirname "$0")" && pwd); W=$(mktemp -d "${TMPDIR:-/tmp}/k114s-no-uki-test.XXXXXX"); trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: got [$2] want [$3]"; fi; }
has() { if printf '%s' "$2" | grep -q -- "$3"; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: lacks [$3]: $(printf '%s' "$2" | tail -3)"; fi; }
sum() { (cd "$1" && find . -type f -exec sha256sum {} + | sort -k2 | sha256sum | cut -c1-16); }
B=$W/bundle; E=$W/esp; mkdir -p "$B/tools" "$B/payload" "$E/EFI/Linux" "$E/m1n1" "$E/vendorfw" "$E/k114s-repair/backup-before-r1/m1n1"
cp "$H"/../../macos/tools/k114s_repair.py "$H"/../../macos/tools/k114s_esp_tool.py "$B/tools/"; cp -r "$H"/../../macos/tools/asahi_firmware "$B/tools/"
python3 -I - "$B" "$E" <<'PY'
import hashlib, io, json, os, sys, tarfile
B, E = sys.argv[1:3]; h = lambda b: hashlib.sha256(b).hexdigest()
w = lambda p, d: open(p, "wb").write(d)
import gzip, struct
def fdt(tag):   # a minimal device tree: root compatible = apple,k114s apple,t6050, plus a tag property
    strs = b"compatible\0tag\0"; val = b"apple,k114s\0apple,t6050\0"
    st = struct.pack(">II", 1, 0) + struct.pack(">III", 3, len(val), 0) + val + b"\0" * (-len(val) % 4)
    st += struct.pack(">III", 3, len(tag), 11) + tag + b"\0" * (-len(tag) % 4) + struct.pack(">II", 2, 9)
    off = 40 + 16; total = off + len(st) + len(strs)
    return struct.pack(">10I", 0xd00dfeed, total, off, off + len(st), 40, 17, 16, 0, len(strs), len(st)) + b"\0" * 16 + st + strs
prefix, trailer = b"AURA", gzip.compress(b"u-boot")
d1, d2 = fdt(b"r1"), fdt(b"trial1")
r1, t1, comb = prefix + d1 + trailer, prefix + d2 + trailer, b"image-combined"
w(B + "/payload/boot-ctxr-k114s-r1.bin", r1); w(B + "/payload/t6050-k114s-r1.dtb", d1)
w(B + "/payload/boot-ctxr-k114s-trial1.bin", t1); w(B + "/payload/t6050-k114s-trial1.dtb", d2)
payload = {n: h(open(B + "/payload/" + n, "rb").read()) for n in os.listdir(B + "/payload")}
json.dump({"stage2_sha256": {"r1": h(r1), "trial1": h(t1), "image-combined": h(comb)}, "payload": payload,
           "original_kernel_sha256": "x", "aura_prefix_bytes": 4, "aura_prefix_sha256": h(prefix), "uboot_trailer_sha256": h(trailer)}, open(B + "/manifest.json", "w"))
w(E + "/m1n1/boot-ctxr.bin", r1); w(E + "/m1n1/boot.bin", comb)
w(E + "/EFI/Linux/omarchy_linux-aurora-k114s.efi", b"not a PE: the repair image stand-in")
tf = io.BytesIO(); t = tarfile.open(fileobj=tf, mode="w"); i = tarfile.TarInfo("apple/tpmtfw-k114s.bin"); i.size = 3; t.addfile(i, io.BytesIO(b"abc")); t.close()
w(E + "/vendorfw/firmware.tar", tf.getvalue()); w(E + "/vendorfw/firmware.cpio", b"cpio"); w(E + "/vendorfw/manifest.txt", b"m")
w(E + "/limine.conf", b"timeout: 5\ndefault_entry: 1\n/Omarchy K114s repair r1 (trackpad fix B)\n  protocol: efi\n  path: boot():/EFI/Linux/omarchy_linux-aurora-k114s.efi\n/+Omarchy\n  //linux-k114s\n")
bk = E + "/k114s-repair/backup-before-r1"
w(bk + "/m1n1/boot-ctxr.bin", t1); w(bk + "/limine.conf", b"default_entry: 2\n/Omarchy\n  //linux-aurora\n")
json.dump({"files": {"m1n1/boot-ctxr.bin": h(t1), "limine.conf": h(open(bk + "/limine.conf", "rb").read())}}, open(bk + "/backup.json", "w"))
w(E + "/k114s-repair/applied-r2c.json", b"{}")
PY
R="python3 -I $B/tools/k114s_repair.py"; before=$(sum "$E")
out=$($R status --esp-dir "$E" 2>&1); has "status works without the original image" "$out" "REMOVED"; has "status still reads the Stage 2" "$out" "boot-ctxr):   r1"
has "status still lists the repair entry as the default" "$out" "1 -> Omarchy K114s repair r1 (trackpad fix B)"
for c in "default original" "kernel r1a" "rollback all" "apply --yes"; do out=$($R $c --esp-dir "$E" 2>&1); has "'$c' stops" "$out" "STOPPED"; ok "'$c' wrote nothing" "$(sum "$E")" "$before"; done
out=$($R rollback all --esp-dir "$E" 2>&1); has "rollback all names the way out" "$out" "rollback stage2  and  default repair"
out=$($R default original --esp-dir "$E" 2>&1); has "default original says why" "$out" "that entry cannot start"
out=$($R default repair --esp-dir "$E" 2>&1); has "default repair works" "$out" "Default boot entry changed"; ok "default repair keeps default_entry 1" "$(grep -c '^default_entry: 1' "$E/limine.conf")" 1
out=$($R stage2 trial1 --esp-dir "$E" 2>&1); has "stage2 switch works" "$out" "Stage 2 is now: trial1"
out=$($R stage2 r1 --esp-dir "$E" 2>&1); has "stage2 r1 works" "$out" "Stage 2 is now: r1"
out=$($R rollback stage2 --esp-dir "$E" 2>&1); has "rollback stage2 works" "$out" "Rolled back: m1n1/boot-ctxr.bin"
ok "the original image is still absent after all of that" "$(ls "$E/EFI/Linux")" "omarchy_linux-aurora-k114s.efi"
# The tool that was delivered before this change (commit 16b7dd6, the first r3a commit) does not recognise the ESP once the original image is gone:
# the runbook therefore requires the fixed tool on the Mac before the image is removed. This keeps that claim tested.
if O=$(git -C "$H" show 16b7dd6:macos/tools/k114s_repair.py 2>/dev/null); then
  cp -r "$B" "$W/old" && printf '%s\n' "$O" > "$W/old/tools/k114s_repair.py"; before=$(sum "$E")
  for c in status "default repair" "stage2 r1" "rollback stage2"; do out=$(python3 -I "$W/old/tools/k114s_repair.py" $c --esp-dir "$E" 2>&1); has "OLD tool '$c' stops: it does not recognise the ESP" "$out" "STOPPED"; done
  ok "the old tool wrote nothing" "$(sum "$E")" "$before"
else echo "SKIP old-tool case (commit 16b7dd6 not in this clone)"; fi
echo "macOS tool (no original image) tests: $pass passed, $fail failed"; [ "$fail" = 0 ]
