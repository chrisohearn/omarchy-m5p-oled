#!/bin/bash
# K114s (omarchy-m5p-oled): STAGE B (loudspeakers) readiness report. READ-ONLY and SILENT.
#
#     bash linux/audio/speaker-readiness.sh [--root DIR]
#
# It answers one question: is anything on this Mac, right now, able to put sound on the loudspeakers,
# and which of the proofs the loudspeakers need are still missing. It opens no sound device, writes
# nothing, starts nothing, needs no root, and plays nothing. The data it would need is this Mac's own
# speaker tuning, which is Apple's and never goes into git; this script only tests that it exists.
#
# Exit status: 0 = no way to the speakers exists (the expected state; blockers are listed),
#              3 = TRIPWIRE: something that could open a speaker path is present while a proof is still
#                  missing (a speaker-side profile or marker, a missing guard, a tree with a speaker path). Shut down, do not play anything, and tell the lead (install-audio.sh installs the guard and --undo keeps it).
#              2 = could not tell.
# The checks are the ones docs/r3-audio.md "Stage B" lists. Nothing here qualifies the speakers.
set -uo pipefail
ROOT=
while [[ $# -gt 0 ]]; do
  case "$1" in --root) ROOT=${2%/}; shift ;; --root=*) ROOT=${1#--root=} ;; *) echo "usage: speaker-readiness.sh [--root DIR]" >&2; exit 2 ;; esac
  shift
done
blockers=0; trips=0
say()  { printf '%s\n' "$*"; }
block(){ say "BLOCKED   $*"; blockers=$((blockers+1)); }
trip() { say "TRIPWIRE  $*"; trips=$((trips+1)); }
good() { say "ok        $*"; }

# --- what could open a path ----------------------------------------------------------------------------
k=$ROOT/usr/share/speakersafetyd/apple
if ls "$k"/k114*.conf >/dev/null 2>&1; then trip "a speakersafetyd profile named k114*.conf exists in $k (a sibling model's, such as the K114c, shares the name): it is the admission switch of speakersafetyd. The guard below keeps it from arming; do not create the marker for it"
else good "no speakersafetyd profile for this model (the switch that would admit the older daemon is off)"; fi

# the owner's marker, and the guard that makes it the only way in (install-audio.sh installs the guard)
marker=$ROOT/etc/omarchy-k114s/speaker-qualification
if [[ -e $marker ]]; then trip "the owner's speaker qualification marker exists ($marker) while proofs are missing"
else good "no speaker qualification marker (the speaker daemons stay skipped)"; fi
g='ConditionPathExists=/etc/omarchy-k114s/speaker-qualification'
# check DIR (the drop-in directory, no ROOT), UNIT-FILE: the guard drop-in exists when the unit does
chk() {
  [[ -e $ROOT$2 ]] || return 0
  grep -qs "$g" "$ROOT$1/99-k114s-speaker-guard.conf" ||
    trip "${2##*/} exists and has no K114s speaker guard (run install-audio.sh): a sibling model's profile could arm it"
}
for u in speakersafetyd speakerguardd speakerguardd-v2 speakerguardd-v2-provision speakerguardd-v2-selfcheck speakerguardd-v2-seat speakerguardd-v2-switchtest speakerguardd-v2-sleep aurora-speaker-upgrade; do
  chk /etc/systemd/system/$u.service.d /usr/lib/systemd/system/$u.service
done
chk /etc/systemd/system/speakerguardd-v2-seat.path.d /usr/lib/systemd/system/speakerguardd-v2-seat.path
for u in speakerguardd-v2-graph speakerguardd-v2-session; do
  chk /etc/systemd/user/$u.service.d /usr/lib/systemd/user/$u.service
done
# On the real system the merged unit as systemd would load it (read-only; starts nothing): the condition
# is in `systemctl cat`, and, with the marker absent, systemd evaluates it false.
if [[ -z $ROOT ]] && command -v systemctl >/dev/null; then
  for u in speakersafetyd speakerguardd-v2 aurora-speaker-upgrade; do
    [[ -e /usr/lib/systemd/system/$u.service ]] || continue
    if systemctl cat "$u.service" 2>/dev/null | grep -q "^$g\$"; then good "systemctl cat $u: the merged unit carries the guard"
    else trip "systemctl cat $u: the merged unit does not carry the guard (a daemon-reload may be missing)"; fi
  done
  if command -v systemd-analyze >/dev/null && [[ ! -e $marker ]]; then
    if systemd-analyze condition "$g" >/dev/null 2>&1; then trip "systemd evaluates the guard condition true while the marker is absent"
    else good "systemd evaluates the guard condition false (units are skipped)"; fi
  fi
fi

# the tree that booted: the Stage A card, or no sound node (the same check WirePlumber runs before it starts)
tc=$(dirname -- "${BASH_SOURCE[0]}")/tree-check
if out=$("$tc" --root "$ROOT" 2>&1); then good "device tree: $out"; else trip "device tree: ${out//$'\n'/; }"; fi

if [[ -r $ROOT/proc/asound/cards ]]; then
  cards=$(sed -n 's/^ *[0-9]* \[\([A-Za-z0-9_]*\) *\].*/\1/p' "$ROOT/proc/asound/cards" | tr '\n' ' ')
  good "sound cards present: ${cards:-none}"
  for c in "$ROOT"/proc/asound/card*; do
    [[ -e $c/id ]] || continue
    id=$(<"$c/id")
    if [[ $id == AppleK114 ]]; then
      if grep -qi 'speaker' "$c"/codec#* 2>/dev/null; then trip "card $id exposes a speaker codec file"; fi
    fi
  done
else
  good "no ALSA cards yet (/proc/asound absent): this tree has no sound"
fi

# --- the proofs ----------------------------------------------------------------------------------------
bundle=$ROOT/lib/firmware/vendor/apple/audio-tuning
if [[ -d $bundle ]] && [[ -n $(ls -A "$bundle" 2>/dev/null) ]]; then good "a speaker tuning bundle is present on this Mac (contents not read here)"
else block "no speaker tuning bundle on this Mac ($bundle): collect it with aurora-speaker-upgrade, see docs/r3-audio.md, Stage B route 1"; fi

gj=$ROOT/usr/share/speakerguardd/gate.json
if [[ -r $gj ]] && command -v python3 >/dev/null; then
  par=$(python3 -I -c 'import json,sys;print(" ".join(json.load(open(sys.argv[1])).get("units_at_parity",[])))' "$gj" 2>/dev/null)
  say "info      protection types the installed gate accepts: ${par:-unknown}"
  if [[ " $par " == *" lsid "* ]]; then good "the gate accepts the lsid protection type"
  else block "the gate does not accept the lsid protection type, which upstream says this model's tuning carries (K114, acoustic id 49): upstream has not qualified it"; fi
else
  say "unknown   could not read $gj"
fi

pj=$ROOT/usr/share/speakerguardd/parity.json
if [[ -r $pj ]]; then
  if grep -q '"27\.' "$pj"; then good "parity.json names a macOS 27 build"
  else block "parity.json has no voicing attestation for a macOS 27 build; this Mac's firmware reports macOS 27.x"; fi
fi

if command -v wiring.py >/dev/null || [[ -x $ROOT/usr/lib/speakerguardd-v2/speakerguardd-gate ]]; then
  g=$ROOT/usr/lib/speakerguardd-v2/speakerguardd-gate
  out=$("$g" explain --wait 0 --setting /nonexistent 2>&1)
  say "info      installed gate says: ${out//$'\n'/ | }"
  case $out in *"v2=1"*) trip "the installed speakerguardd gate admits v2 on this Mac" ;; *) good "the installed gate does not admit v2" ;; esac
else
  say "unknown   speakerguardd gate not installed"
fi

block "no qualification of this model: no measured or derived protection data for the chassis (docs/r3-audio-protection.md)"
block "nobody has heard it: nothing works until the owner hears it on this Mac"

say "---"
if (( trips > 0 )); then say "RESULT: TRIPWIRE ($trips). Something could open a speaker path before protection exists."; exit 3; fi
say "RESULT: no path to the loudspeakers exists; Stage B is blocked on $blockers item(s). Nothing was opened, written or played."
exit 0
