#!/bin/bash
# Replica tests for the omarchy-mac overlay (patches/omarchy/0003 and 0004): the display cutout, the
# microphone mapper and audio.json, the device names, the no-suspend rule and the headset-mic rule,
# against the K114s names this repository's own files produce. Nothing here is hardware proof, nothing is
# installed, and no root is needed: the packaged files are copied from the running system into a fake root.
#
#   bash tests/test-platform-data.sh            # reads /usr (omarchy-mac, omarchy-dev, alsa-ucm-conf-aurora)
#   K114S_PD_ROOT=/some/root bash tests/test-platform-data.sh
#
# Tools: python3, GNU patch, node (steps that need a missing tool or file are skipped, never passed).
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
R=${K114S_PD_ROOT:-}
W=$(mktemp -d "${TMPDIR:-/tmp}/k114pd.XXXXXX"); trap 'rm -rf "$W"' EXIT
pass=0; fail=0; skip=0
ok() { echo "ok   $1"; pass=$((pass+1)); }
no() { echo "FAIL $1"; fail=$((fail+1)); }
sk() { echo "skip $1"; skip=$((skip+1)); }
is() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1: got '$2', want '$3'"; fi; }

F=(share/omarchy-platform/display-cutouts.json share/omarchy-platform/audio.json bin/omarchy-audio-asahi-mic-map
   share/pipewire/pipewire.conf.d/asahi-device-names.conf share/wireplumber/wireplumber.conf.d/asahi-audio-no-suspend.conf)
for f in "${F[@]}"; do
  [ -f "$R/usr/$f" ] || { sk "the omarchy-mac file /usr/$f is not on this system: nothing to patch"; echo "platform-data tests: $pass passed, $fail failed, $skip skipped"; exit 0; }
done
command -v patch >/dev/null || { sk "GNU patch is not installed"; echo "platform-data tests: $pass passed, $fail failed, $skip skipped"; exit 0; }

# --- 1. the real patches, through the real installer, in a fake root that owns the files as omarchy-mac -------
mkroot() { # NAME: a fake root holding the packaged files and omarchy-mac's database record of them
  local r=$W/$1 f d
  d=$r/var/lib/pacman/local/omarchy-mac-0.2.3-2; mkdir -p "$d"
  for f in "${F[@]}"; do
    mkdir -p "$r/usr/$(dirname "$f")"; cp -p "$R/usr/$f" "$r/usr/$f"
    echo "./usr/$f time=1.0 size=1 sha256digest=$(sha256sum "$r/usr/$f" | cut -c1-64)"
  done | gzip > "$d/mtree"
  echo "$r"
}
orig=$(mkroot orig); root=$(mkroot patched)
mkdir -p "$W/src"; cp "$here"/patches/omarchy/0003-*.patch "$here"/patches/omarchy/0004-*.patch "$W/src/"
out=$(K114S_ROOT=$root K114S_OMARCHY_PATCHES_SRC=$W/src bash "$here/linux/omarchy-patches-install" 2>&1) && rc=0 || rc=$?
is "overlay: the installer accepts both patches as changes to omarchy-mac's files (0003 and 0004)" "$rc:$(grep -c ': applied' <<<"$out")" "0:2"
[ "$rc" = 0 ] || { echo "$out" | sed 's/^/     /'; echo "platform-data tests: $pass passed, $fail failed, $skip skipped"; exit 1; }
is "overlay: no .orig or .rej left behind" "$(find "$root/usr" \( -name '*.orig' -o -name '*.rej' \) | wc -l | tr -d ' ')" 0
out=$(K114S_ROOT=$root bash "$root/usr/local/lib/omarchy-k114s/omarchy-patches-apply" 2>&1)
is "overlay: a second run finds both in place" "$(grep -c 'in place' <<<"$out")" 2
K114S_ROOT=$root K114S_OMARCHY_PATCHES_SRC=$W/src bash "$here/linux/omarchy-patches-install" --undo >/dev/null 2>&1 || true
is "overlay: --undo gives back the packaged files byte for byte" \
  "$(cd "$root/usr" && sha256sum "${F[@]}" | cut -c1-64 | tr '\n' ' ')" "$(cd "$orig/usr" && sha256sum "${F[@]}" | cut -c1-64 | tr '\n' ' ')"
