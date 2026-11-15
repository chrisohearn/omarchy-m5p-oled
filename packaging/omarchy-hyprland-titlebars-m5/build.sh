#!/bin/bash
# SPDX-License-Identifier: MIT
# omarchy-m5p-oled: build the M5 rebuild of omarchy-hyprland-titlebars as a normal user.
#
#   build.sh WORKDIR        package lands in WORKDIR/pkg/, build tree and logs beside it
#
# Nothing is installed and nothing outside WORKDIR is written. The environment is emptied first
# so that the result depends on /etc/makepkg.conf and the installed packages only. JOBS sets the
# number of compile jobs (default 4).
set -euo pipefail
[[ $# == 1 ]] || { sed -n '3,9p' "$0"; exit 2; }
((EUID != 0)) || { echo "build.sh: run as a normal user, makepkg refuses root" >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$1"
work=$(cd "$1" && pwd)
mkdir -p "$work"/{makepkg-build,pkg,srcdest,logs}
cd "$here"
env -i HOME="$HOME" PATH=/usr/local/bin:/usr/bin LANG=C.UTF-8 \
  BUILDDIR="$work/makepkg-build" PKGDEST="$work/pkg" SRCDEST="$work/srcdest" LOGDEST="$work/logs" \
  PACKAGER='omarchy-m5p-oled K114s local rebuild <k114s@localhost>' MAKEFLAGS="-j${JOBS:-4}" \
  makepkg --cleanbuild --force --log --noconfirm
echo "build.sh: built:"
ls -1 "$work"/pkg/omarchy-hyprland-titlebars-*.pkg.tar.*
