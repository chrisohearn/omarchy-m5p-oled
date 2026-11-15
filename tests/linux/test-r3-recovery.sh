#!/bin/bash
# Tests of k114s-repackage and k114s-recovery-set in a fake root. No real system file is touched.
# (test-r3-pacman.sh installs a repackaged archive with a real pacman.)
#   usage: test-r3-recovery.sh [LINUX_DIR]
set -u
. "$(dirname "$0")/r3-lib.sh" "${1:-}"
status() { echo $?; }
repack() { local r=$1; shift; K114S_ROOT=$r bash "$(lib "$r")/k114s-repackage" "$@" 2>&1; }
recovery() { local r=$1; shift; K114S_ROOT=$r K114S_ESP_FREE=90000000 K114S_PROC_VERSION="Linux version 7.3.0-17.v272-4-ARCH (test)" K114S_EFI_STUB_ID=$r/stub-id bash "$(lib "$r")/k114s-recovery-set" "$@" 2>&1; }
entries() { bsdtar -tf "$1" | sed 's#/$##' | LC_ALL=C sort | tr '\n' ' '; }

# an installed package with a directory, files, a symlink, a backup file and an install scriptlet,
# installed "as packaged" and then partly changed on disk
mkdemo() { # mkdemo ROOT
  local r=$1 tree d
  tree=$(mktemp -d "$BASE/tree.XXXXXX")
  mkdir -p "$tree/usr/lib/demo/sub" "$tree/usr/bin" "$tree/etc"
  echo "packaged kernel" > "$tree/usr/lib/demo/vmlinuz"; echo "module" > "$tree/usr/lib/demo/sub/mod.ko"
  echo "tool" > "$tree/usr/bin/demo-tool"; chmod 755 "$tree/usr/bin/demo-tool"; ln -s demo-tool "$tree/usr/bin/demo-link"
  echo "setting=1" > "$tree/etc/demo.conf"
  d=$r/var/lib/pacman/local/demo-pkg-1.2-3
  dbpkg "$r" demo-pkg 1.2-3 etc/ etc/demo.conf usr/ usr/bin/ usr/bin/demo-link usr/bin/demo-tool usr/lib/ usr/lib/demo/ usr/lib/demo/sub/ usr/lib/demo/sub/mod.ko usr/lib/demo/vmlinuz
  printf '%%BACKUP%%\netc/demo.conf\td41d8cd98f00b204e9800998ecf8427e\n\n' >> "$d/files"
  printf '%%DEPENDS%%\nglibc\nbash>=5\n\n%%PROVIDES%%\ndemo=1.2\n\n%%CONFLICTS%%\ndemo-old\n\n' >> "$d/desc"
  printf 'post_install() {\n  echo demo installed\n}\n' > "$d/install"
  (cd "$tree" && find . -mindepth 1 -printf '%P\n' | LC_ALL=C sort > "$BASE/.demo.list" &&
    LANG=C bsdtar --uid 0 --gid 0 -cnf - --format=mtree --options='!all,use-set,type,uid,gid,mode,time,size,md5,sha256,link' -T "$BASE/.demo.list" | gzip -c -n > "$d/mtree")
  cp -a "$tree/." "$r/"
  # after installation: the repair kernel placed over the packaged one, and files no package owns beside it
  echo "REPAIR KERNEL" > "$r/usr/lib/demo/vmlinuz"
  echo "not mine" > "$r/usr/lib/demo/unowned.txt"; echo "another package's" > "$r/usr/bin/other-tool"; echo "x" > "$r/etc/other.conf"
}

