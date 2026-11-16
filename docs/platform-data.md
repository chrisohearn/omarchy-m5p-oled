# omarchy-mac platform data for the K114s

What the Apple Silicon platform package (`omarchy-mac`, which owns `/usr/share/omarchy-platform/`,
`omarchy-audio-asahi-mic-map` and the Asahi audio rules) does not know about this Mac, and the local
overlay that adds it. Issues #18, #75, #39 and #40. Evidence labels: **agent-run** (run or read on this Mac,
2026-11-15, read-only), **replica** (a made-up root, no hardware), **upstream-reported**, **derived**
(computed from the others, not measured), **not proven**.

Nothing here is installed. The overlay is patches 0003 and 0004 in `patches/omarchy/`, put on and kept on
by the existing `omarchy-patches-install` (see [omarchy-patches.md](omarchy-patches.md)); the installer, the
update hook and the applier now accept files that `omarchy-mac` installed, as well as `omarchy` and
`omarchy-dev`. Test: `bash tests/test-platform-data.sh` (44 checks; replica).

## The display notch (#18)

omarchy-mac's `display-cutouts.json` gives the bar a floor at least as tall as the notch. An entry matches a
connector-name prefix and an exact mode (4 px of slack), and `top` is physical rows.

- **agent-run:** this Mac's screen is the boot framebuffer, 3024x1986 on `simpledrm`, `asahi,show-notch`
  present. Hyprland calls it `Unknown-1` at scale 2. None of the four shipped entries match.
- **agent-run, not available:** the ADT carries no panel node and no notch height. `/product` has
  `partially-occluded-display = 1` (there is a notch) and `/arm-io/disp0` has `dot-pitch-float` = 254.6 ppi
  (agent-run; matches the figure joshuaswarren derived for the K114c, and the K116s's; a pixel density is not a notch measurement). `display-timing-info` is timing, not geometry. So the height cannot be read; it is
  derived.
- **derived:** `top = 96`. This is the shown-minus-hidden band and probably overstates the floor against omarchy-mac's `top` convention (64 for the 14-inch M1). The K116s has the same pixel density and a 96-pixel notch (**upstream-reported**,
  docs/r3-display-gpu.md: 3472x2266 with the notch shown, 3472x2170 with it hidden: 2266 - 2170 = 96), and
  the K114s and K116s are "identical node for node". The other plausible model (the M1-era 64 rows plus the
  22 extra rows of 1986 over 1964, i.e. 86) agrees with the K116s only by coincidence of its 32 extra rows;
  a floor too small leaves a sliver of window beside the camera, one too big only makes the bar thicker, so
  the larger one is used. **Not measured.**
- Patch 0003 adds `{eDP, 3024, 1986, 96}` (the line for upstream) and `{Unknown-1, 3024, 1986, 96}` (local
  only: the name the boot framebuffer has now; delete it when the panel is `eDP-1`, which the r3a
  internal-panel patch or the DCP hand-off gives). **replica** (the shell's own `BarModel.js`): 48 logical
  px at scale 2, the 14-inch M1 entry unchanged, no floor on an external monitor or a rotated panel.
- **The `shell.toml` workaround in the issue does not work** (**replica**): `[bar] notch-height` only
  replaces the derived value on a screen an entry already matches. With no entry the floor stays 0. That is
  why the entry is needed, and why it carries both names.
- **Native DCP mode: unknown.** A K114s that hands the panel over may come up at 3024x1986 (notch shown;
  the same entry covers it) or at a mode with the notch hidden (1986 - 96 = 1890 by the same arithmetic,
  a guess). A hidden-notch mode needs no entry (**replica**: no floor). Do not add 3024x1890 on a guess.
  After the DCP boot, `k114s-platform-data-check.sh` prints the real mode and whether an entry matches.

## The microphone and the device names (#75, #39)

**agent-run (file read):** the K114s cards are `AppleK114` (the jack) and `AppleK114HPAI` (the array); the
filter-chain nodes (`linux/audio/share/mic.json`) are `effect_output.k114-mic` (mono source) and
`audio_effect.k114-mic` (its capture side). omarchy-mac matches `jNNN` names:

| Where | Pattern (before) | Effect on `effect_output.k114-mic` | Patch 0004 |
| --- | --- | --- | --- |
| `omarchy-audio-asahi-mic-map`, `DSP` | `effect_output\.j[0-9]+-mic` | not found: no stereo source `omarchy_asahi_mic`; stereo clients get MONO | `[jk]` |
| `audio.json` `replaced` | `effect_output\.j[0-9]+-mic` | the mono node is listed next to the (absent) stereo source | `[jk]` |
| `audio.json` `hidden` | `audio_effect\.j[0-9]+-mic` | the raw capture node stays in the device list | `[jk]` |
| `asahi-device-names.conf` | `^effect_output\.j[0-9]+-mic$` | no "MacBook Microphone (Mono)" name from this rule | `[jk]` |
| `asahi-audio-no-suspend.conf` | `hw:AppleJ[0-9][0-9][0-9],[01]` | the jack sink (`hw:AppleK114,0`) suspends when idle: a pop | `Apple[JK]...` |

Two of these are already covered locally and the patch only makes omarchy-mac say the same: the graph names
itself "MacBook Microphone (Mono)" (`mic.json`), and `82-k114-audio.conf` keeps `hw:AppleK114,0` open (a
**replica** check asserts the two rules agree). Smallest fix chosen: option (c) with a local copy (the patch is
the upstream change); option (a), naming the K114 nodes `j114`, would have worked with no patch but names a
board that does not exist and changes names the tests and the rules here already use.

**Left alone:** the mapper's `ARRAY` regex (`AppleJ...HPAI`), which only decides whether to repair a missing
asahi-audio graph, and which reads rules from `/usr/share/wireplumber` only, where the K114 rules do not live.
The K114 graph is not asahi-audio's, so a repair would not apply anyway. The mapper also has not been run
against the real card: **not proven** until the sound boot. **replica:** the mapper's own `find_dsp`, the
shell's own `AudioNodesModel.js` and the rule files, parsed by `spa-json-dump`.

## The headset-mic rule (#40)

`asahi-headset-mic.conf` lowers `priority.session` of `alsa_input.platform-sound.HiFi__Headset__source`.
**replica:** `alsaucm` on a virtual card made from this repository's `macaudio-k114.conf` and the packaged
CS42L84 jack verb (with `${CardId}` set to `AppleK114`, which a card-less `alsaucm` cannot supply) lists the
devices `Headphones` and `Headset`, the Headset capture is `hw:AppleK114,0`, and the card's device-tree node
is `/sound`, so PipeWire's name for it is `alsa_input.platform-sound.HiFi__Headset__source` (verb, device and
direction as the ACP builds them; the composition is a replica of that rule, not observed). The rule matches
it, matches nothing else, and the rename rules match the same two names. **Not done:** a WirePlumber
dry-run on a fake node (a private WirePlumber needs a session and a device; the check on the real node is in
`k114s-platform-data-check.sh` after the sound boot). Whether the headset buttons and the jack control work is
**not proven** (docs/r3-audio-kernel.md).

