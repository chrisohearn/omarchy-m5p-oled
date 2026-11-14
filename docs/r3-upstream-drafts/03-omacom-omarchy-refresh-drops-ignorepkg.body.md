### System details

MacBook Pro 14-inch M5 Pro (Mac17,13, `apple,k114s`), platform `aarch64-apple`. Before the switch: `omarchy 4.5.0-3.7141` with `[omarchy]` on the edge repository; after it: `omarchy-dev 4.0.0.r7859.g9ac0883-1`. **Not an official Omarchy install and not a supported model:** a third-party image (betizzel/omarchy-m5, release omarchy-j714s-3), built from a candidate set with a patched copy of omarchy-mac-installer's image builder.

### What's wrong?

_Written by Claude (an AI agent) working for the owner of this Mac and posted from the owner's account at his direction. "agent-run" marks a command the agent ran on the Mac. "source read" means a file read in `quattro` at `2bab9efd`, omarchy-mac-installer `main` at `c07e54c2` or omarchy-mac-pkgs `main` at `28abebee`. One machine, and an unsupported one._

`omarchy channel set`, `omarchy refresh pacman` and `omarchy reinstall` replace `/etc/pacman.conf` with the channel template, which drops every `IgnorePkg` line, and in the same command run `pacman -Syyuu --noconfirm`. That is documented: the manual puts `IgnorePkg` lines in a `pre-refresh-pacman` hook. But omarchy-mac-installer's image builder writes its hold into `pacman.conf` itself, with a comment that says to keep it. So the first channel switch on such an image removes the hold and runs the transaction it was there to stop. On this Mac that replaced the kernel, m1n1 and U-Boot with the channel's builds, whose kernel package has no device tree for it, and the update's boot verification then passed.

**The two first-party pieces** (source read):

- `image-builder/builder/test_image_pin.py` writes a marked `IgnorePkg` block into `/etc/pacman.conf` of every image built from a candidate set. Its text: "Keep these three lines: the channel has no Mac packages yet, so removing them can downgrade and break this Mac". As written upstream it holds only the packages built from the set's own commits (`omarchy omarchy-mac omarchy-settings` in the README's example); the README says "Everything else follows the channel: the kernel, the closure, and the boot package when the set takes it from the channel."
- `bin/omarchy-refresh-pacman` copies the rendered channel template over `/etc/pacman.conf` (line 48), runs the `pre-refresh-pacman` user hook, then `omarchy-update-pacman -Syyuu --noconfirm` (line 68). `omarchy-channel-set` and `omarchy-reinstall-pkgs` call it. No template carries an `IgnorePkg` line.

`image-builder/README.md` already expects the two to meet: "On this runtime `omarchy-refresh-pacman` and `omarchy-channel-set` leave an Apple Silicon Mac's pacman.conf alone (no aarch64 channel is qualified yet); once they rewrite it from the template, the pin goes with it." They rewrite it now: `default/pacman/aarch64-apple/` has stable, rc and edge templates, and the refresh rewrote this Mac's file (agent-run: the journal shows the `cp` of the rendered file). The hook could put the lines back, but it is per user, only an inactive `.sample` ships, and the image builder installs none. This was not tried on an image from the unpatched builder.

**What is third-party here.** The builder that made this image carries a patch (betizzel/omarchy-m5, `installer/patches/0019`) that extends the same block to the packages its set takes from pull requests: kernel, m1n1, U-Boot, Mesa, Hyprland and firmware. So on this Mac the block held the boot chain; an image from the unpatched builder holds the runtime only. The eight packages below were that project's builds, versioned above the channel's. None of that is Omarchy's to fix. The runtime itself is Omarchy source commit `a948d8a6` without source changes, according to that project's build record; `omarchy-refresh-pacman` and `omarchy-channel-set` are identical at that commit, at tag `v4.5.0` and at `quattro` `2bab9efd` (agent-run, `git diff`).

**What it did here** (agent-run: `pacman.log` and the journal, 2026-11-14; the journal shows the menu's `omarchy-channel-set edge`):

```
Running '/usr/bin/pacman -Syyuu --noconfirm'
downgraded uboot-aurora (2026.07.aurora6.j714s3-1 -> 2026.07.aurora6-1)
downgraded m1n1-aurora (1.6.1.aurora24.v272-3 -> 1.6.1.aurora23-2)
downgraded linux-aurora (7.3.0.aurora17.v272-4 -> 7.2.11.aurora16-1)
downgraded omarchy (4.5.0-3.7141 -> 4.5.0-3)
```

plus `omarchy-settings`, `omarchy-aurora-firmware`, `mesa-aurora` and `vulkan-aurora`: eight packages. Apart from sudo's password prompt nothing asks, and nothing says a hold was removed; the only notice is pacman's own package list as it proceeds. The channel's `linux-aurora 7.2.11.aurora16-1` has no device tree for this SoC (0 of the 115 in the package are T6050), so `95-m1n1-install.hook` wrote `m1n1/boot.bin` without one, and a hook from the image rewrote the Stage 2 file this Mac boots from it. The Mac was not rebooted in that state, so "it would not have booted" is an inference from the missing device tree, not a test. It was repaired from the refresh's own `pacman.conf.bak` and an install-time snapshot.

**The boot verification passed** (agent-run, journal). The switch ends in `omarchy update`, which ran `omarchy-lifecycle-dispatch update-verify` at 14:12:14 local time. What it printed was not kept, but the journal's sudo trail shows `omarchy-apple-silicon-boot-check` (omarchy-mac-boot 20261104-1) reaching its last compare of `m1n1/boot.bin`, and `update-verify` then taking its pass branch (`rm -f /boot/.omarchy-mac-rolled-back`). The check proves that `boot.bin` is m1n1, the installed kernel's device trees and U-Boot (source read). It does not check that one of those device trees is for the Mac it is running on. That part belongs to omarchy-mac-pkgs and can be filed there if it is useful.

#9853 describes the same copy dropping hardware repositories on T2 Macs (fix proposed in #9878). This is the `[options]` side of it.

**Possible fixes, smallest first:**

1. In `omarchy-refresh-pacman`, carry the `IgnorePkg` and `IgnoreGroup` lines of the previous file's `[options]` section into the rendered file before copying it, and print which packages stay held. This changes the documented behaviour; the hook sample names "extra IgnorePkg lines" as something users re-add after every refresh.
2. Or stop before the transaction when it would downgrade a package the previous configuration ignored: list them and ask, and refuse when unattended.
3. Or, on `aarch64-apple` only, ask before a refresh downgrades the installed kernel or boot loader packages.
4. Or leave the refresh alone and have the image builder put its pin where a refresh keeps it. Today that is only the per-user hook.

If one of these shapes is wanted, the owner can send a pull request with a `test/shell.d` case for it. None has been written yet.