# --- repackage ----------------------------------------------------------------------------------
r=$(mkroot); mkdemo "$r"; out=$BASE/out1; mkdir "$out"
text=$(repack "$r" --out "$out" demo-pkg); ok "repackage writes an archive" "$?" 0
a=$out/demo-pkg-1.2-3-any.pkg.tar.zst
ok "archive named NAME-VERSION-ARCH" "$(test -s "$a"; status)" 0
ok "entries are exactly the metadata and the package's file list" "$(entries "$a")" ".INSTALL .MTREE .PKGINFO etc etc/demo.conf usr usr/bin usr/bin/demo-link usr/bin/demo-tool usr/lib usr/lib/demo usr/lib/demo/sub usr/lib/demo/sub/mod.ko usr/lib/demo/vmlinuz "
ok "a listed directory does not bring its other files (the 2026-11-14 mistake)" "$(bsdtar -tf "$a" | grep -c -E 'unowned|other-tool|other.conf')" 0
ok "metadata comes first" "$(bsdtar -tf "$a" | head -n 3 | tr '\n' ' ')" ".PKGINFO .INSTALL .MTREE "
ok "files are archived as they are NOW" "$(bsdtar -xOf "$a" usr/lib/demo/vmlinuz)" "REPAIR KERNEL"
ok "symlink kept as a symlink" "$(bsdtar -tvf "$a" usr/bin/demo-link | grep -c -- '-> demo-tool')" 1
ok "mode kept" "$(bsdtar -tvf "$a" usr/bin/demo-tool | cut -c1-10)" "-rwxr-xr-x"
ok "owner recorded as root" "$(bsdtar -tvf "$a" usr/bin/demo-tool | awk '{print $3"/"$4}')" "root/root"
info=$(bsdtar -xOf "$a" .PKGINFO)
ok ".PKGINFO: name, version, arch" "$(echo "$info" | grep -c -E '^(pkgname = demo-pkg|pkgver = 1.2-3|arch = any)$')" 3
ok ".PKGINFO: depends, provides, conflicts, backup" "$(echo "$info" | grep -c -E '^(depend = glibc|depend = bash>=5|provides = demo=1.2|conflict = demo-old|backup = etc/demo.conf)$')" 5
ok ".INSTALL is the database's scriptlet" "$(bsdtar -xOf "$a" .INSTALL | grep -c post_install)" 1
ok ".MTREE describes what was archived" "$(bsdtar -xOf "$a" .MTREE | gzip -dc | grep -c -E '^\./usr/lib/demo/vmlinuz .*sha256digest='"$(sum "$r/usr/lib/demo/vmlinuz")")" 1
report=$a.repackage.txt
ok "report: sha256 of the archive" "$(awk '$1 == "sha256" { print $2 }' "$report")" "$(sum "$a")"
ok "report: names the file changed since installation" "$(sed -n '/^changed since installation/,/^restore/p' "$report" | grep -c -x '  usr/lib/demo/vmlinuz')" 1
ok "report: and only that one" "$(sed -n '/^changed since installation/,/^restore/p' "$report" | grep -c '^  ')" 1
ok "the summary line names the change too" "$(echo "$text" | grep -c 'changed since installation')" 1
if command -v pacman >/dev/null; then
  ok "pacman reads it as a package" "$(pacman -Qp "$a" 2>/dev/null)" "demo-pkg 1.2-3"
  ok "pacman lists the same files" "$(pacman -Qlpq "$a" 2>/dev/null | sed 's#^/##' | LC_ALL=C sort | tr '\n' ' ')" "$(awk '/^%FILES%$/ { on = 1; next } on && $0 == "" { exit } on' "$r/var/lib/pacman/local/demo-pkg-1.2-3/files" | LC_ALL=C sort | tr '\n' ' ')"
