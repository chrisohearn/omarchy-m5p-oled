#!/bin/bash
# Tests of k114s-release-check in a fake root, against a stand-in channel: a pacman repository on
# disk built with repo-add from small packages. pacman reads the repository lists into a private
# database; nothing is installed and no real system file is touched.
#   usage: test-r3-check.sh [LINUX_DIR]
# Needs pacman, repo-add, fakeroot, vercmp, bsdtar, zstd, python3; skips when one is missing.
set -u
. "$(dirname "$0")/r3-lib.sh" "${1:-}"
have pacman repo-add fakeroot vercmp bsdtar zstd python3 || { echo "r3 check tests: SKIPPED (pacman, repo-add, fakeroot, vercmp, bsdtar, zstd and python3 are needed)"; exit 0; }
status() { echo $?; }
P=$BASE/pkgs; mkdir -p "$P"
export MKROOT_KERNEL=1     # every fake root has the proven kernel (7.3.0-17.v272-4-ARCH, running) and the pinned Stage 2 tree
check() { local r=$1; shift; K114S_UNAME_R=7.3.0-17.v272-4-ARCH K114S_ROOT=$r bash "$(lib "$r")/k114s-release-check" "$@" 2>&1; }
verdict() { awk -F'\t' -v p="$2" '$1 == p { print $3 }' "$1/var/lib/omarchy-k114s/check/verdict.tsv"; }
result() { awk -F'\t' -v p="$2" -v l="$3" '$1 == p && $2 == l { print $4 }' "$1/var/lib/omarchy-k114s/check/checks.tsv"; }
detail() { awk -F'\t' -v p="$2" -v l="$3" '$1 == p && $2 == l { print $5 }' "$1/var/lib/omarchy-k114s/check/checks.tsv"; }
tree() { mktemp -d "$BASE/tree.XXXXXX"; }

# --- the packages a channel can offer ---------------------------------------------------------------
t=$(tree); kernel_tree "$t" 7.2.11-16-ARCH none "CONFIG_IKCONFIG=y"; k_old=$(mkpkg "$t" linux-aurora 7.2.11.aurora16-1 "$P")
t=$(tree); kernel_tree "$t" 7.4.0-1-ARCH none "$GOOD_CONFIG" "clamping Report Size"; k_notree=$(mkpkg "$t" linux-aurora 7.4.0.aurora18-1 "$P")
t=$(tree); kernel_tree "$t" 7.4.1-1-ARCH k114s-bare "$GOOD_CONFIG" "clamping Report Size"; k_bare=$(mkpkg "$t" linux-aurora 7.4.1.aurora18-1 "$P")
t=$(tree); kernel_tree "$t" 7.4.2-1-ARCH k114s-full "CONFIG_IKCONFIG=y
CONFIG_BT_RFCOMM=m" "clamping Report Size"; k_noconfig=$(mkpkg "$t" linux-aurora 7.4.2.aurora18-1 "$P")
t=$(tree); KIMG_MODULE= kernel_tree "$t" 7.4.3-1-ARCH k114s-full "$GOOD_CONFIG"; k_notrackpad=$(mkpkg "$t" linux-aurora 7.4.3.aurora18-1 "$P")
# the clamp in vmlinuz alone (what the old criteria accepted), and the module's frame parser alone
t=$(tree); KIMG_MODULE= kernel_tree "$t" 7.4.5-1-ARCH k114s-full "$GOOD_CONFIG" "clamping Report Size"; k_clamponly=$(mkpkg "$t" linux-aurora 7.4.5.aurora18-1 "$P")
t=$(tree); kernel_tree "$t" 7.4.6-1-ARCH k114s-full "$GOOD_CONFIG"; k_moduleonly=$(mkpkg "$t" linux-aurora 7.4.6.aurora18-1 "$P")
# a kernel that lost the driver of a node of the tree this Mac boots (PCIe built in, the USB controller as a module)
t=$(tree); KIMG_COMPAT="apple,t6050-nvme-ans2 apple,dockchannel-hid apple,smc-hwmon apple,t6050-sart" kernel_tree "$t" 7.4.7-1-ARCH k114s-full "$GOOD_CONFIG" "clamping Report Size"; k_nopcie=$(mkpkg "$t" linux-aurora 7.4.7.aurora18-1 "$P")
t=$(tree); KIMG_NOALIAS=1 kernel_tree "$t" 7.4.8-1-ARCH k114s-full "$GOOD_CONFIG" "clamping Report Size"; k_noalias=$(mkpkg "$t" linux-aurora 7.4.8.aurora18-1 "$P")
t=$(tree); KIMG_COMPAT="apple,t6050-pcie apple,dockchannel-hid apple,smc-hwmon apple,t6050-sart" kernel_tree "$t" 7.4.9-1-ARCH k114s-full "$GOOD_CONFIG" "clamping Report Size"; k_nonvme=$(mkpkg "$t" linux-aurora 7.4.9.aurora18-1 "$P")
t=$(tree); kernel_tree "$t" 7.4.4-1-ARCH k114s-full "$GOOD_CONFIG" "clamping Report Size"; k_good=$(mkpkg "$t" linux-aurora 7.4.4.aurora18-1 "$P")
t=$(tree); mkdir -p "$t/usr/lib/asahi-boot"; echo "m1n1 apple,t6040 apple,t8140" > "$t/usr/lib/asahi-boot/m1n1.bin"; m_old=$(mkpkg "$t" m1n1-aurora 1.6.1.aurora23-2 "$P")
t=$(tree); mkdir -p "$t/usr/lib/asahi-boot"; printf 'm1n1\0apple,t6050\0apcie,t6050\0atc-phy,t6050\0' > "$t/usr/lib/asahi-boot/m1n1.bin"; m_good=$(mkpkg "$t" m1n1-aurora 1.7.0.aurora25-1 "$P")
t=$(tree); mkdir -p "$t/usr/lib/asahi-boot"; printf 'm1n1\0apple,t6050\0' > "$t/usr/lib/asahi-boot/m1n1.bin"; m_half=$(mkpkg "$t" m1n1-aurora 1.6.9.aurora25-1 "$P")
t=$(tree); mkdir -p "$t/usr/lib/asahi-boot"; printf 'U-Boot\0apple,t6050-nvme-ans2\0apple,t6050-sart\0' > "$t/usr/lib/asahi-boot/u-boot-nodtb.bin"; u_good=$(mkpkg "$t" uboot-aurora 2026.10.aurora7-1 "$P")
fw_tree() { local t; t=$(tree); mkdir -p "$t/usr/lib/omarchy/initcpio" "$t/usr/lib/initcpio/install"
  printf 'case "$compatible" in\n  %s) modprobe apple_centauri_t6050 ;;\nesac\n' "$1" > "$t/usr/lib/omarchy/initcpio/aurora-peripheral-firmware.sh"
  printf 'build() {\n  add_module apple_centauri\n}\n' > "$t/usr/lib/initcpio/install/aurora-vendor-order"; echo "$t"; }
