#!/bin/bash
# The macOS tool on the ESP of the r3a promotion (docs/r3a-promotion.md): the repair image and its entry removed, the
# original image gone, the r3a image omarchy_linux-k114s.efi the default by the entry path Omarchy/linux-k114s, and the
# Stage 2 the GPU file. A synthetic bundle and ESP: no payload, no Apple files, no root. It proves what the tool does on
# that layout, not that the real ESP behaves: that is the `status` run on the Mac in runbook step P4b.
#   usage: test-promoted-esp.sh
set -u
H=$(cd "$(dirname "$0")" && pwd); W=$(mktemp -d "${TMPDIR:-/tmp}/k114s-promoted-test.XXXXXX"); trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: got [$2] want [$3]"; fi; }
has() { if printf '%s' "$2" | grep -q -- "$3"; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: lacks [$3]: $(printf '%s' "$2" | tail -3)"; fi; }
sum() { (cd "$1" && find . -type f -exec sha256sum {} + | sort -k2 | sha256sum | cut -c1-16); }
B=$W/bundle; E=$W/esp
mkesp() { # $1: before (repair entry still first, default the path) | after (promoted: no repair) | aurora (after, plus the hook's linux-aurora entry in front)
  #         | window (the display window of docs/r3-display-plan.md 4.4: after, plus the r3b image and its entry behind r3a's)
  rm -rf "$B" "$E"; mkdir -p "$B/tools" "$B/payload" "$E/EFI/Linux" "$E/m1n1" "$E/vendorfw" "$E/k114s-repair/backup-before-r1/m1n1"
  cp "$H"/../../macos/tools/k114s_repair.py "$H"/../../macos/tools/k114s_esp_tool.py "$B/tools/"; cp -r "$H"/../../macos/tools/asahi_firmware "$B/tools/"
  python3 -I - "$B" "$E" "$1" <<'PY'
import hashlib, io, json, os, sys, tarfile, gzip, struct
B, E, layout = sys.argv[1:4]; h = lambda b: hashlib.sha256(b).hexdigest()
w = lambda p, d: open(p, "wb").write(d)
def fdt(tag):
    strs = b"compatible\0tag\0"; val = b"apple,k114s\0apple,t6050\0"
    st = struct.pack(">II", 1, 0) + struct.pack(">III", 3, len(val), 0) + val + b"\0" * (-len(val) % 4)
    st += struct.pack(">III", 3, len(tag), 11) + tag + b"\0" * (-len(tag) % 4) + struct.pack(">II", 2, 9)
    off = 40 + 16; total = off + len(st) + len(strs)
    return struct.pack(">10I", 0xd00dfeed, total, off, off + len(st), 40, 17, 16, 0, len(strs), len(st)) + b"\0" * 16 + st + strs
prefix, trailer = b"AURA", gzip.compress(b"u-boot")
d1, d2, dg = fdt(b"r1"), fdt(b"trial1"), fdt(b"gpu")
r1, t1, gpu, comb = prefix + d1 + trailer, prefix + d2 + trailer, prefix + dg + trailer, b"image-combined"
w(B + "/payload/boot-ctxr-k114s-r1.bin", r1); w(B + "/payload/t6050-k114s-r1.dtb", d1)
w(B + "/payload/boot-ctxr-k114s-trial1.bin", t1); w(B + "/payload/t6050-k114s-trial1.dtb", d2)
payload = {n: h(open(B + "/payload/" + n, "rb").read()) for n in os.listdir(B + "/payload")}
json.dump({"stage2_sha256": {"r1": h(r1), "trial1": h(t1), "image-combined": h(comb)}, "payload": payload,
           "original_kernel_sha256": "x", "aura_prefix_bytes": 4, "aura_prefix_sha256": h(prefix), "uboot_trailer_sha256": h(trailer)}, open(B + "/manifest.json", "w"))
w(E + "/m1n1/boot-ctxr.bin", gpu); w(E + "/m1n1/boot.bin", comb); w(E + "/k114s-repair/k114s.dtb", dg)
k = b"the r3a image stand-in"; w(E + "/EFI/Linux/omarchy_linux-k114s.efi", k); kh = hashlib.blake2b(k).hexdigest()
tf = io.BytesIO(); t = tarfile.open(fileobj=tf, mode="w"); i = tarfile.TarInfo("apple/tpmtfw-k114s.bin"); i.size = 3; t.addfile(i, io.BytesIO(b"abc")); t.close()
w(E + "/vendorfw/firmware.tar", tf.getvalue()); w(E + "/vendorfw/firmware.cpio", b"cpio"); w(E + "/vendorfw/manifest.txt", b"m")
head = "timeout: 5\nquiet: no\ndefault_entry: Omarchy/linux-k114s\nhash_mismatch_panic: no\n"
repair = ("### K114s repair (added from macOS; remove this block to undo)\n/Omarchy K114s repair r1 (trackpad fix B)\n  protocol: efi\n"
          "  path: boot():/EFI/Linux/omarchy_linux-aurora-k114s.efi\n  cmdline: root=UUID=00000000-0000-0000-0000-000000000000 rw\n\n")
# the static fallback kept off the ESP (P4b) and the block kept on it (P0e), and apply's record of the repair image
ri = b"not a PE: the repair image stand-in"
os.makedirs(E + "/k114s-repair/r2c"); os.makedirs(E + "/k114s-repair/promotion"); os.makedirs(B + "/promotion")
w(E + "/k114s-repair/r2c/repair-uki.txt", ("# record\nvariant r1\nuki EFI/Linux/omarchy_linux-aurora-k114s.efi %d %s\n" % (len(ri), h(ri))).encode())
w(E + "/k114s-repair/promotion/repair-block.conf", repair.encode()); w(B + "/promotion/repair-block.conf", repair.encode())
w(B + "/promotion/omarchy_linux-aurora-k114s.efi", ri)
aur = ""
if layout == "aurora":
    a = b"the hook-built linux-aurora image stand-in"; w(E + "/EFI/Linux/omarchy_linux-aurora.efi", a)
    aur = "  //linux-aurora\n  protocol: efi\n  path: boot():/EFI/Linux/omarchy_linux-aurora.efi#%s\n" % hashlib.blake2b(a).hexdigest()
r3b = ""
if layout == "window":
    b = b"the r3b image stand-in"; w(E + "/EFI/Linux/omarchy_linux-k114s-r3b.efi", b)
    r3b = "  //linux-k114s-r3b\n  protocol: efi\n  path: boot():/EFI/Linux/omarchy_linux-k114s-r3b.efi#%s\n" % hashlib.blake2b(b).hexdigest()
folder = "/+Omarchy\ncomment: Omarchy\n" + aur + "  //linux-k114s\n  protocol: efi\n  path: boot():/EFI/Linux/omarchy_linux-k114s.efi#%s\n" % kh + r3b
if layout == "before":
    w(E + "/EFI/Linux/omarchy_linux-aurora-k114s.efi", ri)
    w(E + "/limine.conf", (head + repair + folder).encode())
else:
    w(E + "/limine.conf", (head + folder).encode())
bk = E + "/k114s-repair/backup-before-r1"
w(bk + "/m1n1/boot-ctxr.bin", t1); w(bk + "/limine.conf", b"default_entry: 2\n/Omarchy\n  //linux-aurora\n")
json.dump({"files": {"m1n1/boot-ctxr.bin": h(t1), "limine.conf": h(open(bk + "/limine.conf", "rb").read())}}, open(bk + "/backup.json", "w"))
w(E + "/k114s-repair/applied-r2c.json", b"{}")
PY
}
R="python3 -I $B/tools/k114s_repair.py"
def() { sed -n 's/^default_entry: //p' "$E/limine.conf"; }

# --- before step P5: the repair entry is still first, the default is the path (steps P2 to P4) -----------------------
mkesp before
out=$($R status --esp-dir "$E" 2>&1); has "before P5: status reads the path default" "$out" "Limine default entry:  Omarchy/linux-k114s -> linux-k114s (entry 3)"
has "before P5: status reads the synthetic GPU Stage 2 as the bundle's loader with one other tree" "$out" "boot-ctxr):   same-loader-other-trees(1)"
ok "status names this Mac's GPU and r3a Stage 2 files by their hashes" "$(cd "$B/tools" && python3 -I -c 'import sys; sys.path.insert(0, "."); import k114s_repair as r
print(r.LOCAL_STAGE2["9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc"].split()[0], r.LOCAL_STAGE2["5164bb1e1be1fba39aee64229863b2f835828edd8b4f90e8cfa91e71a6fd8cd9"].split()[0])')" "r3-gpu r3a"
ok "a Stage 2 whose hash is listed is named, before the loader check" "$(cd "$B/tools" && python3 -I -c 'import sys, hashlib; sys.path.insert(0, "."); import k114s_repair as r
r.LOCAL_STAGE2[hashlib.sha256(b"gpu-file").hexdigest()] = "r3-gpu (test)"; print(r.stage2_state(b"gpu-file", {"stage2_sha256": {}}))')" "r3-gpu (test)"
out=$($R default repair --esp-dir "$E" 2>&1); has "before P5: default repair works over a path default" "$out" "Default boot entry changed"; ok "before P5: default repair writes 1" "$(def)" 1
out=$($R default k114s --esp-dir "$E" 2>&1); has "before P5: default k114s puts the path back" "$out" "Default boot entry changed"; ok "before P5: the path is written" "$(def)" "Omarchy/linux-k114s"

# --- after step P5: no repair image, no original image: only the r3a image --------------------------------------------
mkesp after; before=$(sum "$E")
out=$($R status --esp-dir "$E" 2>&1); has "after P5: status finds the ESP by the r3a image" "$out" "installed kernel UKI:  REMOVED"
has "after P5: status says the r3a image is the Linux image" "$out" "omarchy_linux-k114s.efi is"
has "after P5: status reads the path default as entry 2" "$out" "Omarchy/linux-k114s -> linux-k114s (entry 2)"
has "after P5: no repair image, no repair entry" "$out" "repair UKI on ESP:     no; Limine repair entry: no"
ok "after P5: status wrote nothing" "$(sum "$E")" "$before"
for c in "default repair" "default original" "rollback all" "kernel r1a" "apply --yes" "default aurora"; do
  out=$($R $c --esp-dir "$E" 2>&1); has "after P5: '$c' stops" "$out" "STOPPED"; ok "after P5: '$c' wrote nothing" "$(sum "$E")" "$before"
done
out=$($R default repair --esp-dir "$E" 2>&1); has "after P5: default repair names the way out" "$out" "Use  default k114s  or  default aurora"
out=$($R rollback all --esp-dir "$E" 2>&1); has "after P5: rollback all says why" "$out" "the r3a promotion removed it on purpose"
out=$($R default aurora --esp-dir "$E" 2>&1); has "after P5: default aurora stops while that entry does not exist" "$out" "has no entry Omarchy/linux-aurora"
out=$($R stage2 r1 --esp-dir "$E" 2>&1); has "after P5: stage2 r1 works (the way back from the GPU tree)" "$out" "Stage 2 is now: r1"
ok "after P5: stage2 r1 wrote the r1 file and the r1 pin" "$(cmp -s "$E/m1n1/boot-ctxr.bin" "$B/payload/boot-ctxr-k114s-r1.bin" && cmp -s "$E/k114s-repair/k114s.dtb" "$B/payload/t6050-k114s-r1.dtb"; echo $?)" 0
out=$($R default k114s --esp-dir "$E" 2>&1); has "after P5: default k114s works" "$out" "Default boot entry changed"; ok "after P5: default k114s keeps the path" "$(def)" "Omarchy/linux-k114s"
echo x >> "$E/EFI/Linux/omarchy_linux-k114s.efi"; b2=$(sum "$E")
out=$($R default k114s --esp-dir "$E" 2>&1); has "after P5: a default whose image does not match its hash is refused" "$out" "does not match its hash"; ok "that refusal wrote nothing" "$(sum "$E")" "$b2"

# --- after step P6a: the hook's linux-aurora entry is in front of linux-k114s ----------------------------------------
mkesp aurora
out=$($R status --esp-dir "$E" 2>&1); has "after P6a: the path default still names linux-k114s, now entry 3" "$out" "Omarchy/linux-k114s -> linux-k114s (entry 3)"
out=$($R default aurora --esp-dir "$E" 2>&1); has "after P6a: default aurora works (the second image)" "$out" "Default boot entry changed"; ok "after P6a: written as a path" "$(def)" "Omarchy/linux-aurora"
out=$($R default k114s --esp-dir "$E" 2>&1); ok "after P6a: and back" "$(def)" "Omarchy/linux-k114s"
out=$($R rollback all --esp-dir "$E" 2>&1); has "after P6a: rollback all still stops, though an omarchy_linux-aurora.efi is there again" "$out" "STOPPED"

# --- restore-repair: the static repair image back from macOS when both hook-built images fail (section 5) ------------
# RF runs the tool with the ESP's free space faked to $1 bytes (the real ESP has about 111 MB after P5b: too little for
# the 111.8 MB image unless omarchy_linux-aurora.efi goes first)
RF() { local f=$1; shift; python3 -I -c '
import sys; sys.path.insert(0, sys.argv[1]); import k114s_repair as r
r.Esp.free = lambda self, f=int(sys.argv[2]): f
try: sys.exit(r.main(["k114s-repair"] + sys.argv[3:]))
except r.Stop as stop: print("k114s-repair: STOPPED: %s" % stop); sys.exit(1)' "$B/tools" "$f" "$@"; }
rimg=$B/promotion/omarchy_linux-aurora-k114s.efi
mkesp before; cp "$E/limine.conf" "$W/conf.p2"; before=$(sum "$E")
out=$($R restore-repair --check --esp-dir "$E" 2>&1)
has "before P5: restore-repair --check passes" "$out" "restore-repair check passed"
has "before P5: --check proves the saved block is the live repair entry, byte for byte" "$out" "is exactly the saved block"
has "before P5: --check checks the bundle's image against the ESP's record" "$out" "matches the ESP's record"
ok "before P5: --check wrote nothing" "$(sum "$E")" "$before"
ok "--check never prints the command line" "$(printf '%s' "$out" | grep -c 'root=UUID')" 0
out=$($R restore-repair --esp-dir "$E" 2>&1); has "before P5: restore-repair refuses while the repair entry is there" "$out" "use  default repair"
ok "and writes nothing" "$(sum "$E")" "$before"
sed -i 's#rw$#rw quiet#' "$E/limine.conf"; out=$($R restore-repair --check --esp-dir "$E" 2>&1)
has "before P5: --check stops when the live repair entry is not the saved block" "$out" "is not the saved block"
# the promoted ESP: the block cut the way P5a cuts it (k114s-lib.sh), then the hook's linux-aurora entry in front (P5b)
bash -c '. "$1/linux/k114s-lib.sh"; limine_remove_entry_block "$2" EFI/Linux/omarchy_linux-aurora-k114s.efi' _ "$H/../.." "$W/conf.p2" > "$W/conf.p5"
mkesp aurora
ok "the P5a cut of the synthetic menu is the saved block, line for line" \
  "$(diff "$W/conf.p2" "$W/conf.p5" | sed -n 's/^< //p' | cmp -s - "$E/k114s-repair/promotion/repair-block.conf"; echo $?)" 0
before=$(sum "$E")
out=$(RF 1000000 restore-repair --check --esp-dir "$E" 2>&1)
has "after P5b: --check with 1 MB free plans to remove the linux-aurora image" "$out" "omarchy_linux-aurora.efi and its entry would be removed"
has "after P5b: --check passes" "$out" "restore-repair check passed"
ok "after P5b: --check wrote nothing" "$(sum "$E")" "$before"
cp "$E/limine.conf" "$W/conf.p5b"
out=$(RF 1000000 restore-repair --esp-dir "$E" 2>&1)
has "after P5b: restore-repair, short of space: done" "$out" "Restored the repair entry as entry 1"
ok "it removed the linux-aurora image and its entry, and put the bundle's repair image on the ESP" \
  "$(test -e "$E/EFI/Linux/omarchy_linux-aurora.efi"; echo $?) $(grep -c -e '//linux-aurora' -e 'omarchy_linux-aurora[.]efi' "$E/limine.conf") $(cmp -s "$rimg" "$E/EFI/Linux/omarchy_linux-aurora-k114s.efi"; echo $?)" "1 0 0"
ok "the menu is the one before P5 with default_entry 1: the default line is the only difference" \
  "$(diff "$W/conf.p2" "$E/limine.conf" | grep '^[<>]' | tr '\n' '|')" "< default_entry: Omarchy/linux-k114s|> default_entry: 1|"
out=$($R status --esp-dir "$E" 2>&1)
has "after restore-repair: status reads entry 1, the repair entry" "$out" "Limine default entry:  1 -> Omarchy K114s repair r1 (trackpad fix B) (entry 1)"
has "after restore-repair: the repair entry is back" "$out" "Limine repair entry: yes"
ok "restore-repair never prints the command line" "$(printf '%s' "$out" | grep -c 'root=UUID')" 0
out=$($R default k114s --esp-dir "$E" 2>&1); ok "after restore-repair: default k114s goes back to the promoted default" "$(def)" "Omarchy/linux-k114s"
mkesp aurora; out=$($R restore-repair --esp-dir "$E" 2>&1)
ok "with room to spare restore-repair keeps the linux-aurora image and its entry" \
  "$(test -e "$E/EFI/Linux/omarchy_linux-aurora.efi"; echo $?) $(grep -c '//linux-aurora' "$E/limine.conf") $(def)" "0 1 1"
mkesp aurora; rm "$E/EFI/Linux/omarchy_linux-aurora.efi"; out=$($R restore-repair --esp-dir "$E" 2>&1)
ok "a run stopped after removing the linux-aurora image is finished by running it again (its entry goes)" \
  "$(grep -c -e '//linux-aurora' -e 'omarchy_linux-aurora[.]efi' "$E/limine.conf") $(def)" "0 1"
mkesp after; before=$(sum "$E"); out=$(RF 1000000 restore-repair --esp-dir "$E" 2>&1)
has "short of space with no linux-aurora image to remove: stops" "$out" "no omarchy_linux-aurora.efi to remove"
ok "and writes nothing (no space)" "$(sum "$E")" "$before"
mkesp aurora; echo x >> "$rimg"; before=$(sum "$E"); out=$($R restore-repair --esp-dir "$E" 2>&1)
has "a bundle image that is not the recorded one stops" "$out" "is not the repair image the ESP's record names"
ok "and writes nothing (wrong image)" "$(sum "$E")" "$before"
mkesp aurora; rm "$rimg"; out=$($R restore-repair --esp-dir "$E" 2>&1); has "no bundle image: stops" "$out" "no repair image at"
mkesp aurora; out=$($R restore-repair "$W/nothing.efi" --esp-dir "$E" 2>&1); has "an IMAGE argument is used" "$out" "no repair image at $W/nothing.efi"
mkesp aurora; rm "$E/k114s-repair/promotion/repair-block.conf" "$B/promotion/repair-block.conf"; before=$(sum "$E")
out=$($R restore-repair --esp-dir "$E" 2>&1); has "no saved block: stops" "$out" "no saved repair block"; ok "and writes nothing (no block)" "$(sum "$E")" "$before"
mkesp aurora; rm "$E/k114s-repair/promotion/repair-block.conf"; out=$($R restore-repair --esp-dir "$E" 2>&1)
has "the bundle's copy of the block alone is enough" "$out" "Restored the repair entry"
mkesp aurora; echo '# x' >> "$B/promotion/repair-block.conf"; before=$(sum "$E"); out=$($R restore-repair --esp-dir "$E" 2>&1)
has "an ESP block and a bundle block that differ: stops" "$out" "the saved repair blocks differ"; ok "and writes nothing (two blocks)" "$(sum "$E")" "$before"
for bad in 's#omarchy_linux-aurora-k114s.efi#omarchy_linux-k114s.efi#' '/cmdline:/d' 's#^/Omarchy K114s#/Other#' '$a /Second entry'; do
  mkesp aurora; rm "$B/promotion/repair-block.conf"; sed -i "$bad" "$E/k114s-repair/promotion/repair-block.conf"; before=$(sum "$E")
  out=$($R restore-repair --esp-dir "$E" 2>&1); has "a saved block changed by '$bad' stops" "$out" "STOPPED"; ok "and writes nothing ('$bad')" "$(sum "$E")" "$before"
done
mkesp aurora; rm "$E/k114s-repair/r2c/repair-uki.txt"; out=$($R restore-repair --esp-dir "$E" 2>&1)
has "no record of the repair image on the ESP: stops" "$out" "cannot be checked"

# --- the display window (docs/r3-display-plan.md 4.3 and 4.4): linux-aurora's image removed, r3b's beside r3a's ---------
# The real ESP then has about 110.8 MB free against the 111.8 MB image plus the reserve: short, and no linux-aurora image
# to make room. The synthetic image is a few bytes, so "short" is faked as 1 MB free (below the 8 MiB reserve alone).
WINDOW_FREE=1000000
mkesp window; before=$(sum "$E")
out=$($R status --esp-dir "$E" 2>&1)
has "window: status reads the path default, r3a" "$out" "Limine default entry:  Omarchy/linux-k114s -> linux-k114s (entry 2)"
has "window: status says the r3a image is the Linux image" "$out" "omarchy_linux-k114s.efi is"
ok "window: status wrote nothing" "$(sum "$E")" "$before"
out=$(RF $WINDOW_FREE restore-repair --check --esp-dir "$E" 2>&1)
has "window: --check reads the space as short, with nothing to remove" "$out" "NOT ENOUGH, and no omarchy_linux-aurora.efi to remove"
has "window: --check ends short of space" "$out" "restore-repair check: short of space."
ok "window: --check wrote nothing" "$(sum "$E")" "$before"
out=$(RF $WINDOW_FREE restore-repair --esp-dir "$E" 2>&1)
has "window: restore-repair refuses" "$out" "no omarchy_linux-aurora.efi to remove; nothing written"
ok "window: the refusal wrote nothing" "$(sum "$E")" "$before"
out=$($R default aurora --esp-dir "$E" 2>&1); has "window: default aurora stops (no such entry)" "$out" "has no entry Omarchy/linux-aurora"
ok "window: default aurora wrote nothing" "$(sum "$E")" "$before"
out=$($R stage2 r1 --esp-dir "$E" 2>&1); has "window: stage2 r1 works (Stage 2 suspect)" "$out" "Stage 2 is now: r1"
# the manual edit of 4.3 (r3a image suspect only): the default points at r3b by hand
mkesp window; sed -i 's#^default_entry: .*#default_entry: Omarchy/linux-k114s-r3b#' "$E/limine.conf"
out=$($R status --esp-dir "$E" 2>&1)
has "window, default edited to r3b: status reads the r3b entry" "$out" "Omarchy/linux-k114s-r3b -> linux-k114s-r3b (entry 3)"
out=$($R default k114s --esp-dir "$E" 2>&1); ok "window: default k114s puts r3a back" "$(def)" "Omarchy/linux-k114s"
# both suspect: the r3b image comes off first (its entry stays, dangling), then restore-repair has room (about 181 MB)
mkesp window; rm "$E/EFI/Linux/omarchy_linux-k114s-r3b.efi"; cp "$E/limine.conf" "$W/conf.win"
out=$(RF 181000000 restore-repair --check --esp-dir "$E" 2>&1)
has "window, r3b image removed: --check passes" "$out" "restore-repair check passed."
out=$(RF 181000000 restore-repair --esp-dir "$E" 2>&1)
has "window, r3b image removed: restore-repair done" "$out" "Restored the repair entry as entry 1"
ok "it put the bundle's repair image on the ESP" "$(cmp -s "$rimg" "$E/EFI/Linux/omarchy_linux-aurora-k114s.efi"; echo $?)" 0
ok "the menu gains the saved block and default_entry 1; the dangling r3b entry stays" \
  "$(diff "$W/conf.win" "$E/limine.conf" | grep -c '^<') $(def) $(grep -c '//linux-k114s-r3b' "$E/limine.conf")" "1 1 1"
out=$($R status --esp-dir "$E" 2>&1)
has "window, after restore-repair: status reads entry 1, the repair entry (as after P4b's restore)" "$out" "Limine default entry:  1 -> Omarchy K114s repair r1 (trackpad fix B) (entry 1)"
has "window, after restore-repair: the repair entry is back" "$out" "Limine repair entry: yes"

# --- the tool the Mac has before this change (911d43e9, commit 364598e) does not find the promoted ESP ----------------
if O=$(git -C "$H" show 364598e:macos/tools/k114s_repair.py 2>/dev/null); then
  mkesp after; printf '%s\n' "$O" > "$B/tools/k114s_repair.py"; before=$(sum "$E")
  for c in status "stage2 r1" "default repair"; do out=$($R $c --esp-dir "$E" 2>&1); has "OLD tool '$c' stops on the promoted ESP" "$out" "STOPPED"; done
  ok "the old tool wrote nothing" "$(sum "$E")" "$before"
else echo "SKIP old-tool case (commit 364598e not in this clone)"; fi
echo "macOS tool (promoted ESP) tests: $pass passed, $fail failed"; [ "$fail" = 0 ]
