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
export MKROOT_KERNEL=1     # a fake root has the proven kernel's files (the tree-drivers check compares with them)
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
  mkdir -p "$r/etc/default" "$r/sys/class/net/wlan0" "$r/sys/bus/hid/drivers/magicmouse/0019:05AC:0361.0002" "$r/proc/bus/input"; echo 'CUSTOM_UKI_NAME="omarchy"' > "$r/etc/default/limine"
  printf 'N: Name="Apple MTP keyboard"\n\nN: Name="Apple MTP multi-touch"\n' > "$r/proc/bus/input/devices"
  stub "$r" EFI/Linux/omarchy_linux-aurora-k114s.efi
  K114S_ROOT=$r bash "$(lib "$r")/k114s-holds" apply >/dev/null
  echo "$r"
}
run() { # run ROOT TOOL ARG...: a tool in the fake root, booted from the image in ROOT/stub-id
  local r=$1 tool=$2; shift 2
  env K114S_ROOT="$r" K114S_EFI_STUB_ID="$r/stub-id" K114S_UNAME_R="${UNAME_R:-$KOLD}" K114S_PROC_VERSION="$(banner "${UNAME_R:-$KOLD}")" \
    K114S_ESP_FREE="${ESP_FREE:-$((300 * MB))}" K114S_ESP_DT="${ESP_DT:-$r/none}" K114S_ESP_PARTUUID="${ESP_UUID:-}" K114S_BOOT_ID="${BOOT_ID:-aaaa0001}" \
    K114S_DESKTOP="${DESKTOP:-yes}" K114S_SYS="$r/sys" K114S_PROC="$r/proc" K114S_BOOT_WAIT=0 K114S_BOOT_POLL=0 K114S_PACMAN="${PACMAN_STUB:-pacman}" K114S_SIGCHECK="${SIGCHECK_STUB:-true}" \
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
  ok "the configured Stage 2 is not the file that was proven: waits" "$(waits 'is not the file recorded with the proven chain')" 1
  r=$(mk); sync_db "$r"; run "$r" k114s-release mark-known-good >/dev/null; : > "$r/etc/omarchy-k114s/trial-default"; out=$(run "$r" k114s-release auto)
  ok "a boot-menu trial of someone else is under way: the boot chain waits" "$(waits 'boot-chain release waits: a boot-menu trial of someone else is under way') $(test -e "$r/var/lib/omarchy-k114s/release/trial"; status)" "1 1"
  r=$(mk); sync_db "$r"; run "$r" k114s-release mark-known-good >/dev/null; echo x >> "$r/boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi"; out=$(run "$r" k114s-release auto)
  ok "the proven image changed on the ESP: waits" "$(waits 'is not the file that was recorded')" 1
  r=$(mk); sync_db "$r"; run "$r" k114s-release mark-known-good >/dev/null; stub "$r" EFI/Linux/omarchy_linux-aurora.efi; out=$(run "$r" k114s-release auto)
  ok "this boot came from another image than the proven one: waits" "$(waits 'this boot did not come from the proven boot image')" 1
  r=$(mk); run "$r" k114s-release mark-known-good >/dev/null; out=$(run "$r" k114s-release auto)
  ok "the check passed a build pacman's own lists do not offer yet: waits for the next update" "$(waits "pacman's own lists offer nothing")" 1
  r=$(mk); sync_db "$r"; run "$r" k114s-release mark-known-good >/dev/null; out=$(ESP_FREE=$((5 * MB)) run "$r" k114s-release auto)
  ok "no room on the ESP: waits, with the sum" "$(waits 'waits for room on the ESP: linux-aurora needs')" 1
  need_of() { echo "$out" | sed -n 's/.*linux-aurora needs \([0-9]*\) MB.*/\1/p'; }
  n_plain=$(need_of)
  r=$(mk); sync_db "$r"; run "$r" k114s-release mark-known-good >/dev/null; touch "$r/etc/limine-snapper-sync.conf"; out=$(ESP_FREE=$((5 * MB)) run "$r" k114s-release auto)
  ok "limine-snapper-sync's config adds nothing to what a boot-chain release needs (it limits itself)" "$(need_of) $(waits snapshot) $([ -n "$n_plain" ] && echo sum)" "$n_plain 0 sum"
  # this Mac's real sizes: 168 MB free after the standard image is forgotten, a kernel of 54,086,144 bytes, an initramfs of 25,023,354
  r=$(mk); sync_db "$r"; run "$r" k114s-release mark-known-good >/dev/null; touch "$r/etc/limine-snapper-sync.conf"
  truncate -s 25023354 "$r/boot/initramfs-linux-aurora.img"; truncate -s 10040000 "$r/boot/efi/m1n1/boot.bin"; truncate -s 4440000 "$r/boot/efi/m1n1/boot-ctxr.bin"; out=$(ESP_FREE=166000000 run "$r" k114s-release auto)
  ok "real sizes with the snapper config: 166 MB is enough for the release (it was refused as needing 195 MB)" "$(waits 'waits for room')" 0
  r=$(mk); sync_db "$r"; run "$r" k114s-release mark-known-good >/dev/null; sed -i 's/^AUTO_RELEASE_BOOT=.*/AUTO_RELEASE_BOOT=no/' "$r/etc/omarchy-k114s/release.conf"; out=$(run "$r" k114s-release auto)
  ok "AUTO_RELEASE_BOOT=no: reports the kernel, stages nothing" "$(waits 'stage it with: sudo k114s-release release linux-aurora')" 1
  r=$(mk); rm -rf "$REPO/edge"; out=$(run "$r" k114s-release auto); ok "channel unreachable: nothing released, said so, exit 0" "$? $(waits 'the release check could not run')" "0 1"
  mkrepo edge "$good"; r=$(mk); out=$(run "$r" k114s-release release vulkan-aurora); ok "release of a named package that is not fixed: says why" "$(waits 'vulkan-aurora is not released: absent')" 1
fi

# --- preflight: a held package's dependency that stops the channel's upgrade is reported before the update --------------------
cat > "$BASE/pacman-stub" <<'STUB'
#!/bin/bash
# stands for pacman: the lists refresh works; the dry-run upgrade fails the way a new LLVM soname against the held Mesa does
# (STUB_MODE: mesa, the default; ignore: only "ignoring package upgrade" warnings and an unrelated error; lib32: a dependency of lib32-mesa-aurora; kernel: of linux-aurora)
[ -z "${STUB_LOG:-}" ] || echo "LC_ALL=${LC_ALL:-} $*" >> "$STUB_LOG"
# STUB_REAL=1: everything but the dry-run upgrade goes to the real pacman (the release check and the release itself)
[ -z "${STUB_REAL:-}" ] || case " $* " in *" -Sup "*) ;; *) exec pacman "$@" ;; esac
case " $* " in
  *" -Syy "*) exit 0 ;;
  *" -Sup "*) [ -z "${STUB_OK:-}" ] || exit 0
    case ${STUB_MODE:-mesa} in
      ignore) echo "warning: linux-aurora: ignoring package upgrade (1 => 2)"; echo "warning: mesa-aurora: ignoring package upgrade (1 => 2)"; echo "error: failed to synchronize all databases (unable to lock database)"; exit 1 ;;
      lib32) echo "error: failed to prepare transaction (could not satisfy dependencies)"; echo ":: installing llvm-libs (23.1-2) breaks dependency 'libLLVM.so=23.1-64' required by lib32-mesa-aurora"; exit 1 ;;
      kernel) echo "error: failed to prepare transaction (could not satisfy dependencies)"; echo ":: unable to satisfy dependency 'limine>=12' required by linux-aurora"; exit 1 ;;
      conflict) echo "error: failed to prepare transaction (could not satisfy dependencies)"; echo ":: hyprland-0.58-1 and hyprland-m5-0.57.2-2 are in conflict. Remove hyprland-m5? [y/N]"; echo "error: unresolvable package conflicts detected"; exit 1 ;;
      rival) echo "hyprland 0.58-1"; echo "omarchy 2-1"; exit 0 ;;
      lib32conflict) echo ":: hyprland-0.58-1 and hyprland-m5-extra-0.57.2-2 are in conflict"; exit 1 ;;
      missing) echo "error: failed to prepare transaction (could not satisfy dependencies)"; echo ":: unable to satisfy dependency 'linux-aurora>=8.0' required by omarchy-mac-extra"; exit 1 ;;
    esac
    echo "error: failed to prepare transaction (could not satisfy dependencies)"
    echo ":: installing llvm-libs (23.1-2) breaks dependency 'libLLVM.so=23.1-64' required by mesa-aurora"; exit 1 ;;
