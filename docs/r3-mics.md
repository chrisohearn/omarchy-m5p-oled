# K114s built-in microphones: the sound trial tree (issue #38)

Status, 2026-11-17: **the built-in microphones work.** The sound tree booted as a one-boot trial, passed the
speaker gates, recorded on all three microphones, and carried the owner's dictation. It is now the configured
Stage 2. Evidence labels: **agent-run** (a command run on this Mac by the AI agent), **owner-observed**,
**replica** (made-up input). Nothing was ever played.

The owner picked the built-in microphones (#38, #39) for this round. The headphone jack (#37, #40) is out of
scope. The jack codec still comes with the reviewed Stage A fragment, since the microphones were always
planned on the same trial boot. Its issues stay open and untested here. The loudspeakers are never enabled
(docs/r3-audio.md, Stage B).

## The tree

`dts/t6050-k114s-r3b-sound.dts` is the configured Touch ID tree (`t6050-k114s-r3b-touchid.dts`, unchanged)
plus the Stage A sound fragment `dts/t6050-k114s-sound.dtsi`. That fragment turns on the PMP with this Mac's
own values, the AOP and its audio service with the three-microphone channel (`hpai`), the audio DMA and DART,
and the jack codec with its one-link card (`apple,k114-macaudio`). It adds no amplifier node, no shutdown
regulator, no Speaker link and no `spkr` or `sense` channel. Pins 106, 107, 136 and 137 stay reserved.

Both fragments replace the AP bank's `gpio-reserved-ranges`. The Touch ID fragment comes last, so it carries
the sound pins. Its two pin switches are now independent: `K114S_TOUCHID_WITH_SOUND` adds 134 and 139,
`K114S_TOUCHID_WITH_SD` adds 81. Before this change `WITH_SOUND` also exposed 81 (the SD reader's PERST#),
which a tree without the reader must keep reserved. `tests/lint-dtb.py` and `tests/lint-sound-dtb.py` both
refused that tree. The Touch ID tree defines neither switch and is byte-identical before and after.

The build needs this Mac's PMP values (`build/k114s-adt.py pmp-dtsi`, as root, from its own ADT). They are
one Mac's data and stay out of this repository. Regenerated 2026-11-17, they are byte-identical to the file
the sound kernel review used (`df27244e…`, 148 of 148 firmware properties).

| Check | Result | Label |
| --- | --- | --- |
| Control: the Touch ID tree on P's includes | `3d4580e5…`, 109,300 bytes: the pinned tree, byte for byte | agent-run |
| The sound tree on the same includes | `de9fa4b6763459015761c8c99c32f2eb9afe9f3555d345331a3d1010ef1c52c0`, 148,216 bytes, no dtc warning | agent-run |
| `tests/dtb-node-diff.py` Touch ID against sound | 5 nodes added (the jack codec, `/sound` and its link); changed: the PMP and its 148 values, its mailbox, DART and report, three PMP power states always on, the PMC voters, the AOP, its two mailboxes and DART, both audio DMA controllers, i2c2, the AOP audio node (`cout`, `cin`, `hpai`; no `spkr`, no `sense`), the AP `gpio-reserved-ranges` (134 and 139 out) and one phandle renumber | agent-run |
| `tests/lint-sound-dtb.py` | passed: exposed and named 80, 134, 138, 139; PMP with 148 firmware properties | agent-run |
| `tests/lint-dtb.py` | passed: exposed 80, 134, 138, 139 | agent-run |
| `tests/lint-display-gpu-dtb.py` | passed: display and GPU described for the hand-off, as in the Touch ID tree | agent-run |
| `sudo python3 -I tests/k114s-adt-sound-facts.py` | 69 of 69 facts hold | agent-run |
| `sudo python3 -I tests/k114s-adt-touchid-facts.py` on the sound tree | every fact holds | agent-run |
| A driver for every node the tree turns on, in the running kernel (r3b.c4) | yes: `snd-soc-macaudio` (alias `apple,k114-macaudio`), `snd-soc-t8152-aop-audio` (`apple,t6050-aop-audio`), `snd-soc-cs42l84`, `aop`, `apple-pmp`, `apple-admac`, `i2c-pasemi-platform`; the mailboxes, DARTs and the PMP report are built in | agent-run |
| `build/make-stage2.sh` with the pin loader `beceb683…` (control: Touch ID tree) | `3cc123d8…`, byte for byte the configured `m1n1/boot-ctxr.bin` | agent-run |
| The same with the sound tree | `boot-ctxr-sound.bin` `0990b168fc535073d186a1b7b6b98b2831ec39aa544ffb731950f1361d361f3a`, 4,545,458 bytes: prefix `beceb683…`, tree `de9fa4b6…`, trailer `9d8dc11e…` | agent-run |

### The lint gap this closed

`tests/lint-sound-dtb.py` counted a pin as named only through `*-gpios` or `interrupts-extended`. The Touch ID
sensor names pin 138 with `interrupt-parent` plus `interrupts`, so the sound lint called 138 "exposed but named
by no node". The same blind spot let through an interrupt on the amp fault pin 106: a tree with
`interrupt-parent = <&pinctrl_ap>; interrupts = <106 ...>;` passed the old lint (agent-run). The lint now walks
`interrupts` under an AP `interrupt-parent` (the node's own or its nearest ancestor's). `tests/test-sound.sh`
refuses that tree and passes sound plus the Touch ID fragment (62 of 62, agent-run).
`tests/test-touchid-dtb.sh` builds the sound-only and the sound-plus-SD pin variants (all passed, agent-run).

## User space (installed 2026-11-17, before the trial)

`sudo bash linux/audio/install-audio.sh` (docs/r3-audio.md, "Install"). It installs the 12 speaker-guard
drop-ins, the tree check as WirePlumber's start condition, both UCM profiles, `82-k114-audio.conf` and the
default `mic.json`. The files do nothing without the cards.

Before the install, `linux/audio/speaker-readiness.sh` reported 17 tripwires, every one a missing guard. After
the install and both daemon reloads it exits 0 ("no path to the loudspeakers exists"). `systemd-analyze
condition` on the owner's marker fails, as it must, and WirePlumber, PipeWire and pipewire-pulse stay active
(agent-run). `patches/omarchy/0004` (the K-board mic mapper and names, #39) was already applied: the mapper's
DSP pattern reads `effect_output\.[jk][0-9]+-mic` (agent-run).

## The trial (one boot, unattended with Jarvis's acknowledgement)

1. P9 (the configured boot files hold). Arm: write `m1n1/boot-ctxr-sound.bin`, read it back, then `aura-try` =
   `armed` / `m1n1/boot-ctxr-sound.bin`. The arm step refuses unless `speaker-readiness.sh` exits 0, the
   installed tree check guards WirePlumber, no owner speaker marker exists and no `k11x` speakersafetyd profile
   exists. The kernel entry stays the default (r3b.c4).
2. Reboot. A hang: hold the power button and start again. Aura's Stage 1 marked the trial spent before it ran,
   so the next boot is the configured Touch ID tree.
3. In the trial boot, before anything else: docs/r3-audio.md A0 (tree check, `/sound` compatible exactly
   `apple,k114-macaudio apple,macaudio`, `speaker-readiness.sh` exit 0) and A2 (no I2C device at 0x38 to 0x3d,
   no protection, unlock, sense or amplifier control, no speaker line in the kernel log). Then A1 (both cards),
   the kernel log against the previous boot, the codec interrupt rate, Touch ID still bound, and a 4 s raw
   capture of the quiet room. Stop conditions: docs/r3-audio.md, "Stage A stop conditions".
4. With the owner: speech and claps recorded on the raw array and on the mono source; the owner judges the
   result by ear or by dictation (no loudspeaker playback, ever).
5. If all of that holds, promote the sound tree to the configured Stage 2 (`update-boot-ctxr`), as the Touch ID
   tree was promoted.

## Results (2026-11-17)

**Trial boot.** Jarvis acknowledged the unattended one-boot trial for 04:30:00Z. The kernel started at 04:30:40Z
through `m1n1/boot-ctxr-sound.bin` (`/proc/device-tree/chosen/aurora,trial`) on r3b.c4, and `aura-try` read
`spent` afterwards (agent-run).

| Check (in the trial boot) | Result | Label |
| --- | --- | --- |
| A0: `linux/audio/tree-check`, `/sound` compatible, `speaker-readiness.sh` | "the Stage A tree: jack link only, no amplifier, no speaker channel"; exactly `apple,k114-macaudio apple,macaudio`; exit 0 | agent-run |
| A2: I2C devices at 0x38 to 0x3d; mixer controls; kernel log | none; no protection, unlock, sense or amplifier control; no speaker or amplifier line | agent-run |
| A1: the cards | `AppleK114HPAI` (aop_audio, device 0 "Microphone Array") and `AppleK114` (macaudio, device 0 "Primary") | agent-run |
| The coprocessors | "PMP firmware and endpoint ready", "PMP started", PMP report running; AOP RTKit up; both audio DMA controllers. The only new error-like line against the previous boot: the AOP's "crashlog endpoint not in the endpoint map" | agent-run |
| Touch ID, WirePlumber | sensor node present, `aurora-sep` active; WirePlumber started behind its tree check | agent-run |
| P9 | holds (then updated to the sound hashes after the promotion) | agent-run |

**The microphones.**

| Check | Result | Label |
| --- | --- | --- |
| Raw array, quiet room (`arecord -D hw:AppleK114HPAI,0`, 3 ch, 48 kHz, float) | three live channels, about -55 dBFS peak and -73 dBFS RMS, no clipping, correlation about 0.9 | agent-run |
| Raw array with the owner: quiet, counting, claps left and right (two takes) | speech peaks about -43 dBFS raw; claps up to -3.7 dBFS on channel 2, no clipping. Channel 2 reads 3 to 4 dB louder for every sound. Channel 1 is 2 to 3 dB above channel 0 for left claps; right claps show no consistent side | agent-run, owner speaking |
| Mono source `effect_output.k114-mic` (the default graph: equal mix, two gains of 8, high-pass, limiter) | quiet room -39 dBFS RMS; during dictation -20 dBFS peak, no clipping | agent-run |
| Default input | "MacBook Microphone" (`omarchy_asahi_mic`, omarchy-mac's mapper with patch 0004), both channels equal by design; records | agent-run |
| Dictation | the owner dictated with Superwhisper (cloud mode, its default input): "This is me using Superwhisper to reply to you." came out exactly | owner-observed |

**Found on the hardware.**
- The raw array cannot be recorded through PipeWire. The graph's rule (`82-k114-audio.conf`, `hide-parent = true`,
  as on the J714) takes every ordinary client's permission on the raw node away, so `pw-record --target
  alsa_input.platform-sound.RawMics` reports "target not found" and records nothing, and `wpctl` lists no source but
  the processed ones. That is the intended design: apps use the processed source. `tests/hardware/k114s-mic-trial.sh`
  now reads the PCM directly for its raw takes.
- The array layout is still unknown. One sensitivity or position difference (channel 2) and a weak left-right
  difference are not enough to steer a beamformer, so the default stays the equal mix and the beamformer stays opt-in.

**Promotion.** From the trial boot the sound tree became the pinned tree, and `update-boot-ctxr` wrote
`m1n1/boot-ctxr.bin` = `0990b168…`, the trial file byte for byte. The before-copies of the Touch ID files are in
`/var/lib/k114s-recovery/mics/promote-before/` (root-only). The ESP has 110,444,544 bytes free.

**Not tested here:** the headphone jack (out of the owner's scope, #37 and #40), suspend with the PMP and AOP
running (suspend stays masked), the beamformer.
