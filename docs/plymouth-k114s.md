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

An Arch Plymouth upgrade replaces the local build. Its `usr/lib/initcpio/*` files trigger only the K114s image hook
(`/etc/pacman.d/hooks/90-mkinitcpio-apple-install.hook`, `k114s-uki-install`: `linux-k114s` and `linux-k114s-r3b`); the generic
`90-mkinitcpio-install.hook` is gated off on this Mac (`limine-apple-gate --not-mac`), so the upgrade does not rebuild the held
`linux-aurora` image (the rebuild-all trap in `docs/r3-display-d5-d9.md` predates that hook). The only loss is the #262 fix until
the rebuild below.

When Arch Linux ARM ships a newer Plymouth in `extra`, the nightly rebuilds it from that release's recipe
and pins the new source commit and checksum. Check whether the release already fixes #262 before carrying the
patch forward. If it does, retire the local package. Otherwise, keep the `plymouth-k114s` marker and set the
local `pkgrel` to the new distro release plus `.1`. Build and verify the package before staging it for the
guarded package trial.

## Closing #262

The local build went on during boot `d2aeef8bf3234cec8d6cc31f42de69f8` (2026-11-25, after the PR #3105 trial). Before it, `plymouth-start.service`
dumped core on 3 of about 9 boots. The owner's rule (2026-11-25): #262 closes, with the evidence, once **6 boots in a row**
after that boot run the local build (`linux/plymouth-k114s-status` exit 0) and none logs
`plymouth-start.service: Main process exited, code=dumped`. Count from the journal, oldest first. A crash on the local build
resets the count and reopens the investigation instead.
