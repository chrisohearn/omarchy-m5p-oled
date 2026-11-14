#!/bin/bash
# K114s (omarchy-m5p-oled, bundle r2c): make the repair survive package updates inside Linux.
# Run in Linux AFTER the "Omarchy K114s repair" boot entry has booted and works:
#     sudo bash /boot/efi/k114s-repair/r2c/linux-persist.sh
#     sudo bash /boot/efi/k114s-repair/r2c/linux-persist.sh --undo     puts everything back
#
# The repair kernel and the K114s Wi-Fi firmware are taken out of the repair kernel image on the
# ESP, by the byte ranges and hashes in repair-uki.txt (the ESP has no room for second copies).
#
# What it does; --undo reverses each step:
#   1. installs the repair kernel image and the patched trackpad module, so a regenerated boot
#      image carries the fix, and the K114s Wi-Fi firmware under /usr/lib/firmware/updates
#   2. makes the image's Stage 2 hook rebuild the K114s-only Stage 2 with the pinned K114s tree
#   3. keeps held every package the installed image pinned itself, plus the K114s boot stack,
#      also after an Omarchy channel refresh rewrites /etc/pacman.conf
#   4. adds a pacman hook that stops any transaction that would change the boot-chain packages
#   5. tells Omarchy's post-update boot check that this Mac's owner manages its boot chain
#      (the check compares the kernel file with its package and would fail on every update)
#   6. marks the boot-chain packages as explicitly installed, so orphan cleanup never removes them
#   7. records the package list and the boot files' checksums as they were before step 1
#   8. adds a pacman hook that stops package changes while the ESP has less than 100 MB free
#      (an update rebuilds an 80 MB boot image there)
# It does not regenerate the initramfs, change boot files on the ESP, change the channel or reboot.
set -euo pipefail
REV=r2c
ROOT=${K114S_ROOT:-}
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
KVER=7.3.0-17.v272-4-ARCH
MOD=$ROOT/usr/lib/modules/$KVER
LIB=$ROOT/usr/local/lib/omarchy-k114s
STATE=$LIB/persist-$REV
J714S_HOOK_SCRIPT=$ROOT/usr/local/lib/omarchy-j714s/update-boot-ctxr
PACCONF=$ROOT/etc/pacman.conf
HOOK=$ROOT/etc/pacman.d/hooks/00-k114s-hold-guard.hook
SPACE_HOOK=$ROOT/etc/pacman.d/hooks/01-k114s-esp-space.hook
FW=$ROOT/usr/lib/firmware/updates/apple/centauri/k114s-ftab.bin
RECORD=$HERE/repair-uki.txt
OWNER=$ROOT/etc/omarchy-mac-boot/owner-boot-chain
PACMAN=${K114S_PACMAN:-pacman}
PACMAN_CONF=${K114S_PACMAN_CONF:-pacman-conf}
CORE="linux-aurora m1n1-aurora uboot-aurora"
# The packages 00-k114s-hold-guard.hook names: what the boot files are built from and by.
GUARDED="linux-aurora m1n1-aurora uboot-aurora omarchy-aurora-firmware omarchy-mac-boot limine-mkinitcpio-hook"
USER_HOME=${K114S_USER_HOME:-}
if [[ -z $USER_HOME && -n ${SUDO_USER:-} ]]; then USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6); fi
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
  if [[ -e $STATE/boot-vmlinuz.orig ]]; then cp -a "$STATE/boot-vmlinuz.orig" "$ROOT/boot/vmlinuz-linux-aurora"; fi
  restore "$MOD/updates/hid-magicmouse.ko" module
  restore "$J714S_HOOK_SCRIPT" j714s-hook-script
  if [[ -x $LIB/apply-holds ]]; then K114S_ROOT=$ROOT "$LIB/apply-holds" --remove
  else K114S_ROOT=$ROOT bash "$HERE/apply-holds" --remove; fi
  if [[ -f $STATE/user-hook.path ]]; then rm -f "$(cat "$STATE/user-hook.path")"; fi
  restore "$HOOK" guard-hook
  restore "$SPACE_HOOK" space-hook
  restore "$FW" ftab
  if [[ -s $STATE/created-dirs ]]; then
    tac "$STATE/created-dirs" | while read -r dir; do rmdir "$dir" 2>/dev/null || true; done
  fi
  if [[ -e $STATE/owner-boot-chain.created ]]; then
    rm -f "$OWNER"
    rmdir "$(dirname "$OWNER")" 2>/dev/null || true
  fi
  if [[ -s $STATE/was-dependency.list ]]; then
    while read -r package; do
      "$PACMAN" -D --asdeps "$package" >/dev/null || say "note: could not mark $package as a dependency again"
    done < "$STATE/was-dependency.list"
  fi
  rm -f "$LIB/update-boot-ctxr" "$LIB/k114s.dtb" "$LIB/apply-holds" "$LIB/holds.list" "$LIB/hold-guard" \
    "$LIB/k114s-booted-esp" "$LIB/k114s-edge-check" "$LIB/esp-space-guard"
  ${K114S_DEPMOD:-depmod} -b "${ROOT:-/}" "$KVER"
  mv "$STATE" "$STATE.undone.$(date +%s)"
  say "undone. The ESP boot files were not changed. The record under $LIB/recovery is kept."
  exit 0
