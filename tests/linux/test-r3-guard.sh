#!/bin/bash
# Tests of the r3 guards in a fake root: k114s-guard (install, remove, esp, audit), k114s-holds,
# and the pre-refresh user hook. No real system file is touched, no pacman transaction runs
# (test-r3-pacman.sh runs the same guards through a real pacman).
#   usage: test-r3-guard.sh [LINUX_DIR]
set -u
. "$(dirname "$0")/r3-lib.sh" "${1:-}"
MB=1048576
conf_sum() { sum "$1/etc/pacman.conf"; }
holds() { local r=$1; shift; K114S_ROOT=$r bash "$(lib "$r")/k114s-holds" "$@" 2>&1; }
status() { echo $?; }

# --- the hook files -----------------------------------------------------------------------------
for hook in 00-k114s-guard-install.hook 00-k114s-guard-remove.hook 01-k114s-guard-esp.hook; do
  ok "$hook: pre-transaction, aborting, with targets" "$(grep -c -E '^(When = PreTransaction|AbortOnFail|NeedsTargets)$' "$L/$hook")" 3
done
ok "install hook: every install and upgrade" "$(grep -c -E '^(Operation = Install|Operation = Upgrade|Target = \*|Exec = /usr/local/lib/omarchy-k114s/k114s-guard install)$' "$L/00-k114s-guard-install.hook")" 4
ok "remove hook: every removal" "$(grep -c -E '^(Operation = Remove|Target = \*|Exec = /usr/local/lib/omarchy-k114s/k114s-guard remove)$' "$L/00-k114s-guard-remove.hook")" 3
ok "esp hook has no catch-all trigger" "$(grep -c -E '^Target = \*$' "$L/01-k114s-guard-esp.hook")" 0

# --- install: what is held, and the names the review found missing --------------------------------
r=$(mkroot)
out=$(printf 'firefox\nglibc\nomarchy-dev\n' | guard "$r" install); ok "ordinary upgrade passes" "$?" 0
for package in linux-aurora m1n1-aurora uboot-aurora omarchy-aurora-firmware omarchy-mac-boot hyprland-m5 mesa-aurora \
    vulkan-aurora omarchy-mac limine asahi-fwextract asahi-scripts omarchy-hyprland-titlebars; do
  out=$(printf 'firefox\n%s\n' "$package" | guard "$r" install); ok "held: $package stops the transaction" "$?" 1
  ok "held: $package named in the message" "$(echo "$out" | grep -c -E "^  .*\b$package\b")" 1
done
for rival in hyprland mesa hyprland-git mesa-git linux-asahi m1n1 uboot-asahi vulkan-asahi; do
  out=$(echo "$rival" | guard "$r" install); ok "rival: $rival (would replace a held package) stops" "$?" 1
done
out=$(printf 'hyprland-guiutils\nmesa-utils\nlinux-firmware\n' | guard "$r" install); ok "names that only look alike pass" "$?" 0
out=$(printf '' | guard "$r" install); ok "no targets: passes" "$?" 0
ok "a stop says nothing was changed" "$(echo linux-aurora | guard "$r" install | grep -c 'Nothing has been changed')" 1

