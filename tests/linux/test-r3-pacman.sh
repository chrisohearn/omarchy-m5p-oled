#!/bin/bash
# The r3 update tooling under a REAL pacman, as an unprivileged user.
#   usage: test-r3-pacman.sh [LINUX_DIR]
#
# A replica, not the Mac: bubblewrap builds a throwaway system in a user namespace (uid 0 inside,
# no network, the host's /usr/bin and /usr/lib read-only, everything else under a temp folder),
# and pacman installs small stand-in packages there from a repository on disk. The K114s tools
# run with their real paths (/usr/local/lib/omarchy-k114s, /etc/pacman.d/hooks, /boot/efi), so
# pacman runs the real hook files against real transactions. What is stood in for:
#   - the packages: a few bytes each, with the properties release-criteria.conf looks for
#   - the boot hooks: a script that writes a "boot image" and a menu entry per installed kernel
#     (limine-mkinitcpio), one that writes m1n1/boot.bin (update-m1n1), kernel-modules-hook's pair
#   - a boot: the EFI variable naming the booted image, the kernel release, a boot id
#   - free space on the EFI partition (K114S_ESP_FREE)
# It shows that the guards, the release steps and the rollback archives work as pacman
# transactions. It cannot show that any kernel boots.
# Needs bwrap (user namespaces), pacman, repo-add, vercmp, bsdtar, zstd, python3, findmnt, flock, iconv, rsync.
set -u
. "$(dirname "$0")/r3-lib.sh" "${1:-}"
skip() { echo "r3 pacman tests: SKIPPED ($1)"; exit 0; }
have bwrap pacman repo-add vercmp bsdtar zstd python3 findmnt flock iconv rsync || skip "bwrap, pacman, repo-add, vercmp, bsdtar, zstd, python3, findmnt, flock, iconv and rsync are needed"
bwrap --unshare-user --uid 0 --gid 0 --ro-bind / / true 2>/dev/null || skip "bubblewrap cannot make a user namespace here"
status() { echo $?; }
MB=1048576
S=$BASE/sys; P=$BASE/pkgs; mkdir -p "$P"
KLIB=$S/usr/local/lib/omarchy-k114s; ESPD=$S/boot/efi; STATE=$S/var/lib/omarchy-k114s
KOLD=7.3.0-17.v272-4-ARCH; KNEW=7.4.4-1-ARCH
banner() { echo "Linux version $1 (test@build) #1 SMP PREEMPT"; }
UNAME_R=$KOLD; ESP_FREE=$((300 * MB)); BOOT_ID=b0000001; AURA_TRIAL=

# --- the throwaway system -----------------------------------------------------------------------
mkdir -p "$S"/etc/pacman.d/hooks "$S"/etc/default "$S"/etc/k114s-test/sys/class/net/wlan0 "$S"/etc/k114s-test/proc/bus/input \
  "$S"/var/lib/pacman "$S"/var/cache/pacman/pkg "$S"/var/log "$S"/run "$ESPD"/EFI/Linux "$ESPD"/EFI/BOOT "$ESPD"/m1n1 "$ESPD"/k114s-repair \
  "$S"/usr/lib "$S"/usr/share/libalpm/hooks "$S"/usr/share/libalpm/scripts "$S"/usr/local/lib/omarchy-j714s "$S"/opt "$S"/people/owner "$S"/root
