#!/bin/bash
# Tests of k114s-release, k114s-boot-success and k114s-modules-cleanup in a fake root: the
# refusals and the bookkeeping that need no package transaction. (The transactions themselves,
# the trial, retire, abandon and the Stage 2 switch run under a real pacman in test-r3-pacman.sh.)
#   usage: test-r3-release.sh [LINUX_DIR]
set -u
. "$(dirname "$0")/r3-lib.sh" "${1:-}"
have flock iconv python3 || { echo "r3 release tests: SKIPPED (flock, iconv and python3 are needed)"; exit 0; }
status() { echo $?; }
MB=1048576
KOLD=7.3.0-17.v272-4-ARCH
banner() { echo "Linux version $1 (test@build) #1 SMP PREEMPT"; }
stub() { printf '\6\0\0\0' > "$1/stub-id"; printf '/%s' "$(printf '%s' "/$2" | tr / '\\')" | iconv -f ascii -t utf-16le >> "$1/stub-id"; }
mk() { # a fake root as bundle r2c left the ESP: repair image first and default, the standard image under /+Omarchy
  local r; r=$(mkroot)
  kernel_image "$r/boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi" "$KOLD" "CONFIG_IKCONFIG=y" K114S-R1
  kernel_image "$r/boot/efi/EFI/Linux/omarchy_linux-aurora.efi" "$KOLD" "CONFIG_IKCONFIG=y"
  echo STAGE2 > "$r/boot/efi/m1n1/boot-ctxr.bin"; echo BOOTBIN > "$r/boot/efi/m1n1/boot.bin"
  cat > "$r/boot/efi/limine.conf" <<'CONF'
timeout: 5
default_entry: 1
quiet: no

### K114s repair (added from macOS; remove this block to undo)
/Omarchy K114s repair r1 (trackpad fix B)
  comment: K114s repair kernel
  protocol: efi
  path: boot():/EFI/Linux/omarchy_linux-aurora-k114s.efi
  cmdline: root=/dev/mapper/root rw quiet

/+Omarchy
  comment: Omarchy
  //linux-aurora
    comment: Kernel version: 7.3.0-17.v272-4-ARCH
    protocol: efi
    path: boot():/EFI/Linux/omarchy_linux-aurora.efi
    cmdline: root=/dev/mapper/root rw quiet
  //Snapshots
    comment: none yet
CONF
  mkdir -p "$r/etc/default" "$r/sys/class/net/wlan0" "$r/proc/bus/input"; echo 'CUSTOM_UKI_NAME="omarchy"' > "$r/etc/default/limine"
  printf 'N: Name="Apple MTP keyboard"\n\nN: Name="Apple MTP multi-touch"\n' > "$r/proc/bus/input/devices"
  stub "$r" EFI/Linux/omarchy_linux-aurora-k114s.efi
  K114S_ROOT=$r bash "$(lib "$r")/k114s-holds" apply >/dev/null
  echo "$r"
}
run() { # run ROOT TOOL ARG...: a tool in the fake root, booted from the image in ROOT/stub-id
  local r=$1 tool=$2; shift 2
  env K114S_ROOT="$r" K114S_EFI_STUB_ID="$r/stub-id" K114S_UNAME_R="${UNAME_R:-$KOLD}" K114S_PROC_VERSION="$(banner "${UNAME_R:-$KOLD}")" \
    K114S_ESP_FREE="${ESP_FREE:-$((300 * MB))}" K114S_ESP_DT="${ESP_DT:-$r/none}" K114S_ESP_PARTUUID="${ESP_UUID:-}" K114S_BOOT_ID="${BOOT_ID:-aaaa0001}" \
    K114S_DESKTOP="${DESKTOP:-yes}" K114S_SYS="$r/sys" K114S_PROC="$r/proc" K114S_BOOT_WAIT=0 K114S_BOOT_POLL=0 K114S_PACMAN="${PACMAN_STUB:-pacman}" \
    bash ${TRACE:+-x} "$(lib "$r")/$tool" "$@" 2>&1
}
known() { awk -v k="$2" '$1 == k { print $2 }' "$1/var/lib/omarchy-k114s/release/known-good" 2>/dev/null; }
notes() { cat "$1/var/lib/omarchy-k114s/notify.log" 2>/dev/null; }

