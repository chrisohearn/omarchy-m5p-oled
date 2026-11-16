# Touch ID plan for the K114s (issue #49)

Status: **research plan and one disabled device-tree fragment; in no tree, never booted.** Written
2026-11-15 on the K114s (kernel `7.3.0-17.v272-4-k114s-r3a-ARCH`), owner away. Evidence labels:
agent-run, upstream-reported. Nothing here touched the Secure Enclave, xART or macOS: the driver was
never loaded and `/dev/sep-bio` never opened.

## Bottom line

The hardware description is ready: every sensor and SEP value of the K114s's Apple device tree (ADT)
equals what upstream validated on the J714s (#1587, merged). Three things other than the tree block
Touch ID, and none is ours to fix alone:

1. **The installed driver refuses this Mac.** `apple-sep.ko` in the r3a kernel names only
   `apple,j714s` and `apple,k116s` for its T6050 profile (agent-run: strings of the module;
   upstream `drivers/soc/apple/profile.rs` has the same list). linux #1649 added the K116s with a
   three-line change; the K114s needs the same line. Owner of that change: TripleU613's shared T6050
   lane (betizzel/omarchy-m5) or aurora-silicon.
2. **`/aliases/sep` is missing from the booted tree** (agent-run). The K116s tree has `sep = &sep;`.
   The fragment adds it. Whether our m1n1 uses the alias to start the SEP is the owner's boot-trial
   question below.
3. **omarchy-mac answers `unsupported:board` for any T6050** (agent-run: its `touchid-eligibility`
   run against a replica tree with `apple,k114s`/`apple,t6050` and a sensor node, and the same for
   `apple,j714s`; a replica `apple,t8122`/`apple,j613` tree answers `available`). Its board list is
   t8112, t6020, t6021, t8140 and the M3 Airs. Owner: omacom (omarchy-mac). That is why the
   aurora-sep package here is the route, not omarchy-mac's consent flow.

None of this needs a Secure Enclave write to settle. The writes begin only when the owner enrols.

## What was read (agent-run, 2026-11-15)

Booted tree (`/proc/device-tree`, no root needed unless noted):
- `spi@505108000` (spi2), `pinctrl@2881e4000` (the always-on `nub_gpio0` bank, already a GPIO and
  interrupt controller in this base tree) and `sep@502600000` exist, all `status = "disabled"`.
- No `fingerprint@*` node anywhere; no `/aliases/sep`; `/chosen/apfs-preboot-uuid` is present
  (existence only, value not read), which omarchy-mac needs.
- AP pin controller reserves 0-79 and 81-220 (`dts/t6050-k114s-common.dtsi`), so pin 138, the sensor's
  data-ready line, is reserved. That is the gap #1587 fixed on the J714s (`didn't like hwirq-0x8a`).

ADT (root, from the `adt` partition, only addresses, interrupts, pins and the sensor generation id
printed; no calibration, key or serial read), compared by `tests/k114s-adt-touchid-facts.py` with the
compiled tree: **19 facts, all hold.** Two are ADT-only checks of a constant (spi2 clock-ids 451, sensor id 0x3356); chip select 0 is read from the tree only. `tests/test-adt-touchid-facts.py` proves the checker fails when an ADT or tree pin differs.

| Item | ADT |
| --- | --- |
| sensor | `/arm-io/spi2/mesa`, `sensor-id` 0x3356 (Mesa V3, the same id #1587 gives the J714s), `spi-frequency` 8 000 000 |
| spi2 | `0x505108000` + `0x4000`, interrupt 1369, `clock-ids` 451 (the 24 MHz reference) |
| sensor power | `function-mesa_pwr`: nub-gpio0 (`0x2881e4000`, 61 pins) pin 21 |
| data ready | `interrupts`: AP gpio0 pin 138 |
| SEP | `0x502600000` + `0x88000`, `0x502050000`, interrupts 533-536, `clock-ids` 447 |
| dart-sep | `0x500b80000`, interrupt 543, window `0x10000004000` + `0xffff0000` |

Userland on the machine: `aurora-sep` 1.17, `libfprint-aurora`, `fprintd`, `omarchy-mac` 0.2.3 are
installed. `apple_sep` is not loaded, no `/dev/sep-bio`, no Linux keybag
(`/var/lib/aurora-sep-keybag.bin` absent), `aurora-sep status` reports only `sep-device absent`. The
package ships read-only options (`xart_writes=0 provision_keybag=0`), so a load without the owner's
decision still writes nothing.

## The draft fragment

`dts/t6050-k114s-touchid.dtsi`, switch `K114S_R3_TOUCHID`. It is #1587's J714s block plus the K116s SEP
block: spi2 and its power state on, the sensor node `fingerprint@0` (8 MHz, SPI mode 2, CS timing 20 ns,
power `nub_gpio0` pin 21, data ready pin 138 rising), `nub_gpio0` and its always-on power state on, the
SEP mailbox and `ps_sep` on (`sep` and `sep_dart` stay disabled: `apple_sep` enables them), and the `sep`
alias. Pin 138 is exposed; pin 112 stays reserved. `K114S_TOUCHID_WITH_SD` and
`K114S_TOUCHID_WITH_SOUND` carry the pins of the other fragments, since each replaces
`gpio-reserved-ranges`.

`tests/test-touchid-dtb.sh KTREE` (kernel tree `src/r3b`; run after the build environment's `env.sh`):
- without the switch the tree is byte-identical to r1;
- with it, all three pin variants compile; sensor, 8 MHz, pins 21 and 138, the alias and the
  disabled `sep`/`sep_dart` are as listed; pin lint passes (exposed pins 80+138, +81 with the SD
  reader, 80,81,134,138,139 with sound; 112 reserved; no range runs past the 221 pins);
- a wrong power pin is detected. Result today: all passed.

Open values: the two `firmware-name` files (`apple/mesacal-k114s.bin`, `apple/msrk-k114s.bin`) follow
the J714s pattern. `aurora-touchid-setup` carves them from this Mac's own iBoot System Container; it has
a J714s seal fix (#1587) and was never run on a K114s. Whether the K114s seal needs another parser
case is unknown. The sensor's SPI mode and CS timing are the J714s values (the ADT does not carry them).

## What makes the write risk, and the guard

From the package's `XART-SAFETY.md` and README (read, not run): the driver's guard level 1 lets Linux
rewrite only the xART session records Linux created. Creating the identity keybag on first enrolment
rewrites **one existing session record that macOS also uses**, once, after saving the old value to a file.
A bug there can leave macOS unable to unlock (FileVault: a DFU restore that erases the Mac; no
FileVault: macOS resets its keychain and Touch ID). Changing the boot object or Stage 1 afterwards
makes the enclave rewrite another record on first unlock. The J714s validation in #1587 recorded no
refusal and no touched macOS volume, but that is one Mac; the K114s is a different board and boot chain
(Stage 2 chain-loaded by m1n1). A K114s enrolment would be the first on this boot chain.

## Plan

Phases 0 to 2 need no Secure Enclave write. Each later phase needs the owner's go.

| Phase | Work | Who | Writes SEP/xART? |
| --- | --- | --- | --- |
| 0 | This plan, the fragment, the ADT check, `tests/hardware/k114s-touchid-check.sh` | done here | no |
| 1 | Driver profile: add `apple,k114s` to the T6050 match (like #1649). Build a kernel with it | TripleU613 / aurora-silicon, then us to port | no |
| 2 | Include the fragment in a trial tree behind the switch; build; compile test | us | no |
| 3 | Trial boot of that tree with the driver NOT loaded: confirm `/aliases/sep`, the sensor binds on spi2 only if `apple_sep` opens it (it should not), no regression (Wi-Fi, trackpad, GPU), pin 138 mapped | owner at the Mac | no |
| 4 | Read-only load: `modprobe apple_sep` with the shipped options, `aurora-sep status`, `aurora-touchid-setup --check`, `apfs-xart-inspect.py` on the iBoot System Container. Expect attach, 12 endpoints, `xart disabled`, keybag unknown (the RAM-tested J714s result) | owner at the Mac | no (options turn writes off) |
| 5 | Decision to enable; backups of the iBoot System Container's xART store and the macOS FileVault/DFU plan; macOS agent confirms the Mac boots to macOS after the trial | owner | no |
| 6 | Enable writes, enrol, reboot, verify, wrong finger, re-enrol after reboot; macOS boot check | owner | **yes** |
| 7 | omarchy-mac eligibility for T6050 (or keep aurora-sep's own flow); Hyprland lock-screen and sudo prompt | omacom, us | no |

## Owner steps (nothing is needed now)

Today, read only, no reboot:
```
bash tests/hardware/k114s-touchid-check.sh
```
It prints the booted tree's state and the driver's profile list and writes nothing. Phase 3 onward waits
for upstream (phase 1) and for the owner's go for phase 5.

## Upstream

- Driver profile for the K114s: aurora-silicon/linux, or betizzel/omarchy-m5 (the shared T6050 lane), as a
  follow-up to #1649. Not posted. Draft: add `apple,k114s` next to `apple,k116s` in the T6050 profile
  match list of `drivers/soc/apple/profile.rs`, with the ADT facts of this document as evidence.
- omacom/omarchy-mac `lib/touchid-eligibility`: no T6050 board. aurora-sep's README already notes it.
  Needs a decision there on whether Touch ID on T6050 goes through omarchy-mac or aurora-sep.

## Index rows proposed (not edited here)

- `docs/matrix.md` Touch ID / Secure Enclave row: evidence column "ADT sensor and SEP facts all equal
  the J714s of #1587 (19 facts, agent-run); draft fragment `dts/t6050-k114s-touchid.dtsi`; installed
  `apple_sep` does not admit `apple,k114s`; omarchy-mac says `unsupported:board`"; state stays
  `evaluated`; next: upstream K114s profile line (docs/r3-touchid.md).
