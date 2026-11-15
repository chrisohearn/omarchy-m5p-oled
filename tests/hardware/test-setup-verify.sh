#!/bin/bash
# Software test of omarchy-mac-setup-verify.sh against a fixture root (no root, no live system):
# a good fixture passes, and each effect it checks turns into a FAIL when removed.
set -u
here=$(cd "$(dirname "$0")" && pwd)
V=$here/omarchy-mac-setup-verify.sh
t=$(mktemp -d "${TMPDIR:-/tmp}/k114s-setup-verify.XXXXXX") || exit 2
trap 'rm -rf "$t"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: got '$2' want '$3'"; fi; }

good() { # a fixture where every effect holds
  local r=$1 h=$1-home
  mkdir -p "$r/usr/lib/omarchy-mac" "$r/usr/share/omarchy-mac/mpv" "$r/etc/mpv" "$r/var/lib/omarchy-mac" \
    "$r/var/lib/omarchy/mac-first-boot" "$r/usr/lib/NetworkManager/conf.d" "$r/usr/lib/systemd/system" \
    "$r/etc/systemd/system/multi-user.target.wants" "$h/.config/systemd/user/graphical-session.target.wants" "$h/.local/state/omarchy"
  printf '#!/bin/bash\nexit 1\n' >"$r/usr/lib/omarchy-mac/wifi-supported"; chmod +x "$r/usr/lib/omarchy-mac/wifi-supported"
  echo 'hwdec=vaapi-copy' >"$r/usr/share/omarchy-mac/mpv/mpv.conf"; cp "$r/usr/share/omarchy-mac/mpv/mpv.conf" "$r/etc/mpv/mpv.conf"
  : >"$r/var/lib/omarchy-mac/speaker-safety-configured"
  echo keyring >"$r/var/lib/omarchy/mac-first-boot/keyring"; echo 'master=x' >"$r/var/lib/omarchy/mac-first-boot/keyring"
  printf '[device]\nwifi.backend=iwd\n' >"$r/usr/lib/NetworkManager/conf.d/20-omarchy-mac-wifi.conf"
  local u; for u in speakersafetyd omarchy-mac-first-boot omarchy-mac-efi-vars; do
    printf '[Service]\nExecStart=/bin/true\n[Install]\nWantedBy=multi-user.target\n' >"$r/usr/lib/systemd/system/$u.service"
    ln -s "/usr/lib/systemd/system/$u.service" "$r/etc/systemd/system/multi-user.target.wants/$u.service"
  done
  echo '--disable-features=Foo,AcceleratedVideoDecoder' >"$h/.config/chromium-flags.conf"
  ln -s /usr/lib/systemd/user/omarchy-asahi-mic.service "$h/.config/systemd/user/graphical-session.target.wants/omarchy-asahi-mic.service"
  : >"$h/.local/state/omarchy/mac-microphone-configured"
}
run() { OMARCHY_MAC_VERIFY_ROOT=$1 OMARCHY_MAC_VERIFY_HOME=$1-home XDG_CONFIG_HOME= XDG_STATE_HOME= SUDO_USER=nobody "$V" 2>&1; }
# fixture() copies a fresh good tree, applies $2 to it, runs the verifier: prints "rc:FAILlines"
case_() { local r; r=$(mktemp -d "$t/case.XXXXXX"); good "$r"; (cd "$r" && eval "$2"); out=$(run "$r"); echo "$?:$(grep -c '^FAIL' <<<"$out")"; }

r=$t/good; good "$r"; out=$(run "$r"); rc=$?
ok "good fixture: exit 0, no FAIL" "$rc:$(grep -c '^FAIL' <<<"$out")" "0:0"
ok "good fixture: the preset marker is a PASS" "$(grep -c '^PASS .*speaker safety: preset applied' <<<"$out")" 1
ok "good fixture: Wi-Fi resume fix is INFO when wifi-supported fails" "$(grep -c '^INFO .*wifi-supported fails' <<<"$out")" 1

ok "quirk line left behind"     "$(case_ x 'mkdir -p etc/modprobe.d; echo "options brcmfmac feature_disable=0x82000" > etc/modprobe.d/brcmfmac.conf')" "1:1"
ok "no speaker-safety marker"   "$(case_ x 'rm var/lib/omarchy-mac/speaker-safety-configured')" "1:1"
ok "first boot still pending"   "$(case_ x 'touch var/lib/omarchy/mac-first-boot/pending')" "1:1"
ok "first boot last-error"      "$(case_ x 'echo broke > var/lib/omarchy/mac-first-boot/last-error')" "1:1"
ok "unit not enabled"           "$(case_ x 'rm etc/systemd/system/multi-user.target.wants/omarchy-mac-first-boot.service')" "1:1"
ok "foreign mpv.conf is only a WARN" "$(case_ x 'echo hwdec=auto-safe > etc/mpv/mpv.conf')" "0:0"
r=$t/flags; good "$r"; echo '--ozone-platform=wayland' >"$r-home/.config/chromium-flags.conf"; out=$(run "$r"); rc=$?
ok "browser flags without the decoder switch" "$rc:$(grep -c '^FAIL .*browser flags' <<<"$out")" "1:1"
r=$t/mic; good "$r"; rm "$r-home/.local/state/omarchy/mac-microphone-configured"; out=$(run "$r"); rc=$?
ok "microphone mapper not marked" "$rc:$(grep -c '^FAIL .*microphone' <<<"$out")" "1:1"

"$V" --bogus >/dev/null 2>&1; ok "bad argument: exit 2" "$?" 2
echo "setup verify tests: $pass passed, $fail failed"
[ "$fail" = 0 ]
