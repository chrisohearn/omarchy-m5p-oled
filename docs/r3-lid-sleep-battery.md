# Lid close: sleep on battery, lock on external power (K114s)

Owner decision 2026-11-17, confirmed after two attended suspend-to-idle passes on 2026-11-24 on kernel r3d
(`tests/hardware/k114s-sleep-check.sh pm-test freezer`, `devices`, `platform`, and two real cycles, woken by a key and by
the lid: all PASS). Until now every sleep path was blocked three ways (docs/r3-integration.md step C, docs/r3-lid-lock.md).
This opens exactly one of them, on ordinary boots only. Status: **installed 2026-11-24 05:50Z (#238).** A trial boot kept the gate closed, and the ordinary boot at 05:58Z opened it ("lid close suspends on battery, locks on external power"). The owner skipped the overnight drain measurement (2026-11-24), so drain while suspended is unmeasured and deep sleep stays an open question.
All dates here are UTC. Evidence labels: agent-run (a command run on this Mac 2026-11-24, read only), source-read (man page of the installed systemd 262).

## What it does

| State | Lid closed on battery | Lid closed on external power | Docked | Hibernate, hybrid sleep, suspend-then-hibernate |
| --- | --- | --- | --- | --- |
| Ordinary boot (after install) | suspend-to-idle (`SuspendState=freeze`) | lock | ignore | refused |
| Trial boot (Stage 2 trial or one-shot kernel trial) | lock | lock | ignore | refused |
| Not installed (before 2026-11-24, or after `undo`) | lock | lock | ignore | refused |

A trial boot never sleeps: the reason the four targets were masked. Hibernate and hybrid sleep stay off (no swap image, deep
sleep is compiled out): their targets stay masked in `/etc`, and the `/run` drop-in repeats `AllowHibernation=no`,
`AllowHybridSleep=no`, `AllowSuspendThenHibernate=no`.

## How (fail closed)

`linux/r3a-trial/k114s-lid-sleep` is one tool: `install`, `undo`, `check`, `status`, `gate`, `open`, `close`.

| Layer | Where | Ordinary boot | Trial boot |
| --- | --- | --- | --- |
| hibernate, hybrid-sleep, suspend-then-hibernate targets | `/etc/systemd/system` masked | masked | masked |
| `sleep.conf.d/30-k114s-r3a-trial.conf` `AllowSuspend=no` | `/etc` (persistent, from step C) | overridden by the 40 file | in force |
| `logind.conf.d/30-k114s-r3a-trial.conf` lid `lock` | `/etc` (persistent, from step C) | overridden by the 40 file | in force |
| `sleep-40-k114s-lid-sleep.conf` (`AllowSuspend=yes`, `SuspendState=freeze`) and `logind-40-k114s-lid-sleep.conf` (`HandleLidSwitch=suspend`, `ExternalPower=lock`, `Docked=ignore`) | `/run/systemd/*.conf.d`, written by the gate | present | absent |
| `suspend.target` | unmasked in `/etc` by `install`; the gate masks it again in `/run/systemd/system` | static | `masked-runtime` |

`k114s-lid-sleep-gate.service` (`WantedBy=sysinit.target`, before `systemd-logind`) runs `k114s-lid-sleep gate` on every boot.
`/run` is empty after a reboot, so a boot the gate never judged has no 40 drop-in: it keeps the 30 locks, and a failed or
missing gate cannot open anything. A trial boot has up to three locks even if the gate did not run (`AllowSuspend=no`, the lid
`lock`, and the gate's own runtime mask when it did). If the runtime mask or its `daemon-reload` fails, `close` exits non-zero
(the unit fails in the journal) and the 40 files are already gone, so the two locks hold.

A boot is a trial when either holds:

1. `/proc/device-tree/chosen/aurora,trial` exists (a Stage 2 trial through `aura-try`).
2. `$STATE/boot-once-armed` (written by `k114s-boot-once arm`) names an entry and a boot id of an earlier boot, and
   `LoaderEntrySelected` (what Limine started this boot) equals that entry or cannot be read. The boot that ran `arm` is an ordinary
   boot and may sleep. The boot that follows it is a trial if Limine selects the armed entry or its selection is unreadable.

On the first boot the gate sees after arming, it spends the record by writing `$STATE/lid-sleep-trial-seen`. That boot can be
an ordinary boot if Limine selected a different entry. On subsequent boots the spent record has no effect, even if the trial
entry becomes the default or the selected entry stays unreadable. A new `arm` from another boot starts afresh. The gate keeps
the trial reason in `/run` until reboot, so `k114s-boot-once clear` or completion of the self-test leaves the current trial closed.

`k114s-lid-sleep open` by hand refuses on a trial boot, and `open --force` overrides that for an attended test.

### Why the gate runs `daemon-reload` and not a systemd generator

A generator writing the `suspend.target` mask into `/run/systemd/generator.early` would close a trial boot with no reload. Not
done, because it is not simpler or more robust here (design review, source-read, not tried on the Mac):

- The gate is still needed for the other half (the 40 drop-ins, the logind HUP, spending the arming record), so the generator
  would be a second installed file with its own install, undo, check and tests, running the same classification twice.
- A generator runs before any unit, with efivarfs and `/var` not guaranteed readable. It could only fail closed (an unreadable
  entry is a trial), which would turn a slow mount into "the lid never sleeps". The gate is ordered after `local-fs.target` and the
  efivars mount, so it reads what it needs.
- A generator also runs on every `daemon-reload`, including the one `open --force` and `undo` issue, so it would fight them.
- The failure it closes is already covered twice: `AllowSuspend=no` and the lid `lock` stay in `/etc` on a trial boot, and `close`
  now fails loudly if the mask or the reload does not take.

The 2026-11-24 05:55Z trial journal shows `close` reporting a runtime mask after `daemon-reload`, followed by systemd
marking the gate unit finished. The 05:58Z ordinary boot logged that the gate opened. Both entries were read back
on 2026-11-26.

## Where the masks are asserted or set

| Place | Before | Now |
| --- | --- | --- |
| `linux/r3a-trial/k114s-boot-once check` (and so `arm`) | four targets masked | three masked in `/etc` (exactly `masked`); `suspend.target` masked in `/etc`, or `k114s-lid-sleep check` passes: gate unit enabled, tool and the two 40 drop-ins in `/usr/local/lib/omarchy-k114s`, both 30 locks in `/etc`, and a trial boot is closed. `masked-runtime` alone never passes: a `/run` mask is gone after the reboot that starts the trial |
| `tests/hardware/k114s-r3a-check.sh` | four masked | three masked in `/etc`; suspend masked in `/etc`, or `sudo -n /usr/local/lib/omarchy-k114s/k114s-lid-sleep check` passes (it also sees a one-shot kernel trial); a failing check, or one that cannot run, is `BAD` |
| P9 (`~/.local/state/k114s-recovery/owner-session-touchid/p9.sh`, outside the repo) | four masked | gate-aware check verified in the 2026-11-24 close-out |
| runbook blocks in `docs/r3a-promotion.md` (2), `docs/r3-display-trials.md` (2), `docs/r3-display-d5-d9.md` (2) | `systemctl is-enabled` of four, `= masked` | three must read `masked`; `suspend.target` must read `masked`, or `k114s-lid-sleep check` must pass |
| `docs/r3-integration.md` step C and its check at line 433, `docs/r3-integration.md` line 535 | masks as the trial's lock | unchanged: they describe a machine without the gate, still true before `install`. Step C's two 30 files are what `install` also installs |
| `tests/linux/test-sleep-gates.sh`, `test-boot-once.sh`, new `test-lid-sleep.sh` | | see Tests |
| Not changed: `docs/r3-gpu-result.md` (`systemctl mask ...` for the GPU trial), `docs/r3a-promotion.md` prose, `docs/r3c-kernel.md` "Still open" | | history; the lid-sleep item in `docs/r3c-kernel.md` is now this document |

### P9 patch applied on 2026-11-24

The installed `p9.sh` replaced the original line

    [ "$(systemctl is-enabled suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target | sort -u)" = masked ] || stop "a sleep target is not masked"

with

    [ "$(systemctl is-enabled hibernate.target hybrid-sleep.target suspend-then-hibernate.target | sort -u)" = masked ] && case $(systemctl is-enabled suspend.target) in masked) true ;; *) sudo $L/k114s-lid-sleep check >/dev/null ;; esac || stop "a sleep target is not masked, or suspend.target is not masked and the lid-sleep gate does not hold it (sudo $L/k114s-lid-sleep check says why)"

