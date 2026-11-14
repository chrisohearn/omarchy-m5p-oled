#!/bin/bash
# Tests of linux/ (bundle r2c) in a fake root. No real system file is touched.
#   usage: test-persist.sh LINUX_DIR FIXTURES ESP_R1 ESP_R1A
# LINUX_DIR is this repository's linux/. FIXTURES holds the build outputs, which are not in the
# repository: out/Image-k114s-{r1,r1a}, persisttest/src/hid-magicmouse-{r1,r1a}.ko,
# persisttest/t6050-k114s-r1{,-gp1c}.dtb, persisttest/gp1c-stage2.bin, hooktest/boot.bin,
# hooktest/aura-stage2-prefix.bin. ESP_R1 and ESP_R1A are ESP copies the r2c macOS tool applied
# to (test mode), with repair kernel r1 and r1a: their repair kernel image and k114s-repair/r2c.
set -u
L=$(cd "$1" && pwd); F=$(cd "$2" && pwd); E1=$(cd "$3" && pwd); E1A=$(cd "$4" && pwd)
FTAB_SUM=$(awk '$1 == "ftab" {print $4}' "$E1/k114s-repair/r2c/repair-uki.txt")
pass=0; fail=0; KVER=7.3.0-17.v272-4-ARCH
BASE=$(mktemp -d "${TMPDIR:-/tmp}/k114s-persist-test.XXXXXX"); trap 'rm -rf "$BASE"' EXIT   # each fake root is about 40 MB
R1_STAGE2=45a5dbef19c14898e73e79a42af360def638c319d14e2bae97a79f7962e4bfb4
IMAGE_PINS="alsa-ucm-conf-aurora aurora-audio aurora-bless limine-mkinitcpio-hook linux-aurora linux-aurora-headers m1n1-aurora mesa-aurora omarchy omarchy-aurora-firmware omarchy-mac omarchy-mac-boot omarchy-settings speakerguardd uboot-aurora vulkan-aurora"
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: got [$2] want [$3]"; fi; }
sum() { sha256sum "$1" 2>/dev/null | cut -c1-64; }

mk() { # a fake installed system with the r2 files on its ESP; prints its root
  local r e
  local src=${FIX_ESP:-$E1}
  r=$(mktemp -d "$BASE/root.XXXXXX"); e=$r/boot/efi/k114s-repair/r2c
  mkdir -p "$e" "$r/usr/lib/modules/$KVER/kernel/drivers/hid" "$r/usr/local/lib/omarchy-j714s" "$r/etc/pacman.d/hooks" \
    "$r/boot/efi/m1n1" "$r/boot/efi/EFI/Linux" "$r/usr/lib/asahi-boot" "$r/dt" "$r/var/lib/pacman/local" "$r/userhome"
  cp "$L"/linux-persist.sh "$L"/update-boot-ctxr-k114s "$L"/apply-holds "$L"/hold-guard "$L"/00-k114s-hold-guard.hook \
    "$L"/esp-space-guard "$L"/01-k114s-esp-space.hook "$L"/k114s-booted-esp "$L"/k114s-edge-check "$L"/README-linux.txt "$e/"
  cp "$src"/k114s-repair/r2c/repair-uki.txt "$src"/k114s-repair/r2c/hid-magicmouse-*.ko "$e/"
  ln "$src/EFI/Linux/omarchy_linux-aurora-k114s.efi" "$r/boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi" 2>/dev/null ||
    cp --reflink=auto "$src/EFI/Linux/omarchy_linux-aurora-k114s.efi" "$r/boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi"
  (cd "$e" && sha256sum $(ls | grep -v SHA256SUMS) > SHA256SUMS)
  cp "$F/persisttest/t6050-k114s-r1.dtb" "$r/boot/efi/k114s-repair/k114s.dtb"
  echo OLDKERNEL > "$r/usr/lib/modules/$KVER/vmlinuz"; echo OLDKERNEL > "$r/boot/vmlinuz-linux-aurora"
  printf '#!/bin/sh\necho j714s-hook\n' > "$r/usr/local/lib/omarchy-j714s/update-boot-ctxr"; chmod 755 "$r/usr/local/lib/omarchy-j714s/update-boot-ctxr"
  printf '# pacman.conf\n[options]\nHoldPkg = pacman glibc\nIgnorePkg = %s\nArchitecture = auto\n\n[core]\nServer = file:///nowhere\n' "$IMAGE_PINS" > "$r/etc/pacman.conf"
  printf 'apple,k114s\0apple,t6050\0' > "$r/dt/compatible"
  printf '#!/bin/sh\necho "$@" >> %s/depmod.log\n' "$r" > "$r/depmod"; chmod +x "$r/depmod"
  # a pacman stand-in: lists, and logs what it is asked to change
  printf 'linux-aurora\nomarchy-mac-boot\nsome-library\n' > "$r/deps.list"
  cat > "$r/pacman" <<STUB
#!/bin/sh
echo "\$*" >> $r/pacman.log
case "\$1" in
  -Qqd) cat $r/deps.list ;;
  -Q) printf 'linux-aurora 7.3.0.aurora17.v272-4\nm1n1-aurora 1.6.1.aurora24.v272-3\n' ;;
  -D) [ ! -e $r/pacman.fail ] || exit 1 ;;
