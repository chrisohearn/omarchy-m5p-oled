#!/bin/bash
# linux/power/k114s-upower-percentage and its drop-in, in a replica root: install, idempotence, check, undo, refusals.
# Nothing under the real /etc is written and upower is not restarted (K114S_ROOT). The real proof is on the Mac: after the
# install, UPower's percentage equals /sys/class/power_supply/macsmc-battery/capacity (docs/r3-power.md, issue #152).
#   usage: test-upower-percentage.sh [LINUX_DIR]
set -u
. "$(dirname "$0")/r3-lib.sh" "${1:-}"
P=$L/power; TOOL=$P/k114s-upower-percentage; CONF=$P/50-k114s-upower-percentage.conf; NAMEF=$P/upower-product-name
ok "installer parses and is executable" "$(bash -n "$TOOL" 2>&1; test -x "$TOOL"; echo $?)" "0"
ok "the name UPower sees does not start with MacBook (is_macbook)" "$(head -n 1 "$NAMEF" | grep -c '^MacBook')" 0
ok "the drop-in binds the name file over the DMI product name, ignored if missing" "$(grep -c -x 'BindReadOnlyPaths=-/etc/omarchy-k114s/upower-product-name:/sys/devices/virtual/dmi/id/product_name' "$CONF") $(grep -c -x '\[Service\]' "$CONF")" "1 1"
if command -v systemd-analyze >/dev/null; then
  u=$BASE/unit; mkdir -p "$u/upower.service.d"; printf '[Service]\nExecStart=/bin/true\n' > "$u/upower.service"; cp "$CONF" "$u/upower.service.d/"
  ok "systemd parses the drop-in (no unknown key)" "$(SYSTEMD_UNIT_PATH=$u systemd-analyze verify "$u/upower.service" 2>&1 | grep -c -i -E 'unknown|invalid|failed to parse')" 0
fi
X=$BASE/root; DC=$X/etc/systemd/system/upower.service.d/${CONF##*/}; DN=$X/etc/omarchy-k114s/upower-product-name
mkdir -p "$X/etc/systemd/system/upower.service.d" "$X/etc/omarchy-k114s"; echo keep > "$X/etc/systemd/system/upower.service.d/10-other.conf"; echo keep > "$X/etc/omarchy-k114s/stage2-trial"
C=$BASE/compatible; printf 'apple,k114s\0apple,t6050\0apple,arm-platform\0' > "$C"; export K114S_DT_COMPATIBLE=$C
run() { out=$(K114S_ROOT=$X bash "$TOOL" "$@" 2>&1); rc=$?; }
run --check; ok "check before install fails" "$rc" 1
run; ok "install: exit 0, both files are the repository's, mode 644" "$rc $(cmp -s "$CONF" "$DC"; echo $?) $(cmp -s "$NAMEF" "$DN"; echo $?) $(stat -c %a "$DC") $(stat -c %a "$DN")" "0 0 0 644 644"
run --check; ok "check after install passes" "$rc $(echo "$out" | grep -c 'installed')" "0 1"
run; ok "install twice: already installed, and the restart is tried again" "$rc $(echo "$out" | grep -c 'already installed; upower restarted')" "0 1"
echo '# edited' >> "$DC"; run --check; ok "check: an edited drop-in is not installed" "$rc" 1
run; ok "install replaces an edited drop-in" "$rc $(cmp -s "$CONF" "$DC"; echo $?)" "0 0"
run --undo; ok "undo removes both files and nothing else" "$rc $(test -e "$DC"; echo $?) $(test -e "$DN"; echo $?) $(cat "$X/etc/systemd/system/upower.service.d/10-other.conf") $(cat "$X/etc/omarchy-k114s/stage2-trial")" "0 1 1 keep keep"
run --undo; ok "undo with nothing installed says so, and the restart is tried again" "$rc $(echo "$out" | grep -c 'nothing to undo; upower restarted')" "0 1"
printf 'apple,j714s\0apple,t6050\0' > "$BASE/other"; out=$(K114S_ROOT=$X K114S_DT_COMPATIBLE=$BASE/other bash "$TOOL" 2>&1)
ok "install refuses a machine that is not an apple,k114s Mac and writes nothing" "$? $(test -e "$DC"; echo $?) $(test -e "$DN"; echo $?)" "1 1 1"
out=$(K114S_ROOT=$X K114S_DT_COMPATIBLE=$BASE/none bash "$TOOL" 2>&1); ok "install refuses a machine with no device tree (an Intel MacBook)" "$?" 1
mkdir -p "$(dirname "$DC")"; echo '[Service]' > "$DC"; run --undo; ok "undo keeps a drop-in this script did not install" "$rc $(test -e "$DC"; echo $?)" "1 0"; rm -f "$DC"
cp -r "$P" "$BASE/p2"; printf 'MacBook Pro\n' > "$BASE/p2/upower-product-name"
out=$(K114S_ROOT=$X bash "$BASE/p2/k114s-upower-percentage" 2>&1); ok "install refuses a name that starts with MacBook" "$? $(test -e "$DN"; echo $?)" "1 1"
run --bogus; ok "an unknown argument stops" "$rc" 1
# as root this would be a real install, so it runs only for a plain user
if [ "$(id -u)" != 0 ]; then
  out=$(env -u K114S_ROOT bash "$TOOL" 2>&1); ok "install without root and without K114S_ROOT stops" "$? $(echo "$out" | grep -c 'run with sudo')" "1 1"
else echo "SKIPPED the no-root refusal (running as root: it would install for real)"; fi
finish "upower percentage tests"
