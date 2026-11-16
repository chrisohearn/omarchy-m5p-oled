#!/bin/bash
# Software test of chromium-gpu-report.sh with stub chromium, node and curl on a closed PATH (no GPU,
# no browser). Proves the script's own logic: PASS/FAIL/SKIP decisions, exit status, temp cleanup.
set -u
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d) || exit 2
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
basics=$t/basics; mkdir "$basics"
for c in bash sh env grep sed tr head seq sleep mktemp rm cat timeout kill mkdir ls; do
  p=$(type -P "$c") && ln -s "$p" "$basics/$c"
done
b=$t/bin; mkdir "$b"
# chromium stub: records a port file in --user-data-dir, logs $CRASH lines, stays up until killed
cat >"$b/chromium" <<'S'
#!/bin/sh
for a; do case $a in --user-data-dir=*) d=${a#*=};; esac; done
mkdir -p "$d"; echo 9222 >"$d/DevToolsActivePort"
[ -n "${CRASH:-}" ] && echo "GPU process exited unexpectedly" >&2
echo "$LIBGL_ALWAYS_SOFTWARE" >"$d/../sw"
sleep 30
S
echo '#!/bin/sh' >"$b/curl"
# node stub: -e is the WebSocket probe, else print the fixture
cat >"$b/node" <<'S'
#!/bin/sh
[ "$1" = -e ] && exit ${NOWS:-0}
cat "$FIXTURE"
S
chmod +x "$b"/*
fx() { printf '%s' "$2" >"$t/$1"; }
fx gpu 'Graphics Feature Status* Canvas: Hardware accelerated* Compositing: Hardware accelerated* Rasterization: Hardware accelerated* WebGL: Hardware accelerated* GL_RENDERER: ANGLE (Mesa, AGX G13/G14) GL_VERSION: 3.2'
fx swr 'Graphics Feature Status* Canvas: Software only, hardware acceleration unavailable* Compositing: Software only* Rasterization: Software only, hardware acceleration unavailable* WebGL: Disabled* GL_RENDERER: llvmpipe GL_VERSION: 4'
fx swbad 'Graphics Feature Status* Canvas: Hardware accelerated* Rasterization: Software only* WebGL: Hardware accelerated'
fx llv 'Graphics Feature Status* Canvas: Hardware accelerated* Compositing: Hardware accelerated* Rasterization: Hardware accelerated* WebGL: Hardware accelerated* GL_RENDERER: llvmpipe GL_VERSION: 4'
: >"$t/empty"
run() { # fixture args... ; env passes through
  local f=$1; shift
  out=$(PATH=$b:$basics FIXTURE=$t/$f TMPDIR=$t/tmp "$here/chromium-gpu-report.sh" "$@" 2>&1); rc=$?
}
mkdir "$t/tmp"
run gpu;            [[ $rc -eq 0 && $out == *"PASS WebGL hardware"* ]] && ok "GPU pass" || bad "gpu: $rc $out"
run llv;            [[ $rc -eq 1 && $out == *"FAIL software renderer in GPU mode"* ]] && ok "software renderer in GPU mode fails" || bad "llv: $out"
run swr --software; [[ $rc -eq 0 && $out == *"PASS software fallback"* ]] && ok "software-mode pass" || bad "swr: $rc $out"
run swbad --software; [[ $rc -eq 1 && $out == *"FAIL Canvas still accelerated"* && $out == *"FAIL WebGL still accelerated"* ]] && ok "accelerated in software mode fails" || bad "swbad: $out"
CRASH=1 run gpu;    [[ $rc -eq 1 && $out == *"FAIL GPU process crash"* ]] && ok "crash lines fail" || bad "crash: $out"
run empty;          [[ $rc -eq 1 && $out == *"page empty"* ]] && ok "empty page fails" || bad "empty: $out"
NOWS=1 run gpu;     [[ $rc -eq 2 && $out == *"SKIP node has no WebSocket"* ]] && ok "old node is a SKIP" || bad "nows: $out"
LIBGL_ALWAYS_SOFTWARE=1 run gpu; [[ $rc -eq 2 && $out == *"SKIP this session is on the CPU guard"* ]] && ok "CPU guard is a SKIP" || bad "guard: $out"
ASAHI_M5_BRINGUP=0 run gpu;      [[ $rc -eq 2 ]] && ok "bring-up guard is a SKIP" || bad "bringup: $out"
rm "$b/curl"; run gpu; [[ $rc -eq 2 && $out == *"SKIP curl missing"* ]] && ok "missing tool is a SKIP" || bad "tool: $out"
[[ -z $(ls -A "$t/tmp") ]] && ok "temp directory removed" || bad "temp left"
[[ $fail -eq 0 ]] && echo "all ok" || echo "FAILURES"
exit $fail