esac
STUB
  chmod +x "$r/pacman"
  echo "$r"
}
run() { # run linux-persist.sh in fake root R with the given arguments
  local r=$1; shift
  K114S_USER_HOME=$r/userhome K114S_ROOT=$r K114S_DT_COMPATIBLE=$r/dt/compatible K114S_DEPMOD=$r/depmod K114S_PACMAN=$r/pacman \
    K114S_PACMAN_CONF=${PC:-false} K114S_ESP_DT=${ESPDT:-$r/none} K114S_ESP_PARTUUID=${ESPUUID:-} \
    K114S_UNAME_V="${UV:-#1 SMP PREEMPT K114S-R1 Sat Nov 14 2026}" bash "$r/boot/efi/k114s-repair/r2c/linux-persist.sh" "$@" 2>&1
}
snap() { (cd "$1" && find . -type f ! -path './usr/local/lib/omarchy-k114s/*' ! -path './userhome/*' ! -name depmod.log ! -name pacman.log \
  -exec sha256sum {} + | sort -k2 | sha256sum | cut -c1-16); }
lib() { echo "$1/usr/local/lib/omarchy-k114s"; }

# --- the r1 behaviour, unchanged ------------------------------------------------------------
r=$(mk); before=$(snap "$r"); out=$(run "$r"); ok "persist succeeds" "$(echo "$out" | grep -c 'done. Installed')" 1
ok "kernel image installed" "$(sum "$r/usr/lib/modules/$KVER/vmlinuz")" "$(sum "$F/out/Image-k114s-r1")"
ok "/boot kernel copy updated" "$(sum "$r/boot/vmlinuz-linux-aurora")" "$(sum "$F/out/Image-k114s-r1")"
ok "module in updates/" "$(sum "$r/usr/lib/modules/$KVER/updates/hid-magicmouse.ko")" "$(sum "$F/persisttest/src/hid-magicmouse-r1.ko")"
ok "depmod ran for the kernel" "$(tail -1 "$r/depmod.log")" "-b $r $KVER"
ok "Wi-Fi firmware installed from the repair kernel image" "$(sum "$r/usr/lib/firmware/updates/apple/centauri/k114s-ftab.bin")" "$FTAB_SUM"
ok "space guard and its hook installed" "$(ls "$(lib "$r")/esp-space-guard" "$r/etc/pacman.d/hooks/01-k114s-esp-space.hook" | wc -l | tr -d ' ')" 2
ok "J714s hook script now runs the K114s one" "$(grep -c omarchy-k114s/update-boot-ctxr "$r/usr/local/lib/omarchy-j714s/update-boot-ctxr")" 1
ok "pinned device tree installed" "$(sum "$(lib "$r")/k114s.dtb")" "$(sum "$F/persisttest/t6050-k114s-r1.dtb")"
out=$(run "$r"); ok "second run refused" "$(echo "$out" | grep -c 'already applied')" 1

