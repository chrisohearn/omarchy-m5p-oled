#!/bin/bash
# The blocks of docs/r3-display-d5-d9.md (D9p, I1b, S5, T3a, T3b, D5, D7, D7b, D8, T4a, T4b, D6, D9a, D9c, the undo of D9c, P9, C9, D9x,
# D9y, U0, U1, C1b, C2b), and the blocks of docs/r3-display-trials.md it reuses with this window's record folder (P, W0, W1, X, F, C,
# C4, C5), cut out of the runbooks themselves and run as a normal user against the fake Mac of display-fake-lib.sh (a fake ESP with
# the real k114s-boot-once, stand-ins for pacman, limine-entry-tool, systemctl, systemd-run, the hooks, the hardware checks and, for the
# user-session blocks, brightnessctl, hyprctl, the Omarchy scripts, modetest and the backlight in a fake /sys). The real Stage 2 hook
# (linux/update-boot-ctxr-k114s) runs in D9a against fake loaders and trees. So this proves the order of the writes, the STOP paths,
# what the files hold afterwards and what each check decides, not that anything boots, and not what a real panel does.
#   usage: test-display-d5-d9-runbook.sh [LINUX_DIR]
set -u
. "$(dirname "$0")/r3-lib.sh" "${1:-}"
have flock b2sum iconv python3 jq gzip || { echo "display d5-d9 runbook tests: SKIPPED (flock, b2sum, iconv, python3, jq and gzip are needed)"; exit 0; }
DOC1=$T/../../docs/r3-display-trials.md; DOC=$T/../../docs/r3-display-d5-d9.md
. "$(dirname "$0")/display-fake-lib.sh"
block1() { DOC=$DOC1 block "$@"; }
export FAKE_D=$W/rec/display-d5 K114S_BL_SYSFS=$W/sys/class/backlight XDG_STATE_HOME=$W/home/.local/state K114S_BL_SETTLE=0
D=$FAKE_D; DOLD=$W/rec/display-old; BLD=$W/sys/class/backlight/apple-panel-bl; REL=7.3.0-17.v272-11-k114s-r3b-ARCH; BLI=4a67b082-0a4c-41cf-b6c7-440b29bb8c4f

# --- the fake files: valid device trees (the real Stage 2 hook checks the header), the loaders, and the D9 Stage 2 the hook must write ----
python3 -I - "$W/fake" <<'PY'
import gzip, os, struct, sys
d = sys.argv[1]
def fdt(tag):
    body = b"apple,k114s\0" + tag
    return struct.pack(">II", 0xd00dfeed, 40 + len(body)) + b"\0" * 32 + body
def w(n, b): open(d + "/" + n, "wb").write(b)
asahi, pin = os.urandom(2500), os.urandom(3100)
ptree, btree = fdt(b"P"), fdt(b"bright")
tail = gzip.compress(os.urandom(900))
w("asahi-m1n1.bin", asahi); w("pinldr-m1n1.bin", pin); w("bright.dtb", btree); w("ptree.dtb", ptree)
w("boot.bin", asahi + ptree + tail)          # the image-combined file the hook takes the U-Boot tail from
w("d5.bin", pin + btree + tail)              # what the hook must write: pin loader + brightness tree + the same tail
w("r3b1.pkg", os.urandom(700))
PY
chmod 644 "$W/fake/"*
# the hardware wrapper of D5: the real k114s-backlight-check, with the two host-dependent lines (the device-tree floor and the DRM driver) as on the K114s
mkdir -p "$W/repo/linux/brightness" "$W/repo/linux/display"; cp "$REPO_DIR"/linux/display/* "$W/repo/linux/display/"
cat > "$W/repo/linux/brightness/k114s-backlight-check" <<SH
#!/bin/bash
export K114S_BL_KLOG=\$FAKE_W/klog
bash "\${FAKE_BLTOOL:-$REPO_DIR/linux/brightness/k114s-backlight-check}" "\$@" | sed -e 's/^device-tree floor   none/device-tree floor   10/' -e 's/^display drivers .*/display drivers     apple-drm /'
exit \${PIPESTATUS[0]}
SH
chmod +x "$W/repo/linux/brightness/k114s-backlight-check"
# stand-ins for the user-session tools: state in \$FAKE_W/state, the backlight in the fake /sys
cat > "$BIN/hyprctl" <<'SH'
#!/bin/sh
s=$FAKE_W/state; mkdir -p "$s"
case "$1" in
  monitors) vr=false; [ -e "$s/vrr" ] && vr=true; dp=true; [ -e "$s/dpms-off" ] && dp=false
    echo "[{\"name\":\"eDP-1\",\"width\":3024,\"height\":1986,\"refreshRate\":120.0,\"scale\":2.0,\"vrr\":$vr,\"dpmsStatus\":$dp,\"disabled\":false}]" ;;
  eval) case "$2" in *"vrr = 1"*) [ "${FAKE_VRRFAIL:-}" = 1 ] || : > "$s/vrr" ;; *"vrr = 0"*) rm -f "$s/vrr" ;; esac; echo ok ;;
  hyprsunset) [ -e "$s/night" ] && echo 4000 || echo 6500 ;;
esac
exit 0
SH
cat > "$BIN/omarchy-brightness-display" <<'SH'
#!/bin/sh
s=$FAKE_W/state; b=$FAKE_W/sys/class/backlight/apple-panel-bl; mkdir -p "$s"
while [ "$1" = --no-osd ]; do shift; done
case "$1" in
  off) : > "$s/dpms-off" ;;
  on) [ "${FAKE_NOWAKE:-}" = 1 ] || rm -f "$s/dpms-off" ;;
  5%-|+5%) [ "${FAKE_NOSTEP:-}" = 1 ] && exit 0; v=$(cat "$b/brightness"); case $1 in 5%-) v=$((v - 50)); [ $v -lt 10 ] && v=10 ;; *) v=$((v + 50)) ;; esac
    echo $v > "$b/brightness"; echo $v > "$b/actual_brightness" ;;
esac
exit 0
SH
printf '#!/bin/sh\necho apple-panel-bl\n' > "$BIN/omarchy-hw-display"
printf '#!/bin/sh\nb=$FAKE_W/sys/class/backlight/apple-panel-bl\nwhile [ "$1" != set ] && [ -n "$1" ]; do shift; done\n[ "$1" = set ] && { echo "$2" > "$b/brightness"; echo "$2" > "$b/actual_brightness"; }\nexit 0\n' > "$BIN/brightnessctl"
cat > "$BIN/omarchy-toggle-nightlight" <<'SH'
#!/bin/sh
s=$FAKE_W/state; mkdir -p "$s"
if [ "$1" = --status ]; then [ -e "$s/night" ] && echo '{"enabled":true,"temperature":4000}' || echo '{"enabled":false,"temperature":6500}'; exit 0; fi
[ "${FAKE_NIGHTFAIL:-}" = 1 ] && exit 0
[ -e "$s/night" ] && rm -f "$s/night" || : > "$s/night"
exit 0
SH
# modetest -M apple -c: the KMS connector properties; vrr_capable's value comes from $FAKE_W/vrrcap (the sysfs file does not exist on this kernel)
printf '#!/bin/sh\necho "  23 CTM:"\necho "  25 GAMMA_LUT:"\n[ -e "$FAKE_W/vrrcap" ] && printf "  50 vrr_capable:\\n\\t\\tflags: immutable range\\n\\t\\tvalues: 0 1\\n\\t\\tvalue: %%s\\n" "$(cat "$FAKE_W/vrrcap")"\nexit 0\n' > "$BIN/modetest"
printf '#!/bin/sh\nexit 0\n' > "$BIN/mpv"
# the idle guard, the lock, the pending-update list and a test initramfs build (state in $FAKE_W/state)
printf '#!/bin/sh\n[ "$1 $2" = "lock isLocked" ] && { [ -e "$FAKE_W/state/locked" ] && echo true || echo false; }\nexit 0\n' > "$BIN/omarchy-shell"
cat > "$BIN/omarchy-toggle-idle" <<'SH'
#!/bin/sh
s=$FAKE_W/state; mkdir -p "$s"
case "$1" in
  --status) [ -e "$s/stay-awake" ] && echo '{"enabled":true}' || echo '{"enabled":false}' ;;
  stay-awake) [ "${FAKE_IDLEFAIL:-}" = 1 ] || : > "$s/stay-awake" ;;
  allow-idle) rm -f "$s/stay-awake" ;;
