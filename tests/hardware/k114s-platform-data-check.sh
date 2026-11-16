#!/bin/bash
# OWNER AT THE MAC. Read-only report for the omarchy-mac overlay (patches/omarchy/0003, 0004;
# docs/platform-data.md). No root, nothing written, nothing played, no hardware state changed.
#   tests/hardware/k114s-platform-data-check.sh
# Prints "ok", "BAD", "info" and "TODO" lines. A TODO is for you to do by eye or ear; the script cannot.
ok() { echo "ok    $*"; }; bad() { echo "BAD   $*"; }; info() { echo "info  $*"; }; todo() { echo "TODO  $*"; }

echo "== display: the notch floor"
mode=$(hyprctl monitors -j 2>/dev/null | python3 -c 'import json,sys
for m in json.load(sys.stdin): print(m["name"], m["width"], m["height"], m["scale"], m.get("reserved"))' | grep '^eDP' | head -1)
if [ -z "$mode" ]; then info "no eDP monitor from Hyprland (an unconverted boot framebuffer is named Unknown-1)"; mode=$(hyprctl monitors -j | python3 -c 'import json,sys
m=json.load(sys.stdin)[0]; print(m["name"], m["width"], m["height"], m["scale"], m.get("reserved"))'); fi
info "internal panel: name mode(WxH) scale reserved = $mode"
read -r name w h scale _ <<<"$mode"
if python3 -I -c 'import json,sys
w,h=int(sys.argv[1]),int(sys.argv[2])
sys.exit(0 if any(p.get("connector")=="eDP" and abs(p["width"]-w)<=4 and abs(p["height"]-h)<=4 for p in json.load(open("/usr/share/omarchy-platform/display-cutouts.json"))["panels"]) else 1)' "$w" "$h"; then
  ok "display-cutouts.json has an entry for ${w}x${h}"
else
  case $name in eDP*) bad "no display-cutouts.json entry for ${w}x${h}: the bar has no notch floor (the DCP mode differs from 3024x1986; if the notch is hidden in this mode, no entry is right)" ;;
    *) bad "no display-cutouts.json entry for ${w}x${h} (is overlay 0003 installed? The booted framebuffer is Unknown-1 and has its own local line)" ;;
 esac
fi
grep -q '"height": 1986' /usr/share/omarchy-platform/display-cutouts.json && info "installed entry: $(grep '"height": 1986' /usr/share/omarchy-platform/display-cutouts.json | tr -s ' ')"
todo "MEASURE THE NOTCH. With the bar showing, look at the top edge: does any window or bar content peek out above or beside the camera notch, or is the bar much taller than the notch? The entry's top (96 rows = 48 logical px at scale 2) is derived, not measured. Take a photo or grim screenshot, count the bar's logical px, and report 'bar N px, notch Y mm wide'. To try a different value without a package: sudo editing is NOT needed, set [bar] notch-height = <logical px> in ~/.config/omarchy/shell.toml (it replaces the derived value only where an entry matches)."

echo "== audio: names and rules (needs the r3a sound boot; before that these report 'no card')"
cards=$(cat /proc/asound/cards 2>/dev/null)
case $cards in *AppleK114*) ok "card present: $(grep -o 'AppleK114[A-Za-z]*' <<<"$cards" | sort -u | tr '\n' ' ')" ;; *) info "no AppleK114 card yet: the audio checks below say what to expect" ;; esac
nodes=$(pw-dump 2>/dev/null | python3 -c 'import json,sys
for o in json.load(sys.stdin):
    p=o.get("info",{}).get("props",{}) if isinstance(o.get("info"),dict) else {}
    if o.get("type","").endswith(":Node"): print(p.get("node.name"),"|",p.get("node.description"),"|",p.get("media.class"),"|",p.get("priority.session"),"|",p.get("session.suspend-timeout-seconds"))' 2>/dev/null)
want() { grep -qF "$1" <<<"$nodes" && ok "node $1" || bad "no node $1 (expected: $2)"; }
want "alsa_output.platform-sound.HiFi__Headphones__sink" "the jack's output; description Headphones"
want "alsa_input.platform-sound.HiFi__Headset__source" "the headset mic; description Headset Microphone"
want "effect_output.k114-mic" "the mono DSP source; description MacBook Microphone (Mono)"
want "omarchy_asahi_mic" "the stereo source (omarchy-audio-asahi-mic-map, overlay 0004); not in the list when the mapper cannot find the mono one"
grep -q "audio_effect.k114-mic" <<<"$nodes" && info "audio_effect.k114-mic exists (the capture side): audio.json (overlay 0004) should hide it in the panel"
hs=$(grep -F "HiFi__Headset__source" <<<"$nodes" | head -1 | awk -F' [|] ' '{print $4}')
[ "$hs" = 1 ] && ok "the headset source has priority.session 1 (asahi-headset-mic.conf matched)" || { [ -n "$hs" ] && bad "headset source priority.session is '$hs', not 1: the rule did not match this node name" || info "no headset source node yet"; }
info "default source: $(pactl get-default-source 2>/dev/null)   default sink: $(pactl get-default-sink 2>/dev/null)"
todo "HEADSET: plug a headset with a mic, record 5 s (pw-record --target <the headset source>), unplug, replug. After unplugging, the default input must be the built-in array (omarchy_asahi_mic or effect_output.k114-mic), never the headset source. Press each headset button once and note what happens."
todo "POP: play something through the headphones; stop it; start it again. Listen for a pop at each start and stop. A pop means the no-suspend rule did not hold (check 'session.suspend-timeout-seconds' on the sink: pw-dump | grep -A3 HiFi__Headphones__sink). Do not raise the volume."
todo "PANEL NAMES: open the Omarchy audio panel. Expected names: Headphones; Headset Microphone; MacBook Microphone (Mono) or the stereo source; no 'Raw Mic Device' and no 'audio_effect.k114-mic' row. NEVER enable or test the loudspeakers: there is no protection data."
