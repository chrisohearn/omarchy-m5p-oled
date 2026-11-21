# Touchscreen ("kiwi"): port plan for the K114s (issue #48)

Status: **evaluated, not started on hardware.** The kernel driver is still an open draft upstream and has no
verified finger events, so nothing here goes into a boot image yet. This page records what the K114s itself
confirms, what is left, and the exact order of the first trial.

## What is upstream (read 2026-11-15, heads refreshed 2026-11-16, upstream-reported)

| Item | State | Note |
| --- | --- | --- |
| aurora-silicon/linux #1605 `HID: apple-mtp-kiwi: the K114c touch screen` | open draft, head `a7b2febb963a`, rebased onto `integration/aurora` `514ae1f4` | firmware accepted, `Kiwi interface ready with status:0`, 17861-byte frames at about 123 Hz, input device registers. Finger events not verified. The author says no person has touched the panel since the interface came up. A reviewer posted a green rebase check (2026-11-15). |
| #1568 trackpad report 0x5a, head `1e065585d3` | open draft | the body of #1605 names #1737 as its base now |
| #1737 dockchannel report-size clamp and short-report pad, head `99a8061773` | open draft | overlaps the merged #1830 clamp: expect a conflict to resolve when porting |
| #2004 `pinctrl: apple: clear bit 4 of the GPIO mode on the T6050`, head `aea7476f5f` | open, not draft | without it the touch reset never took effect on the K114c |
| #2014, #2015, #2016 the MTP receive ring (DART stream 1, the T6050 DockChannel HID compatible, a look-again after a doorbell), heads `0d1408c7df`, `e3188ea021`, `867f5174d6` | open drafts, stacked (#2015 on #2014, #2016 on #2015) | needed with touch: without them typing lags (the root's decision for this trial) |
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
  **Resolved 2026-11-16 (agent-run):** `Firmware/K114_KiwiFirmware.im4p` from Apple's macOS 27.2 (26B8125) restore image for
  Mac17,13, the build this Mac runs, was fetched by HTTP range request: member 2722859 bytes, sha256
  `e6868fd28a2d23f93ca9d2c0c41804d05a41c1356c3bb04558909ae9762ffb62`. `m5max-touch-fw.py` (read before running) passed its shape
  check for operations 26, 29 and 30 and wrote `tpkiwifw-k114c.bin`, 1310315 bytes, sha256
  `af4ba3aa50779353c42f8f81e5754cc5ead69a84630cabd34dbaa2df0a6f3661`. That equals the tool's published value for the 27.3 b1
  file the working K114c boot uses, so the 27.2 member gives the same blob and the K114s keeps
  `firmware-name = "apple/tpkiwifw-k114c.bin"`. The file is kept outside every repository, in `~/k114s-build/touch-fw/`, and is
  never committed or published. The owner session only installs it to `/lib/firmware/apple/` before the trial boot.

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
3. Done 2026-11-16 without macOS (see "What blocks a K114s tree"; the steps below it were the original plan). Owner, macOS side, no boot risk: extract the two `.im4p` members from the 27.2 restore image on the Mac and run the
   firmware tool; report only the size and sha256 it prints. The agent compares the sha256 with the tool's published
   value for the 27.3 blob to learn whether the 27.2 member differs.
4. Kernel: add #2004, #1737 (resolved against #1830) and #1605 to a separate touch trial kernel as a module, default off. It never changes the reviewed r3b build and hashes the display
   plan pins (`docs/r3-display-plan.md` gates G2, G3, G7): it is a later build made after the display window closes, or its own
   package name. Build and check the dtb with `tests/lint-dtb.py`.
5. Owner, trial, only after the display window (`docs/r3-display-plan.md` 4.4) is closed, because the window forbids package
   transactions, mkinitcpio and new limine entries (4.1 rule 4): one-shot boot of `r3-touch` with the recovery entry available (the proven way back). Then:
   `sudo dmesg | grep -i kiwi` (expect `Kiwi interface ready with status:0`), then
   `sudo libinput debug-events --show-keycodes` while touching the screen. A hang needs a forced power-off; the recovery
   path is the normal boot-chain one, with no macOS or Stage 1 change.
6. Done when finger events are seen and a K114s tree has booted with touch for two clean boots.

## r3b-t1: the trial kernel and tree (built, not booted)

Prepared offline on 2026-11-16 for issue #48. Nothing here was installed or booted. The default-off rule holds: no shipped tree and no
shipped kernel changed.