## Install and undo (owner, when ready; changes the system)

```
sudo bash linux/omarchy-patches-install          # applies 0001-0004 and adds omarchy-mac to the hook
sudo bash linux/omarchy-patches-install --undo
```
Needs GNU `patch`. Patches 0003 and 0004 change only files `omarchy-mac` installed. Not run here. Delete the
`Unknown-1` line (and refresh) once the panel is `eDP-1`.

## Owner at the Mac

`bash tests/hardware/k114s-platform-data-check.sh` is read-only and prints what to check. Display: look at the
notch against the bar; report the bar's height and whether windows peek out. Audio, after the r3a sound boot:
a pop at headphone start and stop, the panel names, a headset record/unplug/replug. Never the loudspeakers.

## Upstream draft: omacom/omarchy-mac-pkgs

(Not filed. Send after the notch is measured and the audio names are seen on the card.)

> **Cover the K-board MacBook Pros (M5): display cutout and audio names**
>
> The M5 MacBook Pro 14" and 16" are boards K114 and K116, not jNNN. Running Omarchy on a K114s (Mac17,13)
> with a kernel that has the AOP audio and jack card, the cards are `AppleK114` and `AppleK114HPAI`, and the
> microphone graph's nodes are `effect_output.k114-mic` and `audio_effect.k114-mic`. Several omarchy-mac
> files match `j[0-9]+` only:
>
> - `omarchy-audio-asahi-mic-map`: `DSP = effect_output\.j[0-9]+-mic`. The mono source is never found, so
>   there is no stereo `omarchy_asahi_mic`.
> - `audio.json`: `hidden` `audio_effect\.j[0-9]+-mic` and `replaced` `effect_output\.j[0-9]+-mic`.
> - `asahi-device-names.conf`: `^effect_output\.j[0-9]+-mic$`.
> - `asahi-audio-no-suspend.conf`: `hw:AppleJ[0-9][0-9][0-9],[01]`: the jack sink suspends and pops.
>
> This widens each to `[jk]` / `Apple[JK]`. The 3-digit K boards match the existing shape. No behaviour
> change for J boards (replica: the mapper's `find_dsp` and the shell's `AudioNodesModel.js` run against
> both names).
>
> `display-cutouts.json`: K114s boot framebuffer 3024x1986, `asahi,show-notch` set; adds
> `{ "connector": "eDP", "width": 3024, "height": 1986, "top": 96 }`. `top` is derived from the K116s's
> 96-pixel notch at the same pixel density, **to be confirmed by a measurement on a K114s before merge**.
> A mode with the notch hidden needs no entry. The K116s's modes (3472x2266, 3472x2170) are not added
> here: we have no K116s to check them.
>
> Tested: replica only (fake root, the shell's own `BarModel.js` and `AudioNodesModel.js`); not on a
> sound-enabled K-board kernel yet. The speakers are not part of this change and stay unsupported on K boards.

The patch to send is `patches/omarchy/0004-...` and the `eDP` line of `0003-...`, rebased onto
omarchy-mac's own tree layout (`/usr/share/...` paths are the package's `usr/share/...`).

## Display audio nodes in the ADT (#42)

**agent-run (read-only):** `dp-audio0..4` are power, clock and reset nodes only, with no `reg`. The display
ADMACs are `admac,t6050` at `0x48a140000` and `dispext0..3` at `0x2b2140000`, `0x392140000`, `0x302140000` and
`0x306140000`. No T6050 `dpaudio` or per-display ADMAC driver exists yet (docs/r3-audio-dp.md, PR #108, not merged).