fi
[[ -z ${1:-} ]] || die "unknown argument $1"

[[ -f $PACCONF ]] && grep -q '^\[options\]' "$PACCONF" || die "could not find [options] in $PACCONF; nothing changed"
release=${K114S_UNAME_V:-$(uname -v)}
case $release in
  *K114S-R1A*) variant=r1a ;;
  *K114S-R1*) variant=r1 ;;
  *) die "the running kernel is not a repair kernel (uname -v: $release). Boot an 'Omarchy K114s repair' entry first." ;;
esac
say "running repair kernel variant: $variant"
for other in r1 r2; do
  [[ ! -d $LIB/persist-$other ]] || die "bundle $other's persistence is applied (see $LIB/persist-$other); undo it with that bundle's script first"
done
[[ ! -d $STATE ]] || die "already applied (see $STATE); use --undo first to redo"
# The repair kernel image on the ESP must be exactly the one the record describes.
[[ -f $RECORD ]] || die "$RECORD is missing"
field() { awk -v k="$1" '$1 == k { $1 = ""; sub(/^ /, ""); print; exit }' "$RECORD"; }
[[ $(field variant) == "$variant" ]] || die "the running repair kernel is $variant, but the ESP's repair kernel image is $(field variant); boot the repair entry again"
read -r uki_rel uki_bytes uki_sum <<<"$(field uki)"
UKI_FILE=$ROOT/boot/efi/$uki_rel
[[ -f $UKI_FILE && $(stat -c %s "$UKI_FILE") == "$uki_bytes" && $(sum "$UKI_FILE") == "$uki_sum" ]] ||
  die "the repair kernel image on the ESP ($uki_rel) does not match $RECORD; nothing changed"
[[ -s $HERE/../k114s.dtb ]] || die "$HERE/../k114s.dtb is missing"
if [[ ${K114S_SKIP_ESP_CHECK:-0} != 1 ]]; then
  OMARCHY_ROOT=$ROOT sh "$HERE/k114s-booted-esp" || die "the ESP mounted at $ROOT/boot/efi is not the one this boot came from; nothing changed"
fi

# Take the kernel and the Wi-Fi firmware out of the image before changing anything.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
extract() { # extract KEY from the repair kernel image to FILE, checking its hash
  local offset length digest
  read -r offset length digest <<<"$(field "$1")"
  [[ $offset =~ ^[0-9]+$ && $length =~ ^[0-9]+$ && $digest =~ ^[0-9a-f]{64}$ ]] || die "bad $1 line in $RECORD; nothing changed"
  dd if="$UKI_FILE" of="$2" bs=1M iflag=skip_bytes,count_bytes skip="$offset" count="$length" status=none
  [[ $(sum "$2") == "$digest" ]] || die "the $1 taken from the repair kernel image does not verify; nothing changed"
}
extract kernel "$work/vmlinuz"
[[ $(od -An -c -N2 "$work/vmlinuz" | tr -d ' ') == MZ ]] || die "the kernel taken from the image is not valid; nothing changed"
extract ftab "$work/ftab"
extract module "$work/module"
cmp -s "$work/module" "$HERE/hid-magicmouse-$variant.ko" || die "hid-magicmouse-$variant.ko is not the module in the repair kernel image; nothing changed"

