# Trackpad click strength (issue #47)

Status 2026-11-15: facts read, tooling ready, values not chosen (they need the owner's finger).

## What is true now (agent-run, read-only)

- The pad is HID product 0x0361 ("Apple MTP multi-touch"), bound to `magicmouse`; dmesg shows
  `initialised MTP haptics` and the MTP firmware logs `Actuator initialized`.
- `hid_apple_mtp_haptic` is loaded (held by `hid_magicmouse`) and has no module parameters.
- The booted device tree has no `apple,click-strength` anywhere and no `actuator` child node.
  The `input@8000` node (`mtp_hid`) has the children `keyboard`, `kiwi` and `multi-touch` only.
- aurora-silicon/linux #1959 (open, IronsideXXVI, tested on a J604 only) is the only upstream change
  touching this: it adds `click_strength=<press>,<release>` (0644, 1-255 each, `0,0` = unchanged),
  written to the live actuator at once and again at each resume, over the device tree values. It
  edits only `drivers/hid/hid-apple-mtp-haptic.c`.

## Where the property goes

The driver reads `apple,click-strength = <press release>` from a child node named `actuator` of the
haptic HID device's parent node, which is `mtp_hid` (`input@8000`). The reference is the J413 tree:

    &mtp_hid {
        actuator {
            apple,click-strength = <0xc0 0x6e>;   /* J413 values; NOT for the K114s */
        };
    };

For the K114s the same child node has to be added to the T6050 `&mtp_hid` override in
`dts/t6050-k114s-common.dtsi` (`&mtp_hid { actuator { apple,click-strength = <P R>; }; };`).
`tests/linux/mkfdt.py` only builds a fake tree for the r3 tests; touch it only if a test needs the node. The values stay open until the owner has judged them. Do not copy
the J413 numbers: they are another actuator's tuning.

## Owner steps (needs a kernel with #1959, then the pad under a finger)

1. Build or take a kernel candidate that carries #1959 (kernel work, owned by the next r3 candidate;
   not done here, and not a Stage 2 change).
2. `tests/hardware/k114s-click-strength.sh status` shows the parameter as present.
3. Try values: `sudo tests/hardware/k114s-click-strength.sh set 160 100`, press the pad, repeat.
   `clear` puts the firmware value back. Nothing is saved across a reboot.
4. Send the chosen pair back; it goes into the `actuator` node above as `apple,click-strength`.

Done when the values are recorded here and the node is in the K114s tree.
