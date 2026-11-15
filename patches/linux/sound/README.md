# Kernel patches for K114s sound (jack and microphones; no speakers)

Apply in order on the installed base (aurora-silicon/linux `a34d26c2` + betizzel/omarchy-m5
`linux-j714s-27.2.patch`, with or without the trackpad series), with `git am` or `patch -Np1`:

    git am patches/linux/sound/000*.patch

Each file is `git format-patch` output with the original author, date and message. The note
between the `---` line and the diffstat is ours and says where the commit comes from and why it is
here; `git am` drops it.

| Patch | Origin | Author | License | Needed for |
| --- | --- | --- | --- | --- |
| `0001-ASoC-apple-macaudio-Add-K116.patch` | aurora-silicon/linux `45f4de446485`, pull request 1648 (merged 2026-11-14) | Jens Axboe | GPL-2.0 | nothing on a K114s; 0004 applies on top of it. Drop it on a base that already has #1648 |
| `0002-ASoC-tas2764-keep-the-bus-quiet-while-the-amp-is-in-.patch` | aurora-silicon/linux `ad10208a01c6`, pull request 1787 (open) | Jens Axboe | GPL-2.0 | nothing while no amp is described; kept with 0003 |
| `0003-i2c-pasemi-report-a-NACK-as-a-NACK-while-the-STOP-is.patch` | aurora-silicon/linux `48243e8f3d32`, pull request 1787 (open) | Jens Axboe | GPL-2.0 | cleaner I2C errors on every bus, the jack codec's included |
| `0004-ASoC-apple-macaudio-Add-K114-with-the-speakers-off.patch` | this repository | this repository (AI-assisted, see the trailer) | GPL-2.0 | **required**: the `apple,k114-macaudio` card, jack only |

Only 0004 changes what the K114s does. It is written on top of 0001 (their lines are neighbours)
and does not apply without it on this base. All three patched files build as modules in the
installed configuration (`snd-soc-macaudio`, `snd-soc-tas2764`, `i2c-pasemi-core`), so none of
them needs a new kernel image by itself.

Not here, on purpose: the other four sound commits of pull request 1648 (`dac02289da54`,
`f25b8eb19c92`, `7e584a680b77`, `8f5a2223fd3a`). They change `t6050-k116s.dts`, do not apply on
this base without the rest of that pull request, and `7e584a680b77` carries the K116s's own PMP
values. They are the source of `dts/t6050-k114s-sound.dtsi`, which names them.

Checked (agent-run, 2026-11-14, clang 23.1.3): the series applies cleanly with `git am`;
`macaudio.o`, `tas2764.o`, `i2c-pasemi-core.o` and `i2c-pasemi-platform.o` build with `W=1` and no
warnings; the five `apple-speaker-*` KUnit suites (59 cases) pass under QEMU; the admission case
fails when the K114 entry's `enable_speakers` is set to true. None of this has run on a K114s.
