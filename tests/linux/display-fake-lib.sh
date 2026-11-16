#!/bin/bash
# Shared by tests/linux/test-display-trials-runbook.sh and test-display-d5-d9-runbook.sh: the fake Mac (ESP, /etc, /var/lib,
# efivars, device tree) the runbooks' blocks run against, the stand-ins for pacman, limine-entry-tool, systemctl, the hooks and the
# hardware checks, rewrite() (system paths and real hashes -> the fake machine) and run(). Sourced after r3-lib.sh, with DOC set.
REPO_DIR=$(cd "$L/.." && pwd)
W=$BASE/dt; BIN=$W/bin
block() { # block ANCHOR: the first ( ... ) code block after the line starting with ANCHOR
  awk -v a="$1" 'index($0, a) == 1 { f = 1 } f && $0 == "    (" { c = 1; next } c && $0 == "    )" { exit } c { print }' "$DOC"
}
GPU=9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc; GPUT=2c870ba9f5963f5ae1ed18a7effa520daa234583997470d9552a795b4aafcda5
R3A=a15fa01ab7e20c9c1bf1b3f61c04f6ab765c4aa425188c22f70648a3871c52f4; AUR=72f5d32c9a4bc443bddab3eba171365b8cd082bf9cc61f665b15684d2d64403a
R3B=438c4efe03d5271ffb5beae0125199e4d5cdba2bc97e5fdc2a05455eeb93f905
B1=0ca7b7593340981702ba306ffb93168cb67615e5a62a162270f9117aff3491ba; B5=90b351377d6fcbad00ddc4c2fb74fce4313dd7fa5f4978ba895a7c41be523e30; BT=5b6b83c8cd5e59333182f6ca37f22b1e99bd029daa1342d186daee096b292fda
PINL=beceb683b63a6d421ce58061a55c14a6d09e0381a23c1a543df55f4cc8007392
OLD=9e43d27a28f750ad559d9060fc9b30c33a59b5e5a8bb6e46ee1f456ffb68a5ca; PIN=3a9884f3513d110c9602e4261d2826e380bff7d92347da63890372f5307f7087
GPIN=3749a5efc7a8a0d3565e3038d4ba42d94475a79944f4789e07fc26c2a89d611e
REL=7.3.0-17.v272-11-k114s-r3b-ARCH; BLI=4a67b082-0a4c-41cf-b6c7-440b29bb8c4f; RT=b2ac5fc9-92b7-4acd-aeac-11e818c3130c
rewrite() { # the block with the system paths and the real hashes of this Mac rewritten to the fake machine
  sed "s#/boot/efi#$W/esp#g; s#/etc/omarchy-k114s#$W/etc#g; s#/usr/local/lib/omarchy-k114s#$W/lib#g; s#/var/lib/k114s-recovery#$W/rec#g
       s#/etc/default/update-m1n1#$W/etc/update-m1n1#g; s#/etc/systemd/system#$W/systemd#g; s#/run/lock#$W/lock#g
       s#/sys/firmware/efi/efivars#$W/efivars#g; s#/proc/device-tree/chosen#$W/chosen#g; s#/usr/lib/modules#$W/modules#g
       s#/etc/machine-id#$W/machine-id#g; s#/proc/sys/kernel/random/boot_id#$W/boot_id#g; s#/dev/mtd1ro#$W/mtd1ro#g
       s#/etc/modprobe.d#$W/modprobe#g; s#/etc/mkinitcpio.conf.d#$W/mkinitcpio.conf.d#g; s#/usr/lib/modprobe.d#$W/usrmodprobe#g; s#/var/lib/k114s-backlight#$W/klb#g
       s#/usr/lib/asahi-boot#$W/asahi#g; s#/etc/pacman.conf#$W/pacman.conf#g; s#/etc/omarchy-mac-boot#$W/macboot#g
       s#/etc/pacman.d/hooks#$W/hooks-etc#g; s#/usr/share/libalpm/hooks#$W/hooks-usr#g; s#/usr/share/omarchy/migrations#$W/migrations#g
       s#/sys/class#$W/sys/class#g; s#/sys/module#$W/sys/module#g; s#/var/tmp#$W/vartmp#g
       s#bash \"\$REPO/packaging/linux-k114s/check-package.sh\"#$BIN/check-package#g
       s#$GPU#$(sum "$W/fake/gpu.bin")#g; s#$GPUT#$(sum "$W/fake/gpu.dtb")#g; s#$R3A#$(sum "$W/fake/r3a.efi")#g
       s#$AUR#$(sum "$W/fake/aurora.efi")#g; s#$R3B#$(sum "$W/fake/r3b.pkg")#g
       s#$B1#$(sum "$W/fake/r3b1.pkg")#g; s#$B5#$(sum "$W/fake/d5.bin")#g; s#$BT#$(sum "$W/fake/bright.dtb")#g; s#$PINL#$(sum "$W/fake/pinldr-m1n1.bin")#g
       s#$OLD#$(sum "$W/fake/oldldr.bin")#g; s#$PIN#$(sum "$W/fake/pinldr.bin")#g; s#$GPIN#$(sum "$W/fake/gpinldr.bin")#g"
}
mkdir -p "$BIN" "$W/fake"
printf '#!/bin/sh\nexit 0\n' > "$BIN/findmnt"
printf '#!/bin/sh\n[ "$1" = -r ] && { echo "${FAKE_UNAME:-7.3.0-17.v272-4-k114s-r3a-ARCH}"; exit 0; }\n[ "$1" = -v ] && { echo "#2 SMP PREEMPT ${FAKE_UNAME_V:-K114S-R3A} Sat Nov 14 2026"; exit 0; }\nexec /usr/bin/uname "$@"\n' > "$BIN/uname"
printf '#!/bin/sh\necho "Avail"; echo "${FAKE_FREE:-190300000}"\n' > "$BIN/df"
printf '#!/bin/sh\necho "check-package: ${FAKE_CHECK:-all passed}"\n' > "$BIN/check-package"
printf '#!/bin/sh\necho "reboot-scheduled $*" >> "$FAKE_W/calls"\nexit 0\n' > "$BIN/systemd-run"
# objcopy --dump-section .initrd=OUT IMAGE /dev/null: like the real one it fails and writes nothing when IMAGE is not readable (a glob a
# root-only folder left unexpanded is a literal name); it logs each readable IMAGE to $FAKE_W/objcopy-calls; exits 1 as the real one does on a UKI
cat > "$BIN/objcopy" <<'SH'
#!/bin/sh
for a; do case $a in -*|.initrd=*) ;; *) [ -n "${img:-}" ] || img=$a ;; esac; done
[ -r "${img:-}" ] || exit 1
echo "$img" >> "$FAKE_W/objcopy-calls"
for a; do case $a in .initrd=*) echo initrd > "${a#.initrd=}" ;; esac; done
exit 1
SH
# lsinitcpio: a module list without appledrm unless FAKE_INITRD=appledrm
cat > "$BIN/lsinitcpio" <<'SH'
#!/bin/sh
i=0; while [ $i -lt 30 ]; do echo "usr/lib/modules/x/kernel/m$i.ko.zst"; i=$((i+1)); done
[ "${FAKE_INITRD:-}" = appledrm ] && echo "usr/lib/modules/x/kernel/drivers/gpu/drm/apple/appledrm.ko.zst"
exit 0
SH
# systemctl: the two snapshot-sync units are active until a stop of both, and again after a start or a (simulated) reboot
cat > "$BIN/systemctl" <<'SH'
#!/bin/sh
echo "$@" >> "$FAKE_W/calls"
case $1 in
  is-enabled) shift; for u; do echo masked; done ;;
  show) [ "$2" = -p ] && [ "$3" = ActiveState ] && { echo "${FAKE_CLEANUP:-inactive}"; exit 0; }; for a; do u=$a; done; ls "$FAKE_W/systemd/$u.d" 2>/dev/null | sed "s#^#$FAKE_W/systemd/$u.d/#" | tr '\n' ' '; echo ;;
  stop) [ "$2 $3" = "snapper-cleanup.timer limine-snapper-sync.service" ] && : > "$FAKE_W/state/sync-stopped" ;;
  start) [ "$2 $3" = "snapper-cleanup.timer limine-snapper-sync.service" ] && rm -f "$FAKE_W/state/sync-stopped" ;;
  is-active) shift; q=0; [ "$1" = -q ] && { q=1; shift; }; rc=3
    for u; do
      case $u in snapper-cleanup.service) st=${FAKE_CLEANUP:-inactive} ;; *) if [ -e "$FAKE_W/state/sync-stopped" ]; then st=inactive; else st=active; fi ;; esac
      [ $q = 1 ] || echo $st; [ $st = active ] && rc=0
    done; exit $rc ;;
