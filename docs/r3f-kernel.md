# r3f: the K114s kernel on aurora-silicon/linux `main` `4abf0f83`

Status 2026-11-24: **r3f is Main (the default), and r3e1 is Backup.** Its one-shot trial (23:49Z) gave `R3F-CHECK: PASS`
(every gate, including a 5 s camera stream with the indicator, 0 Oops/WARNING lines, 0 new error lines, video decode 3/3)
and it was promoted. On that boot: EDR on at the owner's 1200-nit cap (headroom 16, four HDR lines in the EDID), and
CLPC still registers `apple-clpc` with low-power, balanced and performance, so #3090 did not cost the K114s its profile.
The text below records the build: r3f is r3e1 rebased onto the newest upstream `main`,
with upstream's panel HDR value (#2694) in place of our 500-nit EDR cap (the owner's decision, 2026-11-24: "Use
upstream's value"). It was built for a one-shot trial in the Backup slot (`linux-k114s-r3b`, which held r3e), with
r3e1 as Main and the way back. The speakers stay off. Deep sleep stays compiled out (`CONFIG_APPLE_SOC_SLEEP` off), as
in r3d and r3e. Evidence labels as in [r3d-kernel.md](r3d-kernel.md): **agent-run**, **emulator/replica**,
**upstream-reported**.

## 1. What r3f is

