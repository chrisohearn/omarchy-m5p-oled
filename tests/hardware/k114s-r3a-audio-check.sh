#!/bin/bash
# OWNER-RUN, ATTENDED. After the first boot of the r3a kernel with the SOUND tree (t6050-k114s-r3a-sound),
# this reports what the headphone jack, the microphones and Bluetooth audio look like. READ-ONLY: it
# changes no setting, loads no module, pairs nothing and needs no root (a few lines are better with root
# and say so). It plays nothing unless you pass --play. Nothing is ever sent to the loudspeakers: the
# sound tree has no speaker path, and --play refuses any sink that is not the jack card.
#
#   bash tests/hardware/k114s-r3a-audio-check.sh [--listen] [--play] [--no-save]
#     (no flags)  the read-only report only
#     --listen    asks you to plug and unplug headphones, and to listen over Bluetooth, and reads
#                 the jack state and the Wi-Fi link before and after each step (prompts on the terminal)
#     --play      with --listen: plays a 2 s quiet tone on the jack sink after you confirm headphones are
#                 on and the volume is low. Refuses unless the sink is the K114 jack card and its volume
#                 is at or below 50%.
#     --no-save   do not write the report to ~/k114s-audio-check-DATE.txt
#
# The jack card must be AppleK114 and the microphone card AppleK114HPAI (tests/test-audio-userland.sh keeps
# those names in step with the device tree). Bluetooth device addresses (colon, underscore and dash forms, as in bluez_card.xx_xx_...) are replaced by XX:XX:XX:XX:XX:XX
# in the output, and no serial numbers are printed, so the report can be pasted into an issue.
# Evidence from this script is "owner-observed" only for the lines you confirm by ear (ASK lines).
# Before the boot, the same questions for the BUILT package were answered offline (docs/r3-audio.md, "The r3a package").
#
# Lines: ok / BAD (a failed expectation) / info / ASK (needs your ears or hands) / unknown (could not tell).
listen=0; play=0; save=1
for a in "$@"; do
  case $a in
    --listen) listen=1 ;; --play) play=1 ;; --no-save) save=0 ;;
    *) echo "usage: k114s-r3a-audio-check.sh [--listen] [--play] [--no-save]" >&2; exit 2 ;;
  esac
done
[ $play = 1 ] && [ $listen = 0 ] && { echo "--play needs --listen" >&2; exit 2; }
here=$(cd "$(dirname "$0")/../.." && pwd)
if [ $save = 1 ]; then
  out=$HOME/k114s-audio-check-$(date +%Y%m%d-%H%M%S).txt
  exec > >(sed -u -E 's/([0-9A-Fa-f]{2}[:_-]){5}[0-9A-Fa-f]{2}/XX:XX:XX:XX:XX:XX/g' | tee "$out") 2>&1
else
  exec > >(sed -u -E 's/([0-9A-Fa-f]{2}[:_-]){5}[0-9A-Fa-f]{2}/XX:XX:XX:XX:XX:XX/g') 2>&1
fi
ok() { echo "ok      $*"; }; bad() { echo "BAD     $*"; nbad=$((nbad+1)); }; nospk() { nospk=1; }; info() { echo "info    $*"; }
unk() { echo "unknown $*"; }; ask() { echo "ASK     $*"; }
nbad=0; nospk=0   # nospk=1: a speaker path may exist or the kernel is wrong; --play and the attended part refuse
have() { command -v "$1" >/dev/null 2>&1; }
# prompts go to the terminal, not through the redacting pipe
# a Bluetooth device's own name (often a person's) is dropped from wpctl lines whose tag is [bluez5]
names() { sed -E '/\[bluez5\]/ s/([0-9]+\.) .* (\[bluez5\])/\1 <bluetooth device> \2/'; }
pause() { printf '\n>>> %s\n    Press Enter when done (Ctrl-C stops the script; nothing needs undoing).\n' "$1" >/dev/tty; read -r _ </dev/tty; }
jack_state() { amixer -c AppleK114 contents 2>/dev/null | grep -A2 -i "Headphone Jack\|Headset Jack\|Jack" | grep -E "numid|: values=" | tr '\n' ' '; }
irqs() { awk '/cs42l84/ {s+=$2} END {print s+0}' /proc/interrupts 2>/dev/null; }