esac
exit 0
SH
# the stand-ins for the hardware checks (a fake REPO): they log how they were called; FAKE_DCHECK=BAD makes one fail
mkdir -p "$W/repo/tests/hardware"
printf '#!/bin/sh\necho "display-check $*" >> "$FAKE_W/calls"\necho "ok    fake display check"\n[ "${FAKE_DCHECK:-}" = BAD ] && echo "BAD   fake"\nexit 0\n' > "$W/repo/tests/hardware/k114s-display-check.sh"
printf '#!/bin/sh\necho "ok    fake hardware check"\nexit 0\n' > "$W/repo/tests/hardware/k114s-r3a-check.sh"
chmod +x "$W/repo/tests/hardware/"*.sh
printf '#!/bin/sh\necho "[    1.000000] aurora: GPU firmware build: 26B8125 for T6050 G17S, primary then secondary"\n' > "$BIN/dmesg"
printf '#!/bin/sh\necho "renderer: fake"\n' > "$BIN/omarchy-hw-software-rendering"
# journalctl: -b reads FAKE_JOURNAL (the previous boot), --since reads FAKE_SINCE
cat > "$BIN/journalctl" <<'SH'
#!/bin/sh
case " $* " in *" -b "*) cat "${FAKE_JOURNAL:-/dev/null}" ;; *" --since "*) cat "${FAKE_SINCE:-/dev/null}" ;; esac
exit 0
SH
printf '#!/bin/sh\n[ "$1" = -c ] || exit 1\nif [ -e "$FAKE_W/modprobe/aurora-m5-vrr.conf" ]; then grep "^options" "$FAKE_W/modprobe/aurora-m5-vrr.conf"; else echo "options appledrm fw27_panel_vrr=1"; fi\n' > "$BIN/modprobe"
# limine-entry-tool --remove-uki linux-aurora: the sub-entry up to the next one, and its image (FAKE_TOOL=extra also drops a line)
cat > "$BIN/limine-entry-tool" <<'SH'
#!/bin/sh
[ "$1 $2" = "--remove-uki linux-aurora" ] || exit 2
c=$FAKE_W/esp/limine.conf
awk '{ s = $0; sub(/^[ \t]+/, "", s) } s ~ /^\// { skip = (s == "//linux-aurora") } !skip { print }' "$c" > "$c.tmp" && mv "$c.tmp" "$c"
[ "${FAKE_TOOL:-}" = extra ] && sed -i '/^hash_mismatch_panic/d' "$c"
rm -f "$FAKE_W/esp/EFI/Linux/omarchy_linux-aurora.efi"
[ "${FAKE_TOOL:-}" = fail ] && exit 1
exit 0
SH
# pacman as far as the blocks use it; -U of r3b runs the Limine hook (one image, FAKE_HOOK=full rebuilds r3a's too) and the
# Stage 2 hook (rewrites boot-ctxr.bin with the same bytes); -R takes the entry and image away and runs the Stage 2 hook again
cat > "$BIN/pacman" <<'SH'
#!/bin/sh
s=$FAKE_W/state; c=$FAKE_W/esp/limine.conf; rel=7.3.0-17.v272-11-k114s-r3b-ARCH
if [ "$1" = -Sw ]; then # -Sw ... --cachedir DIR NAMES: the package files come from $s/pkg-NAME (a tree), as the real one writes them
  shift; cdir=; while [ $# -gt 0 ]; do case $1 in --cachedir) cdir=$2; shift 2 ;; --dbpath|--logfile) shift 2 ;; -*) shift ;; *) [ -d "$s/pkg-$1" ] || exit 1; bsdtar -cf "$cdir/$1-2-aarch64.pkg.tar.zst" -C "$s/pkg-$1" usr; shift ;; esac; done; exit 0
fi
case "$1" in -Ql) cat "$s/ql-$2" 2>/dev/null; [ -e "$s/ql-$2" ]; exit ;; esac
case "$1 $2" in
  "-Q linux-k114s-r3b") [ -e "$s/r3b" ] && { echo "linux-k114s-r3b $(cat "$s/r3b")"; exit 0; }; exit 1 ;;
  "-Q "*) exit 1 ;;
  "-Qqo "*) case $2 in *-k114s-r3a-ARCH) echo linux-k114s ;; *-k114s-r3b-ARCH) [ -e "$s/r3b" ] && echo linux-k114s-r3b || exit 1 ;; *) exit 1 ;; esac; exit 0 ;;
  "-U --print") echo "linux-k114s-r3b ${FAKE_PKGVER:-7.3.0.r3b-1}"; exit 0 ;;
  "-U --noconfirm")
    img=$FAKE_W/esp/EFI/Linux/omarchy_linux-k114s-r3b.efi; head -c 2100 /dev/urandom > "$img"; hs=$(b2sum "$img" | cut -d' ' -f1)
    cmd=$(awk '/^[ \t]*\/\/linux-k114s[ \t]*$/ {f=1} f && /^[ \t]*cmdline:/ {print; exit}' "$c")
    printf '  //linux-k114s-r3b\n  ### This kernel entry is auto-generated by limine-entry-tool\n  comment: Kernel version: %s\n  comment: kernel-id=linux-k114s-r3b\n  protocol: efi\n  path: boot():/EFI/Linux/omarchy_linux-k114s-r3b.efi#%s\n%s\n\n' "$rel" "$hs" "$cmd" >> "$c"
    mkdir -p "$s" "$FAKE_W/modules/$rel"; echo "${FAKE_PKGVER:-7.3.0.r3b-1}" > "$s/r3b"
    echo "(1/1) installing linux-k114s-r3b"; echo "==> Building UKI for linux-k114s-r3b ($rel)"
    [ "${FAKE_HOOK:-}" = full ] && echo "==> Building UKI for linux-k114s (7.3.0-17.v272-4-k114s-r3a-ARCH)"
    cp "$FAKE_W/esp/m1n1/boot-ctxr.bin" "$FAKE_W/esp/m1n1/boot-ctxr.bin.x" && mv "$FAKE_W/esp/m1n1/boot-ctxr.bin.x" "$FAKE_W/esp/m1n1/boot-ctxr.bin"
    echo "update-boot-ctxr-k114s: wrote $FAKE_W/esp/m1n1/boot-ctxr.bin (4440237 bytes, K114s device tree 2c870ba9f5963f5a)"; exit 0 ;;
  "-R --noconfirm")
    [ -e "$s/r3b" ] || exit 1
    awk '{ t = $0; sub(/^[ \t]+/, "", t) } t ~ /^\// { skip = (t == "//linux-k114s-r3b") } !skip { print }' "$c" > "$c.tmp" && mv "$c.tmp" "$c"
    rm -f "$FAKE_W/esp/EFI/Linux/omarchy_linux-k114s-r3b.efi" "$s/r3b"; rm -rf "$FAKE_W/modules/$rel"
    echo "(1/1) removing linux-k114s-r3b"; echo "Removed unused Limine boot entry: linux-k114s-r3b"
    echo "update-boot-ctxr-k114s: wrote $FAKE_W/esp/m1n1/boot-ctxr.bin (4440237 bytes, K114s device tree 2c870ba9f5963f5a)"; exit 0 ;;
