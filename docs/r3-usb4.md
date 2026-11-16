# r3-usb4: USB4/Thunderbolt routers on the K114s (issue #61)

Status: **device tree candidate built and checked against this Mac's ADT. Not booted, no USB4
device ever plugged in.** Beyond Asahi M1/M2 parity (Thunderbolt/USB4 is work in progress
there); low priority. Written 2026-11-15.

## Where it stands (agent-run, read-only, on the running K114s, r3a kernel)

- The drivers are present and built as modules: `CONFIG_USB4=m`, `USB4_APPLE_SOC=m`,
  `USB4_CONFIGFS=m`; `thunderbolt` and `thunderbolt_apple` are loaded, and the platform drivers
  `thunderbolt-apple-acio` and `thunderbolt-apple-nhi` are registered. Both USB-C controllers
  and the `dwc3-apple` hosts are bound. `/sys/bus/thunderbolt/devices` is empty because the
  K114s tree has no `acio` node, so there is no router to bind. (`ls /sys/bus/thunderbolt/devices`,
  `lsmod`, `ls /sys/bus/platform/drivers`, `zcat /proc/config.gz`.)
- The K114s ADT (read with `sudo build/k114s-adt.py` / the facts script) has `/arm-io/acio1`
  (port number 2, ATC1, left-front) and `acio2` (port number 3, ATC2, right), each with
  `acio-cpu`, `dart-acio`, `apciec` and an LSTX pin.

## What was derived

The K114s routers equal the J714s's and the K114c's, the same SoC: same register addresses,
interrupts and LSTX pins (ATC1 AOP GPIO 79, ATC2 81). So no new node text is needed:

| Port | Router description | Upstream |
| --- | --- | --- |
| ATC1 left-front | `t6050-j714s-left-usb4.dtsi` | aurora-silicon/linux #1791 (merged; J714s lab boot with a USB4 NVMe enclosure) |
| ATC2 right | `t6050-max-atc2-router.dtsi` | #1841 (merged; K114c; probe bound, no device tested) |

- `dts/t6050-k114s-usb4.dtsi` includes both and enables the right router's five suppliers
  (as the K114c tree does). `dts/t6050-k114s-r3-usb4.dts` is the r3a tree plus that file.
- `patches/linux/usb4/0001-t6050-k114s-router-guards.patch` (three `#if` lines): the router
  nodes and the inventory's apciec DARTs are guarded per board in `t6050-max.dtsi` and
  `t6050-peripherals.dtsi`. The guards key on a separate opt-in macro, `T6050_K114S_USB4`, that only
  `t6050-k114s-r3-usb4.dts` defines. Keying on `T6050_K114S` would drop the apciec DARTs from every K114s
  tree that lacks the router files (upstream's `t6050-k114s.dts` and the r3a tree), and dtc then fails on the DMA
  controllers' references. Candidate for upstream (aurora-silicon), with the macro defined in a K114s dts
  that includes the router files.
- Include order in `t6050-k114s-usb4.dtsi`: the right router first, the left file last. The right router's file
  reserves AOP pins `<0 81>, <82 3>`; the left file's `<0 79>, <80 1>, <82 3>` must win so both LSTX pins (79, 81)
  stay usable (as on the J714s). `tests/lint-dtb.py` fails a USB4 tree that does not expose both.
- The kernel base of r3a (aurora-silicon/linux `a34d26c2`, v272-4) does NOT have #1791 and
  #1841, so this needs a newer base (the "next base candidate" of `pins/sources.json`) or a cherry-pick of both.
- The tunables and the left router's host DROM come from the compiled tree, not from the boot loader.
  Aura's `dt_set_acio_tunables()` finds the router nodes through `usb4_N_rc`, `usb4-N-acio` and `usb4_N_nhi`
  aliases, which this tree does not have, so the loader replaces nothing. The facts script checks that the rc,
  PCIe adapter, router firmware, NHI, DART, PHY RX_TOP CIO and PCIe tunnel tunables equal this Mac's ADT, and that the
  left router's DROM is byte-equal to the ADT's (reported yes/no only). The right router has no host DROM in the tree
  (the DROM is not in the repository): a build that wants one can name a generated file in `K114S_USB4_DROM`.
  Whether the NHI driver needs it is untested.

## Test (software)

`tests/test-usb4-dtb.sh KTREE` (KTREE = aurora-silicon/linux with both pull requests) copies the tree, applies the patch,
builds the dtb, lints it (both LSTX pins exposed) and builds the r3a tree and upstream's `t6050-k114s.dts` against the
patched tree (they must still build). With root it then runs `tests/k114s-adt-usb4-facts.py`: for both routers the rc, PCIe
adapter, CPU wrapper, firmware block, mailbox and its four interrupts, LSTX pin, the 25 NHI interrupts, the NHI offset, the DART
interrupt and the five power domains, and every tunable named above, equal the ADT; both LSTX pins are outside the reserved
ranges. Last run (2026-11-15, head tree): all 52 checks hold (27 for the left router, 25 for the right, and the right router's absent DROM
is a note, not a check). Without root the ADT step is skipped and the final line says so. No QEMU boot: QEMU has no
Apple SoC, and a boot test of the tree would only show it parses.

## Left (needs the owner, and a kernel base with #1791 and #1841)

1. Order: USB host proven (`docs/r3-usb.md`) first; the ports are still unplug-tested.
2. Build the kernel and the r3-usb4 dtb on a newer base, trial boot (never over the default).
3. Plug a USB4/Thunderbolt device in the left-front port, then the right, and run
   `bash tests/hardware/k114s-usb4-check.sh`. Expect a router bound at boot, NHI after the link trains,
   `/sys/bus/thunderbolt/devices` entries, and (with a PCIe enclosure) an NVMe behind the tunnel.
4. Then add `USB4_NET` and `TYPEC_TBT_ALTMODE` (docs/r3-config.md).

## Proposed index row (not edited here)

`USB4 / Thunderbolt`: status `candidate built, ADT-verified, not booted`; next `needs kernel base with #1791/#1841, owner plug test`.