f_old=$(mkpkg "$(fw_tree 'apple,j714s')" omarchy-aurora-firmware 20261014-7 "$P")
f_j=$(mkpkg "$(fw_tree 'apple,j714s')" omarchy-aurora-firmware 20261120-1 "$P")
f_good=$(mkpkg "$(fw_tree 'apple,j714s|apple,k114s|apple,k116s')" omarchy-aurora-firmware 20261201-1 "$P")
t=$(tree); mkdir -p "$t/usr/lib"; printf 'gallium\0G14S\0G17S\0ASAHI_M5_BRINGUP\0llvmpipe\0' > "$t/usr/lib/libgallium-26.3.0-devel.so"; g_good=$(mkpkg "$t" mesa-aurora 1:26.3.0_devel.20261201.aaa-1 "$P")
t=$(tree); mkdir -p "$t/usr/lib"; printf 'gallium\0G14S\0G17S\0' > "$t/usr/lib/libgallium-26.3.0-devel.so"; g_nogate=$(mkpkg "$t" mesa-aurora 1:26.3.0_devel.20261203.ccc-1 "$P")
t=$(tree); mkdir -p "$t/usr/lib"; printf 'gallium\0G17S\0ASAHI_M5_BRINGUP\0' > "$t/usr/lib/libgallium-26.3.0-devel.so"; g_nocpu=$(mkpkg "$t" mesa-aurora 1:26.3.0_devel.20261204.ddd-1 "$P")
t=$(tree); mkdir -p "$t/usr/lib"; printf 'vulkan\0G17S\0' > "$t/usr/lib/libvulkan_asahi.so"; v_nogate=$(mkpkg "$t" vulkan-aurora 1:26.3.0_devel.20261202.aaa-1 "$P")
t=$(tree); mkdir -p "$t/usr/lib"; printf 'vulkan\0G17S\0ASAHI_M5_BRINGUP\0' > "$t/usr/lib/libvulkan_asahi.so"; v_good=$(mkpkg "$t" vulkan-aurora 1:26.3.0_devel.20261201.aaa-1 "$P")
t=$(tree); mkdir -p "$t/usr/lib"; printf 'gallium\0G14S\0' > "$t/usr/lib/libgallium-26.3.0-devel.so"; g_nodriver=$(mkpkg "$t" mesa-aurora 1:26.3.0_devel.20261202.bbb-1 "$P")
t=$(tree); mkdir -p "$t/usr/lib"; printf 'gallium\0G17S\0' > "$t/usr/lib/libgallium-26.3.0-devel.so"; g_older=$(mkpkg "$t" mesa-aurora 1:26.3.0_devel.20261107.231485.b7b03c5b3b8-2 "$P")
t=$(tree); mkdir -p "$t/usr/lib/omarchy-hyprland-titlebars"; echo stock > "$t/usr/lib/omarchy-hyprland-titlebars/titlebars.so"; tb_stock=$(mkpkg "$t" omarchy-hyprland-titlebars 0.4.1-1 "$P" "hyprland>=0.57")
t=$(tree); mkdir -p "$t/usr/lib/omarchy-hyprland-titlebars"; echo m5 > "$t/usr/lib/omarchy-hyprland-titlebars/titlebars.so"; tb_m5=$(mkpkg "$t" omarchy-hyprland-titlebars 0.4.2-1 "$P" "hyprland-m5=0.57.2-2")
t=$(tree); mkdir -p "$t/usr/bin"; echo hypr > "$t/usr/bin/Hyprland"; h_new=$(mkpkg "$t" hyprland-m5 0.58.0-1 "$P")
t=$(tree); mkdir -p "$t/usr/share/limine"; echo limine > "$t/usr/share/limine/BOOTAA64.EFI"; l_new=$(mkpkg "$t" limine 12.9.7-1 "$P")

