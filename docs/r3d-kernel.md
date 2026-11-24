# r3d: the K114s kernel on integration/aurora `0bbe021a`, with the open sleep, display and device-tree PRs

Status 2026-11-24: **built, packaged, emulator-tested; not booted on the K114s.** The owner asked to "look across all
repos we are tracking to get this device on the latest known code and fixes" (intake 2026-11-24). The answers: update
the packages, the kernel and the loader; take every relevant open PR, drafts included; run unattended one-shot trials,
and promote a trial that passes every check without asking; post test reports and PRs upstream. The speakers stay
off. Evidence labels: **agent-run**, **emulator/replica**, **upstream-reported**.

## 1. What r3d is

| | r3c-upstream (the default since 2026-11-18) | r3d |
| --- | --- | --- |
| Base | aurora-silicon/linux `677be395` | integration/aurora `0bbe021a28bd` (1342 commits later) |
| Series | betizzel v272-18 + `r3c.series` + `r3c-upstream.series` | `patches/linux/r3d.series`: 93 patches |
| Release | `7.3.0-17.v272-18-k114s-r3c-upstream-ARCH` | `7.3.0-17.v272-18-k114s-r3d-ARCH` |
| Package | `linux-k114s-r3b 7.3.0.r3c.upstream-1` | `linux-k114s 7.3.0.r3d-1`, replacing the original r3c in that slot |

r3c-upstream keeps its slot and stays the way back. The ESP has room for two kernel images, not three.

### Merged upstream since `677be395` (now in the base)

These were open or new at the last sweep:
- #2664 (combo PHY power across s2idle) and #2177 (the T6050 sleep power word).
- #2330 (the Bluetooth transport by PCIe host) and #2873 (external displays when iBoot lit nothing).
- #2561 (the camera indicator) and #2568 (the MTP DART streams).
- #2445, #2167 and #2231 (dark wakes and the SMC reply drain).
- These replace patches we carried: #2113 and #2117 (our `r3c-upstream`), #1983 (the light-sensor driver part of our
  `r3c/0004`) and #1568 (`r3b/0003`, `0004`).

### How the 47 old patches landed

A first pass applied each patch with `git am --3way` on the new base: 19 applied, 2 were already in it, and 26
conflicted. Each conflict was triaged by a worker and checked by a fresh reviewer (agent-run; the verdicts are in the
build records).