esac
exit 0
STUB
chmod 755 "$BASE/pacman-stub"
r=$(mk); out=$(PACMAN_STUB=$BASE/pacman-stub run "$r" k114s-release preflight)
ok "preflight: names the held package whose dependency stops the upgrade, and says what to run" "$? $(echo "$out" | grep -c 'would FAIL on a dependency or conflict of held package(s): mesa-aurora') $(echo "$out" | grep -c 'mesa-aurora: the channel.s build is not fit yet')" "0 1 1"
ok "preflight: and notifies" "$(notes "$r" | grep -c 'would fail on held mesa-aurora')" 1
out=$(STUB_OK=1 PACMAN_STUB=$BASE/pacman-stub run "$r" k114s-release preflight); ok "preflight: an upgrade that works is not reported" "$? $(echo "$out" | grep -c 'no held package stands in the way')" "0 1"
ok "preflight installs nothing and writes no trial or rollback set" "$(test -e "$r/var/lib/omarchy-k114s/release/trial"; status) $(ls "$r/var/lib/omarchy-k114s/rollback" | wc -l | tr -d ' ')" "1 0"
rm -f "$BASE/stub.log"; STUB_LOG=$BASE/stub.log PACMAN_STUB=$BASE/pacman-stub run "$r" k114s-release preflight >/dev/null
ok "preflight: its --dbpath (the check's private lists) comes after the one of the fake root's pacman arguments, so it is the one pacman uses" "$(grep -- '-Sup' "$BASE/stub.log" | grep -o -e '--dbpath [^ ]*' | tail -n 1 | sed 's#.*/var/lib/omarchy-k114s/#K/#')" "K/check/db"
out=$(STUB_MODE=ignore PACMAN_STUB=$BASE/pacman-stub run "$r" k114s-release preflight)
ok "preflight: 'ignoring package upgrade' warnings do not blame a held package" "$? $(echo "$out" | grep -c 'not because of a held package') $(echo "$out" | grep -c 'would FAIL')" "0 1 0"
out=$(STUB_MODE=missing PACMAN_STUB=$BASE/pacman-stub run "$r" k114s-release preflight)
ok "preflight: a held package that is the MISSING dependency (too old for a non-held package) is blamed" "$? $(echo "$out" | grep -c 'would FAIL on a dependency or conflict of held package(s): linux-aurora')" "0 1"
out=$(STUB_MODE=lib32 PACMAN_STUB=$BASE/pacman-stub run "$r" k114s-release preflight)
ok "preflight: a dependency of lib32-mesa-aurora does not blame mesa-aurora (whole names only)" "$? $(echo "$out" | grep -c 'not because of a held package') $(echo "$out" | grep -c 'would FAIL')" "0 1 0"
out=$(STUB_MODE=conflict PACMAN_STUB=$BASE/pacman-stub run "$r" k114s-release preflight)
ok "preflight: a failing dry run that names a held package in a conflict line (version suffix and all) blames it" "$? $(echo "$out" | grep -c 'would FAIL on a dependency or conflict of held package(s): hyprland-m5')" "0 1"
out=$(STUB_MODE=lib32conflict PACMAN_STUB=$BASE/pacman-stub run "$r" k114s-release preflight)
ok "preflight: a conflict with a package that merely starts with a held name blames nobody" "$? $(echo "$out" | grep -c 'not because of a held package')" "0 1"
out=$(STUB_MODE=rival PACMAN_STUB=$BASE/pacman-stub run "$r" k114s-release preflight)
ok "preflight: a dry run that succeeds (-Sup runs no conflict step) but lists a rival of held hyprland-m5 is not an all-clear" "$? $(echo "$out" | grep -c 'would FAIL on a dependency or conflict of held package(s): hyprland-m5') $(echo "$out" | grep -c 'no held package stands in the way')" "0 1 0"
rm -f "$BASE/stub.log"; LC_ALL=de_DE.UTF-8 STUB_LOG=$BASE/stub.log PACMAN_STUB=$BASE/pacman-stub run "$r" k114s-release preflight >/dev/null
ok "preflight: pacman's -Sup runs with LC_ALL=C whatever the owner's locale (the parser reads English messages)" "$(grep -c '^LC_ALL=C .*-Sup' "$BASE/stub.log")" 1
if have pacman repo-add fakeroot vercmp bsdtar zstd; then
  # a blocking held package whose channel build is fixed is released by the preflight as release.conf allows
  r=$(mk); sync_db "$r"; run "$r" k114s-release mark-known-good >/dev/null; out=$(STUB_REAL=1 STUB_MODE=kernel PACMAN_STUB=$BASE/pacman-stub run "$r" k114s-release preflight)
  ok "preflight: a fixed blocking kernel (and limine, the held package it needs a newer build of) goes through the release step (a rollback set is written and the transaction is tried; a fake root cannot install: it says so and names the manual command)" "$? $(echo "$out" | grep -c 'would FAIL on a dependency or conflict of held package(s): limine linux-aurora') $(ls "$r/var/lib/omarchy-k114s/rollback" | grep -c -- '-boot$') $(echo "$out" | grep -c 'linux-aurora: the transaction did not go through') $(echo "$out" | grep -c 'if linux-aurora is not at the build that passed the check yet, run: sudo k114s-release release linux-aurora')" "0 1 1 1 1"
  r=$(mk); sync_db "$r"; run "$r" k114s-release mark-known-good >/dev/null; sed -i 's/^AUTO_RELEASE_BOOT=.*/AUTO_RELEASE_BOOT=no/' "$r/etc/omarchy-k114s/release.conf"; out=$(STUB_REAL=1 STUB_MODE=kernel PACMAN_STUB=$BASE/pacman-stub run "$r" k114s-release preflight)
  ok "preflight: AUTO_RELEASE_BOOT=no: reports the exact command, stages nothing" "$(echo "$out" | grep -c 'stage it with: sudo k114s-release release linux-aurora') $(test -e "$r/var/lib/omarchy-k114s/release/trial"; status)" "1 1"
