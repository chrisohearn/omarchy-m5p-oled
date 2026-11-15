# r3: the audio user space a K114s needs (jack, microphones, and speakers later)

Written 2026-11-14 on the K114s, without root, with nothing played. It builds on
[r3-sound.md](r3-sound.md) (branch `r3/sound`), whose `linux/audio/` files it keeps and extends.
Evidence labels: **read** (source or installed file read), **agent-run** (run here, no sound
card), **emulator/replica** (a private PipeWire with no audio device). Nothing here has been heard
on this Mac.

## Summary

- User space finds a card's profiles **by name** at three layers: ALSA UCM by the card's driver
  and long name, WirePlumber and PipeWire rules by ALSA path (`hw:<card id>,<pcm>`) or card name,
  and the speaker daemons by card id in udev rules plus a per-model profile file. Nothing
  installed today matches a K114 card at any layer: every installed rule says `AppleJ...`.
- The r3 tree and kernel patch make two cards (names read in the driver source, agent-run test
  `tests/test-audio-userland.sh` step 1):

  | Card | id | driver | long name | PCMs |
  | --- | --- | --- | --- | --- |
  | jack | `AppleK114` | `macaudio` | `MacBook Pro K114` | 0 = headphones and headset mic; 1 and 2 = speaker front-ends with nothing behind them |
  | microphones | `AppleK114HPAI` | `aop_audio` | `MacBook Pro K114 High-Power Audio Interface` | 0 = three microphones, 48 kHz, float |

- **Jack and microphones now**: six files, all in `linux/audio/`, five from `r3/sound` and one rule
  block added here (pro-audio off on the jack card). List below.
- **Speakers later**: no file can be written yet. Both protection routes are blocked for this
  model today (speakerguardd v2 refuses AID49 because its LSID stage is not at parity; no
  speakersafetyd profile exists for the K114s). The list below says what each route would add
  and what each file is modelled on.
- **The installed image with a jack-and-microphone K114 card**: safe. Nothing in it opens a
  speaker PCM or touches a speaker control, provided the pro-audio rule here is installed (without
  it, WirePlumber's card probe opens PCM 1 and PCM 2 once at start-up; with the r3 tree that
  reaches no amplifier, but it is the one place user space would touch them).
- **Naming caveat for the lead**: upstream's K114c (M5 Max) tree names its card
  `MacBook Pro K114` too, with speakers enabled. Any K114c user space that appears upstream will
  match the K114s card as well. See "One name for two Macs".

## Where each layer matches a card

| Layer | Key | Read in |
| --- | --- | --- |
| ALSA UCM | `ucm2/conf.d/<driver>/<long name>.conf` | alsa-lib's confd lookup; every file in `alsa-ucm-conf-aurora` follows it (`macaudio/MacBook Pro J616 Jack.conf`, `aop_audio/MacBook Pro J616 High-Power Audio Interface.conf`) |
| WirePlumber `monitor.alsa.rules` | `api.alsa.path`, `alsa.id`/`alsa.device`, or `api.alsa.card.name` | `aurora-audio` `99-asahi.conf` (`~hw:AppleJ[0-9][0-9][0-9],1` for RawSpeakers, `...HPAI,0` for RawMics) |
| WirePlumber `node.software-dsp.rules` | `api.alsa.path` of the raw node | `99-asahi.conf`: one speaker graph and one microphone graph per J model |
| PipeWire `node.rules` | node name | `omarchy-mac` `asahi-device-names.conf` (`audio_effect.j[0-9]+-convolver`, `effect_output.j[0-9]+-mic`) |
| speakersafetyd | udev `ATTRS{id}=="AppleJxxx"` on `pcmC*D2c`, then `apple/<model>.conf` | `95-speakersafetyd.rules` (no K line), `/usr/share/speakersafetyd/apple/` (no k114) |
| speakerguardd v2 | the device tree's card with a Speaker link, the tuning bundle's board and unit ID | `speakerguardd-gate`, `gen.py`, `NEW-PLATFORM.md` |
| aurora-speaker-upgrade | any card with a control `Speaker Protection Interface`, `Speaker Protection` or `Speaker Volume Unlock` | `upgrade.py` `interface_mode()` |
| omarchy-mac helpers | `AppleJ...` cards, `effect_output.jNNN-mic` | `omarchy-audio-asahi-mic-map`, `asahi-audio-no-suspend.conf`, `audio.json` |

What exists upstream for the M5 Pro/Max generation (read, 2026-11-14):

