_Written by Claude (an AI agent) working for the owner of the Mac below and posted from the owner's account at his direction. "agent-run" marks a command the agent ran on that Mac; "source read" is a file read in the named repository. One machine._

## What happens

On an image built from this repository, one Omarchy menu action (Update > Channel) removes the `IgnorePkg` pin and downgrades the kernel, m1n1 and U-Boot in the same command. The Stage 2 it leaves has no device tree for the Mac, so the next boot is not expected to start Linux. That was not tested: it was caught before a reboot.

`omarchy channel set <channel>` (what the menu entry runs), `omarchy refresh pacman` and `omarchy reinstall` all run `omarchy-refresh-pacman`, which copies Omarchy's channel template over `/etc/pacman.conf` and then runs `pacman -Syyuu --noconfirm` (omacom/omarchy `bin/omarchy-channel-set`, `bin/omarchy-reinstall-pkgs`, `bin/omarchy-refresh-pacman`, source read at v4.5.0 and at `quattro` `2bab9efd`). The Apple Silicon templates have no `IgnorePkg` line, so the block the image builder writes ("Test image only ... Keep these three lines: the channel has no Mac packages yet, so removing them can downgrade and break this Mac") is gone before the transaction is computed, and `-uu` is allowed to downgrade. Only the channel switch was run here. The other two commands are from the source.

The README's update check covers `omarchy update` with the pin in place. This path removes the pin first.

## What it did here

Release 3 package set, 2026-11-14, a switch to the Edge channel from the Omarchy menu. The journal has the menu starting `omarchy-channel-set edge` at 14:11:01, and the `pacman.conf` the refresh wrote is byte-identical to Omarchy's Apple Silicon Edge template (both agent-run). From `pacman.log` (agent-run; the eight downgrades and three hooks, local time, time stamps shortened, all other lines left out):

```
[14:11:04] Running '/usr/bin/pacman -Syyuu --noconfirm'
[14:11:19] downgraded mesa-aurora (1:26.3.0_devel.20261109.j714s2.043a4c5-1 -> 1:26.3.0_devel.20261107.231485.b7b03c5b3b8-2)
[14:11:30] downgraded uboot-aurora (2026.07.aurora6.j714s3-1 -> 2026.07.aurora6-1)
[14:11:30] downgraded m1n1-aurora (1.6.1.aurora24.v272-3 -> 1.6.1.aurora23-2)
[14:11:30] downgraded linux-aurora (7.3.0.aurora17.v272-4 -> 7.2.11.aurora16-1)
[14:11:31] downgraded omarchy-settings (4.5.0-3.7141 -> 4.5.0-3)
[14:11:32] downgraded omarchy (4.5.0-3.7141 -> 4.5.0-3)
[14:11:32] downgraded omarchy-aurora-firmware (20261014.j714s9-1 -> 20261014-7)
[14:11:32] downgraded vulkan-aurora (1:26.3.0_devel.20261109.j714s2.043a4c5-1 -> 1:26.3.0_devel.20261107.231485.b7b03c5b3b8-2)
[14:11:33] running '11-omarchy-mac-saved-modules.hook'...
[14:11:33] Moving the running kernel's saved modules (7.3.0-17.v272-4-ARCH) to /usr/lib/modules/.old, as linux-modules-cleanup does at boot, so m1n1 carries the device trees of 7.2.11-16-1-ARCH. [...]
[14:11:47] running '95-m1n1-install.hook'...
[14:11:47] m1n1 updated at /run/.system-efi/m1n1/boot.bin
[14:11:47] running '96-omarchy-j714s-boot-ctxr.hook'...
```

- Edge's `linux-aurora 7.2.11.aurora16-1` ships 115 device trees and none for T6050 (agent-run, the cached package's file list). `update-m1n1` takes its device trees from the newest kernel's `dtbs` directory (agent-run, the installed script), so the Stage 2 it wrote can carry no tree for an M5 Pro. Your `boot-ctxr` hook then copied it over `m1n1/boot-ctxr.bin`, as its helper does when the package has no separate `m1n1-ctxr.bin` (`installer/patches-j714s/0004`, source read; Edge's `m1n1-aurora` has none).
- `11-omarchy-mac-saved-modules.hook` (from `omarchy-mac-boot`) moved the running kernel's modules to `/usr/lib/modules/.old`, and the UKI was rebuilt from the 7.2.11 kernel.
- It was noticed before a reboot. Stage 2 was rebuilt from files still on the machine. Six of the eight packages (all but `omarchy` and `omarchy-settings`, which the switch then replaced with the `-dev` pair) were restored from the install-time snapshot, because the image's package archives were not in the pacman cache. The Mac has booted twice since (agent-run).

The Mac is a K114s (MacBook Pro 14-inch OLED, M5 Pro) carrying its own device tree and a trackpad-fix kernel on top of your image, so the Stage 2 that was overwritten was ours. Nothing in the mechanism is specific to that: it is the image's pin and `boot-ctxr` hook, the Edge channel's packages, asahi-scripts' `update-m1n1` and Omarchy's scripts. On a J714s the same transaction would replace the J714s kernel, loader and Stage 2 the same way. Not reproduced on a J714s. Release 4 was not installed here; nothing in this repository at `42edf84` mentions a channel switch, `refresh pacman` or a `pre-refresh-pacman` hook (source read).

## Ways to close it

1. **A pacman pre-transaction hook** in `/etc/pacman.d/hooks/`, which the template copy does not touch. It refuses any transaction that would install, upgrade, downgrade or remove the boot packages unless a marker file says the change is deliberate. This stops the path whatever happened to `pacman.conf`. An implementation with fake-root tests is in https://github.com/chrisohearn/omarchy-m5p-oled (`linux/00-k114s-hold-guard.hook`, `linux/hold-guard`, `tests/linux/test-persist.sh`), MIT. It has been installed on this Mac since the incident. No transaction since has named those packages, so pacman has not run it yet: it is tested in a fake root only.
2. **A `pre-refresh-pacman` hook** that writes the pin back. Omarchy runs `~/.config/omarchy/hooks/pre-refresh-pacman.d/*` after the template copy and before the transaction, and its sample names "extra IgnorePkg lines" as a use. It is per user, so the image would have to seed it for the first user. It is also not a stop: `omarchy-hook` prints "Hook failed" and carries on, so a hook that fails (it needs `sudo` to write `pacman.conf`) lets the transaction run without the pin (source read). Ours is a one-line hook that calls `linux/apply-holds`. It is installed here and no refresh has run since.
3. **Keep the set's package archives on the image**, so a downgraded Mac can be put back with `pacman -U` without a download or a snapshot. `docs/duplicate-boot-ids.md` takes them from the release's inputs bundle; they are not on the installed system.
4. **A line in the README** until one of these ships: on this image, do not change channel from the Omarchy menu, and do not run `omarchy refresh pacman` or `omarchy reinstall`.

The loss of the pin on a refresh is Omarchy's side of this. An open issue there describes the same template copy dropping hardware repositories (omacom/omarchy#9853).