**What was ported (agent-run).** `r3b-c1` (head `08ddebb521`) plus 12 cherry-picked commits (`-x`), all clean, so there are no conflicts to
resolve. The tree is `0e77e870a11f`. The series is `patches/linux/r3b-t1.series` and the commits are `patches/linux/touch/0001` to `0012`.
`git am` of them onto `08ddebb521` reproduces the built tree (the root ran it).

| Upstream | Head | Commits (picked as) |
| --- | --- | --- |
| #2004 pinctrl | `aea7476f5f` | `61f57c0be5` |
| #1605 kiwi driver | `a7b2febb96` | `067dcc5439` the driver, `a6420a4cf7` the interface in dockchannel-hid, `a00e4512e4` the binding, `2ccb71256f` the K114c tree |
| #2014 | `0d1408c7df` | `e11423a962`, `e003ac684a`, `0e712e75f1` (second DART stream) |
| #2015 | `e3188ea021` | `0926c4547f`, `0d480e8a7a`, `ca4d1232db` (receive ring, T6050 compatible) |
| #2016 | `867f5174d6` | `8d79edfada` |

#1737, #1568 and #2011 are not applied again: `r3b/0001` to `0004` already carry them. The heads r3b was cut from (`d43ac775b8`,
`f28cc1b5b2`) are not the heads upstream shows today (`99a8061773`, `1e065585d3`). The diffs differ; whether only in context lines after a rebase
is not checked. The r3b.c1 patches stay as they are for this trial.

**Configuration delta (agent-run).** From `build/r3b-c1/.config`, `scripts/config -m HID_APPLE_MTP_KIWI`, then `olddefconfig`. The only
difference from the r3b.c1 configuration is `CONFIG_HID_APPLE_MTP_KIWI=m` (one added line). `CONFIG_HID_DOCKCHANNEL=y` is already built in, as in r3b.c1.
The kiwi driver is a module, so it only loads if something asks for it.

**Build (agent-run).** `K114S_LABEL=K114S-R3B-T1`, `kmake O=$HOME/k114s-build/build/r3b-t1 -j10 Image modules dtbs`: exit 0, 8 min 4 s. Release
`7.3.0-17.v272-11-k114s-r3b-ARCH` (unchanged); banner `SMP PREEMPT K114S-R3B-T1`. `Image` 54,282,752 bytes, sha256
`5daa39850f84c37b1c8df57688ae39484536296b079ea3291e9647686946804c` (r3b.c1: `29e22193...`, same size). The Image differs because
`dockchannel-hid` is built in, so a touch trial replaces the Image as well as adding a module. 1973 modules; 138 Apple device trees.
`hid-apple-mtp-kiwi.ko` is 414,224 bytes, vermagic `7.3.0-17.v272-11-k114s-r3b-ARCH SMP preempt mod_unload aarch64`. The log has no warning
from hid, dockchannel, pinctrl or kiwi (the warnings are Rust "never used" ones in `drivers/soc/apple/control.rs` and the asahi GPU driver and thread-safety ones in `drivers/nvme/host/apple.c`, none in
files of this series). `k114s-cmp-modules` against the installed r3b.b1: `NEW drivers/hid/hid-apple-mtp-kiwi.ko`, `DIFF(.text)
appledrm.ko` (the r3b.c1 colour and EDR change, not touch), 1971 same. The built-in `dockchannel-hid` change cannot be seen by that tool.

**Device trees (agent-run, `build/build-r3a-dtb.sh`, dtc 1.8.1).** `dts/t6050-k114s-kiwi.dtsi` holds the fragment above and is a no-op unless
`K114S_R3_TOUCH` is defined. `dts/t6050-k114s-r3-touch.dts` is the D9 default tree `t6050-k114s-r3b-brightness.dts` (unchanged), then that
macro, then the fragment. Every label it uses exists in the ported kernel tree (`kiwi`, `mtp_hid`, `pinctrl_ap` and `ps_nub_gpio`/`nub_gpio0` through the
base; the K114c file shows the same fragment). `firmware-name` stays `apple/tpkiwifw-k114c.bin` (the firmware section above).

