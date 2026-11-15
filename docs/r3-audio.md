# r3 audio on the K114s: the staged work item

Branch `r3/audio-full`, written 2026-11-14 on the K114s (MacBook Pro 14-inch OLED, M5 Pro).
**Nothing here is working until the owner hears it on this Mac.** No sound has been played and no
amplifier has been powered by anything in this work.

Evidence labels used below: **owner-observed** (nobody has yet), **agent-run** (a command run on
this Mac, with a tree built from this branch), **replica** (run on made-up or private input, no
hardware), **read** (taken from a source, not run).

This document sits on top of three earlier ones, which stay as the detail:

| Document | What it holds |
| --- | --- |
| `docs/r3-sound.md` | the first pass: device-tree fragment, kernel patches, the speaker barriers |
| `docs/r3-audio-kernel.md` | an independent review of that kernel and device-tree work, with the ADT facts |
| `docs/r3-audio-protection.md` | what speaker protection needs for this model, and why it cannot be had today |

## The two stages

| Stage | Hardware | State |
| --- | --- | --- |
| **A** | headphone jack, built-in microphones | complete as a candidate; waits for the first boot with sound |
| **B** | the six loudspeaker amplifiers | **blocked, and nothing is enabled.** The missing piece is not on this Mac |

The speakers have no path in Stage A, and Stage B does not add one. A Mac whose owner follows this
document never plays a sound on its loudspeakers.

## Stage A: jack and microphones

### What it changes

Kernel side (unchanged by this branch; reviewed by `docs/r3-audio-kernel.md`, found correct):

- `dts/t6050-k114s-sound.dtsi` with `t6050-k114s-r3-sound.dts` and the `-nomics` variant: turns on the
  PMP, the AOP, the audio DMA and DART, the jack codec and its card link, and the three-microphone
  channel. It has no amplifier node, no shutdown regulator, no Speaker link and no `spkr` or
  `sense` channel. Pins 106, 107, 136 and 137 stay in `gpio-reserved-ranges`.
- `patches/linux/sound/0001` to `0004`: the card-table entry `apple,k114-macaudio` with
  `enable_speakers = false` (the driver then refuses any Speaker link whatever the tree says), plus
  two bus fixes upstream needs for the same family. Only `snd-soc-macaudio`, `snd-soc-tas2764` and
  `i2c-pasemi-core` differ from the installed modules, so no new kernel image is needed.

