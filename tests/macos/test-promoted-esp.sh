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
  #         | display (the layout after docs/r3-display-d5-d9.md D9: window, plus default_entry the r3b entry, the display Stage 2
  #           (pin loader, brightness tree) configured, and the fallback Stage 2 and tree in promotion/ on the ESP and in the bundle)
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
# the display Stage 2 of D9: another loader (so another prefix length), the brightness tree, the same U-Boot tail
pinp, db = b"PINLDR", fdt(b"bright"); disp = pinp + db + trailer
consts = {"pin_bytes": len(pinp), "pin_sha": h(pinp), "gpu_sha": h(gpu), "gputree_sha": h(dg), "disp_sha": h(disp)}
json.dump(consts, open(os.path.dirname(B) + "/consts.json", "w"))
os.makedirs(B + "/promotion", exist_ok=True); os.makedirs(E + "/k114s-repair/promotion", exist_ok=True)
w(B + "/promotion/boot-ctxr-gpu.bin", gpu); w(B + "/promotion/k114s.dtb.gpu", dg)
if layout == "display":
    w(E + "/m1n1/boot-ctxr.bin", disp); w(E + "/k114s-repair/k114s.dtb", db)
    w(E + "/k114s-repair/promotion/boot-ctxr-gpu.bin", gpu); w(E + "/k114s-repair/promotion/k114s.dtb.gpu", dg)
k = b"the r3a image stand-in"; w(E + "/EFI/Linux/omarchy_linux-k114s.efi", k); kh = hashlib.blake2b(k).hexdigest()
tf = io.BytesIO(); t = tarfile.open(fileobj=tf, mode="w"); i = tarfile.TarInfo("apple/tpmtfw-k114s.bin"); i.size = 3; t.addfile(i, io.BytesIO(b"abc")); t.close()
w(E + "/vendorfw/firmware.tar", tf.getvalue()); w(E + "/vendorfw/firmware.cpio", b"cpio"); w(E + "/vendorfw/manifest.txt", b"m")
head = "timeout: 5\nquiet: no\ndefault_entry: Omarchy/linux-k114s%s\nhash_mismatch_panic: no\n" % ("-r3b" if layout == "display" else "")
repair = ("### K114s repair (added from macOS; remove this block to undo)\n/Omarchy K114s repair r1 (trackpad fix B)\n  protocol: efi\n"
          "  path: boot():/EFI/Linux/omarchy_linux-aurora-k114s.efi\n  cmdline: root=UUID=00000000-0000-0000-0000-000000000000 rw\n\n")
# the static fallback kept off the ESP (P4b) and the block kept on it (P0e), and apply's record of the repair image
ri = b"not a PE: the repair image stand-in"
os.makedirs(E + "/k114s-repair/r2c"); os.makedirs(E + "/k114s-repair/promotion", exist_ok=True); os.makedirs(B + "/promotion", exist_ok=True)
w(E + "/k114s-repair/r2c/repair-uki.txt", ("# record\nvariant r1\nuki EFI/Linux/omarchy_linux-aurora-k114s.efi %d %s\n" % (len(ri), h(ri))).encode())
w(E + "/k114s-repair/promotion/repair-block.conf", repair.encode()); w(B + "/promotion/repair-block.conf", repair.encode())
w(B + "/promotion/omarchy_linux-aurora-k114s.efi", ri)
aur = ""
if layout == "aurora":
    a = b"the hook-built linux-aurora image stand-in"; w(E + "/EFI/Linux/omarchy_linux-aurora.efi", a)
    aur = "  //linux-aurora\n  protocol: efi\n  path: boot():/EFI/Linux/omarchy_linux-aurora.efi#%s\n" % hashlib.blake2b(a).hexdigest()
