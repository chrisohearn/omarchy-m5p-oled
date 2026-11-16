#!/bin/bash
# SPDX-License-Identifier: MIT
# Owner step for issue #7: run the title-bar plugin's nested test on real TOP and OVERLAY layer
# surfaces, once on the rebuilt +m5 titlebars.so and once on the disabled stock one.
#
#   1. rm ~/.config/k114s-gpu-desktop ; log out and in (CPU-rendered session)
#   2. bash tests/hardware/k114s-titlebars-nested-check.sh PACKAGE-FILE [STOCK-SO]
#   3. touch ~/.config/k114s-gpu-desktop ; log out and in again (GPU desktop back)
#
# PACKAGE-FILE: the omarchy-hyprland-titlebars +m5 package (its titlebars.so is unpacked to a temp
# dir, nothing is installed). STOCK-SO defaults to the disabled stock library.
# Pass: rebuild prints "background, top and overlay layer surfaces mapped" and 10 PASS lines;
# the stock build dies with a nested SIGSEGV at the first titlebar press. Read-only for the
# system: a nested window appears for about half a minute per run.
set -u
here=$(cd "$(dirname "$0")" && pwd)
nested=$here/../../packaging/omarchy-hyprland-titlebars-m5/nested-test.sh
pkg=${1:?usage: $0 PACKAGE-FILE [STOCK-SO]}
stock=${2:-/usr/lib/omarchy-hyprland-titlebars/titlebars.so.disabled-k114s}
[[ ! -e $HOME/.config/k114s-gpu-desktop ]] || { echo "GPU desktop marker present: remove it and log in again first (see header)" >&2; exit 2; }
[[ -f $stock ]] || { echo "stock library $stock not found" >&2; exit 2; }
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
tar -xf "$pkg" -C "$work" usr/lib/omarchy-hyprland-titlebars/titlebars.so || { echo "cannot unpack titlebars.so from $pkg" >&2; exit 2; }
fail=0
echo "== rebuild =="
bash "$nested" "$work/usr/lib/omarchy-hyprland-titlebars/titlebars.so" --artifacts "$work/a-rebuild" 2>&1 | tee "$work/rebuild.log"
rc=${PIPESTATUS[0]}
grep -q 'background, top and overlay layer surfaces mapped' "$work/rebuild.log" || { echo "FAIL: layer-surface line missing"; fail=1; }
n=$(grep -c '^PASS' "$work/rebuild.log"); [[ $rc == 0 && $n == 10 ]] || { echo "FAIL: rebuild rc=$rc PASS=$n (want 0 and 10)"; fail=1; }
echo "== stock (expected to crash the nested instance) =="
bash "$nested" "$stock" --artifacts "$work/a-stock" 2>&1 | tail -15
src=${PIPESTATUS[0]}
[[ $src != 0 ]] || { echo "FAIL: stock build did not fail"; fail=1; }
((fail)) && { echo "RESULT: FAIL"; exit 1; }
echo "RESULT: OK (paste the output into issue #7)"