esac
exit 0
SH
printf '#!/bin/sh\nwhile [ "$1" != -g ] && [ -n "$1" ]; do shift; done\n[ "$1" = -g ] && echo img > "$2"\nexit 0\n' > "$BIN/mkinitcpio"
printf '#!/bin/sh\n[ -s "$FAKE_W/state/pending" ] && { cat "$FAKE_W/state/pending"; exit 0; }\nexit 2\n' > "$BIN/checkupdates"
mkdir -p "$W/vartmp"
printf '#!/bin/sh\ncat "${FAKE_DMESG:-/dev/null}" 2>/dev/null\necho "[    1.000000] aurora: GPU firmware build: 26B8125 for T6050 G17S, primary then secondary"\n' > "$BIN/dmesg"
# date: the log folders of block F carry the time of the boot; two boots in one second of the test must not share a folder
cat > "$BIN/date" <<'SH'
#!/bin/sh
if [ "$1" = +%Y%m%d-%H%M%S ]; then n=$(cat "$FAKE_W/datectr" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "$FAKE_W/datectr"; printf '20261115-19%04d\n' $n; else exec /usr/bin/date "$@"; fi
SH
printf '#!/bin/sh\nexit 0\n' > "$BIN/sleep"   # the blocks wait seconds between steps; the fake Mac needs none
chmod +x "$BIN"/*

block() { # block ANCHOR (this runbook), rewritten
  awk -v a="$1" 'index($0, a) == 1 { f = 1 } f && $0 == "    (" { c = 1; next } c && $0 == "    )" { exit } c { print }' "$DOC" | rewrite
}
blockold() { awk -v a="$1" 'index($0, a) == 1 { f = 1 } f && $0 == "    (" { c = 1; next } c && $0 == "    )" { exit } c { print }' "$DOC1" | rewrite; }
bP=$(blockold '### Block P:'); bW0=$(blockold '**W0.'); bW1=$(blockold '**W1.'); bX=$(blockold '**Block X:'); bF=$(blockold '**Block F:')
bC=$(blockold '**Block C ('); bC4=$(blockold '**C4.'); bC5=$(blockold '**C5.')
bD9p=$(block '**D9p.'); bI1b=$(block '**I1b.'); bS5=$(block '**S5.'); bT3a=$(block '**T3a.'); bT3b=$(block '**T3b.'); bD5=$(block '**D5.')
bG6a=$(block '**G6a.'); bG6b=$(block '**G6b.'); bD7=$(block '**D7. DPMS'); bD7b=$(block '**D7b.'); bD8=$(block '**D8.'); bT4a=$(block '**T4a.'); bT4b=$(block '**T4b.'); bD6=$(block '**D6.')
bD9a=$(block '**D9a.'); bD9c=$(block '**D9c.'); bD9u=$(block '**Undo of D9c'); bP9=$(block '**Block P9'); bC9=$(block '**Block C9')
bD9x=$(block '**D9x.'); bD9y=$(block '**D9y.'); bU0=$(block '**U0.'); bU1=$(block '**U1.'); bC1b=$(block '**C1b.'); bC2b=$(block '**C2b.')
ALL=("$bD9p" "$bI1b" "$bS5" "$bT3a" "$bT3b" "$bD5" "$bD7" "$bD7b" "$bD8" "$bG6a" "$bG6b" "$bT4a" "$bT4b" "$bD6" "$bD9a" "$bD9c" "$bD9u" "$bP9" "$bC9" "$bD9x" "$bD9y" "$bU0" "$bU1" "$bC1b" "$bC2b")
ok "every block is found (25 here, 8 of the first runbook) and no real hash is left in the ones that write" \
  "$(for b in "${ALL[@]}" "$bP" "$bW0" "$bW1" "$bX" "$bF" "$bC" "$bC4" "$bC5"; do [ -n "$b" ] && echo y; done | wc -l) $(printf '%s' "$bI1b$bS5$bT3a$bT3b$bD9a$bD9c$bD9u$bP9$bT4a$bT4b$bC9" | grep -c -e "$B1" -e "$B5" -e "$BT" -e "$PINL" -e "$GPU" -e "$R3A")" "33 0"

fresh2() { # the Mac as window 1 left it (I0's files in place), the build area, the promotion folder; a default boot of r3a on P
  fresh; unset FAKE_UNAME_V FAKE_PKGVER; rm -rf "$W/asahi" "$W/macboot" "$W/sys" "$W/R5" "$W/RT" "$DOLD" "$W/datectr" "$W/dm" "$W/dm2" "$W/since"
  mkdir -p "$W/R5/pkg" "$W/R5/stage2" "$W/R5/dtb-p" "$W/RT/aura-pin" "$W/asahi" "$W/macboot" "$W/esp/k114s-repair/promotion" "$W/esp/k114s-repair/r2c" \
    "$BLD" "$W/sys/class/drm/card2-eDP-1" "$W/sys/module/appledrm/parameters" "$DOLD/boot-20261115-191015-disp-pinldr" "$W/home/.config/omarchy"
  cp "$W/fake/r3b1.pkg" "$W/R5/pkg/linux-k114s-r3b-7.3.0.r3b.b1-1-aarch64.pkg.tar.zst"; cp "$W/fake/d5.bin" "$W/R5/stage2/boot-ctxr-disp-bl.bin"
  cp "$W/fake/bright.dtb" "$W/R5/dtb-p/t6050-k114s-r3b-brightness.dtb"; cp "$W/fake/pinldr-m1n1.bin" "$W/RT/aura-pin/m1n1.bin"
  cp "$W/fake/asahi-m1n1.bin" "$W/asahi/m1n1.bin"; cp "$W/fake/boot.bin" "$W/esp/m1n1/boot.bin"; cp "$W/fake/gpu.dtb" "$W/lib/k114s.dtb"; cp "$W/fake/gpu.dtb" "$W/esp/k114s-repair/k114s.dtb"
  rewrite < "$REPO_DIR/linux/update-boot-ctxr-k114s" > "$W/lib/update-boot-ctxr"; chmod +x "$W/lib/update-boot-ctxr"
  printf '#!/bin/sh\nprintf "IgnorePkg = %%s\\n" "$(tr "\\n" " " < %s/lib/holds.list)" > %s/pacman.conf\necho "k114s apply-holds: done"\n' "$W" "$W" > "$W/lib/apply-holds"; chmod +x "$W/lib/apply-holds"
  printf 'linux-aurora\nlinux-k114s\nlimine-mkinitcpio-hook\nlimine-snapper-sync\nm1n1-aurora\nuboot-aurora\n' > "$W/lib/holds.list"
  printf 'IgnorePkg = linux-aurora linux-k114s limine-mkinitcpio-hook limine-snapper-sync m1n1-aurora uboot-aurora\n' > "$W/pacman.conf"
  mkdir -p "$W/mkinitcpio.conf.d"; cp "$REPO_DIR/linux/99-k114s-no-appledrm.conf" "$W/mkinitcpio.conf.d/"   # G6a's drop-in, installed
  mkdir -p "$W/icroot/etc"; ln -sfn "$W/mkinitcpio.conf.d" "$W/icroot/etc/mkinitcpio.conf.d"   # the installer's K114S_ROOT view of it
  echo 'K114s: old chain' > "$W/macboot/owner-boot-chain"
  printf 'repair block\n' > "$W/esp/k114s-repair/promotion/repair-block.conf"; cp "$REPO_DIR/macos/tools/k114s_repair.py" "$W/esp/k114s-repair/promotion/k114s_repair.py"
  echo record > "$W/esp/k114s-repair/r2c/repair-uki.txt"
  printf 'options appledrm fw27_panel_vrr=1\n' > "$W/usrmodprobe/aurora-m5-vrr.conf"; printf 'options appledrm fw27_panel_vrr=0\n' > "$W/modprobe/aurora-m5-vrr.conf"
  mkdir -p "$W/systemd/systemd-backlight@backlight:apple-panel-bl.service.d"; cp "$REPO_DIR/linux/brightness/systemd/k114s-first-boot.conf" "$W/systemd/systemd-backlight@backlight:apple-panel-bl.service.d/"
  printf 'hl.monitor({ output = "eDP-2", mode = "preferred", position = "auto", scale = 2 })\n' >> "$W/home/.config/hypr/monitors.lua"
  HOME=$W/home bash "$REPO_DIR/linux/display/k114s-dcp-colour" >/dev/null   # the DCP colour fix (section 4a), as the root installs it before boot 1
  rm -rf "$W/sddm"; mkdir -p "$W/sddm/usr/share/sddm" "$W/sddm/etc/sddm.conf.d"; printf -- '-- stock greeter\n' > "$W/sddm/usr/share/sddm/hyprland.lua"
  cp "$REPO_DIR/linux/gpu-desktop/70-k114s-greeter-software.conf" "$W/sddm/etc/sddm.conf.d/"; K114S_SDDM_ROOT=$W/sddm bash "$REPO_DIR/linux/display/k114s-greeter-colour" >/dev/null   # the greeter's guard, as the root installs it
  echo 500 > "$BLD/brightness"; echo 500 > "$BLD/actual_brightness"; echo 1000 > "$BLD/max_brightness"; echo platform > "$BLD/type"; echo linear > "$BLD/scale"; : > "$BLD/writes.log"
  echo 1 > "$W/vrrcap"; echo Y > "$W/sys/module/appledrm/parameters/fw27_panel_vrr"
  echo '[    5.1] apple-drm display-subsystem: brightness requests below 10 nits are raised to 10 nits' > "$W/klog"
  echo '{"idle":{"lock":300,"screensaver":150}}' > "$W/home/.config/omarchy/shell.json"; rm -rf "$W/state"; mkdir -p "$W/state"
  printf '[0.1] FDT: GPU: firmware 26B8125\n' > "$DOLD/boot-20261115-191015-disp-pinldr/loader.log"; : > "$W/klog.empty"
  mkdir -p "$D"; unset FAKE_DMESG
}
gates() { mkdir -p "$D"; printf 'G0 confirmed: test\nG4 accepted: test\n' > "$D/gates.txt"; }
b1() { export FAKE_PKGVER=7.3.0.r3b.b1-1; }
session0() { # session 0 up to the stage given: w0 w1 i1b s5 (the gates record before I1b, as the runbook says)
  fresh2; run <<< "$bD9p" >/dev/null 2>&1; run <<< "$bW0"; [ "$1" = w0 ] && return; run <<< "$bW1"; [ "$1" = w1 ] && return
  gates; b1; run <<< "$bI1b"; [ "$1" = i1b ] && return; run <<< "$bS5"
  for i in 1 2 3; do echo "N boot$i acked test (the owner is reachable)" > "$D/N-acked-$i"; done   # the lead's record of Jarvis's acknowledgement of N
}
boot() { # boot RELEASE TRIAL ENTRY UNAME_V: what a reboot leaves; the snapshot sync is back until block F
  export FAKE_UNAME=$1 FAKE_UNAME_V=${4:-K114S-R3B-B1}; rm -f "$W/efivars/LoaderEntryOneShot-$BLI" "$W/state/sync-stopped"; : > "$W/esp/ubootefi.var"
  { printf '\007\000\000\000'; printf '%s' "$3" | iconv -t UTF-16LE; printf '\000\000'; } > "$W/efivars/LoaderEntrySelected-$BLI"
  if [ -n "$2" ]; then printf '%s\0' "$2" > "$W/chosen/aurora,trial"; sed -i 1s/.*/spent/ "$W/esp/aura-try"; else rm -f "$W/chosen/aurora,trial"; fi
  echo "boot-$RANDOM$RANDOM" > "$W/boot_id"; }
FR=$W/repo
# a root-only folder, as on the Mac: closed (mode 000) to the plain user, opened by the fake sudo for the commands it runs (the fake sudo opens the folders listed in rootdirs)
closed() { local d; for d in "$@"; do echo "$d" >> "$W/rootdirs"; chmod 000 "$d"; done; }
reopen() { local d; for d in "$@"; do chmod 700 "$d"; grep -v -x -F -- "$d" "$W/rootdirs" > "$W/rootdirs.n"; mv "$W/rootdirs.n" "$W/rootdirs"; done; }

# --- D9p: the macOS tool and the fallback tree onto the ESP ---------------------------------------------------------------------
fresh2; espb=$(espstate); run <<< "$bD9p"; p=$W/esp/k114s-repair/promotion
ok "D9p: exit 0; the new tool and P's tree are on the ESP by hash, the old tool kept beside, nothing else changed" \
  "$rc $(sum "$p/k114s_repair.py") $(sum "$p/k114s.dtb.gpu") $(cmp -s "$p/k114s_repair.py.p4b" "$espb.none" 2>/dev/null; test -s "$p/k114s_repair.py.p4b"; echo $?)" "0 $(sum "$REPO_DIR/macos/tools/k114s_repair.py") $(sum "$W/fake/gpu.dtb") 0"
ok "D9p: the repair block and the record are untouched, no temporary file is left, the tool's hash is printed" "$(sum "$p/repair-block.conf") $(find "$W/esp" -name '*.k114s-new' | wc -l) $(echo "$out" | grep -c "sha256 $(sum "$REPO_DIR/macos/tools/k114s_repair.py")")" "$(printf 'repair block\n' | sha256sum | cut -c1-64) 0 1"
ok "D9p: the repository's tool is kept in \$D with its hash" "$(sum "$D/k114s_repair.py") $(cat "$D/macos-tool.sha256")" "$(sum "$REPO_DIR/macos/tools/k114s_repair.py") $(sum "$REPO_DIR/macos/tools/k114s_repair.py")"
run <<< "$bD9p"; ok "D9p: a second run changes nothing and keeps the first old tool" "$rc $(sum "$p/k114s_repair.py.p4b")" "0 $(sum "$REPO_DIR/macos/tools/k114s_repair.py")"
fresh2; cp "$W/fake/bright.dtb" "$W/esp/k114s-repair/k114s.dtb"; before=$(state); run <<< "$bD9p"; ok "D9p: a pin that is not P's tree stops, nothing written" "$rc $(state)" "1 $before"
fresh2; printf 'x' > "$W/esp/m1n1/boot-ctxr-r3-gpu.bin"; before=$(state); run <<< "$bD9p"; ok "D9p: P's Stage 2 missing from m1n1/ stops" "$rc $(state)" "1 $before"
fresh2; printf '%s\0' m1n1/x.bin > "$W/chosen/aurora,trial"; run <<< "$bD9p"; ok "D9p: refused from a trial boot" "$rc" 1
fresh2; rm "$W/esp/k114s-repair/promotion/repair-block.conf"; run <<< "$bD9p"; ok "D9p: a promotion folder that is not as P0e left it stops" "$rc" 1

# --- the window with this window's record folder: W0, W1, I1b, S5 -----------------------------------------------------------------
fresh2; run <<< "$bW0"
ok "W0 with the new \$D: exit 0, the record and copies in display-d5, the first window's folder never touched" "$rc $(test -s "$D/before-window.txt"; echo $?) $(sum "$D/omarchy_linux-aurora.efi") $(ls "$DOLD" | tr '\n' ' ')" "0 0 $(sum "$W/fake/aurora.efi") boot-20261115-191015-disp-pinldr "
run <<< "$bW1"; ok "W1 with the new \$D: DISPLAY WINDOW OPEN" "$rc $(echo "$out" | grep -c 'W1: DISPLAY WINDOW OPEN') $(test -e "$D/window-open"; echo $?)" "0 1 0"
fresh2; run <<< "$bI1b"; ok "I1b: refused before W1 (the window is not open), nothing installed" "$rc $(test -e "$W/state/r3b"; echo $?)" "1 1"
session0 w1; b1; run <<< "$bI1b"
ok "I1b: exit 0, G3 and G6 pass" "$rc $(echo "$out" | grep -c '^I1b: r3b.b1 installed beside r3a; G3 and G6 pass')" "0 1"
ok "I1b: version b1 installed, the r3b image and entry added, r3a's and the default unchanged" \
  "$(cat "$W/state/r3b") $(test -s "$W/esp/EFI/Linux/omarchy_linux-k114s-r3b.efi"; echo $?) $(grep -c -x '  //linux-k114s-r3b' "$W/esp/limine.conf") $(sum "$W/esp/EFI/Linux/omarchy_linux-k114s.efi") $(sed -n 's/^default_entry: //p' "$W/esp/limine.conf")" \
  "7.3.0.r3b.b1-1 0 1 $(sum "$W/fake/r3a.efi") Omarchy/linux-k114s"