# --- install: the ways through ---------------------------------------------------------------------
r=$(mkroot); mkdir -p "$r/run/omarchy-k114s"
printf '# permit\ninstall mesa-aurora\n' > "$r/run/omarchy-k114s/permit"
out=$(echo mesa-aurora | guard "$r" install); ok "permit: the named package goes through" "$?" 0
ok "permit: and the guard says so" "$(echo "$out" | grep -c 'release permit in force for: mesa-aurora')" 1
out=$(printf 'mesa-aurora\nvulkan-aurora\n' | guard "$r" install); ok "permit: another held package in the same transaction still stops" "$?" 1
ok "permit: only the unpermitted one is named" "$(echo "$out" | sed -n '3p' | tr -d ' ')" vulkan-aurora
out=$(echo mesa-aurora | guard "$r" remove); ok "permit to install is not a permit to remove" "$?" 1
touch -d '2 hours ago' "$r/run/omarchy-k114s/permit"
out=$(echo mesa-aurora | guard "$r" install); ok "permit older than an hour is ignored" "$?" 1
rm "$r/run/omarchy-k114s/permit"
: > "$r/etc/omarchy-k114s/allow-coupled-update"
out=$(echo linux-aurora | guard "$r" install); ok "owner's override marker lets it through" "$?" 0
ok "override: said out loud" "$(echo "$out" | grep -c 'allow-coupled-update exists')" 1
rm "$r/etc/omarchy-k114s/allow-coupled-update"
echo "mesa-aurora 1:27.0.0-1 20261201T000000Z" > "$(lib "$r")/released.list"
out=$(echo mesa-aurora | guard "$r" install); ok "a released package upgrades freely" "$?" 0
out=$(echo mesa | guard "$r" install); ok "its rival is no longer stopped by the install guard" "$?" 0
out=$(echo mesa-aurora | guard "$r" remove); ok "but it is still never removed (protected)" "$?" 1
out=$(echo vulkan-aurora | guard "$r" install); ok "the others stay held" "$?" 1
r=$(mkroot); rm "$(lib "$r")/holds.list"
out=$(echo linux-aurora | guard "$r" install); ok "hold list missing: the boot stack is held anyway" "$?" 1
out=$(echo mesa-aurora | guard "$r" install); ok "hold list missing: only the boot stack" "$?" 0

# --- install: the channel ----------------------------------------------------------------------------
r=$(mkroot)
template "$r" stable; out=$(echo firefox | guard "$r" install); ok "channel: stable is stopped, whatever is installed" "$?" 1
ok "channel: the message names the channel and the way back" "$(echo "$out" | grep -c -E 'stable channel|omarchy-refresh-pacman edge')" 2
template "$r" rc; out=$(echo firefox | guard "$r" install); ok "channel: rc is stopped" "$?" 1
: > "$r/etc/omarchy-k114s/allow-channel-change"; out=$(echo firefox | guard "$r" install); ok "channel: the owner's marker lets it through" "$?" 0
rm "$r/etc/omarchy-k114s/allow-channel-change"
template "$r" edge; out=$(echo firefox | guard "$r" install); ok "channel: edge passes" "$?" 0
echo rc > "$r/etc/omarchy-k114s/channel"; out=$(echo firefox | guard "$r" install); ok "channel: follows /etc/omarchy-k114s/channel (rc wanted, edge found)" "$?" 1
template "$r" rc; out=$(echo firefox | guard "$r" install); ok "channel: rc wanted, rc found" "$?" 0
r=$(mkroot); printf '[options]\n[core]\nServer = https://example.invalid/stable/os\n' > "$r/etc/pacman.conf"
out=$(echo firefox | guard "$r" install); ok "channel: only the [omarchy] repository is read" "$?" 0

# --- remove: channel switch, omarchy reinstall ----------------------------------------------------------
r=$(mkroot)
out=$(printf 'omarchy-dev\nomarchy-settings-dev\n' | guard "$r" remove); ok "channel switch to stable/rc (removes omarchy-dev) is stopped" "$?" 1
ok "channel switch: both named" "$(echo "$out" | sed -n '3p' | tr -s ' ')" " omarchy-dev omarchy-settings-dev"
out=$(echo hyprland-m5 | guard "$r" remove); ok "omarchy reinstall (hyprland replaces hyprland-m5) is stopped" "$?" 1
for package in linux-aurora limine mkinitcpio omarchy-hyprland-titlebars asahi-scripts; do
  out=$(echo "$package" | guard "$r" remove); ok "removal of $package is stopped" "$?" 1
