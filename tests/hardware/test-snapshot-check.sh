#!/bin/bash
# Tests the budget arithmetic of k114s-snapshot-check.sh (no system access).
set -u
here=$(cd "$(dirname "$0")" && pwd)
out=$(bash "$here/k114s-snapshot-check.sh" budget 523132928 412110848 79420416 79253504)
fail=0
check() { grep -q "$1" <<<"$out" || { echo "FAIL: missing: $1"; fail=1; }; }
check 'free=111022080'
check 'after 1 snapshot UKI(s).*94.0% used.*OVER the 85% limit.*pacman guard BLOCKS'
check 'after 2 snapshot UKI(s).*109.1% used'
out=$(bash "$here/k114s-snapshot-check.sh" budget 1000000000 100000000 50000000)
grep -q 'under the 85% limit; pacman guard ok' <<<"$out" || { echo "FAIL: roomy case"; fail=1; }
bash "$here/k114s-snapshot-check.sh" bogus >/dev/null 2>&1; [ $? -eq 2 ] || { echo "FAIL: usage"; fail=1; }
[ $fail -eq 0 ] && echo "ok"; exit $fail