ok "I1b: the package and the install log are in \$D, limine.conf as I1b left it is kept for block Xs and D9c, the command line is never printed" \
  "$(sum "$D/linux-k114s-r3b-7.3.0.r3b.b1-1-aarch64.pkg.tar.zst") $(cmp -s "$D/limine.conf.after-r3b" "$W/esp/limine.conf"; echo $?) $(echo "$out" | grep -c 'root=UUID')" "$(sum "$W/fake/r3b1.pkg") 0 0"
ok "I1b: the configured Stage 2 and both pins are still P's" "$(sum "$W/esp/m1n1/boot-ctxr.bin") $(sum "$W/esp/k114s-repair/k114s.dtb")" "$(sum "$W/fake/gpu.bin") $(sum "$W/fake/gpu.dtb")"
run <<< "$bP"; ok "P (first runbook) holds with r3b installed in this window" "$rc $(echo "$out" | grep -c 'window open, r3b installed')" "0 1"
session0 w1; b1; FAKE_HOOK=full run <<< "$bI1b"; ok "I1b: a hook that builds two images stops" "$rc $(echo "$out" | grep -c 'did not build exactly one image')" "1 1"
session0 w1; b1; FAKE_INITRD=appledrm run <<< "$bI1b"; ok "I1b: appledrm in the initramfs stops (G6)" "$rc $(echo "$out" | grep -c 'appledrm is in r3b')" "1 1"
session0 w1; b1; FAKE_CHECK=FAILED run <<< "$bI1b"; ok "I1b: a failing check-package stops before the install" "$rc $(test -e "$W/state/r3b"; echo $?)" "1 1"
session0 w1; run <<< "$bI1b"; ok "I1b: a transaction that would install the older version (7.3.0.r3b-1) stops before the install" "$rc $(test -e "$W/state/r3b"; echo $?)" "1 1"
session0 w1; b1; cp "$W/fake/r3b.pkg" "$W/R5/pkg/linux-k114s-r3b-7.3.0.r3b.b1-1-aarch64.pkg.tar.zst"; run <<< "$bI1b"; ok "I1b: a package that is not 0ca7b759 stops" "$rc $(test -e "$W/state/r3b"; echo $?)" "1 1"
session0 w1; b1; rm "$W/state/sync-stopped"; run <<< "$bI1b"; ok "I1b: refused while the snapshot sync runs" "$rc $(test -e "$W/state/r3b"; echo $?)" "1 1"
session0 i1b; run <<< "$bS5"
ok "S5: the three inputs in \$D and the Stage 2 on the ESP, each by hash; no temporary file" \
  "$rc $(sum "$D/boot-ctxr-disp-bl.bin") $(sum "$D/k114s.dtb.bright") $(sum "$D/m1n1-pin.bin") $(sum "$W/esp/m1n1/boot-ctxr-disp-bl.bin") $(find "$W/esp" -name '*.k114s-new' | wc -l)" \
  "0 $(sum "$W/fake/d5.bin") $(sum "$W/fake/bright.dtb") $(sum "$W/fake/pinldr-m1n1.bin") $(sum "$W/fake/d5.bin") 0"
session0 w1; before=$(state); run <<< "$bS5"; ok "S5: refused before I1b" "$rc $(state)" "1 $before"
session0 i1b; echo junk > "$W/R5/stage2/boot-ctxr-disp-bl.bin"; run <<< "$bS5"; ok "S5: a Stage 2 that is not the built one stops, nothing on the ESP" "$rc $(test -e "$W/esp/m1n1/boot-ctxr-disp-bl.bin"; echo $?)" "1 1"

# --- T3a: the arm, VRR masked --------------------------------------------------------------------------------------------------
session0 s5; run <<< "$bT3a"
ok "T3a: exit 0, the one-shot names r3b, aura-try armed for the D5 file, the reboot scheduled with systemd-run (never systemctl reboot)" \
  "$rc $(tail -c +5 "$W/efivars/LoaderEntryOneShot-$BLI" | iconv -f UTF-16LE -t UTF-8 | tr -d '\0') $(sed -n 1,2p "$W/esp/aura-try" | tr '\n' ' ')$(grep -c '^reboot-scheduled --on-active=15s --unit=k114s-d5-reboot systemctl reboot' "$W/calls") $(grep -c '^reboot' "$W/calls")" \
  "0 Omarchy.linux-k114s-r3b armed m1n1/boot-ctxr-disp-bl.bin 1 1"
ok "T3a: the configured Stage 2, the pins, default_entry and the mask are untouched" "$(sum "$W/esp/m1n1/boot-ctxr.bin") $(sed -n 's/^default_entry: //p' "$W/esp/limine.conf") $(grep -c 'fw27_panel_vrr=0' "$W/modprobe/aurora-m5-vrr.conf")" "$(sum "$W/fake/gpu.bin") Omarchy/linux-k114s 1"
session0 s5; rm "$D/gates.txt"; run <<< "$bT3a"; ok "T3a: without the gates record nothing is armed" "$rc $(ls "$W/efivars" | grep -c LoaderEntryOneShot)" "1 0"
session0 s5; rm "$W/modprobe/aurora-m5-vrr.conf"; run <<< "$bT3a"; ok "T3a: without the mask (the first window's I0) nothing is armed" "$rc $(ls "$W/efivars" | grep -c LoaderEntryOneShot)" "1 0"
session0 s5; rm -r "$W/systemd/systemd-backlight@backlight:apple-panel-bl.service.d"; run <<< "$bT3a"; ok "T3a: without the brightness drop-in nothing is armed" "$rc $(echo "$out" | grep -c 'drop-in is not installed')" "1 1"
session0 s5; mkdir -p "$W/klb"; : > "$W/klb/restore-enabled"; run <<< "$bT3a"; ok "T3a: with brightness restore turned on nothing is armed" "$rc $(echo "$out" | grep -c 'restore is turned on')" "1 1"
session0 s5; echo 7.3.0.r3b-1 > "$W/state/r3b"; run <<< "$bT3a"; ok "T3a: the older r3b package installed stops (it is not b1)" "$rc $(ls "$W/efivars" | grep -c LoaderEntryOneShot)" "1 0"
session0 s5; run <<< "$bT3a"; ok "T3a: the stay-awake mode is on and what it was is kept" "$rc $(test -e "$W/state/stay-awake"; echo $?) $(cat "$D/idle-before")" "0 0 false"
session0 s5; : > "$W/state/stay-awake"; run <<< "$bT3a"; ok "T3a: a stay-awake mode that was on already (this Mac: the owner's own setting) is recorded as true and stays on" "$rc $(cat "$D/idle-before") $(test -e "$W/state/stay-awake"; echo $?)" "0 true 0"
session0 s5; rm "$D/N-acked-1"; run <<< "$bT3a"; ok "T3a: without the acknowledgement of N (N-acked-1) nothing is armed and no reboot is scheduled" "$rc $(echo "$out" | grep -c 'N-acked-1') $(ls "$W/efivars" | grep -c LoaderEntryOneShot) $(grep -c 'k114s-d5-reboot' "$W/calls" 2>/dev/null)" "1 1 0 0"
session0 s5; FAKE_IDLEFAIL=1 run <<< "$bT3a"; ok "T3a: a stay-awake mode that does not turn on stops, nothing armed" "$rc $(ls "$W/efivars" | grep -c LoaderEntryOneShot) $(sed -n 1p "$W/esp/aura-try")" "1 0 spent"
session0 s5; echo junk >> "$W/esp/m1n1/boot-ctxr-disp-bl.bin"; run <<< "$bT3a"; ok "T3a: a trial file that is not the D5 Stage 2 stops" "$rc $(ls "$W/efivars" | grep -c LoaderEntryOneShot)" "1 0"
session0 s5; sed -i '/eDP-2/d' "$W/home/.config/hypr/monitors.lua"; run <<< "$bT3a"; ok "T3a: without the eDP-2 rule nothing is armed" "$rc $(echo "$out" | grep -c 'eDP-1 and eDP-2 rules')" "1 1"
session0 s5; rm "$W/home/.config/hypr/monitors.lua.k114s-dcp-colour.bak"; HOME=$W/home bash "$REPO_DIR/linux/display/k114s-dcp-colour" --undo >/dev/null; run <<< "$bT3a"; ok "T3a: without the DCP colour fix in monitors.lua nothing is armed" "$rc $(echo "$out" | grep -c 'DCP colour fix') $(ls "$W/efivars" | grep -c LoaderEntryOneShot)" "1 1 0"
session0 s5; run <<< "$bT3a"; before=$(espstate); run <<< "$bT3a"; ok "T3a: a second arm while armed stops, aura-try unchanged" "$rc $(sed -n 1p "$W/esp/aura-try")" "1 armed"

# --- the T3 boot: block F, T3b, then D5, D7, D7b, D8 ---------------------------------------------------------------------------
t3boot() { session0 s5; run <<< "$bT3a"; boot $REL m1n1/boot-ctxr-disp-bl.bin Omarchy.linux-k114s-r3b; mkdir -p "$DOLD/boot-20261115-191015-disp-pinldr"; run <<< "$bF"; }
t3boot; ok "F: the folder is named for the trial and the sync is held off again" "$rc $(basename "$(cat "$D/last-boot")" | sed 's/.*-//') $(test -e "$W/state/sync-stopped"; echo $?)" "0 bl 0"
: > "$W/calls"; FAKE_REPO=$FR run <<< "$bT3b"
ok "T3b: passes with --expect published --floor, finds the first window's T2 loader log, writes T3-booted" \
  "$rc $(grep -c 'display-check --expect published --floor' "$W/calls") $(echo "$out" | grep -c "ok    the loader's GPU lines equal the first window's T2") $(test -s "$D/T3-booted"; echo $?)" "0 1 1 0"
boot $REL m1n1/boot-ctxr-disp-bl.bin Omarchy.linux-k114s-r3b; FAKE_REPO=$FR run <<< "$bT3b"; ok "T3b: refused before block F has run in this boot" "$rc $(echo "$out" | grep -c 'block F has not run')" "1 1"
t3boot; FAKE_UNAME_V=K114S-R3B FAKE_REPO=$FR run <<< "$bT3b"; ok "T3b: a kernel that is not the brightness build stops" "$rc $(echo "$out" | grep -c 'not the brightness build')" "1 1"
t3boot; FAKE_REPO=$FR FAKE_DCHECK=BAD run <<< "$bT3b"; ok "T3b: a BAD from the display check stops and writes no marker" "$rc $(test -e "$D/T3-booted"; echo $?)" "1 1"
t3boot; rm "$W/chosen/aurora,trial"; FAKE_REPO=$FR run <<< "$bT3b"; ok "T3b: no trial in this boot (the Stage 2 hung once: r3b.b1 on P) stops and names D5a" "$rc $(echo "$out" | grep -c 'D5a')" "1 1"
t3boot; rm -rf "$DOLD/boot-20261115-191015-disp-pinldr"; FAKE_REPO=$FR run <<< "$bT3b"; ok "T3b: without the first window's T2 log it still passes (info only)" "$rc $(echo "$out" | grep -c 'no first-window T2')" "0 1"