done
out=$(printf 'orphan-lib\nold-font\n' | guard "$r" remove); ok "orphan cleanup of other packages passes" "$?" 0
mkdir -p "$r/run/omarchy-k114s"; echo "remove hyprland-m5" > "$r/run/omarchy-k114s/permit"
out=$(echo hyprland-m5 | guard "$r" remove); ok "a remove permit lets exactly that removal through" "$?" 0
out=$(printf 'hyprland-m5\nmesa-aurora\n' | guard "$r" remove); ok "and nothing else" "$?" 1

# --- esp: only transactions that can write the EFI partition, and room for what they write -----------
r=$(mkroot); k=$r/usr/lib/modules/7.3.0-17.v272-4-ARCH; mkdir -p "$k"
echo linux-aurora > "$k/pkgbase"; truncate -s $((54 * MB)) "$k/vmlinuz"; truncate -s $((24 * MB)) "$r/boot/initramfs-linux-aurora.img"
truncate -s $((79 * MB)) "$r/boot/efi/EFI/Linux/omarchy_linux-aurora.efi"
truncate -s $((4 * MB)) "$r/boot/efi/m1n1/boot.bin"; truncate -s $((4 * MB)) "$r/boot/efi/m1n1/boot-ctxr.bin"
# need: boot image max(79, 54+24+2)=80, loader 3x4=12, limine 2, margin 8
out=$(echo usr/lib/firmware/brcm/x.bin | guard "$r" esp $((88 * MB))); ok "esp: a firmware update with room for one boot image passes (80+8)" "$?" 0
out=$(echo usr/lib/firmware/brcm/x.bin | guard "$r" esp $((88 * MB - 1))); ok "esp: one byte short stops" "$?" 1
ok "esp: the message shows the sum" "$(echo "$out" | grep -c -E 'boot image for linux-aurora: 83 MB|margin kept free: 8 MB|^92 MB free; the writes need 93 MB')" 3
out=$(echo usr/lib/modules/7.4.0-1-ARCH/vmlinuz | guard "$r" esp $((99 * MB))); ok "esp: a kernel needs the boot image and the loader files (80+12+8): 99 MB stops" "$?" 1
out=$(echo usr/lib/modules/7.4.0-1-ARCH/vmlinuz | guard "$r" esp $((100 * MB))); ok "esp: 100 MB passes" "$?" 0
out=$(echo usr/lib/asahi-boot/m1n1.bin | guard "$r" esp $((20 * MB))); ok "esp: a loader package needs the loader files only (12+8)" "$?" 0
out=$(echo usr/lib/asahi-boot/m1n1.bin | guard "$r" esp $((19 * MB))); ok "esp: and stops below that" "$?" 1
out=$(echo usr/share/limine/BOOTAA64.EFI | guard "$r" esp $((10 * MB))); ok "esp: Limine alone needs 2+8" "$?" 0
out=$(echo usr/share/limine/BOOTAA64.EFI | guard "$r" esp $((9 * MB))); ok "esp: Limine with 9 MB stops" "$?" 1
out=$(echo m1n1-aurora | guard "$r" esp $((20 * MB))); ok "esp: package names classify like their paths" "$?" 0
out=$(echo linux-aurora | guard "$r" esp $((99 * MB))); ok "esp: linux-aurora by name is boot image + loader" "$?" 1
out=$(echo usr/share/libalpm/hooks/99-new.hook | guard "$r" esp $((101 * MB))); ok "esp: a new pacman hook is unknown: everything is assumed (80+12+2+8)" "$?" 1
out=$(echo usr/share/libalpm/hooks/99-new.hook | guard "$r" esp $((102 * MB))); ok "esp: and passes with room for everything" "$?" 0
out=$(printf '' | guard "$r" esp 0); ok "esp: no targets, no check" "$?" 0
out=$(echo usr/lib/firmware/x | guard "$r" esp abc); ok "esp: unreadable free space stops" "$?" 1
: > "$r/etc/omarchy-k114s/allow-low-esp"; out=$(echo linux-aurora | guard "$r" esp 0); ok "esp: the owner's marker skips the check" "$?" 0; rm "$r/etc/omarchy-k114s/allow-low-esp"
sed -i 's/^ESP_MARGIN_MB=.*/ESP_MARGIN_MB=20/' "$r/etc/omarchy-k114s/release.conf"
out=$(echo usr/lib/firmware/x | guard "$r" esp $((99 * MB))); ok "esp: the margin comes from release.conf (80+20)" "$?" 1
r=$(mkroot); out=$(echo usr/lib/firmware/x | guard "$r" esp $((127 * MB))); ok "esp: no kernel to measure assumes a large image (120+8)" "$?" 1
out=$(echo usr/lib/firmware/x | guard "$r" esp $((128 * MB))); ok "esp: 128 MB passes then" "$?" 0
r=$(mkroot); k=$r/usr/lib/modules/7.3.0-17.v272-4-ARCH; mkdir -p "$k"; echo linux-aurora > "$k/pkgbase"; truncate -s $((54 * MB)) "$k/vmlinuz"
truncate -s $((112 * MB)) "$r/boot/efi/EFI/Linux/omarchy_linux-aurora.efi"
out=$(echo usr/lib/firmware/x | guard "$r" esp $((119 * MB))); ok "esp: an existing image larger than the estimate counts (112+8)" "$?" 1
out=$(echo usr/lib/firmware/x | guard "$r" esp $((120 * MB))); ok "esp: 120 MB passes" "$?" 0
# an install is not checked for space...
out=$(echo firefox | guard "$r" install 0); ok "an ordinary install is not stopped by a full EFI partition" "$?" 0

