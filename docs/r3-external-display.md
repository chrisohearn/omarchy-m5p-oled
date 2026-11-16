# External displays over USB-C (issue 23)

Status: **offline evidence gathered; nothing plugged in; blocked on the internal DCP hand-off
(D4) and on the upstream 27.2 external-display path.** Written 2026-11-15 on the K114s, r3a
kernel on the GPU tree. The panel is still simpledrm.

## What the ADT says (agent-run, read-only)

Run: `sudo python3 -I tests/hardware/k114s-external-display-adt.py` (new in this change) and
`tests/k114s-adt-display-facts.py`. Both read the loader's copy of the Apple device tree.

| Fact | K114s value |
| --- | --- |
| DCP image of `dcp`, `dcpext0` to `dcpext3` | all five `3D6C8857-E6F1-3D2E-9DFF-587028AE0C6E` (macOS 27.2 26B8125, the K116s image, pinned by aura #226), all `running=1` |
| external display coprocessors | four: `dcpext0` `0x2b2e00000`, `dcpext1` `0x392e00000`, `dcpext2` `0x302e00000`, `dcpext3` `0x306e00000` (size `0x88000`) |
| display engines | `dispext0` to `dispext3` at `0x2b0000000`, `0x390000000`, `0x300000000`, `0x304000000`; `external` set |
| DARTs | `dart-dcpextN` `0x2b2340000`, `0x392340000`, `0x302340000`, `0x306340000`; `dart-dispextN` `0x2b2300000`, `0x392300000`, `0x302300000`, `0x306300000` |
| routing | each `dcpextN` has `dp-switch-parent` = `display-crossbar0`, `dp-switch-ufp-port` 0, `dp-switch-ufp-endpoint` N, `audio` = `dp-audio(N+1)` |
| DP side | `atc0..3-dpxbar`, `atc0..3-dpphy`, `atc0..2-dpin0..3`, `atc-phy0..3`, `dptx0-aux`, `dptx1-aux` (with `-core`, `-ufp`) |

The running r3a tree already carries all four `apple,t6050-dcpext` nodes (same register
addresses as the ADT) and every one is `status = "disabled"`, as is the K116s tree
(`dcpext1..3` only get clock and DMA-range fixups there). The K114s therefore matches the K116s
here; no K114s-only difference was found. The ADT dcpext image is identical to the internal
DCP's, so the aura #226 pin admits it.

## Why it stays off

- aura #226 (merged) hands off the internal panel only on 27.2: with the external engines
  included, `dcpext0` hits the deferred-probe timeout and delays the display from 2 s to 18.6 s
  on the K116s, and a USB-C port controller logs read failures meanwhile
  (upstream-reported, K116s).
- The K116s tree keeps the right port USB-only ("dcpext0's DisplayPort route through ATC2 stays
  off") and describes no USB4 router (see `docs/r3-usb.md`), so there is no twin to copy.
- The internal panel is not on DCP yet (D4 of `docs/r3-display-plan.md`). External display needs
  that first.

## Not resolved offline

Which `atcN-dpin` input feeds which `dcpextN`, and which of those the left-front and right ports
use, needs the crossbar and `dpin` properties read per node. That is the first step of the
dts draft, and it is only worth doing once the internal hand-off (D4) shows what the 27.2 DCP
accepts.

## Next

1. After D4 passes, prepare a disabled `dcpext` route for one port as a dts draft, tested with
   `tests/lint-display-gpu-dtb.py`; do not enable it by default (the 27.2 timeout above).
2. Upstream: report K114s specifics on aura #226 (draft in the issue comment), watch linux
   #1921, #1806, #1829.
3. Owner trial (needs an external-display tree): plug a USB-C monitor into the left-front port
   with `tests/hardware/k114s-plug-probe.sh`, watching for hangs. Until then there is nothing
   to plug into.
