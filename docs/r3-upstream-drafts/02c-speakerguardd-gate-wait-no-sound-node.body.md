_Written by Claude (an AI agent) working for the owner of the Mac below and posted from the owner's account at his direction. "agent-run" marks a command the agent ran on that Mac; "source read" is a file read in the named repository, with no hardware claim (for this repository: `v2` `04169c44`, its head on 2026-11-14). One machine._

## What happens

On a Mac whose device tree has no sound node, every `speakerguardd-gate` call the units make waits its full 15 s for a speaker card that cannot appear. Two of those waits run one after the other before `systemd-user-sessions.service`, so the display manager and every login are held for about 30 s on every boot. A third wait follows once logins are permitted (the supervisor unit's own gate call) and holds `multi-user.target` for another 15 s.

Seen on three boots (2026-11-13 and 2026-11-14) of a K114s (MacBook Pro 14-inch OLED, M5 Pro, `apple,k114s`) whose tree describes no sound hardware yet: `/proc/device-tree/sound` does not exist and there are no sound cards (agent-run). The tree is our own bring-up tree; `t6050-k114s.dts` in aurora-silicon/linux `integration/aurora` at `0b03fe43` has no `apple,macaudio` node either (source read). Package: `speakerguardd-v2 1.0.0alpha.1-41.1` from the betizzel/omarchy-m5 image, pin `04169c44`, with the units installed as `speakerguardd-v2-*.service`; the installed gate is identical to `packaging/session/speakerguardd-gate` at that commit (agent-run, `cmp`).

Journal of the third of those boots (agent-run; host name, PIDs and the memory-peak field trimmed):

```
15:12:50.93 Starting Speaker protection provisioning (speakerguardd v2)...
15:13:06    speakerguardd-gate: not starting: k114s is unqualified: aurora-speaker-tuning dump refused the tuning (exit 1); no speaker card: the older daemons decide for themselves
15:13:06    speakerguardd-v2-provision.service: Consumed 93ms CPU time over 15.126s wall clock time
15:13:06    speakerguardd-v2-seat.service: Consumed 92ms CPU time over 15.111s wall clock time
15:13:06    Starting Speaker wiring self-check, silent (speakerguardd v2)...
15:13:21    speakerguardd-v2-selfcheck.service: Consumed 91ms CPU time over 15.116s wall clock time
15:13:21.19 Starting Permit User Sessions...
15:13:36    speakerguardd-v2.service: Consumed 63ms CPU time over 15.086s wall clock time
```

Userspace start took 46.3 s on that boot (systemd's `Startup finished` line). With a local `ConditionPathExists=/proc/device-tree/sound` drop-in on the v2 units that run at boot, the next boot's userspace start took 1.2 s (agent-run).

The wait by itself, as a normal user with `--setting` pointed at a path that does not exist so the gate gets past its root-only setting (agent-run): `speakerguardd-gate explain` takes 15.05 s, and with `--wait 0` it prints the same answer in 0.03 s.

## Cause

`_decide()` calls `kernel_interface(args.wait)` whether or not the board qualified, and `kernel_interface()` polls `speaker_card()` every 0.25 s until `--wait` (default 15 s) runs out. `speaker_card()` only accepts an ALSA card whose device tree node is `apple,macaudio` with a speaker link. When the live tree has no such node, the answer is known at once, but the gate still waits.

At boot the gate is the `ExecCondition` of `speakerguardd-provision.service`, `speakerguardd-seat.service`, `speakerguardd-selfcheck.service` (all `prepare`) and `speakerguardd.service` (`v2`). The self-check is ordered `After=speakerguardd-provision.service` and `Before=systemd-user-sessions.service`, and the supervisor `After=systemd-user-sessions.service`: two waits before logins and one after. `speakerguardd-sleep.service` and the older daemons (through `legacy-gate.conf`) call the gate too. `speakerguardd-switchtest.service` does not: its condition is `speakerguardd-selfcheck pending`, and it was skipped in 0.1 s.

This is not #102: that one is the self-check's own run time (mostly the silent switch test) on the first boot after a kernel change, on a Mac that has speakers, and #103 moved that test after login.

## Suggested fix

Before waiting, look for an enabled `apple,macaudio` node with a speaker link in the live device tree (`wiring.read_dt()` already makes that scan of the root nodes, and `wiring.has_speaker_link()` answers the link part). With none, return "no speaker card" immediately; keep the wait for trees that do describe one, where the card can still be probing. A `ConditionPathExists` on the units would be shorter but ties them to the node's path.

Not tested: no patch has been written or run by us. This Mac's speakers are not enabled and will not be until the model has protection data, so we can test "no sound node" and nothing else.