t3ok() { t3boot; FAKE_REPO=$FR run <<< "$bT3b"; }
t3ok; FAKE_REPO=$FR run <<< "$bD5"
ok "D5: exit 0, D5-passed and the pending owner line written, the level back at the start" "$rc $(test -s "$D/D5-passed"; echo $?) $(grep -c 'owner-look D5 PENDING' "$D/owner-look.txt") $(cat "$BLD/brightness") $(cat "$BLD/actual_brightness")" "0 0 1 500 500"
ok "D5: the ladder (down to the floor and back) and the Omarchy steps, never below 10 nits and never 0, and no 1000" \
  "$(tr '\n' ' ' < "$BLD/writes.log") $(echo "$out" | grep -c '^the Omarchy steps: 500 450 400 450 500 nits')" "500 250 100 50 20 10 20 50 100 250 500  1"
ok "D5: the read-only report and every ladder line are printed (the stepped run prints the floor line again in its own header)" "$(echo "$out" | grep -c 'kernel applies it   yes') $(echo "$out" | grep -c 'agent ladder): brightness')" "2 10"
t3ok; rm "$W/klog"; FAKE_REPO=$FR run <<< "$bD5"; ok "D5: no floor line in the kernel log: no write at all" "$rc $(test -s "$BLD/writes.log"; echo $?) $(test -e "$D/D5-passed"; echo $?)" "1 1 1"
t3ok; FAKE_REPO=$FR FAKE_NOSTEP=1 run <<< "$bD5"; ok "D5: Omarchy steps that do not move the level stop, the start level is back, no marker" "$rc $(cat "$BLD/brightness") $(test -e "$D/D5-passed"; echo $?)" "1 500 1"
t3ok; echo 1200 > "$BLD/max_brightness"; FAKE_REPO=$FR run <<< "$bD5"; ok "D5: another scale than 1000 stops before any write" "$rc $(test -s "$BLD/writes.log"; echo $?)" "1 1"
t3ok; rm "$D/T3-booted"; FAKE_REPO=$FR run <<< "$bD5"; ok "D5: refused without T3-booted" "$rc" 1
t3ok; FAKE_UNAME_V=K114S-R3B FAKE_REPO=$FR run <<< "$bD5"; ok "D5: refused on a kernel that is not the brightness build" "$rc $(test -s "$BLD/writes.log"; echo $?)" "1 1"
t3ok; FAKE_REPO=$FR FAKE_DCHECK=BAD run <<< "$bD5"; ok "D5: a BAD from the display check after the writes stops, no marker" "$rc $(test -e "$D/D5-passed"; echo $?)" "1 1"
# a ladder that stops must stop D5 and write no marker (the checker's own status, not tee's): a read-back of 77 after the write of 100
sed 's#echo "$1" >"$p/actual_brightness"#echo "$(( $1 == 100 ? 77 : $1 ))" >"$p/actual_brightness"#' "$REPO_DIR/linux/brightness/k114s-backlight-check" > "$W/bl-bad"
t3ok; FAKE_BLTOOL=$W/bl-bad FAKE_REPO=$FR run <<< "$bD5"
ok "D5: a ladder whose read-back differs (77 after 100) stops D5, puts 500 back and writes no D5-passed and no owner line" "$rc $(echo "$out" | grep -c 'agent ladder stopped at 100') $(echo "$out" | grep -c 'the stepped check stopped') $(cat "$BLD/brightness") $(test -e "$D/D5-passed"; echo $?) $(test -e "$D/owner-look.txt"; echo $?)" "1 1 1 500 1 1"
t3ok; chmod 444 "$BLD/brightness"; FAKE_REPO=$FR run <<< "$bD5"; chmod 644 "$BLD/brightness"
ok "D5: a write that fails stops D5 (WRITE FAILED) and writes no D5-passed" "$rc $(echo "$out" | grep -c 'WRITE FAILED') $(test -e "$D/D5-passed"; echo $?)" "1 1 1"
t3ok; : > "$W/state/locked"; FAKE_REPO=$FR run <<< "$bD5"; ok "D5: a locked session stops before any write" "$rc $(test -s "$BLD/writes.log"; echo $?) $(test -e "$D/D5-passed"; echo $?)" "1 1 1"

t3ok; FAKE_REPO=$FR run <<< "$bD5"; run <<< "$bD7"
ok "D7: exit 0, three off/on cycles, the level kept, D7-passed and the pending owner question (black or dim) written" "$rc $(echo "$out" | grep -c '^cycle . off:') $(cat "$BLD/brightness") $(test -s "$D/D7-passed"; echo $?) $(grep -c 'BLACK or only dim' "$D/owner-look.txt")" "0 3 500 0 1"
t3ok; FAKE_REPO=$FR run <<< "$bD5"; : > "$W/state/locked"; run <<< "$bD7"; ok "D7: a locked session stops before DPMS is touched, no marker" "$rc $(test -e "$W/state/dpms-off"; echo $?) $(test -e "$D/D7-passed"; echo $?)" "1 1 1"
t3ok; run <<< "$bD7"; ok "D7: refused without D5" "$rc $(test -e "$W/state/dpms-off"; echo $?)" "1 1"
t3ok; FAKE_REPO=$FR run <<< "$bD5"; FAKE_NOWAKE=1 run <<< "$bD7"; ok "D7: a panel that does not wake stops and writes no marker" "$rc $(echo "$out" | grep -c 'did not wake') $(test -e "$D/D7-passed"; echo $?)" "1 1 1"
t3ok; FAKE_REPO=$FR run <<< "$bD5"; echo '[   9.0] apple-drm: DCP has crashed' > "$W/dm"; FAKE_DMESG=$W/dm run <<< "$bD7"; ok "D7: a DCP crash line after the cycles stops" "$rc $(test -e "$D/D7-passed"; echo $?)" "1 1"
t3ok; FAKE_REPO=$FR run <<< "$bD5"; run <<< "$bD7"; run <<< "$bD7b"
ok "D7b: the idle profile is 60 and 120 seconds, the old file kept, the JSON still valid" "$rc $(jq -c '.idle' "$W/home/.config/omarchy/shell.json") $(jq -c '.idle' "$W/home/.config/omarchy/shell.json.bak.d7") $(ls "$W/home/.config/omarchy" | grep -c XXXX)" '0 {"lock":120,"screensaver":60} {"lock":300,"screensaver":150} 0'
t3ok; run <<< "$bD7b"; ok "D7b: refused without D7" "$rc $(jq -c '.idle' "$W/home/.config/omarchy/shell.json")" '1 {"lock":300,"screensaver":150}'
t3ok; FAKE_REPO=$FR run <<< "$bD5"; run <<< "$bD7"; echo 'not json' > "$W/home/.config/omarchy/shell.json"; run <<< "$bD7b"; ok "D7b: a shell.json that is not JSON stops, nothing changed" "$rc $(cat "$W/home/.config/omarchy/shell.json")" "1 not json"
t3ok; FAKE_REPO=$FR run <<< "$bD5"; run <<< "$bD7"; run <<< "$bD8"
ok "D8: exit 0, night light on at 4000 K and off again, CTM listed, D8-passed written" "$rc $(echo "$out" | grep -c 'CTM listed on 1') $(test -s "$D/D8-passed"; echo $?) $(test -e "$W/state/night"; echo $?)" "0 1 0 1"
t3ok; FAKE_REPO=$FR run <<< "$bD5"; run <<< "$bD7"; : > "$W/state/locked"; run <<< "$bD8"; ok "D8: a locked session stops, night light untouched" "$rc $(test -e "$W/state/night"; echo $?)" "1 1"
t3ok; run <<< "$bD8"; ok "D8: refused without D7" "$rc $(test -e "$W/state/night"; echo $?)" "1 1"
t3ok; FAKE_REPO=$FR run <<< "$bD5"; run <<< "$bD7"; FAKE_NIGHTFAIL=1 run <<< "$bD8"; ok "D8: a toggle that does not reach 4000 K stops, no marker" "$rc $(test -e "$D/D8-passed"; echo $?)" "1 1"
t3ok; FAKE_REPO=$FR run <<< "$bD5"; run <<< "$bD7"; : > "$W/state/night"; run <<< "$bD8"; ok "D8: night light already on is not toggled blind" "$rc $(echo "$out" | grep -c 'on already')" "1 1"

# --- T4a: drop the mask, arm ----------------------------------------------------------------------------------------------------
alld57() { t3ok; FAKE_REPO=$FR run <<< "$bD5"; run <<< "$bD7"; run <<< "$bD8"; run <<< "$bG6b"; }
alld57; FAKE_UNAME=$REL run <<< "$bT4a"
ok "T4a: exit 0, the mask is out and its copy kept, the one-shot names r3b, aura-try armed for the same file, the reboot scheduled" \
  "$rc $(test -e "$W/modprobe/aurora-m5-vrr.conf"; echo $?) $(grep -c 'fw27_panel_vrr=0' "$D/aurora-m5-vrr.conf.masked") $(tail -c +5 "$W/efivars/LoaderEntryOneShot-$BLI" | iconv -f UTF-16LE -t UTF-8 | tr -d '\0') $(sed -n 1,2p "$W/esp/aura-try" | tr '\n' ' ')$(grep -c 'unit=k114s-d6-reboot' "$W/calls")" \
  "0 1 1 Omarchy.linux-k114s-r3b armed m1n1/boot-ctxr-disp-bl.bin 1"
alld57; rm "$D/N-acked-2"; FAKE_UNAME=$REL run <<< "$bT4a"; ok "T4a: without the acknowledgement of N (N-acked-2) nothing is armed, the mask stays and no reboot is scheduled" "$rc $(echo "$out" | grep -c 'N-acked-2') $(ls "$W/efivars" | grep -c LoaderEntryOneShot) $(test -e "$W/modprobe/aurora-m5-vrr.conf"; echo $?)" "1 1 0 0"
alld57; rm "$D/D7-passed"; FAKE_UNAME=$REL run <<< "$bT4a"; ok "T4a: without D7 nothing is armed and the mask stays" "$rc $(test -e "$W/modprobe/aurora-m5-vrr.conf"; echo $?) $(ls "$W/efivars" | grep -c LoaderEntryOneShot)" "1 0 0"
alld57; rm "$W/home/.config/hypr/monitors.lua.k114s-dcp-colour.bak"; HOME=$W/home bash "$REPO_DIR/linux/display/k114s-dcp-colour" --undo >/dev/null; FAKE_UNAME=$REL run <<< "$bT4a"; ok "T4a: without the DCP colour fix nothing is armed and the mask stays" "$rc $(echo "$out" | grep -c 'DCP colour fix') $(test -e "$W/modprobe/aurora-m5-vrr.conf"; echo $?)" "1 1 0"
alld57; : > "$W/usrmodprobe/aurora-m5-vrr.conf"; FAKE_UNAME=$REL run <<< "$bT4a"; ok "T4a: an installed aurora-m5-vrr.conf that is not the J714s file stops, the mask stays" "$rc $(test -e "$W/modprobe/aurora-m5-vrr.conf"; echo $?)" "1 0"
alld57; printf 'options appledrm fw27_panel_vrr=1\n# x\n' > "$W/modprobe/aurora-m5-vrr.conf"; FAKE_UNAME=$REL run <<< "$bT4a"; ok "T4a: a file that is not the mask is not touched" "$rc $(grep -c '# x' "$W/modprobe/aurora-m5-vrr.conf")" "1 1"
alld57; run <<< "$bT4a"; ok "T4a: a second run after the mask is gone re-arms from the kept copy (the mask file stays out)" "$rc $(test -e "$W/modprobe/aurora-m5-vrr.conf"; echo $?)" "0 1"

