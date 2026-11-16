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

## Comparison with the merged upstream pattern (source-read, aurora-silicon/linux `integration/aurora`)

Two merged trees describe display audio:

- J714s (same SoC as the K114s, ADMAC-fed): `t6050-j714s-dpaudio.dtsi` (commit b8e6029323c7). One
  `apple,t6050-dpaudio` node with `dmas = <&admac_dispext0 0>`, `power-domains = <&ps_dispext0_adma>`
  and an OF-graph endpoint to `dcpext0`. `t6050-peripherals.dtsi` defines `admac_dispext0` at
  0x2b2140000 (size 0x24000) as `apple,t6050-display-admac`, and an alias
  `admac-dispext0-control` that the loader uses to find the ced-ssw block and copy its ADT tunables.
  This is the same per-display ADMAC window and path the K114s ADT shows, so it is the direct
  reference.
- J616s (M4, SIO-fed): aurora-silicon/linux#1267 (merged 2026-11-09, "display audio on by default, ELD
  names, J616s DCPEXT1 audio"), `t6040-j616s-dpaudio.dtsi`: `apple,t6041-dpaudio` with
  `dmas = <&sio 0x66>` and `<&sio 0x68>` and `ps_dpa1` / `ps_dpa2`. The SIO pattern does not apply to
  the K114s, whose `dp-audio*` nodes do not point at `sio`.

K114s versus J714s: the ADT shape matches (no `dp-audio*` MMIO window, per-display ADMAC, `dp-audio1`
on `dcpext0`). So K114s display audio is a port of the J714s dpaudio nodes (`dp-audio1` on `dcpext0`,
then `dp-audio2..4`), not new driver work.

## What is left

- Check that the kernel base we build includes b8e6029323c7 and the `apple,t6050-display-admac`
  driver; if not, rebase onto it.
- Check that the loader copies the ced-ssw tunables for the K114s alias (the J714s uses the
  `admac-dispext0-control` alias).
- External display bring-up (docs/r3-display-gpu.md); display audio rides the DCP.
- Then add the K114s dpaudio nodes modelled on `t6050-j714s-dpaudio.dtsi` and verify.
- Owner: a monitor with speakers on USB-C or HDMI; expected result an ALSA/PipeWire sink and sound.
  Until then nothing to run: `cat /proc/asound/cards` shows no card, as today.
