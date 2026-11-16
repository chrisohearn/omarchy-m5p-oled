#!/bin/bash
# Tests of install.sh and titlebars-abi-check --pre in a throwaway root, with a fake pacman.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: got '$2' want '$3'"; fi; }
BASE=$(mktemp -d "${TMPDIR:-/tmp}/k114s-titlebars-install.XXXXXX"); trap 'rm -rf "$BASE"' EXIT
cat > "$BASE/pacman" <<'FAKE'
#!/bin/sh
case $1 in
  -Qp) echo "${FAKE_INFO:-omarchy-hyprland-titlebars 1:0.4.0+m5-1}" ;;
  -U) { cat "$K114S_ROOT/run/omarchy-k114s/permit"; [ -e "$K114S_ROOT/etc/omarchy-k114s/allow-coupled-update" ] && echo coupled; [ -e "$K114S_ROOT/etc/omarchy-k114s/allow-low-esp" ] && echo lowesp; echo "U $*"; } > "$K114S_ROOT/seen"
      [ -n "$FAKE_NOSO" ] || { mkdir -p "$K114S_ROOT/usr/lib/omarchy-hyprland-titlebars"; : > "$K114S_ROOT/usr/lib/omarchy-hyprland-titlebars/titlebars.so"; }
      exit "${FAKE_RC:-0}" ;;
esac
FAKE
chmod +x "$BASE/pacman"; : > "$BASE/pkg"
inst() { mkdir -p "$1/usr/bin"; : > "$1/usr/bin/Hyprland"; K114S_HYPRLAND_OWNER=hyprland K114S_ROOT=$1 PACMAN=$BASE/pacman "$HERE/install.sh" "${2:-$BASE/pkg}" > "$BASE/out" 2>&1; echo $?; }
E=etc/omarchy-k114s

E=etc/omarchy-k114s
r=$BASE/r1; mkdir -p $r
ok "install: exits 0" "$(inst $r)" 0
ok "... pacman saw the narrow permit and allow-low-esp while it ran" "$(head -2 $r/seen | tr '\n' ' ')" "install omarchy-hyprland-titlebars lowesp "
ok "... permit and marker are gone afterwards" "$(find $r/$E $r/run -type f | tr -d '\n')" ""
ok "... guard script, pre hook and post hook installed" "$(test -x $r/usr/local/lib/omarchy-k114s/titlebars-abi-check && test -f $r/etc/pacman.d/hooks/00-k114s-titlebars-guard.hook && test -f $r/etc/pacman.d/hooks/02-k114s-titlebars-abi.hook && echo yes)" yes
r=$BASE/r2; mkdir -p $r/$E; : > $r/$E/allow-low-esp
inst $r > /dev/null
ok "a marker the owner had already set stays" "$(ls $r/$E)" allow-low-esp
r=$BASE/r3; mkdir -p $r
ok "pacman failing: install fails" "$(FAKE_RC=1 inst $r)" 1
ok "... and the markers are still removed" "$(ls $r/$E)" ""
r=$BASE/r4; mkdir -p $r
ok "the channel's package is refused" "$(FAKE_INFO='omarchy-hyprland-titlebars 0.4.0-1' inst $r)" 1
ok "... before pacman -U or any marker" "$(ls $r/seen $r/$E 2>&1 | grep -c 'No such file')" 2
ok "... and the hooks were not installed either" "$(ls $r/etc/pacman.d/hooks 2>&1 | grep -c 'No such file')" 1

ok "... never opens the blanket allow-coupled-update" "$(grep -c coupled $BASE/r1/seen)" 0
r=$BASE/r5; mkdir -p $r/var/lib/pacman; : > $r/var/lib/pacman/db.lck
ok "a held pacman database: install refuses" "$(inst $r)" 1
ok "... before any marker or permit" "$(find $r/seen $r/$E $r/run -type f 2>/dev/null | wc -l)" 0
r=$BASE/r6; mkdir -p $r
ok "titlebars.so not extracted: install fails" "$(FAKE_NOSO=1 inst $r)" 1
ok "... and permit and marker are still removed" "$(find $r/$E $r/run -type f | tr -d '\n')" ""
r=$BASE/r7; mkdir -p $r/run/omarchy-k114s; echo x > $r/run/omarchy-k114s/permit
ok "an existing release permit: install refuses and leaves it" "$(inst $r)$(cat $r/run/omarchy-k114s/permit)" 1x
r=$BASE/r8; mkdir -p $r
ok "install prints the package sha256" "$(inst $r >/dev/null; grep -c "$BASE/pkg" $BASE/out)" 1

pre() { printf '%s\n' "${@:2}" | K114S_ROOT=$1 sh "$HERE/titlebars-abi-check" --pre > "$BASE/out" 2>&1; echo $?; }
r=$BASE/p1; mkdir -p $r/$E $r/run/omarchy-k114s
ok "--pre: the plugin with no marker: stopped" "$(pre $r omarchy-hyprland-titlebars)" 1
ok "... naming it" "$(grep -c 'would change omarchy-hyprland-titlebars' "$BASE/out")" 1
ok "--pre: hyprland-m5 alone: stopped" "$(pre $r hyprland-m5)" 1
ok "--pre: no targets: nothing to stop" "$(printf '' | K114S_ROOT=$r sh "$HERE/titlebars-abi-check" --pre >/dev/null 2>&1; echo $?)" 0
printf 'install omarchy-hyprland-titlebars\n' > $r/run/omarchy-k114s/permit
ok "--pre: a permit for the plugin lets it through" "$(pre $r omarchy-hyprland-titlebars)" 0
ok "... but not hyprland-m5 beside it" "$(pre $r omarchy-hyprland-titlebars hyprland-m5)" 1
printf 'install omarchy-hyprland-titlebars\ninstall hyprland-m5\n' > $r/run/omarchy-k114s/permit
ok "... a permit for both lets both through" "$(pre $r omarchy-hyprland-titlebars hyprland-m5)" 0
touch -d '2 hours ago' $r/run/omarchy-k114s/permit
ok "--pre: a stale permit counts for nothing" "$(pre $r omarchy-hyprland-titlebars)" 1
: > $r/$E/allow-coupled-update
ok "--pre: allow-coupled-update lets it through" "$(pre $r omarchy-hyprland-titlebars hyprland-m5)" 0
E3B0=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
r=$BASE/s1; mkdir -p $r
ok "expected sha256 that matches: install passes" "$(mkdir -p $r/usr/bin; : > $r/usr/bin/Hyprland; K114S_ROOT=$r PACMAN=$BASE/pacman K114S_HYPRLAND_OWNER=hyprland "$HERE/install.sh" "$BASE/pkg" $E3B0 >/dev/null 2>&1; echo $?)" 0
r=$BASE/s2; mkdir -p $r/usr/bin; : > $r/usr/bin/Hyprland
ok "expected sha256 that differs: install refuses" "$(K114S_ROOT=$r PACMAN=$BASE/pacman K114S_HYPRLAND_OWNER=hyprland "$HERE/install.sh" "$BASE/pkg" "$(printf '0%.0s' {1..64})" >/dev/null 2>&1; echo $?)" 1
ok "... before pacman -U or any marker" "$(find $r/seen $r/$E $r/run -type f 2>/dev/null | wc -l)" 0
echo "titlebars install/guard tests: $pass passed, $fail failed"
[ "$fail" = 0 ]