mkdir -p "$STATE" "$LIB" "$MOD/updates"
trap 'rm -rf "$work"; echo "linux-persist: stopped part-way. Put everything back with: sudo bash $HERE/linux-persist.sh --undo" >&2' ERR
save() { # save FILE under KEY before changing it
  local file=$1 key=$2
  if [[ -e $file ]]; then cp -a "$file" "$STATE/$key.orig"; else : > "$STATE/$key.absent"; fi
}

# 7 (first, so it shows the state before any change): package list and boot-file checksums
record=$LIB/recovery/$(date -u +%Y%m%dT%H%M%SZ)-before-persist-$REV
mkdir -p "$record"
"$PACMAN" -Q > "$record/packages.txt" 2>/dev/null || say "note: could not list the installed packages"
cp -p "$PACCONF" "$record/pacman.conf"
(cd "${ROOT:-/}" && find boot -type f -exec sha256sum {} + 2>/dev/null | LC_ALL=C sort -k2) > "$record/boot-files.sha256" || true

# 1. kernel image and module, so a regenerated UKI/initramfs carries the fix
save "$MOD/vmlinuz" vmlinuz
old_kernel=$(sum "$MOD/vmlinuz" 2>/dev/null || true)
install -m 644 "$work/vmlinuz" "$MOD/vmlinuz"
if [[ -f $ROOT/boot/vmlinuz-linux-aurora && $(sum "$ROOT/boot/vmlinuz-linux-aurora") == "$old_kernel" ]]; then
  cp -a "$ROOT/boot/vmlinuz-linux-aurora" "$STATE/boot-vmlinuz.orig"
  install -m 644 "$work/vmlinuz" "$ROOT/boot/vmlinuz-linux-aurora"
fi
save "$MOD/updates/hid-magicmouse.ko" module
install -m 644 "$HERE/hid-magicmouse-$variant.ko" "$MOD/updates/hid-magicmouse.ko"
${K114S_DEPMOD:-depmod} -b "${ROOT:-/}" "$KVER"
# The Wi-Fi firmware, where the kernel finds it after an ordinary boot image has replaced the repair one
save "$FW" ftab
: > "$STATE/created-dirs"
dir=$(dirname "$FW"); missing=()
while [[ ! -d $dir ]]; do missing=("$dir" "${missing[@]}"); dir=$(dirname "$dir"); done
for dir in "${missing[@]}"; do mkdir "$dir"; echo "$dir" >> "$STATE/created-dirs"; done
install -m 644 "$work/ftab" "$FW"

# 2. Stage 2: the image's hook copies boot.bin over boot-ctxr.bin; make it rebuild the K114s one
install -m 755 "$HERE/update-boot-ctxr-k114s" "$LIB/update-boot-ctxr"
install -m 755 "$HERE/k114s-booted-esp" "$LIB/k114s-booted-esp"
install -m 644 "$HERE/../k114s.dtb" "$LIB/k114s.dtb"
save "$J714S_HOOK_SCRIPT" j714s-hook-script
mkdir -p "$(dirname "$J714S_HOOK_SCRIPT")"
cat > "$J714S_HOOK_SCRIPT" <<'HOOK'
#!/bin/sh
# K114s (omarchy-m5p-oled): this Mac is a K114s. Rebuild the K114s-only Stage 2 instead of copying boot.bin.
exec /usr/local/lib/omarchy-k114s/update-boot-ctxr "$@"
HOOK
chmod 755 "$J714S_HOOK_SCRIPT"

# 3. holds: what the image pinned itself (read now, before any refresh can drop it) plus the boot stack
held_now=$({ "$PACMAN_CONF" --config "$PACCONF" IgnorePkg 2>/dev/null ||
  sed -n 's/^[[:space:]]*IgnorePkg[[:space:]]*=[[:space:]]*//p' "$PACCONF" | tr -s ' \t' '\n\n'; } |
  { grep -E '^[A-Za-z0-9@._+-]+$' || true; } | LC_ALL=C sort -u)
