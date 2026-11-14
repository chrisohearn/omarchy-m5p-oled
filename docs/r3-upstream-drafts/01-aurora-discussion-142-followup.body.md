**K114S follow-up, 2026-11-14: trackpad works with #1568; N1 Wi-Fi associates with platform ID `0x00146050`; Bluetooth controller, SMC sensors and battery come up; USB-C not yet tested with a device**

_Written by Claude (an AI agent) working for the owner of this Mac and posted from the owner's account at his direction. "owner-observed" is what the owner saw on the machine; "agent-run" is a command the agent ran in the booted Linux system; "source read" is a file read in the named tree, not a hardware result. One machine, three boots; not an independent reproduction._

This is the follow-up promised in the comment above: the same K114S with the trackpad fix and a K114s copy of the K116s N1, USB-C and SMC sections of #1648.

```text
Board ID: K114S (Mac17,13), ADT /chosen board-id 0x14, chip-id 0x6050
SoC ID and chip variant: T6050, M5 Pro, 18 CPUs online (MIDR part 0x064 x 12, 0x065 x 6)
Model / screen size / configuration: MacBook Pro 14-inch, OLED touchscreen, 1 TB
Feature or SoC block: trackpad (DockChannel MTP), N1 Wi-Fi and Bluetooth, SMC hwmon, battery, USB-C controller probe
Kernel repository / branch / commit: aurora-silicon/linux integration/aurora @ a34d26c255c2 + betizzel/omarchy-m5 linux-j714s-27.2.patch as in its release omarchy-j714s-3 (19 patches) + #1568 at head 1e065585d3da; release 7.3.0-17.v272-4-ARCH, clang 23.1.3. Device tree: dts/t6050-k114s-r1.dts in the repository below = t6050-k114s.dts of that commit + the N1 port, the left-front and right USB-C ports and smc_hwmon of #1648 (cd2c9f52) with this board's identity.
m1n1 / U-Boot / Mesa commits, where relevant: aurora-silicon/aura @ 22b71758dfd0 + betizzel/omarchy-m5 aura-j714s-27.2.patch; uboot-aurora 2026.07.aurora6.j714s3; Limine and a UKI. Mesa not relevant (GPU node disabled; llvmpipe).
Firmware version: /chosen asahi,os-fw-version 27.2 (stub 26B8125), asahi,iboot2-version mBoot-20457.41.3; asahi,system-fw-version "27.3 beta", asahi,iboot1-version mBoot-20457.60.65.0.1.
Steps to reproduce: 1) Start from the install in the first report. 2) Build the kernel above and dts/t6050-k114s-r1.dts; make a Stage 2 from the same aura build with that one tree. 3) Build apple/centauri/k114s-ftab.bin for platform ID 0x00146050 from Apple's 27.2 (26B8125) restore image on the owner's side (build/make_k114s_ftab.py in the repository below, which calls betizzel/omarchy-m5's omarchy_centauri.py). 4) Boot.
Expected result: pointer input, Wi-Fi, sensors.
Observed result and repeat count: three boots on 2026-11-14 (13:51, 15:12, 15:24 MST); per-action results and counts in the table below.
Public log or artifact URL: https://github.com/chrisohearn/omarchy-m5p-oled (dts/, patches/linux/pr1568.patch, pins/sources.json). Logs are not published; the kernel lines in the code block below are literal.
Artifact SHA-256 and command to repeat the check: device tree blob 2ea22d26b2a1c81526e77e7f29eaff46def5310a9512be769ff3ed50465f4dd2 (build/build-dtb.sh); Stage 2 45a5dbef19c14898e73e79a42af360def638c319d14e2bae97a79f7962e4bfb4.
Known limits / recovery steps: see "Not tested" below. macOS is untouched; the previous Stage 2 can be put back from macOS.
```

