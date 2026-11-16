#!/bin/bash
# OWNER-RUN, ATTENDED. After a boot with the sound tree (card AppleK114HPAI), records the three raw
# microphones and the mono source in four short takes and analyses every channel (issue #38).
# Records only: no playback, no setting is changed, no root needed. Nothing goes to any speaker.
#
#   bash tests/hardware/k114s-mic-trial.sh [--secs N] [--dir DIR]
# Takes: 1 quiet room, 2 talk (counting aloud), 3 clap near the left edge, 4 clap near the right edge.
# Reads: which raw channel is loudest for each clap (a hint for the array layout), per-channel level,
# silence, clipping, correlation. Prints a block to paste into the issue; no names or addresses in it.
secs=5; dir=
while [ $# -gt 0 ]; do case $1 in
  --secs) secs=${2:-}; shift 2 ;; --dir) dir=${2:-}; shift 2 ;;
  *) echo "usage: k114s-mic-trial.sh [--secs N] [--dir DIR]" >&2; exit 2 ;; esac; done
case $secs in ''|*[!0-9]*) echo "--secs needs a number" >&2; exit 2 ;; esac
here=$(cd "$(dirname "$0")" && pwd); A=$here/k114s-mic-analyze.py
for t in pw-record wpctl python3; do command -v $t >/dev/null || { echo "missing: $t" >&2; exit 2; }; done
[ -d /proc/asound/AppleK114HPAI ] || { echo "BAD     no card AppleK114HPAI: this boot has no microphone card (wrong tree?)"; exit 1; }
[ -n "$dir" ] || dir=$(mktemp -d "${TMPDIR:-/tmp}/k114s-mic.XXXXXX"); mkdir -p "$dir"
raw=alsa_input.platform-sound.RawMics; mono=effect_output.k114-mic
wpctl status 2>/dev/null | grep -q -E 'MacBook Microphone|k114' && echo "info    mono source present" || echo "info    mono source not listed in wpctl status (the raw takes still work)"
take() { # name target channels prompt [silent-dbfs]
  printf '\n>>> %s\n    Recording %ss starts when you press Enter.\n' "$4" "$secs" >/dev/tty; read -r _ </dev/tty
  timeout "$secs" pw-record --target "$2" --rate 48000 --channels "$3" --format f32 "$dir/$1.wav" 2>"$dir/$1.err"
  [ -s "$dir/$1.wav" ] || { echo "BAD     $1: nothing recorded (target $2): $(head -c 200 "$dir/$1.err")"; return 1; }
  echo "== $1 ($2, $3 ch)"; python3 -I "$A" "$dir/$1.wav" --expect-channels "$3" --silent-dbfs "${5:--70}"
}
fail=0
take quiet   $raw  3 "Stay silent (a quiet room is not a silent channel, so no silence test here)." -200 || fail=1
take talk    $raw  3 "Count aloud at normal level, 30 cm from the screen." || fail=1
take clapL   $raw  3 "Clap sharply, about once a second, near the LEFT edge of the keyboard." || fail=1
take clapR   $raw  3 "Clap sharply, about once a second, near the RIGHT edge of the keyboard." || fail=1
take mono    $mono 1 "Count aloud again; this is the mono source (what apps use)." || fail=1
echo; echo "== summary: recordings are in $dir (delete them when done; they contain your voice)"
[ $fail = 0 ] && echo "ok      all takes recorded" || echo "BAD     at least one take failed"
echo "ASK     Play the mono take through HEADPHONES only (pw-play --volume 0.3 $dir/mono.wav): intelligible? level ok? noise?"
exit $fail
