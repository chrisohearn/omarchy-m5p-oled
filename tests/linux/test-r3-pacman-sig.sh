#!/bin/bash
# The signature check of a REAL `pacman -U`, and how k114s-release's signed_ok compares with it (issue #16).
#   usage: test-r3-pacman-sig.sh [LINUX_DIR]
#
# A replica, not the Mac: bubblewrap gives uid 0 in a user namespace; pacman installs a one-file stand-in package
# into a throwaway root, with a throwaway gpg keyring as its GPGDir and no hooks. Nothing on the host is written.
# It shows what pacman itself accepts under `LocalFileSigLevel = Optional` (Omarchy's value) and `Required`, and
# that signed_ok (the real gpg path, same keyring) refuses everything Optional refuses, plus the unsigned archive,
# which Optional lets through: that is the gap signed_ok exists to close.
# Needs bwrap (user namespaces), pacman, gpg, bsdtar, zstd.
set -u
. "$(dirname "$0")/r3-lib.sh" "${1:-}"
skip() { echo "r3 pacman signature tests: SKIPPED ($1)"; exit 0; }
have bwrap pacman gpg bsdtar zstd || skip "bwrap, pacman, gpg, bsdtar and zstd are needed"
bwrap --unshare-user --uid 0 --gid 0 --ro-bind / / true 2>/dev/null || skip "bubblewrap cannot make a user namespace here"
W=$BASE/sig; R=$W/root; g=$R/etc/pacman.d/gnupg
mkdir -p "$R/var/lib/pacman" "$R/var/cache/pacman/pkg" "$g" "$W/hooks" "$W/a" "$W/b"; chmod 700 "$g"
G() { gpg --homedir "$g" --batch --no-tty --quiet "$@" 2>/dev/null; }
G --passphrase '' --quick-gen-key 'K114s test signer <signer@example.invalid>' ed25519 sign never
G --passphrase '' --quick-gen-key 'K114s stranger <stranger@example.invalid>' ed25519 sign never
fpr() { G --with-colons --list-keys "$1" | awk -F: '$1 == "fpr" { print $10; exit }'; }
printf '%s:6:\n' "$(fpr signer@example.invalid)" | G --import-ownertrust     # ultimate: the state a pacman master key's signed key ends up in
printf '%s:2:\n' "$(fpr stranger@example.invalid)" | G --import-ownertrust   # in the keyring, trust undefined
mkpkg() { # mkpkg DIR CONTENT -> DIR/sigtest.pkg.tar.zst
  printf 'pkgname = sigtest\npkgver = 1-1\npkgdesc = stand-in\narch = any\nbuilddate = 1700000000\npackager = test\nsize = 1\n' > "$1/.PKGINFO"
  echo "$2" > "$1/f"; (cd "$1" && bsdtar --zstd -cf ../sigtest-$(basename "$1").pkg.tar.zst .PKGINFO f)
}
mkpkg "$W/a" one; mkpkg "$W/b" two
A=$W/sigtest-a.pkg.tar.zst; B=$W/sigtest-b.pkg.tar.zst
conf() { printf '[options]\nRootDir = %s\nDBPath = %s/var/lib/pacman\nCacheDir = %s/var/cache/pacman/pkg\nGPGDir = %s\nHookDir = %s/hooks\nLogFile = %s/pacman.log\nArchitecture = auto\nSigLevel = Required\nLocalFileSigLevel = %s\n' "$R" "$R" "$R" "$g" "$W" "$W" "$1" > "$W/pacman.conf"; }
pu() { # pu LEVEL ARCHIVE -> 0 when real pacman -U installs it
  conf "$1"; rm -rf "$R/var/lib/pacman/local" "$R/f"
  out=$(bwrap --unshare-user --uid 0 --gid 0 --ro-bind / / --bind "$W" "$W" --dev /dev --proc /proc pacman --config "$W/pacman.conf" --noconfirm -U "$2" 2>&1); local s=$?
  [ "$s" = 0 ] && [ -f "$R/f" ] && return 0
  return 1
}
eval "$(sed -n '/^signed_ok() {/,/^}/p' "$L/k114s-release")"
ROOT=$R; unset K114S_SIGCHECK K114S_TEST K114S_ROOT
sg() { rm -f "$2.sig"; [ -z "$1" ] || G --local-user "$1" --detach-sign -o "$2.sig" "$2"; }
both() { # both NAME ARCHIVE WANT-OPTIONAL WANT-REQUIRED WANT-SIGNED_OK  (0 = accepted)
  pu Optional "$2"; local o=$?; pu Required "$2"; local r=$?; signed_ok "$2"; local s=$?
  ok "$1: pacman -U (LocalFileSigLevel Optional / Required), signed_ok" "$o $r $s" "$3 $4 $5"
}
sg signer@example.invalid "$A";                  both "valid signature, trusted key" "$A" 0 0 0
sg "" "$A";                                      both "no signature" "$A" 0 1 1
sg stranger@example.invalid "$A";                both "valid signature, key of undefined trust" "$A" 1 1 1
sg signer@example.invalid "$B"; cp "$A" "$W/x.pkg.tar.zst"; cp "$B.sig" "$W/x.pkg.tar.zst.sig"
                                                 both "signature of another archive" "$W/x.pkg.tar.zst" 1 1 1
: > "$A.sig";                                    both "empty .sig" "$A" 1 1 1
finish "r3 pacman signature tests (replica: real pacman -U in a user namespace)"
