#!/bin/bash
# Compile and run the kernel's own panel-backlight test cases (drivers/gpu/drm/apple/
# dcp_backlight_test.c, which test the pure functions of dcp_backlight.h and dcp-edr.h) as a
# user-space program, with the stand-in headers in kunit-host/.
#
#     tests/brightness/run-dcp-backlight-host.sh KERNEL_TREE [case-name-part]
#
# KERNEL_TREE is a kernel source tree with the series of patches/linux/brightness applied (or
# without it: the upstream cases run just the same). Nothing is written into the tree.
# What a pass means: the level bookkeeping, including the K114s floor (backlight_floor_test),
# behaves as its tests say when compiled for this host. Evidence class: emulator/replica. It
# says nothing about the display coprocessor, the panel, or the kernel build.
set -euo pipefail
tree=${1:?usage: run-dcp-backlight-host.sh KERNEL_TREE [case-name-part]}
here=$(cd "$(dirname "$0")" && pwd)
src=$tree/drivers/gpu/drm/apple
[[ -r $src/dcp_backlight_test.c ]] || { echo "no dcp_backlight_test.c under $src" >&2; exit 2; }
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
${CC:-cc} -std=gnu11 -O1 -Wall -Wno-unused-function \
  -I"$here/kunit-host" -I"$src" -o "$out/dcp-backlight-host" "$src/dcp_backlight_test.c"
"$out/dcp-backlight-host" ${2:+"$2"}