User space (`linux/audio/`; this branch's additions are marked **new**):

| File | Installed as | What it does |
| --- | --- | --- |
| `ucm2/macaudio-k114.conf` | `/usr/share/alsa/ucm2/conf.d/macaudio/MacBook Pro K114.conf` | jack card: Headphones and Headset on PCM 0, through alsa-ucm-conf-aurora's jack-only verb; no speaker device |
| `ucm2/aop_audio-k114-hpai.conf`, `ucm2/aop_audio-k114-HiFi.conf` | `.../aop_audio/MacBook Pro K114 High-Power Audio Interface.conf`, `.../aop_audio/k114/HiFi.conf` | microphone card: one 3-channel "Mic" device (hw:AppleK114HPAI,0) |
| `wireplumber/82-k114-audio.conf` | `/etc/wireplumber/wireplumber.conf.d/` | names the raw array `RawMics` and puts the mono filter on it; **new:** no pro-audio profile on the jack card (it would open PCM 1 and 2); PCM 1 and 2 never become nodes, matched by path and by card id; the jack sink does not suspend between streams (same rule omarchy-mac installs for `AppleJ...` cards, which does not match this one) |
| `share/mic.json` | `/usr/local/share/omarchy-k114s/audio/mic.json` | the default microphone graph: equal mix of the three microphones, gain, 120 Hz high-pass, limiter, mono source `effect_output.k114-mic`. Structure of the image's J714 graph; gains are starting values, not measured |
| `share/mic-beamformer.json` **new** | same path, only with `--with-beamformer` | the same graph with the triforce delay-and-sum beamformer in front (structure of asahi-audio's `firs/j314/mic.json`, MIT, Copyright The Asahi Linux Contributors). **Its array geometry and look direction are the J314's and are unverified for this Mac**; see "Microphone beamformer" below |
| `systemd/99-k114s-speaker-guard.conf` **new** | `/etc/systemd/system/<unit>.service.d/` of `speakersafetyd`, `speakerguardd`, the five `speakerguardd-v2*`, `speakerguardd-v2-sleep` and `aurora-speaker-upgrade`, `speakerguardd-v2-seat.path.d/`, and `/etc/systemd/user/<unit>.service.d/` of `speakerguardd-v2-graph` and `-session` (12 drop-ins) | **the speaker guard**: those units run only while `/etc/omarchy-k114s/speaker-qualification` exists. The owner creates it by hand when Stage B has every proof; nothing here creates it. This is what keeps a sibling model's package (the K114c, M5 Max, shares the card name and could ship `/usr/share/speakersafetyd/apple/k114.conf`) from arming a daemon on this Mac. It also removes the 15 s boot waits. Replaces an earlier drop-in that keyed on `dai-link@1` alone |
| `tree-check`, `systemd/99-k114s-stage-a-tree.conf` **new** | `/usr/local/lib/omarchy-k114s/audio/tree-check`, `/etc/systemd/user/wireplumber.service.d/` | WirePlumber starts only if the booted tree has no amplifier node (`sn012776`, `tas27*`, `cs35l*`, `ssm3515`, `max9836*`), no `spkr` or `sense` DMA channel on an enabled node, no I2C device at 0x38 to 0x3d (these three checks run with or without a sound node), and either no sound node or the Stage A card (compatible `apple,k114-macaudio`, only `dai-link@0`). A packaged J714s tree has a real speaker path and is refused. `speaker-readiness.sh` and `install-audio.sh` use the same check |
| `install-audio.sh` | run by the lead | `--root DIR` (a tree instead of `/`, no root rights needed), `--with-beamformer`, `--undo`, `--check`; **new:** always installs the guard and the tree check first, and only then refuses (running tree not the Stage A tree, `use-packaged-dtb` set, jack verb missing), so a refused install still leaves the guard; `--undo` removes exactly the jack and microphone files and the directories only they needed, and **keeps** the guard, the tree check and the owner's marker; `--remove-guard` removes those too and is refused while `/etc/omarchy-k114s/speaker-qualification` does not exist; `--check` follows the installed graph |
| `speaker-readiness.sh` **new** | run by anyone | silent, read-only report of whether anything could reach the speakers (see Stage B) |

Other `new` work: `tests/test-audio-userland.sh` (guard, tree-check, readiness and installer tests in
fake roots, besides the 19 earlier checks) and the installer tests added to `tests/test-sound.sh`. Review notes of #6 (2026-11-15): every install path now prints the user-manager `daemon-reload` hint (sudo cannot reach the seat user's manager), `speaker-readiness.sh` checks `systemctl --user cat` of WirePlumber and the two v2 user units as the seat user, the stale gate label in `tests/test-sound.sh` is reworded, and its PMP-refusal test now runs against a copy of the dts directory without the generated PMP file, so it holds on a kernel tree that has one.

The jack-card WirePlumber rules (pro-audio off, PCM 1 and 2 never nodes) come from the
`audio-userland` worker's findings (a copy of its working files; if that branch is pushed later its
two files, `82-k114-audio.conf` and `test-audio-userland.sh`, are the ones this branch extends).

### Nothing in Stage A can open a speaker PCM

Six barriers, each independent, and a check for each. A speaker sound would need all six to fail.

| # | Barrier | Checked by |
| --- | --- | --- |
| 1 | no amplifier node, so no driver binds to an amplifier at 0x38 to 0x3d | `tests/lint-sound-dtb.py` and its refusal tests in `tests/test-sound.sh`, `speaker-readiness.sh` (bound I2C addresses) |
| 2 | pins 106, 107 (fault, shutdown) stay reserved; no SDZ regulator | the same lint |
| 3 | no Speaker link; `apple,k114-macaudio` has `enable_speakers = false` | the lint; patch 0004 |
| 4 | no `spkr` or `sense` channel on the AOP audio node | the lint |
| 5 | PCM 1 ("Secondary") exists but cannot be opened (`DMA channel "spkr" unavailable`); WirePlumber makes no node for it; no UCM device names it | `tests/test-audio-userland.sh`, `tests/test-sound.sh` |
| 6 | no `k114.conf`, no udev rule, no speaker graph, no protection daemon configuration is shipped; the speaker daemons are skipped unless the owner's marker exists (the guard); and `speaker-readiness.sh` trips (exit 3) on a `k114*.conf`, the marker, a missing guard, a booted tree that is not the Stage A tree (any `dai-link@N` with N above 0, a speaker or amplifier link name or node, a `spkr` or `sense` DMA channel, a bound amplifier address) | `tests/test-sound.sh`, `tests/test-audio-userland.sh` |

### Microphone beamformer

The default is the plain equal mix, with no steering: it needs no geometry. A beamformer needs the
array's microphone positions and look direction, and for this Mac they are **not known**: the
Apple device tree does not carry them (it names three microphones on the AOP channel and nothing
about their positions), and no public source has them. For the J604 (M4) another worker derived
them from macOS's own beamformer tuning; for the J314 they are a 2 cm equilateral triangle. A
K114s tuning bundle, once collected (Stage B step 1), might hold them, but reading that is not
done. So `share/mic-beamformer.json` is offered as an **opt-in comparison only**, with the J314's
numbers and a comment saying so at the top of the file. Install it with
`--with-beamformer`, listen against the default, and keep whichever sounds better; if the
voice is thinner or off-axis sources are louder, the geometry is wrong and the default stays.
Which raw channel is microphone 1, 2 and 3 is likewise assumed to follow the J314's order.

### Install (the lead, as root)

    sudo bash linux/audio/install-audio.sh                     # plain microphone graph
    sudo bash linux/audio/install-audio.sh --with-beamformer   # optional, the comparison graph
    sudo bash linux/audio/install-audio.sh --undo          # jack and microphone files only; the guard stays
    bash linux/audio/install-audio.sh --check

After the install, check the guard as systemd sees it (read-only, starts nothing):

    systemctl cat speakersafetyd speakerguardd-v2 aurora-speaker-upgrade | grep ConditionPathExists=/etc/omarchy-k114s
    systemd-analyze condition 'ConditionPathExists=/etc/omarchy-k114s/speaker-qualification'   # must fail while no marker exists
    systemd-analyze verify /usr/lib/systemd/system/speakersafetyd.service

`speaker-readiness.sh` runs the first two itself on the live system.

Then, with the sound tree booted and `snd-soc-macaudio.ko` from `patches/linux/sound/0004` in the
root file system, log out and in (or `systemctl --user restart wireplumber pipewire
pipewire-pulse`). The files are inert without the cards, so they may be installed before the boot.
The installer refuses any Mac that is not `apple,k114s`, any running tree with a sound node that is
not the Stage A card, and a Mac with `/usr/local/lib/omarchy-k114s/use-packaged-dtb` set; it installs
no package, touches no boot file, starts and stops no service, and does not reboot. Prerequisites that are the lead's (the
PMP file generated from this Mac's own ADT, the tree, the boot trial through `aura-try`) are in
`docs/r3-sound.md` and `docs/r3-audio-kernel.md`; the `-nomics` tree is the fallback.

### Owner's test steps for Stage A

Do them in order. Stop at the first thing that is not as expected and read "Stop conditions".
Everything is expected to be silent from the loudspeakers, always.

**A0. Gate: is this the Stage A tree? Do nothing else until it passes.** Nothing may be played, and
no step below may be run, on a tree that has a speaker path. (WirePlumber refuses to start on one,
but check it yourself first.)

    bash linux/audio/tree-check                  # exit 0 and "the Stage A tree: jack link only, ..."
    tr '\0' ' ' < /proc/device-tree/sound/compatible; echo   # exactly: apple,k114-macaudio apple,macaudio
    bash linux/audio/speaker-readiness.sh        # exit 0 (not 3)

If any of these says otherwise (for example a packaged J714s device tree is booted), shut down and
report. The same applies after every change of tree, kernel or image.

**A1. The cards.**

    cat /proc/asound/cards
    aplay -l
    arecord -l

Expected: two cards, `AppleK114` ("MacBook Pro K114") and `AppleK114HPAI` ("MacBook Pro K114
High-Power Audio Interface"); with the `-nomics` tree only the first. `aplay -l` lists
`AppleK114` device 0 "Primary" and device 1 "Secondary". That "Secondary" is listed is expected;
it is the speaker front-end and cannot be opened (do not try). `arecord -l` lists `AppleK114`
device 0 (headset) and `AppleK114HPAI` device 0 "Microphone Array". Without a boot of the sound
tree none of this exists (today `/proc/asound` is absent).

**A2. The speakers have no path.**

    bash linux/audio/speaker-readiness.sh      # exit status 0, last line "no path to the loudspeakers exists"
    ls /sys/bus/i2c/devices | grep -E -- '-003[89a-d]$'     # prints nothing
    amixer -c AppleK114 controls | grep -i -E 'protection|unlock|isense|vsense|speaker (volume|sample)|amplifier'   # prints nothing
    journalctl -k -b | grep -i -E 'tas2764|sn012776|speaker|spkr|pwrd'   # at most: DMA channel "spkr" unavailable

`Speaker Switch` and `Speaker Playback Mux` ARE expected on the card (they are on every card of this
driver and have nothing behind them: no path, no amplifier), so the grep above does not look for the
word "speaker" in the control names. Any control that names protection, an unlock, a sample rate, a
sense channel or an amplifier is a stop. Repeat the `journalctl` line after A3 to A5: no `spkr`
power-state transition may appear (the AOP firmware attaches its `spkr` service on every T6050, and
what it does with the amplifiers is as iBoot left them; that is an assumption this work cannot
check from the AP).

**A3. The jack plug.** `amixer -c AppleK114 contents` shows `Headphone Jack` and `Headset Mic Jack`
(read-only controls) and `Headphone Switch`, `Headset Mic Switch`. Unplugged: `Headphone Jack`
`values=off`. Plug in headphones: `values=on` (a headset: `Headset Mic Jack` on too), and
`wpctl status` shows, under Audio, a sink with "Headphones" in its description (node name
`alsa_output.platform-sound.HiFi__Headphones__sink`, which comes from the UCM verb and is
expected, not yet seen). Unplug: the sink goes away or is marked unavailable. There is no sink
or port named "Speaker" at any time.

**A4. Headphone playback.** Use headphones, not the loudspeakers, and keep them off your ears for
the first second.

    wpctl status                                   # the default sink must be the Headphones sink; if it is not, STOP
    wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.2
    pw-play --volume 0.3 SOME_SHORT_SOUND_FILE

Expected: sound in the headphones only, no loud click when it starts or stops. **Stop playback
(Ctrl-C) before you unplug the headphones.** Do not unplug during playback: on a wrongly booted
tree WirePlumber would move the stream to the next sink, possibly a loudspeaker. Run A4 only after
A0 and A2 have passed. After unplugging, `wpctl status` must show no sink for the card, or one marked
unavailable.

**A5. Microphone level test, played back through headphones only.** Plug the headphones in and
confirm with `wpctl status` that the Headphones sink is the default sink. If they are not plugged
in, do not play anything back; read the numbers instead.

    wpctl status | grep -i -E 'k114|mic'           # a source "MacBook Microphone (Mono)", node effect_output.k114-mic
    pw-record --target effect_output.k114-mic --rate 48000 --channels 1 /tmp/k114-mic-test.wav &
    # speak at a normal level, 30 cm from the screen, for about 5 s; then stop it
    kill %1
    sox /tmp/k114-mic-test.wav -n stat 2>&1 | grep -E 'Maximum amplitude|RMS'   # if sox is installed
    wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.2
    pw-play --volume 0.3 /tmp/k114-mic-test.wav    # through the headphones

Expected: a recording that is clearly your voice, peaks roughly between 0.25 and 0.8 of full
scale (not 0.00x, not 1.0), no steady loud hiss. Gains are starting values that were not
measured on this Mac, so "too quiet", "too loud" or "thin" are useful results to report with the
numbers. If the mono source is missing, test the raw array:

    arecord -D hw:AppleK114HPAI,0 -c 3 -r 48000 -f FLOAT_LE -d 3 /tmp/k114-raw.wav

(it may report the device busy, because PipeWire holds it; that is not a failure). The headset
microphone, if the headphones have one: record from the source `Headset Microphone` the same
way.

**A6. Optional: the beamformer.** `sudo bash linux/audio/install-audio.sh --with-beamformer`,
restart WirePlumber as above, repeat A5, compare by ear and by level. Report which is better.
Go back with the installer without the flag.

**A7. Boot and login.** Login should not be delayed by about 30 s (the unit condition is
installed). Suspend and resume once and repeat A2; it should still show no speaker path. Suspend
with the PMP and AOP running is not proven on any model of this family.

### Stage A stop conditions

Shut down (do not reboot into the same tree) and report if **any** of these happens:

1. any sound at all from the loudspeakers, at any moment, including a click or a hiss at boot;
2. A0 fails, `speaker-readiness.sh` exits 3, or A2 shows an I2C device at 0x38 to 0x3d, a
   protection, unlock, sample-rate, sense or amplifier control (`Speaker Switch` and `Speaker
   Playback Mux` are expected), a `spkr` power-state message, or any `tas2764`/`sn012776` message
   other than the `DMA channel "spkr" unavailable` line;
3. a sink or source for PCM 1 or PCM 2 appears, or the default sink is anything but the
   Headphones sink while headphones are plugged in;
4. the machine hangs, resets or loops around the PMP/AOP lines in the kernel log; boot the
   `-nomics` tree or `rollback stage2` (the tree without sound) instead;
5. a loud pop on plugging in or on starting playback in the headphones: stop playing, note
   the volume, report.

If only the microphones misbehave, use the `-nomics` tree; the jack is independent of them.

### The r3a package, checked offline (jack and Bluetooth audio pieces)

Agent-run, 2026-11-15, read-only: `linux-k114s-7.3.0.r3a-2-aarch64.pkg.tar.zst` unpacked into a temporary
directory (nothing installed). The configuration is the one embedded in its `vmlinuz` (IKCONFIG), which
agrees with the build directory's `.config`.

| Piece | In the package |
|---|---|
| Bluetooth core and SCO | `CONFIG_BT=y`, `CONFIG_BT_BREDR=y` (SCO is part of the built-in Bluetooth core; there is no separate `sco.ko`) |
| RFCOMM | `CONFIG_BT_RFCOMM=m`, `CONFIG_BT_RFCOMM_TTY=y`; `net/bluetooth/rfcomm/rfcomm.ko` present; `modules.alias` has `bt-proto-3 rfcomm`, so bluetoothd's HFP/HSP socket loads it |
| Others | `CONFIG_BT_BNEP=m` (`bnep.ko`), `CONFIG_BT_HIDP=y` (built in), `CONFIG_BT_HCICENTAURI=m` (`btcentauri_t6050.ko`, alias `pci:v0000106Bd00001903`, depends on `apple_centauri_t6050`, requests no firmware files; agent-run: on the running kernel `hci0` is bound to this driver). `CONFIG_BT_HCIBCM4377=m` (`hci_bcm4377.ko`) is also built but the N1 does not use it |
| Jack codec and card | `CONFIG_SND_SOC_CS42L84=m` (`snd-soc-cs42l84.ko`, with `cs42l84_set_jack` and `snd_soc_jack_report`), `CONFIG_SND_SOC_APPLE_MACAUDIO=m` (`snd-soc-macaudio.ko`, alias `apple,k114-macaudio`), `CONFIG_SND_SOC_APPLE_MCA=m`, `CONFIG_SND_JACK=y`, `CONFIG_SND_JACK_INPUT_DEV=y` |
| AOP, PMP, DMA, I2C | `aop.ko`, `apple-admac.ko`, `i2c-pasemi-platform.ko`; `CONFIG_APPLE_PMP=m` |

Baseline kept for the comparison after the boot (agent-run, running kernel, this boot's bluetoothd journal):
`RFCOMM server failed for Hands-Free Voice gateway` and `... Hands-Free unit: socket(STREAM, RFCOMM): Protocol not supported (93)`.
After an r3a boot those two lines must be gone: `tests/hardware/k114s-r3a-audio-check.sh` section 4 tests it.
Not proven by any of this: that the modules load and bind, that anything is audible.

### Owner's attended check after the r3a boot

`bash tests/hardware/k114s-r3a-audio-check.sh` (read-only, no root; also writes a redacted copy of the report to
`~/k114s-audio-check-DATE.txt`) reports the kernel and tree, the sound cards, modules, a 5 s codec interrupt count
(an idle codec is quiet; a stuck status latch would show about a thousand a second), the guard state, and the Bluetooth
controller, UUIDs and RFCOMM journal. With `--listen` it pauses for you to plug and unplug headphones, listen over the jack
and over Bluetooth, and run a hands-free test; `--play` adds a 2 s quiet tone on the K114 jack sink only (it refuses any
other sink and a sink volume above 50 %). It never pairs, loads a module or changes a setting. Its ASK lines are what you
record as owner-observed. Its software test is `tests/hardware/test-r3a-audio-check.sh`.

### linux #1895 (cs42l84 probe writes): not applied to the K114s

aurora-silicon/linux #1895 adds an optional `apple,init-writes` device-tree property that the cs42l84 driver
applies right after its ID check, plus a fourth commit that reads `REMOTE_BUTTON_STATUS1` (0x1484) once after the
writes and in every codec interrupt. Read 2026-11-15 (upstream-reported; the author's own J604 measurements, plug and unplug untested at the time):

- The 20 register values are a macOS I2C trace on the J604 (M4, T8132). The only machine with the property is the J604. Nothing says the K114s (M5 Pro, T6050) codec wants the same values: two of them tune jack detect (0x1471 to 0x1480), the rest analog trim, and a trace of macOS on this Mac does not exist here.
- Without the property the driver is unchanged, so the r3a kernel is unaffected whichever way this goes.
- The one hazard the writes bring (an unmasked latch holding the interrupt line asserted, about 1000 interrupts a second) is the author's fix in commit 4, and is irrelevant while the K114s writes nothing.

Decision: do not copy the J604 values to the K114s. Boot first and see whether the jack detects without them. The check script's
interrupt count tells whether this codec shows the same stuck-latch symptom (it should not); if plug detection or headset type
detection fails, the next step is a K114s macOS probe trace, then K114s-specific values, not the J604's. Candidate upstream remark, only after a boot: report the K114s jack result on #1895 (see `UPSTREAM.md` once there is a result).

## Stage B: the loudspeakers

### Result: blocked, nothing enabled

Whether a K114s speaker qualification can be produced from this Mac's own data was researched in
`docs/r3-audio-protection.md`. **It cannot.** The reasons, in the order they bite:

| # | Needed for speakers | Where it stands | On this Mac? |
| --- | --- | --- | --- |
| 1 | kernel entry with speakers admitted, speaker nodes in the tree, loader copies each amplifier's configuration | all derivable from this Mac's ADT; the amplifier description is byte-equal to the K116s's; `src/kboot_audio.c` needs no change | can be written; not written, on purpose |
| 2 | this Mac's own tuning bundle (`AID49`) | none collected (the vendor firmware manifest lists no `audio-tuning`) | readable from this Mac as root: Stage B route 1 |
| 3 | the bundle compiles without refusals | untested until 2 | yes, after 2 |
| 4 | every protection type of the tuning is "at parity" in the installed gate | upstream says K114/K116 tunings are `lsm2` **with an LSID companion**; the gate accepts `spp3`, `lsm2`, `atsp` only. Upstream states these stay muted and that no board allow can bypass it; none of its lab Macs has LSID | **no: this is upstream's measurement work** |
| 5 | voicing attestation for this tuning and macOS build | `AID49` is attested for macOS 26.6.2 only; this Mac runs 27.x | undecidable until 2 |
| 6 | silent self-check on hardware (wiring, slot readback, zero-sample switch test) | needs a kernel with the amplifier nodes | would power the amplifiers: a decision, below |
| 7 | the older daemon (`speakersafetyd`) with a `k114.conf` | no profile exists for this model; the one public K114 draft is for the M5 Max, unmeasured, in a different speaker order; the public tool that derives a profile reads `spp3` and `atsp` only | thermal constants for this model have no public derivation |
| 8 | the owner hears it | | no |

No sibling's tuning, calibration, identity or profile is reused. What the K116s shares with this
Mac is proven only for the electrical description (same amplifier chips, addresses, group order,
levels and sense slots: six equal configuration rows read from this Mac's own ADT and upstream's
published K116s rows); it differs in acoustic ID (49 against 50), chassis (14 against 16 inch)
and voicing key. That proves the wiring is alike; it says nothing about drivers, enclosure,
limits or tuning, and nothing in this work treats it as proof of more. **The decision to treat any
part as shared belongs to the lead and the owner.**

### What Stage B ships (all silent)

- `linux/audio/speaker-readiness.sh`: run any time, no root. Lists what is blocking, and exits 3 if
  anything that could admit a speaker path is present while the proofs are missing (a `k114.conf`,
  a second card link, a bound amplifier address). It also reports what the installed gate says.
  agent-run on this Mac: exit 0, five blockers.
- `linux/audio/stage-b-collect.sh`: the two read-only steps below, wrapped. It refuses to run if the
  readiness report trips, writes only into a new mode-700 directory, runs `collect` only (never
  `run`, `--revert` or anything that switches a daemon), and prints names and verdicts, not
  values. **Not run**: it needs root, which this task did not use.
- `tests/k114s-adt-speaker-facts.py` (from the protection work): checks this Mac's own ADT against
  the K116s layout and prints no payload. Run as root: `sudo python3 -I tests/k114s-adt-speaker-facts.py`.

Not shipped, on purpose: any device-tree include that enables the amplifiers, a gate setting,
a `parity.json`/`gate.json` edit, a `k114.conf`, a UCM speaker device. They would be written
for data that does not exist, and a file in the repository that could be included is a path.
`docs/r3-audio-kernel.md` ("What the speaker step would add") lists what such an addition
consists of, for the day the proofs exist.

### The shortest honest route to speakers

Items 1 to 3 below are silent, local and need only root; item 4 is upstream's and is the part that
decides the outcome. In order:

1. **Collect and read this Mac's own tuning** (root; lead or owner):

       sudo bash linux/audio/stage-b-collect.sh

   (equivalent to `aurora-speaker-upgrade collect --out /root/k114s-tuning --route 1` followed by
   `aurora-speaker-tuning identify`, `validate` and `voicing-check`). The result stays in a root-only
   directory, never in git. If the collect step says the `lsm2` fill is missing, boot macOS once and
   follow `aurora-speaker-upgrade guide` (read-only, no sudo), then `--route 3 --collection FILE`.
   Expected, not yet seen: the unit is `lsm2` with an LSID companion, and `voicing-check` says
   whether item 5 holds. **Whether route 1 works on a macOS 27.x volume is not known.**
2. **Derive the wiring offline** against a candidate tree that has the speaker nodes, without booting
   it: `/usr/lib/speakerguardd-v2/wiring.py describe --dtb CANDIDATE.dtb -- BUNDLE`. A refusal is a
   mismatch found for free.
3. **Run the macOS half of upstream's silent LSID tester** (`tools/lsid-tester` in
   aurora-silicon/speakerguardd; volume 0 and mute; about 10 minutes). Upstream asks for exactly this
   model, and it is what moves item 4. Sending the log is the owner's decision; nothing is posted
   by this work. A question for upstream, if the owner chooses to ask (not sent): "A K114s
   (MacBook Pro 14-inch M5 Pro, acoustic ID 49) has an `lsm2` tuning with an LSID companion and
   the gate refuses it for protection type `lsid`. Which measurements or logs from this model
   would move `lsid` into `units_at_parity`, and is the macOS 27 voicing attestation needed
   separately from 26.6.2?"
4. **Wait for upstream** to put `lsid` into `units_at_parity`, or to merge an `AID49` qualification,
   with this model's data and protection active. That is the first point at which the owner can
   listen. Until then, nothing in this repository changes the answer.

There is **no self-check step**. An earlier draft proposed booting a tree with the amplifier nodes
for a "silent" self-check; it would power the amplifiers and open a stream, so it is removed from
the plan. It could return only as a separate decision of the owner under the conditions in
`docs/r3-audio-protection.md` ("What can be done without sound", step 5): the speaker units
skipped (the guard does it), `enable_speakers = false` so the kernel refuses playback, sense-only,
and the J714 amplifier layout accepted only with owner-reviewed ADT evidence.

**Before any Stage B kernel**: the legacy "Speaker Volume Unlock" interface needs no privilege
(any process holding the element lock can unlock full gain), whereas "Speaker Protection" needs
`CAP_SYS_ADMIN`. A K114s Stage B must offer only the second and refuse the first. The only
daemon-independent protection today is the kernel's locked ceiling (volume step 1, and playback
refused when the lease runs out). Details: `docs/r3-audio-protection.md`, "Stage B kernel floor".

### Things on the image that would act on their own once a speaker card exists

From `docs/r3-audio-protection.md`: a file `/usr/share/speakersafetyd/apple/k114.conf` is the
switch that admits the older daemon (never create one to "try", and a K114c package could supply
one: the guard drop-ins make `/etc/omarchy-k114s/speaker-qualification` the second, owner-only
condition); `aurora-speaker-upgrade.service` runs at every boot with the preview acknowledgement
(with a speaker card it would collect, be refused, and restart the user's PipeWire; it is guarded
too); and what keeps the speakers silent today is the six barriers above, not the absence of a
daemon. Keep `tests/lint-sound-dtb.py` on every tree. Known limit of the guard: it is a drop-in
condition, so a later drop-in that resets `ConditionPathExists=` would remove it; `99-` sorts last
and `speaker-readiness.sh` checks the files and, on the live system, `systemctl cat` for the merged unit.

### Owner's steps for Stage B

None that play sound. Run `bash linux/audio/speaker-readiness.sh` after any change of tree, kernel
or image: it must exit 0. If at any time the loudspeakers produce any sound, shut down and report.

## What is proven where

| Claim | Label | Evidence |
| --- | --- | --- |
| Kernel patches 0001 to 0004 apply in order with `git am` to the installed kernel's source (`52b16218c2`); the result equals the working tree the checks below ran on | agent-run, 2026-11-14 | fresh detached worktree, no diff |
| `macaudio`, `tas2764` and `i2c-pasemi-core` compile and link as modules with `W=1` (clang), no warnings; only these three differ from the installed modules | agent-run, 2026-11-14 | `kmake -j6 W=1`; log in `k114s-build/audio/audio-full/kmake-w1.log` |
| Both sound device trees build and pass `lint-dtb.py` and `lint-sound-dtb.py` (AP pins exposed 80, 134, 139); the lints refuse ten unsafe trees | agent-run (trees built with this Mac's own PMP values by the kernel review) and replica (refusals) | `tests/test-sound.sh`: 52 of 52 on the base tree |
| dtc: one warning (`simple_bus_reg` on `pmp@284e00000`), from the shared upstream file, also in the r1 tree | agent-run | kernel review |
| This Mac's ADT agrees with the fragment: 69 of 69 jack, AOP, DMA, DART, microphone and PMP facts; the six amplifier descriptions are byte-equal to the K116s's | agent-run (read as root by another worker, today) | `tests/k114s-adt-sound-facts.py`, `tests/k114s-adt-speaker-facts.py` |
| UCM profiles parse (`alsaucm`), the jack profile has Headphones and Headset and no Speaker device | agent-run, no card | `tests/test-sound.sh` |
| WirePlumber rules and both microphone graphs parse; the rules name only the six expected properties; PCM 1 and 2 are never nodes | agent-run | `tests/test-audio-userland.sh` (these 19 checks are among its total) |
| `tree-check` accepts the compiled Stage A tree and refuses a packaged J714 card, a Speaker link at `dai-link@1`, `@2` or any address, a speaker-named link, an amplifier node, a `spkr` or `sense` channel and a bound amplifier address; it also refuses them when there is no sound node and an amplifier or a `spkr` channel on an enabled node exists, and ignores a `spkr` channel on a disabled node; the guard drop-ins land on twelve units; a refused install (wrong tree, `use-packaged-dtb`) still leaves the guard; `--undo` keeps the guard and is otherwise exact; `--remove-guard` is refused without the owner's marker | agent-run (compiled tree) and replica (fake roots) | `tests/test-sound.sh`, `tests/test-audio-userland.sh` |
| The guard actually keeps a unit from starting under systemd | **not proven** by starting anything; checkable read-only after install | the drop-in text and its install are tested. After install, `systemctl cat` shows the merged condition and `systemd-analyze condition` evaluates it (both in the install steps above and in `speaker-readiness.sh` on the live system); no unit was started |
| Both microphone graphs load in a private PipeWire (own socket, clean environment, no device, the live session untouched) and create exactly the capture stream and the mono source; a broken graph is refused | replica | same |
| The installer installs, switches graph, undoes, and refuses a non-K114s, in a fake root, with `--root` | replica | `tests/test-sound.sh` |
| `speaker-readiness.sh` reports no path and blockers on a system with the guard installed, and trips on a `k114*.conf`, the marker, a missing guard, or any speaker path in the tree (see barrier 6) | replica (made-up roots); on the live Mac before the installer has run it trips on the missing guards, by design | `tests/test-sound.sh`, `tests/test-audio-userland.sh` |
| The speakerguardd v2 gate, run on the compiled tree, finds no speaker card; on this Mac today it says unqualified (no bundle) | agent-run | `tests/test-sound.sh`; protection doc |
| The cards `AppleK114` and `AppleK114HPAI` appear; the AOP and PMP come up on this board; the jack plays, detects a plug, records a headset; the three microphones record | **not proven** | no sound tree has booted. Upstream marks the K116s microphone commit "not tested on the hardware yet" and the K116s author's later status lists the array as working: neither is a K114s result |
| The gains in either microphone graph; the beamformer geometry | **not proven** | gains are the J714 image's starting values; geometry is the J314's |
| Suspend with the PMP and AOP running | **not proven** | |
| `dt-validate` of the bindings | **not run** | tool not available here |
| This Mac's speaker tuning, qualification, LSID parity, voicing attestation | **does not exist / not obtained** | protection doc |
| `stage-b-collect.sh` end to end | **not run** | needs root; the refusal path (no root) was run |
| Speaker playback, protected or otherwise | **never done, never to be done before protection exists** | |
| Anything heard by the owner | **owner-observed: none yet** | |

Test environment note: `tests/test-sound.sh KTREE` expects a tree without the generated PMP file
(one of its checks is that the build fails without it); a scratch tree that already contains this
Mac's PMP values passes everything else and fails only that check. It needs `dtc` on `PATH`
(the build environment has one).

## Decisions for the lead and the owner

1. Which tree to boot for the first sound trial: sound alone (`t6050-k114s-r3-sound`, tested here) or
   sound on the GPU tree (one more include, built by the kernel review, not in the repository).
2. Whether to run `stage-b-collect.sh` (root, read-only) and, with the owner, the macOS LSID tester,
   and whether to send anything upstream.
3. (Withdrawn.) The silent self-check on an amplifier-node tree is no longer proposed: see Stage B.
4. Whether the generated PMP file may live in this public repository (default: no, kept as a build
   input outside it).
5. Optional hardening, untested: `route_only_fes = BIT(1)` in the K114 entry would remove the
   unopenable PCM 1 altogether.
6. Whether `omarchy-audio-asahi-mic-map` (the image's stereo mapper, which matches `effect_output.jNNN-mic`
   only) should learn the K114 name; without it the mono source still reaches stereo clients
   as MONO on both channels.
   Answered offline: yes, with patch 0004 (the DSP regex, `audio.json` and the name rule take `[jk]`); see
   [docs/platform-data.md](platform-data.md). Needs the owner at the Mac once the card exists.
