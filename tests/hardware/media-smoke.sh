#!/bin/bash
# K114s media smoke test for the owner to run on the Mac. Bounded: every GPU or capture step has a
# timeout (-k 5, so a client stuck in the kernel is killed), captures and caches go to a mktemp
# directory that is deleted on exit, and no system or hardware state is changed and nothing is
# installed. Chromium may still touch ~/.pki/nssdb. See docs/matrix.md rows "GPU", "Screen capture", "Chromium/Electron" and
# "Widevine", and issues #26 #27 #28 #31 #32.
#
#   media-smoke.sh              static checks, vulkaninfo --summary, one grim shot, one 3 s wf-recorder clip
#   media-smoke.sh --no-capture skip the grim and wf-recorder steps (they read the live screen)
#   media-smoke.sh --vkcube     also run vkcube for 10 s: LOOK AT THE PANEL, a spinning cube means pass
#   (Chromium GPU status: run tests/hardware/chromium-gpu-report.sh; --dump-dom cannot read chrome://gpu)
#
# The screenshot and the clip are looked at only for size and format, then deleted; they show the
# screen, so never attach them anywhere. Output holds no serial numbers, addresses or home paths.
# Exit status: 0 no FAIL, 1 at least one FAIL. SKIP means a tool is missing, which is not a pass.
# MEDIA_SMOKE_ROOT prefixes the file paths read (tests/hardware/test-media-smoke.sh sets it).
set -u
root=${MEDIA_SMOKE_ROOT:-}
capture=1 vkcube=0
for a in "$@"; do
  case $a in
    --no-capture) capture=0 ;; --vkcube) vkcube=1 ;;
    *) sed -n '2,18p' "$0"; exit 2 ;;
  esac
done
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
export XDG_CACHE_HOME=$tmp/cache MESA_SHADER_CACHE_DIR=$tmp/cache
fail=0
pass() { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=1; }
skip() { echo "SKIP $1"; }
have() { command -v "$1" >/dev/null 2>&1; }

echo "== Vulkan (#26)"
icd=$root/usr/share/vulkan/icd.d/asahi_icd.aarch64.json
[[ -f $icd ]] && pass "ICD file present: ${icd##*/}" || bad "no asahi ICD file"
if have vulkaninfo; then
  out=$(timeout -k 5 60 vulkaninfo --summary 2>&1); rc=$?
  if [[ $rc -eq 0 && $out == *"Apple M5 Pro"* ]]; then
    pass "vulkaninfo lists the Apple M5 Pro device"
    echo "$out" | grep -E 'deviceName|driverName|apiVersion|driverInfo' | sed 's/^ */  /'
  else bad "vulkaninfo rc=$rc, no Apple M5 Pro device"; fi
else skip "vulkaninfo missing (pacman -S vulkan-tools)"; fi
if [[ $vkcube -eq 1 ]]; then
  if have vkcube; then
    timeout -k 5 10 vkcube --c 600 >/dev/null 2>&1; rc=$?
    [[ $rc -eq 0 || $rc -eq 124 ]] && echo "INFO vkcube ran 10 s (exit $rc): owner must say whether a cube spun" || bad "vkcube crashed, exit $rc"
  else skip "vkcube missing (vulkan-tools)"; fi
fi

echo "== OpenCL (#27)"
if ls "$root"/etc/OpenCL/vendors/*.icd >/dev/null 2>&1; then pass "OpenCL ICD registered"; else
  echo "INFO no OpenCL ICD in /etc/OpenCL/vendors: no rusticl in mesa-aurora (expected today)"; fi
have clinfo && { timeout -k 5 30 clinfo -l 2>&1 | head -5; } || skip "clinfo missing; no compute run is part of this script"

echo "== Screen capture (#32)"
if have gpu-screen-recorder; then opts=$(timeout -k 5 20 gpu-screen-recorder --list-capture-options 2>/dev/null </dev/null); orc=$?; fi
if ! have gpu-screen-recorder; then echo "INFO gpu-screen-recorder absent: wf-recorder is the only backend"
elif [[ $orc -ne 0 || -z $opts ]]; then echo "INFO gpu-screen-recorder listed no capture options (exit $orc): unknown which backend is used"
elif [[ $(grep -v '^portal$' <<<"$opts" | grep -c .) -eq 0 ]]; then
  pass "gpu-screen-recorder lists only the portal target: screen and region targets then fall back to wf-recorder (source-read)"
else echo "INFO gpu-screen-recorder sees a display device: it would be used first"; fi
if [[ $capture -eq 1 ]]; then
  if have grim; then
    timeout -k 5 20 grim "$tmp/s.png" && [[ $(file -b "$tmp/s.png") == "PNG image data"* ]] &&
      pass "grim: $(file -b "$tmp/s.png" | cut -d, -f1,2), $(stat -c %s "$tmp/s.png") bytes" || bad "grim produced no PNG"
    rm -f "$tmp/s.png"
  else skip "grim missing"; fi
  if have wf-recorder && have ffprobe; then
    timeout -s INT -k 5 3 wf-recorder -f "$tmp/c.mkv" -y >/dev/null 2>&1
    info=$(ffprobe -v error -show_entries stream=codec_name,width,height:format=duration -of csv=p=0 "$tmp/c.mkv" 2>&1)
    [[ $info == h264,* ]] && pass "wf-recorder 3 s clip: $(echo "$info" | tr '\n' ' ')" || bad "wf-recorder clip unreadable: $info"
    rm -f "$tmp/c.mkv"
  else skip "wf-recorder or ffprobe missing"; fi
fi

echo "== Chromium and Electron (#28)"
fl=${XDG_CONFIG_HOME:-$HOME/.config}/chromium-flags.conf
[[ -f $fl ]] && grep -qx -- '--disable-features=AcceleratedVideoDecoder' "$fl" &&
  pass "chromium-flags.conf turns hardware video decode off" || bad "chromium-flags.conf lacks --disable-features=AcceleratedVideoDecoder"
if [[ -e $root/usr/share/omarchy/bin/omarchy-cmd-electron-gl-wrap ]]; then echo "INFO electron GL wrapper present"
else echo "INFO no omarchy-cmd-electron-gl-wrap: no software-GL forcing, Chromium uses the render node"; fi
[[ -e $root/dev/dri/renderD128 ]] && pass "render node present" || bad "no render node"

echo "== Widevine (#31)"
cdm=$root/opt/WidevineCdm/chromium
lib=$cdm/_platform_specific/linux_arm64/libwidevinecdm.so
[[ -f $lib ]] && file -L "$lib" | grep -q 'ARM aarch64' && pass "arm64 CDM present" || bad "no arm64 libwidevinecdm.so"
[[ -f $cdm/manifest.json ]] && grep -E '"version"|x-cdm-codecs' "$cdm/manifest.json" | sed 's/^ */  /' || bad "no CDM manifest"
[[ -e $root/usr/lib/chromium/WidevineCdm/manifest.json ]] && pass "Chromium sees the CDM under /usr/lib/chromium" || bad "no /usr/lib/chromium/WidevineCdm"
echo "INFO key-system registration and a real stream need the owner: open a DRM page and watch for video, not blank frames"

echo "== done: $([[ $fail -eq 0 ]] && echo "no FAIL" || echo "at least one FAIL")"
exit $fail
