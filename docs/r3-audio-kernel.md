# r3 sound: review of the kernel and device-tree work (jack and microphones)

Written 2026-11-14 on the K114s, as a second worker's review of `docs/r3-sound.md`,
`dts/t6050-k114s-sound.dtsi` and `patches/linux/sound/` (branch `r3/sound`, `e40ef18`). Every
result here is **agent-run** (builds, lints, source reading, this Mac's Apple device tree read
from a copy). **No sound tree has booted on this Mac, and nothing here is working until the owner
hears it.**

## Verdict

- The kernel and device-tree work is complete and correct for the headphone jack and the
  microphones, as far as it can be checked without booting it. No change to the fragment or the
  patches is needed. The speakers have no path, as the first pass says.
- New since the first pass: this Mac's own Apple device tree (ADT) confirms every value the
  fragment took from the K116s tree, the PMP file was generated from the real ADT, and the real
  trees (not stand-ins) build and pass both lints.
- One risk is specific to this Mac and was not named before: the AOP firmware is this board's
  own image, and the driver starts a fixed set of its endpoints (see "Not proven").

## What was checked

| Check | Result |
| --- | --- |
| Fragment against the K116s tree at `integration/aurora` `0b03fe43` (commits `dac02289da54`, `f25b8eb19c92`, `7e584a680b77`, `8f5a2223fd3a`) | The jack codec, base-ns ADMAC, AOP, both mailboxes, DART, proxy ADMAC, `hpai` channel, PMP nodes and the jack link are the K116s tree's, node for node. Left out on purpose: the SDZ regulator, six amp nodes, `i2c1`/`i2c3`, the `spkr`/`sense` channels, the Speaker link, `speaker-id-gpios`, and the SEP (not sound's). Added: `apple,always-on` on the three PMP power states, which is exactly the change of #1789 (open) |
| Shared T6050 files | `t6050-die0.dtsi` is identical in the installed base and upstream. `t6050-peripherals.dtsi` differs in one unrelated `#if` |
| Audio drivers, installed base against upstream | `sound/soc/apple/*`, `cs42l84`, `tas2764`, `apple-admac`, `aop.rs`, `pmp.rs`: the only difference that matters is the card table in `macaudio.c` (base has `apple,j714-macaudio` only). #1645 (AOP endpoints, the runtime dependency #1648 names for sound on 27.2) is in the base |
| Where a model name is matched | Only `macaudio_snd_device_id[]` in `sound/soc/apple/macaudio.c`. The AOP audio driver matches the SoC (`apple,t6050-aop-audio`) and takes the microphone card's name from `apple,chassis-name`. So `apple,k114-macaudio` is needed, there and in the binding, and nowhere else. Without it the card matches the `apple,macaudio` fallback, whose front-end DAIs (`mca-pcm-N`) the AOP component does not have, so no card registers |
| Patches | `git am` of 0001-0004 on the running kernel's source: clean. `Image` and modules build (clang 23.1.3, `-j6`). `W=1` on `macaudio.o`, `mca.o`, `tas2764.o`, `cs42l84.o`, `i2c-pasemi-core.o`, `i2c-pasemi-platform.o`: no warning. Against the installed modules only `snd-soc-macaudio`, `snd-soc-tas2764` and `i2c-pasemi-core` differ (beyond the three that always differ by a build path), with the running kernel's vermagic. 0002-0004 also apply to upstream's head, where 0001 is already merged |
| This Mac's ADT | `tests/k114s-adt-sound-facts.py` (new): 69 of 69 facts hold. See below |
| PMP file | `build/k114s-adt.py pmp-dtsi` on the real ADT: board-id 20, 148 of 148 firmware properties. Compared by property with upstream's K116s file: the PMP firmware is the same build (same UUID and segment ranges); the board-id and one GPU voltage table differ. So the K116s is a tested reference for starting this PMP firmware, and this Mac's own values are still the ones to use |
| Device trees with the real PMP file | `t6050-k114s-r3-sound` and `-nomics` build both with the repository's method and through the kernel's own `make W=1 apple/<name>.dtb`, to the same bytes. `t6050-k114s-r1` built the same way gives the documented `2ea22d26...` |
| dtc warnings | One, in all three trees including r1, from the shared upstream file: `simple_bus_reg` on `/soc/pmp@284e00000` (its first `reg` is the SRAM window). None from the fragment. `dt-validate` is not available here, so the bindings were not checked |
| `tests/lint-dtb.py`, `tests/lint-sound-dtb.py` | Pass on both sound trees. AP pins exposed: 80, 134, 139 |
| Graph of the compiled tree | Every provider the enabled sound nodes point at (DART streams 0, 1, 8, 11; both mailboxes; both ADMACs; the `i2c2` power state; the three PMP power states; pins 134 and 139) is enabled. No `ti,sn012776` node, `i2c1` and `i2c3` disabled, no `pmp` alias |
| `tests/test-sound.sh` | 41 of 41 (the first pass's 40 and the new checker's self-test) |
| Sound on top of the GPU tree the Mac runs now | `t6050-k114s-r3-gpu.dts` of `r3/gpu-desktop` plus `#include "t6050-k114s-sound.dtsi"` builds (`W=1`) and passes both lints: the two fragments touch no common node. The only new dtc warnings are the GPU fragment's own (six `unit_address_vs_reg` on its reserved-memory nodes). Not booted |

