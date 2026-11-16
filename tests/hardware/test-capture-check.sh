#!/bin/bash
# Software test of k114s-capture-check.sh with stub tools on a closed PATH (no screen, no GPU).
# Proves the script's own logic only: PASS/FAIL/SKIP decisions, exit status, temp cleanup.
set -u
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d) || exit 2
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
basics=$t/basics; mkdir "$basics"
for c in bash sh file grep sed cut tr timeout mktemp rm ls head base64 pgrep dirname basename readlink cat mkdir; do
  p=$(command -v "$c") && ln -s "$p" "$basics/$c"
done
printf '#!/bin/sh\n' >"$basics/sleep"; chmod +x "$basics/sleep" # no real waiting
mk() { # name; $2 = broken makes the --no-dmabuf path fail
  local d=$t/$1 b=$t/$1/bin
  mkdir -p "$b" "$d/root/sys/class/drm/card0" "$d/root/sys/class/drm/renderD128" "$d/tmp"
  printf '#!/bin/sh\necho portal\n' >"$b/gpu-screen-recorder"
  printf '#!/bin/sh\necho iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAwS2OUAAAAABJRU5ErkJggg== | base64 -d >"$1"\n' >"$b/grim"
  printf '#!/bin/sh\nfor a; do [ "$a" = --no-dmabuf ] && nd=1; done\n[ "${nd:-}" = 1 ] && [ "%s" = broken ] && exit 1\nwhile [ $# -gt 0 ]; do [ "$1" = -f ] && echo clip >"$2"; shift; done\n' "${2:-good}" >"$b/wf-recorder"
  printf '#!/bin/sh\nfor l; do :; done\n[ -s "$l" ] && echo h264,3024,1986\n' >"$b/ffprobe"
  chmod +x "$b"/*
}
run() { local d=$t/$1; shift; out=$(CAPTURE_CHECK_ROOT=$d/root TMPDIR=$d/tmp PATH=$d/bin:$basics "$here/k114s-capture-check.sh" "$@" 2>&1); rc=$?; }
mk a; run a
[[ $out == *"PASS grim: PNG image data"* && $out == *"PASS wf-recorder default"* && $out == *"PASS wf-recorder no-dmabuf"* ]] && ok "good stubs pass" || bad "good: $out"
[[ $out == *"INFO card0: driver"* && $out == *"INFO renderD128: driver"* ]] && ok "topology lines printed" || bad "topology: $out"
[[ $out == *"PASS gpu-screen-recorder lists only the portal"* ]] && ok "portal-only recorder detected" || bad "portal: $out"
[[ $rc -eq 0 && -z $(ls -A "$t/a/tmp") ]] && ok "exit 0 and temp removed" || bad "rc=$rc tmp=$(ls -A "$t/a/tmp")"
mk b broken; run b
[[ $out == *"FAIL wf-recorder no-dmabuf"* && $rc -eq 1 ]] && ok "failing --no-dmabuf path is a FAIL, exit 1" || bad "broken: $out rc=$rc"
rm "$t/b/bin/grim" "$t/b/bin/ffprobe"; run b
[[ $out == *"SKIP grim missing"* && $out == *"SKIP wf-recorder or ffprobe missing"* && $rc -eq 1 ]] && ok "missing core tools are SKIPs and exit 1" || bad "skip: $out"
# --script: the stub toggle starts a (fake) wf-recorder state file and writes a clip on stop; pgrep is stubbed.
mk c; b=$t/c/bin
printf '#!/bin/sh\ncase "$1" in --status) exit 1;; --stop-recording) [ "${STUB_NOFILE:-}" = 1 ] || echo clip >"$OMARCHY_SCREENRECORD_DIR/v.mp4";; esac\n' >"$b/omarchy-capture-screenrecording"
printf '#!/bin/sh\n[ "$2" = wf-recorder ]\n' >"$b/pgrep"; printf '#!/bin/sh\nexit 1\n' >"$b/pidof"; chmod +x "$b"/*
run c --script
[[ $out == *"PASS script recorded with wf-recorder"* && $out == *"PASS script wrote a readable clip"* && $rc -eq 0 ]] && ok "--script passes with wf-recorder and a clip" || bad "script: $out rc=$rc"
STUB_NOFILE=1 run c --script
[[ $out == *"FAIL script wrote no readable h264 clip"* && $rc -eq 1 ]] && ok "--script with no file is a FAIL, exit 1" || bad "nofile: $out rc=$rc"
printf '#!/bin/sh\n[ "$1" = gpu-screen-recorder ]\n' >"$b/pidof"; chmod +x "$b/pidof"; run c --script
[[ $out == *"FAIL script did not record with wf-recorder alone"* && $rc -eq 1 ]] && ok "--script with gpu-screen-recorder running is a FAIL" || bad "gsr: $out rc=$rc"
printf '#!/bin/sh\nexit 1\n' >"$b/pidof"; chmod +x "$b/pidof"
printf '#!/bin/sh\nexit 1\n' >"$b/pgrep"; run c --script
[[ $out == *"FAIL script did not record with wf-recorder alone"* && $rc -eq 1 ]] && ok "--script without wf-recorder running is a FAIL" || bad "backend: $out rc=$rc"
printf '#!/bin/sh\n[ "$1" = --status ] && exit 0\n' >"$b/omarchy-capture-screenrecording"; run c --script
[[ $out == *"SKIP a recording is already running"* ]] && ok "running recording is a SKIP, no toggle" || bad "toggle: $out"
run a --bogus; [[ $rc -eq 2 ]] && ok "unknown argument exits 2" || bad "bogus rc=$rc"
exit $fail
