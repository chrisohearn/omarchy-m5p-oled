#!/bin/bash
# Test of patches/omarchy/0005-factory-reset-off-on-k114s-until-qualified.patch against the
# installed omarchy-system-factory-reset (or the file named by $1). No root, no mount, no reset:
# the patched copy gets a line appended so its own "differs from the installed command" check
# always stops it, and every case runs with stdin closed.
#   usage: test-factory-reset-gate.sh [OMARCHY_SYSTEM_FACTORY_RESET]
set -u
here=$(cd "$(dirname "$0")" && pwd)
patch_file=$(ls "$here"/../../patches/omarchy/0003-*.patch)
src=${1:-/usr/bin/omarchy-system-factory-reset}
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: got '$2' want '$3'"; fi; }
[ -f "$src" ] || { echo "SKIP: $src is not installed"; exit 0; }
t=$(mktemp -d "${TMPDIR:-/tmp}/k114s-reset-gate.XXXXXX"); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/usr/bin"; cp "$src" "$t/usr/bin/omarchy-system-factory-reset"
# A machine that already has the patch: take it out first, so the forward patch is what is tested.
grep -q 'K114s local change: a factory reset' "$t/usr/bin/omarchy-system-factory-reset" &&
  patch -p1 -d "$t/usr" -F0 -s -R < "$patch_file"
patch -p1 -d "$t/usr" -F0 -s --dry-run < "$patch_file" >/dev/null 2>&1; ok "patch fits the installed script without fuzz" "$?" 0
patch -p1 -d "$t/usr" -F0 -s < "$patch_file"; ok "patch applies" "$?" 0
f=$t/usr/bin/omarchy-system-factory-reset
bash -n "$f"; ok "patched script parses" "$?" 0
echo '# test sentinel: never equal to the installed command' >>"$f"

ok "gate sits before sudo, the mount and the questions" \
  "$(awk '/K114s local change: a factory reset/{g=NR} /exec sudo|mount -o subvolid|confirm_reset\(\)/&&!s{s=NR} END{print (g&&s&&g<s)?"first":"late"}' "$f")" first

printf 'apple,k114s\0apple,t6050\0apple,arm-platform\0' >"$t/k114s"
printf 'apple,j714s\0apple,t6050\0' >"$t/other"
: >"$t/marker"
run() { # dt marker -> output and status
  env -i PATH=/usr/bin:/bin K114S_DT_COMPATIBLE=$1 K114S_RESET_QUALIFIED=$2 bash "$f" </dev/null 2>&1; }

out=$(run "$t/k114s" "$t/none"); rc=$?
ok "K114s, not qualified: exit 1" "$rc" 1
ok "K114s, not qualified: says it is switched off and changed nothing" "$(grep -c -e 'switched off on this Mac' -e 'Nothing was changed' <<<"$out")" 2
ok "K114s, not qualified: stops at the gate" "$(grep -c 'differs from the installed command' <<<"$out")" 0
out=$(run "$t/k114s" "$t/marker"); rc=$?
ok "K114s, qualified: gate is open (next check runs)" "$rc:$(grep -c 'differs from the installed command' <<<"$out")" "1:1"
out=$(run "$t/other" "$t/none"); rc=$?
ok "another Mac: gate is open" "$rc:$(grep -c 'switched off' <<<"$out"):$(grep -c 'differs from the installed command' <<<"$out")" "1:0:1"
out=$(run "$t/missing" "$t/none"); rc=$?
ok "no device tree (not an Apple Mac): gate is open" "$rc:$(grep -c 'switched off' <<<"$out")" "1:0"

echo "factory reset gate tests: $pass passed, $fail failed"
[ "$fail" = 0 ]
