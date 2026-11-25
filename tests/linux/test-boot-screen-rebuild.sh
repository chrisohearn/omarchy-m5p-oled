#!/bin/bash
# Test of patches/omarchy/0006-boot-screen-rebuilds-only-k114s-images.patch against the installed
# omarchy-plymouth-set (or the file named by $1). Nothing is rebuilt: only the script's last block
# (from the plymouth-set-default-theme call on) runs, with sudo, pacman, df and the Omarchy helper
# replaced by stubs that log what they were asked to do. It runs under the script's own set -euo pipefail.
#   usage: test-boot-screen-rebuild.sh [OMARCHY_PLYMOUTH_SET]
set -u
here=$(cd "$(dirname "$0")" && pwd)
patch_file=$(ls "$here"/../../patches/omarchy/0006-*.patch)
src=${1:-/usr/bin/omarchy-plymouth-set}
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: got '$2' want '$3'"; fi; }
[ -f "$src" ] || { echo "SKIP: $src is not installed"; exit 0; }
t=$(mktemp -d "${TMPDIR:-/tmp}/k114s-boot-screen.XXXXXX"); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/usr/bin" "$t/stub"; cp "$src" "$t/usr/bin/omarchy-plymouth-set"
f=$t/usr/bin/omarchy-plymouth-set
grep -q 'K114s local change: a bare limine-mkinitcpio' "$f" && patch -p1 -d "$t/usr" -F0 -s -R < "$patch_file"
patch -p1 -d "$t/usr" -F0 -s --dry-run < "$patch_file" >/dev/null 2>&1; ok "patch fits the installed script without fuzz" "$?" 0
patch -p1 -d "$t/usr" -F0 -s < "$patch_file"; ok "patch applies" "$?" 0
bash -n "$f"; ok "patched script parses" "$?" 0
start=$(grep -n '^if \[\[ \$mode != "refresh-sddm" \]\]; then$' "$f" | tail -1 | cut -d: -f1)
[ -n "$start" ] || { echo "FAIL the rebuild block was not found"; exit 1; }
{ echo 'set -euo pipefail'; echo 'mode=refresh-plymouth'; tail -n +"$start" "$f"; } > "$t/block"

cat > "$t/stub/sudo" <<'S'
#!/bin/bash
echo "sudo $*" >> "$LOG"
S
cat > "$t/stub/omarchy-cmd-present" <<'S'
#!/bin/bash
[ "$1" != limine-mkinitcpio ] || [ "${LIMINE:-yes}" = yes ]
S
cat > "$t/stub/mountpoint" <<'S'
#!/bin/bash
[ "${MOUNTED:-yes}" = yes ]
S
cat > "$t/stub/pacman" <<'S'
#!/bin/bash
[ "$1" = -Qqo ] || exit 1
printf '%s\n' $PKGS
exit ${PACMAN_RC:-0}
S
cat > "$t/stub/df" <<'S'
#!/bin/bash
printf 'Avail\n%s\n' "$FREE"
S
chmod +x "$t/stub/"*
printf 'apple,k114s\0apple,t6050\0' > "$t/k114s"; printf 'apple,j714s\0apple,t6050\0' > "$t/other"
run() { # dt packages free -> status; the log is $t/log
  : > "$t/log"; env -i ${PACMAN_RC:+PACMAN_RC=$PACMAN_RC} ${MOUNTED:+MOUNTED=$MOUNTED} ${LIMINE:+LIMINE=$LIMINE} PATH="$t/stub:/usr/bin:/bin" LOG="$t/log" K114S_DT_COMPATIBLE=$1 PKGS="$2" FREE=$3 bash "$t/block" </dev/null 2>"$t/err"; }
all='linux-aurora linux-k114s linux-k114s-r3b linux-k114s-r3b'

run "$t/k114s" "$all" 123527168; rc=$?
ok "K114s: succeeds" "$rc" 0
ok "K114s: rebuilds only the K114s kernels, once each" "$(grep limine-mkinitcpio "$t/log")" "sudo limine-mkinitcpio linux-k114s linux-k114s-r3b"
ok "K114s: still sets the theme first" "$(head -1 "$t/log")" "sudo plymouth-set-default-theme omarchy"
run "$t/k114s" "$all" 44000000; rc=$?
ok "K114s, low space: exit 1, nothing rebuilt" "$rc:$(grep -c limine-mkinitcpio "$t/log")" "1:0"
ok "K114s, low space: prints the command for later" "$(grep -c 'sudo limine-mkinitcpio linux-k114s linux-k114s-r3b' "$t/err")" 1
run "$t/k114s" "$all" ''; rc=$?
ok "K114s, unreadable space: exit 1, nothing rebuilt" "$rc:$(grep -c limine-mkinitcpio "$t/log")" "1:0"
run "$t/k114s" "linux-aurora" 123527168; rc=$?
ok "K114s, no K114s kernel: exit 1 with its message, nothing rebuilt" "$rc:$(grep -c limine-mkinitcpio "$t/log"):$(grep -c "No linux-k114s kernel is installed" "$t/err")" "1:0:1"
PACMAN_RC=1; export PACMAN_RC; run "$t/k114s" "$all" 123527168; rc=$?; unset PACMAN_RC
ok "K114s, a module folder pacman does not own: still rebuilds the K114s kernels" "$rc:$(grep limine-mkinitcpio "$t/log")" "0:sudo limine-mkinitcpio linux-k114s linux-k114s-r3b"
MOUNTED=no; run "$t/k114s" "$all" 123527168; rc=$?; unset MOUNTED
ok "K114s, EFI partition not mounted: exit 1, nothing rebuilt" "$rc:$(grep -c limine-mkinitcpio "$t/log"):$(grep -c 'not mounted' "$t/err")" "1:0:1"
LIMINE=no; run "$t/k114s" "$all" 123527168; rc=$?; unset LIMINE
ok "K114s, no limine-mkinitcpio: exit 1, no mkinitcpio -P" "$rc:$(grep -c mkinitcpio "$t/log"):$(grep -c 'limine-mkinitcpio is missing' "$t/err")" "1:0:1"
LIMINE=no; run "$t/other" "$all" 44000000; rc=$?; unset LIMINE
ok "other Mac, no limine-mkinitcpio: unchanged mkinitcpio -P" "$rc:$(grep mkinitcpio "$t/log")" "0:sudo mkinitcpio -P"
run "$t/other" "$all" 44000000; rc=$?
ok "other Mac: unchanged bare rebuild" "$rc:$(grep limine-mkinitcpio "$t/log")" "0:sudo limine-mkinitcpio"

echo "passed $pass, failed $fail"; [ "$fail" = 0 ]
