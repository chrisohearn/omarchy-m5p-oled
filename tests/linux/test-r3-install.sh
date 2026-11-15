#!/bin/bash
# Tests of k114s-tooling-install in a fake root: install over bundle r2c's persistence, --refresh,
# and --undo back to exactly what r2c left. No real system file is touched.
#   usage: test-r3-install.sh [LINUX_DIR]
set -u
. "$(dirname "$0")/r3-lib.sh" "${1:-}"
have flock iconv python3 bsdtar zstd vercmp || { echo "r3 install tests: SKIPPED (flock, iconv, python3, bsdtar, zstd and vercmp are needed)"; exit 0; }
status() { echo $?; }
KOLD=7.3.0-17.v272-4-ARCH
IMAGE_HELD="asahi-fwextract asahi-scripts aurora-sep aurora-speaker-upgrade hyprland-m5 libfprint-aurora limine linux-aurora m1n1-aurora mesa-aurora omarchy omarchy-aurora-firmware omarchy-hyprland-titlebars omarchy-mac omarchy-mac-boot omarchy-settings speakerguardd-v2 uboot-aurora vulkan-aurora"
mk() { # a fake root as r2c's linux-persist.sh left it (its own files, hooks, hold list, user hook), nothing of r3
  local r k p; r=$(mktemp -d "$BASE/root.XXXXXX"); k=$(lib "$r")
  mkdir -p "$k/persist-r2c" "$r/etc/pacman.d/hooks" "$r/etc/systemd/system" "$r/var/lib/pacman/local" "$r/var/cache/pacman/pkg" "$r/var/log" "$r/run" \
    "$r/boot/efi/EFI/Linux" "$r/boot/efi/m1n1" "$r/boot/efi/k114s-repair" "$r/usr/local/lib/omarchy-j714s" "$r/usr/lib/modules/$KOLD" "$r/dt" \
    "$r/userhome/.config/omarchy/hooks/pre-refresh-pacman.d" "$r/etc/omarchy-mac-boot"
  cp "$L"/apply-holds "$L"/hold-guard "$L"/esp-space-guard "$L"/k114s-booted-esp "$L"/k114s-edge-check "$k/"
  echo "r2c's stage 2 hook" > "$k/update-boot-ctxr"; chmod 755 "$k/update-boot-ctxr"; echo DTB > "$k/k114s.dtb"
  cp "$L/00-k114s-hold-guard.hook" "$L/01-k114s-esp-space.hook" "$r/etc/pacman.d/hooks/"
  printf '%s\n' $IMAGE_HELD > "$k/holds.list"; : > "$k/persist-r2c/guard-hook.absent"
  printf '#!/bin/bash\nsudo /usr/local/lib/omarchy-k114s/apply-holds\n' > "$r/userhome/.config/omarchy/hooks/pre-refresh-pacman.d/k114s-holds"
  printf '#!/bin/sh\nexec /usr/local/lib/omarchy-k114s/update-boot-ctxr "$@"\n' > "$r/usr/local/lib/omarchy-j714s/update-boot-ctxr"
  echo "K114s owner boot chain" > "$r/etc/omarchy-mac-boot/owner-boot-chain"
  printf '# rendered\n[options]\nHoldPkg = pacman glibc\nSigLevel = Never\n\n[omarchy]\nServer = file://%s/edge/os\n' "$REPO" > "$r/etc/pacman.conf"
  K114S_ROOT=$r bash "$k/apply-holds" >/dev/null
  for p in "linux-aurora 7.3.0.aurora17.v272-4" "m1n1-aurora 1.6.1.aurora24.v272-3" "uboot-aurora 2026.07.aurora6.j714s3-1" "omarchy-aurora-firmware 20261014.j714s9-1" \
      "mesa-aurora 1:26.3.0-1" "vulkan-aurora 1:26.3.0-1" "hyprland-m5 0.57.2-2" "omarchy-hyprland-titlebars 0.4.0-1" "omarchy-dev 4.0.0-1" "omarchy-settings-dev 4.0.0-1" \
      "omarchy-mac 0.2.3-2" "omarchy-mac-boot 20261104-1" "limine 12.9.6-1" "limine-mkinitcpio-hook 1.0-1" "asahi-scripts 20261023-1" "asahi-fwextract 0.9.2-1" "aurora-sep 1.17-1" "speakerguardd-v2 1.0-1"; do
    dbpkg "$r" $p
  done
  kernel_image "$r/boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi" "$KOLD" "CONFIG_IKCONFIG=y" K114S-R1
  echo STAGE2 > "$r/boot/efi/m1n1/boot-ctxr.bin"; echo BOOTBIN > "$r/boot/efi/m1n1/boot.bin"
  printf 'timeout: 5\ndefault_entry: 1\n\n### K114s repair\n/Omarchy K114s repair r1\n  protocol: efi\n  path: boot():/EFI/Linux/omarchy_linux-aurora-k114s.efi\n' > "$r/boot/efi/limine.conf"
  printf 'apple,k114s\0apple,t6050\0' > "$r/dt/compatible"
  printf '\6\0\0\0' > "$r/stub-id"; printf '/\\EFI\\Linux\\omarchy_linux-aurora-k114s.efi' | iconv -f ascii -t utf-16le >> "$r/stub-id"
  printf '#!/bin/sh\necho "$*" >> %s/systemctl.log\n' "$r" > "$r/systemctl"; chmod +x "$r/systemctl"
  echo "$r"
}
inst() { # inst ROOT [ARG...]: the installer from the repository's linux/ folder
  local r=$1; shift
  env ${AURA+K114S_AURA_TRIAL=$AURA} K114S_ROOT="$r" K114S_USER_HOME="${USER_HOME-$r/userhome}" K114S_DT_COMPATIBLE="$r/dt/compatible" K114S_SYSTEMCTL="$r/systemctl" K114S_EFI_STUB_ID="$r/stub-id" \
    K114S_UNAME_R=$KOLD K114S_PROC_VERSION="Linux version $KOLD (test@build) #1 SMP PREEMPT" K114S_ESP_FREE=300000000 K114S_ESP_DT="$r/none" \
    bash "${FROM:-$L}/k114s-tooling-install" "$@" 2>&1
}
# everything r2c left, by content and mode; the r3 state folders that are deliberately kept are not part of it
snap() { (cd "$1" && find . \( -path ./var/lib/omarchy-k114s -o -path './usr/local/lib/omarchy-k114s/tooling-r3*' -o -name systemctl.log -o -path ./run \) -prune -o \( -type f -o -type l \) -printf '%m %p\n' -exec sha256sum {} \; | LC_ALL=C sort | sha256sum | cut -c1-16); }
k() { lib "$1"; }

