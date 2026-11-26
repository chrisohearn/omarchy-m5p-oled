#!/bin/bash
# Exercise the patched settings-upgrade hook with a fake root and stub rebuilds.
#   usage: test-initcpio-sync-rebuild.sh [OMARCHY_BOOT_SYNC_INITCPIO]
set -u
here=$(cd "$(dirname "$0")" && pwd)
patch_file=$here/../../patches/omarchy/0007-initcpio-sync-rebuilds-only-k114s-images.patch
base=${patch_file%.patch}.base/bin/omarchy-boot-sync-initcpio
src=${1:-/usr/bin/omarchy-boot-sync-initcpio}
if [[ $# -eq 0 && ! -f $src ]] || grep -qs '^# K114s local change:' "$src"; then
  src=$base
fi

t=$(mktemp -d "${TMPDIR:-/tmp}/k114s-initcpio-sync.XXXXXX") || exit 1
trap 'rm -r -- "$t" </dev/null' EXIT
root=$t/root
f=$root/usr/bin/omarchy-boot-sync-initcpio
guard=$root/etc/boot/hooks/pre.d/00-k114s-boot-rebuild-guard
state=$root/var/lib/omarchy/initcpio.sha256
mkdir -p "$root/usr/bin" "$root/usr/share/plymouth/themes/omarchy" "$root/usr/lib/modules/test" \
  "$root/etc/mkinitcpio.conf.d" "$(dirname "$guard")" "$t/stub" || exit 1
cp "$src" "$f" || exit 1
patch -p1 -d "$root/usr" -F0 -s < "$patch_file" || exit 1
bash -n "$f" || exit 1

install -m755 "$here/../../linux/00-k114s-boot-rebuild-guard" "$guard" || exit 1
printf 'linux-aurora\n' > "$root/usr/lib/modules/test/pkgbase"
touch "$root/usr/lib/modules/test/modules.builtin"
printf 'apple,k114s\0apple,t6050\0' > "$t/k114s"
printf 'apple,j714s\0' > "$t/other"
printf 'HOOKS+=(omarchy-test)\n' > "$root/etc/mkinitcpio.conf.d/test.conf"

cat > "$t/stub/pacman" <<'S'
#!/bin/bash
[[ $# -eq 2 && $1 == -Qqo && -f $2 ]] || exit 1
printf '%s\n' linux-aurora linux-k114s linux-k114s-r3b linux-k114s-r3b
S
cat > "$t/stub/omarchy-boot-backend" <<'S'
#!/bin/bash
[[ $# -eq 1 && $1 == --managed ]] || exit 1
printf '%s\n' "$BACKEND"
S
cat > "$t/stub/omarchy-boot-rebuild" <<'S'
#!/bin/bash
printf '%s:%s:%s\n' "${K114S_PLYMOUTH_MIN_FREE:-unset}" "$#" "$*" >> "$LOG"
[[ ${1:-} != "$FAIL_KERNEL" ]]
S
chmod +x "$t/stub/"* || exit 1

fail=0; pass=0
ok() {
  if [[ $2 == "$3" ]]; then
    pass=$((pass+1)); echo "PASS $1"
  else
    fail=$((fail+1)); printf "FAIL %s: got '%s', want '%s'\n" "$1" "$2" "$3"
  fi
}

run() {
  : > "$t/log"
  env -i PATH="$t/stub:/usr/bin:/bin" OMARCHY_INITCPIO_ROOT="$root" \
    K114S_DT_COMPATIBLE="$t/$1" LOG="$t/log" BACKEND="${BACKEND:-limine}" \
    FAIL_KERNEL="${FAIL_KERNEL:-no-failure}" bash "$f" --pacman-hook >"$t/out" 2>"$t/err"
}
log() { paste -sd, "$t/log"; }
saved_hash() { cat "$state" 2>/dev/null; }

budget=$((88080384 + $(du -sb "$root/usr/share/plymouth/themes/omarchy" | cut -f1)))
calls="$budget:1:linux-k114s,$budget:1:linux-k114s-r3b"

FAIL_KERNEL=linux-k114s-r3b run k114s; rc=$?
ok "K114s: second rebuild fails and no initial hash is written" \
  "$rc:$(test -e "$state" && echo present):$(log)" "1::$calls"
ok "K114s: names the failed kernel" "$(grep -c 'Could not rebuild the linux-k114s-r3b boot image' "$t/err")" 1

run k114s; rc=$?
expected=$(env -i PATH=/usr/bin:/bin OMARCHY_INITCPIO_ROOT="$root" bash "$f" --print-hash) || exit 1
ok "K114s: only installed K114s kernels are rebuilt, one per call, with a space budget" "$rc:$(log)" "0:$calls"
ok "K114s: success records the input hash" "$(saved_hash)" "$expected"
run k114s; rc=$?
ok "K114s: unchanged hash skips rebuilds" "$rc:$(log)" "0:"

printf 'HOOKS+=(omarchy-changed)\n' > "$root/etc/mkinitcpio.conf.d/test.conf"
FAIL_KERNEL=linux-k114s-r3b run k114s; rc=$?
ok "K114s: failure after an input change keeps the previous hash" "$rc:$(saved_hash):$(log)" "1:$expected:$calls"
for backend in none systemd-boot $'limine\nsystemd-boot'; do
  BACKEND=$backend run k114s; rc=$?
  ok "K114s: refuses ${backend//$'\n'/ } and keeps the previous hash" \
    "$rc:$(saved_hash):$(log):$(grep -c 'not Limine alone' "$t/err")" "1:$expected::1"
done
chmod -x "$guard"
run k114s; rc=$?
ok "K114s: disabled guard prevents rebuild and preserves the previous hash" \
  "$rc:$(saved_hash):$(log):$(grep -c 'guard is missing or disabled' "$t/err")" "1:$expected::1"

run other; rc=$?
expected=$(env -i PATH=/usr/bin:/bin OMARCHY_INITCPIO_ROOT="$root" bash "$f" --print-hash) || exit 1
ok "other Mac: stock bare rebuild and hash update" "$rc:$(log):$(saved_hash)" "0:unset:0::$expected"

echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
