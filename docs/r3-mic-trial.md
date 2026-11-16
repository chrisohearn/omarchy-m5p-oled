# K114s internal microphones: trial plan and upstream report template (issue #38)

Status: offline work done; the recording trial needs the owner at the Mac on a boot with the sound tree
(card `AppleK114HPAI`). The running kernel today has no sound card (`/proc/asound/cards`: no soundcards).

## Offline evidence (agent-run, read-only)

| Check | Result |
|---|---|
| `sudo python3 -I tests/k114s-adt-sound-facts.py` against this Mac's ADT | 69 of 69 facts hold, including: microphone stream `leap-s-adma-rx-0`, 3 microphones in the array, leap-s RX channels 9, proxy ADMAC dma-channel 0, leap-s interrupt 638, dart-aop streams 1 and 11 |
| Mapper and names for a K board (`omarchy-audio-asahi-mic-map`, `audio.json`) | patch 0004 widens `j` to `[jk]` (see docs/platform-data.md); the graph's mono source `effect_output.k114-mic` matches |
| `mic.json` and `mic-beamformer.json` load in a private PipeWire and create exactly the capture stream and the mono source | `tests/test-audio-userland.sh` |
| New: analyzer and trial script logic | `bash tests/hardware/test-mic-trial.sh` (synthetic three-channel files: silent channel, clipping, wrong channel count, non-WAV) |

Channel order: the ADT names three microphones on one AOP channel and carries no positions, so raw channel
N is not known to be microphone N of the J314 layout. The `mic.json` mix is symmetric (1/3 each), so
the default graph does not depend on the order. Only the opt-in beamformer does, which is why it stays opt-in.
Upstream's J714s array commit (linux #1557) uses the same single 3-channel capture stream.

## Owner trial (about 5 minutes, after a sound-tree boot)

    bash tests/hardware/k114s-mic-trial.sh

It records five short takes (quiet, talk, clap left, clap right, mono source), prints per-channel peak,
RMS, silence and clipping, and the correlation between channels. It plays nothing. Then play the mono take
through headphones only. Done when three channels carry signal, the mono take is intelligible, and the
owner confirms by ear (owner-observed).

## Upstream test report template (for linux, K114s/K116s microphones)

    Machine: MacBook Pro 14" M5 Pro (K114s, T6050)
    Kernel: <uname -r>, tree: <sound tree name>, userspace: <UCM/WirePlumber files used>
    Card: AppleK114HPAI present: yes/no; arecord -l line: <paste>
    Raw capture: hw:AppleK114HPAI,0, 3 channels, 48 kHz, format: <paste>
    Per-channel (from k114s-mic-analyze.py): ch0 <peak/rms>, ch1 <..>, ch2 <..>; silent channels: none/<which>
    Clap left vs right: loudest channel <..> / <..>
    Mono source intelligible: yes/no; noise: <..>; level: <too quiet/ok/too loud>
    dmesg lines (aop, leap, admac, pmp): <paste, no serials>
    Not tested: beamforming geometry, speakers, jack.
