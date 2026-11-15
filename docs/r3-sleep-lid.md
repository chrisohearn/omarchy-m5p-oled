# r3: suspend, resume and the lid on the K114s

Written 2026-11-14 from a session on the K114s itself, without root. **None of the patches or
device trees here has been booted on a K114s.** The patches compile and the device trees build; no
suspend was attempted on this Mac.

Evidence labels used below:

- **agent-run**: a command the AI agent ran on this Mac on 2026-11-14 (read-only).
- **source-read**: read in the kernel or Omarchy source that is installed here; not run.
- **upstream report**: what another owner reported for their board. One machine each.
- owner-observed: none yet for this subsystem.

## Short version

- Today a lid close does nothing, and any suspend the kernel is asked for is refused.
- Three kernel patches admit the K114s to suspend-to-idle with Wi-Fi up. Three more make the
  built-in panel an `eDP` connector while it is still the boot framebuffer, which is what lets
  Omarchy lock and suspend on a lid close.
- Both groups are independent of the display coprocessor and GPU work and can be tested first.
- Two further groups do nothing until other r3 work turns hardware on, and are then required
  before any suspend: the PMP power domains (with sound) and the GPU mailbox change (with the GPU).
- One patch is not about sleep: it stops the battery's uevent from failing.
- It is suspend-to-idle only. Everything stays powered. There is no deep sleep on firmware 27.2
  and hibernation is off in this kernel.

## What the machine does today

Read on the running system: kernel `7.3.0-17.v272-4-ARCH` (K114S-R1), device tree r1, package
`omarchy-dev 4.0.0.r7859.g9ac0883-1`, systemd 262.

### Kernel

| Fact | Value | Evidence |
| --- | --- | --- |
| Sleep states | `/sys/power/state`: `freeze mem`; `mem_sleep`: `[s2idle]` only | agent-run |
| Suspends since boot | `suspend_stats`: success 0, fail 0 (nobody has tried) | agent-run |
| Idle | `Apple: idling in WFI, ignoring idle=nop`; cpuidle driver `apple_idle` | agent-run |
| Hibernation | `PM: hibernation: disabled on this platform: coprocessor firmware state is not restored from an image` | agent-run |
| PCIe | `pcie-apple 1cb0000000.pcie: adopted port 0, endpoint 01:00`: the loader trained the N1 link | agent-run |
| N1 functions | `01:00.0` (`apple_centauri_t6050`), `01:00.1` (no driver of its own), `01:00.2` (`btcentauri_t6050`), root port `00:00.0` (`pcieport`); all in D0 | agent-run |
| Suspend check | `apple_pcie_check_adopted_s2idle()` returns `-EBUSY` unless the machine is `apple,j716c` or `apple,k114c`. This one is `apple,k114s` | source-read |
| Lid switch | input device `Apple SMC power/lid events` reports `SW_LID`; `macsmc-input` is a wakeup source | agent-run |
| Other wakeup sources | the SMC, the keyboard and trackpad transport (`294b30000.input`), battery, charger, both USB controllers | agent-run |
| RTC alarm | no `wakealarm` on `rtc0`: `rtcwake` cannot be used to end a test sleep | agent-run |
| Panel | `simpledrm` on the loader's framebuffer; connector `card0-Unknown-1`; Hyprland output `Unknown-1`, 3024x1986, scale 2 | agent-run |
| Battery | `cat /sys/class/power_supply/macsmc-battery/uevent` prints nothing; `manufacture_year` reads "Operation not supported"; 30 `driver failed to report 'manufacture_year' property: -95` lines in the first five minutes of this boot (the kernel suppresses more), plus `failed to send synthetic uevent: -95`. At the same moment sysfs said `Charging`, 97 % and UPower said discharging, 92 %; the failing uevent is the likely reason, not confirmed | agent-run |

So a suspend request would run the whole suspend path and then fail in the PCIe host's noirq
callback. Expected, not run: `suspend_stats` fail +1, `failed_suspend_noirq` +1,
`last_failed_dev` `1cb0000000.pcie`, `last_failed_errno` -16, `last_failed_step` `suspend_noirq`,
and the session comes back after about a second.

### Omarchy and logind

