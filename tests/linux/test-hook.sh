#!/bin/bash
# Tests of linux/update-boot-ctxr-k114s against the image's real combined boot.bin.
#   usage: test-hook.sh LINUX_DIR FIXTURES     (FIXTURES/hooktest: boot.bin, aura-stage2-prefix.bin,
#   t6050-k114s-r1.dtb, t6050-j714s.dtb; build outputs, not in the repository)
set -u
L=$(cd "$1" && pwd); H=$(cd "$2/hooktest" && pwd); S=$L/update-boot-ctxr-k114s; pass=0; fail=0
R1=45a5dbef19c14898e73e79a42af360def638c319d14e2bae97a79f7962e4bfb4
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: got $2 want $3"; fi; }
sha() { sha256sum "$1" | cut -c1-64; }
BASE=$(mktemp -d "${TMPDIR:-/tmp}/k114s-hook-test.XXXXXX"); trap 'rm -rf "$BASE"' EXIT
mk() { local r; r=$(mktemp -d "$BASE/root.XXXXXX"); mkdir -p "$r/boot/efi/m1n1" "$r/usr/lib/asahi-boot" "$r/usr/local/lib/omarchy-k114s"
  cp "$H/boot.bin" "$r/boot/efi/m1n1/boot.bin"; cp "$H/aura-stage2-prefix.bin" "$r/usr/lib/asahi-boot/m1n1.bin"
  cp "$H/t6050-k114s-r1.dtb" "$r/usr/local/lib/omarchy-k114s/k114s.dtb"; echo OLD > "$r/boot/efi/m1n1/boot-ctxr.bin"; echo "$r"; }
r=$(mk); OMARCHY_ROOT=$r sh "$S" >/dev/null 2>&1; ok "pinned r1 tree gives the r1 Stage 2" "$(sha "$r/boot/efi/m1n1/boot-ctxr.bin")" $R1
OMARCHY_ROOT=$r sh "$S" >/dev/null 2>&1; ok "idempotent" "$(sha "$r/boot/efi/m1n1/boot-ctxr.bin")" $R1
ok "boot.bin untouched" "$(sha "$r/boot/efi/m1n1/boot.bin")" 3bfbff92990e4846255b9af57f1c73202716b96fcfcf1850316d5d62b4dc5bfa
ok "no temp files left" "$(ls -A "$r/boot/efi/m1n1" | tr '\n' ' ')" "boot-ctxr.bin boot.bin "
touch "$r/usr/local/lib/omarchy-k114s/use-packaged-dtb"; OMARCHY_ROOT=$r sh "$S" >/dev/null 2>&1; ok "use-packaged-dtb gives the packaged K114s tree" "$(sha "$r/boot/efi/m1n1/boot-ctxr.bin")" 00382a4f2be9bf09886014bf9eedc41a223ecc788704971ac5d7f8f239a32269
r=$(mk); rm "$r/usr/local/lib/omarchy-k114s/k114s.dtb"; OMARCHY_ROOT=$r sh "$S" >/dev/null 2>&1; rc=$?; ok "missing pinned tree: fails" "$rc" 1; ok "missing pinned tree: old file kept" "$(cat "$r/boot/efi/m1n1/boot-ctxr.bin")" OLD
r=$(mk); cp "$H/t6050-j714s.dtb" "$r/usr/local/lib/omarchy-k114s/k114s.dtb"; OMARCHY_ROOT=$r sh "$S" >/dev/null 2>&1; rc=$?; ok "J714s tree as pinned: refused" "$rc" 1; ok "J714s tree: old file kept" "$(cat "$r/boot/efi/m1n1/boot-ctxr.bin")" OLD
r=$(mk); head -c 1000 /dev/urandom > "$r/usr/lib/asahi-boot/m1n1.bin"; OMARCHY_ROOT=$r sh "$S" >/dev/null 2>&1; rc=$?; ok "boot.bin not starting with m1n1.bin: refused" "$rc" 1; ok "prefix mismatch: old file kept" "$(cat "$r/boot/efi/m1n1/boot-ctxr.bin")" OLD
r=$(mk); head -c 5000000 "$H/boot.bin" > "$r/boot/efi/m1n1/boot.bin"; OMARCHY_ROOT=$r sh "$S" >/dev/null 2>&1; rc=$?; ok "truncated boot.bin: refused" "$rc" 1; ok "truncated: old file kept" "$(cat "$r/boot/efi/m1n1/boot-ctxr.bin")" OLD
r=$(mk); rm "$r/boot/efi/m1n1/boot.bin"; OMARCHY_ROOT=$r sh "$S" >/dev/null 2>&1; rc=$?; ok "ESP not mounted: refused" "$rc" 1
# without the identity helper installed (a system persisted by r1) the hook still works
r=$(mk); OMARCHY_ROOT=$r K114S_ESP_DT=/nonexistent sh "$S" >/dev/null 2>&1; ok "no identity helper: writes as before" "$(sha "$r/boot/efi/m1n1/boot-ctxr.bin")" $R1
r=$(mk); cp "$L/k114s-booted-esp" "$r/usr/local/lib/omarchy-k114s/"; chmod +x "$r/usr/local/lib/omarchy-k114s/k114s-booted-esp"; printf 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\0' > "$r/dt"
OMARCHY_ROOT=$r K114S_ESP_DT=$r/dt K114S_ESP_PARTUUID=ffffffff-bbbb-cccc-dddd-eeeeeeeeeeee sh "$S" >/dev/null 2>&1; rc=$?; ok "another ESP: refused" "$rc" 1; ok "another ESP: old file kept" "$(cat "$r/boot/efi/m1n1/boot-ctxr.bin")" OLD
OMARCHY_ROOT=$r K114S_ESP_DT=$r/dt K114S_ESP_PARTUUID=AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE sh "$S" >/dev/null 2>&1; ok "the booted ESP: written" "$(sha "$r/boot/efi/m1n1/boot-ctxr.bin")" $R1
echo "hook r2 tests: $pass passed, $fail failed"
[ "$fail" = 0 ]