# --- the proven chain ---------------------------------------------------------------------------
r=$(mk); out=$(run "$r" k114s-release mark-known-good); ok "mark-known-good records the running chain" "$?" 0
ok "known-good: image, its hash, Stage 2 hash, kernel release" "$(known "$r" uki) $(known "$r" uki_sha256) $(known "$r" stage2_sha256) $(known "$r" kernel_release)" \
  "EFI/Linux/omarchy_linux-aurora-k114s.efi $(sum "$r/boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi") $(sum "$r/boot/efi/m1n1/boot-ctxr.bin") $KOLD"
out=$(run "$r" k114s-release status); ok "status: intact and running; holds in place; no trial" "$(echo "$out" | grep -c -E 'intact and running|the holds are in place|trial:     none')" 3
ok "status: the EFI partition, the default entry by title" "$(echo "$out" | grep -c -E 'ESP:       314 MB free|default entry 1: Omarchy K114s repair r1')" 2
r=$(mk); rm "$r/stub-id"; out=$(run "$r" k114s-release mark-known-good); ok "no way to tell the booted image: nothing recorded" "$? $(test -e "$r/var/lib/omarchy-k114s/release/known-good"; status)" "1 1"
r=$(mk); out=$(UNAME_R=7.9.9-1-ARCH run "$r" k114s-release mark-known-good); ok "the image named by the firmware is not the running kernel: refused" "$? $(echo "$out" | grep -c 'is not the kernel that is running')" "1 1"
r=$(mk); printf '%s\0' 6f2a1c3e-0b5d-4e7a-9c11-2d3e4f5a6b7c > "$r/espdt"
out=$(ESP_DT=$r/espdt ESP_UUID=11111111-2222-3333-4444-555555555555 run "$r" k114s-release mark-known-good); ok "another ESP is mounted at /boot/efi: refused" "$? $(echo "$out" | grep -c 'not the ESP this boot came from')" "1 1"
out=$(ESP_DT=$r/espdt ESP_UUID=6F2A1C3E-0B5D-4E7A-9C11-2D3E4F5A6B7C run "$r" k114s-release mark-known-good); ok "the booted ESP: recorded" "$?" 0
if [ "$(id -u)" != 0 ]; then
  r=$(mk); out=$(env -u K114S_ROOT bash "$(lib "$r")/k114s-release" auto 2>&1); ok "not root on a real system: refuses before doing anything" "$? $(echo "$out" | grep -c 'run with sudo')" "1 1"
fi
r=$(mk); out=$(run "$r" k114s-release frobnicate); ok "unknown command" "$?" 1

