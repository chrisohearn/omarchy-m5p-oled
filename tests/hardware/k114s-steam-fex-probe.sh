#!/usr/bin/env bash
# Read-only probe for Steam/FEX/muvm prerequisites (issue #29). Changes nothing.
set -u
echo "page size: $(getconf PAGESIZE)"
ls -l /dev/kvm /dev/dri/renderD128 2>&1
(zcat /proc/config.gz 2>/dev/null || cat "/boot/config-$(uname -r)" 2>/dev/null) |
  grep -E '^(CONFIG_KVM=|CONFIG_ARM64_16K_PAGES=|CONFIG_DRM_ASAHI=|CONFIG_VHOST_VSOCK=)'
sudo dmesg | grep -E 'kvm \[1\]|started at EL2' | head -8
for p in muvm FEX-Emu omarchy-steam-fex libkrun virglrenderer mesa-aurora; do
  pacman -Q "$p" 2>/dev/null || echo "$p: not installed ($(pacman -Si "$p" 2>/dev/null | awk -F': *' '/^Version/{print $2}'))"
done
# virglrenderer drm renderers (only works after the package is installed)
lib=$(ls /usr/lib/libvirglrenderer.so* 2>/dev/null | head -1)
[ -n "$lib" ] && { strings "$lib" | grep -iE 'asahi|drm_renderer|native' | head; } || echo "virglrenderer library not installed"
