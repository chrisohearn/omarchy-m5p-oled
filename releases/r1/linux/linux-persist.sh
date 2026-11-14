#!/bin/bash
# K114s repair r1: make the repair survive initramfs/boot-file regeneration inside Linux.
# Run in Linux AFTER the "Omarchy K114s repair r1" entry has booted and works:
#     sudo bash /boot/efi/k114s-repair/r1/linux-persist.sh
# It installs the repair kernel image, the patched trackpad module and a K114s Stage 2 hook, and
# holds only the packages that would undo them (kept across Omarchy channel refreshes).
# It does not regenerate the initramfs, change boot files on the ESP, or reboot.
#     sudo bash /boot/efi/k114s-repair/r1/linux-persist.sh --undo     puts everything back
set -euo pipefail
ROOT=${K114S_ROOT:-}
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
KVER=7.3.0-17.v272-4-ARCH
MOD=$ROOT/usr/lib/modules/$KVER
LIB=$ROOT/usr/local/lib/omarchy-k114s
STATE=$LIB/persist-r1
J714S_HOOK_SCRIPT=$ROOT/usr/local/lib/omarchy-j714s/update-boot-ctxr
PACCONF=$ROOT/etc/pacman.conf
USER_HOME=${K114S_USER_HOME:-}
if [[ -z $USER_HOME && -n ${SUDO_USER:-} ]]; then USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6); fi
HOLD_PKGS="linux-aurora m1n1-aurora uboot-aurora"
die() { echo "linux-persist: $*" >&2; exit 1; }
say() { echo "linux-persist: $*"; }
sum() { sha256sum "$1" | cut -c1-64; }

[[ $(id -u) == 0 || -n ${K114S_ROOT:-} ]] || die "run with sudo"
(cd "$HERE" && sha256sum --quiet -c SHA256SUMS) || die "files beside this script do not match SHA256SUMS"
compatible=${K114S_DT_COMPATIBLE:-/sys/firmware/devicetree/base/compatible}
grep -zFxq 'apple,k114s' "$compatible" || die "this is not an apple,k114s Mac"
[[ -d $MOD ]] || die "$MOD is missing: the installed kernel is not $KVER"

restore() { # restore FILE from its saved copy, or remove it if it did not exist before
  local file=$1 key=$2
  if [[ -e $STATE/$key.orig ]]; then cp -a "$STATE/$key.orig" "$file"
  elif [[ -e $STATE/$key.absent ]]; then rm -f "$file"; fi
}
if [[ ${1:-} == --undo ]]; then
  [[ -d $STATE ]] || die "nothing to undo"
  restore "$MOD/vmlinuz" vmlinuz
  [[ -e $STATE/boot-vmlinuz.orig ]] && cp -a "$STATE/boot-vmlinuz.orig" "$ROOT/boot/vmlinuz-linux-aurora"
  restore "$MOD/updates/hid-magicmouse.ko" module
  restore "$J714S_HOOK_SCRIPT" j714s-hook-script
  K114S_ROOT=$ROOT bash "$HERE/apply-holds" --remove
  [[ -f $STATE/user-hook.path ]] && rm -f "$(cat "$STATE/user-hook.path")"
  rm -f "$LIB/update-boot-ctxr" "$LIB/k114s.dtb" "$LIB/apply-holds"
  ${K114S_DEPMOD:-depmod} -b "${ROOT:-/}" "$KVER"
  mv "$STATE" "$STATE.undone.$(date +%s)"
  say "undone. The ESP boot files were not changed."
  exit 0
fi

[[ -f $PACCONF ]] && grep -q '^\[options\]' "$PACCONF" || die "could not find [options] in $PACCONF; nothing changed"
release=${K114S_UNAME_V:-$(uname -v)}
case $release in
  *K114S-R1A*) variant=r1a ;;
  *K114S-R1*) variant=r1 ;;
  *) die "the running kernel is not a repair kernel (uname -v: $release). Boot an 'Omarchy K114s repair' entry first." ;;
