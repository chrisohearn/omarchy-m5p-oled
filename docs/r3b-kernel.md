# r3b: the K114s kernel candidate on the shared M5 series

2026-11-15. Worker key `r3b`. Evidence labels: **agent-run** (run on this Mac or in its build area),
**emulator/replica** (QEMU, stand-in trees), **read from source** (code or text read, not provoked),
**upstream-reported** (what a pull request or release text says; not checked here). Nothing built for
r3b has run on the K114s hardware and nothing is installed. The root step list is still the r3a runbook
(`docs/r3-integration.md`, section 8), which this document does not change.

## 1. What r3b is, and what it adds over r3a

r3a was built on our own base: aurora-silicon/linux `a34d26c2` + betizzel's 19 patches (v272-4) +
`pr1568.patch` + 20 patches of ours. r3b is built on betizzel's current shared series instead
(issue #12 of betizzel/omarchy-m5: they own the shared T6050 and M5 kernel series, we add only what is
specific to the K114s): their v272-11 (release `omarchy-j714s-6`, aurora-silicon/linux `a5ebec5f` +
their 32 patches), plus six K114s-only patches, the same configuration delta, and the K114s device
trees.

| | r3a | r3b |
| --- | --- | --- |
| Base | aurora-silicon/linux `a34d26c2` + 19 patches (v272-4) | aurora-silicon/linux `a5ebec5f` + 32 patches (v272-11); against `a34d26c2` alone that is 307 files, +22,788 and -1,813 lines |
| Ours on top | `pr1568.patch` + 20 patches + config delta | 4 trackpad commits + 2 K114s patches + the config delta (239 options) |
| Release | `7.3.0-17.v272-4-k114s-r3a-ARCH` | `7.3.0-17.v272-11-k114s-r3b-ARCH` |
| Package | `linux-k114s 7.3.0.r3a-2` | `linux-k114s 7.3.0.r3b-1` |
| What r3b has that r3a lacks | | everything in v272-11 since v272-4: DP audio, the J714s dock work, HDMI, ANE 27.2, GPU fixes, fan control and CPU thermal limit (J714s nodes, section 6), the GPU mailboxes by interrupt in full (section 3, risk 1), the base's own 120 Hz mode gate and PMP power domains |
| What r3a has that r3b lacks | | the T6050-generic patches v272-11 does not have (section 7: the eDP connector, the battery fix, two speaker-bus fixes) and the K116s-only ones. Consequence for the lid, section 3, risk 2 |

Not part of either: `patches/linux/brightness/`, `display-gpu/0001`, `0002`, `0007`, `0008` and
`sleep-lid/0010` were not in r3a, and none is in r3b (`sleep-lid/0010` is in the base now, see below).

## 2. The base: v272-11, verified against the recipe

Recipe: betizzel/omarchy-m5 at tag `omarchy-j714s-6` (commit `f9a972112552`), `installer/recipes/linux-aurora-j714s`
(PKGBUILD `pkgrel=11`, `_aurorarel=17.v272`) and `patches/j714s-27.2/linux` 0001 to 0032. The README of that
directory names the base: aurora-silicon/linux `integration/aurora` at `a5ebec5fd092` (agent-run, read from
source). Every check below was run here:

| Check | Result |
| --- | --- |
| The nine `sha256sums` of the PKGBUILD against the files at that tag (validate-config.py, configure.sh, rust-toolchain.toml, bindgen-kernel.py, `config`, `linux-j714s-27.2.patch`, j714s-required.config, speakersafetyd-hold.conf) and against the tarball it downloads (`linux-a5ebec5fd092...tar.gz`, `6789feab89c7...`) | all nine equal |
| `git archive` of `a5ebec5f` against the unpacked tarball | identical (`diff -r`) |
| The recipe's way (`patch -Np1 < linux-j714s-27.2.patch` on the tarball, then `localversion.10-pkgrel`) against the 32 files of `patches/j714s-27.2/linux` applied one by one with `git am` | identical trees, apart from `localversion.10-pkgrel` (git tree of the 32-commit result `674e3eeeeef7`) |
| Kernel release of the recipe's PKGBUILD | `7.3.0-17.v272-11-ARCH` (`echo "-$_aurorarel-$pkgrel"`) |
| The release notes' kernel line (`7.3.0-17.v272-11-ARCH`, `linux-aurora 7.3.0.aurora17.v272-11`, `a5ebec5f`) | agrees |