## This Mac's ADT

The first pass could not read the ADT (root only) and listed its values as "not verified". They
are verified now, from a copy of the `adt` partition read as root earlier today by another
worker. To repeat it on the Mac:

    sudo python3 -I tests/k114s-adt-sound-facts.py

It prints one line per fact and no ADT data beyond the address, pin or interrupt number of a fact
that does not hold. What holds (agent-run, 2026-11-14):

- Jack: CS42L84 at 0x4b, alone on `i2c2`; reset on AP pin 139 and interrupt on AP pin 134, both on
  the 221-pin controller; `cout`/`cin` on base-ns TX2/RX2.
- AOP: ASC, SRAM window, interrupts 578-581, setup port, `dart-aop` (address, interrupt 616,
  streams, `vm-base-11`, `vm-size-11`), base-ns ADMAC (address, size, interrupt 637, 13+13
  channels).
- Microphones: three, on leap-s RX0; proxy ADMAC address, size and channel; leap-s interrupt 638.
- PMP: both register windows, the firmware property node, `pmc` and `pmc-pmgr`.
- Speakers (not enabled; recorded for the later step): six SN012776 at 0x38-0x3a on `i2c1` and
  0x3b-0x3d on `i2c3`, in the K116s group order; shutdown line on pin 107, fault interrupt on
  106, ID straps on 136 and 137; a speaker-config row per amp with the K116s tree's sense slots;
  the K116s tree's two idle masks; playback on base-ns TX0 and sense on RX0, six playback and
  twelve sense slots.

## The running system (2026-11-14, kernel K114S-R1, the GPU trial tree)

Agent-run, read-only:

- No `/sound` node, no `/proc/asound`. In the live tree the AOP (`apple,t6050-aop`), its DART and
  mailboxes, both ADMACs, the PMP, the PMP report and every I2C bus are `disabled`; `pinctrl_ap`
  is on. So nothing sound-related can probe today, and the kernel log of this boot has no line
  from `aop`, `mca`, `admac`, `macaudio`, `cs42l84` or the PMP.
- `lsmod`: `aop` and `apple_pmp` are loaded and bound to nothing. `apple_pmp` comes from
  `systemd-modules-load` in the initramfs. `aop` is blacklisted for autoload
  (`/usr/lib/modprobe.d/aurora-firmware-order.conf`) and is loaded by
  `aurora-peripheral-firmware.sh`: a K114s is neither of the two boards that script names, so it
  takes the last branch, a plain `modprobe aop`, **in the initramfs**, about one second into the
  boot, after the vendor firmware is unpacked there.
- `modinfo`: the installed `snd-soc-macaudio` knows `apple,j714-macaudio` and the
  `apple,macaudio` fallback, and neither `k114` nor `k116`. `snd-soc-t8152-aop-audio` matches
  `apple,t6050-aop-audio`, `aop` matches `apple,t6050-aop`, `apple-pmp` matches
  `apple,t6050-pmp-v2`, `snd-soc-cs42l84` and `i2c-pasemi-platform` match their nodes. All carry
  the running kernel's vermagic. So the card entry is the only driver piece missing.
- `/chosen/asahi,speaker-id` is present: the loader's audio code runs on this Mac.

What follows for installing a trial:

- The initramfs holds its own copies of `aop`, `aop_als`, `apple_pmp` and `i2c-pasemi-platform`
  with `i2c-pasemi-core` (read from the hooks in `/usr/lib/initcpio/install`, not from the image).
  With the sound tree `i2c2` is the first I2C bus this Mac enables, so the bus driver is loaded
  there. Patch 0003 therefore takes effect only once the initramfs is rebuilt; until then the old
  `i2c-pasemi-core` runs, which only changes how an unanswered address is logged.
