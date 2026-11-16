#!/bin/bash
# K114s screen-capture check (issue #32), to run on the Mac in the live desktop session, and again after
# every change of the display/GPU topology (display-coprocessor hand-off, docs/r3-display-gpu.md).
# Bounded: every step has a timeout (-k 5), captures go to a mktemp directory that is deleted on exit, and
# no system or hardware state is changed. The captures show the screen: they are read for size and format
# only, then deleted; never attach them anywhere.
#
#   k114s-capture-check.sh            grim shot; 5 s wf-recorder clip on the default path; the same with --no-dmabuf
#   k114s-capture-check.sh --script   also run omarchy-capture-screenrecording for 4 s (it records the whole screen;
#                                     --fullscreen skips the region picker) and read the file it wrote
#
# Prints the DRM topology (card and render nodes with their drivers) so runs before and after a topology
# change can be compared. Exit status: 0 no FAIL, 1 at least one FAIL or a missing grim/wf-recorder/ffprobe (the
# core checks did not run). SKIP means a tool is missing or the step was not safe to run.
# CAPTURE_CHECK_ROOT prefixes the file paths read (tests/hardware/test-capture-check.sh sets it).
set -u
root=${CAPTURE_CHECK_ROOT:-}
script=0
for a in "$@"; do
  case $a in --script) script=1 ;; *) sed -n '2,14p' "$0"; exit 2 ;; esac
done
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
fail=0
pass() { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=1; }
skip() { echo "SKIP $1"; }
need() { echo "SKIP $1"; fail=1; } # a skipped core check is not a pass
have() { command -v "$1" >/dev/null 2>&1; }
probe() { ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height -of csv=p=0 "$1" 2>&1 | head -1; }

echo "== DRM topology"
for n in "$root"/sys/class/drm/card[0-9] "$root"/sys/class/drm/renderD*; do
  [[ -e $n ]] || continue
  echo "INFO ${n##*/}: driver $(basename "$(readlink -f "$n/device/driver" 2>/dev/null)")"
done

echo "== Backend selection (source read)"
f=$(command -v omarchy-capture-screenrecording) || f=$root/usr/bin/omarchy-capture-screenrecording
if [[ -r $f ]] && grep -q 'for backend in gpu-screen-recorder wf-recorder' "$f"; then
  pass "omarchy-capture-screenrecording tries gpu-screen-recorder, then wf-recorder"
else skip "omarchy-capture-screenrecording not readable or changed: backend order not confirmed"; fi
if have gpu-screen-recorder; then
  opts=$(timeout -k 5 20 gpu-screen-recorder --list-capture-options 2>/dev/null </dev/null)
  [[ $opts == "portal" ]] && pass "gpu-screen-recorder lists only the portal target (no display device)" ||
    echo "INFO gpu-screen-recorder capture options: $(echo "$opts" | tr '\n' ' ')"
fi

echo "== grim"
if have grim; then
  timeout -k 5 20 grim "$tmp/s.png" && [[ $(file -b "$tmp/s.png") == "PNG image data"* ]] &&
    pass "grim: $(file -b "$tmp/s.png" | cut -d, -f1,2)" || bad "grim produced no PNG"
else need "grim missing"; fi

echo "== wf-recorder"
if have wf-recorder && have ffprobe; then
  for mode in default no-dmabuf; do
    extra=(); [[ $mode == no-dmabuf ]] && extra=(--no-dmabuf)
    # -o and no stdin: with an external monitor wf-recorder would otherwise ask which output and wait.
    have omarchy-hyprland-monitor-focused && extra+=(-o "$(omarchy-hyprland-monitor-focused)")
    timeout -s INT -k 5 5 wf-recorder "${extra[@]}" -f "$tmp/$mode.mkv" -y >/dev/null 2>"$tmp/$mode.err" </dev/null
    info=$(probe "$tmp/$mode.mkv")
    [[ $info == h264,* ]] && pass "wf-recorder $mode, 5 s: $info" ||
      bad "wf-recorder $mode: unreadable clip ($info); stderr: $(head -c 200 "$tmp/$mode.err" | tr '\n' ' ')"
  done
else need "wf-recorder or ffprobe missing"; fi

if [[ $script -eq 1 ]]; then
  echo "== omarchy-capture-screenrecording"
  if ! have omarchy-capture-screenrecording || ! have ffprobe; then
    skip "omarchy-capture-screenrecording or ffprobe missing"
  elif omarchy-capture-screenrecording --status >/dev/null 2>&1; then
    skip "a recording is already running: the script is a toggle, so it would stop yours; stop it and rerun"
  else
    export OMARCHY_SCREENRECORD_DIR=$tmp/vid; mkdir -p "$OMARCHY_SCREENRECORD_DIR"
    timeout -k 5 20 omarchy-capture-screenrecording --fullscreen >/dev/null 2>&1; sleep 4
    pgrep -x wf-recorder >/dev/null && ! pidof gpu-screen-recorder >/dev/null 2>&1 && be=1 || be=0
    timeout -k 5 20 omarchy-capture-screenrecording --stop-recording >/dev/null 2>&1; sleep 3
    [[ $be -eq 1 ]] && pass "script recorded with wf-recorder, not gpu-screen-recorder" || bad "script did not record with wf-recorder alone"
    v=$(ls "$OMARCHY_SCREENRECORD_DIR"/* 2>/dev/null | head -1)
    info=$([[ -n $v ]] && probe "$v")
    [[ $info == h264,* ]] && pass "script wrote a readable clip: $info" || bad "script wrote no readable h264 clip ($info)"
  fi
fi
exit $fail
