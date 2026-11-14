### System details

MacBook Pro 14-inch M5 Pro (Mac17,13, `apple,k114s`), platform `aarch64-apple`, edge channel, `omarchy 4.5.0-3.7141` when it happened. **Not an official Omarchy install and not a supported model:** the image comes from betizzel/omarchy-m5 (release omarchy-j714s-3), built with omarchy-mac-installer's image builder from a candidate set. The scripts involved are Omarchy's own, unchanged.

### What's wrong?

_Written by Claude (an AI agent) working for the owner of this Mac and posted from the owner's account at his direction. "agent-run" marks a command the agent ran on the Mac; "source read" is `quattro` at `2bab9efd` and omarchy-mac-installer `main` at `c07e54c2`. One machine._

`omarchy channel set`, `omarchy refresh pacman` and `omarchy reinstall` remove every `IgnorePkg` line from `/etc/pacman.conf` and then, in the same command, run a transaction that may downgrade with `--noconfirm`. On a Mac whose image holds its boot packages with such a line, one menu choice replaces the kernel, m1n1 and U-Boot with builds that cannot boot it. Nothing is listed and nothing asks first.

**The mechanism is first-party on both sides** (source read):

- omarchy-mac-installer's `image-builder/builder/test_image_pin.py` writes a marked `IgnorePkg` block into `/etc/pacman.conf` of every image built from a candidate set. Its own text: "Keep these three lines: the channel has no Mac packages yet, so removing them can downgrade and break this Mac", and "The runtime's own pacman templates carry no pin".
- `bin/omarchy-refresh-pacman` copies the rendered channel template over `/etc/pacman.conf` (line 48), runs the `pre-refresh-pacman` user hook, then `omarchy-update-pacman -Syyuu --noconfirm` (line 68). `omarchy-channel-set` and `omarchy-reinstall-pkgs` call it.

So the first channel switch on such an image deletes the pin and applies the downgrade the pin existed to prevent. The user hook can put the lines back, but it lives in `~/.config` and has to exist before the first refresh; nothing creates it.

**What it did here** (agent-run, `pacman.log`, 2026-11-14, a switch to edge from the menu):

```
Running '/usr/bin/pacman -Syyuu --noconfirm'
downgraded uboot-aurora (2026.07.aurora6.j714s3-1 -> 2026.07.aurora6-1)
downgraded m1n1-aurora (1.6.1.aurora24.v272-3 -> 1.6.1.aurora23-2)
downgraded linux-aurora (7.3.0.aurora17.v272-4 -> 7.2.11.aurora16-1)
downgraded omarchy (4.5.0-3.7141 -> 4.5.0-3)
```

plus `omarchy-settings`, `omarchy-aurora-firmware`, `mesa-aurora` and `vulkan-aurora`: eight packages. The channel's `linux-aurora 7.2.11.aurora16-1` has no device tree for this SoC (0 of its 115 are T6050), so `update-m1n1` wrote a Stage 2 without one. The switch then ran its `update-verify` step (in the journal at 14:12:14); what that printed was not kept. The damage was caught before a reboot and repaired from the refresh's own `pacman.conf.bak` and an install-time snapshot.

The eight packages were third-party builds, and that part is not Omarchy's to fix. The report is about the step before it: holds that an image, or a user, put in `pacman.conf` on purpose are removed and the downgrade runs unattended. #9853 describes the same copy dropping hardware repositories on T2 Macs (fix proposed in #9878); this is the `[options]` side of it, with a worse outcome on a Mac because the boot chain is a package.

**Possible fixes, smallest first:**

1. In `omarchy-refresh-pacman`, carry the `IgnorePkg` and `IgnoreGroup` lines of the previous file's `[options]` section into the rendered file before copying it, and print which packages stay held. The hook sample already names "extra IgnorePkg lines" as what users re-add after every refresh.
2. Or stop before the transaction when it would downgrade a package the previous configuration ignored: list them and ask, and refuse when unattended.
3. Or, on `aarch64-apple` only, ask before a refresh downgrades the installed kernel or boot loader packages.

A related gap, from reading `omarchy-apple-silicon-boot-check` (not run): it proves `m1n1/boot.bin` matches the installed packages, but not that the installed kernel has a device tree for the Mac it is running on, so a Stage 2 that cannot boot this Mac can pass.

If one of these shapes is wanted, the owner can send a pull request with a `test/shell.d` case for it. None has been written yet.