# /usr/lib: the host's entries as links, and real folders where packages install
find /usr/lib -mindepth 1 -maxdepth 1 -print0 | sed -z 's#^/usr/lib/#/host/usr/lib/#' | xargs -0 ln -s -t "$S/usr/lib/"
rm -f "$S"/usr/lib/libgallium-* "$S"/usr/lib/libvulkan_asahi.so
for d in modules firmware asahi-boot initcpio omarchy omarchy-hyprland-titlebars; do rm -f "$S/usr/lib/$d"; mkdir -p "$S/usr/lib/$d"; done
mkdir -p "$S/usr/lib/initcpio/install" "$S/usr/lib/omarchy/initcpio"
printf 'root:x:0:0:root:/root:/bin/bash\n' > "$S/etc/passwd"; printf 'root:x:0:\n' > "$S/etc/group"
echo 'CUSTOM_UKI_NAME="omarchy"' > "$S/etc/default/limine"
printf 'apple,k114s\0apple,t6050\0' > "$S/etc/k114s-test/compatible"
trackpad() { if [ "$1" = present ]; then mkdir -p "$S/etc/k114s-test/sys/bus/hid/drivers/magicmouse/0019:05AC:0361.0002"; printf 'I: Bus=0000\nN: Name="Apple MTP multi-touch"\n\n' > "$S/etc/k114s-test/proc/bus/input/devices"; else printf 'I: Bus=0000\nN: Name="Apple MTP keyboard"\n\n' > "$S/etc/k114s-test/proc/bus/input/devices"; fi; }
trackpad present
printf '#!/bin/bash\n# stands for sudo while "omarchy update" keeps its authorisation alive\n[[ ${1:-} != -n ]] || shift\nexec "$@"\n' > "$S/usr/local/lib/test-sudo"; chmod 755 "$S/usr/local/lib/test-sudo"
sb() { # run a command inside the throwaway system as its root
  bwrap --unshare-user --uid 0 --gid 0 --unshare-pid --unshare-net --unshare-ipc --die-with-parent --cap-add ALL \
    --tmpfs / --dir /usr --ro-bind /usr/bin /usr/bin --ro-bind /usr/lib /host/usr/lib --bind "$S/usr/lib" /usr/lib \
    --bind "$S/usr/share" /usr/share --bind "$S/usr/local" /usr/local \
    --symlink usr/bin /bin --symlink usr/bin /sbin --symlink usr/lib /lib --symlink usr/lib /lib64 \
    --proc /proc --dev /dev --tmpfs /tmp --ro-bind "$BASE" "$BASE" \
    --bind "$S/etc" /etc --bind "$S/var" /var --bind "$S/run" /run --bind "$S/boot" /boot --bind "$ESPD" /boot/efi \
    --bind "$S/opt" /opt --bind "$S/people" /people --bind "$S/root" /root --ro-bind "$L" "$L" --ro-bind "$T" "$T" \
    --setenv PATH /usr/bin --setenv HOME /root --setenv LC_ALL C --unsetenv K114S_ROOT \
    --setenv K114S_TEST 1 --setenv K114S_SIGCHECK "${SIGCHECK_STUB:-true}" --setenv K114S_UNAME_R "$UNAME_R" --setenv K114S_PROC_VERSION "$(banner "$UNAME_R")" --setenv K114S_ESP_FREE "$ESP_FREE" \
    --setenv K114S_EFI_STUB_ID /etc/k114s-test/stub-id --setenv K114S_ESP_DT /nonexistent --setenv K114S_NOTIFY_LOG /var/log/notify.log \
    --setenv K114S_BOOT_ID "$BOOT_ID" --setenv K114S_AURA_TRIAL "$AURA_TRIAL" --setenv K114S_DESKTOP yes --setenv K114S_SYS /etc/k114s-test/sys --setenv K114S_PROC /etc/k114s-test/proc \
    --setenv K114S_BOOT_WAIT 0 --setenv K114S_DT_COMPATIBLE /etc/k114s-test/compatible --setenv K114S_SYSTEMCTL /usr/bin/true \
    --setenv K114S_USER_HOME /people/owner --setenv K114S_HOLDS_WAIT 1 --setenv K114S_LOCK_WAIT "${LOCK_WAIT:-120}" --setenv K114S_SUDO "${SUDO_STUB:-/usr/local/lib/test-sudo}" --chdir / "$@" 2>&1
}
Q() { sb sh -c 'pacman -Q "$1" 2>/dev/null' _ "$1" | cut -d' ' -f2; }      # the installed version, or nothing
installed() { sb sh -c 'pacman -Qq 2>/dev/null' | grep -c -x "$1"; }      # by name only: pacman -Q also answers for a "provides"
update() { sb pacman -Syyu --noconfirm "$@"; }   # "omarchy update"'s transaction; -yy because the stand-in channel changes within a second
rel() { sb /usr/local/lib/omarchy-k114s/k114s-release "$@"; }
notes() { cat "$S/var/log/notify.log" 2>/dev/null; }
boot() { # boot IMAGE_REL RELEASE: the next start came from that boot image; /run is new, the boot units run. Sets $out.
  # The loader's one-boot trial: an armed aura-try is marked spent and its file booted once (chosen/aurora,trial).
  # HANG=1: that trial start hangs and the watchdog resets the Mac onto the configured Stage 2.
  AURA_TRIAL=
  if [ "$(sed -n 1p "$ESPD/aura-try" 2>/dev/null)" = armed ]; then
    AURA_TRIAL=$(sed -n 2p "$ESPD/aura-try"); printf 'spent\n%s\n' "$AURA_TRIAL" > "$ESPD/aura-try"
    [ -z "${HANG:-}" ] || AURA_TRIAL=
  fi
  printf '\6\0\0\0' > "$S/etc/k114s-test/stub-id"; printf '/%s' "$(printf '%s' "/$1" | tr / '\\')" | iconv -f ascii -t utf-16le >> "$S/etc/k114s-test/stub-id"
  UNAME_R=$2; BOOT_ID=b$(printf '%07d' $(( 10#${BOOT_ID#b} + 1 )))
  rm -rf "$S"/run/*
  sb /usr/local/lib/omarchy-k114s/k114s-modules-cleanup >/dev/null      # linux-modules-cleanup.service with the drop-in
  out=$(sb /usr/local/lib/omarchy-k114s/k114s-boot-success)             # k114s-boot-success.service
}
tree() { mktemp -d "$BASE/tree.XXXXXX"; }
default_title() { awk -v n="$(sed -n 's/^default_entry: //p' "$ESPD/limine.conf")" '/^[[:space:]]*\// { i++; if (i == n) { sub(/^[[:space:]]*\/+\+?/, ""); print } }' "$ESPD/limine.conf"; }

# stand-ins for the boot hooks of the installed system
cat > "$S/usr/share/libalpm/scripts/test-build-uki" <<'SCRIPT'
#!/bin/bash
# stand-in for limine-mkinitcpio-install: one boot image and one menu entry per package-owned kernel
# limine-entry-tool takes /run/lock/boot-partition.lock (the mutex limine-snapper-sync shares) around its writes; k114s-release must not hold it meanwhile
mkdir -p /run/lock; exec 200>/run/lock/boot-partition.lock
flock -w 5 200 || { echo "test-build-uki: Mutex lock timeout (somebody holds the boot partition lock through the transaction)" >&2; exit 1; }
for dir in /usr/lib/modules/*/; do
  dir=${dir%/}
  [[ -f $dir/modules.builtin ]] || continue
  name=$(pacman -Qqo "$dir/modules.builtin" 2>/dev/null) || continue
  uki=/boot/efi/EFI/Linux/omarchy_$name.efi
  { cat "$dir/vmlinuz"; echo "initramfs of ${dir##*/} built $(date +%s%N)"; } > "$uki.new" && mv -f "$uki.new" "$uki"
  grep -q "path: boot():/EFI/Linux/omarchy_$name.efi" /boot/efi/limine.conf ||
    printf '\n/+Omarchy\n  comment: Omarchy\n  //%s\n    comment: Kernel version: %s\n    protocol: efi\n    path: boot():/EFI/Linux/omarchy_%s.efi\n    cmdline: root=/dev/mapper/root rw quiet\n' "$name" "${dir##*/}" "$name" >> /boot/efi/limine.conf
  echo "test-build-uki: wrote $uki for ${dir##*/}"
done
SCRIPT
cat > "$S/usr/share/libalpm/scripts/test-update-m1n1" <<'SCRIPT'
#!/bin/bash
# stand-in for update-m1n1: m1n1 + the newest kernel's device trees + gzip U-Boot -> m1n1/boot.bin
dtbs=$(ls -d /usr/lib/modules/*-ARCH | sort -rV | head -n 1)/dtbs
{ cat /usr/lib/asahi-boot/m1n1.bin; cat "$dtbs"/*.dtb; gzip -c -n /usr/lib/asahi-boot/u-boot-nodtb.bin; } > /boot/efi/m1n1/boot.bin.new && mv -f /boot/efi/m1n1/boot.bin.new /boot/efi/m1n1/boot.bin
echo "test-update-m1n1: wrote m1n1/boot.bin with the trees of $dtbs"
SCRIPT
chmod 755 "$S"/usr/share/libalpm/scripts/test-*
hook() { # hook FILE WHEN EXEC TARGET...
  local file=$1 when=$2 exec=$3; shift 3
  { printf '[Trigger]\nType = Path\nOperation = Install\nOperation = Upgrade\n'; printf 'Target = %s\n' "$@"; printf '\n[Action]\nWhen = %s\nExec = %s\n' "$when" "$exec"; } > "$file"
}
# kernel-modules-hook's pair: the running kernel's modules are saved before a kernel transaction and put back after it
printf '#!/bin/sh\nif test -e "/usr/lib/modules/$K114S_UNAME_R"; then mkdir -p /usr/lib/modules/backup && cp -a "/usr/lib/modules/$K114S_UNAME_R" /usr/lib/modules/backup/; fi\n' > "$S/usr/share/libalpm/scripts/test-modules-save"
printf '#!/bin/sh\nif test -e "/usr/lib/modules/backup/$K114S_UNAME_R"; then rsync -a --ignore-existing "/usr/lib/modules/backup/$K114S_UNAME_R" /usr/lib/modules/; fi\nrm -rf /usr/lib/modules/backup\n' > "$S/usr/share/libalpm/scripts/test-modules-restore"
chmod 755 "$S"/usr/share/libalpm/scripts/test-modules-*
hook "$S/usr/share/libalpm/hooks/10-linux-modules-pre.hook" PreTransaction /usr/share/libalpm/scripts/test-modules-save 'usr/lib/modules/*/vmlinuz'
hook "$S/usr/share/libalpm/hooks/10-linux-modules-post.hook" PostTransaction /usr/share/libalpm/scripts/test-modules-restore 'usr/lib/modules/*/vmlinuz'
# Omarchy's 11-omarchy-mac-saved-modules.hook (omarchy-mac-retire-saved-modules): the same downgrade decision as the real script, which then
# moves the running kernel's modules to /usr/lib/modules/.old. (The real one reads uname -r; here K114S_UNAME_R.)
cat > "$S/usr/share/libalpm/scripts/test-saved-modules" <<'SCRIPT'
#!/bin/bash
installed=()
while IFS= read -r target; do [[ ! $target =~ ^usr/lib/modules/([^/]+)/vmlinuz$ ]] || installed+=("${BASH_REMATCH[1]}"); done
running=$K114S_UNAME_R
[[ -d /usr/lib/modules/$running ]] || exit 0
downgrade=0
for kver in "${installed[@]}"; do [[ $kver == "$running" || $(printf '%s\n' "$kver" "$running" | sort -V | head -n 1) != "$kver" ]] || downgrade=1; done
((downgrade)) || exit 0
echo "Moving the running kernel's saved modules ($running) to /usr/lib/modules/.old"
mkdir -p /usr/lib/modules/.old && cp -a "/usr/lib/modules/$running" /usr/lib/modules/.old/ && rm -rf "/usr/lib/modules/$running"
SCRIPT
chmod 755 "$S/usr/share/libalpm/scripts/test-saved-modules"
printf '[Trigger]\nType = Path\nOperation = Install\nOperation = Upgrade\nTarget = usr/lib/modules/*/vmlinuz\n\n[Action]\nWhen = PostTransaction\nExec = /usr/share/libalpm/scripts/test-saved-modules\nNeedsTargets\n' > "$S/usr/share/libalpm/hooks/11-omarchy-mac-saved-modules.hook"
hook "$S/usr/share/libalpm/hooks/90-mkinitcpio-install.hook" PostTransaction /usr/share/libalpm/scripts/test-build-uki 'usr/lib/modules/*/vmlinuz' 'usr/lib/firmware/*' 'usr/lib/initcpio/*'
hook "$S/usr/share/libalpm/hooks/95-m1n1-install.hook" PostTransaction /usr/share/libalpm/scripts/test-update-m1n1 'usr/lib/modules/*/dtbs/*' 'usr/lib/asahi-boot/*'
hook "$S/etc/pacman.d/hooks/96-omarchy-j714s-boot-ctxr.hook" PostTransaction /usr/local/lib/omarchy-j714s/update-boot-ctxr 'usr/lib/modules/*/dtbs/*' 'usr/lib/asahi-boot/*'
printf '#!/bin/sh\ncp /boot/efi/m1n1/boot.bin /boot/efi/m1n1/boot-ctxr.bin\n' > "$S/usr/local/lib/omarchy-j714s/update-boot-ctxr"; chmod 755 "$S/usr/local/lib/omarchy-j714s/update-boot-ctxr"
printf 'timeout: 5\ndefault_entry: 1\nquiet: no\n' > "$ESPD/limine.conf"
template "$S" edge

# --- the image's packages, installed before any guard exists ----------------------------------------
OLD_CONFIG='CONFIG_IKCONFIG=y'
t=$(tree); kernel_tree "$t" "$KOLD" k114s-bare "$OLD_CONFIG"; i_kernel=$(mkpkg "$t" linux-aurora 7.3.0.aurora17.v272-4 "$P")
t=$(tree); mkdir -p "$t/usr/lib/asahi-boot"; printf 'm1n1 v272\0apple,t6050\0apcie,t6050\0atc-phy,t6050\0' > "$t/usr/lib/asahi-boot/m1n1.bin"; i_m1n1=$(mkpkg "$t" m1n1-aurora 1.6.1.aurora24.v272-3 "$P")
t=$(tree); mkdir -p "$t/usr/lib/asahi-boot"; printf 'U-Boot j714s3\0apple,t6050-nvme-ans2\0apple,t6050-sart\0' > "$t/usr/lib/asahi-boot/u-boot-nodtb.bin"; i_uboot=$(mkpkg "$t" uboot-aurora 2026.07.aurora6.j714s3-1 "$P")
fw_tree() { local t; t=$(tree); mkdir -p "$t/usr/lib/omarchy/initcpio" "$t/usr/lib/initcpio/install"
  printf 'case "$compatible" in\n  %s) modprobe apple_centauri_t6050 ;;\nesac\n' "$1" > "$t/usr/lib/omarchy/initcpio/aurora-peripheral-firmware.sh"
  printf 'build() {\n  add_module apple_centauri\n}\n' > "$t/usr/lib/initcpio/install/aurora-vendor-order"; echo "$t"; }
i_fw=$(mkpkg "$(fw_tree 'apple,j714s')" omarchy-aurora-firmware 20261014.j714s9-1 "$P")
gfx() { local t; t=$(tree); mkdir -p "$t/usr/lib"; printf '%s\0' $3 > "$t/usr/lib/$1"; mkpkg "$t" "$2" "$4" "$P"; }
i_mesa=$(gfx libgallium-99.0.0-test.so mesa-aurora "gallium-j714s2 G17S" 1:26.3.0_devel.20261109.j714s2.043a4c5-1)
i_vulkan=$(gfx libvulkan_asahi.so vulkan-aurora "vulkan-j714s2 G17S" 1:26.3.0_devel.20261109.j714s2.043a4c5-1)
t=$(tree); mkdir -p "$t/opt/hypr"; echo "Hyprland m5" > "$t/opt/hypr/Hyprland"; i_hypr=$(MKPKG_EXTRA=$'provides = hyprland=0.57.2\nconflict = hyprland' mkpkg "$t" hyprland-m5 0.57.2-2 "$P")
tb() { local t; t=$(tree); mkdir -p "$t/usr/lib/omarchy-hyprland-titlebars" "$t/opt/titlebars"; echo "$1" > "$t/usr/lib/omarchy-hyprland-titlebars/titlebars.so"; echo "readme $2" > "$t/opt/titlebars/README"; mkpkg "$t" omarchy-hyprland-titlebars "$2" "$P" "$3"; }
i_tb=$(tb "plugin for stock Hyprland" 0.4.0-1 "hyprland>=0.57")
t=$(tree); mkdir -p "$t/opt/omarchy"; echo dev > "$t/opt/omarchy/version"; i_omarchy=$(MKPKG_EXTRA=$'provides = omarchy\nconflict = omarchy' mkpkg "$t" omarchy-dev 4.0.0.r7859-1 "$P")
t=$(tree); mkdir -p "$t/opt/omarchy-settings"; echo dev > "$t/opt/omarchy-settings/version"; i_settings=$(MKPKG_EXTRA=$'provides = omarchy-settings\nconflict = omarchy-settings' mkpkg "$t" omarchy-settings-dev 4.0.0.r7859-1 "$P")
app() { local t; t=$(tree); mkdir -p "$t/opt/demo"; echo "app $1" > "$t/opt/demo/app"; mkpkg "$t" demo-app "$1" "$P"; }
i_app=$(app 1.0-1)
lfw() { local t; t=$(tree); mkdir -p "$t/usr/lib/firmware/brcm"; echo "fw $1" > "$t/usr/lib/firmware/brcm/x.bin"; mkpkg "$t" linux-firmware "$1" "$P"; }
i_lfw=$(lfw 1-1)
out=$(sb pacman -U --noconfirm "$i_kernel" "$i_m1n1" "$i_uboot" "$i_fw" "$i_mesa" "$i_vulkan" "$i_hypr" "$i_tb" "$i_omarchy" "$i_settings" "$i_app" "$i_lfw")
ok "replica: the image's packages install with a real pacman" "$? $(sb sh -c 'pacman -Qq 2>/dev/null' | wc -l | tr -d ' ')" "0 12"
ok "replica: the boot hooks wrote a boot image, a menu entry and m1n1/boot.bin" "$(test -s "$ESPD/EFI/Linux/omarchy_linux-aurora.efi" && test -s "$ESPD/m1n1/boot.bin" && grep -c 'omarchy_linux-aurora.efi' "$ESPD/limine.conf")" 1

# --- what bundle r2c left: repair image as the default entry, pinned tree, its persistence ---------------
kernel_image "$ESPD/EFI/Linux/omarchy_linux-aurora-k114s.efi" "$KOLD" "$OLD_CONFIG" "K114S-R1 clamping Report Size"
python3 -I "$T/mkfdt.py" "$ESPD/k114s-repair/k114s.dtb" k114s-full
python3 -I - "$ESPD/limine.conf" <<'PY'
import sys
lines = open(sys.argv[1]).read().split("\n")
first = next(i for i, l in enumerate(lines) if l.startswith("/"))
block = ["### K114s repair (added from macOS; remove this block to undo)", "/Omarchy K114s repair r1 (trackpad fix B)",
         "  comment: K114s repair kernel", "  protocol: efi", "  path: boot():/EFI/Linux/omarchy_linux-aurora-k114s.efi",
         "  cmdline: root=/dev/mapper/root rw quiet", ""]
open(sys.argv[1], "w").write("\n".join(lines[:first] + block + lines[first:]))
PY
kernel_image "$S/usr/lib/modules/$KOLD/vmlinuz" "$KOLD" "$OLD_CONFIG" "K114S-R1 clamping Report Size"      # the repair kernel over the packaged one
mkdir -p "$S/usr/lib/modules/$KOLD/updates" "$KLIB/persist-r2c" "$S/people/owner/.config/omarchy/hooks/pre-refresh-pacman.d"
echo "patched module" > "$S/usr/lib/modules/$KOLD/updates/hid-magicmouse.ko"
cp "$L"/apply-holds "$L"/hold-guard "$L"/esp-space-guard "$L"/k114s-booted-esp "$L"/k114s-edge-check "$KLIB/"
git -C "$L" show HEAD:linux/update-boot-ctxr-k114s > "$KLIB/update-boot-ctxr" 2>/dev/null && [ -s "$KLIB/update-boot-ctxr" ] || cp "$L/update-boot-ctxr-k114s" "$KLIB/update-boot-ctxr"
chmod 755 "$KLIB"/*; cp "$ESPD/k114s-repair/k114s.dtb" "$KLIB/k114s.dtb"
cp "$L/00-k114s-hold-guard.hook" "$L/01-k114s-esp-space.hook" "$S/etc/pacman.d/hooks/"
cp "$S/usr/local/lib/omarchy-j714s/update-boot-ctxr" "$KLIB/persist-r2c/j714s-hook-script.orig"
printf '#!/bin/sh\nexec /usr/local/lib/omarchy-k114s/update-boot-ctxr "$@"\n' > "$S/usr/local/lib/omarchy-j714s/update-boot-ctxr"
printf '%s\n' asahi-fwextract asahi-scripts aurora-sep aurora-speaker-upgrade hyprland-m5 libfprint-aurora limine linux-aurora m1n1-aurora mesa-aurora omarchy \
  omarchy-aurora-firmware omarchy-hyprland-titlebars omarchy-mac omarchy-mac-boot omarchy-settings speakerguardd-v2 uboot-aurora vulkan-aurora > "$KLIB/holds.list"
printf '#!/bin/bash\nsudo /usr/local/lib/omarchy-k114s/apply-holds\n' > "$S/people/owner/.config/omarchy/hooks/pre-refresh-pacman.d/k114s-holds"
sb /usr/local/lib/omarchy-k114s/apply-holds >/dev/null
sb /usr/local/lib/omarchy-k114s/update-boot-ctxr >/dev/null
mv "$S/usr/lib/omarchy-hyprland-titlebars/titlebars.so" "$S/usr/lib/omarchy-hyprland-titlebars/titlebars.so.moved-aside"    # 2026-11-14: plugin moved aside
printf '\6\0\0\0' > "$S/etc/k114s-test/stub-id"; printf '/\\EFI\\Linux\\omarchy_linux-aurora-k114s.efi' | iconv -f ascii -t utf-16le >> "$S/etc/k114s-test/stub-id"
STAGE2_R2C=$(sum "$ESPD/m1n1/boot-ctxr.bin"); REPAIR=$(sum "$ESPD/EFI/Linux/omarchy_linux-aurora-k114s.efi")
ok "replica: r2c's Stage 2 carries exactly one device tree, the pinned one" "$(grep -c -a 'apple,centauri-platform-id' "$ESPD/m1n1/boot-ctxr.bin") $(grep -c -a 'apple,j714s' "$ESPD/m1n1/boot-ctxr.bin")" "1 0"

# --- the installer, over r2c's persistence -------------------------------------------------------------------
out=$(sb bash "$L/k114s-tooling-install"); ok "installer runs over r2c's persistence" "$? $(echo "$out" | grep -c 'k114s-tooling-install: installed')" "0 1"
ok "the three r3 hooks are in, r2c's two are out" "$(ls "$S/etc/pacman.d/hooks" | grep -c -E '^(00-k114s-guard-(install|remove)|01-k114s-guard-esp)\.hook$') $(ls "$S/etc/pacman.d/hooks" | grep -c -E 'k114s-hold-guard|k114s-esp-space')" "3 0"
ok "holds: the installed ones of what was held, plus the default set" "$(tr '\n' ' ' < "$KLIB/holds.list")" "hyprland-m5 linux-aurora m1n1-aurora mesa-aurora omarchy-aurora-firmware omarchy-hyprland-titlebars uboot-aurora vulkan-aurora "
ok "pacman reads the holds" "$(sb pacman-conf IgnorePkg | tr '\n' ' ')" "hyprland-m5 linux-aurora m1n1-aurora mesa-aurora omarchy-aurora-firmware omarchy-hyprland-titlebars uboot-aurora vulkan-aurora "
ok "the running boot chain is recorded as proven" "$(awk '$1 == "uki" || $1 == "stage2_sha256" { print $2 }' "$STATE/release/known-good" | tr '\n' ' ')" "EFI/Linux/omarchy_linux-aurora-k114s.efi $STAGE2_R2C "
set_dir=$(ls -d "$STATE"/recovery/*-install 2>/dev/null | head -n 1)
ok "a recovery set of every held package was written at install" "$(ls "$set_dir/packages" 2>/dev/null | grep -c 'pkg.tar.zst$') $(cd "$set_dir" && sha256sum --quiet -c SHA256SUMS >/dev/null 2>&1; status)" "10 0"
ok "its kernel archive holds the repair kernel, and says so" "$(bsdtar -xOf "$set_dir"/packages/linux-aurora-*.zst "usr/lib/modules/$KOLD/vmlinuz" | grep -c -a K114S-R1) $(grep -c "^  usr/lib/modules/$KOLD/vmlinuz$" "$set_dir"/packages/linux-aurora-*.repackage.txt)" "1 1"
ok "the space guard knows every boot hook of this system" "$(sb /usr/local/lib/omarchy-k114s/k114s-guard audit >/dev/null; status)" 0
ok "both user hooks are installed" "$(ls "$S/people/owner/.config/omarchy/hooks/pre-refresh-pacman.d/k114s-holds" "$S/people/owner/.config/omarchy/hooks/post-update.d/k114s-release-check" 2>/dev/null | wc -l | tr -d ' ')" 2
ok "r2c's command name still works (apply-holds forwards to k114s-holds)" "$(sb /usr/local/lib/omarchy-k114s/apply-holds --show | head -n 1) $(sb /usr/local/lib/omarchy-k114s/apply-holds; status)" "hyprland-m5 0"
out=$(sb bash "$L/k114s-tooling-install"); ok "a second install is refused" "$(echo "$out" | grep -c 'already installed')" 1
out=$(rel status); ok "status: proven chain intact and running" "$(echo "$out" | grep -c -E 'intact and running|the holds are in place|trial:     none')" 3

# --- today's channel: older generic builds, and an ordinary update ---------------------------------------------
t=$(tree); kernel_tree "$t" 7.2.11-16-ARCH none "$OLD_CONFIG"; c_kernel_old=$(mkpkg "$t" linux-aurora 7.2.11.aurora16-1 "$P")
t=$(tree); mkdir -p "$t/usr/lib/asahi-boot"; echo "stock m1n1 apple,t6040" > "$t/usr/lib/asahi-boot/m1n1.bin"; c_m1n1_old=$(mkpkg "$t" m1n1-aurora 1.6.1.aurora23-2 "$P")
c_fw_old=$(mkpkg "$(fw_tree 'apple,j714s')" omarchy-aurora-firmware 20261014-7 "$P")
c_mesa_old=$(gfx libgallium-99.0.0-test.so mesa-aurora "gallium-stock" 1:26.3.0_devel.20261107.231485.b7b03c5b3b8-2)
c_app2=$(app 2.0-1); c_lfw2=$(lfw 2-1)
mkrepo edge "$c_kernel_old" "$c_m1n1_old" "$c_fw_old" "$c_mesa_old" "$c_app2"
state() { sb sh -c 'pacman -Q 2>/dev/null' | grep -E '^(linux-aurora|m1n1-aurora|uboot-aurora|omarchy-aurora-firmware|mesa-aurora|vulkan-aurora|hyprland-m5|omarchy-hyprland-titlebars|omarchy-dev|omarchy-settings-dev) ' | sha256sum | cut -c1-16; }
held_before=$(state)
ESP_FREE=$((1 * MB)); out=$(update)
ok "an ordinary update goes through with a FULL EFI partition (it cannot write there)" "$? $(Q demo-app)" "0 2.0-1"
ok "the space guard did not even run" "$(echo "$out" | grep -c 'checking free space on the EFI partition')" 0
ok "the hold guard did" "$(echo "$out" | grep -c 'K114s: checking the held packages and the channel')" 1
ok "no held package changed" "$(state)" "$held_before"
mkrepo edge "$c_kernel_old" "$c_m1n1_old" "$c_fw_old" "$c_mesa_old" "$c_app2" "$c_lfw2"
out=$(update); ok "an update that rebuilds the boot image is stopped while the EFI partition is full" "$? $(Q linux-firmware)" "1 1-1"
ok "by the space guard, with the sum" "$(echo "$out" | grep -c -E 'K114s space guard: stopped|boot image for linux-aurora|margin kept free: 8 MB')" 3
ESP_FREE=$((300 * MB)); image_before=$(sum "$ESPD/EFI/Linux/omarchy_linux-aurora.efi")
out=$(update); ok "with room it goes through" "$? $(Q linux-firmware)" "0 2-1"
ok "and the boot image was rebuilt by the system's hook" "$(test "$(sum "$ESPD/EFI/Linux/omarchy_linux-aurora.efi")" != "$image_before"; status)" 0
ok "the repair image and Stage 2 are untouched" "$(sum "$ESPD/EFI/Linux/omarchy_linux-aurora-k114s.efi") $(sum "$ESPD/m1n1/boot-ctxr.bin")" "$REPAIR $STAGE2_R2C"

# --- the 2026-11-14 incident, replayed -----------------------------------------------------------------------
template "$S" edge                                    # the refresh's template: no IgnorePkg
out=$(sb pacman -Syyuu --noconfirm); ok "channel refresh without holds: the hold guard stops the downgrade" "$?" 1
ok "it names the four packages the channel would downgrade" "$(echo "$out" | grep -A1 'holds at their present build' | tail -n 1 | tr -s ' ')" " linux-aurora m1n1-aurora mesa-aurora omarchy-aurora-firmware"
ok "nothing changed: packages" "$(state)" "$held_before"
ok "nothing changed: Stage 2 and the boot images" "$(sum "$ESPD/m1n1/boot-ctxr.bin") $(sum "$ESPD/EFI/Linux/omarchy_linux-aurora-k114s.efi")" "$STAGE2_R2C $REPAIR"
out=$(sb env HOME=/people/owner bash /people/owner/.config/omarchy/hooks/pre-refresh-pacman.d/k114s-holds); ok "the pre-refresh hook puts the holds back" "$? $(sb /usr/local/lib/omarchy-k114s/k114s-holds check >/dev/null; status)" "0 0"
out=$(sb pacman -Syyuu --noconfirm); ok "the same refresh with holds: pacman ignores the downgrades, exit 0" "$? $(state)" "0 $held_before"
ok "pacman says it skipped them" "$(echo "$out" | grep -c -E 'linux-aurora: ignoring package (downgrade|upgrade)')" 1
out=$(sb pacman -S --noconfirm linux-aurora); ok "a named install of a held package (pacman would say yes): stopped" "$? $(state)" "1 $held_before"
out=$(sb pacman -Rdd --noconfirm uboot-aurora); ok "a forced removal: stopped" "$? $(Q uboot-aurora)" "1 2026.07.aurora6.j714s3-1"
out=$(sb pacman -R --noconfirm demo-app); ok "removing an ordinary package is not our business" "$? $(Q demo-app)" "0 "
sb pacman -S --noconfirm demo-app >/dev/null

# --- a channel switch to stable, and omarchy reinstall -----------------------------------------------------------
t=$(tree); mkdir -p "$t/opt/omarchy"; echo stable > "$t/opt/omarchy/version"; s_omarchy=$(MKPKG_EXTRA=$'conflict = omarchy-dev\nprovides = omarchy-dev' mkpkg "$t" omarchy 4.5.0-3 "$P")
t=$(tree); mkdir -p "$t/opt/omarchy-settings"; echo stable > "$t/opt/omarchy-settings/version"; s_settings=$(MKPKG_EXTRA=$'conflict = omarchy-settings-dev\nprovides = omarchy-settings-dev' mkpkg "$t" omarchy-settings 4.5.0-3 "$P")
s_app=$(app 1.5-1)
mkrepo stable "$s_omarchy" "$s_settings" "$s_app"
template "$S" stable; sb env HOME=/people/owner bash /people/owner/.config/omarchy/hooks/pre-refresh-pacman.d/k114s-holds >/dev/null
out=$(sb pacman -Syyuu --noconfirm --ignore omarchy-dev,omarchy-settings-dev); ok "switch to stable: the refresh's downgrade is stopped by the channel guard" "$? $(Q demo-app)" "1 2.0-1"
ok "it says which channel" "$(echo "$out" | grep -c 'K114s channel guard: stopped')" 1
out=$(sb pacman -S --needed --noconfirm --ask 4 omarchy omarchy-settings); ok "switch to stable: the omarchy-dev -> omarchy swap is stopped" "$? $(Q omarchy-dev) $(installed omarchy)" "1 4.0.0.r7859-1 0"
: > "$S/etc/omarchy-k114s/allow-channel-change"
out=$(sb pacman -S --needed --noconfirm --ask 4 omarchy omarchy-settings); ok "even with the channel allowed, removing the Edge desktop needs its own decision" "$? $(echo "$out" | grep -c 'would remove or replace')" "1 1"
rm "$S/etc/omarchy-k114s/allow-channel-change"
template "$S" edge; sb /usr/local/lib/omarchy-k114s/k114s-holds apply >/dev/null; sb pacman -Syy >/dev/null
t=$(tree); mkdir -p "$t/opt/hypr"; echo "stock Hyprland" > "$t/opt/hypr/Hyprland"; c_hyprland=$(MKPKG_EXTRA=$'conflict = hyprland-m5' mkpkg "$t" hyprland 0.57.2-1 "$P")
c_tb_stock=$(tb "plugin for stock Hyprland, newer" 0.4.1-1 "hyprland>=0.57")
mkrepo edge "$c_kernel_old" "$c_m1n1_old" "$c_fw_old" "$c_mesa_old" "$c_app2" "$c_lfw2" "$c_hyprland" "$c_tb_stock"
out=$(update --ask 4 --needed hyprland demo-app omarchy-hyprland-titlebars)
ok "omarchy reinstall (installs the default 'hyprland' over hyprland-m5): stopped" "$? $(Q hyprland-m5) $(installed hyprland)" "1 0.57.2-2 0"
ok "the guard names the rival and the plugin" "$(echo "$out" | grep -A1 'holds at their present build' | tail -n 1 | tr -s ' ')" " hyprland omarchy-hyprland-titlebars"

# --- the title-bar plugin: kept out until the build against hyprland-m5 is installed ------------------------------
: > "$S/etc/omarchy-k114s/allow-coupled-update"
out=$(sb pacman -S --noconfirm omarchy-hyprland-titlebars); ok "with the owner's override the channel's plugin package installs" "$? $(Q omarchy-hyprland-titlebars)" "0 0.4.1-1"
rm "$S/etc/omarchy-k114s/allow-coupled-update"
ok "but pacman does not extract the stock-ABI plugin file (NoExtract)" "$(test -e "$S/usr/lib/omarchy-hyprland-titlebars/titlebars.so"; status) $(cat "$S/opt/titlebars/README")" "1 readme 0.4.1-1"
m5_tb=$(tb "plugin built against hyprland-m5" 1:0.4.0+m5-1 "hyprland-m5=0.57.2-2")
out=$(rel adopt "$m5_tb"); ok "adopt: the rebuilt plugin installs through the guard" "$? $(Q omarchy-hyprland-titlebars)" "0 1:0.4.0+m5-1"
ok "adopt: its plugin file is extracted" "$(cat "$S/usr/lib/omarchy-hyprland-titlebars/titlebars.so")" "plugin built against hyprland-m5"
ok "adopt: the package stays held, and NoExtract is no longer needed" "$(sb pacman-conf IgnorePkg | grep -c -x omarchy-hyprland-titlebars) $(grep -c '^NoExtract' "$S/etc/pacman.conf")" "1 0"
ok "adopt: the permit and the lift are gone" "$(ls "$S/run/omarchy-k114s" 2>/dev/null | wc -l | tr -d ' ')" 0
ok "adopt: the replaced build is kept as an archive" "$(ls "$STATE"/rollback/*-adopt-omarchy-hyprland-titlebars/packages/ | grep -c '^omarchy-hyprland-titlebars-0.4.1-1-any.pkg.tar.zst$')" 1
out=$(update); ok "an update leaves the adopted plugin alone (epoch above the channel's)" "$? $(Q omarchy-hyprland-titlebars)" "0 1:0.4.0+m5-1"
out=$(rel adopt "$L/k114s-guard"); ok "adopt refuses a file that is not a package" "$? $(echo "$out" | grep -c 'is not a package')" "1 1"
out=$(rel adopt "$c_app2"); ok "adopt refuses a package that is not held" "$? $(echo "$out" | grep -c 'is not held')" "1 1"

# --- release: a userland package ------------------------------------------------------------------------------------
held_before=$(state)
out=$(rel auto); ok "auto with today's channel: nothing released" "$? $(state)" "0 $held_before"
c_mesa_good=$(gfx libgallium-99.0.0-test.so mesa-aurora "gallium-channel G14S G17S ASAHI_M5_BRINGUP llvmpipe" 1:26.3.0_devel.20261201.aaaaaaa-1)
c_vulkan_bad=$(gfx libvulkan_asahi.so vulkan-aurora "vulkan-channel G14S" 1:26.3.0_devel.20261201.aaaaaaa-1)
mkrepo edge "$c_kernel_old" "$c_m1n1_old" "$c_fw_old" "$c_app2" "$c_lfw2" "$c_mesa_good" "$c_vulkan_bad"
update >/dev/null; ok "the fixed Mesa is in the channel but held: an update leaves it" "$(Q mesa-aurora)" "1:26.3.0_devel.20261109.j714s2.043a4c5-1"
sed -i 's/^AUTO_RELEASE=.*/AUTO_RELEASE=no/' "$S/etc/omarchy-k114s/release.conf"
out=$(rel auto); ok "AUTO_RELEASE=no: reports, releases nothing" "$(Q mesa-aurora) $(echo "$out" | grep -c 'release with: sudo k114s-release release mesa-aurora')" "1:26.3.0_devel.20261109.j714s2.043a4c5-1 1"
sed -i 's/^AUTO_RELEASE=.*/AUTO_RELEASE=yes/' "$S/etc/omarchy-k114s/release.conf"
out=$(rel auto); ok "AUTO_RELEASE_GPU=no (the default): the GPU stack is reported, not switched unattended" "$(Q mesa-aurora) $(echo "$out" | grep -c 'not switched unattended (AUTO_RELEASE_GPU=no); release with: sudo k114s-release release mesa-aurora')" "1:26.3.0_devel.20261109.j714s2.043a4c5-1 1"
# the rest of this file exercises the unattended GPU path itself
echo AUTO_RELEASE_GPU=yes >> "$S/etc/omarchy-k114s/release.conf"; : > "$S/var/log/notify.log"
# through the user hook, as omarchy update runs it
out=$(SUDO_STUB=/usr/bin/false sb env HOME=/people/owner bash /people/owner/.config/omarchy/hooks/post-update.d/k114s-release-check)
ok "post-update hook without sudo: checks as the user, tells, changes nothing" "$? $(Q mesa-aurora) $(echo "$out" | grep -c 'ready for release: mesa-aurora')" "0 1:26.3.0_devel.20261109.j714s2.043a4c5-1 1"
out=$(sb env HOME=/people/owner bash /people/owner/.config/omarchy/hooks/post-update.d/k114s-release-check)
ok "post-update hook: the fixed Mesa is installed" "$? $(Q mesa-aurora)" "0 1:26.3.0_devel.20261201.aaaaaaa-1"
ok "the files are the channel's" "$(tr '\0' ' ' < "$S/usr/lib/libgallium-99.0.0-test.so")" "gallium-channel G14S G17S ASAHI_M5_BRINGUP llvmpipe "
ok "Vulkan without the M5 Pro driver stays held at our build" "$(Q vulkan-aurora) $(sb pacman-conf IgnorePkg | grep -c -x vulkan-aurora)" "1:26.3.0_devel.20261109.j714s2.043a4c5-1 1"
ok "Mesa is installed but STAYS held (keep-held): the next channel build is checked again, nothing is released for good" "$(sb pacman-conf IgnorePkg | grep -c -x mesa-aurora) $(cat "$KLIB/released.list" 2>/dev/null | grep -c mesa-aurora)" "1 0"
ok "a desktop notification says so" "$(notes | grep -c 'mesa-aurora installed (it stays held: the next channel build is checked again): now 1:26.3.0_devel.20261201.aaaaaaa-1')" 1
ok "the permit is gone" "$(test -e "$S/run/omarchy-k114s/permit"; status)" 1
roll=$(ls -d "$STATE"/rollback/*-mesa-aurora); archive=$(ls "$roll"/packages/mesa-aurora-*.pkg.tar.zst)
ok "the rollback set holds our Mesa as a package" "$(sb pacman -Qp "$archive")" "mesa-aurora 1:26.3.0_devel.20261109.j714s2.043a4c5-1"
ok "no boot image in a userland rollback set, but the hashes of the whole EFI partition" "$(ls "$roll/esp" | tr '\n' ' ') $(grep -c 'omarchy_linux-aurora-k114s.efi' "$roll/esp-files.sha256")" "k114s-repair limine.conf m1n1  1"
c_mesa_next=$(gfx libgallium-99.0.0-test.so mesa-aurora "gallium-channel-next G17S ASAHI_M5_BRINGUP llvmpipe" 1:26.3.0_devel.20261210.bbbbbbb-1)
mkrepo edge "$c_kernel_old" "$c_m1n1_old" "$c_fw_old" "$c_app2" "$c_lfw2" "$c_mesa_next" "$c_vulkan_bad"
out=$(update); ok "an ordinary update does not move Mesa to the next channel build: it is held, and the check decides" "$? $(Q mesa-aurora)" "0 1:26.3.0_devel.20261201.aaaaaaa-1"
out=$(rel auto); ok "the next auto run checks that build again and installs it (it carries the gate)" "$? $(Q mesa-aurora) $(sb pacman-conf IgnorePkg | grep -c -x mesa-aurora)" "0 1:26.3.0_devel.20261210.bbbbbbb-1 1"
# the way back: the archive, through adopt (a held package; pacman -U by hand is stopped by the guard)
out=$(sb pacman -U --noconfirm "$archive"); ok "rollback by a bare pacman -U is stopped by the guard: the package is held" "$? $(Q mesa-aurora)" "1 1:26.3.0_devel.20261210.bbbbbbb-1"
ok "the notification names the way back that works" "$(notes | grep -c 'Rollback: sudo k114s-release adopt .*/packages/mesa-aurora-')" 2
out=$(rel adopt "$archive"); ok "rollback: k114s-release adopt installs the archive, and the package stays held" "$? $(Q mesa-aurora) $(sb pacman-conf IgnorePkg | grep -c -x mesa-aurora)" "0 1:26.3.0_devel.20261109.j714s2.043a4c5-1 1"
ok "rollback: the file is ours again, byte for byte" "$(tr '\0' ' ' < "$S/usr/lib/libgallium-99.0.0-test.so")" "gallium-j714s2 G17S "
ok "rollback: pacman finds nothing wrong with the reinstalled package" "$(sb pacman -Qkk mesa-aurora | grep -c ' 0 altered files')" 1
sb /usr/local/lib/omarchy-k114s/k114s-holds hold mesa-aurora >/dev/null; ok "and it is held (still)" "$(sb pacman-conf IgnorePkg | grep -c -x mesa-aurora)" 1
ok "adopting over a GPU build that is on trial ends the trial and auto does not put that build back" "$(test -e "$STATE/release/gpu-trial"; status) $(grep -c '^mesa-aurora 1:26.3.0_devel.20261210.bbbbbbb-1$' "$STATE/release/gpu-given-up")" "1 1"
held_before=$(state)

# --- release: the boot chain, never in one step -----------------------------------------------------------------------
t=$(tree); kernel_tree "$t" "$KNEW" k114s-full "$GOOD_CONFIG" "clamping Report Size"; c_kernel=$(mkpkg "$t" linux-aurora 7.4.4.aurora18-1 "$P")
c_fw=$(mkpkg "$(fw_tree 'apple,j714s|apple,k114s|apple,k116s')" omarchy-aurora-firmware 20261201-1 "$P")
t=$(tree); mkdir -p "$t/usr/lib/asahi-boot"; printf 'm1n1 channel\0apple,t6050\0apcie,t6050\0atc-phy,t6050\0' > "$t/usr/lib/asahi-boot/m1n1.bin"; c_m1n1=$(mkpkg "$t" m1n1-aurora 1.7.0.aurora25-1 "$P")
mkrepo edge "$c_kernel" "$c_fw" "$c_m1n1" "$c_app2" "$c_lfw2" "$c_vulkan_bad"
out=$(update); ok "fixed kernel, firmware and loader in the channel, all held: the update leaves them" "$? $(state)" "0 $held_before"
bootbin_before=$(sum "$ESPD/m1n1/boot.bin"); : > "$S/var/log/notify.log"
ESP_FREE=$((5 * MB)); out=$(rel auto); ok "no room on the EFI partition: the release waits, nothing changes" "$(state) $(echo "$out" | grep -c 'waits for room on the ESP')" "$held_before 1"
ok "waiting wrote no rollback set and no trial" "$(ls "$STATE/rollback" | grep -c -- '-boot$') $(test -e "$STATE/release/trial"; status)" "0 1"
# a transaction pacman refuses (a file in the way): nothing is half done
ESP_FREE=$((300 * MB)); mkdir -p "$S/usr/lib/modules/$KNEW"; echo "in the way" > "$S/usr/lib/modules/$KNEW/vmlinuz"
out=$(rel auto); ok "a transaction pacman refuses: the packages are held again at their old builds" "$(state) $(echo "$out" | grep -c 'the transaction did not go through')" "$held_before 1"
ok "refused transaction: no trial, no freeze, no keep list, proven files untouched" "$(test -e "$STATE/release/trial"; status) $(test -e "$S/etc/omarchy-k114s/stage2-frozen"; status) $(cat "$S/etc/omarchy-k114s/keep-modules" | wc -w | tr -d ' ') $(sum "$ESPD/EFI/Linux/omarchy_linux-aurora-k114s.efi") $(sum "$ESPD/m1n1/boot-ctxr.bin")" "1 1 0 $REPAIR $STAGE2_R2C"
ok "refused transaction: pacman's own words are kept" "$(grep -c 'exists in filesystem' "$STATE"/rollback/*-boot/pacman.log)" 1
rm -rf "$S/usr/lib/modules/$KNEW" "$STATE"/rollback/*-boot; : > "$S/var/log/notify.log"
out=$(rel auto); ok "auto: the fixed boot packages are installed" "$? $(Q linux-aurora) $(Q omarchy-aurora-firmware) $(Q m1n1-aurora)" "0 7.4.4.aurora18-1 20261201-1 1.7.0.aurora25-1"
ok "U-Boot is not in the channel and stays as it is" "$(Q uboot-aurora)" "2026.07.aurora6.j714s3-1"
ok "the proven boot image is byte for byte what it was" "$(sum "$ESPD/EFI/Linux/omarchy_linux-aurora-k114s.efi")" "$REPAIR"
ok "Stage 2 is byte for byte what it was (frozen)" "$(sum "$ESPD/m1n1/boot-ctxr.bin") $(test -s "$S/etc/omarchy-k114s/stage2-frozen"; status)" "$STAGE2_R2C 0"
ok "although the loader package's hook ran (m1n1/boot.bin is new)" "$(test "$(sum "$ESPD/m1n1/boot.bin")" != "$bootbin_before"; status) $(grep -c 'Stage 2 is managed by k114s-release' "$STATE"/rollback/*-boot/pacman.log)" "0 1"
ok "the new kernel came up as an additional boot image" "$(grep -a -o -m1 'Linux version [0-9][^ ]*' "$ESPD/EFI/Linux/omarchy_linux-aurora.efi")" "Linux version $KNEW"
ok "the default menu entry is still the proven one" "$(default_title)" "Omarchy K114s repair r1 (trackpad fix B)"
ok "both entries are in the menu" "$(grep -c -E 'path: boot\(\):/EFI/Linux/omarchy_linux-aurora(-k114s)?\.efi' "$ESPD/limine.conf")" 2
ok "a trial is recorded" "$(awk '$1 == "kind" || $1 == "uki" || $1 == "old_release" { print $2 }' "$STATE/release/trial" | tr '\n' ' ')" "uki EFI/Linux/omarchy_linux-aurora.efi $KOLD "
ok "the proven kernel's modules are still there (put back by the system's hook), and on the keep list" "$(test -s "$S/usr/lib/modules/$KOLD/updates/hid-magicmouse.ko" && test -s "$S/usr/lib/modules/$KOLD/kernel/drivers/hid/hid-magicmouse.ko.zst"; status) $(cat "$S/etc/omarchy-k114s/keep-modules")" "0 $KOLD"
ok "all stay held: the three were installed under the permit, none was released" "$(sb pacman-conf IgnorePkg | tr '\n' ' ') $(cat "$KLIB/released.list" 2>/dev/null | wc -l | tr -d ' ')" "hyprland-m5 linux-aurora m1n1-aurora mesa-aurora omarchy-aurora-firmware omarchy-hyprland-titlebars uboot-aurora vulkan-aurora  0"
ok "the notification says how to try it and that nothing old is removed" "$(notes | grep -c -E 'ADDITIONAL boot entry.*The proven entry is still the default.*Nothing old is removed until it has booted')" 1
boot_roll=$(ls -d "$STATE"/rollback/*-boot)
ok "rollback set: the three old packages, the proven image, Stage 2" "$(ls "$boot_roll/packages" | grep -c 'pkg.tar.zst$') $(sum "$boot_roll/esp/EFI/Linux/omarchy_linux-aurora-k114s.efi") $(sum "$boot_roll/esp/m1n1/boot-ctxr.bin")" "3 $REPAIR $STAGE2_R2C"
out=$(rel auto); ok "auto again before a restart: waits, stages nothing twice" "$(echo "$out" | grep -c 'on trial, not booted yet') $(ls "$STATE/rollback" | grep -c -- '-boot$')" "1 1"
out=$(rel retire); ok "retire is refused before the new chain has booted" "$? $(echo "$out" | grep -c 'no recorded successful boot yet')" "1 1"
out=$(rel stage2); ok "the Stage 2 switch is refused during a trial (one change at a time)" "$? $(echo "$out" | grep -c 'one change at a time')" "1 1"
out=$(update); ok "ordinary updates still work during a trial" "$?" 0

# abandon: everything back from the rollback set, as pacman transactions
out=$(rel abandon); ok "abandon: the old packages come back from the archives" "$? $(Q linux-aurora) $(Q omarchy-aurora-firmware) $(Q m1n1-aurora)" "0 7.3.0.aurora17.v272-4 20261014.j714s9-1 1.6.1.aurora24.v272-3"
ok "abandon: the kernel file is the repair kernel again" "$(grep -c -a K114S-R1 "$S/usr/lib/modules/$KOLD/vmlinuz")" 1
ok "abandon: they are held again, the markers are gone" "$(state) $(ls "$S/etc/omarchy-k114s" | grep -c -E 'stage2-frozen') $(cat "$S/etc/omarchy-k114s/keep-modules" | wc -w | tr -d ' ')" "$held_before 0 0"
ok "abandon: proven image and Stage 2 untouched throughout" "$(sum "$ESPD/EFI/Linux/omarchy_linux-aurora-k114s.efi") $(sum "$ESPD/m1n1/boot-ctxr.bin")" "$REPAIR $STAGE2_R2C"
ok "abandon: the trial is closed" "$(test -e "$STATE/release/trial"; status) $(ls "$STATE/release/history" | grep -c 'abandoned$')" "1 1"
ok "abandon: pacman finds the restored kernel package whole" "$(sb pacman -Qkk linux-aurora | grep -c ' 0 altered files')" 1

# Omarchy's 11-omarchy-mac-saved-modules.hook: a channel kernel whose release string sorts BELOW the running one (the same aurora build
# without our .v272-4 tag) makes it move the running kernel's modules away in the same transaction. The proven entry must keep them.
KBELOW=7.3.0-17-ARCH
ok "the release string of the channel's own build sorts below the running one" "$(printf '%s\n%s\n' "$KBELOW" "$KOLD" | sort -V | head -n 1)" "$KBELOW"
t=$(tree); kernel_tree "$t" "$KBELOW" k114s-full "$GOOD_CONFIG" "clamping Report Size"; c_below=$(mkpkg "$t" linux-aurora 7.3.0.aurora17-1 "$P")
mkrepo edge "$c_below" "$c_fw" "$c_m1n1" "$c_app2" "$c_lfw2" "$c_vulkan_bad"
sb pacman -Syy >/dev/null     # what "omarchy update" leaves: pacman's own lists carry the channel's build
out=$(rel auto); ok "a same-version channel kernel is staged" "$? $(Q linux-aurora) $(test -s "$STATE/release/trial"; status)" "0 7.3.0.aurora17-1 0"
ok "Omarchy's hook did move the proven kernel's modules during that transaction" "$(grep -c "Moving the running kernel's saved modules ($KOLD)" "$(ls -d "$STATE"/rollback/*-boot | tail -n 1)/pacman.log")" 1
ok "and the tool put them back before recording the trial: kernel, Wi-Fi module and the repair module are all there" "$(test -s "$S/usr/lib/modules/$KOLD/kernel/drivers/hid/hid-magicmouse.ko.zst" && test -s "$S/usr/lib/modules/$KOLD/updates/hid-magicmouse.ko" && test -s "$S/usr/lib/modules/$KOLD/vmlinuz"; status) $(test -e "$S/usr/lib/modules/.old/$KOLD"; status)" "0 1"
ok "it says so, and raises no PROBLEM" "$(grep -c "modules ($KOLD) had been moved to .*/.old during the transaction; they were put back" "$STATE/release/log") $(notes | grep -c 'PROBLEM')" "1 0"
out=$(rel abandon); ok "abandon after it: the old kernel package is whole again" "$? $(Q linux-aurora) $(sb pacman -Qkk linux-aurora | grep -c ' 0 altered files')" "0 7.3.0.aurora17.v272-4 1"
# A transaction that leaves the boot partition's lock held (limine-snapper-sync starts right after it) must not cut the tool short: the proven
# kernel's modules, the default entry and the trial record are all still written.
printf '#!/bin/sh\n[ -e /etc/k114s-test/hold-lock ] || exit 0\nexec 7>/run/lock/boot-partition.lock\nflock 7\nsetsid sleep 4 </dev/null >/dev/null 2>&1 &\nexit 0\n' > "$S/usr/share/libalpm/scripts/test-hold-lock"; chmod 755 "$S/usr/share/libalpm/scripts/test-hold-lock"
hook "$S/usr/share/libalpm/hooks/99-test-hold-lock.hook" PostTransaction /usr/share/libalpm/scripts/test-hold-lock 'usr/lib/modules/*/vmlinuz'
mkrepo edge "$c_below" "$c_fw" "$c_m1n1" "$c_app2" "$c_lfw2" "$c_vulkan_bad"; sb pacman -Syy >/dev/null
: > "$S/etc/k114s-test/hold-lock"; : > "$S/var/log/notify.log"
out=$(LOCK_WAIT=1 rel auto); rm -f "$S/etc/k114s-test/hold-lock"
ok "the lock is held when the transaction returns: the tool goes on, the trial is recorded" "$? $(Q linux-aurora) $(test -s "$STATE/release/trial"; status) $(echo "$out" | grep -c 'nothing changed, try again')" "0 7.3.0.aurora17-1 0 0"
ok "the proven kernel's modules are back, the proven entry is the default, and it says the lock was not got" "$(test -s "$S/usr/lib/modules/$KOLD/updates/hid-magicmouse.ko"; status) $(default_title) $(grep -c 'lock was still held' "$STATE/release/log")" "0 Omarchy K114s repair r1 (trackpad fix B) 1"
sleep 4
out=$(rel abandon); ok "abandon after it: the old kernel package is whole again" "$? $(Q linux-aurora)" "0 7.3.0.aurora17.v272-4"
rm -f "$S/usr/share/libalpm/hooks/99-test-hold-lock.hook"
# The proven kernel's modules folder exists again, without its modules, when the tool wants to put them back (something recreated it after
# Omarchy's hook): they must not be moved INTO it (that would nest them one level down); the tool says so and leaves both alone.
printf '#!/bin/sh\n[ -e /etc/k114s-test/nest-dir ] || exit 0\nmkdir -p "/usr/lib/modules/$K114S_UNAME_R/leftover"\n' > "$S/usr/share/libalpm/scripts/test-nest-dir"; chmod 755 "$S/usr/share/libalpm/scripts/test-nest-dir"
hook "$S/usr/share/libalpm/hooks/99-test-nest-dir.hook" PostTransaction /usr/share/libalpm/scripts/test-nest-dir 'usr/lib/modules/*/vmlinuz'
mkrepo edge "$c_below" "$c_fw" "$c_m1n1" "$c_app2" "$c_lfw2" "$c_vulkan_bad"; sb pacman -Syy >/dev/null
: > "$S/etc/k114s-test/nest-dir"; : > "$S/var/log/notify.log"
out=$(rel auto); rm -f "$S/etc/k114s-test/nest-dir" "$S/usr/share/libalpm/hooks/99-test-nest-dir.hook"
ok "the modules folder is back without its modules: a PROBLEM is raised and nothing is moved into it" "$(notes | grep -c "PROBLEM: .*/usr/lib/modules/$KOLD exists without its kernel modules") $(test -d "$S/usr/lib/modules/$KOLD/$KOLD"; status) $(test -d "$S/usr/lib/modules/.old/$KOLD/kernel"; status)" "1 1 0"
rm -rf "$S/usr/lib/modules/$KOLD/leftover"
out=$(rel abandon); ok "abandon after it: the old kernel package is whole again" "$? $(Q linux-aurora) $(sb pacman -Qkk linux-aurora | grep -c ' 0 altered files')" "0 7.3.0.aurora17.v272-4 1"
rm -rf "$S/usr/lib/modules/.old"; : > "$S/var/log/notify.log"
mkrepo edge "$c_kernel" "$c_fw" "$c_m1n1" "$c_app2" "$c_lfw2" "$c_vulkan_bad"; sb pacman -Syy >/dev/null

# stage again, then the boots
out=$(rel auto); ok "staged again" "$(Q linux-aurora) $(test -s "$STATE/release/trial"; status)" "7.4.4.aurora18-1 0"
NEW_IMAGE=$(sum "$ESPD/EFI/Linux/omarchy_linux-aurora.efi")
boot EFI/Linux/omarchy_linux-aurora-k114s.efi "$KOLD"; ok "restart into the PROVEN entry: recorded ok" "$(echo "$out" | grep -c 'boot recorded as ok: image EFI/Linux/omarchy_linux-aurora-k114s.efi')" 1
ok "its modules are there (it is the running kernel)" "$(test -d "$S/usr/lib/modules/$KOLD"; status)" 0
out=$(rel auto); ok "a boot of the old entry proves nothing about the new one" "$(echo "$out" | grep -c 'on trial, not booted yet') $(grep -c '^proven' "$STATE/release/trial")" "1 0"
trackpad absent
boot EFI/Linux/omarchy_linux-aurora.efi "$KNEW"; ok "restart into the NEW entry, trackpad missing: recorded incomplete" "$(echo "$out" | grep -c 'boot recorded as incomplete')" 1
ok "the proven kernel's modules survive the boot-time cleanup (keep list)" "$(test -s "$S/usr/lib/modules/$KOLD/kernel/drivers/hid/hid-magicmouse.ko.zst"; status) $(test -e "$S/usr/lib/modules/.old"; status)" "0 1"
out=$(rel auto); ok "an incomplete boot proves nothing" "$(grep -c '^proven' "$STATE/release/trial") $(test -s "$ESPD/EFI/Linux/omarchy_linux-aurora-k114s.efi"; status)" "0 0"
trackpad present
out=$(sb /usr/local/lib/omarchy-k114s/k114s-boot-success); ok "the same boot once the trackpad is there: recorded ok" "$(echo "$out" | grep -c 'boot recorded as ok: image EFI/Linux/omarchy_linux-aurora.efi')" 1
: > "$S/var/log/notify.log"
out=$(rel auto); ok "auto: the new chain is proven" "$(grep -c '^proven' "$STATE/release/trial") $(notes | grep -c 'has a recorded successful boot. The old one is retired on a later run')" "1 1"
ok "but nothing old is retired in the run that proved it" "$(sum "$ESPD/EFI/Linux/omarchy_linux-aurora-k114s.efi") $(default_title)" "$REPAIR Omarchy K114s repair r1 (trackpad fix B)"
out=$(rel auto); ok "nor on the next run of the same boot (RETIRE_AFTER_BOOTS=2)" "$(test -s "$ESPD/EFI/Linux/omarchy_linux-aurora-k114s.efi"; status) $(echo "$out" | grep -c 'proven (1 recorded boot(s); retired after 2')" "0 1"
boot EFI/Linux/omarchy_linux-aurora-k114s.efi "$KOLD"; out=$(rel auto)
ok "booted from the old entry again: retire waits (the trial is not what is running)" "$(test -s "$ESPD/EFI/Linux/omarchy_linux-aurora-k114s.efi"; status)" 0
boot EFI/Linux/omarchy_linux-aurora.efi "$KNEW"; : > "$S/var/log/notify.log"
out=$(rel auto); ok "second good boot of the new entry: auto retires the old boot image" "$? $(test -e "$ESPD/EFI/Linux/omarchy_linux-aurora-k114s.efi"; status)" "0 1"
ok "its menu entry is gone, the new one is the default" "$(grep -c -E 'K114s repair|omarchy_linux-aurora-k114s' "$ESPD/limine.conf") $(default_title)" "0 linux-aurora"
ok "the new chain is the proven one" "$(awk '$1 == "uki" || $1 == "uki_sha256" { print $2 }' "$STATE/release/known-good" | tr '\n' ' ')" "EFI/Linux/omarchy_linux-aurora.efi $NEW_IMAGE "
ok "the retired image is kept in the rollback set" "$(sum "$(ls -d "$STATE"/rollback/*-boot | tail -n 1)/esp/EFI/Linux/omarchy_linux-aurora-k114s.efi")" "$REPAIR"
ok "the trial is closed and the keep list is empty" "$(test -e "$STATE/release/trial"; status) $(cat "$S/etc/omarchy-k114s/keep-modules" | wc -w | tr -d ' ')" "1 0"
ok "Stage 2 is STILL the proven file: a loader package was part of it" "$(sum "$ESPD/m1n1/boot-ctxr.bin") $(notes | grep -c 'Switch it to the installed loader packages when ready: sudo k114s-release stage2')" "$STAGE2_R2C 1"
out=$(rel status); ok "status after retire" "$(echo "$out" | grep -c -E 'intact and running|trial:     none|Stage 2:   frozen')" 3
boot EFI/Linux/omarchy_linux-aurora.efi "$KNEW"; ok "next boot: the old kernel's modules are cleaned up as usual" "$(test -d "$S/usr/lib/modules/$KOLD"; status) $(test -d "$S/usr/lib/modules/.old/$KOLD"; status)" "1 0"

# --- Stage 2: a candidate beside the proven file, tried through the loader's one-boot trial ------------------------------
TRY=$ESPD/m1n1/boot-ctxr-try.bin
: > "$S/var/log/notify.log"; out=$(rel auto)
ok "auto never starts a Stage 2 trial by itself (AUTO_STAGE2_SWITCH=no)" "$(sum "$ESPD/m1n1/boot-ctxr.bin") $(echo "$out" | grep -c 'Stage 2 is still the proven file') $(test -e "$TRY"; status)" "$STAGE2_R2C 1 1"
echo GPU-STAGE2 > "$ESPD/m1n1/boot-ctxr-r3-gpu.bin"; printf '%s\n%s\n' m1n1/boot-ctxr-r3-gpu.bin "$(sum "$ESPD/m1n1/boot-ctxr-r3-gpu.bin")" > "$S/etc/omarchy-k114s/stage2-trial"
out=$(rel stage2 --dtb packaged); ok "refused while someone else's standing Stage 2 trial is under way; nothing written" "$? $(echo "$out" | grep -c 'a standing Stage 2 trial of m1n1/boot-ctxr-r3-gpu.bin') $(test -e "$TRY"; status) $(test -e "$ESPD/aura-try"; status)" "1 1 1 1"
rm -f "$S/etc/omarchy-k114s/stage2-trial" "$ESPD/m1n1/boot-ctxr-r3-gpu.bin"
# update-m1n1 cuts boot.bin from the newest -ARCH kernel directory; when that is not the installed linux-aurora's (the proven kernel's restored one),
# the "packaged" tree is not the one the release check read: refused, nothing written
PKGDTB=$S/usr/lib/modules/$KNEW/dtbs/t6050-k114s.dtb; cp "$PKGDTB" "$BASE/pkgdtb.keep"; printf 'X' | dd of="$PKGDTB" bs=1 seek=200 conv=notrunc 2>/dev/null
out=$(rel stage2 --dtb packaged); ok "stage2 --dtb packaged: a tree in boot.bin that is not the installed package's is refused, nothing written" "$? $(echo "$out" | grep -c 'not the one the installed linux-aurora carries') $(test -e "$TRY"; status) $(test -e "$ESPD/aura-try"; status) $(test -e "$STATE/release/trial"; status)" "1 1 1 1 1"
cp "$BASE/pkgdtb.keep" "$PKGDTB"
out=$(rel stage2 --dtb packaged); ok "k114s-release stage2 --dtb packaged" "$?" 0
CAND=$(sum "$TRY")
ok "the candidate is built from the installed loader and the released kernel's own K114s tree" "$(test "$CAND" != "$STAGE2_R2C"; status) $(grep -c -a 'm1n1 channel' "$TRY") $(grep -c -a 'apple,j714s' "$TRY")" "0 1 0"
ok "BESIDE the proven file, which is untouched" "$(sum "$ESPD/m1n1/boot-ctxr.bin") $(test -s "$S/etc/omarchy-k114s/stage2-frozen"; status)" "$STAGE2_R2C 0"
ok "the loader's one-boot trial is armed for it; a Stage 2 trial is recorded" "$(tr '\n' ' ' < "$ESPD/aura-try") $(awk '$1 == "kind" { print $2 }' "$STATE/release/trial")" "armed m1n1/boot-ctxr-try.bin  stage2"
rm -f "$STATE"/release/boots/*-"$BOOT_ID"; sb /usr/local/lib/omarchy-k114s/k114s-boot-success >/dev/null; out=$(rel auto)
ok "a record written in the boot that armed it proves nothing" "$(grep -c '^proven' "$STATE/release/trial") $(echo "$out" | grep -c 'is armed for the next start')" "0 1"
HANG=1 boot EFI/Linux/omarchy_linux-aurora.efi "$KNEW"
ok "a trial start that hangs: the watchdog's start comes through the proven file, and the trial is spent" "$(echo "$out" | grep -c 'boot recorded as ok: image EFI/Linux/omarchy_linux-aurora.efi, Stage 2 m1n1/boot-ctxr.bin,') $(head -n 1 "$ESPD/aura-try")" "1 spent"
out=$(rel auto); ok "auto says so; nothing proven changed" "$(echo "$out" | grep -c 'this start did not come through m1n1/boot-ctxr-try.bin') $(sum "$ESPD/m1n1/boot-ctxr.bin") $(grep -c '^proven' "$STATE/release/trial")" "1 $STAGE2_R2C 0"
out=$(rel stage2 --rearm); ok "stage2 --rearm arms it again" "$? $(head -n 1 "$ESPD/aura-try")" "0 armed"
boot EFI/Linux/omarchy_linux-aurora.efi "$KNEW"
ok "the trial start: recorded ok through the candidate, and armed again for the next start" "$(echo "$out" | grep -c 'Stage 2 m1n1/boot-ctxr-try.bin (a one-boot trial)') $(head -n 1 "$ESPD/aura-try")" "1 armed"
out=$(rel auto); ok "proven, and not switched in the run that proved it" "$(grep -c '^proven' "$STATE/release/trial") $(sum "$ESPD/m1n1/boot-ctxr.bin")" "1 $STAGE2_R2C"
boot EFI/Linux/omarchy_linux-aurora.efi "$KNEW"; : > "$S/var/log/notify.log"; out=$(rel auto)
ok "a later run after the second good start through it: it is the configured Stage 2 and the proven one" "$(sum "$ESPD/m1n1/boot-ctxr.bin") $(awk '$1 == "stage2_sha256" { print $2 }' "$STATE/release/known-good") $(test -e "$STATE/release/trial"; status) $(test -e "$S/etc/omarchy-k114s/stage2-frozen"; status)" "$CAND $CAND 1 1"
ok "the old file is kept on the EFI partition for the way back from macOS" "$(sum "$ESPD/k114s-repair/known-good/boot-ctxr.bin") $(cut -c1-64 "$ESPD/k114s-repair/known-good/boot-ctxr.bin.sha256")" "$STAGE2_R2C $STAGE2_R2C"
ok "it tells how to go back from macOS; the marker is gone" "$(echo "$out" | grep -c -E 'start macOS|k114s-repair/known-good/boot-ctxr.bin  over') $(test -e "$ESPD/aura-try"; status)" "2 1"
boot EFI/Linux/omarchy_linux-aurora.efi "$KNEW"; out=$(rel auto)
ok "the next start comes through the configured file; the candidate leaves the ESP" "$(test -e "$TRY"; status) $(rel status | grep -c 'intact and running')" "1 1"
STAGE2_NEW=$CAND
# the loader after the switch: still held, and no pacman hook may rewrite the one Stage 2 that every entry shares
t=$(tree); mkdir -p "$t/usr/lib/asahi-boot"; printf 'm1n1 channel next\0apple,t6050\0apcie,t6050\0atc-phy,t6050\0' > "$t/usr/lib/asahi-boot/m1n1.bin"; c_m1n1_next=$(mkpkg "$t" m1n1-aurora 1.8.0.aurora26-1 "$P")
mkrepo edge "$c_kernel" "$c_fw" "$c_m1n1_next" "$c_app2" "$c_lfw2" "$c_vulkan_bad"
out=$(update); ok "the loader after the Stage 2 switch: an ordinary update leaves m1n1-aurora at the released build" "$? $(Q m1n1-aurora) $(sb pacman-conf IgnorePkg | grep -c -x m1n1-aurora)" "0 1.7.0.aurora25-1 1"
out=$(sb pacman -S --noconfirm m1n1-aurora); ok "a named install of the next loader build is stopped by the hold guard" "$? $(Q m1n1-aurora) $(echo "$out" | grep -c 'K114s hold guard: stopped')" "1 1.7.0.aurora25-1 1"
: > "$S/etc/omarchy-k114s/allow-coupled-update"; out=$(sb pacman -S --noconfirm m1n1-aurora)
ok "even with the owner's blanket override the install goes in, its hooks run (boot.bin is rebuilt), and boot-ctxr.bin is NOT touched: nobody writes it but k114s-release" "$? $(Q m1n1-aurora) $(sum "$ESPD/m1n1/boot-ctxr.bin") $(echo "$out" | grep -c 'Stage 2 is managed by k114s-release')" "0 1.8.0.aurora26-1 $STAGE2_NEW 1"
out=$(sb pacman -U --noconfirm "$c_m1n1"); rm "$S/etc/omarchy-k114s/allow-coupled-update"
ok "the released loader build is back; Stage 2 is still the switched one" "$(Q m1n1-aurora) $(sum "$ESPD/m1n1/boot-ctxr.bin")" "1.7.0.aurora25-1 $STAGE2_NEW"

# --- the steady state: the proven image is the standard one, and the next kernel arrives ----------------------------------
held_before=$(state)
t=$(tree); kernel_tree "$t" "$KNEW" k114s-full "$GOOD_CONFIG" "clamping Report Size"; c_same=$(mkpkg "$t" linux-aurora 7.4.4.aurora18-2 "$P")
mkrepo edge "$c_same" "$c_fw" "$c_m1n1" "$c_app2" "$c_lfw2" "$c_vulkan_bad"; update >/dev/null
ok "a released kernel STAYS held: an ordinary update does not move it to the channel's next build" "$(Q linux-aurora) $(sb pacman-conf IgnorePkg | grep -c -x linux-aurora)" "7.4.4.aurora18-1 1"
out=$(sb pacman -S --noconfirm linux-aurora); ok "nor does a named install: the next kernel has to pass the check and the trial again" "$? $(Q linux-aurora) $(echo "$out" | grep -c 'K114s hold guard: stopped')" "1 7.4.4.aurora18-1 1"
ok "and the boot image and Stage 2 are exactly the proven ones" "$(sum "$ESPD/EFI/Linux/omarchy_linux-aurora.efi") $(sum "$ESPD/m1n1/boot-ctxr.bin")" "$NEW_IMAGE $STAGE2_NEW"
rel mark-known-good >/dev/null
PROVEN2=$(sum "$ESPD/EFI/Linux/omarchy_linux-aurora.efi"); K3=7.5.0-1-ARCH
t=$(tree); kernel_tree "$t" "$KNEW" k114s-full "$GOOD_CONFIG" "clamping Report Size"; c_shared=$(mkpkg "$t" linux-aurora 7.4.4.aurora19-1 "$P")
mkrepo edge "$c_shared" "$c_fw" "$c_m1n1" "$c_app2" "$c_lfw2" "$c_vulkan_bad"; update >/dev/null
out=$(rel auto); ok "a kernel with the running kernel's release string is not staged by itself (its modules would replace the proven ones)" "$(Q linux-aurora) $(echo "$out" | grep -c 'has the release string of the running kernel')" "7.4.4.aurora18-1 1"
t=$(tree); kernel_tree "$t" "$K3" k114s-full "$GOOD_CONFIG" "clamping Report Size"; c_k3=$(mkpkg "$t" linux-aurora 7.5.0.aurora20-1 "$P")
mkrepo edge "$c_k3" "$c_fw" "$c_m1n1" "$c_app2" "$c_lfw2" "$c_vulkan_bad"; update >/dev/null
out=$(rel auto); ok "the next kernel is staged" "$? $(Q linux-aurora)" "0 7.5.0.aurora20-1"
ok "the proven image, which the hooks overwrite, was first kept under its own name" "$(sum "$ESPD/EFI/Linux/omarchy_linux-aurora-known-good.efi") $(grep -a -o -m1 'Linux version [0-9][^ ]*' "$ESPD/EFI/Linux/omarchy_linux-aurora.efi")" "$PROVEN2 Linux version $K3"
ok "it is the first menu entry and the default" "$(default_title) $(sed -n 's/^default_entry: //p' "$ESPD/limine.conf")" "Omarchy K114s known-good 1"
ok "the record of the proven chain follows the copy" "$(awk '$1 == "uki" { print $2 }' "$STATE/release/known-good")" "EFI/Linux/omarchy_linux-aurora-known-good.efi"
boot EFI/Linux/omarchy_linux-aurora-known-good.efi "$KNEW"; out=$(rel status)
ok "the known-good entry boots the proven kernel with its modules" "$(echo "$out" | grep -c 'intact and running') $(test -d "$S/usr/lib/modules/$KNEW/kernel"; status)" "1 0"
boot EFI/Linux/omarchy_linux-aurora.efi "$K3"; rel auto >/dev/null; boot EFI/Linux/omarchy_linux-aurora.efi "$K3"; out=$(rel auto)
ok "two good boots later the copy and its entry are retired" "$(test -e "$ESPD/EFI/Linux/omarchy_linux-aurora-known-good.efi"; status) $(grep -c 'known-good' "$ESPD/limine.conf") $(default_title)" "1 0 linux-aurora"
ok "one boot image is the steady state again" "$(ls "$ESPD/EFI/Linux" | tr '\n' ' ')" "omarchy_linux-aurora.efi "

# --- the plugin again: a channel build that names hyprland-m5 replaces the adopted one, although pacman calls it a downgrade ---
c_tb_fit=$(tb "channel plugin built against hyprland-m5" 0.4.2-1 "hyprland-m5=0.57.2-2")
mkrepo edge "$c_k3" "$c_fw" "$c_m1n1" "$c_app2" "$c_lfw2" "$c_vulkan_bad" "$c_tb_fit"; update >/dev/null
ok "an update does not touch the held, adopted plugin" "$(Q omarchy-hyprland-titlebars)" "1:0.4.0+m5-1"
out=$(rel auto); ok "auto releases the plugin to the channel's fit build" "$? $(Q omarchy-hyprland-titlebars) $(cat "$S/usr/lib/omarchy-hyprland-titlebars/titlebars.so")" "0 0.4.2-1 channel plugin built against hyprland-m5"
ok "its plugin file stays extractable from now on (no NoExtract for a released package)" "$(grep -c '^NoExtract' "$S/etc/pacman.conf") $(sb pacman-conf IgnorePkg | grep -c -x omarchy-hyprland-titlebars)" "0 0"

# --- a locally built kernel package (the next K114s kernel) takes the same road, and stays held ----------------------------
sb /usr/local/lib/omarchy-k114s/k114s-holds hold linux-aurora >/dev/null; rel mark-known-good >/dev/null; PROVEN3=$(sum "$ESPD/EFI/Linux/omarchy_linux-aurora.efi")
K4=7.5.0-2.k114s-ARCH; t=$(tree); kernel_tree "$t" "$K4" k114s-full "$GOOD_CONFIG" "clamping Report Size K114S-R3"; l_kernel=$(mkpkg "$t" linux-aurora 7.5.0.aurora20.k114s3-1 "$P")
out=$(rel adopt "$l_kernel" "$m5_tb"); ok "adopt: boot-chain and other packages are not mixed in one run" "$? $(Q linux-aurora)" "1 7.5.0.aurora20-1"
out=$(ESP_FREE=$((5 * MB)) rel adopt "$l_kernel"); ok "adopt of a kernel with no room on the EFI partition: nothing staged" "$? $(Q linux-aurora) $(echo "$out" | grep -c 'waits for room on the ESP')" "1 7.5.0.aurora20-1 1"
out=$(rel adopt "$l_kernel"); ok "adopt: the local kernel package is installed as an additional boot entry" "$? $(Q linux-aurora) $(grep -a -o -m1 'Linux version [0-9][^ ]*' "$ESPD/EFI/Linux/omarchy_linux-aurora.efi")" "0 7.5.0.aurora20.k114s3-1 Linux version $K4"
ok "adopt: the proven image is kept and is the default; Stage 2 untouched" "$(sum "$ESPD/EFI/Linux/omarchy_linux-aurora-known-good.efi") $(default_title) $(sum "$ESPD/m1n1/boot-ctxr.bin")" "$PROVEN3 Omarchy K114s known-good $STAGE2_NEW"
ok "adopt: the package stays held (it is ours, not the channel's)" "$(sb pacman-conf IgnorePkg | grep -c -x linux-aurora) $(awk '$1 == "source" { print $2 }' "$STATE/release/trial")" "1 files"
out=$(update); ok "an update during the trial leaves the adopted kernel alone" "$? $(Q linux-aurora)" "0 7.5.0.aurora20.k114s3-1"
boot EFI/Linux/omarchy_linux-aurora.efi "$K4"; rel auto >/dev/null; boot EFI/Linux/omarchy_linux-aurora.efi "$K4"; out=$(rel auto)
ok "after two recorded boots the old image is retired; one image again" "$(ls "$ESPD/EFI/Linux" | tr '\n' ' ') $(default_title) $(sb pacman-conf IgnorePkg | grep -c -x linux-aurora)" "omarchy_linux-aurora.efi  linux-aurora 1"

# --- a blocking held package with a fit channel build is released by the preflight; the GPU stack from the channel is on trial ---------------
g_mesa() { gfx libgallium-99.0.0-test.so mesa-aurora "gallium-$1 G17S ASAHI_M5_BRINGUP llvmpipe" "1:26.3.0_devel.$2-1"; }
cat > "$BASE/pacman-wrap" <<'WRAP'
#!/bin/bash
# real pacman, except that the dry-run upgrade fails on a dependency of the held Mesa until the wanted Mesa build is installed
case " $* " in *" -Sup "*)
  pacman -Q mesa-aurora | grep -q "$(cat "$(dirname "$0")/wrap-want")" && exit 0
  echo "warning: vulkan-aurora: ignoring package upgrade (1 => 2)"
  echo "error: failed to prepare transaction (could not satisfy dependencies)"
  echo ":: installing llvm-libs (23.1-2) breaks dependency 'libLLVM.so=23.1-64' required by mesa-aurora"; exit 1 ;; esac
exec pacman "$@"
WRAP
chmod 755 "$BASE/pacman-wrap"
mesa_before=$(Q mesa-aurora); rm -f "$STATE/release/gpu-given-up" "$STATE/release/gpu-trial"
g1=$(g_mesa trial-1 20270101.cccccc1); mkrepo edge "$g1"; sb pacman -Syy >/dev/null; echo cccccc1 > "$BASE/wrap-want"; : > "$S/var/log/notify.log"
out=$(sb env K114S_PACMAN="$BASE/pacman-wrap" /usr/local/lib/omarchy-k114s/k114s-release preflight)
ok "preflight: the held Mesa blocks the upgrade and its channel build is fit: the preflight installs it, and it stays held" "$? $(echo "$out" | grep -c 'would FAIL on a dependency or conflict of held package(s): mesa-aurora') $(Q mesa-aurora) $(sb pacman-conf IgnorePkg | grep -c -x mesa-aurora)" "0 1 1:26.3.0_devel.20270101.cccccc1-1 1"
ok "preflight: the release went through (Mesa stays held by design), so no 'still held, run release' hint is printed" "$(echo "$out" | grep -c 'run: sudo k114s-release release')" 0
ok "preflight: the vulkan-aurora 'ignoring package upgrade' warning was not taken for a blocker" "$(echo "$out" | grep -c 'would FAIL on a dependency or conflict of held package(s): mesa-aurora$')" 1
ok "the GPU stack is on trial: the record names the package and its rollback archive" "$(awk '$1 == "package" { print $2 }' "$STATE/release/gpu-trial") $(sb ls "$(awk '$1 == "package" { print $4 }' "$STATE/release/gpu-trial")"/packages | grep -c '^mesa-aurora-.*pkg.tar.zst$')" "mesa-aurora 1"
sleep 1; BOOT_ID=b00000a1; sb env K114S_DESKTOP=no /usr/local/lib/omarchy-k114s/k114s-boot-success >/dev/null; out=$(rel auto)
ok "the interim 'incomplete' record of a boot that is still running (a login screen that waits) is not a verdict: the trial goes on, nothing is rolled back" "$(Q mesa-aurora) $(test -e "$STATE/release/gpu-trial"; status)" "1:26.3.0_devel.20270101.cccccc1-1 0"
BOOT_ID=b00000a9; out=$(rel auto)
ok "the next boot recorded no desktop: auto puts the old Mesa back, held" "$? $(Q mesa-aurora) $(sb pacman-conf IgnorePkg | grep -c -x mesa-aurora) $(test -e "$STATE/release/gpu-trial"; status)" "0 $mesa_before 1 1"
ok "and says so" "$(notes | grep -c 'recorded no desktop: the old build of mesa-aurora is back')" 1
out=$(rel auto); ok "the channel's build that failed is not installed again" "$(Q mesa-aurora) $(grep -c 'rolled back after a boot without a desktop' "$STATE/release/log")" "$mesa_before 2"
g2=$(g_mesa trial-2 20270102.dddddd2); mkrepo edge "$g2"; sb pacman -Syy >/dev/null; sleep 1
out=$(rel auto); ok "a newer channel build is installed (on trial again)" "$(Q mesa-aurora) $(test -e "$STATE/release/gpu-trial"; status)" "1:26.3.0_devel.20270102.dddddd2-1 0"
BOOT_ID=b00000a2; out=$(rel auto); ok "the boot it was installed in decides nothing; a later boot is waited for" "$(test -e "$STATE/release/gpu-trial"; status)" 0
sleep 1; BOOT_ID=b00000a3; sb /usr/local/lib/omarchy-k114s/k114s-boot-success >/dev/null; out=$(rel auto)
ok "a later boot with a desktop ends the trial; the build stays" "$(Q mesa-aurora) $(test -e "$STATE/release/gpu-trial"; status) $(notes | grep -c 'been through a boot that reached the desktop')" "1:26.3.0_devel.20270102.dddddd2-1 1 1"

# keep-held without the gpu marker (asahi-fwextract): a person decides; it is not the GPU stack, so no GPU trial and no GPU wait
t=$(tree); mkdir -p "$t/usr/lib/asahi-fwextract"; echo "fwextract 1" > "$t/usr/lib/asahi-fwextract/version"; c_afw1=$(mkpkg "$t" asahi-fwextract 1-1 "$P")
t=$(tree); mkdir -p "$t/usr/lib/asahi-fwextract"; echo "fwextract 2" > "$t/usr/lib/asahi-fwextract/version"; c_afw2=$(mkpkg "$t" asahi-fwextract 2-1 "$P")
sb pacman -U --noconfirm "$c_afw1" >/dev/null; sb /usr/local/lib/omarchy-k114s/k114s-holds hold asahi-fwextract >/dev/null
g4=$(g_mesa trial-4 20270104.ffffff4); mkrepo edge "$g4" "$c_afw2"; sb pacman -Syy >/dev/null; sleep 1
out=$(rel auto); ok "a GPU trial is open (Mesa waits for a boot)" "$(test -e "$STATE/release/gpu-trial"; status)" 0
out=$(rel release --accept-manual asahi-fwextract)
ok "asahi-fwextract is released by name although a GPU trial is open: it is not the GPU stack" "$(Q asahi-fwextract) $(echo "$out" | grep -c 'GPU stack from the channel')" "2-1 0"
ok "it stays held, and the GPU trial does not list it (nothing puts it back by itself)" "$(sb pacman-conf IgnorePkg | grep -c -x asahi-fwextract) $(grep -c '^package asahi-fwextract' "$STATE/release/gpu-trial")" "1 0"
ok "its note says there is no trial" "$(grep -c 'asahi-fwextract installed (it stays held.*no trial: a person checks that it works' "$STATE/release/log")" 1
sed -i 's/^AUTO_RELEASE_GPU=.*/AUTO_RELEASE_GPU=no/' "$S/etc/omarchy-k114s/release.conf"
t=$(tree); mkdir -p "$t/usr/lib/asahi-fwextract"; echo "fwextract 3" > "$t/usr/lib/asahi-fwextract/version"; c_afw3=$(mkpkg "$t" asahi-fwextract 3-1 "$P"); mkrepo edge "$g4" "$c_afw3"; sb pacman -Syy >/dev/null
out=$(rel auto); ok "AUTO_RELEASE_GPU=no does not speak for asahi-fwextract: its message is the plain one" "$(echo "$out" | grep -c 'asahi-fwextract: the channel.s build is fit for the K114s; release with: sudo k114s-release release asahi-fwextract') $(echo "$out" | grep -c 'asahi-fwextract.*GPU stack')" "0 0"
sed -i 's/^AUTO_RELEASE_GPU=.*/AUTO_RELEASE_GPU=yes/' "$S/etc/omarchy-k114s/release.conf"
rm -f "$STATE/release/gpu-trial"

# the release installs the archive the check verified, not whatever pacman's own lists carry under the same version
mkdir -p "$BASE/pkgsB"; P_keep=$P; P=$BASE/pkgsB; g5b=$(g_mesa build-B 20270105.eeeeee5); P=$P_keep; g5a=$(g_mesa build-A 20270105.eeeeee5)
mkrepo edge "$g5b"; sb pacman -Syy >/dev/null; mkrepo edge "$g5a"       # pacman's own lists: build B; the channel the check reads: build A, same pkgver-pkgrel
out=$(rel auto); ok "same version, different build in pacman's own lists: the verified build is the one installed (the files are build A's)" "$(Q mesa-aurora) $(tr '\0' ' ' < "$S/usr/lib/libgallium-99.0.0-test.so")" "1:26.3.0_devel.20270105.eeeeee5-1 gallium-build-A G17S ASAHI_M5_BRINGUP llvmpipe "
rm -f "$STATE/release/gpu-trial"
g6=$(g_mesa build-6 20270106.eeeeee6); mkrepo edge "$g6"; sb pacman -Syy >/dev/null
cat > "$BASE/pacman-tamper" <<'WRAP'
#!/bin/bash
# real pacman, except that the verdict's SHA-256 of Mesa stops matching the archive after the check and before the install
case " $* " in *" -Sp "*) sed -i -E '/^mesa-aurora\t/ s/\t[0-9a-f]{64}\t/\t0000000000000000000000000000000000000000000000000000000000000000\t/' /var/lib/omarchy-k114s/check/verdict.tsv ;; esac
exec pacman "$@"
WRAP
chmod 755 "$BASE/pacman-tamper"
out=$(sb env K114S_PACMAN="$BASE/pacman-tamper" /usr/local/lib/omarchy-k114s/k114s-release auto)
ok "an archive whose SHA-256 differs from the verdict's is refused: nothing installed, left held" "$(Q mesa-aurora) $(echo "$out" | grep -c 'SHA-256 is not the one that passed') $(test -e "$STATE/release/gpu-trial"; status)" "1:26.3.0_devel.20270105.eeeeee5-1 1 1"

# the archive is installed with pacman -U, so its detached signature is checked here: a bad or missing one leaves it held
out=$(SIGCHECK_STUB=false sb /usr/local/lib/omarchy-k114s/k114s-release auto)
ok "a signature that does not verify is refused: nothing installed, left held" "$(Q mesa-aurora) $(echo "$out" | grep -c 'does not verify against pacman.s keyring; left held') $(test -e "$STATE/release/gpu-trial"; status)" "1:26.3.0_devel.20270105.eeeeee5-1 1 1"
rm -f "$REPO"/edge/os/mesa-aurora-*.sig
out=$(sb /usr/local/lib/omarchy-k114s/k114s-release auto)
ok "an archive without a signature is refused: nothing installed, left held" "$(Q mesa-aurora) $(echo "$out" | grep -c 'has no signature') $(test -e "$STATE/release/gpu-trial"; status)" "1:26.3.0_devel.20270105.eeeeee5-1 1 1"
mkrepo edge "$g6"; sb pacman -Syy >/dev/null
out=$(sb /usr/local/lib/omarchy-k114s/k114s-release auto)
ok "with its signature back, the verified build goes in" "$(Q mesa-aurora) $(echo "$out" | grep -c 'has no signature')" "1:26.3.0_devel.20270106.eeeeee6-1 0"
rm -f "$STATE/release/gpu-trial"

# --- the installer's undo ---------------------------------------------------------------------------------------------------
out=$(sb bash "$L/k114s-tooling-install" --undo); ok "installer --undo" "$? $(echo "$out" | grep -c 'k114s-tooling-install: undone')" "0 1"
ok "undo: r2c's two hooks are back, r3's three are gone" "$(ls "$S/etc/pacman.d/hooks" | grep -c -E 'k114s-hold-guard|k114s-esp-space') $(ls "$S/etc/pacman.d/hooks" | grep -c 'k114s-guard-')" "2 0"
ok "undo: r2c's tools are back" "$(cmp -s "$KLIB/apply-holds" "$L/apply-holds"; status) $(cmp -s "$KLIB/hold-guard" "$L/hold-guard"; status) $(test -e "$KLIB/k114s-release"; status)" "0 0 1"
ok "undo: it says which packages now follow the channel (only the released userland package: boot-chain ones were never released)" "$(echo "$out" | grep -c -E '^  (m1n1-aurora|omarchy-aurora-firmware|linux-aurora|omarchy-hyprland-titlebars) ') $(echo "$out" | grep -c -E '^  omarchy-hyprland-titlebars ')" "1 1"
out=$(sb pacman -Rdd --noconfirm uboot-aurora); ok "undo: r2c's guard is what stops a boot-chain change again" "$? $(echo "$out" | grep -c 'K114s hold guard: stopped')" "1 1"

finish "r3 pacman tests (replica: real pacman in a user namespace)"