K114S_ROOT=$root K114S_OMARCHY_PATCHES_SRC=$W/src bash "$here/linux/omarchy-patches-install" >/dev/null 2>&1   # patched again for the checks below
P=$root/usr; O=$orig/usr

# --- the K114s names, from this repository's own files ---------------------------------------------------------
dtsi="$here/dts/t6050-k114s-sound.dtsi"
model=$(sed -n 's/^[[:space:]]*model = "\([^"]*\)".*/\1/p' "$dtsi" | head -1)
card_id="Apple${model##* }"                                    # AppleK114
mic_dsp=$(sed -n 's/.*"node.name": *"\(effect_output[^"]*\)".*/\1/p' "$here/linux/audio/share/mic.json")
mic_cap=$(sed -n 's/.*"node.name": *"\(audio_effect[^"]*\)".*/\1/p' "$here/linux/audio/share/mic.json")
[ "$card_id" = AppleK114 ] && [ "$mic_dsp" = effect_output.k114-mic ] && [ "$mic_cap" = audio_effect.k114-mic ] &&
  ok "names: card $card_id, filter nodes $mic_dsp and $mic_cap (from dts/ and linux/audio/share/mic.json)" || no "names: got '$card_id' '$mic_dsp' '$mic_cap'"

# --- 2. the display cutout (the shell's own BarModel.js, when it is installed) ----------------------------------
bm=$R/usr/share/omarchy/shell/plugins/bar/BarModel.js
if [ -f "$bm" ] && command -v node >/dev/null; then
  cat > "$W/bar.js" <<'EOF'
const B = require(process.argv[2]), fs = require("fs");
const load = f => B.parseCutouts(fs.readFileSync(f, "utf8"));
const [o, p] = [load(process.argv[3]), load(process.argv[4])];
const floor = (c, w, h, scale, mode, cal, name) => B.notchFloor(c, "top", name || "eDP-1", w / scale, h / scale, scale, mode, cal || 0);
const k114 = { width: 3024, height: 1986, transform: 0 };
const out = [];
out.push(["without the entry the K114s mode has no floor", floor(o, 3024, 1986, 2, k114) === 0]);
out.push(["with it, the floor is 48 logical px at scale 2 (96 rows)", floor(p, 3024, 1986, 2, k114) === 48]);
out.push(["the booted simpledrm framebuffer is named Unknown-1, which the eDP entry does not reach (the patched eDP lines alone)", floor(p.filter(e => e.connector === "eDP"), 3024, 1986, 2, k114, 0, "Unknown-1") === 0]);
out.push(["with the local Unknown-1 line the framebuffer gets the same 48 logical px floor", floor(p, 3024, 1986, 2, k114, 0, "Unknown-1") === 48]);
out.push(["with it, before Hyprland reports a mode (logical size times Qt's ratio)", floor(p, 3024, 1986, 2, null) === 48]);
out.push(["a calibrated [bar] notch-height replaces the derived one on a matching panel", floor(p, 3024, 1986, 2, k114, 44) === 44]);
out.push(["a calibrated notch-height alone does NOT make a floor: no matching entry, no floor (shell.toml is no workaround)", floor(o, 3024, 1986, 2, k114, 44) === 0]);
out.push(["the 14-inch M1 entry is untouched (3024x1964: 32 logical px)", floor(p, 3024, 1964, 2, { width: 3024, height: 1964, transform: 0 }) === 32]);
out.push(["a mode with the notch hidden (3024x1890, a guess) matches no entry: no floor", floor(p, 3024, 1890, 2, { width: 3024, height: 1890, transform: 0 }) === 0]);
out.push(["an external monitor on DP-1 never gets the floor", B.notchFloor(p, "top", "DP-1", 1512, 993, 2, k114, 0) === 0]);
out.push(["a rotated panel has no floor at the top", floor(p, 3024, 1986, 2, { width: 3024, height: 1986, transform: 1 }) === 0]);
for (const [what, good] of out) console.log((good ? "ok   " : "FAIL ") + "display: " + what);
EOF
  while IFS= read -r l; do case "$l" in ok\ *) ok "${l#ok   }" ;; FAIL\ *) no "${l#FAIL }" ;; esac; done \
    < <(node "$W/bar.js" "$bm" "$O/share/omarchy-platform/display-cutouts.json" "$P/share/omarchy-platform/display-cutouts.json" 2>&1 || echo "FAIL display: the test script failed")