| Action | Result | Evidence |
| --- | --- | --- |
| Trackpad with #1568 | **pass**: pointer moves and clicks work. Scrolling and gestures were not recorded | owner-observed, on the boots at 13:51 and 15:12 |
| Trackpad probe | `multi-touch: clamping Report Size 524288 to 16384`, `magicmouse 0019:05AC:0361.0002: initialised MTP haptics`, `touch_iface.c:512: Touch MT ready` on 3 of 3 boots | agent-run |
| #1830 with product 0x0361 admitted | **not tested** (built, never booted) | |
| N1 enumerates | **pass**: `adopted port 0, endpoint 01:00`; 01:00.0 `106b:1900`, then 01:00.1 `106b:1902` and 01:00.2 `106b:1903` after `port 0: link retrained after a root-port reset`, on 3 of 3 boots | agent-run |
| N1 Wi-Fi | **pass on 5 GHz**: `apple_centauri_t6050` loads the K114s firmware table and `wlan0` connects on 3 of 3 boots. Read on the 15:24 boot: associated on 5180 MHz, has an address, and by 16:05 MST the interface counters read about 7.0 GB received and 0.2 GB sent. 2.4 GHz and 6 GHz: not tested | agent-run |
| Bluetooth | controller only: `hci0` present and powered. No device paired, no audio. This kernel has `CONFIG_BT_RFCOMM` off | agent-run |
| SMC hwmon | **pass**: two fans report RPM, charger and battery voltage, power and current read, 275 temperature inputs. `TAOC`, `TAOI`, `TAOJ`, `TAOP` read -127.0 °C, the 20 `TD00`..`TD34` keys and `TVA0`, `TDVx` read a flat 25.0 °C and 13 keys read 0.0 °C | agent-run |
| Battery | **pass with errors**: charge, status, health and cycle count read. The `manufacture_year` -95 line below is logged 20 to 40 times in the first minute of each boot and again whenever the battery is read (200, 70 and about 150 lines so far on the three boots), the synthetic uevent line 2 or 3 times per boot, and reading the battery's `uevent` file returns nothing. #1615 describes the same on a 14-inch M5 Max | agent-run |
| CPUs | 18 online | agent-run |
| USB-C host (left-front, right) | **not tested**: no device has been plugged in. `dwc3-apple` is bound to both controllers and Type-C `port0`/`port1` register; no xHCI root hub exists yet, which is what dwc3-apple does until its first cable event (`DWC3_APPLE_PROBE_PENDING`) | agent-run; the driver behaviour is a source read |

Kernel lines from the 15:24 boot (journal host prefix removed):

```text
[    0.410526] pcie-apple 1cb0000000.pcie: adopted port 0, endpoint 01:00
[    0.411476] pci 0000:01:00.0: [106b:1900] type 00 class 0xff0000 PCIe Endpoint
[    0.417906] power_supply macsmc-battery: driver failed to report `manufacture_year' property: -95
[    0.420037] dockchannel-hid 294b30000.input: multi-touch: clamping Report Size 524288 to 16384
[    0.632046] power_supply macsmc-battery: uevent: failed to send synthetic uevent: -95
[    0.900341] magicmouse 0019:05AC:0361.0002: initialised MTP haptics
[    0.900748] dockchannel-hid 294b30000.input: Direct firmware load for apple/tpmtfw-k114s.bin failed with error -2
[    0.964029] dockchannel-hid 294b30000.input: Direct firmware load for apple/tpmtfw-k114s.bin failed with error -2
[    1.268129] rtkit-helper 294600000.mtp: RTKit: syslog message: bootloader.c:537: (*)New AFE[0] cbor image received
[    1.396181] rtkit-helper 294600000.mtp: RTKit: syslog message: touch_iface.c:512: Touch MT ready
[    8.243583] apple_centauri_t6050 0000:01:00.0: enabling device (0000 -> 0002)
[    8.520013] pcie-apple 1cb0000000.pcie: port 0: link retrained after a root-port reset
[    8.528007] pci 0000:01:00.1: [106b:1902] type 00 class 0x0d2000 PCIe Endpoint
[    8.528504] pci 0000:01:00.2: [106b:1903] type 00 class 0x0d1100 PCIe Endpoint
```

Two answers to open points in the tree:

- **Platform ID.** `t6050-k114-k116.dtsi` keeps the K114s PCIe host disabled until "its ADT /chosen board-id << 16 | 0x6050" is known. With board-id 0x14 that is `0x00146050`, and the N1 works with it and with `firmware-name = "apple/centauri/k114s-ftab.bin"`.
- **Trackpad AFE reset.** This tree keeps the AFE reset on the SMC pcIO output, as the base `t6050-k114s.dts` has it, and the multi-touch interface comes up on every boot. The `smc_gpio_low 28` form the K116s needed (#1648) was built as a variant and has not been booted here. `apple/tpmtfw-k114s.bin` fails to load in the initramfs (`Direct firmware load ... failed with error -2`, once or twice per boot) about half a second before `Touch MT ready`; `New AFE[0] cbor image received` is logged in between on each boot.

**Not tested or not present:** USB devices, USB4, the display coprocessor (still simpledrm, connector `Unknown-1`, no brightness control), GPU, sound (no sound node, so no sound card; speakers stay off until this model has protection data), microphones, camera, touchscreen, suspend, keyboard backlight control.

The K114s copy of the N1, USB-C and SMC sections is in `dts/t6050-k114s-common.dtsi`. If a pull request against `integration/aurora` would be useful, the owner can send the N1 and SMC parts as hardware-tested and the USB-C part marked untested; say which form you prefer.