| Outcome | Patches |
| --- | --- |
| Re-cut onto the new base (the message ends "[re-cut onto integration/aurora 0bbe021a for the K114s]") | betizzel 0001 and 0005 (the 27.2 G17S GPU firmware: without them the GPU refuses this Mac's firmware), 0007, 0009, 0011, 0012, 0014, 0015, 0018; ours `sound/0004` (the K114 card with the speakers off: every refusal and the admission test kept), `sep/0001`, `hdr/0002`-`0004` |
| Already upstream, dropped | betizzel 0008, 0016, 0019-0023; ours `r3c-upstream/0001` (#2113), `0003` (#2117) |
| Upstream as applied, so the patch left no commit | `r3b/0003`, `0004`, `r3c/0002`, `r3c-upstream/0002`, `brightness/0001`, `0003` |
| Obsolete here, dropped | betizzel 0004 (the firmware 27.3 IOMFB table: this Mac's display firmware is 27.2), 0006, 0010 (a J714s-only mode) |

### Open PRs added

| PR | What | How |
| --- | --- | --- |
| #2559, #2877, #2187 | a port's dark wake counted on every board; Wi-Fi keep-alive sleep hardening; J716c external displays and display sleep on 27.2 | applied as is |
| #2282, #2281, #2276, #2540 (drafts but #2540) | shared trees: keyboard backlight, SMC fans and sensors, the GPU, the system-cache controller | applied as is |
| #2488, #2729 (draft) | adopted PCIe links kept across s2idle on every adopted host; an adopted-link sleep refused in prepare | re-cut on our `r3c/0001` (#2488 removes the board list that `r3c/0001` extended) |
| #2201, #2070 | firmware-driven deep sleep on the K116s (32 of 35 commits; 3 were in the base) and the deep-sleep refusal at `.prepare` | re-cut; #2070 now takes "known" from the selected method table, as its review asked, so it cannot refuse a 27.2 K116s or K114s |
| #2631 | the SEP profile chosen by the SoC | re-cut; our `sep/0001` stays and is now redundant |
| #2280, #2275, #2285, #2278, #2293 (all but #2275 drafts) | shared trees: the K boards' N1 and USB-C ports, the camera, the AOP, the media engines, the Neural Engine | re-cut. #2285's K114s hunk is left out: `t6050-aop.dtsi` would enable `aop_audio` with the speaker DMA channels on `apple,k114s` |

Not taken: #2298 and #2536 (speakers behind the protection lease; no protection data exists for this model, AID49),
#2817 (NVRAM writes by partition; it conflicts with our `r3c/0005`-`0007`), #2329 (T8142).

Deep sleep is compiled out, as on r3c (`CONFIG_APPLE_SOC_SLEEP` off). The owner's rule from 2026-11-17 stands:
deep sleep only if suspend-to-idle drains more than about 2% an hour.

## 2. Build and checks

    # a clone of aurora-silicon/linux
    git checkout -b r3d 0bbe021a28bd563905364d42162c75754ee4ae39
    grep -v '^#' patches/linux/r3d.series | grep . | while read p; do git am --3way patches/linux/$p; done
    printf -- '-17.v272-18-k114s-r3d' > localversion.10-pkgrel
    cp $RECIPE/installer/recipes/linux-aurora-j714s/config $O/.config
    scripts/kconfig/merge_config.sh -m -O $O $O/.config patches/linux/config/k114s-r3.config; kmake O=$O olddefconfig
    K114S_LABEL=K114S-R3D kmake O=$O -j16 Image modules dtbs

| Check | Result | Label |
| --- | --- | --- |
| Build (clang 23.1.3, Rust 1.98.1) | 398 s; `Image` 54,413,824 bytes, sha256 `196d770cb8e974961494bd5ac204be82e85997543fc08bf25347f35fd1db2df8` | agent-run |
| `build/validate-config.py` with `k114s-required.config` and `k114s-r3.config` | pass: 385 requirements, 0 not met | agent-run |
| The recipe's `validate-config.py` with `j714s-required.config` | exit 0 | agent-run |
| QEMU `k114s-qemu-smoke shell` | PASS, `7.3.0-17.v272-18-k114s-r3d-ARCH` | emulator/replica |
| QEMU, every module | `ok=1966 failed=7`, the same seven as every earlier kernel | emulator/replica |
| `check-package.sh` (with the build's `Module.symvers`) | all passed. For r3d it also checks that apple-sep picks the T6050 profile by SoC (#2631), not by the `apple,k114s` string | agent-run |
| The PKGBUILD's r3d source guard | the tree carries the brightness floor, the 500-nit EDR cap, Display P3, the unknown-SDR EDR guard, the battery-date fix, the light-sensor blob, the K114s NVRAM row, #2488's adopted-link test, the `apple,k114-macaudio` card and the 27.2 GPU firmware entry | agent-run |

## 3. The trial

- **Stage 2:** the kernel trial keeps the configured Stage 2 and its tree. The new shared trees reach the Mac only
  through a later Stage 2 trial.
- **Install:** the package replaces the original r3c in the `linux-k114s` slot. That image is archived off the ESP
  first.
- **Boot:** a Limine one-shot boots `Omarchy/linux-k114s` once. The default stays r3c-upstream, so a hang is
  followed by the proven boot. The trial watchdog does not arm on this Mac, so a hung trial waits for a long
  power-button press.
- **Gates:** the speaker gate, the cards and the microphone, video decode, Touch ID, Wi-Fi, Bluetooth, the battery,
  the GPU desktop at 10-bit Display P3 and 120 Hz, the light sensor, the NVRAM read path, and P9.
- **Promotion:** a trial that passes every gate is promoted without asking (the owner's choice). The default becomes
  `Omarchy/linux-k114s`, and P9's pins follow it.
