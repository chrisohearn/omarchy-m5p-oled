# r3: USB-C host ports (left-front, right)

Status: **diagnosed, nothing to fix found; the ports have never been plug-tested.** Written
2026-11-14 on the K114s itself, on the r1 kernel (`uname -v` contains `K114S-R1`, driver source
aurora-silicon/linux `a34d26c255c2`).

## Answer

"No USB host controllers registered, `/sys/bus/usb/devices` empty" is the **idle state of these
ports, by design**, and not a failure. On Apple Silicon the host controller of a Type-C port
(`dwc3-apple`) does not start at boot. It starts when the port's controller reports an attached
device and stops again when the cable goes. With nothing plugged into the left-front or right
port there is no xHCI, no root hub and no USB device. Nothing was plugged into either port in
any of the three boots of the r1 kernel that the journal holds.

Every driver in the chain of both ports is bound, with no error or deferral in the log. The
K114s device tree's USB-C description is equal, node for node and property for property, to the
K116s tree at upstream head, whose ports the K116s owner uses. So there is no device-tree or
kernel change to make for USB host in r3. What is missing is the test: **plug a device in.**

`218e3f85` (tipd asynchronous probe) is not the cause and not a fix. See below.

## Evidence

All of this is **agent-run**, read-only, without root, on the running K114s. None of it is
owner-observed, and none of it shows that a port works.

### 1. The whole chain is bound

| Device | Driver bound (`/sys/bus/.../driver`) |
| --- | --- |
| `28a188000.spmi`, `28a1a8000.spmi` (nub-spmi-a0, a1) | `apple-spmi` |
| SPMI `1-0a` (hpm1, left-front), `2-0c` (hpm2, right) | `sn201202x` |
| `2ab000000.phy`, `383000000.phy` (ATC1, ATC2) | `apple-t6050-dp-phy` |
| `2aa280000.usb`, `382280000.usb` (usb-drd1, usb-drd2) | `dwc3-apple` |
| `2aaf00000`, `2aaf80000`, `382f00000`, `382f80000` `.iommu` | `apple-dart` |

`waiting_for_supplier` is 0 for all of them. The Type-C class has both ports
(`/sys/class/typec/port0`, `port1`), each with its two suppliers linked
(`supplier:platform:2aa280000.usb`, `supplier:platform:2ab000000.phy`, and the right port's
pair). Both role switches are registered (`/sys/class/usb_role/2aa280000.usb-role-switch`,
`382280000.usb-role-switch`). Modules loaded: `sn201202x`, `tps6598x_core`, `typec`,
`atc_t6050_dp`, `dwc3_apple`, `thunderbolt`, `thunderbolt_apple`.

That the port controllers bound means their SPMI buses work: the probe reads the controller's
mode and status over SPMI and fails otherwise. The driver has polled both controllers every
500 ms since boot (they have no interrupt on this SoC generation), and the SPMI driver has logged
none of its errors ("command not acknowledged", "unexpected SPMI response").

### 2. The kernel log has nothing but the bind

The complete output of `journalctl -b -k` for dwc3, xhci, tipd, sn201202x, apple-spmi, typec,
the PHYs, "deferred" and "probe" on this boot:

```
/soc@200000000/spmi@28a188000/usb-pd@a/connector: Fixed dependency cycle(s) with /soc@200000000/phy@2ab000000
/soc@200000000/usb@2aa280000: Fixed dependency cycle(s) with /soc@200000000/phy@2ab000000
/soc@200000000/spmi@28a188000/usb-pd@a/connector: Fixed dependency cycle(s) with /soc@200000000/usb@2aa280000
/soc@200000000/phy@2ab000000: Fixed dependency cycle(s) with /soc@200000000/spmi@28a188000/usb-pd@a/connector
/soc@200000000/usb@2aa280000: Fixed dependency cycle(s) with /soc@200000000/spmi@28a188000/usb-pd@a/connector
/soc@200000000/phy@383000000: Fixed dependency cycle(s) with /soc/spmi@28a1a8000/usb-pd@c/connector
/soc/spmi@28a1a8000/usb-pd@c/connector: Fixed dependency cycle(s) with /soc@200000000/phy@383000000
/soc@200000000/usb@382280000: Fixed dependency cycle(s) with /soc/spmi@28a1a8000/usb-pd@c/connector
/soc/spmi@28a1a8000/usb-pd@c/connector: Fixed dependency cycle(s) with /soc@200000000/usb@382280000
usbcore: registered new interface driver usbfs
usbcore: registered new interface driver hub
usbcore: registered new device driver usb
platform 2aa280000.usb: Adding to iommu group 0
platform 382280000.usb: Adding to iommu group 2
```