# --- the T4 boot: F, T4b, D6 ---------------------------------------------------------------------------------------------------
t4boot() { alld57; FAKE_UNAME=$REL run <<< "$bT4a"; boot $REL m1n1/boot-ctxr-disp-bl.bin Omarchy.linux-k114s-r3b; run <<< "$bF"; FAKE_REPO=$FR run <<< "$bT4b"; }
: > "$W/calls"; t4boot; ok "T4b: passes with --vrr on and --floor, compares with T3's loader log, writes T4-booted" "$rc $(grep -c 'display-check --expect published --floor --vrr on' "$W/calls") $(echo "$out" | grep -c "ok    the loader's GPU lines equal T3's") $(test -s "$D/T4-booted"; echo $?)" "0 1 1 0"
alld57; FAKE_UNAME=$REL run <<< "$bT4a"; boot $REL m1n1/boot-ctxr-disp-bl.bin Omarchy.linux-k114s-r3b; FAKE_REPO=$FR run <<< "$bT4b"; ok "T4b: refused before block F has run in this boot" "$rc" 1
t4boot; FAKE_REPO=$FR run <<< "$bD6"
ok "D6: exit 0, the ladder again, VRR on then off, D6-passed and the pending owner line written, VRR left off" "$rc $(test -s "$D/D6-passed"; echo $?) $(test -e "$W/state/vrr"; echo $?) $(grep -c 'owner-look D6 PENDING' "$D/owner-look.txt") $(cat "$BLD/brightness")" "0 0 1 1 500"
t4boot; echo 0 > "$W/vrrcap"; FAKE_REPO=$FR run <<< "$bD6"; ok "D6: vrr_capable 0 stops before VRR is touched and writes no D6-failed (nothing was tried)" "$rc $(test -e "$D/D6-failed"; echo $?) $(test -e "$W/state/vrr"; echo $?)" "1 1 1"
t4boot; echo N > "$W/sys/module/appledrm/parameters/fw27_panel_vrr"; FAKE_REPO=$FR run <<< "$bD6"; ok "D6: fw27_panel_vrr N stops" "$rc" 1
t4boot; FAKE_VRRFAIL=1 FAKE_REPO=$FR run <<< "$bD6"; ok "D6: Hyprland that does not turn VRR on: D6-failed is written and VRR is off" "$rc $(test -s "$D/D6-failed"; echo $?) $(test -e "$D/D6-passed"; echo $?) $(test -e "$W/state/vrr"; echo $?)" "1 0 1 1"
t4boot; printf '[  9.0] apple-drm: adaptive swap timed out, restoring fixed refresh\n' > "$W/dm"; FAKE_DMESG=$W/dm FAKE_REPO=$FR run <<< "$bD6"; ok "D6: a swap-watchdog line that was in the log before the test is not counted against it (the block compares counts)" "$rc" 0
# a dmesg that logs the watchdog line each time it is read while VRR is on
t4boot; printf '#!/bin/sh\n[ -e "%s/state/vrr" ] && echo "[  9.0] apple-drm: adaptive swap timed out" >> "%s/dm2"\ncat "%s/dm2" 2>/dev/null\necho "[    1.000000] aurora: GPU firmware build: 26B8125"\n' "$W" "$W" "$W" > "$BIN/dmesg"; chmod +x "$BIN/dmesg"; FAKE_REPO=$FR run <<< "$bD6"
ok "D6: a swap-watchdog line that appears while VRR is on stops and writes D6-failed" "$rc $(test -s "$D/D6-failed"; echo $?)" "1 0"
printf '#!/bin/sh\ncat "${FAKE_DMESG:-/dev/null}" 2>/dev/null\necho "[    1.000000] aurora: GPU firmware build: 26B8125 for T6050 G17S, primary then secondary"\n' > "$BIN/dmesg"; chmod +x "$BIN/dmesg"
alld57; FAKE_REPO=$FR run <<< "$bD6"; ok "D6: refused without T4-booted" "$rc" 1
t4boot; : > "$W/state/locked"; FAKE_REPO=$FR run <<< "$bD6"; ok "D6: a locked session stops before VRR is touched and records no D6-failed or D6-passed" "$rc $(test -e "$W/state/vrr"; echo $?) $(test -e "$D/D6-failed"; echo $?) $(test -e "$D/D6-passed"; echo $?)" "1 1 1 1"
t3ok; FAKE_REPO=$FR run <<< "$bD5"; run <<< "$bD7"; run <<< "$bD8"; run <<< "$bG6b"
ok "G6b: a build from the display-tree boot without appledrm writes G6b-passed and leaves no temporary folder" "$rc $(test -s "$D/G6b-passed"; echo $?) $(ls "$W/vartmp" | wc -l)" "0 0 0"
t3ok; rm "$W/mkinitcpio.conf.d/99-k114s-no-appledrm.conf"; run <<< "$bG6b"; ok "G6b: without the drop-in installed it stops before any build and names G6a" "$rc $(echo "$out" | grep -c 'G6a') $(test -e "$D/G6b-passed"; echo $?) $(ls "$W/vartmp" | wc -l)" "1 1 1 0"
t3ok; echo '# old' > "$W/mkinitcpio.conf.d/99-k114s-no-appledrm.conf"; run <<< "$bG6b"; ok "G6b: a drop-in that is not the repository's file stops too" "$rc $(test -e "$D/G6b-passed"; echo $?)" "1 1"
t3ok; echo old > "$D/G6b-failed"; run <<< "$bG6b"; ok "G6b: a pass removes an earlier G6b-failed" "$rc $(test -e "$D/G6b-failed"; echo $?)" "0 1"
rm -f "$W/mkinitcpio.conf.d/99-k114s-no-appledrm.conf"; t3ok; K114S_ROOT=$W/icroot run <<< "$bG6a"; ok "G6a: installs the repository's drop-in (through the installer script) and says so" "$rc $(cmp -s "$REPO_DIR/linux/99-k114s-no-appledrm.conf" "$W/mkinitcpio.conf.d/99-k114s-no-appledrm.conf"; echo $?) $(echo "$out" | grep -c '^G6a: ')" "0 0 1"
K114S_ROOT=$W/icroot run <<< "$bG6a"; ok "G6a: a second run changes nothing" "$rc" 0
t3ok; FAKE_INITRD=appledrm run <<< "$bG6b"; ok "G6b: appledrm in the test initramfs writes G6b-failed and no G6b-passed (D9 stays blocked)" "$rc $(test -s "$D/G6b-failed"; echo $?) $(test -e "$D/G6b-passed"; echo $?)" "1 0 1"
t3ok; rm -rf "$W/sys/class/drm/card2-eDP-1"; run <<< "$bG6b"; ok "G6b: a boot with no eDP connector stops (it would prove nothing)" "$rc $(test -e "$D/G6b-passed"; echo $?)" "1 1"

# --- D9a: the gate and the proof --------------------------------------------------------------------------------------------------
ready() { # everything D9a needs: T4 booted, D6 passed, M9 recorded for the staged tool
  t4boot; FAKE_REPO=$FR run <<< "$bD6"
  echo "M9 passed: tool $(sum "$W/esp/k114s-repair/promotion/k114s_repair.py")" > "$D/M9-passed"; }
ready; run <<< "$bD9a"
ok "D9a: exit 0, D6 and D8 outcomes shown, D9a-passed written" "$rc $(echo "$out" | grep -c '^D6: passed') $(echo "$out" | grep -c '^D8: passed') $(test -e "$D/D9a-passed"; echo $?)" "0 1 1 0"
ok "D9a: the real Stage 2 hook, in a throw-away root, wrote the D9 file byte for byte (that is what it checks), and wrote nothing on the fake ESP" "$(echo "$out" | grep -c '^D9a: ') $(sum "$W/esp/m1n1/boot-ctxr.bin")" "1 $(sum "$W/fake/gpu.bin")"
ready; rm "$D/G6b-passed"; run <<< "$bD9a"; ok "D9a: without G6b-passed it stops" "$rc $(test -e "$D/D9a-passed"; echo $?)" "1 1"
ready; rm "$W/mkinitcpio.conf.d/99-k114s-no-appledrm.conf"; run <<< "$bD9a"; ok "D9a: without the no-appledrm drop-in installed it stops" "$rc $(echo "$out" | grep -c 'G6a') $(test -e "$D/D9a-passed"; echo $?)" "1 1 1"
ready; rm "$W/home/.config/hypr/monitors.lua.k114s-dcp-colour.bak"; HOME=$W/home bash "$REPO_DIR/linux/display/k114s-dcp-colour" --undo >/dev/null; run <<< "$bD9a"; ok "D9a: without the DCP colour fix it stops" "$rc $(echo "$out" | grep -c 'DCP colour fix') $(test -e "$D/D9a-passed"; echo $?)" "1 1 1"
ready; rm "$D/M9-passed"; run <<< "$bD9a"; ok "D9a: without M9-passed it stops" "$rc $(test -e "$D/D9a-passed"; echo $?)" "1 1"
ready; echo "M9 passed: tool 0000" > "$D/M9-passed"; run <<< "$bD9a"; ok "D9a: an M9 record that names another tool stops" "$rc $(echo "$out" | grep -c 'name the tool now staged')" "1 1"
ready; rm "$D/D6-passed"; run <<< "$bD9a"; ok "D9a: no outcome for D6 stops; D6-skipped is accepted" "$rc $(echo "$out" | grep -c 'no outcome recorded for D6')" "1 1"
echo skipped > "$D/D6-skipped"; run <<< "$bD9a"; ok "D9a: D6-skipped is an outcome" "$rc $(echo "$out" | grep -c '^D6: skipped')" "0 1"
ready; rm "$D/D7-passed"; run <<< "$bD9a"; ok "D9a: without D7-passed it stops (the lock screen blanks the display)" "$rc" 1
ready; rm "$D/T4-booted"; run <<< "$bD9a"; ok "D9a: without the second clean boot (T4-booted) it stops" "$rc" 1
ready; cp "$W/fake/ptree.dtb" "$W/R5/dtb-p/x"; echo junk >> "$D/m1n1-pin.bin"; run <<< "$bD9a"; ok "D9a: an input in \$D that is not the expected file stops" "$rc" 1
ready; cp "$W/fake/asahi-m1n1.bin" "$D/m1n1-pin.bin"; printf '%s\n' "$(sum "$W/fake/asahi-m1n1.bin")" > /dev/null; run <<< "$bD9a"; ok "D9a: a loader that is not the pin loader stops" "$rc" 1

# --- D9c: the promotion, its P9 check, its undo --------------------------------------------------------------------------------
promote() { ready; run <<< "$bD9a"; FAKE_UNAME=$REL run <<< "$bD9c"; }
promote
ok "D9c: exit 0, the last line says the reboot" "$rc $(echo "$out" | grep -c '^D9c: default Omarchy/linux-k114s-r3b')" "0 1"
ok "D9c: the Stage 2 is the D9 file, both pins the brightness tree, the pin loader in m1n1-ctxr.bin, the trial copy gone" \
  "$(sum "$W/esp/m1n1/boot-ctxr.bin") $(sum "$W/esp/k114s-repair/k114s.dtb") $(sum "$W/lib/k114s.dtb") $(sum "$W/asahi/m1n1-ctxr.bin") $(test -e "$W/esp/m1n1/boot-ctxr-disp-bl.bin"; echo $?)" \
  "$(sum "$W/fake/d5.bin") $(sum "$W/fake/bright.dtb") $(sum "$W/fake/bright.dtb") $(sum "$W/fake/pinldr-m1n1.bin") 1"
ok "D9c: default_entry is the r3b path and nothing else in limine.conf changed" "$(sed -n 's/^default_entry: //p' "$W/esp/limine.conf") $(diff "$D/limine.conf.before-d9" "$W/esp/limine.conf" | grep -c '^[<>]')" "Omarchy/linux-k114s-r3b 2"
ok "D9c: the holds name linux-k114s-r3b, the chain declaration names the new default, P's tree and old files are kept in \$D" \
  "$(grep -c -x linux-k114s-r3b "$W/lib/holds.list") $(grep -c -w linux-k114s-r3b "$W/pacman.conf") $(grep -c 'linux-k114s-r3b 7.3.0.r3b.b1-1' "$W/macboot/owner-boot-chain") $(sum "$D/k114s.dtb.p") $(grep -c 'old chain' "$D/owner-boot-chain.before-d9")" "1 1 1 $(sum "$W/fake/gpu.dtb") 1"
ok "D9c: D6 passed, so the mask file stays out; the after-record and limine.conf copy are kept; r3a's and r3b's images are unchanged" \
  "$(test -e "$W/modprobe/aurora-m5-vrr.conf"; echo $?) $(test -s "$D/after-d9.txt"; echo $?) $(cmp -s "$D/limine.conf.after-d9" "$W/esp/limine.conf"; echo $?) $(LC_ALL=C ls "$W/esp/EFI/Linux" | tr '\n' ' ')" "1 0 0 omarchy_linux-k114s-r3b.efi omarchy_linux-k114s.efi "
