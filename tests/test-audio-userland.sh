#!/bin/bash
# Software tests for the K114s audio user space in linux/audio/ (replica tests; nothing here is hardware
# proof). No sound card, no root, and nothing is played: the PipeWire test runs a private daemon in a
# temporary runtime directory with no audio device in it, loads the graph and stops.
#
#   bash tests/test-audio-userland.sh
#
#   1. names: the card names the device tree and the kernel produce are the ones every user-space file
#      matches (a renamed model or chassis would otherwise leave PipeWire on its fallback profiles);
#   2. WirePlumber rules: parse, pro-audio off on the jack card, PCM 1 and 2 never nodes, one filter only;
#   3. no file gives the loudspeakers a device, a node, a graph or a daemon;
#   4. the microphone graph loads in a private PipeWire (which loads its plugins), and a broken copy
#      does not;
#   5. the speaker guard: tree-check on Stage A and speaker-path trees, speaker-readiness.sh, and the installer
#      (guard, refusals, --undo exactness, --check) in fake roots;
#   6. notes (never failures): what the installed Omarchy and Asahi files match by name.
# Tools: python3, spa-json-dump and pipewire where installed (steps that need a missing tool are skipped).
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
A="$here/linux/audio"
W=$(mktemp -d); daemon=
cleanup() { [ -n "$daemon" ] && kill "$daemon" 2>/dev/null; rm -rf "$W"; }
trap cleanup EXIT
pass=0; fail=0; skip=0
ok() { echo "ok   $1"; pass=$((pass+1)); }
no() { echo "FAIL $1"; fail=$((fail+1)); }
sk() { echo "skip $1"; skip=$((skip+1)); }
note() { echo "note $1"; }

# --- 1. names ---------------------------------------------------------------------------------------------
dtsi="$here/dts/t6050-k114s-sound.dtsi"
val() { sed -n "s/^[[:space:]]*$1 = \"\\([^\"]*\\)\".*/\\1/p" "$dtsi" | head -1; }
model=$(val model); chassis=$(val 'apple,chassis-name'); kind=$(val 'apple,machine-kind')
card_id="Apple${model##* }"                       # macaudio: "Apple" and the model's last word
mic_id="Apple${chassis}HPAI"                      # t8152-aop-audio
mic_long="$kind $chassis High-Power Audio Interface"
[ -n "$model" ] && [ -n "$chassis" ] && [ -n "$kind" ] && ok "names: the device tree gives model '$model', chassis '$chassis', kind '$kind'" ||
  no "names: model, chassis or machine kind missing in dts/t6050-k114s-sound.dtsi"