| | r3e1 (Main until 2026-11-24; now Backup) | r3f (now Main) |
| --- | --- | --- |
| Base | aurora-silicon/linux `main` `c3369f4855e9` | aurora-silicon/linux `main` `4abf0f83c290fd7275d44b09dc490e34b405749b` (Merge of #2559, 144 commits after `c3369f48`: 96 of them not merges) |
| Series | `patches/linux/r3e1.series`: 76 patches | `patches/linux/r3f.series`: 74 patches (`patches/linux/r3f/`) |
| Release | `7.3.0-17.v272-18-k114s-r3e1-ARCH` | `7.3.0-17.v272-18-k114s-r3f-ARCH` (label `K114S-R3F`) |
| Package | `linux-k114s 7.3.0.r3e1-1` | `linux-k114s-r3b 7.3.0.r3f-1`: staged in the Backup slot, replacing r3e there (`vercmp`: `r3f` is newer than `r3e`); Main since its promotion |

The 76 r3e1 patches became: **72 kept as they were, 2 re-cut onto #2694, 2 dropped**. `git range-diff` of the r3e1 branch
against the r3f branch shows exactly that. The 72 kept patches are r3e's own text under their new numbers, and the 2 re-cuts are
fresh `git format-patch` output. The series was applied again to a clean `4abf0f83c29` with `git am --3way` and
gives the same git tree (`17e2bbc3385d`) as the tree that was built (agent-run).

## 2. Disposition of the r3e1 patches

The r3f number is the patch's place in `r3f.series`. r3e `0001`-`0018` keep their numbers; `0020`-`0022` become
`0019`-`0021`; `0024`-`0076` become `0022`-`0074`.

| r3e | Patch | Outcome | Upstream commit / reason |
| --- | --- | --- | --- |
| 0017 | drm/apple: describe an internal panel without a known gamut as Display P3 | re-cut (r3f 0017) | #2694 changed the `dcp_panel_read_adt()` lines next to it: the Display P3 lines stay and #2694's unconditional `edr_ceiling` read goes with them (see section 3) |
| 0018 | drm/apple: cap the panel peak a firmware 27 panel's EDR may use | re-cut (r3f 0018) | same spot: the parameter `fw27_panel_edr_max_nits` (read-only, **default 0**, no cap) and `dcp_edr_peak()` are kept, now inside #2694's `if (dcp->panel.edr_ceiling && ...)` |
| 0019 | drm/apple: K114s: no panel EDR above 500 nits by default | **dropped** | the owner's decision, 2026-11-24: use upstream's EDR value (section 3). The only line it changed is `fw27_panel_edr_max_nits = 500;` and its description |
| 0023 | mfd: macsmc: count a port's dark wake on every board with a sleep policy | **dropped** | `af97a52c0a5` (Jens Axboe, same subject): #2559 merged (merge `4abf0f83c29`); our patch and that commit have equal patch-ids |
| other 72 | | kept | applied with `git am --3way` and no hand edit |

The kept patches include all the K114s-specific ones: `0014` (the K114 sound card, **speakers off**; its refusals and
admission test are untouched), `0020` and `0063`/`0064` (`sep`), `0021` (the 193-byte AOP calibration), `0016` (the
brightness floor), `0017` (Display P3), `0019` (no EDR with a cap set and the SDR maximum unknown), `0073` (the camera
without a described light) and `0074` (the small camera indicator under the notch; `dcp-indicator-test.c` passes as a plain
program: 11 cases, 0 failed, agent-run).

Open pull requests r3e carried (#2877, #2631, #2201, #2070, #2798, the drafts) are unchanged on `main`: none merged since
r3e, so no further patch drops out. `git am` found no other patch whose subject or patch-id matches a new upstream commit.

## 3. The panel HDR decision: upstream's value (#2694)

Upstream #2694 ("panel/edr-from-adt-headroom", merge `065904c137f`, commits `46ff84f8d7e` and `ced0f429efa`) decides
whether an internal panel has HDR from the machine: the ADT backlight node's `EDRPotentialHeadroom` above 1.0. The ceiling
is now read on every firmware (`dcp->panel.edr_ceiling = dcp_edr_ceiling(...)`, no `desktop || fw 27.0` condition). A
panel without one gets no peak, no PQ in its EDID-equivalent metadata and no `Colorspace` / `HDR_OUTPUT_METADATA`
properties (`dcp_panel_edr()` replaces `dcp_fw_compat_panel_edr()`; `dcp_fw_swap_has_edr()` keeps the firmware check for the
swap interface). The firmware 27 peak is the ADT's `LmaxProduct`, taken only above the SDR maximum.

**What r3f changes, exactly.** r3e1 had `static unsigned int fw27_panel_edr_max_nits = 500;` (r3e `0019`), which, with the
panel's SDR maximum of 1000 nits, left no EDR headroom: no PQ in the EDID, PQ commits refused. r3f drops that patch. The
line is now `static unsigned int fw27_panel_edr_max_nits;` (default 0, "the panel's own peak"; the parameter still exists and
can lower the peak by hand, `modinfo -F parm appledrm` shows `(default: 0)`). With #2694 and the K114s ADT (peak 2000 nits,
EDR potential headroom 16, from the r3e notes) the panel offers EDR, advertises PQ and the HDR connector properties, and a PQ frame
ramps the panel towards the cap in force: 1200 nits on this Mac while `/etc/modprobe.d/k114s-edr-cap.conf` stands (see
below), the panel's own 2000-nit peak without it. PQ content has been shown on this OLED only up to a 1200-nit
cap (owner-observed 2026-11-16, [r3-hdr.md](r3-hdr.md) sections 8 and 9), never at the full 2000-nit peak.

**On this Mac r3f runs at 1200 nits** (the trial did, and Main does). The managed HDR default, `/etc/modprobe.d/k114s-edr-cap.conf`
(`linux/display/k114s-edr-cap`), sets `options appledrm fw27_panel_edr_max_nits=1200`, and it applies to r3f as it did to
r3e1. The owner chose that cap on 2026-11-16, and the 2026-11-24 decision was about the kernel's own default, so the
override stays (a reversible default; `sudo bash linux/display/k114s-edr-cap --undo` and a reboot give the panel's own
peak). What r3f changes on this Mac is the code path: #2694 decides EDR from the ADT's headroom. The r3f check records the
parameter, the EDR kernel lines, the EDID's HDR blocks and the CLPC platform profile. A
`appledrm.fw27_panel_edr_max_nits=<n>` on the kernel command line (or `options appledrm fw27_panel_edr_max_nits=<n>` in `/etc/modprobe.d`) goes back to a cap with no rebuild.

**Kept, and not superseded by #2694:**

| Item | r3f | Why it stays |
| --- | --- | --- |
| Brightness floor | `0015`, `0016` | #2694 touches no brightness-request code |
| Display P3 for a panel with no known gamut | `0017` | #2694 changes the neighbouring EDR lines in `dcp_panel_read_adt()` only; #2798 (the same default, upstream) is still an open draft |
| The unknown-SDR EDR guard | `0019` | #2694 does not decide anything about a cap with an unknown SDR maximum. With the default 0 it is inert; it only matters when the parameter is set |
| The cap mechanism (`dcp_edr_peak()`, the parameter) | `0018` | the guard above and the KUnit cases depend on it. It is the opt-in way back to a lower peak |

Nothing of ours is superseded by #2694. `dcp_edr_peak(adt_peak, sdr_max, 0)` and #2694's `peak > brightness.maximum &&
peak <= 10000` give the same peak for the same inputs (checked by reading both, not run).

## 4. New upstream since r3e (now in the r3f base)

144 commits (96 not merges) after `c3369f48`. The ones that matter for a K114s, in what the commit messages say (read, not
run on this Mac):

| PR | What | For the K114s |
| --- | --- | --- |
| #3078 (`f2cff432dfc`) | **G17 MMU:** `drm/asahi: mmu: skip healthy last-job VM drain on all GPUs`. The healthy last-job release fast path (added for M5 VMs) was gated on `vm.m5`; it now runs on every GPU generation | no change for the K114s: its VMs are M5 and already took the fast path. It matters for the G15/G16/other G17 GPUs |
| #2759 (`a9b4b113c7a`) | **T6050 adopt target speed:** a port Linux trains itself takes its target link speed from the root port's `max-link-speed` (default stays 8 GT/s without the property), and an adopted boot-trained link is accepted up to the root port's own target speed instead of a fixed 8 GT/s | no K114s DT carries `max-link-speed`, and the N1 is 8 GT/s, so nothing changes until the Stage 2 tree publishes it. The adopted-link and s2idle paths (#2488, #2729, in r3e) are the code this edits |
| #2936 (`7a95696ca57`) | **AOP IIO:** `aop_devmotion` writes the whole buffer scan; `aop_motion` frees its IIO device with the device's resources | the K114s describes the AOP (r3f 0068) with its motion sensors; the light-sensor path (`0021`) is untouched |
| #2943 (`94ecc40594d`) | **bcm4377 ring index:** the Bluetooth transfer ring's producer index stays on the host, an event's footer payload is bounded by the footer; adds KUnit and a selftest | a robustness fix in `hci_bcm4377`; whether the K114s's N1 Bluetooth (`n1_beta`) runs this driver was not checked |
| #2694 (`065904c137f`) | **EDR from ADT headroom** | section 3 |
| #3090 (`3f500da587a`) | CLPC: no 64 % fallback ceiling, no 10 Hz idle poll, stricter PMC check; the binding now says a standalone `apple,clpc` node with neither `apple,low-power-frequency-max-mhz` nor `apple,high-power-mode` **registers no platform profile** | the K114s DT sets neither (only the J714s and K116s set `apple,high-power-mode`), so the K114s probably has **no low-power platform profile** now, where r3e derived a ceiling from the cluster tables. Not run; to check in the trial (the CLPC and platform-profile lines in the boot log) |
| #2437 (`4f63cd72f54`) | `drm/asahi: g17: M5: drop the unreachable EAGAIN retry of a host-port submission` | the K114s GPU path; the removed branch was unreachable by the message |
| #2498 (`0c1f7e70778`) | HDMI: a mode set waits until the DCP has the display plugged in | only an output with an HDMI port; our `0011` (T6050 HDMI flips) applied unchanged |
| #3076 (`10112d81a84`) | DCP v26.6 desktop: brightness correction for CTM commits; XRGB2101010 premultiplied on primary planes | the XRGB2101010 change is in the common plane code |
| #3091 (`645f7cd3589`) | revert of #3075 (the G14 27.2 GPU's full performance-state range) | not a K114s GPU |
| #2594, #2178, #2486, #2691 | T8152 and M4 Pro USB4 and tipd (`thunderbolt: apple`, ACIO DARTs, ...) | other SoCs |
| #2533, #2325, #2428 | T8132 PMP, T8142 media (Neural Engine, encoder, JPEG on every M5), ProRes node descriptions | the T8142 DT is another SoC; the T6050 media is ours, `0069`-`0072` |
| #2881 | AVD `bus_info` | the decoder, not in the K114s tree's boot path |
| #2928-#2933, #2941, #2942, #2956, #2957, #2821 | KUnit suites (efuses, DWI backlight, pmgr fabric, cio-reset, dockchannel, dockchannel UART, rtkit-helper, EDAC, regview, dbgview, CLPC policy) | no runtime change; KUnit is not built into the K114s config |
| #2156 | the system-Mesa handoff of `aurora-sep` / `mesa-m3` | not the K114s kernel |

## 5. Build and checks

    REPO=~/Developer/Personal/Projects/omarchy-m5p-oled               # this repository
    git worktree add -b r3f ~/k114s-build/src/r3f 4abf0f83c290fd7275d44b09dc490e34b405749b   # main at the time; run in a linux clone
    cd ~/k114s-build/src/r3f
    grep -v '^#' "$REPO/patches/linux/r3f.series" | grep . | while read p; do git am --3way "$REPO/patches/linux/$p"; done
    printf -- '-17.v272-18-k114s-r3f' > localversion.10-pkgrel
    mkdir -p ~/k114s-build/out/r3f && cp ~/k114s-build/out/r3e1/.config ~/k114s-build/out/r3f/.config      # then: kmake O=... olddefconfig (no change)
    K114S_LABEL=K114S-R3F kmake O=~/k114s-build/out/r3f -j16 Image modules dtbs

| Check | Result | Label |
| --- | --- | --- |
| Build (clang 23.1.3, Rust 1.98.1) | about 4 minutes; `Image` 54,413,824 bytes, sha256 `08fc9eabe14b1b5b96a51c92e2082dfc487748cf72b07d55f1155e22d4c334ce`; 74 commits on `main` | agent-run |
| `olddefconfig` on r3e1's `.config` | "No change to .config": no new option asked for | agent-run |
| `build/validate-config.py` with `k114s-required.config` and `k114s-r3.config` | pass: 385 requirements, 0 not met, 21 built in where a module was requested | agent-run |
| QEMU `k114s-qemu-smoke shell` | PASS, `7.3.0-17.v272-18-k114s-r3f-ARCH` | emulator/replica |
| QEMU, every module | `ok=1966 failed=7`: the same seven as r3d, r3e and every earlier kernel (tcrypt ipmi_si cppc_cpufreq sun50i-cpufreq-nvmem stratix10-soc apple-pmp-j613-hwmon xen-pciback) | emulator/replica |
| `dcp-indicator-test.c` as a plain program | 11 cases ok, 0 not ok | agent-run |
| `check-package.sh` on the real package, against `linux-aurora` and against `linux-k114s` (r3e1) | both: all passed (23 checks, 1973 modules with the release's vermagic, `depmod -a -e` clean) | agent-run |
| The PKGBUILD's r3f source guard | pass: brightness floor, Display P3, unknown-SDR EDR guard, **no 500-nit cap** (the parameter's default is 0), #2694's `dcp_panel_edr()`, `dcp_fw_swap_has_edr()` and its unconditional `edr_ceiling`, #2559's dark-wake count, battery-date fix, light-sensor blob, `main`'s adopted-link predicate with `adopt_link` on `t6050_hw`, #2817's NVRAM path with no K114s row, no `nvram` partition in the K114s DT, `apple,k114-macaudio`, the 26B8125 G17S entry exactly once, `apple,camera-light-undescribed`, the small indicator | agent-run |
| `build/check-publishable.sh` | ok (795 files) | agent-run |

Warnings: compiler warnings in code from upstream only (Rust dead-code lints, as in r3e).

## 6. Packaging

`PKGBUILD` got an `r3f` case (`linux-k114s-r3b`, `7.3.0.r3f-1`: `pkgname linux-k114s-r3b`, `_kcand r3f`, `_ver r3f`) and the
r3f source guard above. `check-package.sh` knows the `-k114s-r3f-ARCH` release (want `linux-k114s-r3b`) and checks that
`fw27_panel_edr_max_nits` defaults to 0 instead of 500. The r3e1 and older checks stay. To package:
`K114S_CAND=r3f makepkg -f --nodeps --skipinteg` with `K114S_SRC=$B/src/r3f K114S_OUT=$B/out/r3f`. The package built for
this document: `~/k114s-build/build/pkg-r3f.IsPVg3/d/linux-k114s-r3b-7.3.0.r3f-1-aarch64.pkg.tar.xz` (sha256 `757ecb5f99099cb41e08e9c61f900c97fc9124e20adfb2ec8f9c5e74e1694004`; `32,572,828` bytes).

## 7. Mesa (built with the kernel, not part of it)

`mesa-aurora` and `vulkan-aurora` at aurora-silicon/mesa `aurora-wip` `89472d5e832` (Merge of #726, 70 commits after
r3e1's pairing `886a7732455`), without the omacom M3/G15 carries (#415, #416), as `mesa-886a773` was built: the same
PKGBUILD with `pkgver` `26.3.0_devel.20261124.233311.89472d5e832` (UTC date of the head, `git rev-list --count` 233311,
11-character sha) and `_commit` moved, the source the local clone, `makepkg -e` over a prepared `src/mesa-k114s` worktree.
`meson test`: **252 ok, 0 fail**. Packages (epoch 1, `-1`): `~/k114s-build/build/mesa-89472d5.0EQu5z/mesa-aurora-1:26.3.0_devel.20261124.233311.89472d5e832-1-aarch64.pkg.tar.xz` (sha256 `c10baafe…`) and `…/vulkan-aurora-1:26.3.0_devel.20261124.233311.89472d5e832-1-aarch64.pkg.tar.xz` (sha256 `4b02898d…`). Installed after its guarded test boot passed on 2026-11-24 (agent-run; [r3-package-batch.md](r3-package-batch.md)).

## 8. Left for later

- Done 2026-11-24: staged into the Backup slot, tried by a one-shot (23:49Z, `R3F-CHECK: PASS`) and promoted (see the
  status at the top). The trial recorded EDR on at the 1200-nit cap, HDR blocks in the EDID and the CLPC profiles intact.
- Still open: the panel's own 2000-nit peak (needs the 1200-nit override removed) and a validated PQ picture
  ([r3-hdr.md](r3-hdr.md) and linux#2060); VRR stays masked ([r3-vrr.md](r3-vrr.md), linux#3107).
- The r3e and r3e1 series (`r3e.series`, `r3e1.series`, `r3e/`) stay in the repository: they are the booted kernels' record.