else
  sk "display: node or the shell's BarModel.js is not available here"
fi
python3 -I - "$P/share/omarchy-platform/display-cutouts.json" <<'EOF' && ok "display: the cutout file is valid JSON and every entry has a top below its height" || no "display: the cutout file is malformed"
import json, sys
for e in json.load(open(sys.argv[1]))["panels"]:
    assert e["connector"] and 0 < e["top"] < e["height"], e
EOF

# --- 3. the microphone mapper, audio.json, the names, the no-suspend rule ---------------------------------------
python3 -I - "$O/bin/omarchy-audio-asahi-mic-map" "$P/bin/omarchy-audio-asahi-mic-map" "$mic_dsp" > "$W/map.out" 2>&1 <<'EOF' || true
import importlib.machinery, importlib.util, sys
def load(path, name):
    spec = importlib.util.spec_from_loader(name, importlib.machinery.SourceFileLoader(name, path))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
o, p, k = load(sys.argv[1], "mo"), load(sys.argv[2], "mp"), sys.argv[3]
src = lambda *names: [{"name": n} for n in names]
def check(what, cond): print(("ok   " if cond else "FAIL ") + "mapper: " + what)
check("unpatched, %s is not found: the source would stay MONO" % k, o.find_dsp(src("alsa_input.x", k)) is None)
check("patched, %s is found" % k, p.find_dsp(src("alsa_input.x", k)) == k)
check("patched, a jNNN mic is still found", p.find_dsp(src("effect_output.j314-mic")) == "effect_output.j314-mic")
check("patched, the raw array node and the capture side are not taken for the DSP",
      p.find_dsp(src("alsa_input.platform-sound.RawMics", "audio_effect.k114-mic", "effect_output.k114-convolver", "effect_output.mini-mic")) is None)
EOF
while IFS= read -r l; do case "$l" in ok\ *) ok "${l#ok   }" ;; FAIL\ *) no "${l#FAIL }" ;; esac; done < "$W/map.out"
grep -q '^ok' "$W/map.out" || { no "mapper: the checks did not run"; sed 's/^/     /' "$W/map.out" | head -5; }

am=$R/usr/share/omarchy/shell/Commons/AudioNodesModel.js
if [ -f "$am" ] && command -v node >/dev/null; then
  cat > "$W/audio.js" <<'EOF'
const A = require(process.argv[2]), fs = require("fs");
const hints = f => A.parsePlatformAudio(fs.readFileSync(f, "utf8"));
const [o, p] = [hints(process.argv[3]), hints(process.argv[4])], dsp = process.argv[5], cap = process.argv[6];
const all = [dsp, cap, "omarchy_asahi_mic", "alsa_input.platform-sound.RawMics", "alsa_input.platform-sound.HiFi__Headset__source"];
const out = [];
out.push(["unpatched, the raw capture node " + cap + " stays in the device list", !A.platformHidesNode(cap, o, all)]);
out.push(["unpatched, the mono " + dsp + " stays listed next to the stereo source", !A.platformHidesNode(dsp, o, all)]);
out.push(["patched, " + cap + " is hidden", A.platformHidesNode(cap, p, all)]);
out.push(["patched, " + dsp + " is replaced by omarchy_asahi_mic once that exists", A.platformHidesNode(dsp, p, all)]);
out.push(["patched, " + dsp + " stays listed while the stereo source does not exist (no dead end)", !A.platformHidesNode(dsp, p, [dsp, cap])]);
out.push(["patched, the stereo source itself and the headset mic stay listed", !A.platformHidesNode("omarchy_asahi_mic", p, all) && !A.platformHidesNode("alsa_input.platform-sound.HiFi__Headset__source", p, all)]);
out.push(["patched, the raw array RawMics is hidden (it was, with or without the patch)", A.platformHidesNode("alsa_input.platform-sound.RawMics", p, all)]);
out.push(["patched, a jNNN mic is still handled", A.platformHidesNode("audio_effect.j314-mic", p, all) && A.platformHidesNode("effect_output.j314-mic", p, ["effect_output.j314-mic", "omarchy_asahi_mic"])]);
for (const [what, good] of out) console.log((good ? "ok   " : "FAIL ") + "audio.json: " + what);
EOF
  while IFS= read -r l; do case "$l" in ok\ *) ok "${l#ok   }" ;; FAIL\ *) no "${l#FAIL }" ;; esac; done \
    < <(node "$W/audio.js" "$am" "$O/share/omarchy-platform/audio.json" "$P/share/omarchy-platform/audio.json" "$mic_dsp" "$mic_cap" 2>&1 || echo "FAIL audio.json: the test script failed")