# --- audit: the esp hook's triggers against the boot hooks present ---------------------------------------
r=$(mkroot); mkdir -p "$r/usr/share/libalpm/hooks"
printf '[Trigger]\nType = Path\nOperation = Install\nTarget = usr/lib/modules/*/vmlinuz\nTarget = usr/lib/initcpio/*\n\n[Action]\nWhen = PostTransaction\nExec = /usr/share/libalpm/scripts/mkinitcpio install\n' > "$r/usr/share/libalpm/hooks/90-mkinitcpio-install.hook"
printf '[Trigger]\nType = Package\nOperation = Upgrade\nTarget = *\n\n[Action]\nWhen = PostTransaction\nExec = /usr/bin/update-desktop-database\n' > "$r/usr/share/libalpm/hooks/update-desktop-database.hook"
out=$(guard "$r" audit); ok "audit: known boot hooks are covered" "$?" 0
ok "audit: a catch-all hook that writes no boot file does not count" "$(echo "$out" | grep -c 'cover every boot-file hook')" 1
printf '[Trigger]\nType = Path\nOperation = Upgrade\nTarget = usr/lib/newthing/*\n\n[Action]\nWhen = PostTransaction\nExec = /usr/bin/limine-update\n' > "$r/etc/pacman.d/hooks/99-new-boot.hook"
out=$(guard "$r" audit); ok "audit: a boot hook with an unknown trigger is reported" "$?" 1
ok "audit: it names hook and trigger" "$(echo "$out" | grep -c '99-new-boot.hook: usr/lib/newthing/\*')" 1
ok "audit: and leaves the stale marker" "$(test -s "$r/var/lib/omarchy-k114s/esp-triggers-stale"; status)" 0
out=$(echo firefox | guard "$r" install 0); ok "stale triggers: now every install is checked for space" "$?" 1
out=$(echo firefox | guard "$r" install $((300 * MB))); ok "stale triggers: with room it passes" "$?" 0
echo "99-new-boot.hook   # reviewed: writes nothing" >> "$(lib "$r")/esp-audit-ignore.list"
out=$(guard "$r" audit); ok "audit: a reviewed hook can be listed as harmless" "$?" 0
ok "audit: the stale marker is gone" "$(test -e "$r/var/lib/omarchy-k114s/esp-triggers-stale"; status)" 1
printf '[Trigger]\nType = Path\nOperation = Upgrade\nTarget = usr/lib/other/*\n\n[Action]\nWhen = PostTransaction\nExec = /usr/bin/true\n' > "$r/etc/pacman.d/hooks/90-mkinitcpio-install.hook"
out=$(guard "$r" audit); ok "audit: a hook in /etc overrides the same name in /usr/share" "$?" 0
: > "$r/etc/omarchy-k114s/esp-guard-conservative"
out=$(echo firefox | guard "$r" install 0); ok "conservative marker: every install is checked for space" "$?" 1
# the hooks of the machine this runs on, when it is an Omarchy Mac (read-only: copies)
if [ -d /usr/lib/omarchy/mac-boot ] && [ -d /usr/share/libalpm/hooks ]; then
  r=$(mkroot); mkdir -p "$r/usr/share/libalpm/hooks"
  cp /usr/share/libalpm/hooks/*.hook "$r/usr/share/libalpm/hooks/" 2>/dev/null
  for hook in /etc/pacman.d/hooks/*.hook; do case ${hook##*/} in 0?-k114s-*) ;; *) cp "$hook" "$r/etc/pacman.d/hooks/" 2>/dev/null ;; esac; done
  out=$(guard "$r" audit); ok "audit: covers every boot-file hook installed on this machine" "$? $(echo "$out" | head -n 3 | tr '\n' ' ')" "0 k114s-guard audit: the space guard's triggers cover every boot-file hook on this system "