The "Fixed dependency cycle(s)" lines are informational: the connector graph points both ways
between a port controller, its PHY and its dwc3, and the driver core says it resolved that. No
line says "deferred", "failed" or "error" for any of these devices, and no line mentions xHCI.
The two earlier boots of this kernel (13:51 and 15:12 on 2026-11-14) have the same lines and
nothing else: no attach was ever logged.

### 3. Nothing is attached

```
port0 IDLE  "USB-C Left-front", controller 1-0a [sn201202x], phy 2ab000000.phy [apple-t6050-dp-phy],
            usb 2aa280000.usb [dwc3-apple], partner no, data device, power sink
port1 IDLE  "USB-C Right", controller 2-0c [sn201202x], phy 383000000.phy [apple-t6050-dp-phy],
            usb 382280000.usb [dwc3-apple], partner no, data device, power sink
```

(`tests/k114s-usb-check.sh`.) Neither port has a `portN-partner`. The two port controllers'
power supplies (`tps6598x-source-psy-1-0a`, `-2-0c`) report `online` 0 while `macsmc-ac` reports
1: the charger was on MagSafe or on the left-back port, which is not described.

### 4. Idle means no xHCI: the driver says so

`drivers/usb/dwc3/dwc3-apple.c` at `a34d26c255c2`, in the description of its state machine and
again in the probe function:

> During initial probe we don't have any information about the connected cable and can't bring
> up the PHY properly and thus also can't fully bring up dwc3. Instead, we just keep everything
> off and defer the first dwc3 probe until we get the first cable connected event. Until then we
> stay in DWC3_APPLE_PROBE_PENDING.

The xHCI platform device is created by `dwc3_host_init()`. For a port like these it first runs
from `dwc3_usb_role_switch_set()` with `USB_ROLE_HOST`, which the port controller's driver calls
after it has read a data connection from the controller. On a disconnect the driver tears the
core down again (`DWC3_APPLE_NO_CABLE`). The only boards with a host at boot are those with a
fixed hub on the controller (Apple J700), which this is not.

Two more things follow from the same file and matter for the test:

- `apple,t6050-dwc3` is **host-only**: `dwc3_apple_host_only()`. If the other end is a host or
  a charger (the Mac would be the USB device), the port logs "No device mode on this port:
  staying off" and stays off. That is not a fault either.
