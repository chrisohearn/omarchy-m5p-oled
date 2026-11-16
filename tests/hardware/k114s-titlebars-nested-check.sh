#!/bin/bash
# SPDX-License-Identifier: MIT
# Owner step for issue #7: run the title-bar plugin's nested test on real TOP and OVERLAY layer
# surfaces, once on the rebuilt +m5 titlebars.so and once on the disabled stock one.
#
#   1. rm ~/.config/k114s-gpu-desktop ; log out and in (CPU-rendered session)
#   2. bash tests/hardware/k114s-titlebars-nested-check.sh PACKAGE-FILE [STOCK-SO]
#   3. touch ~/.config/k114s-gpu-desktop ; log out and in again (GPU desktop back)
#
# Only for an r3a (CPU-rendered) session: an r3b/DCP boot renders on the GPU through the separate
# k114s-gpu-desktop-r3b opt-in, so the script refuses while that file exists too.
# PACKAGE-FILE: the omarchy-hyprland-titlebars +m5 package (its titlebars.so is unpacked to a temp
# dir, nothing is installed). STOCK-SO defaults to the disabled stock library. Logs and the crash
# report are kept in a directory whose path is printed at the end.
# Pass: rebuild prints "background, top and overlay layer surfaces mapped" and 10 PASS lines;
# the stock build dies with a nested SIGSEGV at the first titlebar press. Read-only for the
# system: a nested window appears for about half a minute per run.
set -u
here=$(cd "$(dirname "$0")" && pwd)
nested=$here/../../packaging/omarchy-hyprland-titlebars-m5/nested-test.sh
pkg=${1:?usage: $0 PACKAGE-FILE [STOCK-SO]}
stock=${2:-/usr/lib/omarchy-hyprland-titlebars/titlebars.so.disabled-k114s}
[[ ! -e $HOME/.config/k114s-gpu-desktop && ! -e $HOME/.config/k114s-gpu-desktop-r3b ]] || { echo "GPU desktop marker present: remove it and log in again first (see header)" >&2; exit 2; }
[[ -f $stock ]] || { echo "stock library $stock not found" >&2; exit 2; }
info=$(pacman -Qp "$pkg") || { echo "pacman cannot read $pkg" >&2; exit 2; }
[[ $info == "omarchy-hyprland-titlebars "*+m5-* ]] || { echo "$pkg is '$info', not the +m5 rebuild" >&2; exit 2; }
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
keep=$(mktemp -d -t titlebars-nested-check.XXXXXX)
tar -xf "$pkg" -C "$work" usr/lib/omarchy-hyprland-titlebars/titlebars.so || { echo "cannot unpack titlebars.so from $pkg" >&2; exit 2; }
fail=0
echo "== rebuild =="
bash "$nested" "$work/usr/lib/omarchy-hyprland-titlebars/titlebars.so" --artifacts "$keep/a-rebuild" 2>&1 | tee "$keep/rebuild.log"
rc=${PIPESTATUS[0]}
grep -q 'background, top and overlay layer surfaces mapped' "$keep/rebuild.log" || { echo "FAIL: layer-surface line missing"; fail=1; }
n=$(grep -c '^PASS' "$keep/rebuild.log"); [[ $rc == 0 && $n == 10 ]] || { echo "FAIL: rebuild rc=$rc PASS=$n (want 0 and 10)"; fail=1; }
echo "== stock (expected to crash the nested instance) =="
bash "$nested" "$stock" --artifacts "$keep/a-stock" > "$keep/stock.log" 2>&1
src=$?
tail -15 "$keep/stock.log"
# a plain nonzero exit is not enough: a verifier FAIL would also do; demand the nested crash itself
[[ $src != 0 ]] && grep -q 'the nested Hyprland crashed' "$keep/stock.log" || { echo "FAIL: stock build did not crash the nested Hyprland (rc=$src)"; fail=1; }
echo "logs and crash report kept in $keep"
((fail)) && { echo "RESULT: FAIL"; exit 1; }
echo "RESULT: OK (paste the output into issue #7)"
