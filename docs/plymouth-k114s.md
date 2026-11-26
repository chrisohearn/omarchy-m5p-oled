# Plymouth on K114s

The local Plymouth package addresses the crash in [issue #262](https://github.com/chrisohearn/omarchy-m5p-oled/issues/262).
When Apple DCP takes over from simpledrm, Plymouth now tells the splash to release the renderer's keyboard before
freeing it.

[The recipe](../packaging/plymouth-k114s/PKGBUILD) uses Arch's `26.134.222-3` packaging and pins the
Plymouth release commit. The package keeps the name `plymouth`. Pacman orders the local release
`26.134.222-3.1` after `26.134.222-3` and before `26.134.222-4`.

## Build and check

1. On aarch64, with the recipe's build dependencies available, copy `packaging/plymouth-k114s/` into a fresh
   `mktemp -d "$HOME/k114s-build/build/plymouth-k114s.XXXXXXXX"` directory. Run `makepkg` there as an ordinary user.
2. Keep the package and its SHA-256 under `~/k114s-build`. Installation can trigger an initramfs and UKI rebuild.
   Use the guarded package trial in the [nightly runbook](nightly-rollout.md) for installation and rollback.
3. Run `linux/plymouth-k114s-status` after the package update. Exit 0 means the installed package carries the
   local marker. Exit 1 means the installed package lacks it. Exit 2 means the installed package or its version
   could not be read.

When Arch Linux ARM ships a newer Plymouth in `extra`, the nightly rebuilds it from that release's recipe
and pins the new source commit and checksum. Check whether the release already fixes #262 before carrying the
patch forward. If it does, retire the local package. Otherwise, keep the `plymouth-k114s` marker and set the
local `pkgrel` to the new distro release plus `.1`. Build and verify the package before staging it for the
guarded package trial.
