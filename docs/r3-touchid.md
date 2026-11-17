# Touch ID plan for the K114s (issue #49)

Status: **phases 1 and 2 done (2026-11-16): the kernel r3b.c4 admits the K114s and the trial tree and
its Stage 2 file are built; not booted.** The owner chose to go through to enrolment (section "The owner's
decision"). The plan below was written 2026-11-15 on the K114s (kernel `7.3.0-17.v272-4-k114s-r3a-ARCH`),
owner away. Evidence labels: agent-run, upstream-reported, emulator/replica. Nothing here touched the
Secure Enclave, xART or macOS: the driver was never loaded and `/dev/sep-bio` never opened.

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

Since 2026-11-16, 1 and 2 have a local answer: `patches/linux/sep/0001` (kernel r3b.c4) adds the K114s line,
and the trial tree `dts/t6050-k114s-r3b-touchid.dts` carries the alias (section "Phases 1 and 2"). 1 still
needs the same line upstream. 3 stays: this Mac takes the aurora-sep route.

## The owner's decision (2026-11-16)

Asked in a T3 dialog (K114s display-parity thread, ledger row `k114s/touch-id`), answered by the owner:
- **How far:** all the way to enrolment, through the read-only trial first.
- **FileVault in macOS:** not known, so it is treated as on: a Secure Enclave bug that broke macOS unlock
  would then need a DFU restore, which erases the whole disk, this Linux install included. A read of
  the macOS container's volume flags does not settle it (agent-run): the macOS data volume and the boot
  stub's data volume, which has no FileVault user, both read encrypted (`fs_flags` 0x100), as every Apple
  silicon data volume does.
- **Upstream:** open the K114s profile line on aurora-silicon/linux once the read-only trial passes.
- **Reboot:** first "when I am at the Mac"; in a second round the same evening, away from the Mac, the owner
  chose to run the trial boot unattended, accepting that a hang leaves the Mac dark until the power button is
  held. The reboot rule still applies: a Jarvis acknowledgement is recorded first.
- **Backup copy:** the iBoot System Container image also goes to omarchy-pc (owner-only folder, checksums on both
  machines).
- **macOS:** holds nothing the owner still needs, so no macOS backup comes before enrolment.
- **Where the fingerprint works:** sudo, polkit (admin dialogs) and the lock screen, Omarchy's own set.

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
| 1 | Driver profile: add `apple,k114s` to the T6050 match (like #1649). Build a kernel with it | **done locally 2026-11-16** (`sep/0001`, r3b.c4); upstream after phase 4 | no |
| 2 | Include the fragment in a trial tree behind the switch; build; compile test | **done 2026-11-16** (`t6050-k114s-r3b-touchid.dts`, Stage 2 `3cc123d8…`) | no |
| 3 | Trial boot of that tree with the driver NOT loaded: confirm `/aliases/sep`, the sensor binds on spi2 only if `apple_sep` opens it (it should not), no regression (Wi-Fi, trackpad, GPU), pin 138 mapped | owner at the Mac | no |
| 4 | Read-only load: `modprobe apple_sep` with the shipped options, `aurora-sep status`, `aurora-touchid-setup --check`, `apfs-xart-inspect.py` on the iBoot System Container. Expect attach, 12 endpoints, `xart disabled`, keybag unknown (the RAM-tested J714s result) | owner at the Mac | no (options turn writes off) |
| 5 | Decision to enable; backups of the iBoot System Container's xART store and the macOS FileVault/DFU plan; macOS agent confirms the Mac boots to macOS after the trial | owner | no |
| 6 | Enable writes, enrol, reboot, verify, wrong finger, re-enrol after reboot; macOS boot check | owner | **yes** |
| 7 | omarchy-mac eligibility for T6050 (or keep aurora-sep's own flow); Hyprland lock-screen and sudo prompt | omacom, us | no |

## Phases 1 and 2: r3b.c4 and the trial tree (2026-11-16)

**Kernel r3b.c4** (`patches/linux/r3b-c4.series`) is r3b.c3 plus `sep/0001`: `apple,k114s` joins `apple,j714s`
and `apple,k116s` in the T6050 match of `drivers/soc/apple/profile.rs`, with a KUnit case, the form #1649 used
for the K116s. The release, the package name and the configuration stay, and nothing loads `apple_sep` by
itself, so r3b.c4 boots as r3b.c3 does. The build record is in `docs/r3b-kernel.md`, section 12.

**Trial tree** `dts/t6050-k114s-r3b-touchid.dts`: the booted brightness tree plus the fragment, switched on,
built on the same includes (P's, `docs/r3-display-plan.md` 3.2). The brightness tree has neither the SD reader
nor sound, so the fragment's default pin variant applies.

| Check | Result | Label |
| --- | --- | --- |
| `build/build-dtb.sh` of `t6050-k114s-r3b-brightness` on P's includes (control) | `5b6b83c8…`, byte for byte the pinned tree this Mac boots | agent-run |
| The same for `t6050-k114s-r3b-touchid` | `3d4580e5f7e81428c02deeb306262aa7595b0ff47e34318df8d497bc0d5bf0d0`, 109,300 bytes | agent-run |
| `tests/dtb-node-diff.py` brightness against Touch ID | 1 node added (`fingerprint@0` on spi2); changed: `sep` alias, spi2 status and clock, nub-gpio0 status, the SEP mailbox, AP `gpio-reserved-ranges` (138 out), five power domains (two `apple,firmware-owned`) | agent-run |
| `tests/lint-dtb.py` | passed: 221 AP pins, exposed 80 and 138 | agent-run |
| `sudo python3 -I tests/k114s-adt-touchid-facts.py` on the trial tree, against this Mac's ADT | every fact holds (19) | agent-run |
| `tests/test-touchid-dtb.sh` on P's includes and on `src/r3b-c4` | all passed, including the new check that the trial tree is the brightness tree plus the fragment and nothing else (it fails when one more property is added) | agent-run |
| `build/make-stage2.sh` with the pin loader `beceb683…` (control: brightness tree) | `90b35137…`, byte for byte this Mac's `m1n1/boot-ctxr.bin` | agent-run |
| The same with the Touch ID tree | `boot-ctxr-touchid.bin` `3cc123d88d49f9af6ffa4692d42bc8785d15c8f1012a08c0040a443e44b64061`, 4,506,542 bytes: prefix `beceb683…`, tree `3d4580e5…`, trailer `9d8dc11e…` | agent-run |

The tree, the Stage 2 file and `SHA256SUMS` are in `$K114S_BUILD_ROOT/integrate/release-touchid-t1/`.

## Phases 3 and 4: one watched trial boot

1. **Install r3b.c4** in place of r3b.c3, as r3b.c3 was installed (`docs/r3-vrr.md` section 5, V1 step 2:
   `SHA256SUMS`, `check-package.sh` with `K114S_CAND=r3b-c4` against `linux-aurora` and `linux-k114s`, one
   `Building UKI for linux-k114s-r3b` line, `boot-ctxr.bin` and the r3a image unchanged). No reboot needed:
   it changes only `apple-sep.ko`, which nothing loads. The way back is the r3b.c3 package.
2. **Arm, with the owner at the Mac.** Block P9 first. Write `boot-ctxr-touchid.bin` to `/boot/efi/m1n1/`, read
   it back, then `aura-try` = `armed` / `m1n1/boot-ctxr-touchid.bin` (as the display trials did,
   `docs/r3-display-d5-d9.md` T3a). The kernel entry is the default; no Limine one-shot. Reboot.
3. **If the trial boot hangs**, hold the power button and start again: Aura's Stage 1 marked the trial
   `spent` before it ran, so the next boot is the configured Stage 2 (`90b35137…`).
4. **Phase 3 checks, in the trial boot.** `/proc/device-tree/chosen/aurora,trial` names
   `m1n1/boot-ctxr-touchid.bin`; `tests/hardware/k114s-touchid-check.sh` shows the sensor node, `/aliases/sep`
   and `apple_sep admits apple,k114s`; block P9 (display, GPU, Wi-Fi, trackpad, keyboard) holds; no new
   `pinctrl`, `spi` or `gpio` error in the kernel log.
5. **Phase 4, read only, in the same boot.** `modprobe -c` names exactly `xart_writes=0 provision_keybag=0`
   for `apple_sep` (`/usr/lib/modprobe.d/aurora-sep-xart.conf`, nothing in `/etc`). Then, as aurora-sep's
   `README.omarchy-m5.md` step 2 says: `sudo modprobe apple_sep`, `sudo aurora-sep status` (expect the driver
   attached, `xart disabled`, keybag `unknown` or `missing`), `sudo python3 /usr/lib/aurora-sep/apfs-xart-inspect.py
   /dev/disk/by-partlabel/iBootSystemContainer` (one `.gl` extent), `sudo aurora-touchid-setup --check` (names
   `apple/mesacal-k114s.bin` and `apple/msrk-k114s.bin`, the tree's `firmware-name`, and says it can build them;
   a seal it cannot parse is a finding for upstream, not a reason to force).
6. **Promote the tree** once 4 and 5 pass: the Touch ID tree becomes the pinned tree (both copies of
   `k114s.dtb`), and `update-boot-ctxr` rewrites `m1n1/boot-ctxr.bin`, which must then be `3cc123d8…`, the file
   the trial booted. Then the upstream PR (section "Upstream").

## Phases 5 and 6: backups and enrolment

These follow aurora-sep's `README.omarchy-m5.md` steps 3 to 6, which this package's maintainers wrote for the
J714s. On this Mac:
- **Guard.** The T6050 profile is T6040's, so `xart_guard` is 1: Linux rewrites only the session records it
  created, and the keybag creation is let through one rewrite of one existing record, whose old value is saved
  to `/var/lib/aurora-sep-xart-policy-previous.bin` first (`XART-SAFETY.md`, "The keybag creation window").
- **Backups before the first write.** The macOS data the owner still needs. The iBoot System Container imaged
  read-only (`zstd`, `sha256sum` of the partition and of the decompressed image, root-only under
  `/var/lib/aurora-rollback/`), and a copy **off this Mac**: a DFU restore erases this disk, Linux included.
  The image is evidence, not an undo: the enclave's anti-replay counters only move forward.
- **Opt in:** `/etc/modprobe.d/aurora-sep-xart.conf` with `options apple_sep xart_writes=1 provision_keybag=1`,
  `sudo aurora-touchid-setup` (writes only `/usr/lib/firmware/apple/*.bin` and `/var/lib/aurora-sep/`, with
  rollback copies), `systemctl enable aurora-sep.service`, reboot.
- **Enrol and verify:** `fprintd-enroll`, `fprintd-verify` with the enrolled finger and with another one, reboot,
  `fprintd-verify` again without re-enrolling.
- **Not Omarchy's Setup > Security > Fingerprint:** it installs `libfprint-git`, which speaks sep-bio interface
  4; this kernel speaks 5 (`libfprint-aurora` conflicts with it, so the transaction fails), and its
  `enable-fingerprint` hook asks omarchy-mac, which answers `unsupported:board`. Phase 7 does its other two steps
  by hand: the `pam_fprintd` lines of its `setup_pam_config` (sudo and polkit, each behind the
  `omarchy-hw-laptop-closed` clamshell gate), then `omarchy-apply-lock`, which turns the lock screen's fingerprint
  PAM on once `fprintd-list` shows an enrolled finger.
- **Later boot-chain changes.** A new Stage 1, another boot object or a boot-mode change makes the enclave
  rewrite one record on the first unlock after it. Before such a change run `sudo aurora-sep-policy-change
  --expect` (`XART-SAFETY.md`, "Changing Stage 1 on purpose"). Stage 2 files on the ESP (`boot-ctxr.bin`,
  `aura-try`) are not the boot policy.
- **macOS afterwards.** On the next macOS boot, the owner checks Touch ID and unlock there (recorded, not a
  gate), and can read the FileVault setting, which settles the question above.

Read only, any time:
```
bash tests/hardware/k114s-touchid-check.sh
```
It prints the booted tree's state and the driver's profile list and writes nothing.

## Upstream

- Driver profile for the K114s: aurora-silicon/linux, as a follow-up to #1649. `patches/linux/sep/0001` is the
  change (it applies to `integrate/aurora` as #1649's did). Not posted: the owner chose to open it once the
  read-only trial (phase 4) passes, with that result and the ADT facts of this document as evidence.
- omacom/omarchy-mac `lib/touchid-eligibility`: no T6050 board. aurora-sep's README already notes it.
  Needs a decision there on whether Touch ID on T6050 goes through omarchy-mac or aurora-sep.

