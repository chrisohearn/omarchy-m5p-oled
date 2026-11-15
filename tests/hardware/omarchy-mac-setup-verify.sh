#!/bin/bash
# Did omarchy-mac-setup-system and omarchy-mac-setup-user leave the effects they should? READ ONLY.
# For the owner (or root) on the K114s. See docs/platform-audit.md, "First boot" (issue #63).
#
#   tests/hardware/omarchy-mac-setup-verify.sh                  no root: everything that needs none
#   sudo tests/hardware/omarchy-mac-setup-verify.sh             adds the root-only reads (logs, iwd profiles)
#   sudo tests/hardware/omarchy-mac-setup-verify.sh --mount-factory
#                                                               also mounts the btrfs top level READ ONLY, temporarily,
#                                                               to compare @factory's kernel with /boot (issue #69)
#
# Run it once with sudo and once without: the per-user checks and the user units need your own session.
# Nothing is written, enabled, started or installed. Output holds counts and verdicts only: no network
# names, keys, addresses or serial numbers (log tails have UUIDs, hex strings and MACs masked).
#
# Lines: PASS / FAIL (an effect that must hold does not) / WARN (differs from the baseline, explained) /
# INFO / NEEDS-ROOT / N/A. Exit 0 unless a line says FAIL; 2 on bad arguments.
#
# OMARCHY_MAC_VERIFY_ROOT points the file checks at a fixture root and turns the live-system checks off;
# only tests/hardware/test-setup-verify.sh sets it.
set -u
mount_factory=0
case "${1:-}" in "") ;; --mount-factory) mount_factory=1 ;; *) echo "usage: $0 [--mount-factory]" >&2; exit 2 ;; esac
ROOT=${OMARCHY_MAC_VERIFY_ROOT:-}; ROOT=${ROOT%/}
live=1; [[ -n $ROOT ]] && live=0
root_ok=0; [[ $EUID -eq 0 || -n $ROOT ]] && root_ok=1
user=${SUDO_USER:-${USER:-}}
home=${OMARCHY_MAC_VERIFY_HOME:-$(getent passwd "$user" | cut -d: -f6)}
config=${XDG_CONFIG_HOME:-$home/.config}; [[ -n ${SUDO_USER:-} ]] && config=$home/.config
nfail=0
say() { printf '%-10s %s\n' "$1" "$2"; }
pass() { say PASS "$1"; }
fail() { say FAIL "$1"; nfail=$((nfail + 1)); }
warn() { say WARN "$1"; }
info() { say INFO "$1"; }
na() { say N/A "$1"; }
needroot() { say NEEDS-ROOT "$1 (run with sudo)"; }
mask() { sed -E 's/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F-]{4,}/<uuid>/g; s/([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/<mac>/g; s/[0-9a-f]{24,}/<hex>/g' | cut -c1-160; }
unit_state() { systemctl --root="${ROOT:-/}" is-enabled "$1" 2>/dev/null; }

echo "== setup-system (omarchy-mac-setup-system, root)"
if (( live )); then
  omarchy-hw-apple-silicon && pass "platform: the Apple Silicon check passes, so the script does its work" ||
    { fail "platform: omarchy-hw-apple-silicon fails, so setup-system exits without doing anything"; exit 1; }
  for p in omarchy-mac omarchy-mac-boot aurora-bless; do
    bad=$(pacman -Qkk "$p" 2>&1 | grep -c -i -E 'warning|error')
    [[ $bad == 0 ]] && pass "package $p: every file present and unaltered" || fail "package $p: $bad altered or missing file(s) (pacman -Qkk $p)"
  done
else
  info "fixture root: live checks (platform, packages, running units) are off"
fi

quirk="options brcmfmac feature_disable=0x82000"
b=$ROOT/etc/modprobe.d/brcmfmac.conf
if [[ -f $b ]] && grep -Fxq -- "$quirk" "$b"; then fail "Intel Mac Broadcom quirk is still in $b (setup removes exactly that line)"
else pass "no Intel Mac Broadcom quirk line in /etc/modprobe.d/brcmfmac.conf"; fi
[[ -e $ROOT/var/lib/omarchy/migrations/1789172112-initramfs-pending ]] &&
  info "initramfs rebuild is owed (migration marker 1789172112-initramfs-pending exists): setup removed the quirk"