| Tree | Against | sha256 |
| --- | --- | --- |
| `t6050-k114s-r3b-brightness` | r3b-c1 includes | `86c3f9593f21c9c13ff1b6fe88f2fe3d996dda3aa4cdeaa1a68b74f41da05282` |
| `t6050-k114s-r3b-brightness` | r3b-t1 includes | `785c0fb3a3a97349e7447eff32e9e21d8fec58cea5c2f4712a53e639eedaf84f` |
| same plus the fragment included without the macro | r3b-t1 includes | `785c0fb3...`, identical to the line above |
| `t6050-k114s-r3-touch` | r3b-t1 includes | `3a8f4bb0a137ef4a9f12df784ca1c2bd56f5337c9a632ee48e453df19482125b`, 109,308 bytes |

`tests/lint-dtb.py` passes on the touch tree and on the brightness tree built on the r3b-t1 includes. The touch tree differs from the brightness tree on the
same includes by 2 added pin nodes, `status` on `nub_gpio0` and one power controller (`power-controller@88`), `pinctrl-0`/`pinctrl-names` on `mtp_hid`,
and the `kiwi` properties and status (`tests/dtb-node-diff.py`). **Default tree unchanged:** no existing file under `dts/` changed (the repo diff is new files and this page only), and the
fragment without its macro leaves the brightness tree byte-identical (rows 2 and 3). The shipped D9 bytes (`5b6b83c8...`, built on P's includes, `docs/r3-display-plan.md` 3.2) were
not rebuilt: P's includes are not in the build area. The brightness tree built on the r3b-c1 includes (row 1) is a different base from P's, as `docs/r3-display-plan.md` says.
**The kernel's base device tree changed with the series:** `t6050-k114-k116.dtsi` now gives the MTP transport DART streams 0 and 1 and the `apple,t6050-dockchannel-hid`
compatible (#2014, #2015), so the same repo tree compiles to different bytes on the r3b-t1 includes (row 1 against row 2). The touch trial tree is therefore only for the r3b-t1 kernel.
No Stage 2 file was composed.

**Not verified.** No boot of any of this. No firmware load: the blob exists on the build machine but nothing has read it from `/lib/firmware`. Finger events are not
verified upstream (see the table). The DART stream 1 change and the receive ring (#2014 to #2016) touch the keyboard and trackpad transport,
so a boot of r3b-t1 can break typing before it ever reaches touch. The KUnit cases in the series were not run. The QEMU smoke test was not run
on r3b-t1. The ADT facts (12 of 12) say the pins agree; they say nothing about the polarities or about the 27.2 firmware actually running.

### Offline packaging objective (#219)

Prepare the existing r3b-t1 touchscreen build as an opt-in local package with
both a distinct package name and a distinct kernel release. The package name
must select its own pkgbase, preset and UKI name. The release must select its
own `/usr/lib/modules` directory. Reject a build with the plain r3b release
before staging any files. Keep the current default and all existing package
variants as they are.

Proof is an offline archive or package-root inspection. Check its names and
paths against the r3b package, check that the regular r3b variant still selects
its existing names, and verify that the trial build contains the Kiwi module.
The endpoint is a locally verified archive and repository source. Installing the
package, creating an entry and booting remain part of the later attended trial.
Check the ESP budget and verify the recovery route before staging that trial.

**Owner-session steps (not run).** Keep the default-off rule and the one-shot pattern. Only after the display window is closed
(`docs/r3-display-plan.md` 4.4):

1. Install the firmware from the build area (`~/k114s-build/touch-fw/`) to `/lib/firmware/apple/tpkiwifw-k114c.bin` (built from Apple's 27.2 restore image for this model; never committed).
2. Package the r3b-t1 build under its own name, not as `linux-k114s-r3b`, so the r3b.c1 package and its UKI stay untouched, and add its own boot entry.
3. Compose a Stage 2 from `t6050-k114s-r3-touch.dtb` on the loader the default Stage 2 uses, as an `aura-try` one-shot (`m1n1/boot-ctxr.bin` is not written),
   with the recovery entry available.
4. Boot once. Check keyboard and trackpad first, then `sudo dmesg | grep -i kiwi` (expect `Kiwi interface ready with status:0`), then
   `sudo libinput debug-events --show-keycodes` while touching the screen.
5. A hang needs a forced power-off. The next boot returns to the configured Stage 2 and kernel.

## Evidence labels

agent-run: the ADT facts, the boot log lines, the repo greps, the firmware build and the r3b-t1 build and device-tree results above. upstream-reported: everything in the
upstream table. owner-observed: nothing yet.