else
  sk "audio.json: node or the shell's AudioNodesModel.js is not available here"
fi

# Rules: parsed by spa-json-dump (as WirePlumber and PipeWire read them); "~" is a regular expression.
if command -v spa-json-dump >/dev/null; then
  spa-json-dump "$P/share/pipewire/pipewire.conf.d/asahi-device-names.conf" > "$W/names.json" &&
  spa-json-dump "$O/share/wireplumber/wireplumber.conf.d/asahi-audio-no-suspend.conf" > "$W/ns-o.json" &&
  spa-json-dump "$P/share/wireplumber/wireplumber.conf.d/asahi-audio-no-suspend.conf" > "$W/ns-p.json" &&
  spa-json-dump "$here/linux/audio/wireplumber/82-k114-audio.conf" > "$W/82.json" &&
  spa-json-dump "$R/usr/share/wireplumber/wireplumber.conf.d/asahi-headset-mic.conf" > "$W/hs.json" || no "rules: a rule file does not parse"
  python3 -I - "$W" "$card_id" "$mic_dsp" "$mic_cap" > "$W/rules.out" 2>&1 <<'EOF' || true
import json, re, sys
w, card, dsp, cap = sys.argv[1:5]
L = lambda n: json.load(open("%s/%s.json" % (w, n)))
def hit(value, pattern): return bool(re.search(pattern[1:], value)) if pattern.startswith("~") else value == pattern
def match(matches, props):  # a rule matches when any entry of matches has every key matching
    return any(all(k in props and hit(props[k], v) for k, v in m.items()) for m in matches)
def acts(rule): return rule["actions"].get("update-props", {})
def check(what, cond): print(("ok   " if cond else "FAIL ") + what)
names = L("names")["node.rules"]
desc = lambda n: [acts(r)["node.description"] for r in names if match(r["matches"], {"node.name": n})]
check("names: %s is named 'MacBook Microphone (Mono)'" % dsp, desc(dsp) == ["MacBook Microphone (Mono)"])
check("names: a jNNN mic is still named so", desc("effect_output.j314-mic") == ["MacBook Microphone (Mono)"])
check("names: the capture side %s is not renamed" % cap, desc(cap) == [])
check("names: the headphone and headset nodes the jack verb makes are named",
      desc("alsa_output.platform-sound.HiFi__Headphones__sink") == ["Headphones"] and desc("alsa_input.platform-sound.HiFi__Headset__source") == ["Headset Microphone"])
sink = {"api.alsa.path": "hw:%s,0" % card, "media.class": "Audio/Sink"}
src = {"api.alsa.path": "hw:%s,0" % card, "media.class": "Audio/Source"}
mic_card = {"api.alsa.path": "hw:%sHPAI,0" % card, "media.class": "Audio/Source"}
def nosusp(n, props): return [r for r in L(n)["monitor.alsa.rules"] if match(r["matches"], props)]
check("no-suspend: unpatched, the packaged rule misses hw:%s,0" % card, not nosusp("ns-o", sink))
check("no-suspend: patched, the packaged rule keeps hw:%s,0 open" % card, len(nosusp("ns-p", sink)) == 1)
check("no-suspend: patched, a J board is still covered", len(nosusp("ns-p", {"api.alsa.path": "hw:AppleJ314,0", "media.class": "Audio/Sink"})) == 1)
check("no-suspend: capture and the microphone card still suspend", not nosusp("ns-p", src) and not nosusp("ns-p", mic_card))
check("no-suspend: this repository's 82-k114-audio.conf says the same for the jack sink, so the local rule and the patch agree",
      len([r for r in L("82")["monitor.alsa.rules"] if match(r["matches"], sink) and acts(r).get("session.suspend-timeout-seconds") == 0]) == 1)