- `snd-soc-macaudio`, `snd-soc-tas2764`, `snd-soc-cs42l84`, `snd-soc-t8152-aop-audio` and
  `apple-admac` are loaded from the root file system. Replacing `snd-soc-macaudio.ko` there is
  enough for the card (0004); no new kernel image is needed.

## Corrections to `docs/r3-sound.md`

1. "The two Macs have the same firmware build" holds for the PMP, not for the AOP. The AOP
   firmware is a board image: this Mac's ADT names one for this board, with a UUID of its own.
2. Upstream's statement on the microphones is mixed: the commit says "Not tested on the hardware
   yet", and the description of #1648 adds that the author's status of 2026-11-11 "lists the
   3-mic array as working" on the K116s. Still unproven on a K114s.
3. The AOP audio driver attaches the firmware's `spkr` service at probe on every T6050 Mac,
   whatever the tree says (`t8152_aop_audio.rs`, `probe`). It is an attach only: no power request
   follows without a speaker stream, and barrier 5 (no `spkr`/`sense` channel) is unaffected. With
   the microphone channel present the probe also puts `cout` in its standby state (`pw0`).
4. The "values to confirm" table is confirmed (above), and `build/k114s-adt.py` has now run on
   the real ADT.
5. The card still has PCM 1 ("Secondary", playback only). Nothing can open it: the driver logs
   `DMA channel "spkr" unavailable` and returns an error. A session manager that probes every PCM
   leaves that line in the kernel log. It is noise, not a path.

## What a boot of the sound tree should show

With the kernel patches (or the three rebuilt modules), the tree, and the user-space files:

- `/proc/asound/cards`: `AppleK114` ("MacBook Pro K114", driver `macaudio`) and `AppleK114HPAI`
  ("MacBook Pro K114 High-Power Audio Interface", driver `aop_audio`). With the `-nomics` tree,
  the first only.
- `AppleK114`: PCM 0 "Primary" (jack playback, headset capture) and PCM 1 "Secondary" (cannot be
  opened). No PCM 2. Controls: `Headphone Switch`, `Headset Mic Switch`, `Speaker Switch` (nothing
  behind it), `Headphone Playback Mux`, `Speaker Playback Mux`, and the codec's with the `Jack`
  prefix: `Jack DAC Playback Volume` (limited to 0 dB by the driver), `Jack ADC Preamp Capture
  Volume`, `Jack ADC PGA Capture Volume`, `Jack ADC WNF Switch`, `Jack WNF Corner Frequency`,
  `Jack ADC HPF Switch`, `Jack HPF Corner Frequency` and the codec's selects. No `Speaker Volume`,
  `Speaker Volume Unlock`, `Speaker Protection`, `Speaker Protection Interface` or `Speaker Sample
  Rate`.
- Jack detection: the jack controls `Headphone Jack` and `Headset Mic Jack`, and an input device
  for the card's "Headphone Jack" with the headset buttons.
- `AppleK114HPAI`: one capture PCM, `hw:AppleK114HPAI,0` "Microphone Array", 3 channels, 48 kHz,
  `FLOAT_LE`.
- New devices besides sound: the PMP, the AOP's lid-angle and ambient-light sensors (IIO). The lid
  angle is an IIO value only; the driver sends no lid switch event.
- No I2C device at 0x38-0x3d, no `sn012776-sdz` regulator.

## Not proven

- Anything on hardware.
- That this board's AOP firmware comes up. The driver starts endpoints 0x20-0x30
  (`AFK_ENDPOINT_COUNT` in `drivers/soc/apple/aop.rs`), the set the K116s firmware advertises. If
  this board's image advertises one more, the firmware waits for it and announces no service: no
  sound card, no sensors, as on the K116s before #1645. The sign is a line of the AOP's own log
  with "waiting for endpoint enable"; the fix is that constant, in the `aop` module.
- That the AOP comes up when it is started this early. On this image a J714s gets its
  `modprobe aop` in the root stage; a K114s gets it in the initramfs (see "The running system"),
  moments after `apple_pmp` is loaded there. The K116s tree says the audio firmware needs the PMP
  running. Whether the driver waits for it or the order matters was not determined. If the PMP
  lines of the kernel log come after the AOP's and no service appears, try `modprobe -r aop` and
  `modprobe aop` once from the running system before changing anything else.
- The PMP together with the GPU. The Mac runs the GPU tree without the PMP today. The sound
  fragment starts the PMP and gives the PMC its votes, for the whole SoC. The combined tree
  builds; what the GPU does with the PMP running is a new configuration and belongs to the same
  trial.
