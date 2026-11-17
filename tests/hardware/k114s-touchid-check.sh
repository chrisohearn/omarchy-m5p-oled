#!/bin/bash
# k114s-touchid-check.sh: where does Touch ID stand on this Mac? READ ONLY (issue #49, docs/r3-touchid.md).
#
#   bash tests/hardware/k114s-touchid-check.sh
#   (run it as your user; no root needed)
#
# Never loads apple_sep, never opens /dev/sep-bio, never writes enclave or xART state, never touches the
# iBoot System Container. Prints one line per fact, "state:" lines for what is missing. Exit 0 always:
# this is a status report, not a gate.
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
dt=/proc/device-tree
say() { printf '%-9s %s\n' "$1" "$2"; }
txt() { tr '\0' ' ' <"$1" 2>/dev/null; }

sensor=""
for n in "$dt"/soc/*/fingerprint@* "$dt"/soc@*/*/fingerprint@*; do [ -e "$n/compatible" ] && sensor=$n; done
if [ -n "$sensor" ]; then say ok "booted tree has a sensor node: apple,mesa-fingerprint"; else say state: "booted tree has no sensor node (boot the trial tree dts/t6050-k114s-r3b-touchid.dts: docs/r3-touchid.md, phase 3)"; fi
spi=$(ls -d "$dt"/soc/spi@505108000 2>/dev/null)
[ -n "$spi" ] && say info "spi2 node present, status: $(txt "$spi/status")"
nub=$(ls -d "$dt"/soc/pinctrl@2881e4000 2>/dev/null)
[ -n "$nub" ] && say info "nub-gpio0 node present, status: $(txt "$nub/status")"
sepn=$(ls -d "$dt"/soc@*/sep@502600000 2>/dev/null | head -1)
[ -n "$sepn" ] && say info "sep node present, status: $(txt "$sepn/status")"
if [ -e "$dt/aliases/sep" ]; then say ok "/aliases/sep exists"; else say state: "no /aliases/sep (m1n1 finds the SEP through it)"; fi
[ -e "$dt/chosen/apfs-preboot-uuid" ] && say ok "/chosen/apfs-preboot-uuid is present (value not read)" || say state: "no /chosen/apfs-preboot-uuid"

m=$(modinfo -n apple_sep 2>/dev/null)
if [ -n "$m" ]; then
  case $m in *.zst) rd='zstd -dc' ;; *.xz) rd='xz -dc' ;; *) rd=cat ;; esac
  if $rd "$m" 2>/dev/null | strings | grep -q 'apple,k114s'; then say ok "installed apple_sep admits apple,k114s"
  else say state: "installed apple_sep does not name apple,k114s (T6050 profile: j714s and k116s only); it would refuse this Mac: install r3b.c4 (patches/linux/sep/0001)"; fi
else say state: "no apple_sep module installed"; fi
if lsmod | grep -q '^apple_sep'; then say info "apple_sep is loaded"; else say info "apple_sep is not loaded (nothing loads it by itself)"; fi
[ -e /var/lib/aurora-sep-keybag.bin ] && say info "a Linux identity keybag exists" || say info "no Linux identity keybag (nothing has written enclave state)"

e=/usr/lib/omarchy-mac/touchid-eligibility
[ -x $e ] && say info "omarchy-mac touchid-eligibility says: $($e)"
echo "done: nothing was written."