EOF
  while IFS= read -r l; do case "$l" in ok\ *) ok "${l#ok   }" ;; FAIL\ *) no "${l#FAIL }" ;; esac; done < "$W/rules.out"
  grep -q '^ok' "$W/rules.out" || { no "rules: the checks did not run"; sed 's/^/     /' "$W/rules.out" | head -5; }
else
  sk "rules: spa-json-dump is not installed here"
fi

# --- 4. the headset-mic rule against the names the jack's UCM verb makes -----------------------------------------
ucm=$R/usr/share/alsa/ucm2/conf.d/macaudio/cs42l84/HiFi-jack.conf
if command -v alsaucm >/dev/null && command -v spa-json-dump >/dev/null && [ -f "$ucm" ] && [ -f "$W/hs.json" ]; then
  # alsaucm opens a virtual card (conf.virt.d) with no sound hardware. ${CardId} is not defined without a
  # card, so the verb file is copied with the K114s card id put in. The verb is the one the packaged jack
  # profile includes; the card file is this repository's.
  U=$W/ucm2; mkdir -p "$U/conf.virt.d" "$U/conf.d/macaudio/cs42l84"
  cp "$R/usr/share/alsa/ucm2/ucm.conf" "$U/"; cp -r "$R/usr/share/alsa/ucm2/lib" "$U/" 2>/dev/null || true
  sed "s/\${CardId}/$card_id/g" "$ucm" > "$U/conf.d/macaudio/cs42l84/HiFi-jack.conf"
  cp "$here/linux/audio/ucm2/macaudio-k114.conf" "$U/conf.virt.d/k114jack.conf"
  devs=$(ALSA_CONFIG_UCM2=$U alsaucm -c k114jack list _devices/HiFi 2>/dev/null | sed -n 's/^ *[0-9]*: //p' | grep -v ' ' || true)
  # The ACP names a UCM node alsa_<output|input>.<card device name>.<verb>__<device>__<sink|source>; the card's
  # device name is platform-<DT node name> (the K114s card node is /sound).
  grep -qE '^	sound \{' "$dtsi" && node_name=sound || node_name=
  is "headset: the jack verb has the devices Headphones and Headset" "$(echo $devs)" "Headphones Headset"
  is "headset: the card's device tree node is /sound (so the card is platform-sound)" "$node_name" sound
  src_name="alsa_input.platform-$node_name.HiFi__Headset__source"
  snk_name="alsa_output.platform-$node_name.HiFi__Headphones__sink"
  ALSA_CONFIG_UCM2=$U alsaucm -c k114jack get CapturePCM/Headset/HiFi 2>/dev/null | grep -q "hw:$card_id,0" &&
    ok "headset: the Headset capture is PCM 0 of $card_id" || no "headset: the Headset capture is not hw:$card_id,0"
  python3 -I - "$W/hs.json" "$W/names.json" "$src_name" "$snk_name" > "$W/hs.out" 2>&1 <<'EOF' || true
import json, sys
hs, names = json.load(open(sys.argv[1]))["monitor.alsa.rules"], json.load(open(sys.argv[2]))["node.rules"]
src, snk = sys.argv[3:5]
def check(what, cond): print(("ok   " if cond else "FAIL ") + "headset: " + what)
m = [r for r in hs if {"node.name": src} in r["matches"]]
check("asahi-headset-mic.conf matches the node name the K114s jack verb makes (%s)" % src, len(m) == 1 and m[0]["actions"]["update-props"] == {"priority.session": 1})
check("it does not match the headphone sink or a name with another card", not any({"node.name": n} in r["matches"] for r in hs for n in (snk, "alsa_input.platform-sound.RawMics")))
check("the device-names rules match the same two node names", any({"node.name": src} in r["matches"] for r in names) and any({"node.name": snk} in r["matches"] for r in names))
EOF
  while IFS= read -r l; do case "$l" in ok\ *) ok "${l#ok   }" ;; FAIL\ *) no "${l#FAIL }" ;; esac; done < "$W/hs.out"
  grep -q '^ok' "$W/hs.out" || { no "headset: the checks did not run"; sed 's/^/     /' "$W/hs.out" | head -5; }
else
  sk "headset: alsaucm, spa-json-dump or alsa-ucm-conf-aurora's HiFi-jack.conf is not available here"
fi

echo "platform-data tests: $pass passed, $fail failed, $skip skipped"
[ "$fail" = 0 ]