# --- a boot-chain release waits unless the proven chain is recorded, intact and running --------------
if have pacman repo-add fakeroot vercmp bsdtar zstd; then
  P=$BASE/pkgs; mkdir -p "$P"; t=$(mktemp -d "$BASE/tree.XXXXXX")
  kernel_tree "$t" 7.4.4-1-ARCH k114s-full "$GOOD_CONFIG" "clamping Report Size"; good=$(mkpkg "$t" linux-aurora 7.4.4.aurora18-1 "$P"); mkrepo edge "$good"
  sync_db() { mkdir -p "$1/var/lib/pacman/sync"; cp "$REPO/edge/os/omarchy.db.tar.gz" "$1/var/lib/pacman/sync/omarchy.db"; }   # what "omarchy update" leaves
  waits() { echo "$out" | grep -c "$1"; }
  packages_before() { ls "$1/var/lib/pacman/local" | sha256sum | cut -c1-16; }
  r=$(mk); sync_db "$r"; b=$(packages_before "$r"); out=$(run "$r" k114s-release auto)
  ok "fixed kernel, but no proven chain recorded: waits" "$(waits 'boot-chain release waits: no proven boot chain is recorded yet') $(packages_before "$r")" "1 $b"
  ok "it still left the holds alone and wrote no rollback set" "$(K114S_ROOT=$r bash "$(lib "$r")/k114s-holds" show | grep -c -x linux-aurora) $(ls "$r/var/lib/omarchy-k114s/rollback" | wc -l | tr -d ' ')" "1 0"
  ok "the wait is notified" "$(notes "$r" | grep -c 'no proven boot chain is recorded yet')" 1
  r=$(mk); sync_db "$r"; run "$r" k114s-release mark-known-good >/dev/null; echo CHANGED > "$r/boot/efi/m1n1/boot-ctxr.bin"; out=$(run "$r" k114s-release auto)
  ok "Stage 2 is not the file that was proven: waits" "$(waits 'is not the Stage 2 that was recorded as proven')" 1
  r=$(mk); sync_db "$r"; run "$r" k114s-release mark-known-good >/dev/null; echo x >> "$r/boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi"; out=$(run "$r" k114s-release auto)
  ok "the proven image changed on the ESP: waits" "$(waits 'is not the file that was recorded')" 1
  r=$(mk); sync_db "$r"; run "$r" k114s-release mark-known-good >/dev/null; stub "$r" EFI/Linux/omarchy_linux-aurora.efi; out=$(run "$r" k114s-release auto)
  ok "this boot came from another image than the proven one: waits" "$(waits 'this boot did not come from the proven boot image')" 1
  r=$(mk); run "$r" k114s-release mark-known-good >/dev/null; out=$(run "$r" k114s-release auto)
  ok "the check passed a build pacman's own lists do not offer yet: waits for the next update" "$(waits "pacman's own lists offer nothing")" 1
  r=$(mk); sync_db "$r"; run "$r" k114s-release mark-known-good >/dev/null; out=$(ESP_FREE=$((5 * MB)) run "$r" k114s-release auto)
  ok "no room on the ESP: waits, with the sum" "$(waits 'waits for room on the ESP: linux-aurora needs')" 1
  r=$(mk); sync_db "$r"; run "$r" k114s-release mark-known-good >/dev/null; sed -i 's/^AUTO_RELEASE_BOOT=.*/AUTO_RELEASE_BOOT=no/' "$r/etc/omarchy-k114s/release.conf"; out=$(run "$r" k114s-release auto)
  ok "AUTO_RELEASE_BOOT=no: reports the kernel, stages nothing" "$(waits 'stage it with: sudo k114s-release release linux-aurora')" 1
  r=$(mk); rm -rf "$REPO/edge"; out=$(run "$r" k114s-release auto); ok "channel unreachable: nothing released, said so, exit 0" "$? $(waits 'the release check could not run')" "0 1"
  mkrepo edge "$good"; r=$(mk); out=$(run "$r" k114s-release release vulkan-aurora); ok "release of a named package that is not fixed: says why" "$(waits 'vulkan-aurora is not released: absent')" 1
fi