ok "D9c: the P fallback files are still on the ESP (the way back from Linux and from macOS)" "$(sum "$W/esp/m1n1/boot-ctxr-r3-gpu.bin") $(sum "$W/esp/k114s-repair/promotion/k114s.dtb.gpu")" "$(sum "$W/fake/gpu.bin") $(sum "$W/fake/gpu.dtb")"
ok "D9c: the printed reboot line names N-acked-3 and the owner or macOS agent check; the block schedules nothing" "$(echo "$out" | grep -c "N-acked-3.*owner|macos.*N-acked-3 && sudo systemd-run")" 1
ok "D9c: the printed reboot line says STOP when N-acked-3 is missing or names neither" "$(echo "$out" | grep -c "systemctl reboot || echo 'STOP: no reboot scheduled")" 1
ok "D9c: the first reboot is not scheduled by the block (the lead reads the output first)" "$(grep -c 'k114s-d9-reboot' "$W/calls")" 0
FAKE_UNAME=$REL run <<< "$bD9c"; ok "D9c: a second run stops (P is no longer the configured state), nothing changed" "$rc $(echo "$out" | grep -c 'P is not the configured state')" "1 1"
FAKE_UNAME=$REL FAKE_PKGVER=7.3.0.r3b.b1-1 run <<< "$bP9"; ok "P9 (with the fake boot-ctxr hashes): holds after D9c" "$rc $(echo "$out" | grep -c '^P9: ')" "0 1"
closed "$W/esp/EFI/Linux"; FAKE_UNAME=$REL FAKE_PKGVER=7.3.0.r3b.b1-1 run <<< "$bP9"; reopen "$W/esp/EFI/Linux"
ok "P9: with a root-only EFI/Linux (as on the Mac) the images are still listed and checked (a glob in the user's shell would pass a literal name)" "$rc $(echo "$out" | grep -c '^P9: ') $(echo "$out" | grep -c 'no .initrd section')" "0 1 0"
ok "P9: prints this boot's kernel and the ESP free space" "$(echo "$out" | grep -c '^this boot: ') $(echo "$out" | grep -c '^ESP free: ')" "1 1"
cp "$W/esp/EFI/Linux/omarchy_linux-k114s.efi" "$W/esp/EFI/Linux/omarchy_linux-aurora.efi"; run <<< "$bP9"; ok "P9: a third image (linux-aurora's came back) stops and names U1" "$rc $(echo "$out" | grep -c 'U1')" "1 1"; rm "$W/esp/EFI/Linux/omarchy_linux-aurora.efi"
FAKE_INITRD=appledrm FAKE_UNAME=$REL FAKE_PKGVER=7.3.0.r3b.b1-1 run <<< "$bP9"; ok "P9: appledrm in an image's initramfs stops (G6 on every image, F16)" "$rc $(echo "$out" | grep -c 'appledrm or dcp-fabric-core is in the initramfs')" "1 1"
rm "$W/mkinitcpio.conf.d/99-k114s-no-appledrm.conf"; run <<< "$bP9"; ok "P9: without the no-appledrm drop-in it stops (a rebuild would put appledrm back)" "$rc $(echo "$out" | grep -c 'G6a')" "1 1"; cp "$REPO_DIR/linux/99-k114s-no-appledrm.conf" "$W/mkinitcpio.conf.d/"
rm "$W/home/.config/hypr/monitors.lua.k114s-dcp-colour.bak"; HOME=$W/home bash "$REPO_DIR/linux/display/k114s-dcp-colour" --undo >/dev/null; FAKE_UNAME=$REL FAKE_PKGVER=7.3.0.r3b.b1-1 run <<< "$bP9"
ok "P9: the colour fix gone from monitors.lua (a migration rewrote it) stops" "$rc $(echo "$out" | grep -c 'colour fix is gone')" "1 1"; HOME=$W/home bash "$REPO_DIR/linux/display/k114s-dcp-colour" >/dev/null
K114S_SDDM_ROOT=$W/sddm bash "$REPO_DIR/linux/display/k114s-greeter-colour" --undo >/dev/null; FAKE_UNAME=$REL FAKE_PKGVER=7.3.0.r3b.b1-1 run <<< "$bP9"
ok "P9: without the greeter's colour guard it stops and names the installer" "$rc $(echo "$out" | grep -c 'k114s-greeter-colour')" "1 1"; K114S_SDDM_ROOT=$W/sddm bash "$REPO_DIR/linux/display/k114s-greeter-colour" >/dev/null
sed -i '/dcp_fabric_core/d' "$W/mkinitcpio.conf.d/99-k114s-no-appledrm.conf"; FAKE_UNAME=$REL FAKE_PKGVER=7.3.0.r3b.b1-1 run <<< "$bP9"; ok "P9: a drop-in that lost its dcp_fabric_core line stops" "$rc $(echo "$out" | grep -c 'G6a')" "1 1"; cp "$REPO_DIR/linux/99-k114s-no-appledrm.conf" "$W/mkinitcpio.conf.d/"
rm "$W/asahi/m1n1-ctxr.bin"; run <<< "$bP9"; ok "P9: a missing m1n1-ctxr.bin stops (a Stage 2 hook run would write the installed loader's file)" "$rc" 1; cp "$W/fake/pinldr-m1n1.bin" "$W/asahi/m1n1-ctxr.bin"
sed -i 's/linux-k114s-r3b//' "$W/pacman.conf"; run <<< "$bP9"; ok "P9: a holds block without linux-k114s-r3b stops" "$rc" 1; printf 'IgnorePkg = linux-k114s-r3b\n' > "$W/pacman.conf"
echo x >> "$W/esp/m1n1/boot-ctxr.bin"; run <<< "$bP9"; ok "P9: a Stage 2 that is not the D9 file stops" "$rc" 1
promote; FAKE_UNAME=$REL run <<< "$bD9u"
ok "D9u: exit 0, P's Stage 2 and tree are back, default_entry is r3a, m1n1-ctxr.bin is gone, r3b stays installed" \
  "$rc $(sum "$W/esp/m1n1/boot-ctxr.bin") $(sum "$W/esp/k114s-repair/k114s.dtb") $(sum "$W/lib/k114s.dtb") $(sed -n 's/^default_entry: //p' "$W/esp/limine.conf") $(test -e "$W/asahi/m1n1-ctxr.bin"; echo $?) $(test -e "$W/state/r3b"; echo $?)" \
  "0 $(sum "$W/fake/gpu.bin") $(sum "$W/fake/gpu.dtb") $(sum "$W/fake/gpu.dtb") Omarchy/linux-k114s 1 0"
ok "D9u: limine.conf is the file D9c found (default_entry the only difference)" "$(cmp -s "$D/limine.conf.before-d9" "$W/esp/limine.conf"; echo $?)" 0
FAKE_UNAME=$REL run <<< "$bD9c"; ok "D9u then D9c again works (the undo leaves D9a's gate and the state D9c wants)" "$rc" 0
ready; run <<< "$bD9a"; rm "$D/D9a-passed"; FAKE_UNAME=$REL run <<< "$bD9c"; ok "D9c: refused without D9a-passed" "$rc $(sum "$W/esp/m1n1/boot-ctxr.bin")" "1 $(sum "$W/fake/gpu.bin")"
ready; run <<< "$bD9a"; before=$(state); FAKE_UNAME=7.3.0-17.v272-4-ARCH run <<< "$bD9c"; ok "D9c: an unexpected kernel stops, nothing changed" "$rc $(state)" "1 $before"
ready; run <<< "$bD9a"; rm "$W/state/sync-stopped" 2>/dev/null; : > "$W/state/sync-running"; rm -f "$W/state/sync-stopped"; before=$(state); FAKE_UNAME=$REL run <<< "$bD9c"; ok "D9c: refused while the snapshot sync runs, nothing changed" "$rc $(state)" "1 $before"
ready; run <<< "$bD9a"; echo '# rebuilt' >> "$W/esp/limine.conf"; before=$(state); FAKE_UNAME=$REL run <<< "$bD9c"; ok "D9c: a limine.conf that is not I1b's file stops, nothing changed" "$rc $(state)" "1 $before"
ready; run <<< "$bD9a"; mkdir -p "$W/asahi"; cp "$W/fake/pinldr-m1n1.bin" "$W/asahi/m1n1-ctxr.bin"; before=$(state); FAKE_UNAME=$REL run <<< "$bD9c"; ok "D9c: an existing m1n1-ctxr.bin stops (a half-run), nothing changed" "$rc $(state)" "1 $before"
ready; run <<< "$bD9a"; rm "$D/D6-passed"; echo failed > "$D/D6-failed"; FAKE_UNAME=$REL run <<< "$bD9c"
ok "D9c: a failed D6 puts the mask back from the kept copy" "$rc $(grep -c 'fw27_panel_vrr=0' "$W/modprobe/aurora-m5-vrr.conf")" "0 1"
ready; run <<< "$bD9a"; sed -i 's/^Omarchy\/linux-k114s/&/' "$W/pacman.conf"; printf '#!/bin/sh\nexit 1\n' > "$W/lib/apply-holds"; before=$(sum "$W/esp/m1n1/boot-ctxr.bin"); FAKE_UNAME=$REL run <<< "$bD9c"
ok "D9c: a failing apply-holds stops after the writes with the copies named" "$rc $(echo "$out" | grep -c 'holds.list.before-d9')" "1 1"