# --- install -----------------------------------------------------------------------------------
r=$(mk); before=$(snap "$r"); out=$(inst "$r"); ok "install over r2c's persistence" "$? $(echo "$out" | grep -c 'k114s-tooling-install: installed')" "0 1"
ok "the tools are in place and executable" "$(for f in k114s-guard k114s-holds k114s-repackage k114s-recovery-set k114s-release-check k114s-release k114s-boot-success k114s-modules-cleanup k114s-fdt k114s-binscan; do test -x "$(k "$r")/$f" || echo "$f"; done)" ""
ok "the library is installed as a file to source, the data beside it" "$(stat -c %a "$(k "$r")/k114s-lib.sh") $(ls "$(k "$r")" | grep -c -x -E 'release-criteria.conf|kernel-config.required|rivals.list|protected.list|noextract.list|extras.list|esp-audit-ignore.list|holds.default')" "644 8"
ok "installed files are the repository's" "$(for f in k114s-guard k114s-release release-criteria.conf; do cmp -s "$L/$f" "$(k "$r")/$f" || echo "$f"; done; cmp -s "$L/update-boot-ctxr-k114s" "$(k "$r")/update-boot-ctxr" || echo update-boot-ctxr)" ""
ok "pacman hooks: r3's three, r2c's two gone" "$(ls "$r/etc/pacman.d/hooks" | tr '\n' ' ')" "00-k114s-guard-install.hook 00-k114s-guard-remove.hook 01-k114s-guard-esp.hook "
ok "r2c's guard scripts are gone, apply-holds forwards" "$(test -e "$(k "$r")/hold-guard"; status) $(test -e "$(k "$r")/esp-space-guard"; status) $(grep -q 'exec /usr/local/lib/omarchy-k114s/k114s-holds apply' "$(k "$r")/apply-holds"; status)" "1 1 0"
ok "hold list: what was held and is installed, plus the default set that is installed" "$(tr '\n' ' ' < "$(k "$r")/holds.list")" \
  "asahi-fwextract asahi-scripts aurora-sep hyprland-m5 limine limine-mkinitcpio-hook linux-aurora m1n1-aurora mesa-aurora omarchy-aurora-firmware omarchy-hyprland-titlebars omarchy-mac omarchy-mac-boot speakerguardd-v2 uboot-aurora vulkan-aurora "