# --- holds: the image's whole pinned set, not three names --------------------------------------
want=$(printf '%s\n' $IMAGE_PINS | LC_ALL=C sort -u | tr '\n' ' '); want=${want% }
ok "holds.list is the image's pinned set" "$(tr '\n' ' ' < "$(lib "$r")/holds.list" | sed 's/ $//')" "$want"
ok "the managed block holds the whole set" "$(sed -n '/^# >>> K114s holds/,/^# <<< K114s holds/p' "$r/etc/pacman.conf" | grep -c -Fx "IgnorePkg = $want")" 1
ok "block sits right under [options]" "$(sed -n '3p' "$r/etc/pacman.conf" | cut -c1-17)" "# >>> K114s holds"
ok "the image's own line is still there" "$(grep -c "^IgnorePkg = alsa-ucm-conf-aurora aurora-audio" "$r/etc/pacman.conf")" 2
ok "other pacman.conf lines kept" "$(grep -c -E '^(HoldPkg|Architecture|\[core\]|Server)' "$r/etc/pacman.conf")" 4
# a channel refresh copies a template over pacman.conf, then runs the user hook
h=$r/userhome/.config/omarchy/hooks/pre-refresh-pacman.d/k114s-holds
ok "channel-refresh hook installed for the user" "$(grep -c 'sudo /usr/local/lib/omarchy-k114s/apply-holds' "$h")" 1
printf '# rendered template\n[options]\nHoldPkg = pacman glibc\nArchitecture = auto\n[omarchy]\nServer = x\n' > "$r/etc/pacman.conf"
K114S_ROOT=$r bash "$(lib "$r")/apply-holds" >/dev/null 2>&1
ok "after a template replaced pacman.conf: the whole set is held again" "$(grep -c -Fx "IgnorePkg = $want" "$r/etc/pacman.conf")" 1
ok "NoUpgrade re-applied" "$(grep -c '^NoUpgrade = usr/local/lib/omarchy-j714s/update-boot-ctxr' "$r/etc/pacman.conf")" 1
K114S_ROOT=$r bash "$(lib "$r")/apply-holds" >/dev/null 2>&1; ok "apply-holds is idempotent" "$(grep -c '^IgnorePkg' "$r/etc/pacman.conf")" 1
ok "template lines kept" "$(grep -c -E '^(HoldPkg|Architecture|\[omarchy\]|Server)' "$r/etc/pacman.conf")" 4
echo extra-package >> "$(lib "$r")/holds.list"; K114S_ROOT=$r bash "$(lib "$r")/apply-holds" >/dev/null 2>&1
ok "a changed holds.list replaces the block" "$(grep -c '^IgnorePkg = .* extra-package' "$r/etc/pacman.conf")$(grep -c '^IgnorePkg' "$r/etc/pacman.conf")$(grep -c '^# >>> K114s holds' "$r/etc/pacman.conf")" 111
echo 'bad name; rm -rf' >> "$(lib "$r")/holds.list"; K114S_ROOT=$r bash "$(lib "$r")/apply-holds" >/dev/null 2>&1
ok "an invalid name in holds.list is left out" "$(grep -c 'rm -rf' "$r/etc/pacman.conf")" 0
K114S_ROOT=$r bash "$(lib "$r")/apply-holds" --remove >/dev/null 2>&1
ok "--remove takes exactly the block out" "$(tr '\n' '|' < "$r/etc/pacman.conf")" "# rendered template|[options]|HoldPkg = pacman glibc|Architecture = auto|[omarchy]|Server = x|"
printf '# no options\n[core]\n' > "$r/etc/pacman.conf"; K114S_ROOT=$r bash "$(lib "$r")/apply-holds" >/dev/null 2>&1
ok "apply-holds refuses a file without [options]" "$?" 1; ok "and leaves it unchanged" "$(tr '\n' '|' < "$r/etc/pacman.conf")" "# no options|[core]|"
rm "$(lib "$r")/holds.list"; printf '[options]\n' > "$r/etc/pacman.conf"; K114S_ROOT=$r bash "$(lib "$r")/apply-holds" >/dev/null 2>&1
ok "without holds.list the boot stack is still held" "$(grep -c -Fx 'IgnorePkg = linux-aurora m1n1-aurora uboot-aurora' "$r/etc/pacman.conf")" 1
r=$(mk); printf '# pacman.conf\n[options]\nArchitecture = auto\n' > "$r/etc/pacman.conf"; run "$r" >/dev/null
ok "an image without pins: the boot stack is held" "$(tr '\n' ' ' < "$(lib "$r")/holds.list")" "linux-aurora m1n1-aurora uboot-aurora "
if command -v pacman-conf >/dev/null; then
  r=$(mk); PC=pacman-conf run "$r" >/dev/null
  ok "pacman-conf reads the same pinned set" "$(tr '\n' ' ' < "$(lib "$r")/holds.list" | sed 's/ $//')" "$want"