# --- retire: only what can be taken out safely ---------------------------------------------------------
trial() { # trial ROOT: a proven uki trial of the standard image by hand, old = repair image; two recorded boots
  local r=$1 st=$1/var/lib/omarchy-k114s/release d=$1/var/lib/omarchy-k114s/rollback/t1
  run "$r" k114s-release mark-known-good >/dev/null
  mkdir -p "$d/esp/EFI/Linux" "$st/boots"; cp "$r/boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi" "$d/esp/EFI/Linux/"
  printf 'id t1\nkind uki\npackages linux-aurora\nuki EFI/Linux/omarchy_linux-aurora.efi\nuki_sha256 %s\nstage2_sha256 %s\nold_release %s\nrollback %s\nstarted 20260101T000000Z\nboot_id aaaa0001\nproven 20260102T000000Z\n' \
    "$(sum "$r/boot/efi/EFI/Linux/omarchy_linux-aurora.efi")" "$(sum "$r/boot/efi/m1n1/boot-ctxr.bin")" "$KOLD" "$d" > "$st/trial"
  for n in 2 3; do printf 'time 2026010%sT000000Z\nboot_id aaaa000%s\nuki EFI/Linux/omarchy_linux-aurora.efi\nuki_sha256 %s\nstage2_sha256 %s\nresult ok\n' "$n" "$n" \
    "$(sum "$r/boot/efi/EFI/Linux/omarchy_linux-aurora.efi")" "$(sum "$r/boot/efi/m1n1/boot-ctxr.bin")" > "$st/boots/2026010${n}T000000Z-aaaa000$n"; done
  echo "$KOLD" > "$r/etc/omarchy-k114s/keep-modules"; stub "$r" EFI/Linux/omarchy_linux-aurora.efi
}
r=$(mk); trial "$r"; out=$(BOOT_ID=aaaa0003 run "$r" k114s-release auto); ok "retire: the old image leaves the ESP" "$? $(test -e "$r/boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi"; status)" "0 1"
ok "retire: its block and marker are out of the menu; every other line is as it was" "$(grep -c -E 'K114s repair|aurora-k114s' "$r/boot/efi/limine.conf") $(grep -c -E '^/\+Omarchy$|^  //linux-aurora$|^  //Snapshots$|^timeout: 5$|^quiet: no$' "$r/boot/efi/limine.conf")" "0 5"
ok "retire: the default is the new image's entry, counted as Limine counts (directories too)" "$(sed -n 's/^default_entry: //p' "$r/boot/efi/limine.conf")" 2
ok "retire: the menu as it was is kept beside the rollback set" "$(grep -c '^/Omarchy K114s repair' "$r/var/lib/omarchy-k114s/rollback/t1/limine.conf.before-retire")" 1
ok "retire: known-good is the new chain; freeze and keep list are gone" "$(known "$r" uki) $(test -e "$r/etc/omarchy-k114s/stage2-frozen"; status) $(wc -w < "$r/etc/omarchy-k114s/keep-modules" | tr -d ' ')" "EFI/Linux/omarchy_linux-aurora.efi 1 0"
r=$(mk); trial "$r"; out=$(BOOT_ID=aaaa0003 UNAME_R=$KOLD run "$r" k114s-release auto >/dev/null; stub "$r" EFI/Linux/omarchy_linux-aurora-k114s.efi)
r=$(mk); trial "$r"; stub "$r" EFI/Linux/omarchy_linux-aurora-k114s.efi; out=$(BOOT_ID=aaaa0003 run "$r" k114s-release auto)
ok "retire waits while the old entry is the one running" "$(test -e "$r/boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi"; status) $(echo "$out" | grep -c 'retire waits: the boot chain on trial is not the one running')" "0 1"
r=$(mk); trial "$r"; out=$(BOOT_ID=aaaa0001 run "$r" k114s-release auto)
ok "retire waits in the boot that staged the trial, whatever the records say" "$(test -e "$r/boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi"; status)" 0
r=$(mk); trial "$r"; rm "$r/var/lib/omarchy-k114s/rollback/t1/esp/EFI/Linux/omarchy_linux-aurora-k114s.efi"; out=$(BOOT_ID=aaaa0003 run "$r" k114s-release auto)
ok "retire waits when the rollback set has lost the old image" "$(test -e "$r/boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi"; status) $(echo "$out" | grep -c 'no longer holds the old boot image')" "0 1"
r=$(mk); trial "$r"; echo x >> "$r/boot/efi/EFI/Linux/omarchy_linux-aurora.efi"; out=$(BOOT_ID=aaaa0003 run "$r" k114s-release auto)
ok "retire waits when the image on trial is no longer the file that booted" "$(test -e "$r/boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi"; status)" 0
r=$(mk); trial "$r"; rm "$r"/var/lib/omarchy-k114s/release/boots/*3; out=$(BOOT_ID=aaaa0003 run "$r" k114s-release auto)
ok "one recorded boot is not enough for the automatic retire (RETIRE_AFTER_BOOTS=2)" "$(test -e "$r/boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi"; status) $(echo "$out" | grep -c 'retired after 2')" "0 1"
out=$(BOOT_ID=aaaa0003 run "$r" k114s-release retire); ok "the owner can retire after one: k114s-release retire" "$? $(test -e "$r/boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi"; status)" "0 1"
r=$(mk); trial "$r"; sed -i 's/^AUTO_RETIRE=.*/AUTO_RETIRE=no/' "$r/etc/omarchy-k114s/release.conf"; out=$(BOOT_ID=aaaa0003 run "$r" k114s-release auto)
ok "AUTO_RETIRE=no: nothing is retired by itself" "$(test -e "$r/boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi"; status)" 0
# an old image whose menu entry is not a top-level block of its own: the menu is left alone
r=$(mk); trial "$r"; python3 -I - "$r/boot/efi/limine.conf" <<'PY'
import sys
t = open(sys.argv[1]).read()
block = t[t.index("### K114s repair"):t.index("/+Omarchy")]
t = t.replace(block, "") + "  //Old repair kernel\n    protocol: efi\n    path: boot():/EFI/Linux/omarchy_linux-aurora-k114s.efi\n"
open(sys.argv[1], "w").write(t)
PY
b=$(sum "$r/boot/efi/limine.conf"); out=$(TRACE=${R3_TRACE:-} BOOT_ID=aaaa0003 run "$r" k114s-release auto)
ok "an entry this tool cannot take out as a block: menu and image left as they are" "$(sum "$r/boot/efi/limine.conf") $(test -e "$r/boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi"; status) $(echo "$out" | grep -c 'not a block this tool can take out safely')" "$b 0 1"
ok "and no half-written menu is left on the ESP" "$(ls "$r/boot/efi" | grep -c 'k114s-new')" 0
r=$(mk); out=$(run "$r" k114s-release retire); ok "retire without a trial" "$? $(echo "$out" | grep -c 'no trial is in progress')" "1 1"
out=$(run "$r" k114s-release abandon); ok "abandon without a trial" "$?" 1

