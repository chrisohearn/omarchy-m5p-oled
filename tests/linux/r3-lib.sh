# Shared by the r3 tests (tests/linux/test-r3-*.sh). Sourced. Everything runs as a normal user
# against throwaway folders; no real system file is touched and no fixtures are needed.
#   usage in a test:  . "$(dirname "$0")/r3-lib.sh" "$LINUX_DIR"
L=$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")/../../linux}" && pwd)
T=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
pass=0; fail=0
BASE=$(mktemp -d "${TMPDIR:-/tmp}/k114s-r3-test.XXXXXX")
trap '[ -n "${R3_KEEP:-}" ] && echo "kept: $BASE" || { chmod -R u+rwX "$BASE" 2>/dev/null; rm -rf "$BASE"; }' EXIT   # R3_KEEP=1 keeps the folder for a look
ok() { # ok NAME GOT WANT    (R3_DEBUG=1 also prints the last command output, $out, of a failing test)
  if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: got [$2] want [$3]"
    [ -z "${R3_DEBUG:-}" ] || printf '%s\n' "${out:-}" | sed 's/^/    | /'; fi
}
sum() { sha256sum "$1" 2>/dev/null | cut -c1-64; }
lib() { echo "$1/usr/local/lib/omarchy-k114s"; }
finish() { echo "$1: $pass passed, $fail failed"; [ "$fail" = 0 ]; }

HELD="asahi-fwextract asahi-scripts hyprland-m5 limine linux-aurora m1n1-aurora mesa-aurora omarchy-aurora-firmware omarchy-hyprland-titlebars omarchy-mac omarchy-mac-boot uboot-aurora vulkan-aurora"

