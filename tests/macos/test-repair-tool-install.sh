#!/bin/bash
# tools/k114s-repair-tool-install on a replica ESP (a folder): the repair tool copy and k114s-repair/known-loaders.json,
# and that the macOS tool then reads the Stage 2 the list describes. Synthetic loader and tail, no root, no real ESP.
#   usage: test-repair-tool-install.sh
set -u
H=$(cd "$(dirname "$0")" && pwd); R=$H/../..; W=$(mktemp -d "${TMPDIR:-/tmp}/k114s-install-test.XXXXXX"); trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: got [$2] want [$3]"; fi; }
has() { if printf '%s' "$2" | grep -q -- "$3"; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: lacks [$3]: $(printf '%s' "$2" | tail -3)"; fi; }
sum() { (cd "$1" && find . -type f -exec sha256sum {} + | sort -k2 | sha256sum | cut -c1-16); }
E=$W/esp; L=$W/loader.bin; I="python3 -I $R/tools/k114s-repair-tool-install --esp $E --loader $L"
mkesp() { # $1: the loader bytes, $2: the U-Boot payload
  rm -rf "$E"; mkdir -p "$E/m1n1" "$E/k114s-repair/promotion"; printf '%s' "$1" > "$L"
  python3 -I - "$E" "$L" "$2" <<'PY'
import gzip, struct, sys
E, L, ub = sys.argv[1:4]
strs = b"compatible\0"; val = b"apple,k114s\0apple,t6050\0"
st = struct.pack(">II", 1, 0) + struct.pack(">III", 3, len(val), 0) + val + b"\0" * (-len(val) % 4) + struct.pack(">II", 2, 9)
off = 56; tree = struct.pack(">10I", 0xd00dfeed, off + len(st) + len(strs), off, off + len(st), 40, 17, 16, 0, len(strs), len(st)) + b"\0" * 16 + st + strs
open(E + "/m1n1/boot-ctxr.bin", "wb").write(open(L, "rb").read() + tree + gzip.compress(ub.encode()))
PY
}
mkesp B13LDR aurora9-uboot
out=$($I --check 2>&1); has "--check says both files will be written" "$out" "will be written"; ok "--check wrote nothing" "$(find "$E/k114s-repair" -type f | wc -l | tr -d ' ')" 0
# Matching digests must not let malformed entries stand in for the configured loader and trailer.
python3 -I - "$E" "$L" <<'PYFIXTURE'
from pathlib import Path
import hashlib, json, sys
esp, loader = map(Path, sys.argv[1:])
data = (esp / "m1n1/boot-ctxr.bin").read_bytes()
digest = hashlib.sha256(loader.read_bytes()).hexdigest()
tail = hashlib.sha256(data[data.index(b"\x1f\x8b"):]).hexdigest()
known = {
    "loaders": [
        {"name": "bad loader", "bytes": 6, "sha256": digest},
        {"name": "aura-bool", "bytes": True, "sha256": digest},
        {"name": "aura-bad-digest", "bytes": 6, "sha256": "G" * 64},
        {"name": "aura-wrong-size", "bytes": 7, "sha256": digest},
        None,
    ],
    "trailers": [{"name": "bundle", "sha256": tail}, "invalid"],
}
(esp / "k114s-repair/known-loaders.json").write_text(json.dumps(known))
PYFIXTURE
out=$($I 2>&1); has "install says the tool's hash" "$out" "repair tool:  k114s-repair/promotion/k114s_repair.py  sha256 $(sha256sum "$R/macos/tools/k114s_repair.py" | cut -c1-64)"
ok "the ESP copy is the repository tool, byte for byte" "$(cmp -s "$E/k114s-repair/promotion/k114s_repair.py" "$R/macos/tools/k114s_repair.py"; echo $?)" 0
ok "the list drops malformed entries, keeps the valid one and adds the configured loader and tail" "$(python3 -I -c 'import json, sys; k = json.load(open(sys.argv[1])); print([(e["name"], e["bytes"]) for e in k["loaders"]], len(k["trailers"]))' "$E/k114s-repair/known-loaders.json")" "[('aura-wrong-size', 7), ('aura-$(sha256sum "$L" | cut -c1-8)', 6)] 1"
ok "no temporary file is left" "$(find "$E" -name '.*k114s-new' | wc -l | tr -d ' ')" 0
s=$(sum "$E"); out=$($I 2>&1); has "a second run says up to date" "$out" "up to date"; ok "and changes nothing" "$(sum "$E")" "$s"
# the tool the ESP now carries reads the Stage 2 through the list (no bundle needed beyond a manifest): a throw-away bundle folder
B=$W/bundle; mkdir -p "$B/tools"; cp "$R"/macos/tools/k114s_esp_tool.py "$E/k114s-repair/promotion/k114s_repair.py" "$B/tools/"; cp -r "$R/macos/tools/asahi_firmware" "$B/tools/"
python3 -I -c 'import json, sys; json.dump({"stage2_sha256": {}, "payload": {}, "original_kernel_sha256": "x", "aura_prefix_bytes": 4, "aura_prefix_sha256": "0" * 64, "uboot_trailer_sha256": "0" * 64}, open(sys.argv[1], "w"))' "$B/manifest.json"
out=$(python3 -I - "$B/tools" "$E" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1]); import k114s_repair as r
class Esp:   # the part of the ESP class the Stage 2 reading uses, over the folder
    def __init__(self, root): self.root = root
    def has(self, rel): import os; return os.path.exists(self.root + "/" + rel)
    def get(self, rel): return open(self.root + "/" + rel, "rb").read()
