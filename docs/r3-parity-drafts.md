# Parity drafts: video decode (#30), SD card reader (#62), ambient light and lid angle (#67)

Status: **three disabled device-tree fragments, checked against this Mac's Apple device tree
(ADT); in no tree, never booted.** Written 2026-11-15 on the K114s (kernel `7.3.0-17.v272-4-ARCH`),
owner away. Evidence labels: agent-run, replica, upstream-reported.

## What was added

| Issue | Fragment | Switch | Source |
| --- | --- | --- | --- |
| #30 hardware video decode | `dts/t6050-k114s-avd.dtsi` | `K114S_R3_AVD` | linux #1856 (K116s, merged), equal to J714s #1577 |
| #62 SD card reader | `dts/t6050-k114s-sd.dtsi` | `K114S_R3_SD` (`K114S_SD_WITH_SOUND`) | linux #1719 (K114c draft), same values as K116s `54348df1` (#1648) |
| #67 ambient light, lid angle | `dts/t6050-k114s-aop-sensors.dtsi` | `K114S_R3_AOP_SENSORS` (`K114S_AOP_WITH_AUDIO`) | the AOP enable of the K116s, K114c and J714s trees; `als`/`las` nodes of the base, linux #1645, #1751 |

Each fragment is inert unless its switch is defined: included without it, the tree is byte-identical
to r1 (tested). None is included by any `.dts` of this repository, so no booting tree changes. Include
one after `t6050-k114s-common.dtsi`; the SD fragment needs `K114S_R1_N1` and refuses to compile
without it. The nodes themselves are in the base kernel tree, disabled; the AVD and AOP fragments
only enable them, the SD fragment adds the port-1 node as the K114c tree does.

## What the ADT says (agent-run, 2026-11-15, `tests/k114s-adt-parity-facts.py`, 72 facts, all hold)