[ ${#card_id} -le 15 ] && [ ${#mic_id} -le 15 ] && ok "names: the card ids $card_id and $mic_id fit ALSA's 15 characters" || no "names: a card id is longer than 15 characters"
grep -q 'apple,k114-macaudio' "$here"/patches/linux/sound/0004-*.patch && grep -q '"apple,k114-macaudio"' "$dtsi" &&
  ok "names: the device tree's card compatible is the one patch 0004 adds" || no "names: the card compatible and patch 0004 disagree"
inst="$A/install-audio.sh"
grep -qF "|/usr/share/alsa/ucm2/conf.d/macaudio/$model.conf" "$inst" && ok "names: the jack profile is installed under the card's name" || no "names: no UCM file named '$model.conf' in the installer"
grep -qF "|/usr/share/alsa/ucm2/conf.d/aop_audio/$mic_long.conf" "$inst" && ok "names: the microphone profile is installed under the card's long name" || no "names: no UCM file named '$mic_long.conf' in the installer"

# --- 2. WirePlumber rules ---------------------------------------------------------------------------------
wp="$A/wireplumber/82-k114-audio.conf"
if command -v spa-json-dump >/dev/null; then
  if spa-json-dump "$wp" > "$W/wp.json" 2>"$W/err" && spa-json-dump "$A/share/mic.json" > "$W/mic.json" 2>>"$W/err"; then
    ok "wireplumber: the rules and the microphone graph parse (spa-json-dump)"
    python3 -I - "$W/wp.json" "$W/mic.json" "$model" "$card_id" "$mic_id" > "$W/sem" <<'EOF' || true
import json, sys
wp, mic = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
model, card, micid = sys.argv[3:6]
rules, dsp = wp["monitor.alsa.rules"], wp["node.software-dsp.rules"]
def acts(r): return r["actions"].get("update-props", {})
def check(what, cond): print(("ok   " if cond else "FAIL ") + what)
pro = [r for r in rules if acts(r).get("api.acp.disable-pro-audio") is True]
check("wireplumber: no pro-audio profile on the card named '%s'" % model,
      len(pro) == 1 and pro[0]["matches"] == [{"device.name": "~alsa_card.*", "api.alsa.card.name": model}])
off = [m for r in rules if acts(r).get("node.disabled") is True for m in r["matches"]]
want = [{"api.alsa.path": "hw:%s,%d" % (card, n)} for n in (1, 2)] + [{"alsa.id": card, "alsa.device": n} for n in (1, 2)]
check("wireplumber: PCM 1 and PCM 2 of %s never become nodes (by path and by card id)" % card, all(w in off for w in want))
raw = [r for r in rules if acts(r).get("node.name")]
check("wireplumber: the raw array hw:%s,0 is renamed" % micid,
      len(raw) == 1 and raw[0]["matches"] == [{"api.alsa.path": "hw:%s,0" % micid}])
check("wireplumber: one filter only, on the microphone array",
      len(dsp) == 1 and dsp[0]["matches"] == [{"api.alsa.path": "hw:%s,0" % micid}]
      and dsp[0]["actions"]["create-filter"].get("hide-parent") is True)
check("wireplumber: no rule names a property other than the six expected",
      {k for r in rules for k in acts(r)} == {"node.name", "node.description", "node.nick", "api.acp.disable-pro-audio", "node.disabled", "session.suspend-timeout-seconds"})
cap, play = mic["capture.props"], mic["playback.props"]
check("mic: the filter records from the node the rules name", raw and cap.get("target.object") == acts(raw[0]).get("node.name"))
check("mic: three raw channels in, one MONO source out",
      str(cap.get("audio.channels")) == "3" and str(play.get("audio.channels")) == "1"
      and play.get("audio.position") == ["MONO"] and play.get("media.class") == "Audio/Source")
print("PATH " + dsp[0]["actions"]["create-filter"]["filter-path"])
EOF
    while IFS= read -r line; do
      case "$line" in ok\ *) ok "${line#ok   }" ;; FAIL\ *) no "${line#FAIL }" ;; esac
    done < "$W/sem"
    grep -q '^ok' "$W/sem" || no "wireplumber: the rule checks did not run"
    fpath=$(sed -n 's/^PATH //p' "$W/sem")
    grep -qF "|$fpath" "$inst" && ok "mic: the graph is installed where the rule looks for it" || no "mic: the installer does not install $fpath"
  else
    no "wireplumber: the rules or the microphone graph do not parse"; sed 's/^/     /' "$W/err"
  fi
else
  sk "wireplumber: spa-json-dump is not installed here"
fi

# --- 3. nothing for the loudspeakers ----------------------------------------------------------------------
if grep -rnE 'RawSpeakers|convolver|graph(-[a-z0-9]+)?\.json|bankstown|speakersafetyd|Speaker (Volume|Protection|Switch|Playback)|SectionDevice\."Speaker' \
     "$A/ucm2" "$A/wireplumber" "$A/share" > "$W/spk" 2>/dev/null; then
  no "speakers: a user-space file names a speaker node, graph, plugin, control or daemon"; sed 's/^/     /' "$W/spk"
else
  ok "speakers: no user-space file names a speaker node, graph, plugin, control or daemon"
fi
[ -z "$(find "$A" -name '*.rules' -o -name 'k114.conf')" ] && ok "speakers: no udev rule and no protection profile is shipped" ||
  no "speakers: a udev rule or a k114.conf is shipped"

# --- 4. the microphone graph in a private PipeWire --------------------------------------------------------
R=$(mktemp -d "${TMPDIR:-/tmp}/k114au.XXXXXX"); mkdir -m 700 "$R/run" "$R/home"
if ! command -v pipewire >/dev/null || ! command -v pw-dump >/dev/null; then
  sk "mic: pipewire is not installed here"