# --- today's channel: older, generic builds ------------------------------------------------------------
mkrepo edge "$k_old" "$m_old" "$f_old" "$g_older"
r=$(mkroot); db_before=$(cd "$r/var/lib/pacman" && find . -type f -exec sha256sum {} + | LC_ALL=C sort | sha256sum)
out=$(check "$r"); ok "today's channel: nothing to release (exit 0)" "$?" 0
ok "linux-aurora: not-fixed" "$(verdict "$r" linux-aurora)" not-fixed
ok "linux-aurora: because the channel's is older" "$(detail "$r" linux-aurora newer)" "channel 7.2.11.aurora16-1 is not newer than installed 7.3.0.aurora17.v272-4"
ok "linux-aurora: the other checks are not evaluated for an older build" "$(result "$r" linux-aurora k114s-tree)" skipped
ok "m1n1-aurora, firmware, mesa: not-fixed" "$(verdict "$r" m1n1-aurora) $(verdict "$r" omarchy-aurora-firmware) $(verdict "$r" mesa-aurora)" "not-fixed not-fixed not-fixed"
ok "a held package the channel does not have: absent" "$(verdict "$r" hyprland-m5) $(verdict "$r" uboot-aurora)" "absent absent"
ok "a held name that is not installed: said so" "$(verdict "$r" limine)" not-installed
ok "summary names the reason" "$(echo "$out" | grep -c 'newer: channel 7.2.11.aurora16-1 is not newer')" 1
ok "nothing installed: pacman's database is untouched" "$(cd "$r/var/lib/pacman" && find . -type f -exec sha256sum {} + | LC_ALL=C sort | sha256sum)" "$db_before"
ok "no repository lists in pacman's own database" "$(test -e "$r/var/lib/pacman/sync"; status)" 1
ok "pacman's own cache is untouched" "$(ls "$r/var/cache/pacman/pkg" | wc -l | tr -d ' ')" 0
ok "verdict.json is valid JSON" "$(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d["packages"]))' "$r/var/lib/omarchy-k114s/check/verdict.json")" 13
ok "verdict.json carries verdicts and checks" "$(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); p=[x for x in d["packages"] if x["name"]=="linux-aurora"][0]; print(p["verdict"], p["class"], p["checks"][0]["label"], p["checks"][0]["result"])' "$r/var/lib/omarchy-k114s/check/verdict.json")" "not-fixed boot-uki newer fail"
out=$(check "$r" --full --packages linux-aurora); ok "--full evaluates every check of an older build" "$(result "$r" linux-aurora k114s-tree) $(result "$r" linux-aurora config)" "fail fail"
ok "--full: the reasons" "$(echo "$out" | grep -c -E 'k114s-tree: no file matches|config: not set: CONFIG_BT_RFCOMM')" 2
ok "--packages limits the run" "$(wc -l < "$r/var/lib/omarchy-k114s/check/verdict.tsv" | tr -d ' ')" 1