# --- forget-image: room on the ESP without touching what is proven or running -----------------------------------
r=$(mk); run "$r" k114s-release mark-known-good >/dev/null; std=$(sum "$r/boot/efi/EFI/Linux/omarchy_linux-aurora.efi")
out=$(run "$r" k114s-release forget-image EFI/Linux/omarchy_linux-aurora-k114s.efi); ok "forget-image refuses the proven image" "$? $(test -s "$r/boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi"; status)" "1 0"
out=$(run "$r" k114s-release forget-image ../../etc/passwd); ok "forget-image takes boot images only" "$?" 1
out=$(run "$r" k114s-release forget-image EFI/Linux/nothing.efi); ok "forget-image: not on the ESP" "$?" 1
b=$(sum "$r/boot/efi/limine.conf"); out=$(run "$r" k114s-release forget-image EFI/Linux/omarchy_linux-aurora.efi)
ok "forget-image leaves an image whose menu entry it cannot take out as a block (a sub-entry)" "$? $(sum "$r/boot/efi/limine.conf") $(sum "$r/boot/efi/EFI/Linux/omarchy_linux-aurora.efi")" "1 $b $std"
# the other way round: the standard image is proven and running, the repair image is the spare one
r=$(mk); stub "$r" EFI/Linux/omarchy_linux-aurora.efi; run "$r" k114s-release mark-known-good >/dev/null; spare=$(sum "$r/boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi")
out=$(run "$r" k114s-release forget-image EFI/Linux/omarchy_linux-aurora-k114s.efi); ok "forget-image takes the spare repair image off the ESP" "$? $(test -e "$r/boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi"; status)" "0 1"
ok "its menu block is gone and the default is the proven image's entry" "$(grep -c -E 'K114s repair|aurora-k114s' "$r/boot/efi/limine.conf") $(sed -n 's/^default_entry: //p' "$r/boot/efi/limine.conf")" "0 2"
ok "a verified copy and the menu as it was are kept" "$(sum "$r"/var/lib/omarchy-k114s/rollback/*-forget/esp/EFI/Linux/omarchy_linux-aurora-k114s.efi) $(cd "$r"/var/lib/omarchy-k114s/rollback/*-forget && sha256sum --quiet -c SHA256SUMS >/dev/null 2>&1; status) $(grep -c 'K114s repair' "$r"/var/lib/omarchy-k114s/rollback/*-forget/esp/limine.conf)" "$spare 0 3"
out=$(run "$r" k114s-release status); ok "the proven chain is still intact and running afterwards" "$(echo "$out" | grep -c 'intact and running')" 1
r=$(mk); stub "$r" EFI/Linux/omarchy_linux-aurora.efi; out=$(run "$r" k114s-release forget-image EFI/Linux/omarchy_linux-aurora-k114s.efi); ok "forget-image needs a recorded proven chain first" "$? $(test -s "$r/boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi"; status)" "1 0"