| Trigger | What is configured | What happens on this Mac today |
| --- | --- | --- |
| Lid close | Hyprland binding `switch:on:Apple SMC power/lid events` runs `omarchy-system-lid-close`: lock if the lid is shut and no external monitor is connected, then `omarchy-hyprland-monitor-clamshell`. logind: `HandleLidSwitch=suspend`, `HandleLidSwitchDocked=ignore` | **Nothing.** `omarchy-hw-external-monitors` counts every connected connector that is not `eDP`, `LVDS` or `DSI` as external, so `Unknown-1` is "an external monitor": no lock. `omarchy-system-lid-inhibit` holds a block inhibitor on `handle-lid-switch` ("External display in use") for the same reason, so logind does not suspend. `systemd-inhibit --list` shows it held (agent-run). The session stays unlocked and running under the closed lid |
| Idle | `omarchy-shell` idle service: screensaver after 150 s, lock after 300 s, then `omarchy-brightness-display off` (Hyprland DPMS off). logind `IdleAction=ignore` | No idle suspend, by design. DPMS off on `simpledrm` clears the framebuffer to black (source-read) |
| Menu "Suspend", `systemctl suspend` | logind, after `omarchy-sleep-lock.service` has locked (delay inhibitor, `InhibitDelayMaxSec=15`) | Would lock, then fail in the kernel as above. Refused outright while any application holds a block inhibitor on `sleep` (one did during this read: a tool that keeps the machine awake while agents work) |
| Power button, moon key | `HandlePowerKey=ignore`, `HandleSuspendKey=ignore` | Nothing |
| Hibernate | menu entry hidden unless set up | Not available: off in the kernel |

## What changes

### Kernel patches (`patches/linux/sleep-lid/`, in order)

