#!/bin/bash
# K114s (omarchy-m5p-oled): install the sound configuration for the headphone jack and the
# microphones. Nothing here is for the loudspeakers.
#
#     sudo bash linux/audio/install-audio.sh                      install
#     sudo bash linux/audio/install-audio.sh --with-beamformer    install, and make the beamformed
#                                                                 microphone graph the one in use
#     sudo bash linux/audio/install-audio.sh --undo               remove what it installed, restore what it replaced
#     bash linux/audio/install-audio.sh --check                   say what is installed, change nothing
#     --root DIR (or K114S_ROOT=DIR) works on a directory tree instead of /: for tests. With a root the
#     script needs no root rights (it still checks the device tree named by K114S_DT_COMPATIBLE, default
#     the running Mac's) and neither reloads systemd nor touches any service. Switching between the plain
#     and the beamformed graph is a re-run with or without --with-beamformer.
#
# What it installs (every file is new; an existing file of the same name is kept as *.k114s-orig):
#   1. ALSA UCM profiles for the two cards the kernel creates:
#        /usr/share/alsa/ucm2/conf.d/macaudio/MacBook Pro K114.conf                              (jack)
#        /usr/share/alsa/ucm2/conf.d/aop_audio/MacBook Pro K114 High-Power Audio Interface.conf  (microphones)
#        /usr/share/alsa/ucm2/conf.d/aop_audio/k114/HiFi.conf
#   2. WirePlumber rules and the microphone's mono filter graph:
#        /etc/wireplumber/wireplumber.conf.d/82-k114-audio.conf
#        /usr/local/share/omarchy-k114s/audio/mic.json
#   3. a second condition on the five speakerguardd v2 units, so they stay skipped while the card
#      has no speaker link (otherwise each waits 15 s at boot before refusing):
#        /etc/systemd/system/speakerguardd-v2{,-provision,-selfcheck,-seat,-switchtest}.service.d/91-k114s-no-speaker-link.conf
# It installs no package, changes no boot file, starts or stops no service and does not reboot.
# The UCM files sit in a directory owned by alsa-ucm-conf-aurora under names that package does not
# have; if a later package ships a "MacBook Pro K114" profile, pacman will report a file conflict:
# run --undo first, then update.
set -euo pipefail
ROOT=${K114S_ROOT:-}
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STATE=$ROOT/usr/local/lib/omarchy-k114s/audio
UNITS="speakerguardd-v2 speakerguardd-v2-provision speakerguardd-v2-selfcheck speakerguardd-v2-seat speakerguardd-v2-switchtest"
die() { echo "install-audio: $*" >&2; exit 1; }
say() { echo "install-audio: $*"; }

# source (relative to this folder) -> destination, one pair per line
pairs() {
  local MICSRC=share/mic.json; [[ $beam == 1 ]] && MICSRC=share/mic-beamformer.json
  cat <<EOF
ucm2/macaudio-k114.conf|/usr/share/alsa/ucm2/conf.d/macaudio/MacBook Pro K114.conf
ucm2/aop_audio-k114-hpai.conf|/usr/share/alsa/ucm2/conf.d/aop_audio/MacBook Pro K114 High-Power Audio Interface.conf
ucm2/aop_audio-k114-HiFi.conf|/usr/share/alsa/ucm2/conf.d/aop_audio/k114/HiFi.conf
wireplumber/82-k114-audio.conf|/etc/wireplumber/wireplumber.conf.d/82-k114-audio.conf
$MICSRC|/usr/local/share/omarchy-k114s/audio/mic.json
EOF
  for u in $UNITS; do
    echo "systemd/91-k114s-no-speaker-link.conf|/etc/systemd/system/$u.service.d/91-k114s-no-speaker-link.conf"
  done
}

mode=install; beam=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --undo|--check) mode=$1 ;;
    --with-beamformer) beam=1 ;;
    --root) [[ $# -ge 2 ]] || die "--root needs a directory"; ROOT=${2%/}; shift ;;
    --root=*) ROOT=${1#--root=}; ROOT=${ROOT%/} ;;
    *) die "usage: install-audio.sh [--undo|--check] [--with-beamformer] [--root DIR]" ;;
  esac
  shift
done
if [[ -n $ROOT ]]; then STATE=$ROOT/usr/local/lib/omarchy-k114s/audio; fi

if [[ $mode == --check ]]; then
  rc=0
  while IFS='|' read -r src dst; do
    if [[ -f $ROOT$dst ]] && cmp -s "$HERE/$src" "$ROOT$dst"; then say "installed: $dst"
    elif [[ -e $ROOT$dst ]]; then say "DIFFERENT: $dst"; rc=1
    else say "missing: $dst"; rc=1; fi
  done < <(pairs)
  exit $rc
fi

[[ $(id -u) == 0 || -n $ROOT ]] || die "run with sudo"
compatible=${K114S_DT_COMPATIBLE:-/sys/firmware/devicetree/base/compatible}
grep -zFxq 'apple,k114s' "$compatible" || die "this is not an apple,k114s Mac"

if [[ $mode == --undo ]]; then
  while IFS='|' read -r src dst; do
    if [[ -e $ROOT$dst.k114s-orig ]]; then mv -f "$ROOT$dst.k114s-orig" "$ROOT$dst"; say "restored $dst"
    elif [[ -f $ROOT$dst ]]; then rm -f "$ROOT$dst"; say "removed $dst"; fi
  done < <(pairs)
  rmdir "$ROOT/usr/share/alsa/ucm2/conf.d/aop_audio/k114" "$ROOT/usr/local/share/omarchy-k114s/audio" 2>/dev/null || true
  rm -f "$STATE/installed"; rmdir "$STATE" 2>/dev/null || true
else
  # the verb the jack profile includes comes from alsa-ucm-conf-aurora
  [[ -f $ROOT/usr/share/alsa/ucm2/conf.d/macaudio/cs42l84/HiFi-jack.conf ]] ||
    die "/usr/share/alsa/ucm2/conf.d/macaudio/cs42l84/HiFi-jack.conf is missing (alsa-ucm-conf-aurora): nothing installed"
  while IFS='|' read -r src dst; do [[ -f $HERE/$src ]] || die "missing beside this script: $src"; done < <(pairs)
  while IFS='|' read -r src dst; do
    if [[ -f $ROOT$dst ]] && cmp -s "$HERE/$src" "$ROOT$dst"; then continue; fi
    if [[ -e $ROOT$dst && ! -e $ROOT$dst.k114s-orig && ! -e $STATE/installed ]]; then mv "$ROOT$dst" "$ROOT$dst.k114s-orig"; say "kept the existing $dst as $dst.k114s-orig"; fi
    install -D -m 0644 "$HERE/$src" "$ROOT$dst"
    say "installed $dst"
  done < <(pairs)
  mkdir -p "$STATE"; date -u +%Y-%m-%dT%H:%M:%SZ > "$STATE/installed"
fi

if [[ -z $ROOT ]]; then
  systemctl daemon-reload
  say "systemd reloaded. The sound cards themselves need the r3 kernel and device tree: after that boot,"
  say "log out and in again (or: systemctl --user restart wireplumber pipewire pipewire-pulse) to pick up the rules."
fi