# --- the kernel, one missing property at a time --------------------------------------------------------
kcase() { mkrepo edge "$1"; r=$(mkroot); out=$(check "$r" --packages linux-aurora); code=$?; }
kcase "$k_notree"; ok "newer kernel without a K114s tree: not-fixed" "$code $(verdict "$r" linux-aurora) $(result "$r" linux-aurora k114s-tree)" "0 not-fixed fail"
kcase "$k_bare"; ok "K114s tree without Wi-Fi, USB, sensors: not-fixed" "$code $(verdict "$r" linux-aurora)" "0 not-fixed"
ok "bare tree: identity passes" "$(result "$r" linux-aurora k114s-identity)" pass
ok "bare tree: the N1 platform id is missing" "$(result "$r" linux-aurora n1-platform-id) $(result "$r" linux-aurora n1-wifi) $(result "$r" linux-aurora n1-pcie)" "fail fail fail"
ok "bare tree: USB controllers are there but disabled" "$(detail "$r" linux-aurora usb-controllers)" "0 enabled node(s) compatible:apple,t6050-dwc3, need 2"
ok "bare tree: sensors disabled" "$(result "$r" linux-aurora sensors)" fail
ok "bare tree: keyboard transport passes" "$(result "$r" linux-aurora input-transport)" pass
kcase "$k_noconfig"; ok "full tree, config without our options: not-fixed" "$code $(verdict "$r" linux-aurora)" "0 not-fixed"
ok "config: names what is not set" "$(detail "$r" linux-aurora config)" "not set: CONFIG_NETFILTER_XT_MATCH_HL CONFIG_IP6_NF_MATCH_HL CONFIG_IP6_NF_MATCH_RT CONFIG_PKCS8_PRIVATE_KEY_PARSER"
ok "config: everything else passes" "$(awk -F'\t' '$4 != "pass" && $2 != "trackpad-module" && $2 != "report-clamp" { print $2 }' "$r/var/lib/omarchy-k114s/check/checks.tsv" | tr '\n' ' ')" "config "
kcase "$k_notrackpad"; ok "full tree and config, no trackpad fix: not-fixed" "$code $(verdict "$r" linux-aurora)" "0 not-fixed"
ok "trackpad: neither the module's raw-event path nor product 0x0361, and no clamp" "$(awk -F'\t' '$2 == "trackpad-module" || $2 == "report-clamp" { print $2 ":" $4 }' "$r/var/lib/omarchy-k114s/check/checks.tsv" | tr '\n' ' ')" "trackpad-module:fail trackpad-module:fail report-clamp:fail report-clamp:fail "
kcase "$k_clamponly"; ok "the clamp in vmlinuz alone is NOT enough: the hid-magicmouse module must carry the frame parser (r2c had to patch it)" "$code $(verdict "$r" linux-aurora) $(awk -F'\t' '$2 == "report-clamp" { print $4 }' "$r/var/lib/omarchy-k114s/check/checks.tsv" | sort | tr '\n' ' ') $(awk -F'\t' '$2 == "trackpad-module" { print $4 }' "$r/var/lib/omarchy-k114s/check/checks.tsv" | tr '\n' ' ')" "0 not-fixed fail pass  fail fail "
kcase "$k_moduleonly"; ok "the module's parser alone is not enough either: the clamp must be in the image" "$code $(verdict "$r" linux-aurora) $(awk -F'\t' '$2 == "report-clamp" { print $4 }' "$r/var/lib/omarchy-k114s/check/checks.tsv" | sort | tr '\n' ' ')" "0 not-fixed fail fail "
kcase "$k_nopcie"; ok "a kernel that lost the PCIe driver of the tree this Mac boots: not-fixed, naming it" "$code $(verdict "$r" linux-aurora) $(detail "$r" linux-aurora tree-drivers)" "0 not-fixed the channel's kernel lost the driver for: apple,t6050-pcie"
kcase "$k_noalias"; ok "a kernel whose modules no longer carry the USB controller's alias: not-fixed, naming both" "$code $(verdict "$r" linux-aurora) $(detail "$r" linux-aurora tree-drivers)" "0 not-fixed the channel's kernel lost the driver for: apple,sn201202x apple,t6050-dwc3"
kcase "$k_nonvme"; ok "NVMe/ANS is checked by name" "$code $(verdict "$r" linux-aurora) $(result "$r" linux-aurora nvme-ans)" "0 not-fixed fail"
# the tree Stage 2 really boots: the live device tree (r3-gpu adds the GPU) counts, and the packaged tree only after --dtb packaged
kcase "$k_good"; mkdir -p "$r/proc/device-tree/gpu"; printf 'apple,agx-g17s\0' > "$r/proc/device-tree/gpu/compatible"; printf 'okay\0' > "$r/proc/device-tree/gpu/status"
{ printf '\0apple,agx-g17s\0'; } >> "$r/usr/lib/modules/7.3.0-17.v272-4-ARCH/vmlinuz"
out=$(check "$r" --packages linux-aurora); ok "the running tree has a GPU node and the proven kernel has its driver: a channel kernel without it is not fixed" "$(verdict "$r" linux-aurora) $(detail "$r" linux-aurora tree-drivers)" "not-fixed the channel's kernel lost the driver for: apple,agx-g17s"
printf 'disabled\0' > "$r/proc/device-tree/gpu/status"; out=$(check "$r" --packages linux-aurora); ok "a disabled node is not wanted" "$(verdict "$r" linux-aurora)" fixed
kcase "$k_good"; rm -f "$(lib "$r")/k114s.dtb"; rm -rf "$r/proc"; out=$(check "$r" --packages linux-aurora); ok "no tree of the Mac to read at all: an error, never a pass" "$(verdict "$r" linux-aurora) $(result "$r" linux-aurora tree-drivers)" "error error"
kcase "$k_good"; rm -f "$r/usr/lib/modules/7.3.0-17.v272-4-ARCH/vmlinuz"; out=$(check "$r" --packages linux-aurora); ok "no proven kernel to compare with: an error, never a pass" "$(verdict "$r" linux-aurora) $(result "$r" linux-aurora tree-drivers)" "error error"
kcase "$k_good"; ok "a kernel with everything: FIXED (exit 10)" "$code $(verdict "$r" linux-aurora)" "10 fixed"
ok "fixed: the N1 platform id reads 0x00146050" "$(detail "$r" linux-aurora n1-platform-id)" "apple,centauri-platform-id = 0x00146050"
ok "fixed: two USB controllers and two port controllers enabled" "$(detail "$r" linux-aurora usb-controllers) / $(detail "$r" linux-aurora usb-port-control)" "2 enabled / 2 enabled"
ok "fixed: one of the two module proofs is enough" "$(awk -F'\t' '$2 == "trackpad-module" { print $4 }' "$r/var/lib/omarchy-k114s/check/checks.tsv" | LC_ALL=C sort | tr '\n' ' ')" "fail pass "
ok "fixed: no check failed outside an any-group" "$(awk -F'\t' '$4 != "pass" && $2 != "trackpad-module" && $2 != "report-clamp"' "$r/var/lib/omarchy-k114s/check/checks.tsv" | wc -l | tr -d ' ')" 0
ok "fixed: the verdict carries the SHA-256 that was checked" "$(awk -F'\t' '{ print $7 }' "$r/var/lib/omarchy-k114s/check/verdict.tsv")" "$(sum "$k_good")"
ok "fixed: and the file" "$(sum "$(awk -F'\t' '{ print $8 }' "$r/var/lib/omarchy-k114s/check/verdict.tsv")")" "$(sum "$k_good")"
ok "fixed: summary" "$(echo "$out" | grep -c 'FIXED       linux-aurora  7.3.0.aurora17.v272-4 -> 7.4.4.aurora18-1 (boot-uki)')" 1
ok "the unpacked package is cleaned up" "$(ls "$r/var/lib/omarchy-k114s/check/x" | wc -l | tr -d ' ')" 0
ok "still nothing installed" "$(ls "$r/var/lib/pacman/local" | grep -c '^linux-aurora-7.3.0')" 1
# the config fragment language
kcase "$k_good"; printf '# CONFIG_BT_RFCOMM is not set\n' > "$(lib "$r")/kernel-config.required"; out=$(check "$r" --packages linux-aurora)
ok "fragment: 'is not set' fails when the option is on" "$(detail "$r" linux-aurora config)" "not set: CONFIG_BT_RFCOMM(must be off)"
printf 'CONFIG_BT_RFCOMM=y\n' > "$(lib "$r")/kernel-config.required"; out=$(check "$r" --packages linux-aurora)
ok "fragment: =y is not met by a module" "$(result "$r" linux-aurora config)" fail
printf '# a comment\nCONFIG_IP6_NF_MATCH_RT=m\n# CONFIG_NOT_THERE is not set\nCONFIG_BT_RFCOMM\n' > "$(lib "$r")/kernel-config.required"; out=$(check "$r" --packages linux-aurora)
ok "fragment: =m is met by built in; off stays off; bare name is y or m" "$(result "$r" linux-aurora config) $?" "pass 0"
printf 'rm -rf /\n' > "$(lib "$r")/kernel-config.required"; out=$(check "$r" --packages linux-aurora)
ok "fragment: anything else is an error, never a pass" "$(verdict "$r" linux-aurora) $(result "$r" linux-aurora config)" "error error"

