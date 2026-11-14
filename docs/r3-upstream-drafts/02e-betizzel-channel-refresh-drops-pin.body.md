_Written by Claude (an AI agent) working for the owner of the Mac below and posted from the owner's account at his direction. "agent-run" marks a command the agent ran on that Mac; "source read" is a file read in the named repository. One machine._

## What happens

On an image built from this repository, one Omarchy menu action removes the `IgnorePkg` pin and downgrades the whole boot chain in the same command. The next boot does not start Linux.

The actions are `omarchy channel set <channel>`, `omarchy refresh pacman` and `omarchy reinstall`. All three run `omarchy-refresh-pacman`, which copies Omarchy's channel template over `/etc/pacman.conf` and then runs `pacman -Syyuu --noconfirm` (omacom/omarchy `bin/omarchy-refresh-pacman`, source read). The template has no `IgnorePkg` line, so the block the image builder writes ("Test image only ... Keep these three lines: the channel has no Mac packages yet, so removing them can downgrade and break this Mac") is gone before the transaction is computed, and `-uu` is allowed to downgrade.

The README's update check covers `omarchy update` with the pin in place. This path removes the pin first.

## What it did here

Release 3 package set, 2026-11-14, a switch to the Edge channel from the Omarchy menu. From `pacman.log` (agent-run):

```
[14:11:04] Running '/usr/bin/pacman -Syyuu --noconfirm'
downgraded mesa-aurora (1:26.3.0_devel.20261109.j714s2.043a4c5-1 -> 1:26.3.0_devel.20261107.231485.b7b03c5b3b8-2)
downgraded uboot-aurora (2026.07.aurora6.j714s3-1 -> 2026.07.aurora6-1)
downgraded m1n1-aurora (1.6.1.aurora24.v272-3 -> 1.6.1.aurora23-2)
downgraded linux-aurora (7.3.0.aurora17.v272-4 -> 7.2.11.aurora16-1)
downgraded omarchy-settings (4.5.0-3.7141 -> 4.5.0-3)
downgraded omarchy (4.5.0-3.7141 -> 4.5.0-3)
downgraded omarchy-aurora-firmware (20261014.j714s9-1 -> 20261014-7)
downgraded vulkan-aurora (1:26.3.0_devel.20261109.j714s2.043a4c5-1 -> 1:26.3.0_devel.20261107.231485.b7b03c5b3b8-2)
running '95-m1n1-install.hook'...   m1n1 updated at /run/.system-efi/m1n1/boot.bin
running '96-omarchy-j714s-boot-ctxr.hook'...
```

- Edge's `linux-aurora 7.2.11.aurora16-1` ships 115 device trees and none for T6050 (agent-run, the cached package's file list). `update-m1n1` therefore built a Stage 2 with no tree for an M5 Pro, and the `boot-ctxr` hook copied it over `m1n1/boot-ctxr.bin`.
- `11-omarchy-mac-saved-modules.hook` moved the running kernel's modules to `/usr/lib/modules/.old`, and the UKI was rebuilt from the 7.2.11 kernel.
- It was noticed before a reboot. Stage 2 was rebuilt from files still on the machine and the six boot packages were restored from the install-time snapshot, because the image's package archives were not in the pacman cache. The Mac has booted twice since.

The Mac is a K114s (MacBook Pro 14-inch OLED, M5 Pro) carrying its own device tree and trackpad kernel on top of your image, so the Stage 2 that was overwritten was ours. The mechanism above uses only your packages, your hook and Omarchy's scripts; on a J714s the same transaction would replace the J714s kernel, loader and Stage 2 the same way. Not reproduced on a J714s.

## Ways to close it

1. **A pacman pre-transaction hook** in `/etc/pacman.d/hooks/`, which the template copy does not touch. It refuses any transaction that would install, downgrade or remove the pinned boot packages unless a marker file says the change is deliberate. This stops the path whatever happened to `pacman.conf`. An implementation with fake-root tests is in https://github.com/chrisohearn/omarchy-m5p-oled (`linux/00-k114s-hold-guard.hook`, `linux/hold-guard`, `tests/linux/`), MIT. It is installed on this Mac since the incident; it has not yet had to stop a real transaction.
2. **A `pre-refresh-pacman` hook** that writes the pin back. Omarchy runs `~/.config/omarchy/hooks/pre-refresh-pacman.d/*` after the template copy and before the transaction, and its sample names "extra IgnorePkg lines" as a use. It is per user, so the image would have to seed it for the first user. Ours is `linux/apply-holds`.
3. **Keep the set's package archives on the image**, so a downgraded Mac can be put back with `pacman -U` instead of from a snapshot.
4. **A line in the README** until one of these ships: do not change channel, refresh pacman or reinstall packages from the Omarchy menu on this image.

The loss of the pin on refresh is also being reported to omacom/omarchy (LINK-OMACOM), where an open issue describes the same template copy dropping hardware repositories (omacom/omarchy#9853).