echo "== K114s r3a audio and Bluetooth check, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "== 1. kernel and tree"
rel=$(uname -r)
case $rel in *k114s-r3a-ARCH) ok "running kernel $rel" ;; *) bad "running kernel is $rel, not the r3a kernel: stop here, the rest is meaningless"; nospk ;; esac
trial=$(tr -d '\0' < /proc/device-tree/chosen/aurora,trial 2>/dev/null)
info "Stage 2: ${trial:-the configured m1n1/boot-ctxr.bin}"
tc=/usr/local/lib/omarchy-k114s/audio/tree-check; [ -x "$tc" ] || tc=$here/linux/audio/tree-check
if out=$("$tc" 2>&1); then ok "device tree: $out"; else bad "device tree: ${out//$'\n'/; }"; fi
if [ -r /proc/config.gz ]; then
  conf=$(zcat /proc/config.gz)
  for o in BT BT_BREDR BT_RFCOMM BT_HIDP SND_JACK SND_SOC_CS42L84 SND_SOC_APPLE_MACAUDIO BT_HCICENTAURI; do
    v=$(grep -E "^CONFIG_$o=" <<<"$conf" | cut -d= -f2); [ -n "$v" ] && ok "CONFIG_$o=$v" || bad "CONFIG_$o is not set"
  done
else unk "no /proc/config.gz"; fi

echo "== 2. sound cards and modules"
cards=$(cat /proc/asound/cards 2>/dev/null)
if [ -z "$cards" ] || grep -q 'no soundcards' <<<"$cards"; then
  bad "no ALSA card. The jack needs the PMP, AOP and cs42l84 to probe; read the PMP and AOP lines first: sudo dmesg | grep -iE 'pmp|aop|cs42l84|macaudio|asoc'"
else
  grep -q 'AppleK114 ' <<<"$cards" && ok "card AppleK114 (the jack) is present" || bad "no card AppleK114; cards: $(sed -n 's/^ *[0-9]* \[\([^]]*\)\].*/\1/p' <<<"$cards" | tr -d ' ' | tr '\n' ' ')"
  grep -q 'AppleK114HPAI' <<<"$cards" && ok "card AppleK114HPAI (the microphones) is present" || info "no card AppleK114HPAI (the microphones; the -nomics tree has none)"
  grep -qiE 'speaker' /proc/asound/cards /proc/asound/pcm 2>/dev/null && { bad "something named speaker is in /proc/asound: run linux/audio/speaker-readiness.sh and do NOT play anything"; nospk; } || ok "nothing named speaker in /proc/asound"
fi
for m in snd_soc_cs42l84 snd_soc_macaudio snd_soc_apple_mca aop apple_pmp apple_admac i2c_pasemi_platform; do
  grep -q "^$m " /proc/modules && ok "module $m loaded" || info "module $m not loaded"
done
dm=$(dmesg 2>/dev/null)
if [ -z "$dm" ]; then unk "dmesg is root-only here; run: sudo dmesg | grep -iE 'cs42l84|macaudio|asoc|pmp|aop|rfcomm|bluetooth|hci0'"
else
  grep -iE 'cs42l84|macaudio|asoc|apple-pmp|apple_pmp|aop' <<<"$dm" | tail -12 | sed 's/^/info    dmesg: /'
  grep -iE 'Oops|BUG:|WARNING:|SError|Call trace' <<<"$dm" | head -5 | sed 's/^/BAD     dmesg: /'
fi
if grep -q cs42l84 /proc/interrupts 2>/dev/null; then
  a=$(irqs); sleep 5; b=$(irqs)
  # an idle codec is quiet; a stuck interrupt latch (as linux #1895 fixes on the J604) would be about 1000 per second
  [ $((b-a)) -lt 500 ] && ok "cs42l84 interrupts at idle: $((b-a)) in 5 s" || bad "cs42l84 interrupt storm at idle: $((b-a)) in 5 s (a latched status; see docs/r3-audio.md, cs42l84 init writes)"
else info "no cs42l84 line in /proc/interrupts yet"; fi

echo "== 3. jack and microphone in user space"
if have amixer && [ -e /proc/asound/AppleK114 ]; then
  info "jack controls: $(jack_state)"
  amixer -c AppleK114 contents 2>/dev/null | grep -qi 'jack' && ok "the card exposes a jack control" || bad "no jack control on AppleK114"
else unk "amixer or the card is missing"; fi
if have wpctl; then
  wpctl status 2>/dev/null | sed -n '/Audio/,/Video/p' | grep -iE "K114|Dummy|Headphone|Headset|bluez|Speaker" | names | sed 's/^/info    wpctl: /'
  wpctl status 2>/dev/null | grep -qi 'Dummy Output' && bad "WirePlumber has only a Dummy Output"
  wpctl status 2>/dev/null | grep -iE 'speaker' | grep -qi k114 && { bad "a K114 speaker node exists in WirePlumber: do not play anything"; nospk; }