fi

# --- holds: the managed block -------------------------------------------------------------------------------
r=$(mkroot); before=$(conf_sum "$r")
out=$(holds "$r" check); ok "holds check: a fresh template has none" "$?" 1
out=$(holds "$r" apply); ok "holds apply" "$?" 0
want=$(printf '%s\n' $HELD | LC_ALL=C sort | tr '\n' ' '); want=${want% }
ok "IgnorePkg holds the whole list" "$(sed -n 's/^IgnorePkg = //p' "$r/etc/pacman.conf")" "$want"
ok "the block sits right under [options]" "$(sed -n '2,3p' "$r/etc/pacman.conf" | cut -c1-17 | tr '\n' '|')" "[options]|# >>> K114s holds|"
ok "NoUpgrade keeps the Stage 2 hook script" "$(grep -c '^NoUpgrade = usr/local/lib/omarchy-j714s/update-boot-ctxr$' "$r/etc/pacman.conf")" 1
ok "NoExtract keeps the stock-ABI title-bar plugin out" "$(sed -n 's/^NoExtract = //p' "$r/etc/pacman.conf")" "usr/lib/omarchy-hyprland-titlebars/titlebars.so"
out=$(holds "$r" check); ok "holds check passes after apply" "$?" 0
after=$(conf_sum "$r"); holds "$r" apply >/dev/null; ok "apply twice changes nothing" "$(conf_sum "$r")" "$after"
if command -v pacman-conf >/dev/null; then
  ok "pacman itself reads the holds" "$(pacman-conf --config "$r/etc/pacman.conf" IgnorePkg | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')" "$want"
  ok "pacman itself reads NoExtract" "$(pacman-conf --config "$r/etc/pacman.conf" NoExtract)" "usr/lib/omarchy-hyprland-titlebars/titlebars.so"
