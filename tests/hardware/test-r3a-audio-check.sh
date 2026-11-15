#!/bin/bash
# Software test of k114s-r3a-audio-check.sh. The unattended part is read-only, so it runs on whatever kernel
# is running: it must finish, never prompt, write nothing under HOME with --no-save,
# print no MAC address, refuse bad arguments, and report a kernel that is not the r3a kernel as BAD.
# It proves the script's own logic only, not the sound or Bluetooth hardware.
set -u
here=$(cd "$(dirname "$0")" && pwd); S=$here/k114s-r3a-audio-check.sh
fail=0; ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
bash -n "$S" && ok "syntax" || bad "syntax"
bash "$S" --bogus >/dev/null 2>&1; [ $? = 2 ] && ok "an unknown flag is refused" || bad "unknown flag accepted"
bash "$S" --play >/dev/null 2>&1; [ $? = 2 ] && ok "--play without --listen is refused" || bad "--play alone accepted"
out=$(timeout 120 bash "$S" --no-save </dev/null 2>&1); rc=$?
case $(uname -r) in
  *k114s-r3a-ARCH) [ $rc = 0 ] || [ $rc = 1 ] && ok "runs to the end on the r3a kernel (exit $rc)" || bad "exit $rc" ;;
  *) [ $rc = 1 ] && grep -q '^BAD     running kernel is' <<<"$out" && ok "a kernel that is not r3a is a BAD line and exit 1" || bad "wrong kernel not reported (exit $rc)" ;;
esac
grep -q '^== 5. summary' <<<"$out" && ok "the unattended report reaches its summary" || bad "no summary"
grep -qE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' <<<"$out" && bad "an address-shaped string is in the output" || ok "no address-shaped string in the output"
# the script's own redaction expression, applied to samples built at run time (no address-shaped literal in this file)
re=$(grep -m1 -o "sed -u -E '[^']*'" "$S" | sed "s/^sed -u -E '//; s/'\$//")
a=AA; red=0
for sep in : _ -; do
  r=$(echo "x $a${sep}bb${sep}CC${sep}01${sep}02${sep}03 y" | sed -E "$re"); [ "$r" = 'x XX:XX:XX:XX:XX:XX y' ] || red=1
done
[ -n "$re" ] && [ $red = 0 ] && ok "redaction covers colon, underscore and dash forms" || bad "redaction"
grep -qE '([0-9A-Fa-f]{2}[:_-]){5}[0-9A-Fa-f]{2}' <<<"$out" && bad "an address-shaped string (any separator) is in the output" || ok "no address-shaped string of any form in the output"
# --no-save writes nothing under HOME; the unattended path never prompts (no controlling tty, so a prompt would fail or hang)
h=$(mktemp -d); HOME=$h timeout 120 setsid bash "$S" --no-save </dev/null >/dev/null 2>&1; rc=$?
[ -z "$(ls -A "$h")" ] && ok "--no-save leaves HOME empty" || bad "--no-save wrote into HOME"
[ $rc != 124 ] && ok "the unattended run finishes without a tty (exit $rc)" || bad "the unattended run hung (a prompt?)"
rm -rf "$h"
[ $fail = 0 ]
