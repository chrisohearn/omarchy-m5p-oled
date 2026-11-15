# Speaker protection on the K114s: what it needs, and whether this Mac can meet it

Written 2026-11-14 on the K114s itself. Nothing here played a sound, enabled an amplifier or
changed the system. One root action was taken: this Mac's Apple device tree (ADT) was read once,
read-only, from the `adt` MTD device. Everything else is reading of installed files and public
sources. Labels: **agent-run** (a command run on this Mac today), **replica** (run on made-up
input), **read** (taken from a source, not run).

This builds on `docs/r3-sound.md` (branch `r3/sound`: headphone jack and microphones, speakers
without any path). It does not change that candidate.

## Answer

**The speakers cannot be enabled today, and nothing this Mac can produce by itself changes that.**
The machine side of a qualification is in good shape. The blocker is on the software side of both
protection stacks:

1. **speakerguardd v2** (the stack the image ships). This Mac's tuning is macOS's `AID49`. Its
   protection is an `lsm2` unit with an `LSID` companion. Upstream has not qualified LSID: none of
   its lab Macs has one, so it compiles such a tuning **muted**, and the gate refuses it with
   "protection types not at parity: lsid". Upstream's own documents name this model: "K114/K116
   (AID49/50) remain muted". There is no override; an explicit board "allow" cannot bypass it.
2. **speakersafetyd** (the older daemon, also installed and enabled). It needs a per-model profile,
   `k114.conf`. None exists that is right for this model: there is no public K116 profile, the one
   public K114 draft is for the M5 Max, unmerged, unmeasured, and does not match this Mac's
   amplifier layout, and the public tool that turns a Mac's own macOS tuning into a profile does
   not read `lsm2` tunings.

What moves it forward is upstream work that this Mac's owner can feed with silent test runs
(section "What can be done without sound"). Until one of the two stacks protects with this
model's own data, the `r3/sound` arrangement (no amplifier path at all) is the right state.

## Why the gate says "dump refused the tuning" today

agent-run, without root, the gate's documented read-only mode:

    $ /usr/lib/speakerguardd-v2/speakerguardd-gate explain --wait 0 --setting /nonexistent
    v2=0 legacy=1: k114s is unqualified: aurora-speaker-tuning dump refused the tuning (exit 1);
    no speaker card: the older daemons decide for themselves

    $ aurora-speaker-tuning dump --json
    error[load]: /lib/firmware/vendor/apple/audio-tuning: no speaker tuning bundle found

The message is about the first missing item, not the last one. The gate asks the tuning reader for
this Mac's bundle; **there is no bundle on this Mac at all**, so the reader exits 1 and the gate
reports that. The installer did not collect one: the vendor firmware manifest lists no
`apple/audio-tuning/` file. (`--setting /nonexistent` only keeps the unprivileged gate from
stopping at a root-only file first.)

Once a bundle exists, the same gate will say **"k114s is unqualified: protection types not at
parity: lsid"** instead. That is what a J813 owner's run of upstream's tester shows for the same
situation (speakerguardd issue 174), and what the installed policy code answers for the unit set
`lsid, lsm2` (replica: `gen.qualification_policy('k114s', ['lsid','lsm2'])` refuses with exactly
that text; `['lsm2']` alone passes).

## What this Mac is (its own Apple device tree)

agent-run: `sudo python3 -I tests/k114s-adt-speaker-facts.py` prints these and no payload. Every
line is this Mac's, read today; none is taken from a sibling.