else unk "wpctl not installed"; fi
for u in wireplumber pipewire pipewire-pulse; do info "user unit $u: $(systemctl --user is-active $u 2>/dev/null)"; done
if [ -x "$here/linux/audio/speaker-readiness.sh" ]; then
  while IFS= read -r l; do case $l in TRIPWIRE*) bad "readiness: $l (do not play anything; install-audio.sh puts the guard in)"; nospk ;; *) info "readiness: $l" ;; esac
  done < <(bash "$here/linux/audio/speaker-readiness.sh" 2>&1 | grep -E '^(TRIPWIRE|RESULT|unknown)')
fi

echo "== 4. Bluetooth"
[ -d /sys/class/bluetooth/hci0 ] && ok "hci0 present" || bad "no hci0"
drv=$(basename "$(readlink /sys/class/bluetooth/hci0/device/driver 2>/dev/null)" 2>/dev/null)
[ "$drv" = btcentauri_t6050 ] && ok "hci0 is bound to btcentauri_t6050" || bad "hci0 driver is ${drv:-none}, expected btcentauri_t6050"
grep -q "^btcentauri_t6050 " /proc/modules && ok "module btcentauri_t6050 loaded" || bad "module btcentauri_t6050 not loaded"
rfkill list bluetooth 2>/dev/null | grep -q 'blocked: yes' && bad "Bluetooth is blocked in rfkill" || ok "Bluetooth is not blocked in rfkill"
grep -q "^rfcomm " /proc/modules && ok "module rfcomm loaded" || info "rfcomm not loaded yet (bluetoothd's HFP socket autoloads it through the bt-proto-3 alias)"
if have bluetoothctl; then
  show=$(bluetoothctl show 2>/dev/null)
  grep -q 'Powered: yes' <<<"$show" && ok "controller powered" || bad "controller not powered"
  for pair in "0000110b:A2DP sink" "0000110a:A2DP source" "0000111e:Hands-Free (HFP)" "0000111f:Hands-Free gateway (HFP AG)" "00001108:Headset (HSP)" "0000110e:AVRCP"; do
    grep -qi "UUID:.*(${pair%%:*}" <<<"$show" && ok "bluez advertises ${pair#*:}" || info "bluez does not advertise ${pair#*:}"
  done
  info "paired devices: $(bluetoothctl devices Paired 2>/dev/null | wc -l)"
else unk "bluetoothctl not installed"; fi
if have journalctl; then
  j=$(journalctl -b -u bluetooth --no-pager 2>/dev/null | grep -iE 'rfcomm|Protocol not supported|Hands-Free|failed' | tail -5)
  if journalctl -b -u bluetooth --no-pager -n 1 >/dev/null 2>&1; then
    grep -qi 'RFCOMM server failed' <<<"$j" && bad "bluetoothd still reports an RFCOMM server failure: $j" || ok "no RFCOMM server failure in this boot's bluetoothd journal"
  else unk "bluetoothd journal is not readable (add yourself to systemd-journal, or run with sudo)"; fi
fi
if have pactl; then
  pactl list cards short 2>/dev/null | grep -i bluez | sed 's/^/info    bluez card: /'
  pactl list cards 2>/dev/null | awk '/^Card/ {c=0} /bluez/ {c=1} c && /a2dp|headset-head-unit|handsfree|Active Profile/' | sed 's/^[[:space:]]*/info    profile: /' | head -12
fi
iw=$(have iw && iw dev 2>/dev/null | awk '/Interface/ {print $2; exit}')
[ -n "$iw" ] && info "Wi-Fi link: $(iw dev "$iw" link 2>/dev/null | grep -E 'signal|tx bitrate|rx bitrate' | tr -s ' \t' ' ' | tr '\n' ';')"

echo "== 5. summary of the unattended part: $nbad BAD line(s)"
if [ $listen = 0 ]; then
  echo "Run again with --listen at the Mac, with headphones and a Bluetooth headset at hand."
  [ $nbad = 0 ] && exit 0 || exit 1
fi

