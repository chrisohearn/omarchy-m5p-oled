#!/bin/bash
# Test of patches/omarchy/0006-boot-screen-rebuilds-only-k114s-images.patch against the installed
# omarchy-plymouth-set (or the file named by $1). Nothing is rebuilt: only the script's last block
# (from the plymouth-set-default-theme call on) and the pre-build guard run. Stubs provide the
# kernel packages, Omarchy backend and ESP space, and model Limine's mutex with a temporary file.
#   usage: test-boot-screen-rebuild.sh [OMARCHY_PLYMOUTH_SET]
set -u
here=$(cd "$(dirname "$0")" && pwd)
patch_file=$(ls "$here"/../../patches/omarchy/0006-*.patch)
src=${1:-/usr/bin/omarchy-plymouth-set}
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: got '$2' want '$3'"; fi; }
[ -f "$src" ] || { echo "SKIP: $src is not installed"; exit 0; }
t=$(mktemp -d "${TMPDIR:-/tmp}/k114s-boot-screen.XXXXXX"); trap 'rm -r -- "$t" </dev/null' EXIT
mkdir -p "$t/usr/bin" "$t/stub"; cp "$src" "$t/usr/bin/omarchy-plymouth-set"
f=$t/usr/bin/omarchy-plymouth-set
# A machine that already has a version of 0006 (perhaps an older one): test the forward patch on
# the base file it was written for instead.
grep -q 'K114s local change: ' "$f" &&
  cp "${patch_file%.patch}.base/bin/omarchy-plymouth-set" "$f"
patch -p1 -d "$t/usr" -F0 -s --dry-run < "$patch_file" >/dev/null 2>&1; ok "patch fits the installed script without fuzz" "$?" 0
patch -p1 -d "$t/usr" -F0 -s < "$patch_file"; ok "patch applies" "$?" 0
bash -n "$f"; ok "patched script parses" "$?" 0
start=$(grep -n '^if \[\[ \$mode != "refresh-sddm" \]\]; then$' "$f" | tail -1 | cut -d: -f1)
[ -n "$start" ] || { echo "FAIL the rebuild block was not found"; exit 1; }
{ echo 'set -euo pipefail'; echo 'mode=refresh-plymouth'; tail -n +"$start" "$f"; } |
  sed -e 's#/etc/boot/hooks/pre.d/00-k114s-boot-rebuild-guard#"$GUARD"#g' \
      -e 's/(( EUID == 0 ))/(( TEST_EUID == 0 ))/' > "$t/block"
sed 's#/run/lock/boot-partition.lock#"$LOCK"#; s#/proc/device-tree/compatible#"$K114S_DT_COMPATIBLE"#' \
  "$here/../../linux/00-k114s-boot-rebuild-guard" > "$t/guard"
chmod +x "$t/guard"