- The microphones (see correction 2), and the jack beyond "the codec probes" on the K116s.
- Sleep with the PMP and the AOP running. The always-on power states are #1789's answer on the
  K116s; whether suspend-to-idle still works on this Mac with them is for the sleep work to try.
- The bindings (`dt-validate`), and the K114c.

## What the speaker step would add (not done, not proposed here)

In one reviewed change, with protection data for this model:

- Device tree, as in the K116s tree: pins 106, 107, 136, 137 out of the reserved ranges; the
  `sn012776-sdz` fixed regulator on pin 107; `i2c1` with the amps at 0x38, 0x39, 0x3a and `i2c3`
  (its power state without the parent, its clock from `clkref`) with 0x3b, 0x3c, 0x3d, each
  `"ti,sn012776", "ti,tas2764"` with the SDZ supply, `apple,sdz-group-fail-closed`, the fault
  interrupt, its sense slots and `ti,bclk-ratio = <250>`; the `spkr` and `sense` channels; the
  Speaker link on DAI 3 with the two idle masks; `speaker-id-gpios`.
- Kernel: the K114 entry with the speakers admitted (patch 0004 turned around), and 0002 starts
  to matter (the amps do not answer on I2C until the shutdown line is raised).
- Loader: nothing to change. `src/kboot_audio.c` of the installed loader (aura `22b71758`) runs on
  every Apple Silicon Mac with no board check: for each ADT amp group it finds the tree's
  `ti,sn012776` nodes by I2C address and copies `apple,speaker-config` and
  `apple,amp-tx-zd-config` (one row per amp), `apple,bop-config` and
  `apple,amp-dcblocker-config` from **this Mac's** ADT, at every boot, just before the tree is
  handed over. It never stops the boot. If one amp of the group has no node, or two nodes share an
  address, the whole group is left alone, and the kernel then refuses the speakers ("the boot
  loader passed no amp levels, disabling speakers"). A property the ADT lacks is removed from the
  nodes. The same file reads the speaker-ID straps already today: `/chosen/asahi,speaker-id` is
  present on the running system, so this code has run on this Mac without refusing.
- Tests: `tests/lint-sound-dtb.py` fails such a tree by design and would have to be rewritten
  with the change.

What the ADT shows about the speaker description, and what it does not: the amps' addresses,
buses, group order, pins, sense slots, idle masks and stream shape are the K116s tree's. That is
the electrical description. It says nothing about the drivers, the enclosure, their limits or a
tuning: the K114s is a 14-inch chassis and the K116s a 16-inch one, and no sibling's protection
data is this model's. Whether protection data for this model exists is the protection work's
question, not this review's.

## The installed speaker units once `/sound` exists

Read from the installed units and gate, and the gate run as a user with a stand-in for the tuning
tool (agent-run):

- `speakerguardd-v2-provision`, `-selfcheck`, `-seat` and `speakerguardd-v2`: the gate finds no
  card with a Speaker link, waits its 15 s and exits 1 ("no speaker card"). Skipped, not failed.
  `-switchtest`: `speakerguardd-selfcheck pending` exits 1. None starts.
- `speakersafetyd`: its gate (`legacy`) exits **0** when there is no speaker card ("the older
  daemons decide for themselves"). What keeps it from starting is the lead's condition on
  `/usr/share/speakersafetyd/apple/k114.conf`. Without that condition it would start, find no
  profile, exit and be restarted in a loop; it would still have no control to take. A file of that
  name must not appear before the speaker step: it is the switch.
- `aurora-speaker-upgrade`: "not now: no speaker card yet", as today.
- So nothing unsafe: no unit starts, and the card has no speaker PCM, speaker volume or
  protection control for one to act on. The cost is time: two 15 s waits before the login
  screen, unless `linux/audio/install-audio.sh` has added its second condition.

## Suggestions for the lead

1. Run `sudo python3 -I tests/k114s-adt-sound-facts.py` once on the Mac (it should print 69 facts
   that hold), then generate the PMP file as `docs/r3-sound.md` says.
2. Boot the sound tree as a one-time trial (`aura-try`), with the `-nomics` tree as the fallback.
   If no card appears, read the PMP and AOP lines of the kernel log before anything else. Since
   the Mac now runs the GPU tree, decide first whether the trial is sound alone (the tested
   `t6050-k114s-r3-sound`, which has no GPU) or sound on the GPU tree (one more include, built
   here, not in the repository).
3. Optional hardening, not tested: `route_only_fes = BIT(1)` in the K114 entry would leave the
   card without PCM 1 at all, as the J616s jack card does for its unused front-end.
