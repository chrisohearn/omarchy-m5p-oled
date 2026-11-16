#!/bin/bash
# Software test of k114s-widevine-probe.sh's own logic (no Chromium started): bad usage, a missing CDM
# and a CDM file that is not an arm64 ELF must fail, and a bad option must exit 2.
set -u
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d) || exit 2
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
bash "$here/k114s-widevine-probe.sh" --nope >/dev/null 2>&1; [[ $? -eq 2 ]] && ok "bad option exits 2" || bad "bad option"
WIDEVINE_ROOT=$t bash "$here/k114s-widevine-probe.sh" >"$t/o" 2>&1; rc=$?
[[ $rc -eq 1 ]] && grep -q 'FAIL no arm64 CDM' "$t/o" && ok "missing CDM fails" || bad "missing CDM (rc=$rc)"
d=$t/usr/lib/chromium/WidevineCdm/_platform_specific/linux_arm64; mkdir -p "$d"; echo text >"$d/libwidevinecdm.so"
WIDEVINE_ROOT=$t bash "$here/k114s-widevine-probe.sh" >"$t/o" 2>&1; rc=$?
[[ $rc -eq 1 ]] && ok "non-ELF CDM fails" || bad "non-ELF CDM (rc=$rc)"
exit $fail