| # | Change | Upstream state and test | Needed when | State here |
| --- | --- | --- | --- | --- |
| 0001 | PCI: admit the K116s to s2idle over the loader-trained N1 link (#1647, `aa16d423`, Jens Axboe) | open. K116s: "One s2idle cycle with Wi-Fi up, lid close/open, 18.5 s asleep: `suspend_stats` success 1, fail 0" | carrier for 0003 | built |
| 0002 | PCI: below a port Linux trained itself, only devices on the awake path must stay in D0 (#1647, `70bf8ed1`, Jens Axboe, narrowed by Thomas Glanzmann) | open. K116s on this head: 1 success / 0 fail, "every device back in D0 and Wi-Fi rejoined" | the K116s SD port. The K114s tree has no such port, so every device must be in D0, as before | built |
| 0003 | PCI: admit `apple,k114s` beside the K116s (**ours**, 6 lines) | not upstream. Never run | **now**: without it every suspend is refused | built |
| 0004 | simpledrm: an `eDP` connector for a framebuffer node with `apple,internal-panel` (#1688, `1006491a`, ed) | open draft. J714c (author's kernel): "the panel is card0-eDP-1 ... closing the lid locks the Omarchy session". Not booted in the #1688 form | **now**, while the panel is the boot framebuffer | built |
| 0005 | The property on the shared K114/K116 framebuffer node (#1688, `76c5ea39`, Joshua Warren) | open draft, compile check only | with 0004 | built |
| 0006 | Binding for the property (#1688, `67e63a57`) | open draft | documentation only | applied |
| 0007 | Battery: an unreadable manufacture date returns `-ENODATA`, which the power-supply core skips (#1615, `089b082f`, Joshua Warren) | open draft. "Not yet booted on the M5" | **now**; not a sleep fix | built |
| 0008 | Device tree: the three PMP power domains always on (#1789, `f61eb455`, Jens Axboe) | open. K116s: PMP crashed at wake "in 3 of the 4 suspends" without it; with it "19 s2idle cycles in total" over 26 boots and "no PMP crash or RTKit crash line after any resume", one of them an hour long | once the PMP nodes are enabled (sound) | dtb built |
| 0009, 0010 | Mailbox: the T6050 GPU mailboxes receive by interrupt, pollers removed (#1844, `41c359da`, `788441e0`, Erik Bourget, Diljit Singh) | merged. K116s, lid open, GPU active: before, "never wakes, 2 of 2" (panic in the noirq phase, #1843); with it "18.1 s asleep, woken by a key, `suspend_stats` success 1" | once the GPU nodes are enabled | built |

"built" means the object compiled with the running configuration and clang 23.1.3 at `W=1`
without a warning: `pcie-apple.o`, `simpledrm.o`, `macsmc-power.o`, `mailbox.o`. No full kernel
was built or booted for this branch.

Why 0003 is expected to be right (source-read plus upstream report, not hardware):

- The K114s and K116s 27.2 Apple device trees are identical node for node; the r1 tree describes
  the same host, the same port 0 and the same three N1 functions as the K116s tree.
- This Mac logs the same adoption line as the K116s and binds the same drivers. The two N1
  drivers save their PCI state in their suspend callbacks without leaving D0
  (`centauri_t6050_suspend()`, `cen_suspend()`), and the PCI core then leaves the root port in D0
  as well; that is the state the check asks for.
- The K114s tree has no second port, so it takes the strict path (every device in D0), the one
  the J716c and K114c take.

Two cases stay refused, by design (source-read):

- The N1 drivers are not loaded. Nothing then keeps the root port in D0, the check fails and the
  log says `adopted link requires accessible D0 devices for s2idle`. Nothing in Linux can retrain
  that link, so refusing is the safe answer.
- The Wi-Fi firmware has not finished booting, or failed to. `centauri_t6050_suspend()` returns
  `-EBUSY` until its boot phase is ready; `last_failed_dev` is then `0000:01:00.0`.

### Device tree (`dts/t6050-k114s-sleep.dtsi`)

Four properties, written as overrides so they hold on a kernel tree without 0005 and 0008:

- `apple,internal-panel` on `/chosen/framebuffer@0`;
- `apple,always-on` on `ps_pms`, `ps_pmp`, `ps_pms_sram`. They are `status = "disabled"` in the
  K114s tree today (agent-run: `/proc/device-tree`), so this does nothing until the PMP is
  described.

`dts/t6050-k114s-r1-sleep.dts` is r1 plus this fragment and nothing else, for testing sleep before
the display work. The loader keeps unknown properties on the framebuffer node: it fills and renames
the existing node (source-read, `kboot.c`).

### What it changes for the desktop

Once the connector is `eDP-1` (source-read, Omarchy scripts as installed):

1. `omarchy-hw-external-monitors` is false, the lid inhibitor is not taken, and a lid close locks
   the session and suspends through logind. Opening the lid wakes to the lock screen.
2. **A lid close suspends even while agents are working.** logind's
   `LidSwitchIgnoreInhibited` defaults to yes: a block inhibitor on `sleep` stops the menu and
   `systemctl suspend`, not the lid. Today the lid does nothing, so long-running work survives a
   closed lid; after this change it is frozen until the lid opens. If that is not wanted, the
   choice is `LidSwitchIgnoreInhibited=no` in a logind drop-in. That is the owner's decision; it
   is not part of this change.
3. **The Hyprland output is renamed from `Unknown-1` to `eDP-1`.** The owner's
   `~/.config/hypr/monitors.lua` has a rule for `Unknown-1` with `scale = 2` (agent-run). It will
   stop matching and the panel falls back to Omarchy's default, `scale = "auto"`. Add the same
   rule for `eDP-1` before the first boot of this tree; a rule for an output that does not exist
   yet is inert:

   ```lua
   hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 2 })
   ```

   The display coprocessor work renames the output the same way, so this is needed for r3 anyway.
4. Brightness keys: no change. There is no backlight device either way.
5. Omarchy's clamshell and internal-monitor scripts now find a laptop panel. With no external
   output possible on this tree they have nothing to switch.

### What suspend is on this machine

- Suspend-to-idle: tasks frozen, devices suspended, CPUs in WFI. Coprocessors, NVMe, Wi-Fi and the
  panel electronics stay powered.
- On the boot framebuffer the panel is not turned off. `simpledrm` disables its plane on suspend,
  which clears the framebuffer to black (source-read); on an OLED that should leave the pixels
  dark. On the J714s (LCD) the same path "leaves the panel lit" (betizzel/omarchy-m5 status).
  Whether the closed K114s panel is dark is for the owner to look at (test 5).
- Power: the only figure is the K116s with its display coprocessor driven, "3.6-3.9 W over 24
  minutes against about 5.1 W awake idle" (upstream report). Expect hours of standby, not days,
  and less saving than that while the panel is the boot framebuffer.
- Wake: a key, the trackpad, the power button, opening the lid, plugging in power. Not by timer.

## Which pieces stand alone and which depend on other r3 work

| Piece | Without display/GPU work | With it |
| --- | --- | --- |
| 0001-0003 | Safe and sufficient for the kernel to accept a suspend. Only this host's suspend check changes | Still required |
| 0004-0006 + `apple,internal-panel` | Safe: only the connector's type. Take it together with 0001-0003, or every lid close locks and then fails to suspend | Inert once the display coprocessor owns the panel: `apple-drm` replaces `simpledrm` and names the connector `eDP-1` itself (K116s: "eDP-1 connected at 3472x2170") |
| 0007 | Safe, independent | Same |
| 0008 + `apple,always-on` | No effect: the domains are disabled | **Required in the same build that enables the PMP** (sound). Without it expect `PS pms: Failed to reach power state` at suspend and a PMP crash at wake |
| 0009-0010 | No effect: no `ascwrap-v6` mailbox is bound today (agent-run: the five bound mailboxes are all `apple,t6050-asc-mailbox`) | **Required in the same build that enables the GPU.** Without it a suspend with the lid open panics in the noirq phase and looks like a machine that never wakes |

What the other work must not assume from this: the suspend path through the display coprocessor
(blank at suspend, modeset at wake) and through the GPU has only the K116s reports behind it.
After display, GPU or sound land, tests 2 to 8 below have to be run again.

Upstream commit `e0120892` ("drm/asahi: g17: refuse a sleep the commit can't stop") was read and
left out: by its own message it concerns the firmware-driven sleep of the A18 Pro, not s2idle.
`983f9c65` (rtkit-helper, unanswered AP idle notice) was read and left out for the same reason:
the notice is only sent for a firmware-driven suspend (source-read).

## Overlap with other r3 branches

`r3/display-gpu` also carries #1688's first two commits and both #1844 commits. They are the same
upstream commits (same patch-id). On its kernel branch 0004, 0005, 0009 and 0010 are already
present and the other six apply cleanly (agent-run, `git apply --check`). `patches/linux/sleep-lid/series`
marks the four shared files.

## Test plan for the owner

Needs: a kernel built with the series, booted with `t6050-k114s-r1-sleep.dtb` (or the r3 tree with
`t6050-k114s-sleep.dtsi` included), and the `eDP-1` rule from above already in `monitors.lua`.
Mains power connected for tests 1 to 8. Save open work first.

`tests/hardware/k114s-sleep-check.sh` runs the steps and prints a PASS or FAIL line. Its `pm-test`
and `cycle` modes write to `/sys/power` directly, so logind, inhibitors and the lock screen are
not involved and agents may keep running (they are frozen for the duration).

| # | Do | Expect |
| --- | --- | --- |
| 0 | Optional, on **today's** kernel, before anything is installed: tests 2, 3 and 4 | 2 and 3 PASS; 4 FAILs as described there. That confirms the diagnosis on hardware and shows that every driver's suspend and resume callbacks run cleanly up to the PCIe check. It carries the same risk as picking Suspend from the menu today |
| 1 | `tests/hardware/k114s-sleep-check.sh status` | `connector: eDP-1 connected`; no `handle-lid-switch` line under block inhibitors; `battery uevent lines:` above 0; `suspend_stats: success=0 fail=0`. Also `journalctl -b -k \| grep -c manufacture_year` prints 0, and the desktop is at its usual scale |
| 2 | `sudo tests/hardware/k114s-sleep-check.sh pm-test freezer` | Returns after about 5 s. `RESULT: PASS (success 0 -> 1, fail stays 0)` |
| 3 | `sudo tests/hardware/k114s-sleep-check.sh pm-test devices` | Screen goes black for about 5 s and comes back. `PASS (success 1 -> 2 ...)` |
| 4 | `sudo tests/hardware/k114s-sleep-check.sh pm-test platform` | As 3. This level runs the noirq phase, where today's kernel refuses. `PASS (success 2 -> 3 ...)`. On the r1 kernel the same command is expected to FAIL with `last_failed_dev=1cb0000000.pcie last_failed_errno=-16 last_failed_step=suspend_noirq` (test 0) |
| 5 | `sudo tests/hardware/k114s-sleep-check.sh cycle`, wait 20 s with the lid open, press a key | Screen black while asleep (note whether any glow is visible). Wakes on the key. `PASS (success 3 -> 4 ...)`. Then `ping -c 3` to the router works without reconnecting by hand, and `bluetoothctl show` still lists the controller |
| 6 | The same, asleep for 3 minutes, wake with the power button | PASS. This covers the window in which a K114c's storage firmware crashed about 60 s into a sleep with a change that is **not** in this kernel (#1698). Afterwards `journalctl -b -k \| grep -iE 'RTKit.*(crash\|assert)\|nvme.*(timeout\|reset)\|SError\|adopted link'` prints nothing and `touch ~/sleep-test && rm ~/sleep-test` works |
| 7 | With no agent work running: menu, Suspend (or `systemctl suspend`), lid open; wake with a key | Lock screen appears, then black. Wakes to the lock screen; unlocking works. `cat /sys/power/suspend_stats/success` is one higher |
| 8 | Close the lid for 30 s, open it | Wakes to the lock screen. `journalctl -b -k \| grep 'lid open'` shows one `macsmc-input ... MSLD=0: wakeup` line, timed at about 30000 ms. success one higher, `fail` still 0 |
| 9 | On battery: note `cat /sys/class/power_supply/macsmc-battery/charge_now`, close the lid for 30 minutes, open, read it again | A drop consistent with a few watts. Record the two numbers and the minutes; this is the first K114s sleep power figure |
| 10 | Repeat 8 five times in one boot | 5 more successes, 0 failures, Wi-Fi back each time |

Record for each step: PASS or FAIL, the `suspend_stats` line, and for a failure the `last_failed_*`
values. The script cuts MAC-like strings from the kernel lines it prints; still read the output
before sharing it.

### If something goes wrong

- **A `pm-test` step fails**: the machine is awake and nothing is harmed. `last_failed_dev` names
  the driver. Stop there and report it; do not go on to a real cycle.
- **It does not wake** (tests 5 to 10): hold the power button about 10 s to power off, then boot.
  Filesystems were synced before the suspend. The failed sleep leaves no log, which is why the
  `pm-test` levels come first.
- **It wakes without Wi-Fi** and the log says `adopted link lost during suspend-to-idle`: the link
  is gone until the next boot. Reboot and report.
- **A lid-close sleep ends by itself while the lid is shut**, and the log has `lid open ... at
  +2xx ms in sleep, MSLD=0: wakeup` a fraction of a second after the suspend began: that is the
  false lid-open report seen on the J716s, where the driver waits 2000 ms before it believes one.
  The wait is off for other boards. Report it; the trial setting is the kernel parameter
  `macsmc_input.lid_wake_settle_ms=2000` (read-only at run time, so it needs a boot entry change).
- **It wakes with a dead keyboard or trackpad**: use the power button to shut down and report;
  that has not been seen on a K-board.
- **Going back**: boot the r1 kernel entry and restore the r1 device tree with the macOS tool's
  `rollback stage2`. Without these patches the machine behaves as described under "today".

## What was verified here, and how

| Check | Result | Label |
| --- | --- | --- |
| The five pull requests' heads and states re-read at the source on 2026-11-14 | heads as cited; #1844 merged, the others open | agent-run |
| Each upstream patch's `git patch-id --stable` against the pull request's own patch | 9 of 9 equal | agent-run |
| `git am` of the ten published files on the installed kernel source | applies; the resulting tree equals the build branch's tree | agent-run |
| Compile of the touched objects, running configuration, clang 23.1.3, `W=1` | no warnings | agent-run |
| `t6050-k114s-r1.dtb` rebuilt from `dts/` on this Mac | sha256 `2ea22d26...` equals `manifests/r2c.json` | agent-run |
| `t6050-k114s-r1-sleep.dtb` against r1, decompiled | differs by exactly the four properties; `tests/lint-dtb.py` passes | agent-run |
| The same file built against the patched kernel tree | identical to the one built against the unpatched tree | agent-run |
| `tests/hardware/test-sleep-check.sh` (fake `/sys/power`) | 10 of 10 | agent-run, software only |
| `k114s-sleep-check.sh status` on this Mac | prints the "today" state above | agent-run |

Not verified: a boot of any kernel with these patches; any suspend, resume or lid event; the
`eDP-1` name on this Mac; the lock screen on this Mac; that the OLED is dark while asleep; sleep
power; `rtcwake`-style unattended cycles (no alarm device). The `-EBUSY` on today's kernel is
read from the source, not provoked.

Build note: `build/build-dtb.sh` passes `-Wno-graph_child_address`, which neither dtc 1.8.1 nor
the dtc in the 7.3 tree accepts ("Unrecognized check name"). The trees above were built with that
one flag removed and nothing else changed.

## Building (for the lead)

No configuration change is needed: `CONFIG_SUSPEND`, `CONFIG_PM_DEBUG`, `CONFIG_PM_SLEEP_DEBUG`
(for `/sys/power/pm_test`) and `CONFIG_DRM_SIMPLEDRM` are already set in the running configuration.

All four changed drivers are built in (`CONFIG_PCIE_APPLE`, `CONFIG_DRM_SIMPLEDRM`,
`CONFIG_MACSMC_POWER`, `CONFIG_APPLE_MAILBOX` are `y`), and none changes an exported interface
(source-read). So this series changes the kernel image only; no module is rebuilt because of it.

```
source ~/k114s-build/env.sh                  # the shared user-local toolchain
cd <installed kernel source>                 # a34d26c2 + linux-j714s-27.2.patch + trackpad series
git am <repository>/patches/linux/sleep-lid/00*.patch
cp <repository>/dts/t6050-k114s-*.dts <repository>/dts/t6050-k114s-*.dtsi arch/arm64/boot/dts/apple/
kmake O=<out> olddefconfig
kmake O=<out> Image modules
DTC=<out>/scripts/dtc/dtc <repository>/build/build-dtb.sh . t6050-k114s-r1-sleep <dtb out>
```

The last line needs the `-Wno-graph_child_address` flag dropped from `build/build-dtb.sh` first
(see the build note above). Installing the kernel and the Stage 2 payload is the bundle process and
needs root or the macOS tool; nothing in this branch installs anything.

## Rows for `NOTICE.md` (for the lead)

| Path | Origin | Author | License |
| --- | --- | --- | --- |
| `patches/linux/sleep-lid/0001`, `0002` | aurora-silicon/linux pull request 1647, commits `aa16d423cf8a`, `70bf8ed1867b` | Jens Axboe; Thomas Glanzmann | GPL-2.0 (Linux kernel) |
| `patches/linux/sleep-lid/0003` | this repository | K114s admission here | GPL-2.0 (Linux kernel) |
| `patches/linux/sleep-lid/0004` | aurora-silicon/linux pull request 1688, commit `1006491abe42`; first in omacom/linux-aurora `9dee12b1266c` | ed (edimoldovan) | GPL-2.0 (Linux kernel) |
| `patches/linux/sleep-lid/0005`, `0006` | aurora-silicon/linux pull request 1688, commits `76c5ea390d74`, `67e63a577af4` | Joshua Warren | GPL-2.0 (Linux kernel); device tree GPL-2.0+ OR MIT |
| `patches/linux/sleep-lid/0007` | aurora-silicon/linux pull request 1615, commit `089b082fa329` | Joshua Warren | GPL-2.0 (Linux kernel) |
| `patches/linux/sleep-lid/0008` | aurora-silicon/linux pull request 1789, commit `f61eb4550a95` | Jens Axboe; Thomas Glanzmann | GPL-2.0+ OR MIT (device tree) |
| `patches/linux/sleep-lid/0009`, `0010` | aurora-silicon/linux pull request 1844, commits `41c359da8175`, `788441e0890e` | Erik Bourget; Diljit Singh | GPL-2.0 (Linux kernel) |
| `dts/t6050-k114s-sleep.dtsi` | the lines of pull requests 1688 and 1789 as K114s overrides | Joshua Warren, Jens Axboe (lines); K114s fragment here | GPL-2.0+ OR MIT |

## For upstream, once the owner has run the tests

A K114s line for #1647 (the six lines of 0003) with the test results, as a comment on that pull
request; and a K114s confirmation or failure for #1688 and #1615, which both still say "not
booted". Candidates only: nothing is sent before hardware results exist (`UPSTREAM.md`).
