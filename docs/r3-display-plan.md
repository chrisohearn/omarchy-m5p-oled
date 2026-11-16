# r3 display plan: the K114s OLED panel from simpledrm to the DCP

Plan, 2026-11-15, revised after the r3a promotion. Branch `display/dcp-plan`. Takes the internal panel (3024x1986 tandem
OLED with the notch rows shown, 120 Hz ProMotion) from the boot framebuffer (`simpledrm`, `card0`) to the display
coprocessor (DCP, `appledrm`). Then it adds brightness (#2), 120 Hz and VRR (#19), DPMS and burn-in care (#22) and night
light (#73), and confirms the greeter (#25). Umbrella issue: #17.

It builds on [r3a-promotion.md](r3a-promotion.md) (PR #88, `a0b05a57`: the boot chain this plan starts from, and its P7,
which governs any r3b trial), [r3-display-gpu.md](r3-display-gpu.md) (the research and the K116s copy of the nodes),
[r3b-kernel.md](r3b-kernel.md) (the kernel), [r3-brightness.md](r3-brightness.md), [r3-gpu-result.md](r3-gpu-result.md),
[r3-integration.md](r3-integration.md) (the one-boot mechanisms) and [esp-space.md](esp-space.md). Nothing in this plan
has run. No step here is authorised by this document. Each trial is a root step for the lead, with the owner at the Mac.

Every claim carries one of three labels:

- **source-read**: code, a device tree, a file, a log or a pull request, read here.
- **seen on hardware (board)**: observed on that machine. For K114s, agent-run on this Mac unless it says owner. Other
  boards are upstream- or partner-reported.
- **unknown**: not established.

## 1. Corrections to the brief

| Brief said | Fact | Evidence |
| --- | --- | --- |
| J714s is a 16-inch LCD | The 14-inch M5 Pro/Max with a **mini-LED** LCD (`apple,panel-j714`, `apple,panel-mini-led`, 302 x 196 mm, `adj-height-mm` 189). Do not copy its panel node: `panel-mini-led` selects the mini-LED backlight path | source-read (r3b `t6050-j714s-gpu-panel.dtsi`) |
| Panel is 3024x1964 | **3024x1986**: the boot framebuffer, fb0 `virtual_size`, ADT `artwork-device-subtype` 0x7c2. The loader sets `/chosen/asahi,show-notch = "1"`. 1964 is the J714s/J314 mini-LED family (the J714s DCP log shows `3024x1964`) | seen on hardware (K114s); source-read (#14) |
| "The J714s DCP works on v272-11, so port its nodes" | The J714s runs DCP image `C51FB0C8-…` (26B123). The K114s runs `3D6C8857-E6F1-3D2E-9DFF-587028AE0C6E` (26B8125, the **K116s** image) on `dcp` and on all four `dcpext`. The installed loader pins only `C51FB0C8` on 27.2, so it **refuses** the K114s. The precedent is the K116s (aura #226, linux #1648/#1859), not the J714s | source-read (ADT facts file, aura source); seen on hardware (K116s, upstream) |
| "card2-eDP-1" is in betizzel #12 | It is in betizzel **#14** (J714s). #12 holds the lane agreement | source-read (`gh issue view 14 -R betizzel/omarchy-m5 --comments`) |
| P5 and P6 are next; the repair entry stays until P5; about 78 MB free | P5a, P5b, P5c, P6a, P6c and P6d are done. The log records `PROMOTION COMPLETE` at 16:06. The repair entry and image are off the ESP. Free space is **111,022,080** bytes | source-read (the lead's recovery log); seen on hardware (K114s, `df -B1`, today) |
| The owner authorised D0-D4 | Recorded at the 14:50 intake. At 16:06 the log adds: "Background workflow (config PR + display D0) resume was declined by the owner; not restarted." Whether that withdraws D0 is not settled (G0) | source-read (recovery log) |

## 2. Where we are (after P6)

Read-only, agent-run on this Mac today, unless a row says otherwise.

| Fact | Evidence |
| --- | --- |
| This boot (16:06) is the default: r3a `7.3.0-17.v272-4-k114s-r3a-ARCH`, no aura trial. `default_entry: Omarchy/linux-k114s`. Menu: 1 `/+Omarchy`, 2 `//linux-aurora`, 3 `//linux-k114s` | seen on hardware (K114s) |
| Configured Stage 2 `m1n1/boot-ctxr.bin` = `9825a103…` (loader prefix `1546dd50…` + GPU tree `2c870ba9…`). Both pins (`k114s-repair/k114s.dtb`, `/usr/local/lib/omarchy-k114s/k114s.dtb`) = `2c870ba9…`. The tree's source is `dts/t6050-k114s-r3-gpu.dts` (`K114S_R1_N1`, `K114S_R1_USB`, `K114S_R3_GPU`; no sleep dtsi). r1 kept at `k114s-repair/known-good/boot-ctxr.bin` (`45a5dbef…`) | seen on hardware (K114s: hashes); source-read (dts, r3a-promotion.md P1) |
| `aura-try` reads `spent`. The standing trial is retired (`/etc/omarchy-k114s/stage2-trial` absent, `k114s-stage2-rearm.service` disabled). `k114s-trial-default-revert.service` masked | seen on hardware (K114s) |
| Images: `omarchy_linux-k114s.efi` 79,420,416 bytes, sha256 `a15fa01ab7e20c9c1bf1b3f61c04f6ab765c4aa425188c22f70648a3871c52f4`, `#hash` (b2) `4d2647d5512067c5…` (the full value is its `path:` line). `omarchy_linux-aurora.efi` 79,253,504 bytes, sha256 `72f5d32c…`, hook-built at 16:00 (P5b) | seen on hardware (K114s) |
| Packages: `linux-k114s 7.3.0.r3a-2`, `linux-aurora 7.3.0.aurora17.v272-4`. 22 held names, including `linux-k114s`, `linux-aurora`, `limine-mkinitcpio-hook` and `limine-snapper-sync`. `M1N1_UPDATE_DISABLED=1`. Sleep targets masked. `omarchy-dev` and `omarchy-settings-dev` are not held (r3a-promotion.md D7) | seen on hardware (K114s); source-read (log P6c) |
| ESP: 111,022,080 free of 523,132,928 (78.8 % used). After P5a, with r3a's image alone, it was 190,275,584, so the `linux-aurora` image takes 79,253,504 | seen on hardware (K114s); source-read (log P5a) |
| `card0` simpledrm (`card0-Unknown-1`, 3024x1986), `card1` + `renderD128` aurora GPU. `/sys/class/backlight` is empty. The live DCP nodes are present but `disabled`, with no `dcp`/`disp0` alias and no `display-subsystem` | seen on hardware (K114s) |
| Loader log, every boot: five `DCP: T6050: __OS_LOG 0x…+0x2c000 overlaps /memreserve/ 0x1000f000000+0x5174000` lines, then `the device tree does not describe the internal display: no handoff`. aura #226 reports the same lines on the K116s as benign | seen on hardware (K114s); source-read (#226) |
| GPU mailbox receive interrupt on r3a: about 421/s and 385/s in step G; `2302600000.mailbox-recv` 145,218 this boot. The J714s on v272-11 idles at about 64/s | seen on hardware (K114s; J714s, partner-reported in #14) |
| ADT (facts file): image `3D6C8857-…` running=1 on dcp, dcpext0-3. `disp0` not external. `disp0 clock-ids [361, 458]`. `/vram 0x10fd41b4000 + 0x46fc000`. `user-accessible-max-nits` 1000 (16.16). `artwork-display-gamut` Rec2020. **No panel node** | source-read (`$K114S_BUILD_ROOT/integrate/release-r3b/adt-display-facts.out`) |
| ADT (not in the facts file): `/product` `oled-display=1`, `supports-burnin-mitigation=1`, `partially-occluded-display=1`, `artwork-device-subtype` 0x7c2. `/arm-io/disp0` `dot-pitch-float` 0x437e999a (254.6 ppi) | source-read (`build/k114s-adt.py --adt <saved copy> show product disp0`) |
| The facts file's ADT comparison ran on a tree without a `dcp` alias, so the dcp checks did not run | source-read |
| `appledrm` is in neither current UKI's initramfs (`lsinitcpio` of the `.initrd` section: 0 matches in both) | seen on hardware (K114s) |
| The built r3b package is `pkgname = pkgbase = linux-k114s` (`7.3.0.r3b-1`), the same name as r3a. The hook names each UKI `omarchy_<pacman package>.efi` (`limine-mkinitcpio-install:143`). Installed as built, it would **replace r3a**, the default | source-read (`.PKGINFO`, hook) |
| r3b's blobs differ from r3a's: `t6050-k114s-r3-gpu` against the r3b includes gives `6a04f79e…`, not `2c870ba9…`, because the base `/soc@200000000 ranges` changed (`403f0bc409`) | source-read (r3b-kernel.md section 6) |
| Installed `/usr/lib/modprobe.d/aurora-m5-vrr.conf`: `options appledrm fw27_panel_vrr=1` (tested on the J714s only) | seen on hardware (K114s) |
| GPU guard `70-k114s-gpu-desktop` v3 exits early when `/dev/dri/by-path/platform-display-subsystem-card` exists; `60-aurora-m5-display` then sets zink. The first DCP boot is also a GPU-rendered desktop | source-read (installed generator) |
| betizzel/omarchy-m5 moved to **v272-12** (release `omarchy-j714s-8`, 2026-11-15T22:29Z). r3b is on v272-11 | source-read (`gh release list`) |
| J714s DCP boot on v272-12 (#14, TripleU613, 22:55Z): simpledrm at 1.21 s; `apple-drm` binds `48ae00000.dcp` at 1.95 s; `DCP booted`; `[drm] Initialized apple 1.0.0 for display-subsystem on minor 2` at 2.13 s; `card2-eDP-1` at 3024x1964@120, `XRGB8888`, only the 120 Hz mode offered; `no loader brightness reported; backlight starts at 500 nits without a panel change`. No blacklist test (offered) | seen on hardware (J714s, partner-reported); source-read |

## 3. Decisions

### 3.1 Base kernel: r3b, under its own package name

r3b is aurora-silicon/linux `a5ebec5f` (v272-11) plus betizzel's 32 patches plus the six K114s patches and our config
delta. It is built but not booted. The reasons to use it:

- Its `drivers/gpu/drm/apple` is the driver that both working T6050 panels ran on: the J714s on v272-11, and the K116s on
  upstream around `a5ebec5f`. Against r3a it differs in about 1,100 lines: #1891, #1887, kvzalloc dictionaries,
  singleton services, betizzel 0002/0003/0004/0014 and the HDMI/fabric patches 0018-0026. source-read.
- It has every piece the panel needs: the 120 Hz-only gate (`iomfb.c:3066`, `dcp.c:8995`, #1868); the 27.2 method table
  (`iomfb_v27.c:126`, chosen by `apple,firmware-compat` `<27 2 0>`); `fw27_panel_vrr` (`iomfb.c:52`, default off);
  `apple-panel-bl` (`dcp_backlight.c`); CTM on the CRTC (`apple_drv.c:1195`); betizzel 0003 (brightness writes refused
  once the DCP has crashed). source-read.
- The lane agreement (#12): the K114s kernel is betizzel's series plus our tree. Their newest is now v272-12, so r3b is one
  behind. **Before D0's rebuild**, the lead records whether r3b moves to v272-12 or stays on v272-11, with
  `git diff <v272-11>..<v272-12> -- drivers/gpu/drm/apple` summarised in the record (the 500-nit start line is a known
  item to look for). Recommended: stay on v272-11 unless that diff has a T6050 or 27.2 fix, because r3b is the reviewed
  build. source-read (releases); unknown (the diff). **D0 result** (section 5.1): r3b's `drivers/gpu/drm/apple` is
  v272-11's byte for byte; v272-12's delta there (28 files, +2,910 -18, all from the base `c0a2a752`) is firmware-27
  display sleep, the T6050 external engines and J714s-gated paths. No internal-panel or 27.2 fix for an `apple,k114s`
  board. The 500-nit start line is already in v272-11. Recommendation unchanged: stay on v272-11. source-read.

**It must be rebuilt as `linux-k114s-r3b`** (`pkgname` and `pkgbase`, config under `/usr/share/linux-k114s-r3b/`,
`pkgbase` file in the module directory), as P7 asks. pacman then installs it beside r3a, the mkinitcpio preset is its
own, and the hook writes `omarchy_linux-k114s-r3b.efi` and an `Omarchy/linux-k114s-r3b` entry. `default_entry` keeps
naming r3a. The brightness build (D5a) is a later version of the same package and replaces the r3b UKI in place.
source-read.

**What has to be true first:**

| Gate | Condition | How it is checked |
| --- | --- | --- |
| G0 | The root confirms with the owner, or through Jarvis, that the 16:06 decline does not withdraw the D0-D4 authorisation. The window decision (4.4) is sent with its default | the answer, recorded in the recovery log and on the ledger row |
| G1 | P is recorded (section 2): configured file `9825a103…`, tree `2c870ba9…` (`t6050-k114s-r3-gpu.dts`) in both pins, the r3a UKI's sha256 `a15fa01a…` and its full `#hash` from the `path:` line, `default_entry: Omarchy/linux-k114s`. Already met: the path-aware `k114s-boot-once` is installed (P0b) and block C is clean on it; the macOS tool `3bfa3d11…` passed `status` and `restore-repair --check` on the Mac (P4b). Still to do: the window replica case and the Mac check of 4.3 | the record; 4.2 checks |
| G2 | The ESP budget below holds on the **measured** window layout | `df -B1 /boot/efi` before D1 and before D5a |
| G3 | r3b installed beside r3a: `pacman -U --print` names only `linux-k114s-r3b`; the hook prints `Building UKI for linux-k114s-r3b (7.3.0-17.v272-11-k114s-r3b-ARCH)` and no other; the `96-omarchy-j714s-boot-ctxr` hook rewrites `m1n1/boot-ctxr.bin` byte for byte from the pinned tree (`update-boot-ctxr-k114s: wrote ... K114s device tree 2c870ba9f5963f5a`; the file is `9825a103...` afterwards, and the pins unchanged); `pacman -Qo` gives `linux-k114s` for r3a's module directory and `linux-k114s-r3b` for r3b's; `packaging/linux-k114s/check-package.sh` ends `check-package: all passed` against both other kernels (it now says `SKIP` when the other kernel is not installed); both UKIs in `limine.conf` with matching `#hash`; `k114s-boot-once check` clean; the r3a UKI's sha256 still equals G1 | before D1 is armed (`docs/r3-display-trials.md` I1) |
| G4 | **The lead accepts the interrupt-only GPU mailbox on r3b** (`788441e089`, which r3b-kernel.md asks to decide before r3b runs on the GPU tree), citing step G (385-421/s on r3a, no storm guard message) and the J714s figure (#14). Recorded before D1. P is the GPU tree now, so D1 and every fallback that lands on a pending one-shot run r3b on it, and D2-D4 do anyway. Without acceptance, D1 uses P7's alternative (`aura-try` of `k114s-repair/known-good/boot-ctxr.bin` with the one-shot), and D2 does not start | the record; then D1 clean, with a GPU-desktop session |
| G5 | `tests/k114s-adt-display-facts.py --dtb` on the **built display tree** reports no failed comparison. It is extended to compare the `dcp_mbox` **interrupts** with the ADT (1043-1046). The register is already checked (tool line 319, and the loader) | D0 |
| G6 | `appledrm` absent from the r3b UKI's initramfs, so the screens before the root filesystem stay on simpledrm | `lsinitcpio` of the `.initrd` section (D0, and after every UKI rebuild) |
| G7 | The r3b runbook names and hashes replaced (r3b-kernel.md section 9), GPU guard v3 with the `k114s-gpu-desktop-r3b` opt-in, `M1N1_UPDATE_DISABLED=1` kept | review of the runbook diff |

**G2, the ESP budget.** Measured base, then derived steps. The r3b UKI is taken at r3a's size plus 64 KiB, Stage 2 files
at 4.5 MB.

| Layout | Free (bytes) | Against 88,080,384 |
| --- | ---: | --- |
| Now: r3a + `linux-aurora` images | 111,022,080 (measured) | passes; a third image does not fit |
| Window open: `linux-aurora` image removed | 190,275,584 (measured after P5a) | passes |
| … then the r3b UKI | about 110,790,000 | passes |
| … then two trial Stage 2 files | about 101,800,000 | passes by about 13.7 MB |
| … during the D5a rebuild (new UKI written before the old one goes) | about 22,000,000 at the peak | the guard checks first (101.8 MB) and passes; the write fits |

At most two trial Stage 2 files sit on the ESP at once; the others wait in `/var/lib/k114s-recovery/`. G2 is recomputed
from the real numbers before D1 and before D5a.

**Why the window rule (4.4) is needed, not just the hold.** Holding `linux-aurora` does not stop the hook from rebuilding
its image. `limine-mkinitcpio-install` sets `rebuild_all` for any changed target outside `usr/lib/modules` (firmware,
initcpio, systemd, cryptsetup, lvm: `/etc/pacman.d/hooks/90-mkinitcpio-install.hook`) and then rebuilds every kernel
directory with a `modules.builtin`. In the window that is three images (`linux-aurora`, r3a, r3b) on an ESP that holds
two, and the guard passes at about 101.8 MB, so it would not stop it: the result is truncated images. An `omarchy-dev`
migration that runs `limine-mkinitcpio` does the same outside pacman. source-read.

Plan B, if D1 fails: r3a also has the 120 Hz gate, `fw27_panel_vrr` and the K-board panel binding (r3a.series). The
display stages could run on r3a, changing only the Stage 2. That is a lead's decision and is not the plan.

### 3.2 Device-tree base: the K116s nodes on P's includes

`dts/t6050-k114s-display-gpu.dtsi`, section `K114S_R3_DISPLAY`, already holds the K114s copy of the K116s hand-off section
(#1648 `377b2a2d` in the form #1859 leaves it). It differs from the K116s only in the panel node and in
`apple,clock-ids`. The external engines stay off: aura #226 hands off only the internal panel for the 26B8125 image.
source-read.

The display tree is `dts/t6050-k114s-r3b-display.dts`: P's source (`t6050-k114s-r3-gpu.dts`) plus `K114S_R3_DISPLAY`,
later plus the brightness include. **It is built against the includes that reproduce P**, not the r3b includes. Those are
the device-tree includes of the kernel that was running when P was built (the r1 kernel's source, aurora-silicon/linux
`a34d26c2` plus betizzel's v272-4 series: `$K114S_BUILD_ROOT/display-gpu/src/ktree-installed`). They are **not** the r3a
tree: `t6050-k114s-r3-gpu` against `src/r3a` gives `d8c3c031…`, against `src/r3b` `6a04f79e…`, and only the r1
kernel's includes give `2c870ba9…` (agent-run, D0). D0 asserts that the same file built with `K114S_D0_DISPLAY_OFF`
(which leaves `K114S_R3_DISPLAY` undefined; `build/build-dtb.sh` takes it from `K114S_DTS_DEFINES`) is byte-identical
to `2c870ba9…` and prints both hashes. So every trial runs on P's base, and D4 differs from D3 by the display section
alone.

D0: the display section builds against P's includes (section 5.1). If it had not, the fallback was the r3b includes, said plainly: D2 is then
also the first boot of r3b on the new base ranges (`403f0bc409`), and D4 differs from D3 by the display section plus that
base delta. The lead picks; the record names which. source-read.

### 3.3 Loader: the r3 loader (aura #226 merged)

The installed loader is aura `22b71758` plus betizzel's seven patches (`1.0.0b13-g22b71758-dirty`, prefix `1546dd50…`).
The r3 loader adds our three, `patches/aura/0001`-`0003`:

- 0001: the #226 pin table, hand-merged, which admits `3D6C8857` with `ext = false`;
- 0002: #230, the GPU firmware hint;
- 0003: the host-stub fix (tests only).

**Superseded for D3 and D4 by the lead's decision** (`docs/r3-display-trials.md`, E2): the trials use the loader of
`betizzel/omarchy-m5#18` (Aura 0008: the #226 pin for `3D6C8857` beside 0005's J714s pin, internal panel only), sha256
`beceb683...`, so the K114s trial validates what TripleU613 will ship. It lacks #230 (0002), which only spares the GPU
driver one refused build at probe; today's loader lacks it too and the GPU runs. The r3 loader below stays for reference.

The build at `$K114S_BUILD_ROOT/display-gpu/src/aura/build/aura.bin` is 4,063,232 bytes, against 3,997,696 for the installed
loader. The gate test passes 12 replica cases. source-read and agent-run build. It has never run on hardware.

D0 (agent-run): its source is the installed loader's source plus `patches/aura/0001`-`0003` exactly (`git am` of the
repository's three patches on `k114s-base` gives the tree `74abd333…` of the build commit `bdf42d19`), and a clean
rebuild of `bdf42d19` reproduces `aura.bin` byte for byte (`582df9bb…`, version `1.0.0b13-gbdf42d19`). The installed
loader (`1546dd50…`, `1.0.0b13-g22b71758-dirty`) does **not** reproduce with the build area's toolchain (LLVM 23.1.3): the
same source and recipe patch give `daf9d5e4…`, same size and version string, 192,889 bytes different. So D3 changes the
loader binary as a whole (the three patches and a different compiler build), not only the three patches.

Two consequences:

- A Stage 2 with this loader is a new prefix. `build/make-stage2.sh TREE OUT DIR` takes it from a directory that holds the
  new `aura.bin` as `m1n1.bin` and the installed `u-boot-nodtb.bin`.
- The macOS tool splits at `aura_prefix_bytes` (`manifests/payload-r1.json`: 3997696). It needs a per-variant value, and a
  rollback that restores the loader bytes, before such a Stage 2 is ever *configured* (D9b). Trials through `aura-try` do
  not touch the configured file, so they do not need it.

## 4. Trial mechanism and the way back

### 4.1 Mechanism

The mechanism is r3-integration.md section 6:

- **Limine one-shot.** `k114s-boot-once arm <entry>` writes `LoaderEntryOneShot`. Limine erases it when it reads it.
- **Stage 2 one-boot.** `armed\n<file>\n` goes into `/boot/efi/aura-try`. The loader marks it `spent` before it loads the
  file, and reports `/chosen/aurora,trial`. The trial watchdog does **not** arm on this Mac (`WDT: could not arm the
  trial watchdog`), so a hang needs a forced power-off. seen on hardware (K114s).

Rules for every display trial:

1. **A trial that changes the Stage 2 arms both: `aura-try` and a one-shot of the trial kernel's entry.** The one-shot
   goes first and the Stage 2 last, with the STOP checks of r3-integration.md step F. A kernel-only trial (D1, D5a) arms
   the one-shot alone.
2. The configured `m1n1/boot-ctxr.bin` and `default_entry` are never written by a trial (D9a and D9b are promotions).
3. No standing re-arm exists (retired in P1); every trial is exactly one boot.
4. **The display window (4.4) holds from its opening to its close, not only during trial boots:** no package transaction,
   no `omarchy update`, no `limine-mkinitcpio` or `mkinitcpio`, no `update-m1n1`, except the attended r3b install (D1)
   and rebuild (D5a) with their G2 and G3 checks.
5. Suspend stays blocked. The lid steps wait for #1688 (section 9).

### 4.2 The proven configuration P, checked before every arm

Read-only:

- `sha256sum /boot/efi/m1n1/boot-ctxr.bin` is `9825a103…`; both pins are `2c870ba9…`.
- `k114s-boot-once check`: `default_entry` resolves to `Omarchy/linux-k114s` and its file matches its `#hash`,
  `remember_last_entry` is not `yes`, and the r3a UKI's sha256 is `a15fa01a…`.
- `aura-try` reads `spent`, and `/etc/omarchy-k114s/stage2-trial` is absent.
- The boot-once self-test marker exists, and `boot-once-not-durable` does not.
- The current boot has no `/chosen/aurora,trial`, or shows the trial you expect.
- Window state: `EFI/Linux` holds only the r3a and r3b images, free space is within 1 MB of the value recorded when the
  window opened (less any Stage 2 file copied since), and `limine.conf` has no entry added since then.
- The snapshot sync is held off: `snapper-cleanup.timer` and `limine-snapper-sync.service` read `inactive`, and
  `limine_history` on the ESP is as it was when the window opened. `limine-snapper-sync` runs from that timer every hour
  and 10 minutes after each boot (and on every snapshot change), adds a `Snapshots` entry and copies each kernel's image
  unless the ESP would pass `LIMIT_USAGE_PERCENT=85`. With two images it estimates 78.8 % to 109.3 % (+152.3 MiB) and
  adds nothing (journal, 2026-11-15). But in the window's one-image states (after the `linux-aurora` image comes off and
  before r3b's goes on, and again after r3b is removed and before the image goes back) 190,275,584 of 523,132,928 bytes
  are free: 63.6 % used, +76.6 MiB for one kernel, 79.0 %, under the limit. A run there would copy about 80 MB and add
  the entry. So the runbook stops both units (a plain `systemctl stop`, nothing disabled) in every boot of the window,
  checks it before each step, and has a block that removes a `Snapshots` entry if one slips through
  (`docs/r3-display-trials.md`, E12). Its hourly rewrite of `limine.conf` is byte-identical on the promoted layout
  (measured 2026-11-15: the 18:16:44 hourly run left `limine.conf`'s sha256 unchanged).

### 4.3 Black screen or hang: the way back, in boot-chain terms

1. Hold the power button until the Mac is off. Start it.
2. The first loader stage finds `aura-try` already `spent` and boots the configured Stage 2 (P's tree, the installed
   loader). That loader refuses any panel hand-off for this image, and P's tree has no `dcp` alias. The panel stays on
   simpledrm.
3. Which kernel comes next depends on where the hang was:
   - After Limine read the one-shot: the next boot is `default_entry`, r3a, so P.
   - Earlier (Stage 2 or U-Boot): the one-shot is still pending, so the next boot is the **trial kernel** on P's tree. For
     D2-D4 that is r3b, proven by D1; for D5-D8 the brightness build, proven by D5a. Limine consumes the one-shot on that
     boot, so there is nothing to clear. Run `sudo k114s-boot-once status`: no `LoaderEntryOneShot` in efivarfs or
     `ubootefi.var`, and `this boot started: Omarchy.linux-k114s-r3b`; `aura-try` reads `spent`. Then reboot to the
     default.
4. If the one-shot entry keeps booting (the erase did not survive the power cut), follow r3-integration.md "a stuck
   request", from macOS.
5. **From macOS, in the window** (tool `3bfa3d11…`, bundle folder). `default aurora` does not exist here: its image is
   off the ESP.
   - Stage 2 suspect: `sudo ./k114s-repair stage2 r1`. r3a ran on the r1 tree in step E.
   - r3a image suspect only: point the default at r3b by hand, as in r3a-promotion.md section 5 ("a manual edit"):
     `sudo sed -i '' 's#^default_entry: .*#default_entry: Omarchy/linux-k114s-r3b#' /Volumes/EFI/limine.conf`, check with
     `grep -n '^default_entry'`, unmount. r3b on P is proven by D1.
   - Both suspect (the static way back): first `sudo rm /Volumes/EFI/EFI/Linux/omarchy_linux-k114s-r3b.efi` (its entry
     stays, dangling and unused), then `sudo ./k114s-repair restore-repair --check` and `sudo ./k114s-repair
     restore-repair`. Without that removal it stops with `no omarchy_linux-aurora.efi to remove; nothing written`
     (`macos/tools/k114s_repair.py` `restore_repair`, lines 922-945: it needs 111.8 MB plus an 8 MiB reserve and only
     frees space by removing the `linux-aurora` image). After the removal about 181 MB is free.

   Before D1, two prerequisites (part of G1):
   - A replica case in `tests/macos/test-promoted-esp.sh` for the window layout: r3a and r3b images, no `linux-aurora`
     image. `restore-repair --check` reports short of space and writes nothing; `restore-repair` refuses with the message
     above; with the r3b image removed and its entry dangling, `restore-repair` succeeds and `status` reads as after P4b's
     restore.
   - On the Mac, after G3 and before arming D1: `status` and `restore-repair --check`. Expected: the image and block
     lines pass, and the space line reads `NOT ENOUGH, and no omarchy_linux-aurora.efi to remove`. Then back to Linux
     and block C.

**Not counted as a way back** (untested, so never relied on):

- `module_blacklist=appledrm` or `nomodeset`. In source, `nomodeset` makes `appledrm_register()` return `-ENODEV`
  (`drm_firmware_drivers_only()`). The aurora GPU driver does not check it. Neither has been tried after a *published*
  hand-off; TripleU613 has offered to try the blacklist on the J714s.
- `default aurora` while the window is open (no image).
- The macOS `stage2` rollback for a new-loader variant. It is not implemented (D9b needs it).
- Booting the r3a menu entry on the display Stage 2. Never trialed (D9).

**There is no in-kernel retreat on T6050.** `dcp_takeover_trial()` refuses only for 26.6 desktop firmware. On firmware 27
it returns 0, and `appledrm` evicts simpledrm (`aperture_remove_conflicting_devices`, `apple_drv.c:1760`) as soon as it
binds. A DCP that fails after that point leaves a dark panel until the power-off above. source-read.

Logs: the journal is persistent, so `journalctl -b -1` after a fallback has the trial's kernel side, if it reached the
root filesystem. The loader log (`/dev/mtd1ro`) is this boot's only. Copy it as the **first** command of every trial
boot. unknown whether it survives a reboot.

### 4.4 The display window (P7)

**Opening**, after G0-G2 and before D1's install:

1. Write a before-record as P6d does (hashes of the Stage 2, pins, images, the `default_entry`, entry and `path:` lines,
   `aura-try`) to `/var/lib/k114s-recovery/display/before-window.txt`.
2. `sudo limine-entry-tool --remove-uki linux-aurora`, as r3a-integration D1 did. Then `k114s-boot-once check` clean,
   `default_entry` unchanged, free about 190,275,584. `linux-aurora` stays installed and held.
3. Record `DISPLAY WINDOW OPEN` in the recovery log.

From then until the close, rule 4 of 4.1 holds. This pauses the updates P6 resumed.

**Closing**, after D4 (or after D9a if D5-D8 run inside the window):

1. Either `sudo pacman -R linux-k114s-r3b` (the hook removes its image and entry; the package stays in
   `/var/lib/k114s-recovery/`), or, on the D9a path, r3b becomes the default and r3a is retired, each with its own record.
2. Rebuild the `linux-aurora` image as P5b did (`sudo limine-mkinitcpio linux-aurora` with P5b's checks: the default
   unchanged, `check` clean, its `#hash` matches, its command line equals the default's, free at least 100 MB).
3. Move the trial Stage 2 files off the ESP to `/var/lib/k114s-recovery/display/`.
4. Run the P6d after-block against the before-record. Expected: `no boot file changed` (D4 close) or only the D9a
   changes. Record `DISPLAY WINDOW CLOSED`. Updates resume as in P6.

**Decision for the owner** (through Jarvis, with the default taken meanwhile because it is reversible): the window
overrides P6's "updates resume". Recommended default: **the window covers D1-D4 only**, in one attended sitting, and
closes after D4. D5a-D8 open a second window later, under the same rules, with their own G2.

## 5. Stages

Each stage is one reviewable change, one PR, and one attended trial boot. Stop at any failed check. Record the result on
the issue named in the stage. **D1-D4 run as `docs/r3-display-trials.md`**: D1 and D2 share one boot, D4 has its own, D3
runs only if D4 fails in a way that points at the loader, and D4 and D3 use the PR #18 loader (that runbook's E1, E2).
**D5-D9 run as `docs/r3-display-d5-d9.md`**: D5a is folded into D5, D5, D7 and D8 share one boot, D6 has its own (the mask is
dropped for it), D9a and D9b are one write session, and the layout after D9 keeps r3b.b1 and r3a on the ESP (its F1, F2, F8, F11).

| Stage | One change | Trial (4.1) | Pass | Issue |
| --- | --- | --- | --- | --- |
| **D0** | Offline. Record the v272-11 / v272-12 choice (3.1). Rebuild r3b as `linux-k114s-r3b`. Add `dts/t6050-k114s-r3b-display.dts` on P's includes (3.2) and assert the display-off build is `2c870ba9…`. Extend the facts tool for the `dcp_mbox` interrupts. Add the window replica case (4.3). Build the Stage 2 files: `-disp-oldldr` (installed loader + display tree), `-gpu-newldr` (r3 loader + P's tree, byte-identical to the one in the configured file), `-disp` (r3 loader + display tree) | none | G5, G6. `tests/lint-display-gpu-dtb.py --k116s` lists only the known differences. Every file is at most 16 MiB and its prefix hash is printed. `check-package.sh` passes. The replica tests pass | #17 |
| **D1** | Open the window (4.4). Install `linux-k114s-r3b` beside r3a (G3). Write `/etc/modprobe.d/aurora-m5-vrr.conf` (section 7). Mac check of 4.3 | one-shot `Omarchy/linux-k114s-r3b` only, P's Stage 2 | `uname -r` ends `-k114s-r3b-ARCH`. No Oops, SError or `RTKit` crash. Trackpad (`magicmouse`, pointer). `aurora … Initialized`, both `mailbox-recv` counts rise, and a **GPU-desktop session**: `touch ~/.config/k114s-gpu-desktop-r3b`, log in, a render load (`vkcube` or `glmark2`) for five minutes, the counts still rising, no GPU fault in `dmesg` | #17 (r3b) |
| **D2** | Display tree on the **installed** loader (refusal path) | `aura-try` `-disp-oldldr` + one-shot r3b | `/chosen/asahi,t6050-dcp-handoff` = `refused`. The loader log has the five `__OS_LOG … overlaps /memreserve/` lines, `DCP: T6050: DCP image 3D6C8857-E6F1-3D2E-9DFF-587028AE0C6E is not C51FB0C8-C45D-39B0-85BC-520E600FC950` and `internal display handoff refused; the boot framebuffer keeps the panel`. DCP nodes still `disabled`. `card0` simpledrm only. GPU as D1 | #17 |
| **D3** | The r3 loader on P's exact tree (loader change only) | `aura-try` `-gpu-newldr` + one-shot r3b | the loader is told apart by its hash (`boot-ctxr.bin`'s sha256), not by its version string: the pin loader reports the same `1.0.0b13-g22b71758-dirty` (`release-display-trials/aura-pin/build-info.txt`). The GPU is admitted. With the PR #18 loader the trials use (no #230), one `GPU firmware image not admitted` line before the admitted build is expected, as on P today (`docs/r3-display-trials.md` E2). The five `__OS_LOG` lines, then `the device tree does not describe the internal display: no handoff`. A 64 KiB larger Stage 2 loads through `aura-try` | #17 |
| **D4** | **The hand-off**: r3 loader + display tree | `aura-try` `-disp` + one-shot r3b | the section 9 list. A short attended session (section 10). Then close the window (4.4) unless the decision extends it | #17, #19, #25 |
| **D5a** | The brightness kernel: `patches/linux/brightness` 0001-0003, 0005, 0006 on r3b (0004 is already in v272-11; all five apply in order with `git am`, `patches/linux/r3b-b1.series`), as `linux-k114s-r3b` version `r3b.b1`, replacing the r3b UKI in place (window open, G2 recomputed; the D1 package kept in `/var/lib/k114s-recovery/`). Built offline, section 5.2 | one-shot `Omarchy/linux-k114s-r3b` only, P's Stage 2 | D1's list, GPU-desktop session included | #2 |
| **D5** | Brightness tree `dts/t6050-k114s-r3b-brightness.dts`: the D4 tree plus `#include "t6050-k114s-brightness.dtsi"` (`apple,min-brightness = <10>`), Stage 2 `boot-ctxr-disp-bl.bin` (section 5.2), plus the systemd-backlight first-boot drop-in **before** the boot | `aura-try` display + brightness tree + one-shot r3b | D4's list on the new kernel, then `k114s-backlight-check --read-only`, then the stepped check (r3-brightness.md, owner steps 1-7). `max_brightness` 1000. The floor line is in the kernel log | #2 |
| **D6** | VRR offered: `fw27_panel_vrr=1` in the `/etc` file (section 7) | `aura-try` D5's Stage 2 + one-shot | `vrr_capable` 1 on the connector. Then, live, Hyprland `misc:vrr`: no flicker. About 385 ms of black when VRR toggles is expected (J716s). The swap watchdog never logs that it turned VRR off | #19 |
| **D7** | DPMS and idle: an Omarchy idle profile for OLED (section 10). No kernel change | none new; in a D5/D6 session | `omarchy-brightness-display off`: is the panel black or dim (unknown, see 10)? It wakes on a key, with no DCP crash. The idle timeout blanks a static screen | #22 |
| **D8** | Night light | none new; in a D5+ session, last, because a DCP crash ends brightness until a reboot | `CTM` listed on the `appledrm` CRTC (`drm_info` or `modetest -p`). `omarchy-toggle-nightlight` visibly warms the panel. No `DCP has crashed` | #73 |
| **D9a** | Promote the display kernel: `default_entry` becomes `Omarchy/linux-k114s-r3b`, with the P2 checks and its own record (UKI sha256, `#hash`) | after two clean D5+ boots; the first boot after the change is r3b on P's Stage 2, which D5a proved | `k114s-boot-once check` names the new default; r3a stays in the menu until the window closes | #17 |
| **D9b** | Configure the display Stage 2 | prerequisites below | greeter on the DCP card over two boots (#25: see section 9 on `wait-for-display`). The pinned tree is updated as in promotion P1 | #17, #25 |

D4 is the only stage that first risks the picture. Plan for D4 to fail once, and keep its log.

### 5.1 D0 result (agent-run, 2026-11-15)

Offline. Nothing was installed. Nothing on the ESP, in `/boot` or in `/etc` was written, and the ESP was not read. Outputs are in
`$K114S_BUILD_ROOT/integrate/release-display-d0/`, all listed in its `SHA256SUMS`; the gate logs are in `gates/`.

| Output | sha256 | Notes |
| --- | --- | --- |
| `pkg/linux-k114s-r3b-7.3.0.r3b-1-aarch64.pkg.tar.zst` | `438c4efe03d5271ffb5beae0125199e4d5cdba2bc97e5fdc2a05455eeb93f905` | The built r3b kernel repackaged, with no rebuild (`K114S_CAND=r3b`: `pkgname = pkgbase = linux-k114s-r3b`). Against the earlier `linux-k114s-7.3.0.r3b-1`, 2,035 files are the same, except the `pkgbase` file and the config's directory. `vmlinuz` `279ee5cb…` |
| `dtb-p/t6050-k114s-r3b-display.dtb` | `914ec379c565d4b0a2df5f3055c91c63ee4ab68d462319d0e78a31a7bb35846a` | The display tree on P's includes (3.2). Against P's tree it adds exactly the display section: `/display-subsystem`, `dcp/panel`, the `dcp` and `disp0` aliases, and `apple,dma-range` on both DARTs |
| `dtb-p/display-off/…` | `2c870ba9f5963f5ae1ed18a7effa520daa234583997470d9552a795b4aafcda5` | The same file with `K114S_D0_DISPLAY_OFF`: **P's tree, byte for byte** |
| `stage2/boot-ctxr-disp-oldldr.bin` (D2) | `9e43d27a28f750ad559d9060fc9b30c33a59b5e5a8bb6e46ee1f456ffb68a5ca` | 4,440,586 bytes. Prefix `1546dd50…` (installed loader), tree `914ec379…`, trailer `9d8dc11e…` |
| `stage2/boot-ctxr-gpu-newldr.bin` (D3) | `f7f95ea98417c593e8bd64b8856491696acf00cd1cb30467535da26b8e1650bd` | 4,505,773 bytes. Prefix `582df9bb…` (r3 loader, 4,063,232 bytes), tree `2c870ba9…`, same trailer |
| `stage2/boot-ctxr-disp.bin` (D4) | `177f0028879529a1554ca0a8a2bd9c68f7a85ec0e9586f977aeaf77e41e2460e` | 4,506,122 bytes. Prefix `582df9bb…`, tree `914ec379…`, same trailer |
| `dtb-r3binc/…`, `stage2/alt-r3b-includes/…` | tree `19d03675…`; `-disp-r3binc-oldldr` `b9764aae…`, `-disp-r3binc` `13b09462…` | The 3.2 fallback, for reference only: the same source on the r3b includes. Its display-off build is `6a04f79e…`, and against P's base it differs by `/soc@200000000 ranges` and by `apple,always-on` on three PMP power controllers (`@100`, `@128`, `@130`) |

Where the inputs came from:

- The `-gpu-newldr` tree is the pinned copy outside the ESP (`/usr/local/lib/omarchy-k114s/k114s.dtb`, `2c870ba9…`), not
  cut from the configured file. The installed loader plus that tree plus the installed U-Boot, put together with
  `build/make-stage2.sh`, gives `9825a103…`, the configured file's hash, so the tree is the one in it.
- The r3 loader is `bdf42d19`, rebuilt clean to the same bytes (3.3).

| Gate or check | Result | Evidence |
| --- | --- | --- |
| v272-11 or v272-12 (3.1) | stay on v272-11; the record is `gates/v272-11-vs-12.txt` | source-read |
| P's base (3.2): the display-off build is `2c870ba9…` | PASS | agent-run |
| G5: `tests/k114s-adt-display-facts.py --dtb` on the display tree, now including the `dcp_mbox` interrupts | PASS, 17 comparisons, none failed, on the live ADT (`sudo`, read-only) and on the saved copy (same output). Tree send-empty 1043, send-not-empty 1044, recv-empty 1045, recv-not-empty 1046; ADT `[1044, 1043, 1046, 1045]`. The r3b-includes tree passes too | agent-run |
| Facts tool replica (`tests/test-adt-display-facts.py`) | 15 checks pass, including a new one: swapped `dcp` mailbox interrupts fail exactly one comparison | emulator/replica |
| G6: no `appledrm` in the r3b initramfs | PASS: `appledrm` is `=m`. A `mkinitcpio -r <package root>` dry run with this system's configuration gives 81 modules and no `appledrm`, and the same run for r3a gives none either. `/etc/default/limine`, `mkinitcpio.conf.d` and `modules-load.d` do not name it. The real UKI is checked again after D1 | agent-run |
| `tests/lint-display-gpu-dtb.py --k116s` | PASS. The only differences are the named ones: `apple,clock-ids` (the loader writes it), the panel's compatible, width and height, and the GPU on `ps_gfx` | agent-run |
| `tests/lint-dtb.py` | PASS | agent-run |
| Every Stage 2 file is at most 16 MiB, with its prefix hash printed | PASS (`build/make-stage2.sh` checks the size; `gates/stage2-build.out`) | agent-run |
| `check-package.sh` against `linux-aurora` and against `linux-k114s` | PASS, both. The check now also requires the package name to match the release (`linux-k114s-r3b` for `-k114s-r3b-ARCH`), and the earlier shared-name r3b package fails it. The r3a package still passes | agent-run |
| `pacman -U --print` | `linux-k114s-r3b 7.3.0.r3b-1` only | agent-run |
| Window replica case (4.3), `tests/macos/test-promoted-esp.sh` | 103 pass (19 new, 84 before). Covered: `status`; `restore-repair --check` short of space, with `NOT ENOUGH, and no omarchy_linux-aurora.efi to remove`; `restore-repair` refusing and writing nothing; `default aurora` stopping; `stage2 r1`; the manual edit of the default to r3b; and, once the r3b image is removed with its entry left dangling, `restore-repair` succeeding with `status` reading the repair entry | emulator/replica |
| `tests/linux/run-r3.sh` | 1,053 pass, 0 fail | emulator/replica |
| r3 loader: `tests/aura/test-t6050-image-gate.py`, aura's `run-t8122-display-handoff.sh` | 12 cases pass; every scenario passes | emulator/replica |

`release-display-d0/aura-k114s-pin/` (the PR's loader, `beceb683...`) sits in the same folder but is **not a D0 output**:
D0's `SHA256SUMS` does not list it. The trial Stage 2 files built from it are in `release-display-trials/`
(`docs/r3-display-trials.md`).

Not done in D0:

- The full `tests/macos/test-macos-tool.sh`. It needs the assembled bundle and the installer image.
- The Mac check of 4.3.
- G0, G1's records, G2, G3 and G4. They are the lead's, at D1.

**D9 and the way back after it.** After D9b every boot takes the hand-off, so "power off, then P on simpledrm" no longer
exists, and the only kernel trialed on the display Stage 2 is the D9a default. That is why D9a comes first. D9b's
prerequisites:

- the macOS tool's per-variant `aura_prefix_bytes` (4,063,232 for the r3 loader) and the loader-byte rollback,
  implemented, with a replica test in `tests/macos/` that configures the display file and rolls it back to P's file byte
  for byte;
- `status` run with that tool on the Mac;
- P's configured file (`9825a103…`) kept beside `k114s-repair/known-good/boot-ctxr.bin`;
- the way back written into the D9b runbook: from macOS, the tool's `stage2` back to P's file; from a Linux that still
  boots, a one-boot `aura-try` of P's file.

### 5.2 D5a and D5 offline build (agent-run, 2026-11-15)

Offline, like D0. Nothing was installed. Nothing on the ESP, in `/boot` or in `/etc` was written, and the ESP was not read.
Outputs are in `$K114S_BUILD_ROOT/integrate/release-display-d5/`, all listed in its `SHA256SUMS`; the gate logs are in
`gates/`.

**Package decision: an upgrade of `linux-k114s-r3b`, not a third K114s package.** The brightness kernel keeps the name,
`pkgbase` and kernel release of the D1 package (`linux-k114s-r3b`, `7.3.0-17.v272-11-k114s-r3b-ARCH`) and only raises the
version to `7.3.0.r3b.b1-1` (`vercmp` against `7.3.0.r3b-1`: newer). Reasons:

- ESP (G2): in the window the ESP holds the r3a and r3b images, about 110.8 MB free with the r3b UKI and about 101.8 MB with
  two trial Stage 2 files. A new package name would be a new preset and a third kernel image (about 79.4 MB), which breaks
  the 88,080,384-byte guard. In place, the hook rewrites `omarchy_linux-k114s-r3b.efi`; the peak is the G2 row "during
  the D5a rebuild". The new `Image` is the same size as r3b's (54,282,752 bytes) and the dry-run initramfs has the same 81
  modules, so the UKI is expected at D1's size. G2 is still recomputed from `df -B1` before D5a.
- Window and way back (4.3, 4.4): `Omarchy/linux-k114s-r3b`, the one-shot entry, `this boot started:
  Omarchy.linux-k114s-r3b`, the macOS manual edit to the r3b default and D9a all keep their names. The release keeps the GPU
  guard's opt-in `~/.config/k114s-gpu-desktop-r3b` and `check-package.sh`'s name rule. The D1 package stays in
  `/var/lib/k114s-recovery/` as the downgrade (`pacman -U` of it, attended, from a boot on P's Stage 2).
- Telling them apart on a running system: `uname -v` reads `K114S-R3B-B1` (r3b: `K114S-R3B`), `pacman -Q
  linux-k114s-r3b` gives `7.3.0.r3b.b1-1`, and the kernel log has `brightness requests below 10 nits are raised to 10 nits`
  once the D5 tree is in.

The PKGBUILD takes it as `K114S_CAND=r3b-b1` (source `src/r3b-b1`, output `build/r3b-b1`, and a guard that the source
carries the floor). The series is `patches/linux/r3b-b1.series`: r3b's six, the release suffix, then brightness 0001-0003,
0005 and 0006 with `git am`, no fuzz. Applied from the repository files alone onto the base they give the built tree
(git tree `2e785a04fdfa601a25b1db5026192712d8b7b0a1`; r3b's is `3ad64f0f…`).

| Output | sha256 | Notes |
| --- | --- | --- |
| `pkg/linux-k114s-r3b-7.3.0.r3b.b1-1-aarch64.pkg.tar.zst` | `0ca7b7593340981702ba306ffb93168cb67615e5a62a162270f9117aff3491ba` | 47,536,324 bytes. Full build from clean output (`Image modules dtbs`, `-j18` at `nice 19`, 357 s), r3b's `.config` byte for byte. `vmlinuz` `93b7870c4eb8332b464fc18c2a2ffcd172d947f49d5be255c3bba2dbc6dd61b4`. Against the D0 package (`438c4efe…`): the same 2,035 files, the same config and 46 dtbs, and of 1,972 modules only `appledrm.ko` differs in code or data (`k114s-cmp-modules`) |
| `dtb-p/t6050-k114s-r3b-brightness.dtb` | `5b6b83c8cd5e59333182f6ca37f22b1e99bd029daa1342d186daee096b292fda` | `dts/t6050-k114s-r3b-brightness.dts`: the D4 display tree plus `t6050-k114s-brightness.dtsi`, on P's includes. Against the D4 tree `914ec379…` it adds exactly one property: `apple,min-brightness = <10>` on `/soc/dcp@48ae00000/panel`. It refuses to build with `K114S_D0_DISPLAY_OFF` |
| `dtb-p/display/…`, `dtb-p/display-off/…` | `914ec379…`, `2c870ba9…` | Controls, rebuilt from the same includes: D0's display tree and P's tree, byte for byte |
| `stage2/boot-ctxr-disp-bl.bin` (D5) | `e089e8c843ee7c22f1c3b4c25c1201924667151d39573ebdfeeb3f595c2b2402` | 4,506,159 bytes. Prefix `582df9bb…` (r3 loader), tree `5b6b83c8…`, trailer `9d8dc11e…`. The control rebuild of D0's `-disp` gives `177f0028…` again |
| `systemd/k114s-first-boot.conf` | `cc2c17ef475bea81c368e048f9e6f7975356a38ac49eb3cc0cc059620d0c0fd5` | The repository's `linux/brightness/systemd/k114s-first-boot.conf`, for `/etc/systemd/system/systemd-backlight@backlight:apple-panel-bl.service.d/` before the D5 boot (root step, not done) |

| Gate or check | Result | Evidence |
| --- | --- | --- |
| `check-package.sh` against `linux-aurora` and against `linux-k114s` | PASS, both. It now also requires a `…r3b.b<N>` version to carry the floor in `appledrm` (the D0 package reports `floor no` and still passes) | agent-run |
| `pacman -U --print` | `linux-k114s-r3b 7.3.0.r3b.b1-1` only | agent-run |
| G6: no `appledrm` in the initramfs | PASS: `appledrm` is `=m`; the `mkinitcpio -r <package root>` dry run gives 81 modules and no `appledrm`, as D0's. The real UKI is checked again after D5a | agent-run |
| Brightness host cases (`tests/brightness/run-dcp-backlight-host.sh src/r3b-b1`) | 28 cases, 0 failed (r3b without the series: 27). With the floor line removed, `backlight_floor_test` fails | emulator/replica |
| `tests/brightness/test-backlight-check.sh` | 22 checks, 0 failed (drop-in text included) | emulator/replica |
| `tests/lint-display-gpu-dtb.py --k116s` on the D5 tree | PASS. The lint now knows the floor: one cell, 1 to 999 nits (0, 1000 and two cells fail, 5 passes) | agent-run |
| `tests/lint-dtb.py`; `tests/k114s-adt-display-facts.py --dtb` (saved ADT copy) | PASS; 17 comparisons, none failed | agent-run |
| QEMU `k114s-qemu-smoke shell` and `modules` | PASS: banner `K114S-R3B-B1`; `ok=1965 failed=7`, the same seven as r3b; no Oops, BUG or WARNING | emulator/replica |
| `tests/linux/run-r3.sh` | 1,053 pass, 0 fail | emulator/replica |

Read from source, for the lead: brightness 0003 makes D590 a handled callback on 27.2, so the firmware-27 size check
(`iomfb.c`, `iomfb_v27_callback_size_valid`) now applies to it: a D590 shorter than 20 bytes would mark the DCP crashed,
where before it logged an unknown callback. That check comes from `231d448e4b`, an ancestor of Jens's `907bb7ec59`, so his
K116s run (same DCP image `3D6C8857`) had it too. D5a boots 0001-0003 before any panel trial, and 0003 is the first to drop
if D5 shows `unqualified IOMFB callback 590`.

Not done here: G2's measurement, the D5a install and UKI rebuild, the drop-in install, and the trials. They are the lead's,
with the owner, in the second window (4.4). The D5a rebuild runs from a boot on P's Stage 2 (section 12, `appledrm` and
the initramfs).

### 5.3 Result of the display window, boot 1 (2026-11-15)

The internal display runs on the DCP (`appledrm`) at 3024x1986, 120 Hz, in the D5-D9 window (`docs/r3-display-d5-d9.md`,
section 4a). The black screens of earlier DCP boots were Hyprland colour management (`render:cm_enabled`), not the hand-off;
`linux/display/k114s-dcp-colour` adds `cm_enabled = false` only when `ASAHI_M5_BRINGUP=1`. T2 had been agent-checked only.

| Stage | Result | Label |
| --- | --- | --- |
| D4 picture (DCP, 3024x1986, 120 Hz) | seen with colour management off; black with it on | owner-observed |
| D5 brightness | ladder read back; the panel dimmed and recovered | agent-run, owner-observed |
| D7 DPMS | off and on three times | owner-observed |
| D8 night light | on and off, no DCP crash; the warming is not recorded | agent-run |
| Look | colours normal, text sharp, movement smooth; the notch covered some text (cutout overlay now installed) | owner-observed |
| D6 VRR | not yet run (boot 2) | unknown |
| G6b | stopped: an initramfs from this boot contains `appledrm` (blocks D9, F16) | agent-run |

## 6. Device-tree nodes (display tree)

Everything stays `disabled` in the tree. The loader enables it only after its ADT, DT and DART checks pass. source-read
(aura `t6050_check_adt/dt/darts`, `t6050_publish`).

| Node | Properties | K114s ADT value it must equal | Where | Evidence |
| --- | --- | --- | --- | --- |
| `/aliases` | `dcp = &dcp; disp0 = &display;` | (the loader requires both; it writes `apple,notch-height` into `dcp`) | display-gpu.dtsi | source-read |
| `/display-subsystem` (`display:`) | `compatible = "apple,display-subsystem"; iommus = <&disp0_dart 0>;` | dart-disp0 `l1-tt-0` present | display-gpu.dtsi | source-read (ADT) |
| `&dcp_dart` iommu@48a340000 | base `reg <0x4 0x8a340000 0 0x20000>`, AIC 990; ours `apple,dma-range = <0x100 0x0 0x300 0x0>` | dart-dcp `0x48a340000 + 0x20000`, vm-base `0x10000000000`, vm-size `0x30000000000`, `l1-tt-23` | base + display-gpu.dtsi | source-read (ADT) |
| `&disp0_dart` iommu@48a300000 | base `reg <… 0x8a300000 0 0xc000>, <… 0x8a314000 0 0x4000>`, AIC 990; ours same `apple,dma-range` | dart-disp0 `0x48a300000 + 0xc000`, same window, `l1-tt-0`, `l1-tt-16` | base + display-gpu.dtsi | source-read (ADT) |
| `&dcp_mbox` mailbox@48ae08000 | base `apple,t6050-asc-mailbox`, `apple,asc-mailbox-v4`, `reg + 0x4000`, AIC 1043/1044/1045/1046 | dcp interrupts `[1044, 1043, 1046, 1045, …]`; dcp reg[0] + 0x8000 | base | source-read. Register and compatible checked by the loader and the facts tool; the **interrupts** by no tool yet (G5) |
| `&dcp` dcp@48ae00000 | base `reg` coproc `0x48ae00000+0x4000`, disp-0..4, iop-vbar `0x48a850000+0x4000`; `iommus = <&dcp_dart 23>`; `piodma { iommus = <&disp0_dart 16>; }` | dcp reg[0] `0x48ae00000+0x88000`, reg[1] `0x48a850000+0x4000`; disp0 reg[0..4] `0x488000000+0x4000000`, `0x48a240000+0x10000`, `0x48a3ac000+0x4000`, `0x48a800000+0x800000`, `0x286700000+0x114000` | base | source-read; the loader compares at boot, the tool on the display tree (G5) |
| `&dcp/panel` | `compatible = "apple,panel-k114", "apple,panel"; width-mm = <302>; height-mm = <198>;` | no ADT panel node. disp0 `dot-pitch-float` 254.6 ppi gives 301.7 x 198.1 mm at 3024x1986 | display-gpu.dtsi (binding `3adc985b`, in v272-11) | source-read |
| `&dcp/panel` (D5) | `apple,min-brightness = <10>` | none (ours, unmeasured) | brightness.dtsi | source-read |

**Written by the loader, never in our tree** (it refuses a tree that already has `memory-region`, `clocks` or
`apple,bw-scratch`, and it overwrites `apple,clock-ids`): `apple,firmware-version`, `apple,firmware-compat` (`<27 2 0>`)
and `apple,firmware-uuid`; `clocks`, `clock-names`, the `clock-dcp-firmware-<id>` fixed clocks and `apple,clock-ids <361
458>`; `apple,bw-scratch` and `pmc-metadata`; `/reserved-memory/framebuffer@10fd41b4000` as `memory-region "framebuffer"`
on `dcp` and `display`; `apple,max-brightness` (1000); `apple,artwork-display-gamut` (`Rec2020`); `status = "okay"` on
`dcp`, `display`, the mailbox and both DARTs; `/chosen/asahi,t6050-dcp-handoff`. source-read (aura
`kboot_display_handoff.c` 3487-3600, `firmware.c` `firmware_set_fdt`).

**Not ported:**

- `dcpext0`-`3`, their DARTs and `apple,clock-ids`: internal panel only on 26B8125 (aura #226: `dcpext0` delays the
  display by 16 s). The J714s log binds its external engines; that is not our case.
- The J714s panel node, `t6050-j714s-display.dtsi` routes, DP PHYs and muxes.
- `K114S_R3_EDP`: r3b lacks #1688, so the property would be ignored.
- `power-domains` on `dcp`: the base and the K116s have none. The ADT `power-gates` ids (`0x25e` dcp; `0x260`, `0x25f`,
  `0x25d` disp0) are not mapped to `ps_*` nodes. The display stays powered because iBoot left it on and the command line
  keeps `pd_ignore_unused clk_ignore_unused m5_pmgr_ro`. Keep them. unknown whether anything else depends on this.

## 7. Kernel config, parameters and the command line

**Config** (r3b `.config`, no change needed beyond the package name): `DRM_APPLE=m`, `DRM_SIMPLEDRM=y`, `SYSFB=y`,
`SYSFB_SIMPLEFB=y`, `BACKLIGHT_CLASS_DEVICE=y`, `APPLE_DART=y`, `APPLE_MAILBOX=y`, `APPLE_RTKIT=y`, `APPLE_SART=y`,
`DRM_ASAHI=y`, `MTD_PHRAM=m`, `KUNIT` not set. source-read. `appledrm` must stay a module and stay out of the initramfs
(G6).

**Parameters:**

| Parameter | Value for D4 | Why | Evidence |
| --- | --- | --- | --- |
| `appledrm.fw27_panel_vrr` | `0` | The installed `/usr/lib/modprobe.d/aurora-m5-vrr.conf` sets `1`, tested on the J714s LCD only. `/etc/modprobe.d/aurora-m5-vrr.conf` with `options appledrm fw27_panel_vrr=0` masks it (same name). `appledrm` is not in the initramfs (G6), so it loads from the root filesystem and reads `/etc/modprobe.d`. Check `/sys/module/appledrm/parameters/fw27_panel_vrr` reads `N` | source-read; unknown on hardware |
| `appledrm.show_notch` | leave as installed | `/chosen/asahi,show-notch = "1"` implies it (`dcp.c:365`), and `omarchy-mac` already ships `/usr/lib/modprobe.d/asahi-notch.conf` with `options appledrm show_notch=1` (found in D0). The expected mode is 3024x1986@120. The K116s height changed between loaders, so the K114s may come up at another height | source-read; unknown |
| `systemd.restore_state` | prefer the drop-in (D5) | keeps the unattended N/2 brightness write off | source-read |
| `pd_ignore_unused clk_ignore_unused m5_pmgr_ro m5_pmgr_allow=…` | keep | DCP power, section 6 | source-read |

**Command line:** no per-kernel line. A `KERNEL_CMDLINE[linux-k114s-r3b]` key would replace the default line for that
kernel, not add to it, so it would copy the whole line into `/etc/default/limine` and could drift from r3a's later. r3b's
line stays equal to r3a's. Check it the P5b way: the `cmdline:` lines of the `//linux-k114s-r3b` and `//linux-k114s`
entries in `limine.conf`, normalised and compared, never printed (G3, and after D5a). D4 then differs from D3 by the
display section alone (3.2). source-read.

## 8. Firmware

- **DCP:** there is no file. `drivers/gpu/drm/apple` has no `request_firmware`. iBoot preloads the DCP image from the
  macOS 27.2 26B8125 stub (`3D6C8857-…`, running=1), and the loader passes its UUID and `firmware-compat <27 2 0>` (from
  `mBoot-20457.41.3`), which picks `dcp_methods_27_2` (AppleDCP-1317.40.16). source-read; seen on hardware (K116s,
  upstream).
- Consequence: the stub's OS firmware must stay 27.2 26B8125, and the hard constraints already forbid touching macOS and
  boot policy. Any other image is refused by the loader (safe), and must never be added to its table without that
  image's method table.
- **GPU:** 26B8125 through the loader, unchanged. seen on hardware (K114s).
- **Userspace, already installed:** `omarchy-aurora-firmware 20261014.j714s9-1` (its `60-aurora-m5-display` generator
  sets `AQ_DRM_DEVICES`, `AQ_NO_MODIFIERS=1`, zink and `ASAHI_M5_BRINGUP=1` when
  `/dev/dri/by-path/platform-display-subsystem-card` exists; our guard steps aside then, which is why D1 proves the GPU
  desktop first), `hyprland-m5 0.57.2-2`, `mesa-aurora` j714s2. seen on hardware (K114s), package state.

## 9. Checks per trial

**First command of every trial boot** (root, read-only). Save the output under `/var/lib/k114s-recovery/display/`:

    tr -d '\0' < /proc/device-tree/chosen/aurora,trial; echo; uname -r
    tr -d '\0' < /proc/device-tree/chosen/asahi,t6050-dcp-handoff 2>/dev/null; echo
    sudo cat /dev/mtd1ro | tr -d '\0' | grep -E 'DCP:|GPU:|T6050|display|WDT'
    ls /sys/class/drm /sys/class/backlight; cat /sys/class/graphics/fb0/virtual_size
    grep -E 'mailbox-recv' /proc/interrupts

**Expected in every loader log (D2-D9):** the five `DCP: T6050: __OS_LOG … overlaps /memreserve/` lines. Not a failure.

**D4 hand-off pass** (all of them):

- `handoff = published`. On `dcp@48ae00000`, `apple,firmware-uuid = 3D6C8857-…`, and
  `od -An -tu4 --endian=big /proc/device-tree/soc/dcp@48ae00000/apple,firmware-compat` prints `27 2 0`. The loader log
  says `internal display handed off: firmware 27.2` and `external display engines not handed off on firmware 27.2`.
- `dmesg`, in the J714s order (#14): simpledrm first, then `DCP booted`, `[drm] Initialized apple … for
  display-subsystem`, `panel ADT: … panel node absent, dimensions 302x198 mm`, then `fb0: appledrmfb`. None of `DCP has
  crashed`, `RTKit: co-processor has crashed`, `DCP_FIRMWARE_UNKNOWN`, `present dropped`, SError or Oops.
- A new card (expected `card2`) with an `eDP-*` connector. Its `modes` lists only `3024x1986` at 120 Hz. The boot
  framebuffer is gone. unknown: the card index, `eDP-1` or `eDP-2`, and the height.
- `/dev/dri/by-path/platform-display-subsystem-card` exists. The session runs Hyprland on it through zink, at 120 Hz
  (`hyprctl monitors`), with `vrr` false and `currentFormat` recorded (`XRGB8888` on the J714s). Mailbox counts rise as in
  D1.
- `/sys/module/appledrm/parameters/fw27_panel_vrr` = `N`.
- `apple-panel-bl` exists with `max_brightness` 1000. **Read it only. No write until D5.** Record its `brightness` and
  whether the log has `no loader brightness reported; backlight starts at 500 nits` (the J714s on v272-12 logs it; whether
  v272-11 has the line is the D0 diff).
- Colours are right on an ordinary Omarchy screen. In r3b the T6050 plane still offers XRGB8888 (`xrgb_is_alpha` only
  covers H17G and T8142, `apple_drv.c:1152`). If colours are wrong, #1873 is the follow-up. source-read.

**Monitor rules first:** `monitors.lua` has `Unknown-1` and `eDP-1`. Add `eDP-2` before D4. Both rules are harmless.

**Stop conditions, any stage:** a `refused` where `published` was expected (D4, D5), any DCP or RTKit crash, an SError or
Oops, a GPU mailbox count that stays flat (D1, D5a), or a window check of 4.2 that fails. Power off, fall back (4.3), keep
the logs, and open a finding on the stage's issue.

## 10. Burn-in precautions (OLED, #22)

These hold from D4 until D7 has passed:

- Keep sessions short. Never leave a static screen unattended. Shut down instead of idling. Today the panel is lit at the
  boot level with no control, so this applies already.
- **At D4 the level may be 500 nits.** The J714s log shows the driver starting the backlight at 500 nits when the loader
  reports no brightness (#14, v272-12). If r3b does the same, that is bright for an OLED with static UI, and there is no
  control until D5. Keep D4's session to the pass list, use a dark theme, auto-hide the bar if possible, and keep the
  screensaver on (`omarchy-launch-screensaver`). No brightness keys or `brightnessctl` before D5. source-read
  (J714s); unknown (K114s).
- Keep no boot-time brightness write (the drop-in, D5). Kernel floor 10 nits (patch 0006). Alt + brightness-down (held)
  reaches 0 without it (r3-brightness.md).
- DPMS off on the DCP presents 0 nits and keeps the pipe running (source-read, r3-brightness.md). Whether 0 nits is black
  on this panel is **unknown**: the K116s firmware logged non-zero drive values around 0 nits. Until D7 shows black, treat
  DPMS-off as dimming, and use power-off for long breaks.
- No upstream DPMS power-off exists for T6050. linux #1941 and #2019 are T8142 on firmware 27.0 only. Do not port them
  without an OLED result.
- Pixel shift, a low-contrast bar and the idle profile are Omarchy-side items for #22 after D7.

## 11. What to ask TripleU613 (betizzel/omarchy-m5) and upstream

For TripleU613 and betizzel (#12, #14):

1. **Answered (22:55Z): yes, from us.** We open the PR that adds aura #226's pin for `3D6C8857` (internal panel only)
   beside the J714s `C51FB0C8` row in their `m1n1-aurora` recipe and `patches/j714s-27.2/aura`, the J714s row untouched.
   They build it and boot it on the J714s before merging. Our `patches/aura/0001` is the source.
2. **Answered except the blacklist test.** Their v272-12 DCP boot log is in section 2. Accept their offer: does
   `module_blacklist=appledrm` after a published hand-off keep simpledrm on the J714s?
3. Scope `aurora-m5-vrr.conf` (`fw27_panel_vrr=1`) to the J714s, or default it off for OLED boards. The file ships to
   every image.
4. Reconsider #1688 (our `sleep-lid/0004`-`0006`). The K114s stays on simpledrm until D9b and needs it for `eDP-1` and
   the lid (r3b-kernel.md section 7).
5. Who owns `omarchy-mac`'s `wait-for-display`? It tests `/proc/device-tree/soc/display-subsystem` and
   `platform-soc:display-subsystem-card` (the M1/M2 layout). On T6050 the node is at the root, so the greeter never waits
   (#25). source-read. We will send the fix wherever they point.

For aurora-silicon upstream:

6. Jens Axboe or the K116s owners: CTM or hyprsunset on a T6050 OLED (is `set_matrix` A473 on 27.2 safe?); a by-eye
   brightness write; whether 0 nits is black; `fw27_panel_vrr=1` on an OLED. None has a public result. Also the source of
   the `program_dbv` log r3-brightness.md cites (linux #1647 is a PCI pull request).
7. linux #1873: its boot check on the K114c, before we take it.
8. aura: why the trial watchdog does not arm on the K114s. An armed watchdog would turn a D4 hang into an automatic
   fallback.
9. After D4 passes: a linux PR with the K114s display section (as #1648 did for the K116s), and a K114s report on aura #226.

## 12. Risks and unknowns

| Risk | Mitigation | Label |
| --- | --- | --- |
| Installing r3b under the shared name replaces r3a, the default, and its UKI | rebuild as `linux-k114s-r3b`; G3 before D1 | source-read |
| A full rebuild in the window writes three images on an ESP that holds two; the 88 MB guard passes and does not stop it | the window rule (4.1 rule 4, 4.4); the window check of 4.2 | source-read |
| `limine-snapper-sync` copies an image into a snapshot entry in the window | its 85 % limit does **not** skip it in the one-image states (63.6 % used, 79.0 % after one kernel's +76.6 MiB); its timer (hourly, and 10 min after each boot) and watcher are stopped in every boot of the window, checked before each step, and a `Snapshots` entry has its own undo (4.2; trials runbook E12, block Xs) | source-read; usage measured |
| Updates pause for the window, overriding P6 | the owner decision in 4.4; default D1-D4 only | source-read |
| `default aurora` is gone and `restore-repair` stops for lack of space in the window | the r3b image comes off first (4.3); replica case and Mac `--check` before D1 | source-read |
| The display section does not build on P's includes | the r3b includes, with D2 also the first r3b boot on the new base ranges (3.2) | unknown |
| r3b on v272-11 misses a v272-12 drm/apple fix | the D0 diff and record (3.1) | unknown |
| The new loader (D3) or the hand-off (D4) hangs with no watchdog | forced power-off, then P (4.3). D1 (and D5a for D5-D8) make the pending-one-shot case safe | seen on hardware (K114s: no watchdog) |
| The DCP dies after it evicts simpledrm, with no in-kernel retreat on fw27 | power-off. No reliance on blacklist or `nomodeset` | source-read |
| A wrong `dcp_mbox` interrupt is not caught by the loader (its register is) | G5 tool extension | source-read (checks); unknown (effect) |
| The interrupt-only GPU mailbox on r3b hangs the GPU or suspend | G4: the lead's acceptance, then D1 with a GPU-desktop session. Suspend stays blocked | seen on hardware (interrupt firing on r3a and the J714s); unknown (r3b) |
| The backlight starts at 500 nits on an OLED with no control until D5 | short D4 session, dark theme, screensaver (section 10) | source-read (J714s); unknown (K114s) |
| A 60 Hz modeset crashes the DCP | `only_120hz_modes` in r3b | source-read; seen on hardware (K114c) |
| XRGB read as alpha gives wrong colours | #1873 follow-up | seen on hardware (K114c); unknown on K114s |
| VRR on an OLED, untested anywhere | `fw27_panel_vrr=0` until D6 | unknown |
| The PMU-temperature reply (brightness 0001) changes OLED firmware behaviour | D5a boots it alone first; D5 repeats D4's list | unknown |
| The panel does not follow brightness writes | the owner's stepped check; a macOS trace is the next step | unknown |
| 0 nits is not black, so DPMS does not protect against burn-in | section 10 | unknown |
| A CTM write crashes the DCP | D8 last, in a session that can be power-cycled | unknown |
| `appledrm` gets into the initramfs on a later rebuild | G6 check after every rebuild. Mechanism (D0, source-read): `HOOKS` has `autodetect` and `kms`, and `appledrm` has the modalias `of:N*T*Capple,display-subsystem`. A rebuild on a boot whose tree has an **enabled** display subsystem (after D4's hand-off, or any boot after D9b) would add it. So the D1 install and the D5a rebuild run from a boot on P's Stage 2, whose tree has no display subsystem | unknown |
| The mode height is not 1986, or the notch is cut | read `modes` at D4; `appledrm.show_notch=1` is a later, separate trial | unknown |
| After D9b no cheap way back exists; r3a on the display Stage 2 is untested | D9a first; D9b only with the tested macOS rollback (section 5) | source-read |
| The greeter races simpledrm | the `wait-for-display` path fix (11.5) before D9b | source-read |
| The lid counts the panel as external (`Unknown-1` on r3b) | suspend stays blocked; #1688 ask | source-read |
