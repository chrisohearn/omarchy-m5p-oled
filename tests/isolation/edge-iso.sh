#!/bin/bash
# Run bundle r2's Linux-side update handling inside a COPY of the installed image, against the
# live Edge repositories. Nothing here touches a real Mac. It needs root (loop mounts, chroot)
# and, on an x86 host, qemu-user binfmt for aarch64.
#   usage: edge-iso.sh WORKDIR IMAGE_ZIP BUNDLE
# The image zip is the installed image's package (root.img, boot.img, esp/). Sections of the log
# start with "=== ".
set -uo pipefail
E=$(cd "$1" && pwd); Z=$2; B=$(cd "$3" && pwd); M=$E/mnt; WK=$E/work
log() { echo; echo "=== $*"; }
cleanup() {
  local p r n=0
  # pacman-key leaves a gpg-agent running inside the image copy; it would keep the mounts busy
  for p in /proc/[0-9]*; do
    r=$(sudo readlink "$p/root" 2>/dev/null) || continue
    case "$r" in "$M" | "$M"/*) sudo kill "${p#/proc/}" 2>/dev/null ;; esac
  done
  sleep 1
  while findmnt -n "$M" >/dev/null 2>&1 && [ "$n" -lt 6 ]; do sudo umount -R "$M" 2>/dev/null || break; n=$((n + 1)); done
  if [ -f "$E/loops" ]; then for p in $(cat "$E/loops"); do sudo losetup -d "$p" 2>/dev/null; done; rm -f "$E/loops"; fi
  findmnt -n "$M" >/dev/null 2>&1 && echo "edge-iso: WARNING: $M is still mounted" >&2
  return 0
}
trap cleanup EXIT
cleanup; sudo rm -rf "$WK"; mkdir -p "$WK" "$M"
C() { sudo chroot "$M" /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/bin HOME=/root TERM=dumb LC_ALL=C "$@"; }
# pacman's download sandbox needs Landlock, which user-mode emulation does not give: off here only.
P() { C env OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman --disable-sandbox "$@"; }
PERSIST() { C env K114S_DT_COMPATIBLE=/tmp/compat "K114S_UNAME_V=#1 SMP PREEMPT K114S-R1 Sat Nov 14 2026" K114S_ESP_DT=/nonexistent K114S_USER_HOME=/root bash /boot/efi/k114s-repair/r2/linux-persist.sh "$@"; }
held() { for p in linux-aurora m1n1-aurora uboot-aurora omarchy-aurora-firmware omarchy-mac-boot limine-mkinitcpio-hook mesa-aurora omarchy omarchy-settings omarchy-mac; do C pacman -Q "$p" 2>&1; done; }

log "extract (date: $(date -u +%FT%TZ))"
unzip -q -o "$Z" root.img boot.img 'esp/*' -d "$WK" && ls -la "$WK" | sed -n 2,8p
mkdir -p "$WK/esp/vendorfw"
python3 -I - "$WK/esp/vendorfw" "$B" <<'PY'
import sys, os
sys.path.insert(0, sys.argv[2] + '/tools')
from asahi_firmware.core import FWPackage, FWFile
p = FWPackage(sys.argv[1])
for n, d in [('apple/tpmtfw-k114s.bin', open(sys.argv[2] + '/payload/tpmtfw-k114s.bin', 'rb').read()), ('apple/placeholder-a.bin', os.urandom(4096)), ('apple/placeholder-b.bin', b'same' * 500)]:
    p.add_file(n, FWFile(n, d))
p.close()
PY
log "macOS tool on the image's ESP files (test mode)"
python3 -I "$B/tools/k114s_repair.py" apply --yes --esp-dir "$WK/esp" 2>&1 | tail -9

log "mount"
truncate -s 524288000 "$WK/esp.img" && mkfs.vfat -F 32 -i 4F4D5801 "$WK/esp.img" >/dev/null
root=$(sudo losetup -fP --show "$WK/root.img"); boot=$(sudo losetup -fP --show "$WK/boot.img"); esp=$(sudo losetup -fP --show "$WK/esp.img"); echo "$root $boot $esp" > "$E/loops"
sudo mount -o subvol=@ "$root" "$M" || exit 1
sudo mount "$boot" "$M/boot" || exit 1
sudo mkdir -p "$M/boot/efi" && sudo mount -o umask=0077 "$esp" "$M/boot/efi" && sudo cp -r "$WK/esp/." "$M/boot/efi/" || exit 1
sudo mount -t proc proc "$M/proc"; sudo mount -t sysfs sys "$M/sys"; sudo mount -t devtmpfs dev "$M/dev"; sudo mount -t devpts devpts "$M/dev/pts"
sudo mount -t tmpfs tmpfs "$M/run"; sudo mount -t tmpfs tmpfs "$M/tmp"
sudo rm -f "$M/etc/resolv.conf"; sudo cp -L /etc/resolv.conf "$M/etc/resolv.conf"
printf 'apple,k114s\0apple,t6050\0apple,arm-platform\0' | sudo tee "$M/tmp/compat" >/dev/null
C uname -m; findmnt -R "$M" -o TARGET,FSTYPE | sed -n 1,12p

log "image facts"
C grep -n -E '^[[:space:]]*(IgnorePkg|IgnoreGroup|HookDir|NoUpgrade|\[)' /etc/pacman.conf | cut -c1-400
C sh -c 'pacman -Qi linux-aurora m1n1-aurora uboot-aurora omarchy-mac-boot omarchy-aurora-firmware limine-mkinitcpio-hook | grep -E "^(Name|Version|Install Reason|Required By)"'
C sh -c 'ls -la /etc/pacman.d/hooks; ls -la /etc/omarchy-mac-boot 2>&1; ls /usr/local/lib; echo "orphans now: $(pacman -Qdtq | tr "\n" " ")"'
held
C sh -c 'cat /etc/fstab | grep -v "^#"; ls /usr/share/omarchy/default/pacman/ 2>&1 | head; ls /usr/share/omarchy/default/pacman/aarch64-apple 2>&1'

log "keyring"
C pacman-key --init 2>&1 | tail -2; C pacman-key --populate 2>&1 | tail -3

log "boot check before persist"
C env OMARCHY_BOOT_CHECK_ALLOW_PENDING_REBOOT=1 omarchy-apple-silicon-boot-check --boot-chain 2>&1 | tail -8; echo "rc=${PIPESTATUS[0]}"

log "persist, undo, compare"
snapshot() { C sh -c 'sha256sum /etc/pacman.conf /usr/lib/modules/*/vmlinuz /boot/vmlinuz-linux-aurora /usr/local/lib/omarchy-j714s/update-boot-ctxr; ls /etc/pacman.d/hooks; ls /etc/omarchy-mac-boot 2>&1; pacman -Qqe | sha256sum; pacman -Qqd | sha256sum; find /usr/lib/modules -name "hid-magicmouse*" | sort' 2>&1; }
snapshot > "$WK/snap.before"
PERSIST 2>&1 | tail -9; echo "rc=${PIPESTATUS[0]}"
PERSIST --undo 2>&1 | tail -3; echo "rc=${PIPESTATUS[0]}"
snapshot > "$WK/snap.after-undo"
cmp -s "$WK/snap.before" "$WK/snap.after-undo" && echo "UNDO-EXACT: yes" || { echo "UNDO-EXACT: NO"; diff "$WK/snap.before" "$WK/snap.after-undo" | head -20; }

log "persist (kept)"
PERSIST 2>&1 | tail -9; echo "rc=${PIPESTATUS[0]}"
C sh -c 'echo "holds.list: $(tr "\n" " " < /usr/local/lib/omarchy-k114s/holds.list)"; sed -n "/^# >>> K114s holds/,/^# <<< K114s holds/p" /etc/pacman.conf | cut -c1-300; cat /etc/omarchy-mac-boot/owner-boot-chain; pacman -Qi linux-aurora m1n1-aurora uboot-aurora omarchy-mac-boot omarchy-aurora-firmware limine-mkinitcpio-hook | grep -E "^(Name|Install Reason)" | paste - - ; pacman-conf IgnorePkg | wc -l; ls /usr/local/lib/omarchy-k114s /usr/local/lib/omarchy-k114s/recovery/*'

log "boot check after persist (no owner-boot-chain)"
C sh -c 'mv /etc/omarchy-mac-boot/owner-boot-chain /tmp/obc; OMARCHY_BOOT_CHECK_ALLOW_PENDING_REBOOT=1 omarchy-apple-silicon-boot-check --boot-chain > /tmp/bc.out 2>&1; echo "rc=$?"; tail -6 /tmp/bc.out; mv /tmp/obc /etc/omarchy-mac-boot/owner-boot-chain'
log "update-verify after persist (owner-boot-chain present)"
C /usr/lib/omarchy/mac-boot/update-verify 2>&1 | tail -12; echo "rc=${PIPESTATUS[0]}"

log "edge-check (read-only solve of the pending upgrade; holds present)"
C pacman -Q > "$WK/q.0"
C sh -c 'printf "#!/bin/sh\nexec pacman --disable-sandbox \"\$@\"\n" > /usr/local/bin/pacman-iso; chmod +x /usr/local/bin/pacman-iso'
C env K114S_PACMAN=/usr/local/bin/pacman-iso /usr/local/lib/omarchy-k114s/k114s-edge-check 2>&1 | tail -60; echo "rc=${PIPESTATUS[0]}"
C pacman -Q > "$WK/q.1"; cmp -s "$WK/q.0" "$WK/q.1" && echo "edge-check changed no package: yes"
C sh -c 'ls /var/lib/pacman/sync 2>/dev/null | wc -l'

log "update: pacman -Syu as omarchy update runs it (holds present)"
P -Syu --noconfirm > "$WK/syu.log" 2>&1; echo "rc=$?"; grep -c -E '^(upgrading|installing|removing|downgrading) ' "$WK/syu.log"; grep -iE 'error|warning: .*ignor|failed|K114s|hook' "$WK/syu.log" | cut -c1-220 | head -40; tail -6 "$WK/syu.log" | cut -c1-220
C pacman -Q > "$WK/q.2"; echo "packages changed: $(diff "$WK/q.1" "$WK/q.2" | grep -c '^>')"; held
C sh -c 'sha256sum /boot/efi/m1n1/boot-ctxr.bin /boot/efi/m1n1/boot.bin /usr/lib/modules/7.3.0-17.v272-4-ARCH/vmlinuz | cut -c1-80; grep -c "K114s repair" /boot/efi/limine.conf; grep -n "default_entry\|^/" /boot/efi/limine.conf | head -8'
log "update-verify after the update"
C /usr/lib/omarchy/mac-boot/update-verify 2>&1 | tail -8; echo "rc=${PIPESTATUS[0]}"

log "channel refresh, simulated: template over pacman.conf, the user hook, then -Syyuu"
C sh -c 'cp /etc/pacman.conf /root/pacman.conf.before-refresh; T=/usr/share/omarchy/default/pacman/aarch64-apple/pacman-edge.conf; [ -f $T ] || T=$(ls /usr/share/omarchy/default/pacman/*/pacman-edge.conf | head -1); echo "template: $T"; cp -f $T /etc/pacman.conf; echo "IgnorePkg lines after the template: $(grep -c "^IgnorePkg" /etc/pacman.conf)"; bash /root/.config/omarchy/hooks/pre-refresh-pacman.d/k114s-holds; echo "hook rc=$?"; grep -c "^# >>> K114s holds" /etc/pacman.conf; pacman-conf IgnorePkg | tr "\n" " "'
P -Syyuu --noconfirm > "$WK/refresh.log" 2>&1; echo "rc=$?"; grep -c -E '^(upgrading|installing|removing|downgrading) ' "$WK/refresh.log"; grep -iE 'error|ignor|failed|K114s|downgrad' "$WK/refresh.log" | cut -c1-220 | head -30
C pacman -Q > "$WK/q.3"; echo "packages changed by the refresh upgrade: $(diff "$WK/q.2" "$WK/q.3" | grep -c '^>')"; diff "$WK/q.2" "$WK/q.3" | head -20; held

log "guard: no holds at all, then the refresh's upgrade"
C sh -c '/usr/local/lib/omarchy-k114s/apply-holds --remove; echo "IgnorePkg lines: $(grep -c "^IgnorePkg" /etc/pacman.conf)"'
P -Syyuu --noconfirm > "$WK/guard.log" 2>&1; echo "rc=$?"; grep -E 'K114s hold guard|linux-aurora|m1n1-aurora|uboot-aurora|error|Nothing has been changed' "$WK/guard.log" | cut -c1-220 | head -20
C pacman -Q > "$WK/q.4"; cmp -s "$WK/q.3" "$WK/q.4" && echo "GUARD: no package changed" || { echo "GUARD: PACKAGES CHANGED"; diff "$WK/q.3" "$WK/q.4" | head; }
log "what that upgrade wanted to do (print only)"
P -Sup --print-format '%n %v %r' 2>&1 | grep -E '^(linux-aurora|m1n1-aurora|uboot-aurora|omarchy-aurora-firmware|omarchy-mac-boot|limine-mkinitcpio-hook|mesa-aurora|vulkan-aurora|omarchy|omarchy-settings|omarchy-mac|hyprland|speakerguardd|alsa-ucm-conf-aurora|aurora-audio|aurora-bless|linux-aurora-headers) ' | head -30

log "guard: holds back; a named reinstall and a removal"
C /usr/local/lib/omarchy-k114s/apply-holds
P -S --noconfirm linux-aurora 2>&1 | grep -E 'K114s hold guard|IgnorePkg|error|Nothing' | cut -c1-200 | head -8; echo "rc=${PIPESTATUS[0]}"
P -Rdd --noconfirm uboot-aurora 2>&1 | grep -E 'K114s hold guard|error|Nothing' | cut -c1-200 | head -6; echo "rc=${PIPESTATUS[0]}"
C pacman -Q > "$WK/q.5"; cmp -s "$WK/q.4" "$WK/q.5" && echo "GUARD: no package changed"
C sh -c 'mkdir -p /etc/omarchy-k114s && touch /etc/omarchy-k114s/allow-coupled-update'; P -S --noconfirm uboot-aurora 2>&1 | grep -E 'K114s hold guard|error|reinstalling|installing' | cut -c1-200 | head -6; echo "rc=${PIPESTATUS[0]}"; C rm -f /etc/omarchy-k114s/allow-coupled-update

log "Update > Channel > Edge: what the package swap would do (print only)"
P -Sp --print-format '%n %v %r' omarchy-dev omarchy-settings-dev 2>&1 | head -30; echo "rc=${PIPESTATUS[0]}"
C sh -c 'pacman -Si omarchy-dev 2>/dev/null | grep -E "^(Version|Depends On|Conflicts With|Replaces|Provides)" | cut -c1-600'

log "Update > Channel > Edge: the swap itself (guard), then forced through in this copy"
P -S --needed --noconfirm --ask 4 omarchy-dev omarchy-settings-dev 2>&1 | grep -E 'K114s hold guard|omarchy|error|Nothing' | cut -c1-200 | head -8; echo "rc=${PIPESTATUS[0]}"
C pacman -Q > "$WK/q.6"; C pacman -Q omarchy omarchy-settings 2>&1
C sh -c 'touch /etc/omarchy-k114s/allow-coupled-update'
P -S --needed --noconfirm --ask 4 omarchy-dev omarchy-settings-dev > "$WK/swap.log" 2>&1; echo "forced swap rc=$?"; grep -iE 'error|warning|removing|installing|K114s' "$WK/swap.log" | cut -c1-200 | head -20
C rm -f /etc/omarchy-k114s/allow-coupled-update
C sh -c 'pacman -Q omarchy-dev omarchy-settings-dev 2>&1; pacman -Q omarchy 2>&1 | head -1; echo "dependency check: $(pacman -Dk 2>&1 | tail -3 | tr "\n" " ")"; ls /usr/share/omarchy/migrations 2>/dev/null | wc -l; cat /usr/share/omarchy/version 2>/dev/null'
held
C sh -c 'sha256sum /boot/efi/m1n1/boot-ctxr.bin /usr/lib/modules/7.3.0-17.v272-4-ARCH/vmlinuz | cut -c1-80; grep -c "K114s repair" /boot/efi/limine.conf; grep -c "^# >>> K114s holds" /etc/pacman.conf; ls /etc/pacman.d/hooks'
C /usr/lib/omarchy/mac-boot/update-verify 2>&1 | tail -4; echo "update-verify rc=${PIPESTATUS[0]}"

log "done (date: $(date -u +%FT%TZ))"
