#!/bin/bash
# K114s (omarchy-m5p-oled): STAGE B, step 1 and 2. Collect THIS Mac's own speaker tuning, read-only,
# and read it offline. SILENT: it opens no sound device, enables no amplifier, switches no protection
# daemon (collect only; no `run`, no `--revert`) and installs nothing. Root is needed to read the Apple
# device tree partition and the macOS System volume. Run it by hand; nothing runs it.
#
#     sudo bash linux/audio/stage-b-collect.sh [--out DIR]       (default /root/k114s-tuning, must not exist)
#
# The result is Apple's data: it stays in a root-only directory (mode 700), never in git, never in a
# bug report. This script prints only what the tuning reader says about it (unit types, verdicts).
# It does NOT qualify the speakers and it does NOT make the gate pass: the protection research
# (docs/r3-audio-protection.md) found the missing piece is upstream's, not data on this Mac.
set -uo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
OUT=/root/k114s-tuning
while [[ $# -gt 0 ]]; do
  case "$1" in --out) OUT=${2:?--out needs a directory}; shift ;; *) echo "usage: stage-b-collect.sh [--out DIR]" >&2; exit 2 ;; esac
  shift
done
die() { echo "stage-b-collect: $*" >&2; exit 1; }
[[ $(id -u) == 0 ]] || die "needs root (reads the adt partition and the macOS System volume); run with sudo"
grep -zFxq 'apple,k114s' /sys/firmware/devicetree/base/compatible 2>/dev/null || die "this is not an apple,k114s Mac"
[[ ! -e $OUT ]] || die "$OUT exists; choose a new directory"
command -v aurora-speaker-upgrade >/dev/null && command -v aurora-speaker-tuning >/dev/null || die "aurora-speaker-upgrade / aurora-speaker-tuning not installed"

# nothing may be able to reach the speakers while we do this; the readiness report says so
bash "$HERE/speaker-readiness.sh" > /dev/null; rc=$?
[[ $rc == 3 ]] && die "speaker-readiness.sh reports a TRIPWIRE: run it by hand, fix that first"

umask 077
export AURORA_LZFSE_LIB=${AURORA_LZFSE_LIB:-/usr/lib/omarchy-aurora/liblzfse.so.1}
echo "== collecting (route 1: the unencrypted macOS System volume and the device tree), read-only"
aurora-speaker-upgrade collect --out "$OUT" --route 1; c=$?
echo "== collect exit status: $c"
[[ -d $OUT ]] && chmod 700 "$OUT"
if [[ $c != 0 ]]; then
  echo "== collect did not finish. If it says the lsm2 fill is missing, boot macOS once and follow:"
  echo "     aurora-speaker-upgrade guide"
  echo "   then re-run with --route 3 --collection FILE (see docs/r3-audio.md, Stage B)."
  exit $c
fi
echo "== reading the bundle offline (names and verdicts only)"
for sub in identify validate "voicing-check --attestations /usr/share/speakerguardd/parity.json"; do
  echo "-- aurora-speaker-tuning $sub"
  # shellcheck disable=SC2086
  aurora-speaker-tuning $sub "$OUT"; echo "   exit status: $?"
done
echo "== done. Keep $OUT root-only. Next: docs/r3-audio.md, Stage B, step 3 onwards. Nothing was enabled."
