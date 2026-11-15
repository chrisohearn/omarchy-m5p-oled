# r3 candidate: sound on the K114s (headphone jack and microphones, no speakers)

Written 2026-11-14 on the K114s itself, without root. **Nothing here has run on this Mac.** It was
built, linted and unit-tested (agent-run, emulator/replica); the first hardware test is the
owner's boot of a tree that includes it.

## Summary

- The K114s sound hardware is described like the K116s's: the AOP coprocessor runs the audio
  streams, a CS42L84 codec on I2C bus 2 is the headphone jack, three microphones come in through
  the AOP's own card, and six SN012776 amplifiers on I2C buses 1 and 3 drive the speakers.
- This candidate turns on the jack and the microphones and leaves the speakers with no path at
  all. There is no protection data for this model, so the speakers stay out until there is.
- The jack needs four things together: a kernel with one small patch (the `apple,k114-macaudio`
  card), the device-tree fragment, **this Mac's own PMP values** (read from its Apple device tree,
  as root, on Linux), and two ALSA profiles.
- Upstream's microphone commit says "Not tested on the hardware yet" (K116s). The same holds here.
  A second tree variant builds the jack alone.
- The jack itself is thinly tested upstream on this kernel line. For the K116s, pull request 1648
  reports "speakers (with speakersafetyd), jack codec probes". For the J714s on the same kernel,
  betizzel/omarchy-m5's table says of the jack and microphones "cards show up, untested". No source
  read for this work reports sound heard through the jack of a T6050 Mac on this kernel. Expect to
  be the first to try.

## What is in the branch

| Path | What |
| --- | --- |
| `patches/linux/sound/` | four kernel patches and their provenance (`README.md` there) |
| `dts/t6050-k114s-sound.dtsi` | the K114s sound nodes; include after `t6050-k114s-common.dtsi` |
| `dts/t6050-k114s-r3-sound.dts` | r1 + sound, for building and testing the fragment |
| `dts/t6050-k114s-r3-sound-nomics.dts` | r1 + jack only (`K114S_SOUND_NO_MICS`) |
| `build/k114s-adt.py` | reads this Mac's Apple device tree on Linux (root); writes the PMP file |
| `linux/audio/` | ALSA UCM profiles, WirePlumber rules, the microphone filter, unit conditions, installer |
| `tests/lint-sound-dtb.py` | the speaker-safety lint for a compiled tree |
| `tests/test-sound.sh` | all software tests for this candidate (40 checks) |
| `tests/lint-dtb.py` | one line changed: with the jack codec, AP pins 134 and 139 are expected next to 80 |

## How the pieces fit

1. **AOP.** `aop`, its mailbox, setup mailbox and DART are in the shared T6050 files, disabled. The
   fragment enables them. The driver `apple,t6050-aop-audio` (module `snd-soc-t8152-aop-audio`,
   already in the installed kernel) offers the jack as DAI 0. It matches the SoC, not the model.
2. **PMP.** The AOP's audio firmware does not come up without the PMP: on the K116s "the audio
   controller never reaches systemReady and no AOP service is announced". The fragment enables
   the PMP, its DART, mailbox and report, links the PMC to it, and keeps its three power states
   always on (the device-tree change of aurora-silicon/linux #1789, so suspend does not gate them
   under the running firmware).
3. **Jack codec.** `cirrus,cs42l84` at 0x4b on `i2c2`, reset on AP pin 139, interrupt on pin 134.
4. **Card.** `/sound` is `"apple,k114-macaudio", "apple,macaudio"`, model `MacBook Pro K114`, with
   one link, "Headphone Jack". ALSA will show it as card `AppleK114`.
5. **Microphones.** The proxy ADMAC is enabled and the AOP audio node gets the `hpai` channel plus
   `apple,chassis-name = "K114"`. The driver then creates a second card, `AppleK114HPAI`
   ("MacBook Pro K114 High-Power Audio Interface"), with one 3-channel 48 kHz capture PCM.

The only place the kernel matches on the model is the card table in `sound/soc/apple/macaudio.c`.
Patch 0004 adds the K114 entry: J714's jack configuration with `enable_speakers = false`, the same
arrangement the driver already has for J873 and J604.