r3b = ""
if layout in ("window", "display"):
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
# RP runs the tool with the constants of this synthetic world: the pin loader's prefix, the r3-gpu file and tree it restores,
# and the display file's name (the real hashes belong to the real files and have a case of their own below)
RP() { python3 -I -c '
import json, sys; sys.path.insert(0, sys.argv[1]); import k114s_repair as r
c = json.load(open(sys.argv[2]))
r.PIN_LOADER = (c["pin_bytes"], c["pin_sha"]); r.LOCAL_STAGE2[c["disp_sha"]] = "r3-display (test)"
r.PROMOTED_STAGE2["r3-gpu"] = ("boot-ctxr-gpu.bin", "k114s.dtb.gpu", c["gpu_sha"], c["gputree_sha"], "installed")
try: sys.exit(r.main(["k114s-repair"] + sys.argv[3:]))
except r.Stop as stop: print("k114s-repair: STOPPED: %s" % stop); sys.exit(1)' "$B/tools" "$W/consts.json" "$@"; }
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
# a menu with_repair_block refuses (two default_entry lines) is found before any write, even when room must be made first
for mode in "" "--check"; do
  mkesp aurora; sed -i '1i default_entry: 2' "$E/limine.conf"; before=$(sum "$E")
  out=$(RF 1000000 restore-repair $mode --esp-dir "$E" 2>&1); has "a refused menu stops ($mode)" "$out" "2 default_entry lines"
  ok "and writes nothing, the linux-aurora image stays ($mode)" "$(sum "$E")" "$before"
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


# --- after D9 (docs/r3-display-d5-d9.md): the display Stage 2 configured, r3b.b1 the default, r3a and the fallbacks kept --------
mkesp display; before=$(sum "$E"); gpuf=$B/promotion/boot-ctxr-gpu.bin
out=$(RP status --esp-dir "$E" 2>&1)
has "D9: status names the display Stage 2 (a loader this tool knows)" "$out" "Stage 2 (boot-ctxr):   r3-display (test)"
has "D9: status reads the r3b default as entry 3" "$out" "Omarchy/linux-k114s-r3b -> linux-k114s-r3b (entry 3)"
ok "D9: status wrote nothing" "$(sum "$E")" "$before"
out=$($R status --esp-dir "$E" 2>&1); has "D9: without the test constants the real tool does not know the synthetic loader" "$out" "Stage 2 (boot-ctxr):   unknown"
out=$(RP stage2 r3-gpu --esp-dir "$E" 2>&1); has "D9: stage2 r3-gpu rolls the display Stage 2 back" "$out" "Stage 2 is now: r3-gpu"
ok "D9: it wrote the bundle's file over the loader bytes and the tree beside it, byte for byte" \
  "$(cmp -s "$E/m1n1/boot-ctxr.bin" "$gpuf"; echo $?) $(cmp -s "$E/k114s-repair/k114s.dtb" "$B/promotion/k114s.dtb.gpu"; echo $?)" "0 0"
rest() { (cd "$E" && find . -type f ! -name boot-ctxr.bin ! -name k114s.dtb -exec sha256sum {} + | sort -k2 | sha256sum | cut -c1-16); }
a=$(rest); mkesp display; ok "D9: it touched nothing else (limine.conf, the images, promotion/ on the ESP)" "$a" "$(rest)"
RP stage2 r3-gpu --esp-dir "$E" >/dev/null 2>&1; out=$(RP status --esp-dir "$E" 2>&1)
has "D9: after the rollback status reads the installed loader's Stage 2 (the synthetic file is not the real P file)" "$out" "same-loader-other-trees(1)"
out=$(RP stage2 r3-gpu --esp-dir "$E" 2>&1); has "D9: r3-gpu on r3-gpu is a no-op write (the proof run in M9 on the real ESP)" "$out" "Stage 2 is now: r3-gpu"
mkesp display; before=$(sum "$E"); out=$($R stage2 r3-gpu --esp-dir "$E" 2>&1)
has "D9: the real hashes do not accept a synthetic promotion file" "$out" "are not the r3-gpu Stage 2 and tree this tool knows (sha256 9825a103"
ok "D9: and that wrote nothing" "$(sum "$E")" "$before"
mkesp display; echo x >> "$B/promotion/boot-ctxr-gpu.bin"; before=$(sum "$E"); out=$(RP stage2 r3-gpu --esp-dir "$E" 2>&1)
has "D9: a promotion file that changed one byte stops" "$out" "are not the r3-gpu Stage 2"; ok "D9: and wrote nothing (changed file)" "$(sum "$E")" "$before"
mkesp display; echo x >> "$B/promotion/k114s.dtb.gpu"; before=$(sum "$E"); out=$(RP stage2 r3-gpu --esp-dir "$E" 2>&1)
has "D9: a promotion tree that changed one byte stops" "$out" "are not the r3-gpu Stage 2"; ok "D9: and wrote nothing (changed tree)" "$(sum "$E")" "$before"
mkesp display; rm "$B/promotion/boot-ctxr-gpu.bin"; before=$(sum "$E"); out=$(RP stage2 r3-gpu --esp-dir "$E" 2>&1)
has "D9: no promotion file: stops and says what to copy" "$out" "has no boot-ctxr-gpu.bin"; has "D9: it names the step" "$out" "docs/r3-display-d5-d9.md M9"
ok "D9: and wrote nothing (no file)" "$(sum "$E")" "$before"
mkesp display; printf 'neither loader nor tree' > "$E/m1n1/boot-ctxr.bin"; before=$(sum "$E"); out=$(RP stage2 r3-gpu --esp-dir "$E" 2>&1)
has "D9: a live Stage 2 with no known loader is not replaced" "$out" "the live Stage 2 is not one this bundle knows"; ok "D9: and wrote nothing (unknown live file)" "$(sum "$E")" "$before"
# a rebuilt display file: the pin loader and its U-Boot tail, but another tree
mkesp display; python3 -I -c '
import sys; f = sys.argv[1] + "/m1n1/boot-ctxr.bin"; d = open(f, "rb").read(); i = d.index(b"\xd0\x0d\xfe\xed")
open(f, "wb").write(d[:i] + d[i:].replace(b"bright", b"brighT"))' "$E"
out=$(RP status --esp-dir "$E" 2>&1); has "D9: a rebuilt display file on the pin loader reads as the pin loader with another tree" "$out" "pin-loader-other-trees(1)"
out=$(RP stage2 r3-gpu --esp-dir "$E" 2>&1); has "D9: and can be rolled back too" "$out" "Stage 2 is now: r3-gpu"
mkesp display; out=$(RP stage2 r1 --esp-dir "$E" 2>&1); has "D9: stage2 r1 also rolls the loader back" "$out" "Stage 2 is now: r1"
ok "D9: r1's file replaced the pin loader's" "$(cmp -s "$E/m1n1/boot-ctxr.bin" "$B/payload/boot-ctxr-k114s-r1.bin"; echo $?)" 0
mkesp display; out=$($R default k114s --esp-dir "$E" 2>&1); has "D9: default k114s puts r3a back as the default from macOS" "$out" "Default boot entry changed"; ok "D9: the path is written" "$(def)" "Omarchy/linux-k114s"
mkesp display; before=$(sum "$E"); out=$($R default aurora --esp-dir "$E" 2>&1); has "D9: default aurora stops (its image is off the ESP)" "$out" "has no entry Omarchy/linux-aurora"
ok "D9: and wrote nothing (default aurora)" "$(sum "$E")" "$before"
out=$(RF $WINDOW_FREE restore-repair --check --esp-dir "$E" 2>&1); has "D9: restore-repair --check is short of space with nothing to remove (as in the window)" "$out" "NOT ENOUGH, and no omarchy_linux-aurora.efi to remove"
ok "D9: --check wrote nothing" "$(sum "$E")" "$before"
mkesp display; rm "$E/EFI/Linux/omarchy_linux-k114s-r3b.efi"; out=$(RF 181000000 restore-repair --esp-dir "$E" 2>&1)
has "D9: with the r3b image removed by hand first, restore-repair works" "$out" "Restored the repair entry as entry 1"
ok "D9: restore-repair leaves the display Stage 2 alone (the way back names stage2 r3-gpu first)" "$(RP status --esp-dir "$E" 2>&1 | grep -c 'Stage 2 (boot-ctxr):   r3-display (test)')" 1
# the tool's own constants, and the real files when the build area is here
ok "the tool's r3-gpu hashes are the promoted GPU Stage 2 and tree (docs/r3a-promotion.md P1), and it names the D9 file" "$(cd "$B/tools" && python3 -I -c 'import sys; sys.path.insert(0, "."); import k114s_repair as r
print(r.PROMOTED_STAGE2["r3-gpu"][2][:8], r.PROMOTED_STAGE2["r3-gpu"][3][:8], r.PIN_LOADER[0], r.PIN_LOADER[1][:8], sorted(k[:8] for k in r.LOCAL_STAGE2))')" \
  "9825a103 2c870ba9 4063232 beceb683 ['5164bb1e', '90b35137', '9825a103']"
BR=${K114S_BUILD_ROOT:-$HOME/k114s-build}/integrate; PIN=$BR/release-display-trials/aura-pin/m1n1.bin; D5S2=$BR/release-display-d5/stage2/boot-ctxr-disp-bl.bin
if [ -s "$PIN" ]; then ok "the pin loader's length and hash are those of the built loader file" "$(wc -c < "$PIN" | tr -d ' ') $(sha256sum "$PIN" | cut -c1-64)" \
  "$(cd "$B/tools" && python3 -I -c 'import sys; sys.path.insert(0, "."); import k114s_repair as r; print(r.PIN_LOADER[0], r.PIN_LOADER[1])')"
else echo "SKIP the pin loader file is not in this build area"; fi
if [ -s "$D5S2" ] && [ -s "$PIN" ]; then
  ok "the real D9 Stage 2 splits at the pin loader's length, one tree, and its tail is the one the manifest's installed loader files carry" "$(cd "$B/tools" && python3 -I -c 'import sys; sys.path.insert(0, "."); import k114s_repair as r
d = open(sys.argv[1], "rb").read(); m = r.json.load(open(sys.argv[2]))
hit = r.split_known(d, m); print(hit[0], len(hit[2]), r.sha(hit[2][0])[:8], r.sha(hit[3])[:8], r.stage2_state(d, m))' "$D5S2" "$H/../../manifests/payload-r1.json")" \
    "pin 1 5b6b83c8 9d8dc11e r3-display (pin loader + brightness tree, not in this bundle)"
else echo "SKIP the real D9 Stage 2 is not in this build area"; fi

# --- the tool the Mac has before this change (911d43e9, commit 364598e) does not find the promoted ESP ----------------
if O=$(git -C "$H" show 364598e:macos/tools/k114s_repair.py 2>/dev/null); then
  mkesp after; printf '%s\n' "$O" > "$B/tools/k114s_repair.py"; before=$(sum "$E")
  for c in status "stage2 r1" "default repair"; do out=$($R $c --esp-dir "$E" 2>&1); has "OLD tool '$c' stops on the promoted ESP" "$out" "STOPPED"; done
  ok "the old tool wrote nothing" "$(sum "$E")" "$before"
else echo "SKIP old-tool case (commit 364598e not in this clone)"; fi
echo "macOS tool (promoted ESP) tests: $pass passed, $fail failed"; [ "$fail" = 0 ]