# --- the two boots of the promoted configuration, then D9x and D9y ----------------------------------------------------------------
dboot() { boot $REL "" Omarchy.linux-k114s-r3b; rm -f "$W/chosen/aurora,trial"; printf '1.0.0b13-g22b71758-dirty\0' > "$W/chosen/asahi,m1n1-stage2-version"; run <<< "$bF"; }
promote; dboot; ok "F on a D9 boot: the folder is named configured" "$rc $(basename "$(cat "$D/last-boot")" | sed 's/.*-//')" "0 configured"
: > "$W/calls"; FAKE_REPO=$FR run <<< "$bC9"
ok "C9: passes with --expect published --floor --vrr on (D6 passed), writes its boot marker" "$rc $(grep -c 'display-check --expect published --floor --vrr on' "$W/calls") $(echo "$out" | grep -c '^C9: a clean default boot') $(ls "$D" | grep -c '^C9-passed-')" "0 1 1 1"
ok "C9: holds the snapshot sync off while the hold marker exists" "$(test -e "$W/state/sync-stopped"; echo $?)" 0
run <<< "$bD9x"; ok "D9x: refused after one clean boot" "$rc $(echo "$out" | grep -c 'fewer than two')" "1 1"
dboot; FAKE_REPO=$FR run <<< "$bC9"; echo 'N boot1 acked' > "$D/N-acked-1"; run <<< "$bD9x"
ok "D9x: exit 0 after two clean boots: PROMOTED, the sync started again, the hold and window markers gone, D9-done written" "$rc $(echo "$out" | grep -c 'D9x: PROMOTED') $(test -e "$W/state/sync-stopped"; echo $?) $(test -e "$D/sync-held"; echo $?) $(test -e "$D/window-open"; echo $?) $(test -s "$D/D9-done"; echo $?)" "0 1 1 1 1 0"
ok "D9x: the notices' acknowledgements are removed, so a later window cannot reuse them" "$(ls "$D"/N-acked-* 2>/dev/null | grep -c .)" 0
promote; dboot; FAKE_REPO=$FR run <<< "$bC9"; dboot; FAKE_REPO=$FR run <<< "$bC9"; echo 'N boot1 acked' > "$D/N-acked-1"; echo 'N boot2 acked' > "$D/N-acked-2"; closed "$D"; run <<< "$bD9x"; reopen "$D"
ok "D9x: with a root-only \$D (as on the Mac) the acknowledgements are removed too (a glob in the user's shell stays a literal name)" "$rc $(echo "$out" | grep -c 'D9x: PROMOTED') $(ls "$D"/N-acked-* 2>/dev/null | grep -c .)" "0 1 0"
ok "D9x: the stay-awake mode that T3a turned on is back off (it was off before the window)" "$(test -e "$W/state/stay-awake"; echo $?)" 1
promote; dboot; FAKE_REPO=$FR run <<< "$bC9"; dboot; FAKE_REPO=$FR run <<< "$bC9"; echo true > "$D/idle-before"; : > "$W/state/stay-awake"; run <<< "$bD9x"
ok "D9x: with idle-before true (this Mac: on since 2026-11-14) the mode stays on, the block still passes and says to report it to Jarvis" "$rc $(echo "$out" | grep -c 'D9x: PROMOTED') $(test -e "$W/state/stay-awake"; echo $?) $(echo "$out" | grep -c 'stay-awake is still on.*Jarvis')" "0 1 0 1"
promote; dboot; FAKE_REPO=$FR run <<< "$bC9"; dboot; FAKE_REPO=$FR run <<< "$bC9"; run <<< "$bD9x"
run <<< "$bD9y"; ok "D9y: no sync run yet stops, benign, nothing changed" "$rc $(echo "$out" | grep -c 'benign')" "1 1"
printf 'Boot usage limit reached: x\nStopping boot entry creation: Boot partition usage from 78.8%% to 109.3%% will exceed the 85.0%% limit.\nUpdated: %s/esp/limine.conf\n' "$W" > "$W/since"
FAKE_SINCE=$W/since run <<< "$bD9y"; ok "D9y: after the sync's run, limine.conf is as D9c wrote it" "$rc $(echo "$out" | grep -c '^D9y: the snapshot sync ran (1)')" "0 1"
cp -p "$W/esp/limine.conf" "$W/lc"; echo '# rewritten' >> "$W/esp/limine.conf"; FAKE_SINCE=$W/since run <<< "$bD9y"; ok "D9y: a run that changed limine.conf stops" "$rc $(echo "$out" | grep -c 'changed limine.conf')" "1 1"; mv "$W/lc" "$W/esp/limine.conf"
promote; dboot; FAKE_REPO=$FR run <<< "$bC9"; dboot; FAKE_REPO=$FR run <<< "$bC9"; echo x >> "$W/lib/k114s.dtb"; run <<< "$bD9x"; ok "D9x: a boot file that changed since D9c stops the close" "$rc $(echo "$out" | grep -c 'differs from the record')" "1 1"
promote; dboot; FAKE_REPO=$FR run <<< "$bC9"; dboot; FAKE_REPO=$FR run <<< "$bC9"; rm "$W/state/sync-stopped" 2>/dev/null; : > "$W/state/sync-stopped"; rm "$W/state/sync-stopped"; run <<< "$bD9x"; ok "D9x: refused while the sync runs" "$rc" 1
promote; dboot; FAKE_UNAME=7.3.0-17.v272-4-k114s-r3a-ARCH FAKE_REPO=$FR run <<< "$bC9"; ok "C9: an r3a boot stops" "$rc" 1
promote; boot $REL m1n1/boot-ctxr-disp-bl.bin Omarchy.linux-k114s-r3b; run <<< "$bF"; FAKE_REPO=$FR run <<< "$bC9"; ok "C9: a boot that came through an aura-try trial stops" "$rc $(echo "$out" | grep -c 'aura-try trial')" "1 1"
promote; dboot; FAKE_REPO=$FR FAKE_DCHECK=BAD run <<< "$bC9"; ok "C9: a BAD from the display check stops and leaves no marker" "$rc $(ls "$D" | grep -c '^C9-passed-')" "1 0"
promote; dboot; rm "$W/home/.config/hypr/monitors.lua.k114s-dcp-colour.bak"; HOME=$W/home bash "$REPO_DIR/linux/display/k114s-dcp-colour" --undo >/dev/null; FAKE_REPO=$FR run <<< "$bC9"; ok "C9: without the DCP colour fix it stops and leaves no marker" "$rc $(echo "$out" | grep -c 'DCP colour fix') $(ls "$D" | grep -c '^C9-passed-')" "1 1 0"
promote; boot $REL "" Omarchy.linux-k114s; printf '1.0.0b13-g22b71758-dirty\0' > "$W/chosen/asahi,m1n1-stage2-version"; run <<< "$bF"; FAKE_REPO=$FR run <<< "$bC9"; ok "C9: Limine that started the r3a entry stops" "$rc $(echo "$out" | grep -c 'did not start Omarchy.linux-k114s-r3b')" "1 1"

# --- the first update: U0 and U1 ----------------------------------------------------------------------------------------------------
hooks() { # the active hooks of the replica: /usr's copy (with modprobe.d and mdadm), the /etc override of 90-mkinitcpio-install (with dtbs, without modprobe.d), the Mac-boot hook, a remove hook and an unrelated one
  mkdir -p "$W/hooks-etc" "$W/hooks-usr"
  printf '[Trigger]\nType = Path\nOperation = Install\nOperation = Upgrade\nOperation = Remove\nTarget = usr/lib/initcpio/*\nTarget = usr/lib/firmware/*\nTarget = usr/lib/modprobe.d/\nTarget = usr/bin/mdadm\n\n[Trigger]\nType = Path\nOperation = Install\nOperation = Upgrade\nTarget = usr/lib/modules/*/vmlinuz\n\n[Trigger]\nType = Package\nOperation = Install\nOperation = Upgrade\nTarget = mkinitcpio\n\n[Action]\nWhen = PostTransaction\nExec = /usr/share/libalpm/scripts/mkinitcpio install\nNeedsTargets\n' > "$W/hooks-usr/90-mkinitcpio-install.hook"
  printf '[Trigger]\nType = Path\nOperation = Install\nOperation = Upgrade\nOperation = Remove\nTarget = usr/lib/initcpio/*\nTarget = usr/lib/firmware/*\nTarget = boot/dtbs/*\nTarget = usr/bin/cryptsetup\n\n[Trigger]\nType = Path\nOperation = Install\nOperation = Upgrade\nTarget = usr/lib/modules/*/vmlinuz\n\n[Trigger]\nType = Package\nOperation = Install\nOperation = Upgrade\nTarget = mkinitcpio\nTarget = mkinitcpio-git\n\n[Action]\nWhen = PostTransaction\nExec = /usr/share/libalpm/scripts/limine-apple-gate /usr/share/libalpm/scripts/limine-mkinitcpio-install\nNeedsTargets\n' > "$W/hooks-etc/90-mkinitcpio-install.hook"
  printf '[Trigger]\nType = Path\nOperation = Upgrade\nTarget = etc/initcpio/install/*\nTarget = usr/lib/omarchy/initcpio/*\n\n[Action]\nWhen = PostTransaction\nExec = /usr/share/libalpm/scripts/mkinitcpio install\n' > "$W/hooks-usr/91-omarchy-mac-boot-initramfs.hook"
  printf '[Trigger]\nType = Path\nOperation = Remove\nTarget = usr/lib/removeonly/*\n\n[Action]\nWhen = PreTransaction\nExec = /usr/share/libalpm/scripts/mkinitcpio remove\n' > "$W/hooks-usr/60-mkinitcpio-remove.hook"
  printf '[Trigger]\nType = Path\nOperation = Upgrade\nTarget = usr/lib/unrelated/*\n\n[Action]\nWhen = PostTransaction\nExec = /usr/bin/true\n' > "$W/hooks-usr/30-unrelated.hook"
}
u0pend() { printf '%s 1-1 -> 1-2\n' "$1" > "$W/state/pending"; printf '%s %s\n' "$1" "$2" > "$W/state/ql-$1"; run <<< "$bU0"; }
promote; hooks; printf 'foo 1-1 -> 1-2\n' > "$W/state/pending"; printf 'foo /usr/bin/foo\nfoo /usr/share/foo/x\n' > "$W/state/ql-foo"; run <<< "$bU0"
ok "U0: a pending package that triggers no rebuild passes and says so" "$rc $(echo "$out" | grep -c '^U0: 1 pending packages, none triggers')" "0 1"
rm -f "$D/before-update.txt"; printf 'foo 1-1 -> 1-2\nmkinitcpio 40-1 -> 41-1\n' > "$W/state/pending"; run <<< "$bU0"
ok "U0: a pending mkinitcpio (a Package target of the active hook) stops before anything is recorded (F8) and names the package" "$rc $(echo "$out" | grep -c 'trigger the rebuild of every image.*mkinitcpio') $(test -e "$D/before-update.txt"; echo $?)" "1 1 1"
u0pend baz /usr/lib/firmware/baz/blob.bin; ok "U0: a package that ships files under usr/lib/firmware stops too" "$rc $(echo "$out" | grep -c 'rebuild of every image.*baz')" "1 1"
u0pend qux /usr/lib/modprobe.d/; ok "U0: a modprobe.d file is no trigger while the /etc hook overrides the /usr one (the active hook has no such line)" "$rc" 0
u0pend dtb /boot/dtbs/x.dtb; ok "U0: a boot/dtbs file stops (a trigger line only the /etc override has)" "$rc $(echo "$out" | grep -c 'rebuild of every image.*dtb')" "1 1"
u0pend omx /usr/lib/omarchy/initcpio/hooks/y; ok "U0: a path trigger of a second active hook (the Mac-boot one) stops" "$rc" 1
u0pend rem /usr/lib/removeonly/z; ok "U0: a hook that only removes (Exec mkinitcpio remove) and an unrelated hook add no trigger" "$rc $(u0pend unr /usr/lib/unrelated/z >/dev/null; echo $rc)" "0 0"
rm "$W/hooks-etc/90-mkinitcpio-install.hook"; u0pend qux /usr/lib/modprobe.d/; ok "U0: with no /etc override the /usr hook's lines apply (modprobe.d is a trigger)" "$rc" 1
u0pend dtb /boot/dtbs/x.dtb; ok "U0: and a boot/dtbs file is no trigger of the /usr hook" "$rc" 0
rm -rf "$W/hooks-etc" "$W/hooks-usr"; u0pend foo /usr/bin/foo; ok "U0: no active mkinitcpio hook found stops (the trigger list is unknown)" "$rc $(echo "$out" | grep -c 'trigger list is unknown')" "1 1"
hooks
mig=$W/migrations; mst=$W/home/.local/state/omarchy/migrations; rm -rf "$mig" "$mst"; mkdir -p "$mig" "$mst"; : > "$mig/old.sh"; : > "$mst/old.sh"
mkpkg() { d=$W/state/pkg-$1/usr/share/omarchy/migrations; mkdir -p "$d"; shift; for m; do echo "${m#*=}" > "$d/${m%%=*}"; done; }
rm -f "$D/before-update.txt"; mkpkg omarchy-dev 'old.sh=sudo limine-mkinitcpio' 'new1.sh=[ -e /x ] || exit 0; sudo limine-mkinitcpio' 'new2.sh=echo hello'
u0pend omarchy-dev /usr/share/omarchy/migrations/old.sh
ok "U0: every new migration stops, the one that calls limine-mkinitcpio and the harmless-looking one alike (named, kept in \\$D for reading, nothing recorded); the one already run (its marker) does not" "$rc $(echo "$out" | grep -c 'new1.sh') $(echo "$out" | grep -c 'new2.sh') $(echo "$out" | grep -c 'old.sh') $(test -s "$D/migration-pending-new1.sh"; echo $?) $(test -s "$D/migration-pending-new2.sh"; echo $?) $(test -e "$D/before-update.txt"; echo $?)" "1 1 1 0 0 0 1"
mkpkg omarchy-dev 'old.sh=sudo limine-mkinitcpio' 'new4.sh=omarchy-hibernation-setup'; u0pend omarchy-dev /usr/share/omarchy/migrations/old.sh
ok "U0: a new migration that reaches the rebuild through a helper (no rebuild command by name) stops" "$rc $(echo "$out" | grep -c 'new4.sh')" "1 1"
mkpkg omarchy-dev 'old.sh=sudo limine-mkinitcpio' 'new5.sh=omarchy-pkg-drop yt6801-dkms'; u0pend omarchy-dev /usr/share/omarchy/migrations/old.sh
ok "U0: a new migration that drops a package (a pacman transaction checkupdates never lists) stops" "$rc $(echo "$out" | grep -c 'new5.sh')" "1 1"
rm -rf "$W/state/pkg-omarchy-dev"; mkpkg omarchy-dev 'old.sh=sudo limine-mkinitcpio' 'new1.sh=[ -e /x ] || exit 0; sudo limine-mkinitcpio' 'new2.sh=echo hello'
for m in new1.sh new2.sh; do echo "read: its gate exits on a Mac without the J-board marker" > "$D/migration-ok-$m"; done; run <<< "$bU0"
ok "U0: once the lead has recorded every new migration as read, U0 passes and the record is written" "$rc $(echo "$out" | grep -c 'migrations of omarchy-dev were read') $(test -s "$D/before-update.txt"; echo $?)" "0 1 0"
rm -f "$D/before-update.txt"; echo 'sudo limine-mkinitcpio' > "$mig/pend.sh"; u0pend omarchy-dev /usr/share/omarchy/migrations/old.sh
ok "U0: an installed migration with no marker (it failed or has not run, so the update runs it) stops too, and its record releases it" "$rc $(echo "$out" | grep -c 'pend.sh') $(test -s "$D/migration-pending-pend.sh"; echo $?) $(echo ok > "$D/migration-ok-pend.sh"; run <<< "$bU0"; echo $rc)" "1 1 0 0"
rm -f "$mig/pend.sh" "$D/before-update.txt" "$D"/migration-ok-*; mkpkg omarchy-dev 'new3.sh=mkinitcpio -P' ; u0pend omarchy-dev /usr/share/omarchy/migrations/old.sh; ok "U0: mkinitcpio -P in a new migration stops too" "$rc $(echo "$out" | grep -c 'new3.sh')" "1 1"
rm -rf "$W/state/pkg-omarchy-dev"; u0pend omarchy-dev /usr/share/omarchy/migrations/old.sh; ok "U0: a migration package that cannot be downloaded stops (its migrations are unread)" "$rc $(echo "$out" | grep -c 'could not be downloaded')" "1 1"
rm -rf "$W/state/pkg-omarchy-dev"; mkpkg zed 'new1.sh=limine-update'; u0pend zed "$W/migrations/old.sh"; ok "U0: a package that does not start with omarchy but ships migrations today is read too" "$rc $(echo "$out" | grep -c 'new1.sh')" "1 1"
rm -rf "$W/state/pkg-zed" "$D"/migration-ok-* "$D/before-update.txt"; mkdir -p "$mst/dirmark.sh"; : > "$mig/dirmark.sh"; u0pend foo /usr/bin/foo
ok "U0: a marker that is not a regular file is no marker (omarchy-migrate tests -f), so the migration stops it" "$rc $(echo "$out" | grep -c 'dirmark.sh')" "1 1"; rmdir "$mst/dirmark.sh"; rm "$mig/dirmark.sh"
mkdir -p "$W/omp/migrations"; : > "$W/omp/migrations/other.sh"; FAKE_OMARCHY_PATH=$W/omp u0pend foo /usr/bin/foo
ok "U0: the migrations folder is \$OMARCHY_PATH/migrations, as omarchy-migrate reads it (a migration there with no marker stops)" "$rc $(echo "$out" | grep -c 'other.sh')" "1 1"; rm -rf "$W/omp"
u0pend foo /usr/bin/foo; ok "U0: and the default folder with every migration marked passes" "$rc" 0
rm -rf "$mig"
promote; hooks; rm -f "$W/state/pending"; run <<< "$bU0"; ok "U0: nothing pending (checkupdates exit 2) passes" "$rc" 0
promote; hooks; run <<< "$bU0"; ok "U0: the before-record is written (the Stage 2, the pins, m1n1-ctxr.bin, the images, the entries)" "$rc $(echo "$out" | grep -c '^U0: before-record') $(grep -c 'm1n1-ctxr' "$D/before-update.txt" | head -1)" "0 1 1"
HOME=$W/home bash "$REPO_DIR/linux/display/k114s-dcp-colour" --undo >/dev/null; run <<< "$bU1"; ok "U1: the colour fix gone from monitors.lua stops" "$rc $(echo "$out" | grep -c 'colour fix is gone')" "1 1"; HOME=$W/home bash "$REPO_DIR/linux/display/k114s-dcp-colour" >/dev/null
run <<< "$bU1"; ok "U1: no change: no third image, no stray file, the diff is empty" "$rc $(echo "$out" | grep -c 'no boot file changed') $(echo "$out" | grep -c '^U1: ')" "0 1 1"
cp "$W/esp/EFI/Linux/omarchy_linux-k114s.efi" "$W/esp/EFI/Linux/omarchy_linux-aurora.efi"; run <<< "$bU1"; ok "U1: a returned linux-aurora image stops and prints the fix (the removal and the check of r3a's image), nothing is changed by the block" "$rc $(echo "$out" | grep -c 'limine-entry-tool --remove-uki linux-aurora') $(echo "$out" | grep -c "r3a's image") $(test -e "$W/esp/EFI/Linux/omarchy_linux-aurora.efi"; echo $?)" "1 1 3 0"; rm "$W/esp/EFI/Linux/omarchy_linux-aurora.efi"
: > "$W/esp/EFI/Linux/omarchy_linux-k114s.efi.tmp"; run <<< "$bU1"; ok "U1: a stray temporary file on the ESP stops" "$rc $(echo "$out" | grep -c 'temporary file')" "1 1"; rm "$W/esp/EFI/Linux/omarchy_linux-k114s.efi.tmp"
head -c 2100 /dev/urandom > "$W/esp/EFI/Linux/omarchy_linux-k114s-r3b.efi"; run <<< "$bU1"; ok "U1: a rebuilt image shows as a diff (only its hash line), not as no change" "$rc $(echo "$out" | grep -c 'the diff above is the change')" "0 1"
promote; run <<< "$bU1"; ok "U1: without U0's record it stops" "$rc" 1

