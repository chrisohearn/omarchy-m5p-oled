#!/bin/bash
# Software test of k114s-wifi-check.sh with stubbed iw, ip, ping, systemctl and journalctl on PATH
# (no radio, no root, no journal). It proves the script's own logic: band decision, gateway check,
# failure detection from the kernel and iwd sources, resume windowing and redaction.
set -u
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d) || exit 2
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
mkdir "$t/bin"

cat >"$t/bin/iw" <<'S'
#!/bin/bash
[[ $* == "dev wlan0 link" && -n ${FAKE_FREQ:-} ]] && printf 'Connected\n\tfreq: %s\n' "$FAKE_FREQ"
exit 0
S
cat >"$t/bin/ip" <<'S'
#!/bin/bash
echo "default via 192.0.2.1 dev wlan0"
S
cat >"$t/bin/ping" <<'S'
#!/bin/bash
[[ ${FAKE_PING:-ok} == ok ]]
S
# journalctl stub: -k reads $FAKE_KERNEL, -u iwd reads $FAKE_IWD; files hold "unixtime|text".
# -k together with -u prints nothing, like the real tool. -o short-unix prefixes the time.
cat >"$t/bin/journalctl" <<'S'
#!/bin/bash
k=0 u=0 unix=0 since=0
while (($#)); do
  case $1 in -k) k=1 ;; -u) u=1; shift ;; -o) [[ $2 == short-unix ]] && unix=1; shift ;; --since) since=${2#@}; shift ;; esac
  shift
done
((k && u)) && exit 0
f=$FAKE_KERNEL; ((u)) && f=$FAKE_IWD
[[ -f $f ]] || exit 0
awk -F'|' -v unix=$unix -v since="$since" '$1 >= since { if (unix) printf "%s.0 host kernel: %s\n", $1, $2; else print $2 }' "$f"
S
echo '#!/bin/bash' >"$t/bin/systemctl"
chmod +x "$t"/bin/*

run() { # mode -> output, rc in $rc
  out=$(PATH="$t/bin:$PATH" "$here/k114s-wifi-check.sh" "$@" 2>&1); rc=$?
}
export FAKE_KERNEL=$t/kernel FAKE_IWD=$t/iwd
: >"$t/kernel"; : >"$t/iwd"

# 1. 6 GHz link, gateway up, clean journal: PASS
FAKE_FREQ=6115 run 6ghz
[[ $rc -eq 0 && $out == *"RESULT: PASS"* ]] && ok "6 GHz clean passes" || bad "6 GHz pass: rc=$rc $out"

# 2. 5 GHz link: FAIL
FAKE_FREQ=5180 run 6ghz
[[ $rc -eq 1 && $out == *"not 6 GHz"* ]] && ok "5 GHz link fails" || bad "5 GHz: rc=$rc"

# 3. silent gateway: FAIL
FAKE_FREQ=6115 FAKE_PING=no run 6ghz
[[ $rc -eq 1 && $out == *"gateway does not answer"* ]] && ok "silent gateway fails" || bad "gateway: rc=$rc"

# 4. firmware-dead line in the kernel source, and a SAE failure in the iwd source: each FAILs
mac=$(printf "%s:" aa BB cc dd ee ff); mac=${mac%:}  # built at run time: no MAC literal in the source
echo "100|brcmfmac: firmware dead at $mac" >"$t/kernel"
FAKE_FREQ=6115 run 6ghz
[[ $rc -eq 1 && $out == *"1 failure line"* ]] && ok "kernel firmware failure fails" || bad "kernel failure: rc=$rc $out"
[[ $out == *"<mac>"* && $out != *"BB:cc"* ]] && ok "uppercase MAC redacted" || bad "MAC not redacted: $out"
: >"$t/kernel"; echo '100|SAE auth failed for "HomeNet" 198.51.100.7' >"$t/iwd"
FAKE_FREQ=6115 run 6ghz
[[ $rc -eq 1 && $out == *"<ip>"* && $out == *"<name>"* && $out != *HomeNet* && $out != *198.51* ]] && ok "iwd failure fails, name and IP redacted" || bad "iwd failure: rc=$rc $out"
: >"$t/iwd"

# 5. resume: no resume logged is a FAIL
FAKE_FREQ=5180 run resume
[[ $rc -eq 1 && $out == *"no suspend/resume logged"* ]] && ok "no resume fails" || bad "no resume: rc=$rc $out"

# 6. resume: a failure before the resume is ignored, one after it fails
printf '50|wlan reset after firmware crash\n200|PM: suspend exit\n' >"$t/kernel"
FAKE_FREQ=5180 run resume
[[ $rc -eq 0 && $out == *"RESULT: PASS"* ]] && ok "failure before resume ignored" || bad "pre-resume failure: rc=$rc $out"
echo "300|firmware timeout" >>"$t/kernel"
FAKE_FREQ=5180 run resume
[[ $rc -eq 1 && $out == *"since the last resume"* ]] && ok "failure after resume fails" || bad "post-resume failure: rc=$rc $out"

# 7. arguments
PATH="$t/bin:$PATH" "$here/k114s-wifi-check.sh" nonsense >/dev/null 2>&1; [[ $? -eq 2 ]] && ok "unknown mode refused" || bad "unknown mode accepted"

[[ $fail -eq 0 ]] && echo "wifi-check test: passed" || echo "wifi-check test: FAILED"
exit $fail
