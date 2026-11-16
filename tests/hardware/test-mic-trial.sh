#!/bin/bash
# Software test of k114s-mic-trial.sh and k114s-mic-analyze.py: logic only, no sound hardware needed.
set -u
here=$(cd "$(dirname "$0")" && pwd); fail=0
ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
bash -n "$here/k114s-mic-trial.sh" && ok "trial script syntax" || bad "trial script syntax"
python3 -I "$here/k114s-mic-analyze.py" --self-test >/dev/null && ok "analyzer self-test" || bad "analyzer self-test"
bash "$here/k114s-mic-trial.sh" --bogus >/dev/null 2>&1; [ $? = 2 ] && ok "unknown flag refused" || bad "unknown flag"
bash "$here/k114s-mic-trial.sh" --secs x >/dev/null 2>&1; [ $? = 2 ] && ok "non-numeric --secs refused" || bad "--secs x"
if [ ! -d /proc/asound/AppleK114HPAI ]; then
  out=$(bash "$here/k114s-mic-trial.sh" </dev/null 2>&1); rc=$?
  [ $rc = 1 ] && grep -q 'no card AppleK114HPAI' <<<"$out" && ok "no microphone card is a BAD line, exit 1, no prompt" || bad "missing card not reported (rc $rc)"
fi
exit $fail