# --- Stage 2 switch: refusals ------------------------------------------------------------------------------
r=$(mk); run "$r" k114s-release mark-known-good >/dev/null; s2=$(sum "$r/boot/efi/m1n1/boot-ctxr.bin")
truncate -s $((4 * MB)) "$r/boot/efi/m1n1/boot-ctxr.bin"; run "$r" k114s-release mark-known-good >/dev/null; s2=$(sum "$r/boot/efi/m1n1/boot-ctxr.bin")
out=$(ESP_FREE=$((19 * MB)) run "$r" k114s-release stage2); ok "Stage 2 switch: not enough room for new file, temp and kept copy (3x4+8): refused" "$? $(sum "$r/boot/efi/m1n1/boot-ctxr.bin")" "1 $s2"
out=$(run "$r" k114s-release stage2 --dtb elsewhere); ok "Stage 2 switch: unknown tree choice refused" "$?" 1
out=$(run "$r" k114s-release stage2); ok "Stage 2 switch: the hook refuses (no boot.bin to cut from): the proven file stays, frozen" "$? $(sum "$r/boot/efi/m1n1/boot-ctxr.bin") $(test -s "$r/etc/omarchy-k114s/stage2-frozen"; status)" "1 $s2 0"
ok "Stage 2 switch refused: no trial was started" "$(test -e "$r/var/lib/omarchy-k114s/release/trial"; status)" 1
r=$(mk); out=$(run "$r" k114s-release stage2); ok "Stage 2 switch without a proven chain: refused" "$? $(echo "$out" | grep -c 'no proven boot chain is recorded yet')" "1 1"

# --- the Stage 2 hook's freeze (the rest of the hook is r2c's, tested with the image's own files there) -----
r=$(mkroot); mkdir -p "$r/usr/lib/asahi-boot"; printf 'M1N1-STAGE2-PREFIX' > "$r/usr/lib/asahi-boot/m1n1.bin"
python3 -I "$T/mkfdt.py" "$r/j.dtb" j714s; python3 -I "$T/mkfdt.py" "$r/packaged.dtb" k114s-bare; python3 -I "$T/mkfdt.py" "$r/boot/efi/k114s-repair/k114s.dtb" k114s-full
{ cat "$r/usr/lib/asahi-boot/m1n1.bin" "$r/j.dtb" "$r/packaged.dtb"; echo U-BOOT | gzip -c -n; } > "$r/boot/efi/m1n1/boot.bin"
s2hook() { OMARCHY_ROOT=$r K114S_ESP_DT=$r/none sh "$(lib "$r")/update-boot-ctxr" 2>&1; }
out=$(s2hook); ok "Stage 2 hook: builds loader + the pinned K114s tree + U-Boot" "$? $(grep -c -a 'apple,centauri-platform-id' "$r/boot/efi/m1n1/boot-ctxr.bin") $(grep -c -a 'apple,j714s' "$r/boot/efi/m1n1/boot-ctxr.bin")" "0 1 0"
pinned=$(sum "$r/boot/efi/m1n1/boot-ctxr.bin"); echo "$pinned" > "$r/etc/omarchy-k114s/stage2-frozen"
printf 'NEW-M1N1-PREFIX' > "$r/usr/lib/asahi-boot/m1n1.bin"; { cat "$r/usr/lib/asahi-boot/m1n1.bin" "$r/j.dtb" "$r/packaged.dtb"; echo U-BOOT | gzip -c -n; } > "$r/boot/efi/m1n1/boot.bin"
out=$(s2hook); ok "frozen: a new loader does not reach Stage 2, and the hook succeeds (the transaction goes on)" "$? $(sum "$r/boot/efi/m1n1/boot-ctxr.bin") $(echo "$out" | grep -c 'Stage 2 is frozen')" "0 $pinned 1"
: > "$(lib "$r")/use-packaged-dtb"; out=$(s2hook); ok "frozen: not even the tree choice changes it" "$(sum "$r/boot/efi/m1n1/boot-ctxr.bin")" "$pinned"
rm "$r/etc/omarchy-k114s/stage2-frozen"; out=$(s2hook); ok "unfrozen with the packaged tree: the new loader and the kernel package's own K114s tree" "$? $(grep -c -a 'NEW-M1N1-PREFIX' "$r/boot/efi/m1n1/boot-ctxr.bin") $(grep -c -a 'apple,centauri-platform-id' "$r/boot/efi/m1n1/boot-ctxr.bin") $(grep -c -a 'apple,k114s' "$r/boot/efi/m1n1/boot-ctxr.bin")" "0 1 0 1"
rm "$(lib "$r")/use-packaged-dtb" "$r/boot/efi/m1n1/boot-ctxr.bin"; echo x > "$r/etc/omarchy-k114s/stage2-frozen"
out=$(s2hook); ok "a freeze never leaves the Mac WITHOUT a Stage 2: a missing file is built" "$? $(test -s "$r/boot/efi/m1n1/boot-ctxr.bin"; status)" "0 0"

