# r3: left-back USB-C port (ATC0), draft

Status: **draft, compiled and linted, never booted.** Issue #72. Written 2026-11-15 on the K114s,
r3a kernel (`7.3.0-17.v272-4-k114s-r3a-ARCH`, driver source aurora-silicon/linux `a34d26c255c2`).
Evidence labels: agent-run, upstream-reported. There is no owner-observed result yet.

## Answer

The left-back port is kept as the loader's debug port in two places, and both are a choice, not a
hardware limit:

1. **Our tree** does not describe it, and `tests/lint-usb-dtb.py` enforces that.
2. **aura** (the Stage 2 loader) skips the PHY of port index 0 when it copies the ADT's tunables:
   `t6050_setup_atc()` in `src/kboot_atc.c`, "Port 0 carries aura's debug link: never describe it".
   The skip does not look at the boot options, so it applies to our Stage 2, which is built
   without the debug-USB proxy (`RELEASE=1 CHAINLOADING=1 ESP_STAGE2=1`).

The kernel side needs nothing new. The PHY driver at `a34d26c255c2` bounds the index only from
above (`port > 5` in `atc-t6050-dp.c`), so index 0 binds (aurora-silicon/linux #1268, merged,
upstream-reported). Upstream describes this very port on the J716c
(`t6050-j716c-left-usb4.dtsi`, "USB-C Left Rear", `#1220`).

## What is in this branch

| Path | What |
| --- | --- |
| `dts/t6050-k114s-usb.dtsi`, section `K114S_R3_USB_ATC0` | hpm0 (`usb-pd@c` on nub-spmi-a0), connector graph, ATC0 PHY and mailbox, dwc3 `usb-drd0` and its two DARTs, the five power domains. Off unless defined; with it off every tree is byte-identical to before |
| `dts/t6050-k114s-r3-usb-atc0.dts` | r1 plus that section and nothing else. Flagged draft, **lint-only, not a boot candidate**: it has no GPU node, so booting it would also drop the GPU desktop (see "What has to change first") |
| `tests/lint-usb-dtb.py --atc0 [--atc0-reference J716C.dtb]` | The third port checked like the other two; optional comparison with the J716c's ATC0 nodes. Without `--atc0` the lint still demands an undescribed left-back port |
| `tests/test-usb-dtb.sh KTREE [K116S [J716C]]` | Builds the new tree, checks both lint directions, and with a J716c tree compares |
| `tests/k114s-usb-root-probe.py adt` | Now also reports usb-drd0, atc-phy0, acio-phy-cpu0 and dart-usb0 against the draft's addresses (informational, not part of the verdict) |
| `patches/aura/atc0/0001-...patch` | Draft loader change: skip port 0 only while `aura-debug` is on or in a `USE_DEBUG_USB` build. Applies to aura `85c7dc55`, passes a syntax check, **not built into a Stage 2** |
| `tests/hardware/k114s-atc0-plug-test.sh` | Owner test after a trial boot |

## Evidence (all agent-run)

- `sudo python3 tests/k114s-usb-root-probe.py adt` on this Mac: hpm0 is on nub-spmi-a0 at SPMI
  0x0c (port-type 2), and the ADT has usb-drd0 reg[0] `0x2a2280000`, atc-phy0 reg[2]
  `0x2a3000000`, acio-phy-cpu0 reg[0] `0x2a3148000` and dart-usb0 reg[0] `0x2a2f00000`: the
  draft's addresses. Its interrupt numbers and tunables were not read (the probe prints addresses
  only); they are the J716c's, from the same SoC.
- `tests/test-usb-dtb.sh` with the installed kernel source, the K116s tree at PR 1648 and the
  integration/aurora head: r3-usb is byte-identical to r1, the ATC0 tree lints as "all three
  ports complete", and its dwc3, PHY (first 11 register windows, compatible, index and switches),
  mailbox and both DART nodes equal the J716c's, property by property. The two lint directions
  and the existing negative tests pass.