- `aurora-silicon/alsa-ucm-conf-asahi` (`96b3206`): `macaudio/MacBook Pro J714.conf` (one card,
  jack on PCM 0, speakers on PCM 1, `laptops/HiFi.conf`). Open PR 19 adds
  `aop_audio/MacBook Pro J714 High-Power Audio Interface.conf` with a `3chan-nojack` verb (this
  driver has no lid "Internal Mic Jack" control). Nothing for K114 or K116.
- `aurora-silicon/asahi-audio` (`0f39f96`): J714 rules; the J714 speaker graph is the **J314's
  tuning** renamed (`Makefile` `aliases-j714`). Open PR 30 adds a generator that builds the
  microphone graph from the Mac's own macOS tuning, and a jack auto-switch script. Nothing for
  K114 or K116.
- `aurora-silicon/linux` `integration/aurora` (`0b03fe43`): K116s card `apple,k116-macaudio`,
  model `MacBook Pro K116`; K114c card `apple,j714-macaudio`, model `MacBook Pro K114`, speakers
  enabled (commit `215f8ed9d2`); the K114s tree there has no sound node.
- The image installs the J714 profiles from `omarchy-aurora-firmware` (`macaudio/MacBook Pro
  J714.conf`, `t8140-aop-audio/MacBook Pro J714 AOP Audio.conf`, `j714-mic.conf`). None matches
  a K114 card.

The worked example, IronsideXXVI/omarchy-j604 (M4, J604), splits the jack into a card of its own
(`MacBook Pro J604 Jack`, J616s style). The K114s, like the J714 and K116s, has one `macaudio`
card that holds the jack now and would hold the speakers later. Its pieces map as follows:

| omarchy-j604 | What it adds | K114s equivalent |
| --- | --- | --- |
| `alsa-ucm-conf-aurora` 0001 | jack and HPAI UCM names to shared verbs | `ucm2/macaudio-k114.conf`, `ucm2/aop_audio-k114-*.conf` (have) |
| `alsa-ucm-conf-aurora` 0002 | speaker UCM | later, item S1 |
| `aurora-audio` 0006 | `api.acp.disable-pro-audio` on jack cards (`~^Mac.* Jack$`) | rule added here (the K114 name does not end in " Jack") |
| `aurora-audio` 0002, 0007 | MONO processed mic; hide the mic cards | `share/mic.json` is MONO (have); hiding is cosmetic, not done |
| `aurora-audio` 0005, 0009, 0004 | speaker graph, own biquads, true-peak limiter | later, item S3 |
| `aurora-audio` 0010, `triforce-lv2` fix | beamformer steered with macOS's array geometry | later, item M1 (needs this Mac's geometry) |
| `speakersafetyd` 0002 | udev line and `apple/j604.conf` | later, item S2b |

## What the installed image does when a jack-and-microphone K114 card appears

Read in the installed files and agent-run where noted. "Opens a speaker PCM" means `hw:AppleK114,1`
or `hw:AppleK114,2`.

