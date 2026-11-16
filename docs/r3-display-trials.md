# r3 display trials: hyprland-m5, the display window, r3b beside r3a, and the trial boots D1-D4

Written 2026-11-15, after the r3a promotion (`docs/r3a-promotion.md`, PR #88: `PROMOTION COMPLETE` at 16:06) and D0
(`docs/r3-display-plan.md` section 5.1, PR #91). This is the runbook the lead pastes block by block for stages D1 to D4
of the display plan, plus the adoption of `hyprland-m5 0.57.2-3` (H). It replaces the plan's one-boot-per-stage table
with three reboots (section 1) and says why each combination keeps a failure attributable (section 2).

**Authorisation.** The owner authorised D0-D4, including the panel hand-off, to run without asking again while the owner
is at the Mac (intake, recovery log 14:50). The owner asked for as few reboots as possible. The lead records G0 and G4 in
`$D/gates.txt` before the first arm (T1's block checks for both lines).

Evidence labels as in `docs/r3-display-plan.md`: **source-read**, **seen on hardware (board)** (K114s: agent-run on
this Mac unless it says owner), **emulator/replica**, **unknown**. Nothing in this runbook has run as root. Every write
below is the lead's, in the order given, with the owner at the Mac.

Hard limits for every step: nothing touches macOS, Apple's boot policy, Stage 1, Apple firmware or NVRAM; no security
control is weakened or bypassed (no key is imported into pacman's keyring, no guard marker such as `allow-low-esp` or
`allow-coupled-update` is used); the speakers stay off (nothing here touches sound, and the render load runs with
`--ao=null`); suspend stays blocked (the four masked targets and the two `30-k114s-r3a-trial.conf` drop-ins stay); no block
prints the kernel command line or anything that unlocks the disk (blocks compare command lines, never show them; the
records in `$D` are root-only); the configured `m1n1/boot-ctxr.bin` and `default_entry` are never written. A hang has one
recovery: hold the power button until the Mac is off. The loader's trial watchdog does not arm on this Mac, so nothing
resets a hung trial by itself. From W0 to C4 `limine-snapper-sync` is held off with a plain `systemctl stop` of
`snapper-cleanup.timer` and `limine-snapper-sync.service` in every boot (E12): no unit file, configuration or limit is
changed, and nothing is disabled or masked, so a reboot starts both again and the first block of each boot stops them.

## 1. The boots

| Boot | What runs | Tests | Falls back to, if it hangs |
| --- | --- | --- | --- |
| (none) session 0, on today's default boot | H (`hyprland-m5 0.57.2-3`, a log-out only), W (hold the snapshot sync off, open the window), I (r3b beside r3a), S (two trial Stage 2 files onto the ESP) | H: Hyprland and the title-bar plugin, by a log-out and log-in. I: G3, G6 | nothing booted |
| **1. T1 = D1 + D2** | one-shot `Omarchy/linux-k114s-r3b` + `aura-try` `m1n1/boot-ctxr-disp-oldldr.bin` (installed loader `1546dd50...` + display tree `914ec379...`) | D1: r3b boots, trackpad, the GPU desktop under a five-minute render load, the GPU mailbox keeps firing. D2: the installed loader **refuses** the hand-off on the display tree; the display section stays inert; the panel stays on simpledrm | before Limine: r3b on P (the one-shot is still pending). After Limine: r3a on P (the default) |
| **2. T2 = D4** (with D3's loader checks) | one-shot `Omarchy/linux-k114s-r3b` + `aura-try` `m1n1/boot-ctxr-disp-pinldr.bin` (the K114s-pin loader `beceb683...` + display tree `914ec379...`) | the hand-off: `published`, `card2-eDP-1` (or whatever appears) at 3024x1986@120 (or 1964), `apple-panel-bl` read only, Hyprland on eDP at scale 2, the GPU as in T1, brightness untouched | before Limine: r3b on P, which T1 proved. After Limine: r3a on P |
| **3. default** | `default_entry` (r3a on P), nothing armed | block C, then the close (C1, C2, X, C4) | the default again; section 5 |

Three reboots. Conditional boots, only on a failure, each one boot: **D1 alone** (one-shot only, P's Stage 2) after a T1
kernel-side failure; **D3** (one-shot + `m1n1/boot-ctxr-gpu-pinldr.bin`, the pin loader on P's exact tree) after a T2
failure before the kernel, a GPU-side failure in T2, or a T2 black screen whose kernel log does not show the display path
failing after the root mount (block A). The macOS check of the plan's G1 (two more boots) is optional and not in the
count (decision E10).

## 2. Decisions, with the facts behind them

**E1. D1 and D2 share boot 1; D4 has a boot of its own; D3 runs only if D4 fails in a way that points at the loader.**

- *D1 + D2 together.* D2's delta over D1 is the display section of the tree on the installed loader. That loader sees
  that the tree describes the panel, checks the ADT, finds `3D6C8857-...` where it pins `C51FB0C8-...`, and refuses
  before it publishes anything: it writes `/chosen/asahi,t6050-dcp-handoff = refused` and leaves every display node
  `disabled` (aura `t6050_handoff`, source-read; the binary carries both strings, agent-run `strings`). Linux binds no
  driver to a disabled node, and `appledrm` is not in r3b's initramfs (G6), so the kernel side of D2 is D1 plus the
  disabled `display-subsystem` and panel nodes, the `dcp` and `disp0` aliases and an `apple,dma-range` on two disabled
  DARTs (`gates/dtb-node-diff.out` in D0). D2
  touches the display path, D1's new parts are the kernel, the GPU mailbox and the trackpad: different subsystems. What
  the failure tells:
  - a hang before Limine is the Stage 2 file (installed loader on the display tree). The next boot is r3b on P with the
    one-shot still pending: that boot is D1 alone, measured for free;
  - a hang after Limine is r3b (or, much less likely, the inert nodes). The next boot is the default; the conditional
    D1-alone boot separates the two;
  - a clean boot proves both, and is what T2's fallback needs: r3b on P (T2's pending-one-shot case) runs the same kernel
    on the same base as T1, minus the inert section.
  Cost: one reboot fewer on success, the same count on failure.
- *D3 folded into D4.* The pin loader is the installed loader's source plus Aura 0008 (`betizzel/omarchy-m5#18`), built
  with LLVM 23.1.3 (`aura-pin/build-info.txt`). On P's tree it never reaches 0008's code: the loader stops at "the
  device tree does not describe the internal display: no handoff" before the ADT check (seen on hardware, K114s: every
  P boot logs that line and no `DCP image ... is not ...` line). So D3 tests only the binary (compiler and the
  64 KiB layout shift) on everything else the loader does, and D4 tests that too. If D4 passes, D3 adds nothing. If D4
  fails before Limine, the next boot is r3b on P (T1 proved it), and **then** D3 separates "the binary" from "the
  hand-off" in one boot, the same count as running D3 first. If D4's kernel side shows a GPU fault, D3 separates the
  loader's GPU set-up from the hand-off the same way. D3 is skipped only on evidence: block A finds, in the kernel log of
  the T2 boot (`journalctl -b -1`, filtered), a DCP, RTKit-on-DCP or apple-drm failure line after `Switching root`. That
  points at the hand-off itself. If that log is empty or ends early (a forced power-off can lose the last seconds of
  info-level kernel lines, which journald syncs every 5 minutes, not at once), or the hang came before the disk unlock or
  the root mount (`appledrm` cannot have loaded there: G6), or the failure lines are not on the display path, the new
  loader binary is as likely as the hand-off, and D3 runs (one boot) before anything is attributed or reported on #17.
- *D4 not combined with anything.* It is the only stage that risks the picture, and after it the only kernel retreat
  is a power-off (`appledrm` evicts simpledrm as it binds; there is no in-kernel way back on firmware 27,
  `docs/r3-display-plan.md` 4.3). Its fallback has to be a proven configuration, which T1 gives it.
- *Boot 3 cannot be saved.* The close removes r3b and puts the `linux-aurora` image back. Removing the running kernel's
  package from the D4 boot is unsafe (its module directory goes), and the D4 boot is the riskiest one to do ESP work in.
  The trial is one boot by design, so boot 3 is the return to the default anyway. The close puts the boot files back
  byte for byte (E5), to a state that booted many times since 16:06, so it needs no boot of its own.

**E2. The loader for D4 (and D3) is the pin loader of PR betizzel/omarchy-m5#18, not the r3 loader `582df9bb`.** The
lead's decision: the K114s trial validates the loader TripleU613 will ship. Built at
`release-display-d0/aura-k114s-pin/aura.bin`, sha256 `beceb683b63a6d421ce58061a55c14a6d09e0381a23c1a543df55f4cc8007392`,
4,063,232 bytes. It is not a D0 output (D0's `SHA256SUMS` does not list it; it was built for the PR from aura `22b71758`
plus `aura-j714s-27.2.patch` with 0008). What `582df9bb` carries that it does not:
- **#230** (`patches/aura/0002`): the loader writes `apple,firmware-version` on the GPU node, so the GPU driver tries the
  loaded build first. Without it the driver walks its table and logs one refusal before it admits the right build.
  **The GPU path does not need it**: this Mac runs the GPU today on the installed loader, which lacks #230, and logs
  exactly that (agent-run, this boot: `unsupported GPU firmware build ...`, `GPU firmware image not admitted: EINVAL`,
  then `GPU firmware build: 26B8125 for T6050 G17S, primary then secondary`). So the pin loader is used for D4 and D3
  as well, and D3's pass line changes: the `not admitted: EINVAL` line is **expected** (the same as on P), not a failure.
- `patches/aura/0003` (host-stub test fix): tests only.
- `0001` vs 0008: the same #226 pin table; 0008 keeps 0005's J714s row and messages and adds the `ext` flag
  (`external display engines not handed off on firmware 27.2`), which is the line D4 uses to tell the pin loader in the log.
Both loaders print the version string `1.0.0b13-g22b71758-dirty` (the pin loader's tree is `22b71758` plus a patch, as
the installed one is). A boot is tied to its loader by `/chosen/aurora,trial` (the file name), the file's sha256 on the
ESP, and, in D4, the 0008 log line.

**E3. The kernel stays r3b (v272-11). No rebase for D4.** D0 compared `drivers/gpu/drm/apple` from v272-11 to v272-12: 28
files, all from the base `c0a2a752`, all firmware-27 display sleep, the T6050 external engines and J714s-gated paths
(`v27_j714s`); no internal-panel or 27.2 fix for an `apple,k114s` board (`gates/v272-11-vs-12.txt`). v272-13 keeps the
base `c0a2a752` and changes only PCIe and ATC PHY suspend handling and a device-tree always-on for the ATC usb-aon domains
(betizzel `d2c5bdb25`, `c34484225`, source-read): nothing in `drivers/gpu/drm/apple`. TripleU613's DCP boot ran on
v272-12; what it shows that matters here (bind at about 2 s, `card2-eDP-1`, 120 Hz only, the 500-nit start) is already in
v272-11 (`dcp.c:4993`, the 120 Hz gate `iomfb.c:3066`). Re-check at D5a.

**E4. H runs first, in session 0, outside the window, and costs a log-out, not a reboot.** It is a package transaction,
so it cannot run inside the window (rule 4 of the plan's 4.1), and the window's first boot should not be the first time
the new compositor runs. `hyprland-m5 0.57.2-3` (betizzel `41d8d7786`) moves the three direct-scanout members to the end
of `Monitor::CMonitor`, so every stock member keeps its offset: compiled against the package's own headers,
`m_layerSurfaceLayers` is at `0x790` (stock) and `m_dsFailedClient` at `0x970`; against the installed 0.57.2-2 headers they
are `0x7b0` and `0x5b0` (agent-run, `packaging/omarchy-hyprland-titlebars-m5/abi-probe.cpp`). The stock
`omarchy-hyprland-titlebars 0.4.0-1` reads `0x790`, so its `titlebars.so` (sha256 `160ca037...`, the package's own file,
renamed `.disabled-k114s` at 14:49 on 2026-11-14) goes back unchanged. The repository's own rebuild
(`1:0.4.0+m5-1`, for 0.57.2-2) is not needed and is not installed. The package's files touch no hook trigger that
rebuilds an image (`usr/bin`, headers, `usr/lib/systemd/user/hyprland-session.target`; the Limine hook triggers on
`usr/lib/systemd/systemd` only).

*Provenance.* `hyprland-m5-0.57.2-3-aarch64.pkg.tar.zst`, sha256 `c87f2570...`, 51,124,129 bytes, comes from betizzel's
release `installer-build-inputs-j714s-4601e97e9413` (the release digest matches) and is listed with that sha256 in
betizzel's `0007` manifest. **Those two are what the trust rests on.** The detached signature and
`pkg-sig/candidate-signing-key.asc` come with the package, from the same release, so `Good signature` from
`0DA040FF52D5EC6FB6538769DBFEBBB2B6D116B1` shows only that the files agree with each other, not who made them; the key
itself says it is a developer key, "not a production release". H1 checks the sha256 first and the signature second (a
damaged download), in a throwaway keyring. The key is not in pacman's keyring and is **not** imported; the file installs
under this Mac's `LocalFileSigLevel = Optional`. The 0.57.2-2 package (`12e46eb0...`, the installed binary byte for
byte) is kept for the undo.

*Holds.* No hold is released. `hyprland-m5` is held twice in `/etc/pacman.conf` (line 7, the `apply-holds` block, and
line 12, the image's own list) and `omarchy-hyprland-titlebars` once (line 7). `IgnorePkg` holds back the upgrades
pacman chooses itself (`-Syu`); it does not hold back a file named to `pacman -U`, which at most asks `Install anyway?`,
and `--noconfirm` takes its default, yes (`pacman -U --print` of both files lists them with the holds in place,
agent-run). H1 checks after the install that the version moved and that both holds are still listed; the hold guard
(`00-k114s-hold-guard.hook`) does not name either package.

*Order.* The plugin goes back only after the log-out and log-in (H3), once the running compositor is the 0.57.2-3
binary: put back while the 0.57.2-2 compositor still runs from memory, anything that floats would load it into the
mismatched `CMonitor` layout (`0x7b0`) that crashed the 2026-11-14 sessions. The click test (H4) floats a workspace with
`hyprctl eval`, which applies the mode without saving it in `~/.local/state/omarchy/workspace-layouts/`, and puts the
saved mode back at once, so a crash during the test cannot leave a floating workspace that loads the plugin at every
later login. H-crash is the way out of a crash loop without a mouse and without the lead.

**E5. The window takes the `linux-aurora` image off and puts the same bytes back.** P7 and the plan's 4.4 remove it
with `limine-entry-tool --remove-uki linux-aurora` and rebuild it at the close. A rebuild makes a new, unbooted image,
and from a DCP boot it would put `appledrm` in its initramfs (plan, risk G6). So W0 keeps the image (`72f5d32c...`) and
`limine.conf` as they are, W1 records the file the removal leaves, and the close (X) puts both back byte for byte,
only after `limine.conf` reads exactly as W1 left it. The P6a boot proved that image. The close then compares the whole
boot record with the one taken before the window (`no boot file changed`). If the file differs (something rebuilt
an image during the window), X stops. If the only difference is a `Snapshots` tree from `limine-snapper-sync`, block Xs
removes it and puts the saved file back (E12); otherwise the fallback is P5b's rebuild from a boot on P.

**E6. Two trial Stage 2 files on the ESP, the third on the Linux disk.** `-disp-oldldr` (T1) and `-disp-pinldr` (T2)
are copied in step S, so T2 is armed from the T1 boot without another ESP copy. `-gpu-pinldr` (D3) waits in `$D`.
Budget, measured base 111,022,080: after W1 about 190,275,584; after I1 (r3b's image at r3a's size plus 64 KiB) about
110,790,000; after S (8,946,708 bytes) about 101,840,000. The installed 88 MB guard only runs for package transactions,
and the only ones in the window are I1 (about 190 MB free) and C2 (about 110 MB free, after C1).

**E7. The brightness drop-in goes in before T2.** With the hand-off, `apple-panel-bl` appears, and `99-systemd.rules`
starts `systemd-backlight@backlight:apple-panel-bl`, whose `load` with no saved level writes the current level back (the
500-nit start), a level-carrying present a few seconds into the boot (`docs/r3-brightness.md`). "Brightness untouched"
in D4 needs that write gone, so I0 installs `linux/brightness/systemd/k114s-first-boot.conf` (the plan has it at D5).
It is inert until the device exists. T2 checks the unit was skipped and nothing was saved.

**E8. `appledrm.fw27_panel_vrr=0` from `/etc/modprobe.d/aurora-m5-vrr.conf`** (same name as the installed J714s file,
which sets 1; the `/etc` file replaces it). `appledrm` loads from the root filesystem (G6), so it reads `/etc`.

**E9. The r3b GPU-desktop opt-in is made in session 0.** `~/.config/k114s-gpu-desktop-r3b` (guard v3) makes T1's first
session the GPU-desktop session D1 asks for, without a log-out cycle in T1. On T2 the guard steps aside anyway (the DCP
card exists) and `60-aurora-m5-display` sets zink. Undo: `rm ~/.config/k114s-gpu-desktop-r3b`, then log out.

**E10. The macOS check of G1 is optional; recommended: skip it.** It costs two boots (macOS, then the default) and
proves only read-only output (`status`, `restore-repair --check`) on the window layout. The replica case for that layout
passed in D0 (`tests/macos/test-promoted-esp.sh`, 103 checks); the same tool (`3bfa3d11...`) passed `status` and
`restore-repair --check` on the real ESP in P4b; and the window's first way back, a power-off, needs no macOS. If the lead
keeps G1 as written, run it between I1 and T1 (section 4, M).

**E11. After the close:** r3a stays the default; `linux-aurora` and its image are back (byte for byte); `linux-k114s-r3b`
is removed (its package stays in `$D` for D5a, which installs a later version under the same name); `hyprland-m5
0.57.2-3` and `titlebars.so` stay, held; `/etc/modprobe.d/aurora-m5-vrr.conf`, the brightness drop-in, the `eDP-2` rule
and the r3b opt-in stay (each is inert without a DCP boot or an r3b kernel, and each is what the next window needs).
The trial Stage 2 files, loader logs and records stay in `$D`. Updates resume as in P6.

**E12. `limine-snapper-sync` is held off from W0 to C4.** It runs from three places (agent-run, read-only):
`snapper-cleanup.timer` (`OnBootSec=10m`, `OnUnitActiveSec=1h`) whose service runs it as `ExecStopPost` (drop-in
`limine-snapper-override.conf`); `limine-snapper-sync.service`, which is `limine-snapper-watcher` (inotify on
`/.snapshots`: a run per snapshot created or deleted); and the snapper plugin `10-limine-snapper-sync` (on snapshot
changes made through snapper). `snap-pac` is not installed, so a pacman transaction makes no snapshot; `omarchy update`
does (snapshots 3 and 4 today). Each run tries to add a `Snapshots` tree to `limine.conf` and copy each kernel's image
into `/boot/efi/<machine-id>/limine_history/`, unless that would take the ESP past `LIMIT_USAGE_PERCENT=85`. Today, with
two images, it estimates 78.8 % to 109.3 % (+152.3 MiB) and adds nothing (journal, 16:46:39). But the ESP is 523,132,928
bytes, so with only r3a's image on it (after W1 and before I1, and after C2 and before X: 190,275,584 free) it is 63.6 %
used, one kernel costs +76.6 MiB, and the estimate ends at 79.0 %, under the limit: a run there adds the entry and
copies about 80 MB. Then I1 and X stop (`limine.conf` is neither W0's nor W1's file), and the macOS `restore-repair` of
section 5 no longer fits (about 110 MB free, below the image's 111.8 MB plus the tool's 8 MiB reserve). The r3a trial
window's D1 state had room for it too and missed a run by luck. So:
- W0 waits for any running cleanup, then stops `snapper-cleanup.timer` and `limine-snapper-sync.service` (a plain stop;
  nothing is disabled, masked or reconfigured) and writes `$D/sync-held`. A stop does not survive a reboot, so block F
  (every trial boot) and block C (boot 3) stop both again first. Block P, W1, X, Xs, I1, S, T1a, T2a, D3 and C2 stop
  unless both and `snapper-cleanup.service` read `inactive`; P, F and C also compare `limine_history` with W0's copy.
- In the window, no `snapper`, `omarchy update`, `omarchy-snapshot` or `limine-snapper-*` command: they would run it
  through the plugin or directly. (`limine-snapper-*` commands escalate themselves through `sudo` and ignore unknown
  options: `limine-snapper-sync --help`, run by the agent as a normal user at 17:51:56 to read its usage, ran a full sync.)
- C4 starts both again after `no boot file changed`; the timer's 10-minute boot delay has passed, so it runs at once.
  C5 checks that run: the same `78.8 % ... +152.3 MiB` skip, and `limine.conf` still the file from before the window.
- Each run also rewrites `limine.conf` (`Updated: /boot/efi/limine.conf`, every hour). On the promoted layout that
  rewrite is byte-identical: the 17:51:56 run and the 18:16:44 hourly run (the timer's own) each left sha256
  `2723642d...` (3,015 bytes, the 17:16:42 hourly run's file) unchanged, and `limine_history/snapshots.json` equal to its
  `.old` copy (agent-run, hashed before and after each). So H1's record, taken outside the
  window, is not upset by it, and from W0 to C4 nothing rewrites the file.
- If a `Snapshots` entry appears anyway (block P, F or C says so), block Xs removes it and the copies, and compares the
  rest with the saved file before anything else runs.

### Code changed for this runbook

| File | Change | Tests |
| --- | --- | --- |
| `tests/hardware/k114s-display-check.sh` | new: the read-only report of a display trial boot (`--expect` with `refused`, `published` or `none`; `--loader-log`; `--hypr`). Filters every log line it prints so a command line never shows | `tests/hardware/test-display-check.sh`, 23 passed |
| `tests/linux/test-display-trials-runbook.sh` | new: runs block P, this runbook's writing blocks (W0, W1, X, Xs, I0, I1, S, T1a, T2a, D3, C1, C2, C4) and the checks of the trial boots (F, T1b, T1b-D1, T2b, D3b, A, C, C5) and their STOP paths, cut out of this file, against a fake ESP with the real `k114s-boot-once` and stand-ins for pacman, `limine-entry-tool`, the two hooks, the snapshot-sync units, `journalctl` and the hardware checks; one case with a `sudo` that really changes access to a root-only `$D`; parses every block | 108 passed |
| `tests/linux/run-r3.sh` | runs the two new tests | |
| `packaging/linux-k114s/check-package.sh` | says `SKIP ... is not installed` and ends `all run checks passed; 2 skipped` when the other kernel is not installed, instead of passing silently (D0 review) | run against both kernels and a missing name (section 9) |
| `tests/k114s-adt-display-facts.py`, `tests/test-adt-display-facts.py` | the `dcp` mailbox check also requires each interrupt's type cell (AIC_IRQ) and die cell to be 0 (D0 review) | 17 replica checks (2 new: die 1, FIQ) |
| `docs/r3b-kernel.md` section 9 | the r3b package name, file and sha256 (`438c4efe...`), "Building UKI for linux-k114s-r3b", `M1N1_UPDATE_DISABLED` while either kernel is installed (D0 review) | |
| `docs/r3-display-plan.md` | G3 lists the Stage 2 hook's byte-identical rewrite; the loader decision; `aura-k114s-pin/` is not a D0 output; 4.2 and the risk table give the measured snapshot-sync figures (63.6 % and 79.0 %) and the hold-off; points here | |

## 3. Rules and variables

- From W1 to C4 the display window is open: no package transaction except I1 and C2, no `omarchy update`, no
  `limine-mkinitcpio`, `mkinitcpio` or `update-m1n1`. Close the window before any update. (H runs before W1.)
- From W0 to C4 the snapshot sync is held off (E12): no `snapper`, `omarchy-snapshot` or `limine-snapper-*` command, and
  no `systemctl start` of `snapper-cleanup.timer` or `limine-snapper-sync.service` before C4. Each boot in the window
  starts them again; block F (a trial boot) or block C (any other boot) is the first thing run, and stops them.
- On macOS, never `rollback all`, `rollback stage2`, `kernel`, `apply` or `default original`; in the window, also not
  `default aurora` (its image is off the ESP).
- The owner is at the Mac for every reboot. A hang, a black screen, or a Limine menu that stays up: hold the power button
  until the Mac is off, start it, and go to section 6.
- Variables do not survive a reboot. Set them at the top of each session:

      REPO=<a checkout of this repository that has this file>
      K=/usr/local/lib/omarchy-k114s/k114s-boot-once
      D=/var/lib/k114s-recovery/display
      R=${K114S_BUILD_ROOT:-$HOME/k114s-build}/integrate/release-display-trials

- Every block with a `findmnt` guard is a subshell `( ... )`. A `STOP` ends it with `exit 1`, the rest does not run,
  and the terminal stays open. Paste each block whole. Stop at the first expectation that is not met.
- Record each step's result in the lead's recovery log before the next step.
- What `$R` holds (agent-built, `SHA256SUMS` beside it; nothing in it was booted):

  | File | sha256 | What |
  | --- | --- | --- |
  | `pkg/linux-k114s-r3b-7.3.0.r3b-1-aarch64.pkg.tar.zst` | `438c4efe03d5271ffb5beae0125199e4d5cdba2bc97e5fdc2a05455eeb93f905` | r3b under its own name (D0) |
  | `pkg/hyprland-m5-0.57.2-3-aarch64.pkg.tar.zst` | `c87f25701f46d11041c85dfb8a76cae92877b42147368e16e486bfb68fab8b87` | H; its signature and the build's key in `pkg-sig/` |
  | `pkg-rollback/hyprland-m5-0.57.2-2-aarch64.pkg.tar.zst` | `12e46eb0bb1a956307a3459f05bed5e97500bc8ae802fd44aa5dc383d9edab9d` | the undo of H |
  | `stage2/boot-ctxr-disp-oldldr.bin` | `9e43d27a28f750ad559d9060fc9b30c33a59b5e5a8bb6e46ee1f456ffb68a5ca` | T1: installed loader `1546dd50...` + display tree `914ec379...`, 4,440,586 bytes (= D0's) |
  | `stage2/boot-ctxr-disp-pinldr.bin` | `3a9884f3513d110c9602e4261d2826e380bff7d92347da63890372f5307f7087` | T2: pin loader `beceb683...` + display tree `914ec379...`, 4,506,122 bytes |
  | `stage2/boot-ctxr-gpu-pinldr.bin` | `3749a5efc7a8a0d3565e3038d4ba42d94475a79944f4789e07fc26c2a89d611e` | D3 (conditional): pin loader + P's tree `2c870ba9...`, 4,505,773 bytes |

  Each Stage 2 file was composed with `build/make-stage2.sh` from `aura-installed/` or `aura-pin/` (the loader as
  `m1n1.bin` and the installed `u-boot-nodtb.bin` with its mtime) and `dtb/`; the same run recomposed P's configured file
  `9825a103...` byte for byte as the control, and every file has the trailer `9d8dc11e...` (`gates/stage2-build.out`).

## 4. The runbook

### Block P: the proven configuration (read-only; before every arm, and in every default boot)

    (
    : "${K:?STOP: set K, REPO, D and R first (section 3)}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    h() { sudo sha256sum "$1" 2>/dev/null | cut -c1-64; }
    c=/boot/efi/limine.conf; BLI=4a67b082-0a4c-41cf-b6c7-440b29bb8c4f
    GPU=9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc; GPUT=2c870ba9f5963f5ae1ed18a7effa520daa234583997470d9552a795b4aafcda5
    R3A=a15fa01ab7e20c9c1bf1b3f61c04f6ab765c4aa425188c22f70648a3871c52f4
    [ "$(h /boot/efi/m1n1/boot-ctxr.bin)" = $GPU ] || stop "the configured Stage 2 is not P's file 9825a103..."
    [ "$(h /boot/efi/k114s-repair/k114s.dtb)" = $GPUT ] && [ "$(h /usr/local/lib/omarchy-k114s/k114s.dtb)" = $GPUT ] || stop "a pinned tree is not 2c870ba9..."
    [ "$(h /boot/efi/EFI/Linux/omarchy_linux-k114s.efi)" = $R3A ] || stop "the r3a image is not a15fa01a..."
    [ "$(sudo grep -c -i '^default_entry:' $c)" = 1 ] && sudo grep -q -x 'default_entry: Omarchy/linux-k114s' $c || stop "default_entry is not exactly Omarchy/linux-k114s"
    sudo $K check || stop "k114s-boot-once check is not clean"
    [ "$(sudo sed -n 1p /boot/efi/aura-try)" = spent ] || stop "aura-try does not read spent"
    sudo test -e /etc/omarchy-k114s/stage2-trial && stop "a standing Stage 2 trial is configured"
    sudo test -e /var/lib/k114s-recovery/boot-once-selftest-ok && ! sudo test -e /var/lib/k114s-recovery/boot-once-not-durable || stop "the one-shot self-test marker is missing, or the not-durable marker exists"
    [ -e /sys/firmware/efi/efivars/LoaderEntryOneShot-$BLI ] && stop "a one-shot request is pending"
    grep -q -x 'export M1N1_UPDATE_DISABLED=1' /etc/default/update-m1n1 || stop "update-m1n1 is not off"
    [ "$(systemctl is-enabled suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target | sort -u)" = masked ] || stop "a sleep target is not masked"
    # from W0 to C4 the snapshot sync is held off and has copied nothing (E12)
    if sudo test -e "$D/sync-held"; then
      [ "$(systemctl is-active snapper-cleanup.timer limine-snapper-sync.service snapper-cleanup.service | sort -u)" = inactive ] || stop "the snapshot sync runs in the window (E12): sudo systemctl stop snapper-cleanup.timer limine-snapper-sync.service (block F or C does it first in each boot)"
      sudo diff -r -q "$D/limine_history.before-window" "/boot/efi/$(cat /etc/machine-id)/limine_history" >/dev/null || stop "limine_history changed since W0 (a Snapshots copy?): block Xs"
    fi
    # the window state decides which images and entries are expected
    if pacman -Q linux-k114s-r3b >/dev/null 2>&1; then imgs="omarchy_linux-k114s-r3b.efi omarchy_linux-k114s.efi "; ents="/+Omarchy //linux-k114s //linux-k114s-r3b "; st="window open, r3b installed"
    elif sudo test -e "$D/window-open"; then imgs="omarchy_linux-k114s.efi "; ents="/+Omarchy //linux-k114s "; st="window open, r3b not installed"
    else imgs="omarchy_linux-aurora.efi omarchy_linux-k114s.efi "; ents="/+Omarchy //linux-aurora //linux-k114s "; st="window closed"; fi
    [ "$(sudo ls /boot/efi/EFI/Linux | LC_ALL=C sort | tr '\n' ' ')" = "$imgs" ] || stop "$st: EFI/Linux is not exactly: $imgs"
    [ "$(sudo grep -E '^[[:blank:]]*/' $c | tr -d ' \t' | LC_ALL=C sort | tr '\n' ' ')" = "$(echo $ents | tr ' ' '\n' | LC_ALL=C sort | tr '\n' ' ')" ] || stop "$st: the menu is not exactly: $ents(a Snapshots entry? in the window: block Xs)"
    echo "this boot: $(uname -r), started $(tail -c +5 /sys/firmware/efi/efivars/LoaderEntrySelected-$BLI 2>/dev/null | iconv -f UTF-16LE -t UTF-8 | tr -d '\0'), Stage 2 $({ tr -d '\0' < /proc/device-tree/chosen/aurora,trial; } 2>/dev/null || echo configured)"
    echo "ESP free: $(df -B1 --output=avail /boot/efi | tail -1)"
    echo "P: the proven configuration holds ($st)"
    )

Expected: `ok` lines from `check` with `default_entry is Omarchy/linux-k114s (entry N, id Omarchy.linux-k114s, ...)`
(N is 3 with `linux-aurora` in the folder, 2 without, 2 or 3 with r3b, depending on where the hook put it), then the
last line. Nothing to undo.

### H. `hyprland-m5 0.57.2-3` and the title-bar plugin (session 0, before the window; a log-out, no reboot)

**H1. Check, install, check the holds are still listed (the plugin stays parked).**

    (
    : "${D:?STOP: set K, REPO, D and R first (section 3)}" "${R:?STOP: set R first}" "${REPO:?STOP: set REPO first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    f=/usr/lib/omarchy-hyprland-titlebars; pkg=$R/pkg/hyprland-m5-0.57.2-3-aarch64.pkg.tar.zst
    HYP=c87f25701f46d11041c85dfb8a76cae92877b42147368e16e486bfb68fab8b87; TB=160ca037d712acda64b1f894c9bff2ac77495080ffc4df03f50081a50574e55e
    rec() { sudo sh -c 'cd /boot/efi && { sha256sum limine.conf m1n1/boot-ctxr.bin k114s-repair/k114s.dtb EFI/Linux/*.efi; sha256sum /usr/local/lib/omarchy-k114s/k114s.dtb; grep -i "^default_entry" limine.conf; grep -E "^[[:blank:]]*/" limine.conf; grep -E "^[[:blank:]]*path:" limine.conf; sed -n 1p aura-try; }'; }
    held() { for p; do grep '^IgnorePkg = ' /etc/pacman.conf | tr ' ' '\n' | grep -q -x -- "$p" || return 1; done; }
    sudo test -e "$D/window-open" && stop "the display window is open: H is a package transaction and runs before W1; nothing was changed"
    [ "$(pacman -Q hyprland-m5)" = "hyprland-m5 0.57.2-2" ] && [ "$(pacman -Q omarchy-hyprland-titlebars)" = "omarchy-hyprland-titlebars 0.4.0-1" ] || stop "hyprland-m5 or the plugin is not the expected version; nothing was changed"
    [ -e $f/titlebars.so ] && stop "titlebars.so is in place: park it first (sudo mv $f/titlebars.so $f/titlebars.so.disabled-k114s); nothing was changed"
    [ "$(sha256sum < $f/titlebars.so.disabled-k114s | cut -c1-64)" = $TB ] || stop "the parked titlebars.so is not the package's file; nothing was changed"
    # provenance: the sha256 betizzel's 0007 manifest lists for the release 4601e97e (E4)
    [ "$(sha256sum < "$pkg" | cut -c1-64)" = $HYP ] || stop "the package is not c87f2570...; nothing was changed"
    [ -e "$pkg.sig" ] && stop "a .sig lies beside the package: pacman would ask to import the build's key. Keep it in pkg-sig/; nothing was changed"
    # the signature and its key come with the package, so this only catches a damaged file, not a forged one (E4)
    g=$(mktemp -d) || exit 1; trap 'rm -rf "$g"' EXIT
    gpg --homedir "$g" --quiet --import "$R/pkg-sig/candidate-signing-key.asc" 2>/dev/null
    gpg --homedir "$g" --status-fd 1 --verify "$R/pkg-sig/${pkg##*/}.sig" "$pkg" 2>/dev/null | grep -q '^\[GNUPG:\] VALIDSIG 0DA040FF52D5EC6FB6538769DBFEBBB2B6D116B1 ' ||
      stop "the signature that came with the package does not verify (a throwaway keyring; nothing is imported anywhere); nothing was changed"
    # the layout the stock plugin reads: m_layerSurfaceLayers at the stock 0x790 in the package's own headers
    bsdtar -xf "$pkg" -C "$g" usr/include/hyprland || stop "cannot read the package's headers"
    cf=$(pkg-config --cflags hyprland libdrm libinput libudev pixman-1 wayland-server xkbcommon | sed "s#-I/usr/include/hyprland#-I$g/usr/include/hyprland#g")
    g++ -std=gnu++23 -O1 -fPIC -c "$REPO/packaging/omarchy-hyprland-titlebars-m5/abi-probe.cpp" -o "$g/probe.o" -I"$g/usr/include" $cf 2>/dev/null || stop "the ABI probe does not compile against the package's headers"
    off=$(nm -S --defined-only "$g/probe.o" | awk '$4 == "abi_off_m_layerSurfaceLayers" { print $2 }')
    [ "$off" = 0000000000000790 ] || stop "CMonitor::m_layerSurfaceLayers is at 0x$off in 0.57.2-3, not the stock 0x790: the stock plugin would crash; nothing was changed"
    [ "$(pacman -U --print --print-format '%n %v' "$pkg")" = "hyprland-m5 0.57.2-3" ] || stop "the transaction would change more than hyprland-m5; nothing was changed"
    held hyprland-m5 omarchy-hyprland-titlebars || stop "hyprland-m5 and omarchy-hyprland-titlebars are not both in IgnorePkg; nothing was changed"
    sudo mkdir -p "$D" && sudo chmod 700 "$D" || stop "cannot make $D"
    rec > /dev/null && rec | sudo tee "$D/before-h.txt" >/dev/null || stop "no boot record"
    # the install. No hold is released: IgnorePkg does not hold back a file named to -U (E4)
    sudo pacman -U --noconfirm "$pkg"; rc=$?
    [ $rc = 0 ] && [ "$(pacman -Q hyprland-m5)" = "hyprland-m5 0.57.2-3" ] || stop "the install failed (pacman exit $rc, its message above): $(pacman -Q hyprland-m5); the plugin stays parked"
    held hyprland-m5 omarchy-hyprland-titlebars || stop "a hold is no longer in IgnorePkg: sudo /usr/local/lib/omarchy-k114s/apply-holds, then read the IgnorePkg lines again"
    [ -e $f/titlebars.so.disabled-k114s ] && [ ! -e $f/titlebars.so ] || stop "the plugin is no longer parked: sudo mv $f/titlebars.so $f/titlebars.so.disabled-k114s"
    rec | sudo cmp -s "$D/before-h.txt" - || stop "a boot file changed during H: read sudo diff $D/before-h.txt against a new record; do not reboot"
    echo "H1: hyprland-m5 0.57.2-3 installed, both packages still held, titlebars.so still parked. Float nothing; log out and log in now, then H2"
    )

Expected: pacman's `loading packages...`, perhaps `:: hyprland-m5 is in IgnorePkg/IgnoreGroup. Install anyway? [Y/n]`
answered `Y` by `--noconfirm`, `upgrading hyprland-m5`, the hooks (no `Building UKI`, no `Updating the confined m1n1 Stage
2`: the package has no files they trigger on), then the last line. The ESP space guard passes (about 111 MB free). From
here to the log-out the old compositor still runs from memory: **float nothing** (the plugin is parked, so nothing can
load it anyway). Undo (from Linux, any time, then log out):

    (
    : "${D:?STOP: set D and R first (section 3)}" "${R:?STOP: set R first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    f=/usr/lib/omarchy-hyprland-titlebars; old=$R/pkg-rollback/hyprland-m5-0.57.2-2-aarch64.pkg.tar.zst
    held() { for p; do grep '^IgnorePkg = ' /etc/pacman.conf | tr ' ' '\n' | grep -q -x -- "$p" || return 1; done; }
    sudo test -e "$D/window-open" && stop "the display window is open: close it first (C1 to C4)"
    [ "$(sha256sum < "$old" | cut -c1-64)" = 12e46eb0bb1a956307a3459f05bed5e97500bc8ae802fd44aa5dc383d9edab9d ] || stop "the 0.57.2-2 package is not 12e46eb0...; nothing was changed"
    [ -e $f/titlebars.so ] && { sudo mv $f/titlebars.so $f/titlebars.so.disabled-k114s || stop "titlebars.so was not parked"; }
    sudo pacman -U --noconfirm "$old"; rc=$?
    [ $rc = 0 ] && [ "$(pacman -Q hyprland-m5)" = "hyprland-m5 0.57.2-2" ] || stop "the downgrade failed (pacman exit $rc); the plugin is parked"
    held hyprland-m5 omarchy-hyprland-titlebars || stop "a hold is no longer in IgnorePkg: sudo /usr/local/lib/omarchy-k114s/apply-holds"
    echo "undo of H: hyprland-m5 0.57.2-2, titlebars.so parked, holds as before. Log out and in"
    )

The 0.57.2-2 package's `Hyprland` is the installed one byte for byte (agent-run `cmp`).

**H2. After the log-out and log-in: the new compositor runs (as the user, in the new session; changes nothing).**

    (
    stop() { echo "STOP: $*"; exit 1; }
    [ "$(pacman -Q hyprland-m5)" = "hyprland-m5 0.57.2-3" ] || stop "hyprland-m5 is not 0.57.2-3"
    pid=$(pgrep -x -o Hyprland) || stop "no Hyprland process"
    case $(readlink /proc/$pid/exe) in *deleted*) stop "this Hyprland is the old binary: log out and in again" ;; esac
    hyprctl version | head -1
    hyprctl monitors | grep -E '^Monitor|@|scale:'
    hyprctl plugin list | grep -q -i -E 'hyprbars|titlebar' && stop "a title-bar plugin is loaded although titlebars.so is parked"
    echo "H2: the 0.57.2-3 compositor runs, the plugin is parked. Now H3"
    )

Expected: `Hyprland 0.57.2 built from branch v0.57.2 ...`, `Monitor Unknown-1`, `3024x1986@60...`, `scale: 2`, the last
line. A crash at login (before H3, so not the plugin): the undo of H from a text console (H-crash says how to reach one).

**H3. Put the plugin back (in the new session, after H2).**

    (
    : "${D:?STOP: set K, REPO, D and R first (section 3)}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    f=/usr/lib/omarchy-hyprland-titlebars; TB=160ca037d712acda64b1f894c9bff2ac77495080ffc4df03f50081a50574e55e; L=~/.local/state/omarchy/workspace-layouts
    [ "$(pacman -Q hyprland-m5)" = "hyprland-m5 0.57.2-3" ] || stop "hyprland-m5 is not 0.57.2-3 (H1); nothing was changed"
    pid=$(pgrep -x -o Hyprland) || stop "no Hyprland process: run this in the desktop session; nothing was changed"
    case $(readlink /proc/$pid/exe) in *deleted*) stop "the running Hyprland is still the old binary: log out and in first; nothing was changed" ;; esac
    [ -e $f/titlebars.so ] && stop "titlebars.so is already in place; nothing was changed"
    [ "$(sha256sum < $f/titlebars.so.disabled-k114s | cut -c1-64)" = $TB ] || stop "the parked titlebars.so is not the package's file; nothing was changed"
    # no saved mode may float: a floating workspace loads the plugin at every login (E4)
    grep -l -s -E 'mode = "floating"|default = "floating"' "$L"/*.lua && stop "a saved workspace mode floats (the files above): set it to tiling first (Super + L); nothing was changed"
    rm -rf "$L.before-h4" && cp -rp "$L" "$L.before-h4" || stop "no copy of the saved layouts; nothing was changed"
    sudo mv $f/titlebars.so.disabled-k114s $f/titlebars.so || stop "titlebars.so was not put back"
    pacman -Qkk omarchy-hyprland-titlebars 2>/dev/null | grep -q ' 0 altered files' || stop "the plugin does not match its package: park it again (sudo mv $f/titlebars.so $f/titlebars.so.disabled-k114s)"
    echo "H3: titlebars.so is back (the package's own file); the saved layouts are copied to $L.before-h4. Now H4"
    )

Expected: only the last line. Nothing loads the plugin yet: nothing floats.

**H4. The click test (the owner, in the desktop).** Float the current workspace for this session only (`hyprctl eval`
applies the mode and saves nothing; do not use Super + L or the menu, which save it):

    WS=$(hyprctl activeworkspace -j | jq -r .id); hyprctl eval "o.workspace_mode({ workspace = \"$WS\", mode = \"floating\" })" && sleep 2
    # the first eval loads the plugin, whose reload starts a fresh Lua state: run it again so the bars are configured
    hyprctl eval "o.workspace_mode({ workspace = \"$WS\", mode = \"floating\" })" && sleep 2
    hyprctl plugin list | grep -i -E 'hyprbars|titlebar' || echo "STOP: the plugin is not loaded; the click test would test nothing"
    hyprctl clients -j | jq -e --argjson w "$WS" '[.[] | select(.workspace.id == $w) | .tags[]?] | any(test("omarchy-floating-workspace"))' >/dev/null ||
      echo "STOP: no window on workspace $WS carries the omarchy-floating-workspace tag; open a window there and run these lines again"
    echo "workspace $WS floats for this session only (not saved)"

Expected: the plugin's line (`hyprbars`), no STOP line, then the last line. The owner drags a window by its title bar and clicks its
buttons about ten times (the 2026-11-14 crash came at the first click). Then, in the same terminal, whatever happened:

    (
    : "${WS:?STOP: run the first line of H4 in this terminal first}"
    stop() { echo "STOP: $*"; exit 1; }
    L=~/.local/state/omarchy/workspace-layouts
    m=$(sed -n 's/.*mode = "\([a-z]*\)".*/\1/p' "$L/$WS.lua" 2>/dev/null); [ -n "$m" ] || m=$(sed -n 's/.*default = "\([a-z]*\)".*/\1/p' "$L/default.lua" 2>/dev/null)
    hyprctl eval "o.workspace_mode({ workspace = \"$WS\", mode = \"${m:-dwindle}\" })" >/dev/null || stop "workspace $WS was not put back to ${m:-dwindle}: Super + L until it tiles"
    diff -r -q "$L.before-h4" "$L" >/dev/null || stop "the saved layouts changed during the test: rm -r $L && cp -rp $L.before-h4 $L"
    n=$(find ~/.cache/hyprland -name 'hyprlandCrashReport*' -newer /usr/lib/omarchy-hyprland-titlebars 2>/dev/null | wc -l)
    [ "$n" = 0 ] && [ "$(coredumpctl list Hyprland --since -30min --no-legend 2>/dev/null | wc -l)" = 0 ] || stop "Hyprland crashed since H3 ($n crash reports): the undo of H"
    echo "H4: workspace $WS is back to ${m:-dwindle}, nothing saved floats; no crash since H3"
    )

Expected: `H4: workspace 1 is back to dwindle ...` (the saved modes today: workspace 1 `dwindle`, the default
`scrolling`). Record `H PASSED` in the recovery log. A crash during the test ends the session (and the lead's T3
desktop, a user service without lingering): go to H-crash.

**H-crash: a crash loop, without a mouse and without the lead.** If Hyprland crashes during H4, or at the first click
after a later login: log in again and click nothing. Nothing floats at login (H4 saved nothing, and H3 refused to run with
a saved floating mode), so the plugin should not load. Switch to a text console with Ctrl + Alt + F3 (hold fn as well if
the top row acts as media keys) or open a terminal with Super + Return, log in, and run:

    sudo mv /usr/lib/omarchy-hyprland-titlebars/titlebars.so /usr/lib/omarchy-hyprland-titlebars/titlebars.so.disabled-k114s

With the file parked, `titlebars_installed()` in Omarchy's `workspace-modes.lua` is false, so the plugin cannot load
whatever floats. If a saved mode floats anyway (`grep -l floating ~/.local/state/omarchy/workspace-layouts/*.lua` prints a
name), put the copy back: `rm -r ~/.local/state/omarchy/workspace-layouts && cp -rp
~/.local/state/omarchy/workspace-layouts.before-h4 ~/.local/state/omarchy/workspace-layouts`. Return to the desktop
(Ctrl + Alt + F1 or F2), log out and in. The lead, once back, runs the undo of H (or keeps 0.57.2-3 with the plugin
parked, which is how the Mac ran before H) and records the crash with its report.

### W. Open the display window

**W0. Hold the snapshot sync off, then the before-record and the copies on the Linux disk (changes nothing on the
ESP).** From a default boot, after block P (`window closed`) and H.

    (
    : "${K:?STOP: set K, REPO, D and R first (section 3)}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*; nothing on the ESP was changed"; exit 1; }
    h() { sudo sha256sum "$1" 2>/dev/null | cut -c1-64; }
    c=/boot/efi/limine.conf; A=/boot/efi/EFI/Linux/omarchy_linux-aurora.efi
    AUR=72f5d32c9a4bc443bddab3eba171365b8cd082bf9cc61f665b15684d2d64403a; R3A=a15fa01ab7e20c9c1bf1b3f61c04f6ab765c4aa425188c22f70648a3871c52f4
    rec() { sudo sh -c 'cd /boot/efi && { sha256sum limine.conf m1n1/boot-ctxr.bin k114s-repair/k114s.dtb EFI/Linux/*.efi; sha256sum /usr/local/lib/omarchy-k114s/k114s.dtb; grep -i "^default_entry" limine.conf; grep -E "^[[:blank:]]*/" limine.conf; grep -E "^[[:blank:]]*path:" limine.conf; sed -n 1p aura-try; }'; }
    [ "$(uname -r)" = 7.3.0-17.v272-4-k114s-r3a-ARCH ] || stop "run this from a default boot of r3a"
    sudo test -e "$D/window-open" && stop "the window is already open"
    sudo test -e "$D/before-window.txt" && stop "$D/before-window.txt exists: an earlier opening? read it first"
    [ "$(h $A)" = $AUR ] && [ "$(h /boot/efi/EFI/Linux/omarchy_linux-k114s.efi)" = $R3A ] || stop "the two images are not the promoted ones (72f5d32c..., a15fa01a...)"
    [ "$(sudo ls /boot/efi/EFI/Linux | LC_ALL=C sort | tr '\n' ' ')" = "omarchy_linux-aurora.efi omarchy_linux-k114s.efi " ] || stop "EFI/Linux holds more than the two promoted images"
    [ "$(sudo grep -E '^[[:blank:]]*/' $c | tr -d ' \t' | tr '\n' ' ')" = "/+Omarchy //linux-aurora //linux-k114s " ] || stop "the menu is not exactly the folder, linux-aurora and linux-k114s (a Snapshots entry?)"
    pacman -Q linux-k114s-r3b >/dev/null 2>&1 && stop "linux-k114s-r3b is already installed"
    sudo mkdir -p "$D" && sudo chmod 700 "$D" || stop "cannot make $D"
    # 1. limine-snapper-sync held off until C4 (E12): let a running cleanup finish, then a plain stop of both units
    for i in $(seq 90); do [ "$(systemctl show -p ActiveState --value snapper-cleanup.service)" = inactive ] && break; sleep 2; done
    sudo systemctl stop snapper-cleanup.timer limine-snapper-sync.service || stop "the snapshot sync was not stopped"
    [ "$(systemctl is-active snapper-cleanup.timer limine-snapper-sync.service snapper-cleanup.service | sort -u)" = inactive ] || stop "the snapshot sync is not inactive (systemctl status snapper-cleanup.timer limine-snapper-sync.service); start it again: sudo systemctl start snapper-cleanup.timer limine-snapper-sync.service"
    sudo touch "$D/sync-held" || stop "cannot write $D/sync-held"
    hist=/boot/efi/$(cat /etc/machine-id)/limine_history
    [ "$(sudo find "$hist" -type f | wc -l)" -le 4 ] && [ "$(sudo du -sb "$hist" | cut -f1)" -le 1048576 ] || stop "limine_history holds image copies already (sudo ls -la $hist)"
    sudo rm -rf "$D/limine_history.before-window" && sudo cp -a "$hist" "$D/limine_history.before-window" || stop "limine_history was not copied"
    # 2. the record
    sudo cp -p $c "$D/limine.conf.before-window" && sudo cmp -s $c "$D/limine.conf.before-window" || stop "limine.conf was not copied"
    sudo cp -p $A "$D/omarchy_linux-aurora.efi" && [ "$(h "$D/omarchy_linux-aurora.efi")" = $AUR ] || stop "the linux-aurora image was not copied"
    sudo cp -p /boot/efi/aura-try "$D/aura-try.before-window" || stop "aura-try was not copied"
    sudo ls /boot/efi/m1n1 | LC_ALL=C sort | sudo tee "$D/m1n1.before-window" >/dev/null || stop "no listing of m1n1/"
    rec > /dev/null && rec | sudo tee "$D/before-window.txt" >/dev/null || stop "no boot record"
    df -B1 --output=avail /boot/efi | tail -1 | sudo tee "$D/free.before-window" >/dev/null
    echo "W0: before-record $(sudo grep -c '' "$D/before-window.txt") lines; image copy 72f5d32c...; ESP free $(sudo cat "$D/free.before-window")"
    )

Expected: `W0: before-record 13 lines; image copy 72f5d32c...; ESP free 111022080` (or the value of the day). Writes only
in `$D` (root-only: `limine.conf` holds the command line), and stops the two sync units until C4 or a reboot.
`systemctl list-timers snapper-cleanup.timer` now lists no next run. Undo (only before W1): `sudo systemctl start
snapper-cleanup.timer limine-snapper-sync.service && sudo rm -r /var/lib/k114s-recovery/display`.

**W1. Take the `linux-aurora` image off (this opens the window).**

    (
    : "${K:?STOP: set K and D first (section 3)}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    c=/boot/efi/limine.conf; A=/boot/efi/EFI/Linux/omarchy_linux-aurora.efi
    sudo test -s "$D/before-window.txt" && sudo test -s "$D/omarchy_linux-aurora.efi" || stop "W0 first; nothing was changed"
    sudo test -e "$D/window-open" && stop "the window is already open; nothing was changed"
    [ "$(systemctl is-active snapper-cleanup.timer limine-snapper-sync.service snapper-cleanup.service | sort -u)" = inactive ] || stop "the snapshot sync runs (E12): run W0's stop lines again in this boot; nothing was changed"
    sudo cmp -s $c "$D/limine.conf.before-window" || stop "limine.conf changed since W0; nothing was changed"
    sudo touch "$D/window-open" || stop "cannot write the window marker; nothing was changed"
    sudo limine-entry-tool --remove-uki linux-aurora; rc=$?
    # kept first, whatever the tool did, so block X can undo even a removal that the checks below reject
    sudo cp -p $c "$D/limine.conf.after-window" && sudo chmod 600 "$D/limine.conf.after-window" || stop "the after-window copy was not written: run block X (it compares by hand then)"
    [ $rc = 0 ] || stop "limine-entry-tool failed (exit $rc, its message above): run block X"
    sudo test -e $A && stop "omarchy_linux-aurora.efi is still on the ESP: run block X"
    t=$(mktemp -d) || exit 1; trap 'rm -rf "$t"' EXIT
    sudo cat $c > "$t/now"; sudo cat "$D/limine.conf.before-window" > "$t/old"
    # only lines removed, one contiguous block: the linux-aurora entry with its one path and one command line
    diff "$t/old" "$t/now" | sed -n 's/^< //p' > "$t/cut"
    [ "$(diff "$t/old" "$t/now" | grep -c '^>')" = 0 ] && [ "$(diff "$t/old" "$t/now" | grep -c -E '^[0-9]+(,[0-9]+)?d[0-9]+$')" = 1 ] &&
      [ "$(grep -v '^[[:blank:]]*$' "$t/cut" | sed -n 1p | tr -d ' \t')" = //linux-aurora ] && [ "$(grep -c -E '^[[:blank:]]*/' "$t/cut")" = 1 ] &&
      [ "$(grep -c -E '^[[:blank:]]*path: boot\(\):/EFI/Linux/omarchy_linux-aurora\.efi#' "$t/cut")" = 1 ] && [ "$(grep -c -E '^[[:blank:]]*cmdline:' "$t/cut")" = 1 ] ||
      stop "the removal changed more than the linux-aurora entry: run block X; do not reboot"
    sudo grep -q -x 'default_entry: Omarchy/linux-k114s' $c && [ "$(sudo grep -c -i '^default_entry:' $c)" = 1 ] || stop "default_entry changed: run block X; do not reboot"
    sudo $K check || stop "check is not clean: run block X; do not reboot"
    free=$(df -B1 --output=avail /boot/efi | tail -1); echo "ESP free: $free"
    [ "$free" -ge 185000000 ] || stop "less free space than expected (about 190 MB): run block X"
    echo "W1: DISPLAY WINDOW OPEN: $(grep -c '' "$t/cut") lines of the linux-aurora entry removed, its image off the ESP (a copy in $D)"
    )

Expected: the tool's removal line, the check with `ok    default_entry is Omarchy/linux-k114s (entry 2, id
Omarchy.linux-k114s, ...)`, `ESP free: 190275584` (or within a few KB), and `W1: DISPLAY WINDOW OPEN: 8 lines ...` (read
on the live file: the entry line, the tool's `### This kernel entry is auto-generated` marker, two comments, protocol,
path, cmdline and a blank line; 7 if the tool keeps the blank). Record `DISPLAY WINDOW OPEN` in the
recovery log. From now until C4 the window rules of section 3 hold. Run I0, I1 and S straight after W1: the held-off
sync is what keeps this one-image state safe (E12), and running them back to back keeps the state short. Undo: block X,
then C4.

**Block X: put the `linux-aurora` image and its entry back, byte for byte** (the undo of W1, and step 3 of the close).

    (
    : "${K:?STOP: set K and D first (section 3)}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    h() { sudo sha256sum "$1" 2>/dev/null | cut -c1-64; }
    c=/boot/efi/limine.conf; A=/boot/efi/EFI/Linux/omarchy_linux-aurora.efi; AUR=72f5d32c9a4bc443bddab3eba171365b8cd082bf9cc61f665b15684d2d64403a
    pacman -Q linux-k114s-r3b >/dev/null 2>&1 && stop "linux-k114s-r3b is installed: step C2 first; nothing was changed"
    sudo test -e /boot/efi/EFI/Linux/omarchy_linux-k114s-r3b.efi && stop "the r3b image is still on the ESP: step C2 first; nothing was changed"
    [ "$(h "$D/omarchy_linux-aurora.efi")" = $AUR ] && sudo test -s "$D/limine.conf.before-window" || stop "the W0 copies do not verify; nothing was changed"
    [ "$(systemctl is-active snapper-cleanup.timer limine-snapper-sync.service snapper-cleanup.service | sort -u)" = inactive ] || stop "the snapshot sync runs (E12): block C's stop lines first; nothing was changed"
    if ! sudo cmp -s $c "$D/limine.conf.before-window"; then
      sudo test -s "$D/limine.conf.after-window" || stop "W1 left no record of limine.conf: compare it with $D/limine.conf.before-window by hand (sudo diff, not printed in a shared window); nothing was changed"
      sudo grep -q -E '^[[:blank:]]*//Snapshots' $c && stop "limine.conf has a Snapshots entry (E12): block Xs first, then X again; nothing was changed"
      sudo cmp -s $c "$D/limine.conf.after-window" || stop "limine.conf is not the file W1 left (an image was rebuilt?). Nothing was changed. Do not reboot into a guess: rebuild the image the P5b way from a boot on P instead (docs/r3a-promotion.md P5b)"
    fi
    # 1. the image, written beside its name and read back (skipped when it is already there and right)
    if [ "$(h $A)" != $AUR ]; then
      [ "$(df -B1 --output=avail /boot/efi | tail -1)" -ge 85000000 ] || stop "less than 85 MB free: move the trial Stage 2 files off first (C1); nothing was changed"
      sudo cp "$D/omarchy_linux-aurora.efi" $A.k114s-new && sudo sync -f /boot/efi || { sudo rm -f $A.k114s-new; stop "the image was not copied; nothing was changed"; }
      [ "$(h $A.k114s-new)" = $AUR ] || { sudo rm -f $A.k114s-new; stop "the copy does not read back; nothing was changed"; }
      sudo mv -f $A.k114s-new $A && sudo sync -f /boot/efi
      [ "$(h $A)" = $AUR ] || stop "the image does not read back after the rename: run X again"
    fi
    # 2. limine.conf as it was before the window, under the boot-partition lock, through a file beside it
    if ! sudo cmp -s $c "$D/limine.conf.before-window"; then
      sudo flock -w 120 /run/lock/boot-partition.lock sh -c 'cmp -s "$1" "$2" || { echo "limine.conf changed while this block ran"; exit 1; }
        cp "$3" "$1.k114s-new" && sync -f "${1%/*}" && cmp -s "$3" "$1.k114s-new" && mv -f "$1.k114s-new" "$1" && sync -f "${1%/*}"' _ $c "$D/limine.conf.after-window" "$D/limine.conf.before-window" ||
        stop "limine.conf was not written (sudo rm -f $c.k114s-new); the image is back and unused, which is harmless. Run X again"
    fi
    sudo cmp -s $c "$D/limine.conf.before-window" || stop "limine.conf does not read back as the file from before the window: run X again; do not reboot"
    sudo $K check || stop "check is not clean; do not reboot"
    l=$(sudo awk '{ s = $0; sub(/^[ \t]+/, "", s) } s == "//linux-aurora" {f=1; next} f && /^[ \t]*\/\// {exit} f && /^[ \t]*path:/ {print; exit}' $c); p=${l#*boot():}; hh=${p#*#}; p=${p%%#*}
    [ -n "$l" ] && [ "$(sudo b2sum "/boot/efi$p" | cut -d' ' -f1)" = "$hh" ] || stop "the linux-aurora entry's #hash does not match its image; do not reboot"
    sudo rm -f "$D/window-open"
    echo "X: the linux-aurora image (72f5d32c...) and its entry are back; ESP free $(df -B1 --output=avail /boot/efi | tail -1)"
    )

Expected: the check with `(entry 3, id Omarchy.linux-k114s, ...)`, then `X: ...` with about 111,022,080 free. It can be
run again after any stop. The removal list (`/var/lib/limine/removed_kernels.list`) and the image's module directory are
untouched by it: `linux-aurora` stayed installed and held throughout. After X as the undo of W1 (not in the close), run
C4: it compares the boot record and starts the snapshot sync again.

**Block Xs: a `Snapshots` entry appeared in the window** (block P, F, C or X says so; E12). It removes what
`limine-snapper-sync` added, and puts `limine.conf` back only if the rest of it is the saved file byte for byte.

    (
    : "${K:?STOP: set K and D first (section 3)}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    c=/boot/efi/limine.conf; hist=/boot/efi/$(cat /etc/machine-id)/limine_history
    sudo test -e "$D/sync-held" && sudo test -d "$D/limine_history.before-window" || stop "W0 has not run: this block is for the window only; nothing was changed"
    [ "$(systemctl is-active snapper-cleanup.timer limine-snapper-sync.service snapper-cleanup.service | sort -u)" = inactive ] || stop "the snapshot sync runs: stop it first (block C's stop lines); nothing was changed"
    # the file limine.conf should be: I1's with r3b installed, W1's in the open window, W0's before W1
    if pacman -Q linux-k114s-r3b >/dev/null 2>&1; then want=$D/limine.conf.after-r3b; elif sudo test -e "$D/window-open"; then want=$D/limine.conf.after-window; else want=$D/limine.conf.before-window; fi
    sudo test -s "$want" || stop "no saved ${want##*/}; nothing was changed"
    [ "$(sudo grep -c -E '^[[:blank:]]*//Snapshots' $c)" -ge 1 ] || stop "limine.conf has no //Snapshots entry: not this block's case; nothing was changed"
    t=$(mktemp -d) || exit 1; trap 'rm -rf "$t"' EXIT
    # limine.conf without the Snapshots tree (its //Snapshots line and every line up to the next //entry or /OS line), trailing blank lines ignored
    trim() { sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}'; }
    sudo awk '{ s = $0; sub(/^[ \t]+/, "", s) } s ~ /^\/\/Snapshots/ { cut = 1; next } cut && (s ~ /^\/\/[^\/]/ || s ~ /^\/[^\/]/) { cut = 0 } !cut { print }' $c | trim > "$t/cut"
    sudo cat "$want" | trim > "$t/want"
    cmp -s "$t/cut" "$t/want" || stop "limine.conf differs from ${want##*/} by more than the Snapshots tree: nothing was changed; do not reboot. Read sudo diff $want $c under sudo (never in a shared window); the way out is X's P5b rebuild"
    # 1. limine.conf back to the saved file, under the boot-partition lock, through a file beside it
    sudo flock -w 120 /run/lock/boot-partition.lock sh -c 'cp "$2" "$1.k114s-new" && sync -f "${1%/*}" && cmp -s "$2" "$1.k114s-new" && mv -f "$1.k114s-new" "$1" && sync -f "${1%/*}"' _ $c "$want" ||
      stop "limine.conf was not written (sudo rm -f $c.k114s-new); run Xs again"
    sudo cmp -s $c "$want" || stop "limine.conf does not read back as ${want##*/}: run Xs again; do not reboot"
    # 2. limine_history as before the window: the image copies go
    sudo cp -a "$D/limine_history.before-window" "$hist.k114s-new" && sudo rm -rf "$hist" && sudo mv "$hist.k114s-new" "$hist" && sudo sync -f /boot/efi || stop "limine_history was not put back: run Xs again"
    sudo diff -r -q "$D/limine_history.before-window" "$hist" >/dev/null || stop "limine_history does not read back as W0's copy"
    sudo $K check || stop "check is not clean; do not reboot"
    echo "Xs: the Snapshots entry and its copies are gone; limine.conf is ${want##*/} again; ESP free $(df -B1 --output=avail /boot/efi | tail -1). Go back to the block that stopped"
    )

Expected: the check and the last line, with the free space of the state you were in (section 2, E6). The snapshots
themselves (`/.snapshots`, on the Linux disk) are not touched.

### I. r3b beside r3a

**I0. What D1-D4 need besides the kernel: no VRR, no boot-time brightness write, the eDP rules, the r3b opt-in.**
Inert on r3a and on P (no `appledrm` binds there).

    (
    : "${REPO:?STOP: set K, REPO, D and R first (section 3)}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    m=/etc/modprobe.d/aurora-m5-vrr.conf; bd='/etc/systemd/system/systemd-backlight@backlight:apple-panel-bl.service.d'
    ml=~/.config/hypr/monitors.lua; e1='hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 2 })'
    e2='hl.monitor({ output = "eDP-2", mode = "preferred", position = "auto", scale = 2 })'
    sudo test -e "$D/window-open" || stop "open the window first (W0, W1); nothing was changed"
    [ -e /usr/lib/modprobe.d/aurora-m5-vrr.conf ] || stop "no installed aurora-m5-vrr.conf: the name to mask is not there; nothing was changed"
    [ -e $m ] && stop "$m exists: read it first; nothing was changed"
    sudo test -e /var/lib/k114s-backlight/restore-enabled && stop "brightness restore is turned on (/var/lib/k114s-backlight/restore-enabled); nothing was changed"
    [ "$(grep -c -x -F "$e1" $ml)" = 1 ] || stop "monitors.lua does not have exactly one eDP-1 rule; nothing was changed"
    # 1. no VRR offered on the OLED until D6 (the same name replaces the J714s file, which sets 1)
    printf '%s\n' '# K114s display trials (docs/r3-display-trials.md, E8): no VRR on the OLED panel until D6.' \
      '# Same name as /usr/lib/modprobe.d/aurora-m5-vrr.conf (fw27_panel_vrr=1, tested on the J714s LCD only), so it replaces it.' \
      'options appledrm fw27_panel_vrr=0' | sudo tee $m >/dev/null || stop "$m was not written"
    [ "$(modprobe -c | grep -c -E '^options appledrm fw27_panel_vrr=1')" = 0 ] && [ "$(modprobe -c | grep -c -E '^options appledrm fw27_panel_vrr=0')" = 1 ] || stop "modprobe still reads fw27_panel_vrr=1: sudo rm $m"
    # 2. systemd-backlight does not write the level at boot or save it at shutdown (E7)
    sudo install -d "$bd" && sudo install -m644 "$REPO/linux/brightness/systemd/k114s-first-boot.conf" "$bd/" && sudo systemctl daemon-reload || stop "the drop-in was not installed: sudo rm -r '$bd'"
    systemctl show -p DropInPaths --value 'systemd-backlight@backlight:apple-panel-bl.service' | grep -q 'k114s-first-boot.conf' || stop "systemd does not read the drop-in: sudo rm -r '$bd' && sudo systemctl daemon-reload"
    # 3. the panel's connector on the DCP may be eDP-1 or eDP-2: both at scale 2
    cp -p $ml "$ml.bak.display-trials" || stop "no copy of monitors.lua"
    grep -q -x -F "$e2" $ml || printf '\n-- The K114s panel on the display coprocessor if it comes up as eDP-2 (docs/r3-display-trials.md; inert until then).\n%s\n' "$e2" >> $ml
    [ "$(grep -c -x -F "$e1" $ml) $(grep -c -x -F "$e2" $ml)" = "1 1" ] || stop "monitors.lua does not have one eDP-1 and one eDP-2 rule: cp -p $ml.bak.display-trials $ml"
    # 4. the GPU desktop on r3b (guard v3): T1's first session is the GPU-desktop session D1 asks for
    touch ~/.config/k114s-gpu-desktop-r3b
    echo "I0: fw27_panel_vrr=0, brightness drop-in, eDP-1 and eDP-2 rules, r3b opt-in"
    )

Expected: only the last line (Hyprland reloads `monitors.lua` by itself; neither rule matches a monitor now).
Undo: `sudo rm /etc/modprobe.d/aurora-m5-vrr.conf`,
`sudo rm -r '/etc/systemd/system/systemd-backlight@backlight:apple-panel-bl.service.d' && sudo systemctl daemon-reload`,
`cp -p ~/.config/hypr/monitors.lua.bak.display-trials ~/.config/hypr/monitors.lua`, `rm ~/.config/k114s-gpu-desktop-r3b`.

**I1. Install `linux-k114s-r3b`, then G3 and G6.**

    (
    : "${K:?STOP: set K, REPO, D and R first (section 3)}" "${REPO:?STOP: set REPO first}" "${D:?STOP: set D first}" "${R:?STOP: set R first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    h() { sudo sha256sum "$1" 2>/dev/null | cut -c1-64; }
    c=/boot/efi/limine.conf; KU=/boot/efi/EFI/Linux/omarchy_linux-k114s.efi; BU=/boot/efi/EFI/Linux/omarchy_linux-k114s-r3b.efi
    pkg=$R/pkg/linux-k114s-r3b-7.3.0.r3b-1-aarch64.pkg.tar.zst; REL=7.3.0-17.v272-11-k114s-r3b-ARCH
    R3B=438c4efe03d5271ffb5beae0125199e4d5cdba2bc97e5fdc2a05455eeb93f905; R3A=a15fa01ab7e20c9c1bf1b3f61c04f6ab765c4aa425188c22f70648a3871c52f4
    GPU=9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc; GPUT=2c870ba9f5963f5ae1ed18a7effa520daa234583997470d9552a795b4aafcda5
    [ "$(uname -r)" = 7.3.0-17.v272-4-k114s-r3a-ARCH ] && [ ! -e /proc/device-tree/chosen/aurora,trial ] || stop "run this from a default boot of r3a on P (G6: no display subsystem in this boot's tree); nothing was changed"
    sudo test -e "$D/window-open" && sudo cmp -s $c "$D/limine.conf.after-window" || stop "the window is not open as W1 left it; nothing was changed"
    [ "$(systemctl is-active snapper-cleanup.timer limine-snapper-sync.service snapper-cleanup.service | sort -u)" = inactive ] || stop "the snapshot sync runs (E12): block C's stop lines first; nothing was changed"
    pacman -Q linux-k114s-r3b >/dev/null 2>&1 && stop "linux-k114s-r3b is already installed; nothing was changed"
    [ "$(sha256sum < "$pkg" | cut -c1-64)" = $R3B ] || stop "the package is not 438c4efe...; nothing was changed"
    for o in linux-aurora linux-k114s; do
      [ "$(K114S_CAND=r3b bash "$REPO/packaging/linux-k114s/check-package.sh" "$pkg" $o 2>&1 | tail -1)" = "check-package: all passed" ] || stop "check-package.sh against $o does not end 'check-package: all passed'; nothing was changed"
    done
    [ "$(pacman -U --print --print-format '%n %v' "$pkg")" = "linux-k114s-r3b 7.3.0.r3b-1" ] || stop "the transaction would change more than linux-k114s-r3b; nothing was changed"
    grep -q -x 'export M1N1_UPDATE_DISABLED=1' /etc/default/update-m1n1 || stop "update-m1n1 is not off; nothing was changed"
    [ "$(df -B1 --output=avail /boot/efi | tail -1)" -ge 185000000 ] || stop "less than 185 MB free (G2); nothing was changed"
    [ "$(h $KU)" = $R3A ] || stop "the r3a image is not a15fa01a...; nothing was changed"
    kline=$(sudo grep -E '^[[:blank:]]*path: boot\(\):/EFI/Linux/omarchy_linux-k114s\.efi#' $c)
    sudo install -m600 "$pkg" "$D/" && sudo cp -p $c "$D/limine.conf.before-r3b" || stop "no copies in $D; nothing was changed"
    # the install: its output is kept root-only (the hooks' lines are counted, never searched for anything else)
    sudo pacman -U --noconfirm "$pkg" 2>&1 | sudo tee "$D/install-r3b.log" | grep -E '^(:: |\(|warning|error)|Building|Updating|update-boot-ctxr|Image generation'
    log() { sudo grep -c -F -- "$1" "$D/install-r3b.log"; }
    pacman -Q linux-k114s-r3b >/dev/null 2>&1 || stop "linux-k114s-r3b is not installed (pacman's message is above); nothing else to undo"
    # G3: one image built, and it is r3b's; the Stage 2 hook rewrote the configured file byte for byte
    [ "$(log 'Building UKI for')" = 1 ] && [ "$(log "Building UKI for linux-k114s-r3b ($REL)")" = 1 ] || stop "the hook did not build exactly one image, r3b's (a full rebuild?): do not reboot; run C2 then block X"
    [ "$(log 'update-boot-ctxr-k114s: wrote /boot/efi/m1n1/boot-ctxr.bin (4440237 bytes, K114s device tree 2c870ba9f5963f5a)')" = 1 ] || stop "the Stage 2 hook did not rewrite boot-ctxr.bin from the GPU tree: do not reboot; read $D/install-r3b.log"
    [ "$(h /boot/efi/m1n1/boot-ctxr.bin)" = $GPU ] || stop "boot-ctxr.bin is no longer 9825a103...: do not reboot (put back: the undo of P1's first lines with /var/lib/k114s-recovery/promotion/boot-ctxr-r3-gpu.bin)"
    [ "$(h /boot/efi/k114s-repair/k114s.dtb)" = $GPUT ] && [ "$(h /usr/local/lib/omarchy-k114s/k114s.dtb)" = $GPUT ] || stop "a pinned tree changed: do not reboot"
    [ "$(h $KU)" = $R3A ] && sudo grep -q -x -F -- "$kline" $c || stop "the r3a image or its entry changed: do not reboot; run C2 then block X"
    [ "$(pacman -Qqo /usr/lib/modules/7.3.0-17.v272-4-k114s-r3a-ARCH)" = linux-k114s ] && [ "$(pacman -Qqo /usr/lib/modules/$REL)" = linux-k114s-r3b ] || stop "the module directories are not owned one by each package"
    [ "$(sudo grep -c -i '^default_entry:' $c)" = 1 ] && sudo grep -q -x 'default_entry: Omarchy/linux-k114s' $c || stop "default_entry changed: do not reboot; run C2 then block X"
    [ "$(sudo grep -c -E '^[[:blank:]]*//linux-k114s-r3b' $c)" = 1 ] && [ "$(sudo grep -c -x -E '[[:blank:]]*//linux-k114s-r3b' $c)" = 1 ] || stop "the r3b entry line is not exactly //linux-k114s-r3b, once"
    l=$(sudo awk '{ s = $0; sub(/^[ \t]+/, "", s) } s == "//linux-k114s-r3b" {f=1; next} f && /^[ \t]*\/\// {exit} f && /^[ \t]*path:/ {print; exit}' $c); p=${l#*boot():}; hh=${p#*#}; p=${p%%#*}
    [ "/boot/efi$p" = $BU ] && [ "$(sudo b2sum $BU | cut -d' ' -f1)" = "$hh" ] || stop "the r3b entry does not boot omarchy_linux-k114s-r3b.efi with a matching #hash"
    t=$(mktemp -d) || exit 1; trap 'sudo rm -rf "$t"' EXIT
    norm() { tr -d '\0' | tr -s ' \n' '\n' | sed '/^$/d' | sort; }
    for e in linux-k114s linux-k114s-r3b; do
      sudo awk -v e="$e" '{ s = $0; sub(/^[ \t]+/, "", s) } s == "//" e {f=1; next} f && /^[ \t]*\/\// {exit} f && /^[ \t]*cmdline:/ {sub(/^[ \t]*cmdline:[ \t]*/,""); print; exit}' $c | norm > "$t/$e"
    done
    [ -s "$t/linux-k114s" ] && cmp -s "$t/linux-k114s" "$t/linux-k114s-r3b" || stop "the r3b entry's command line differs from r3a's (compared, not shown)"
    sudo cat $c > "$t/now"; sudo cat "$D/limine.conf.after-window" > "$t/aw"
    [ "$(diff "$t/aw" "$t/now" | grep -c '^<')" = 0 ] && [ "$(diff "$t/aw" "$t/now" | grep -c '^>')" -le 10 ] && [ "$(diff "$t/aw" "$t/now" | grep '^>' | grep -c -E '^> [[:blank:]]*/')" = 1 ] || stop "limine.conf changed beyond the new r3b entry"
    sudo $K check || stop "check is not clean"
    # G6: appledrm is not in r3b's initramfs, so the screens before the root filesystem stay on simpledrm
    sudo objcopy --dump-section .initrd="$t/initrd" $BU /dev/null 2>/dev/null; sudo test -s "$t/initrd" || stop "no .initrd section dumped from the r3b image"
    sudo lsinitcpio "$t/initrd" > "$t/list" 2>/dev/null; [ "$(grep -c '\.ko' "$t/list")" -ge 20 ] || stop "lsinitcpio lists no modules: cannot read the r3b initramfs"
    [ "$(grep -c appledrm "$t/list")" = 0 ] || stop "appledrm is in r3b's initramfs (G6): do not boot r3b; run C2 then block X"
    [ "$(sudo ls /boot/efi/EFI/Linux | LC_ALL=C sort | tr '\n' ' ')" = "omarchy_linux-k114s-r3b.efi omarchy_linux-k114s.efi " ] || stop "EFI/Linux is not exactly the r3a and r3b images"
    free=$(df -B1 --output=avail /boot/efi | tail -1); echo "ESP free: $free"; [ "$free" -ge 105000000 ] || stop "less than 105 MB free"
    sudo cp -p $c "$D/limine.conf.after-r3b" && sudo chmod 600 "$D/limine.conf.after-r3b" || stop "no copy of limine.conf as I1 left it (block Xs needs it)"
    sudo $K entries
    echo "I1: r3b installed beside r3a; G3 and G6 pass ($(grep -c '\.ko' "$t/list") modules in its initramfs, no appledrm)"
    )

Expected on screen: `:: Processing package changes...`, `(1/1) installing linux-k114s-r3b`, the hooks: `Updating linux
initcpios under /boot (Apple Silicon)...` with `Image generation successful` (the `/boot` preset
`linux-k114s-r3b.preset`), `Updating linux initcpios...` with `Building UKI for linux-k114s-r3b
(7.3.0-17.v272-11-k114s-r3b-ARCH)` and no other `Building UKI` line, `Updating m1n1 image...` (prints nothing: off),
`Updating the confined m1n1 Stage 2 (m1n1/boot-ctxr.bin)...` with `update-boot-ctxr-k114s: wrote
/boot/efi/m1n1/boot-ctxr.bin (4440237 bytes, K114s device tree 2c870ba9f5963f5a)`: the byte-identical rewrite of
`9825a103...` (it builds from the pinned tree, never the package's dtbs; `docs/r3-integration.md` section 5). Then the
checks, `ESP free` about 110,790,000, `entries` with `Omarchy.linux-k114s` and `Omarchy.linux-k114s-r3b`, and the last
line (D0's dry run gave 81 modules). The space guard passes silently (about 190 MB free); the hold guard does not trigger.
Undo: step C2 (before any trial boot), then block X if the window closes.

**M (optional, E10). The macOS check of the window layout (two boots).** Only if the lead keeps G1 as written. Restart
into macOS (Startup Options). In the bundle folder: `sudo ./k114s-repair status` and `sudo ./k114s-repair
restore-repair --check`. Expected: the image and block lines pass, the space line reads `NOT ENOUGH, and no
omarchy_linux-aurora.efi to remove`, `Limine default entry:  Omarchy/linux-k114s -> linux-k114s`. Restart: the default
boots; run block C, then block P (`window open, r3b installed`).

### S. The trial Stage 2 files onto the ESP

    (
    : "${D:?STOP: set K, REPO, D and R first (section 3)}" "${R:?STOP: set R first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    h() { sudo sha256sum "$1" 2>/dev/null | cut -c1-64; }
    OLD=9e43d27a28f750ad559d9060fc9b30c33a59b5e5a8bb6e46ee1f456ffb68a5ca; PIN=3a9884f3513d110c9602e4261d2826e380bff7d92347da63890372f5307f7087
    GPIN=3749a5efc7a8a0d3565e3038d4ba42d94475a79944f4789e07fc26c2a89d611e
    sudo test -e "$D/window-open" && pacman -Q linux-k114s-r3b >/dev/null 2>&1 || stop "W1 and I1 first; nothing was changed"
    [ "$(systemctl is-active snapper-cleanup.timer limine-snapper-sync.service snapper-cleanup.service | sort -u)" = inactive ] || stop "the snapshot sync runs (E12): block C's stop lines first; nothing was changed"
    # all three on the Linux disk, read back
    for n in disp-oldldr:$OLD disp-pinldr:$PIN gpu-pinldr:$GPIN; do
      f=boot-ctxr-${n%%:*}.bin; sudo install -m600 "$R/stage2/$f" "$D/$f" && [ "$(h "$D/$f")" = ${n#*:} ] || stop "$f: the copy in $D is not ${n#*:}"
    done
    # two on the ESP (T1's and T2's), written beside their names and read back
    for n in disp-oldldr:$OLD disp-pinldr:$PIN; do
      f=m1n1/boot-ctxr-${n%%:*}.bin
      sudo cp "$D/${f#m1n1/}" /boot/efi/$f.k114s-new && sudo sync -f /boot/efi && [ "$(h /boot/efi/$f.k114s-new)" = ${n#*:} ] ||
        { sudo rm -f /boot/efi/$f.k114s-new; stop "$f was not written; remove what S wrote: sudo rm -f /boot/efi/m1n1/boot-ctxr-disp-*.bin"; }
      sudo mv -f /boot/efi/$f.k114s-new /boot/efi/$f && sudo sync -f /boot/efi && [ "$(h /boot/efi/$f)" = ${n#*:} ] || stop "$f does not read back"
    done
    free=$(df -B1 --output=avail /boot/efi | tail -1); [ "$free" -ge 95000000 ] || stop "less than 95 MB free"
    echo "S: m1n1/boot-ctxr-disp-oldldr.bin and -disp-pinldr.bin on the ESP; -gpu-pinldr.bin in $D; ESP free $free"
    )

Expected: the last line with about 101,840,000 free. Undo: step C1.

### The gates record

Before T1 the lead writes, in their own words, the two records the arm blocks look for (G0: the owner's authorisation of
D0-D4 stands after the 16:06 decline, or the answer that withdrew it; G4: the lead accepts the interrupt-only GPU mailbox
on r3b, citing step G, 385-421/s on r3a with no storm-guard message, and the J714s figure of #14):

    printf '%s\n' 'G0 confirmed: <who, when, where recorded>' 'G4 accepted: <the lead, the evidence>' | sudo tee /var/lib/k114s-recovery/display/gates.txt

Without `G4 accepted`, T1 does not arm. P7's alternative (r3b on the r1 tree, `aura-try` of
`k114s-repair/known-good/boot-ctxr.bin` with the one-shot) is then D1's only form, and D2-D4 do not start.

### T1 = D1 + D2 (boot 1)

**T1a. Arm, from the default boot of session 0.** Run block P first (`window open, r3b installed`).

    (
    : "${K:?STOP: set K, REPO, D and R first (section 3)}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    BLI=4a67b082-0a4c-41cf-b6c7-440b29bb8c4f; OLD=9e43d27a28f750ad559d9060fc9b30c33a59b5e5a8bb6e46ee1f456ffb68a5ca
    GPU=9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc; S2=m1n1/boot-ctxr-disp-oldldr.bin
    [ "$(uname -r)" = 7.3.0-17.v272-4-k114s-r3a-ARCH ] && [ ! -e /proc/device-tree/chosen/aurora,trial ] || stop "arm T1 from a default boot of r3a on P; nothing is armed"
    sudo grep -q '^G0 confirmed' "$D/gates.txt" 2>/dev/null && sudo grep -q '^G4 accepted' "$D/gates.txt" || stop "$D/gates.txt has no 'G0 confirmed' or no 'G4 accepted' line (the gates record); nothing is armed"
    [ "$(systemctl is-active snapper-cleanup.timer limine-snapper-sync.service snapper-cleanup.service | sort -u)" = inactive ] || stop "the snapshot sync runs (E12): block C's stop lines first; nothing is armed"
    [ "$(pacman -Q linux-k114s-r3b)" = "linux-k114s-r3b 7.3.0.r3b-1" ] || stop "r3b is not installed (I1); nothing is armed"
    [ "$(sudo sha256sum /boot/efi/m1n1/boot-ctxr.bin | cut -c1-64)" = $GPU ] || stop "the configured Stage 2 is not P's file; nothing is armed"
    [ "$(sudo sha256sum /boot/efi/$S2 | cut -c1-64)" = $OLD ] || stop "$S2 is not 9e43d27a...; nothing is armed"
    [ "$(sudo sed -n 1p /boot/efi/aura-try)" = spent ] || stop "aura-try does not read spent; nothing is armed"
    [ -e ~/.config/k114s-gpu-desktop-r3b ] || echo "note: no ~/.config/k114s-gpu-desktop-r3b: T1's desktop draws on the CPU (D1 then needs a log-out after touching it)"
    sudo $K arm Omarchy/linux-k114s-r3b || stop "the arm refused (its message is above); nothing is armed"
    # the Stage 2 trial last: if writing it fails, the pending request alone is r3b on P, D1's own configuration
    sudo sh -c "printf 'armed\n$S2\n' > /boot/efi/aura-try && sync -f /boot/efi" || {
      sudo sh -c "printf 'spent\n$S2\n' > /boot/efi/aura-try; sync -f /boot/efi"
      [ "$(sudo sed -n 1p /boot/efi/aura-try 2>/dev/null)" = spent ] || {
        echo "STOP: aura-try does not read spent, so it may still read armed. Do not reboot. Run: sudo cat /boot/efi/aura-try; if the first line is not spent: sudo sed -i 1s/armed/spent/ /boot/efi/aura-try && sudo sync -f /boot/efi, then read it again"; exit 1; }
      echo "STOP: aura-try was not written or not synced; it reads spent now. The one-shot is still pending: the next boot is r3b on P (D1 alone), or run sudo $K clear"; exit 1; }
    [ "$(sudo sed -n 1,2p /boot/efi/aura-try | tr '\n' ' ')" = "armed $S2 " ] || stop "aura-try does not read back as armed for $S2 (sudo cat /boot/efi/aura-try)"
    sudo $K status
    echo "T1 armed: r3b once, through $S2 once. Rebooting"
    sudo systemctl reboot
    )

Expected: `armed: the next boot starts 'Omarchy/linux-k114s-r3b' (id Omarchy.linux-k114s-r3b) once`, `default_entry
stays Omarchy/linux-k114s`, `status` with `efivarfs: LoaderEntryOneShot = Omarchy.linux-k114s-r3b`, the U-Boot file
holding it, `aura-try: armed m1n1/boot-ctxr-disp-oldldr.bin`, then the reboot. `arm` runs without
`--with-stage2-trial`, so it also checked that no Stage 2 trial was armed before it.

**Block F: the first command of every trial boot** (T1, T2, D1 alone, D3, a fallback boot on r3b). Before anything else,
because the loader log is this boot's only (`/dev/mtd1ro`, 16 KiB), and because the snapshot sync came back with the
boot (E12: its timer first runs 10 minutes after the boot).

    (
    : "${D:?STOP: set K, REPO, D and R first (section 3): they do not survive the reboot}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    tr=$({ tr -d '\0' < /proc/device-tree/chosen/aurora,trial; } 2>/dev/null); n=${tr##*/}; n=${n%.bin}; n=${n#boot-ctxr-}
    o=$D/boot-$(date +%Y%m%d-%H%M%S)-${n:-configured}
    sudo sh -c "umask 077; mkdir -p '$o' && cat /dev/mtd1ro | tr -d '\\000' > '$o/loader.log' && dmesg > '$o/dmesg.txt' && cat /proc/sys/kernel/random/boot_id > '$o/boot_id'" || stop "the logs were not saved"
    echo "$o" | sudo tee "$D/last-boot" >/dev/null
    # the snapshot sync held off again in this boot (E12)
    for i in $(seq 90); do [ "$(systemctl show -p ActiveState --value snapper-cleanup.service)" = inactive ] && break; sleep 2; done
    sudo systemctl stop snapper-cleanup.timer limine-snapper-sync.service || stop "the snapshot sync was not stopped"
    [ "$(systemctl is-active snapper-cleanup.timer limine-snapper-sync.service snapper-cleanup.service | sort -u)" = inactive ] || stop "the snapshot sync is not inactive (systemctl status snapper-cleanup.timer limine-snapper-sync.service)"
    sudo grep -q -E '^[[:blank:]]*//Snapshots' /boot/efi/limine.conf && stop "limine.conf has a Snapshots entry (the sync ran before this block): block Xs, then go on"
    sudo diff -r -q "$D/limine_history.before-window" "/boot/efi/$(cat /etc/machine-id)/limine_history" >/dev/null || stop "limine_history changed since W0: block Xs, then go on"
    echo "logs: $o; snapshot sync held off"; uname -r; echo "Stage 2: ${tr:-the configured m1n1/boot-ctxr.bin}"
    echo "hand-off marker: $({ tr -d '\0' < /proc/device-tree/chosen/asahi,t6050-dcp-handoff; } 2>/dev/null || echo absent)"
    ls /sys/class/drm /sys/class/backlight; cat /sys/class/graphics/fb0/name
    grep -E 'mailbox-recv' /proc/interrupts | awk '{print $NF}' | tr '\n' ' '; echo
    )

The saved `dmesg.txt` holds the kernel command line: it stays in the root-only `$D` and is never printed or published.
The checks below find this boot's folder by its `boot_id`, so they refuse to run on the logs of an earlier boot.

**T1b. The checks (in the T1 boot, after block F).**

    (
    : "${K:?STOP: set K, REPO, D and R first (section 3): they do not survive the reboot}" "${REPO:?STOP: set REPO first}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    BLI=4a67b082-0a4c-41cf-b6c7-440b29bb8c4f; o=$(sudo cat "$D/last-boot")
    [ "$(uname -r)" = 7.3.0-17.v272-11-k114s-r3b-ARCH ] || stop "this boot is $(uname -r), not r3b"
    [ "$(tail -c +5 /sys/firmware/efi/efivars/LoaderEntrySelected-$BLI | iconv -f UTF-16LE -t UTF-8 | tr -d '\0')" = Omarchy.linux-k114s-r3b ] || stop "Limine did not start Omarchy.linux-k114s-r3b"
    [ -e /sys/firmware/efi/efivars/LoaderEntryOneShot-$BLI ] && stop "a one-shot request is still pending"
    [ "$(tr -d '\0' < /proc/device-tree/chosen/aurora,trial 2>/dev/null)" = m1n1/boot-ctxr-disp-oldldr.bin ] || stop "this boot did not come through m1n1/boot-ctxr-disp-oldldr.bin: if it shows no trial, the Stage 2 hung once and this is r3b on P (D1 alone): run T1b-D1 instead"
    [ "$(sudo sed -n 1p /boot/efi/aura-try)" = spent ] || stop "aura-try does not read spent"
    sudo cmp -s "$o/boot_id" /proc/sys/kernel/random/boot_id || stop "block F has not run in this boot (last logs: $o)"
    case $o in "$D"/boot-*-disp-oldldr) ;; *) stop "this boot's logs ($o) are not named for disp-oldldr" ;; esac
    sudo $K status
    t=$(mktemp) || exit 1; trap 'rm -f "$t"' EXIT
    sudo "$REPO/tests/hardware/k114s-display-check.sh" --expect refused --loader-log "$o/loader.log" --wait 10 | tee "$t"
    grep -q '^BAD' "$t" && stop "the display check printed BAD (above)"
    "$REPO/tests/hardware/k114s-r3a-check.sh" --allow-gpu 2>/dev/null | tee "$t"
    grep -q '^BAD' "$t" && stop "the hardware check printed BAD (above)"
    sudo dmesg | grep -i -E 'magicmouse|report_size' | grep -v -i 'command line' | head -5
    grep -l -i -E 'trackpad|magic' /sys/class/input/*/device/name 2>/dev/null | head -2
    omarchy-hw-software-rendering --print
    echo "T1b: r3b on the display tree, hand-off refused, panel on simpledrm; now the GPU-desktop session (T1c)"
    )

Expected: `this boot started: Omarchy.linux-k114s-r3b`, `no LoaderEntryOneShot` twice, `aura-try: spent
m1n1/boot-ctxr-disp-oldldr.bin`. The display check: `ok` for the `refused` marker, `DCP image
3D6C8857-E6F1-3D2E-9DFF-587028AE0C6E is not C51FB0C8-C45D-39B0-85BC-520E600FC950`, `internal display handoff refused`,
`soc/dcp@48ae00000: disabled`, `display-subsystem: disabled`, `no DCP card`, `simpledrm keeps the panel
(card0-Unknown-1)`, no backlight, no crash, the render node, the receive count rising (about 100-420/s), and five
`__OS_LOG` lines as info. The hardware check: the r3b info line, `ok` lines, `device tree is the r1 tree` (right: the
display tree has no `apple,internal-panel`). The kernel's `hid-magicmouse` lines, the trackpad's input device, and the
renderer `Apple M5 Pro (G17S B1)`. The owner checks the keyboard, the trackpad (pointer, click, scroll), Wi-Fi and the
desktop.

**T1c. The GPU-desktop session under load (as the user, in the desktop; about six minutes).** The same lines serve T1
and D1 alone: the second line expects `refused` on the T1 file and `none` on P.

    timeout 300 mpv --no-config --vo=gpu --hwdec=no --ao=null --no-audio --fs --loop-file=inf 'av://lavfi:mandelbrot=size=1512x982:rate=60'; echo "mpv exit $? (124 = the five minutes ran out: expected)"
    e=none; tr -d '\0' < /proc/device-tree/chosen/aurora,trial 2>/dev/null | grep -q disp-oldldr && e=refused; "$REPO/tests/hardware/k114s-display-check.sh" --expect $e --wait 10 --hypr | grep -E '^(ok|BAD)|hyprland|display-check'
    sudo dmesg | grep -i -E 'aurora .*(fault|timeout|hang|error)|GPU fault|drm.*(hang|timeout)' | grep -v -i 'command line' | head

(`/proc/device-tree/chosen/aurora,trial` ends in a NUL byte, so a plain `grep -q -s` on it fails to match; the first line
strips it with `tr -d '\0'` first. With the plain grep T1c passed `--expect none` on the T1 boot and printed two false
`BAD` lines.)

Expected: a moving fractal full screen for five minutes and `mpv exit 124`; then `2302600000.mailbox-recv rises`,
`hyprland: Unknown-1 ... scale 2`, no `BAD`; the last command prints nothing. (No audio device is opened: `--ao=null`.)
A GPU fault or a flat count: stop, keep `$D/boot-*`, and do not arm T2 (the plan's stop conditions).
Record `T1 PASSED` (D1 and D2) in the recovery log and in `$D`: `echo "T1 passed $(date -Is)" | sudo tee "$D/T1-passed"`.

**T1b-D1. D1 alone: r3b on P, no trial** (T1's Stage 2 hung and the pending one-shot started r3b on P, or the
conditional D1-alone boot below). After block F (its folder ends `-configured`):

    (
    : "${K:?STOP: set K, REPO, D and R first (section 3): they do not survive the reboot}" "${REPO:?STOP: set REPO first}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    BLI=4a67b082-0a4c-41cf-b6c7-440b29bb8c4f; o=$(sudo cat "$D/last-boot")
    [ "$(uname -r)" = 7.3.0-17.v272-11-k114s-r3b-ARCH ] || stop "this boot is $(uname -r), not r3b"
    [ "$(tail -c +5 /sys/firmware/efi/efivars/LoaderEntrySelected-$BLI | iconv -f UTF-16LE -t UTF-8 | tr -d '\0')" = Omarchy.linux-k114s-r3b ] || stop "Limine did not start Omarchy.linux-k114s-r3b"
    [ -e /sys/firmware/efi/efivars/LoaderEntryOneShot-$BLI ] && stop "a one-shot request is still pending"
    [ -e /proc/device-tree/chosen/aurora,trial ] && stop "this boot came through $(tr -d '\0' < /proc/device-tree/chosen/aurora,trial): not r3b on P (T1b or D3b instead)"
    [ "$(sudo sed -n 1p /boot/efi/aura-try)" = spent ] || stop "aura-try does not read spent"
    sudo cmp -s "$o/boot_id" /proc/sys/kernel/random/boot_id || stop "block F has not run in this boot (last logs: $o)"
    case $o in "$D"/boot-*-configured) ;; *) stop "this boot's logs ($o) are not named for the configured Stage 2" ;; esac
    sudo $K status
    t=$(mktemp) || exit 1; trap 'rm -f "$t"' EXIT
    sudo "$REPO/tests/hardware/k114s-display-check.sh" --expect none --loader-log "$o/loader.log" --wait 10 | tee "$t"
    grep -q '^BAD' "$t" && stop "the display check printed BAD (above)"
    "$REPO/tests/hardware/k114s-r3a-check.sh" --allow-gpu 2>/dev/null | tee "$t"
    grep -q '^BAD' "$t" && stop "the hardware check printed BAD (above)"
    sudo dmesg | grep -i -E 'magicmouse|report_size' | grep -v -i 'command line' | head -5
    grep -l -i -E 'trackpad|magic' /sys/class/input/*/device/name 2>/dev/null | head -2
    omarchy-hw-software-rendering --print
    echo "T1b-D1: r3b on P (D1 alone), no display section, panel on simpledrm; now T1c"
    )

Expected: as T1b, but the display check reads `/chosen/asahi,t6050-dcp-handoff: absent`, the loader's `does not describe
the internal display: no handoff` line, and `display-subsystem: absent`. Then T1c. Passing proves D1 alone. After a
Stage 2 hang, D2's file is then the suspect (the installed loader's refusal path on the display tree): record it, keep
the loader logs, and stop; the lead decides whether D4 still runs (its loader takes another path on the same tree).

**T1 failed after Limine** (the next boot was the default): block C, then `sudo journalctl -b -1 -k | grep -v -i
'command line' | tail -50` for the kernel side. The conditional **D1 alone** separates r3b from the inert section: after
block P, `sudo $K arm Omarchy/linux-k114s-r3b`, reboot, block F, T1b-D1, T1c.

### T2 = D4, the hand-off (boot 2)

**T2a. Arm, from the T1 boot, after T1 passed.**

    (
    : "${K:?STOP: set K, REPO, D and R first (section 3)}" "${REPO:?STOP: set REPO first}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    PIN=3a9884f3513d110c9602e4261d2826e380bff7d92347da63890372f5307f7087; GPU=9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc
    S2=m1n1/boot-ctxr-disp-pinldr.bin; bd='/etc/systemd/system/systemd-backlight@backlight:apple-panel-bl.service.d'
    sudo test -s "$D/T1-passed" || stop "T1 has not passed ($D/T1-passed); nothing is armed"
    [ "$(uname -r)" = 7.3.0-17.v272-11-k114s-r3b-ARCH ] || [ "$(uname -r)" = 7.3.0-17.v272-4-k114s-r3a-ARCH ] || stop "an unexpected kernel; nothing is armed"
    [ "$(systemctl is-active snapper-cleanup.timer limine-snapper-sync.service snapper-cleanup.service | sort -u)" = inactive ] || stop "the snapshot sync runs (E12): block F's stop lines first; nothing is armed"
    # what D4 needs, already in place (I0)
    grep -q -x 'options appledrm fw27_panel_vrr=0' /etc/modprobe.d/aurora-m5-vrr.conf || stop "no fw27_panel_vrr=0 file (I0); nothing is armed"
    cmp -s "$REPO/linux/brightness/systemd/k114s-first-boot.conf" "$bd/k114s-first-boot.conf" || stop "the brightness drop-in is not installed (I0, E7); nothing is armed"
    sudo test -e /var/lib/k114s-backlight/restore-enabled && stop "brightness restore is turned on; nothing is armed"
    [ "$(grep -c -E '^hl\.monitor\(\{ output = "eDP-[12]", mode = "preferred", position = "auto", scale = 2 \}\)$' ~/.config/hypr/monitors.lua)" = 2 ] || stop "monitors.lua does not have the eDP-1 and eDP-2 rules (I0); nothing is armed"
    [ "$(sudo sha256sum /boot/efi/m1n1/boot-ctxr.bin | cut -c1-64)" = $GPU ] || stop "the configured Stage 2 is not P's file; nothing is armed"
    [ "$(sudo sha256sum /boot/efi/$S2 | cut -c1-64)" = $PIN ] || stop "$S2 is not 3a9884f3...; nothing is armed"
    [ "$(sudo sed -n 1p /boot/efi/aura-try)" = spent ] || stop "aura-try does not read spent; nothing is armed"
    sudo $K arm Omarchy/linux-k114s-r3b || stop "the arm refused (its message is above); nothing is armed"
    sudo sh -c "printf 'armed\n$S2\n' > /boot/efi/aura-try && sync -f /boot/efi" || {
      sudo sh -c "printf 'spent\n$S2\n' > /boot/efi/aura-try; sync -f /boot/efi"
      [ "$(sudo sed -n 1p /boot/efi/aura-try 2>/dev/null)" = spent ] || {
        echo "STOP: aura-try does not read spent, so it may still read armed. Do not reboot. Run: sudo cat /boot/efi/aura-try; if the first line is not spent: sudo sed -i 1s/armed/spent/ /boot/efi/aura-try && sudo sync -f /boot/efi, then read it again"; exit 1; }
      echo "STOP: aura-try was not written or not synced; it reads spent now. The one-shot is still pending: the next boot is r3b on P, or run sudo $K clear"; exit 1; }
    [ "$(sudo sed -n 1,2p /boot/efi/aura-try | tr '\n' ' ')" = "armed $S2 " ] || stop "aura-try does not read back as armed for $S2 (sudo cat /boot/efi/aura-try)"
    sudo $K status
    echo "T2 armed: r3b once, through $S2 once (the hand-off). Rebooting"
    sudo systemctl reboot
    )

Before the reboot (section 10 of the plan): a dark Omarchy theme, the screensaver on, nothing static left on screen.
Expected: as T1a, with `aura-try: armed m1n1/boot-ctxr-disp-pinldr.bin`.

**T2b. The hand-off checks (in the T2 boot, after block F; keep the session short).**

    (
    : "${K:?STOP: set K, REPO, D and R first (section 3): they do not survive the reboot}" "${REPO:?STOP: set REPO first}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    BLI=4a67b082-0a4c-41cf-b6c7-440b29bb8c4f; o=$(sudo cat "$D/last-boot")
    [ "$(uname -r)" = 7.3.0-17.v272-11-k114s-r3b-ARCH ] || stop "this boot is $(uname -r), not r3b"
    [ "$(tail -c +5 /sys/firmware/efi/efivars/LoaderEntrySelected-$BLI | iconv -f UTF-16LE -t UTF-8 | tr -d '\0')" = Omarchy.linux-k114s-r3b ] || stop "Limine did not start Omarchy.linux-k114s-r3b"
    [ -e /sys/firmware/efi/efivars/LoaderEntryOneShot-$BLI ] && stop "a one-shot request is still pending"
    [ "$(tr -d '\0' < /proc/device-tree/chosen/aurora,trial 2>/dev/null)" = m1n1/boot-ctxr-disp-pinldr.bin ] || stop "this boot did not come through m1n1/boot-ctxr-disp-pinldr.bin (no trial: the Stage 2 hung once, this is r3b on P; section 6)"
    [ "$(sudo sed -n 1p /boot/efi/aura-try)" = spent ] || stop "aura-try does not read spent"
    sudo cmp -s "$o/boot_id" /proc/sys/kernel/random/boot_id || stop "block F has not run in this boot (last logs: $o)"
    case $o in "$D"/boot-*-disp-pinldr) ;; *) stop "this boot's logs ($o) are not named for disp-pinldr" ;; esac
    t=$(mktemp) || exit 1; trap 'rm -f "$t" "$t.a" "$t.b"' EXIT
    sudo "$REPO/tests/hardware/k114s-display-check.sh" --expect published --loader-log "$o/loader.log" --wait 10 | tee "$t"
    grep -q '^BAD' "$t" && stop "the display check printed BAD (above): power off after reading it, then section 6"
    # D3's part: the pin loader set the GPU up as the installed loader did in T1 (timestamps dropped). $D is root-only: list it as root
    t1=$(sudo sh -c 'ls -d "$1"/boot-*-disp-oldldr 2>/dev/null | tail -1' _ "$D")
    [ -n "$t1" ] || stop "no T1 loader log in $D to compare with"
    sudo sh -c 'grep -F "FDT: GPU:" "$1/loader.log" | sed "s/^\[[^]]*\] //" | sort -u' _ "$t1" > "$t.a"; sudo sh -c 'grep -F "FDT: GPU:" "$1/loader.log" | sed "s/^\[[^]]*\] //" | sort -u' _ "$o" > "$t.b"
    [ -s "$t.a" ] && cmp -s "$t.a" "$t.b" && echo "ok    the loader's GPU lines equal T1's ($(grep -c '' "$t.a"))" || echo "info  the loader's GPU lines differ from T1's, or T1 logged none: sudo diff them (they carry no command line)"
    sudo dmesg | grep -E 'GPU firmware build: 26B8125' | grep -v -i 'command line' | head -1
    "$REPO/tests/hardware/k114s-r3a-check.sh" --allow-gpu 2>/dev/null | grep -E '^BAD' && stop "the hardware check printed BAD (above)"
    echo "T2b: the hand-off is published and the panel runs on the DCP; now the owner's look and the session checks (T2c)"
    )

Expected (the plan's section 9 list): `ok` for the `published` marker, `internal display handed off: firmware 27.2`,
`external display engines not handed off (Aura 0008, internal panel only)`, `soc/dcp@48ae00000: okay`,
`display-subsystem: okay`, `apple,firmware-uuid 3D6C8857-...`, `apple,firmware-compat 27 2 0`, `the DCP card exists
(../card2)` (the index may differ), `connector card2-eDP-1: connected` (or `eDP-2`), `modes: 3024x1986` (or `1964`: either is
accepted, and only that one size), `vrr_capable 0`, `fb0 is appledrm's`, `appledrm.fw27_panel_vrr = N`, `apple-panel-bl
max_brightness 1000`, `info  apple-panel-bl brightness <b>, actual_brightness <a> (read only)`, `systemd-backlight ...
was skipped`, no saved level, `[drm] Initialized apple for display-subsystem`, no crash, the render node and a rising
receive count. The info lines show the kernel's order (simpledrm first, `DCP booted`, `Initialized apple`, perhaps `no
loader brightness reported; backlight starts at 500 nits`, `appledrmfb`). `ok    the loader's GPU lines equal T1's`, and
the kernel admits `26B8125` after one `not admitted: EINVAL` line, as on P (E2: #230 is not in this loader). A `BAD` is a
stop: read it, power off, section 6.

**T2c. The owner's look and the session (as the user, in the desktop; ten minutes at most).**

    "$REPO/tests/hardware/k114s-display-check.sh" --expect published --wait 5 --hypr | grep -E '^(ok|BAD)|hyprland|display-check'
    hyprctl monitors | grep -E '^Monitor|@|scale:|vrr:|currentFormat:'

Expected: `hyprland: eDP-1 3024x1986@120.00 scale 2 vrr False format XRGB8888` (name, height and format may differ) and
`ok    hyprland: eDP-1 as expected`. The owner looks at an ordinary Omarchy screen: the picture fills the panel with the
notch rows shown, colours are right (wrong colours: linux #1873 is the follow-up, plan section 9), text is sharp at scale
2, the pointer and the keyboard work, and the brightness by eye (record it: no key, no `brightnessctl`, no write, until
D5). Then `sudo systemctl reboot` (boot 3). Record `T2 (D4) PASSED` with the brightness values and the connector name.
On anything wrong: record it, reboot (or power off if the screen is dark), section 6.

**Block A: after a T2 failure, on the r3a boot that follows (after block C; reads only).** It decides whether the kernel
log of the T2 boot shows the display path failing, which alone lets the failure be put on the hand-off (E1).

    (
    : "${D:?STOP: set K, REPO, D and R first (section 3): they do not survive the reboot}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    [ "$(uname -r)" = 7.3.0-17.v272-4-k114s-r3a-ARCH ] || stop "run this on the r3a boot that followed T2"
    t=$(mktemp -d) || exit 1; trap 'rm -rf "$t"' EXIT
    sudo journalctl -b -1 -o short-monotonic --no-pager 2>/dev/null | grep -v -i -E 'command line|cmdline' > "$t/j"
    grep -q -F 'Linux version 7.3.0-17.v272-11-k114s-r3b-ARCH' "$t/j" || stop "the previous boot's journal does not show r3b starting (empty, or lost at the power-off): run D3 (one boot) before attributing anything"
    sw=$(grep -m1 -F 'systemd[1]: Switching root.' "$t/j" | sed -n 's/^\[ *\([0-9.]*\)\].*/\1/p')
    [ -n "$sw" ] || stop "the previous boot's journal ends before the root mount (no 'Switching root'): appledrm cannot have loaded (G6). Run D3 (one boot) before attributing anything"
    awk -v sw="$sw" 'match($0, /^\[ *[0-9]+\.[0-9]+\]/) { ts = substr($0, 2, RLENGTH - 2) + 0; l = tolower($0)
      if (ts > sw + 0 && l ~ / kernel: / && l ~ /dcp|apple-drm|appledrm|display-subsystem/ && l ~ /crash|fail|error|timeout|timed out|panic|fault|oops|abort|died/) print }' "$t/j" > "$t/f"
    echo "kernel lines on the display path that report a failure after the root mount (at ${sw} s): $(grep -c '' "$t/f")"; head -20 "$t/f"
    [ -s "$t/f" ] || stop "no DCP, RTKit-on-DCP or apple-drm failure after the root mount in T2's kernel log (the last line it kept: $(grep ' kernel: ' "$t/j" | tail -1 | cut -c1-16)). Not shown to be the display path: run D3 (one boot) before attributing anything"
    sudo install -m600 "$t/f" "$D/T2-display-failure.txt" || stop "the lines were not kept in $D"
    echo "A: T2's kernel log shows the display path failing after the root mount: the hand-off is the suspect. Record it on #17 with both loader logs; D3 is not needed"
    )

Expected on a hand-off failure: the count, the lines (`DCP`, `RTKit`, `apple-drm` with a crash, timeout or error), then
`A: ...`. Any STOP here means D3 next.

### Boot 3: back to the default, then close the window

**Block C (after the reboot, first thing; stops the snapshot sync again, otherwise reads only).** Also the first block
of any default boot inside the window (a fallback boot after a hang).

    (
    : "${K:?STOP: set K, REPO, D and R first (section 3): they do not survive the reboot}" "${REPO:?STOP: set REPO first}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    BLI=4a67b082-0a4c-41cf-b6c7-440b29bb8c4f
    # the snapshot sync held off again in this boot (E12)
    for i in $(seq 90); do [ "$(systemctl show -p ActiveState --value snapper-cleanup.service)" = inactive ] && break; sleep 2; done
    sudo systemctl stop snapper-cleanup.timer limine-snapper-sync.service || stop "the snapshot sync was not stopped"
    [ "$(systemctl is-active snapper-cleanup.timer limine-snapper-sync.service snapper-cleanup.service | sort -u)" = inactive ] || stop "the snapshot sync is not inactive (systemctl status snapper-cleanup.timer limine-snapper-sync.service)"
    sudo grep -q -E '^[[:blank:]]*//Snapshots' /boot/efi/limine.conf && stop "limine.conf has a Snapshots entry (the sync ran before this block): block Xs, then block C again"
    sudo diff -r -q "$D/limine_history.before-window" "/boot/efi/$(cat /etc/machine-id)/limine_history" >/dev/null || stop "limine_history changed since W0: block Xs, then block C again"
    [ "$(uname -r)" = 7.3.0-17.v272-4-k114s-r3a-ARCH ] || stop "this boot is $(uname -r), not r3a"
    [ "$(tail -c +5 /sys/firmware/efi/efivars/LoaderEntrySelected-$BLI | iconv -f UTF-16LE -t UTF-8 | tr -d '\0')" = Omarchy.linux-k114s ] || stop "Limine did not start Omarchy.linux-k114s"
    [ -e /sys/firmware/efi/efivars/LoaderEntryOneShot-$BLI ] && stop "a one-shot request is pending: this was not a default boot"
    [ -e /proc/device-tree/chosen/aurora,trial ] && stop "this boot came through an aura-try trial: $(tr -d '\0' < /proc/device-tree/chosen/aurora,trial)"
    [ "$(tr -d '\0' < /proc/device-tree/chosen/asahi,m1n1-stage2-version)" = 1.0.0b13-g22b71758-dirty ] || stop "not the proven loader"
    [ "$(sudo sha256sum /boot/efi/m1n1/boot-ctxr.bin | cut -c1-64)" = 9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc ] || stop "boot-ctxr.bin is not the GPU file"
    sudo $K status
    t=$(mktemp) || exit 1; trap 'rm -f "$t"' EXIT
    "$REPO/tests/hardware/k114s-r3a-check.sh" --allow-gpu 2>/dev/null | tee "$t"
    grep -q '^BAD' "$t" && stop "the hardware check printed BAD (above)"
    sudo "$REPO/tests/hardware/k114s-display-check.sh" --expect none --wait 5 | grep -E '^BAD' && stop "the display check printed BAD (above)"
    sudo dmesg | grep -E 'Oops|BUG:|WARNING:|SError|storm' | grep -v -i 'command line' && stop "the kernel log has an Oops, BUG, WARNING, SError or storm line (above)"
    echo "C: a clean default boot of r3a on the configured GPU Stage 2; the snapshot sync held off"
    )

Then block P (`window open, r3b installed`). Expected: `this boot started: Omarchy.linux-k114s`, `no LoaderEntryOneShot`
twice, the hardware check's `ok` lines, the render node, `C: ...`.

**C1. The trial Stage 2 files off the ESP** (their copies stay in `$D`).

    (
    : "${D:?STOP: set K, REPO, D and R first (section 3)}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    h() { sudo sha256sum "$1" 2>/dev/null | cut -c1-64; }
    [ "$(sudo sed -n 1p /boot/efi/aura-try)" = spent ] || stop "aura-try does not read spent: a trial is armed; nothing was changed"
    for f in boot-ctxr-disp-oldldr.bin boot-ctxr-disp-pinldr.bin boot-ctxr-gpu-pinldr.bin; do
      sudo test -e /boot/efi/m1n1/$f || continue
      [ "$(h /boot/efi/m1n1/$f)" = "$(h "$D/$f")" ] || stop "m1n1/$f differs from its copy in $D; it stays on the ESP"
      sudo rm /boot/efi/m1n1/$f && sudo sync -f /boot/efi || stop "m1n1/$f was not removed"
    done
    sudo ls /boot/efi/m1n1 | LC_ALL=C sort | sudo cmp -s "$D/m1n1.before-window" - || stop "m1n1/ is not as before the window: $(sudo ls /boot/efi/m1n1 | tr '\n' ' ')"
    echo "C1: the trial Stage 2 files are off the ESP; ESP free $(df -B1 --output=avail /boot/efi | tail -1)"
    )

Expected: the last line with about 110,790,000 free.

**C2. Remove `linux-k114s-r3b`** (its package stays in `$D`). Run C2, X and C4 back to back.

    (
    : "${K:?STOP: set K, REPO, D and R first (section 3)}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    c=/boot/efi/limine.conf; REL=7.3.0-17.v272-11-k114s-r3b-ARCH; GPU=9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc
    [ "$(uname -r)" = 7.3.0-17.v272-4-k114s-r3a-ARCH ] || stop "remove r3b from a boot of r3a, never from r3b itself; nothing was changed"
    pacman -Q linux-k114s-r3b >/dev/null 2>&1 || stop "linux-k114s-r3b is not installed; nothing to remove"
    sudo test -s "$D/linux-k114s-r3b-7.3.0.r3b-1-aarch64.pkg.tar.zst" || stop "the package is not kept in $D; nothing was changed"
    [ "$(systemctl is-active snapper-cleanup.timer limine-snapper-sync.service snapper-cleanup.service | sort -u)" = inactive ] || stop "the snapshot sync runs (E12): block C's stop lines first; nothing was changed"
    grep -q -x 'export M1N1_UPDATE_DISABLED=1' /etc/default/update-m1n1 || stop "update-m1n1 is not off; nothing was changed"
    [ "$(df -B1 --output=avail /boot/efi | tail -1)" -ge 88080384 ] || stop "below the space guard's minimum: C1 first; nothing was changed"
    sudo pacman -R --noconfirm linux-k114s-r3b 2>&1 | sudo tee "$D/remove-r3b.log" | grep -E '^(:: |\(|warning|error)|Removed|Updating|update-boot-ctxr'
    pacman -Q linux-k114s-r3b >/dev/null 2>&1 && stop "linux-k114s-r3b is still installed (pacman's message is above)"
    sudo test -e /boot/efi/EFI/Linux/omarchy_linux-k114s-r3b.efi && stop "the r3b image is still on the ESP: do not reboot; read $D/remove-r3b.log"
    [ -e /usr/lib/modules/$REL ] && echo "info  /usr/lib/modules/$REL is left (files pacman did not own): sudo rm -r it once read"
    [ "$(sudo sha256sum /boot/efi/m1n1/boot-ctxr.bin | cut -c1-64)" = $GPU ] || stop "boot-ctxr.bin is no longer 9825a103...: do not reboot"
    sudo cmp -s $c "$D/limine.conf.after-window" || stop "limine.conf is not the file W1 left (compare under sudo, never in a shared window); block X will refuse: a Snapshots entry is block Xs, anything else the P5b rebuild"
    sudo $K check || stop "check is not clean; do not reboot"
    echo "C2: r3b removed; limine.conf is as W1 left it; boot-ctxr.bin rewritten byte for byte. Now block X"
    )

Expected: `(1/1) removing linux-k114s-r3b`, `Removed unused Limine boot entry: linux-k114s-r3b`, the Stage 2 hook's
`update-boot-ctxr-k114s: wrote ... K114s device tree 2c870ba9f5963f5a` (it also runs on a removal of `dtbs/`), then the
check with `entry 2` and the last line.

**C3. Block X** (above): the `linux-aurora` image and its entry back, byte for byte.

**C4. The boot record against the one from before the window, the close, and the snapshot sync back on.**

    (
    : "${K:?STOP: set K, REPO, D and R first (section 3)}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    rec() { sudo sh -c 'cd /boot/efi && { sha256sum limine.conf m1n1/boot-ctxr.bin k114s-repair/k114s.dtb EFI/Linux/*.efi; sha256sum /usr/local/lib/omarchy-k114s/k114s.dtb; grep -i "^default_entry" limine.conf; grep -E "^[[:blank:]]*/" limine.conf; grep -E "^[[:blank:]]*path:" limine.conf; sed -n 1p aura-try; }'; }
    sudo test -e "$D/window-open" && stop "the window marker is still there: block X has not finished"
    pacman -Q linux-k114s-r3b >/dev/null 2>&1 && stop "r3b is still installed: C2 first"
    rec | sudo cmp -s "$D/before-window.txt" - || { rec | sudo diff "$D/before-window.txt" - | grep -v -i cmdline; stop "a boot file differs from the record taken before the window (above)"; }
    sudo diff -r -q "$D/limine_history.before-window" "/boot/efi/$(cat /etc/machine-id)/limine_history" >/dev/null || stop "limine_history differs from W0's copy: block Xs first"
    echo "no boot file changed"
    sudo $K check || stop "check is not clean"
    was=$(sudo cat "$D/free.before-window"); now=$(df -B1 --output=avail /boot/efi | tail -1)
    [ $((now - was)) -le 1048576 ] && [ $((was - now)) -le 1048576 ] || stop "ESP free is $now, the window opened at $was: find what took the space"
    grep -m1 '^IgnorePkg = ' /etc/pacman.conf | grep -q -w linux-k114s || stop "the holds block is gone"
    [ "$(systemctl is-enabled suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target | sort -u)" = masked ] || stop "a sleep target is not masked"
    # the snapshot sync back on (E12): its 10-minute boot delay has passed, so the timer runs once at once
    date +%s | sudo tee "$D/sync-restarted" >/dev/null
    sudo systemctl start snapper-cleanup.timer limine-snapper-sync.service || stop "the snapshot sync did not start: sudo systemctl start snapper-cleanup.timer limine-snapper-sync.service"
    systemctl is-active -q snapper-cleanup.timer && systemctl is-active -q limine-snapper-sync.service || stop "the snapshot sync is not active again"
    sudo rm -f "$D/sync-held"
    echo "C4: DISPLAY WINDOW CLOSED. ESP free $now (was $was); the snapshot sync runs again. In a minute: C5"
    )

Expected: `no boot file changed`, the check with `entry 3`, and `C4: DISPLAY WINDOW CLOSED`. Record it in the recovery
log. Updates resume as in P6, with the P6d after-block before every reboot that follows an update. What stays installed:
E11.

**C5. The sync's first run after the close left `limine.conf` alone (reads only; a minute after C4).**

    (
    : "${D:?STOP: set K, REPO, D and R first (section 3)}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    c=/boot/efi/limine.conf; since=$(sudo cat "$D/sync-restarted") || stop "C4 has not run"
    systemctl is-active -q snapper-cleanup.service && stop "the cleanup is still running: run C5 again in a minute"
    n=$(sudo journalctl --since "@$since" --no-pager -o cat | grep -c -F 'Updated: /boot/efi/limine.conf')
    [ "$n" -ge 1 ] || stop "no sync run since C4 yet: run C5 again after the next one (systemctl list-timers snapper-cleanup.timer)"
    sudo journalctl --since "@$since" --no-pager -o cat | grep -E 'Stopping boot entry creation|Boot usage limit' | head -2
    sudo cmp -s $c "$D/limine.conf.before-window" || stop "the sync's run changed limine.conf: compare it under sudo with $D/limine.conf.before-window (never in a shared window); do not reboot until it is read"
    [ "$(sudo grep -E '^[[:blank:]]*/' $c | tr -d ' \t' | tr '\n' ' ')" = "/+Omarchy //linux-aurora //linux-k114s " ] || stop "the menu is not exactly the folder, linux-aurora and linux-k114s"
    echo "C5: the snapshot sync ran ($n) and left limine.conf as before the window"
    )

Expected: `Boot usage limit reached ...`, `Stopping boot entry creation: Boot partition usage from 78.8% to 109.3% (+152.3
MiB) will exceed the 85.0% limit.` (the figures of the day), then the last line. Record it.

C5 can stop with `no sync run since C4 yet: run C5 again after the next one`. That is benign: the timer's run had not
happened yet (it ran about a minute after C4 on the first window, and C5 passed on the second try). Nothing was changed
by the stop. Wait for the sync (`systemctl list-timers snapper-cleanup.timer`) and run C5 again; do not start the sync
by hand.

### D3 (conditional): the pin loader on P's exact tree

Only after a T2 failure before the kernel (the fallback boot was r3b on P with no `aurora,trial`), a GPU-side failure in
T2, or a stop in block A. From any boot on P, with block P passing:

    (
    : "${K:?STOP: set K, REPO, D and R first (section 3)}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    h() { sudo sha256sum "$1" 2>/dev/null | cut -c1-64; }
    GPIN=3749a5efc7a8a0d3565e3038d4ba42d94475a79944f4789e07fc26c2a89d611e; S2=m1n1/boot-ctxr-gpu-pinldr.bin
    sudo test -e "$D/window-open" && pacman -Q linux-k114s-r3b >/dev/null 2>&1 || stop "the window is not open with r3b installed; nothing is armed"
    [ ! -e /proc/device-tree/chosen/aurora,trial ] || stop "arm from a boot on P; nothing is armed"
    [ "$(systemctl is-active snapper-cleanup.timer limine-snapper-sync.service snapper-cleanup.service | sort -u)" = inactive ] || stop "the snapshot sync runs (E12): block C's or F's stop lines first; nothing is armed"
    [ "$(sudo sed -n 1p /boot/efi/aura-try)" = spent ] || stop "aura-try does not read spent; nothing is armed"
    if [ "$(h /boot/efi/$S2)" != $GPIN ]; then
      sudo cp "$D/${S2#m1n1/}" /boot/efi/$S2.k114s-new && sudo sync -f /boot/efi && [ "$(h /boot/efi/$S2.k114s-new)" = $GPIN ] || { sudo rm -f /boot/efi/$S2.k114s-new; stop "$S2 was not written; nothing is armed"; }
      sudo mv -f /boot/efi/$S2.k114s-new /boot/efi/$S2 && sudo sync -f /boot/efi && [ "$(h /boot/efi/$S2)" = $GPIN ] || stop "$S2 does not read back; nothing is armed"
    fi
    sudo $K arm Omarchy/linux-k114s-r3b || stop "the arm refused (its message is above); nothing is armed"
    sudo sh -c "printf 'armed\n$S2\n' > /boot/efi/aura-try && sync -f /boot/efi" || {
      sudo sh -c "printf 'spent\n$S2\n' > /boot/efi/aura-try; sync -f /boot/efi"
      [ "$(sudo sed -n 1p /boot/efi/aura-try 2>/dev/null)" = spent ] || {
        echo "STOP: aura-try does not read spent, so it may still read armed. Do not reboot. Run: sudo cat /boot/efi/aura-try; if the first line is not spent: sudo sed -i 1s/armed/spent/ /boot/efi/aura-try && sudo sync -f /boot/efi, then read it again"; exit 1; }
      echo "STOP: aura-try was not written or not synced; it reads spent now. The one-shot is still pending: the next boot is r3b on P, or run sudo $K clear"; exit 1; }
    [ "$(sudo sed -n 1,2p /boot/efi/aura-try | tr '\n' ' ')" = "armed $S2 " ] || stop "aura-try does not read back as armed for $S2"
    echo "D3 armed: r3b once, through $S2 once. Rebooting"
    sudo systemctl reboot
    )

**D3b. The checks (in the D3 boot, after block F; its folder ends `-gpu-pinldr`).**

    (
    : "${K:?STOP: set K, REPO, D and R first (section 3): they do not survive the reboot}" "${REPO:?STOP: set REPO first}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    BLI=4a67b082-0a4c-41cf-b6c7-440b29bb8c4f; o=$(sudo cat "$D/last-boot")
    [ "$(uname -r)" = 7.3.0-17.v272-11-k114s-r3b-ARCH ] || stop "this boot is $(uname -r), not r3b"
    [ "$(tail -c +5 /sys/firmware/efi/efivars/LoaderEntrySelected-$BLI | iconv -f UTF-16LE -t UTF-8 | tr -d '\0')" = Omarchy.linux-k114s-r3b ] || stop "Limine did not start Omarchy.linux-k114s-r3b"
    [ -e /sys/firmware/efi/efivars/LoaderEntryOneShot-$BLI ] && stop "a one-shot request is still pending"
    [ "$(tr -d '\0' < /proc/device-tree/chosen/aurora,trial 2>/dev/null)" = m1n1/boot-ctxr-gpu-pinldr.bin ] || stop "this boot did not come through m1n1/boot-ctxr-gpu-pinldr.bin: with no trial the pin loader hung on P's tree (the binary is the suspect: section 6)"
    [ "$(sudo sed -n 1p /boot/efi/aura-try)" = spent ] || stop "aura-try does not read spent"
    sudo cmp -s "$o/boot_id" /proc/sys/kernel/random/boot_id || stop "block F has not run in this boot (last logs: $o)"
    case $o in "$D"/boot-*-gpu-pinldr) ;; *) stop "this boot's logs ($o) are not named for gpu-pinldr" ;; esac
    sudo $K status
    t=$(mktemp) || exit 1; trap 'rm -f "$t" "$t.a" "$t.b"' EXIT
    sudo "$REPO/tests/hardware/k114s-display-check.sh" --expect none --loader-log "$o/loader.log" --wait 10 | tee "$t"
    grep -q '^BAD' "$t" && stop "the display check printed BAD (above)"
    "$REPO/tests/hardware/k114s-r3a-check.sh" --allow-gpu 2>/dev/null | tee "$t"
    grep -q '^BAD' "$t" && stop "the hardware check printed BAD (above)"
    # the pin loader set the GPU up as the installed loader did (T1, or any P boot logged by block F). $D is root-only: list it as root
    t1=$(sudo sh -c 'ls -d "$1"/boot-*-disp-oldldr "$1"/boot-*-configured 2>/dev/null | tail -1' _ "$D")
    [ -n "$t1" ] || stop "no installed-loader log in $D to compare with"
    sudo sh -c 'grep -F "FDT: GPU:" "$1/loader.log" | sed "s/^\[[^]]*\] //" | sort -u' _ "$t1" > "$t.a"; sudo sh -c 'grep -F "FDT: GPU:" "$1/loader.log" | sed "s/^\[[^]]*\] //" | sort -u' _ "$o" > "$t.b"
    [ -s "$t.a" ] && cmp -s "$t.a" "$t.b" || stop "the pin loader's GPU lines differ from the installed loader's (${t1##*/}): sudo diff them; the binary is the suspect"
    sudo dmesg | grep -E 'GPU firmware build: 26B8125' | grep -v -i 'command line' | head -1
    echo "D3b: the pin loader boots P's tree as the installed loader does: T2's failure is the hand-off; record it on #17 with both loader logs"
    )

Expected: as T1b-D1 (`absent` marker, the `does not describe the internal display: no handoff` line, `display-subsystem:
absent`, no DCP card), the GPU lines equal, `26B8125` admitted after one `not admitted: EINVAL` line. A D3 that hangs (no
trial in the fallback boot, or a black screen) puts T2's failure on the loader binary, not on the hand-off; record that on
#18. C1 removes the file with the others.

## 5. Ways back

Each step's undo is next to it. The configured Stage 2 and `default_entry` are never written in this runbook, so every
power-off lands on P with r3a, except when the one-shot is still pending (section 6).

**From Linux:**

| Layout | Back to the promoted state |
| --- | --- |
| After W0 only | `sudo systemctl start snapper-cleanup.timer limine-snapper-sync.service && sudo rm -r /var/lib/k114s-recovery/display` |
| After W1 (image off, no r3b) | block X, then C4 (it starts the snapshot sync again) |
| A `Snapshots` entry in the window | block Xs, then the step that stopped |
| After I0 | its undo line (four commands) |
| After I1 or S | C1, C2, then block X, then C4 |
| A one-shot armed but not booted | `sudo $K clear`; and if `aura-try` reads `armed`: `sudo sed -i 1s/armed/spent/ /boot/efi/aura-try && sudo sync -f /boot/efi` |
| After H | the undo of H; a crash loop: H-crash |

**From macOS** (Startup Options, Terminal in the repair bundle folder, tool `3bfa3d11...`):

- **The window is closed** (before W1, after C4): the promotion's section 5 as written: `stage2 r1`, `default aurora`,
  `restore-repair`. Between W0 and W1 too: nothing on the ESP has changed.
- **The window is open, no r3b** (after W1, before I1, or after C2, before X): `default aurora` does not exist (no
  image). `sudo ./k114s-repair stage2 r1` for a Stage 2 suspect. `restore-repair --check`, then `restore-repair`, works
  without any removal: about 190 MB are free, more than the image's 111.8 MB plus the tool's 8 MiB reserve
  (`k114s_repair.py` `restore_repair`, lines 922-945). That holds only because the snapshot sync is held off (E12): a
  `Snapshots` copy of r3a's image would leave about 110 MB, and `--check` would then say `NOT ENOUGH`. If it does, boot
  Linux (the default still works) and run block C, then Xs.
- **The window is open, r3b installed** (after I1):
  - Stage 2 suspect: `sudo ./k114s-repair stage2 r1` (r3a ran on the r1 tree in step E).
  - r3a image suspect only: point the default at r3b by hand (`docs/r3a-promotion.md` section 5, "a manual edit"):
    `sudo diskutil mount <the EFI volume>`, `sudo sed -i '' 's#^default_entry: .*#default_entry: Omarchy/linux-k114s-r3b#'
    /Volumes/EFI/limine.conf`, check with `grep -n '^default_entry' /Volumes/EFI/limine.conf`, `diskutil unmount`. r3b
    on P is proven by T1 (not before). Then, in Linux, put the line back the P2a way with `Omarchy/linux-k114s`.
  - Both suspect (the static way back): first `sudo rm /Volumes/EFI/EFI/Linux/omarchy_linux-k114s-r3b.efi` (its entry
    stays, dangling and unused), then `sudo ./k114s-repair restore-repair --check` and `sudo ./k114s-repair
    restore-repair`. Without that removal it stops with `no omarchy_linux-aurora.efi to remove; nothing written`. After
    it about 181 MB are free (the two trial Stage 2 files take about 9 MB; tested in D0's replica case, 103 checks).
- **A stuck request** (r3b boots again and again, because Limine's erase did not survive the power cut): mount the ESP
  read-write and rename the r3b entry so its id matches nothing:
  `sudo sed -i '' 's#^\([[:blank:]]*//linux-k114s-r3b\)[[:blank:]]*$#\1-off#' /Volumes/EFI/limine.conf`, check with
  `grep -n 'linux-k114s-r3b' /Volumes/EFI/limine.conf`, unmount, boot Linux (an id that matches nothing falls through to
  `default_entry`). In Linux: `sudo $K clear`, then undo the rename. An `aura-try` that keeps reading `armed` cannot
  happen: the loader writes `spent` before it loads the file.
- **Never from macOS:** `rollback all`, `rollback stage2` (it restores trial1, not r1), `kernel`, `apply`, `default
  original`; in the window also `default aurora`. The macOS `stage2` command for a new-loader file does not exist (D9b):
  the trial files are never configured, so it is not needed.

**Not counted as a way back** (untested): `module_blacklist=appledrm` or `nomodeset` after a published hand-off
(TripleU613 offered to try the first on the J714s); booting the r3a entry on the display Stage 2.

## 6. A hang or a black screen: which boot comes next

If the Mac still answers over T3 or ssh, use the black-T2 note below the table first (a clean reboot keeps the loader log). Otherwise hold the power button until the Mac is off, start it, and run block F first on an r3b boot (block C on an r3a boot),
then block P, then the row:

| Trial | The fallback boot is | How to tell | Then |
| --- | --- | --- | --- |
| T1, hang before Limine (the loader on the display tree) | r3b on P: the one-shot was still pending | `uname -r` is r3b, no `aurora,trial`, `status`: `this boot started: Omarchy.linux-k114s-r3b` | T1b-D1 (D1 alone, measured on this boot). Report D2's failure |
| T1, hang or black after Limine (the kernel) | r3a on P (the default) | `uname -r` is r3a | block C, the T1 kernel log (`journalctl -b -1 -k`, filtered), then the conditional D1 alone |
| T1's fallback (r3b on P) also hangs | r3a on P | as above | block C. r3b is the suspect; stop the trials, close the window (C1, C2, X, C4) |
| T2, hang before Limine | r3b on P, proven by T1 | as in the first row | T1b-D1 (`--expect none`), then D3 (one boot) |
| T2, black after the kernel started | r3a on P | `uname -r` is r3a | block C, then block A. **Only** if A ends `A: ...` (a DCP, RTKit-on-DCP or apple-drm failure logged after `Switching root`): the hand-off; record on #17, no D3. If A stops (no T2 journal, a journal that ends before the root mount or the disk unlock, or no failure line on the display path): D3 (one boot) before anything is attributed or reported (E1) |
| T2, a picture but a `BAD` | reboot normally: r3a on P | | block C; block A for the record; D3 if the `BAD` is on the GPU side |
| D3, hang (no trial in the fallback boot) or black | r3b on P (before Limine) or r3a on P | as in the rows above | T2's failure is the loader binary, not the hand-off: record on #18; stop the trials and close the window |
| Any boot stops at the Limine menu | the keyboard does not work there: power off | | macOS, section 5 |

A black T2 panel does not mean a dead kernel. If T3 or ssh still answers, the lead runs block F and T2b remotely (the logs survive), then `sudo journalctl --sync; sync` and `sudo systemctl reboot` (the default r3a on P comes back). Only if nothing answers: wait more than 5 minutes first (journald syncs error lines every 5 minutes), then hold the power button. A forced power-off loses T2's loader log, so block A may send the lead to D3.


After a failed T2 the window stays open until the lead decides: a fixed retry (same blocks, new file hashes) or the close.

## 7. Next: D5 brightness (briefly; the runbook is now `docs/r3-display-d5-d9.md`)

A second window under the same rules (W0, W1, then the D5a package instead of I1's): `linux-k114s-r3b` version
`r3b.b1` with `patches/linux/brightness` 0001-0003, 0005, 0006 (0004 is in v272-11), built from the kept r3b tree and
installed from a boot on P (G6), then D5a as T1 was (one-shot only, P's Stage 2, the GPU-desktop session), then D5 as T2
with the brightness tree (`t6050-k114s-brightness.dtsi`, `apple,min-brightness = <10>`) on the pin loader, and the
owner's stepped check (`docs/r3-brightness.md`, steps 1-7). The drop-in from I0 stays until that check passes. Re-check
the kernel base (E3) against betizzel's newest release before the D5a build. Then D6 (VRR), D7 (DPMS on OLED), D8 (night
light), and the promotions D9a and D9b (which need the macOS tool's per-variant loader prefix first).

## 8. Risks the owner should know

- **D4 may leave the panel dark until a power-off.** Once `appledrm` binds, simpledrm is gone; a DCP that fails after
  that point has no retreat on firmware 27. The power-off lands on r3a on P with the panel on simpledrm.
- **The pin loader has never run on any Mac.** It is the PR's build (LLVM 23.1.3), not the channel's. A hang in it falls
  back to r3b on P (T1 proves that boot), and D3 then tells the binary from the hand-off.
- **The backlight may start at 500 nits on an OLED with no control until D5** (`no loader brightness reported`, the
  J714s on v272-12; the same code is in v272-11). Keep T2's session short, a dark theme, the screensaver on, nothing
  static. Nothing writes the level (E7), so the panel keeps whatever the firmware shows.
- **Two kernels and one image during the window.** `default aurora` from macOS is gone; `restore-repair` needs the r3b
  image removed first (section 5). Updates are paused until C4.
- **hyprland-m5 0.57.2-3 is a developer build.** Its provenance is betizzel's release digest (`4601e97e...`) and the
  sha256 in betizzel's manifest (`c87f2570...`); its signature and key ship with it in the same release, so the
  signature only shows the files agree with each other (E4). A compositor crash is recovered by H-crash and the undo of H.
- **A hook could do more than expected** (a full image rebuild during I1 or C2). I1, C2 and X stop on any `limine.conf`
  difference beyond the expected entry, before a reboot.
- **The `Snapshots` risk comes from a timer, not only from hooks.** `snapper-cleanup.timer` runs `limine-snapper-sync`
  every hour and 10 minutes after each boot, and in the one-image states of the window its 85 % limit would let it copy
  r3a's image (E12). It is held off by a stop in every boot of the window (W0, F, C) and checked before each step; if a
  run slips through (a block run more than 10 minutes after a boot), block F or C stops and block Xs undoes it.
- **The loader log is a 16 KiB ring** and is lost at the next boot: block F first, every time.
- **Suspend stays blocked.** Closing the lid locks the session and nothing more.

## 9. Tests and evidence

Agent-run on 2026-11-15, as a normal user (sudo for reads only), nothing installed, nothing written outside the build
area and the scratch folder:

| Test | Result | Label |
| --- | --- | --- |
| `bash tests/linux/run-r3.sh` | `r3 update tooling: 1184 passed, 0 failed, 0 test file(s) skipped` (1,053 before; the two new files add 108 and 23) | emulator/replica |
| `tests/linux/test-display-trials-runbook.sh` | 108 passed: block P in the three window states; W0, W1, X, Xs, I0, I1, S, T1a, T2a, D3, C1, C2, C4 and C5 cut out of this file and run in order against a fake ESP with the real `k114s-boot-once`; the close ends with `no boot file changed` and the ESP as before the window; the snapshot sync stopped by W0, F and C, started by C4, and refused by P, W1, X, Xs, T2a and C2 while it runs; a `Snapshots` entry stops X and is undone by Xs (after W1 and with r3b installed), and Xs refuses a file that differs by more; W1 keeps its after-window copy when the tool fails; F, T1b, T1b-D1, T2b and D3b each in its own simulated boot (a trial block refuses another boot's logs or trial, and calls the display check with its own `--expect`); T2b and D3b find T1's folder in a root-only `$D` (and the draft's plain `ls` does not); block A lets T2 skip D3 only on a display-path failure after `Switching root`; each other STOP (a second W0, an extra menu entry, a removal that changes more than the entry, too little space, a `limine.conf` that is neither W0's nor W1's, a hook that builds two images, `appledrm` in the initramfs, a failing `check-package`, no gates record, no G4, an armed `aura-try`, a wrong trial file, no T1 pass, no `eDP-2` rule, no brightness drop-in, a trial file that differs from its copy, a removal from the r3b boot, a boot file changed during the window) leaves the files as they were or says what to run; every block parses with `bash -n`, every writing block has the `findmnt` guard, every STOP exits 1 | emulator/replica |
| `tests/hardware/test-display-check.sh` | 23 passed | emulator/replica |
| `tests/hardware/k114s-display-check.sh --expect none` on this boot (P, r3a; `sudo` for the loader log) | `display-check (none): 11 ok, 0 BAD`; with `--hypr` as the user, `Unknown-1 3024x1986@60.00 scale 2` | agent-run |
| `tests/test-adt-display-facts.py` on the display tree | 17 checks pass (2 new) | emulator/replica |
| `tests/k114s-adt-display-facts.py --dtb` the display tree, live ADT (read-only) and saved copy | 17 PASS, none failed; the stricter mailbox check passes (type and die cells 0) | agent-run |
| `check-package.sh` r3b against `linux-aurora`, `linux-k114s`, and a name that is not installed | `all passed`, `all passed`, `SKIP ... is not installed` and `all run checks passed; 2 skipped` | agent-run |
| `pacman -U --print` | `linux-k114s-r3b 7.3.0.r3b-1`; `hyprland-m5 0.57.2-3` | agent-run |
| `build/make-stage2.sh` | the control recomposes `9825a103...` byte for byte; `-disp-oldldr` equals D0's `9e43d27a...`; `-disp-pinldr` `3a9884f3...`, `-gpu-pinldr` `3749a5ef...` | agent-run |
| `abi-probe.cpp` against 0.57.2-3's and 0.57.2-2's headers | `m_layerSurfaceLayers` `0x790` (stock) and `0x7b0` | agent-run |
| both hyprland-m5 packages: sha256 against betizzel's manifests (the provenance); `gpg --verify` with the key from the same release (integrity only, E4) | `c87f2570...`, `12e46eb0...`; `Good signature` from `0DA040FF...` | agent-run |
| `/etc/pacman.conf` `IgnorePkg` lines; `pacman -U --print` of both hyprland-m5 files with the holds in place | `hyprland-m5` on lines 7 and 12, `omarchy-hyprland-titlebars` on line 7; both listed | agent-run |
| the snapshot sync's units, drop-in, watcher and plugin; its journal; the ESP size | `snapper-cleanup.timer` `OnBootSec=10m` `OnUnitActiveSec=1h`, `ExecStopPost=limine-snapper-sync`; `78.8% to 109.3% (+152.3 MiB)`; 523,132,928 bytes, so 63.6 % used and 79.0 % after one kernel in the one-image states | agent-run |
| two `limine-snapper-sync` runs on the promoted layout: 17:51:56 (see below) and the timer's hourly run at 18:16:44 | `limine.conf` sha256 `2723642d...` (3,015 bytes) the same before and after each; `snapshots.json` equal to `.old`; the hourly run logged the `78.8% to 109.3%` skip and `Updated: /boot/efi/limine.conf` | agent-run |
| Omarchy's `workspace-modes.lua` and `omarchy-hyprland-workspace-layout-toggle` | the plugin loads only while `titlebars.so` exists and something floats; the toggle saves the mode, `hyprctl eval` alone does not; saved today: workspace 1 `dwindle`, default `scrolling` | source-read |
| `strings` of both loaders | the 0008 line `external display engines not handed off on firmware %s` and `3D6C8857-...` only in the pin loader; the refusal, `handed off` and `does not describe` lines in both | agent-run |
| `mpv` with the lavfi source, `--vo=null --ao=null` | plays | agent-run |
| `build/check-publishable.sh` | `check-publishable: ok (343 files)` | agent-run |

**One unplanned write by the agent (2026-11-15 17:51:56).** To read its usage the agent ran `limine-snapper-sync --help`
as a normal user. The tool ignores unknown options and escalates itself through `sudo`, so it ran one full sync: it logged
the usual skip (`78.8% to 109.3%`), rewrote `/boot/efi/limine.conf` and `limine_history/snapshots.json`, and added
nothing. The rewrite was byte-identical (`2723642d...` before and after, measured around it), so only the two files'
modification times changed; the same rewrite runs every hour from the timer. That is why the window rules now name the
`limine-snapper-*` commands.

Not verified: anything that boots; `limine-entry-tool --remove-uki` followed by the hook's add and remove of r3b leaving
`limine.conf` exactly as W1 left it (X and C2 check it and stop if not); the macOS tool on the window layout of the real
ESP (M, optional); `hyprctl plugin list` with the restored plugin and the unsaved float by `hyprctl eval` (H3 and H4 are
the first time); the text-console switch of H-crash on this keyboard; the shape of a real `Snapshots` tree (Xs compares
and refuses anything it does not recognise); the 10-minute timer's first run in a trial boot (block F and C stop it, and
check for a `Snapshots` entry in case it ran first).