## Why no signal can reach the speakers

Each line is independent of the others. "Checked" says how; none is a hardware observation.

| # | Barrier | Checked |
| --- | --- | --- |
| 1 | No amplifier node. `i2c1` and `i2c3` (the two amp buses) stay disabled, so the amp driver never binds, the buses are not registered, and nothing in Linux, user space included, can write to an amp. After a reset the amp is in software shutdown (the driver's register default for its power control is 0x1a) and plays only once it has been written over I2C. | `tests/lint-sound-dtb.py`; the lint fails on a tree with an amp node, and on one with an amp bus enabled |
| 2 | The amps' shared shutdown line (AP pin 107) and fault line (106) stay inside `gpio-reserved-ranges`, and no regulator or node names them. gpiolib refuses a reserved pin to every requester. The line stays as the boot firmware left it. | lint; fails with pin 107 exposed, and with a regulator on it |
| 3 | The card has no "Speaker" link, so no PCM is routed to the AOP's speaker back-end (DAI 3). | lint; fails with a Speaker link |
| 4 | The driver refuses a "Speaker" link for `apple,k114-macaudio` even if a tree adds one, and does not create the speaker volume and protection controls. | KUnit `apple-speaker-admission` under QEMU; the case fails when the entry is flipped to enabled |
| 5 | The AOP audio node has no `spkr` and no `sense` DMA channel. The driver requests a channel by name when a PCM is opened, so the speaker stream cannot be opened at all. | lint; fails with the channels present |
| 6 | The loader copies `apple,speaker-config` (the amp levels) only into `ti,sn012776` nodes. With none, it logs "group left alone" and continues. The driver refuses SN012776 speakers without levels. | read in aura `src/kboot_audio.c` at `22b71758` ("Nothing here stops the boot") |
| 7 | User space: the UCM profile has the jack only; WirePlumber is told not to make nodes for PCM 1 and 2 of the card; speakersafetyd and speakerguardd v2 do not start (next section) and would find no speaker control to unlock. | `alsaucm` parse; the installed gate code run on the compiled tree |

What this does not rest on: any daemon running, any volume limit, or the state of the amps.

Two statements here are expectations, not checks:

- The shutdown line is low after boot. On the K116s the amps do not answer on I2C until Linux
  raises that line (aurora-silicon/linux #1787), and the two Macs have the same firmware build and
  the same audio nodes. It has not been measured on a K114s, and nothing above depends on it.
- The AOP firmware does not start the speaker stream by itself. In the driver that stream is
  powered and run only when a speaker PCM starts.

A control named "Speaker Switch" still shows on the card (the driver registers it on every
model). There is nothing behind it.

**To admit the speakers later**, all of this has to change in one reviewed step, and only with
protection data for this model: a `speakersafetyd` profile or a qualified speakerguardd tuning,
then the amp nodes, the shutdown regulator, the link, the channels and the driver entry. The lint
is there to make a partial change fail.

## The boot-time speaker units and the new `/sound` node

Read from the installed units and `/usr/lib/speakerguardd-v2/speakerguardd-gate` (agent-run):

- Five units (`speakerguardd-v2`, `-provision`, `-selfcheck`, `-seat`, `-switchtest`) carry the
  drop-in `90-k114s.conf` with `ConditionPathExists=/proc/device-tree/sound`. Today they are
  skipped. With this tree the condition holds, so each runs its `ExecCondition`: the gate for
  four of them, and `speakerguardd-selfcheck pending` for `-switchtest`.
- The gate looks for a sound card whose device-tree node has a "Speaker" link. This tree has none,
  so in each of the four it waits its 15 s for one and exits 1: "no speaker card". The self-check
  never runs, so it defers no switch test, and `pending` exits 1 as well. None of the five starts.
  Run against the compiled tree, the gate's own reader refuses with "0 apple,macaudio cards with a
  speaker link in the device tree (want 1)".
- That is **safe**: nothing is started, and there is no speaker control on the card to take.
  It is **slow**: `-provision` and `-selfcheck` are ordered before `systemd-user-sessions`, so the
  login screen comes about 30 s later.
- `speakersafetyd.service` stays skipped by its own drop-in
  (`ConditionPathExists=/usr/share/speakersafetyd/apple/k114.conf`; the file does not exist).
- `aurora-speaker-upgrade.service` already runs at every boot and ends with "not now: no speaker
  card yet" (journal of 2026-11-14). It looks for a card with a speaker protection control. The
  K114 card has none, so the result stays the same.

`linux/audio/install-audio.sh` adds a second condition to the five units,
`ConditionPathExists=/proc/device-tree/sound/dai-link@1`, which is false while the card has only
the jack link. That removes the wait. It adds to `90-k114s.conf` and replaces nothing.

## User space

`pacman -Ql` on the installed image: the J714 profiles come from `omarchy-aurora-firmware`
(`macaudio/MacBook Pro J714.conf`, `omarchy-j714/HiFi.conf`, `j714-mic.conf`, `j714/mic.json`);
the generic verbs from `alsa-ucm-conf-aurora`; the J-model WirePlumber rules from `aurora-audio`.
`aurora-speaker-upgrade` holds no profiles. Nothing installed matches a K114 card: the rules in
`99-asahi.conf` match `AppleJ...` only.

`linux/audio/` adds:

| File | Installed as | Purpose |
| --- | --- | --- |
| `ucm2/macaudio-k114.conf` | `/usr/share/alsa/ucm2/conf.d/macaudio/MacBook Pro K114.conf` | card `AppleK114`: Headphones and Headset on PCM 0, through `cs42l84/HiFi-jack.conf` of `alsa-ucm-conf-aurora` (the J616s jack-only verb; its control names match this kernel's codec driver) |
| `ucm2/aop_audio-k114-hpai.conf`, `ucm2/aop_audio-k114-HiFi.conf` | `/usr/share/alsa/ucm2/conf.d/aop_audio/MacBook Pro K114 High-Power Audio Interface.conf`, `.../aop_audio/k114/HiFi.conf` | card `AppleK114HPAI`: a 3-channel "Mic" device. No lid jack control: this kernel's driver has none on this card |
| `wireplumber/82-k114-audio.conf` | `/etc/wireplumber/wireplumber.conf.d/` | names the raw array `RawMics`, puts a mono source on it, disables nodes on the jack card's PCM 1 and 2 |
| `share/mic.json` | `/usr/local/share/omarchy-k114s/audio/` | the mono source: equal mix of the three microphones, 36 dB gain, 120 Hz high-pass, limiter. Same structure as the image's J714 graph; the gains are starting values, not measured on a K114s |
| `systemd/91-k114s-no-speaker-link.conf` | the five `speakerguardd-v2*.service.d/` folders | the condition above |

Install and undo (root; the lead or the owner):

    sudo bash linux/audio/install-audio.sh
    sudo bash linux/audio/install-audio.sh --undo
    bash linux/audio/install-audio.sh --check

It refuses any Mac that is not `apple,k114s`, keeps an existing file of the same name as
`*.k114s-orig`, installs no package and touches no boot file. The profiles are inert until the
cards exist, so they can be installed before the first sound boot.

## Values that come from this Mac's Apple device tree

The running `/proc/device-tree` is our Linux tree, so it cannot confirm anything about the
hardware description. The Apple device tree (ADT) can, and it does not need macOS: the boot chain
keeps the ADT iBoot handed over and exposes it as the MTD partition `adt` (`/proc/mtd`, 770048
bytes on this boot). Its device node is root-only, so none of the values below could be read in
this session.

    sudo python3 -I build/k114s-adt.py sound-report            # the nodes below, for comparison
    sudo python3 -I build/k114s-adt.py show audio-codec-output  # one node

The output is this Mac's Apple data. Read it; do not commit it.

**Required before any sound build: the PMP file.** The K116s and J714s files differ in the DRAM
vendor (1 and 255), the GPU voltage table, the firmware segment ranges and the firmware UUID.
None of these is taken from a sibling. The fragment includes `t6050-k114s-pmp-tunables.dtsi` and
does not compile without it:

    sudo python3 -I build/k114s-adt.py pmp-dtsi \
        --names-from KTREE/arch/arm64/boot/dts/apple/t6050-j714s-pmp-tunables.dtsi \
        -o KTREE/arch/arm64/boot/dts/apple/t6050-k114s-pmp-tunables.dtsi

It writes `apple,board-id`, `apple,dram-vendor-id` (`/chosen`), `apple,pmc`, `apple,pmc-pmgr`
(`/arm-io/pmgr`) and the 148 firmware properties upstream's file has, from
`/arm-io/pmp0/iop-pmp0-nub`. It refuses an ADT whose board-id is not 0x14 and reports any listed
property this ADT lacks. Whether the generated file may live in this public repository is the
lead's decision; upstream publishes the same kind of file for its boards, but it is one Mac's
data, and the default here is to keep it as a build input outside the repository, like the
firmware. The display and GPU work needs the same file.

**To compare** (the fragment's comments carry the K116s tree's values; the K114s ADT has to show
the same):

| Value in the fragment | ADT node and property (as the K116s tree names them) |
| --- | --- |
| jack codec at 0x4b on i2c2 | `/arm-io/i2c2/audio-codec-output` `reg` |
| codec reset = AP pin 139, active high | same node, `function-reset` GPIO(0x8b, 0x1) |
| codec interrupt = AP pin 134 | same node, interrupt |
| base-ns ADMAC 0x293800000, IRQ 637, dart-aop stream 8 | `admac-base-ns` |
| proxy ADMAC 0x2d3200000 + 0x34000, IRQ 638, dart-aop stream 11, vm-base 0x10040000000 | `admac-hp-mic-ec-proxy`, `admac-leap-s`, `dart-aop` |
| three microphones, 48 kHz | `audio-hp-mic` |
| AOP 0x290c00000, ASC 0x290600000, IRQs 578-581; setup port 0x2d067c000 | `aop`, `aop-exclave-mailbox` |
| jack on base-ns TX2/RX2 | `iop-audio-controller` |
| PMC 1, PMC-PMGR 63 | `/arm-io/pmgr` `pmc`, `pmc-pmgr` (the tool reads them) |
| amp shutdown = AP pin 107, fault = 106, speaker ID = 136/137 (must stay reserved) | `audio-speaker` `function-reset`, interrupt, `function-speaker-id0/1` |

The repository's earlier review found the 27.2 ADTs of the K114s and the K116s "identical node for
node", which is why a mismatch is not expected. This table is the check of that for sound.

Read from the running tree without root: `/chosen/asahi,speaker-id` is 0 (the loader's reading of
the speaker-ID straps). It is not used here.

## Building it into a candidate (for the lead)

1. Kernel: `git am patches/linux/sound/000*.patch` on the base. A base that already has #1648
   drops 0001. All patched code is modular in the installed configuration, so a module-only
   delivery (`snd-soc-macaudio.ko`, `i2c-pasemi-core.ko` under `updates/`) is possible if the
   modules are built from the exact source and configuration of the running kernel.
2. PMP file: the `pmp-dtsi` command above, as root on this Mac.
3. Device tree: copy `dts/t6050-k114s-sound.dtsi` next to the other K114s files and include it
   after the common file. It sets `gpio-reserved-ranges` of the AP pin controller for pins 80,
   134 and 139. **A fragment included later that sets the property again must list these pins
   too**, and must keep 106, 107, 136 and 137 reserved. Enabling `aop`, `pmp0` and the PMP power
   states a second time in another fragment is harmless. Do not add a `pmp` alias: the loader's
   `dt_set_pmp()` then looks for an ADT path this SoC does not have and stops the boot.
4. Lint every tree that includes the fragment:
   `python3 tests/lint-sound-dtb.py TREE.dtb` and `python3 tests/lint-dtb.py TREE.dtb`.
5. User space: `sudo bash linux/audio/install-audio.sh`.
6. Software tests, all of them:

       DTC=/path/to/dtc CPP=cpp bash tests/test-sound.sh KTREE

The loader does not need a change for sound.

## What else changes when this is on

- **The PMP runs.** That is the largest change in the fragment: the PMC then honours the PMP's
  votes next to the CLPC (`apple,static-voters = <0 1 3>`). It is the K116s and J714s
  arrangement, with this Mac's values. The display and GPU candidates need the PMP as well.
- **The AOP runs.** Its other services start too: the lid-angle sensor and the ambient-light
  sensor appear as IIO devices. The light sensor loads `apple/aop-als-cal.bin`. A file of that
  name is installed (193 bytes, owned by no package, dated like the trackpad firmware the installer
  extracted). Whether it holds this Mac's calibration was not checked; the rule against a
  sibling's calibration applies to it, and the ambient-light row should settle it.
- **I2C errors read differently** on every bus (patch 0003): an absent device is a NACK.
- **Suspend.** Not changed here. The always-on PMP power states are what #1789 found necessary
  on the K116s once the PMP runs.

## Hardware test (owner), once a tree with this boots

Nothing below is expected to make the built-in speakers produce any sound. If they do, at any
point, shut down and report it.

1. `cat /proc/asound/cards` shows `AppleK114` and `AppleK114HPAI`.
2. `journalctl -k -b | grep -iE 'macaudio|aop|pmp|cs42l84|admac'` has no error. If no AOP service
   appears, look at the PMP lines first. The modules `aop` and `apple_pmp` are already loaded at
   boot on this image (seen in `lsmod` today, with their nodes still disabled), so no `modprobe`
   step is expected; `lsmod | grep -E 'aop|pmp|macaudio|cs42l84'` shows whether the rest followed.
3. `ls /sys/bus/i2c/devices` shows no device at 0x38 to 0x3d; `amixer -c AppleK114 controls` shows
   no "Speaker Volume" and no "Speaker Protection" control.
4. Headphones: plug in, set a low volume (`wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.2`), play
   something. Unplug: output stops, the speakers stay silent.
5. Headset microphone, if the headphones have one: record from "Headset Microphone".
6. Built-in microphones: record from "MacBook Microphone (Mono)". If it is silent, clipped or
   noisy, try the raw device: `arecord -D hw:AppleK114HPAI,0 -c 3 -r 48000 -f FLOAT_LE -d 3 t.wav`.
7. Login is not delayed by about 30 s (the unit condition is installed).

If the microphone card breaks the boot or the jack, use the `-nomics` tree. If the PMP or the AOP
does, `rollback stage2` returns to the tree without sound; the kernel patches and the user-space
files are inert without the `/sound` node.

## Tests run (agent-run, 2026-11-14, on this Mac as an unprivileged user)

- `tests/test-sound.sh` against the base tree with dtc 1.8.1 and gcc's preprocessor: 40 of 40.
  It covers the ADT reader on a made-up ADT (9), compile and lint of both trees (4), a build that
  must fail without the PMP file (1), ten unsafe trees the lint must refuse (10), the UCM
  profiles through `alsaucm` (4), the installer in a fake root (10), and the installed
  speakerguardd v2 reader on the compiled tree (2).
- Kernel: series applies with `git am`; `W=1` builds of the four touched objects with clang
  23.1.3, no warnings; KUnit `apple-speaker-*` 59 of 59 under QEMU 11.1.3 (arm64 `virt`);
  mutation check of the K114 assertion.
- The jack codec node and the jack link are byte-identical to the K116s tree at
  `integration/aurora` `0b03fe43`. The compiled sound tree differs from the r1 tree only in the
  nodes listed under "How the pieces fit".

## Not verified

- Anything on hardware: that the AOP and PMP start on a K114s, that the jack plays and detects a
  plug, that the microphones record, that the speakers stay silent in practice.
- Every ADT value in the table above, and that the `adt` partition holds the complete ADT with
  `iop-pmp0-nub` (root-only; the tool was tested on a made-up ADT only).
- The PMP with this Mac's values: none were read, so no real PMP file was built.
- The microphone path anywhere: upstream has not tested it on the K116s either.
- The microphone gains in `mic.json`, and the behaviour of WirePlumber and the UCM profiles with
  the real cards (parsed only).
- The device tree against the dt-schema bindings (no `dt-validate` here).
- The state of the amp shutdown line after boot on this Mac.
- That the K114c shares this card; patch 0004 names the chassis, and only the K114s was looked at.

## Upstream

Candidates once the jack has played on this Mac: the `apple,k114-macaudio` entry (patch 0004) and
the K114s sound nodes, to aurora-silicon/linux, as hardware-tested for the jack and with the
speakers deliberately off. The lead owns the registry.