[ $nospk = 1 ] && { echo "== stopping: a speaker-related BAD line or a non-r3a kernel is above; no attended step and no tone runs"; exit 1; }
echo "== 6. attended: headphone jack (owner-observed)"
before=$(jack_state); info "jack before: ${before:-no jack control}"
pause "Plug wired headphones into the 3.5 mm jack."
sleep 1; after=$(jack_state); info "jack after plug: ${after:-no jack control}"
[ "$after" != "$before" ] && ok "the jack control changed on plug" || bad "the jack control did not change on plug (or no control)"
have wpctl && wpctl status 2>/dev/null | sed -n '/Sinks/,/Sources/p' | grep -iE 'K114|Headphone|Headset' | names | sed 's/^/info    sink: /'
if [ $play = 1 ]; then
  # the sink is the one whose ALSA path is the jack card (node names are alsa_output.platform-sound.*, not K114)
  sink=$(pactl list sinks 2>/dev/null | awk '/^[[:space:]]*Name:/ {n=$2} /api.alsa.path = "hw:AppleK114,0"/ {print n; exit}')
  case $sink in *[Ss]peaker*) sink= ;; esac
  vol=$(pactl get-sink-volume "$sink" 2>/dev/null | grep -o '[0-9]*%' | sort -n -r | head -1 | tr -d %)   # loudest channel
  if [ -z "$sink" ]; then bad "no sink on hw:AppleK114,0 to play on; nothing played"
  elif [ -z "$vol" ] || [ "$vol" -gt 50 ]; then bad "the sink volume is ${vol:-unknown}%, above 50%: lower it yourself (wpctl set-volume @DEFAULT_AUDIO_SINK@ 30%), then run again; nothing played"
  else
    pause "Put the headphones ON, check the sink volume is low ($vol%). A 2 s tone plays on $sink only."
    vol=$(pactl get-sink-volume "$sink" 2>/dev/null | grep -o '[0-9]*%' | sort -n -r | head -1 | tr -d %)
    if [ -z "$vol" ] || [ "$vol" -gt 50 ]; then bad "the volume changed to ${vol:-unknown}% during the pause: above 50%, nothing played"
    else
    tone=$(mktemp --suffix=.wav); python3 -I -c '
import math,struct,sys,wave
w=wave.open(sys.argv[1],"wb"); w.setnchannels(2); w.setsampwidth(2); w.setframerate(48000)
w.writeframes(b"".join(struct.pack("<hh",int(3000*math.sin(2*math.pi*440*i/48000)),int(3000*math.sin(2*math.pi*440*i/48000))) for i in range(96000)))' "$tone"
    if have pw-play; then pw-play --target "$sink" "$tone"; else paplay --device="$sink" "$tone"; fi; rm -f "$tone"
    fi
  fi
else
  pause "Play any sound at LOW volume now (for example: wpctl set-volume @DEFAULT_AUDIO_SINK@ 30%, then play a file). Listen in the headphones."
fi
ask "Did you hear it in BOTH ears, and ONLY in the headphones (not from the loudspeakers)? Note it as owner-observed: yes or no."
pause "Unplug the headphones."
sleep 1; gone=$(jack_state); info "jack after unplug: ${gone:-no jack control}"
[ "$gone" = "$before" ] && ok "the jack control returned to its unplugged state" || bad "the jack control did not return after unplug"
if grep -q AppleK114HPAI /proc/asound/cards 2>/dev/null; then
  ask "Microphones: record a few seconds (pw-record --target <the K114 mic source> /tmp/mic.wav, then play it back). Is your voice clear, mono, and not distorted?"
fi

echo "== 7. attended: Bluetooth audio (owner-observed)"
if have bluetoothctl; then
  n=$(bluetoothctl devices Paired 2>/dev/null | wc -l)
  if [ "$n" = 0 ]; then
    pause "No device is paired. Put your headset in pairing mode, then in another terminal: bluetoothctl, then: scan on, pair <address>, trust <address>, connect <address>. This script never pairs."
  fi
  have pactl && pactl list cards short 2>/dev/null | grep -i bluez | sed 's/^/info    bluez card: /'
  pactl list cards 2>/dev/null | awk '/^Card/ {c=0} /bluez/ {c=1} c && /a2dp|headset-head-unit|handsfree|Active Profile/' | sed 's/^[[:space:]]*/info    profile: /' | head -12
  ask "Play music over Bluetooth (A2DP) for 60 s. Any dropouts, stutter or crackle? Does it get worse while Wi-Fi is busy (try a download)?"
  gw=$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}')
  if [ -n "$gw" ]; then
    pause "A 20 s ping to the router runs now while you listen for dropouts."
    ping -c 20 -i 1 "$gw" 2>&1 | tail -2 | sed 's/^/info    ping: /'
  fi
  ask "Hands-free: switch the headset's card profile to headset-head-unit yourself (pactl set-card-profile <card> headset-head-unit), call or record. Does the headset microphone work, and does the card list a headset-head-unit profile at all? (Needs rfcomm and bluetoothd: section 4 says whether the RFCOMM error is gone.)"
fi
echo "== done: $nbad BAD line(s). Answer the ASK lines in the issue (#37 jack, #41 and #59 Bluetooth) as owner-observed."
[ "$nbad" = 0 ]
