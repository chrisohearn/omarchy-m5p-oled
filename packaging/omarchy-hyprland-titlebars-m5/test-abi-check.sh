#!/bin/bash
# Tests of titlebars-abi-check in throwaway roots. Needs cc and readelf or file.
#   usage: test-abi-check.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd); S=$HERE/titlebars-abi-check; pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: got $2 want $3"; fi; }
BASE=$(mktemp -d "${TMPDIR:-/tmp}/k114s-titlebars-test.XXXXXX"); trap 'rm -rf "$BASE"' EXIT
echo 'int main(void) { return 0; }' > "$BASE/a.c"; echo 'int main(void) { return 1; }' > "$BASE/b.c"
cc -Wl,--build-id=sha1 -o "$BASE/hyprland-a" "$BASE/a.c"; cc -Wl,--build-id=sha1 -o "$BASE/hyprland-b" "$BASE/b.c"
id() { readelf -n "$1" 2>/dev/null | awk '/Build ID:/ { print $3; exit }'; }
A=$(id "$BASE/hyprland-a")
[ -n "$A" ] && [ "$A" != "$(id "$BASE/hyprland-b")" ] || { echo "cannot make two binaries with build IDs"; exit 2; }
mk() { # mk HYPRLAND [abi-build-id]: a root with that Hyprland and a plugin, stamped when an ID is given
  local r; r=$(mktemp -d "$BASE/root.XXXXXX"); mkdir -p "$r/usr/bin" "$r/usr/lib/omarchy-hyprland-titlebars"
  cp "$BASE/$1" "$r/usr/bin/Hyprland"; echo plugin > "$r/usr/lib/omarchy-hyprland-titlebars/titlebars.so"
  if [ -n "${2:-}" ]; then printf 'hyprland_package=hyprland-m5\nhyprland_version=0.57.2-2\nhyprland_build_id=%s\n' "$2" > "$r/usr/lib/omarchy-hyprland-titlebars/titlebars.abi"; fi
  echo "$r"; }
run() { K114S_ROOT=$1 K114S_HYPRLAND_OWNER=$2 sh "$S" ${3:-} > "$BASE/out" 2>&1; echo $?; }
armed() { [ -e "$1/usr/lib/omarchy-hyprland-titlebars/titlebars.so" ] && echo armed || echo aside; }

r=$(mk hyprland-a "$A"); ok "rebuild beside the Hyprland it names: ok" "$(run "$r" hyprland-m5)" 0
ok "... and --disarm leaves it armed" "$(run "$r" hyprland-m5 --disarm; armed "$r")" "0
armed"
r=$(mk hyprland-b "$A"); ok "rebuild beside another Hyprland build: mismatch" "$(run "$r" hyprland-m5)" 1
ok "... check alone moves nothing" "$(armed "$r")" armed
ok "... --disarm exits 0" "$(run "$r" hyprland-m5 --disarm)" 0
ok "... and moves the plugin aside" "$(armed "$r")" aside
ok "... to the name Omarchy does not load" "$(cat "$r/usr/lib/omarchy-hyprland-titlebars/titlebars.so.disabled-k114s")" plugin
ok "... and a second run finds nothing to load" "$(run "$r" hyprland-m5 --disarm; grep -c 'nothing can be loaded' "$BASE/out")" "0
1"
r=$(mk hyprland-a); ok "channel plugin beside hyprland-m5: mismatch" "$(run "$r" hyprland-m5)" 1
ok "... --disarm moves it aside" "$(run "$r" hyprland-m5 --disarm; armed "$r")" "0
aside"
r=$(mk hyprland-a); ok "channel plugin beside the channel's hyprland: ok" "$(run "$r" hyprland)" 0
ok "... and --disarm leaves it armed" "$(run "$r" hyprland --disarm; armed "$r")" "0
armed"
r=$(mk hyprland-b "$A"); ok "a stale stamp beside the channel's hyprland: mismatch" "$(run "$r" hyprland)" 1
r=$(mk hyprland-a "$A"); rm "$r/usr/lib/omarchy-hyprland-titlebars/titlebars.so"; ok "no plugin installed: ok" "$(run "$r" hyprland-m5 --disarm)" 0
r=$(mk hyprland-a "$A"); rm "$r/usr/bin/Hyprland"; ok "no Hyprland installed: ok, nothing moved" "$(run "$r" hyprland-m5 --disarm; armed "$r")" "0
armed"
r=$(mk hyprland-a "$A"); echo not-elf > "$r/usr/bin/Hyprland"; ok "Hyprland without a build ID: mismatch" "$(run "$r" hyprland-m5)" 1
r=$(mk hyprland-a "$A"); ok "unknown argument: refused" "$(run "$r" hyprland-m5 --arm)" 2
echo "titlebars-abi-check tests: $pass passed, $fail failed"
[ "$fail" = 0 ]
