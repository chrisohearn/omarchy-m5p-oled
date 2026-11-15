#!/bin/bash
# K114s (omarchy-m5p-oled): install the sound configuration for the headphone jack and the
# microphones. Nothing here is for the loudspeakers.
#
#     sudo bash linux/audio/install-audio.sh                      install
#     sudo bash linux/audio/install-audio.sh --with-beamformer    install, and make the beamformed
#                                                                 microphone graph the one in use
#     sudo bash linux/audio/install-audio.sh --undo               remove the jack and microphone files, restore what they replaced;
#                                                                 the speaker guard and the tree check STAY
#     sudo bash linux/audio/install-audio.sh --remove-guard       remove the guard and the tree check too; refused while the
#                                                                 owner's /etc/omarchy-k114s/speaker-qualification does not exist
#     bash linux/audio/install-audio.sh --check                   say what is installed, change nothing
#     --root DIR (or K114S_ROOT=DIR) works on a directory tree instead of /: for tests. With a root the
#     script needs no root rights (it still checks the device tree named by K114S_DT_COMPATIBLE, default
#     the running Mac's) and neither reloads systemd nor touches any service. Switching between the plain
#     and the beamformed graph is a re-run with or without --with-beamformer.
#
# What it installs (every file is new; an existing file of the same name is kept as *.k114s-orig).
# The guard (3 and 4) is installed on every run, first, even when the run then refuses; --undo keeps it.
#   1. ALSA UCM profiles for the two cards the kernel creates:
#        /usr/share/alsa/ucm2/conf.d/macaudio/MacBook Pro K114.conf                              (jack)
#        /usr/share/alsa/ucm2/conf.d/aop_audio/MacBook Pro K114 High-Power Audio Interface.conf  (microphones)
#        /usr/share/alsa/ucm2/conf.d/aop_audio/k114/HiFi.conf
#   2. WirePlumber rules and the microphone's mono filter graph:
#        /etc/wireplumber/wireplumber.conf.d/82-k114-audio.conf
#        /usr/local/share/omarchy-k114s/audio/mic.json
#   3. the speaker guard: a condition on every unit that could act on the loudspeakers' protection
#      (speakersafetyd, speakerguardd, the speakerguardd-v2 units and their two user units, the seat path,
#      aurora-speaker-upgrade), which skips
#      them unless the owner has created /etc/omarchy-k114s/speaker-qualification by hand (nothing here
#      creates or removes it). It keeps a sibling model's profile, such as a K114c k114.conf from a
#      package update, from arming a daemon on this Mac; it also removes the 15 s waits at boot:
#        /etc/systemd/system/<unit>.service.d/99-k114s-speaker-guard.conf   (and the seat .path.d)
#        /etc/systemd/user/<unit>.service.d/99-k114s-speaker-guard.conf
#   4. a check of the booted device tree, run before every WirePlumber start (the only thing that opens
#      the cards for a user): a tree with a speaker path keeps WirePlumber from starting:
#        /usr/local/lib/omarchy-k114s/audio/tree-check
#        /etc/systemd/user/wireplumber.service.d/99-k114s-stage-a-tree.conf
#      The installer refuses to install 1 and 2 (but still installs 3 and 4) while the tree that is running
#      has a sound node that is not the Stage A card or an amplifier or speaker DMA channel, and while
#      /usr/local/lib/omarchy-k114s/use-packaged-dtb exists (packaged trees of other models have speaker
#      paths).
# It installs no package, changes no boot file, starts or stops no service and does not reboot. --undo
# keeps 3 and 4 on purpose: the update that brings a K114c profile is the one that needs them.
# The UCM files sit in a directory owned by alsa-ucm-conf-aurora under names that package does not
# have; if a later package ships a "MacBook Pro K114" profile, pacman will report a file conflict:
# run --undo (the guard stays), then update, then install again if the new profile is not wanted.
set -euo pipefail
ROOT=${K114S_ROOT:-}
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STATE=$ROOT/usr/local/lib/omarchy-k114s/audio
UNITS="speakersafetyd speakerguardd speakerguardd-v2 speakerguardd-v2-provision speakerguardd-v2-selfcheck speakerguardd-v2-seat speakerguardd-v2-switchtest speakerguardd-v2-sleep aurora-speaker-upgrade"
USERUNITS="speakerguardd-v2-graph speakerguardd-v2-session"
die() { echo "install-audio: $*" >&2; exit 1; }
say() { echo "install-audio: $*"; }

