#!/bin/bash
# Software test of k114s-parity-check.sh: the exit status follows the BAD lines. Stubs stand in for dmesg and lspci.
set -u
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d) || exit 2
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
mkdir "$t/bin"
printf '#!/bin/sh\necho "apple-pcie: port 1 link timeout"\n' >"$t/bin/dmesg"
printf '#!/bin/sh\necho "00:00.0 SD Host controller: Genesys Logic GL9755"\n' >"$t/bin/lspci"
chmod +x "$t/bin/dmesg" "$t/bin/lspci"
out=$(PATH=$t/bin:$PATH "$here/k114s-parity-check.sh" sd 2>&1); rc=$?
[[ $rc -eq 1 && $out == *"BAD   dmesg: apple-pcie: port 1 link timeout"* ]] && ok "a BAD dmesg line gives exit 1" || { bad "dmesg BAD (rc=$rc)"; echo "$out"; }
exit $fail
