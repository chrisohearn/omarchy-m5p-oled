#!/bin/bash
# Software test of k114s-mic-trial.sh and k114s-mic-analyze.py: logic only, no sound hardware needed.
set -u
here=$(cd "$(dirname "$0")" && pwd); fail=0
ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
bash -n "$here/k114s-mic-trial.sh" && ok "trial script syntax" || bad "trial script syntax"
python3 -I "$here/k114s-mic-analyze.py" --self-test >/dev/null && ok "analyzer self-test" || bad "analyzer self-test"
bash "$here/k114s-mic-trial.sh" --bogus >/dev/null 2>&1; [ $? = 2 ] && ok "unknown flag refused" || bad "unknown flag"
bash "$here/k114s-mic-trial.sh" --secs x >/dev/null 2>&1; [ $? = 2 ] && ok "non-numeric --secs refused" || bad "--secs x"
# the raw array is hidden from PipeWire clients (hide-parent): the raw takes must read the PCM, not a PipeWire node
grep -q '^raw=hw:AppleK114HPAI,0;' "$here/k114s-mic-trial.sh" && ! grep -q 'pw-record --target "\$2" .*--channels "\$3"' "$here/k114s-mic-trial.sh" &&
  ok "raw takes read hw:AppleK114HPAI,0 with arecord (the RawMics node is hidden from clients)" || bad "raw takes still go through a PipeWire node"
if [ ! -d /proc/asound/AppleK114HPAI ]; then
  out=$(bash "$here/k114s-mic-trial.sh" </dev/null 2>&1); rc=$?
  [ $rc = 1 ] && grep -q 'no card AppleK114HPAI' <<<"$out" && ok "no microphone card is a BAD line, exit 1, no prompt" || bad "missing card not reported (rc $rc)"
fi
exit $fail
