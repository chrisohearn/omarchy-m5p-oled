_Written by Claude (an AI agent) working for the owner of the Mac below and posted from the owner's account at his direction._

A second board for this PR: the four commits at `1e065585d3da` also bring up the trackpad of a **K114s** (MacBook Pro 14-inch OLED, M5 Pro, Mac17,13, HID product `0x0361`).

Without the PR (the kernel of betizzel/omarchy-m5 release 3, the same base; one boot, kernel log read by the agent) there is no pointer (seen by the owner):

```
hid-generic 0019:05AC:0361.0002: invalid report_size 524288
hid-generic 0019:05AC:0361.0002: probe with driver hid-generic failed with error -22
magicmouse 0019:05AC:0361.0002: probe with driver magicmouse failed with error -22
```

With it, on 3 of 3 boots on 2026-11-14 (kernel log read by the agent):

```
dockchannel-hid 294b30000.input: multi-touch: clamping Report Size 524288 to 16384
magicmouse 0019:05AC:0361.0002: initialised MTP haptics
rtkit-helper 294600000.mtp: RTKit: syslog message: touch_iface.c:512: Touch MT ready
dockchannel-hid 294b30000.input: Interface multi-touch is now ready
```

The pointer moves and clicks work (seen by the owner on two of those boots). The MTP firmware here logs `Version: AppleMTPFirmwareMac-6310.85.7~46` and `Personality: K2C1`; the fourth commit names K2C1 with `6320.86.1` for the K114c. No frames were captured on this board, so the 0x5a layout was not checked field by field here. Scrolling, gestures and suspend were not recorded.

The patches were applied with `patch -p1` (offsets, one hunk with fuzz 1) on `a34d26c255c2` plus betizzel/omarchy-m5's `linux-j714s-27.2.patch`. That base already contains #1601 and #1606; #1605 was not applied. One machine. Full report with the device tree, loader and firmware revisions: https://github.com/aurora-silicon/linux/discussions/142#discussioncomment-19621345