**AVD (#30).** `avd0` window `0x2108000000 + 0x1404000` (the tree's four sub-blocks lie inside it),
interrupts 2417 and 2418; `dart-avd0` `0x2109020000 + 0x20000`, interrupt 2424, streams 0 to 2 as the
tree's `iommus`; pmgr block `reg[46]` `0x2180600000`; power states `FAB1_SOC` offset `0x1b0` and
`AVD_SYS` offset `0x1d8`, `AVD_SYS` a child of `FAB1_SOC`; the power gates of `avd0` and `dart-avd0`
hang off `AVD_SYS`. All equal the K116s values of #1856. The ADT also gives `avd-version` 4 and
`avd-ads-keytype-version` 3 (the T8142 generation the base's node is written for).

**SD reader (#62).** Port 1 registers (`apcie0` reg[22], [24], [25], and the shared PHY reg[3]),
port interrupt 1531, PERST# gpio0 pin 81, power `pKW8('pcIO', 0x0, 0x190000)` (SMC command index 3 in
this tree's list), `dart-apcie1` `0x211000000` interrupt 1532 with `manual-availability`, card-detect
and write-protect polarity 1 (active high), `gl9755-*` properties, and the five link-tunable lists of
`pci-bridge1`. All equal the K114c and K116s values. Pin 81 is taken out of the reserved range; pin
112 (SError on read) stays reserved.

**AOP sensors (#67).** AOP ASC `0x290600000`, SRAM window `0x290c00000`, interrupts 578 to 581,
`dart-aop` `0x290fc0000` interrupt 616, setup port `0x2d067c000`, and an `als` node under
`/arm-io/aop/iop-aop-nub`. The fragment leaves the audio service disabled, and the checker fails a
tree that carries an amplifier or an enabled `spkr` channel.

## Open values and what is not known

- **#30:** which pmgr register block the base's `psreg 4` maps to is upstream's step (#1856), not
  derivable from the ADT; the tree and ADT agree on `reg[46]` and both offsets. Decoding itself,
  10-bit and over 1080p are untested upstream (#1995, #1936 open). Decided: keep the omarchy-mac `mpv.conf`
  (`hwdec=vaapi-copy`) as it is; it is already `/etc/mpv/mpv.conf` here, and mpv falls back to software without
  the decoder. See [r3-avd-decode.md](r3-avd-decode.md).
- **#62:** the reader's DART stream (iommu-map `0x200` to `dart_apcie1` stream 1) is the K114c and
  J714s value; the ADT lists streams 16 to 18 and a mapper but names none for the reader. s2idle with
  a kernel-trained SD port is linux #1647 (open) and needs an `apple,k114s` line in pcie-apple; #1998
  (open, J604) powers an empty reader down. If the link does not train, boot may stall.
- **#67:** the ADT has **no `las` (lid angle) node**. The firmware announces its services at run time
  (linux #1805 reports `las` that way on J815); whether this one does is unknown until the AOP
  runs. The ADT's `als` node carries no calibration (`harmony-db-version` 3 only), and the VD6286
  starts only after a calibration (driver file `apple/aop-als-cal.bin`). Open linux #1983 (193-byte
  calibration on the 14-inch M5 Max) and #1929 (VD6286 enable sequence) are driver changes for that;
  #1876 (stop reports on suspend) and #1924 (motion sensors only while read) are open drafts too.
  Applicability judged from the PR text only, nothing was built or run: none is needed to boot the
  node; #1983 and #1929 are what could make readings appear. The ADT also has `accel` and `gyro`
  nodes (the `aop_motion` driver, not enabled here).
- **AOP risk:** it is the coprocessor the audio port also needs, started from a halted state (docs/r3-sound.md).
  Enable it once, in the same candidate as the sound Stage A (`K114S_AOP_WITH_AUDIO` with the sound
  fragment); a crash may hang boot. Speakers stay muted: no amplifier node, no `spkr` or `sense` channel.

## Tests

```
source ~/k114s-build/env.sh; DTC=$B/tools/alarm/usr/bin/dtc tests/test-parity-dtb.sh ~/k114s-build/src/base           # replica and compile
DTC=... tests/test-parity-dtb.sh ~/k114s-build/src/base --real                                                        # also reads this Mac's ADT (sudo, read-only)
```

`tests/test-parity-dtb.sh` (a kernel tree at the installed base): fragments off give r1 byte for
byte; fragments on compile and enable exactly their named nodes; `tests/lint-dtb.py` passes (the SD
tree exposes pin 81 besides 80); 16 trees with one wrong value each (interrupt, DART address, offset,
missing parent, PERST# pin, port interrupt, power index, polarity, tunable, DART interrupt, pin 112,
mailbox interrupt, enabled audio, an amplifier node) all fail the checker; a replica ADT built from
the public K116s values passes and six single-value changes to it fail (`tests/test-adt-parity-facts.py`,
no Apple data, no serial or MAC address in the output). `tests/k114s-adt-parity-facts.py GROUP=DTB...`
is the checker itself (root, read-only; `--adt FILE` for a copy of the ADT). Not run: the sound tree
combined with the SD fragment (needs this Mac's PMP file); the SD tree built with `K114S_SD_WITH_SOUND`
alone is checked for its pins.

## Needs the owner at the Mac

Not done and not doable remotely: booting any of these trees, a decode of a real video, a card in the
reader, a hand over the sensor and the lid. `tests/hardware/k114s-parity-check.sh [avd] [sd] [sensors]`
is a read-only report to run after such a boot (marked owner-at-the-mac; it changes nothing).
Booting follows the one-boot trial of docs/r3-gpu-result.md; a hang needs a forced power-off. The
candidates should be separate trials (AVD alone, SD alone, AOP with the sound Stage A), because each
adds its own way to hang.

## Upstream drafts

Comment for aurora-silicon/linux #1856 (and #1719): "K114s (Mac17,13, 27.2 26B8125) ADT checked: avd0
window, interrupts 2417/2418, dart-avd0 0x2109020000 irq 2424, pmgr reg[46], FAB1_SOC 0x1b0, AVD_SYS 0x1d8
(child of FAB1_SOC) and avd-version 4 equal the K116s values; the same for the SD reader on port 1 (PERST#
81, IRQ 1531, pcIO sd_pwr_en, dart-apcie1 0x211000000 irq 1532, polarities, five tunable lists). Not booted."
For #1805/#1983: "K114s ADT has an als node under iop-aop-nub (harmony-db-version 3) and no las node; accel
and gyro nodes exist."