# source (relative to this folder)|destination|mode, one per line. Two lists: the guard (kept by --undo)
# and the jack and microphone files.
guard_pairs() {
  cat <<EOF
tree-check|/usr/local/lib/omarchy-k114s/audio/tree-check|0755
systemd/99-k114s-stage-a-tree.conf|/etc/systemd/user/wireplumber.service.d/99-k114s-stage-a-tree.conf|0644
systemd/99-k114s-speaker-guard.conf|/etc/systemd/system/speakerguardd-v2-seat.path.d/99-k114s-speaker-guard.conf|0644
EOF
  for u in $UNITS; do
    echo "systemd/99-k114s-speaker-guard.conf|/etc/systemd/system/$u.service.d/99-k114s-speaker-guard.conf|0644"
  done
  for u in $USERUNITS; do
    echo "systemd/99-k114s-speaker-guard.conf|/etc/systemd/user/$u.service.d/99-k114s-speaker-guard.conf|0644"
  done
}
pairs() {
  local MICSRC=share/mic.json; [[ $beam == 1 ]] && MICSRC=share/mic-beamformer.json
  cat <<EOF
ucm2/macaudio-k114.conf|/usr/share/alsa/ucm2/conf.d/macaudio/MacBook Pro K114.conf|0644
ucm2/aop_audio-k114-hpai.conf|/usr/share/alsa/ucm2/conf.d/aop_audio/MacBook Pro K114 High-Power Audio Interface.conf|0644
ucm2/aop_audio-k114-HiFi.conf|/usr/share/alsa/ucm2/conf.d/aop_audio/k114/HiFi.conf|0644
wireplumber/82-k114-audio.conf|/etc/wireplumber/wireplumber.conf.d/82-k114-audio.conf|0644
$MICSRC|/usr/local/share/omarchy-k114s/audio/mic.json|0644
EOF
}