esac
say "running repair kernel variant: $variant"
[[ ! -d $STATE ]] || die "already applied (see $STATE); use --undo first to redo"
mkdir -p "$STATE" "$LIB" "$MOD/updates"
save() { # save FILE under KEY before changing it
  local file=$1 key=$2
  if [[ -e $file ]]; then cp -a "$file" "$STATE/$key.orig"; else : > "$STATE/$key.absent"; fi
}

# 1. kernel image and module, so a regenerated UKI/initramfs carries the fix
save "$MOD/vmlinuz" vmlinuz
old_kernel=$(sum "$MOD/vmlinuz" 2>/dev/null || true)
gzip -dc "$HERE/vmlinuz-k114s-$variant.gz" > "$STATE/vmlinuz.new"
[[ $(od -An -c -N2 "$STATE/vmlinuz.new" | tr -d ' ') == MZ ]] || die "the unpacked kernel image is not valid; nothing changed"
install -m 644 "$STATE/vmlinuz.new" "$MOD/vmlinuz"
if [[ -f $ROOT/boot/vmlinuz-linux-aurora && $(sum "$ROOT/boot/vmlinuz-linux-aurora") == "$old_kernel" ]]; then
  cp -a "$ROOT/boot/vmlinuz-linux-aurora" "$STATE/boot-vmlinuz.orig"
  install -m 644 "$STATE/vmlinuz.new" "$ROOT/boot/vmlinuz-linux-aurora"
fi
rm -f "$STATE/vmlinuz.new"
save "$MOD/updates/hid-magicmouse.ko" module
install -m 644 "$HERE/hid-magicmouse-$variant.ko" "$MOD/updates/hid-magicmouse.ko"
${K114S_DEPMOD:-depmod} -b "${ROOT:-/}" "$KVER"

# 2. Stage 2: the image's hook copies boot.bin over boot-ctxr.bin; make it rebuild the K114s one
install -m 755 "$HERE/update-boot-ctxr-k114s" "$LIB/update-boot-ctxr"
[[ -s $HERE/../k114s.dtb ]] || die "$HERE/../k114s.dtb is missing"
install -m 644 "$HERE/../k114s.dtb" "$LIB/k114s.dtb"
save "$J714S_HOOK_SCRIPT" j714s-hook-script
mkdir -p "$(dirname "$J714S_HOOK_SCRIPT")"
cat > "$J714S_HOOK_SCRIPT" <<'HOOK'
#!/bin/sh
# K114s repair r1: this Mac is a K114s. Rebuild the K114s-only Stage 2 instead of copying boot.bin.
exec /usr/local/lib/omarchy-k114s/update-boot-ctxr "$@"
HOOK
chmod 755 "$J714S_HOOK_SCRIPT"

# 3. hold only the packages that would replace the repaired kernel, loader or U-Boot
install -m 755 "$HERE/apply-holds" "$LIB/apply-holds"
K114S_ROOT=$ROOT "$LIB/apply-holds"
# Omarchy's channel refresh replaces pacman.conf from a template and then runs the user's
# pre-refresh-pacman hooks: put the holds back there, before its upgrade transaction.
if [[ -n $USER_HOME ]]; then
  hook_dir=$USER_HOME/.config/omarchy/hooks/pre-refresh-pacman.d
  mkdir -p "$hook_dir"
  printf '%s\n' '#!/bin/bash' '# K114s repair r1: keep the K114s boot stack held across channel refreshes' \
    'sudo /usr/local/lib/omarchy-k114s/apply-holds' > "$hook_dir/k114s-holds"
  chmod 755 "$hook_dir/k114s-holds"
  [[ -z ${SUDO_UID:-} ]] || chown -R "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$USER_HOME/.config/omarchy/hooks"
  echo "$hook_dir/k114s-holds" > "$STATE/user-hook.path"
fi
say "done. Installed: kernel image, hid-magicmouse (updates/), K114s Stage 2 hook, package holds."
[[ -n $USER_HOME ]] || say "note: no invoking user found, so the channel-refresh hook was not installed"
say "Held packages: $HOLD_PKGS. Undo with: sudo bash $HERE/linux-persist.sh --undo"
