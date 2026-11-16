#!/bin/bash
# Software test of k114s-bluetooth-check.sh: read-only, finishes without a tty, prints no address.
# It proves the script's own logic only, not the Bluetooth hardware.
set -u
here=$(cd "$(dirname "$0")" && pwd); S=$here/k114s-bluetooth-check.sh
fail=0; ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
bash -n "$S" && ok "syntax" || bad "syntax"
re=$(grep -m1 -o "sed -u -E '[^']*'" "$S" | sed "s/^sed -u -E '//; s/'\$//")
a=AA; red=0
for sep in : _ -; do
  r=$(echo "x $a${sep}bb${sep}CC${sep}01${sep}02${sep}03 y" | sed -E "$re"); [ "$r" = 'x XX:XX:XX:XX:XX:XX y' ] || red=1
done
[ -n "$re" ] && [ $red = 0 ] && ok "redaction covers colon, underscore and dash forms" || bad "redaction"
out=$(timeout 120 setsid bash "$S" </dev/null 2>&1); rc=$?
[ $rc != 124 ] && ok "finishes without a tty (exit $rc)" || bad "hung"
grep -q '^== done: [0-9]* BAD line(s)\|bluetoothctl missing' <<<"$out" && ok "reaches its end line" || bad "no end line"
grep -qE '([0-9A-Fa-f]{2}[:_-]){5}[0-9A-Fa-f]{2}' <<<"$out" && bad "an address-shaped string is in the output" || ok "no address-shaped string of any form in the output"
# a bluetoothctl that hangs must not hang the report
d=$(mktemp -d); printf '#!/bin/sh\nsleep 100\n' >"$d/bluetoothctl"; chmod +x "$d/bluetoothctl"
PATH=$d:$PATH timeout 60 setsid bash "$S" </dev/null >/dev/null 2>&1; [ $? != 124 ] && ok "a hung bluetoothctl is cut off by the timeout" || bad "hung bluetoothctl hangs the report"
rm -rf "$d"
[ $fail = 0 ]