The recipe builds its configuration by `cp config; olddefconfig; validate-config.py j714s-required.config`
(the PKGBUILD's `prepare()`), not by `configure.sh`'s asahi.config merge. r3b does the same.

## 3. Decisions for every r3a patch

Evidence per row: **reverse** is `git apply --check -R` against the v272-11 tree (the patch is already
applied there); **forward** is `git apply --check` against it (it applies, so it is missing); **log** is
`git log --grep` of the subject on `a5ebec5f`; **lines** is every added line of the patch looked up in the file it
changes. All agent-run.

| r3a patch | Decision | Evidence |
| --- | --- | --- |
| `pr1568.patch` (4 commits of #1568, head `1e065585`) | **still needed, replaced by the current cut of the same fix** (`r3b/0001` to `0004`), section 4 | forward fails: 2 of 4 hunks of `hid-magicmouse.c` do not apply on `a5ebec5f`. Its commit 1 (clamp) overlaps `07687621d1` (#1830) already in the base; its commit 2 (not a direct device) is in the base as `magicmouse_setup_input_mtp()` (`a68b43218e`, #1830) |
| `sleep-lid/0001` (K116s admitted to s2idle, #1647) | **not needed on a K114s**, not carried | forward applies, so it is missing; it admits `apple,k116s` only |
| `sleep-lid/0002` (devices below a kernel-trained port may leave D0, #1647) | **not needed on a K114s**, not carried | it exists for the K116s's second, kernel-trained port (SD reader). No tree of this repository enables the K114s SD reader (`dts/t6050-k114s-sd.dtsi` is a draft, included nowhere). Needed again only if that draft is enabled |
| `sleep-lid/0003` (K114s admitted to s2idle) | **still needed**, re-cut to apply without 0001 and 0002: `r3b/0005` | forward fails and reverse fails (context from 0001/0002); the K114c is already admitted in the base, the K114s is not (`apple_pcie_check_adopted_s2idle`) |
| `sleep-lid/0004`, `0005`, `0006` (#1688: eDP connector for a boot framebuffer marked `apple,internal-panel`; the K114/K116 dtsi line; binding) | **T6050-generic, missing, not needed to boot: send to betizzel** (section 7) | forward applies, reverse fails, no log hit |
| `sleep-lid/0007` (#1615: unreadable battery manufacture date) | **T6050-generic, missing: send to betizzel** | forward applies; log none. It makes an unreadable manufacture date return `-ENODATA`, which the power-supply core skips. Observed on this K114s: 30 `manufacture_year ... -95` lines in five minutes (`docs/r3-sleep-lid.md`) |
| `sleep-lid/0008` (PMP power domains always on, #1789) | **in v272-11** (their 0028, same patch) | reverse applies cleanly; all 8 added lines present |
| `sleep-lid/0009` (GPU mailbox receive by interrupt, `41c359da`, #1844) | **in v272-11** | log: merge `adb5a7e344` of #1844, commits `41c359da81` and `788441e089` are in the history. See risk 1 |
| `display-gpu/0003` to `0006` (#1868: 120 Hz-only T6050 internal panel modes) | **in v272-11**, in upstream's merged shape | log: merge `1177fdf5f9` (#1868), `3176918ba2`, `84b3b93c04`, `10f14b7ff8`. The base scopes the gate with `dcp->hw.only_120hz_modes`, our `0006` did it with an fw-compat test: same behaviour, different lines (`0006` reverse applies; `0003` to `0005` differ in a few comment and condition lines only) |
| `display-gpu/0009`, `0010` (bindings) | **in v272-11** | reverse applies; log `3adc985b5a`, `8f418a490a` |
| `sound/0001` (macaudio K116) | **in v272-11** | reverse applies; log `45f4de4464` |
| `sound/0002` (tas2764: quiet bus while the amp is in reset) | **T6050/Apple-generic, missing: send to betizzel** | forward applies; speakers stay off in every r3 tree, so the K114s does not need it to boot |
| `sound/0003` (i2c-pasemi: report a NACK as a NACK) | **generic, missing: send to betizzel** | same |
| `sound/0004` (macaudio K114, speakers off) | **still needed, K114s-only**, taken unchanged | forward applies; nothing in the base names the K114 in macaudio |
| `usb/0001` (tipd async probe) | **in v272-11** | reverse applies; log `218e3f8550` |

The other "r3" series of this repository (`patches/linux/brightness/`, `display-gpu/0001`, `0002`, `0007`,
`0008`) were not in r3a and are not in r3b. `display-gpu/0007`, `0008` are `sleep-lid/0004`, `0005`.

`patches/linux/r3b.series` lists what r3b applies, in order: `r3b/0001` to `0004`, `sound/0004`, `r3b/0005`.
The files in `patches/linux/r3b/` are `git format-patch` output (the first line is zeroed as in the other series
directories). Reproduced from the repository files alone onto a fresh checkout of the base: the same tree as
the built one, git tree `3ad64f0fbcdadcb34ec5dd001160bf30c15b1570` (agent-run).

### Risks the base brings (read from source)

1. **GPU mailbox receive is interrupt-only in v272-11.** The base contains `788441e089`, which is r3a's
   `sleep-lid/0010`. r3a left it out on purpose (the GPU Stage 2 trial on this Mac receives by polling and
   no GPU interrupt had been seen on a 14-inch T6050; `docs/r3-integration.md`, section 2). On r3b, the
   `ascwrap-v6` mailboxes of `dts/t6050-k114s-display-gpu.dtsi` receive by interrupt and the poller is gone.
   The K114s tree lists the interrupts (`send-empty` 2797/2801, `recv-not-empty` 2800/2804) and they match
   this Mac's Apple device tree (agent-run: `tests/k114s-adt-display-facts.py`, PASS). The J714s, also a
   14-inch M5 Pro, boots its GPU this way in release 6 (upstream-reported). The session guard now keeps the desktop on the CPU on any r3 kernel without that release's own opt-in (section 9). Not seen on a K114s: the r3a
   runbook's step G (the kernel on the GPU tree) is therefore a different test on r3b, and the GPU trial
   already running on this Mac (r1 kernel, polling) says nothing about it.
2. **The lid.** r3b does not carry `sleep-lid/0004` to `0006`, so the boot framebuffer's connector stays
   `Unknown-1` and `apple,internal-panel` in `dts/t6050-k114s-sleep.dtsi` has no effect (it did not break
   anything before: "a kernel without `1006491a` ignores it"). The lid-close steps of the runbook that expect
   `eDP-1` cannot pass on r3b as it is. Everything else about s2idle is carried (`r3b/0005`, and the base has
   the PMP domains and the mailbox interrupts). If the lead wants the r3a lid behaviour before betizzel takes
   #1688, `sleep-lid/0004` to `0007` and `sound/0002`, `0003` apply cleanly on top of r3b in this order
   (agent-run, `git am`, six commits, no fuzz). That would be carried and marked "to be upstreamed".
3. **The trackpad series is not booted at these heads** (next section).
4. Build warnings (clang `-Wthread-safety-analysis`) in `drivers/nvme/host/apple.c` and
   `drivers/bluetooth/mt7932_bt_pcie.c`: upstream code in the base, not touched by r3b. No warning in any file
   r3b changes.

## 4. The trackpad

The K114s reports HID product `0x0361` and the same "invalid report_size 524288" as the K114c. r1 and r3a use
#1568 and the owner saw the trackpad work (`README.md`). At `a5ebec5f` the base already has #1830 (Jens Axboe:
`dchid_parse()` clamp `07687621d1`, and the K116s Trackpad26 parser `a68b43218e`, gated on product `0x0362`), so
the old `pr1568.patch` does not apply any more.

Before this build, joshuaswarren re-cut the work on 2026-11-15 on top of #1830 (upstream-reported): #1568 became a
single commit, the clamp moved to #1737 (two commits), and the GD Mouse commit became #2011. They apply to
`a5ebec5f` without conflict (agent-run) and are `r3b/0001` to `0004`:

| File | Upstream | What | Against the proven r1 |
| --- | --- | --- | --- |
| `r3b/0001` | #1737 1/2, `d4b57f3332` | clamp Report Size items where the descriptor arrives (2 to 4 byte items), replaces the `dchid_parse()` clamp of #1830 | same idea as #1568 commit 1 |
| `r3b/0002` | #1737 2/2, `d43ac775b8` | pad short reports into a per-interface buffer after the clamp | **new**: not in r1; it acts on every clamped interface. Drop it first if the trackpad misbehaves |
| `r3b/0003` | #2011, `b084d5098d` | drop the GD Mouse usages on dockchannel MTP devices | the old #1568 commit 3 |
| `r3b/0004` | #1568, `f28cc1b5b2` | parse the 0x5a MTP report, taken only when the device is not a Trackpad26 one | the old #1568 commit 4 plus a `!msc->mtp_tp26` guard. The old parser lines and the new ones differ only in that guard and its braces (compared line by line, agent-run) |

On product `0x0361` the guard is true (`mtp_tp26` is set only for `0x0362`, `hid-magicmouse.c`), so the K114s takes the
parser that r1 proved. Open: nothing of this stack was booted on a Mac at these heads (the PR texts say so),
and the pad (`r3b/0002`) is new. Compiled here; the KUnit case of `0001` is not enabled in our configuration and was
not run. #1830's `0x0361` admission (the `r1a` idea in `pins/sources.json`) is not needed any more.

## 5. Configuration

Their config is `installer/recipes/linux-aurora-j714s/config`. `olddefconfig` with our toolchain changes only the
compiler lines (`CC_VERSION_TEXT`, `RUSTC_VERSION*`) and adds `CC_CAN_LINK=y`, as for r3a. It passes their
validator against `j714s-required.config` and ours (`build/validate-config.py`) against
`k114s-required.config`: 133 requirements, 0 not met (agent-run). `CONFIG_IKCONFIG=y` and `CONFIG_IKCONFIG_PROC=y`
are in it and stay.

Their v272-11 config differs from the running kernel's config (v272-4) in seven options, and all seven are ours
from r3a's list (RFCOMM, `BT_RFCOMM_TTY`, the `HL`, `RT` and `TTL` matches, PKCS8: betizzel/omarchy-m5 #9).

The delta is `patches/linux/config/k114s-r3.config`, unchanged and merged the same way as r3a
(`merge_config.sh -m`, then `olddefconfig`): **252 requirements, 13 already met (9 equal, 4 "is not set" that their
config also leaves off), 239 added**, and `validate-config.py` passes all 252 on the result. It turns nothing off
and downgrades nothing that their config has on (agent-run: every option of theirs that is set has the same value
in the result). Each option's reason and evidence label is the comment above it in the file. Per section:

| Section of `k114s-r3.config` | Lines | Already in theirs | Added | Evidence of the added ones |
| --- | --- | --- | --- | --- |
| 1 Bluetooth profiles | 5 | 2 | 3 | observed 3 (BNEP; RFCOMM is theirs now) |
| 2 Firewall: ufw's IPv6 rules | 15 | 4 | 11 | installed 11 |
| 3 Policy routing and packet marks: Tailscale | 15 | 0 | 15 | observed 10, installed 4, common 1 |
| 4 Network defaults Omarchy sets | 9 | 0 | 9 | observed 8, common 1 (BBR, fq) |
| 5 Docker and containers | 26 | 0 | 26 | installed 25, observed 1 |
| 6 Standard iptables extensions | 32 | 0 | 32 | common 32 |
| 7 VPN and tunnels | 10 | 0 | 10 | common 10 |
| 8 System services | 5 | 1 | 4 | common 3, observed 1 (PSI) |
| 9 Input devices | 81 | 0 | 81 | peripheral 79, installed 2 |
| 10 USB storage, card readers, optical drives | 4 | 0 | 4 | peripheral 4 |
| 11 File systems on removable media and the network | 26 | 2 | 24 | peripheral 18, installed 6 |
| 12 USB network adapters, phones, serial adapters | 16 | 0 | 16 | peripheral 14, common 2 |
| 13 MIDI | 5 | 0 | 5 | common 5 |
| 14 Virtual machines | 3 | 0 | 3 | common 3 |
| **Total** | **252** | **13** | **239** | |

Labels are those of the file: *observed* = the running kernel logged the failure on this K114s on 2026-11-14,
*installed* = a package installed here uses it, *peripheral* and *common* = plausible hardware and software, not
tested here (counted by the label that was last stated above each option, so the split is approximate). Only 23
of the 239 are "observed". The rest are the same convenience options r3a already carried. 195 of the 239 are modules; 44
are `y` or `n` as the fragment asks (policy routing, `PSI`, `BINFMT_MISC`, conntrack marks, CFS bandwidth and others). Decision for the
lead: carry all 239 as r3a did, or only *observed* and *installed*. The last option, "send to betizzel", fits
sections 1 to 4 (every machine on Omarchy has ufw, BBR and Tailscale rules): they are not K114s-specific. The
full per-option list with its section, label, requested and resulting values is in
`integrate/release-r3b/config-delta.txt` of the build area.

Result: 1972 modules, as in r3a.

## 6. Device trees

Built against the r3b kernel tree's includes (`build/build-r3a-dtb.sh`, dtc 1.8.1; the build script is unchanged):

| Tree | sha256 | r3a's against its kernel |
| --- | --- | --- |
| `t6050-k114s-r1` | `23207df5abe04f9bc53f004f26a5f00d2d4a8fc0918fbd321af5e21963157aff` | `2ea22d26...` (proven, a34d26c2 base) |
| `t6050-k114s-r3a` | `7b12883b2d5bb12678f3d239e5211be3e35a88cff97e383adf8144dd9435928f` | `154568fe...` |
| `t6050-k114s-r3-gpu` | `6a04f79e5447748096fae73d473a1c6cfbcf1078fac81d2997f929dc6c2497cb` | (not recorded) |

All 14 `dts/t6050-k114s-*.dts` compile (the three sound trees with the stand-in PMP tunables of the build area: emulator/replica). `tests/lint-dtb.py`
passes on all 14, `tests/lint-display-gpu-dtb.py` on r3-gpu, `tests/lint-sound-dtb.py` on the sound variant.
ADT fact checks against this Mac's Apple device tree, read from a local copy (`--adt`; nothing as root): the
display and GPU facts of the r3-gpu tree, "no comparison failed"; the parity facts of the three drafts (AVD, SD reader,
AOP sensors), "every fact holds". The replica tests of the checkers (`tests/test-parity-dtb.sh`) pass. The sound
facts checker needs this Mac's PMP tunables and was not run (not changed by r3b).

Why the blobs differ from r3a's, node by node (`tests/dtb-node-diff.py`, old r1 blob against new r1 blob; old r3a against new
r3a):

- `/soc@200000000 ranges`: `<0x2 0x0 0x2 0x0 0x3 0xc0000000>` becomes `<0x2 0x0 0x2 0x0 0x4 0x0>`. That is the base's
  `t6050-base.dtsi` (Mariano Miguel, `403f0bc409`: die0's range now covers the ISP watchdog), not ours. Same
  for J714s.
- r1 only: `apple,always-on` on the three PMP power domains. The base's shared `t6050-peripherals.dtsi` has it now
  (their 0028), so r3a's `t6050-k114s-sleep.dtsi` repeats a property that is already set: harmless, and left alone.
- Nothing else. No node added or removed.

Because the base moved, **the proven r1 tree built against r3b is not byte-identical to the proven r1 blob**. The
r1 Stage 2 file that is installed now stays what it is; an r3b trial uses the r3b blobs above.

### The J714s nodes of v272-11

| J714s change | K114s equivalent? | Draft |
| --- | --- | --- |
| Fan manual control, #1944, their 0024: `apple,fan-manual-control` on `fan-F0Ac`, `fan-F1Ac` | **yes, same two fans and mode keys** (`F0md`, `F1md` in `t6050-k114s-common.dtsi`; this Mac's running kernel exposes `fan1` and `fan2` with min, max, target, read only, and `fan_control=N`: agent-run). The SMC fan keys are not in the Apple device tree, so no ADT fact can check that a K114s SMC accepts a manual speed | `dts/t6050-k114s-fan.dtsi`, macro `K114S_R3B_FAN_MANUAL`, off by default. Without the macro the tree is byte-identical to r1; with it two properties are added (agent-run) |
| PMP fast-die effort, #1950, their 0032: `apple,fast-die-effort = <&pmp0_report N>` on the three cluster controllers | **yes where the ADT allows**: `/arm-io/pmp0/iop-pmp0-nub` has `fast-die-ctrl-ce-map` with `MACC0`, `MACC1`, `PACC_ANE` in the J714s order (agent-run, names only). It cannot be on today: the properties point at the PMP report, which exists only while the PMP runs, and until it reports cpufreq holds each cluster at a fallback limit, so a K114s tree without a running PMP would run slower. The PMP needs this Mac's tunables (root-only ADT) | `dts/t6050-k114s-fast-die.dtsi`, macro `K114S_R3B_FAST_DIE`, off by default, for a tree that enables `&pmp0_report` and after the PMP is proven. Off: byte-identical to r1; on: three properties and phandle renumbering (agent-run) |
| PMP domains through s2idle, #1789, their 0028 | **already applies**: it is in the shared T6050 dtsi, so the K114s gets it (the domains stay disabled in our trees, so the property does nothing yet) | none needed |

`tests/test-parity-dtb.sh` now also runs the two drafts through its "off is byte-identical, on compiles" loop
(a one-line change to that script).

## 7. To send to betizzel

T6050-generic changes that v272-11 lacks. None is needed for the K114s to boot, so none is in our series. Each applies
cleanly on top of v272-11 (agent-run); the repository files are named.

| Patch | Upstream | What | Why they would want it |
| --- | --- | --- | --- |
| `sleep-lid/0004`, `0005`, `0006` | aurora-silicon/linux #1688 (open draft) | simpledrm gives a boot framebuffer marked `apple,internal-panel` an `eDP-1` connector; `0004` adds the property to `t6050-j714c.dts`, `0005` to the K114/K116 dtsi; the binding | a lid close would count the internal panel as an external monitor on a J714s too (inference: not tested here; `t6050-j714s.dts` would need the property, `0004` does not add it) |
| `sleep-lid/0007` | #1615 (open draft) | an unreadable battery manufacture date returns `-ENODATA`, which the power-supply core skips, instead of a logged error | 30 log lines in five minutes on a K114s. Whether the J714s SMC does the same is not known here |
| `sound/0002`, `0003` | #1787 (open, Jens Axboe) | tas2764 keeps its bus quiet while the amp is in reset; i2c-pasemi reports a NACK as a NACK (cleaner I2C errors on every bus) | any T6050 with an amp on that bus; the J714s speaker path is the candidate, untested here |
| the config options of sections 1 to 4 of `k114s-r3.config` (BNEP, BBR, `fq`, policy routing, conntrack marks, connmark, masquerade, TCPMSS) | betizzel/omarchy-m5 #9 (the RFCOMM and PKCS8 part is in v272-9 already) | 38 options: observed failures of bluetoothd, systemd-sysctl and tailscaled on an Omarchy install | they are Omarchy-install needs, not K114s ones. Same journal lines on any J714s with this config |

Not for them: `sleep-lid/0001`, `0002` (K116s), `sleep-lid/0003`/`r3b/0005` and `sound/0004` (K114s), `r3b/0001` to `0004`
(the K114c/K114s trackpad; the J714s has its own and their release notes say nothing about it).
Marked "to be upstreamed": `r3b/0005` could go to aurora-silicon/linux as the K114s line of the #1711-style K114c admission.

## 8. Build, package, tests (agent-run unless marked)

Build: `source $K114S_BUILD_ROOT/env.sh; cd $K114S_BUILD_ROOT/src/r3b; export K114S_LABEL=K114S-R3B;
kmake O=$K114S_BUILD_ROOT/build/r3b -j18 Image modules dtbs`, clang 23.1.3, Rust 1.98.1, the private bindgen. Full build
from nothing, 5 min 55 s (`-j18`, all cores; a few small dtc runs alongside). `kernelrelease` `7.3.0-17.v272-11-k114s-r3b-ARCH`;
`Image` 54,282,752 bytes (r3a 54,217,216, running 54,086,144), sha256
`279ee5cbd6a70234520915321345abb53f20197f907d6a097dee3a64fe4c94e8`; 1972 modules; 138 Apple device trees built.
The Linux banner carries `K114S-R3B`.

Source reproduction (all from this repository and the recipe):

    # a clone of aurora-silicon/linux
    git checkout -b r3b a5ebec5fd092327b16ff26366cb3840448285578
    for p in $RECIPE/patches/j714s-27.2/linux/0*.patch; do git am --3way "$p"; done     # tag omarchy-j714s-6
    grep -v '^#' patches/linux/r3b.series | grep . | while read p; do git am patches/linux/$p; done
    printf -- '-17.v272-11-k114s-r3b' > localversion.10-pkgrel
    # configuration: their config, then the delta
    cp $RECIPE/installer/recipes/linux-aurora-j714s/config $O/.config
    scripts/kconfig/merge_config.sh -m -O $O $O/.config patches/linux/config/k114s-r3.config; kmake O=$O olddefconfig
    build/validate-config.py $O/.config patches/linux/config/k114s-required.config patches/linux/config/k114s-r3.config

| Check | Result | Label |
| --- | --- | --- |
| Their validator against the resulting config; ours against `k114s-required.config` and `k114s-r3.config` | passes; 133 and 252 requirements, 0 not met | agent-run |
| QEMU TCG `virt`, `k114s-qemu-smoke shell` | PASS: banner `7.3.0-17.v272-11-k114s-r3b-ARCH`, `#1 SMP PREEMPT K114S-R3B` | emulator/replica |
| QEMU, all 1972 modules in an initramfs, `modprobe` each (`k114s-qemu-smoke modules`) | `ok=1965 failed=7`; the same seven as the baseline and r3a (`tcrypt ipmi_si cppc_cpufreq sun50i-cpufreq-nvmem stratix10-soc apple-pmp-j613-hwmon xen-pciback`); `magicmouse` loads; no Oops, BUG or WARNING. Baseline kernel (r1): 1721 of 1728, same seven; r3a: 1965 of 1972 | emulator/replica |
| `k114s-cmp-modules` against the running kernel's installed modules | 1182 differ, 244 new, 546 same (r3a: 1181, 244, 547): expected, the base and the delta changed them | agent-run |
| `packaging/linux-k114s/check-package.sh` on `linux-k114s-7.3.0.r3b-1-aarch64.pkg.tar.zst` | all passed: one module directory, release ends in `-ARCH` and differs from `linux-aurora`'s, no file in common with it, `dtbs.list` (46), 1972 modules with the release's vermagic, `depmod -a -e` clean, banner. The `vmlinuz` in the package equals the built `Image` | agent-run |
| 14 device trees compile, `lint-dtb.py`, `lint-display-gpu-dtb.py`, `lint-sound-dtb.py`, `test-parity-dtb.sh`, ADT display and parity facts | pass (section 6) | agent-run / emulator/replica |

Outputs, outside the repository, in `$K114S_BUILD_ROOT/integrate/release-r3b/` (`SHA256SUMS` lists the first three):

| File | sha256 | Size |
| --- | --- | --- |
| `linux-k114s-7.3.0.r3b-1-aarch64.pkg.tar.zst` | `2859267bb3fbbfaa66392ee9353c4418ccc49206c7ed7b5e0d5c6eb78f7856e7` | 47,526,432 bytes, 2,588 entries |
| `k114s-r3b.dtb` (= `t6050-k114s-r3a.dtb` above) | `7b12883b2d5bb12678f3d239e5211be3e35a88cff97e383adf8144dd9435928f` | 107,727 bytes |
| `boot-ctxr-r3b.bin` (Aura + that tree + the installed gzip U-Boot, `build/make-stage2.sh`) | `54fcff9e780d52553c6e4fea59fe64824c0b28fac5080656445103cb102a290f` | 4,439,433 bytes. Prefix `1546dd50...` and trailer `9d8dc11e...` are r3a's |

The PKGBUILD takes the candidate from `K114S_CAND` (`r3a`, the default, or `r3b`): `pkgver` 7.3.0.\<cand\>, `pkgrel` 2 or 1, source and
output `src/<cand>`, `build/<cand>`, and for r3b a guard against r3a's release. The default stays r3a, so the r3a runbook, which
does not set it, keeps building and checking the r3a package. For r3b: `K114S_CAND=r3b PKGEXT=.pkg.tar.zst makepkg ...` and
`K114S_CAND=r3b check-package.sh ...` (without `PKGEXT` makepkg here writes `.xz`). Re-packaged with this PKGBUILD (agent-run): the
same file list, sizes and modes as the delivered package, and `check-package.sh` passes again; the delivered package and its hash
above stand (its `.PKGINFO` time stamps would only change the hash).

Superseded for installing (docs/r3-display-plan.md, D0): `K114S_CAND=r3b` now names the package `linux-k114s-r3b`
(`pkgname`, `pkgbase`, the module directory's `pkgbase` file, `/usr/share/linux-k114s-r3b/`), so it installs beside r3a
instead of replacing it. The same build, repackaged: `linux-k114s-r3b-7.3.0.r3b-1-aarch64.pkg.tar.zst`, sha256
`438c4efe03d5271ffb5beae0125199e4d5cdba2bc97e5fdc2a05455eeb93f905`. The shared-name package above is kept for the
record only and now fails `check-package.sh`.

Not verified: anything on the hardware; the Image against an installed one; the trackpad stack booted; the GPU
mailbox interrupts on a K114s; the KUnit cases; the sound checker.

## 9. Does the r3a runbook apply to r3b?

The steps and their order apply (slot design, hooks, one-shot entry, Stage 2 trial, the ways back); package layout,
dtbs, `-ARCH` and the hooks are the same. The commands do not apply as they are written: they carry r3a's names and
hashes, and four things behave differently. Not changed yet, as asked; this is the list for the person who changes them.

Names and hashes to replace (the runbook, `docs/r3-integration.md` sections 1 to 8):

| r3a | r3b |
| --- | --- |
| `7.3.0-17.v272-4-k114s-r3a-ARCH` (release, `uname -r`, "Building UKI for linux-k114s (...)", vermagic) | `7.3.0-17.v272-11-k114s-r3b-ARCH` |
| `linux-k114s-7.3.0.r3a-2-aarch64.pkg.tar.zst`, sha256 `122fdcf8...` | `linux-k114s-7.3.0.r3b-1-aarch64.pkg.tar.zst`, `2859267b...` |
| `vmlinuz` sha256 `bbf5ad5e...` | `279ee5cb...` |
| `boot-ctxr-r3a.bin`, `5164bb1e...`, tree `154568fe...` (also in `aura-try`: `armed\nm1n1/boot-ctxr-r3a.bin`, and the hash literal in the STOP check of step F) | `boot-ctxr-r3b.bin`, `54fcff9e...`, tree `7b12883b...` |
| `dts/t6050-k114s-r3a.dts`, `build-r3a-dtb.sh` | unchanged files (the tree name stays `r3a`); only the hashes move |
| module counts: 1972, QEMU 1965 of 1972 | the same numbers |
| `patches/linux/r3a.series`, `-k114s-r3a` in `localversion.10-pkgrel` | `r3b.series`, `-17.v272-11-k114s-r3b` |
| the running kernel `7.3.0-17.v272-4-ARCH` in the guards | still right until a v272-11 `linux-aurora` is installed; r3b's release differs either way |
| `Image` size 54,217,216 bytes (`docs/esp-space.md` budgets the UKI) | 54,282,752 (+65,536) |

Scripts that matched only the string `k114s-r3a-ARCH` and so did not recognise an r3b kernel (all repaired after review):

- **Done (review repair):** `linux/r3a-trial/70-k114s-gpu-desktop` is now version 3: the second lock matches every `*-k114s-r3*-ARCH`
  release and needs that release's own opt-in (`~/.config/k114s-gpu-desktop-r3b` for r3b, `-r3a` for r3a), so on an r3b kernel the
  standing opt-in alone leaves the desktop on the CPU. `tests/linux/test-gpu-guard.sh` has the r3b cases (12 passed). The runbook's
  install command for the guard (D-step, `sudo install -m755 ... 70-k114s-gpu-desktop`) installs this version; **install it before any r3b
  boot**, and keep the GPU tree out of r3b trials (section 3, risk 1) until the lead decides on the mailbox interrupt, or carry a revert of
  `788441e089` so that receive polls until the interrupt is proven.
- **Done:** `tests/hardware/k114s-r3a-check.sh` and `k114s-r3a-audio-check.sh` (and the audio test) accept an r3a or r3b kernel; the `Kernel version:` fixture of `tests/linux/test-boot-once.sh` is the r3b release.
- Still true: the script names keep "r3a"; the runbook text above is still the r3a one.

**`update-m1n1` after the window.** `7.3.0-17.v272-11-k114s-r3b-ARCH` sorts above every `linux-aurora` release (also a later
`7.3.0-17.v272-11-ARCH`) in version sort (`sort -rV`, as update-m1n1 uses), and `95-m1n1-install` takes the dtbs of the highest `*-ARCH` directory. With `linux-k114s`
installed, any later kernel transaction would therefore rebuild `boot.bin` from r3b's 46 packaged dtbs (including the preliminary
`t6050-k114s.dtb`, `73ab156a...`) and write `boot.bin.new` and `.old` (about 20 MB transient, on an ESP with about 87.6 MB free). It does
not change what boots (`boot-ctxr.bin`), but it can trip the ESP guard, and it was the same for r3a. For r3b: keep
`M1N1_UPDATE_DISABLED=1` in `/etc/default/update-m1n1` for as long as `linux-k114s` is installed (D2 sets it for the install and D4
restores it: for r3b D4 must not restore it while the package stays), or remove the package first. Fixing `update-m1n1` to skip `*-k114s-*`
is the alternative; it is a system script and is not touched here.

Behaviour that differs (section 3): the GPU mailboxes receive by interrupt (step G is the first time on a K114s; r3a's
"0009-only kernel" description and "suspend stays forbidden on the GPU tree until 0010 is in" no longer describe the kernel); the
connector stays `Unknown-1` (the `eDP-1` monitor rule and every `eDP-1 connected` expectation fail on r3b without
`sleep-lid/0004`); the trackpad stack is new code (step E needs a trackpad check that r3a's did not: `dmesg | grep -iE
'magicmouse|report_size'` and pointer movement); the lid close tests are blocked by the connector.

Packaging, `check-package.sh` and the Stage 2 builder are reusable as they are.