printf '%s\n' "$held_now" > "$STATE/holds-found.list"
{ printf '%s\n' $CORE; printf '%s\n' "$held_now"; } | { grep -E '^[A-Za-z0-9@._+-]+$' || true; } | LC_ALL=C sort -u > "$LIB/holds.list"
install -m 755 "$HERE/apply-holds" "$LIB/apply-holds"
K114S_ROOT=$ROOT "$LIB/apply-holds"
# Omarchy's channel refresh replaces pacman.conf from a template and then runs the user's
# pre-refresh-pacman hooks: put the holds back there, before its upgrade transaction.
if [[ -n $USER_HOME ]]; then
  hook_dir=$USER_HOME/.config/omarchy/hooks/pre-refresh-pacman.d
  mkdir -p "$hook_dir"
  printf '%s\n' '#!/bin/bash' '# K114s (omarchy-m5p-oled): keep the pinned set and the K114s boot stack held across channel refreshes' \
    'sudo /usr/local/lib/omarchy-k114s/apply-holds' > "$hook_dir/k114s-holds"
  chmod 755 "$hook_dir/k114s-holds"
  [[ -z ${SUDO_UID:-} ]] || chown -R "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$USER_HOME/.config/omarchy/hooks"
  echo "$hook_dir/k114s-holds" > "$STATE/user-hook.path"
fi

# 4. the backstop: a pre-transaction hook pacman.conf's template cannot remove
install -m 755 "$HERE/hold-guard" "$LIB/hold-guard"
save "$HOOK" guard-hook
mkdir -p "$(dirname "$HOOK")"
install -m 644 "$HERE/00-k114s-hold-guard.hook" "$HOOK"

# 5. Omarchy's post-update boot check: this Mac's owner manages the boot chain
if [[ ! -e $OWNER ]]; then
  mkdir -p "$(dirname "$OWNER")"
  echo "K114s (Mac17,13): repair kernel and K114s-only Stage 2 from omarchy-m5p-oled bundle $REV; see /usr/local/lib/omarchy-k114s" > "$OWNER"
  : > "$STATE/owner-boot-chain.created"
fi

# 6. never orphans: mark the installed boot-chain packages as explicitly installed
: > "$STATE/was-dependency.list"
dependencies=$("$PACMAN" -Qqd 2>/dev/null || true)
for package in $GUARDED; do
  grep -Fxq "$package" <<<"$dependencies" || continue
  echo "$package" >> "$STATE/was-dependency.list"
  "$PACMAN" -D --asexplicit "$package" >/dev/null
done

# 8. no package changes while the ESP is too full for the boot image an update rebuilds
install -m 755 "$HERE/esp-space-guard" "$LIB/esp-space-guard"
save "$SPACE_HOOK" space-hook
install -m 644 "$HERE/01-k114s-esp-space.hook" "$SPACE_HOOK"

install -m 755 "$HERE/k114s-edge-check" "$LIB/k114s-edge-check"
trap - ERR
say "done. Installed: kernel image, hid-magicmouse (updates/), K114s Stage 2 hook, package holds,"
say "  hold guard, boot-chain declaration. Record of the state before: $record"
[[ -n $USER_HOME ]] || say "note: no invoking user found, so the channel-refresh hook was not installed"
say "Held packages: $(tr '\n' ' ' < "$LIB/holds.list")"
say "Before an update you can ask what it would change: sudo $LIB/k114s-edge-check"
esp_free=$(df -B1 --output=avail "$ROOT/boot/efi" 2>/dev/null | tail -n 1 | tr -d ' ')
if [[ $esp_free =~ ^[0-9]+$ ]] && (( esp_free < 104857600 )); then
  say "note: the EFI partition has $((esp_free / 1000000)) MB free. Package changes stay stopped until it has 100 MB:"
  say "  an update rebuilds an 80 MB boot image there."
fi
say "Undo with: sudo bash $HERE/linux-persist.sh --undo"
