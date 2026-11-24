# r3 display trials, part 2: brightness (D5), VRR (D6), DPMS and idle (D7), night light (D8), and the promotion (D9)

Written 2026-11-15, after the first display window (`docs/r3-display-trials.md`, PR #127): T1 (D1 and D2) passed, T2 (D4,
the DCP hand-off) passed, and the window was closed (C5 passed). This is the runbook the lead pastes block by block for
D5 to D9. It uses the plan of `docs/r3-display-plan.md` (section 5, D5 to D9; 5.2 for the offline build), the first
runbook's blocks wherever they work unchanged, and its style: blocks, STOPs, expected output, an undo for each step, and ways
back.

**Authorisation.** The owner's intake of 2026-11-15 17:15 (recovery log) authorises D5 to D9 without asking again: one boot
per change, a proven way back, and "owner at the Mac for reboots" (that is the log's wording). The root's brief for this
window adds that the owner at the Mac is not required, because T3 resumes after the boot and the agent reboots itself
(section 3). That addition is not in the recorded intake, and the standing rule on unattended reboots says a trial that can hang
hard needs a person. So: **the wording is confirmed through Jarvis before boot 1 (the notice of section 3, N), and every boot
that can hang hard has a person on the deadline (N).** HDR is out of scope (#92). The speakers stay off. The lead records the gates (G) of this window
in `$D/gates.txt` before the first arm. Money is not involved. The one step that needs a person is the macOS copy of D9
(M9), which the owner's macOS agent does through Jarvis, as P4b did.

Evidence labels as in the plan: **source-read**, **seen on hardware (board)** (K114s, agent-run unless it says owner),
**owner-observed**, **emulator/replica**, **unknown**. Nothing in this runbook has run as root. Every write below is the
lead's, in the order given. **What the agent cannot see**: whether the panel follows a brightness write, whether DPMS-off is
black or dim, whether night light warms the picture, whether VRR flickers, and T2's colours, notch and sharpness. Those are
**owner-observed** items (section 2, F5). The agent-run checks prove the writes, the read-backs, the kernel log and the
compositor's state; they never claim the picture.

Hard limits for every step: nothing touches macOS, Apple's boot policy, Stage 1, Apple firmware or NVRAM; no security control
is weakened or bypassed (no key is imported into pacman's keyring, no guard marker such as `allow-low-esp` or
`allow-coupled-update` is used); the speakers stay off; suspend stays blocked; no block prints the kernel command line or
anything that unlocks the disk (blocks compare command lines, never show them; the records in `$D` are root-only); a trial
never writes the configured `m1n1/boot-ctxr.bin` or `default_entry` (only D9c does, once, with its own undo). A hang has one
recovery: hold the power button until the Mac is off (the loader's trial watchdog does not arm on this Mac). From W0 to the
close, `limine-snapper-sync` is held off with a plain `systemctl stop` in every boot (E12 of the first runbook; block F and
block C do it first). **Never write 0 to the backlight** (DPMS is D7); the only writes are the stepped ones of section 4, D5,
bounded by `apple,min-brightness` (10 nits).

## 1. The boots

| Boot | What runs | Tests | Falls back to, if it hangs |
| --- | --- | --- | --- |
| (none) session 0, a default boot of r3a on P | block P, D9p (stage the macOS tool and the fallback tree on the ESP), then M9 (the macOS excursion; its return boot is this session's boot), W0, W1, I1b (`linux-k114s-r3b 7.3.0.r3b.b1-1` beside r3a), S5 (the D5 Stage 2 onto the ESP), the gates record | I1b: G3 and G6 | nothing booted |
| **1. T3 = D5 + D7 + D8** | one-shot `Omarchy/linux-k114s-r3b` + `aura-try` `m1n1/boot-ctxr-disp-bl.bin` (pin loader `beceb683...` + brightness tree `5b6b83c8...`), VRR masked | the hand-off as T2, then D5 (the stepped writes), D7 (DPMS off and on three times, the OLED idle profile), D8 (night light), G6a (the no-`appledrm` drop-in) and G6b (no `appledrm` in a build from this boot) | before Limine: r3b.b1 on P (the one-shot is still pending: D5a, measured for free). After Limine: r3a on P |
| **2. T4 = D6** (and D9c at the end of its session) | the same one-shot + `aura-try`, the mask `fw27_panel_vrr=0` dropped for this boot | the boot checks again with `--vrr on` (the second clean brightness-tree boot), the D5 ladder again, `vrr_capable`, a Hyprland VRR test; then D9c writes the promotion | as boot 1 |
| **3. D9, first boot** | the new default: `Omarchy/linux-k114s-r3b` on the configured display Stage 2 (no trial, no one-shot) | block F, block C9 | none cheap: section 5 |
| **4. D9, second boot** | the same, nothing armed | block F, block C9, D9x (the close), D9y, P9, the first update | as boot 3 |

Four reboots in the window, plus the one macOS boot of M9 (its return boot is session 0's, so it adds none). Conditional
boots, only on a failure: **D5a alone** (the one-shot with P's Stage 2, `r3b.b1` on P: the same as the first runbook's D1
alone, section 6) and **a masked retry of T4** when T4's boot itself fails (section 2, F3).

## 2. Decisions, with the facts behind them

**F1. Four reboots, not eight.** The plan's table has one boot per stage (D5a, D5, D6, D7, D8, D9a, D9b: seven or eight).
D5, D7 and D8 are runtime only once the panel runs on the brightness tree, so they share boot 1. D6 needs a boot without the
mask (`fw27_panel_vrr` is read when the modes are parsed, `iomfb.c:2140`, so a runtime write of the module parameter does not
change `vrr_capable`), so it has boot 2. D9a and D9b share boot 3 (F11). Boot 4 is the second clean boot of the promoted
configuration that the plan's D9b asks for (#25).

**F2. D5a is folded into D5.** D5a is "r3b.b1 alone, on P's Stage 2". On P's tree there is no display subsystem, so
`appledrm` never binds, and the only module that differs from r3b's is `appledrm.ko` (`gates/compare-with-d0-r3b.out` in
`release-display-d5`: 2,035 files, 46 dtbs, and of 1,972 modules only `appledrm.ko` differs). Everything else of D5a is T1 (r3b
on P), already proven. So D5a would test a kernel whose only change is unused. The case D5a exists for survives anyway: if boot
1 hangs before Limine, the one-shot is still pending and the next boot is r3b.b1 on P, which is D5a measured for free. If it
hangs after Limine, the next boot is r3a, and the conditional D5a-alone boot separates the kernel from the tree (section 6).

**F3. D6 has its own boot, and the mask is dropped only for that boot.** The first runbook's I0 wrote
`/etc/modprobe.d/aurora-m5-vrr.conf` (`options appledrm fw27_panel_vrr=0`, replacing the J714s file of the same name that sets
1). With `=1` the mode parser gives the 120 Hz mode a VRR range (`zero_vrr_range_fallback`) and `vrr_capable` becomes 1. At
boot nothing else changes: the panel's modeset takes VRR only when userspace sets `VRR_ENABLED` (`iomfb_template.c:4100`,
source-read), and Hyprland's `misc:vrr` is not set (`monitors.lua:37` is a comment). A boot that fails with the mask dropped
could still be the mask or the brightness build, so the mask stays for boot 1 (D5's first boot on the brightness tree) and is
dropped for boot 2. T4a keeps a copy of the mask file in `$D`. D9c keeps the mask removed if D6 passed (the J714s default `=1`
then applies; Hyprland still does not use VRR unless configured), and puts it back if D6 failed or was skipped.

**F4. D7 and D8 ride boot 1, after D5.** They are runtime. A DCP crash in either ends brightness control until a reboot, but D5
has recorded its result by then. D8 runs last (CTM on a T6050 OLED has no public result). A stage that crashes the DCP is
recorded `-failed`, the rest of that boot is stopped, and the next boot skips it.

**F5. Agent-run proves the writes; the owner's eyes are separate and do not block the promotion, except D7's wake-up.** The
agent cannot judge a picture. Each stage writes an `owner-look` line to `$D/owner-look.txt` as **pending**:
T2's colours, notch and sharpness; D5 "the panel follows 25 %, 10 % and 100 %" and the physical brightness keys; D6 flicker;
D7 "black or dim"; D8 "warmer". The lead replaces a pending line when the owner reports. A pending look never stops a block.
What does stop D9a: `D5-passed` (the writes work), `D7-passed` (DPMS-off and the wake-up are agent-checked; the lock screen
blanks the display five seconds after locking, `plugins/lock/Service.qml:764`, so a DCP that does not wake would meet the
owner every time the screen locks), both boots, and `M9-passed`.

**F6. `k114s-backlight-check --auto`.** The existing check asks the owner "brighter or darker" after each write and puts the
last confirmed level back when no answer comes. An agent cannot answer. `--auto` asks nothing: from the level the device
reported it steps down (25 %, 10 %, 5 %, 2 %, 1 % of the maximum, never below `apple,min-brightness`, never 0, never above
the start) and back up, reads `brightness` and `actual_brightness` after every write, and stops at the first write that fails
or reads back another value, putting the start level back (`tests/brightness/test-backlight-check.sh`, cases 13). It does not
go to the 1000-nit maximum: that is the owner's `Shift + brightness-up`. The level D5 leaves is the one it started at
(500 nits at T2). **The floor is proven by the kernel log line and the device-tree property, not by writing below it.**

**F7. The OLED idle profile (D7).** Omarchy's lock blanks the display (`omarchy-brightness-display off`) five seconds after it
locks, and the screensaver runs before that. The profile is two numbers in `~/.config/omarchy/shell.json`: `idle.screensaver`
60 and `idle.lock` 120 (today 150 and 300), so a static desktop is at most two minutes lit. It hot-reloads. Reversible, so it
is taken as the default (the lead tells Jarvis's inbox which values); the idle timing itself needs the owner (the lock cannot be
unlocked by an agent), so the check is: the file, the reload, and the DPMS cycles of D7. **The profile only acts while the idle
guard of F15 is off**: an unattended window keeps the session awake, and D9x puts the mode back as `idle-before` recorded. On this Mac
that is **on** (the owner's own stay-awake setting since 2026-11-14), so the profile does not act after D9x unless the owner runs
`omarchy-toggle-idle` (section 8).

**F8. What fits on the ESP after D9: r3b.b1 (default) and r3a. The `linux-aurora` image stays off.** The ESP is 523,132,928
bytes. The images are 79,253,504 (`linux-aurora`), 79,420,416 (r3a) and about 79,485,000 (r3b.b1: r3a's size plus 64 KiB, as the
first window measured). All three do not fit with the space guard's 88,080,384 bytes and one image's worth of room for a
rebuild (`docs/esp-space.md` section 3.1): used would be 491.6 MB, 31.5 MB free. With r3b.b1 and r3a: about 110.8 MB free, the
same figure as the first window's open state (E6 there). Why r3a rather than `linux-aurora`: it is the K114s kernel, the one
every P boot has run since 15:41, and the one `default k114s` from macOS and the manual edit already name; `linux-aurora` is
the stock kernel (the repair-image base) and keeps its copy (`$D/omarchy_linux-aurora.efi`, `72f5d32c...`, byte for byte, plus
the first window's `$DO` copy) and its package, held. The two ESP images are still hook-built from one initramfs state, as
P6 said; the static fallback is M9's `stage2 r3-gpu` plus the repair image (`restore-repair`). Budget through the runbook (all
agent-run reads for the starting point; the rest derived from the first window's measurements and these file sizes):

| State | ESP free (bytes) |
| --- | ---: |
| today, window closed (aurora + r3a) | 111,022,080 |
| after D9p (the tree and the tool, about 0.2 MB) | about 110.8 million |
| after W1 (aurora's image off) | about 190.0 million |
| after I1b (r3b.b1's image) | about 110.5 million |
| after S5 (the D5 Stage 2, 4.5 MB) | about 106.0 million |
| after D9c (the Stage 2 trial copy removed, the configured file 66 KB larger) | about 110.4 million |

The guard's minimum is 88,080,384. **A full image rebuild is a trap in this layout**: three kernel packages are installed
(`linux-aurora`, `linux-k114s`, `linux-k114s-r3b`) and two images exist, so a transaction that triggers
`limine-mkinitcpio-install`'s rebuild-all (systemd, mkinitcpio, firmware or cryptsetup, `limine-mkinitcpio-install:100`) would
build the `linux-aurora` image as well: 31.5 MB free, below the 79.4 MB the next image's rebuild needs beside the old one. The
guard cannot see this (it checks the free space before the transaction, 110 MB). Whether the failure leaves the old images and
a stray temporary file, or a short image, is unknown (the tool builds into a temporary file first, then `limine-entry-tool
--add-uki` copies it; its failure mode was not read). So the runbook **prevents** it rather than detects it: U0 lists the pending upgrades before `omarchy update`
(`checkupdates`, which syncs a throw-away copy of the databases and changes nothing) and stops when any of them would hit a
trigger of an active hook that runs `mkinitcpio` or `limine-mkinitcpio-install` (U0 reads the trigger lines of the hooks themselves:
`/etc/pacman.d/hooks` first, then `/usr/share/libalpm/hooks`, a same-named `/etc` hook overriding the `/usr` one; a package that is a
Package target, or that ships a file matching a Path target, stops it). Those updates wait: no
pacman hold is added for them, and `omarchy update` is not run until the pre-transaction hook of section 7 exists, or the owner
decides otherwise. A pending Omarchy package that ships migrations (`usr/share/omarchy/migrations/`: `omarchy-dev` does; `omarchy-settings-dev` ships none today,
but every `omarchy*` package is downloaded and read, because that is cheaper than knowing which one starts to) is the
second path: a migration that runs `limine-mkinitcpio` with no arguments rebuilds every image, outside pacman, so no hook sees it. **Two more paths U0 does not see**: `omarchy update`
also runs `omarchy-update-orphan-pkgs -y` (which runs `omarchy-pkg-drop` on every new orphan: a new `omarchy-settings-dev` that drops a dependency
whose files match a trigger, such as `plymouth`'s `usr/lib/initcpio/install/*`, would rebuild every image in a Remove transaction) and
`omarchy-update-aur-pkgs` (`yay -Sua`). Nothing is exposed today (no orphans; the foreign packages are held or not in the AUR), and they are
not read ahead: U1 and P9 are the net for them. If a later package starts dropping dependencies, read its `.PKGINFO` before the update.
Migrations reach a rebuild through helpers too (`omarchy-hibernation-setup` and `omarchy-keyboard-toprow` run
`limine-mkinitcpio`), and through `omarchy-pkg-add`, `omarchy-pkg-drop` or `pacman -S`/`-R` (a transaction whose packages
`checkupdates` never lists), so no text pattern is enough. U0 therefore downloads such a package into a throw-away cache (a
throw-away database and cache folder; the real ones are never written) and stops on **every** migration that would run at the
update, new in the package or installed with no marker in `omarchy-migrate`'s state folder, until the lead has read it (with the
helpers it calls and the packages it adds or drops) and recorded in `$D` that it cannot rebuild every image on this Mac. The detection stays behind that as a net (U1, P9): a third image stops everything before the reboot, and the fix
rebuilds and re-verifies r3a's image as well as removing the extra one (U1). **This remains the largest risk of the promoted
layout** (section 8); the hook itself (a PreTransaction hook that refuses a rebuild-all while kernel module directories outnumber the
images) is not part of this change; it would catch a migration's pacman transaction but not a migration that calls
`limine-mkinitcpio` directly or through a helper (that runs outside pacman).

**F9. The Stage 2 hook is made to write the pin loader by a file, not by code.** `update-boot-ctxr-k114s` already reads the
loader it writes from `/usr/lib/asahi-boot/m1n1-ctxr.bin` when that file exists (`m1n1_out`), and checks the existing
`boot.bin` against the installed `m1n1.bin` only as the source of the U-Boot tail. D9c installs the pin loader
(`beceb683...`, 4,063,232 bytes) as `m1n1-ctxr.bin` and pins the brightness tree; D9a proves, in a throw-away root and before
anything is written, that the hook then writes `90b35137...` byte for byte (P1b's method). Without that file a later package
transaction that runs the hook (a `dtbs/` change, a removal of r3b) would write the installed loader plus the brightness tree,
which the installed loader refuses (T1: `refused`): the panel would fall back to simpledrm. D9c writes `boot-ctxr.bin` itself
from the kept file, not through the hook.

**F10. The macOS tool: loaders by prefix, a rollback that restores them, and one more rollback target.** The tool split every
Stage 2 at the manifest's `aura_prefix_bytes` (3,997,696, the installed loader), so a display Stage 2 (pin loader, 4,063,232)
read as `unknown` and `stage2` refused to replace it. Now `split_known` tries the installed loader (manifest) and the pin loader
(`PIN_LOADER`, a constant), so a Stage 2 on either is recognised; the D9 file is named by hash (`LOCAL_STAGE2`); and
`stage2 r3-gpu` writes the proven Stage 2 (`9825a103...`) and its tree (`2c870ba9...`) from the bundle's `promotion/` folder,
checked against hashes in the tool. The whole file is written, so the loader bytes are restored with it. `stage2 r1` also
works from the display state (it is whole-file too). The Mac's copy is M9's job. `restore-repair` is unchanged and, in the D9
layout, needs the r3b image removed by hand first (as in the first window's way back).

**F11. D9a and D9b are one write session and one boot.** The plan sequences the default kernel (D9a) before the Stage 2
(D9b), each with a boot. Boot 1 and boot 2 already ran the exact D9 configuration through `aura-try` (r3b.b1 entry, pin loader,
brightness tree, the same bytes), and r3b on P is T1. The remaining difference is that Limine starts the entry by default and
Stage 1 reads the configured file instead of `aura-try`. So D9c writes the pins, the loader file, `default_entry` and the Stage 2
in that order (a stop leaves a state T1 or the P files proved: r3b.b1 on P, or the installed loader on the display tree), and
the first reboot is boot 3. A second boot (boot 4) is the plan's "two boots". The cost of a boot 3 failure is the macOS way back
(section 5), which M9 has proven before D9c.

**F12. A sleeping owner does not block.** M9 is the one human step. It runs first in session 0, while nothing else depends on
it; if it is not done when D9a is reached, boots 1 and 2 and D9a still run, and D9c waits for `M9-passed` (the only wait that
is not an unanswered intake). The macOS agent's brief is section 4, M9.

**F13. The holds.** `linux-k114s-r3b` joins `holds.list` and `IgnorePkg` (P6c's way; `apply-holds`). `linux-k114s`,
`linux-aurora`, `m1n1-aurora`, `uboot-aurora`, `limine-mkinitcpio-hook` and `limine-snapper-sync` are held already and are
re-checked. `update-m1n1` stays off while any K114s kernel is installed. `/etc/omarchy-mac-boot/owner-boot-chain` is rewritten
to name the new default. `restore-enabled` for `systemd-backlight` stays absent: whether to keep the level across boots is the
owner's call after D5's look (`docs/r3-brightness.md`, "The first write"), and each boot starts at the level the firmware gives
(500 nits at T2); the first runbook's drop-in stays.

**F14. Self-reboot.** Every arm block ends with `sudo systemd-run --on-active=15s --unit=NAME systemctl reboot`, which returns
at once, then the lead schedules a T3 one-shot wake-up about four minutes later; the wake-up's first command is block F (a trial
boot) or block C9 (a D9 boot). No variable survives the boot: section 3 is pasted again. **Before each of boots 1 to 3 the notice N
of section 3 goes to Jarvis's inbox**, because a hung Mac hosts T3 itself and nothing on it can report its own hang.

**F15. The session stays awake for the whole window.** In an unattended window nothing touches the keyboard, so Omarchy's idle
timers run from login (today screensaver 150 s, lock 300 s): by the time block F, T3b and D5 have run, about four minutes after
the wake-up, the screen can be locked and DPMS-off (the lock blanks the display five seconds after it locks, `plugins/lock/Service.qml:764`),
and an agent cannot unlock it. D7 would then stop on 'not lit', and D6's VRR run behind a lock would record a result about a
dark panel, on which D9c removes the VRR mask. So T3a turns on Omarchy's stay-awake mode (`omarchy-toggle-idle stay-awake`: a state
file in the home directory, so it holds from the login of every boot), after recording what it was (`$D/idle-before`). D5, D7, D8 and D6
begin with `omarchy-shell lock isLocked` = `false`. D9x puts the mode back as it was; the abandon path does the same. **On this Mac
the mode has been on since 2026-11-14 (the owner's own setting, not this window's: `omarchy-toggle-idle --status` reads `enabled`
true), so T3a records `idle-before` = true and D9x leaves it on**; whether to allow idle afterwards is the owner's call (section 8).
The idle timing itself stays owner-observed (D7b).

**F16. G6 is checked on every image, every time.** The plan wants no `appledrm` in the initramfs after every UKI rebuild. I1b held it
only because it ran from P, a boot with no display subsystem. After D9 every boot is on the display tree, and mkinitcpio's
`autodetect` and `kms` hooks read the device modaliases of the running system, so a rebuild (during an update, or from a repaired
r3a image) can put `appledrm` into an image that is then started unchecked, with the display driver probing before the root filesystem
is mounted. So: **G6b** (boot 1, after D8) builds a throw-away initramfs from the display-tree boot into a temporary folder and
lists it; D9a needs `G6b-passed`; and block P9 dumps and lists the `.initrd` of every image on the ESP in every check (before and
after every update, in every default boot). A failed G6b blocks D9.

The remedy is a mkinitcpio drop-in, `linux/99-k114s-no-appledrm.conf`, installed as `/etc/mkinitcpio.conf.d/99-k114s-no-appledrm.conf` by
`linux/initramfs-no-appledrm-k114s` (block **G6a**; `--undo` removes it). The mechanism: mkinitcpio's `add_module` returns at once for a module
already counted in its `_addedmodules` table, so the drop-in counts `appledrm` and `dcp_fabric_core` (the display's fabric power-domain driver,
whose only user is `appledrm`) as added, and neither lands in an image, whichever hook asks for it (`kms` adds everything under
`drivers/gpu/drm/`, `autodetect` lists every loaded module). It is one `/etc` file and no replaced hook: the hook arrays, `simpledrm` (built
in), the GPU, Plymouth, the vconsole and `sd-encrypt` paths are not touched, and a module a MODULES entry names (`apple_pmp` in
`92-omarchy-mac-pmp.conf`) is still added. What it does take out with the pair is what only they pulled in as dependencies. A throw-away
`mkinitcpio -k 7.3.0-17.v272-11-k114s-r3b-ARCH -g` with copies of the real `/etc/mkinitcpio.conf` and every drop-in, with and without the
file, went from 93 to 84 modules: `appledrm`, `dcp-fabric-core`, `drm_dma_helper`, `mux-apple-display-crossbar`, `snd`, `snd-pcm`,
`snd-pcm-dmaengine`, `snd-timer` and `soundcore` (`modules.dep` shows only `appledrm` uses them on all three installed kernels); `atc-t6050-dp`,
`typec` and `apple-pmp` (a MODULES entry) stay. (A `kms`-only build without autodetect, the first measurement, named only the crossbar and the DP alt-mode driver.) It is read only when mkinitcpio is run without
`-c` (the way `limine-mkinitcpio`, `mkinitcpio -P` and block G6b run it; `-c` switches `/etc/mkinitcpio.conf.d` off). G6b requires the file
to be installed and to be the repository's, so a pass proves a build with it; D9a and P9 check it is still there.

## 3. Rules and variables

- From W1 to the close the display window is open: no package transaction except I1b (and C2b on the abandon path), no
  `omarchy update`, no `limine-mkinitcpio`, `mkinitcpio` or `update-m1n1`. D9c is no package transaction. Close the window
  before any update (D9x).
- The snapshot sync is held off from W0 to D9x (E12 of the first runbook): no `snapper`, `omarchy-snapshot` or
  `limine-snapper-*` command, and no `systemctl start` of `snapper-cleanup.timer` or `limine-snapper-sync.service`.
- On macOS, never `rollback all`, `rollback stage2`, `kernel`, `apply` or `default original`; before D9 also not
  `default aurora` in the window (its image is off the ESP).
- No write to `/sys/class/backlight/*/brightness` except the stepped writes of D5 (the ladder, the Omarchy steps) and the level
  put back; never 0; no `brightnessctl set 0`; no Alt + brightness-down held. A DPMS test uses `omarchy-brightness-display
  off` and `on` only.
- Reboots and wake-ups: F14. **N, the notice to Jarvis's inbox before each of boots 1, 2 and 3** (the lead sends it first, and records Jarvis's
  acknowledgement with `echo 'N boot<n> acked <time> <Jarvis message>' | sudo tee "$D/N-acked-<n>"`; T3a (boot 1), T4a (boot 2) and
  D9c's printed reboot line (boot 3) refuse to schedule the reboot without that file, and boot 3's line must also say that the owner or
  the macOS agent is reachable). It stands alone, with the thread link and the ledger
  key: "Boot <n> of the K114s display window is armed for <time>. The Mac reports 'booted' (block T3b, T4b or C9 wrote its marker, and
  the lead posts it) by T+10 minutes. With no report by then, Chris must hold the Mac's power button until it is off, then start it
  (boot 1 and 2: that returns r3a or r3b on P and costs nothing; boot 3: the configured display Stage 2 may be the cause, and the way
  back is the macOS one of section 5, which needs him or the macOS agent). Please keep this deadline and tell Chris; nothing on the
  Mac can report its own hang." Boots 1 and 2 may run with nobody at the Mac once Jarvis has confirmed both the deadline and the
  owner's wording (Authorisation). **Boot 3 runs only while the owner or the macOS agent is reachable** (Jarvis says so in the
  acknowledgement); otherwise D9c waits (F12's wait, not an unanswered intake).
- The session stays awake (F15): T3a turns on the stay-awake mode; D9x turns it back as it was. Never run D7b's profile as a test of
  idle while the mode is on.
- Variables do not survive a reboot. Set them at the top of each session:

      REPO=<a checkout of this repository that has this file>
      K=/usr/local/lib/omarchy-k114s/k114s-boot-once
      D=/var/lib/k114s-recovery/display-d5          # this window's records (root-only); the first window's folder is read only
      DO=/var/lib/k114s-recovery/display            # the first window's records: T2's loader log is compared with
      R5=${K114S_BUILD_ROOT:-$HOME/k114s-build}/integrate/release-display-d5
      RT=${K114S_BUILD_ROOT:-$HOME/k114s-build}/integrate/release-display-trials

- **Blocks of `docs/r3-display-trials.md` used here unchanged**, always with this window's `D`: block P (the window states),
  W0, W1, block X, block Xs, block F, block C, C4 and C5. They are parameterised by `D`, never by a file name of the first
  window. Block P stops after D9c (its configured-Stage-2 line is P's file): from D9c on use block P9.
- Every block with a `findmnt` guard is a subshell `( ... )`. A `STOP` ends it with `exit 1`, the rest does not run, and the
  terminal stays open. Paste each block whole. Stop at the first expectation that is not met.
- The blocks that say "as the user, in the desktop" need the Hyprland session's environment. The lead's agent has it; without it
  `export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/$(id -u)/hypr | head -1)` first. `brightnessctl` writes through logind:
  if the first write of D5 reports `WRITE FAILED`, run D5 from a terminal in the desktop session.
- Record each step's result in the lead's recovery log before the next step.
- What `$R5` holds (agent-built, `SHA256SUMS` beside it; the Stage 2 file was rebuilt on the pin loader and listed 2026-11-15
  19:23):

  | File | sha256 | What |
  | --- | --- | --- |
  | `pkg/linux-k114s-r3b-7.3.0.r3b.b1-1-aarch64.pkg.tar.zst` | `0ca7b7593340981702ba306ffb93168cb67615e5a62a162270f9117aff3491ba` | `linux-k114s-r3b 7.3.0.r3b.b1-1`: r3b plus brightness 0001-0003, 0005, 0006, release `7.3.0-17.v272-11-k114s-r3b-ARCH`, 47,536,324 bytes |
  | `dtb-p/t6050-k114s-r3b-brightness.dtb` | `5b6b83c8cd5e59333182f6ca37f22b1e99bd029daa1342d186daee096b292fda` | the D4 display tree `914ec379...` plus `apple,min-brightness = <10>` |
  | `stage2/boot-ctxr-disp-bl.bin` | `90b351377d6fcbad00ddc4c2fb74fce4313dd7fa5f4978ba895a7c41be523e30` | pin loader `beceb683...` + tree `5b6b83c8...` + trailer `9d8dc11e...`, 4,506,159 bytes, composed with `build/make-stage2.sh` from `$RT/aura-pin` (not rebuilt here) |

  and `$RT/aura-pin/m1n1.bin` (`beceb683b63a6d421ce58061a55c14a6d09e0381a23c1a543df55f4cc8007392`, 4,063,232 bytes), the loader
  D4 proved. Expected owner-observed gates in `$D/owner-look.txt` stay pending until the owner reports (F5).

## 4. The runbook

### Block P and the window

Block P (first runbook, `window closed`), then **D9p**, then **M9**, then W0 and W1 (the first runbook, with this `D`).

**D9p. Stage the macOS tool and the fallback tree on the ESP (from a default boot; writes only `k114s-repair/promotion/`).**
P's Stage 2 itself is not copied again: M9 reads `m1n1/boot-ctxr-r3-gpu.bin` (the standing P file, `9825a103...`, which stays on
the ESP).

    (
    : "${REPO:?STOP: set K, REPO, D, R5, RT and DO first (section 3)}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    h() { sudo sha256sum "$1" 2>/dev/null | cut -c1-64; }
    p=/boot/efi/k114s-repair/promotion; GPU=9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc; GPUT=2c870ba9f5963f5ae1ed18a7effa520daa234583997470d9552a795b4aafcda5
    [ ! -e /proc/device-tree/chosen/aurora,trial ] || stop "run D9p from a default boot on P; nothing was changed"
    [ "$(h /boot/efi/k114s-repair/k114s.dtb)" = $GPUT ] && [ "$(h /usr/local/lib/omarchy-k114s/k114s.dtb)" = $GPUT ] || stop "a pin is not P's tree (D9p runs before D9c); nothing was changed"
    [ "$(h /boot/efi/m1n1/boot-ctxr-r3-gpu.bin)" = $GPU ] && [ "$(h /boot/efi/m1n1/boot-ctxr.bin)" = $GPU ] || stop "P's Stage 2 is not on the ESP twice (m1n1/boot-ctxr.bin and m1n1/boot-ctxr-r3-gpu.bin); nothing was changed"
    sudo test -s $p/repair-block.conf && sudo test -s $p/k114s_repair.py || stop "$p is not as P0e left it; nothing was changed"
    python3 -I -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' "$REPO/macos/tools/k114s_repair.py" || stop "the repository's macOS tool does not parse; nothing was changed"
    new=$(sha256sum < "$REPO/macos/tools/k114s_repair.py" | cut -c1-64)
    sudo mkdir -p "$D" && sudo chmod 700 "$D" || stop "cannot make $D"
    # the tool the Mac has today stays beside the new one (P4b kept its own copy on the Mac)
    sudo test -e $p/k114s_repair.py.p4b || sudo cp -p $p/k114s_repair.py $p/k114s_repair.py.p4b || stop "the old tool was not kept"
    sudo cp "$REPO/macos/tools/k114s_repair.py" $p/k114s_repair.py.k114s-new && sudo cp /usr/local/lib/omarchy-k114s/k114s.dtb $p/k114s.dtb.gpu.k114s-new && sudo sync -f /boot/efi ||
      { sudo rm -f $p/*.k114s-new; stop "the files were not copied; only $p/*.k114s-new were written and are removed"; }
    [ "$(h $p/k114s_repair.py.k114s-new)" = $new ] && [ "$(h $p/k114s.dtb.gpu.k114s-new)" = $GPUT ] || { sudo rm -f $p/*.k114s-new; stop "a copy does not read back; $p/*.k114s-new removed"; }
    sudo mv -f $p/k114s_repair.py.k114s-new $p/k114s_repair.py && sudo mv -f $p/k114s.dtb.gpu.k114s-new $p/k114s.dtb.gpu && sudo sync -f /boot/efi
    [ "$(h $p/k114s_repair.py)" = $new ] && [ "$(h $p/k114s.dtb.gpu)" = $GPUT ] || stop "a file does not read back after the rename: sudo cp -p $p/k114s_repair.py.p4b $p/k114s_repair.py"
    sudo install -m600 "$REPO/macos/tools/k114s_repair.py" "$D/k114s_repair.py" && echo "$new" | sudo tee "$D/macos-tool.sha256" >/dev/null
    echo "D9p: $p holds k114s_repair.py (sha256 $new; the old one is k114s_repair.py.p4b) and k114s.dtb.gpu (2c870ba9...); ESP free $(df -B1 --output=avail /boot/efi | tail -1)"
    )

Expected: the last line, about 110.8 million free. Undo: `sudo cp -p /boot/efi/k114s-repair/promotion/k114s_repair.py.p4b
/boot/efi/k114s-repair/promotion/k114s_repair.py && sudo rm /boot/efi/k114s-repair/promotion/k114s.dtb.gpu`. Print the tool's
hash (the line above) into the macOS brief.

**M9. The owner's macOS agent, through Jarvis: install the changed tool, keep the Stage 2 fallback, and prove the rollback
(a hard prerequisite of D9c).** The brief for Jarvis's inbox (it stands alone; the thread link and ledger key go on top):

    Request for the owner's macOS agent (about 10 minutes, one macOS restart; the Mac boots Linux again afterwards).
    Why: the display promotion (docs/r3-display-d5-d9.md) will make a new Stage 2 the one this Mac boots. Before that, the
    Mac's repair tool must be able to put the proven Stage 2 back, and the files it needs must be on the Mac.
    Restart into macOS (Startup Options). In Terminal, in the repair bundle folder (the one P4b used), run:

      diskutil list                                        # the EFI partition of the internal disk
      sudo diskutil mount readOnly <the EFI volume>
      shasum -a 256 /Volumes/EFI/k114s-repair/promotion/k114s_repair.py          # must print <TOOL_SHA256: the line D9p printed>
      cp tools/k114s_repair.py tools/k114s_repair.py.p4b                          # keep the tool that worked
      cp /Volumes/EFI/k114s-repair/promotion/k114s_repair.py tools/k114s_repair.py
      sudo cp /Volumes/EFI/m1n1/boot-ctxr-r3-gpu.bin promotion/boot-ctxr-gpu.bin
      sudo cp /Volumes/EFI/k114s-repair/promotion/k114s.dtb.gpu promotion/k114s.dtb.gpu
      sudo chown "$(id -un)" promotion/*; chmod 600 promotion/*
      shasum -a 256 promotion/boot-ctxr-gpu.bin promotion/k114s.dtb.gpu
          # 9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc  and  2c870ba9f5963f5ae1ed18a7effa520daa234583997470d9552a795b4aafcda5
      diskutil unmount <the EFI volume>
      sudo ./k114s-repair status
      sudo ./k114s-repair restore-repair --check
      sudo ./k114s-repair stage2 r3-gpu
      sudo ./k114s-repair status

    Expected: both shasum lines match; status and --check as they were at P4b (Stage 2 "r3-gpu (GPU tree, not in this bundle)",
    default entry Omarchy/linux-k114s, "restore-repair check passed" or the space line of the day); "stage2 r3-gpu" prints
    "Stage 2 is now: r3-gpu" and the final status is unchanged (the Mac is on that Stage 2 already, so this write changes no
    byte; it proves the command, the checks and the write path on the real ESP). If any command prints STOPPED, or a hash
    differs: put tools/k114s_repair.py.p4b back, change nothing else, restart, and report the exact message.
    Then restart: the Mac starts Linux as usual. Report: the three shasum values, the status text after stage2, and
    "the tool is <TOOL_SHA256>".

Then, in Linux (the return boot is a default boot of r3a on P, before W0, so the first runbook's block C, which needs W0's
records, is not used): block P (`window closed`), `"$REPO/tests/hardware/k114s-r3a-check.sh" --allow-gpu | grep -E '^(ok|BAD)'`
(the hardware check block C runs; no `BAD`), then

    echo "M9 passed $(date -Is): the macOS agent ran tool <TOOL_SHA256> and stage2 r3-gpu on the real ESP (Jarvis: <message>)" | sudo tee "$D/M9-passed"

(`D9a` looks for the staged tool's sha256 in that line.) A `STOPPED` from the new tool: do not write `M9-passed`; read it, fix the
tool in the repository, run D9p again, and repeat M9.

W0 and W1 follow, with `D=/var/lib/k114s-recovery/display-d5`, from the first runbook unchanged. The gates record, then I1b.

**The gates record.** Before the first arm the lead writes, in their own words, two lines (the first window's records are in
`$DO/gates.txt`: G0 is the intake of 17:15 and the root brief of this window; G4 the same acceptance of the interrupt-only
mailbox, now with T1 and T2 passed):

    printf '%s\n' 'G0 confirmed: <who, when, where recorded>' 'G4 accepted: <the lead, the evidence>' | sudo tee /var/lib/k114s-recovery/display-d5/gates.txt

**I1b. Install `linux-k114s-r3b 7.3.0.r3b.b1-1`, then G3 and G6.** The same release string as r3b, so the entry, the image
name and the module directory are r3b's (the first runbook's C2 removed them; `/usr/lib/modules/$REL` does not exist now).

    (
    : "${K:?STOP: set K, REPO, D, R5, RT and DO first (section 3)}" "${REPO:?STOP: set REPO first}" "${D:?STOP: set D first}" "${R5:?STOP: set R5 first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    h() { sudo sha256sum "$1" 2>/dev/null | cut -c1-64; }
    c=/boot/efi/limine.conf; KU=/boot/efi/EFI/Linux/omarchy_linux-k114s.efi; BU=/boot/efi/EFI/Linux/omarchy_linux-k114s-r3b.efi
    pkg=$R5/pkg/linux-k114s-r3b-7.3.0.r3b.b1-1-aarch64.pkg.tar.zst; REL=7.3.0-17.v272-11-k114s-r3b-ARCH
    B1=0ca7b7593340981702ba306ffb93168cb67615e5a62a162270f9117aff3491ba; R3A=a15fa01ab7e20c9c1bf1b3f61c04f6ab765c4aa425188c22f70648a3871c52f4
    GPU=9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc; GPUT=2c870ba9f5963f5ae1ed18a7effa520daa234583997470d9552a795b4aafcda5
    [ "$(uname -r)" = 7.3.0-17.v272-4-k114s-r3a-ARCH ] && [ ! -e /proc/device-tree/chosen/aurora,trial ] || stop "run this from a default boot of r3a on P (G6: no display subsystem in this boot's tree); nothing was changed"
    sudo test -e "$D/window-open" && sudo cmp -s $c "$D/limine.conf.after-window" || stop "the window is not open as W1 left it; nothing was changed"
    [ "$(systemctl is-active snapper-cleanup.timer limine-snapper-sync.service snapper-cleanup.service | sort -u)" = inactive ] || stop "the snapshot sync runs (E12): block C's stop lines first; nothing was changed"
    pacman -Q linux-k114s-r3b >/dev/null 2>&1 && stop "linux-k114s-r3b is already installed; nothing was changed"
    [ "$(sha256sum < "$pkg" | cut -c1-64)" = $B1 ] || stop "the package is not 0ca7b759...; nothing was changed"
    for o in linux-aurora linux-k114s; do
      [ "$(K114S_CAND=r3b-b1 bash "$REPO/packaging/linux-k114s/check-package.sh" "$pkg" $o 2>&1 | tail -1)" = "check-package: all passed" ] || stop "check-package.sh against $o does not end 'check-package: all passed'; nothing was changed"
    done
    [ "$(pacman -U --print --print-format '%n %v' "$pkg")" = "linux-k114s-r3b 7.3.0.r3b.b1-1" ] || stop "the transaction would change more than linux-k114s-r3b; nothing was changed"
    grep -q -x 'export M1N1_UPDATE_DISABLED=1' /etc/default/update-m1n1 || stop "update-m1n1 is not off; nothing was changed"
    [ "$(df -B1 --output=avail /boot/efi | tail -1)" -ge 185000000 ] || stop "less than 185 MB free (G2); nothing was changed"
    [ "$(h $KU)" = $R3A ] || stop "the r3a image is not a15fa01a...; nothing was changed"
    [ -e /usr/lib/modules/$REL ] && echo "info  /usr/lib/modules/$REL exists (left by the first window's removal?): read it; the install goes on"
    kline=$(sudo grep -E '^[[:blank:]]*path: boot\(\):/EFI/Linux/omarchy_linux-k114s\.efi#' $c)
    sudo install -m600 "$pkg" "$D/" && sudo cp -p $c "$D/limine.conf.before-r3b" || stop "no copies in $D; nothing was changed"
    # the install: its output is kept root-only (the hooks' lines are counted, never searched for anything else)
    sudo pacman -U --noconfirm "$pkg" 2>&1 | sudo tee "$D/install-r3b.log" | grep -E '^(:: |\(|warning|error)|Building|Updating|update-boot-ctxr|Image generation'
    log() { sudo grep -c -F -- "$1" "$D/install-r3b.log"; }
    pacman -Q linux-k114s-r3b >/dev/null 2>&1 || stop "linux-k114s-r3b is not installed (pacman's message is above); nothing else to undo"
    # G3: one image built, and it is r3b's; the Stage 2 hook rewrote the configured file byte for byte
    [ "$(log 'Building UKI for')" = 1 ] && [ "$(log "Building UKI for linux-k114s-r3b ($REL)")" = 1 ] || stop "the hook did not build exactly one image, r3b's (a full rebuild?): do not reboot; run C2b then block X"
    [ "$(log 'update-boot-ctxr-k114s: wrote /boot/efi/m1n1/boot-ctxr.bin (4440237 bytes, K114s device tree 2c870ba9f5963f5a)')" = 1 ] || stop "the Stage 2 hook did not rewrite boot-ctxr.bin from the GPU tree: do not reboot; read $D/install-r3b.log"
    [ "$(h /boot/efi/m1n1/boot-ctxr.bin)" = $GPU ] || stop "boot-ctxr.bin is no longer 9825a103...: do not reboot (put back: m1n1/boot-ctxr-r3-gpu.bin is that file)"
    [ "$(h /boot/efi/k114s-repair/k114s.dtb)" = $GPUT ] && [ "$(h /usr/local/lib/omarchy-k114s/k114s.dtb)" = $GPUT ] || stop "a pinned tree changed: do not reboot"
    [ "$(h $KU)" = $R3A ] && sudo grep -q -x -F -- "$kline" $c || stop "the r3a image or its entry changed: do not reboot; run C2b then block X"
    [ "$(pacman -Qqo /usr/lib/modules/7.3.0-17.v272-4-k114s-r3a-ARCH)" = linux-k114s ] && [ "$(pacman -Qqo /usr/lib/modules/$REL)" = linux-k114s-r3b ] || stop "the module directories are not owned one by each package"
    [ "$(sudo grep -c -i '^default_entry:' $c)" = 1 ] && sudo grep -q -x 'default_entry: Omarchy/linux-k114s' $c || stop "default_entry changed: do not reboot; run C2b then block X"
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
    [ "$(grep -c appledrm "$t/list")" = 0 ] || stop "appledrm is in r3b's initramfs (G6): do not boot r3b; run C2b then block X"
    [ "$(sudo ls /boot/efi/EFI/Linux | LC_ALL=C sort | tr '\n' ' ')" = "omarchy_linux-k114s-r3b.efi omarchy_linux-k114s.efi " ] || stop "EFI/Linux is not exactly the r3a and r3b images"
    free=$(df -B1 --output=avail /boot/efi | tail -1); echo "ESP free: $free"; [ "$free" -ge 105000000 ] || stop "less than 105 MB free"
    sudo cp -p $c "$D/limine.conf.after-r3b" && sudo chmod 600 "$D/limine.conf.after-r3b" || stop "no copy of limine.conf as I1b left it (block Xs and D9c need it)"
    sudo $K entries
    echo "I1b: r3b.b1 installed beside r3a; G3 and G6 pass ($(grep -c '\.ko' "$t/list") modules in its initramfs, no appledrm)"
    )

Expected on screen: the first runbook's I1 text with `(1/1) installing linux-k114s-r3b`, one `Building UKI for linux-k114s-r3b
(7.3.0-17.v272-11-k114s-r3b-ARCH)`, the Stage 2 hook's `wrote /boot/efi/m1n1/boot-ctxr.bin (4440237 bytes, K114s device tree
2c870ba9f5963f5a)` (a byte-identical rewrite of P's file), the checks, `ESP free` about 110.5 million, `entries` with
`Omarchy.linux-k114s` and `Omarchy.linux-k114s-r3b`, and the last line (84 modules in the first window). Undo: C2b, then block X.

**S5. The D5 Stage 2, the brightness tree and the pin loader, onto the Linux disk; the Stage 2 onto the ESP.**

    (
    : "${D:?STOP: set K, REPO, D, R5, RT and DO first (section 3)}" "${R5:?STOP: set R5 first}" "${RT:?STOP: set RT first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    h() { sudo sha256sum "$1" 2>/dev/null | cut -c1-64; }
    B5=90b351377d6fcbad00ddc4c2fb74fce4313dd7fa5f4978ba895a7c41be523e30; BT=5b6b83c8cd5e59333182f6ca37f22b1e99bd029daa1342d186daee096b292fda
    PINL=beceb683b63a6d421ce58061a55c14a6d09e0381a23c1a543df55f4cc8007392; S2=m1n1/boot-ctxr-disp-bl.bin
    sudo test -e "$D/window-open" && pacman -Q linux-k114s-r3b >/dev/null 2>&1 || stop "W1 and I1b first; nothing was changed"
    [ "$(systemctl is-active snapper-cleanup.timer limine-snapper-sync.service snapper-cleanup.service | sort -u)" = inactive ] || stop "the snapshot sync runs (E12): block C's stop lines first; nothing was changed"
    # the three inputs of D9 on the Linux disk, read back (the build area is not needed again)
    for n in boot-ctxr-disp-bl.bin:$B5:"$R5/stage2/boot-ctxr-disp-bl.bin" k114s.dtb.bright:$BT:"$R5/dtb-p/t6050-k114s-r3b-brightness.dtb" m1n1-pin.bin:$PINL:"$RT/aura-pin/m1n1.bin"; do
      f=${n%%:*}; r=${n#*:}; want=${r%%:*}; src=${r#*:}
      sudo install -m600 "$src" "$D/$f" && [ "$(h "$D/$f")" = $want ] || stop "$f: the copy in $D is not ${want:0:8}..."
    done
    # the Stage 2 on the ESP (the trial file), written beside its name and read back
    sudo cp "$D/boot-ctxr-disp-bl.bin" /boot/efi/$S2.k114s-new && sudo sync -f /boot/efi && [ "$(h /boot/efi/$S2.k114s-new)" = $B5 ] ||
      { sudo rm -f /boot/efi/$S2.k114s-new; stop "$S2 was not written; nothing is armed"; }
    sudo mv -f /boot/efi/$S2.k114s-new /boot/efi/$S2 && sudo sync -f /boot/efi && [ "$(h /boot/efi/$S2)" = $B5 ] || stop "$S2 does not read back as 90b35137..."
    free=$(df -B1 --output=avail /boot/efi | tail -1); [ "$free" -ge 100000000 ] || stop "less than 100 MB free"
    echo "S5: $S2 on the ESP; the Stage 2, the brightness tree and the pin loader in $D; ESP free $free"
    )

Expected: the last line with about 106.0 million free. Undo: C1b.

### T3 = D5 + D7 + D8 (boot 1)

**T3a. Arm, from the default boot of session 0.** Run block P first (`window open, r3b installed`).

    (
    : "${K:?STOP: set K, REPO, D, R5, RT and DO first (section 3)}" "${REPO:?STOP: set REPO first}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    B5=90b351377d6fcbad00ddc4c2fb74fce4313dd7fa5f4978ba895a7c41be523e30; GPU=9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc
    S2=m1n1/boot-ctxr-disp-bl.bin; bd='/etc/systemd/system/systemd-backlight@backlight:apple-panel-bl.service.d'
    [ ! -e /proc/device-tree/chosen/aurora,trial ] || stop "arm T3 from a boot on P; nothing is armed"
    sudo test -s "$D/N-acked-1" || stop "the notice N for boot 1 is not acknowledged: the lead records it (echo 'N boot1 acked <time> <Jarvis message>' | sudo tee $D/N-acked-1); nothing is armed"
    sudo grep -q '^G0 confirmed' "$D/gates.txt" 2>/dev/null && sudo grep -q '^G4 accepted' "$D/gates.txt" || stop "$D/gates.txt has no 'G0 confirmed' or no 'G4 accepted' line (the gates record); nothing is armed"
    [ "$(systemctl is-active snapper-cleanup.timer limine-snapper-sync.service snapper-cleanup.service | sort -u)" = inactive ] || stop "the snapshot sync runs (E12): block C's stop lines first; nothing is armed"
    [ "$(pacman -Q linux-k114s-r3b)" = "linux-k114s-r3b 7.3.0.r3b.b1-1" ] || stop "r3b.b1 is not installed (I1b); nothing is armed"
    [ "$(sudo sha256sum /boot/efi/m1n1/boot-ctxr.bin | cut -c1-64)" = $GPU ] || stop "the configured Stage 2 is not P's file; nothing is armed"
    [ "$(sudo sha256sum /boot/efi/$S2 | cut -c1-64)" = $B5 ] || stop "$S2 is not 90b35137... (S5); nothing is armed"
    # what the brightness boot needs, left by the first window's I0: the mask (VRR stays off for this boot), the drop-in, the eDP rules
    grep -q -x 'options appledrm fw27_panel_vrr=0' /etc/modprobe.d/aurora-m5-vrr.conf || stop "no fw27_panel_vrr=0 file (the first window's I0, E8); nothing is armed"
    [ "$(modprobe -c | grep -c -E '^options appledrm fw27_panel_vrr=0')" = 1 ] || stop "modprobe does not read fw27_panel_vrr=0; nothing is armed"
    cmp -s "$REPO/linux/brightness/systemd/k114s-first-boot.conf" "$bd/k114s-first-boot.conf" || stop "the brightness drop-in is not installed (I0, E7); nothing is armed"
    sudo test -e /var/lib/k114s-backlight/restore-enabled && stop "brightness restore is turned on; nothing is armed"
    [ "$(grep -c -E '^hl\.monitor\(\{ output = "eDP-[12]", mode = "preferred", position = "auto", scale = 2(, cm = "srgb")? \}\)( --.*)?$' ~/.config/hypr/monitors.lua)" = 2 ] || stop "monitors.lua does not have the eDP-1 and eDP-2 rules (I0); nothing is armed"
    bash "$REPO/linux/display/k114s-dcp-colour" --check >/dev/null 2>&1 || stop "the DCP colour fix is not in monitors.lua (section 4a: bash $REPO/linux/display/k114s-dcp-colour); nothing is armed"
    [ "$(sudo sed -n 1p /boot/efi/aura-try)" = spent ] || stop "aura-try does not read spent; nothing is armed"
    # F15: the session stays awake through the window; what it was is kept once, for D9x
    sudo test -e "$D/idle-before" || omarchy-toggle-idle --status | jq -r .enabled | sudo tee "$D/idle-before" >/dev/null
    omarchy-toggle-idle stay-awake >/dev/null && [ "$(omarchy-toggle-idle --status | jq -r .enabled)" = true ] || stop "the stay-awake mode did not turn on (an unattended window would lock); nothing is armed"
    sudo $K arm Omarchy/linux-k114s-r3b || stop "the arm refused (its message is above); nothing is armed"
    # the Stage 2 trial last: if writing it fails, the pending request alone is r3b.b1 on P (D5a), a configuration T1 proved
    sudo sh -c "printf 'armed\n$S2\n' > /boot/efi/aura-try && sync -f /boot/efi" || {
      sudo sh -c "printf 'spent\n$S2\n' > /boot/efi/aura-try; sync -f /boot/efi"
      [ "$(sudo sed -n 1p /boot/efi/aura-try 2>/dev/null)" = spent ] || {
        echo "STOP: aura-try does not read spent, so it may still read armed. Do not reboot. Run: sudo cat /boot/efi/aura-try; if the first line is not spent: sudo sed -i 1s/armed/spent/ /boot/efi/aura-try && sudo sync -f /boot/efi, then read it again"; exit 1; }
      echo "STOP: aura-try was not written or not synced; it reads spent now. The one-shot is still pending: the next boot is r3b.b1 on P, or run sudo $K clear"; exit 1; }
    [ "$(sudo sed -n 1,2p /boot/efi/aura-try | tr '\n' ' ')" = "armed $S2 " ] || stop "aura-try does not read back as armed for $S2 (sudo cat /boot/efi/aura-try)"
    sudo $K status
    echo "T3 armed: r3b.b1 once, through $S2 once (the hand-off, the brightness tree, VRR masked). Rebooting"
    sudo systemd-run --on-active=15s --unit=k114s-d5-reboot systemctl reboot
    )

Before the reboot (section 10 of the plan): a dark Omarchy theme, nothing static on screen, the notice N sent and acknowledged. The
stay-awake mode (F15) is on from here to D9x. Then the T3 wake-up (F14), and N's deadline. Expected: `armed: the next boot starts 'Omarchy/linux-k114s-r3b' (id Omarchy.linux-k114s-r3b) once`,
`default_entry stays Omarchy/linux-k114s`, `status` with `aura-try: armed m1n1/boot-ctxr-disp-bl.bin`, then `Running timer
as unit: k114s-d5-reboot.timer`.

**T3b. The boot checks (in the T3 boot, after block F; its folder ends `-disp-bl`).**

    (
    : "${K:?STOP: set K, REPO, D, R5, RT and DO first (section 3): they do not survive the reboot}" "${REPO:?STOP: set REPO first}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    BLI=4a67b082-0a4c-41cf-b6c7-440b29bb8c4f; o=$(sudo cat "$D/last-boot"); REL=7.3.0-17.v272-11-k114s-r3b-ARCH
    [ "$(uname -r)" = $REL ] || stop "this boot is $(uname -r), not r3b"
    uname -v | grep -q 'K114S-R3B-B1' || stop "this kernel is not the brightness build (uname -v: $(uname -v)): the pending one-shot started r3b.b1 only if the package is b1"
    [ "$(tail -c +5 /sys/firmware/efi/efivars/LoaderEntrySelected-$BLI | iconv -f UTF-16LE -t UTF-8 | tr -d '\0')" = Omarchy.linux-k114s-r3b ] || stop "Limine did not start Omarchy.linux-k114s-r3b"
    [ -e /sys/firmware/efi/efivars/LoaderEntryOneShot-$BLI ] && stop "a one-shot request is still pending"
    [ "$(tr -d '\0' < /proc/device-tree/chosen/aurora,trial 2>/dev/null)" = m1n1/boot-ctxr-disp-bl.bin ] || stop "this boot did not come through m1n1/boot-ctxr-disp-bl.bin (no trial: the Stage 2 hung once and this is r3b.b1 on P, D5a: run the first runbook's T1b-D1, section 6)"
    [ "$(sudo sed -n 1p /boot/efi/aura-try)" = spent ] || stop "aura-try does not read spent"
    sudo cmp -s "$o/boot_id" /proc/sys/kernel/random/boot_id || stop "block F has not run in this boot (last logs: $o)"
    case $o in "$D"/boot-*-disp-bl) ;; *) stop "this boot's logs ($o) are not named for disp-bl" ;; esac
    t=$(mktemp) || exit 1; trap 'rm -f "$t" "$t.a" "$t.b"' EXIT
    sudo "$REPO/tests/hardware/k114s-display-check.sh" --expect published --floor --loader-log "$o/loader.log" --wait 10 | tee "$t"
    grep -q '^BAD' "$t" && stop "the display check printed BAD (above): power off after reading it, section 6"
    # the pin loader set the GPU up as in the first window's T2 (timestamps dropped); $DO is root-only
    t2=$(sudo sh -c 'ls -d "$1"/boot-*-disp-pinldr 2>/dev/null | tail -1' _ "${DO:-/var/lib/k114s-recovery/display}")
    if [ -n "$t2" ]; then
      sudo sh -c 'grep -F "FDT: GPU:" "$1/loader.log" | sed "s/^\[[^]]*\] //" | sort -u' _ "$t2" > "$t.a"; sudo sh -c 'grep -F "FDT: GPU:" "$1/loader.log" | sed "s/^\[[^]]*\] //" | sort -u' _ "$o" > "$t.b"
      [ -s "$t.a" ] && cmp -s "$t.a" "$t.b" && echo "ok    the loader's GPU lines equal the first window's T2 ($(grep -c '' "$t.a"))" || echo "info  the loader's GPU lines differ from the first window's T2, or it logged none: sudo diff them (they carry no command line)"
    else echo "info  no first-window T2 loader log to compare with"; fi
    sudo dmesg | grep -E 'GPU firmware build: 26B8125' | grep -v -i 'command line' | head -1
    "$REPO/tests/hardware/k114s-r3a-check.sh" --allow-gpu 2>/dev/null | grep -E '^BAD' && stop "the hardware check printed BAD (above)"
    echo "T3 booted $(date -Is) $(uname -v | cut -c1-40)" | sudo tee "$D/T3-booted" >/dev/null
    echo "T3b: the hand-off is published on the brightness build and tree; the floor line is in the kernel log. Now D5 (the stepped writes), D7, D8"
    )

Expected: as the first runbook's T2b, plus `ok    kernel: brightness requests below 10 nits are raised to 10 nits (the floor, patch 0006)`
and `ok    soc/dcp@48ae00000/panel apple,min-brightness 10`; `apple-panel-bl` `max_brightness 1000`; `fw27_panel_vrr = N`;
`systemd-backlight ... was skipped`; no crash; `ok    the loader's GPU lines equal the first window's T2`. The kernel admits `26B8125`
after one `not admitted: EINVAL` line (E2 of the first runbook). A `BAD` is a stop: read it, power off, section 6. **On a
`BAD` about `unqualified IOMFB callback 590`**: brightness 0003 is the first patch to drop (it makes D590 a handled callback
whose firmware-27 size check can mark the DCP crashed, `docs/r3-display-plan.md` 5.2); rebuild the package without it before
anything else.

**D5. Brightness (as the user, in the desktop; about two minutes). Agent-run: the writes, the read-backs and the Omarchy scripts.**
No write below the floor and no 0. It ends with the level it started at.

    (
    : "${REPO:?STOP: set K, REPO, D, R5, RT and DO first (section 3)}" "${D:?STOP: set D first}"
    stop() { echo "STOP: $*"; exit 1; }
    bl=/sys/class/backlight/apple-panel-bl; t=$(mktemp) || exit 1; trap 'rm -f "$t"' EXIT
    sudo test -s "$D/T3-booted" || stop "T3b has not passed in this boot ($D/T3-booted)"
    uname -v | grep -q 'K114S-R3B-B1' || stop "this kernel is not the brightness build"
    [ -d $bl ] || stop "no $bl: the hand-off is not published in this boot"
    [ "$(omarchy-hw-display)" = apple-panel-bl ] || stop "omarchy-hw-display does not pick apple-panel-bl (the keys and the slider would not reach it)"
    [ "$(omarchy-shell lock isLocked)" = false ] || stop "the session is locked (F15: an agent cannot unlock it); nothing was changed"
    start=$(cat $bl/brightness); max=$(cat $bl/max_brightness)
    [ "$max" = 1000 ] && [ "$start" -ge 10 ] && [ "$start" -le "$max" ] || stop "max_brightness $max, brightness $start: not the expected scale"
    # 1. what the kernel registered: reads only
    "$REPO/linux/brightness/k114s-backlight-check" --read-only | tee "$t"
    grep -q '^kernel applies it   yes' "$t" || stop "the kernel does not apply the 10-nit floor: no write (docs/r3-brightness.md)"
    grep -q '^device-tree floor   10 ' "$t" && grep -q '^display drivers .*apple-drm' "$t" || stop "the floor is not 10 or the panel is not on apple-drm"
    # 2. the stepped ladder (no questions): down to the floor and back, brightness and actual_brightness read back after every write
    # the checker's own status, not tee's (this block has no pipefail): a stopped ladder exits 1 after putting the start level back
    "$REPO/linux/brightness/k114s-backlight-check" --auto > "$t"; r=$?; cat "$t"
    [ $r = 0 ] && grep -q '^agent ladder done' "$t" || stop "the stepped check stopped (above; exit $r); it put the start level back. No D5-passed"
    [ "$(cat $bl/brightness)" = "$start" ] || stop "the level is $(cat $bl/brightness), not the start level $start"
    # 3. the script the brightness keys fall back to: two 5 % steps down and two up (omarchy-brightness-display, through brightnessctl).
    #    On the eDP the keys themselves are the shell's (services/BrightnessKeys.qml, one brightnessctl write); this proves the script path
    a=$(cat $bl/brightness)
    omarchy-brightness-display --no-osd 5%-; sleep 1; b=$(cat $bl/brightness)
    omarchy-brightness-display --no-osd 5%-; sleep 1; c=$(cat $bl/brightness)
    omarchy-brightness-display --no-osd +5%; sleep 1; d=$(cat $bl/brightness)
    omarchy-brightness-display --no-osd +5%; sleep 1; e=$(cat $bl/brightness)
    echo "the Omarchy steps: $a $b $c $d $e nits (down, down, up, up)"
    brightnessctl -q -d apple-panel-bl set "$start"; sleep 1
    [ "$b" -lt "$a" ] && [ "$c" -lt "$b" ] && [ "$c" -ge 10 ] && [ "$d" -gt "$c" ] && [ "$e" -gt "$d" ] || stop "the Omarchy steps did not go down, down, up, up (above); the start level was put back"
    # 4. the level is the start level again, and nothing in the kernel log says the DCP objected
    [ "$(cat $bl/brightness)" = "$start" ] && [ "$(cat $bl/actual_brightness)" = "$start" ] || stop "the level is not back at $start: brightnessctl -d apple-panel-bl set $start"
    sudo "$REPO/tests/hardware/k114s-display-check.sh" --expect published --floor --wait 3 | tee "$t" | grep -E '^(BAD|display-check)'
    grep -q '^BAD' "$t" && stop "the display check printed BAD after the writes (above)"
    echo "D5 agent-run passed $(date -Is): start $start nits, ladder and Omarchy steps read back, level restored" | sudo tee "$D/D5-passed" >/dev/null
    echo "owner-look D5 PENDING: the panel follows 25/10/5/2/1 % (darker each time) and the brightness keys; 10 nits readable; then Shift+up for 100 % briefly" | sudo tee -a "$D/owner-look.txt" >/dev/null
    echo "D5: the writes work and read back; whether the panel follows is the owner's to see"
    )

The Omarchy steps are the script the keys fall back to, not the key path: on the eDP the keys are handled in the shell, one
`brightnessctl` write each, and `Alt` + brightness-down passes `1%-`, which could ask for 0; that case is held only by patch 0006's
floor (the kernel raises a request below `apple,min-brightness`), which C9's `--floor` checks in every boot (section 8).

Expected: the read-only report (`device-tree floor 10`, `kernel applies it   yes: ...`, `display drivers ... apple-drm`), then
the ladder lines `level N nits (agent ladder): brightness N, actual_brightness N, agent: not asked` for 500 250 100 50 20 10
20 50 100 250, then `agent ladder done: ...; left at 500 nits`, the Omarchy steps line (for example `500 450 400 450 500`), the
display check's summary `0 BAD`, and the last line. A `WRITE FAILED` or `agent ladder stopped` is a stop: the block put the
start level back (the block's own status check; it stops there and writes no `D5-passed`); read the kernel log (`sudo dmesg | grep -i -E 'dcp|brightness'`), and if the DCP crashed (`DCP has crashed`)
the panel level cannot change until a reboot: record `D5 FAILED`, reboot, section 6. Undo: `brightnessctl -d apple-panel-bl set
<start>`. The owner's look (F5) stays pending in `$D/owner-look.txt`.

**D7. DPMS off and on (as the user, in the desktop; about 40 seconds). Agent-run: three cycles, the wake-up, the level kept, no crash.**
Black or dim is the owner's (pending line).

    (
    : "${D:?STOP: set K, REPO, D, R5, RT and DO first (section 3)}"
    stop() { echo "STOP: $*"; exit 1; }
    bl=/sys/class/backlight/apple-panel-bl
    sudo test -s "$D/D5-passed" || stop "D5 first (a DPMS test needs the level control proven)"
    [ "$(omarchy-shell lock isLocked)" = false ] || stop "the session is locked (F15: the stay-awake mode did not hold; an agent cannot unlock it): the owner unlocks, then run D7 again; nothing was changed"
    mon() { hyprctl monitors -j | jq -r '.[] | select(.name | test("^eDP-")) | .dpmsStatus'; }
    before=$(cat $bl/brightness)
    [ "$(mon)" = true ] || stop "the panel is not lit before the test (dpmsStatus '$(mon)')"
    for i in 1 2 3; do
      omarchy-brightness-display off; sleep 5
      [ "$(mon)" = false ] || { omarchy-brightness-display on; stop "cycle $i: dpmsStatus is '$(mon)' after off"; }
      echo "cycle $i off: brightness $(cat $bl/brightness), actual_brightness $(cat $bl/actual_brightness)  (the owner's look: black or dim?)"
      omarchy-brightness-display on; sleep 5
      [ "$(mon)" = true ] || stop "cycle $i: the panel did not wake (dpmsStatus '$(mon)'): a key or the pointer, then omarchy-brightness-display on; power-cycle if it stays dark"
      [ "$(cat $bl/brightness)" = "$before" ] || stop "cycle $i: the level is $(cat $bl/brightness) after waking, not $before"
    done
    sudo dmesg | grep -v -i 'command line' | grep -E 'DCP has crashed|co-processor has crashed|present dropped|swap not completed|SError|Oops|BUG:' && stop "a DCP crash line after DPMS (above)"
    echo "D7 agent-run passed $(date -Is): three off/on cycles, level $before kept" | sudo tee "$D/D7-passed" >/dev/null
    echo "owner-look D7 PENDING: after omarchy-brightness-display off, is the panel BLACK or only dim? (burn-in: section 10 of the plan)" | sudo tee -a "$D/owner-look.txt" >/dev/null
    echo "D7: DPMS-off and the wake-up work three times; black or dim is the owner's to say"
    )

Expected: three `cycle N off: brightness B, actual_brightness A` lines (the figures are the evidence for the owner's question:
the firmware logged non-zero drive values around 0 nits on the K116s) and the last line. A panel that does not wake is the
stop; `$D/D7-passed` is then not written and D9a will not run. Undo: `omarchy-brightness-display on`.

**D7b. The OLED idle profile (as the user; writes `~/.config/omarchy/shell.json`, which the shell reloads by itself).**

    (
    : "${D:?STOP: set K, REPO, D, R5, RT and DO first (section 3)}"
    stop() { echo "STOP: $*"; exit 1; }
    f=$HOME/.config/omarchy/shell.json
    sudo test -s "$D/D7-passed" || stop "D7 first; nothing was changed"
    [ -s "$f" ] && jq -e . "$f" >/dev/null || stop "$f is missing or not JSON; nothing was changed"
    [ -e "$f.bak.d7" ] || cp -p "$f" "$f.bak.d7" || stop "no copy of $f; nothing was changed"
    tmp=$(mktemp "$f.XXXXXX") && jq '.idle.screensaver = 60 | .idle.lock = 120' "$f" > "$tmp" && jq -e '.idle.screensaver == 60 and .idle.lock == 120' "$tmp" >/dev/null && mv -f "$tmp" "$f" || { rm -f "$tmp"; stop "the profile was not written; $f is unchanged"; }
    echo "D7b: idle screensaver 60 s and lock 120 s (the lock blanks the display 5 s later; was $(jq -c '.idle' "$f.bak.d7")); undo: cp -p $f.bak.d7 $f"
    echo "owner-look D7b PENDING: once the stay-awake mode is off (it is the owner's own setting, on since 2026-11-14; the owner runs omarchy-toggle-idle to allow idle): leave the desktop untouched for two minutes: screensaver, then lock, then the panel goes dark; wake it by a key and unlock" | sudo tee -a "$D/owner-look.txt" >/dev/null
    )

Expected: the last line. The profile acts only while the stay-awake mode (F15) is off; D9x restores it as `idle-before` recorded, which is on for this Mac, so the owner decides (section 8). The idle timing itself is not agent-checked (the lock cannot be unlocked by an agent).

**D8. Night light (as the user, in the desktop; about 20 seconds). Agent-run: the toggle, hyprsunset's temperature, no crash.**
Whether the picture warms is the owner's (pending line).

    (
    : "${D:?STOP: set K, REPO, D, R5, RT and DO first (section 3)}"
    stop() { echo "STOP: $*"; exit 1; }
    sudo test -s "$D/D7-passed" || stop "D7 first (D8 runs last: a CTM write has no public result on a T6050 OLED)"
    [ "$(omarchy-shell lock isLocked)" = false ] || stop "the session is locked (F15); nothing was changed"
    ctms=$(sudo modetest -M apple -p 2>/dev/null | grep -c -E '[0-9] CTM:')
    echo "CTM listed on $ctms CRTC property list(s) of the appledrm device (0 means Hyprland falls back to its own colour matrix)"
    [ "$(omarchy-toggle-nightlight --status | jq -r .enabled)" = false ] || stop "night light is on already (omarchy-toggle-nightlight --status): turn it off first; nothing was changed"
    omarchy-toggle-nightlight; sleep 3
    [ "$(omarchy-toggle-nightlight --status | jq -r .enabled)" = true ] && [ "$(hyprctl hyprsunset temperature | grep -o -E '[0-9]+' | head -1)" = 4000 ] || { omarchy-toggle-nightlight; stop "night light did not reach 4000 K (hyprsunset's answer: $(hyprctl hyprsunset temperature)); toggled back"; }
    sudo dmesg | grep -v -i 'command line' | grep -E 'DCP has crashed|co-processor has crashed|present dropped|swap not completed|SError|Oops|BUG:' && stop "a DCP crash line with night light on (above); toggle it back and reboot"
    omarchy-toggle-nightlight; sleep 3
    [ "$(omarchy-toggle-nightlight --status | jq -r .enabled)" = false ] || stop "night light did not turn off again: omarchy-toggle-nightlight"
    sudo dmesg | grep -v -i 'command line' | grep -E 'DCP has crashed|co-processor has crashed|present dropped|swap not completed|SError|Oops|BUG:' && stop "a DCP crash line after night light went off (above)"
    echo "D8 agent-run passed $(date -Is): CTM listed on $ctms, 4000 K on, off again, no crash" | sudo tee "$D/D8-passed" >/dev/null
    echo "owner-look D8 PENDING: omarchy-toggle-nightlight visibly warms the picture and the colours come back when it is off" | sudo tee -a "$D/owner-look.txt" >/dev/null
    echo "D8: night light on and off, no DCP crash"
    )

Expected: `CTM listed on 1 ...` (or 0), `D8: ...`. A crash line: record `echo "D8 failed $(date -Is) <the line>" | sudo tee "$D/D8-failed"`,
reboot (boot 2 runs without D8). A `STOP` that is not a crash (hyprsunset not reaching 4000 K) is `D8-failed` too: night light
stays off and does not block D9. **After a `D8-failed` the promoted default must not offer the owner a night-light click that
crashes the DCP** (the bar indicator, the menu and `omarchy-toggle-nightlight` stay one click away): the lead writes
`echo "D8 FAILED: do not use night light on this Mac (a DCP crash or no 4000 K at D8, $(date +%F)); do not toggle it" | sudo tee "$D/owner-look-README"`,
puts the same line into the owner's look file and the post-D9 report to Jarvis, and lists it in section 8. Guarding the toggle itself
(an override of the Omarchy script) is a follow-up, not part of this change. Undo: `omarchy-toggle-nightlight`.

**G6a. Install the no-`appledrm` drop-in (as the user, with sudo; writes `/etc/mkinitcpio.conf.d/99-k114s-no-appledrm.conf` and nothing else).**
The prevention for F16 (the mechanism is described there). It builds nothing and touches no image, `/boot` or ESP; the next build is the first to
use it. Run it before G6b; it is safe in any boot.

    (
    : "${REPO:?STOP: set K, REPO, D, R5, RT and DO first (section 3)}"
    stop() { echo "STOP: $*"; exit 1; }
    sudo bash "$REPO/linux/initramfs-no-appledrm-k114s" || stop "the installer failed; nothing else was changed"
    cmp -s "$REPO/linux/99-k114s-no-appledrm.conf" /etc/mkinitcpio.conf.d/99-k114s-no-appledrm.conf || stop "the installed drop-in is not the repository's file"
    echo "G6a: /etc/mkinitcpio.conf.d/99-k114s-no-appledrm.conf is installed; every initramfs built from now on leaves appledrm out"
    )

Expected: the last line. Undo: `sudo bash "$REPO/linux/initramfs-no-appledrm-k114s" --undo` (D9a, P9 and G6b then stop until it is installed again).

**G6b. No `appledrm` in an initramfs built from a display-tree boot, with the G6a drop-in installed (as the user; writes only a temporary folder; about a minute).**
This is the check for F16: the build is what a rebuild in the promoted layout would do, and the drop-in is what must keep `appledrm` out of it.

    (
    : "${REPO:?STOP: set K, REPO, D, R5, RT and DO first (section 3)}" "${D:?STOP: set D first}"
    stop() { echo "STOP: $*"; exit 1; }
    cmp -s "$REPO/linux/99-k114s-no-appledrm.conf" /etc/mkinitcpio.conf.d/99-k114s-no-appledrm.conf || stop "the no-appledrm drop-in is not installed (or is not the repository's file): run G6a first (F16); nothing was changed"
    REL=7.3.0-17.v272-11-k114s-r3b-ARCH
    sudo test -s "$D/T3-booted" && [ "$(uname -r)" = $REL ] || stop "run G6b in the T3 boot, after T3b; nothing was changed"
    ls /sys/class/drm | grep -q -- '-eDP-' || stop "no eDP connector: this boot has no display subsystem, so a build here proves nothing about the promoted boots"
    # the folder is root-only (an initramfs may hold disk-unlock material): every write into it and read from it runs under sudo, and nothing from the image is printed
    t=$(sudo mktemp -d /var/tmp/k114s-g6b.XXXXXX) || exit 1; trap 'sudo rm -rf "$t"' EXIT
    sudo sh -c 'mkinitcpio -k "$1" -g "$2/test.img" > "$2/build.log" 2>&1' _ $REL "$t" || { sudo tail -5 "$t/build.log"; stop "mkinitcpio could not build a test image (the log lines are above); nothing on the ESP was touched"; }
    sudo sh -c 'lsinitcpio "$1/test.img" > "$1/list" 2>/dev/null' _ "$t"; [ "$(sudo grep -c '\.ko' "$t/list")" -ge 20 ] || stop "lsinitcpio lists no modules: cannot read the test image"
    if [ "$(sudo grep -c -E 'appledrm|dcp.fabric.core' "$t/list")" != 0 ]; then
      echo "G6b-failed $(date -Is): a display-tree build puts appledrm in the initramfs" | sudo tee "$D/G6b-failed" >/dev/null
      stop "appledrm is in an initramfs built from this boot even with the G6a drop-in (F16): D9 stays blocked until this block passes; the lead reads $t/build.log's hooks and the module names (sudo grep appledrm $t/list; never copy the image) before deciding"
    fi
    sudo rm -f "$D/G6b-failed"
    echo "G6b $(date -Is): $(sudo grep -c '\.ko' "$t/list") modules, no appledrm (with the G6a drop-in)" | sudo tee "$D/G6b-passed" >/dev/null
    echo "G6b: a build from a display-tree boot has no appledrm in its initramfs (the ESP and /boot were not touched)"
    )

Expected: the last line. It writes a temporary image of about 30 MB into `/var/tmp` and removes it; no hook runs (`-g` builds a
plain image, not a UKI, and does not call limine). A `STOP` about `appledrm` or about the drop-in is a blocker for D9, not for D5 to D8
(run G6a, then G6b again). Undo: nothing.

Record `T3 PASSED` (D5, D7, D8, G6a, G6b) in the recovery log with the start level. Then T4a.

### T4 = D6 (boot 2)

**T4a. Drop the mask and arm, from the T3 boot, after D5 and D7 passed.**

    (
    : "${K:?STOP: set K, REPO, D, R5, RT and DO first (section 3)}" "${REPO:?STOP: set REPO first}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    B5=90b351377d6fcbad00ddc4c2fb74fce4313dd7fa5f4978ba895a7c41be523e30; GPU=9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc
    S2=m1n1/boot-ctxr-disp-bl.bin; m=/etc/modprobe.d/aurora-m5-vrr.conf
    sudo test -s "$D/N-acked-2" || stop "the notice N for boot 2 is not acknowledged: the lead records it (echo 'N boot2 acked <time> <Jarvis message>' | sudo tee $D/N-acked-2); nothing is armed"
    [ "$(omarchy-toggle-idle --status | jq -r .enabled)" = true ] || stop "the stay-awake mode (F15) is off: omarchy-toggle-idle stay-awake; nothing is armed"
    sudo test -s "$D/T3-booted" && sudo test -s "$D/D5-passed" && sudo test -s "$D/D7-passed" || stop "T3 has not passed (T3-booted, D5-passed, D7-passed in $D); nothing is armed"
    case $(uname -r) in 7.3.0-17.v272-11-k114s-r3b-ARCH | 7.3.0-17.v272-4-k114s-r3a-ARCH) ;; *) stop "an unexpected kernel; nothing is armed" ;; esac
    [ "$(systemctl is-active snapper-cleanup.timer limine-snapper-sync.service snapper-cleanup.service | sort -u)" = inactive ] || stop "the snapshot sync runs (E12): block F's stop lines first; nothing is armed"
    [ "$(sudo sha256sum /boot/efi/m1n1/boot-ctxr.bin | cut -c1-64)" = $GPU ] || stop "the configured Stage 2 is not P's file; nothing is armed"
    bash "$REPO/linux/display/k114s-dcp-colour" --check >/dev/null 2>&1 || stop "the DCP colour fix is not in monitors.lua (section 4a: bash $REPO/linux/display/k114s-dcp-colour); nothing is armed"
    [ "$(sudo sha256sum /boot/efi/$S2 | cut -c1-64)" = $B5 ] || stop "$S2 is not 90b35137...; nothing is armed"
    [ "$(sudo sed -n 1p /boot/efi/aura-try)" = spent ] || stop "aura-try does not read spent; nothing is armed"
    [ -e /usr/lib/modprobe.d/aurora-m5-vrr.conf ] && grep -q -x 'options appledrm fw27_panel_vrr=1' /usr/lib/modprobe.d/aurora-m5-vrr.conf || stop "the installed aurora-m5-vrr.conf is not the J714s file (fw27_panel_vrr=1) the mask replaces; nothing is armed"
    # the mask goes for one boot; its copy is kept for the undo and for D9c
    if [ -e $m ]; then
      grep -q -x 'options appledrm fw27_panel_vrr=0' $m || stop "$m is not the mask I0 wrote: read it; nothing is armed"
      sudo cp -p $m "$D/aurora-m5-vrr.conf.masked" && sudo rm $m || stop "the mask was not moved; nothing is armed"
    fi
    sudo test -s "$D/aurora-m5-vrr.conf.masked" || stop "no copy of the mask in $D (the undo needs it): nothing is armed"
    [ "$(modprobe -c | grep -c -E '^options appledrm fw27_panel_vrr=1')" = 1 ] && [ "$(modprobe -c | grep -c -E '^options appledrm fw27_panel_vrr=0')" = 0 ] || { sudo cp -p "$D/aurora-m5-vrr.conf.masked" $m; stop "modprobe does not read fw27_panel_vrr=1 without the mask: the mask is back; nothing is armed"; }
    sudo $K arm Omarchy/linux-k114s-r3b || { sudo cp -p "$D/aurora-m5-vrr.conf.masked" $m; stop "the arm refused (its message is above); the mask is back; nothing is armed"; }
    sudo sh -c "printf 'armed\n$S2\n' > /boot/efi/aura-try && sync -f /boot/efi" || {
      sudo sh -c "printf 'spent\n$S2\n' > /boot/efi/aura-try; sync -f /boot/efi"
      [ "$(sudo sed -n 1p /boot/efi/aura-try 2>/dev/null)" = spent ] || {
        echo "STOP: aura-try does not read spent, so it may still read armed. Do not reboot. Run: sudo cat /boot/efi/aura-try; if the first line is not spent: sudo sed -i 1s/armed/spent/ /boot/efi/aura-try && sudo sync -f /boot/efi, then read it again"; exit 1; }
      echo "STOP: aura-try was not written or not synced; it reads spent now. The one-shot is still pending; the mask is gone: put it back with sudo cp -p $D/aurora-m5-vrr.conf.masked $m"; exit 1; }
    [ "$(sudo sed -n 1,2p /boot/efi/aura-try | tr '\n' ' ')" = "armed $S2 " ] || stop "aura-try does not read back as armed for $S2 (sudo cat /boot/efi/aura-try)"
    sudo $K status
    echo "T4 armed: r3b.b1 once, through $S2 once, with fw27_panel_vrr=1 (the mask file is out until D6's result decides it). Rebooting"
    sudo systemd-run --on-active=15s --unit=k114s-d6-reboot systemctl reboot
    )

Expected: as T3a (and the notice N before the reboot). Undo (before the reboot): `sudo $K clear`, `sudo cp -p /var/lib/k114s-recovery/display-d5/aurora-m5-vrr.conf.masked
/etc/modprobe.d/aurora-m5-vrr.conf`, and if `aura-try` reads `armed`: `sudo sed -i 1s/armed/spent/ /boot/efi/aura-try && sudo sync -f /boot/efi`.

**T4b. The boot checks (in the T4 boot, after block F; its folder ends `-disp-bl` again).** T3b with `--vrr on`, and T3's
loader log as the comparison.

    (
    : "${K:?STOP: set K, REPO, D, R5, RT and DO first (section 3): they do not survive the reboot}" "${REPO:?STOP: set REPO first}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    BLI=4a67b082-0a4c-41cf-b6c7-440b29bb8c4f; o=$(sudo cat "$D/last-boot"); REL=7.3.0-17.v272-11-k114s-r3b-ARCH
    [ "$(uname -r)" = $REL ] || stop "this boot is $(uname -r), not r3b"
    uname -v | grep -q 'K114S-R3B-B1' || stop "this kernel is not the brightness build (uname -v: $(uname -v))"
    [ "$(tail -c +5 /sys/firmware/efi/efivars/LoaderEntrySelected-$BLI | iconv -f UTF-16LE -t UTF-8 | tr -d '\0')" = Omarchy.linux-k114s-r3b ] || stop "Limine did not start Omarchy.linux-k114s-r3b"
    [ -e /sys/firmware/efi/efivars/LoaderEntryOneShot-$BLI ] && stop "a one-shot request is still pending"
    [ "$(tr -d '\0' < /proc/device-tree/chosen/aurora,trial 2>/dev/null)" = m1n1/boot-ctxr-disp-bl.bin ] || stop "this boot did not come through m1n1/boot-ctxr-disp-bl.bin (no trial: the Stage 2 hung once and this is r3b.b1 on P: section 6)"
    [ "$(sudo sed -n 1p /boot/efi/aura-try)" = spent ] || stop "aura-try does not read spent"
    sudo cmp -s "$o/boot_id" /proc/sys/kernel/random/boot_id || stop "block F has not run in this boot (last logs: $o)"
    case $o in "$D"/boot-*-disp-bl) ;; *) stop "this boot's logs ($o) are not named for disp-bl" ;; esac
    t=$(mktemp) || exit 1; trap 'rm -f "$t" "$t.a" "$t.b"' EXIT
    sudo "$REPO/tests/hardware/k114s-display-check.sh" --expect published --floor --vrr on --loader-log "$o/loader.log" --wait 10 | tee "$t"
    grep -q '^BAD' "$t" && stop "the display check printed BAD (above): power off after reading it, section 6 (the masked retry: F3)"
    t3=$(sudo sh -c 'ls -d "$1"/boot-*-disp-bl 2>/dev/null | grep -v -x "$2" | tail -1' _ "$D" "$o")
    if [ -n "$t3" ]; then
      sudo sh -c 'grep -F "FDT: GPU:" "$1/loader.log" | sed "s/^\[[^]]*\] //" | sort -u' _ "$t3" > "$t.a"; sudo sh -c 'grep -F "FDT: GPU:" "$1/loader.log" | sed "s/^\[[^]]*\] //" | sort -u' _ "$o" > "$t.b"
      [ -s "$t.a" ] && cmp -s "$t.a" "$t.b" && echo "ok    the loader's GPU lines equal T3's ($(grep -c '' "$t.a"))" || echo "info  the loader's GPU lines differ from T3's, or none: sudo diff them"
    fi
    "$REPO/tests/hardware/k114s-r3a-check.sh" --allow-gpu 2>/dev/null | grep -E '^BAD' && stop "the hardware check printed BAD (above)"
    echo "T4 booted $(date -Is) vrr_capable 1" | sudo tee "$D/T4-booted" >/dev/null
    echo "T4b: the second clean brightness-tree boot, with VRR offered (vrr_capable 1). Now D6"
    )

Expected: as T3b with `ok    vrr_capable 1`, `ok    appledrm.fw27_panel_vrr = Y (--vrr on)`, and the Hyprland line with `vrr` not
checked (the display check run with `--hypr` below sees `vrr False` until D6 turns it on).

**D6. VRR (as the user, in the desktop; about 40 seconds). Agent-run: the D5 ladder again, `vrr_capable`, `misc:vrr` on under a
moving picture, no swap-watchdog line, `misc:vrr` off.** The owner's look (flicker, the 385 ms black on toggling) is pending.

    (
    : "${REPO:?STOP: set K, REPO, D, R5, RT and DO first (section 3)}" "${D:?STOP: set D first}"
    bl=/sys/class/backlight/apple-panel-bl; armed=0
    stop() { echo "STOP: $*"; [ $armed = 1 ] && echo "D6 failed $(date -Is) $*" | sudo tee "$D/D6-failed" >/dev/null; exit 1; }
    off() { hyprctl eval 'hl.config({ misc = { vrr = 0 } })' >/dev/null 2>&1; }
    sudo test -s "$D/T4-booted" || stop "T4b has not passed in this boot ($D/T4-booted)"
    [ "$(omarchy-shell lock isLocked)" = false ] && [ "$(hyprctl monitors -j | jq -r '[.[] | select(.name | test("^eDP-")) | .dpmsStatus] | all')" = true ] || stop "the session is locked or the panel is not lit (F15): a VRR run behind a lock would record a result about a dark panel; nothing was changed"
    vrr() { hyprctl monitors -j | jq -r '.[] | select(.name | test("^eDP-")) | .vrr'; }
    # vrr_capable is a KMS connector property (this kernel has no sysfs file of that name): read it with modetest, which needs no root
    vc=$(modetest -M apple -c 2>/dev/null | awk '$2 == "vrr_capable:" { f = 1; next } f && $1 == "value:" { print $2; exit }')
    [ "$vc" = 1 ] || stop "vrr_capable is '$vc', not 1 (the KMS connector property of the apple card): the mask is still in place or the mode has no VRR range"
    [ "$(cat /sys/module/appledrm/parameters/fw27_panel_vrr)" = Y ] || stop "fw27_panel_vrr is not Y in this boot"
    [ "$(vrr)" = false ] || stop "Hyprland has VRR on already (misc:vrr)"
    # the second clean brightness boot: the D5 ladder again (no questions), the start level back
    "$REPO/linux/brightness/k114s-backlight-check" --auto >/dev/null || stop "the stepped brightness check stopped in the unmasked boot (run it alone to read why)"
    n0=$(sudo dmesg | grep -c -E 'adaptive swap timed out|swap not completed')
    armed=1; trap off EXIT
    hyprctl eval 'hl.config({ misc = { vrr = 1 } })' >/dev/null || stop "hyprctl eval did not take misc:vrr"
    sleep 3; [ "$(vrr)" = true ] || stop "Hyprland did not turn VRR on (vrr '$(vrr)')"
    timeout 20 mpv --no-config --vo=gpu --hwdec=no --ao=null --no-audio --fs --loop-file=inf 'av://lavfi:mandelbrot=size=1512x982:rate=60'; echo "mpv exit $? (124: the 20 seconds ran out, expected)"
    sudo dmesg | grep -v -i 'command line' | grep -E 'VRR_ENABLED' | tail -3 | sed 's/^/info  kernel: /'
    sleep 1; off; sleep 3; [ "$(vrr)" = false ] || stop "Hyprland did not turn VRR off again"
    [ "$(sudo dmesg | grep -c -E 'adaptive swap timed out|swap not completed')" = "$n0" ] || stop "the swap watchdog fired with VRR on (adaptive swap timed out / swap not completed: the driver turned VRR off itself)"
    sudo dmesg | grep -v -i 'command line' | grep -E 'DCP has crashed|co-processor has crashed|present dropped|SError|Oops|BUG:' && stop "a DCP crash line with VRR on (above)"
    armed=0; trap - EXIT
    echo "D6 agent-run passed $(date -Is): vrr_capable 1, misc:vrr on 20 s under load and off again, no watchdog line, no crash" | sudo tee "$D/D6-passed" >/dev/null
    echo "owner-look D6 PENDING: no flicker with VRR on under motion; about 385 ms of black when it toggles is expected (J716s)" | sudo tee -a "$D/owner-look.txt" >/dev/null
    echo "D6: VRR offered and used at runtime without a watchdog line or a crash"
    )

Expected: `mpv exit 124`, `info  kernel: ... VRR_ENABLED 1: selecting ... again` (the line is the kernel's own at the first
VRR swap), the last line. On any stop after VRR was turned on the block writes `D6-failed` and turns `misc:vrr` off. The result
decides the mask in D9c (F3). Undo: `hyprctl eval 'hl.config({ misc = { vrr = 0 } })'`.

Record `T4 PASSED` (D6) in the recovery log. If the session is going on to D9c, do it now (section D9c; its first guard allows
this boot, whose Stage 2 trial is spent). Otherwise `sudo systemctl reboot`: the default (r3a on P) comes back; run block C, then
block P.

### D9. The promotion: r3b.b1 and the display Stage 2 become what this Mac boots

**D9a. The gate and the proof (reads only; writes the record `$D/D9a-passed`).**

    (
    : "${REPO:?STOP: set K, REPO, D, R5, RT and DO first (section 3)}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    h() { sudo sha256sum "$1" 2>/dev/null | cut -c1-64; }
    B5=90b351377d6fcbad00ddc4c2fb74fce4313dd7fa5f4978ba895a7c41be523e30; BT=5b6b83c8cd5e59333182f6ca37f22b1e99bd029daa1342d186daee096b292fda
    PINL=beceb683b63a6d421ce58061a55c14a6d09e0381a23c1a543df55f4cc8007392; GPU=9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc
    for m in T3-booted T4-booted D5-passed D7-passed G6b-passed M9-passed; do sudo test -s "$D/$m" || stop "no $D/$m: that gate has not passed (section 2, F5)"; done
    bash "$REPO/linux/display/k114s-dcp-colour" --check >/dev/null 2>&1 || stop "the DCP colour fix is not in monitors.lua (section 4a: bash $REPO/linux/display/k114s-dcp-colour); nothing was changed"
    for s in D6 D8; do
      o=; for r in passed failed skipped; do sudo test -s "$D/$s-$r" && o=$r; done
      [ -n "$o" ] || stop "no outcome recorded for $s (passed, failed or skipped: write $D/$s-skipped to skip it on purpose)"
      echo "$s: $o"
    done
    tool=$(h /boot/efi/k114s-repair/promotion/k114s_repair.py)
    sudo grep -q "$tool" "$D/M9-passed" || stop "M9-passed does not name the tool now staged on the ESP ($tool): the macOS agent ran another one; repeat M9"
    [ "$(h "$D/k114s.dtb.bright")" = $BT ] && [ "$(h "$D/m1n1-pin.bin")" = $PINL ] && [ "$(h "$D/boot-ctxr-disp-bl.bin")" = $B5 ] || stop "an input in $D is not the expected file (S5)"
    [ "$(h /boot/efi/m1n1/boot-ctxr-r3-gpu.bin)" = $GPU ] || stop "m1n1/boot-ctxr-r3-gpu.bin (the Linux-side fallback and M9's source) is not P's file"
    cmp -s "$REPO/linux/99-k114s-no-appledrm.conf" /etc/mkinitcpio.conf.d/99-k114s-no-appledrm.conf || stop "the no-appledrm drop-in is not installed (G6a): a rebuild after D9 would put appledrm in the initramfs (F16)"
    # the proof (P1b's method): in a throw-away root, the Stage 2 hook, with the pin loader as m1n1-ctxr.bin and the brightness
    # tree pinned, writes the D9 file byte for byte; with no m1n1-ctxr.bin it would write the installed loader's file
    t=$(mktemp -d) || exit 1; trap 'sudo rm -rf "$t"' EXIT
    mkdir -p "$t/boot/efi/m1n1" "$t/boot/efi/k114s-repair" "$t/usr/lib/asahi-boot"
    sudo cat /boot/efi/m1n1/boot.bin > "$t/boot/efi/m1n1/boot.bin"; cp /usr/lib/asahi-boot/m1n1.bin "$t/usr/lib/asahi-boot/"
    sudo cat "$D/k114s.dtb.bright" > "$t/boot/efi/k114s-repair/k114s.dtb"
    OMARCHY_ROOT=$t sh /usr/local/lib/omarchy-k114s/update-boot-ctxr >/dev/null || stop "the Stage 2 hook refused the brightness tree"
    [ "$(sha256sum < "$t/boot/efi/m1n1/boot-ctxr.bin" | cut -c1-64)" != $B5 ] || stop "without m1n1-ctxr.bin the hook already writes the D9 file: the installed loader is not what this runbook thinks"
    sudo cat "$D/m1n1-pin.bin" > "$t/usr/lib/asahi-boot/m1n1-ctxr.bin"
    OMARCHY_ROOT=$t sh /usr/local/lib/omarchy-k114s/update-boot-ctxr >/dev/null || stop "the Stage 2 hook refused the pin loader"
    [ "$(sha256sum < "$t/boot/efi/m1n1/boot-ctxr.bin" | cut -c1-64)" = $B5 ] || stop "a hook run with m1n1-ctxr.bin would not write the D9 file byte for byte (90b35137...): do not run D9c"
    echo "D9a $(date -Is)" | sudo tee "$D/D9a-passed" >/dev/null || stop "cannot write $D/D9a-passed"
    echo "D9a: the gates hold, the staged tool is the one the macOS agent ran, and the hook with the pin loader writes the D9 Stage 2 byte for byte"
    )

Expected: `D6: passed` (or failed, skipped), `D8: ...`, the last line.

**D9c. Write the promotion (from boot 2's session, or any boot of r3a or r3b.b1; no package transaction).**
Order, so that every stop leaves a state that boots and has been proven: the pins (the installed loader on the display tree:
T1), the loader file, `default_entry` (r3b.b1 on P's Stage 2: T1's configuration), then the Stage 2.

    (
    : "${K:?STOP: set K, REPO, D, R5, RT and DO first (section 3)}" "${REPO:?STOP: set REPO first}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    h() { sudo sha256sum "$1" 2>/dev/null | cut -c1-64; }
    c=/boot/efi/limine.conf; L=/usr/local/lib/omarchy-k114s; BI=/boot/efi/EFI/Linux/omarchy_linux-k114s-r3b.efi; m=/etc/modprobe.d/aurora-m5-vrr.conf
    B5=90b351377d6fcbad00ddc4c2fb74fce4313dd7fa5f4978ba895a7c41be523e30; BT=5b6b83c8cd5e59333182f6ca37f22b1e99bd029daa1342d186daee096b292fda
    PINL=beceb683b63a6d421ce58061a55c14a6d09e0381a23c1a543df55f4cc8007392; GPU=9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc
    GPUT=2c870ba9f5963f5ae1ed18a7effa520daa234583997470d9552a795b4aafcda5; R3A=a15fa01ab7e20c9c1bf1b3f61c04f6ab765c4aa425188c22f70648a3871c52f4
    rec() { sudo sh -c 'cd /boot/efi && { sha256sum limine.conf m1n1/boot-ctxr.bin k114s-repair/k114s.dtb EFI/Linux/*.efi; sha256sum /usr/local/lib/omarchy-k114s/k114s.dtb; grep -i "^default_entry" limine.conf; grep -E "^[[:blank:]]*/" limine.conf; grep -E "^[[:blank:]]*path:" limine.conf; sed -n 1p aura-try; }'; }
    case $(uname -r) in 7.3.0-17.v272-4-k114s-r3a-ARCH | 7.3.0-17.v272-11-k114s-r3b-ARCH) ;; *) stop "an unexpected kernel; nothing was changed" ;; esac
    sudo test -s "$D/D9a-passed" || stop "D9a first; nothing was changed"
    [ "$(pacman -Q linux-k114s-r3b)" = "linux-k114s-r3b 7.3.0.r3b.b1-1" ] || stop "r3b.b1 is not installed; nothing was changed"
    [ "$(systemctl is-active snapper-cleanup.timer limine-snapper-sync.service snapper-cleanup.service | sort -u)" = inactive ] || stop "the snapshot sync runs (E12): block C's or F's stop lines first; nothing was changed"
    [ "$(h /boot/efi/m1n1/boot-ctxr.bin)" = $GPU ] && [ "$(h /boot/efi/k114s-repair/k114s.dtb)" = $GPUT ] && [ "$(h $L/k114s.dtb)" = $GPUT ] || stop "P is not the configured state (a half-run D9c? read the undo of D9c); nothing was changed"
    [ "$(h /boot/efi/m1n1/boot-ctxr-r3-gpu.bin)" = $GPU ] || stop "m1n1/boot-ctxr-r3-gpu.bin is not P's file; nothing was changed"
    [ "$(sudo sed -n 1p /boot/efi/aura-try)" = spent ] || stop "aura-try does not read spent; nothing was changed"
    [ "$(sudo grep -c -i '^default_entry:' $c)" = 1 ] && sudo grep -q -x 'default_entry: Omarchy/linux-k114s' $c || stop "default_entry is not exactly Omarchy/linux-k114s; nothing was changed"
    sudo cmp -s $c "$D/limine.conf.after-r3b" || stop "limine.conf is not the file I1b left (a Snapshots entry: block Xs first); nothing was changed"
    l=$(sudo awk '{ s = $0; sub(/^[ \t]+/, "", s) } s == "//linux-k114s-r3b" {f=1; next} f && /^[ \t]*\/\// {exit} f && /^[ \t]*path:/ {print; exit}' $c); p=${l#*boot():}; hh=${p#*#}; p=${p%%#*}
    [ "/boot/efi$p" = $BI ] && [ "$(sudo b2sum $BI | cut -d' ' -f1)" = "$hh" ] || stop "the r3b entry does not boot omarchy_linux-k114s-r3b.efi with a matching #hash; nothing was changed"
    [ "$(h /boot/efi/EFI/Linux/omarchy_linux-k114s.efi)" = $R3A ] || stop "the r3a image is not a15fa01a...; nothing was changed"
    [ "$(sudo ls /boot/efi/EFI/Linux | LC_ALL=C sort | tr '\n' ' ')" = "omarchy_linux-k114s-r3b.efi omarchy_linux-k114s.efi " ] || stop "EFI/Linux is not exactly the r3a and r3b images; nothing was changed"
    [ ! -e /usr/lib/asahi-boot/m1n1-ctxr.bin ] || stop "/usr/lib/asahi-boot/m1n1-ctxr.bin exists: read it (a half-run D9c?); nothing was changed"
    sudo $K check || stop "check is not clean; nothing was changed"
    [ "$(df -B1 --output=avail /boot/efi | tail -1)" -ge 95000000 ] || stop "less than 95 MB free; nothing was changed"
    # the records and the copies the undo needs
    rec | sudo tee "$D/before-d9.txt" >/dev/null && sudo test -s "$D/before-d9.txt" || stop "no boot record; nothing was changed"
    sudo cp -p $c "$D/limine.conf.before-d9" && sudo cp -p /etc/pacman.conf "$D/pacman.conf.before-d9" && sudo cp -p $L/holds.list "$D/holds.list.before-d9" &&
      sudo cp -p /etc/omarchy-mac-boot/owner-boot-chain "$D/owner-boot-chain.before-d9" && sudo cp -p $L/k114s.dtb "$D/k114s.dtb.p" || stop "the copies were not made; nothing was changed"
    [ "$(h "$D/k114s.dtb.p")" = $GPUT ] || stop "the copy of P's tree does not verify; nothing was changed"
    # 1. both pins become the brightness tree: the Linux copy first, then the one the hook reads first (P1a's order)
    sudo install -m644 "$D/k114s.dtb.bright" $L/k114s.dtb.k114s-new && sudo mv -f $L/k114s.dtb.k114s-new $L/k114s.dtb
    sudo cp "$D/k114s.dtb.bright" /boot/efi/k114s-repair/k114s.dtb.k114s-new && sudo sync -f /boot/efi && sudo mv -f /boot/efi/k114s-repair/k114s.dtb.k114s-new /boot/efi/k114s-repair/k114s.dtb && sudo sync -f /boot/efi
    [ "$(h $L/k114s.dtb)" = $BT ] && [ "$(h /boot/efi/k114s-repair/k114s.dtb)" = $BT ] || stop "a pin does not read back as the brightness tree: run the undo of D9c; do not reboot"
    # 2. the pin loader, where the Stage 2 hook looks for the loader it writes
    sudo install -m644 "$D/m1n1-pin.bin" /usr/lib/asahi-boot/m1n1-ctxr.bin.k114s-new && sudo mv -f /usr/lib/asahi-boot/m1n1-ctxr.bin.k114s-new /usr/lib/asahi-boot/m1n1-ctxr.bin
    [ "$(h /usr/lib/asahi-boot/m1n1-ctxr.bin)" = $PINL ] || stop "m1n1-ctxr.bin does not read back as the pin loader: run the undo of D9c; do not reboot"
    # 3. default_entry becomes the r3b path (D9a), under the boot-partition lock, through a file beside it
    t=$(mktemp -d) || exit 1; trap 'rm -rf "$t"' EXIT
    sudo cat $c > "$t/old"; sed 's#^default_entry: Omarchy/linux-k114s$#default_entry: Omarchy/linux-k114s-r3b#' "$t/old" > "$t/new"
    [ "$(diff "$t/old" "$t/new" | grep -c '^[<>]')" = 2 ] && grep -q -x 'default_entry: Omarchy/linux-k114s-r3b' "$t/new" || stop "the edit is not that one line: run the undo of D9c; do not reboot"
    sudo flock -w 120 /run/lock/boot-partition.lock sh -c 'cmp -s "$1" "$2" || { echo "limine.conf changed while this block ran"; exit 1; }
      cp "$3" "$1.k114s-new" && sync -f "${1%/*}" && cmp -s "$3" "$1.k114s-new" && mv -f "$1.k114s-new" "$1" && sync -f "${1%/*}"' _ $c "$t/old" "$t/new" ||
      stop "limine.conf was not written (sudo rm -f $c.k114s-new); run the undo of D9c; do not reboot"
    sudo cmp -s $c "$t/new" || stop "limine.conf does not read back as written: run the undo of D9c now; do not reboot"
    sudo $K check || stop "check is not clean: run the undo of D9c now; do not reboot"
    # 4. the configured Stage 2: written beside, read back, renamed, read back
    sudo cp "$D/boot-ctxr-disp-bl.bin" /boot/efi/m1n1/boot-ctxr.bin.k114s-new && sudo sync -f /boot/efi
    [ "$(h /boot/efi/m1n1/boot-ctxr.bin.k114s-new)" = $B5 ] || { sudo rm -f /boot/efi/m1n1/boot-ctxr.bin.k114s-new; stop "the new file does not read back; boot-ctxr.bin is still P's file. Run the undo of D9c"; }
    sudo mv -f /boot/efi/m1n1/boot-ctxr.bin.k114s-new /boot/efi/m1n1/boot-ctxr.bin && sudo sync -f /boot/efi
    [ "$(h /boot/efi/m1n1/boot-ctxr.bin)" = $B5 ] || stop "boot-ctxr.bin does not read back as the D9 file: run the undo of D9c now; do not reboot"
    # 5. the trial copy of that file comes off the ESP (its copy stays in $D)
    sudo test -e /boot/efi/m1n1/boot-ctxr-disp-bl.bin && { sudo rm /boot/efi/m1n1/boot-ctxr-disp-bl.bin && sudo sync -f /boot/efi || stop "the trial copy was not removed"; }
    # 6. the holds: linux-k114s-r3b joins the held set (P6c's way)
    grep -q -x linux-k114s-r3b $L/holds.list || echo linux-k114s-r3b | sudo tee -a $L/holds.list >/dev/null
    sudo $L/apply-holds || stop "apply-holds failed: sudo cp -p $D/holds.list.before-d9 $L/holds.list; sudo cp -p $D/pacman.conf.before-d9 /etc/pacman.conf"
    held=$(grep -m1 '^IgnorePkg = ' /etc/pacman.conf)
    for q in linux-k114s-r3b linux-k114s linux-aurora m1n1-aurora uboot-aurora limine-mkinitcpio-hook limine-snapper-sync; do echo " $held " | grep -q " $q " || stop "$q is not in the first IgnorePkg line"; done
    grep -q -x 'export M1N1_UPDATE_DISABLED=1' /etc/default/update-m1n1 || stop "update-m1n1 is not off"
    # 7. the owner's boot-chain declaration names what boots now
    echo "K114s: kernel linux-k114s-r3b 7.3.0.r3b.b1-1 (Limine default Omarchy/linux-k114s-r3b; second image linux-k114s r3a) and the display Stage 2 (m1n1/boot-ctxr.bin = pin loader beceb683 + brightness tree 5b6b83c8) from omarchy-m5p-oled, promoted $(date +%F); see /usr/local/lib/omarchy-k114s and docs/r3-display-d5-d9.md" |
      sudo tee /etc/omarchy-mac-boot/owner-boot-chain >/dev/null
    # 8. the VRR mask follows D6: out if D6 passed, in if it failed or was skipped
    if sudo test -s "$D/D6-passed"; then
      [ ! -e $m ] || stop "the mask file is back after a passed D6: read $m; the promotion is written"
    else
      [ -e $m ] || { sudo test -s "$D/aurora-m5-vrr.conf.masked" && sudo cp -p "$D/aurora-m5-vrr.conf.masked" $m; } || stop "no mask file to put back for a D6 that did not pass: sudo install the mask (options appledrm fw27_panel_vrr=0) at $m"
      grep -q -x 'options appledrm fw27_panel_vrr=0' $m || stop "$m is not the mask"
    fi
    sudo $K check || stop "check is not clean: run the undo of D9c now; do not reboot"
    rec | sudo tee "$D/after-d9.txt" >/dev/null && sudo cp -p $c "$D/limine.conf.after-d9" && sudo chmod 600 "$D/limine.conf.after-d9" || stop "no after-record"
    sudo $K entries
    echo "D9c: default Omarchy/linux-k114s-r3b, Stage 2 and pins the display files, the pin loader in m1n1-ctxr.bin, holds updated; ESP free $(df -B1 --output=avail /boot/efi | tail -1). Reboot (boot 3) only after the lead has recorded the acknowledgement of the notice N in $D/N-acked-3, saying that the owner or the macOS agent is reachable; this line checks it: sudo grep -q -i -E 'owner|macos' $D/N-acked-3 && sudo systemd-run --on-active=15s --unit=k114s-d9-reboot systemctl reboot || echo 'STOP: no reboot scheduled: N-acked-3 is missing or does not say the owner or the macOS agent is reachable'"
    )

Expected: `ok    default_entry is Omarchy/linux-k114s-r3b (entry 3, id Omarchy.linux-k114s-r3b, boots boot():/EFI/Linux/omarchy_linux-k114s-r3b.efi#...)`
and `ok    the default entry's file matches limine.conf` (twice), `k114s apply-holds: holds in /etc/pacman.conf: ...` with one name more
than P6c's 22 (`linux-k114s-r3b`), `entries` listing the default, and the last line with about 110.4 million free.
Then record `D9 WRITTEN` and reboot (F14): the new default boots, nothing is armed.

**Undo of D9c (from Linux, any boot that answers).** It puts P's Stage 2 and tree, `default_entry` r3a and the loader file back.
The holds, the owner-boot-chain text and the VRR mask stay (harmless).

    (
    : "${K:?STOP: set K, REPO, D, R5, RT and DO first (section 3)}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    h() { sudo sha256sum "$1" 2>/dev/null | cut -c1-64; }
    c=/boot/efi/limine.conf; L=/usr/local/lib/omarchy-k114s
    GPU=9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc; GPUT=2c870ba9f5963f5ae1ed18a7effa520daa234583997470d9552a795b4aafcda5
    [ "$(h /boot/efi/m1n1/boot-ctxr-r3-gpu.bin)" = $GPU ] && [ "$(h "$D/k114s.dtb.p")" = $GPUT ] || stop "P's Stage 2 or tree is not where the undo expects it (m1n1/boot-ctxr-r3-gpu.bin, $D/k114s.dtb.p); nothing was changed"
    [ "$(sudo grep -c -i '^default_entry:' $c)" = 1 ] || stop "not exactly one default_entry line; nothing was changed"
    # 1. the configured Stage 2 is P's file again
    sudo cp /boot/efi/m1n1/boot-ctxr-r3-gpu.bin /boot/efi/m1n1/boot-ctxr.bin.k114s-new && sudo sync -f /boot/efi
    [ "$(h /boot/efi/m1n1/boot-ctxr.bin.k114s-new)" = $GPU ] || { sudo rm -f /boot/efi/m1n1/boot-ctxr.bin.k114s-new; stop "the copy of P's Stage 2 does not read back; nothing was changed"; }
    sudo mv -f /boot/efi/m1n1/boot-ctxr.bin.k114s-new /boot/efi/m1n1/boot-ctxr.bin && sudo sync -f /boot/efi
    [ "$(h /boot/efi/m1n1/boot-ctxr.bin)" = $GPU ] || stop "boot-ctxr.bin does not read back as P's file: run this undo again; do not reboot"
    # 2. both pins are P's tree
    sudo install -m644 "$D/k114s.dtb.p" $L/k114s.dtb
    sudo cp "$D/k114s.dtb.p" /boot/efi/k114s-repair/k114s.dtb.k114s-new && sudo sync -f /boot/efi && sudo mv -f /boot/efi/k114s-repair/k114s.dtb.k114s-new /boot/efi/k114s-repair/k114s.dtb && sudo sync -f /boot/efi
    [ "$(h $L/k114s.dtb)" = $GPUT ] && [ "$(h /boot/efi/k114s-repair/k114s.dtb)" = $GPUT ] || stop "a pin does not read back as P's tree: run this undo again"
    # 3. default_entry is the r3a path again
    t=$(mktemp -d) || exit 1; trap 'rm -rf "$t"' EXIT
    sudo cat $c > "$t/old"; sed 's#^default_entry: .*$#default_entry: Omarchy/linux-k114s#' "$t/old" > "$t/new"
    sudo flock -w 120 /run/lock/boot-partition.lock sh -c 'cmp -s "$1" "$2" || { echo "limine.conf changed while this block ran"; exit 1; }
      cp "$3" "$1.k114s-new" && sync -f "${1%/*}" && cmp -s "$3" "$1.k114s-new" && mv -f "$1.k114s-new" "$1" && sync -f "${1%/*}"' _ $c "$t/old" "$t/new" || stop "limine.conf was not written (sudo rm -f $c.k114s-new): run this undo again"
    # 4. the Stage 2 hook goes back to the installed loader
    sudo rm -f /usr/lib/asahi-boot/m1n1-ctxr.bin
    sudo sh -c "printf 'spent\nm1n1/boot-ctxr-r3-gpu.bin\n' > /boot/efi/aura-try && sync -f /boot/efi"
    sudo $K check || stop "check is not clean"
    echo "D9u: P's Stage 2 and tree, default Omarchy/linux-k114s (r3a); r3b.b1 stays installed beside it. Reboot, then block C"
    )

Expected: the check with `default_entry is Omarchy/linux-k114s (entry 3, ...)` and the last line. After it: block C, block P
(`window open, r3b installed`), and the window continues (or closes: C1b, C2b, block X, C4).

**Block P9: the promoted configuration holds (read-only; after D9c in every default boot, and before and after every update).**

    (
    : "${K:?STOP: set K, REPO, D, R5, RT and DO first (section 3)}" "${REPO:?STOP: set REPO first}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    h() { sudo sha256sum "$1" 2>/dev/null | cut -c1-64; }
    c=/boot/efi/limine.conf; L=/usr/local/lib/omarchy-k114s
    B5=90b351377d6fcbad00ddc4c2fb74fce4313dd7fa5f4978ba895a7c41be523e30; BT=5b6b83c8cd5e59333182f6ca37f22b1e99bd029daa1342d186daee096b292fda
    PINL=beceb683b63a6d421ce58061a55c14a6d09e0381a23c1a543df55f4cc8007392; GPU=9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc
    GPUT=2c870ba9f5963f5ae1ed18a7effa520daa234583997470d9552a795b4aafcda5; R3A=a15fa01ab7e20c9c1bf1b3f61c04f6ab765c4aa425188c22f70648a3871c52f4
    AUR=72f5d32c9a4bc443bddab3eba171365b8cd082bf9cc61f665b15684d2d64403a
    [ "$(h /boot/efi/m1n1/boot-ctxr.bin)" = $B5 ] || stop "the configured Stage 2 is not the display file 90b35137..."
    [ "$(h /boot/efi/k114s-repair/k114s.dtb)" = $BT ] && [ "$(h $L/k114s.dtb)" = $BT ] || stop "a pinned tree is not the brightness tree 5b6b83c8..."
    [ "$(h /usr/lib/asahi-boot/m1n1-ctxr.bin)" = $PINL ] || stop "/usr/lib/asahi-boot/m1n1-ctxr.bin is not the pin loader (a Stage 2 hook run would write the installed loader's file)"
    [ "$(h /boot/efi/m1n1/boot-ctxr-r3-gpu.bin)" = $GPU ] && [ "$(h /boot/efi/k114s-repair/promotion/k114s.dtb.gpu)" = $GPUT ] || stop "the fallback files are not P's (m1n1/boot-ctxr-r3-gpu.bin, k114s-repair/promotion/k114s.dtb.gpu)"
    sudo test -s /boot/efi/k114s-repair/promotion/repair-block.conf && sudo test -s /boot/efi/k114s-repair/promotion/k114s_repair.py && sudo test -s /boot/efi/k114s-repair/r2c/repair-uki.txt || stop "a file restore-repair needs is gone from the ESP"
    [ "$(h /boot/efi/EFI/Linux/omarchy_linux-k114s.efi)" = $R3A ] || stop "the r3a image is not a15fa01a..."
    [ "$(sudo ls /boot/efi/EFI/Linux | LC_ALL=C sort | tr '\n' ' ')" = "omarchy_linux-k114s-r3b.efi omarchy_linux-k114s.efi " ] || stop "EFI/Linux is not exactly the r3b and r3a images (a third image? a rebuild brought linux-aurora's back: section 4, U1): $(sudo ls /boot/efi/EFI/Linux | tr '\n' ' ')"
    # G6 on every image, every time (F16): a rebuild from a display-tree boot can put appledrm into the initramfs; the drop-in is what prevents it
    grep -q -x '  _addedmodules\[appledrm\]=1' /etc/mkinitcpio.conf.d/99-k114s-no-appledrm.conf 2>/dev/null && grep -q -x '  _addedmodules\[dcp_fabric_core\]=1' /etc/mkinitcpio.conf.d/99-k114s-no-appledrm.conf || stop "the no-appledrm drop-in is not installed (G6a): the next rebuild would put appledrm in the initramfs (F16)"
    # an Omarchy migration rewrote monitors.lua once: a DCP boot without the colour fix is black (section 4a)
    bash "$REPO/linux/display/k114s-dcp-colour" --check >/dev/null 2>&1 || stop "the DCP colour fix is missing or outdated in monitors.lua (a black screen on a DCP boot: bash $REPO/linux/display/k114s-dcp-colour, then restart Hyprland)"
    bash "$REPO/linux/display/k114s-greeter-colour" --check >/dev/null 2>&1 || stop "the greeter's colour guard is not in place (an omarchy-settings-dev update may have changed the stock greeter config): sudo bash $REPO/linux/display/k114s-greeter-colour"
    g=$(sudo mktemp -d /var/tmp/k114s-p9.XXXXXX) || exit 1; trap 'sudo rm -rf "$g"' EXIT
    # the folder is root-only: a glob here is expanded by the user's shell, finds nothing and passes the literal name, so list it under sudo
    for i in $(sudo find /boot/efi/EFI/Linux -maxdepth 1 -name "*.efi" | sort); do
      sudo objcopy --dump-section .initrd="$g/initrd" "$i" /dev/null 2>/dev/null; sudo test -s "$g/initrd" || stop "no .initrd section dumped from $i"
      sudo sh -c 'lsinitcpio "$1/initrd" > "$1/list" 2>/dev/null' _ "$g"; [ "$(sudo grep -c '\.ko' "$g/list")" -ge 20 ] || stop "lsinitcpio lists no modules for $i"
      [ "$(sudo grep -c -E 'appledrm|dcp.fabric.core' "$g/list")" = 0 ] || stop "appledrm or dcp-fabric-core is in the initramfs of $i (G6): do not reboot into it; section 4, U1 says what to rebuild"
      sudo rm -f "$g/initrd"
    done
    [ "$(sudo grep -E '^[[:blank:]]*/' $c | tr -d ' \t' | LC_ALL=C sort | tr '\n' ' ')" = "$(printf '%s\n' /+Omarchy //linux-k114s //linux-k114s-r3b | LC_ALL=C sort | tr '\n' ' ')" ] || stop "the menu is not exactly the folder, linux-k114s and linux-k114s-r3b (a Snapshots entry?)"
    [ "$(sudo grep -c -i '^default_entry:' $c)" = 1 ] && sudo grep -q -x 'default_entry: Omarchy/linux-k114s-r3b' $c || stop "default_entry is not exactly Omarchy/linux-k114s-r3b"
    for e in linux-k114s linux-k114s-r3b; do
      l=$(sudo awk -v e="$e" '{ s = $0; sub(/^[ \t]+/, "", s) } s == "//" e {f=1; next} f && /^[ \t]*\/\// {exit} f && /^[ \t]*path:/ {print; exit}' $c); f=${l#*boot():}; hh=${f#*#}; f=${f%%#*}
      [ -n "$l" ] && [ "$hh" != "$f" ] && [ "$(sudo b2sum "/boot/efi$f" | cut -d' ' -f1)" = "$hh" ] || stop "the $e entry has no hash or does not match its image (Limine would wait for a key)"
    done
    sudo $K check || stop "k114s-boot-once check is not clean"
    [ "$(sudo sed -n 1p /boot/efi/aura-try)" = spent ] || stop "aura-try does not read spent"
    sudo test -e /etc/omarchy-k114s/stage2-trial && stop "a standing Stage 2 trial is configured"
    grep -q -x 'export M1N1_UPDATE_DISABLED=1' /etc/default/update-m1n1 || stop "update-m1n1 is not off"
    grep -m1 '^IgnorePkg = ' /etc/pacman.conf | tr ' ' '\n' | grep -q -x linux-k114s-r3b || stop "the holds block lacks linux-k114s-r3b (sudo $L/apply-holds)"
    [ "$(systemctl is-enabled hibernate.target hybrid-sleep.target suspend-then-hibernate.target | sort -u)" = masked ] && case $(systemctl is-enabled suspend.target) in masked) true ;; *) sudo /usr/local/lib/omarchy-k114s/k114s-lid-sleep check >/dev/null ;; esac || stop "a sleep target is not masked, or suspend.target is not masked and the lid-sleep gate does not hold it (sudo /usr/local/lib/omarchy-k114s/k114s-lid-sleep check says why)"
    [ "$(h "$D/omarchy_linux-aurora.efi")" = $AUR ] || stop "the copy of the linux-aurora image in $D is gone or changed (the way back to three images needs it)"
    free=$(df -B1 --output=avail /boot/efi | tail -1); [ "$free" -ge 95000000 ] || stop "ESP free is $free: below 95 MB (the guard's minimum is 88,080,384): find what took the space"
    echo "this boot: $(uname -r), Stage 2 $({ tr -d '\0' < /proc/device-tree/chosen/aurora,trial; } 2>/dev/null || echo configured)"; echo "ESP free: $free"
    echo "P9: the promoted display configuration holds"
    )

Expected: the check with `default_entry is Omarchy/linux-k114s-r3b (entry 3, ...)`, `ESP free` about 110.4 million, the last
line (G6 is checked for both images). Nothing to undo.

**Block C9: the check after a boot of the promoted configuration (boots 3 and 4 only: after block F).** Block F always stops the
snapshot sync and refuses on a `limine_history` that changed after W0, so neither F nor C9 is run after D9x. A later boot is
checked with block P9 and, as the user in the desktop, `k114s-display-check.sh --expect published --vrr <on|off> --wait 5 --hypr` and
`k114s-r3a-check.sh --allow-gpu` (no `BAD`).

    (
    : "${K:?STOP: set K, REPO, D, R5, RT and DO first (section 3): they do not survive the reboot}" "${REPO:?STOP: set REPO first}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    BLI=4a67b082-0a4c-41cf-b6c7-440b29bb8c4f; REL=7.3.0-17.v272-11-k114s-r3b-ARCH; o=$(sudo cat "$D/last-boot")
    # before the close (D9x) the snapshot sync is held off in every boot (E12); after it, left alone
    if sudo test -e "$D/sync-held"; then
      for i in $(seq 90); do [ "$(systemctl show -p ActiveState --value snapper-cleanup.service)" = inactive ] && break; sleep 2; done
      sudo systemctl stop snapper-cleanup.timer limine-snapper-sync.service || stop "the snapshot sync was not stopped"
      sudo grep -q -E '^[[:blank:]]*//Snapshots' /boot/efi/limine.conf && stop "limine.conf has a Snapshots entry (the sync ran before this block): block Xs, then block C9 again"
      sudo diff -r -q "$D/limine_history.before-window" "/boot/efi/$(cat /etc/machine-id)/limine_history" >/dev/null || stop "limine_history changed since W0: block Xs, then block C9 again"
    fi
    [ "$(uname -r)" = $REL ] || stop "this boot is $(uname -r), not r3b"
    bash "$REPO/linux/display/k114s-dcp-colour" --check >/dev/null 2>&1 || stop "the DCP colour fix is not in monitors.lua (a black screen on a DCP boot: bash $REPO/linux/display/k114s-dcp-colour, then restart Hyprland)"
    uname -v | grep -q 'K114S-R3B-B1' || stop "this kernel is not the brightness build (uname -v: $(uname -v))"
    [ "$(tail -c +5 /sys/firmware/efi/efivars/LoaderEntrySelected-$BLI | iconv -f UTF-16LE -t UTF-8 | tr -d '\0')" = Omarchy.linux-k114s-r3b ] || stop "Limine did not start Omarchy.linux-k114s-r3b"
    [ -e /sys/firmware/efi/efivars/LoaderEntryOneShot-$BLI ] && stop "a one-shot request is pending: this was not a default boot"
    [ -e /proc/device-tree/chosen/aurora,trial ] && stop "this boot came through an aura-try trial: $(tr -d '\0' < /proc/device-tree/chosen/aurora,trial)"
    # the loader's identity is the Stage 2 file's hash and the published hand-off (the display check): the pin and the installed loader report one version string
    [ "$(sudo sha256sum /boot/efi/m1n1/boot-ctxr.bin | cut -c1-64)" = 90b351377d6fcbad00ddc4c2fb74fce4313dd7fa5f4978ba895a7c41be523e30 ] || stop "boot-ctxr.bin is not the display file"
    sudo cmp -s "$o/boot_id" /proc/sys/kernel/random/boot_id || stop "block F has not run in this boot (last logs: $o)"
    case $o in "$D"/boot-*-configured) ;; *) stop "this boot's logs ($o) are not named for the configured Stage 2" ;; esac
    vrr=off; sudo test -s "$D/D6-passed" && vrr=on
    sudo $K status
    t=$(mktemp) || exit 1; trap 'rm -f "$t"' EXIT
    sudo "$REPO/tests/hardware/k114s-display-check.sh" --expect published --floor --vrr $vrr --loader-log "$o/loader.log" --wait 10 | tee "$t"
    grep -q '^BAD' "$t" && stop "the display check printed BAD (above)"
    "$REPO/tests/hardware/k114s-r3a-check.sh" --allow-gpu 2>/dev/null | tee "$t"
    grep -q '^BAD' "$t" && stop "the hardware check printed BAD (above)"
    sudo dmesg | grep -E 'Oops|BUG:|WARNING:|SError|storm' | grep -v -i 'command line' && stop "the kernel log has an Oops, BUG, WARNING, SError or storm line (above)"
    echo "C9 $(cat /proc/sys/kernel/random/boot_id) $(date -Is)" | sudo tee "$D/C9-passed-$(cat /proc/sys/kernel/random/boot_id)" >/dev/null
    echo "C9: a clean default boot of r3b.b1 on the configured display Stage 2 (vrr $vrr)"
    )

Then block P9, and, as the user in the desktop, `"$REPO/tests/hardware/k114s-display-check.sh" --expect published --vrr <on|off>
--wait 5 --hypr | grep -E '^(ok|BAD)|hyprland|display-check'` (`hyprland: eDP-1 3024x1986@120.00 scale 2 vrr False`). Expected: the
first runbook's block C text with `this boot started: Omarchy.linux-k114s-r3b`, the display check's `ok` lines and
`display-check (published): N ok, 0 BAD`, no `BAD`, the last line. The first boot after D9c also needs the greeter to come up on
the DCP card (#25): the session is the check (the T2 and T3 boots reached Hyprland through the same greeter).

**D9x. Close the window by promotion (after two clean D9 boots; nothing is put back).**

    (
    : "${K:?STOP: set K, REPO, D, R5, RT and DO first (section 3)}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    rec() { sudo sh -c 'cd /boot/efi && { sha256sum limine.conf m1n1/boot-ctxr.bin k114s-repair/k114s.dtb EFI/Linux/*.efi; sha256sum /usr/local/lib/omarchy-k114s/k114s.dtb; grep -i "^default_entry" limine.conf; grep -E "^[[:blank:]]*/" limine.conf; grep -E "^[[:blank:]]*path:" limine.conf; sed -n 1p aura-try; }'; }
    sudo test -s "$D/after-d9.txt" || stop "D9c has not run (no $D/after-d9.txt)"
    [ "$(sudo sh -c 'ls "$1"/C9-passed-* 2>/dev/null | wc -l' _ "$D")" -ge 2 ] || stop "fewer than two clean D9 boots have passed block C9 ($D/C9-passed-*): boots 3 and 4"
    sudo test -e "$D/C9-passed-$(cat /proc/sys/kernel/random/boot_id)" || stop "block C9 has not passed in this boot"
    [ "$(systemctl is-active snapper-cleanup.timer limine-snapper-sync.service snapper-cleanup.service | sort -u)" = inactive ] || stop "the snapshot sync runs (E12): block C9's stop lines first"
    rec | sudo cmp -s "$D/after-d9.txt" - || { rec | sudo diff "$D/after-d9.txt" - | grep -v -i cmdline; stop "a boot file differs from the record taken at the end of D9c (above)"; }
    sudo diff -r -q "$D/limine_history.before-window" "/boot/efi/$(cat /etc/machine-id)/limine_history" >/dev/null || stop "limine_history differs from W0's copy: block Xs first"
    echo "no boot file changed since D9c"
    sudo $K check || stop "check is not clean"
    now=$(df -B1 --output=avail /boot/efi | tail -1); [ "$now" -ge 95000000 ] || stop "ESP free is $now: below 95 MB"
    [ "$(systemctl is-enabled hibernate.target hybrid-sleep.target suspend-then-hibernate.target | sort -u)" = masked ] && case $(systemctl is-enabled suspend.target) in masked) true ;; *) sudo /usr/local/lib/omarchy-k114s/k114s-lid-sleep check >/dev/null ;; esac || stop "a sleep target is not masked, or suspend.target is not masked and the lid-sleep gate does not hold it (sudo /usr/local/lib/omarchy-k114s/k114s-lid-sleep check says why)"
    # the snapshot sync back on (E12): with the two promoted images it estimates the same skip as with aurora and r3a (78.8 % to 109.3 %)
    date +%s | sudo tee "$D/sync-restarted" >/dev/null
    sudo systemctl start snapper-cleanup.timer limine-snapper-sync.service || stop "the snapshot sync did not start: sudo systemctl start snapper-cleanup.timer limine-snapper-sync.service"
    systemctl is-active -q snapper-cleanup.timer && systemctl is-active -q limine-snapper-sync.service || stop "the snapshot sync is not active again"
    # the notices' acknowledgements belong to this window only; $D is root-only, so the glob is expanded under root (a glob in the user's shell stays a literal name and removes nothing)
    sudo rm -f "$D/sync-held" "$D/window-open"; sudo sh -c 'rm -f "$1"/N-acked-*' _ "$D"
    # F15: the stay-awake mode goes back as it was (on for this Mac: the owner's own setting since 2026-11-14), never changed beyond that
    [ "$(sudo cat "$D/idle-before" 2>/dev/null)" = true ] || omarchy-toggle-idle allow-idle >/dev/null
    [ "$(sudo cat "$D/idle-before" 2>/dev/null)" = true ] && echo "D9x: stay-awake is still on (the owner's own setting): the OLED stays lit and static, with no idle lock or panel-off; put this in the report to Jarvis as a reversible decision, recommended default omarchy-toggle-idle allow-idle"
    echo "D9 $(date -Is)" | sudo tee "$D/D9-done" >/dev/null
    echo "D9x: PROMOTED. ESP free $now; the snapshot sync runs again; the display window is closed. In a minute: D9y"
    )

Expected: `no boot file changed since D9c`, the check with `entry 3`, and `D9x: PROMOTED`. Record it in the recovery log. From here
neither block F nor block C9 is run (see C9); the stay-awake mode is as `idle-before` recorded (this Mac: on, so `omarchy-toggle-idle --status` reads `"enabled":true`; a Mac where it
was off before T3a reads `"enabled":false`).

**D9y. The sync's first run after the close left `limine.conf` alone (reads only; a minute after D9x; C5's twin).**

    (
    : "${D:?STOP: set K, REPO, D, R5, RT and DO first (section 3)}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    c=/boot/efi/limine.conf; since=$(sudo cat "$D/sync-restarted") || stop "D9x has not run"
    systemctl is-active -q snapper-cleanup.service && stop "the cleanup is still running: run D9y again in a minute"
    n=$(sudo journalctl --since "@$since" --no-pager -o cat | grep -c -F 'Updated: /boot/efi/limine.conf')
    [ "$n" -ge 1 ] || stop "no sync run since D9x yet: run D9y again after the next one (systemctl list-timers snapper-cleanup.timer); benign, nothing was changed"
    sudo journalctl --since "@$since" --no-pager -o cat | grep -E 'Stopping boot entry creation|Boot usage limit' | head -2
    sudo cmp -s $c "$D/limine.conf.after-d9" || stop "the sync's run changed limine.conf: compare it under sudo with $D/limine.conf.after-d9 (never in a shared window); do not reboot until it is read"
    [ "$(sudo grep -E '^[[:blank:]]*/' $c | tr -d ' \t' | LC_ALL=C sort | tr '\n' ' ')" = "$(printf '%s\n' /+Omarchy //linux-k114s //linux-k114s-r3b | LC_ALL=C sort | tr '\n' ' ')" ] || stop "the menu is not exactly the folder, linux-k114s and linux-k114s-r3b"
    echo "D9y: the snapshot sync ran ($n) and left limine.conf as D9c wrote it"
    )

Expected: `Boot usage limit reached ...`, `Stopping boot entry creation: Boot partition usage from ...% to ...% will exceed the 85.0%
limit.` (about 78.8 % to 109 %: the figures of the day), then the last line. The stop `no sync run since D9x yet` is benign.

### The first update after D9

Updates were paused from W1 to D9x. They resume as in P6, with these changes, and the same rule: **no reboot after an update before
U1 and block P9 pass.** What upgrades: `omarchy-dev` and `omarchy-settings-dev` and the userland. What does not: everything in
`holds.list`, now with `linux-k114s-r3b`. Three kernel packages are installed and two images exist (F8): a transaction that
rebuilds every image (systemd, mkinitcpio, firmware or cryptsetup, or a migration that calls `limine-mkinitcpio`) would try to
write `linux-aurora`'s image as well, on 110 MB free. Read the update's output for `Building UKI for` lines: more than the held
kernels' two, or `linux-aurora`, is the case U1 covers.

**U0. The pending-update check and the record before the update (the record is kept for the comparison).** It stops, before
anything is installed, when a pending package would trigger a rebuild of every image (F8): with three kernel packages and two
images that rebuild overfills the ESP. `checkupdates` works on a throw-away copy of the databases.

    (
    : "${D:?STOP: set K, REPO, D, R5, RT and DO first (section 3)}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    t=$(mktemp) && db=$(mktemp -d) && c=$(mktemp -d) || exit 1; trap 'rm -rf "$t" "$db" "$c"' EXIT
    # a throw-away database and package cache: the real ones are never written
    CHECKUPDATES_DB=$db checkupdates > "$t" 2>/dev/null; r=$?
    [ $r = 0 ] || [ $r = 2 ] || stop "checkupdates failed (exit $r): the pending set is unknown; do not run the update"
    # the triggers come from the active hooks that run mkinitcpio or limine-mkinitcpio-install (/etc/pacman.d/hooks first; a same-named /etc hook overrides the /usr one)
    seen=; tg=
    for f in /etc/pacman.d/hooks/*.hook /usr/share/libalpm/hooks/*.hook; do
      [ -e "$f" ] || continue; b=${f##*/}; case " $seen " in *" $b "*) continue ;; esac; seen="$seen $b"
      grep '^Exec' "$f" | grep mkinitcpio | grep -q -v remove || continue
      tg="$tg
$(awk 'function fl() { if (sec == "[Trigger]" && op) for (i = 1; i <= n; i++) if (t[i] !~ /^!/) print (type == "Path" ? "P " : "K ") t[i]; n = 0; op = 0; type = "" }
        /^\[/ { fl(); sec = $1; next }
        sec == "[Trigger]" && $1 == "Type" { type = $3 }
        sec == "[Trigger]" && $1 == "Operation" && $3 != "Remove" { op = 1 }
        sec == "[Trigger]" && $1 == "Target" { t[++n] = $3 }
        END { fl() }' "$f")"
    done
    trig=$(printf '%s\n' "$tg" | sed -n 's/^P //p' | sort -u | sed 's/[]+?^$(){}|.[]/\\&/g; s/\*/.*/g; s#^#^/#; s#$#$#' | paste -sd'|')
    pk=$(printf '%s\n' "$tg" | sed -n 's/^K //p' | sort -u)
    [ -n "$trig" ] || stop "no active mkinitcpio hook with a path trigger was found (/etc/pacman.d/hooks, /usr/share/libalpm/hooks): the trigger list is unknown; do not run the update"
    bad=; mig=
    for n in $(cut -d' ' -f1 "$t"); do
      fl=$(pacman -Ql "$n" 2>/dev/null | cut -d' ' -f2)
      { printf '%s\n' "$pk" | grep -q -x -F -- "$n" || printf '%s\n' "$fl" | grep -q -E "$trig"; } && bad="$bad $n"
      # shortcut: only omarchy* packages and packages that ship migrations today are read for new ones; upgrade when another package starts shipping them
      case $n in omarchy*) mig="$mig $n" ;; *) printf '%s\n' "$fl" | grep -q '^/usr/share/omarchy/migrations/' && mig="$mig $n" ;; esac
    done
    [ -z "$bad" ] || stop "these pending packages would trigger the rebuild of every image (F8):$bad. Do not run omarchy update (and do not hold them one by one); the pre-transaction hook of section 7 or the owner's decision comes first"
    # Omarchy migrations run outside pacman (no hook, no space guard sees them), and they reach a rebuild through helpers
    # (omarchy-hibernation-setup, omarchy-keyboard-toprow), omarchy-pkg-add or -drop, or pacman itself, so no pattern is enough:
    # every migration that would run (no marker in omarchy-migrate's state folder) stops U0 until the lead has read it and recorded it
    ms=${OMARCHY_MIGRATION_STATE:-$HOME/.local/state/omarchy/migrations}; badm=
    for f in "${OMARCHY_PATH:-/usr/share/omarchy}"/migrations/*.sh; do   # omarchy-migrate reads $OMARCHY_PATH/migrations and tests the marker with -f
      [ -e "$f" ] || continue; m=${f##*/}; [ -f "$ms/$m" ] && continue
      sudo cp "$f" "$D/migration-pending-$m"; sudo test -s "$D/migration-ok-$m" || badm="$badm $m"
    done
    if [ -n "$mig" ]; then
      fakeroot -- pacman -Sw --noconfirm --disable-sandbox --cachedir "$c" --dbpath "$db" --logfile /dev/null $mig >/dev/null 2>&1 || stop "the pending packages$mig could not be downloaded into the throw-away cache: their migrations are unread; do not run the update"
      for p in "$c"/*.pkg.tar.*; do
        case $p in *.sig) continue ;; esac; [ -e "$p" ] || continue
        for f in $(bsdtar -tf "$p" | grep -E '^usr/share/omarchy/migrations/.'); do
          m=${f##*/}; [ -f "$ms/$m" ] && continue
          bsdtar -xOf "$p" "$f" | sudo tee "$D/migration-pending-$m" >/dev/null
          sudo test -s "$D/migration-ok-$m" || badm="$badm $m"
        done
      done
    fi
    [ -z "$badm" ] || stop "these Omarchy migrations would run at the update and are not recorded as read (F8):$(printf ' %s' $badm | tr ' ' '\n' | sort -u | paste -sd' ' -). Do not run omarchy update. Read each (sudo cat $D/migration-pending-<name>), including the helpers it calls, any package it adds or drops and any rewrite of ~/.config/hypr/monitors.lua (P9 and U1 check the colour fix there); when it cannot rebuild every image on this Mac, record it: echo '<why it is safe here>' | sudo tee $D/migration-ok-<name>, then run U0 again"
    echo "U0: $(grep -c '' "$t") pending packages, none triggers a rebuild of every image${mig:+; the migrations of$mig were read}; every migration that would run is recorded as read"
    sudo sh -c "cd /boot/efi && { sha256sum limine.conf m1n1/boot-ctxr.bin k114s-repair/k114s.dtb EFI/Linux/*.efi; sha256sum /usr/local/lib/omarchy-k114s/k114s.dtb; sha256sum /usr/lib/asahi-boot/m1n1-ctxr.bin; grep -i '^default_entry' limine.conf; grep -E '^[[:blank:]]*/' limine.conf; grep -E '^[[:blank:]]*path:' limine.conf; sed -n 1p aura-try; } > '$D/before-update.txt'"
    sudo test -s "$D/before-update.txt" || { echo "STOP: the before-record is empty or unreadable; do not run the update"; exit 1; }
    echo "U0: before-record $(sudo grep -c '' "$D/before-update.txt") lines; ESP free $(df -B1 --output=avail /boot/efi | tail -1)"
    )

