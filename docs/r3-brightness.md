# K114s panel brightness: the r3 work item

Tracking issue: #2. Branch `r3/brightness`. State on 2026-11-14, running kernel
`7.3.0-17.v272-4-ARCH` (K114S-R1). Companion documents: `docs/brightness-boot-stage.md` (what sets
the level today, and the macOS test) and, on branch `r3/display-gpu`, `docs/r3-display-gpu.md`
(the display coprocessor candidate this depends on).

Evidence labels: **owner-observed** (the owner saw it on this Mac), **agent-run** (a command or a
source read on this Mac), **emulator/replica** (our code run against a stand-in), **upstream**
(someone else's report, on their hardware). **Nothing about K114s brightness is owner-observed
yet, and nothing here is "working".**

## Short answer

- Today the panel is the boot framebuffer. Linux has no brightness control for it and cannot get
  one: the OLED has no backlight controller of its own, so the only route is the display
  coprocessor (DCP). The keys do nothing because there is nothing for them to drive.
- Once display-gpu's candidate puts the panel on the coprocessor, the kernel that is already
  running has the driver code: a backlight device `apple-panel-bl`, in nits, 0 to the panel's
  user maximum, should appear with **no backlight-specific kernel patch**, and Omarchy's keys and
  slider should drive it with **no Omarchy change**. "100 %" is then the panel's user maximum as
  Apple's device tree states it (1000 nits on the K116s; the K114s value is not read yet).
- Whether the OLED panel follows the level is unproven. Nobody has published a brightness write on
  any K-board OLED. The owner's test below would be the first result.
- This branch adds: four upstream patches that are not needed for the device but clean up the
  OLED path, a floor of our own so that no brightness write can darken the panel, the
  device-tree line for it, a stepped hardware check with an automatic way back, and an optional
  dimming-only stopgap for today.

## Mechanism

### Today (boot framebuffer)

Apple's boot stage lights the panel at one level and hands Linux a plain framebuffer
(`simpledrm`, connector `Unknown-1`). Neither the loader nor Linux can change the level; details
and sources are in `docs/brightness-boot-stage.md`.

### After the hand-off to the coprocessor (source reading of the running kernel's tree)

1. The loader (display-gpu's rebuilt Stage 2) reads the user maximum from this machine's Apple
   device tree (ADT), `/backlight-override` `user-accessible-max-nits`, and writes it into the
   Linux device tree as `apple,max-brightness` on the panel node. Without that ADT value it
   refuses the whole hand-off and the panel stays on the boot framebuffer.
2. The kernel's coprocessor driver reads the panel node at probe. A panel with a width and a
   maximum becomes an eDP connector.
3. The backlight device is created by a work item: after the firmware reports the level the boot
   stage set, or, if no report comes, 2 s after the first mode set. In the second case the device
   reads half the maximum until the first write, whatever the panel really shows, and the kernel
   logs `no loader brightness reported; backlight starts at N nits without a panel change`.
4. A write to `/sys/class/backlight/apple-panel-bl/brightness` is a level in nits. The driver
   shows the current picture again with the level attached to it (there is no separate
   "set brightness" call). The first write jumps; later ones fade over 250 ms. The firmware's
   completion of that present is what `actual_brightness` then reports.
5. Display off (DPMS) presents 0 nits and keeps the pipe running; display on presents the level
   again.

Nothing in the driver is specific to OLED or to mini-LED apart from one flag, which decides only
whether the firmware's panel-temperature request is answered (patch 0001 below answers it for
every panel).

## What is proven, and where

| Statement | Evidence |
| --- | --- |
| The brightness keys reach Linux as `KEY_BRIGHTNESSUP` / `KEY_BRIGHTNESSDOWN` | agent-run (the lead, 2026-11-14; not re-run for this document) |
| `/sys/class/backlight` is empty; the only DRM driver is `simple-framebuffer`, connector `Unknown-1`; the tree's `dcp` nodes are disabled | agent-run (`linux/brightness/k114s-backlight-check --read-only`, `/proc/device-tree`) |
| Omarchy's keys and slider need a monitor named `eDP-*` and a kernel backlight device, prefer `apple-panel-bl`, never ask for less than 1 %, and write through `brightnessctl` | agent-run (read of the installed scripts and shell; `linux/brightness/README.md`) |
| The running kernel's source registers `apple-panel-bl` for a T6050 panel on firmware 27 and carries the level in nits in each present; it already contains the J714s brightness fixes (linux #1659, #1674) | agent-run (source read; the kernel's own 27 backlight test cases pass when compiled for the host) |
| The loader writes `apple,max-brightness` only when the tree has none, from the ADT, and refuses the hand-off without the ADT value | agent-run (read of display-gpu's loader branch, `src/kboot_display_handoff.c`) |
| The six patches here apply with `git am` to the running kernel's source, alone and on top of display-gpu's ten; patches 0001 to 0004 are diff-identical to their upstream commits (`git patch-id`) | agent-run |
| With all sixteen applied, every object of `drivers/gpu/drm/apple` compiles with the running kernel's configuration (clang 23.1.3), and the test objects compile with the KUnit option on. No module was built, nothing was loaded | agent-run |
| The floor (patch 0006): a request below it becomes the floor, display off still presents 0, a loader level below it stays until the first request | emulator/replica (`tests/brightness/run-dcp-backlight-host.sh`: 28 cases pass; the new case fails with the floor line removed). Not run under KUnit, not on hardware |
| `dts/t6050-k114s-brightness.dtsi` compiles into display-gpu's r3 tree and adds exactly one property | agent-run (cpp + dtc 1.8.1, decompiled diff) |
| The hardware check script never writes 0 or a level below its lowest, and puts the last confirmed level back on no answer, on "hard to read" and on a signal | emulator/replica (`tests/brightness/test-backlight-check.sh`, 15 checks) |
| J714s (same SoC, mini-LED, firmware 27.0 and 27.3): brightness through `apple-panel-bl` follows writes, "confirmed visually, not inferred from sysfs", with power readings at several levels | upstream (betizzel; DjDeveloperr in linux #1659 and #1674) |
| K116s (OLED, firmware 27.2, the sibling of this Mac): the panel runs on the coprocessor; the loader prints a scale of 1000 nits; the firmware logged a level of 0 at suspend and about 101 nits at resume | upstream (Jens Axboe, aura #226, linux #1647 and #1648 comments). No brightness write and no by-eye check published |
| K114c (OLED, firmware 27.3): "`/sys/class/backlight` has a device"; "Not confirmed yet: a lit panel and brightness"; later "Not measured: absolute brightness" | upstream (joshuaswarren, linux #1816, #1873) |
| An OLED panel changes its light when a brightness write arrives | nobody, anywhere we searched |
| Anything about brightness on this K114s with the panel on the coprocessor | not yet: needs the owner's boot of the candidate |

## Dependency on the display coprocessor candidate

Everything after "Today" needs branch `r3/display-gpu` to work on this Mac first: its rebuilt
loader (K114s admission, the 27.2 hand-off), its kernel series (`patches/linux/display-gpu`, ten
patches, among them the 120 Hz-only mode gate without which a mode set can crash the coprocessor
and every brightness write then returns an I/O error), and its device tree
(`dts/t6050-k114s-display-gpu.dtsi`, which creates the panel node). This branch adds to those
and replaces none of them. If the hand-off does not happen, this branch changes nothing visible:
the panel stays on the boot framebuffer at the boot level.

Two facts that decide the outcome live only in this Mac's ADT, which Linux exposes to root as the
MTD device `adt` (display-gpu's `tests/k114s-adt-display-facts.py` prints them; it needs `sudo`,
so it is the lead's or the owner's to run):

| ADT value | Why it matters | Known |
| --- | --- | --- |
| `/backlight-override` `user-accessible-max-nits` (16.16 fixed point) | becomes `apple,max-brightness` and `max_brightness`: what 100 % is. Missing: no hand-off at all | K116s: 1000. K114s: could not determine without root |
| `/backlight` `LmaxProduct`, `EDRPotentialHeadroom` | panel peak and HDR headroom, read by the kernel itself; HDR only | K114s: could not determine. The kernel logs `panel peak luminance N nits (ADT)` when the peak is above the user maximum |

The same values can be read from macOS (`ioreg -p IODeviceTree -r -n backlight-override`; not
run).

## Kernel patches (`patches/linux/brightness`)

`git format-patch` form, original authors kept, each naming its upstream commit. Base: the
running kernel's source (aurora-silicon/linux `a34d26c255c2` + betizzel's 27.2 series + pull
request 1568), with or without display-gpu's series. **None of them is needed for the backlight
device to exist**; upstream has nothing further that is (linux #1696, the open "firmware 27
presents no longer dropped" pull request, changes nothing on this SoC: its first commit is for
the M5's T8142 only, and the case its second commit handles is already handled on firmware 27 by
#1674, which is in our base).

| Patch | Source | What it changes for this Mac | Tested by its author on | On a K114s |
| --- | --- | --- | --- | --- |
| 0001 answer the PMU temperature for every panel, quiet the TAOC fallback | linux #1646 (open), `50db17f86f92`, Jens Axboe | The OLED firmware asks for a temperature for its panel compensation and today gets "false" (it logs `failed to read PMU temperature property!`). With this it gets the battery temperature. **A behaviour change in what the firmware is told.** Also moves a once-a-second firmware log line to debug | K116s OLED, 27.2 | hardware-untested |
| 0002 apply the syslog debug filter to the internal panel's DCP | #1646, `8847a289036a`, Jens Axboe | makes the log filter of 0001 take effect on the internal panel | K116s | hardware-untested |
| 0003 take the 27.2 D590 notification as a no-op | #1646, `907bb7ec5990`, Jens Axboe | stops an "unknown callback" warning after every present on 27.2 | K116s | hardware-untested |
| 0004 don't warn on a brightness change left pending while the panel is off | linux #1887 (merged), `629e81bc2dd6`, Ryan Murray | removes a false `brightness change still pending at suspend` warning | MacBook Neo | hardware-untested |
| 0005 dt-bindings: optional panel brightness floor | ours | documents `apple,min-brightness` | nothing | hardware-untested |
| 0006 hold brightness requests at the panel's floor | ours | a brightness request below `apple,min-brightness` is raised to it, and the device reads the raised level back. Display off, blanking and suspend are untouched. No property, no change | host test only | hardware-untested |

Recommendation to the lead: take 0004 to 0006 with the device-tree fragment. Take 0001 to 0003 as
well unless the first coprocessor boot should carry the fewest possible differences from what
Jens booted; whether his K116s display result was obtained with or without them could not be
determined (he wrote them on that machine). Without them expect the temperature error twice and
one log line a second, neither known to affect brightness.

To check the series again (nothing is written to shared trees; `~/k114s-build` is the build area
on this Mac):

    cp -a --reflink=auto ~/k114s-build/src/r1 ~/k114s-build/src/brightness-try && cd ~/k114s-build/src/brightness-try
    git am <display-gpu worktree>/patches/linux/display-gpu/*.patch    # optional
    git am <this worktree>/patches/linux/brightness/*.patch
    <this worktree>/tests/brightness/run-dcp-backlight-host.sh .      # 28 cases, 0 failed

## Device tree

Brightness needs these on the internal `dcp` node's `panel` child:

| Property | Value | Source | Who provides it |
| --- | --- | --- | --- |
| `compatible` | `"apple,panel-k114", "apple,panel"` | upstream K116s tree (linux #1648); not `apple,panel-mini-led` | display-gpu's dtsi |
| `width-mm`, `height-mm` | 302, 198 | computed from the panel's pixel pitch (display-gpu); a panel without a width gets no backlight | display-gpu's dtsi |
| `apple,max-brightness` | this Mac's ADT value, whole nits | **only this machine's ADT**; never written in a tree of ours, because the loader keeps a value the tree already has and would then ignore the machine's own | the loader, every boot |
| `apple,min-brightness` | `<10>` | ours: a first value, not a measured one (1 % of the K116s scale) | `dts/t6050-k114s-brightness.dtsi` |

To use the fragment, add one line at the end of display-gpu's `dts/t6050-k114s-r3.dts`:

    #include "t6050-k114s-brightness.dtsi"

A kernel without patches 0005 and 0006 ignores the property. With them the kernel logs
`brightness requests below 10 nits are raised to 10 nits` at probe.

## Omarchy

Nothing is needed once `apple-panel-bl` and `eDP-1` exist; `linux/brightness/README.md` has the
piece-by-piece reading. Short form: the platform file already prefers `apple-panel-bl`, the
scripts accept an `eDP-*` monitor, `brightnessctl` writes through logind without any rule, and
`systemd-backlight` keeps the level across restarts.

## The floor

Requirement: no brightness write may leave the panel dark without a way back.

- **Kernel (patch 0006 + the fragment):** no request can reach the panel below 10 nits. `echo 0`
  reads back 10. This is the only layer that covers every writer.
- **Omarchy:** keys and slider stop at 1 % (10 nits on a 1000-nit scale) on their own.
- **systemd:** the level restored at boot is at least 5 % of the maximum.
- **The check script:** confirms each lower step with the owner before the next, and puts the
  last confirmed level back when no answer comes.

What the floor does not prove: that 10 nits is visible on this panel. Nobody has reported any
level on an OLED K-board, so 10 is a first value. If the check shows a higher level is the lowest
readable one, raise `apple,min-brightness` to it; if 10 is comfortably readable and the owner
wants darker, lower it. Display off still goes fully dark by design; its way back is display on
(any key or pointer movement), then a brightness key, as below.

## The owner's hardware test (first boot with the panel on the coprocessor)

No `sudo` anywhere. Have this page open on another device. Keep the maximum step short on a
static screen (OLED). Optional, before starting: a second way in (for example `sshd`, off on this
Mac today; turning it on is a root step and the owner's choice).

**If the screen is dark or unreadable at any point**, in this order:

1. If the check script is running: do nothing for 20 seconds. It puts the last confirmed level
   back.
2. Press Shift + brightness-up (Omarchy's 100 %), or brightness-up several times.
3. Move the pointer or press a key (in case the display was only switched off), then step 2 again.
4. Blind: Super + Return opens a terminal; type `brightnessctl -d apple-panel-bl set 50%` and
   Enter.
5. Hold the power button until the Mac is off, start it again. The kernel keeps no level across
   a restart; systemd writes back the saved one, never below 5 % of the maximum.
6. If the panel is still unreadable after a restart, go back to the last boot-framebuffer
   candidate the way the candidate's bundle notes describe (from macOS if need be): on the boot
   framebuffer the level is the boot stage's and Linux cannot touch it.

**Steps:**

1. What the kernel registered (reads only):

       linux/brightness/k114s-backlight-check --read-only

   Expected: `type / scale  platform / linear`; `max_brightness N nits` with the same N from the
   device tree (K116s: 1000; the K114s value is not known, write down what it is);
   `kernel floor 10`; `connectors` contains `eDP-1`; `display drivers` is `apple-drm`.
   `brightness` is either the level the boot stage set or exactly N/2.
   If the device is missing the script says what it found instead.

2. The kernel's side of it:

       journalctl -k -b --no-pager | grep -iE 'apple-dcp|dcp@|backlight|brightness|powerlog|AFK\[ep:20\]|present dropped|PMU temperature'

   Fine: `brightness requests below 10 nits are raised to 10 nits`;
   `no loader brightness reported; backlight starts at N nits without a panel change` (then the
   first write may make the picture jump); `panel peak luminance N nits (ADT)`.
   Report: `Missing property 'apple,max-brightness'`, `present dropped: ... brightness maximum 0`
   (every frame is then dropped: the loader did not write the maximum),
   `Unable to register backlight device`, `backlight registration failed`,
   `failed to extract init props` on `AFK[ep:20]`.

3. The stepped check (about three minutes). It asks after each level what you see:

       linux/brightness/k114s-backlight-check

   Expected if the panel follows: "same" or a jump at the first write, "brighter" at the maximum,
   "darker" at each step down to 10 nits, all readable; `actual_brightness` equal to each level
   written. Paste the result file it names into the issue. If every answer is "same", the device
   exists but the panel does not follow: that is the upstream-level finding, see the end of this
   section.

4. The keys and the slider: brightness-down and brightness-up step by 5 % with Omarchy's bar on
   screen; Shift + brightness-up is 100 %; Shift + brightness-down is 1 %; the display panel's
   slider moves the same level. `omarchy brightness display` prints the percentage.

5. The floor, only after step 3 confirmed 10 nits readable. The first line puts 50 % back after
   15 seconds whatever happens:

       ( sleep 15; brightnessctl -q -d apple-panel-bl set 50% ) &
       brightnessctl -q -d apple-panel-bl set 0; cat /sys/class/backlight/apple-panel-bl/brightness

   Expected: `10`, and a readable picture.

6. Display off and on:

       omarchy-brightness-display off; sleep 5; omarchy-brightness-display on

   Expected: dark for five seconds, then the same level as before. If it stays dark, use the list
   above from step 2.

7. After the next restart: the level is the one from before the restart
   (`systemctl status 'systemd-backlight@backlight:apple-panel-bl'`).

Record on issue #2, as owner-observed: N, the result file, the log lines of step 2, and for steps
4 to 7 what happened.

If the device appears but the panel does not follow writes, no local patch is the next step. It
means the OLED firmware wants the level some other way than the mini-LED firmware does, and the
way to learn it is a trace of macOS 27.2 changing brightness on an OLED K-board. Until then
"100 %" depends on the boot stage (next section).

## Stopgap for today

There is no brightness control today. Two things exist, both the owner's choice:

- **For a brighter panel:** set the brightness to maximum in macOS with automatic adjustment off,
  shut down, start Omarchy. Upstream says the boot stage lights the panel at the level macOS
  keeps in NVRAM; that was tested on LCD models only, so **whether it works on this Mac is not
  known**. `docs/brightness-boot-stage.md` has the two-pass procedure that finds out without
  risking a dark panel. Nothing is written from Linux.
- **For a dimmer picture:** `linux/brightness/interim/` (software dimming through the
  compositor). It can only go below the boot level, it is not yet run on this Mac, and it is not
  installed; `linux/brightness/README.md` lists the exact files and destinations.

## Open questions

- The K114s `user-accessible-max-nits`, and whether the property exists at all: could not
  determine (needs root or macOS).
- Whether the OLED 27.2 firmware changes the panel's light when a present carries a level: could
  not determine. This is the question the owner's test answers.
- What 0 nits looks like on this panel (black, or a firmware minimum), and whether 10 nits is
  readable: could not determine. The floor and the check are built so that neither has to be
  found out the hard way.
- Whether the firmware reports the boot stage's level on this SoC with 27.2, or the device starts
  at half the maximum: could not determine. Upstream says firmware 27 "generally" announces that
  service without the data the driver needs (linux #1683).
- Whether the full user maximum is held on a static picture or limited by the firmware
  (temperature, average picture level): could not determine.
- Whether the alpha behaviour reported for the K114c under the coprocessor (linux #1873: a low
  alpha byte shows as about half brightness) affects perceived brightness here: not examined; the
  image's `hyprland-m5` writes alpha.
- HDR: the kernel reads the panel peak from the ADT and has an EDR path that can exceed the user
  maximum for HDR content. Untested on any OLED and out of scope here.
- Whether the boot stage applies the macOS level on this model (the stopgap above): could not
  determine.

## For whoever owns `docs/matrix.md`

Suggested wording for the "OLED brightness" row: the K116s "1000 nits" is the loader's scale
maximum, not a fixed level; the driver path is already in the running kernel and needs the
display coprocessor row first; K114c reports a backlight device with brightness unconfirmed;
status "candidate prepared on `r3/brightness`, hardware-untested".
