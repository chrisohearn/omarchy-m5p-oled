# Reporting upstream

Results and fixes for this model go back to the projects they belong to, through each project's
normal public channel, from the owner's GitHub account.

## What is sent

1. **Hardware confirmations** for Mac17,13 / `apple,k114s` / board-id 0x14 when this machine
   actually shows a capability. Each says what was tested, the date, the exact kernel, loader,
   device tree and firmware revisions, the steps, the result and the limits.
2. **Minimal fixes** with their source, dependencies, why the K114s needs them, the tests run and
   the hardware status. A fix that only passed software tests is offered as hardware-untested.
3. **Regressions or failures** met when applying upstream changes to the K114s, with our own
   local changes named.

## Rules

- Evidence is labelled: owner-observed (seen or photographed by the owner), agent-run (a command
  run by the AI agent on the machine or a build host), or emulator/replica. One machine is not an
  independent reproduction.
- Nothing is claimed to work on the Mac because it compiled or booted in QEMU.
- Read the destination's contributing rules, templates and AI policy first. Prefer the existing
  thread. One canonical report per result, with a cross-link only where needed.
- Before sending, check the registry below and the destination for an earlier report of the same
  result. After sending, read the post back and record its URL.
- Original authors keep their authorship. No `Signed-off-by`, `Tested-by` or legal assent is
  written on anyone's behalf. A CLA or DCO that needs the owner is the owner's action.
- Never included: Apple firmware, tickets or calibration, MAC addresses, network names, serial
  numbers, credentials, backups, unredacted logs or photos.
- Posts written by the AI agent say so.

## States

`candidate` → `built/tested` → `hardware-confirmed` → `submitted` → `acknowledged` → `merged`.
The registry is `ledger/outgoing.json`.

## Candidates

| Item | Destination | Depends on | State |
| --- | --- | --- | --- |
| K114s boots: NVMe root, keyboard, boot framebuffer; trackpad fails as on K116s; board-id 0x14 gives the N1 platform ID `0x00146050` | aurora-silicon/linux, the M5 MacBook Pro hardware discussion | nothing further | **submitted** 2026-11-14: [discussion 142 comment](https://github.com/aurora-silicon/linux/discussions/142#discussioncomment-19618807) |
| K114s follow-up on the `K114S-R1` kernel: trackpad with #1568, N1 Wi-Fi with platform ID `0x00146050`, Bluetooth controller, SMC sensors, battery; USB-C not tested with a device | aurora-silicon/linux, the same discussion, as a reply under the first report | nothing further | **submitted** 2026-11-14: [discussion 142 reply](https://github.com/aurora-silicon/linux/discussions/142#discussioncomment-19621345) |
| #1568 brings up the K114s trackpad (HID product 0x0361): a second board for that pull request | aurora-silicon/linux #1568 | nothing further | **submitted** 2026-11-14: [comment](https://github.com/aurora-silicon/linux/pull/1568#issuecomment-6885700857) |
| HID product 0x0361 for the Trackpad26 gate of #1830 | aurora-silicon/linux | the r1a kernel moving the pointer on this Mac | candidate |
| K114s N1, USB-C and SMC device tree sections | aurora-silicon/linux | N1 and SMC are hardware-confirmed and offered in the discussion reply; a pull request waits for a USB device enumerating on this Mac, the maintainers' preferred form and the owner's sign-off | candidate |
| K114s on release 3: what works, and `apple,k114s` admission in the installer build on offer | betizzel/omarchy-m5 | nothing further; a pull request only if the maintainer asks | **submitted** 2026-11-14: [issue 10](https://github.com/betizzel/omarchy-m5/issues/10) |
| `hyprland-m5 0.57.2-2` changes `CMonitor`'s layout under the stock commit hash, so the stock titlebars plugin loads and Hyprland aborts | betizzel/omarchy-m5 | nothing further | **submitted** 2026-11-14: [issue 8](https://github.com/betizzel/omarchy-m5/issues/8) |
| `linux-aurora` recipe config: no `hl`/`rt` matches (ufw IPv6), no RFCOMM, no `pkcs8_key_parser` | betizzel/omarchy-m5 | nothing further; the result of a kernel with the options follows its first boot | **submitted** 2026-11-14: [issue 9](https://github.com/betizzel/omarchy-m5/issues/9) |
| A channel switch or `omarchy refresh pacman` removes the image's `IgnorePkg` pin and downgrades the kernel, m1n1 and U-Boot | betizzel/omarchy-m5 | nothing further | **submitted** 2026-11-14: [issue 11](https://github.com/betizzel/omarchy-m5/issues/11) |
| `speakerguardd-gate` waits its full 15 s per call when the device tree has no sound node | aurora-silicon/speakerguardd | nothing further | **submitted** 2026-11-14: [issue 183](https://github.com/aurora-silicon/speakerguardd/issues/183) |
| Channel switch and refresh drop `IgnorePkg` holds, then downgrade the boot packages unattended | omacom/omarchy | nothing further; a pull request only if the maintainers pick a shape | **submitted** 2026-11-14: [issue 18954](https://github.com/omacom/omarchy/issues/18954) |
| Electron 44 crash in libyuv's SME row function: comment on pingdotgg/t3code #11731 | pingdotgg/t3code | not part of the 2026-11-14 posting step | candidate (drafted) |
| Electron 44.x backport of the libyuv fix | electron/electron | Electron's AI policy: the owner files it himself | candidate (held) |
