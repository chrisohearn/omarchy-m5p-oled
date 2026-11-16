# HDMI / DisplayPort audio (issue 42)

Status: blocked on external display bring-up (docs/r3-display-gpu.md). The offline comparison below
is done. Evidence labels: agent-run, upstream-reported, source-read.

## What the K114s ADT has (agent-run: `sudo python3 tests/k114s-adt-dp-audio.py`)

| ADT node | Facts |
|---|---|
| `dp-audio0` to `dp-audio4` | no `reg`, no `compatible`; properties `power-gates`, `clock-gates` (one id each: 154, 68, 81, 75, 78), `function-device_reset_dpa`, `dma-channels` (identical in all five), `dma-parent` |
| `dp-audio0` | belongs to the internal `disp0`; `dma-parent` is `admac-disp0` |
| `dp-audio1` to `dp-audio4` | `audio` property of `dcpext0` to `dcpext3`; `dma-parent` is `admac-dispext0` to `admac-dispext3` |
| `admac-disp0`, `admac-dispext0..3` | `admac,t6050` (not the t8103-style ADMAC), windows 0x48a140000, 0x2b2140000, 0x392140000, 0x302140000 (size 0x24000), one interrupt each; each has an `admacled,t6050` "ced-ssw" companion node |
| `sio`, `dart-sio` | `sio` is `iop,ascwrap-v6` at 0x505e00000; `dart-sio` is `dart,t8110` at 0x505060000 |

## Comparison with the merged M2 Pro/Max pattern (source-read, AsahiLinux/linux `asahi` branch)

On T602x (J414s/J416s) and T8112, display audio is `dpaudio0..N` (`apple,t6020-dpaudio`):
a 0x4000 window next to the audio ADMAC (0x39b500000 on t6020 die 0), `dmas = <&sio 0x64>`
(DMA through the SIO coprocessor), `power-domains`/`reset-domains = <&ps_dpa0>`, and an OF graph
endpoint to the DCP's `dcp_audio` / `dcpext*_audio` port. `dcpext*` nodes carry the matching
remote endpoint.

The K114s differs in three ways, so the M2 nodes do not port by copy:

1. No MMIO window for the DP audio block in the ADT. The `dp-audio*` nodes are only power/clock/reset
   functions.
2. The DMA path is per-display ADMAC (`admac,t6050` plus `admacled` ced-ssw), not SIO channel 0x64.
   `sio` (with an `sio-dma` child) is present but no `dp-audio*` property points at it.
3. Mainline `apple,dpaudio` has no T6050 compatible, and the `admac,t6050` / `admacled` layout has no
   driver. This needs new kernel work, not just device-tree nodes.

Not found: the cited "linux #1267" does not resolve in AsahiLinux/linux (issue or PR); the merged
pattern above was read from the `asahi` branch device trees instead. Treat the number as unverified.

## What is left

- Upstream/lane owner: T6050 DP audio driver support (ADMAC t6050 for the display engines, DPA power
  gating). Belongs with TripleU613 (shared T6050 kernel work) and the Asahi audio maintainers; ask
  whether M3/M4 (`admac,t6030`-style) has the same per-display ADMAC.
- Ours, after external display works: add `dp-audio` nodes to the K114s tree and verify.
- Owner: a monitor with speakers on USB-C or HDMI; expected result an ALSA/PipeWire sink and sound.
  Until then nothing to run: `cat /proc/asound/cards` shows no card, as today.