fi
ok "the adopt hint for a held package names k114s-release adopt, not a pacman -U the guard stops" "$(grep -c 'adopted from .*Rollback: sudo k114s-release adopt' "$L/k114s-release")" 1

# --- the boot partition's lock (limine-snapper-sync and limine-entry-tool take it around their writes) -------------------
r=$(mk); run "$r" k114s-release mark-known-good >/dev/null; kernel_image "$r/boot/efi/EFI/Linux/omarchy_linux-old.efi" "$KOLD" "CONFIG_IKCONFIG=y"; mkdir -p "$r/run/lock"
(flock "$r/run/lock/boot-partition.lock" sleep 6) & sleep 1
out=$(K114S_LOCK_WAIT=1 run "$r" k114s-release forget-image EFI/Linux/omarchy_linux-old.efi)
ok "an edit of the ESP waits for the boot partition lock, then stops without changing anything when it is not given" "$? $(echo "$out" | grep -c 'holds the boot partition lock') $(test -e "$r/boot/efi/EFI/Linux/omarchy_linux-old.efi"; status) $(sum "$r/boot/efi/limine.conf")" "1 1 0 $(sum "$r/boot/efi/limine.conf")"
wait
out=$(K114S_LOCK_WAIT=1 run "$r" k114s-release forget-image EFI/Linux/omarchy_linux-old.efi)
ok "with the lock free it goes ahead" "$? $(test -e "$r/boot/efi/EFI/Linux/omarchy_linux-old.efi"; status)" "0 1"

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
out=$(run "$r" k114s-release stage2); ok "Stage 2 trial: the hook refuses (no boot.bin to cut from): the proven file stays, no candidate, nothing armed" "$? $(sum "$r/boot/efi/m1n1/boot-ctxr.bin") $(test -e "$r/boot/efi/m1n1/boot-ctxr-try.bin"; status) $(test -e "$r/boot/efi/aura-try"; status)" "1 $s2 1 1"
ok "Stage 2 switch refused: no trial was started" "$(test -e "$r/var/lib/omarchy-k114s/release/trial"; status)" 1
r=$(mk); out=$(run "$r" k114s-release stage2); ok "Stage 2 switch without a proven chain: refused" "$? $(echo "$out" | grep -c 'no proven boot chain is recorded yet')" "1 1"