fi

# --- the hold guard --------------------------------------------------------------------------
r=$(mk); run "$r" >/dev/null; g=$(lib "$r")/hold-guard; hook=$r/etc/pacman.d/hooks/00-k114s-hold-guard.hook
ok "guard hook installed" "$(sum "$hook")" "$(sum "$L/00-k114s-hold-guard.hook")"
ok "hook is pre-transaction, aborting, with targets" "$(grep -c -E '^(When = PreTransaction|AbortOnFail|NeedsTargets|Exec = /usr/local/lib/omarchy-k114s/hold-guard)$' "$hook")" 4
ok "hook names the boot chain" "$(grep -c -E '^Target = (linux-aurora|m1n1-aurora|uboot-aurora|omarchy-aurora-firmware|omarchy-mac-boot|limine-mkinitcpio-hook)$' "$hook")" 6
ok "hook covers install, upgrade and remove" "$(grep -c -E '^Operation = (Install|Upgrade|Remove)$' "$hook")" 4
ok "hook also stops the removal a channel switch makes" "$(sed -n '/^# A channel switch/,/^\[Action\]/p' "$hook" | grep -c -E '^(Operation = Remove|Target = omarchy|Target = omarchy-settings)$')" 3
ok "hook has two triggers and one action" "$(grep -c '^\[Trigger\]$' "$hook")$(grep -c '^\[Action\]$' "$hook")" 21
out=$(printf 'linux-aurora\nm1n1-aurora\n' | K114S_ROOT=$r sh "$g" 2>&1); ok "guard stops a transaction on the boot chain" "$?" 1
ok "guard names the packages" "$(echo "$out" | grep -c 'linux-aurora m1n1-aurora')" 1
ok "guard says how to put the holds back" "$(echo "$out" | grep -c 'apply-holds')" 1
mkdir -p "$r/etc/omarchy-k114s"; : > "$r/etc/omarchy-k114s/allow-coupled-update"
printf 'linux-aurora\n' | K114S_ROOT=$r sh "$g" >/dev/null 2>&1; ok "guard lets a deliberate update through" "$?" 0
rm "$r/etc/omarchy-k114s/allow-coupled-update"; printf '' | K114S_ROOT=$r sh "$g" >/dev/null 2>&1; ok "guard passes with no targets" "$?" 0