fi
template "$r" edge; out=$(holds "$r" check); ok "a channel refresh (template over pacman.conf) drops them" "$?" 1
holds "$r" apply >/dev/null; ok "and apply puts the same block back" "$(conf_sum "$r")" "$after"
holds "$r" remove >/dev/null; ok "remove leaves the template exactly" "$(conf_sum "$r")" "$before"
# over r2c's block and the image's own line
r=$(mkroot)
printf '[options]\n# >>> K114s holds (omarchy-m5p-oled): written by /usr/local/lib/omarchy-k114s/apply-holds; edit holds.list, not these lines\nIgnorePkg = linux-aurora m1n1-aurora\nNoUpgrade = usr/local/lib/omarchy-j714s/update-boot-ctxr\n# <<< K114s holds\n# Test image only: keep these three lines\nIgnorePkg = linux-aurora mesa-aurora omarchy\nColor\n\n[omarchy]\nServer = file:///x/edge/os\n' > "$r/etc/pacman.conf"
holds "$r" apply >/dev/null
ok "r2c's block is replaced, not doubled" "$(grep -c '^# >>> K114s holds' "$r/etc/pacman.conf")" 1
ok "the image's own IgnorePkg line is left alone" "$(grep -c '^IgnorePkg = linux-aurora mesa-aurora omarchy$' "$r/etc/pacman.conf")" 1
out=$(holds "$r" release mesa-aurora 1:27.0.0-1); ok "release" "$(echo "$out" | grep -c 'mesa-aurora released')" 1
ok "released: out of our block" "$(sed -n '3p' "$r/etc/pacman.conf" | grep -c -w mesa-aurora)" 0
ok "released: out of the image's own line too" "$(grep -c '^IgnorePkg = linux-aurora omarchy$' "$r/etc/pacman.conf")" 1
ok "released: recorded with its version" "$(cut -d' ' -f1,2 "$(lib "$r")/released.list")" "mesa-aurora 1:27.0.0-1"
out=$(holds "$r" check); ok "check passes after a release" "$?" 0
out=$(holds "$r" release mesa-aurora); ok "releasing twice is harmless" "$(wc -l < "$(lib "$r")/released.list" | tr -d ' ')" 1
holds "$r" hold mesa-aurora >/dev/null; ok "hold puts it back" "$(sed -n '3p' "$r/etc/pacman.conf" | grep -c -w mesa-aurora)" 1
ok "hold: no longer released" "$(grep -c mesa-aurora "$(lib "$r")/released.list")" 0
out=$(holds "$r" release 'bad name;rm'); ok "a bad package name is refused" "$?" 1
# NoExtract follows the installed plugin build
r=$(mkroot); holds "$r" apply >/dev/null
rm -rf "$r/var/lib/pacman/local/omarchy-hyprland-titlebars-0.4.0-1"; dbpkg "$r" omarchy-hyprland-titlebars 1:0.4.0+m5-1
holds "$r" apply >/dev/null; ok "NoExtract goes once the +m5 build of the plugin is installed" "$(grep -c '^NoExtract' "$r/etc/pacman.conf")" 0
r=$(mkroot); holds "$r" apply >/dev/null
holds "$r" lift-noextract usr/lib/omarchy-hyprland-titlebars/titlebars.so >/dev/null; ok "lift-noextract takes the line out for one transaction" "$(grep -c '^NoExtract' "$r/etc/pacman.conf")" 0
holds "$r" restore-noextract >/dev/null; ok "restore-noextract puts it back" "$(grep -c '^NoExtract' "$r/etc/pacman.conf")" 1
r=$(mkroot); holds "$r" apply >/dev/null; holds "$r" release omarchy-hyprland-titlebars 0.5.0-1 >/dev/null
ok "NoExtract goes when the plugin package is released (its channel build passed the criteria)" "$(grep -c '^NoExtract' "$r/etc/pacman.conf")" 0
holds "$r" hold omarchy-hyprland-titlebars >/dev/null; ok "and is back when it is held again" "$(grep -c '^NoExtract' "$r/etc/pacman.conf")" 1
r=$(mkroot); printf '# no options\n[omarchy]\nServer = file:///x/edge/os\n' > "$r/etc/pacman.conf"; b=$(conf_sum "$r")
out=$(holds "$r" apply); ok "no [options] section: refuses" "$?" 1; ok "no [options]: file untouched" "$(conf_sum "$r")" "$b"
ok "show lists the held names" "$(holds "$r" show | wc -l | tr -d ' ')" "$(echo $HELD | wc -w | tr -d ' ')"