fi
snapshot() { (cd "$1" && find . -path ./var/lib/omarchy-k114s -prune -o -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -c1-16); }
r=$(mkroot); mkdemo "$r"; before=$(snapshot "$r"); repack "$r" --out "$BASE/out1b" demo-pkg >/dev/null; ok "repackage changes nothing in the root" "$(snapshot "$r")" "$before"
# refusals
r=$(mkroot); mkdemo "$r"; rm "$r/usr/lib/demo/sub/mod.ko"; out=$BASE/out2; mkdir "$out"
text=$(repack "$r" --out "$out" demo-pkg); ok "a missing file: refused" "$? $(ls "$out" | wc -l | tr -d ' ')" "1 0"
ok "missing: says which" "$(echo "$text" | grep -c 'usr/lib/demo/sub/mod.ko')" 1
text=$(repack "$r" --out "$out" --allow-missing demo-pkg); ok "--allow-missing writes the archive without it" "$? $(bsdtar -tf "$out"/demo-pkg-*.zst | grep -c mod.ko)" "0 0"
ok "--allow-missing: the report names what is not in it" "$(sed -n '/^missing on disk/,/^changed/p' "$out"/demo-pkg-*.repackage.txt | grep -c -x '  usr/lib/demo/sub/mod.ko')" 1
if [ "$(id -u)" != 0 ]; then
  r=$(mkroot); mkdemo "$r"; chmod 000 "$r/usr/lib/demo/vmlinuz"; out=$BASE/out3; mkdir "$out"
  text=$(repack "$r" --out "$out" demo-pkg); ok "an unreadable file: refused, nothing written" "$? $(ls "$out" | wc -l | tr -d ' ')" "1 0"
  ok "unreadable: asks for sudo" "$(echo "$text" | grep -c 'run with sudo')" 1
  chmod 644 "$r/usr/lib/demo/vmlinuz"
fi
r=$(mkroot); dbpkg "$r" evil 1-1 usr/ ../outside; out=$BASE/out4; mkdir "$out"
text=$(repack "$r" --out "$out" evil); ok "a path that leaves the root: refused" "$? $(echo "$text" | grep -c 'unsafe path')" "1 1"
r=$(mkroot); text=$(repack "$r" --out "$BASE/out4" not-there); ok "not installed: refused" "$? $(echo "$text" | grep -c 'is not installed')" "1 1"
text=$(repack "$r" --out "$BASE/out4" 'a b'); ok "two names: usage" "$?" 2
# the right database entry for a name that is a prefix of another
r=$(mkroot); mkdir -p "$r/usr/share/hdr"; echo h > "$r/usr/share/hdr/h"; echo k > "$r/usr/share/hdr/k"
dbpkg "$r" linux-aurora-headers 9.9-1 usr/share/hdr/h; rm -rf "$r/var/lib/pacman/local/linux-aurora-7.3.0.aurora17.v272-4"; dbpkg "$r" linux-aurora 7.3.0.aurora17.v272-4 usr/share/hdr/k
out=$BASE/out5; mkdir "$out"; repack "$r" --out "$out" linux-aurora >/dev/null
ok "linux-aurora is not confused with linux-aurora-headers" "$(ls "$out" | grep -c '^linux-aurora-7.3.0.aurora17.v272-4-any.pkg.tar.zst$') $(bsdtar -tf "$out"/linux-aurora-7*.zst | grep -c 'hdr/h$')" "1 0"