e = Esp(sys.argv[2]); m = json.load(open(sys.argv[1] + "/../manifest.json"))
print(r.stage2_state(e.get("m1n1/boot-ctxr.bin"), m, e), r.stage2_state(e.get("m1n1/boot-ctxr.bin"), m))
PY
); ok "the copied tool reads it with the list and not without" "$out" "aura-$(sha256sum "$L" | cut -c1-8)-loader-other-trees(1) unknown"
# a new tool, a new Stage 2: the old tool copy is kept, the list grows and keeps the first entries
echo "# older copy" >> "$E/k114s-repair/promotion/k114s_repair.py"; old=$(sha256sum < "$E/k114s-repair/promotion/k114s_repair.py")
out=$($I 2>&1); ok "an older copy on the ESP is replaced" "$(cmp -s "$E/k114s-repair/promotion/k114s_repair.py" "$R/macos/tools/k114s_repair.py"; echo $?)" 0
ok "and kept as .prev" "$(sha256sum < "$E/k114s-repair/promotion/k114s_repair.py.prev")" "$old"
first=$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["loaders"][-1]["sha256"])' "$E/k114s-repair/known-loaders.json")
mkesp B15LDRX aurora10-uboot; mkdir -p "$E/k114s-repair"; python3 -I -c 'import json, sys, hashlib; h = lambda b: hashlib.sha256(b).hexdigest()
json.dump({"loaders": [{"name": "aura-old", "bytes": 6, "sha256": sys.argv[1]}], "trailers": []}, open(sys.argv[2], "w"))' "$first" "$E/k114s-repair/known-loaders.json"
out=$($I 2>&1)
ok "a new Stage 2 adds its entries and keeps the earlier one" "$(python3 -I -c 'import json, sys; k = json.load(open(sys.argv[1])); print(len(k["loaders"]), k["loaders"][0]["name"], len(k["trailers"]))' "$E/k114s-repair/known-loaders.json")" "2 aura-old 1"
# refusals write nothing
for case in "wrong loader" "no tree" "no esp" "damaged list"; do
  mkesp B13LDR aurora9-uboot
  case $case in
    "wrong loader") printf 'OTHER!' > "$L" ;;
    "no tree") printf 'B13LDRnot a tree' > "$E/m1n1/boot-ctxr.bin" ;;
    "no esp") rm "$E/m1n1/boot-ctxr.bin" ;;
    "damaged list") echo '{not json' > "$E/k114s-repair/known-loaders.json" ;;
  esac
  s=$(sum "$E"); out=$($I 2>&1); code=$?
  ok "$case: stops" "$code" 1; has "$case: says nothing written" "$out" "nothing written"; ok "$case: wrote nothing" "$(sum "$E")" "$s"
done
echo "macOS tool ESP copy and Stage 2 list tests: $pass passed, $fail failed"; [ "$fail" = 0 ]