- aura `85c7dc55`: `usb_init()` brings up all hpm ports when `USE_DEBUG_USB` is not built (it is
  not in our recipe) and `aura_debug_enabled()` is false, so nothing of aura's holds port 0 after
  the hand-off in a normal boot. The tunables skip is the only loader block found.
- Live: the Type-C class has `port0` and `port1` only; the SPMI bus has 1-0a and 2-0c and no
  0c on nub-spmi-a0; `phy-coproc@2a3148000`, `usb@2a2280000` and both `iommu@2a2f..` nodes exist
  disabled in the live tree (the shared T6050 inventory).

## Not verified, and risks

- **Nothing has been booted.** Whether the PHY comes up without or with loader tunables, whether
  the port enumerates a device, and whether the port survives a plug/unplug are all unknown.
- The dwc3 tunables in the draft are the J716c's (ATC1's in `t6050-dieX.dtsi` are identical).
  Not compared with this Mac's ADT tables.
- **Charging.** The charger may be on this port (docs/r3-power.md: neither described port has a
  partner, `macsmc-ac` is online). With the port described, the tipd driver takes over hpm0. The
  J716c sets `apple,reset-inherited-usb2-connection` on its hpm0; whether this Mac needs it with
  a device (or a charger) attached at boot is unknown. Do the first trial boot with the charger on
  MagSafe, and nothing in the left-back port.
- Enabling `ps_fab0_piogw` and `ps_fab3_soc` (the domains ps_atc0_common sits behind, enabled the
  same way by the J716c) changes the power tree. Not tried.
- The draft builds the J716c's USB-only subset: no DisplayPort or USB4 on this port.

## What has to change first

1. **Loader.** Without the aura change the PHY has no tunables. Options: (a) get
   `patches/aura/atc0/0001` (or an equivalent) into aurora-silicon/aura, then take the pinned
   aura that has it; (b) carry it locally in our Stage 2 build, which is a change of the boot
   chain and needs the owner's decision. The upstream comment is drafted in the issue.
2. **Trial tree.** The trial tree is P, the configured Stage 2 tree `t6050-k114s-r3-gpu.dts`
   (docs/r3-display-plan.md), plus `K114S_R3_USB_ATC0`, so the GPU desktop stays and the ATC0
   section is the only variable. `t6050-k114s-r3-usb-atc0.dts` is r1-based and only for the lint
   and compile checks; it is not that trial tree, and the P-based file is still to be written.
3. **Loader, in the display plan's sequence.** The display plan's r3 loader (`patches/aura/0001-0003`,
   build `bdf42d19`, stage D3) is also a new Stage 2 loader prefix, and its G2 ESP budget allows at
   most two trial Stage 2 files at once. The ATC0 patch applies cleanly to aura `85c7dc55` and to
   `bdf42d19`, so build the ATC0 loader change together with (or after) the display r3 loader in one
   prefix, and give the trial a slot in that plan's trial sequence and G2 budget. Keep
   `patches/aura/atc0/` out of the `git am patches/aura/*.patch` set: the subdirectory already does.
4. A trial build of Stage 2 with that prefix and the P-based ATC0 tree (docs/r3a-promotion.md
   style: one boot, owner at the Mac, default entry restored).

## Owner steps (after step 1 and 2 are done; not before)

1. Charger on MagSafe, nothing in the left-back port. Trial boot of the ATC0 tree (the way
   back as for any trial; it may hang: hold the power button to force off).
2. `bash tests/hardware/k114s-atc0-plug-test.sh 90`, and while it runs plug a USB device (flash
   drive, keyboard or USB Ethernet) into the **left-back** port; unplug, flip, plug again.
   Paste the output into issue #72.
3. If the verdict is `IDLE` with a device in: `sudo python3 tests/k114s-usb-root-probe.py regs`
   with the device plugged in (read-only). `NO-HOST` or `HOST-EMPTY`: the log lines the script
   prints name the stage (PHY tunables, DART, "USB3 PHY setup failed").
4. Last: charger in the left-back port, see that the charge state is unchanged.