# --- recovery set ----------------------------------------------------------------------------------
mkesp() { # boot files on the fake ESP and in /boot
  local r=$1
  echo "limine menu" > "$r/boot/efi/limine.conf"; echo BOOTBIN > "$r/boot/efi/m1n1/boot.bin"; echo STAGE2 > "$r/boot/efi/m1n1/boot-ctxr.bin"
  echo DTB > "$r/boot/efi/k114s-repair/k114s.dtb"; echo LIMINE > "$r/boot/efi/EFI/BOOT/BOOTAA64.EFI"
  echo "repair image" > "$r/boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi"; echo "standard image" > "$r/boot/efi/EFI/Linux/omarchy_linux-aurora.efi"
  mkdir -p "$r/boot/efi/vendorfw"; echo FW > "$r/boot/efi/vendorfw/firmware.cpio"
  echo KERNEL > "$r/boot/vmlinuz-linux-aurora"; echo INITRAMFS > "$r/boot/initramfs-linux-aurora.img"
  mkdir -p "$r/usr/lib/modules/7.3.0-17.v272-4-ARCH/updates" "$r/usr/lib/firmware/updates/apple/centauri" "$r/usr/local/lib/omarchy-j714s" "$r/etc/omarchy-mac-boot" "$r/etc/default"
  echo MODULE > "$r/usr/lib/modules/7.3.0-17.v272-4-ARCH/updates/hid-magicmouse.ko"; echo FTAB > "$r/usr/lib/firmware/updates/apple/centauri/k114s-fw"
  echo hook > "$r/usr/local/lib/omarchy-j714s/update-boot-ctxr"; echo owner > "$r/etc/omarchy-mac-boot/owner-boot-chain"; echo 'CUSTOM_UKI_NAME="omarchy"' > "$r/etc/default/limine"
  printf '\6\0\0\0' > "$r/stub-id"; printf '/\\EFI\\Linux\\omarchy_linux-aurora-k114s.efi' | iconv -f ascii -t utf-16le >> "$r/stub-id"
}
r=$(mkroot); mkdemo "$r"; mkesp "$r"; echo demo-pkg >> "$(lib "$r")/holds.list"
mkdir -p "$r/usr/share/m"; echo mesa > "$r/usr/share/m/lib"; rm -rf "$r/var/lib/pacman/local/mesa-aurora-"*; dbpkg "$r" mesa-aurora 1:26.3.0-1 usr/share/m/lib
esp_before=$(cd "$r/boot/efi" && find . -type f -exec sha256sum {} + | LC_ALL=C sort | sha256sum)
text=$(recovery "$r"); ok "recovery set written" "$?" 0
set_dir=$(ls -d "$r"/var/lib/omarchy-k114s/recovery/*-recovery)
ok "the set verifies against its own SHA256SUMS" "$(cd "$set_dir" && sha256sum --quiet -c SHA256SUMS >/dev/null 2>&1; status)" 0
ok "every installed held or protected package is archived" "$(ls "$set_dir/packages" | grep -c '\.pkg\.tar\.zst$')" 11
ok "each archive has its report" "$(ls "$set_dir/packages" | grep -c '\.repackage\.txt$')" 11
ok "a version with an epoch gets a valid file name" "$(ls "$set_dir/packages" | grep -c '^mesa-aurora-1:26.3.0-1-any.pkg.tar.zst$')" 1
ok "names that are not installed are listed, not fatal" "$(awk '$1 == "not" { $1 = $2 = ""; print }' "$set_dir/state.txt" | tr -s ' ')" " asahi-fwextract asahi-scripts kernel-modules-hook limine limine-mkinitcpio-hook mkinitcpio omarchy-mac omarchy-mac-boot"
ok "/boot files copied" "$(ls "$set_dir/boot" | tr '\n' ' ')" "initramfs-linux-aurora.img vmlinuz-linux-aurora "
ok "ESP boot files copied with their folders" "$(cd "$set_dir/esp" && find . -type f | LC_ALL=C sort | tr '\n' ' ')" "./EFI/BOOT/BOOTAA64.EFI ./EFI/Linux/omarchy_linux-aurora-k114s.efi ./EFI/Linux/omarchy_linux-aurora.efi ./k114s-repair/k114s.dtb ./limine.conf ./m1n1/boot-ctxr.bin ./m1n1/boot.bin "
ok "copies are byte for byte" "$(sum "$set_dir/esp/m1n1/boot-ctxr.bin")" "$(sum "$r/boot/efi/m1n1/boot-ctxr.bin")"
ok "every ESP file is hashed, copied or not" "$(grep -c -E 'vendorfw/firmware.cpio|EFI/Linux/omarchy_linux-aurora.efi' "$set_dir/esp-files.sha256")" 2
ok "the ESP hashes verify against the ESP" "$(cd "$r/boot/efi" && sha256sum --quiet -c "$set_dir/esp-files.sha256" >/dev/null 2>&1; status)" 0
ok "files no package owns are in extras.tar" "$(bsdtar -tf "$set_dir/extras.tar" | grep -c -E 'updates/hid-magicmouse.ko$|centauri/k114s-fw$|omarchy-j714s/update-boot-ctxr$|owner-boot-chain$|etc/default/limine$')" 5
ok "state: booted image and Stage 2 hash" "$(grep -c -E "^booted image    EFI/Linux/omarchy_linux-aurora-k114s.efi$|^stage2 sha256   $(sum "$r/boot/efi/m1n1/boot-ctxr.bin")   \(m1n1/boot-ctxr.bin, the configured Stage 2\)$" "$set_dir/state.txt")" 2
ok "pacman.conf and the hold list are kept with it" "$(ls "$set_dir" | grep -c -x -E 'pacman.conf|holds.list|README.txt|packages.txt')" 4
ok "nothing was written to the ESP" "$(cd "$r/boot/efi" && find . -type f -exec sha256sum {} + | LC_ALL=C sort | sha256sum)" "$esp_before"
ok "the set is on the root filesystem, not the ESP" "$(case $set_dir in "$r"/boot/*) echo esp ;; *) echo root ;; esac)" root
# options
text=$(recovery "$r" --out "$BASE/set2" --packages "demo-pkg" --no-uki --label release); ok "a named set" "$?" 0
ok "--packages: only those" "$(ls "$BASE/set2/packages" | grep -c 'pkg.tar.zst$')" 1
ok "--no-uki leaves the boot images out, keeps the rest" "$(ls "$BASE/set2/esp/EFI" | tr '\n' ' ')$(test -s "$BASE/set2/esp/m1n1/boot-ctxr.bin"; status)" "BOOT 0"
ok "--no-uki: the images are still hashed" "$(grep -c 'omarchy_linux-aurora-k114s.efi' "$BASE/set2/esp-files.sha256")" 1
text=$(recovery "$r" --out "$BASE/set2"); ok "an existing folder is refused" "$? $(echo "$text" | grep -c 'exists already')" "1 1"
text=$(recovery "$r" --label 'a/b'); ok "a bad label is refused" "$?" 1
# keep the newest N of a label
r=$(mkroot); mkesp "$r"; printf 'hyprland-m5\n' > "$(lib "$r")/holds.list"; : > "$(lib "$r")/protected.list"; mkdir -p "$r/var/lib/omarchy-k114s/recovery"
for stamp in 20260101T000000Z 20260102T000000Z 20260103T000000Z; do mkdir "$r/var/lib/omarchy-k114s/recovery/$stamp-recovery"; done
mkdir "$r/var/lib/omarchy-k114s/recovery/20260101T000000Z-install"
text=$(recovery "$r" --keep 2); ok "keep: the oldest sets of the label go" "$(ls "$r/var/lib/omarchy-k114s/recovery" | grep -c -- '-recovery$')" 2
ok "keep: the newest older one stays" "$(test -d "$r/var/lib/omarchy-k114s/recovery/20260103T000000Z-recovery"; status)" 0
ok "keep: other labels are not touched" "$(test -d "$r/var/lib/omarchy-k114s/recovery/20260101T000000Z-install"; status)" 0
ok "the newest set of the label is noted" "$(cat "$r/var/lib/omarchy-k114s/recovery/.latest-recovery")" "$(ls -d "$r"/var/lib/omarchy-k114s/recovery/*-recovery | tail -n 1)"
# a package that cannot be archived stops the set
if [ "$(id -u)" != 0 ]; then
  r=$(mkroot); mkdemo "$r"; mkesp "$r"; echo demo-pkg > "$(lib "$r")/holds.list"; : > "$(lib "$r")/protected.list"; chmod 000 "$r/usr/lib/demo/vmlinuz"
  text=$(recovery "$r" --out "$BASE/set3"); ok "a package that cannot be read stops the set" "$? $(echo "$text" | grep -c 'could not archive demo-pkg')" "1 1"
  ok "and the incomplete set has no SHA256SUMS to be mistaken for a whole one" "$(test -e "$BASE/set3/SHA256SUMS"; status)" 1
  chmod 644 "$r/usr/lib/demo/vmlinuz"
fi

finish "r3 recovery tests"