- On the K114c the right port has had no data device (aurora-silicon/linux #1714: "not
  tested"); its worked example is a USB Ethernet adapter at SuperSpeed. The K116s report says
  "USB-C" without naming a port. Test the left-front port first.

### 5. The device tree is the K116s's

Compiled and compared as trees (phandles resolved to node paths), `dts/t6050-k114s-r1.dts`
against `t6050-k116s.dts` of aurora-silicon/linux `0b03fe434e50` (integration/aurora on
2026-11-14, with pull request 1648, `377b2a2decf1`): **0 differences** over the 42 nodes of the
two ports. That is both SPMI buses with their controllers and connector graphs, both PHYs, both
PHY mailboxes, both dwc3 nodes, the four DARTs and the eight power domains they need. `tests/test-usb-dtb.sh KTREE K116S_KTREE` repeats the comparison.

The live tree (`/proc/device-tree`) equals the built r1 tree in those nodes, plus what the loader
adds: 14 `apple,tunable-*` properties on each PHY and one `apple,tunable` on each of the four
DARTs, 32 properties in all and no other difference. So the loader found both PHYs through the
`atcphy1`/`atcphy2` aliases and filled their tunables from this machine's ADT.

No kernel code on this path depends on the board: `dwc3-apple.c`, `atc-t6050-dp.c`,
`spmi-apple-controller.c` and the tipd driver test the SoC or other boards (J613, J716c), never
K114s or K116s.

### 6. Kernel configuration

From `/proc/config.gz`: `USB_DWC3_APPLE=m`, `USB_DWC3_DUAL_ROLE=y`, `USB_XHCI_HCD=y`,
`USB_XHCI_PLATFORM=y`, `TYPEC=m`, `TYPEC_SN201202X=m`, `PHY_APPLE_T6050_DP=m`, `SPMI_APPLE=y`,
`APPLE_DART=y`, `USB_ROLE_SWITCH=y`, and for the first test devices `USB_STORAGE=y`, `USB_HID=y`,
`USB_RTL8152=m`, `USB_NET_CDC_NCM=m`. Nothing the host path needs is missing.
`DYNAMIC_DEBUG` is off, so the drivers' debug messages cannot be turned on in this kernel; the
`tps6598x` trace events can (root).

## The candidates of docs/upstream-applicability.md row 3

| Candidate | Finding |
| --- | --- |
| `218e3f8550ba` tipd: probe asynchronously (#1671) | Not in base, and **not a fix here**. It only lets the port controllers of one machine probe at the same time instead of one after another. It was written for the J575c, where each inherited connection is renegotiated for 5.6 s at probe. Both K114s controllers already probe and bind, and the renegotiation is keyed to J716c (and J575c at head) and to a property this tree does not have. Carried as `patches/linux/usb/0001-…patch` so r3 can follow upstream head; optional. |
| `1a774eeee49a` tipd: renegotiate inherited J575c connections (#1671) | J575c only (board key table). Not applicable. |
| `377b2a2decf1` (#1648, USB part) | Already ported in r1; equal to upstream head (section 5). |
| #1714 (K114c) | In base. Its K114c tree gives nub-spmi-a0 the fault-queue window, which K116s and r1 do not have. It is a diagnostic, not a requirement: see `K114S_R3_USB_SPMI_FAULTS` below. |

Between base and head nothing else changed in `drivers/usb/typec`, `dwc3-apple.c`,
`atc-t6050-dp.c`, `drivers/spmi` or `drivers/usb/roles` (the three `phy: apple: atc` commits are
T8132 only).

## What is in this branch

| Path | What |
| --- | --- |
| `dts/t6050-k114s-usb.dtsi` | r3 USB file. Adds nothing by default. Section `K114S_R3_USB_SPMI_FAULTS` gives both port-controller buses their fault-queue window (diagnostic) |
| `dts/t6050-k114s-r3-usb.dts` | r1 plus that file with no section on: compiles byte-identical to `t6050-k114s-r1.dts` (sha256 of the blob built against `a34d26c255c2`: `2ea22d26…`). The name r3 builds on |
| `dts/t6050-k114s-r3-usb-faults.dts` | r1 plus the fault queues. Only for a plug test that failed with SPMI errors. Not booted anywhere |
| `patches/linux/usb/0001-usb-typec-tipd-sn201202x-probe-asynchronously.patch` | Upstream `218e3f8550ba`, Roberto Dantas, GPL-2.0, optional. Applies to the installed source (offset 10 lines) |
| `tests/k114s-usb-check.sh` | Port state from sysfs and the log, no root. One verdict per port; `--watch N` prints every change while a device is plugged in |
| `tests/k114s-usb-root-probe.py` | Root, read-only: `regs` decodes the port controllers' registers (does the controller see the plug?), `adt` compares the tree's USB-C addresses and bus positions with this machine's ADT |
| `tests/lint-usb-dtb.py`, `tests/test-usb-dtb.sh` | Tree lint (enabled suppliers, closed graph, required properties, debug port not described) and the K116s comparison |
| `tests/test-usb-check.sh`, `tests/test-usb-root-probe.py` | Software tests of the two scripts against made-up sysfs trees, registers and an ADT |

The r1 tree files are unchanged.

## The plug test (owner, no root)

1. `tests/k114s-usb-check.sh --watch 60`
2. Plug a USB device (a flash drive, keyboard or USB Ethernet adapter; not a charger, not another
   computer) directly into the **left-front** port. Wait for the report to change. Unplug, turn
   the plug over, plug in again.
3. The same on the **right** port.
4. Then once with the device attached before power-on (an inherited connection), and run the
   script without `--watch` after boot.

| Verdict | Meaning | Next step |
| --- | --- | --- |
| `OK` with the device listed | The port works. Record speed and orientation as owner-observed | none |
| `IDLE` with a device plugged in | The port controller reports no plug, or the driver's poll does not see it | `sudo python3 tests/k114s-usb-root-probe.py regs` with the device in. "NO plug": controller or connector side (compare with the `adt` output). "plug present": the poll does not act on it, a tipd driver matter for upstream |
| `NOT-A-HOST` | The Mac is the USB device on this cable (charger, other host). By design | test with a real device |
| `NO-HOST` | Device attached, Mac is host, no xHCI | the log lines the script prints: `dwc3-apple … Failed to …`, `USB3 PHY setup failed`, PHY or DART errors name the stage |
| `HOST-EMPTY` | xHCI is up, the device did not enumerate | try a USB2 device and the other orientation; "USB3 PHY setup failed, USB2 only" in the log means the SuperSpeed lanes |
| `NOT-PROBED` | A driver is not bound (not the state today) | `tests/test-usb-dtb.sh` on the tree that was booted |

If the log shows `apple-spmi` errors during the test, boot `t6050-k114s-r3-usb-faults` once: the
SPMI driver then logs the controller's fault record after a failed command.

## State on r3a (2026-11-15, agent-run) and the plug test script

Re-read on the promoted r3a kernel (`uname -v` contains `K114S-R3A`) on the GPU Stage 2, without
root: both `dwc3-apple` devices, both `sn201202x` controllers and both PHYs are bound, both typec
ports exist, `tests/k114s-usb-check.sh` says `IDLE` for both ("partner no", data device, power
sink), `/sys/bus/usb/devices` is empty, and the kernel log has no Type-C, dwc3, xHCI, tipd or
SPMI line. **Port numbering moved:** on r3a `port0` is "USB-C Right" (controller 2-0c) and `port1`
is "USB-C Left-front" (1-0a); on r1 it was the other way round. Go by the label, not the number.
The tipd asynchronous probe (`218e3f85`, `patches/linux/usb/0001`) is in r3a and both controllers
still bind with no error, but that is not a plug test: no attach has happened since it went in.
Still untested, as before.

**Owner plug test in one command** (no root, read-only, about five minutes):

```
bash tests/hardware/k114s-usb-plug-test.sh
```

It prompts for each port in turn (left-front, then right): plug, watch 60 s, flip the plug,
unplug. It prints the verdict, the Type-C partner and roles, every enumerated device with speed
(no serial numbers) and the attach's kernel-log lines (addresses masked). Paste the output into
#60. Use a device that is a USB device (flash drive, keyboard, USB Ethernet adapter), not a
charger. A suspend or forced power-off is not expected; if the Mac hangs, say at which step.
`bash tests/test-usb-plug-test.sh` tests the script against a made-up sysfs tree.

## Upstream candidates reviewed for r3a (aurora-silicon/linux, 2026-11-15)

| PR | State | Verdict for K114s |
| --- | --- | --- |
| #1648, #1714 | merged | In r3a already (section above) |
| #1671 (`218e3f85`, `1a774eee`) | merged | Async probe carried (optional); the renegotiation is J575c-keyed, not applicable |
| #1721 tipd: no `LDCM` to a dry port | open | **Candidate, not a blocker.** Changes only `drivers/usb/typec/tipd/spmi.c` and `tps6598x.h`. macOS sends no `LDCM` to a dry port; the driver today sends one at each probe and reset and waits up to 5 s. Both K114s controllers bind with no error today, so it fixes no observed fault. Take it after the plug test, only if the attach log shows a delay or a liquid-detection (contaminant) report. Not applied. |
| #1889 tipd: idle sleep on T6041 | open | **Not applicable.** Keyed to T6041 (M4 Max); the K114s is T6050, the controllers stay awake. |
| #1947 dwc3-apple: PM notifier teardown | merged (after r3a was cut) | Concerns suspend (blocked here by masked targets). Pick up with the next integration rebase, with the suspend work (`r3-sleep-lid.md`), not for USB host. |

Nothing here changes the r3a contents; the decision is "no USB patch joins r3a before the plug
test".

## Root steps for the lead

None are needed for USB host. Optional, read-only, to settle two things the agent could not read:

```
sudo python3 tests/k114s-usb-root-probe.py adt     # tree addresses and SPMI positions vs this Mac's ADT
sudo python3 tests/k114s-usb-root-probe.py regs    # what each port controller reports (run with a device in)
```

The `adt` output prints only addresses, bus positions, port numbers and node names. Do not
publish the ADT itself.

## Not verified

- **That either port works.** No device has been attached under Linux on this Mac. Equality with
  the K116s tree is a software result.
- The tree's USB-C addresses against this machine's own ADT. The repository's record is that the
  K114s and K116s ADTs are identical in these nodes; `k114s-usb-root-probe.py adt` checks it and
  has not been run (root). Its node paths (`/arm-io/nub-spmi-a0`, `usb-drd1`, `atc-phy1`, `hpm1`
  and so on) are taken from the tree's comments, not read here.
- `K114S_R3_USB_SPMI_FAULTS`: nub-spmi-a0's fault window `0x28a184000` is the J714s and K114c
  value (same SoC), not read from the K114s ADT. The `adt` probe prints the real one. Do not boot
  the faults tree before that matches.
- A device attached at boot. Upstream renegotiates such connections on J716c and J575c only.
- The right port with a data device: no upstream report names one on a K114c or K116s.

## USB4 / Thunderbolt (notes only, not enabled)

- The `thunderbolt` and `thunderbolt_apple` modules are loaded (`USB4=m`, `USB4_APPLE_SOC=m`), but
  the tree describes no router, so there is no NHI and nothing for them to bind.
- Without a router the ports are USB only: USB 2 and USB 3 devices and hubs, and the USB part of a
  USB4 or Thunderbolt 4 dock. A Thunderbolt 3 device with no USB fallback will not appear. No
  DisplayPort over USB-C either (see the matrix: on 27.2 the K116s's `dcpext0` times out).
- Upstream describes T6050 routers for J714s left-front (`t6050-j714s-left-usb4.dtsi`, #1791),
  J716c left, and the right port (`t6050-max-atc2.dtsi`, `t6050-max-atc2-router.dtsi`; K114c in
  #1841, `18b66412170c`). **The K116s tree at head describes none**, so the K114s has no twin to
  copy from yet.
- A K114s router needs, per port: the `acio` router node and its mailbox, the NHI, its DART, the
  PCIe tunnel, the `ps_atcN_cio*` and `ps_atcN_pcie` domains, the router's LSTX pin on the AOP
  GPIO controller, a `port@3` endpoint on the connector, the CIO tunables of the PHY, and the
  host DROM. Addresses, interrupts, the LSTX pin and every tunable must be read from this
  machine's ADT (`/arm-io/acio1`, `acio2` and their neighbours). The host DROM carries the
  router's UUID, which is the unit's identity: it must come from this Mac through the loader and
  never from a sibling's tree.
- Order: USB host confirmed on both ports first, then the right port's router (the one with a
  K114c example), each as its own tree.