ok "names the image pinned that are not installed any more are dropped (omarchy, omarchy-settings)" "$(grep -c -x -E 'omarchy|omarchy-settings|libfprint-aurora' "$(k "$r")/holds.list")" 0
ok "pacman.conf: one block, written by k114s-holds, verified" "$(grep -c '^# >>> K114s holds' "$r/etc/pacman.conf") $(grep -c 'written by /usr/local/lib/omarchy-k114s/k114s-holds' "$r/etc/pacman.conf") $(K114S_ROOT=$r bash "$(k "$r")/k114s-holds" check; status)" "1 1 0"
ok "settings: release.conf with automatic release on, and the channel this install follows" "$(grep -c -x -E 'AUTO_RELEASE=yes|AUTO_RELEASE_BOOT=yes|AUTO_STAGE2_SWITCH=no' "$r/etc/omarchy-k114s/release.conf") $(cat "$r/etc/omarchy-k114s/channel")" "3 edge"
ok "units and the cleanup drop-in are installed" "$(ls "$r/etc/systemd/system" | tr '\n' ' ')$(ls "$r/etc/systemd/system/linux-modules-cleanup.service.d")" "k114s-boot-success.service k114s-boot-success.timer k114s-holds.path k114s-holds.service linux-modules-cleanup.service.d k114s-keep.conf"
ok "units are enabled now, not at some later step" "$(cat "$r/systemctl.log" | tr '\n' '|')" "daemon-reload|enable --now k114s-holds.path k114s-boot-success.timer|"
ok "user hooks: the loud pre-refresh hook replaces r2c's one-liner; post-update is added" "$(grep -c 'FAIL LOUDLY' "$r/userhome/.config/omarchy/hooks/pre-refresh-pacman.d/k114s-holds") $(test -x "$r/userhome/.config/omarchy/hooks/post-update.d/k114s-release-check"; status)" "1 0"
ok "the running boot chain is recorded as proven during install" "$(awk '$1 == "uki" { print $2 }' "$r/var/lib/omarchy-k114s/release/known-good")" "EFI/Linux/omarchy_linux-aurora-k114s.efi"
set_dir=$(ls -d "$r"/var/lib/omarchy-k114s/recovery/*-install 2>/dev/null)
ok "a recovery set of every held and protected package is written during install" "$(ls "$set_dir/packages" | grep -c 'pkg.tar.zst$') $(cd "$set_dir" && sha256sum --quiet -c SHA256SUMS >/dev/null 2>&1; status)" "18 0"
ok "what r2c installed for the boot is untouched" "$(cat "$r/usr/local/lib/omarchy-j714s/update-boot-ctxr" | grep -c omarchy-k114s/update-boot-ctxr) $(cat "$r/etc/omarchy-mac-boot/owner-boot-chain") $(cat "$(k "$r")/k114s.dtb")" "1 K114s owner boot chain DTB"
ok "no boot file on the ESP was changed" "$(cat "$r/boot/efi/m1n1/boot-ctxr.bin") $(sed -n 's/^default_entry: //p' "$r/boot/efi/limine.conf") $(ls "$r/boot/efi/EFI/Linux" | wc -l | tr -d ' ')" "STAGE2 1 1"
out=$(inst "$r"); ok "a second install is refused" "$? $(echo "$out" | grep -c 'already installed')" "1 1"

# --- refresh: new scripts, same state ----------------------------------------------------------------
sed -i 's/^AUTO_RELEASE=.*/AUTO_RELEASE=no/' "$r/etc/omarchy-k114s/release.conf"; echo "mesa-aurora 1:27-1 20261201T000000Z" > "$(k "$r")/released.list"
echo "# tampered" >> "$(k "$r")/k114s-guard"; held=$(sum "$(k "$r")/holds.list")
out=$(inst "$r" --refresh); ok "--refresh copies the scripts again" "$? $(cmp -s "$L/k114s-guard" "$(k "$r")/k114s-guard"; status)" "0 0"
ok "--refresh keeps the owner's settings, the hold list and what was released" "$(grep -c -x 'AUTO_RELEASE=no' "$r/etc/omarchy-k114s/release.conf") $(sum "$(k "$r")/holds.list") $(wc -l < "$(k "$r")/released.list" | tr -d ' ')" "1 $held 1"
ok "--refresh re-applies the holds (the released package is not held)" "$(sed -n 's/^IgnorePkg = //p' "$r/etc/pacman.conf" | tr ' ' '\n' | grep -c -x mesa-aurora)" 0
rm "$(k "$r")/released.list"; sed -i 's/^AUTO_RELEASE=.*/AUTO_RELEASE=yes/' "$r/etc/omarchy-k114s/release.conf"

# --- undo: exactly what r2c left ------------------------------------------------------------------------
out=$(inst "$r" --undo); ok "--undo" "$? $(echo "$out" | grep -c 'undone')" "0 1"
ok "undo restores every file r2c left, by content and mode, and removes every file r3 added" "$(snap "$r")" "$before"
ok "undo: r2c's block is back in pacman.conf with r2c's hold list" "$(grep -c 'written by /usr/local/lib/omarchy-k114s/apply-holds' "$r/etc/pacman.conf") $(sed -n 's/^IgnorePkg = //p' "$r/etc/pacman.conf")" "1 $IMAGE_HELD"
ok "undo: units disabled" "$(tail -n 2 "$r/systemctl.log" | head -n 1)" "disable --now k114s-holds.path k114s-boot-success.timer"
ok "undo keeps the recovery set and the saved files" "$(ls -d "$r"/var/lib/omarchy-k114s/recovery/*-install | wc -l | tr -d ' ') $(ls -d "$(k "$r")"/tooling-r3.undone.* | wc -l | tr -d ' ')" "1 1"
out=$(inst "$r" --undo); ok "a second undo has nothing to do" "$? $(echo "$out" | grep -c 'nothing to undo')" "1 1"
out=$(inst "$r"); ok "install again after an undo" "$?" 0
out=$(inst "$r" --undo); ok "and undo again: still exactly r2c" "$(snap "$r")" "$before"

# --- refusals: nothing changed ---------------------------------------------------------------------------
r=$(mk); b=$(snap "$r"); printf 'apple,j714s\0apple,t6050\0' > "$r/dt/compatible"; b=$(snap "$r"); out=$(inst "$r"); ok "not an apple,k114s Mac: refused, nothing changed" "$? $(snap "$r")" "1 $b"
r=$(mk); rmdir "$(k "$r")/persist-r2c" 2>/dev/null || rm -rf "$(k "$r")/persist-r2c"; b=$(snap "$r"); out=$(inst "$r"); ok "r2c's persistence is not applied: refused, nothing changed" "$? $(echo "$out" | grep -c 'linux-persist.sh first') $(snap "$r")" "1 1 $b"
r=$(mk); printf '# no options\n' > "$r/etc/pacman.conf"; b=$(snap "$r"); out=$(inst "$r"); ok "pacman.conf without [options]: refused, nothing changed" "$? $(snap "$r")" "1 $b"
r=$(mk); b=$(snap "$r"); F=$BASE/partial; rm -rf "$F"; cp -r "$L" "$F"; rm "$F/k114s-release"; out=$(FROM=$F inst "$r"); ok "a file missing beside the installer: refused, nothing changed" "$? $(echo "$out" | grep -c 'k114s-release is missing') $(snap "$r")" "1 1 $b"
F=$BASE/broken; rm -rf "$F"; cp -r "$L" "$F"; echo 'if then fi (' >> "$F/k114s-guard"; out=$(FROM=$F inst "$r"); ok "a script that does not parse: refused, nothing changed" "$? $(snap "$r")" "1 $b"
F=$BASE/summed; rm -rf "$F"; cp -r "$L" "$F"; (cd "$F" && sha256sum k114s-* > SHA256SUMS); echo "# changed in transit" >> "$F/k114s-holds"
out=$(FROM=$F inst "$r"); ok "files that do not match the bundle's SHA256SUMS: refused, nothing changed" "$? $(echo "$out" | grep -c 'do not match SHA256SUMS') $(snap "$r")" "1 1 $b"
out=$(inst "$r" --bogus); ok "unknown argument" "$?" 1
out=$(inst "$r" --refresh); ok "--refresh without an install: refused" "$? $(snap "$r")" "1 $b"
if [ "$(id -u)" != 0 ]; then out=$(env -u K114S_ROOT bash "$L/k114s-tooling-install" 2>&1); ok "not root on a real system: refused" "$? $(echo "$out" | grep -c 'run with sudo')" "1 1"; fi

# --- variations ----------------------------------------------------------------------------------------------
r=$(mk); out=$(inst "$r" --no-recovery-set); ok "--no-recovery-set installs without archiving" "$? $(ls "$r/var/lib/omarchy-k114s/recovery" 2>/dev/null | wc -l | tr -d ' ')" "0 0"
r=$(mk); out=$(USER_HOME= inst "$r" --no-recovery-set); ok "no invoking user: installs, and says the user hooks are missing" "$? $(echo "$out" | grep -c 'the two Omarchy user hooks were not installed')" "0 1"
r=$(mk); rm "$r/stub-id"; out=$(inst "$r" --no-recovery-set); ok "booted image unknown: installs the guards anyway, and says what is left to do" "$? $(echo "$out" | grep -c 'was not recorded as proven') $(ls "$r/etc/pacman.d/hooks" | wc -l | tr -d ' ')" "0 1 3"
r=$(mk); mkdir -p "$r/etc/omarchy-k114s"; printf 'AUTO_RELEASE=no\n' > "$r/etc/omarchy-k114s/release.conf"; out=$(inst "$r" --no-recovery-set)
ok "an existing release.conf is the owner's and is kept" "$(cat "$r/etc/omarchy-k114s/release.conf")" "AUTO_RELEASE=no"
out=$(inst "$r" --undo); ok "undo leaves a release.conf it did not create" "$(cat "$r/etc/omarchy-k114s/release.conf")" "AUTO_RELEASE=no"
r=$(mk); inst "$r" --no-recovery-set >/dev/null; mkdir -p "$r/var/lib/omarchy-k114s/release"; echo "kind uki" > "$r/var/lib/omarchy-k114s/release/trial"
out=$(inst "$r" --undo); ok "undo is refused while a boot-chain trial is in progress" "$? $(echo "$out" | grep -c 'trial is in progress') $(ls "$r/etc/pacman.d/hooks" | wc -l | tr -d ' ')" "1 1 3"
# the Mac as found on 2026-11-14: the lead's own pieces beside r2c's (a standing GPU Stage 2 trial, its
# re-arm unit, trial reports, the Omarchy script patches). The installer works around them and its undo leaves them.
lead() { local r=$1 k; k=$(lib "$r"); mkdir -p "$r/etc/omarchy-k114s" "$k/omarchy-patches"
  for f in stage2-rearm trial-boot-report trial-default-revert gpu-desktop-restart gpu-desktop-revert omarchy-patches-apply omarchy-patches-lib.sh omarchy-patches/0001.patch; do echo "lead's $f" > "$k/$f"; done
  echo "lead's hook" > "$r/etc/pacman.d/hooks/03-k114s-omarchy-patches.hook"; echo "lead's unit" > "$r/etc/systemd/system/k114s-stage2-rearm.service"
  echo GPU-STAGE2 > "$r/boot/efi/m1n1/boot-ctxr-r3-gpu.bin"; printf 'spent\nm1n1/boot-ctxr-r3-gpu.bin\n' > "$r/boot/efi/aura-try"
  printf 'm1n1/boot-ctxr-r3-gpu.bin\n%s\n' "$(sum "$r/boot/efi/m1n1/boot-ctxr-r3-gpu.bin")" > "$r/etc/omarchy-k114s/stage2-trial"; }
leadsum() { (cd "$1" && sha256sum usr/local/lib/omarchy-k114s/{stage2-rearm,trial-boot-report,trial-default-revert,gpu-desktop-restart,gpu-desktop-revert,omarchy-patches-apply,omarchy-patches-lib.sh,omarchy-patches/0001.patch} \
  etc/pacman.d/hooks/03-k114s-omarchy-patches.hook etc/systemd/system/k114s-stage2-rearm.service boot/efi/m1n1/boot-ctxr-r3-gpu.bin boot/efi/aura-try etc/omarchy-k114s/stage2-trial | sha256sum | cut -c1-16); }
r=$(mk); lead "$r"; before=$(snap "$r"); lb=$(leadsum "$r"); out=$(AURA=m1n1/boot-ctxr-r3-gpu.bin inst "$r" --no-recovery-set)
ok "install beside the lead's standing Stage 2 trial and patches" "$? $(leadsum "$r")" "0 $lb"
ok "the proven chain is what booted: the trial image, with the configured file as the fallback" \
  "$(awk '$1 == "stage2" || $1 == "configured_stage2_sha256" { print $2 }' "$r/var/lib/omarchy-k114s/release/known-good" | tr '\n' ' ')" "m1n1/boot-ctxr-r3-gpu.bin $(sum "$r/boot/efi/m1n1/boot-ctxr.bin") "
out=$(AURA=m1n1/boot-ctxr-r3-gpu.bin inst "$r" --refresh); ok "refresh leaves the lead's pieces" "$? $(leadsum "$r")" "0 $lb"
out=$(inst "$r" --undo); ok "undo leaves the lead's pieces and restores r2c exactly" "$? $(leadsum "$r") $(snap "$r")" "0 $lb $before"
# a failure part-way: the message, and the undo
if [ "$(id -u)" != 0 ]; then
  r=$(mk); b=$(snap "$r"); chmod 555 "$r/etc/systemd/system"; out=$(inst "$r" --no-recovery-set); ok "a failure part-way stops with the undo hint" "$? $(echo "$out" | grep -c 'stopped part-way')" "1 1"
  chmod 755 "$r/etc/systemd/system"; out=$(inst "$r" --undo); ok "undo after a part-way stop restores r2c exactly" "$? $(snap "$r")" "0 $b"
fi

finish "r3 install tests"