In P9, `$L` is `/usr/local/lib/omarchy-k114s`. The first branch accepts an /etc mask for suspend. Otherwise P9
requires the lid-sleep gate check. The installed `k114s-boot-once check` read back on 2026-11-26 uses the same rule.

## Install

Run from an ordinary boot (`[ ! -e /proc/device-tree/chosen/aurora,trial ]`, `sudo $K status` shows no pending request),
`$REPO` = the checkout with this change, `$K` = `/usr/local/lib/omarchy-k114s/k114s-boot-once`. Nothing here writes `/boot`, arms
a trial or reboots.

    sudo $K check                                               # clean before
    sudo sh $REPO/linux/r3a-trial/k114s-lid-sleep install       # prints "open (ordinary boot)" and the undo line
    sudo /usr/local/lib/omarchy-k114s/k114s-lid-sleep status    # this boot: ordinary; suspend static, three masked, gate enabled, both 40 files open
    sudo /usr/local/lib/omarchy-k114s/k114s-lid-sleep check     # ok lines only
    sudo $K check                                               # still clean: it now names suspend.target static
    systemd-analyze cat-config systemd/logind.conf | grep -E '^HandleLidSwitch'     # suspend, lock, ignore (the 40 file wins)
    systemd-analyze cat-config systemd/sleep.conf  | grep -E '^Allow|^SuspendState'  # AllowSuspend=yes, SuspendState=freeze, the rest no