| Fact | This Mac's ADT | Meaning |
| --- | --- | --- |
| `/product/audio` `acoustic-id` | 49 | macOS uses `/System/Library/Audio/Tunings/AID49` |
| `/product/audio` `speaker-thiele-small` | present, 138 bytes | the per-unit factory speaker record; this unit's own, never a sibling's |
| amplifiers | six `audio-control,sn012776` | SN012776, the J714s/K116s/J604 part |
| group order (= macOS's protection channel order) | left woofer 1 (0x38, i2c1), right woofer 1 (0x3b, i2c3), left woofer 2 (0x39, i2c1), right woofer 2 (0x3c, i2c3), left tweeter (0x3a, i2c1), right tweeter (0x3d, i2c3) | the K116s tree's order and addresses |
| `speaker-config` | six 4-byte rows: receive slot = index, one level for all six, V sense at slot 4N, I at 4N+2 | the same rows upstream published for the K116s (commit `8f5a2223fd3a` shows them); the level is the one that tree documents |
| `amp-tx-zd-config`, `bop-config`, `amp-dcblocker-config` | present (48, 24, 4 bytes) | the loader copies these to the amplifier nodes |
| `find-speaker-id`, `valid-speaker-ids` | 1; 0 and 3 | two speaker assemblies exist for this model; `/chosen/asahi,speaker-id` on this unit is 0 |
| pins | shutdown 107, fault 106, speaker ID 136 and 137 | as `docs/r3-sound.md` expected |
| `speaker-protection` | present (4 bytes) | not interpreted here |

The audio-related ADT nodes, for completeness (names only): `/arm-io/i2c1/audio-speaker` and five
`audio-speaker-<side>-<role>` nodes on `i2c1` and `i2c3`; `/arm-io/i2c2/audio-codec-output`
(`audio-control,cs42l84`, 0x4b); `/arm-io/iop-audio-controller` with `audio-speaker`
(`iop-adma-stream,mca`, data node `audio-data,sn012776`), `audio-speaker-tap`, `audio-hp-mic`,
`audio-codec-input`, `audio-codec-output`, three loopback devices and the low-power microphone
devices; `/arm-io/aop/iop-aop-nub/aop-audio` (`iop-audio,aop-service`) and `aop-voicetrigger`;
`admac-base-ns`, `admac-leap-ns`, `admac-leap-s`, `admac-hp-mic-ec-proxy`, `audio-hp-mic-proxy`;
`dp-audio0` to `dp-audio4`; `/product/audio`.

## What a K114s qualification consists of

### Route A: speakerguardd v2 (installed, `1.0.0alpha.1-41.1`, upstream branch `v2` at `04169c44`)

The installed `NEW-PLATFORM.md`, gate and `wiring.py` are byte-identical to upstream's (agent-run
`diff`). A board is "qualified" when **all** of these hold; there is no list of boards to be added
to.

| # | Item | Where it comes from | From this Mac alone? |
| --- | --- | --- | --- |
| 1 | Kernel: an `apple,k114-macaudio` entry with the speakers enabled, the "Speaker Protection" interface | a kernel patch | Yes (code). `r3/sound` has the entry with the speakers off |
| 2 | Device tree: the "Speaker" link, six amplifier nodes with `sound-name-prefix` and V/I sense slots, the shutdown regulator, the AOP `spkr` and `sense` channels | the K116s nodes, checked against this Mac's ADT | Yes. The table above is that check for the amplifiers |
| 3 | Loader: copies each amplifier's `apple,speaker-config` and the group's blocks from the ADT; publishes the speaker ID and the serial number (the unit binding) | aura `src/kboot_audio.c` | Yes. The speaker ID is already published (0) |
| 4 | Tuning bundle: this Mac's own `AID49` folder, its DSP database entry, the per-unit speaker record, the `lsm2` bucket lattice from its own macOS, and, if its presets are short, the `lsm2` parameter readback from its **running** macOS; bound to this board and this unit | `aurora-speaker-upgrade` (read-only from the macOS System volume, or Apple's restore image, or a collection made in macOS) | Yes. Reading from Linux may be enough; the readback needs one boot of macOS. Not present today |
| 5 | The bundle compiles without refusals | `aurora-speaker-tuning compile` | Probably: an LSID tuning compiles, but **muted** (`lsid-disabled`, `lsm2-release-gated`) |
| 6 | Every protection type of the tuning is in the build's `units_at_parity` | `gate.json`: `spp3`, `lsm2`, `atsp`. **Not `lsid`** | **No. Upstream work** |
| 7 | The voicing (the stages before protection) is attested for this tuning and macOS build | `parity.json` | Partly. `AID49` is attested "pass" for macOS 26.6.2 (25G83), speaker IDs 0, 3 and invalid. This Mac's macOS is 27.x; it counts only if its `AID49` speaker files equal 25G83's. Not checked |
| 8 | Self-check: the wiring derived from the device tree and the tuning, each amplifier's slots read back, and a switch test on an all-zero stream; bound to board, kernel, blob and wiring | `speakerguardd-selfcheck` on a kernel with the speaker card | **Not planned.** It powers the amplifiers and opens a stream, which is the opposite of the owner's rule. It is not "silent" for the hardware. See "The self-check is not a step" below |
| 9 | Supervisor checks at run time: the blob's channels against the record, the operating point against the amplifiers' gain readback; a 6-amplifier plugin; a known transport | installed code | Yes (replica: `wiring.py` accepts the K116s-style description for a K114 card: transport `apple,t6050-aop-audio`, plugin `6ch-vi`, V/I on sense channels 2N and 2N+1) |
| 10 | The owner hears it | | The last step, never the first |

