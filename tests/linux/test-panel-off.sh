#!/bin/bash
# linux/display/k114s-panel-off against a throw-away config folder with a stand-in systemctl and hypridle: install, idempotence,
# check, a changed config, a missing hypridle, undo; and the config's settings (5 minutes, the proven DPMS commands, systemd
# inhibitors ignored, Wayland and D-Bus inhibitors honoured).
#   usage: test-panel-off.sh [LINUX_DIR]
set -u
. "$(dirname "$0")/r3-lib.sh" "${1:-}"
S=$L/display/k114s-panel-off; C=$BASE/config; export K114S_CONFIG_DIR=$C
mkdir -p "$BASE/bin"; st=$BASE/units; mkdir -p "$st"
cat > "$BASE/bin/systemctl" <<EOF
#!/bin/bash
# stand-in for systemctl --user: enable/disable/restart/is-enabled/is-active on files in $st
[ "\$1" = --user ] && shift
case \$1 in
  daemon-reload) exit 0 ;;
  enable) touch "$st/\$2.enabled" ;;
  disable) shift; [ "\$1" = --now ] && shift; rm -f "$st/\$1.enabled" "$st/\$1.active" ;;
  restart) [ -e "$BASE/fail-start" ] && exit 1; touch "$st/\$2.active" ;;
  is-enabled) [ -e "$st/\$2.enabled" ] && echo enabled || { echo disabled; exit 1; } ;;
  is-active) [ -e "$st/\$2.active" ] && echo active || { echo inactive; exit 3; } ;;
esac
EOF
chmod +x "$BASE/bin/systemctl"; printf '#!/bin/sh\n' > "$BASE/bin/hypridle"; chmod +x "$BASE/bin/hypridle"
export K114S_SYSTEMCTL=$BASE/bin/systemctl K114S_HYPRIDLE=$BASE/bin/hypridle
conf=$C/hypr/k114s-panel-off.conf; unit=$C/systemd/user/k114s-panel-off.service
bash -n "$S"; ok "the script parses" $? 0
bash "$S" --check >/dev/null 2>&1; ok "check before install fails" $? 1
out=$(bash "$S" 2>&1); ok "install exits 0 and --check passes" "$? $(bash "$S" --check >/dev/null 2>&1; echo $?)" "0 0"
ok "config and unit are the repository's" "$(cmp -s "$L/display/k114s-panel-off.conf" "$conf"; echo $?) $(cmp -s "$L/display/k114s-panel-off.service" "$unit"; echo $?)" "0 0"
ok "the unit is enabled and running" "$(test -e "$st/k114s-panel-off.service.enabled"; echo $?) $(test -e "$st/k114s-panel-off.service.active"; echo $?)" "0 0"
bash "$S" >/dev/null 2>&1; ok "a second install changes nothing and passes" "$? $(cmp -s "$L/display/k114s-panel-off.conf" "$conf"; echo $?)" "0 0"
echo '# edited' >> "$conf"; bash "$S" --check >/dev/null 2>&1; ok "a changed config is not 'installed'" $? 1
bash "$S" >/dev/null 2>&1; ok "install puts the repository's config back" "$(cmp -s "$L/display/k114s-panel-off.conf" "$conf"; echo $?)" 0
rm "$st/k114s-panel-off.service.active"; bash "$S" --check >/dev/null 2>&1; ok "a stopped unit is not 'installed'" $? 1
bash "$S" >/dev/null 2>&1
touch "$BASE/fail-start"; rm "$st/k114s-panel-off.service.active"; bash "$S" >/dev/null 2>&1; ok "a unit that cannot start makes install fail" $? 1; rm "$BASE/fail-start"
K114S_HYPRIDLE=$BASE/bin/nope bash "$S" >/dev/null 2>&1; ok "no hypridle: install refuses" $? 1
bash "$S" --undo >/dev/null 2>&1; ok "undo removes both files and the unit" "$? $(test -e "$conf"; echo $?) $(test -e "$unit"; echo $?) $(test -e "$st/k114s-panel-off.service.enabled"; echo $?)" "0 1 1 1"
bash "$S" --bogus >/dev/null 2>&1; ok "an unknown option fails" $? 1
# the settings
cf=$L/display/k114s-panel-off.conf
ok "panel off after 300 s" "$(grep -cE '^\s*timeout = 300$' "$cf")" 1
ok "off and on use omarchy-brightness-display (the DPMS path D7 proved)" "$(grep -cE '^\s*on-timeout = omarchy-brightness-display off$' "$cf") $(grep -cE '^\s*on-resume = omarchy-brightness-display on$' "$cf")" "1 1"
ok "systemd inhibitors ignored; Wayland and D-Bus inhibitors not" "$(grep -cE '^\s*ignore_systemd_inhibit = true$' "$cf") $(grep -cE 'ignore_(wayland|dbus)_inhibit = true' "$cf")" "1 0"
ok "the unit runs hypridle with this config only" "$(grep -c '^ExecStart=/usr/bin/hypridle -c %h/.config/hypr/k114s-panel-off.conf$' "$L/display/k114s-panel-off.service")" 1
finish "panel-off tests"
