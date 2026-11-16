#!/bin/bash
# Software test of media-smoke.sh against a fake file tree and stub tools (no GPU, no screen, no
# Chromium), run with a closed PATH (stubs plus basic tools only), so host GPU tools never run. It proves the script's own logic only: the PASS/FAIL/SKIP decisions, the exit status,
# and that the temp files are gone afterwards.
set -u
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d) || exit 2
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

# closed PATH: symlinks to only the basics the script needs
basics=$t/basics; mkdir "$basics"
for c in bash sh file grep sed stat cut tr timeout mktemp rm ls head base64 dirname cat; do
  p=$(command -v "$c") && ln -s "$p" "$basics/$c"
done
realfile=$(command -v file)

# build a fake root and a bin dir of stubs; $1 = name, $2 = "good" or "broken"
mk() {
  local d=$t/$1 r=$t/$1/root b=$t/$1/bin
  mkdir -p "$r/usr/share/vulkan/icd.d" "$r/dev/dri" "$r/opt/WidevineCdm/chromium/_platform_specific/linux_arm64" \
    "$r/usr/lib/chromium/WidevineCdm" "$b" "$d/home/.config"
  touch "$r/usr/share/vulkan/icd.d/asahi_icd.aarch64.json" "$r/dev/dri/renderD128"
  echo '--disable-features=AcceleratedVideoDecoder' >"$d/home/.config/chromium-flags.conf"
  echo '"version": "1"' >"$r/opt/WidevineCdm/chromium/manifest.json"
  : >"$r/usr/lib/chromium/WidevineCdm/manifest.json"
  echo text >"$r/opt/WidevineCdm/chromium/_platform_specific/linux_arm64/libwidevinecdm.so" # not an ELF: file says so
  printf '#!/bin/sh\necho "    deviceName = Apple M5 Pro (G17S B1)"\n' >"$b/vulkaninfo"
  printf '#!/bin/sh\necho portal\n' >"$b/gpu-screen-recorder"
  printf '#!/bin/sh\necho iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAwS2OUAAAAABJRU5ErkJggg== | base64 -d >"$1"\n' >"$b/grim"
  printf '#!/bin/sh\nwhile [ $# -gt 0 ]; do [ "$1" = -f ] && echo clip >"$2"; shift; done\n' >"$b/wf-recorder"
  printf '#!/bin/sh\nfor l; do :; done\n[ -s "$l" ] && echo h264,3024,1986,2.9\n' >"$b/ffprobe"
  # file reports the CDM as ARM only in the good fixture; everything else goes to the real file
  printf '#!/bin/sh\n%s\nexec %s "$@"\n' "$([[ ${2:-} == good ]] && echo 'case "$*" in *libwidevinecdm*) echo "ELF 64-bit LSB shared object, ARM aarch64"; exit 0;; esac')" "$realfile" >"$b/file"
  chmod +x "$b"/*
  echo "$d"
}
run() { # dir args... -> output; sets rc
  local d=$1; shift
  out=$(HOME=$d/home XDG_CONFIG_HOME=$d/home/.config MEDIA_SMOKE_ROOT=$d/root TMPDIR=$d/tmp PATH=$d/bin:$basics "$here/media-smoke.sh" "$@" 2>&1); rc=$?
}

d=$(mk a); mkdir "$d/tmp"
run "$d" --no-capture
[[ $out == *"PASS ICD file present"* && $out == *"PASS vulkaninfo lists the Apple M5 Pro"* ]] && ok "vulkaninfo device is a pass" || bad "vulkan: $out"
[[ $out == *"PASS gpu-screen-recorder lists only the portal"* ]] && ok "portal-only recorder is detected" || bad "recorder: $out"
[[ $out == *"FAIL arm64 CDM"* || $out == *"FAIL no arm64"* ]] && ok "a non-ARM CDM is a FAIL" || bad "cdm: $out"
[[ $rc -eq 1 ]] && ok "a FAIL gives exit 1" || bad "exit status $rc"
[[ -z $(ls -A "$d/tmp") ]] && ok "temp directory removed" || bad "temp left: $(ls -A "$d/tmp")"

run "$d" --bogus
[[ $rc -eq 2 ]] && ok "unknown argument exits 2" || bad "bogus rc=$rc"

d=$(mk b); mkdir "$d/tmp"; rm "$d/bin/vulkaninfo" "$d/home/.config/chromium-flags.conf"
run "$d"
[[ $out == *"SKIP vulkaninfo missing"* ]] && ok "missing vulkaninfo is a SKIP" || bad "skip: $out"
[[ $out == *"FAIL chromium-flags.conf lacks"* ]] && ok "missing flags file is a FAIL" || bad "flags: $out"
[[ $out == *"PASS grim: PNG image data"* && $out == *"PASS wf-recorder 3 s clip"* ]] && ok "capture steps pass with stubs" || bad "capture: $out"
[[ -z $(ls -A "$d/tmp") ]] && ok "capture temp files removed" || bad "temp left"

# good fixture: clean path, exit 0, no FAIL
d=$(mk c good); mkdir "$d/tmp"
run "$d"
[[ $rc -eq 0 && $out == *"PASS arm64 CDM present"* ]] && ! grep -q "^FAIL" <<<"$out" && ok "healthy system: exit 0, no FAIL" || bad "good: rc=$rc $out"
[[ $out == *"PASS wf-recorder 3 s clip"* ]] && ok "ffprobe reads the file wf-recorder wrote" || bad "clip: $out"

# vulkaninfo failure
printf '#!/bin/sh\nexit 1\n' >"$d/bin/vulkaninfo"; chmod +x "$d/bin/vulkaninfo"
run "$d" --no-capture
[[ $rc -eq 1 && $out == *"FAIL vulkaninfo rc=1"* ]] && ok "vulkaninfo failure is a FAIL" || bad "vk rc: $out"

# gpu-screen-recorder variants
printf '#!/bin/sh\necho portal\necho DP-1\n' >"$d/bin/gpu-screen-recorder"; chmod +x "$d/bin/gpu-screen-recorder"
run "$d" --no-capture
[[ $out == *"INFO gpu-screen-recorder sees a display device"* ]] && ok "a listed monitor is reported" || bad "gsr mon: $out"
printf '#!/bin/sh\nexit 1\n' >"$d/bin/gpu-screen-recorder"; chmod +x "$d/bin/gpu-screen-recorder"
run "$d" --no-capture
[[ $out == *"listed no capture options"* && $out != *"sees a display"* ]] && ok "failing recorder is not misreported" || bad "gsr fail: $out"
rm "$d/bin/gpu-screen-recorder"
run "$d" --no-capture
[[ $out == *"gpu-screen-recorder absent"* ]] && ok "absent recorder is reported" || bad "gsr absent: $out"

[[ $fail -eq 0 ]] && echo "all ok" || echo "FAILURES"
exit $fail