Item 6 is the wall. What upstream says about it (read):

- `docs/NEW-PLATFORM.md`: "`lsid` is not at parity, so K114/K116 (AID49/50) remain muted. Parity is
  a property of the unit implementation in the build, never of a board. There is no board
  allowlist ... an explicit allow cannot bypass any proof."
- `docs/LSID.md`: a companion bundle "carries mandatory audible-release gates" and the unit
  "**mutes output** until those gates are closed"; "There is no switch to remove these gates";
  adaptation "cannot be enabled, including with all Cargo features".
- `tools/lsid-tester/README.md` (2026-11-13): LSID is on the J713, J813, K114 and K116. "None of
  the Aurora lab Macs has it, so speakerguardd v2 keeps those speakers muted and we can't qualify
  LSID ourselves. One run on your Mac tells us what we need."

What nobody has yet: a qualified LSID estimator (it follows each speaker's resistance and
resonance from the V/I sense while music plays). Qualifying it needs reference behaviour from
macOS on LSID Macs, which upstream is collecting from owners. That is measurement work on macOS,
not data that can be read out of this Mac.

### Route B: speakersafetyd (installed 2.0.1; `speakersafetyd.service` is enabled)

It reads `/usr/share/speakersafetyd/apple/<model>.conf`; for `apple,k114s` the name is
`k114.conf`. A profile consists of:

| # | Item | How siblings got it | For the K114s |
| --- | --- | --- | --- |
| 1 | Per-speaker thermal model: coil and magnet thermal resistance and time constant, nominal coil resistance, temperature limit and headroom | From the Mac's **own macOS tuning** with `docs/audump.py` (J604, J815 and the older models) | `audump.py` reads `spp3` and `atsp` tunings only. `AID49` is `lsm2`. The installed reader lists the `lsm2` parameters as "ID-to-name map not yet in the specification". **No public way to derive them** |
| 2 | Sense layout: which sense channel is which amplifier's voltage and current, and any sample lag between them | Derived from the device tree, then **measured** with a quiet sweep per speaker (J813 and J815 found one voltage channel a sample late) | Derivable (this Mac's rows give V on channel 2N, I on 2N+1). The order can be proven silently by v2's switch test. A lag can only be measured with a signal |
| 3 | A volume ceiling well below full scale while the model is unproven | The Aurora fork's `max_volume_db` (J813, J815: -24 dB woofers, -32 dB tweeters) | The installed 2.0.1 does not have this key (agent-run: not in the binary). Unlocked, it allows the amplifiers' full range |
| 4 | Kernel entry with the speakers enabled, a udev rule for the `AppleK114` card, a speaker device in the ALSA profile, and a speaker DSP graph (crossover and high-pass, so the tweeters never get bass) | Per model | None exists for a K114 |
| 5 | Hardware qualification: ceilings read back, relock when the daemon stops, sustained playback with thermal telemetry | J813, J815 documents | Needs sound; only after protection is active |

### How the siblings got theirs

