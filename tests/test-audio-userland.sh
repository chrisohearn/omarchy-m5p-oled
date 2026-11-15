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
#   5. notes (never failures): what the installed Omarchy and Asahi files match by name.
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
check("wireplumber: no rule names a property other than the five expected",
      {k for r in rules for k in acts(r)} == {"node.name", "node.description", "node.nick", "api.acp.disable-pro-audio", "node.disabled"})
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

# --- 5. notes on the installed image (never failures) -----------------------------------------------------
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