| Component | What it does | Opens a speaker PCM? |
| --- | --- | --- |
| WirePlumber, with UCM | uses the `HiFi` verb: Headphones and Headset on PCM 0 | no |
| WirePlumber, pro-audio probe | `acp.c` `add_pro_profile` opens every PCM of the card for playback and capture (open, hw_params, close) when the card is first seen, before any profile is chosen | **yes, once**, unless `api.acp.disable-pro-audio` is set: the rule here sets it |
| `99-asahi.conf` | matches `AppleJ...` only | no |
| `asahi-lock-volume.lua` | forces 100 % on a route named "Speaker(s)" of a HiFi profile; the K114 profile has none | no |
| `81-aurora-busy-discovery.conf` | exposes busy cards; no K114 effect | no |
| speakersafetyd | no udev line for `AppleK114`; unit also skipped by the lead's `90-k114s.conf` (no `k114.conf`) | no |
| speakerguardd 0.1 | udev line for `AppleJ700` only | no |
| speakerguardd v2 (system units) | the gate waits 15 s for a card with a Speaker link, refuses "no speaker card"; `91-k114s-no-speaker-link.conf` skips the wait | no |
| speakerguardd v2 (user units) | `-graph` and `-session` find no provisioned seat user and exit ("no speaker graph here", seen in today's journal) | no |
| aurora-speaker-upgrade | runs at boot (opt-in drop-in from `omarchy-aurora-firmware`); `interface_mode()` asks each card for the three protection controls with `amixer cget`; the K114 card has none, so it exits 2 "not now: no speaker card yet" | no |
| omarchy-mac mic mapper | looks for `AppleJ...` arrays and `effect_output.jNNN-mic` | no (the K114 mic stays mono, which is fine) |
| omarchy-audio-watchdog | restarts the stack when it hangs | no |

Conclusion: with `82-k114-audio.conf` installed, no installed user-space component opens a K114
speaker PCM or writes a speaker control. Without it, only the WirePlumber probe would, and the r3
kernel and tree give PCM 1 and 2 no speaker back-end, no amplifier node and no DMA channel
(r3-sound.md, barriers 1 to 6), so even then nothing reaches an amplifier.

**Does speakerguardd v2 replace asahi-audio's speaker graph?** On a Mac it owns, yes (read in
`gen.py` and the shipped `60-sgv2-j616.conf` / `sgv2-j616.conf`). Provisioning writes, under
`/run/speakerguardd-graph`, a WirePlumber file that disables the nodes on PCM 1 and PCM 2 of the
speaker card, so asahi-audio's software-dsp filter never gets its parent node, and a PipeWire file
that makes its own voicing sink, protect stage (`sgv2` LV2) and sense source on those PCMs. The
user unit `speakerguardd-v2-graph` links both into the seat user's `pipewire.conf.d` and
`wireplumber.conf.d`; `speakerguardd-v2-session` links the amplifiers only while the kernel grants
protection. A new board's voicing still points at "the interim asahi-audio graph for the
machine. A new board has no such graph" (`NEW-PLATFORM.md`); it is meant to be generated from the
Mac's own tuning bundle.

## (1) Jack and microphones now: files to add

All six are in `linux/audio/` and installed by `install-audio.sh` (root, the lead or the owner).

| # | Repository file | Installed as | Modelled on |
| --- | --- | --- | --- |
| J1 | `ucm2/macaudio-k114.conf` | `/usr/share/alsa/ucm2/conf.d/macaudio/MacBook Pro K114.conf` | alsa-ucm-conf-asahi `macaudio/MacBook Pro J616 Jack.conf` and omarchy-j604 `MacBook Pro J604 Jack.conf`: both include `cs42l84/HiFi-jack.conf` |
| M1a | `ucm2/aop_audio-k114-hpai.conf` | `/usr/share/alsa/ucm2/conf.d/aop_audio/MacBook Pro K114 High-Power Audio Interface.conf` | alsa-ucm-conf-asahi PR 19 `MacBook Pro J714 High-Power Audio Interface.conf` |
| M1b | `ucm2/aop_audio-k114-HiFi.conf` | `/usr/share/alsa/ucm2/conf.d/aop_audio/k114/HiFi.conf` | `aop_audio/3chan/HiFi.conf` without its `JackControl`, the same as PR 19's `3chan-nojack/HiFi.conf`; switch to that file once PR 19 is packaged |
| W1 | `wireplumber/82-k114-audio.conf` | `/etc/wireplumber/wireplumber.conf.d/` | `99-asahi.conf` RawMics rule and software-dsp rule; `j714-mic.conf` (image); **pro-audio off**: aurora-audio a67903a / omarchy-j604 0006 and speakerguardd v2 `gen.py` `wireplumber_raw_conf`; PCM 1/2 `node.disabled`: the same `gen.py` function |
| W2 | `share/mic.json` | `/usr/local/share/omarchy-k114s/audio/mic.json` | the image's `omarchy-mac/j714/mic.json` structure (equal mix of three, gain, 120 Hz high-pass, limiter); output MONO as omarchy-j604 aurora-audio 0002 |
| U1 | `systemd/91-k114s-no-speaker-link.conf` | the five `speakerguardd-v2*.service.d/` | none upstream; adds a second condition to the lead's `90-k114s.conf` |

Added in this branch: the pro-audio rule in W1 (a block of its own, matched on the card name), and
`tests/test-audio-userland.sh` (18 checks, agent-run and emulator/replica, below).

Deliberately not added:

- **A microphone beamformer.** A steered `triforce` graph needs this Mac's array geometry. The
  J604's came from its own macOS beamformer coefficients (omarchy-j604 aurora-audio 0010); the
  J314's 2 cm triangle is a different Mac. The installed `triforce-lv2` 0.3.2-1 also lacks the
  steering-phase fix (chadmed/triforce#12, open), so any look direction gives almost the same
  beam. The equal mix in W2 is the honest default. Item M1 below.
- **No-suspend for the jack sink.** `omarchy-mac`'s `asahi-audio-no-suspend.conf` keeps
  `AppleJ...` sinks open to avoid amplifier pops. Whether the CS42L84 pops on resume on this Mac
  could not be determined; add `session.suspend-timeout-seconds = 0` on
  `api.alsa.path = "hw:AppleK114,0"` only if the owner hears pops.
- **Names in the Omarchy picker.** `omarchy-mac`'s `audio.json` hides `audio_effect.j[0-9]+-mic`;
  the K114 capture stream `audio_effect.k114-mic` may show in the device list. Cosmetic.
- **Jack auto-switch.** With no speakers the jack is the only sink. asahi-audio PR 30's
  `asahi-jack-switch.lua` becomes relevant with speakers.

## (2) Speakers later: files that would have to be added

None may be written or installed before protection data that is right for this Mac exists.
Every item says what blocks it.

**Blocker today, either route** (read; details in the audio-protection worker's report):

- speakerguardd v2 route: this Mac's acoustic ID is 49 (AID49, "K114 MacBook Pro (M5 Pro / M5
  Max)" in speakerguardd v2 `tools/aid-inventory.py`). Its protection has an LSID stage; `lsid`
  is not in `units_at_parity`, and `NEW-PLATFORM.md` says "K114/K116 (AID49/50) remain muted". No
  override admits it. The tuning bundle must also come from this Mac's own macOS
  (aurora-speaker-upgrade), and there is none on this Mac today.
- speakersafetyd route: there is no profile for the K114s. speakerguardd PR 178 (open) adds
  `conf/apple/k114.conf` for the K114c (M5 Max), from that owner's vendor data, unmeasured, on top
  of PR 177 (16-bit sense format). It is a sibling's data; see "One name for two Macs".

| # | File | Route | Modelled on |
| --- | --- | --- | --- |
| S1 | `ucm2/macaudio-k114.conf` replaced: `Define.JackCodec "cs42l84"`, `PlaybackChannels "6"`, `JackDevice "0"`, `SpeakerDevice "1"`, `SpeakerElem` = the first woofer's volume control as the K114 amp prefixes name it, `File laptops/HiFi.conf` (the version with speakerguardd v2's condition, alsa-ucm-conf-asahi 4805553 / #13; the image carries it as `omarchy-j714/HiFi.conf`), or `HiFi-aop.conf` once PR 19 lands | both | alsa-ucm-conf-asahi `macaudio/MacBook Pro J714.conf`; omarchy-j604 `alsa-ucm-conf-aurora` 0002 |
| S2a | nothing static: speakerguardd-provision generates the PipeWire graph (`sgv2-k114`-style voicing sink, protect stage, sense source) and the WirePlumber file at run time from this Mac's bundle; aurora-speaker-upgrade collects the bundle | v2 | `/usr/share/speakerguardd/pipewire/sgv2-j616.conf`, `wireplumber/60-sgv2-j616.conf` (generated by `gen.py` from a fixture) |
| S2b | `/usr/share/speakersafetyd/apple/k114.conf` with this Mac's thermal and electrical constants and its own channel order (ADT group order LW1 RW1 LW2 RW2 LT RT), and in `95-speakersafetyd.rules`: `KERNEL=="pcmC*D2c", ATTRS{id}=="AppleK114", ENV{ACP_IGNORE}="1"` plus the `SYSTEMD_WANTS="speakersafetyd.service"` line | legacy | speakersafetyd `conf/apple/j414.conf`; omarchy-j604 `speakersafetyd` 0002 (`j604.conf` and its udev line); PR 177 for the sense format |
| S3 | a speaker DSP graph for `hw:AppleK114,1` (filter-chain JSON, FIR or biquads) and, in W1, the `RawSpeakers` rename for PCM 1 and its software-dsp rule; the `node.disabled` lines for PCM 1 come out for the legacy route only (v2 keeps its own) | legacy (v2 generates its voicing) | asahi-audio `firs/j314/graph.json` structure; omarchy-j604 aurora-audio 0005, 0009 (own biquads fitted to a measurement of this Mac), 0004 (true-peak limiter). **Not** asahi-audio's J714 alias of the J314 FIRs |
| S4 | W1: `session.suspend-timeout-seconds = 0` on `hw:AppleK114,[01]` sinks; `asahi-device-names`-style names for the K114 nodes | both | omarchy-mac `asahi-audio-no-suspend.conf`, `asahi-device-names.conf` |
| S5 | jack auto-switch | both | asahi-audio PR 30 `asahi-jack-switch.lua` |
| S6 | removal of `91-k114s-no-speaker-link.conf` and of the lead's `90-k114s.conf` drop-ins | both | none |
| M1 | a beamformer `mic.json` with this Mac's geometry, or a graph from asahi-audio PR 30's `mic-from-tuning` run on this Mac's bundle | mic, no speaker risk | omarchy-j604 aurora-audio 0010 + triforce#12 |

All of S1 to S6 belong in the one reviewed step r3-sound.md describes (amp nodes, shutdown
regulator, Speaker link, DMA channels, driver entry), together, never one at a time.

## One name for two Macs

Upstream's K114c (M5 Max) tree (`integration/aurora`, commit `215f8ed9d2`) and the r3 K114s tree
give the card the same model, `MacBook Pro K114`, so the same ids `AppleK114` and `AppleK114HPAI`.
The chassis is the same (`apple,chassis-name = "K114"` in both). Consequences:

- The jack and microphone files here would serve a K114c as well, and a K114c jack profile from
  upstream would serve the K114s. A K114c speaker profile (S1 form) is harmless on today's
  K114s card: `laptops/HiFi.conf` offers the Speaker device only when `SpeakerElem` exists, and
  no amp controls exist on this card.
- **Speaker data keyed by that name would apply to the K114s too.** A future package that ships
  the K114c's `apple/k114.conf` and an `AppleK114` udev line (PR 178's route) would make the
  lead's `90-k114s.conf` condition true and start speakersafetyd with the K114c's constants on
  this Mac. With today's r3 tree there is no sense PCM back-end and no amplifier, so nothing
  reaches a speaker; once the speakers are enabled, it would be a sibling's data used as this
  model's. speakerguardd v2 is not affected in the same way: it binds the tuning to this Mac's
  board and unit ID, not to the card name.