- **K116s** (upstream #1648, Jens Axboe's machine): "speakers (with speakersafetyd)". The kernel
  side is public: the `apple,k116-macaudio` entry reuses the J714 configuration. **The
  speakersafetyd profile he ran is not public.** Neither aurora-silicon/speakersafetyd nor
  AsahiLinux's has a `k116.conf`, and a code search finds none. Could not determine what data it
  holds or how it was made. The K116s is `AID50`, an LSID model too, so under v2 it is muted like
  this Mac.
- **J714s** (the image's own model): speakerguardd v2 with each Mac's own tuning. On one owner's
  J714s "`aurora-speaker-upgrade` passed every v2 check ... `gate.json`/`parity.json` unedited"
  (betizzel/omarchy-m5 `docs/left-out.md`), "nobody has listened yet". The earlier
  `j714.conf` for speakersafetyd was removed from the image. Since the unedited gate passed, the
  J714's tuning has no LSID companion: its protection differs from this Mac's.
- **J604** (IronsideXXVI/omarchy-j604): `docs/audump.py` run on the J604's own macOS tuning
  (`AID30`, an `spp3` tuning) "prints exactly j504.conf's body", and macOS's tuning for `AID30` is
  byte-identical to the J504's. Limits are Apple's. The kernel patch series (linux #1894) adds the
  amplifier set-up and shutdown writes traced under macOS on that machine; it is about clicks and
  correct power-down, not about the protection data.
- **J815, J813** (aurora-silicon/speakersafetyd): J815's constants are the J615's because macOS
  ships one file (hard link) for the three 15-inch Airs; limits are deliberately lower than
  Apple's; the sense layout was measured. J813 is an `lsm2` Mac: "Physical parameter data was
  inspected locally", conservative limits, then measured.
- **K114c** (M5 Max, same chassis; speakerguardd pull request 178, open, not reviewed by a
  maintainer): a `k114.conf` for the older speakerguardd 0.1 daemon with "vendor profile data read
  from the owner's own machine". Its author: "We did not measure them on this Mac", "It does not
  show the thermal numbers are right". **It must not be used here.** Three things in it can be
  checked and do not fit this Mac: it gives all six speakers one thermal block, while upstream's description of the
  six-lane tuning has two speaker families (four woofers, two tweeters); it lists the speakers as
  woofer, woofer, tweeter, tweeter, woofer, woofer, while this Mac's ADT order is four woofers
  then two tweeters; and it reads voltage from the odd sense channels, while this Mac's rows put
  voltage on the even ones. Whether those match his kernel's device tree could not be determined;
  against the K116s-style tree they would apply the model to the wrong speaker and the wrong
  signal.

## Is this Mac's speaker hardware identical to a sibling's?

| Sibling | What is proven | What is not |
| --- | --- | --- |
| K116s (16-inch, `AID50`) | Same amplifier chips, addresses, order, level and sense slots (this Mac's rows equal the published K116s rows) | **Not the same speakers as far as macOS is concerned**: a different acoustic ID, and `parity.json` carries different voicing keys for `AID49` and `AID50`. Its tuning or profile is not this Mac's |
| J714s (14-inch LCD) | Same amplifier arrangement (the K116s commit says the K116s "has the J714s's audio") | Its acoustic ID was not determined. Its tuning passes the unedited v2 gate, so it has no LSID stage; this Mac's has. Not the same protection |
| J604 (14-inch M4, `AID30`) | Same amplifier part | Different SoC, different tuning family (`spp3`). Not the same |
| K114c (14-inch OLED, M5 Max) | Upstream's inventory names `AID49` "K114 MacBook Pro (M5 Pro / M5 Max)". If a K114c's ADT also says 49, macOS itself uses one tuning for both, which is the same kind of proof the J815 and J604 profiles rest on | **Assumed, not read**: no K114c ADT was seen. Even then the per-unit speaker record and the speaker ID (0 or 3) belong to each unit, and the only K114c profile is the unusable draft above |

So no sibling's data qualifies as this Mac's. The one identity that could later carry weight is
`AID49` itself: a profile or attestation made **from an `AID49` tuning** is this model's by Apple's
own key, whichever K114 it was collected on. The decision to rely on that is the lead's and the
owner's.

## What a wrong profile risks

- **Burnt voice coils.** The daemons do not measure temperature; they compute it from the signal
  and the thermal constants. Constants that are too optimistic (a coil resistance set too high, a
  thermal resistance too low, a limit too high) let the real coil run hotter than the model says.
  The tweeters go first: public profiles give tweeter coils a time constant of about 1.5 to 2.5
  seconds. The K114c draft itself notes that its resistance change "lowers the computed power by
  about 18 percent".
- **The right model on the wrong speaker.** A wrong order or swapped V/I channels makes the
  daemon protect a woofer with a tweeter's numbers, or compute power from the wrong signal. It
  still runs, and still unlocks the amplifiers.
- **No ceiling.** The installed speakersafetyd has no volume cap of its own. Once it holds the
  lock, the kernel lets the amplifiers go to 0 dB, and only the profile stands between the signal
  and the speakers.
- **Mechanical damage is not covered at all** by a thermal profile. Excursion is limited only by
  the DSP graph in front (high-pass, crossover, limiter). A graph made for another enclosure is as
  much a wrong profile as wrong thermal numbers. On macOS this is what `lsm2` and LSID do with the
  per-unit record.
- What does **not** go wrong: a daemon that dies or stalls. The kernel relocks by itself (read in
  `macaudio.c`): without a holder of the lock an SN012776's volume ceiling is the lowest step, and
  under the v2 interface no speaker stream can start. Damage comes from a protection that runs
  with wrong data, not from one that is absent.

## Three things on this image that would act by themselves

Found while reading the installed units (agent-run `systemctl cat`). None matters while the tree
has no speaker card; each matters the moment one appears.

1. **A file named `/usr/share/speakersafetyd/apple/k114.conf` is the switch for Route B.**
   `speakersafetyd.service` is enabled; the lead's drop-in holds it back only while that file is
   absent; the J714 hold in the image matches `apple,j714*` only; and on this dual-interface kernel
   the gate answers "the older daemons protect the speakers" for an unqualified board. Never
   install a `k114.conf` to try something. **The file name is not specific to this Mac**: the K114c
   (M5 Max) shares the card name `AppleK114`, upstream merged its speakers on 2026-11-11 and a
   `k114.conf` for it is open as speakerguardd PR 178, so a routine package update could supply the
   file. `linux/audio/install-audio.sh` therefore adds a second condition to `speakersafetyd`,
   `speakerguardd`, the `speakerguardd-v2*` units and `aurora-speaker-upgrade`: they run only while
   `/etc/omarchy-k114s/speaker-qualification` exists. The **owner** creates that file by hand, after
   Stage B has every proof; nothing in this repository creates it, and `speaker-readiness.sh` trips
   while it exists with proofs missing.
2. **`aurora-speaker-upgrade.service` runs at every boot with the preview acknowledgement.** Today
   it ends with "no speaker card yet". With a card that has the protection controls it will, on its
   own: read the macOS System volume (or fetch about 20 MB from Apple's restore image), store the
   bundle under `/var/lib/aurora-speaker-upgrade`, write `/etc/speakerguardd/provision.conf`, stop
   the older daemons, be refused at item 6, and go back, which stops and restarts the logged-in
   user's PipeWire. It then records the refusal and does not retry until the kernel or
   speakerguardd changes. Safe, but it should happen when the lead expects it.
3. **The first-pass barriers are what keeps the speakers silent, not the absence of a daemon.**
   Keep `tests/lint-sound-dtb.py` of `r3/sound` on every tree.

## Stage B kernel floor: what a K114s Stage B must change first

Read from `macaudio.c` (review finding, not run): with no lease the SN012776 volume ceiling is
the lowest step (`max = 1`, the safe-volume path is commented out), a lease that runs out returns
it there, and `macaudio_spk_floor` refuses playback when the floor cannot be set. That floor is the
one protection that does not depend on a daemon. Against it, the default **"Speaker Volume
Unlock"** interface is unlocked by any process that holds the element lock and writes
`SPEAKER_MAGIC_VALUE`, with no `CAP_SYS_ADMIN` check, unlike the "Speaker Protection" interface.
So any seat-user process with `/dev/snd` access could lift the ceiling with no thermal model. For
a K114s Stage B the kernel must therefore offer only the "Speaker Protection" (`CAP_SYS_ADMIN`)
interface and refuse the legacy unlock for this compatible (or gate the legacy unlock on
`capable(CAP_SYS_ADMIN)`), and `enable_speakers` stays `false` until a K114s profile exists. Not
written: patch 0004 keeps the speakers off, which is the only thing Stage A needs. The K114
entry's amplifier type and layout (`AMP_SN012776`, `SPKR_2W1T`, `spk_secondary_only`) are copied
from the J714 and unused while `enable_speakers` is false; they are an assumption, not a result.

## What can be done without sound (in order; root steps are the lead's or the owner's)

1. **Collect this Mac's own tuning, read-only, from Linux.** No card needed, nothing switched:

       sudo AURORA_LZFSE_LIB=/usr/lib/omarchy-aurora/liblzfse.so.1 \
            aurora-speaker-upgrade collect --out /root/k114s-tuning --route 1

   It reads the unencrypted macOS System volume and the ADT. Keep the result root-only and out of
   git. If it answers "collected before the installer read the lsm2 fill", boot macOS once and
   follow `aurora-speaker-upgrade guide` (aurora-installer `tools/speaker-tuning/collect-macos.sh`,
   read-only, no sudo), then `--route 3 --collection FILE`.
2. **Read it, offline.** `aurora-speaker-tuning identify`, `validate`, `dump --json` and
   `voicing-check --attestations /usr/share/speakerguardd/parity.json` on the bundle. This settles:
   that the unit is `lsm2` with an LSID companion (expected, not yet seen on this Mac), whether the
   presets need the macOS readback, and whether item 7 holds for this macOS build.
3. **Derive the wiring offline** against a candidate tree that has the speaker nodes, without
   booting it: `wiring.py describe --dtb CANDIDATE.dtb -- BUNDLE`. A refusal here is a tree or
   tuning mismatch found for free.
4. **Run upstream's LSID tester kit** (`tools/lsid-tester`, both halves, about 10 minutes) and send
   the two logs. "It is silent": zero samples on Linux, volume 0 and mute on macOS. The Linux half
   needs a kernel with the speaker card, so on this Mac it waits for the lead's decision below; the
   macOS half does not. This is the contribution that actually moves item 6, and upstream asks for
   it from exactly this model. Posting to upstream is the owner's decision.
5. **The self-check is not a step** (finding of the safety review). Earlier drafts proposed a
   "silent" self-check on a kernel and tree with the amplifier nodes. It is not silent for the
   hardware: it powers six amplifiers and opens a zero-sample stream, with no protection data for
   this model behind it, and `aurora-speaker-upgrade` would run it at every boot with the preview
   flag, collect, be refused and restart PipeWire. It is therefore **removed from the plan**. It
   may be reconsidered only as its own decision of the owner, with every one of these first:
   `aurora-speaker-upgrade` and the speakerguardd and speakersafetyd units masked for that boot
   (the guard of `install-audio.sh` already skips them, so do not create the marker), the kernel
   keeping `enable_speakers = false` so that it refuses playback, a check that only senses (no
   speaker transmit stream), and the amplifier layout of the J714 accepted as this Mac's only with
   ADT evidence (amplifier count, I2C addresses, part ID, channel map) recorded as owner-reviewed,
   with the speaker driver and the enclosure still marked as assumed. Until then items 2, 3, 8 and
   9 stay unproven on hardware, and step 4 has only its macOS half.
6. **Watch upstream** for `lsid` entering `units_at_parity`, for a merged `AID49` profile with its
   qualification document, and for what Jens Axboe's K116s runs. The first of these that carries
   this model's own data, with protection active, is the point at which the owner can listen.

## Not verified, could not determine

- The contents of this Mac's `AID49` tuning: no bundle was collected (root, outside this task).
  That it is `lsm2` with LSID rests on upstream's statements about K114/`AID49`, not on a reading
  of this Mac's files.
- Whether route 1 works on this Mac's macOS (27.x) and whether its presets need the macOS readback.
- Whether this Mac's `AID49` speaker files equal macOS 26.6.2's (item 7).
- The speakersafetyd profile used on the K116s, and the J714's acoustic ID.
- Whether a K114c's ADT says `acoustic-id` 49.
- Anything on hardware: the amplifiers were not powered, no stream was opened, nothing was heard.
- The meaning of the ADT `speaker-protection` property.

## Sources

- Installed: `/usr/share/doc/speakerguardd-v2/NEW-PLATFORM.md`, `/usr/lib/speakerguardd-v2/`
  (`speakerguardd-gate`, `wiring.py`, `gen.py`, `speakerguardd-provision`),
  `/usr/share/speakerguardd/{gate,parity}.json`, `/usr/lib/aurora-speaker-upgrade/`, the unit files
  and drop-ins, `/usr/bin/speakersafetyd` 2.0.1.
- aurora-silicon/speakerguardd branch `v2` at `04169c44`: `docs/NEW-PLATFORM.md`, `docs/LSID.md`,
  `tools/lsid-tester/README.md`, `tools/aid-inventory.py`; issue 174; pull requests 177 and 178.
- aurora-silicon/speakersafetyd `main` at `30c2027`: `docs/j813.md`, `docs/j815.md`,
  `docs/audump.py`, `conf/apple/`.
- aurora-silicon/linux: #1648 (commits `45f4de446485`, `dac02289da54`, `8f5a2223fd3a`), #1787,
  #1645, #1894; `sound/soc/apple/macaudio.c`.
- aurora-silicon/aura `src/kboot_audio.c`.
- IronsideXXVI/omarchy-j604 `speakersafetyd/patches/0002-conf-Add-J604-MacBook-Pro-14-inch-M4.patch`.
- betizzel/omarchy-m5 `README.md`, `docs/left-out.md`,
  `installer/recipes/speakerguardd-v2-upstream/README.md`.