Run block P9 first; it must pass, and so must U0 (its pending-package check). Then `omarchy update` in a terminal. **Do not follow update-verify's advice to run `sudo mkinitcpio -P && sudo
update-m1n1 && sudo omarchy-mac-boot-update`**, and do not accept its reboot prompt before U1 and P9 pass. If the space guard
stops the update, nothing has changed: read the free space; do not use `allow-low-esp`.

**U1. After the update, before any reboot (reads; the one thing it may print is the fix for a returned `linux-aurora` image).**

    (
    : "${D:?STOP: set K, REPO, D, R5, RT and DO first (section 3)}" "${REPO:?STOP: set REPO first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*; do not reboot"; exit 1; }
    bash "$REPO/linux/display/k114s-dcp-colour" --check >/dev/null 2>&1 || stop "the DCP colour fix is missing or outdated in monitors.lua (an Omarchy migration rewrote it? a DCP boot would be black: bash $REPO/linux/display/k114s-dcp-colour)"
    sudo test -s "$D/before-update.txt" || stop "no before-record: run U0 before the update next time"
    sudo true || stop "sudo is not available (a failed sudo would look like a diff)"
    if sudo test -e /boot/efi/EFI/Linux/omarchy_linux-aurora.efi; then
      echo "the update rebuilt the linux-aurora image (three kernels, two images: F8). The rebuild went on, in the order of the module directories,"
      echo "past r3b's and linux-aurora's image to r3a's, which had no room beside the old one: r3a's image may be damaged. In this order, then run U1 and P9 again:"
      echo "  sudo ls -la /boot/efi/EFI/Linux                       # a half-written image or a stray .tmp file: read it first; r3a's image must be 79,420,416 bytes"
      echo "  sudo limine-entry-tool --remove-uki linux-aurora      # the window's own removal; the package stays installed and held"
      echo "  if r3a's image is missing, short or its hash differs from limine.conf: do not reboot. The rebuild command is not proven here (read limine-mkinitcpio-install first, the space the removal gave is the room it needs), or use the macOS way back (section 5)"
      echo "  then: sudo b2sum /boot/efi/EFI/Linux/omarchy_linux-k114s.efi must equal the #hash of the //linux-k114s entry's path: line (block P9 checks both), and G6: P9 lists both initramfs images"
      stop "a third image is on the ESP"
    fi
    sudo find /boot/efi/EFI/Linux /boot/efi/m1n1 -name '*.tmp' -o -name '*.k114s-new' | grep -q . && stop "a temporary file is on the ESP (an interrupted copy): $(sudo find /boot/efi/EFI/Linux /boot/efi/m1n1 -name '*.tmp' -o -name '*.k114s-new' | tr '\n' ' ')"
    sudo sh -c "cd /boot/efi && { sha256sum limine.conf m1n1/boot-ctxr.bin k114s-repair/k114s.dtb EFI/Linux/*.efi; sha256sum /usr/local/lib/omarchy-k114s/k114s.dtb; sha256sum /usr/lib/asahi-boot/m1n1-ctxr.bin; grep -i '^default_entry' limine.conf; grep -E '^[[:blank:]]*/' limine.conf; grep -E '^[[:blank:]]*path:' limine.conf; sed -n 1p aura-try; }" | sudo diff "$D/before-update.txt" -
    r=${PIPESTATUS[1]}
    case $r in 0) echo "no boot file changed" ;; 1) echo "the diff above is the change: only new hashes of the two images and their path: lines are expected (a rebuild); the Stage 2, the pins, m1n1-ctxr.bin and default_entry must not appear" ;; *) stop "the before-record could not be read or compared (diff exit $r)" ;; esac
    echo "ESP free: $(df -B1 --output=avail /boot/efi | tail -1)"
    echo "U1: no third image, no stray file. Now block P9 (it checks every hash and the menu); then reboot and run block F and block C9 if D9x has not run, otherwise P9 and the display check of C9's note (boot-ctxr.bin must still be the display file)"
    )

Expected: `no boot file changed` or a diff of only the two images' hashes and `path:` lines (a rebuild changes both), `ESP free` about 110
million, the last line. Then block P9. A `STOP: a third image` is the F8 trap, which U0 should have prevented: the fix is printed. Read `ls -la` first: if the two promoted
images' sizes and hashes are unchanged (P9 checks), the removal alone is enough; if r3a's image is short or its hash differs, rebuild it
and re-verify it as printed before any reboot (r3a is `default k114s` from macOS). A changed image hash after a legitimate rebuild is
expected, and P9 then re-checks G6 on it: an initramfs with `appledrm` stops everything before the reboot (F16).

### The abandon path: close the window without promoting

If D9 does not run (a failed gate, or the owner's decision), the first window's close applies with this window's `D`:
C1b (the trial file off the ESP), C2b (remove r3b.b1), block X (the `linux-aurora` image and entry back), C4 and C5. The configured
files were never written. Put the idle mode back as well (F15): `[ "$(sudo cat /var/lib/k114s-recovery/display-d5/idle-before)" = true ] || omarchy-toggle-idle allow-idle`, and remove the notices'
acknowledgements so a later window cannot reuse them: `sudo sh -c 'rm -f "$1"/N-acked-*' _ /var/lib/k114s-recovery/display-d5` (the folder is root-only, so the glob must be expanded under root).

**C1b. The trial Stage 2 file off the ESP (its copy stays in `$D`).**

    (
    : "${D:?STOP: set K, REPO, D, R5, RT and DO first (section 3)}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    h() { sudo sha256sum "$1" 2>/dev/null | cut -c1-64; }
    [ "$(sudo sed -n 1p /boot/efi/aura-try)" = spent ] || stop "aura-try does not read spent: a trial is armed; nothing was changed"
    f=boot-ctxr-disp-bl.bin
    if sudo test -e /boot/efi/m1n1/$f; then
      [ "$(h /boot/efi/m1n1/$f)" = "$(h "$D/$f")" ] || stop "m1n1/$f differs from its copy in $D; it stays on the ESP"
      sudo rm /boot/efi/m1n1/$f && sudo sync -f /boot/efi || stop "m1n1/$f was not removed"
    fi
    sudo ls /boot/efi/m1n1 | LC_ALL=C sort | sudo cmp -s "$D/m1n1.before-window" - || stop "m1n1/ is not as before the window: $(sudo ls /boot/efi/m1n1 | tr '\n' ' ')"
    echo "C1b: the trial Stage 2 file is off the ESP; ESP free $(df -B1 --output=avail /boot/efi | tail -1)"
    )

**C2b. Remove `linux-k114s-r3b` (its package stays in `$D`).** Run C2b, X and C4 back to back.

    (
    : "${K:?STOP: set K, REPO, D, R5, RT and DO first (section 3)}" "${D:?STOP: set D first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    c=/boot/efi/limine.conf; REL=7.3.0-17.v272-11-k114s-r3b-ARCH; GPU=9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc
    [ "$(uname -r)" = 7.3.0-17.v272-4-k114s-r3a-ARCH ] || stop "remove r3b from a boot of r3a, never from r3b itself; nothing was changed"
    pacman -Q linux-k114s-r3b >/dev/null 2>&1 || stop "linux-k114s-r3b is not installed; nothing to remove"
    sudo test -s "$D/linux-k114s-r3b-7.3.0.r3b.b1-1-aarch64.pkg.tar.zst" || stop "the package is not kept in $D; nothing was changed"
    [ "$(systemctl is-active snapper-cleanup.timer limine-snapper-sync.service snapper-cleanup.service | sort -u)" = inactive ] || stop "the snapshot sync runs (E12): block C's stop lines first; nothing was changed"
    grep -q -x 'export M1N1_UPDATE_DISABLED=1' /etc/default/update-m1n1 || stop "update-m1n1 is not off; nothing was changed"
    [ "$(sudo sha256sum /boot/efi/m1n1/boot-ctxr.bin | cut -c1-64)" = $GPU ] || stop "boot-ctxr.bin is not P's file (D9c ran? use the undo of D9c first); nothing was changed"
    [ "$(df -B1 --output=avail /boot/efi | tail -1)" -ge 88080384 ] || stop "below the space guard's minimum: C1b first; nothing was changed"
    sudo pacman -R --noconfirm linux-k114s-r3b 2>&1 | sudo tee "$D/remove-r3b.log" | grep -E '^(:: |\(|warning|error)|Removed|Updating|update-boot-ctxr'
    pacman -Q linux-k114s-r3b >/dev/null 2>&1 && stop "linux-k114s-r3b is still installed (pacman's message is above)"
    sudo test -e /boot/efi/EFI/Linux/omarchy_linux-k114s-r3b.efi && stop "the r3b image is still on the ESP: do not reboot; read $D/remove-r3b.log"
    [ -e /usr/lib/modules/$REL ] && echo "info  /usr/lib/modules/$REL is left (files pacman did not own): sudo rm -r it once read"
    [ "$(sudo sha256sum /boot/efi/m1n1/boot-ctxr.bin | cut -c1-64)" = $GPU ] || stop "boot-ctxr.bin is no longer 9825a103...: do not reboot"
    sudo cmp -s $c "$D/limine.conf.after-window" || stop "limine.conf is not the file W1 left (compare under sudo, never in a shared window); block X will refuse: a Snapshots entry is block Xs, anything else the P5b rebuild"
    sudo $K check || stop "check is not clean; do not reboot"
    echo "C2b: r3b removed; limine.conf is as W1 left it; boot-ctxr.bin rewritten byte for byte. Now block X"
    )

Expected: as the first runbook's C2.

### 4a. Colour management and the black panel (found in boot 1, 2026-11-15)

**Finding.** On every boot where the display coprocessor (DCP, `appledrm`) drove the panel, the desktop was black until
Hyprland's colour management was turned off (`render:cm_enabled = false`). The connector reported `Colorspace BT2020_RGB` while
colour management was on (agent-run read). `modetest` test patterns in `XR24` and `AR24` lit the panel (owner-observed), so
the hand-off, the scanout and the panel were fine; and the desktop with `cm_enabled = false` lit it too (owner-observed).
Brightness writes had reached the panel all along: the D5 ladder read back correctly (agent-run) and the owner saw the panel
dim and recover (owner-observed), so "black" was never a zero-brightness panel. Root cause: Hyprland's colour-management
path (monitor preset `edid`) produced all-black frames on this panel. **Evidence label: owner-observed for the picture,
agent-run for the connector property; the Hyprland-side mechanism is not read in source and stays unknown.**

**Correction to this runbook's start.** T2 (the first window's hand-off) was **agent-checked only**: its checks read the
device tree, the loader log, the kernel log, the connector and the compositor's state, and the owner never saw its picture. The
first line of this document and F5 call T2 "passed" for the hand-off, which stays true for what those reads prove; they could
not show a black picture, and the black screens seen afterwards were not a failed hand-off.

**The fix** is `linux/display/dcp-colour.lua`, added to `monitors.lua` by `linux/display/k114s-dcp-colour` (user session, no
sudo; the script does not reload, but Hyprland may reload `monitors.lua` by itself when it changes, because `misc:disable_autoreload` is
off, and the setting is certain to apply at its next start):

    if os.getenv("ASAHI_M5_BRINGUP") == "1" then
      hl.config({ render = { cm_enabled = false } })
      hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 2, cm = "srgb" })
    end

The second line is a second finding of boot 4: Hyprland warned "wide color gamut is enabled but the display is not in 10-bit
mode". Omarchy's `default/hypr/wide-gamut.lua` wraps `hl.monitor` on Apple Silicon and gives every rule without a `cm` the preset `edid`, and
the driver's EDID has zero primaries, so the rule names `cm = "srgb"` (which the wrapper keeps). A later `hl.monitor` for the same
output replaces the earlier rule, so the rule in the block wins on a DCP boot and the simpledrm boots keep the plain one.

`ASAHI_M5_BRINGUP=1` is printed by the user-environment generator `60-aurora-m5-display` only when
`/dev/dri/by-path/platform-display-subsystem-card` exists, so on a simpledrm boot the line does nothing. Install:
`bash "$REPO/linux/display/k114s-dcp-colour"`. It is idempotent, keeps the file as it was in `monitors.lua.k114s-dcp-colour.bak`
(first install only), replaces a changed block, and prints where it wrote. Check: `--check` (exit 0 when the block is there and
equal). Undo: `--undo` removes only the marked block and leaves the backup: a fix written by hand in the same file (the root's own, tonight)
is not removed by it, so run the installer instead of adding a second block by hand. **On this Mac** the hand-edited line is the eDP-1 rule itself, `hl.monitor({ output = "eDP-1", ..., cm = "srgb" }) -- K114s DCP...`, and the I0 check counts it as one of the two eDP rules (T3a checks for both): do not delete it, put it back to the plain I0 rule, `hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 2 })` (remove `, cm = "srgb"` and the trailing comment), then run the installer. The installed block then holds the `cm = "srgb"` rule, which wins on a DCP boot.
**After this is merged, on the live Mac (user session, no sudo):** edit that line as above, then `bash "$REPO/linux/display/k114s-dcp-colour"`; `--check` must exit 0 before the next P9 or U1, which stop on a block that is missing or outdated (the live file has the older block without the `hl.monitor` line). `sudo bash "$REPO/linux/display/k114s-greeter-colour" --check` already passes for the hand-installed greeter state. T3a, T4a,
D9a, C9, P9 and U1 stop when `--check` fails (nothing armed, nothing written; C9 writes no marker). P9 and U1 are there because an Omarchy
migration rewrote `monitors.lua` once; U0's stop message says to look for migrations that rewrite it.

**The SDDM greeter has the same guard.** The greeter's Hyprland (`start-hyprland-m5 -- --config /usr/share/sddm/hyprland.lua`) gets
`ASAHI_M5_BRINGUP=1` on a DCP boot too, and `cm_enabled` stays at its default there. `linux/display/k114s-greeter-colour` (root) writes
`/etc/sddm/hyprland-k114s.lua`, a copy of the stock file plus the guard, and points `/etc/sddm.conf.d/70-k114s-greeter-software.conf` at it
(`sudo bash "$REPO/linux/display/k114s-greeter-colour"`; `--check` needs no root; `--undo` points the conf at the stock file again and removes the
copy; the first-install conf is kept as `<conf>.k114s-greeter-colour.bak`). The conf must exist (`linux/gpu-desktop/`). The copy goes stale when an
`omarchy-settings-dev` update changes the stock file: `--check` then fails, and P9 stops on it (sudo bash the installer again). Autologin hides the greeter
today; the greeter on a DCP boot has not been looked at (**unknown**, owner-pending).

**Boot 1 results (2026-11-15, T3, kernel r3b.b1, with the fix).**

| Item | Result | Label |
| --- | --- | --- |
| Desktop on the DCP at 3024x1986, 120 Hz | seen | owner-observed (picture), agent-run (mode read) |
| T3b | 22 ok, 0 BAD | agent-run |
| D5 ladder | read back; the owner saw the panel dim and recover | agent-run, owner-observed |
| D7 DPMS off and on, three times | panel went off and woke each time | owner-observed |
| D8 night light on and off | no DCP crash line | agent-run |
| Look: colours, text, movement | colours normal, text sharp, movement smooth | owner-observed |
| Notch | covered some text: the cutout overlay (patch 0003) is now installed; not looked at again yet | owner-observed, then unknown |
| G6b | **stopped**: an initramfs built from this boot (`mkinitcpio -k 7.3.0-17.v272-11-k114s-r3b-ARCH`) contains `appledrm`, which blocks D9 (F16) | agent-run |

### 4b. What actually ran on 2026-11-15 night (the record, as the lead wrote it)

- **Boot 2 (T4, D6) did not run.** The repeated T3 boots (22:45 and 23:04, and the probe boots before them) were clean boots of the brightness
  tree, so the lead wrote `T4-booted` as the equivalent (`echo "T4 booted <time> equivalent: repeated T3 boots" | sudo tee $D/T4-booted`; D9a
  needs that file and nothing else from T4). **D6 was skipped**: the block could not read `vrr_capable` from sysfs on this kernel (fixed above: it
  is the KMS connector property, read with `modetest -M apple -c`), and the lead wrote `D6-skipped` on purpose (D9a accepts `passed`, `failed`
  or `skipped`; D9c then puts the VRR mask back). VRR stays deferred and the mask stays in.
- **D9 promoted after boots 3 and 4.** Boot 3: the default `r3b.b1` on the configured display Stage 2, block F ok, C9 clean; P9 as first written
  stopped on the glob bug (fixed above); with it fixed P9 held and the display check showed 18 ok, 0 BAD. Boot 4: C9 clean, P9 holds, `D9x` printed
  `PROMOTED` and closed the window (the snapshot sync is back; the `N-acked-*` files were removed under root).
- **Found on the night and fixed here**: the P9 glob (the root-only `EFI/Linux` folder), D9x's and the abandon line's `N-acked-*` glob (issue #135),
  D6's sysfs `vrr_capable`, the greeter's missing colour guard (installed by hand, now `k114s-greeter-colour`), the `cm = "edid"` gamut warning (now
  `cm = "srgb"` in the managed block), and the colour fix gone from `monitors.lua` after a migration (P9 and U1 now check it).

### 4c. After the window, 2026-11-16: the colour default and D6 (the owner at the Mac)

- **Colour management (4a, closed).** With r3b.c1 (`docs/r3-hdr.md`, section 7) the panel EDID has Display P3 primaries and
  `k114s-cm-trial edid`, `dp3` and `srgb` with colour management on all stayed lit with normal colours (owner-observed). The
  managed block of `k114s-dcp-colour` now turns colour management **on** with the eDP-1 preset `dp3` (the owner's choice).
  P9 and U1 still run `k114s-dcp-colour --check`, which now checks for that block. The greeter keeps its guard (off).
- **D6 (VRR): failed, the DCP crashed.** Run in a default boot of r3b.c1, not through T4a (the window is closed, so there was no
  one-shot and no `aura-try`): the mask file was moved into `$D/aurora-m5-vrr.conf.masked`, one reboot (owner watching), then the
  D6 block. The boot itself was clean (`fw27_panel_vrr` Y, `vrr_capable` 1, the DCP's `set_digital_out_mode ... vrr:1`) and the
  brightness ladder passed again (agent-run). Turning `misc:vrr` on in Hyprland made the panel go black at once (owner-observed).
  The kernel log (agent-run; kept root-only as `$D/D6-dcp-crash-*.log`): `VRR_ENABLED 1: selecting "3024x1986": 120 ...` at the
  first VRR swap, then half a second later `DCP has crashed` and `a reboot is required to restore the display`;
  Hyprland fell back to its 1920x1080 `FALLBACK` output; `set_digital_out_mode timed out`; `IOMFB transaction timed out
  ... pending IOMFB A463`. The block wrote `D6-failed` (its own stop line names the empty `vrr` read that followed the
  crash). **The mask is back** (`options appledrm fw27_panel_vrr=0`) and a reboot restored the panel, so VRR stays masked on
  this Mac; D9's rule (the mask follows D6) holds. VRR on the K114s OLED needs a driver change first: the opt-in path
  (betizzel series patch 0014, `fw27_panel_vrr`) was tested upstream on the J714s LCD only.

## 5. Ways back

Each step's undo is next to it. The first runbook's section 5 holds for every state it names (the window layouts are the same).
New or changed:

**From Linux:**

| Layout | Back |
| --- | --- |
| After D9p | its undo line |
| After I1b or S5 | C1b, C2b, then block X, then C4 |
| T3 or T4 armed, not booted | `sudo $K clear`; if `aura-try` reads `armed`: `sudo sed -i 1s/armed/spent/ /boot/efi/aura-try && sudo sync -f /boot/efi`; after T4a also the mask: `sudo cp -p /var/lib/k114s-recovery/display-d5/aurora-m5-vrr.conf.masked /etc/modprobe.d/aurora-m5-vrr.conf` |
| After D7b | `cp -p ~/.config/omarchy/shell.json.bak.d7 ~/.config/omarchy/shell.json` |
| After D9c, Linux answers | the undo of D9c, reboot (r3a on P), block C |
| D9 abandoned after boots 3 or 4 | the undo of D9c, then the abandon path (C1b needs no file: the trial copy is already off; C2b, block X, C4) |

**From macOS** (Startup Options, Terminal in the repair bundle folder, the changed tool and `promotion/boot-ctxr-gpu.bin`,
`promotion/k114s.dtb.gpu` from M9):

- **The configured display Stage 2 hangs before the kernel, or the panel never lights, and Linux does not answer** (boots 3 and 4;
  the next boot is the same): `sudo ./k114s-repair stage2 r3-gpu`. It writes P's Stage 2 over the display file and P's tree
  over the pin, the whole file, loader bytes included, checked against `9825a103...` and `2c870ba9...`. Then `sudo
  ./k114s-repair status` (`Stage 2 (boot-ctxr):   r3-gpu (GPU tree, not in this bundle)`) and boot Linux: r3b.b1, the new
  default, on P's Stage 2, a configuration T1 proved. In Linux: the undo of D9c (it finds P's Stage 2 already there and puts the
  Linux pin and `default_entry` back), and `m1n1-ctxr.bin` removed. `stage2 r1` also works from the display state.
- **The r3b.b1 kernel is the suspect** (it boots and hangs, or Limine fails to start it): `sudo ./k114s-repair default k114s`
  (r3a, entry `Omarchy/linux-k114s`); add `stage2 r3-gpu` if the Stage 2 is also in doubt. r3a on the display Stage 2 has
  **never been booted**; use both together.
- **Both kernels or the images are the suspect**: `restore-repair` needs 111.8 MB plus the 8 MiB reserve and there is no
  `linux-aurora` image to remove, so first mount the EFI volume read-write (`sudo diskutil mount <the EFI volume>`, the identifier from `diskutil list`),
  `sudo rm /Volumes/EFI/EFI/Linux/omarchy_linux-k114s-r3b.efi` (its entry stays, dangling) and `diskutil unmount <the EFI volume>`
  (the tool mounts and unmounts the ESP by itself, so it must not be mounted when it runs), then `sudo ./k114s-repair stage2 r3-gpu` (the static repair kernel was proven on P's file at P1c, not on the
  display file), then `restore-repair --check` and `restore-repair` (replica: `tests/macos/test-promoted-esp.sh`).
- **Never from macOS:** `rollback all`, `rollback stage2`, `kernel`, `apply`, `default original`, `default aurora` (no image).

**Not counted as a way back** (untested): `module_blacklist=appledrm` or `nomodeset` after a published hand-off; r3a or the
repair kernel on the display Stage 2; the macOS tool on the real D9 layout (M9 proves the command on today's layout, the replica
case on the D9 layout).

## 6. A hang or a black screen: which boot comes next

If the Mac still answers over T3 or ssh, use the first runbook's black-T2 note first (a clean reboot keeps the loader log).
Otherwise hold the power button until the Mac is off, start it, and run block F first on an r3b boot (block C on an r3a boot, block
C9 on a D9 boot), then block P (P9 after D9c), then the row:

| Trial | The fallback boot is | How to tell | Then |
| --- | --- | --- | --- |
| T3 or T4, hang before Limine | r3b.b1 on P: the one-shot was still pending | `uname -r` is r3b, no `aurora,trial`, `status`: `this boot started: Omarchy.linux-k114s-r3b` | the first runbook's T1b-D1 (`--expect none`; `uname -v` reads `K114S-R3B-B1`): this is D5a. If it passes, the loader's path on the brightness tree is the suspect: report it, stop |
| T3, hang or black after Limine | r3a on P | `uname -r` is r3a | block C, then the first runbook's block A (it reads the T3 boot's journal; the release string is r3b's). A display-path failure after `Switching root`: the brightness tree or kernel; otherwise the D5a-alone boot (the one-shot with P's Stage 2: `sudo $K arm Omarchy/linux-k114s-r3b`, reboot, block F, T1b-D1) |
| T3, a picture but a `BAD` or a DCP crash line in D5, D7 or D8 | reboot normally: r3a on P | | block C; record `D5 FAILED` / `D7 FAILED` / `D8 failed`; D5 and D7 block D9, D8 does not |
| T4, hang before Limine or black after it, and T3 passed | as above | | the masked retry: put the mask back (`sudo cp -p $D/aurora-m5-vrr.conf.masked /etc/modprobe.d/aurora-m5-vrr.conf`), run T3a's checks, arm again (one boot): if that passes the unmasked boot is the suspect: `D6-failed`, the mask stays |
| T4, a picture but D6's VRR stop | reboot normally | | `D6-failed` (the block wrote it); D9c puts the mask back |
| D9 boot 3, hang before Limine | the same configuration again (Stage 1 reads the configured file) | | macOS, section 5 |
| D9 boot 3 or 4, black after the kernel started, Linux answers over T3 | | | run block F and block C9 remotely (the logs survive), then the undo of D9c, then `sudo systemctl reboot` |
| T3 or T4 (boot 1 or 2): no 'booted' report by N's deadline, the Mac does not answer | the owner (or Jarvis's reminder) holds the power button until it is off, then starts it | | the rows above, from the first |
| D9 boot 3: no report by N's deadline | power off the same way | | the next boot is the same configuration: macOS, section 5 (Jarvis tells the owner or the macOS agent) |
| Any boot stops at the Limine menu | the keyboard does not work there: power off | | macOS, section 5 |

## 7. Next

D9 leaves open: the owner's look at the pending items in `$D/owner-look.txt`; whether `systemd-backlight` restore is turned on
(`docs/r3-brightness.md`, "The first write": `restore-enabled` plus one `systemctl start`, after the owner has seen the ladder);
the lock-screen and idle timing; HDR (#92); the pre-transaction hook for the rebuild trap (F8: it refuses a rebuild-all while kernel module directories with `modules.builtin` outnumber the images on the ESP; until it ships, U0 holds every update whose pending packages hit a trigger, and every Omarchy migration that would run until the lead has read it; the hook would see a migration's pacman transaction but not a direct or helper call of `limine-mkinitcpio`); the K114s report to TripleU613 and the
linux PR with the K114s display section (plan section 11); and `hyprland-m5 0.57.2-3` (H of the first runbook, a log-out, not
yet run).

## 8. Risks the owner should know

- **The promoted layout has three kernel packages and two images (F8).** A full-rebuild transaction (systemd, mkinitcpio,
  firmware, cryptsetup, or an Omarchy migration that calls `limine-mkinitcpio`) would write `linux-aurora`'s image as well, on about
  110 MB of free space, and the space guard cannot see it. What a failed copy leaves is unknown. U0 prevents it for the packages it
  can see (`checkupdates`, the trigger lines of the active mkinitcpio hooks; a trigger file that a new package version adds and the
  installed one lacks is not seen) and for the migrations that a pending Omarchy package brings (downloaded to a throw-away cache and
  read; a package that starts shipping migrations only in the new version, and is not named `omarchy*`, is not seen). A pending
  package that hits a trigger waits for the pre-transaction hook of section 7 or the owner's decision (no `omarchy update` until
  then). A migration waits until the lead has read its gate and recorded it (`$D/migration-ok-<name>`). The orphan-package and AUR steps
  of `omarchy update` are not read by U0 (F8); U1 and P9 catch what they do. Every migration that would run stops U0 until the lead has read it, because migrations reach a rebuild through
helpers and through packages they add or drop. The planned pre-transaction hook would see a migration's pacman transaction, not a
direct or helper call of `limine-mkinitcpio`. **Owner option, not taken:**
  removing the `linux-aurora` package (after keeping its package file and image copy in `$D`) would make two kernel packages match
  the two images and remove the trap itself. U1
  and P9 are the net if one slips through: a third image or a stray file stops everything before the reboot, and the fix rebuilds
  and re-verifies r3a's image too. A rebuild that damages r3a's image (the macOS `default k114s` target) before U1 runs is the worst
  case.
- **G6 is no longer held by the boot (F16).** After D9 every boot has the display subsystem, so a rebuild can put `appledrm` into
  an image. The `/etc/mkinitcpio.conf.d/99-k114s-no-appledrm.conf` drop-in (G6a) keeps it out of every build; G6b proves a build from a display-tree
  boot with it before D9; D9a and P9 check it is installed and P9 lists both images in every check. A package update that replaces `/etc` files
  or a build run with `-c` would bypass the drop-in, and the image listing in P9 is the net. An image with `appledrm`
  has never been booted and could hang before the root filesystem.
- **Unattended trial boots can hang hard.** Boots 1 to 3 have no software watchdog on this Mac. Boots 1 and 2 fall back by a power-button
  hold; boot 3 by macOS. The deadline lives with Jarvis (N) because a hung Mac cannot report itself; if the notice is not
  acknowledged the boot is not armed.
- **The idle guard (F15) keeps an OLED awake and possibly static for the whole window** (hours, in the worst case). The runbook's dark
  theme and the first-window screensaver advice limit it; D9x and the abandon path put the mode back as it was before T3a. **The owner
  has had stay-awake on since 2026-11-14, so after D9 the OLED stays lit and static** (no screensaver, no lock, no DPMS-off) at 500
  nits, and D7b's idle profile does not act. The owner can run `omarchy-toggle-idle` to allow idle.
- **A failed D8 leaves a click that could crash the DCP.** Night light stays one click away on the promoted default; a `D8-failed`
  writes the owner's README line and the report to Jarvis, nothing guards the toggle.
- **`Alt` + brightness-down passes `1%-` on the eDP, which could ask for 0.** Only patch 0006's floor (a request below
  `apple,min-brightness` is raised to 10 nits) holds it; C9's `--floor` checks the log line in every boot, D5 proves the script path, not the key path.
- **After D9c there is no cheap way back from a hang before the kernel.** The Stage 2 is configured; every boot takes the
  hand-off. The way back is macOS (`stage2 r3-gpu`), which needs the owner (or the macOS agent) at the Mac. M9 proves the command on
  today's ESP before D9c, and the replica test proves it on the D9 layout. If the kernel is up and the panel is dark, Linux
  answers over T3 and the undo of D9c is a Linux step.
- **r3a and the repair kernel on the display Stage 2 have never been booted.** r3a is the fallback kernel only on P's Stage 2.
  The macOS way back therefore puts P's Stage 2 back first.
- **The agent cannot see the panel.** Brightness following, black versus dim, warmth and flicker are owner-observed and stay
  pending until reported (F5). A panel that does not follow brightness writes (nobody has published a K-board OLED result) would
  leave 500 nits on a static desktop: the idle profile (60 and 120 seconds) and the lock's DPMS-off are the mitigation once the owner has allowed idle, and
  DPMS-off is dim, not black, until the owner says otherwise.
- **The brightness ladder writes through `brightnessctl`, which asks logind.** If the agent's session is not allowed, D5's first
  write fails and nothing was changed; the block names the retry from a desktop terminal.
- **0 nits is not black** (plan section 10): until D7's look says so, use a shutdown instead of an idle screen for long breaks.
- **The pin loader boots a configured Stage 2 for the first time at D9.** By then it has booted three times through `aura-try`
  (T2 on the D4 tree in the first window, T3 and T4 on the brightness tree), always the same loader bytes.
- **`/usr/lib/asahi-boot/m1n1-ctxr.bin` is an untracked file in a package-owned directory.** A package that rewrites the directory
  wholesale would drop it; P9 and U1 check it, and without it a Stage 2 hook run would write the installed loader's file.
- **The first update after D9 can touch the boot chain.** See U0 and U1; the held set is unchanged apart from `linux-k114s-r3b`.
- **Suspend stays blocked.** Closing the lid locks the session and nothing more.

## 9. Tests and evidence

Agent-run on 2026-11-15, as a normal user (sudo for reads only), nothing installed, nothing written outside the repository
worktree and the scratch folders:

| Test | Result | Label |
| --- | --- | --- |
| `bash tests/linux/run-r3.sh` | `r3 update tooling: 1462 passed, 0 failed, 0 test file(s) skipped` | emulator/replica |
| `tests/linux/test-display-d5-d9-runbook.sh` (new; it is in `run-r3.sh`) | `display d5-d9 runbook tests: 204 passed, 0 failed` (the night-of-2026-11-15 repair added, each failing on the old form: P9 lists a root-only `EFI/Linux` under sudo; D9x removes the acknowledgements in a root-only `$D`; D6 reads `vrr_capable` with `modetest` (the fake has no sysfs file); U0 reads `$OMARCHY_PATH/migrations` and counts a marker only if it is a regular file; P9 and U1 stop without the colour fix, P9 without the greeter guard or a drop-in that lost its `dcp_fabric_core` line; lints for the globs and for D6. The G6 repair added: G6a installs the drop-in through the installer and is idempotent; G6b stops before any build without the drop-in or with one that is not the repository's file, and a pass removes an earlier `G6b-failed`; D9a and P9 stop without the drop-in. The third round added: U0 stops on every migration that would run until it is recorded as read, with helper, package-drop and unmarked-installed cases; D9x removes the notices' acknowledgements and reports stay-awake to Jarvis; D9c's printed line says STOP. The second repair round added: root-only scratch folders for G6b and P9 (the fake sudo closes a `sudo mktemp -d` folder to the plain user, with a test that the old form fails and a lint); U0's migration reading and its recorded-gate release, and its trigger regex built from replica hook files (an /etc override, a second hook, a remove-only hook); N's `N-acked-<boot>` refusal in T3a and T4a and D9c's printed line; the stay-awake mode already on (idle-before true) kept by T3a and D9x. The first repair round added: a D5 ladder whose read-back differs and a D5 write that fails each stop D5 and write no `D5-passed`; the locked-session stops of D5, D7, D8 and D6; T3a's stay-awake mode and its refusal; G6b's pass, its `appledrm` failure and its no-eDP stop; D9a's refusal without `G6b-passed`; P9's G6 on every image; D9x's idle restore; U0's pending-package stops; U1's r3a-image lines). Cuts the blocks D9p, I1b, S5, T3a, T3b, D5, D7, D7b, D8, G6a, G6b, T4a, T4b, D6, D9a, D9c, the undo of D9c, P9, C9, D9x, D9y, U0, U1, C1b and C2b out of this file, and the first runbook's P, W0, W1, X, F, C, C4 and C5 out of that one, and runs them against the fake Mac of `display-fake-lib.sh` with this window's record folder. Covered: the first window's folder is never written; I1b installs version `7.3.0.r3b.b1-1` with G3 and G6 and refuses the older package, a wrong hash, a full rebuild and `appledrm` in the initramfs; S5 and both arms (the one-shot, `aura-try`, the mask, the reboot scheduled with `systemd-run` and never `systemctl reboot`); every STOP of the arms (no gates, no mask, no drop-in, restore turned on, a wrong trial file, a missing `eDP-2` rule); T3b and T4b after block F with `--floor` and `--vrr on`, and refused before F, on the wrong kernel, with a `BAD`, with no trial; D5 (the ladder `500 250 100 50 20 10 20 50 100 250 500`, the Omarchy steps `500 450 400 450 500`, no write below 10 nits, none of 0 or 1000, the start level back; no floor line, an unmoving step, another scale, a `BAD` stop it), D7 (three cycles; a panel that does not wake, a DCP crash line), D7b (the profile, the copy, bad JSON), D8, D6 (the failed-marker, the watchdog counted, VRR off again); D9a with the real Stage 2 hook run in a throw-away root against fake loaders and trees, which must write the D9 file byte for byte (and, without the pin loader, must not); D9c (the Stage 2, the pins, the loader file, `default_entry`, the holds, the chain text, the mask by D6's outcome, the records), its undo, and its refusals (no D9a, an unexpected kernel, the sync running, a `limine.conf` that is not I1b's, a half-run); P9 (a third image, a missing `m1n1-ctxr.bin`, a missing hold, a wrong Stage 2); C9 and D9x after one and two clean boots, D9y, U0 and U1 (a returned `linux-aurora` image, a stray temporary file, a rebuilt image); the abandon path to `no boot file changed`; every block parses with `bash -n`, no block writes 0 to the backlight, no block prints a `limine.conf` line that could hold the command line. about 45 seconds in a quiet run (the fake `sleep` makes the blocks' waits instant) | emulator/replica |
| `tests/linux/test-initramfs-no-appledrm.sh` (new; it is in `run-r3.sh`) | `initramfs no-appledrm tests: 21 passed, 0 failed` (`apple_pmp` only through its MODULES entry now, and a host check that mkinitcpio never resets `_addedmodules`; the installer's install, second run, replacing a different file, `--undo`, a foreign file kept, an unknown argument, no root; the drop-in against a fake `add_module` with the same early return as mkinitcpio's: `appledrm` and `dcp_fabric_core` out, the rest and a MODULES entry in; sourced without the associative table under `set -u` it does nothing; and two reads of this host's mkinitcpio that the mechanism still holds) | emulator/replica |
| `tests/linux/test-dcp-colour.sh` (in `run-r3.sh`) | `dcp colour tests: 18 passed, 0 failed` (install, idempotence, backup, undo, `--check`; the block's eDP-1 rule is `cm = "srgb"` and another preset is not 'installed'; the snippet under a Lua stand-in only acts with `ASAHI_M5_BRINGUP=1`) | emulator/replica |
| `tests/linux/test-greeter-colour.sh` (new; in `run-r3.sh`) | `greeter colour tests: 17 passed, 0 failed` (install into a throw-away root, idempotence, the stock file untouched, a changed stock file makes `--check` fail, an edited copy or a conf that no longer points at it is not installed, `--undo` restores the conf bytes, no conf or no stock file refuses). Not run on the real greeter: it has not been looked at on a DCP boot | emulator/replica |
| a real throw-away `mkinitcpio -g` build, kms hook only, with and without the drop-in, in a scratch folder (as a normal user, `MKINITCPIO_CONF` instead of `-c`) | 159 modules and `appledrm.ko` plus `dcp-fabric-core.ko` without it; 154 and neither with it (also gone: `mux-apple-display-crossbar`, `atc-t6050-dp` and, in that kms-only config, `apple-pmp`, which the real configuration's MODULES entry adds back); exit 0 both times | seen on hardware (board) |
| `tests/linux/test-display-trials-runbook.sh` (now sharing `display-fake-lib.sh`) | `display trials runbook tests: 108 passed, 0 failed` (unchanged by the split) | emulator/replica |
| `tests/hardware/test-display-check.sh` | `display-check test: 34 passed, 0 failed` (`vrr_capable` read with `modetest`, unreadable is BAD; 10 earlier: `--floor` on the brightness build, on the D4 build and tree, a dropped floor and callback 590; `--vrr on` on an unmasked boot, on a masked one, with Hyprland's vrr true; an unknown `--vrr`) | emulator/replica |
| `tests/brightness/test-backlight-check.sh` | `# backlight-check replica: 0 failed` (30 `ok` lines; 8 new for `--auto`: the ladder from 500 and from 40 nits, the start level back, a read-back that differs stops and puts 500 back, a failing write never tries the maximum, nothing above the start or below 10, a reported level below the floor starts at the floor, a TERM mid-ladder puts the start level back) | emulator/replica |
| `tests/macos/test-promoted-esp.sh` | `macOS tool (promoted ESP) tests: 138 passed, 0 failed` (103 in the first window's D0; 35 new for the D9 layout: status names the display Stage 2, `stage2 r3-gpu` writes the bundle's file and tree byte for byte over the loader bytes and touches nothing else, refuses a changed file, a changed tree, a missing file, the real hashes against synthetic files, an unknown live file; a rebuilt display file reads as the pin loader with another tree and rolls back; `stage2 r1` and `default k114s` from the display layout; `default aurora` and `restore-repair --check` as in the window; the tool's constants against the promoted hashes and, when the build area is here, against the built loader and the D5 Stage 2) | emulator/replica |
| `tests/macos/test-no-original-uki.sh` | `macOS tool (no original image) tests: 24 passed, 0 failed` | emulator/replica |
| `tests/macos/test-r2c-fat.sh`, `tests/macos/test-macos-tool.sh` | not run: they need macOS (`hdiutil`) or the assembled bundle | not run |
| `build/check-publishable.sh` | `check-publishable: ok (432 files)` | agent-run |
| `release-display-d5/stage2/boot-ctxr-disp-bl.bin` and `pkg/...r3b.b1-1...` | `90b35137...` (4,506,159 bytes) and `0ca7b759...`, as listed in `SHA256SUMS`; not rebuilt here | agent-run |
| `sudo ls -la` of the first window's `display/` folder and `/boot/efi/k114s-repair/promotion`, `/boot/efi/m1n1`, `df` of the ESP, `/etc/omarchy-k114s`, `/usr/lib/asahi-boot`, `holds.list`, `/etc/pacman.conf` | the record names the layout this runbook starts from: ESP free 111,022,080; `m1n1/` holds `boot.bin`, `boot.bin.old`, `boot-ctxr.bin`, `boot-ctxr-r3a.bin`, `boot-ctxr-r3-gpu.bin`; `/usr/lib/asahi-boot` holds `m1n1.bin` and `u-boot-nodtb.bin` only; the macOS tool on the ESP is 53,529 bytes; `holds.list` has 22 names; `IgnorePkg` lines 7 and 12 | agent-run (reads) |
| source reads: `iomfb.c:51-61, 2140, 3735-3765`, `iomfb_template.c:3860-4200`, `dcp.c:1575-1600` (the VRR parameter and the swap watchdog), `limine-mkinitcpio-install:66-126` (rebuild-all), `update-boot-ctxr-k114s` (`m1n1-ctxr.bin`), `plugins/lock/Service.qml:740-790` (the lock's DPMS-off), `omarchy-brightness-display`, `omarchy-toggle-nightlight` | the claims of F3, F7, F8, F9 | source-read |

Not verified: anything that boots; that `brightnessctl` may be run by the agent's session (the first write of D5 says so); whether the panel follows
a brightness write, DPMS-off is black, night light warms the picture or VRR flickers (owner-observed, F5); what a rebuild-all that runs out of space leaves
on the ESP (F8); the macOS tool on the real D9 layout (M9 runs it on today's layout, the replica on the D9 layout); `limine-entry-tool --remove-uki
linux-aurora` after a rebuild that wrote that image (U1 names it; it is the window's own removal, which W1 ran on the real ESP); the D9 Stage 2 as the
configured file (it has run three times through `aura-try`).
