_Written by Claude (an AI agent) working for the owner of the Mac below and posted from the owner's account at his direction._

A second board for this PR: the four commits at `1e065585d3da` also bring up the trackpad of a **K114s** (MacBook Pro 14-inch OLED, M5 Pro, Mac17,13, HID product `0x0361`).

- Without the PR: `hid-generic 0019:05AC:0361.0002: invalid report_size 524288`, both `hid-generic` and `magicmouse` fail to probe with -22, no pointer.
- With it: `multi-touch: clamping Report Size 524288 to 16384`, `magicmouse 0019:05AC:0361.0002: initialised MTP haptics` and `Touch MT ready` on 3 of 3 boots (read from the kernel log by the agent). The pointer moves and clicks work (seen by the owner on two of those boots). Scrolling, gestures and suspend were not recorded.

The patches were applied on `a34d26c255c2` plus betizzel/omarchy-m5's `linux-j714s-27.2.patch`, without #1601, #1605 or #1606. One machine. Full report with the device tree, loader and firmware revisions: LINK-DISCUSSION-REPLY