# --- the pre-refresh user hook: wait, ask sudo, fail loudly ---------------------------------------------
hook() { local r=$1; shift; env K114S_ROOT="$r" K114S_HOLDS_WAIT=1 "$@" bash "$L/hooks/pre-refresh-pacman-k114s-holds" 2>&1; }
cat > "$BASE/sudo-ok" <<'STUB'
#!/bin/bash
echo "sudo $*" >> "$SUDO_LOG"
exec bash "$@"
STUB
printf '#!/bin/bash\necho "sudo: a password is required" >&2\nexit 1\n' > "$BASE/sudo-fail"; chmod +x "$BASE/sudo-ok" "$BASE/sudo-fail"
r=$(mkroot); holds "$r" apply >/dev/null; export SUDO_LOG=$r/sudo.log
out=$(hook "$r" K114S_SUDO="$BASE/sudo-fail"); ok "hook: holds in place, nothing to do, sudo not needed" "$? $(echo "$out" | wc -c | tr -d ' ')" "0 1"
template "$r" edge; out=$(hook "$r" K114S_SUDO="$BASE/sudo-ok"); ok "hook: after a refresh it puts the holds back through sudo" "$?" 0
ok "hook: the holds verify" "$(holds "$r" check; status)" 0
template "$r" edge; out=$(hook "$r" K114S_SUDO="$BASE/sudo-fail"); ok "hook: sudo fails -> the hook fails" "$?" 1
ok "hook: and says so loudly" "$(echo "$out" | grep -c -E '=+ K114s: the package holds could NOT be put back \(sudo failed\) =+')" 1
ok "hook: tells what happens next" "$(echo "$out" | grep -c 'will be stopped by the K114s hold guard')" 1
ok "hook: the holds are indeed missing" "$(holds "$r" check; status)" 1
out=$(echo linux-aurora | guard "$r" install); ok "hook: and the pacman guard is what stops the downgrade then" "$?" 1
template "$r" stable; out=$(hook "$r" K114S_SUDO="$BASE/sudo-ok"); ok "hook: a refresh to another channel is announced" "$(echo "$out" | grep -c 'this refresh moves to the stable channel')" 1
r=$(mkroot); rm "$(lib "$r")/k114s-holds"; out=$(hook "$r" K114S_SUDO="$BASE/sudo-ok"); ok "hook: tooling missing -> fails loudly" "$? $(echo "$out" | grep -c 'not installed')" "1 1"
# no sudo and no guard installed: the last resort ends the refresh that called it
r=$(mkroot); rm "$r"/etc/pacman.d/hooks/00-k114s-guard-install.hook
mkdir -p "$BASE/bin"
cat > "$BASE/bin/omarchy-hook" <<STUB
#!/bin/bash
bash "$L/hooks/pre-refresh-pacman-k114s-holds" || echo "Hook failed"
STUB
cat > "$BASE/bin/omarchy-refresh-pacman" <<STUB
#!/bin/bash
bash "$BASE/bin/omarchy-hook"
echo "PACMAN WOULD RUN NOW" > "$r/reached-pacman"
STUB
out=$(K114S_ROOT=$r K114S_HOLDS_WAIT=1 K114S_SUDO="$BASE/sudo-fail" bash "$BASE/bin/omarchy-refresh-pacman" 2>&1)
ok "hook: no sudo and no guard -> the refresh is ended before its pacman" "$(test -e "$r/reached-pacman"; status)" 1
ok "hook: with the reason" "$(echo "$out" | grep -c 'the hold guard is not installed')" 1
# with the guard installed the refresh is left running (the guard stops the transaction)
r=$(mkroot); sed -i "s#$BASE/root[^/]*/reached#$r/reached#" "$BASE/bin/omarchy-refresh-pacman"
out=$(K114S_ROOT=$r K114S_HOLDS_WAIT=1 K114S_SUDO="$BASE/sudo-fail" bash "$BASE/bin/omarchy-refresh-pacman" 2>&1)
ok "hook: with the guard installed the refresh runs on into the guard" "$(test -e "$r/reached-pacman"; status)" 0

finish "r3 guard tests"