mpv=$ROOT/etc/mpv/mpv.conf; shipped=$ROOT/usr/share/omarchy-mac/mpv/mpv.conf
if [[ ! -f $mpv ]]; then info "no /etc/mpv/mpv.conf (tmpfiles copies the omarchy-mac default at boot)"
elif cmp -s "$mpv" "$shipped"; then pass "/etc/mpv/mpv.conf is the omarchy-mac Apple default"
elif [[ $(sha256sum <"$mpv") == "9e186dd88be483b3666795b805e780921adecd1051ae85986857c22152a2d818  -" ]]; then
  fail "/etc/mpv/mpv.conf is the earlier omarchy-mac default (no gpu-sw): setup-system should have replaced it"
else warn "/etc/mpv/mpv.conf is not the omarchy-mac default (another package or an edit owns it), so hwdec=vaapi-copy, vo=gpu and gpu-sw=yes are not in effect; setup only replaces the earlier default byte for byte"; fi

unit=omarchy-wifi-resume-fix.service; marker=$ROOT/var/lib/omarchy-mac/wifi-configured
if "$ROOT/usr/lib/omarchy-mac/wifi-supported" 2>/dev/null; then
  if [[ $(unit_state $unit) == enabled && -f $marker ]]; then pass "Wi-Fi resume fix: enabled and marked configured"
  elif [[ -e $ROOT/etc/systemd/system/$unit || -L $ROOT/etc/systemd/system/$unit ]]; then info "Wi-Fi resume fix: an administrator unit in /etc is kept"
  else fail "Wi-Fi resume fix: the chip is supported, but the unit is not enabled and marked"; fi
else
  [[ -f $marker ]] && warn "Wi-Fi resume fix: marked configured although wifi-supported fails here" ||
    info "Wi-Fi resume fix: wifi-supported fails on this Mac (not a BCM4378/4387/4388), so setup leaves it disabled and unmarked; its ExecCondition keeps it harmless"
fi

sm=$ROOT/var/lib/omarchy-mac/speaker-safety-configured
[[ -f $sm ]] && pass "speaker safety: preset applied once (marker present)" || fail "speaker safety: no marker, setup-system did not apply the preset"
st=$(unit_state speakersafetyd.service)
case $st in enabled|masked*|static) pass "speaker safety: speakersafetyd.service is '$st'" ;; *) fail "speaker safety: speakersafetyd.service is '${st:-missing}'" ;; esac
if [[ -e $ROOT/usr/share/speakersafetyd/apple/k114.conf ]]; then info "speaker safety: a k114 protection profile is installed"
else info "speaker safety: no k114 protection profile; the local drop-in keeps the daemon inactive and the speakers stay muted (docs/r3-audio-protection.md). Not a fault."; fi

if (( live )); then
  nm=$(NetworkManager --print-config 2>/dev/null)
  grep -qx 'wifi.backend=iwd' <<<"$nm" && pass "NetworkManager: wifi.backend=iwd in effect" || fail "NetworkManager: wifi.backend=iwd is not in the effective configuration"
  iwdenv=$(systemctl show iwd.service -p Environment 2>/dev/null)
  if grep -q 'CONFIGURATION_DIRECTORY=/etc/iwd:/usr/lib/omarchy-mac/iwd' <<<"$iwdenv"; then pass "iwd: reads /etc/iwd, then the omarchy-mac default (6 GHz joins off)"
  elif grep -q 'CONFIGURATION_DIRECTORY=/etc/iwd:/usr/lib/omarchy-aurora/iwd-n1' <<<"$iwdenv"; then
    info "iwd: omarchy-aurora-firmware's 30-aurora-n1-6ghz.conf replaces the omarchy-mac default on purpose (N1: 6 GHz joins on)"
  else fail "iwd: neither the omarchy-mac nor the omarchy-aurora default directory is in the unit's environment"; fi
else
  grep -qx 'wifi.backend=iwd' "$ROOT/usr/lib/NetworkManager/conf.d/20-omarchy-mac-wifi.conf" 2>/dev/null && pass "NetworkManager: package conf selects iwd" || fail "NetworkManager: package conf does not select iwd"
fi
[[ -e $ROOT/etc/iwd/main.conf ]] && warn "/etc/iwd/main.conf exists and replaces the omarchy-mac default whole (BandModifier6GHz=0.0 is lost unless copied)" || pass "no /etc/iwd/main.conf: the omarchy-mac iwd default applies"