# --- boot-success ------------------------------------------------------------------------------------------------
rec() { cat "$1"/var/lib/omarchy-k114s/release/boots/*-"$2" 2>/dev/null; }
r=$(mk); out=$(run "$r" k114s-boot-success); ok "boot-success: desktop, Wi-Fi interface and trackpad present -> ok" "$? $(echo "$out" | grep -c 'boot recorded as ok')" "0 1"
ok "the record names what booted" "$(rec "$r" aaaa0001 | grep -c -E "^(uki EFI/Linux/omarchy_linux-aurora-k114s.efi|uki_sha256 $(sum "$r/boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi")|stage2_sha256 $(sum "$r/boot/efi/m1n1/boot-ctxr.bin")|kernel_release $KOLD|boot_id aaaa0001|result ok)$")" 6
out=$(run "$r" k114s-boot-success); ok "a second run in the same boot adds nothing" "$(echo "$out" | grep -c 'already recorded as ok') $(ls "$r/var/lib/omarchy-k114s/release/boots" | wc -l | tr -d ' ')" "1 1"
out=$(BOOT_ID=aaaa0002 run "$r" k114s-boot-success); ok "the next boot gets its own record" "$(ls "$r/var/lib/omarchy-k114s/release/boots" | wc -l | tr -d ' ')" 2
r=$(mk); out=$(DESKTOP=no run "$r" k114s-boot-success); ok "no desktop session -> incomplete" "$(rec "$r" aaaa0001 | grep -c -E '^(desktop no|result incomplete)$')" 2
ok "incomplete is notified" "$(notes "$r" | grep -c 'K114s boot check incomplete: desktop no, wlan0 yes, trackpad yes')" 1
out=$(DESKTOP=no run "$r" k114s-boot-success); ok "the timer's later runs in the same boot do not notify again" "$(notes "$r" | grep -c 'K114s boot check incomplete') $(ls "$r/var/lib/omarchy-k114s/release/boots" | wc -l | tr -d ' ')" "1 1"
out=$(run "$r" k114s-boot-success); ok "the same boot later, desktop up: the record becomes ok (one record per boot)" "$(rec "$r" aaaa0001 | grep -c '^result ok$') $(ls "$r/var/lib/omarchy-k114s/release/boots" | wc -l | tr -d ' ')" "1 1"
r=$(mk); rmdir "$r/sys/class/net/wlan0"; out=$(run "$r" k114s-boot-success); ok "no Wi-Fi interface -> incomplete" "$(rec "$r" aaaa0001 | grep -c -E '^(network no \(wlan0\)|result incomplete)$')" 2
r=$(mk); printf 'N: Name="Apple MTP keyboard"\n' > "$r/proc/bus/input/devices"; out=$(run "$r" k114s-boot-success); ok "no trackpad device -> incomplete" "$(rec "$r" aaaa0001 | grep -c -E '^(trackpad no .*|result incomplete)$')" 2
r=$(mk); mkdir "$r/sys/class/net/wlp1s0"; rmdir "$r/sys/class/net/wlan0"; sed -i 's/^BOOT_NET_INTERFACE=.*/BOOT_NET_INTERFACE=wlp1s0/' "$r/etc/omarchy-k114s/release.conf"
out=$(run "$r" k114s-boot-success); ok "the interface and device names come from release.conf" "$(rec "$r" aaaa0001 | grep -c -E '^(network yes \(wlp1s0\)|result ok)$')" 2
# the per-boot self-checks
r=$(mk); template "$r" edge; out=$(run "$r" k114s-boot-success); ok "every boot puts missing holds back into pacman.conf" "$(K114S_ROOT=$r bash "$(lib "$r")/k114s-holds" check; status)" 0
r=$(mk); rm "$r/etc/pacman.d/hooks/00-k114s-guard-remove.hook"; out=$(run "$r" k114s-boot-success)
ok "a missing guard hook is a critical notification" "$(notes "$r" | grep -c 'notify\[critical\]: K114s update guards need attention: 00-k114s-guard-remove.hook is missing')" 1
r=$(mk); mkdir -p "$r/usr/share/libalpm/hooks"; printf '[Trigger]\nType = Path\nOperation = Upgrade\nTarget = usr/lib/newboot/*\n\n[Action]\nWhen = PostTransaction\nExec = /usr/bin/mkinitcpio -P\n' > "$r/usr/share/libalpm/hooks/90-new.hook"
out=$(run "$r" k114s-boot-success); ok "a boot hook the space guard does not know is noticed at boot" "$(notes "$r" | grep -c 'does not know every boot-file hook') $(test -s "$r/var/lib/omarchy-k114s/esp-triggers-stale"; status)" "1 0"
r=$(mk); sed -i 's/^NOTIFY=.*/NOTIFY=no/' "$r/etc/omarchy-k114s/release.conf"; out=$(DESKTOP=no run "$r" k114s-boot-success); ok "NOTIFY=no silences notifications, not the record" "$(notes "$r" | wc -l | tr -d ' ') $(rec "$r" aaaa0001 | grep -c '^result incomplete$')" "0 1"

# --- the module cleanup with a keep list ----------------------------------------------------------------------
if have rsync; then
  mkmods() { local r; r=$(mkroot); for k in 7.3.0-17.v272-4-ARCH 7.4.4-1-ARCH 7.1.0-1-ARCH; do mkdir -p "$r/usr/lib/modules/$k/kernel"; echo "$k" > "$r/usr/lib/modules/$k/kernel/m.ko"; done
    printf '#!/bin/sh\n# pacman stand-in: only the 7.4.4 tree belongs to a package\ncase "$2" in */7.4.4-1-ARCH) exit 0 ;; esac\nexit 1\n' > "$r/pacman-stub"; chmod +x "$r/pacman-stub"; echo "$r"; }
  r=$(mkmods); out=$(UNAME_R=7.4.4-1-ARCH PACMAN_STUB=$r/pacman-stub run "$r" k114s-modules-cleanup)
  ok "cleanup without a keep list is the stock cleanup: unowned trees of other kernels move to .old" "$(ls "$r/usr/lib/modules" | tr '\n' ' ') $(ls "$r/usr/lib/modules/.old" | tr '\n' ' ')" "7.4.4-1-ARCH  7.1.0-1-ARCH 7.3.0-17.v272-4-ARCH "
  r=$(mkmods); echo 7.3.0-17.v272-4-ARCH > "$r/etc/omarchy-k114s/keep-modules"; out=$(UNAME_R=7.4.4-1-ARCH PACMAN_STUB=$r/pacman-stub run "$r" k114s-modules-cleanup)
  ok "with the keep list the proven kernel's modules stay; other leftovers still go" "$(ls "$r/usr/lib/modules" | tr '\n' ' ') $(ls "$r/usr/lib/modules/.old" | tr '\n' ' ')" "7.3.0-17.v272-4-ARCH 7.4.4-1-ARCH  7.1.0-1-ARCH "
  ok "kept modules are intact" "$(cat "$r/usr/lib/modules/7.3.0-17.v272-4-ARCH/kernel/m.ko")" 7.3.0-17.v272-4-ARCH
  r=$(mkmods); out=$(UNAME_R=7.3.0-17.v272-4-ARCH PACMAN_STUB=$r/pacman-stub run "$r" k114s-modules-cleanup)
  ok "the running kernel's unowned modules always stay" "$(ls "$r/usr/lib/modules" | tr '\n' ' ')" "7.3.0-17.v272-4-ARCH 7.4.4-1-ARCH "
fi
ok "drop-in replaces the stock command with ours" "$(grep -c -E '^ExecStart=$|^ExecStart=/usr/local/lib/omarchy-k114s/k114s-modules-cleanup$' "$L/linux-modules-cleanup-k114s-keep.conf")" 2
ok "boot-success timer: a minute after boot, then every ten minutes until the boot is recorded ok" "$(grep -c -E '^OnBootSec=60$|^OnUnitInactiveSec=600$|^WantedBy=timers.target$' "$L/k114s-boot-success.timer")" 3
ok "holds path unit watches pacman.conf" "$(grep -c -E '^PathChanged=/etc/pacman.conf$|^Unit=k114s-holds.service$' "$L/k114s-holds.path")" 2
ok "no unit, hook or script of the tooling can restart the machine" "$(for f in "$L"/k114s-* "$L"/hooks/* "$L"/*.hook "$L"/*.service "$L"/*.timer "$L"/*.path; do grep -v '^[[:space:]]*#' "$f" | grep -q -E '\b(reboot|shutdown|kexec|poweroff|halt)\b' && echo "$f"; done | wc -l | tr -d ' ')" 0

finish "r3 release tests"
