#!/bin/bash
# linux/display/k114s-edr-cap in a replica root: install, idempotence, the trial-file clean-up, check, undo, refusals.
# Nothing under the real /etc is written (K114S_ROOT). The real proof is on the Mac after a reboot: appledrm logs
# 'panel EDR capped at 1200 nits' and the eDP-1 EDID has an HDR static metadata block (docs/r3-hdr.md section 8).
#   usage: test-edr-cap.sh [LINUX_DIR]
set -u
. "$(dirname "$0")/r3-lib.sh" "${1:-}"
TOOL=$L/display/k114s-edr-cap; CONF=$L/display/k114s-edr-cap.conf
ok "installer parses and is executable" "$(bash -n "$TOOL" 2>&1; test -x "$TOOL"; echo $?)" "0"
ok "the file sets the cap to 1200 and nothing else" "$(grep -v '^#' "$CONF" | sed '/^$/d')" "options appledrm fw27_panel_edr_max_nits=1200"
X=$BASE/root; M=$X/etc/modprobe.d; mkdir -p "$M"; echo 'options appledrm fw27_panel_vrr=0' > "$M/aurora-m5-vrr.conf"
C=$BASE/compatible; printf 'apple,k114s\0apple,t6050\0apple,arm-platform\0' > "$C"; export K114S_DT_COMPATIBLE=$C
run() { out=$(K114S_ROOT=$X bash "$TOOL" "$@" 2>&1); rc=$?; }
run --check; ok "check before install fails" "$rc" 1
printf '%s\n' '# K114s EDR test (docs/r3-hdr.md section 8): remove after the test' 'options appledrm fw27_panel_edr_max_nits=1200' > "$M/k114s-edr-trial.conf"
run; ok "install: the file is the repository's, mode 644, and the one-boot test file is gone" "$rc $(cmp -s "$CONF" "$M/k114s-edr-cap.conf"; echo $?) $(stat -c %a "$M/k114s-edr-cap.conf") $(test -e "$M/k114s-edr-trial.conf"; echo $?)" "0 0 644 1"
ok "install leaves the VRR mask alone" "$(cat "$M/aurora-m5-vrr.conf")" "options appledrm fw27_panel_vrr=0"
run --check; ok "check after install passes" "$rc" 0
run; ok "install twice: already installed" "$rc $(echo "$out" | grep -c 'already installed')" "0 1"
echo 'options appledrm fw27_panel_edr_max_nits=1600' > "$M/k114s-edr-trial.conf"; run --check
ok "check fails while a test file with another cap is there (it could override 1200)" "$rc $(echo "$out" | grep -c 'sets the cap too')" "1 1"
rm -f "$M/k114s-edr-cap.conf"; run
ok "install refuses while another file sets another cap, and writes nothing" "$rc $(test -e "$M/k114s-edr-cap.conf"; echo $?) $(test -e "$M/k114s-edr-trial.conf"; echo $?)" "1 1 0"
mv "$M/k114s-edr-trial.conf" "$M/50-other.conf"; run; ok "install refuses any other file that sets the cap" "$rc $(test -e "$M/k114s-edr-cap.conf"; echo $?)" "1 1"
printf '# fw27_panel_edr_max_nits=2000 in a comment only\n' > "$M/50-other.conf"; run; ok "a file that only mentions the cap in a comment does not block install" "$rc $(test -e "$M/k114s-edr-cap.conf"; echo $?)" "0 0"; rm -f "$M/50-other.conf"
run --undo; ok "undo removes only its file" "$rc $(test -e "$M/k114s-edr-cap.conf"; echo $?) $(cat "$M/aurora-m5-vrr.conf")" "0 1 options appledrm fw27_panel_vrr=0"
run --undo; ok "undo with nothing installed says so" "$rc $(echo "$out" | grep -c 'nothing to undo')" "0 1"
echo 'options appledrm fw27_panel_edr_max_nits=2000' > "$M/k114s-edr-cap.conf"; run --undo; ok "undo keeps a file this script did not install" "$rc $(test -e "$M/k114s-edr-cap.conf"; echo $?)" "1 0"; rm -f "$M/k114s-edr-cap.conf"
# every modprobe.d directory counts, and a re-created test file counts for check and undo (#169)
mkdir -p "$X/usr/lib/modprobe.d"; echo 'options appledrm fw27_panel_edr_max_nits=1600' > "$X/usr/lib/modprobe.d/zz-vendor.conf"
rm -f "$M/k114s-edr-cap.conf"; run; ok "install refuses a cap set under /usr/lib/modprobe.d" "$rc $(test -e "$M/k114s-edr-cap.conf"; echo $?)" "1 1"
rm -f "$X/usr/lib/modprobe.d/zz-vendor.conf"; run; ok "install works once that file is gone" "$rc" 0
printf '%s\n' '# K114s EDR test (docs/r3-hdr.md section 8): remove after the test' 'options appledrm fw27_panel_edr_max_nits=1200' > "$M/k114s-edr-trial.conf"
run --check; ok "check fails when the one-boot test file is back after install" "$rc $(echo "$out" | grep -c 'sets the cap too')" "1 1"
run --undo; ok "undo with the test file back: says EDR stays on, exit 1" "$rc $(echo "$out" | grep -c 'EDR stays on') $(test -e "$M/k114s-edr-cap.conf"; echo $?)" "1 1 1"
rm -f "$M/k114s-edr-trial.conf"
printf 'apple,j714s\0' > "$BASE/other"; out=$(K114S_ROOT=$X K114S_DT_COMPATIBLE=$BASE/other bash "$TOOL" 2>&1); ok "install refuses a machine that is not an apple,k114s Mac" "$? $(test -e "$M/k114s-edr-cap.conf"; echo $?)" "1 1"
run --bogus; ok "an unknown argument stops" "$rc" 1
if [ "$(id -u)" != 0 ]; then
  out=$(env -u K114S_ROOT bash "$TOOL" 2>&1); ok "install without root and without K114S_ROOT stops" "$? $(echo "$out" | grep -c 'run with sudo')" "1 1"
else echo "SKIPPED the no-root refusal (running as root)"; fi
finish "edr cap tests"