# --- aura-try: the loader's one-boot Stage 2 trial (a standing one is the lead's; ours is the candidate) -----------
GPU=m1n1/boot-ctxr-r3-gpu.bin
rec() { cat "$1"/var/lib/omarchy-k114s/release/boots/*-"$2" 2>/dev/null; }
aura() { # aura ROOT: the Mac as found on 2026-11-14: a standing trial of $GPU, re-armed at shutdown, this boot came through it
  echo GPU-STAGE2 > "$1/boot/efi/$GPU"; printf 'spent\n%s\n' "$GPU" > "$1/boot/efi/aura-try"
  printf '%s\n%s\n' "$GPU" "$(sum "$1/boot/efi/$GPU")" > "$1/etc/omarchy-k114s/stage2-trial"
}
r=$(mk); aura "$r"; out=$(K114S_AURA_TRIAL=$GPU run "$r" k114s-release mark-known-good)
ok "mark-known-good under a standing trial: what booted is the trial image, the configured file is recorded beside it" \
  "$? $(known "$r" stage2) $(known "$r" stage2_sha256) $(known "$r" configured_stage2_sha256) $(known "$r" trial)" "0 $GPU $(sum "$r/boot/efi/$GPU") $(sum "$r/boot/efi/m1n1/boot-ctxr.bin") $GPU"
out=$(K114S_AURA_TRIAL=$GPU run "$r" k114s-release status); ok "status: intact and running, the booted Stage 2 and the other trial are shown" \
  "$(echo "$out" | grep -c -E "intact and running|^booted:    Stage 2 $GPU \(a one-boot trial\)|^elsewhere: a standing Stage 2 trial of $GPU|^aura-try:  spent $GPU")" 4
out=$(K114S_AURA_TRIAL= run "$r" k114s-release status); ok "a start through the configured file is not the proven chain while the trial image is" "$(echo "$out" | grep -c "did not come through the proven Stage 2 ($GPU); it came through m1n1/boot-ctxr.bin")" 1
echo CHANGED > "$r/boot/efi/m1n1/boot-ctxr.bin"; out=$(K114S_AURA_TRIAL=$GPU run "$r" k114s-release status)
ok "the configured file (the watchdog's fallback) changed: not intact" "$(echo "$out" | grep -c 'the configured Stage 2, what the loader falls back to')" 1
r=$(mk); out=$(K114S_AURA_TRIAL=m1n1/boot-ctxr-gone.bin run "$r" k114s-release mark-known-good); ok "a trial image that is not on the ESP: nothing recorded" "$? $(test -e "$r/var/lib/omarchy-k114s/release/known-good"; status)" "1 1"
r=$(mk); out=$(K114S_AURA_TRIAL=../../etc/x run "$r" k114s-release mark-known-good); ok "a trial path that leaves the ESP is not followed" "$? $(echo "$out" | grep -c 'not on the ESP as a file')" "1 1"
r=$(mk); aura "$r"; K114S_AURA_TRIAL=$GPU run "$r" k114s-release mark-known-good >/dev/null; b=$(sum "$r/boot/efi/aura-try")
out=$(K114S_AURA_TRIAL=$GPU run "$r" k114s-release stage2); ok "Stage 2 trial refused while a standing trial is under way; nothing written" \
  "$? $(echo "$out" | grep -c 'another trial of the boot chain is under way: a standing Stage 2 trial') $(sum "$r/boot/efi/aura-try") $(test -e "$r/boot/efi/m1n1/boot-ctxr-try.bin"; status) $(test -e "$r/var/lib/omarchy-k114s/release/trial"; status)" "1 1 $b 1 1"
r=$(mk); run "$r" k114s-release mark-known-good >/dev/null; echo X > "$r/boot/efi/m1n1/boot-ctxr-x.bin"; printf 'armed\nm1n1/boot-ctxr-x.bin\n' > "$r/boot/efi/aura-try"
out=$(run "$r" k114s-release stage2); ok "Stage 2 trial refused while another file is armed" "$? $(echo "$out" | grep -c 'an armed one-boot Stage 2 trial of m1n1/boot-ctxr-x.bin') $(sed -n 2p "$r/boot/efi/aura-try")" "1 1 m1n1/boot-ctxr-x.bin"
r=$(mk); run "$r" k114s-release mark-known-good >/dev/null; : > "$r/etc/omarchy-k114s/trial-default"
out=$(run "$r" k114s-release stage2); ok "Stage 2 trial refused during a boot-menu trial" "$? $(echo "$out" | grep -c 'a one-boot boot-menu trial')" "1 1"
# the re-arm at boot: a trial of ours, kind stage2, this start came through the candidate
s2trial() { # s2trial ROOT: a Stage 2 trial of k114s-release by hand: candidate on the ESP, marker spent by the loader
  local r=$1 st=$1/var/lib/omarchy-k114s/release
  run "$r" k114s-release mark-known-good >/dev/null
  echo CANDIDATE > "$r/boot/efi/m1n1/boot-ctxr-try.bin"; printf 'spent\nm1n1/boot-ctxr-try.bin\n' > "$r/boot/efi/aura-try"
  mkdir -p "$r/var/lib/omarchy-k114s/rollback/s1/esp/m1n1"; cp "$r/boot/efi/m1n1/boot-ctxr.bin" "$r/var/lib/omarchy-k114s/rollback/s1/esp/m1n1/"
  printf 'id s1\nkind stage2\npackages m1n1-aurora uboot-aurora\ndtb packaged\nuki %s\nuki_sha256 %s\nstage2 m1n1/boot-ctxr-try.bin\nstage2_sha256 %s\nconfigured_stage2_sha256 %s\nrollback %s\nstarted 20260101T000000Z\nboot_id aaaa0000\n' \
    "$(known "$r" uki)" "$(known "$r" uki_sha256)" "$(sum "$r/boot/efi/m1n1/boot-ctxr-try.bin")" "$(sum "$r/boot/efi/m1n1/boot-ctxr.bin")" "$r/var/lib/omarchy-k114s/rollback/s1" > "$st/trial"
  echo x > "$r/etc/omarchy-k114s/stage2-frozen"
}
TRY=m1n1/boot-ctxr-try.bin
r=$(mk); s2trial "$r"; out=$(K114S_AURA_TRIAL=$TRY run "$r" k114s-boot-success)
ok "a good start through our candidate: recorded with its hash, and armed again for the next start" \
  "$(rec "$r" aaaa0001 | grep -c -E "^(stage2 $TRY|stage2_sha256 $(sum "$r/boot/efi/$TRY")|trial $TRY|result ok)$") $(head -n 1 "$r/boot/efi/aura-try") $(echo "$out" | grep -c 'armed again')" "4 armed 1"
r=$(mk); s2trial "$r"; out=$(DESKTOP=no K114S_AURA_TRIAL=$TRY run "$r" k114s-boot-success); ok "an incomplete start through it: not armed again (the next start is the proven file)" "$(head -n 1 "$r/boot/efi/aura-try")" spent
r=$(mk); s2trial "$r"; out=$(K114S_AURA_TRIAL= run "$r" k114s-boot-success); ok "a start that fell back to the configured file: not armed again" "$(head -n 1 "$r/boot/efi/aura-try")" spent
r=$(mk); s2trial "$r"; echo OTHER > "$r/boot/efi/$TRY"; out=$(K114S_AURA_TRIAL=$TRY run "$r" k114s-boot-success); ok "the candidate is not the file on trial: not armed" "$(head -n 1 "$r/boot/efi/aura-try")" spent
r=$(mk); s2trial "$r"; aura "$r"; out=$(K114S_AURA_TRIAL=$TRY run "$r" k114s-boot-success); ok "another trial appeared: ours is not armed over it" "$(cat "$r/boot/efi/aura-try" | tr '\n' ' ')" "spent $GPU "
r=$(mk); s2trial "$r"; out=$(BOOT_ID=aaaa0002 run "$r" k114s-release auto); ok "auto after a start that did not come through it: says so, changes nothing proven" \
  "$(echo "$out" | grep -c 'this start did not come through m1n1/boot-ctxr-try.bin') $(test -e "$r/boot/efi/$TRY"; status)" "1 0"
out=$(BOOT_ID=aaaa0002 run "$r" k114s-release stage2 --rearm); ok "stage2 --rearm arms the candidate again" "$? $(cat "$r/boot/efi/aura-try" | tr '\n' ' ')" "0 armed $TRY "
out=$(BOOT_ID=aaaa0002 run "$r" k114s-release auto); ok "auto while it is armed: restart when convenient" "$(echo "$out" | grep -c 'is armed for the next start')" 1
# promotion: two good starts through the candidate, on a later run
s2boots() { local r=$1 n; for n in 2 3; do printf 'time 2026010%sT000000Z\nboot_id aaaa000%s\nuki %s\nuki_sha256 %s\nstage2 %s\nstage2_sha256 %s\ntrial %s\nresult ok\n' "$n" "$n" "$(known "$r" uki)" "$(known "$r" uki_sha256)" "$TRY" "$(sum "$r/boot/efi/$TRY")" "$TRY" \
  > "$r/var/lib/omarchy-k114s/release/boots/2026010${n}T000000Z-aaaa000$n"; done; }
r=$(mk); s2trial "$r"; mkdir -p "$r/var/lib/omarchy-k114s/release/boots"; s2boots "$r"; old=$(sum "$r/boot/efi/m1n1/boot-ctxr.bin"); new=$(sum "$r/boot/efi/$TRY")
out=$(BOOT_ID=aaaa0003 K114S_AURA_TRIAL=$TRY run "$r" k114s-release auto); ok "the run that sees the first records only proves the candidate" "$(grep -c '^proven' "$r/var/lib/omarchy-k114s/release/trial") $(sum "$r/boot/efi/m1n1/boot-ctxr.bin")" "1 $old"
out=$(BOOT_ID=aaaa0003 K114S_AURA_TRIAL= run "$r" k114s-release auto); ok "a later run from a start through the configured file: no switch" "$(sum "$r/boot/efi/m1n1/boot-ctxr.bin") $(echo "$out" | grep -c 'did not come through')" "$old 1"
out=$(BOOT_ID=aaaa0003 K114S_AURA_TRIAL=$TRY ESP_FREE=$((8 * MB)) run "$r" k114s-release auto); ok "no room for the kept copy and a temp file: the switch waits" "$(sum "$r/boot/efi/m1n1/boot-ctxr.bin") $(echo "$out" | grep -c 'switch waits for room')" "$old 1"
: > "$r/etc/omarchy-k114s/trial-default"; out=$(BOOT_ID=aaaa0003 K114S_AURA_TRIAL=$TRY run "$r" k114s-release auto); ok "another trial under way: the switch waits" "$(sum "$r/boot/efi/m1n1/boot-ctxr.bin") $(echo "$out" | grep -c 'the Stage 2 switch waits: a one-boot boot-menu trial')" "$old 1"
rm "$r/etc/omarchy-k114s/trial-default"
out=$(BOOT_ID=aaaa0003 K114S_AURA_TRIAL=$TRY run "$r" k114s-release auto); ok "a later run, from a start through the candidate, after two good starts: it becomes the configured file" "$? $(sum "$r/boot/efi/m1n1/boot-ctxr.bin")" "0 $new"
ok "the old configured file is kept on the ESP with its hash, and in the rollback set" "$(sum "$r/boot/efi/k114s-repair/known-good/boot-ctxr.bin") $(cut -c1-64 "$r/boot/efi/k114s-repair/known-good/boot-ctxr.bin.sha256") $(sum "$r/var/lib/omarchy-k114s/rollback/s1/esp/m1n1/boot-ctxr.bin")" "$old $old $old"
ok "proven now: the configured file; the trial is closed, the freeze and the marker are gone, the tree choice is kept" \
  "$(known "$r" stage2) $(known "$r" stage2_sha256) $(known "$r" configured_stage2_sha256) $(test -e "$r/var/lib/omarchy-k114s/release/trial"; status) $(test -e "$r/etc/omarchy-k114s/stage2-frozen"; status) $(test -e "$r/boot/efi/aura-try"; status) $(test -e "$(lib "$r")/use-packaged-dtb"; status)" \
  "m1n1/boot-ctxr.bin $new $new 1 1 1 0"
ok "the candidate file stays while this start runs from it, and the chain is intact" "$(test -e "$r/boot/efi/$TRY"; status) $(K114S_AURA_TRIAL=$TRY run "$r" k114s-release status | grep -c 'intact and running')" "0 1"
rm -rf "$REPO/edge"; out=$(BOOT_ID=aaaa0004 K114S_AURA_TRIAL= run "$r" k114s-release auto); ok "the next start comes through the configured file: the candidate leaves the ESP" "$(test -e "$r/boot/efi/$TRY"; status) $(K114S_AURA_TRIAL= BOOT_ID=aaaa0004 run "$r" k114s-release status | grep -c 'intact and running')" "1 1"
r=$(mk); s2trial "$r"; out=$(BOOT_ID=aaaa0002 run "$r" k114s-release abandon); ok "abandon of a Stage 2 trial: disarmed, candidate gone, configured untouched, frozen" \
  "$? $(test -e "$r/boot/efi/aura-try"; status) $(test -e "$r/boot/efi/$TRY"; status) $(sum "$r/boot/efi/m1n1/boot-ctxr.bin") $(test -s "$r/etc/omarchy-k114s/stage2-frozen"; status)" "0 1 1 $(known "$r" configured_stage2_sha256) 0"
r=$(mk); s2trial "$r"; printf 'armed\nm1n1/boot-ctxr-x.bin\n' > "$r/boot/efi/aura-try"; out=$(BOOT_ID=aaaa0002 run "$r" k114s-release abandon); ok "abandon leaves another's marker alone" "$(sed -n 2p "$r/boot/efi/aura-try")" m1n1/boot-ctxr-x.bin

# the Stage 2 trial started for real (the hook builds the candidate), given up, and the automatic switch
r=$(mk); mkdir -p "$r/usr/lib/asahi-boot"; printf 'M1N1-STAGE2-PREFIX' > "$r/usr/lib/asahi-boot/m1n1.bin"
python3 -I "$T/mkfdt.py" "$r/j.dtb" j714s; python3 -I "$T/mkfdt.py" "$r/packaged.dtb" k114s-bare; python3 -I "$T/mkfdt.py" "$r/boot/efi/k114s-repair/k114s.dtb" k114s-full
{ cat "$r/usr/lib/asahi-boot/m1n1.bin" "$r/j.dtb" "$r/packaged.dtb"; echo U-BOOT | gzip -c -n; } > "$r/boot/efi/m1n1/boot.bin"
run "$r" k114s-release mark-known-good >/dev/null; conf=$(sum "$r/boot/efi/m1n1/boot-ctxr.bin"); echo "$conf" > "$r/etc/omarchy-k114s/stage2-frozen"
out=$(run "$r" k114s-release stage2 --dtb pinned); ok "stage2: the candidate is built beside the configured file and armed" \
  "$? $(sum "$r/boot/efi/m1n1/boot-ctxr.bin") $(grep -c -a 'apple,centauri-platform-id' "$r/boot/efi/$TRY") $(head -n 1 "$r/boot/efi/aura-try") $(awk '$1 == "kind" || $1 == "dtb" { print $2 }' "$r/var/lib/omarchy-k114s/release/trial" | tr '\n' ' ')" "0 $conf 1 armed stage2 pinned "
out=$(run "$r" k114s-release stage2); ok "a second stage2 during the trial: refused" "$? $(echo "$out" | grep -c 'one change at a time')" "1 1"
out=$(run "$r" k114s-release abandon); ok "abandon in the boot that armed it" "$? $(test -e "$r/boot/efi/$TRY"; status) $(test -e "$r/boot/efi/aura-try"; status) $(sum "$r/boot/efi/m1n1/boot-ctxr.bin")" "0 1 1 $conf"
sed -i 's/^AUTO_STAGE2_SWITCH=.*/AUTO_STAGE2_SWITCH=yes/' "$r/etc/omarchy-k114s/release.conf"; rm -rf "$REPO/edge"; out=$(run "$r" k114s-release auto)
ok "AUTO_STAGE2_SWITCH=yes does not try a candidate that was given up" "$(echo "$out" | grep -c 'was given up before') $(test -e "$r/var/lib/omarchy-k114s/release/trial"; status) $(test -e "$r/boot/efi/$TRY"; status)" "1 1 1"
{ cat "$r/usr/lib/asahi-boot/m1n1.bin" "$r/j.dtb" "$r/packaged.dtb"; echo NEW-U-BOOT | gzip -c -n; } > "$r/boot/efi/m1n1/boot.bin"; out=$(run "$r" k114s-release auto)
ok "AUTO_STAGE2_SWITCH=yes: a new candidate is tried by itself, beside the proven file" "$(awk '$1 == "kind" { print $2 }' "$r/var/lib/omarchy-k114s/release/trial") $(head -n 1 "$r/boot/efi/aura-try") $(sum "$r/boot/efi/m1n1/boot-ctxr.bin")" "stage2 armed $conf"
run "$r" k114s-release abandon >/dev/null
K114S_STAGE2_OUT=boot-ctxr-x.bin K114S_STAGE2_DTB=pinned OMARCHY_ROOT=$r sh "$(lib "$r")/update-boot-ctxr" >/dev/null 2>&1; mv "$r/boot/efi/m1n1/boot-ctxr-x.bin" "$r/boot/efi/m1n1/boot-ctxr.bin"
run "$r" k114s-release mark-known-good >/dev/null; echo x > "$r/etc/omarchy-k114s/stage2-frozen"; out=$(run "$r" k114s-release stage2 --dtb pinned)
ok "the packages build the configured file byte for byte: nothing to try, the freeze is lifted" "$? $(echo "$out" | grep -c 'nothing to try, and the freeze is lifted') $(test -e "$r/etc/omarchy-k114s/stage2-frozen"; status) $(test -e "$r/var/lib/omarchy-k114s/release/trial"; status)" "0 1 1 1"

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
rm "$r/etc/omarchy-k114s/stage2-frozen"; : > "$r/etc/omarchy-k114s/stage2-managed"; out=$(s2hook)
ok "managed (the tooling is installed): no freeze file, a new loader, the packaged-tree marker, and the hook still never rewrites boot-ctxr.bin" "$? $(sum "$r/boot/efi/m1n1/boot-ctxr.bin") $(echo "$out" | grep -c 'Stage 2 is managed by k114s-release')" "0 $pinned 1"
out=$(K114S_STAGE2_OUT=boot-ctxr-m.bin K114S_STAGE2_DTB=packaged s2hook); ok "but k114s-release can still build a candidate beside it" "$? $(test -s "$r/boot/efi/m1n1/boot-ctxr-m.bin"; status)" "0 0"
rm -f "$r/boot/efi/m1n1/boot-ctxr-m.bin" "$r/etc/omarchy-k114s/stage2-managed"
rm "$r/etc/omarchy-k114s/stage2-frozen"; out=$(s2hook); ok "unfrozen with the packaged tree: the new loader and the kernel package's own K114s tree" "$? $(grep -c -a 'NEW-M1N1-PREFIX' "$r/boot/efi/m1n1/boot-ctxr.bin") $(grep -c -a 'apple,centauri-platform-id' "$r/boot/efi/m1n1/boot-ctxr.bin") $(grep -c -a 'apple,k114s' "$r/boot/efi/m1n1/boot-ctxr.bin")" "0 1 0 1"
rm "$(lib "$r")/use-packaged-dtb" "$r/boot/efi/m1n1/boot-ctxr.bin"; echo x > "$r/etc/omarchy-k114s/stage2-frozen"
out=$(s2hook); ok "a freeze never leaves the Mac WITHOUT a Stage 2: a missing file is built" "$? $(test -s "$r/boot/efi/m1n1/boot-ctxr.bin"; status)" "0 0"
conf=$(sum "$r/boot/efi/m1n1/boot-ctxr.bin")
out=$(K114S_STAGE2_OUT=boot-ctxr-try.bin K114S_STAGE2_DTB=packaged s2hook); ok "a candidate is built beside it, frozen or not; the configured file is not touched"   "$? $(sum "$r/boot/efi/m1n1/boot-ctxr.bin") $(grep -c -a 'NEW-M1N1-PREFIX' "$r/boot/efi/m1n1/boot-ctxr-try.bin") $(grep -c -a 'apple,centauri-platform-id' "$r/boot/efi/m1n1/boot-ctxr-try.bin")" "0 $conf 1 0"
: > "$(lib "$r")/use-packaged-dtb"; out=$(K114S_STAGE2_OUT=boot-ctxr-try.bin K114S_STAGE2_DTB=pinned s2hook); ok "the tree named for the candidate wins over the marker" "$? $(grep -c -a 'apple,centauri-platform-id' "$r/boot/efi/m1n1/boot-ctxr-try.bin")" "0 1"
for name in boot-ctxr.bin ../boot-ctxr-x.bin other.bin; do out=$(K114S_STAGE2_OUT=$name s2hook); ok "candidate name $name is refused" "$? $(sum "$r/boot/efi/m1n1/boot-ctxr.bin")" "1 $conf"; done
out=$(K114S_STAGE2_DTB=elsewhere s2hook); ok "an unknown tree choice is refused" "$?" 1

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
r=$(mk); rmdir "$r/sys/bus/hid/drivers/magicmouse/0019:05AC:0361.0002"; out=$(run "$r" k114s-boot-success)
ok "the trackpad device is there but no hid-magicmouse is bound to it (the transport registers the name alone) -> incomplete" "$(rec "$r" aaaa0001 | grep -c -E '^(trackpad no .*|result incomplete)$')" 2
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

# --- the signature check itself (the real gpg path, on a throwaway keyring standing in for pacman's) -------------------------
if have gpg; then
  sr=$BASE/sigroot; g=$sr/etc/pacman.d/gnupg; mkdir -p "$g"; chmod 700 "$g"
  G() { gpg --homedir "$g" --batch --no-tty --quiet "$@" 2>/dev/null; }
  G --passphrase '' --quick-gen-key 'K114s test signer <signer@example.invalid>' ed25519 sign never
  G --passphrase '' --quick-gen-key 'K114s stranger <stranger@example.invalid>' ed25519 sign never
  fpr() { G --with-colons --list-keys "$1" | awk -F: '$1 == "fpr" { print $10; exit }'; }
  printf '%s:6:\n' "$(fpr signer@example.invalid)" | G --import-ownertrust     # ultimate, as a pacman master key's signed key ends up
  printf '%s:2:\n' "$(fpr stranger@example.invalid)" | G --import-ownertrust   # in the keyring, trust undefined
  a=$sr/pkg.tar.zst; echo archive > "$a"
  eval "$(sed -n '/^signed_ok() {/,/^}/p' "$L/k114s-release")"
  ROOT=$sr; unset K114S_SIGCHECK K114S_TEST K114S_ROOT
  G --local-user signer@example.invalid --detach-sign -o "$a.sig" "$a"
  ok "signature: a valid signature by a fully trusted key passes" "$(signed_ok "$a"; status)" 0
  rm -f "$a.sig"; ok "signature: a missing .sig is refused" "$(signed_ok "$a"; status)" 1
  : > "$a.sig"; ok "signature: an empty .sig is refused" "$(signed_ok "$a"; status)" 1
  G --local-user stranger@example.invalid --detach-sign -o "$a.sig.new" "$a"; mv -f "$a.sig.new" "$a.sig"
  ok "signature: a valid signature by a key in the keyring that is not trusted is refused (pacman-key --verify would pass it)" "$(signed_ok "$a"; status)" 1
  G --local-user signer@example.invalid --detach-sign -o "$a.sig.new" "$a"; mv -f "$a.sig.new" "$a.sig"; echo changed >> "$a"
  ok "signature: an archive changed after signing is refused" "$(signed_ok "$a"; status)" 1
  sed -i '$d' "$a"; ok "signature: back to the signed bytes, it passes again" "$(signed_ok "$a"; status)" 0
  printf 'disable\nsave\n' | G --command-fd 0 --edit-key "$(fpr signer@example.invalid)"
  ok "signature: a disabled key (as pacman-key --populate leaves a revoked one) is refused" "$(signed_ok "$a"; status)" 1
  K114S_SIGCHECK=true; ok "signature: K114S_SIGCHECK is ignored outside the test sandboxes" "$(signed_ok "$a"; status)" 1
  unset K114S_SIGCHECK; ROOT=
else
  echo "SKIP signature check (no gpg)"
fi

# --- a default_entry written as an entry path (docs/r3a-promotion.md) ---------------------------------------------
# forget-image, and every other put-back of the default, keeps a path a path: an entry the hook adds in front later cannot move it
r=$(mk); stub "$r" EFI/Linux/omarchy_linux-aurora.efi; run "$r" k114s-release mark-known-good >/dev/null
sed -i 's#^default_entry: 1$#default_entry: Omarchy K114s repair r1 (trackpad fix B)#' "$r/boot/efi/limine.conf"
out=$(run "$r" k114s-release forget-image EFI/Linux/omarchy_linux-aurora-k114s.efi)
ok "forget-image with a path default: the default becomes the proven entry's path, not a number" "$? $(sed -n 's/^default_entry: //p' "$r/boot/efi/limine.conf")" "0 Omarchy/linux-aurora"
lt() { bash -c '. "$1/k114s-lib.sh"; shift; "$@"' _ "$L" "$@"; }
c=$BASE/limine-path.conf
printf 'timeout: 5\ndefault_entry: Omarchy/linux-k114s\n/+Omarchy\n  //linux-aurora\n  path: boot():/EFI/Linux/omarchy_linux-aurora.efi\n  //linux-k114s\n  path: boot():/EFI/Linux/omarchy_linux-k114s.efi\n' > "$c"
ok "limine_default prints a path default as written" "$(lt limine_default "$c")" "Omarchy/linux-k114s"
ok "limine_default_index resolves the path as Limine numbers entries (the folder counts)" "$(lt limine_default_index "$c")" 3
ok "limine_path_of gives an entry's path" "$(lt limine_path_of "$c" 2)" "Omarchy/linux-aurora"
lt limine_set_default "$c" 2; ok "limine_set_default keeps the path form" "$(lt limine_default "$c")" "Omarchy/linux-aurora"
ok "limine_set_default refuses a number past the last entry, and changes nothing" "$(lt limine_set_default "$c" 9; status) $(lt limine_default "$c")" "1 Omarchy/linux-aurora"
sed -i 's#^default_entry: .*#default_entry: Omarchy/nothing#' "$c"; ok "limine_default_index: a path that names nothing gives nothing" "$(lt limine_default_index "$c")" ""
sed -i 's#^default_entry: .*#default_entry: 3#' "$c"; ok "limine_default_index: a number is itself" "$(lt limine_default_index "$c")" 3
lt limine_set_default "$c" 2; ok "limine_set_default keeps a numeric default numeric" "$(lt limine_default "$c")" 2
sed -i 's#^default_entry: .*#default_entry: Omarchy/linux-k114s\#1#' "$c"; ok "limine_default_index does not resolve a '#' suffix" "$(lt limine_default_index "$c")" ""
sed -i 's#^default_entry: .*#Default_Entry: Omarchy/linux-k114s#' "$c"
ok "limine_default reads the option name in any case, as Limine and k114s-boot-once do" "$(lt limine_default "$c") $(lt limine_default_index "$c")" "Omarchy/linux-k114s 3"
lt limine_set_default "$c" 2; ok "limine_set_default rewrites a mixed-case default line, keeping the path form" "$(lt limine_default "$c") $(grep -c -i '^default_entry:' "$c")" "Omarchy/linux-aurora 1"

finish "r3 release tests"