dbpkg() { # dbpkg ROOT NAME VERSION [PATH...]: an entry in pacman's local database (files are not created)
  local r=$1 name=$2 version=$3 d
  shift 3
  d=$r/var/lib/pacman/local/$name-$version
  mkdir -p "$d"; echo 9 > "$r/var/lib/pacman/local/ALPM_DB_VERSION"
  printf '%%NAME%%\n%s\n\n%%VERSION%%\n%s\n\n%%BASE%%\n%s\n\n%%DESC%%\ntest package %s\n\n%%URL%%\nhttps://example.invalid/\n\n%%ARCH%%\nany\n\n%%BUILDDATE%%\n1700000000\n\n%%INSTALLDATE%%\n1700000001\n\n%%PACKAGER%%\nUnknown Packager\n\n%%SIZE%%\n1\n\n%%LICENSE%%\nMIT\n\n%%VALIDATION%%\nnone\n\n' \
    "$name" "$version" "$name" "$name" > "$d/desc"
  { echo '%FILES%'; [ $# = 0 ] || printf '%s\n' "$@"; echo; } > "$d/files"
}
REPO=$BASE/repo            # the stand-in channel: $REPO/<channel>/os is a pacman repository named "omarchy"
template() { # template ROOT CHANNEL: what omarchy-refresh-pacman leaves in /etc/pacman.conf (no holds, no IgnorePkg)
  printf '# rendered template\n[options]\nHoldPkg = pacman glibc\nArchitecture = auto\nSigLevel = Never\nLocalFileSigLevel = Never\n\n[omarchy]\nServer = file://%s/%s/os\n' "$REPO" "$2" > "$1/etc/pacman.conf"
}
mkroot() { # a fake root with the r3 tools installed as the installer would, the usual packages and an edge pacman.conf
  local r p
  r=$(mktemp -d "$BASE/root.XXXXXX")
  mkdir -p "$(lib "$r")" "$r/etc/omarchy-k114s" "$r/etc/pacman.d/hooks" "$r/var/lib/omarchy-k114s" "$r/run" \
    "$r/boot/efi/EFI/Linux" "$r/boot/efi/EFI/BOOT" "$r/boot/efi/m1n1" "$r/boot/efi/k114s-repair" "$r/usr/lib/modules" "$r/var/cache/pacman/pkg" "$r/var/log"
  for p in k114s-lib.sh k114s-guard k114s-holds k114s-repackage k114s-recovery-set k114s-release-check k114s-release k114s-boot-success \
      k114s-modules-cleanup k114s-fdt k114s-binscan k114s-booted-esp release-criteria.conf kernel-config.required rivals.list \
      protected.list noextract.list extras.list esp-audit-ignore.list holds.default; do cp "$L/$p" "$(lib "$r")/"; done
  cp "$L/update-boot-ctxr-k114s" "$(lib "$r")/update-boot-ctxr"
  cp "$L"/0?-k114s-guard-*.hook "$r/etc/pacman.d/hooks/"
  cp "$L/release.conf" "$r/etc/omarchy-k114s/release.conf"
  printf '%s\n' $HELD > "$(lib "$r")/holds.list"
  template "$r" edge
  dbpkg "$r" linux-aurora 7.3.0.aurora17.v272-4
  dbpkg "$r" m1n1-aurora 1.6.1.aurora24.v272-3
  dbpkg "$r" uboot-aurora 2026.07.aurora6.j714s3-1
  dbpkg "$r" omarchy-aurora-firmware 20261014.j714s9-1
  dbpkg "$r" mesa-aurora 1:26.3.0_devel.20261109.j714s2.043a4c5-1
  dbpkg "$r" vulkan-aurora 1:26.3.0_devel.20261109.j714s2.043a4c5-1
  dbpkg "$r" hyprland-m5 0.57.2-2
  dbpkg "$r" omarchy-hyprland-titlebars 0.4.0-1
  dbpkg "$r" omarchy-dev 4.0.0.r7859.g9ac0883-1
  dbpkg "$r" omarchy-settings-dev 4.0.0.r7859.g9ac0883-1
  echo "$r"
}
guard() { # guard ROOT MODE [ESP_FREE] < targets
  local r=$1 mode=$2
  K114S_ROOT=$r K114S_ESP_FREE=${3:-} bash "$(lib "$r")/k114s-guard" "$mode" 2>&1
}
mkpkg() { # mkpkg TREE NAME VERSION OUTDIR [DEPEND...]: a real pacman package from the files in TREE; prints its path
  # MKPKG_EXTRA: further .PKGINFO lines ("conflict = x", "provides = y"), one per line
  local tree=$1 name=$2 version=$3 out=$4 d
  shift 4
  {
    echo "pkgname = $name"; echo "pkgbase = $name"; echo "pkgver = $version"; echo "pkgdesc = test package $name"
    echo "url = https://example.invalid/"; echo "builddate = 1700000000"; echo "packager = Unknown Packager"
    echo "size = $(du -sb "$tree" | cut -f1)"; echo "arch = any"; echo "license = MIT"
    for d in "$@"; do echo "depend = $d"; done
    [ -z "${MKPKG_EXTRA:-}" ] || printf '%s\n' "$MKPKG_EXTRA"
  } > "$tree/.PKGINFO"
  (cd "$tree" && find . -mindepth 1 ! -name .MTREE -printf '%P\n' | LC_ALL=C sort > "$BASE/.mkpkg.list" &&
    LANG=C bsdtar --uid 0 --gid 0 -cnf - --format=mtree --options='!all,use-set,type,uid,gid,mode,time,size,md5,sha256,link' -T "$BASE/.mkpkg.list" | gzip -c -n > .MTREE &&
    { printf '.PKGINFO\n.MTREE\n'; grep -v -x -e .PKGINFO -e .MTREE "$BASE/.mkpkg.list"; } > "$BASE/.mkpkg.order" &&
    LANG=C bsdtar --uid 0 --gid 0 --uname root --gname root --no-fflags -cnf - -T "$BASE/.mkpkg.order" | zstd -q -c > "$out/$name-$version-any.pkg.tar.zst")
  rm -f "$tree/.PKGINFO" "$tree/.MTREE"
  echo "$out/$name-$version-any.pkg.tar.zst"
}

# --- stand-in channel packages ------------------------------------------------------------------
# Small files with the properties release-criteria.conf looks for; nothing here is a real kernel.
GOOD_CONFIG='CONFIG_IKCONFIG=y
CONFIG_BT_RFCOMM=m
CONFIG_NETFILTER_XT_MATCH_HL=m
CONFIG_IP6_NF_MATCH_HL=m
CONFIG_IP6_NF_MATCH_RT=y
CONFIG_PKCS8_PRIVATE_KEY_PARSER=y'
kernel_image() { # kernel_image FILE RELEASE CONFIG [EXTRA TEXT]: an "image" with a banner and a built-in config
  # the banner twice, as a real image has it: first with a bare "#", then the text /proc/version shows
  { printf 'MZ\0\0'; printf 'Linux version %s (test@build) # SMP PREEMPT\n\0Linux version %s (test@build) #1 SMP PREEMPT\n\0' "$2" "$2"; printf '%s\0' "${4:-}"
    printf 'IKCFG_ST'; printf '%s\n' "$3" | gzip -c -n; printf 'IKCFG_ED'; } > "$1"
}
kernel_tree() { # kernel_tree TREE RELEASE DTB_VARIANT CONFIG [EXTRA]: the files of a linux-aurora package
  local m=$1/usr/lib/modules/$2
  mkdir -p "$m/dtbs" "$m/kernel/drivers/hid" "$m/kernel/drivers/net/wireless/apple/centauri/t6050"
  kernel_image "$m/vmlinuz" "$2" "$4" "${5:-}"
  echo linux-aurora > "$m/pkgbase"; echo kernel/builtin.ko > "$m/modules.builtin"
  [ "$3" = none ] || python3 -I "$T/mkfdt.py" "$m/dtbs/t6050-k114s.dtb" "$3"
  python3 -I "$T/mkfdt.py" "$m/dtbs/t6050-j714s.dtb" j714s
  echo "module $2" | zstd -q -c > "$m/kernel/drivers/hid/hid-magicmouse.ko.zst"
  echo "module $2" | zstd -q -c > "$m/kernel/drivers/net/wireless/apple/centauri/t6050/apple_centauri_t6050.ko.zst"
}
mkrepo() { # mkrepo CHANNEL PACKAGE_FILE...: (re)build the stand-in repository "omarchy" of that channel
  local d=$REPO/$1/os
  shift
  rm -rf "$d"; mkdir -p "$d"
  [ $# = 0 ] || cp "$@" "$d/"
  (cd "$d" && LC_ALL=C repo-add -q omarchy.db.tar.gz ./*.pkg.tar.zst >/dev/null 2>&1)
}
have() { local c; for c in "$@"; do command -v "$c" >/dev/null 2>&1 || return 1; done; }