# --- the other packages -------------------------------------------------------------------------------------
mkrepo edge "$m_good" "$u_good" "$f_good" "$g_good" "$tb_stock" "$h_new"
r=$(mkroot); out=$(check "$r"); code=$?
ok "loader with T6050 support, U-Boot, firmware for apple,k114s, Mesa with G17S: fixed" "$code $(verdict "$r" m1n1-aurora) $(verdict "$r" uboot-aurora) $(verdict "$r" omarchy-aurora-firmware) $(verdict "$r" mesa-aurora)" "10 fixed fixed fixed fixed"
ok "title-bar plugin built against stock Hyprland: not-fixed while hyprland-m5 is the compositor" "$(verdict "$r" omarchy-hyprland-titlebars)" not-fixed
ok "hyprland-m5: newer, but a person decides" "$(verdict "$r" hyprland-m5) $(result "$r" hyprland-m5 decision)" "not-fixed fail"
ok "classes are reported" "$(awk -F'\t' '$1 == "m1n1-aurora" || $1 == "mesa-aurora" || $1 == "omarchy-aurora-firmware" { print $2 }' "$r/var/lib/omarchy-k114s/check/verdict.tsv" | tr '\n' ' ')" "boot-stage2 userland boot-uki "
out=$(check "$r" --accept-manual --packages hyprland-m5); ok "--accept-manual: the person's decision counts" "$? $(verdict "$r" hyprland-m5)" "10 fixed"
mkrepo edge "$m_half" "$f_j" "$g_nodriver" "$tb_m5"
r=$(mkroot); out=$(check "$r"); code=$?
ok "loader that knows the SoC but not its PCIe and PHY: not-fixed" "$(verdict "$r" m1n1-aurora) $(result "$r" m1n1-aurora t6050) $(result "$r" m1n1-aurora t6050-pcie)" "not-fixed pass fail"
ok "firmware that still loads the N1 for apple,j714s only: not-fixed" "$(verdict "$r" omarchy-aurora-firmware) $(result "$r" omarchy-aurora-firmware n1-for-k114s)" "not-fixed fail"
ok "Mesa without the M5 Pro driver: not-fixed" "$(verdict "$r" mesa-aurora)" not-fixed
mkrepo edge "$g_nogate" "$v_nogate"; r=$(mkroot); out=$(check "$r" --packages "mesa-aurora vulkan-aurora")
ok "Mesa and Vulkan with the device but without the M5 bringup gate: not-fixed (a version string and G17S are not enough)" "$(verdict "$r" mesa-aurora) $(result "$r" mesa-aurora g17s) $(result "$r" mesa-aurora m5-bringup) $(verdict "$r" vulkan-aurora) $(result "$r" vulkan-aurora m5-bringup)" "not-fixed pass fail not-fixed fail"
mkrepo edge "$g_nocpu"; r=$(mkroot); out=$(check "$r" --packages mesa-aurora)
ok "Mesa without the software renderer: not-fixed (the desktop guard falls back to the CPU with it)" "$(verdict "$r" mesa-aurora) $(result "$r" mesa-aurora m5-bringup) $(result "$r" mesa-aurora cpu-fallback)" "not-fixed pass fail"
mkrepo edge "$g_good" "$v_good"; r=$(mkroot); out=$(check "$r" --packages "mesa-aurora vulkan-aurora")
ok "Mesa and Vulkan with the device, the gate and the CPU renderer: fixed" "$(verdict "$r" mesa-aurora) $(verdict "$r" vulkan-aurora)" "fixed fixed"
mkrepo edge "$m_half" "$f_j" "$g_nodriver" "$tb_m5"; r=$(mkroot); out=$(check "$r"); code=$?
ok "title-bar plugin that depends on hyprland-m5: fixed" "$code $(verdict "$r" omarchy-hyprland-titlebars)" "10 fixed"
r=$(mkroot); rm -rf "$r/var/lib/pacman/local/hyprland-m5-0.57.2-2"; mkrepo edge "$tb_stock"; out=$(check "$r" --packages omarchy-hyprland-titlebars)
ok "stock plugin is fine once hyprland-m5 is not installed" "$(verdict "$r" omarchy-hyprland-titlebars)" fixed
# our own build tags in a version: pacman sorts them above the channel's build of the same upstream version for ever
ub() { local t; t=$(tree); mkdir -p "$t/usr/lib/asahi-boot"; printf '%s\0' $1 > "$t/usr/lib/asahi-boot/u-boot-nodtb.bin"; mkpkg "$t" uboot-aurora "$2" "$P"; }
u_stock=$(ub "U-Boot apple,t6040-nvme" 2026.07.aurora6-1); u_fit=$(ub "U-Boot apple,t6050-nvme-ans2 apple,t6050-sart" 2026.07.aurora6-2)
u_ours=$(ub "U-Boot apple,t6050-nvme-ans2 apple,t6050-sart" 2026.07.aurora6.j714s3-1); u_older=$(ub "U-Boot apple,t6050-nvme-ans2 apple,t6050-sart" 2026.04.aurora5-9)
mkrepo edge "$u_stock"; r=$(mkroot); out=$(check "$r" --packages uboot-aurora)
ok "today: the channel's build of the upstream version ours was made from is 'not older', and its content decides: not-fixed" "$(verdict "$r" uboot-aurora) $(result "$r" uboot-aurora newer) $(result "$r" uboot-aurora t6050-nvme)" "not-fixed pass fail"
mkrepo edge "$u_fit"; r=$(mkroot); out=$(check "$r" --packages uboot-aurora)
ok "its rebuild with the fix sorts BELOW our tagged version for pacman, and is fixed here" "$(vercmp 2026.07.aurora6-2 2026.07.aurora6.j714s3-1) $(verdict "$r" uboot-aurora)" "-1 fixed"
ok "the reason is spelled out" "$(detail "$r" uboot-aurora newer)" "2026.07.aurora6-2 is the channel's build of 2026.07.aurora6 or later; the installed 2026.07.aurora6.j714s3-1 carries our build tag"
mkrepo edge "$u_ours"; r=$(mkroot); out=$(check "$r" --packages uboot-aurora)
ok "the identical version is never 'newer', whatever is in it" "$(verdict "$r" uboot-aurora) $(detail "$r" uboot-aurora newer)" "not-fixed the channel has the installed version, 2026.07.aurora6.j714s3-1"
mkrepo edge "$u_older"; r=$(mkroot); out=$(check "$r" --packages uboot-aurora)
ok "an older upstream version stays older, whatever its release number" "$(verdict "$r" uboot-aurora) $(result "$r" uboot-aurora newer)" "not-fixed fail"
r=$(mkroot); rm -rf "$r/var/lib/pacman/local/omarchy-hyprland-titlebars-0.4.0-1"; dbpkg "$r" omarchy-hyprland-titlebars 1:0.4.0+m5-1; mkrepo edge "$tb_m5"; out=$(check "$r" --packages omarchy-hyprland-titlebars)
ok "the locally rebuilt plugin (epoch, +m5) does not hide a fit channel build for ever" "$(verdict "$r" omarchy-hyprland-titlebars)" fixed
mkrepo edge "$tb_stock"; r=$(mkroot); rm -rf "$r/var/lib/pacman/local/omarchy-hyprland-titlebars-0.4.0-1"; dbpkg "$r" omarchy-hyprland-titlebars 1:0.4.0+m5-1; out=$(check "$r" --packages omarchy-hyprland-titlebars)
ok "and a newer stock-ABI build still does not replace it" "$(verdict "$r" omarchy-hyprland-titlebars) $(result "$r" omarchy-hyprland-titlebars newer)" "not-fixed pass"
# held without criteria, released, and the default selection
r=$(mkroot); t=$(tree); mkdir -p "$t/usr/bin"; echo x > "$t/usr/bin/sg"; sg=$(mkpkg "$t" speakerguardd-v2 2.0-1 "$P"); mkrepo edge "$sg" "$g_good"
dbpkg "$r" speakerguardd-v2 1.0.0alpha.1-41.1; echo speakerguardd-v2 >> "$(lib "$r")/holds.list"
out=$(check "$r"); ok "a held package without criteria is never released" "$(verdict "$r" speakerguardd-v2)" no-criteria
echo "mesa-aurora 1:26.3.0-1 20261201T000000Z" > "$(lib "$r")/released.list"; out=$(check "$r")
ok "a released package is no longer checked" "$(verdict "$r" mesa-aurora)" ""