esac
exit 1
SH
printf '#!/bin/sh\n[ "$1" = -- ] && shift\nexec "$@"\n' > "$BIN/fakeroot"
chmod +x "$BIN"/*
for f in gpu.bin:4001 gpu.dtb:301 r3a.efi:2000 aurora.efi:1900 r3b.pkg:500 oldldr.bin:4100 pinldr.bin:4200 gpinldr.bin:4150; do head -c "${f#*:}" /dev/urandom > "$W/fake/${f%%:*}"; done
fresh() { # the Mac as the promotion left it, on a default boot of r3a
  rm -rf "$W/rootdirs" "$W/hooks-etc" "$W/hooks-usr" "$W/esp" "$W/etc" "$W/lib" "$W/rec" "$W/lock" "$W/efivars" "$W/chosen" "$W/calls" "$W/home" "$W/modules" "$W/systemd" \
    "$W/modprobe" "$W/usrmodprobe" "$W/mkinitcpio.conf.d" "$W/klb" "$W/state" "$W/R"; unset FAKE_UNAME
  echo 00000000000000000000000000000000 > "$W/machine-id"; echo boot-0 > "$W/boot_id"
  printf '[0.1] FDT: GPU: firmware 26B8125\n[0.2] the device tree does not describe the internal display: no handoff\n' > "$W/mtd1ro"
  mkdir -p "$W/esp/EFI/Linux" "$W/esp/m1n1" "$W/esp/k114s-repair" "$W/etc" "$W/lib" "$W/rec" "$W/lock" "$W/efivars" "$W/chosen" \
    "$W/home/.config/hypr" "$W/modules/7.3.0-17.v272-4-k114s-r3a-ARCH" "$W/systemd" "$W/modprobe" "$W/usrmodprobe" "$W/state" "$W/R/pkg" "$W/R/stage2"
  cp "$W/fake/gpu.bin" "$W/esp/m1n1/boot-ctxr.bin"; cp "$W/fake/gpu.bin" "$W/esp/m1n1/boot-ctxr-r3-gpu.bin"; : > "$W/esp/m1n1/boot.bin"
  cp "$W/fake/gpu.dtb" "$W/esp/k114s-repair/k114s.dtb"; cp "$W/fake/gpu.dtb" "$W/lib/k114s.dtb"
  cp "$W/fake/r3a.efi" "$W/esp/EFI/Linux/omarchy_linux-k114s.efi"; cp "$W/fake/aurora.efi" "$W/esp/EFI/Linux/omarchy_linux-aurora.efi"
  cp "$W/fake/r3b.pkg" "$W/R/pkg/linux-k114s-r3b-7.3.0.r3b-1-aarch64.pkg.tar.zst"
  cp "$W/fake/oldldr.bin" "$W/R/stage2/boot-ctxr-disp-oldldr.bin"; cp "$W/fake/pinldr.bin" "$W/R/stage2/boot-ctxr-disp-pinldr.bin"; cp "$W/fake/gpinldr.bin" "$W/R/stage2/boot-ctxr-gpu-pinldr.bin"
  mkdir -p "$W/esp/00000000000000000000000000000000/limine_history"; echo '{}' > "$W/esp/00000000000000000000000000000000/limine_history/snapshots.json"
  cp "$W/esp/00000000000000000000000000000000/limine_history/snapshots.json" "$W/esp/00000000000000000000000000000000/limine_history/snapshots.json.old"
  printf '1.0.0b13-g22b71758-dirty\0' > "$W/chosen/asahi,m1n1-stage2-version"
  printf 'spent\nm1n1/boot-ctxr-r3-gpu.bin\n' > "$W/esp/aura-try"; printf 'export LC_ALL=C\nexport M1N1_UPDATE_DISABLED=1\n' > "$W/etc/update-m1n1"
  echo "ok boot=x id=x" > "$W/rec/boot-once-selftest-ok"
  printf 'IgnorePkg = linux-aurora linux-k114s limine-mkinitcpio-hook limine-snapper-sync m1n1-aurora uboot-aurora\n' > "$W/pacman.conf"
  : > "$W/usrmodprobe/aurora-m5-vrr.conf"
  printf -- '-- rules\nhl.monitor({ output = "Unknown-1", mode = "preferred", position = "auto", scale = 2 })\nhl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 2 })\n' > "$W/home/.config/hypr/monitors.lua"
  { printf '\007\000\000\000'; printf 'ubootefi.var\0'; } > "$W/efivars/RTStorageVolatile-$RT"; : > "$W/esp/ubootefi.var"
  { printf '\007\000\000\000'; printf 'Omarchy.linux-k114s' | iconv -t UTF-16LE; printf '\000\000'; } > "$W/efivars/LoaderEntrySelected-$BLI"
  cat > "$W/save" <<'SAVE'
#!/bin/sh
f=$K114S_ESP/ubootefi.var; : > "$f"
v=$K114S_EFIVARS/LoaderEntryOneShot-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f
[ -e "$v" ] && { printf 'LoaderEntryOneShot' | iconv -t UTF-16LE >> "$f"; printf '\0\0' >> "$f"; tail -c +5 "$v" >> "$f"; }
exit 0
SAVE
  chmod +x "$W/save"
  cat > "$W/esp/limine.conf" <<CONF
timeout: 5
default_entry: Omarchy/linux-k114s
hash_mismatch_panic: no

/+Omarchy
comment: machine-id=00000000000000000000000000000000
  //linux-aurora
  ### This kernel entry is auto-generated by limine-entry-tool
  comment: Kernel version: 7.3.0-17.v272-4-ARCH
  comment: kernel-id=linux-aurora
  protocol: efi
  path: boot():/EFI/Linux/omarchy_linux-aurora.efi#$(b2sum "$W/esp/EFI/Linux/omarchy_linux-aurora.efi" | cut -d' ' -f1)
  cmdline: root=UUID=00000000-0000-0000-0000-000000000000 rw

  //linux-k114s
  ### This kernel entry is auto-generated by limine-entry-tool
  comment: Kernel version: 7.3.0-17.v272-4-k114s-r3a-ARCH
  comment: kernel-id=linux-k114s
  protocol: efi
  path: boot():/EFI/Linux/omarchy_linux-k114s.efi#$(b2sum "$W/esp/EFI/Linux/omarchy_linux-k114s.efi" | cut -d' ' -f1)
  cmdline: root=UUID=00000000-0000-0000-0000-000000000000 rw

CONF
}
# The fake sudo is not a plain pass-through: a folder made by `sudo mktemp -d` is closed (mode 000) to the plain user and opens
# only for the commands run through sudo, as root-only folders do on the Mac (a bare redirect or read into it fails).
FAKE_SUDO='sudo() { local d r; if [ "$1" = mktemp ]; then d=$("$@") || return; chmod 000 "$d"; echo "$d" >> "$FAKE_W/rootdirs"; echo "$d"; return; fi
  for d in $(cat "$FAKE_W/rootdirs" 2>/dev/null); do [ -d "$d" ] && chmod 700 "$d"; done; "$@"; r=$?
  for d in $(cat "$FAKE_W/rootdirs" 2>/dev/null); do [ -d "$d" ] && chmod 000 "$d"; done; return $r; }; '
run() { # stdin: the block, rewritten -> $out, $rc
  out=$(cd "$W" && FAKE_W=$W HOME=$W/home PATH=$BIN:$PATH K=$L/r3a-trial/k114s-boot-once D=${FAKE_D:-$W/rec/display} R=$W/R R5=$W/R5 RT=$W/RT DO=$W/rec/display-old REPO=${FAKE_REPO:-$REPO_DIR} \
    K114S_ESP=$W/esp K114S_ETC=$W/etc K114S_EFIVARS=$W/efivars K114S_STATE=$W/rec K114S_SYSTEMCTL=$BIN/systemctl K114S_SAVE=$W/save \
    OMARCHY_PATH=${FAKE_OMARCHY_PATH:-$W} K114S_SDDM_ROOT=$W/sddm K114S_BOOTID=boot1 bash -c "$FAKE_SUDO"'FAKE=1; '"$(cat)" 2>&1); rc=$?
}
state() { (cd "$W" && find esp etc lib rec systemd modprobe home -type f -exec sha256sum {} + 2>/dev/null | sort -k2 | sha256sum | cut -c1-16); }
espstate() { (cd "$W" && find esp -type f -exec sha256sum {} + 2>/dev/null | sort -k2 | sha256sum | cut -c1-16); }