elif [ ${#R} -gt 80 ]; then
  sk "mic: the temporary directory's path is too long for a socket (set TMPDIR to a short path)"
else
  cat > "$R/k114au-daemon.conf" <<'EOF'
context.properties = { core.daemon = true core.name = pipewire-0 default.clock.rate = 48000 log.level = 2 }
context.spa-libs = { audio.convert.* = audioconvert/libspa-audioconvert support.* = support/libspa-support }
context.modules = [
  { name = libpipewire-module-protocol-native }
  { name = libpipewire-module-access }
  { name = libpipewire-module-metadata }
  { name = libpipewire-module-spa-node-factory }
  { name = libpipewire-module-client-node }
  { name = libpipewire-module-adapter }
  { name = libpipewire-module-link-factory }
]
EOF
  client() { # graph file -> a client configuration that loads it as WirePlumber's software-dsp does
    { echo 'context.properties = { log.level = 2 }'
      echo 'context.spa-libs = { audio.convert.* = audioconvert/libspa-audioconvert support.* = support/libspa-support }'
      echo 'context.modules = ['
      echo '  { name = libpipewire-module-protocol-native }'
      echo '  { name = libpipewire-module-client-node }'
      echo '  { name = libpipewire-module-adapter }'
      echo '  { name = libpipewire-module-filter-chain args ='
      cat "$1"
      echo '  }'
      echo ']'; } > "$2"
  }
  # A clean environment: the private daemon's socket only, never the session's.
  # An array, not a function: "$!" must be the daemon itself, so that the cleanup stops it.
  P=(env -i HOME="$R/home" XDG_RUNTIME_DIR="$R/run" PATH=/usr/bin:/bin LANG=C)
  "${P[@]}" pipewire -c "$R/k114au-daemon.conf" > "$R/daemon.log" 2>&1 & daemon=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -S "$R/run/pipewire-0" ] && break; sleep 0.3; done
  if [ -S "$R/run/pipewire-0" ]; then
    client "$A/share/mic.json" "$R/k114au-mic.conf"
    "${P[@]}" timeout 8 pipewire -c "$R/k114au-mic.conf" > "$R/mic.log" 2>&1 & cl=$!
    sleep 2
    "${P[@]}" timeout 5 pw-dump > "$R/dump.json" 2>/dev/null || true
    kill "$cl" 2>/dev/null; wait "$cl" 2>/dev/null || true
    if python3 -I - "$R/dump.json" > "$R/nodes" 2>&1 <<'EOF'
import json, sys
nodes = {o["info"]["props"].get("node.name"): o["info"]["props"] for o in json.load(open(sys.argv[1]))
         if o.get("type", "").endswith(":Node")}
for n, p in sorted(nodes.items()): print(n, p.get("media.class"), p.get("audio.channels"))
src, cap = nodes.get("effect_output.k114-mic"), nodes.get("audio_effect.k114-mic")
sys.exit(0 if src and cap and src.get("media.class") == "Audio/Source" and len(nodes) == 2 else 1)
EOF
    then ok "mic: the graph loads in a private PipeWire and makes the mono source and its capture stream, nothing else"
    elif grep -q "can't load plugin" "$R/mic.log"; then sk "mic: a plugin of the graph is not installed here: $(grep -m1 -o "can't load plugin [^ ]*" "$R/mic.log")"
    else no "mic: the graph did not make its two nodes in a private PipeWire"; sed 's/^/     /' "$R/nodes" "$R/mic.log" | head -20; fi
    # the optional beamformed graph: same two nodes, same names (it replaces mic.json when asked for)
    client "$A/share/mic-beamformer.json" "$R/k114au-bf.conf"
    "${P[@]}" timeout 8 pipewire -c "$R/k114au-bf.conf" > "$R/bf.log" 2>&1 & cl=$!
    sleep 2
    "${P[@]}" timeout 5 pw-dump > "$R/dumpbf.json" 2>/dev/null || true
    kill "$cl" 2>/dev/null; wait "$cl" 2>/dev/null || true
    if python3 -I - "$R/dumpbf.json" > /dev/null 2>&1 <<'EOF'
import json, sys
n = {o["info"]["props"].get("node.name") for o in json.load(open(sys.argv[1])) if o.get("type", "").endswith(":Node")}
sys.exit(0 if n == {"effect_output.k114-mic", "audio_effect.k114-mic"} else 1)
EOF
    then ok "mic: the optional beamformed graph loads in a private PipeWire (triforce and the limiter plugin found)"
    elif grep -q "can't load plugin" "$R/bf.log"; then sk "mic: a plugin of the beamformed graph is not installed here: $(grep -m1 -o "can't load plugin [^ ]*" "$R/bf.log")"
    else no "mic: the beamformed graph did not make its two nodes"; sed 's/^/     /' "$R/bf.log" | head -10; fi
    sed 's/"lim:in"/"lim:nosuchport"/' "$A/share/mic.json" > "$R/bad.json"; client "$R/bad.json" "$R/k114au-bad.conf"
    if "${P[@]}" timeout 5 pipewire -c "$R/k114au-bad.conf" > "$R/bad.log" 2>&1; then no "mic: a graph with a wrong port name was accepted"
    elif grep -q "unknown input port" "$R/bad.log"; then ok "mic: a graph with a wrong port name is refused (the test can fail)"
    else no "mic: the broken graph failed for another reason"; sed 's/^/     /' "$R/bad.log" | head -5; fi
  else
    sk "mic: the private PipeWire daemon did not start"; sed 's/^/     /' "$R/daemon.log" | head -5
  fi
  kill "$daemon" 2>/dev/null; wait "$daemon" 2>/dev/null || true; daemon=
fi
rm -rf "$R"

# --- 5. the speaker guard, the tree check and the installer (fake roots, no root rights) ----------------------
TC="$A/tree-check"; SR="$A/speaker-readiness.sh"; INS="$A/install-audio.sh"
printf 'apple,k114s\0apple,t6050\0' > "$W/compat"; printf 'apple,j714s\0apple,t6050\0' > "$W/compat-j714s"
rc_of() { local rc=0; "$@" > "$W/o" 2>&1 || rc=$?; echo $rc; }
tree() { # NAME: a fake root with the Stage A tree (one jack link, no amplifier)
  local r=$W/$1; rm -rf "$r"; mkdir -p "$r/proc/device-tree/sound/dai-link@0" "$r/proc/device-tree/aop-audio" "$r/sys/bus/i2c/devices" "$r/usr/share/speakersafetyd/apple" "$r/usr/lib/systemd/system"
  printf 'apple,k114-macaudio\0apple,macaudio\0' > "$r/proc/device-tree/sound/compatible"
  printf 'Headphone Jack\0' > "$r/proc/device-tree/sound/dai-link@0/link-name"
  printf 'cout\0cin\0hpai\0' > "$r/proc/device-tree/aop-audio/dma-names"
  echo "$r"
}
r=$(tree t1); [ "$(rc_of "$TC" --root "$r")" = 0 ] && ok "guard: the Stage A tree passes tree-check" || no "guard: the Stage A tree fails tree-check"
r=$(tree t2); rm -r "$r/proc/device-tree/sound"; [ "$(rc_of "$TC" --root "$r")" = 0 ] && ok "guard: no sound node passes tree-check" || no "guard: a tree without sound fails tree-check"
[ "$(rc_of "$TC" --root "$W/nonexistent")" = 1 ] && ok "guard: a tree that cannot be read fails tree-check" || no "guard: unreadable tree passed"
bad() { # WHAT, then a command that turns the Stage A fake root in $r into a tree with a speaker path
  local what=$1; shift; r=$(tree t3); ( cd "$r/proc/device-tree" && "$@" )
  [ "$(rc_of "$TC" --root "$r")" = 1 ] && ok "guard: tree-check refuses $what" || no "guard: tree-check accepted $what"
}
bad "a packaged J714 card"            sh -c "printf 'apple,j714-macaudio\0apple,macaudio\0' > sound/compatible"
bad "a Speaker link at dai-link@1"    mkdir sound/dai-link@1
bad "a Speaker link at dai-link@2"    mkdir sound/dai-link@2
bad "a Speaker link at another unit address" mkdir sound/dai-link@a0
bad "a link named Speaker at dai-link@0" sh -c "printf 'Speaker\0' > sound/dai-link@0/link-name"
bad "an sn012776 node"                sh -c "mkdir amp; printf 'ti,sn012776\0' > amp/compatible"
bad "a tas27xx node"                  sh -c "mkdir amp; printf 'ti,tas2764\0' > amp/compatible"
ssm() { sh -c "mkdir amp; printf 'adi,ssm3515\0' > amp/compatible"; }
bad "an ssm3515 node"                 ssm
bad "a max98360a node"                sh -c "mkdir amp; printf 'maxim,max98360a\0' > amp/compatible"
bad "a spkr DMA channel"              sh -c "printf 'cout\0cin\0spkr\0' > aop-audio/dma-names"
bad "a sense DMA channel"             sh -c "printf 'cout\0cin\0sense\0' > aop-audio/dma-names"
bad "an extra compatible string"      sh -c "printf 'apple,k114-macaudio\0apple,j714-macaudio\0apple,macaudio\0' > sound/compatible"
# the amplifier, DMA and I2C checks hold without a sound node too
nosound() { r=$(tree t9); rm -r "$r/proc/device-tree/sound"; ( cd "$r/proc/device-tree" && "$@" ); }
nosound sh -c "mkdir amp; printf 'ti,sn012776\0' > amp/compatible"; [ "$(rc_of "$TC" --root "$r")" = 1 ] && ok "guard: tree-check refuses an amplifier node when there is no sound node" || no "guard: no-sound tree with an amplifier passed"
nosound sh -c "printf 'cout\0cin\0spkr\0sense\0' > aop-audio/dma-names"; [ "$(rc_of "$TC" --root "$r")" = 1 ] && ok "guard: tree-check refuses a spkr channel when there is no sound node" || no "guard: no-sound tree with spkr passed"
nosound sh -c "printf 'cout\0cin\0spkr\0sense\0' > aop-audio/dma-names; printf 'disabled\0' > aop-audio/status"; [ "$(rc_of "$TC" --root "$r")" = 0 ] && ok "guard: a spkr channel on a disabled node is harmless and passes" || no "guard: disabled aop node refused"
nosound sh -c "printf 'cout\0cin\0spkr\0sense\0' > aop-audio/dma-names; printf 'okay\0' > aop-audio/status"; [ "$(rc_of "$TC" --root "$r")" = 1 ] && ok "guard: a spkr channel on an okay node is refused" || no "guard: okay aop node with spkr passed"
nosound true; mkdir "$r/sys/bus/i2c/devices/1-0038"; [ "$(rc_of "$TC" --root "$r")" = 1 ] && ok "guard: tree-check refuses a bound amplifier address when there is no sound node" || no "guard: no-sound i2c passed"
# as on the Mac, /proc/device-tree is a symlink (to /sys/firmware/devicetree/base): the DMA scan must follow it
r=$(tree t10); mkdir -p "$r/sys/firmware/devicetree"; mv "$r/proc/device-tree" "$r/sys/firmware/devicetree/base"; ln -s ../sys/firmware/devicetree/base "$r/proc/device-tree"
[ "$(rc_of "$TC" --root "$r")" = 0 ] && ok "guard: the Stage A tree behind a /proc/device-tree symlink passes" || no "guard: symlinked Stage A tree failed"
printf 'cout\0cin\0spkr\0' > "$r/sys/firmware/devicetree/base/aop-audio/dma-names"
[ "$(rc_of "$TC" --root "$r")" = 1 ] && ok "guard: a spkr channel behind a /proc/device-tree symlink is refused" || no "guard: symlinked tree with spkr passed"
# a node whose parent is disabled never binds, whatever its own status says
nosound sh -c "mkdir -p aop/audio; printf 'disabled\0' > aop/status; printf 'cout\0cin\0spkr\0' > aop/audio/dma-names"; [ "$(rc_of "$TC" --root "$r")" = 0 ] && ok "guard: a spkr channel under a disabled parent is harmless and passes" || no "guard: disabled parent refused"
nosound sh -c "mkdir -p aop/audio; printf 'okay\0' > aop/status; printf 'cout\0cin\0spkr\0' > aop/audio/dma-names"; [ "$(rc_of "$TC" --root "$r")" = 1 ] && ok "guard: a spkr channel under an okay parent is refused" || no "guard: okay parent with spkr passed"
r=$(tree t4); mkdir "$r/sys/bus/i2c/devices/1-003b"; [ "$(rc_of "$TC" --root "$r")" = 1 ] && ok "guard: tree-check refuses a bound amplifier address" || no "guard: i2c amplifier address accepted"

# the readiness report: the tree check, the marker, the guard, a sibling's k114.conf
r=$(tree t5); [ "$(rc_of bash "$SR" --root "$r")" = 0 ] && ok "readiness: the Stage A tree, no guard needed while no speaker unit exists" || { no "readiness: Stage A tree tripped"; cat "$W/o"; }
mkdir "$r/proc/device-tree/sound/dai-link@2"; [ "$(rc_of bash "$SR" --root "$r")" = 3 ] && ok "readiness: a Speaker link at dai-link@2 trips" || no "readiness: dai-link@2 did not trip"
r=$(tree t6); printf 'apple,j714-macaudio\0apple,macaudio\0' > "$r/proc/device-tree/sound/compatible"
[ "$(rc_of bash "$SR" --root "$r")" = 3 ] && ok "readiness: a packaged J714 tree trips" || no "readiness: J714 tree did not trip"
r=$(tree t7); mkdir -p "$r/etc/omarchy-k114s"; : > "$r/etc/omarchy-k114s/speaker-qualification"
[ "$(rc_of bash "$SR" --root "$r")" = 3 ] && ok "readiness: the owner's marker with the proofs missing trips" || no "readiness: marker did not trip"
r=$(tree t8); : > "$r/usr/lib/systemd/system/speakersafetyd.service"
[ "$(rc_of bash "$SR" --root "$r")" = 3 ] && ok "readiness: a speaker unit without the guard trips" || no "readiness: unguarded unit did not trip"
mkdir -p "$r/etc/systemd/system/speakersafetyd.service.d"; cp "$A/systemd/99-k114s-speaker-guard.conf" "$r/etc/systemd/system/speakersafetyd.service.d/"
[ "$(rc_of bash "$SR" --root "$r")" = 0 ] && ok "readiness: the guarded unit does not trip" || { no "readiness: guarded unit tripped"; cat "$W/o"; }
: > "$r/usr/share/speakersafetyd/apple/k114.conf"
[ "$(rc_of bash "$SR" --root "$r")" = 3 ] && ok "readiness: a sibling's k114.conf still trips (and the unit stays guarded)" || no "readiness: k114.conf did not trip"

r=$(tree t10); : > "$r/usr/lib/systemd/system/speakerguardd-v2-seat.path"
[ "$(rc_of bash "$SR" --root "$r")" = 3 ] && ok "readiness: an unguarded seat .path unit trips" || no "readiness: seat path did not trip"
mkdir -p "$r/etc/systemd/system/speakerguardd-v2-seat.path.d"; cp "$A/systemd/99-k114s-speaker-guard.conf" "$r/etc/systemd/system/speakerguardd-v2-seat.path.d/"
[ "$(rc_of bash "$SR" --root "$r")" = 0 ] && ok "readiness: the guarded seat .path unit does not trip" || no "readiness: guarded seat path tripped"
mkdir -p "$r/usr/lib/systemd/user"; : > "$r/usr/lib/systemd/user/speakerguardd-v2-graph.service"
[ "$(rc_of bash "$SR" --root "$r")" = 3 ] && ok "readiness: an unguarded v2 user unit trips" || no "readiness: user unit did not trip"
mkdir -p "$r/etc/systemd/user/speakerguardd-v2-graph.service.d"; cp "$A/systemd/99-k114s-speaker-guard.conf" "$r/etc/systemd/user/speakerguardd-v2-graph.service.d/"
[ "$(rc_of bash "$SR" --root "$r")" = 0 ] && ok "readiness: the guarded v2 user unit does not trip" || no "readiness: guarded user unit tripped"

# the readiness report and the user manager (a fake systemctl: --user show works, cat prints a merged unit)
r=$(tree t11); mkdir -p "$r/etc/systemd/user/wireplumber.service.d" "$r/usr/lib/systemd/user"
: > "$r/etc/systemd/user/wireplumber.service.d/99-k114s-stage-a-tree.conf"; : > "$r/usr/lib/systemd/user/speakerguardd-v2-graph.service"
mkdir -p "$r/etc/systemd/user/speakerguardd-v2-graph.service.d"; cp "$A/systemd/99-k114s-speaker-guard.conf" "$r/etc/systemd/user/speakerguardd-v2-graph.service.d/"
mkdir -p "$W/fakebin"; cat > "$W/fakebin/systemctl" <<'SH'
#!/bin/sh
# --user show ...: succeed. --user cat UNIT: print what $FAKE_USER_LOADED (a file) holds when set, else nothing
[ "$1" = --user ] && [ "$2" = show ] && exit 0
[ "$1" = --user ] && [ "$2" = cat ] && { [ -n "$FAKE_USER_LOADED" ] && cat "$FAKE_USER_LOADED"; exit 0; }
exit 1
SH
chmod +x "$W/fakebin/systemctl"
printf 'ExecCondition=/usr/local/lib/omarchy-k114s/audio/tree-check\nConditionPathExists=/etc/omarchy-k114s/speaker-qualification\n' > "$W/loaded"
if [ "$(id -u)" != 0 ]; then
  rdy() { K114S_SYSTEMCTL="$W/fakebin/systemctl" FAKE_USER_LOADED="$1" rc_of bash "$SR" --root "$r"; }
  [ "$(rdy "$W/loaded")" = 0 ] && ok "readiness: the user manager has loaded the tree check and the user guard" || { no "readiness: loaded user units tripped"; cat "$W/o"; }
  [ "$(rdy "")" = 3 ] && grep -q 'systemctl --user daemon-reload' "$W/o" && ok "readiness: user drop-ins the user manager has not loaded trip (the missing daemon-reload)" || no "readiness: unloaded user units did not trip"
else sk "readiness: the user-manager check is for the seat user, not root"; fi

# the installer
mk() { rm -rf "$1"; mkdir -p "$1/usr/share/alsa/ucm2/conf.d/macaudio/cs42l84" "$1/proc/device-tree" "$1/etc"; : > "$1/usr/share/alsa/ucm2/conf.d/macaudio/cs42l84/HiFi-jack.conf"; }
inst() { K114S_DT_COMPATIBLE="$W/compat" bash "$INS" --root "$I" "$@"; }
I=$W/i1; mk "$I"; find "$I" | sort > "$W/before"
[ "$(rc_of inst)" = 0 ] && ok "install: installs into a fake root" || { no "install: install failed"; cat "$W/o"; }
g=$(find "$I" -name 99-k114s-speaker-guard.conf | wc -l)
[ "$g" = 12 ] && ok "install: the guard lands on the nine speaker units, the seat path and the two user units" || no "install: $g guard drop-ins, not 12"
for u in speakerguardd-v2-graph speakerguardd-v2-session; do
  grep -q '^ConditionPathExists=/etc/omarchy-k114s/speaker-qualification$' "$I/etc/systemd/user/$u.service.d/99-k114s-speaker-guard.conf" || no "install: no guard on user unit $u"
done
for u in speakersafetyd speakerguardd-v2 aurora-speaker-upgrade; do
  grep -q '^ConditionPathExists=/etc/omarchy-k114s/speaker-qualification$' "$I/etc/systemd/system/$u.service.d/99-k114s-speaker-guard.conf" || no "install: no guard on $u"
done
[ -x "$I/usr/local/lib/omarchy-k114s/audio/tree-check" ] && grep -q 'tree-check' "$I/etc/systemd/user/wireplumber.service.d/99-k114s-stage-a-tree.conf" &&
  ok "install: tree-check is installed and WirePlumber waits for it" || no "install: tree-check or its WirePlumber condition missing"
[ ! -e "$I/etc/omarchy-k114s/speaker-qualification" ] && ok "install: the qualification marker is not created" || no "install: the installer created the marker"
[ "$(rc_of inst --check)" = 0 ] && ok "install: --check is clean after an install" || { no "install: --check after install"; cat "$W/o"; }
mkdir -p "$I/etc/omarchy-k114s"; : > "$I/etc/omarchy-k114s/speaker-qualification"
[ "$(rc_of inst --undo)" = 0 ] && ok "install: --undo runs" || no "install: --undo failed"
[ -e "$I/etc/omarchy-k114s/speaker-qualification" ] && ok "install: --undo leaves the owner's marker alone" || no "install: --undo removed the owner's marker"
[ "$(find "$I" -name 99-k114s-speaker-guard.conf | wc -l)" = 12 ] && [ -x "$I/usr/local/lib/omarchy-k114s/audio/tree-check" ] &&
  [ -f "$I/etc/systemd/user/wireplumber.service.d/99-k114s-stage-a-tree.conf" ] && ok "install: --undo keeps the speaker guard and the tree check" || no "install: --undo removed the guard"
[ ! -e "$I/etc/wireplumber/wireplumber.conf.d/82-k114-audio.conf" ] && [ ! -e "$I/usr/share/alsa/ucm2/conf.d/macaudio/MacBook Pro K114.conf" ] && ok "install: --undo removed the jack and microphone files" || no "install: --undo left jack or microphone files"
[ "$(rc_of inst --check)" = 1 ] && ok "install: --check says missing after --undo (the jack files)" || no "install: --check after --undo"
rm -r "$I/etc/omarchy-k114s"
[ "$(rc_of inst --remove-guard)" = 1 ] && [ "$(find "$I" -name 99-k114s-speaker-guard.conf | wc -l)" = 12 ] && ok "install: --remove-guard is refused while the owner's marker does not exist" || no "install: --remove-guard without a marker"
mkdir -p "$I/etc/omarchy-k114s"; : > "$I/etc/omarchy-k114s/speaker-qualification"
[ "$(rc_of inst --remove-guard)" = 0 ] && ok "install: --remove-guard runs once the marker exists" || { no "install: --remove-guard with the marker"; cat "$W/o"; }
rm -r "$I/etc/omarchy-k114s"; find "$I" | sort > "$W/after"
diff -q "$W/before" "$W/after" > /dev/null && ok "install: --undo then --remove-guard is exact (files and directories as before)" || { no "install: undo and remove-guard left a difference"; diff "$W/before" "$W/after" | head; }
# the user manager is not reachable through sudo: every path that touches the user units says to reload it
hint='systemctl --user daemon-reload'
I=$W/h1; mk "$I"; inst > "$W/o" 2>&1; grep -q "$hint" "$W/o" && ok "install: the install path prints the user daemon-reload hint" || no "install: no user daemon-reload hint on install"
inst --undo > "$W/o" 2>&1; grep -q "$hint" "$W/o" && ok "install: --undo prints the user daemon-reload hint" || no "install: no user daemon-reload hint on --undo"
mkdir -p "$I/etc/omarchy-k114s"; : > "$I/etc/omarchy-k114s/speaker-qualification"
inst --remove-guard > "$W/o" 2>&1; grep -q "$hint" "$W/o" && ok "install: --remove-guard prints the user daemon-reload hint" || no "install: no user daemon-reload hint on --remove-guard"
I=$W/h2; mk "$I"; rm "$I/usr/share/alsa/ucm2/conf.d/macaudio/cs42l84/HiFi-jack.conf"
inst > "$W/o" 2>&1 || true; grep -q "$hint" "$W/o" && ok "install: a refused install prints the user daemon-reload hint (the guard went in)" || no "install: no user daemon-reload hint on a refusal"
# a directory somebody else put into ours stays; one run, a graph switch, and --check follow the installed graph
I=$W/i2; mk "$I"; find "$I" | sort > "$W/before"
inst > /dev/null; inst --with-beamformer > /dev/null
[ "$(rc_of inst --check)" = 0 ] && ok "install: --check after --with-beamformer follows the installed graph" || { no "install: --check after --with-beamformer"; cat "$W/o"; }
inst > /dev/null; [ "$(rc_of inst --check)" = 0 ] && ok "install: --check after going back to the plain graph" || no "install: --check after the plain graph"
inst --undo > /dev/null; mkdir -p "$I/etc/omarchy-k114s"; : > "$I/etc/omarchy-k114s/speaker-qualification"; inst --remove-guard > /dev/null; rm -r "$I/etc/omarchy-k114s"; find "$I" | sort > "$W/after"
diff -q "$W/before" "$W/after" > /dev/null && ok "install: --undo after two runs is exact" || { no "install: --undo after two runs"; diff "$W/before" "$W/after" | head; }
# refusals
I=$W/i3; mk "$I"; mkdir -p "$I/proc/device-tree/sound/dai-link@0"; printf 'apple,j714-macaudio\0apple,macaudio\0' > "$I/proc/device-tree/sound/compatible"
refused() { # the jack and microphone files are absent, the guard (12 drop-ins, tree-check, the WirePlumber drop-in) is in place
  [ "$(find "$1" -name 99-k114s-speaker-guard.conf | wc -l)" = 12 ] && [ -x "$1/usr/local/lib/omarchy-k114s/audio/tree-check" ] &&
  [ ! -e "$1/etc/wireplumber/wireplumber.conf.d/82-k114-audio.conf" ] && [ ! -e "$1/usr/local/share/omarchy-k114s/audio/mic.json" ]
}
[ "$(rc_of inst)" = 1 ] && refused "$I" && ok "install: refuses a booted tree with another model's card, installs the guard and nothing else" || no "install: accepted a J714 tree, or left no guard"
I=$W/i4; mk "$I"; mkdir -p "$I/usr/local/lib/omarchy-k114s"; : > "$I/usr/local/lib/omarchy-k114s/use-packaged-dtb"
[ "$(rc_of inst)" = 1 ] && refused "$I" && ok "install: use-packaged-dtb refuses the jack and microphone files but still installs the guard" || no "install: use-packaged-dtb: accepted, or no guard"
rm "$I/usr/local/lib/omarchy-k114s/use-packaged-dtb"; mkdir -p "$I/etc/omarchy-k114s"
[ "$(rc_of inst --undo)" = 0 ] && [ "$(find "$I" -name 99-k114s-speaker-guard.conf | wc -l)" = 12 ] && ok "install: --undo after a refused install keeps the guard" || no "install: --undo after a refusal"
I=$W/i6; mk "$I"; rm "$I/usr/share/alsa/ucm2/conf.d/macaudio/cs42l84/HiFi-jack.conf"
[ "$(rc_of inst)" = 1 ] && refused "$I" && ok "install: a missing jack verb refuses the jack files but still installs the guard" || no "install: missing verb"
I=$W/i5; mk "$I"; [ "$(rc_of env K114S_DT_COMPATIBLE="$W/compat-j714s" bash "$INS" --root "$I")" = 1 ] && ok "install: refuses a Mac that is not apple,k114s" || no "install: accepted a J714s"

# --- 6. notes on the installed image (never failures) -----------------------------------------------------
m=/usr/bin/omarchy-audio-asahi-mic-map
if [ -f "$m" ]; then
  grep -q "effect_output\\\\.j\[0-9\]+-mic" "$m" &&
    note "omarchy-mac's microphone mapper looks for effect_output.jNNN-mic: it leaves effect_output.k114-mic alone (no stereo mapping)"
  grep -q "AppleJ\[0-9\]+(?:HPAI|AOP)" "$m" && note "omarchy-mac's mapper knows array cards named AppleJ...: not $mic_id"
fi
s=/usr/share/wireplumber/wireplumber.conf.d
[ -f "$s/99-asahi.conf" ] && ! grep -q "Apple\[JK\]\|AppleK" "$s/99-asahi.conf" &&
  note "the installed asahi-audio rules match AppleJ... cards only: the K114 rules here are needed"
[ -f "$s/asahi-audio-no-suspend.conf" ] && note "omarchy-mac's no-suspend rule matches AppleJ... only: the K114 jack sink suspends when idle"
for f in "/usr/share/alsa/ucm2/conf.d/macaudio/$model.conf" "/usr/share/alsa/ucm2/conf.d/aop_audio/$mic_long.conf"; do
  [ -e "$f" ] && note "already on this system: $f ($(cmp -s "$f" /dev/null; pacman -Qqo "$f" 2>/dev/null || echo 'no package'))"
done

echo "audio user-space tests: $pass passed, $fail failed, $skip skipped"
[ "$fail" = 0 ]
