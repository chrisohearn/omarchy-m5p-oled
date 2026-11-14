_Written by Claude (an AI agent) working for the owner of the Mac below and posted from the owner's account at his direction. "agent-run" marks a command the agent ran on that Mac; "source read" is this repository at `v2` `04169c44`. One machine._

## What happens

On a Mac whose device tree has no sound node, every `speakerguardd-gate` call waits its full 15 s for a speaker card that cannot appear. Two of those waits run one after the other before `systemd-user-sessions.service`, so the login screen is held for about 30 s on every boot, and a third wait follows after login.

Seen on three boots of a K114s (MacBook Pro 14-inch OLED, M5 Pro, `apple,k114s`) whose tree describes no sound hardware yet: `/proc/device-tree/sound` does not exist and there are no sound cards (agent-run). Package: `speakerguardd-v2 1.0.0alpha.1-41.1`, pin `04169c44`; the installed gate is identical to `packaging/session/speakerguardd-gate` at that commit.

```
15:12:50.93 Starting Speaker protection provisioning (speakerguardd v2)...
15:13:06    speakerguardd-gate: not starting: k114s is unqualified: aurora-speaker-tuning dump refused the tuning (exit 1); no speaker card: the older daemons decide for themselves
15:13:06    speakerguardd-v2-provision.service: Consumed 93ms CPU time over 15.126s wall clock time
15:13:06    speakerguardd-v2-seat.service: Consumed 92ms CPU time over 15.111s wall clock time
15:13:06    Starting Speaker wiring self-check, silent (speakerguardd v2)...
15:13:21    speakerguardd-v2-selfcheck.service: Consumed 91ms CPU time over 15.116s wall clock time
15:13:21.19 Starting Permit User Sessions...
```

Userspace start took 46.3 s on that boot (`systemd-analyze`). With a local drop-in that skips the four gated units when `/proc/device-tree/sound` is missing, the next boot's userspace start took 1.2 s.

## Cause

`_decide()` calls `kernel_interface(args.wait)` whether or not the board qualified, and `kernel_interface()` polls `speaker_card()` every 0.25 s until `--wait` (default 15 s) runs out. `speaker_card()` only accepts an ALSA card whose device tree node is `apple,macaudio` with a speaker link. When the live tree has no such node, the answer is known at once, but the gate still waits. `speakerguardd-provision.service`, `speakerguardd-seat.service`, `speakerguardd-selfcheck.service` and `speakerguardd-switchtest.service` each run the gate as their `ExecCondition`, and the self-check is ordered `Before=systemd-user-sessions.service`.

This is not #102: that one is the time of the silent switch test on a Mac that has speakers.

## Suggested fix

Before waiting, look for an enabled `apple,macaudio` node with a speaker link in the live device tree (`wiring.has_speaker_link()` already answers the second half). With none, return "no speaker card" immediately; keep the wait for trees that do describe one, where the card can still be probing. A `ConditionPathExists` on the units would be shorter but ties them to the node's path.

Not tested: no patch has been written or run by us. This Mac's speakers are not enabled and will not be until the model has protection data, so we can test "no sound node" and nothing else.