cat > "$t/stub/sudo" <<'S'
#!/bin/bash
echo "sudo $*" >> "$LOG"
if [[ $1 == K114S_PLYMOUTH_MIN_FREE=* ]]; then
  export K114S_PLYMOUTH_MIN_FREE=${1#*=}
  shift
  exec "$@"
fi
S
cat > "$t/stub/omarchy-boot-rebuild" <<'S'
#!/bin/bash
export HOOK_CALLER=limine-mkinitcpio-install
exec 200>"$LOCK"
# The installed Limine installer continues to the hook even on a mutex timeout.
flock -n 200 || echo 'mutex timed out' >> "$LOG"
"$GUARD" || exit 2
if [[ ${RACE:-} == yes ]]; then competing-writer; fi
echo "rebuilt $1" >> "$LOG"
S
cat > "$t/stub/competing-writer" <<'S'
#!/bin/bash
# Simulate a snapshot sync or package rebuild arriving just after the space read.
export HOOK_CALLER=limine-snapper-sync
unset K114S_PLYMOUTH_MIN_FREE
exec 200>"$LOCK"
flock -n 200 || true
if "$GUARD" 2>/dev/null; then
  echo 'competing writer got in' >> "$LOG"
else
  echo 'competing writer blocked' >> "$LOG"
fi
S
cat > "$t/stub/du" <<'S'
#!/bin/bash
printf '%s\t%s\n' "${THEME:-174225}" "$2"
S
cat > "$t/stub/omarchy-boot-backend" <<'S'
#!/bin/bash
# BACKEND is what --managed prints (space-separated); without --managed the first one, as upstream.
set -- ${BACKEND-limine} "$@"
if [ "${!#}" = --managed ]; then printf '%s\n' ${BACKEND-limine}; else echo "${1:-none}"; fi
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
# FREE is one value per call (the last repeats); DF_RC makes df fail as after an I/O error.
n=$(grep -c '^df$' "$LOG"); echo df >> "$LOG"
set -- $FREE; i=$(( n + 1 > $# ? $# : n + 1 )); printf 'Avail\n%s\n' "${!i:-}"
if [[ ${RACE:-} == yes ]]; then competing-writer; fi
exit ${DF_RC:-0}
S
chmod +x "$t/stub/"*
printf 'apple,k114s\0apple,t6050\0' > "$t/k114s"; printf 'apple,j714s\0apple,t6050\0' > "$t/other"
run() { # dt packages free -> status; the log is $t/log
  : > "$t/log"
  env -i ${PACMAN_RC:+PACMAN_RC=$PACMAN_RC} ${MOUNTED:+MOUNTED=$MOUNTED} ${BACKEND+BACKEND="$BACKEND"} \
    ${DF_RC:+DF_RC=$DF_RC} ${THEME:+THEME=$THEME} ${RACE:+RACE=$RACE} PATH="$t/stub:/usr/bin:/bin" \
    LOG="$t/log" LOCK="$t/lock" GUARD="$t/guard" K114S_DT_COMPATIBLE="$1" PKGS="$2" FREE="$3" TEST_EUID="${TEST_EUID:-1000}" \
    bash "$t/block" </dev/null 2>"$t/err"
}
all='linux-aurora linux-k114s linux-k114s-r3b linux-k114s-r3b'

TEST_EUID=0 run "$t/k114s" "$all" 123527168 > "$t/root-out"; rc=$?
ok "K114s root hardware setup: sets the theme and leaves the rebuild to its caller" \
  "$rc:$(cat "$t/log"):$(grep -c 'Boot image not rebuilt' "$t/root-out")" "0:sudo plymouth-set-default-theme omarchy:1"

RACE=yes run "$t/k114s" "$all" 123527168; rc=$?
ok "K114s: succeeds" "$rc" 0
ok "K114s: rebuilds only the K114s kernels, one at a time, once each" "$(grep '^rebuilt ' "$t/log" | paste -sd,)" "rebuilt linux-k114s,rebuilt linux-k114s-r3b"
ok "K114s: still sets the theme first" "$(head -1 "$t/log")" "sudo plymouth-set-default-theme omarchy"
ok "K114s: a contender cannot enter during or after df before either write" \
  "$(grep -E '^(df|competing writer|rebuilt)' "$t/log" | paste -sd,)" \
  "df,competing writer blocked,competing writer blocked,rebuilt linux-k114s,df,competing writer blocked,competing writer blocked,rebuilt linux-k114s-r3b"
( exec 201>"$t/lock"; flock -n 201 && run "$t/k114s" "$all" 123527168 ); rc=$?
ok "K114s, Limine's mutex times out: refuses before df or rebuild" \
  "$rc:$(grep -c 'mutex timed out' "$t/log"):$(grep -Ec '^df$|^rebuilt ' "$t/log"):$(grep -c 'lock is busy or unavailable' "$t/err")" "1:1:0:1"
chmod -x "$t/guard"; run "$t/k114s" "$all" 123527168; rc=$?; chmod +x "$t/guard"
ok "K114s, guard missing or disabled: refuses before invoking the rebuild" \
  "$rc:$(grep -c 'omarchy-boot-rebuild' "$t/log"):$(grep -c 'guard is missing or disabled' "$t/err")" "1:0:1"
run "$t/k114s" "$all" 44000000; rc=$?
ok "K114s, low space: exit 1, nothing rebuilt" "$rc:$(grep -c '^rebuilt ' "$t/log")" "1:0"
ok "K114s, low space: prints the command for later" "$(grep -c 'sudo omarchy-boot-rebuild linux-k114s linux-k114s-r3b' "$t/err")" 1
run "$t/k114s" "$all" ''; rc=$?
ok "K114s, unreadable space: exit 1, nothing rebuilt" "$rc:$(grep -c '^rebuilt ' "$t/log")" "1:0"
run "$t/k114s" "linux-aurora" 123527168; rc=$?
ok "K114s, no K114s kernel: exit 1 with its message, nothing rebuilt" "$rc:$(grep -c "mkinitcpio\|boot-rebuild" "$t/log"):$(grep -c "No linux-k114s kernel is installed" "$t/err")" "1:0:1"
PACMAN_RC=1; export PACMAN_RC; run "$t/k114s" "$all" 123527168; rc=$?; unset PACMAN_RC
ok "K114s, a module folder pacman does not own: still rebuilds the K114s kernels" "$rc:$(grep '^rebuilt ' "$t/log" | paste -sd,)" "0:rebuilt linux-k114s,rebuilt linux-k114s-r3b"
run "$t/k114s" "$all" "123527168 44000000"; rc=$?
ok "K114s, room for only the first image: rebuilds it, then refuses" "$rc:$(grep '^rebuilt ' "$t/log" | paste -sd,)" "1:rebuilt linux-k114s"
DF_RC=1; run "$t/k114s" "$all" 123527168; rc=$?; unset DF_RC
ok "K114s, df fails: exit 1 with the refusal, nothing rebuilt" "$rc:$(grep -c '^rebuilt ' "$t/log"):$(grep -c 'unreadable or too full' "$t/err")" "1:0:1"
THEME=40000000; run "$t/k114s" "$all" 123527168; rc=$?; unset THEME
ok "K114s, a 40 MB boot theme: needs the guard's minimum plus the theme, refuses at 123.5 MB" "$rc:$(grep -c '^rebuilt ' "$t/log"):$(grep -c 'needs 128080384 bytes' "$t/err")" "1:0:1"
MOUNTED=no; run "$t/k114s" "$all" 123527168; rc=$?; unset MOUNTED
ok "K114s, EFI partition not mounted: exit 1, nothing rebuilt" "$rc:$(grep -c '^rebuilt ' "$t/log"):$(grep -c 'not mounted' "$t/err")" "1:0:1"
BACKEND=none; export BACKEND; run "$t/k114s" "$all" 123527168; rc=$?; unset BACKEND
ok "K114s, no boot backend: exit 1, no mkinitcpio -P" "$rc:$(grep -c 'mkinitcpio\|boot-rebuild' "$t/log"):$(grep -c 'not Limine alone' "$t/err")" "1:0:1"
BACKEND='limine systemd-boot'; export BACKEND; run "$t/k114s" "$all" 123527168; rc=$?; unset BACKEND
ok "K114s, Limine and systemd-boot both managed (a switch on trial): exit 1, nothing rebuilt" "$rc:$(grep -c 'mkinitcpio\|boot-rebuild' "$t/log"):$(grep -c 'not Limine alone' "$t/err")" "1:0:1"
BACKEND=none; export BACKEND; run "$t/other" "$all" 44000000; rc=$?; unset BACKEND
ok "other Mac, no boot backend: unchanged mkinitcpio -P" "$rc:$(grep 'mkinitcpio\|boot-rebuild' "$t/log")" "0:sudo mkinitcpio -P"
run "$t/other" "$all" 44000000; rc=$?
ok "other Mac: unchanged bare rebuild" "$rc:$(grep 'mkinitcpio\|boot-rebuild' "$t/log")" "0:sudo omarchy-boot-rebuild"

echo "passed $pass, failed $fail"; [ "$fail" = 0 ]
