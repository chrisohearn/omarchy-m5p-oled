# Touchscreen ("kiwi"): port plan for the K114s (issue #48)

Status: **evaluated, not started on hardware.** The kernel driver is still an open draft upstream and has no
verified finger events, so nothing here goes into a boot image yet. This page records what the K114s itself
confirms, what is left, and the exact order of the first trial.

## What is upstream (read 2026-11-15, upstream-reported)

| Item | State | Note |
| --- | --- | --- |
| aurora-silicon/linux #1605 `HID: apple-mtp-kiwi: the K114c touch screen` | open draft, head `a7b2febb963a`, rebased onto `integration/aurora` `514ae1f4` | firmware accepted, `Kiwi interface ready with status:0`, 17861-byte frames at about 123 Hz, input device registers. Finger events not verified. The author says no person has touched the panel since the interface came up. A reviewer posted a green rebase check (2026-11-15). |
| #1568 trackpad report 0x5a | open draft | the body of #1605 names #1737 as its base now |
| #1737 dockchannel report-size clamp and short-report pad | open draft | overlaps the merged #1830 clamp: expect a conflict to resolve when porting |
| #2004 `pinctrl: apple: clear bit 4 of the GPIO mode on the T6050` | open, not draft | without it the touch reset never took effect on the K114c |
| joshuaswarren/m5max-touch-firmware | `m5max-touch-fw.py` | builds `tpkiwifw-k114c.bin` from the macOS restore image members `K114_Multitouch.im4p` and `K114_KiwiFirmware.im4p`; removes three placeholder operations (26, 29, 30). Nothing Apple-made is in the repo |

## What this Mac confirms (agent-run, 2026-11-15)

1. `sudo python3 -I tests/k114s-adt-kiwi-facts.py` reads this Mac's Apple device tree (read-only) and compares it with
   the K114c pins in #1605: **12 of 12 facts hold.** The K114s ADT has the same `kiwi` node under `mtp-transport`:
   24 MHz clock on NUB GPIO 22, display sync on AP GPIO 11, power on NUB GPIO 26, reset on NUB GPIO 25, SMC power
   reference `rCIO`, firmware image tag `fsat`, CBOR bootloader. The pin numbers are therefore identical, so the K114c
   device-tree block can be reused for the K114s unchanged. The tool prints no calibration data and no firmware bytes.
   `--self-test` proves the comparison on a made-up ADT.
2. The reset and power polarities (reset active low, power active high) cannot be read from the ADT's flag words
   directly; the K114c values are "those of a device tree that gave touch on this machine" (#1605). The first trial
   uses them as is.
3. The running kernel already reaches the touchscreen's firmware interface: the MTP co-processor log shows `Initializing comm
   interface <7 "kiwi">`, `<8 "kiwi-diag-p0">` and `Kiwi interface initialized with status: 0` at boot. That is the
   co-processor side only. No Linux driver is bound and our tree has no kiwi node (`grep kiwi dts/` finds nothing).
4. The trackpad on this tree uses the same MTP transport and already works, so the transport under the touch node is
   proven. The touch power sequence is separate from the trackpad's AFE reset line.

## What blocks a K114s tree

* Kernel: #1605 needs #1737 (conflicts with the merged #1830 clamp) and #2004 below it, and our base lacks the
  `kiwi` label, the `nub_gpio0` node and its power domain. Porting is an r3b-class kernel change, to be done after
  upstream shows verified finger events, not before.
* Firmware: the tool is written against the macOS 27.3 beta 1 restore image. The issue text says the Mac's image is
  27.2. The `K114_KiwiFirmware.im4p` member is shared by the K114 family (ADT `hid-merge-personality` is `K114,2`), but whether
  the 27.2 member has the same three removable operations is unchecked. The tool stops if the operation shape differs.
  Firmware is built from the owner's own image and never committed or published.

## Proposed K114s device-tree fragment (not compiled, not in any tree)

Copied from #1605 for the K114c. It becomes `dts/t6050-k114s-kiwi.dtsi` once the base has the labels. `firmware-name` changes to the K114s file
name chosen when the image is built (kept `tpkiwifw-k114c.bin` if the same blob is used, which the shared K114
personality suggests):

```dts
#include <dt-bindings/pinctrl/apple.h>

&ps_nub_gpio { status = "okay"; };
&nub_gpio0 {
	status = "okay";
	kiwi_clk24_pins: kiwi-clk24-pins { pinmux = <APPLE_PINMUX(22, 1)>; };
};
&pinctrl_ap {
	kiwi_dsync_pins: kiwi-dsync-pins { pinmux = <APPLE_PINMUX(11, 1)>; };
};
&mtp_hid {
	pinctrl-0 = <&kiwi_clk24_pins>, <&kiwi_dsync_pins>;
	pinctrl-names = "default";
};
&kiwi {
	firmware-name = "apple/tpkiwifw-k114c.bin";
	apple,power-method = <2>;
	apple,reset-gpios = <&nub_gpio0 25 GPIO_ACTIVE_LOW>;
	apple,power-gpios = <&nub_gpio0 26 GPIO_ACTIVE_HIGH>;
	status = "okay";
};
```

Default-off rule: the fragment stays out of `t6050-k114s-r3.dts` and every shipped tree. It is added only by a
separate trial tree (`t6050-k114s-r3-touch.dts`, same pattern as the sound and USB trial trees), booted one-shot.

## Order of work

1. Done now: pins confirmed against the K114s ADT (this page and `tests/k114s-adt-kiwi-facts.py`).
2. Wait for #1605 to show verified finger events on the K114c (`libinput debug-events` capture). Watch #1605, #1737, #2004.
3. Owner, macOS side, no boot risk: extract the two `.im4p` members from the 27.2 restore image on the Mac and run the
   firmware tool; report only the size and sha256 it prints. The agent compares the sha256 with the tool's published
   value for the 27.3 blob to learn whether the 27.2 member differs.
4. Kernel: add #2004, #1737 (resolved against #1830) and #1605 to a trial kernel (r3b line) as a module, default off;
   build and check the dtb with `tests/lint-dtb.py`.
5. Owner, trial: one-shot boot of `r3-touch` with the recovery entry available (the proven way back). Then:
   `sudo dmesg | grep -i kiwi` (expect `Kiwi interface ready with status:0`), then
   `sudo libinput debug-events --show-keycodes` while touching the screen. A hang needs a forced power-off; the recovery
   path is the normal boot-chain one, with no macOS or Stage 1 change.
6. Done when finger events are seen and a K114s tree has booted with touch for two clean boots.

## Evidence labels

agent-run: the ADT facts, the boot log lines and the repo greps above. upstream-reported: everything in the
upstream table. owner-observed: nothing yet.
