#!/bin/bash
# Software test of linux/media/k114s-vaapi in a fake root: install, check, undo, and the refusal without the driver.
set -u
here=$(cd "$(dirname "$0")/../.." && pwd); S=$here/linux/media/k114s-vaapi; fail=0; n=0; nf=0
ok() { echo "ok   $1"; n=$((n+1)); }; bad() { echo "FAIL $1"; fail=1; nf=$((nf+1)); }
R=$(mktemp -d); trap 'rm -rf "$R"' EXIT
dst=$R/etc/environment.d/50-k114s-vaapi.conf
out=$(K114S_ROOT=$R bash "$S" --install 2>&1); rc=$?
[ $rc = 1 ] && [ ! -e "$dst" ] && grep -q 'asahi_drv_video.so is missing' <<<"$out" && ok "no VA-API driver: refused, nothing written" || bad "missing driver not refused (rc $rc): $out"
mkdir -p "$R/usr/lib/dri" && : > "$R/usr/lib/dri/asahi_drv_video.so"
K114S_ROOT=$R bash "$S" --check >/dev/null 2>&1 && bad "check passes before install" || ok "check fails before install"
K114S_ROOT=$R bash "$S" --install >/dev/null 2>&1 && [ -f "$dst" ] && ok "install writes $(basename "$dst")" || bad "install"
[ "$(grep -v '^#' "$dst")" = "LIBVA_DRIVER_NAME=asahi" ] && ok "the file sets exactly LIBVA_DRIVER_NAME=asahi" || bad "file content: $(cat "$dst")"
[ "$(stat -c %a "$dst")" = 644 ] && ok "mode 644" || bad "mode $(stat -c %a "$dst")"
K114S_ROOT=$R bash "$S" --check >/dev/null 2>&1 && ok "check passes after install" || bad "check after install"
echo "LIBVA_DRIVER_NAME=other" > "$dst"; K114S_ROOT=$R bash "$S" --check >/dev/null 2>&1 && bad "check passes on a changed file" || ok "check fails on a changed file"
K114S_ROOT=$R bash "$S" --install >/dev/null 2>&1 && K114S_ROOT=$R bash "$S" --check >/dev/null 2>&1 && ok "install repairs a changed file" || bad "repair"
# an override that cannot be removed (a read-only directory) must fail undo, not report success (#186); root ignores the mode
if [ "$(id -u)" != 0 ]; then
  chmod 555 "$(dirname "$dst")"; out=$(K114S_ROOT=$R bash "$S" --undo 2>&1); rc=$?; chmod 755 "$(dirname "$dst")"
  [ $rc != 0 ] && [ -e "$dst" ] && grep -q 'cannot remove' <<<"$out" && ok "undo fails when the override cannot be removed" || bad "undo reported success with the override still present (rc $rc): $out"
fi
K114S_ROOT=$R bash "$S" --undo >/dev/null 2>&1 && [ ! -e "$dst" ] && ok "undo removes it" || bad "undo"
K114S_ROOT=$R bash "$S" --bogus >/dev/null 2>&1 && bad "unknown flag accepted" || ok "unknown flag refused"
echo "vaapi tests: $n passed, $nf failed"; exit $fail