# --- what the check must refuse to trust ----------------------------------------------------------------
mkrepo edge "$k_good"; r=$(mkroot)
printf 'tampered' >> "$REPO/edge/os/${k_good##*/}"
out=$(check "$r" --packages linux-aurora); ok "a package that does not match the repository list's SHA-256: error, not fixed" "$? $(verdict "$r" linux-aurora)" "0 error"
ok "tampered: the reason" "$(echo "$out" | grep -q 'does not match the repository list'; status)" 0
mkrepo edge "$k_good"; r=$(mkroot); rm -rf "$REPO/edge"
out=$(check "$r" --packages linux-aurora); ok "channel unreachable: cannot run (exit 2)" "$?" 2
ok "unreachable: says so" "$(echo "$out" | grep -c 'could not refresh the repository lists')" 1
mkrepo edge "$k_good"; r=$(mkroot); check "$r" --packages linux-aurora >/dev/null; rm "$r/var/lib/omarchy-k114s/check/refresh.log"
out=$(check "$r" --no-refresh --packages linux-aurora); ok "--no-refresh reuses the lists it has" "$(verdict "$r" linux-aurora) $(test -e "$r/var/lib/omarchy-k114s/check/refresh.log"; status)" "fixed 1"
r=$(mkroot); printf 'package linux-aurora boot-uki\ncheck linux-aurora newer version-newer\ncheck linux-aurora odd no-such-type x\n' > "$BASE/odd.conf"
out=$(K114S_CRITERIA=$BASE/odd.conf check "$r" --packages linux-aurora); ok "an unknown check type is an error, never a pass" "$(verdict "$r" linux-aurora) $(result "$r" linux-aurora odd)" "error error"
r=$(mkroot); out=$(K114S_CRITERIA=$BASE/missing.conf check "$r"); ok "criteria file missing: cannot run" "$?" 2
out=$(check "$r" --bogus); ok "unknown argument" "$?" 2
# the criteria name a class for every package they describe, and only known check types
ok "criteria: every described package has a class" "$(awk '$1 == "package" && $3 !~ /^(boot-uki|boot-stage2|userland)$/' "$L/release-criteria.conf" | wc -l | tr -d ' ')" 0
ok "criteria: every check line belongs to a described package" "$(awk '$1 == "package" { known[$2] = 1 } ($1 == "check" || $1 == "any") && !($2 in known)' "$L/release-criteria.conf" | wc -l | tr -d ' ')" 0
ok "criteria: only known check types" "$(awk '($1 == "check" || $1 == "any") { print $4 }' "$L/release-criteria.conf" | grep -c -v -x -E 'version-newer|file-exists|file-contains|file-matches|dtb-root-compatible|dtb-node|dtb-okay|dtb-prop|kconfig|module-parm|code-imm16|tree-drivers|depends-on|not-installed|manual')" 0
ok "criteria: the optional fourth word of a package line is only ever keep-held" "$(awk '$1 == "package" && $4 != "" && $4 != "keep-held"' "$L/release-criteria.conf" | wc -l | tr -d ' ')" 0
ok "criteria: the optional fifth word is only ever gpu, and only on a keep-held package; the GPU stack is mesa-aurora and vulkan-aurora, not asahi-fwextract or omarchy-mac" "$(awk '$1 == "package" && $5 != "" && ($5 != "gpu" || $4 != "keep-held")' "$L/release-criteria.conf" | wc -l | tr -d ' ') $(awk '$1 == "package" && $5 == "gpu" { print $2 }' "$L/release-criteria.conf" | LC_ALL=C sort | tr '\n' ' ')" "0 mesa-aurora vulkan-aurora "
ok "criteria: the GPU stack and the boot-time tooling a person decides on are keep-held" "$(awk '$1 == "package" && $4 == "keep-held" { print $2 }' "$L/release-criteria.conf" | LC_ALL=C sort | tr '\n' ' ')" "asahi-fwextract mesa-aurora omarchy-mac vulkan-aurora "
ok "criteria: every package starts with the version check" "$(awk '$1 == "package" { want[$2] = 1 } ($1 == "check" || $1 == "any") && ($2 in want) { if ($4 != "version-newer") bad++; delete want[$2] } END { print bad + 0 }' "$L/release-criteria.conf")" 0

finish "r3 release-check tests"
