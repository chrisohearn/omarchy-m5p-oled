#!/bin/bash
# Software tests for the K114s sound candidate (replica and compile tests; nothing here is hardware proof).
#
#   tests/test-sound.sh KTREE
#
# KTREE: a kernel tree at the installed base (aurora-silicon/linux a34d26c2 + linux-j714s-27.2.patch).
# It is only read. Tools: python3, a C preprocessor (CPP, default "cpp") and dtc (DTC, default "dtc").
#
#   1. build/k114s-adt.py against a made-up ADT: the PMP file it writes, and what it refuses; and the
#      self-test of tests/k114s-adt-sound-facts.py (the check of the real ADT is a root step, not run here);
#   2. the sound trees compile against KTREE (with a stand-in PMP file from that made-up ADT);
#   3. tests/lint-sound-dtb.py passes on them;
#   4. the lint fails on trees that give the amplifiers a way to play (the K116s amp nodes, a Speaker
#      link, the shutdown pin exposed, a speaker DMA channel, the K116 card);
#   5. the ALSA UCM profiles parse with the installed alsaucm, where it and alsa-ucm-conf-aurora exist;
#   6. linux/audio/install-audio.sh installs and undoes cleanly in a fake root (--root, --with-beamformer);
#   7. the installed speakerguardd v2 gate code, given the compiled tree, finds no speaker card.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
K=${1:?usage: test-sound.sh KTREE}
CPP=${CPP:-cpp}; DTC=${DTC:-dtc}
A="$K/arch/arm64/boot/dts/apple"
[ -f "$A/t6050-k114-k116.dtsi" ] || { echo "not a kernel tree with the T6050 K-board files: $K"; exit 2; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ok() { echo "ok   $1"; pass=$((pass+1)); }
no() { echo "FAIL $1"; fail=$((fail+1)); }
expect() { local what=$1; shift; if "$@" >"$W/out" 2>&1; then ok "$what"; else no "$what"; sed 's/^/     /' "$W/out"; fi; }
refuse() { local what=$1; shift; if "$@" >"$W/out" 2>&1; then no "$what (was accepted)"; sed 's/^/     /' "$W/out"; else ok "$what"; fi; }

# --- 1. the ADT reader, on a made-up ADT ------------------------------------------------------------------
python3 - "$W" "$A/t6050-j714s-pmp-tunables.dtsi" <<'EOF'
import re, struct, sys
out, names_file = sys.argv[1], sys.argv[2]
names = re.findall(r"^\s*apple,tunable-([A-Za-z0-9_,.+-]+)\s*=", open(names_file).read(), re.M)
def prop(name, val):
    return name.encode().ljust(32, b"\0") + struct.pack("<I", len(val)) + val + b"\0" * (-len(val) % 4)
def node(name, props, children=()):
    props = [("name", name.encode() + b"\0")] + props
    return struct.pack("<II", len(props), len(children)) + b"".join(prop(n, v) for n, v in props) + b"".join(children)
def adt(board, drop=()):
    # every value is made up: a counter, never anything from a Mac
    nub = [(n, struct.pack("<I", 0xA0000000 + i)) for i, n in enumerate(names) if n not in drop]
    nub += [("AAPL,phandle", struct.pack("<I", 77)), ("not-in-the-list", b"\x01\0\0\0")]
    return node("device-tree", [("compatible", b"TEST\0")], [
        node("chosen", [("board-id", struct.pack("<I", board)), ("dram-vendor-id", struct.pack("<I", 3))]),
        node("arm-io", [], [
            node("pmgr", [("pmc", struct.pack("<I", 1)), ("pmc-pmgr", struct.pack("<I", 63))]),
            node("pmp0", [], [node("iop-pmp0-nub", nub)]),
            node("i2c2", [], [node("audio-codec-output", [("reg", struct.pack("<I", 0x4b))])]),
        ]),
    ])
open(out + "/k114s.adt", "wb").write(adt(0x14))
open(out + "/k116s.adt", "wb").write(adt(0x16))
open(out + "/short.adt", "wb").write(adt(0x14, drop=(names[5],)))
open(out + "/names", "w").write("\n".join(names))
EOF
tool="python3 -I $here/build/k114s-adt.py"
expect "adt: writes the PMP file from a K114s ADT" $tool --adt "$W/k114s.adt" pmp-dtsi --names-from "$A/t6050-j714s-pmp-tunables.dtsi" -o "$W/t6050-k114s-pmp-tunables.dtsi"
n=$(wc -l < "$W/names"); n=$((n+1))
[ "$(grep -c '^\sapple,tunable-' "$W/t6050-k114s-pmp-tunables.dtsi")" = "$n" ] && ok "adt: all $n firmware properties of the upstream name list are written" || no "adt: property count"
grep -q 'apple,board-id = <20>;' "$W/t6050-k114s-pmp-tunables.dtsi" && grep -q 'apple,dram-vendor-id = <3>;' "$W/t6050-k114s-pmp-tunables.dtsi" &&
  grep -q 'apple,pmc = <1>;' "$W/t6050-k114s-pmp-tunables.dtsi" && grep -q 'apple,pmc-pmgr = <63>;' "$W/t6050-k114s-pmp-tunables.dtsi" &&
  ok "adt: board-id, dram-vendor-id, pmc and pmc-pmgr come from the ADT" || no "adt: boot arguments"
grep -q 'not-in-the-list\|AAPL,phandle' "$W/t6050-k114s-pmp-tunables.dtsi" && no "adt: wrote a property outside the name list" || ok "adt: properties outside the name list are not written"
refuse "adt: refuses another board's ADT (board-id 0x16)" $tool --adt "$W/k116s.adt" pmp-dtsi --names-from "$A/t6050-j714s-pmp-tunables.dtsi" -o "$W/wrong.dtsi"
refuse "adt: an ADT lacking a listed property is not called complete" $tool --adt "$W/short.adt" pmp-dtsi --names-from "$A/t6050-j714s-pmp-tunables.dtsi" -o "$W/short.dtsi"
expect "adt: show finds a node by name" $tool --adt "$W/k114s.adt" show audio-codec-output
refuse "adt: a missing ADT is an error, not an empty file" $tool --adt "$W/none.adt" pmp-dtsi --names-from "$A/t6050-j714s-pmp-tunables.dtsi" -o "$W/none.dtsi"
[ ! -e "$W/wrong.dtsi" ] && [ ! -e "$W/none.dtsi" ] && ok "adt: a refusal writes no file" || no "adt: a refusal left a file"
expect "adt: the sound fact checker (tests/k114s-adt-sound-facts.py) passes its self-test" python3 -I "$here/tests/k114s-adt-sound-facts.py" --self-test

# --- 2-4. compile and lint ---------------------------------------------------------------------------------
# the kernel's dtc warning switches; a newer dtc no longer knows some of them
dtcw=""
for c in unit_address_vs_reg avoid_unnecessary_addr_size alias_paths graph_child_address simple_bus_reg unique_unit_address interrupt_provider; do
  if echo '/dts-v1/; / { };' | "$DTC" -Wno-$c -O dtb -o /dev/null - 2>/dev/null; then dtcw="$dtcw -Wno-$c"; fi
done
build() { # build NAME SRC-DIR -> $W/NAME.dtb   (the include order is the kernel's; our files come first)
  rm -f "$W/$1.dtb"
  "$CPP" -E -nostdinc -I "$2" -I "$W" -I "$here/dts" -I "$K/scripts/dtc/include-prefixes" -I "$K/include" -I "$A" \
      -undef -D__DTS__ -x assembler-with-cpp -o "$W/$1.pp" "$2/$1.dts" &&
  "$DTC" -O dtb -o "$W/$1.dtb" -b 0 -i "$A" $dtcw "$W/$1.pp"
}
for t in t6050-k114s-r3-sound t6050-k114s-r3-sound-nomics; do
  expect "dts: $t compiles against the base tree" build "$t" "$here/dts"
  expect "lint: $t passes the speaker-safety lint" python3 "$here/tests/lint-sound-dtb.py" "$W/$t.dtb"
done
mv "$W/t6050-k114s-pmp-tunables.dtsi" "$W/pmp.keep"
refuse "dts: the sound tree does not compile without this Mac's PMP file" build t6050-k114s-r3-sound "$here/dts"
mv "$W/pmp.keep" "$W/t6050-k114s-pmp-tunables.dtsi"
build t6050-k114s-r3-sound "$here/dts" >/dev/null 2>&1   # the gate check below reads this tree again

mkdir "$W/bad"
bad() { # bad NAME 'dts text appended to the sound tree'
  { echo '#define K114S_R1_N1'; echo '#define K114S_R1_USB'; echo '#include "t6050-k114s-common.dtsi"'
    echo '#include "t6050-k114s-sound.dtsi"'; echo "$2"; } > "$W/bad/$1.dts"
  if build "$1" "$W/bad" >"$W/out" 2>&1; then
    refuse "lint: refuses $3" python3 "$here/tests/lint-sound-dtb.py" "$W/$1.dtb"
    [ -z "${SHOW_REFUSALS:-}" ] || sed 's/^/     /' "$W/out"
  else no "bad tree $1 did not compile"; sed 's/^/     /' "$W/out"; fi
}
amp='compatible = "ti,sn012776", "ti,tas2764"; reg = <0x38>; #sound-dai-cells = <0>;'
bad amp-node    "&i2c1 { status = \"okay\"; spk: codec@38 { $amp }; };"                                       "an amplifier node on i2c1"
bad amp-bus     '&i2c3 { clocks = <&clkref>; status = "okay"; };'                                            "the right amp bus enabled, even empty"
bad sdz-pin     '&pinctrl_ap { gpio-reserved-ranges = <0 80>, <81 26>, <108 26>, <135 4>, <140 81>; };'      "the shutdown pin 107 outside the reserved ranges"
bad sdz-reg     '/ { r: regulator-sn012776-sdz { compatible = "regulator-fixed"; regulator-name = "sn012776-sdz"; gpios = <&pinctrl_ap 107 GPIO_ACTIVE_HIGH>; enable-active-high; }; };' "a regulator on the shutdown pin"
bad spk-link    "&i2c1 { spk: codec@38 { $amp }; }; / { sound { dai-link@1 { reg = <1>; link-name = \"Speaker\"; cpu { sound-dai = <&aop_audio 3>; }; codec { sound-dai = <&spk>; }; }; }; };" "a Speaker link"
bad spk-dma     '&aop_audio { dmas = <&admac_base_ns 4>, <&admac_base_ns 5>, <&admac_base_ns 0>, <&admac_base_ns 1>; dma-names = "cout", "cin", "spkr", "sense"; };' "the speaker DMA channels"
bad k116-card   '/ { sound { compatible = "apple,k116-macaudio", "apple,macaudio"; }; };'                     "the K116 card (speakers admitted in the driver)"
bad j714-card   '/ { sound { compatible = "apple,j714-macaudio", "apple,macaudio"; }; };'                     "the J714 card"
bad spk-id      '/ { sound { speaker-id-gpios = <&pinctrl_ap 136 GPIO_ACTIVE_HIGH>, <&pinctrl_ap 137 GPIO_ACTIVE_HIGH>; }; };' "the speaker-ID pins"
bad pmp-alias   '/ { aliases { pmp = &pmp0; }; };'                                                           "a pmp alias (the loader would stop the boot)"

# --- 5. UCM profiles -----------------------------------------------------------------------------------------
sys=/usr/share/alsa/ucm2
if command -v alsaucm >/dev/null && [ -f "$sys/conf.d/macaudio/cs42l84/HiFi-jack.conf" ] && [ -f "$sys/conf.d/aop_audio/3chan/HiFi.conf" ]; then
  # alsaucm opens a name that is no card as ucm2/NAME/NAME.conf. Such a name has no ${CardId}, so the
  # staged copies of the verbs get a literal card in its place; everything else is the installed text.
  U="$W/ucm2"; mkdir -p "$U/k114jack" "$U/k114mic" "$U/conf.d/macaudio/cs42l84" "$U/conf.d/aop_audio/k114"
  for d in "$sys"/*; do [ "$(basename "$d")" = conf.d ] || ln -s "$d" "$U/"; done
  sed 's/\${CardId}/K114/g' "$sys/conf.d/macaudio/cs42l84/HiFi-jack.conf" > "$U/conf.d/macaudio/cs42l84/HiFi-jack.conf"
  sed 's/\${CardId}/K114/g' "$here/linux/audio/ucm2/aop_audio-k114-HiFi.conf" > "$U/conf.d/aop_audio/k114/HiFi.conf"
  cp "$here/linux/audio/ucm2/macaudio-k114.conf" "$U/k114jack/k114jack.conf"
  cp "$here/linux/audio/ucm2/aop_audio-k114-hpai.conf" "$U/k114mic/k114mic.conf"
  ucm() { ALSA_CONFIG_UCM2="$U" alsaucm -c "$1" list "_devices/HiFi"; }
  expect "ucm: the K114 jack profile parses" ucm k114jack
  ALSA_CONFIG_UCM2="$U" alsaucm -c k114jack list _devices/HiFi 2>/dev/null > "$W/devs" || true
  grep -q Headphones "$W/devs" && grep -q Headset "$W/devs" && ! grep -qi speaker "$W/devs" &&
    ok "ucm: the jack profile offers Headphones and Headset and no Speaker device" || { no "ucm: jack devices"; cat "$W/devs"; }
  expect "ucm: the K114 microphone profile parses" ucm k114mic
else
  echo "skip ucm: alsaucm or alsa-ucm-conf-aurora is not installed here"
fi
grep -rqE 'SectionDevice\."Speaker|Speaker (Switch|Volume|Playback)|hw:\$\{CardId\},[12]' "$here/linux/audio/ucm2" &&
  no "ucm: a profile has a speaker device, a speaker control or PCM 1/2" || ok "ucm: no profile has a speaker device, a speaker control or PCM 1/2"

# --- 6. the installer, in a fake root --------------------------------------------------------------------------
R="$W/root"; mkdir -p "$R/usr/share/alsa/ucm2/conf.d/macaudio/cs42l84" "$R/etc/wireplumber/wireplumber.conf.d"
: > "$R/usr/share/alsa/ucm2/conf.d/macaudio/cs42l84/HiFi-jack.conf"
echo "someone else's" > "$R/etc/wireplumber/wireplumber.conf.d/82-k114-audio.conf"
printf 'apple,k114s\0apple,t6050\0apple,arm-platform\0' > "$W/compat"; printf 'apple,j714s\0apple,t6050\0' > "$W/compat-j714s"
inst() { K114S_ROOT="$R" K114S_DT_COMPATIBLE="$W/compat" bash "$here/linux/audio/install-audio.sh" "$@"; }
refuse "install: refuses a Mac that is not apple,k114s" env K114S_ROOT="$R" K114S_DT_COMPATIBLE="$W/compat-j714s" bash "$here/linux/audio/install-audio.sh"
[ "$(find "$R" -type f | wc -l)" = 2 ] && ok "install: a refusal installs nothing" || no "install: a refusal left files"
expect "install: installs into the root" inst
expect "install: --check finds every file" inst --check
[ "$(find "$R" -name '91-k114s-no-speaker-link.conf' | wc -l)" = 5 ] && ok "install: the five speakerguardd v2 units get the condition" || no "install: unit drop-ins"
[ "$(cat "$R/etc/wireplumber/wireplumber.conf.d/82-k114-audio.conf.k114s-orig")" = "someone else's" ] && ok "install: an existing file is kept beside the new one" || no "install: existing file lost"
expect "install: a second run changes nothing" inst
find "$R" -type f | sort > "$W/after-install"
expect "install: --undo runs" inst --undo
[ "$(find "$R" -type f | wc -l)" = 2 ] && [ "$(cat "$R/etc/wireplumber/wireplumber.conf.d/82-k114-audio.conf")" = "someone else's" ] &&
  ok "install: --undo leaves the root as it was" || { no "install: --undo left a difference"; find "$R" -type f; }
# --root and the beamformed graph (a second root: the flag, not the environment variable)
R2="$W/root2"; mkdir -p "$R2/usr/share/alsa/ucm2/conf.d/macaudio/cs42l84"; : > "$R2/usr/share/alsa/ucm2/conf.d/macaudio/cs42l84/HiFi-jack.conf"
inst2() { K114S_DT_COMPATIBLE="$W/compat" bash "$here/linux/audio/install-audio.sh" --root "$R2" "$@"; }
M="$R2/usr/local/share/omarchy-k114s/audio/mic.json"
expect "install: --root installs into the given tree" inst2
cmp -s "$M" "$here/linux/audio/share/mic.json" && ok "install: the plain microphone graph is the default" || no "install: default graph"
expect "install: --with-beamformer switches the graph" inst2 --with-beamformer
cmp -s "$M" "$here/linux/audio/share/mic-beamformer.json" && ok "install: the beamformed graph is in place" || no "install: beamformed graph"
[ ! -e "$M.k114s-orig" ] && ok "install: switching graphs does not keep our own file as an original" || no "install: switching made a .k114s-orig"
expect "install: --undo with --root" inst2 --undo
[ "$(find "$R2" -type f | wc -l)" = 1 ] && ok "install: --root --undo leaves only the stand-in verb file" || { no "install: --root --undo left files"; find "$R2" -type f; }
# the Stage B readiness report: silent, and it trips on anything that could admit a speaker path
SR="$here/linux/audio/speaker-readiness.sh"; R3="$W/root3"; mkdir -p "$R3/usr/share/speakersafetyd/apple" "$R3/proc/device-tree/sound" "$R3/sys/bus/i2c/devices"
rc=0; bash "$SR" --root "$R3" > "$W/sr.out" 2>&1 || rc=$?
[ $rc = 0 ] && grep -q '^BLOCKED' "$W/sr.out" && ok "readiness: an empty root is blocked, no tripwire" || { no "readiness: empty root (exit $rc)"; cat "$W/sr.out"; }
: > "$R3/usr/share/speakersafetyd/apple/k114.conf"; rc=0; bash "$SR" --root "$R3" > /dev/null 2>&1 || rc=$?; [ $rc = 3 ] && ok "readiness: a k114.conf trips it" || no "readiness: k114.conf did not trip"
rm "$R3/usr/share/speakersafetyd/apple/k114.conf"; mkdir "$R3/proc/device-tree/sound/dai-link@1"; rc=0; bash "$SR" --root "$R3" > /dev/null 2>&1 || rc=$?; [ $rc = 3 ] && ok "readiness: a second card link trips it" || no "readiness: dai-link@1 did not trip"
rmdir "$R3/proc/device-tree/sound/dai-link@1"; mkdir "$R3/sys/bus/i2c/devices/1-0038"; rc=0; bash "$SR" --root "$R3" > /dev/null 2>&1 || rc=$?; [ $rc = 3 ] && ok "readiness: a bound amplifier address trips it" || no "readiness: i2c 1-0038 did not trip"
if find "$here/linux/audio" -type f ! -name speaker-readiness.sh -print0 | xargs -0 grep -l -iE 'speakersafetyd|Speaker Volume Unlock|Speaker Protection' | grep -q .; then
  no "install: a shipped file names speakersafetyd or a speaker protection control"; else ok "install: no shipped file names speakersafetyd or a speaker protection control"; fi

# --- 7. what the installed speaker protection gate makes of the tree --------------------------------------------
gatelib=/usr/lib/speakerguardd-v2
if [ -f "$gatelib/wiring.py" ]; then
  cat > "$W/gate.py" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import wiring
wiring._fdt_to_dir(open(sys.argv[2], "rb").read(), sys.argv[3])
if wiring.has_speaker_link(sys.argv[3] + "/sound"):
    sys.exit("the gate sees a speaker link")
try:
    wiring.read_dt(sys.argv[3], sysfs="/nonexistent")
except wiring.Refused as e:
    print("refused:", e)
else:
    sys.exit("the gate found a speaker card")
PY
  expect "gate: speakerguardd v2's own reader finds no speaker card in the tree" python3 -I "$W/gate.py" "$gatelib" "$W/t6050-k114s-r3-sound.dtb" "$W/dt"
  [ -d "$W/dt/sound" ] && [ ! -e "$W/dt/sound/dai-link@1" ] &&
    ok "gate: /sound exists and /sound/dai-link@1 does not (the unit condition linux/audio installs)" || no "gate: unit condition paths"
else
  echo "skip gate: speakerguardd-v2 is not installed here"
fi

echo "sound tests: $pass passed, $fail failed"
[ "$fail" = 0 ]