What is shown and what is assumed about K114s vs K114c speaker hardware:

- Shown (read): both are AID49 in speakerguardd v2's inventory ("K114 MacBook Pro (M5 Pro / M5
  Max)"); both trees use six SN012776 on I2C1 and I2C3 with J714 wiring; the K114c commit says
  the amps "share the J714s wiring, per the K114c device tree". The audio-protection worker found
  this Mac's `speaker-config` rows equal to those upstream published for the K116s.
- Not shown: that the drivers, enclosures and thermal constants are the same part, that PR
  178's channel order and V/I channel assignment match this Mac's ADT (the audio-protection
  worker found they do not), and that the K114c's vendor numbers hold for the K114s. An equal
  acoustic ID is a strong hint, not proof.

The decision whether any K114c data may serve this Mac is the lead's and the owner's. Options
for the lead: keep the shared name (upstream's convention: model = chassis) and add a guard so
that no speakersafetyd profile starts on a K114s unless the repository installed it (for example
a condition on a file only `install-audio.sh` writes, in place of the `k114.conf` existence
test); or give the K114s tree a model of its own. The first keeps user space compatible with
upstream; the second needs every K114s file renamed.

## Tests (agent-run and emulator/replica, 2026-11-14)

`bash tests/test-audio-userland.sh` (no root; set `TMPDIR` to a short path): 18 of 18.

1. Names: the model, chassis and kind in `dts/t6050-k114s-sound.dtsi` give `AppleK114`,
   `AppleK114HPAI` and the long name the UCM files are installed under; the compatible is patch
   0004's.
2. WirePlumber rules parsed with `spa-json-dump`: pro-audio off on exactly the card named
   `MacBook Pro K114`; PCM 1 and 2 disabled by path and by card id; one filter only, on the
   microphone array.
3. No user-space file names a speaker node, graph, plugin, control or daemon; no udev rule and no
   `k114.conf` is shipped.
4. The microphone graph loads in a private PipeWire daemon (own runtime directory, no ALSA, no
   session sockets) and makes exactly the mono source and its capture stream; a copy with a wrong
   port name is refused.
5. Notes on the installed image (never failures).

Also run: `tests/test-sound.sh` against the base tree (dtc 1.8.1): 40 of 40, unchanged.

## Not verified

- Anything with a real K114 card: that WirePlumber picks the UCM profiles, that the jack plays and
  detects a plug, that the microphones record at a usable level.
- That `alsa.udev.expose-busy` and the pro-audio rule interact as read (source only).
- Whether the K114c ships user space under the shared name: none found upstream on 2026-11-14.
- This Mac's microphone geometry, and whether a tuning bundle could be read from its macOS.