`install` puts the tool in `/usr/local/lib/omarchy-k114s/`. It also installs this change's `k114s-boot-once` there, written
through a temp file and compared afterwards. The copy it replaces is kept as `k114s-boot-once.before-lid-sleep`, and `undo`
puts it back. Without that update, the installed `k114s-boot-once` would refuse every `check`, `arm` and P9 once
`suspend.target` is open. `install` also puts the two 40 files in `.../lid-sleep/`, the unit in `/etc/systemd/system`
(enabled), the two 30 files in `/etc/systemd/{sleep,logind}.conf.d`, runs `systemctl unmask suspend.target` (only that one), and
applies the gate to the running boot at once (it sends logind a HUP). No reboot is needed. The first reboot after install must be
watched once: `journalctl -b -u k114s-lid-sleep-gate.service` shows `open` (ordinary) or `trial boot (...)`.

Then apply the P9 patch, and check by hand (owner attending, `tests/hardware/k114s-sleep-check.sh status` first):

1. Battery, lid closed, wait for the screen and keyboard light to go dark, open it: the session is locked, the machine is back.
2. External power, lid closed: the session locks and the Mac stays up.
3. After a trial boot (`aura-try` or `$K arm`), `sudo /usr/local/lib/omarchy-k114s/k114s-lid-sleep status` prints `this boot: trial` and `suspend.target:
   masked-runtime`; `sudo $K check` passes; a lid close locks.

## Undo (one command, no reboot)

    sudo /usr/local/lib/omarchy-k114s/k114s-lid-sleep undo

It removes the `/run` drop-ins and runtime mask, disables and deletes the gate unit, runs `systemctl mask suspend.target`
(back to four masked), tells logind to reload, and deletes the tool and its copies. The two 30 drop-ins stay, as before. Check:
`systemctl is-enabled suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target` reads `masked` four times.
Undo the P9 patch by restoring its original line.

## T3's sleep inhibitor

`systemd-inhibit --list` on this Mac (2026-11-24, agent-run) shows `T3 Code  sleep  "Agents are working"  block`, held by a
`systemd-inhibit` child of T3 while agents run. Omarchy, hypridle, NetworkManager, UPower and t3code hold `sleep` `delay`
inhibitors (a delay only postpones sleep up to `InhibitDelayMaxSec=15`).

Does a lid close honour it? **No, not with this configuration** (source-read, `logind.conf(5)` of systemd 262:
"`LidSwitchIgnoreInhibited=` ... defaults to yes ... the lid switch does not respect suspend blockers by default"; only the
low-level `handle-lid-switch` block inhibitor is always honoured, which Omarchy takes only while an external monitor is in use). So:

- a battery lid close suspends the Mac **even while T3 holds its block**, and the agents stop until it wakes;
- `systemctl suspend` and the Omarchy menu entry are refused for the user while T3 holds the block, so the lid is the one path
  that sleeps an agent-busy Mac (an idle action does not exist: `IdleAction=ignore`).

This was not exercised with a real lid close. If the owner wants working agents to keep the Mac awake on a lid close, add a third
file `/etc/systemd/logind.conf.d/50-k114s-lid-honour-inhibit.conf` with `[Login]` / `LidSwitchIgnoreInhibited=no` (then
`sudo systemctl kill -s HUP systemd-logind`). The lid close then does nothing from logind while a block is held (Omarchy's own lid binding
still locks the session). It is not shipped: it changes the decision from "battery lid close sleeps" to "sleeps unless agents are
working", which is the owner's call.

The Omarchy system menu's Suspend entry now works on ordinary boots, on external power as well (`AllowSuspend=yes`); hide it with
`omarchy-toggle-suspend` if unwanted. The "on external power it locks" rule covers the lid only.

## Tests

`tests/linux/test-lid-sleep.sh` (also in `tests/linux/run-r3.sh`) runs the tool and `k114s-boot-once check` against fake roots with
a stand-in `systemctl`: install (only suspend unmasked, hibernate, hybrid and suspend-then-hibernate masked), the 40 files' lid
and sleep values, an ordinary boot opens, a Stage 2 trial and a one-shot kernel trial each close all four, the arming boot stays
ordinary, an unreadable boot entry fails closed, a spent arming record (the trial entry promoted to the default) leaves later boots
ordinary while a new `arm` is a trial again, `open` refuses on a trial boot unless `--force`, `check` and boot-once `check` pass in
each intended state (four masks, ordinary open, trial closed) and refuse when a trial could sleep (suspend open on a trial boot, gate
disabled, tool or a 40 drop-in missing, a 30 lock missing, hibernate, hybrid or suspend-then-hibernate unmasked or masked only in
`/run`, suspend masked only in `/run` with the gate disabled, the tool missing or a lock gone), and `undo`. `test-boot-once.sh` and
`test-sleep-gates.sh` cover the same refusals in boot-once and as static guards (including `k114s-r3a-check.sh`). Use the boot journal to verify the gate and its reload. The HUP and physical lid response need the live checks above.
