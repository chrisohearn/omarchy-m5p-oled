#!/bin/bash
# Software test of k114s-bt-audio-check.sh: finishes without a tty, never prompts, writes nothing under HOME
# with --no-save, prints no address-shaped string, refuses bad arguments. Proves the script's logic only.
set -u
S=$(cd "$(dirname "$0")" && pwd)/k114s-bt-audio-check.sh
fail=0; ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
bash -n "$S" && ok "syntax" || bad "syntax"
bash "$S" --bogus >/dev/null 2>&1; [ $? = 2 ] && ok "unknown flag refused" || bad "unknown flag accepted"
h=$(mktemp -d); out=$(HOME=$h timeout 60 setsid bash "$S" --no-save </dev/null 2>&1); rc=$?
[ $rc != 124 ] && ok "finishes without a tty (exit $rc)" || bad "hung"
grep -q '^== done' <<<"$out" && ok "reaches its summary" || bad "no summary"
[ -z "$(ls -A "$h")" ] && ok "--no-save leaves HOME empty" || bad "wrote into HOME"
grep -qE '([0-9A-Fa-f]{2}[:_-]){5}[0-9A-Fa-f]{2}' <<<"$out" && bad "address-shaped string in output" || ok "no address-shaped string"
re=$(grep -m1 -o "sed -u -E '[^']*'" "$S" | sed "s/^sed -u -E '//; s/'\$//"); r=0
for sep in : _ -; do t=$(echo "x AA${sep}bb${sep}CC${sep}01${sep}02${sep}03 y" | sed -E "$re"); [ "$t" = 'x XX:XX:XX:XX:XX:XX y' ] || r=1; done
[ $r = 0 ] && ok "redaction covers three separators" || bad "redaction"
rm -rf "$h"; [ $fail = 0 ] && echo "PASS" || { echo "FAILED"; exit 1; }