# --- the root-only scratch folders of G6b and P9 (the fake sudo closes a `sudo mktemp -d` folder to the plain user) -----------------------
cat > "$W/oldform" <<'X'
g=$(sudo mktemp -d "$FAKE_W/vartmp/x.XXXXXX") || exit 9
sudo lsinitcpio /dev/null > "$g/list" 2>/dev/null; echo "old-redirect:$?"
grep -c ko "$g/list" 2>/dev/null; echo "old-read:$?"
sudo sh -c 'lsinitcpio "$1/x" > "$1/list" 2>/dev/null' _ "$g"; echo "sudo-redirect:$?"
sudo grep -c ko "$g/list"; echo "sudo-read:$?"
sudo rm -rf "$g"
X
run < "$W/oldform"
ok "harness: a user-shell redirect or read into a sudo mktemp folder fails (the old G6b and P9 form), the sudo form works" "$(echo "$out" | grep -c 'old-redirect:[^0]') $(echo "$out" | grep -c 'old-read:2') $(echo "$out" | grep -c 'sudo-redirect:0') $(echo "$out" | grep -c 'sudo-read:0')" "1 1 1 1"
ok "lint: no line of G6b or P9 writes or reads the root-only folder without sudo; the old lines would be caught" \
  "$(printf '%s\n%s\n' "$bG6b" "$bP9" | grep -E '"\$[tg]/' | grep -v sudo | wc -l) $(printf '%s\n' 'sudo lsinitcpio "$g/initrd" > "$g/list"; grep -c x "$g/list"' | grep -E '"\$[tg]/' | grep -v -E 'sudo (grep|tail|rm|test)' | wc -l)" "0 1"

ok "lint: no N-acked-* glob is expanded by the user's shell (the folder is root-only) and no loop globs the root-only ESP folder" \
  "$(grep -E 'rm -f.*N-acked-\*' "$DOC" | grep -v 'sh -c' | wc -l) $(grep -c -E 'for [a-z]+ in /boot/efi/[^ ;]*\*' "$DOC") $(printf '%s\n' 'sudo rm -f "$D"/N-acked-*' | grep -E 'rm -f.*N-acked-\*' | grep -v 'sh -c' | wc -l)" "0 0 1"
ok "lint: D6 reads vrr_capable through modetest, never from sysfs" "$(printf '%s\n' "$bD6" | grep -c 'modetest -M apple -c') $(printf '%s\n' "$bD6" | grep -c 'cat "$edp/vrr_capable"') $(test -e "$W/sys/class/drm/card2-eDP-1/vrr_capable"; echo $?)" "1 0 1"

# --- the abandon path: C1b, C2b, X, C4 (the first runbook's X and C4 with this window's \$D) ---------------------------------------
session0 s5; run <<< "$bC1b"; ok "C1b: the trial file is off the ESP, its copy stays, m1n1/ as before the window" "$rc $(test -e "$W/esp/m1n1/boot-ctxr-disp-bl.bin"; echo $?) $(sum "$D/boot-ctxr-disp-bl.bin")" "0 1 $(sum "$W/fake/d5.bin")"
FAKE_UNAME=$REL run <<< "$bC2b"; ok "C2b: refused from the r3b boot itself" "$rc $(test -e "$W/state/r3b"; echo $?)" "1 0"
run <<< "$bC2b"; ok "C2b: exit 0, r3b removed, limine.conf is W1's file" "$rc $(test -e "$W/state/r3b"; echo $?) $(cmp -s "$W/esp/limine.conf" "$D/limine.conf.after-window"; echo $?)" "0 1 0"
run <<< "$bX"; run <<< "$bC4"; ok "X then C4 close the window: no boot file changed, DISPLAY WINDOW CLOSED" "$rc $(echo "$out" | grep -c 'no boot file changed') $(echo "$out" | grep -c 'C4: DISPLAY WINDOW CLOSED')" "0 1 1"
session0 s5; run <<< "$bT3a"; run <<< "$bC1b"; ok "C1b: refused while aura-try is armed" "$rc" 1
promote; run <<< "$bC2b"; ok "C2b: refused after D9c (the configured Stage 2 is not P's file)" "$rc $(test -e "$W/state/r3b"; echo $?)" "1 0"

# --- the user-session blocks and the writing blocks parse, and every writing block has the guard ---------------------------------
n=0; bad=; while IFS= read -r -d '' b; do n=$((n+1)); bash -n <<< "$b" 2>/dev/null || bad="$bad $n"
  printf '%s' "$b" | grep -q -E 'sudo (cp|mv|rm|install|tee|sh|flock|systemctl|limine|mkdir|pacman|touch|systemd-run|\$K arm|\$L/apply-holds)' && ! printf '%s' "$b" | grep -q '^findmnt /boot/efi' &&
    ! printf '%s' "$b" | grep -q -E 'hyprctl|omarchy-brightness-display|omarchy-toggle-nightlight|shell\.json|mkinitcpio' && bad="$bad $n(no-guard)"
  printf '%s' "$b" | grep -q 'STOP' && ! printf '%s' "$b" | grep -q 'exit 1' && bad="$bad $n(stop-without-exit)"; done < <(
  awk '$0 == "    (" { c = 1; b = ""; next } c && $0 == "    )" { printf "%s%c", b, 0; c = 0; next } c { b = b substr($0, 5) "\n" }' "$DOC")
ok "all $n blocks of the runbook parse with bash -n, every STOP exits 1 (the user-session blocks write only records through sudo tee)" "${bad:-none} $((n >= 25))" "none 1"
ok "no block of the runbook writes 0 to the backlight (no 'set 0', no 'echo 0 >' to a brightness file)" "$(awk '$0 == "    (" { c = 1; next } c && $0 == "    )" { c = 0 } c' "$DOC" | grep -c -E "set 0( |\$)|echo 0 *> *[^ ]*brightness")" 0
ok "no block of the runbook prints a limine.conf line that could hold the command line" \
  "$(awk '$0 == "    (" { c = 1; next } c && $0 == "    )" { c = 0 } c' "$DOC" | grep -E "grep[^|]*limine\.conf|grep[^|]*\\\$c( |\$)" | grep -v -E 'grep -(c|q)|grep -[a-zA-Z]*[cq][a-zA-Z]* |default_entry|\^\[\[:blank:\]\]\*/|\^\[\[:blank:\]\]\*path:|path: boot|//Snapshots|\^\[\[:blank:\]\]\*//linux|-x -E' | grep -c .)" 0
finish "display d5-d9 runbook tests"