# --- boot check declaration, install reasons, record ------------------------------------------
ok "owner-boot-chain written" "$(grep -c 'omarchy-m5p-oled bundle r2' "$r/etc/omarchy-mac-boot/owner-boot-chain")" 1
ok "dependencies of the boot chain marked explicit" "$(grep -c -E '^-D --asexplicit (linux-aurora|omarchy-mac-boot)$' "$r/pacman.log")" 2
ok "nothing else marked" "$(grep -c -- '-D --asexplicit' "$r/pacman.log")" 2
rec=$(ls -d "$(lib "$r")"/recovery/*-before-persist-r2c)
ok "record has the package list" "$(grep -c '^linux-aurora 7.3.0.aurora17.v272-4$' "$rec/packages.txt")" 1
ok "record has the kernel as it was before" "$(grep -c "$(echo OLDKERNEL | sha256sum | cut -c1-64)  boot/vmlinuz-linux-aurora" "$rec/boot-files.sha256")" 1
ok "record has pacman.conf as it was before" "$(grep -c '^# >>> K114s holds' "$rec/pacman.conf")" 0

# --- undo ------------------------------------------------------------------------------------
r=$(mk); before=$(snap "$r"); run "$r" >/dev/null
cp "$F/hooktest/boot.bin" "$r/boot/efi/m1n1/boot.bin"; cp "$F/hooktest/aura-stage2-prefix.bin" "$r/usr/lib/asahi-boot/m1n1.bin"; echo OLD > "$r/boot/efi/m1n1/boot-ctxr.bin"
sed -i "s#exec /usr/local#exec $r/usr/local#" "$r/usr/local/lib/omarchy-j714s/update-boot-ctxr"; OMARCHY_ROOT=$r sh "$r/usr/local/lib/omarchy-j714s/update-boot-ctxr" >/dev/null 2>&1
ok "hook chain writes the r1 Stage 2" "$(sum "$r/boot/efi/m1n1/boot-ctxr.bin")" "$R1_STAGE2"
rm -f "$r/boot/efi/m1n1/boot.bin" "$r/boot/efi/m1n1/boot-ctxr.bin" "$r/usr/lib/asahi-boot/m1n1.bin"
out=$(run "$r" --undo); ok "undo succeeds" "$(echo "$out" | grep -c undone)" 1; ok "undo restores every file" "$(snap "$r")" "$before"
ok "undo marks the two packages as dependencies again" "$(grep -c -E '^-D --asdeps (linux-aurora|omarchy-mac-boot)$' "$r/pacman.log")" 2
ok "undo removes the user hook" "$(ls "$r/userhome/.config/omarchy/hooks/pre-refresh-pacman.d" 2>/dev/null | wc -l)" 0
ok "undo removes the installed tools" "$(ls "$(lib "$r")" | grep -c -E '^(apply-holds|hold-guard|holds.list|update-boot-ctxr|k114s.dtb|k114s-booted-esp|k114s-edge-check|esp-space-guard)$')" 0
ok "undo removes the Wi-Fi firmware and the folders it made" "$(ls -d "$r/usr/lib/firmware" 2>/dev/null | wc -l | tr -d ' ')" 0
ok "undo removes the space hook" "$(ls "$r/etc/pacman.d/hooks" | grep -c 01-k114s)" 0
ok "undo keeps the record" "$(ls -d "$(lib "$r")"/recovery/* | wc -l)" 1
r=$(mk); mkdir -p "$r/etc/omarchy-mac-boot"; echo "my own chain" > "$r/etc/omarchy-mac-boot/owner-boot-chain"; b=$(snap "$r"); run "$r" >/dev/null; run "$r" --undo >/dev/null
ok "an owner-boot-chain that was already there is kept" "$(cat "$r/etc/omarchy-mac-boot/owner-boot-chain")" "my own chain"; ok "and undo is still exact" "$(snap "$r")" "$b"
r=$(mk); run "$r" >/dev/null; echo "IgnorePkg = someone-elses-package" >> "$r/etc/pacman.conf"; echo "[custom]" >> "$r/etc/pacman.conf"; run "$r" --undo >/dev/null
ok "undo removes only the K114s block" "$(grep -c -E 'K114s holds|^NoUpgrade = usr/local' "$r/etc/pacman.conf")" 0
ok "undo keeps the image's line and later edits" "$(grep -c -E '^IgnorePkg = (someone-elses-package|alsa-ucm-conf-aurora .*)$|^\[custom\]|^HoldPkg|^Architecture' "$r/etc/pacman.conf")" 5

# --- refusals change nothing -----------------------------------------------------------------
r=$(mk); b=$(snap "$r"); out=$(UV="#2 SMP PREEMPT Fri, 13 Nov 2026" run "$r"); ok "refused on the original kernel" "$(echo "$out" | grep -c 'not a repair kernel')" 1; ok "refusal changes nothing" "$(snap "$r")" "$b"
r=$(mk); printf 'apple,j714s\0' > "$r/dt/compatible"; b=$(snap "$r"); out=$(run "$r"); ok "refused on another board" "$(echo "$out" | grep -c 'not an apple,k114s')" 1; ok "other board: nothing changed" "$(snap "$r")" "$b"
r=$(mk); echo x >> "$r/boot/efi/k114s-repair/r2c/hid-magicmouse-r1.ko"; b=$(snap "$r"); out=$(run "$r"); ok "damaged files refused" "$(echo "$out" | grep -c 'do not match SHA256SUMS')" 1; ok "damaged files: nothing changed" "$(snap "$r")" "$b"
r=$(mk); u=$r/boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi; cp --remove-destination "$E1/EFI/Linux/omarchy_linux-aurora-k114s.efi" "$u"; printf 'Z' | dd of="$u" bs=1 seek=60000000 conv=notrunc status=none
b=$(snap "$r"); out=$(run "$r"); ok "damaged repair kernel image refused" "$(echo "$out" | grep -c 'does not match')" 1; ok "damaged image: nothing changed" "$(snap "$r")" "$b"
r=$(mk); rm "$r/boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi"; b=$(snap "$r"); out=$(run "$r"); ok "missing repair kernel image refused" "$(echo "$out" | grep -c 'does not match')" 1; ok "missing image: nothing changed" "$(snap "$r")" "$b"
r=$(mk); b=$(snap "$r"); out=$(UV="#1 SMP PREEMPT K114S-R1A Sat Nov 14 2026" run "$r"); ok "running r1a against an r1 image refused" "$(echo "$out" | grep -c 'boot the repair entry again')" 1; ok "variant mismatch: nothing changed" "$(snap "$r")" "$b"
r=$(mk); run "$r" >/dev/null; g=$(lib "$r")/esp-space-guard
K114S_ROOT=$r sh "$g" >/dev/null 2>&1; ok "space guard passes with room on the ESP" "$?" 0
out=$(K114S_ROOT=$r K114S_ESP_MIN_FREE=999999999999999 sh "$g" 2>&1); ok "space guard stops package changes when the ESP is too full" "$?" 1; ok "and says why" "$(echo "$out" | grep -c 'K114s space guard: stopped')" 1
mkdir -p "$r/etc/omarchy-k114s"; : > "$r/etc/omarchy-k114s/allow-low-esp"; K114S_ROOT=$r K114S_ESP_MIN_FREE=999999999999999 sh "$g" >/dev/null 2>&1; ok "space guard can be overridden on purpose" "$?" 0
ok "space hook: pre-transaction, aborting, every package" "$(grep -c -E '^(When = PreTransaction|AbortOnFail|Target = \*|Exec = /usr/local/lib/omarchy-k114s/esp-space-guard)$' "$r/etc/pacman.d/hooks/01-k114s-esp-space.hook")" 4
r=$(mk); printf '# no options section\n[core]\n' > "$r/etc/pacman.conf"; b=$(snap "$r"); out=$(run "$r"); ok "pacman.conf without [options]: stops" "$(echo "$out" | grep -c 'could not find')" 1; ok "no [options]: nothing changed" "$(snap "$r")" "$b"
r=$(mk); mkdir -p "$(lib "$r")/persist-r1"; out=$(run "$r"); ok "refused while r1's persistence is applied" "$(echo "$out" | grep -c "bundle r1's persistence is applied")" 1
r=$(mk); mkdir -p "$(lib "$r")/persist-r2"; out=$(run "$r"); ok "refused while r2's persistence is applied" "$(echo "$out" | grep -c "bundle r2's persistence is applied")" 1
r=$(mk); out=$(run "$r" --bogus); ok "unknown argument refused" "$(echo "$out" | grep -c 'unknown argument')" 1
r=$(FIX_ESP=$E1A mk); out=$(UV="#1 SMP PREEMPT K114S-R1A Sat Nov 14 2026" run "$r"); ok "r1a: persist succeeds" "$(echo "$out" | grep -c 'done. Installed')" 1
ok "r1a: its kernel image installed" "$(sum "$r/usr/lib/modules/$KVER/vmlinuz")" "$(sum "$F/out/Image-k114s-r1a")"; ok "r1a: its module installed" "$(sum "$r/usr/lib/modules/$KVER/updates/hid-magicmouse.ko")" "$(sum "$F/persisttest/src/hid-magicmouse-r1a.ko")"

# --- the ESP this boot came from ---------------------------------------------------------------
U=6f2a1c3e-0b5d-4e7a-9c11-2d3e4f5a6b7c; V=11111111-2222-3333-4444-555555555555
r=$(mk); printf '%s\0' "$U" > "$r/espdt"; out=$(ESPDT=$r/espdt ESPUUID=$(echo "$U" | tr a-f A-F) run "$r"); ok "booted ESP matches (case ignored): persist runs" "$(echo "$out" | grep -c 'done. Installed')" 1
r=$(mk); printf '%s\0' "$U" > "$r/espdt"; b=$(snap "$r"); out=$(ESPDT=$r/espdt ESPUUID=$V run "$r"); ok "another ESP mounted: refused" "$(echo "$out" | grep -c 'not the one this boot came from')" 1
ok "another ESP: nothing changed" "$(snap "$r" | cat; ls "$(lib "$r")" 2>/dev/null | wc -l)" "$b
0"
r=$(mk); printf 'garbage' > "$r/espdt"; out=$(ESPDT=$r/espdt ESPUUID=$V run "$r"); ok "unreadable loader value: not treated as a mismatch" "$(echo "$out" | grep -c 'done. Installed')" 1
# the Stage 2 hook makes the same check
r=$(mk); run "$r" >/dev/null; cp "$F/hooktest/boot.bin" "$r/boot/efi/m1n1/boot.bin"; cp "$F/hooktest/aura-stage2-prefix.bin" "$r/usr/lib/asahi-boot/m1n1.bin"; echo OLD > "$r/boot/efi/m1n1/boot-ctxr.bin"
printf '%s\0' "$U" > "$r/espdt"
K114S_ESP_DT=$r/espdt K114S_ESP_PARTUUID=$V OMARCHY_ROOT=$r sh "$(lib "$r")/update-boot-ctxr" >/dev/null 2>&1; ok "Stage 2 hook refuses another ESP" "$?" 1; ok "and leaves boot-ctxr.bin alone" "$(cat "$r/boot/efi/m1n1/boot-ctxr.bin")" OLD
K114S_ESP_DT=$r/espdt K114S_ESP_PARTUUID=$U OMARCHY_ROOT=$r sh "$(lib "$r")/update-boot-ctxr" >/dev/null 2>&1; ok "Stage 2 hook writes on the booted ESP" "$(sum "$r/boot/efi/m1n1/boot-ctxr.bin")" "$R1_STAGE2"
cp "$F/persisttest/t6050-k114s-r1-gp1c.dtb" "$r/boot/efi/k114s-repair/k114s.dtb"; OMARCHY_ROOT=$r sh "$(lib "$r")/update-boot-ctxr" >/dev/null 2>&1
ok "hook follows the ESP pinned tree (gp1c)" "$(sum "$r/boot/efi/m1n1/boot-ctxr.bin")" "$(sum "$F/persisttest/gp1c-stage2.bin")"
rm "$r/boot/efi/k114s-repair/k114s.dtb"; OMARCHY_ROOT=$r sh "$(lib "$r")/update-boot-ctxr" >/dev/null 2>&1; ok "hook falls back to the installed pinned tree (r1)" "$(sum "$r/boot/efi/m1n1/boot-ctxr.bin")" "$R1_STAGE2"

# --- a step failing part-way ---------------------------------------------------------------
r=$(mk); b=$(snap "$r"); : > "$r/pacman.fail"; out=$(run "$r"); ok "a failing step stops with the undo hint" "$(echo "$out" | grep -c 'stopped part-way')" 1
rm "$r/pacman.fail"; out=$(run "$r" --undo); ok "undo after a part-way stop" "$(echo "$out" | grep -c undone)" 1; ok "part-way undo restores every file" "$(snap "$r")" "$b"

echo "linux-persist r2c tests: $pass passed, $fail failed"
[ "$fail" = 0 ]