saved=0; (( live )) && saved=$(nmcli -t -f TYPE connection show 2>/dev/null | grep -c '^802-11-wireless$')
if (( root_ok )); then
  profiles=$(ls "$ROOT/var/lib/iwd" 2>/dev/null | grep -c -E '\.(psk|open|8021x)$')
  info "iwd: $profiles profile(s) in /var/lib/iwd, $saved saved NetworkManager Wi-Fi connection(s) (names not printed)"
  (( live && saved > 0 && profiles == 0 )) && warn "iwd has no profile although NetworkManager saved $saved Wi-Fi connection(s): wifi-iwd-profiles carried none over (open networks and agent-owned keys get none by design)"
else needroot "iwd profile count in /var/lib/iwd"; fi

helper=$(command -v omarchy-cmd-electron-gl-wrap 2>/dev/null)
if [[ -z $helper && $live == 1 ]]; then
  warn "Electron wrappers: the runtime has no omarchy-cmd-electron-gl-wrap, so setup-system skips them (the install log says 'Skipping Electron launchers')"
else
  for app in chromium:/usr/bin/chromium 1password:/opt/1Password/1password cursor:/usr/bin/cursor; do
    [[ -x $ROOT${app#*:} ]] || { na "Electron wrapper ${app%%:*}: app not installed"; continue; }
    [[ -x $ROOT/usr/local/bin/${app%%:*} ]] && pass "Electron wrapper: /usr/local/bin/${app%%:*} present" || fail "Electron wrapper: ${app%%:*} is installed but /usr/local/bin/${app%%:*} is missing"
  done
fi
if (( live )) && pacman -Q steam >/dev/null 2>&1; then
  pacman -Q omarchy-steam-fex >/dev/null 2>&1 && pass "Steam: omarchy-steam-fex installed" || fail "Steam is installed without omarchy-steam-fex"
else na "Steam FEX launcher: Steam is not installed"; fi

fb=$ROOT/var/lib/omarchy/mac-first-boot
[[ -e $fb/pending ]] && fail "first boot: $fb/pending still exists, so the next boot repeats first boot" || pass "first boot: nothing pending"
[[ -e $fb/last-error ]] && fail "first boot: $fb/last-error exists: $(mask <"$fb/last-error" | head -1)" || pass "first boot: no last-error"
[[ -s $fb/keyring ]] && pass "first boot: this Mac's package keyring was recorded" || fail "first boot: no keyring record"
[[ -e $fb/deferred-steps ]] && info "first boot: deferred-steps is left behind ($(grep -c . "$fb/deferred-steps") step(s); the encryption conversion token)"
[[ -e $ROOT/var/lib/omarchy/image/target.booted ]] && pass "image: target.booted recorded" || info "image: no target.booted (not an image install)"
log=$ROOT/var/log/omarchy-install.log
if [[ -r $log ]]; then
  grep -q 'Completed: .*platform-setup.sh' "$log" && pass "install log: platform-setup.sh (runs setup-system) completed" || fail "install log: no completed platform-setup.sh"
  grep -q 'wifi.backend=iwd' "$log" && pass "install log: setup-system reached its final NetworkManager print" || warn "install log: setup-system's last output (NetworkManager config) is not in the log"
fi
if (( root_ok )); then
  for l in omarchy-mac-first-boot omarchy-provision-owner; do
    f=$ROOT/var/log/$l.log
    if [[ -r $f ]]; then
      # mise's "Failed to resolve tool version list" warnings are offline-first-boot noise, not a step failing.
      bad=$(grep -i -E 'fail|error' "$f" | grep -c -v 'mise WARN')
      if [[ $bad == 0 ]]; then pass "log $l: $(wc -l <"$f") lines, no fail/error besides mise version warnings"
      else warn "log $l: $bad line(s) match fail/error besides mise warnings (read them; a unit's Restart=on-failure text is not a failure):"
        grep -i -E 'fail|error' "$f" | grep -v 'mise WARN' | head -5 | mask | sed 's/^/           | /'; fi
      tail -n 5 "$f" | grep -q -E 'committed|first-boot setup complete' && pass "log $l: completion line in its last 5 lines" || fail "log $l: no completion line"
      tail -n 3 "$f" | mask | sed "s/^/           | /"
    else warn "log $l: not readable or missing"; fi
  done
else needroot "first-boot and owner-provisioning logs (exit status, last lines)"; fi
for u in omarchy-mac-first-boot.service omarchy-mac-efi-vars.service; do
  [[ $(unit_state $u) == enabled ]] && pass "unit $u enabled" || { [[ $(unit_state $u) == static ]] && info "unit $u is static (started by a dependency)" || fail "unit $u is '$(unit_state $u)'"; }
done
(( live )) && { systemctl is-active --quiet omarchy-mac-efi-vars.service && pass "omarchy-mac-efi-vars.service active" || fail "omarchy-mac-efi-vars.service not active"; }

echo "== setup-user (omarchy-mac-setup-user, per user: $user)"
n=0
for flags in "$config"/{chromium,chrome,microsoft-edge-stable,brave,brave-origin}-flags.conf; do
  [[ -f $flags ]] || continue
  n=$((n + 1))
  grep -E '^--disable-features=(.*,)?AcceleratedVideoDecoder([,[:space:]]|$)' "$flags" >/dev/null &&
    pass "browser flags $(basename "$flags"): AcceleratedVideoDecoder is off" || fail "browser flags $(basename "$flags"): AcceleratedVideoDecoder is not disabled"
done
(( n )) || na "browser flags: no Chromium-family flags file"
wants=$config/systemd/user/graphical-session.target.wants/omarchy-asahi-mic.service
mm=${XDG_STATE_HOME:-$home/.local/state}/omarchy/mac-microphone-configured
[[ -n ${SUDO_USER:-} ]] && mm=$home/.local/state/omarchy/mac-microphone-configured
if [[ -L $wants && $(readlink "$wants") == /usr/lib/systemd/user/omarchy-asahi-mic.service && -f $mm ]]; then pass "microphone mapper: enabled once, marker present"
elif [[ -f $mm && ! -e $wants ]]; then info "microphone mapper: disabled by the user after setup (kept)"
else fail "microphone mapper: not enabled and marked (link '$wants', marker '$mm')"; fi
if (( live )) && [[ $EUID -ne 0 ]]; then
  for u in omarchy-asahi-mic omarchy-audio-watchdog; do
    systemctl --user is-active --quiet "$u.service" && pass "user unit $u active" || warn "user unit $u not active (needs a graphical session)"
  done
elif (( live )); then say NEEDS-USER "user unit state: run once WITHOUT sudo for it"; fi
if [[ -z ${helper:-} && $live == 1 ]]; then warn "Electron desktop entries: the runtime lacks omarchy-cmd-desktop-exec-repair/-electron-gl-wrap, setup-user skips them"; fi

if (( mount_factory )); then
  echo "== @factory (issue #69): READ-ONLY mount of the btrfs top level, removed again"
  if [[ $EUID -ne 0 ]]; then echo "--mount-factory needs sudo" >&2; exit 2; fi
  dev=$(findmnt -no SOURCE / | sed 's/\[.*\]//'); top=$(mktemp -d /run/k114s-factory-audit.XXXXXX)
  trap 'umount "$top" 2>/dev/null; rmdir "$top" 2>/dev/null' EXIT
  if mount -o ro,subvolid=5 "$dev" "$top"; then
    f=$top/@factory
    if [[ -d $f ]]; then
      pass "@factory exists"
      kernel=$(omarchy-mac-kernel 2>/dev/null); n=0; same=0
      for d in "$f"/usr/lib/modules/*/; do [[ -f $d/pkgbase && $(<"$d/pkgbase") == "$kernel" ]] || continue
        n=$((n + 1)); cmp -s "$d/vmlinuz" "/boot/vmlinuz-$kernel" && same=1; done
      (( n == 1 && same )) && pass "@factory carries the kernel on /boot: reset-prepare's kernel check would pass" ||
        warn "@factory's $kernel kernel ($n found) is not the file on /boot: reset-prepare refuses ('The factory system's kernel differs')"
      [[ -f $f/usr/lib/omarchy-mac/boot/factory-reset.sh ]] && info "@factory ships factory-reset.sh" || info "@factory predates the reset scripts"
    else fail "no @factory subvolume: a reset has nothing to return to"; fi
  else fail "could not mount the btrfs top level read-only"; fi
fi

echo "== $nfail FAIL"
exit $(( nfail > 0 ))