mode=install; beam=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --undo|--check|--remove-guard) mode=$1 ;;
    --with-beamformer) beam=1 ;;
    --root) [[ $# -ge 2 ]] || die "--root needs a directory"; ROOT=${2%/}; shift ;;
    --root=*) ROOT=${1#--root=}; ROOT=${ROOT%/} ;;
    *) die "usage: install-audio.sh [--undo|--remove-guard|--check] [--with-beamformer] [--root DIR]" ;;
  esac
  shift
done
if [[ -n $ROOT ]]; then STATE=$ROOT/usr/local/lib/omarchy-k114s/audio; fi

# a --check without the flag compares against the graph that was installed
[[ $mode == --check && $beam == 0 ]] && grep -qx 'beamformer=1' "$STATE/installed" 2>/dev/null && beam=1
if [[ $mode == --check ]]; then
  rc=0
  while IFS='|' read -r src dst fmode; do
    if [[ -f $ROOT$dst ]] && cmp -s "$HERE/$src" "$ROOT$dst"; then say "installed: $dst"
    elif [[ -e $ROOT$dst ]]; then say "DIFFERENT: $dst"; rc=1
    else say "missing: $dst"; rc=1; fi
  done < <(guard_pairs; pairs)
  [[ -e $ROOT/etc/omarchy-k114s/speaker-qualification ]] && say "NOTE: the owner's speaker qualification marker exists"
  exit $rc
fi

[[ $(id -u) == 0 || -n $ROOT ]] || die "run with sudo"
compatible=${K114S_DT_COMPATIBLE:-/sys/firmware/devicetree/base/compatible}
grep -zFxq 'apple,k114s' "$compatible" || die "this is not an apple,k114s Mac"

# make DIR and every missing parent; each directory made is recorded (outermost first) in $STATE/dirs, so
# that --undo and --remove-guard remove exactly those
mkdirs() {
  local d=$1 new=() x
  while [[ -n $d && ! -d $d ]]; do new=("$d" "${new[@]}"); d=${d%/*}; done
  for x in "${new[@]}"; do mkdir "$x"; echo "$x" >> "$STATE/dirs"; done
}
# remove the files of one list (stdin), restoring *.k114s-orig
remove_pairs() {
  while IFS='|' read -r src dst fmode; do
    if [[ -e $ROOT$dst.k114s-orig ]]; then mv -f "$ROOT$dst.k114s-orig" "$ROOT$dst"; say "restored $dst"
    elif [[ -f $ROOT$dst ]]; then rm -f "$ROOT$dst"; say "removed $dst"; fi
  done
}
# put the files of one list (stdin) in place
put_pairs() {
  while IFS='|' read -r src dst fmode; do
    if [[ -f $ROOT$dst ]] && cmp -s "$HERE/$src" "$ROOT$dst"; then continue; fi
    if [[ -e $ROOT$dst && ! -e $ROOT$dst.k114s-orig && $fresh == 1 ]]; then mv "$ROOT$dst" "$ROOT$dst.k114s-orig"; say "kept the existing $dst as $dst.k114s-orig"; fi
    mkdirs "$(dirname "$ROOT$dst")"
    install -m "$fmode" "$HERE/$src" "$ROOT$dst"
    say "installed $dst"
  done
}
# remove the recorded directories that are empty now, innermost first; one that is not empty is someone
# else's now and stays (and stays recorded)
prune_dirs() {
  [[ -f $STATE/dirs ]] || return 0
  local d keep=() made
  mapfile -t made < <(tac "$STATE/dirs"); rm -f "$STATE/dirs"   # the list lives in the last of the directories
  for d in "${made[@]}"; do rmdir "$d" 2>/dev/null || keep=("$d" "${keep[@]}"); done
  if (( ${#keep[@]} )) && [[ -d $STATE ]]; then printf '%s\n' "${keep[@]}" > "$STATE/dirs"; fi
}
reload() {
  [[ -z $ROOT ]] || return 0
  systemctl daemon-reload
  say "systemd reloaded. Check the guard: systemctl cat speakersafetyd | grep ConditionPathExists"
}

if [[ $mode == --remove-guard ]]; then
  [[ -e $ROOT/etc/omarchy-k114s/speaker-qualification ]] ||
    die "refused: the owner's /etc/omarchy-k114s/speaker-qualification does not exist, so the guard stays (create that file only when docs/r3-audio.md Stage B has every proof)"
  guard_pairs | remove_pairs
  prune_dirs
elif [[ $mode == --undo ]]; then
  pairs | remove_pairs
  rm -f "$STATE/installed"
  prune_dirs
  say "the speaker guard and the tree check stay (install-audio.sh --remove-guard removes them, once the owner has qualified the speakers)"
else
  # the guard first, always: it needs no sound card and no tree, and it is what keeps a sibling model's
  # speaker profile from arming a daemon, so no refusal below may skip it
  while IFS='|' read -r src dst fmode; do [[ -f $HERE/$src ]] || die "missing beside this script: $src"; done < <(guard_pairs; pairs)
  fresh=0; [[ -e $STATE/installed ]] || fresh=1
  d=$STATE; new=(); while [[ ! -d $d ]]; do new=("$d" "${new[@]}"); d=${d%/*}; done
  mkdir -p "$STATE"; for x in "${new[@]}"; do echo "$x" >> "$STATE/dirs"; done
  guard_pairs | put_pairs
  # no sound tree with a speaker path, and no packaged tree of a sibling model: then no UCM, WirePlumber or microphone files
  refuse=
  if [[ -e $ROOT/usr/local/lib/omarchy-k114s/use-packaged-dtb ]]; then
    refuse="use-packaged-dtb is set: the packaged device tree of another model may have a speaker path"
  elif ! out=$("$HERE/tree-check" --root "$ROOT"); then
    refuse="the running device tree is not the Stage A tree (${out//$'\n'/; })"
  # the verb the jack profile includes comes from alsa-ucm-conf-aurora
  elif [[ ! -f $ROOT/usr/share/alsa/ucm2/conf.d/macaudio/cs42l84/HiFi-jack.conf ]]; then
    refuse="/usr/share/alsa/ucm2/conf.d/macaudio/cs42l84/HiFi-jack.conf is missing (alsa-ucm-conf-aurora)"
  fi
  if [[ -n $refuse ]]; then
    reload
    die "$refuse. The speaker guard is installed; the jack and microphone files are not"
  fi
  pairs | put_pairs
  { date -u +%Y-%m-%dT%H:%M:%SZ; echo "beamformer=$beam"; } > "$STATE/installed"
fi

reload
if [[ -z $ROOT && $mode == install ]]; then
  say "The sound cards themselves need the r3 kernel and device tree: after that boot,"
  say "log out and in again (or: systemctl --user daemon-reload; systemctl --user restart wireplumber pipewire pipewire-pulse)."
fi
