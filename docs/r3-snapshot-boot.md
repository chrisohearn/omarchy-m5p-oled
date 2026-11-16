# Snapshot boot entries and boot-menu requests on the K114s (issue #68)

Evidence labels: agent-run (read-only commands on the Mac, 2026-11-15), model (arithmetic), not yet owner-observed.
This updates the #68 section of `platform-audit.md` for the state after the r3a promotion (repair image off the ESP).

## Verdict

A Snapshots boot is still **not safe to enable**, and nothing can offer one today: `limine-snapper-sync` refuses every
entry because the ESP is too small for even one snapshot UKI under its 85 percent limit.

## Found (agent-run)

- `limine.conf` has the Omarchy OS with two kernel entries (`linux-aurora`, `linux-k114s`) and no Snapshots section.
  `limine_history/snapshots.json` has `snapshotEntries []`. `BOOT_ORDER` ends with `Snapshots`; `ENABLE_UKI=yes`;
  `LIMIT_USAGE_PERCENT=85`; `MAX_SNAPSHOT_ENTRIES` unset (auto).
- The watcher saw snapshot 4 (16:46) and refused it: "Boot partition usage from 78.8% to 109.3% (+152.3 MiB) will exceed
  the 85.0% limit". The +152.3 MiB is both kernels' UKIs, because every snapshot entry copies a UKI per kernel.
- ESP now: 523,132,928 bytes, 412,110,848 used (78.8 percent), 111,022,080 free. UKIs: `linux-k114s` 79,420,416,
  `linux-aurora` 79,253,504.
- Snapshot kernels versus the installed ones (sha256 of `vmlinuz`, from `k114s-snapshot-check.sh status`):
  snapshots 3 and 4 carry both installed kernels byte-for-byte. Snapshot 1 (image baseline) has only the stock
  `linux-aurora` 7.3.0-17.v272-4, which differs from the installed one. Snapshot 2 is the broken stock 7.2.11 kernel and
  must never be offered (its description says so).
- `omarchy-mac-efi-vars` is active; `RTStorageVolatile` and `VarToFile` exist. `OsIndicationsSupported` is `0x6`
  (no boot-to-firmware-UI bit).
- The boot chain outside every snapshot (m1n1 Stage 2, the device trees, U-Boot, Limine) is on the ESP and is reused by a
  snapshot boot. A snapshot boots with the Stage 2 and DTB installed now. That is fine for snapshots 3 and 4 (same
  kernels, and the r3a tree matches the r3a kernel) and wrong for snapshot 1: the stock kernel does not match the
  K114s tree, which is why the 04/99 snapshot-check hooks refuse such a restore.

## ESP budget (model)

Limit headroom is 32,552,141 bytes (31.0 MiB). One UKI is 75.7 MiB.

| Snapshot UKIs held | Used | Free | At or under 85 percent | Pacman guard (86,016 KiB) |
|---|---|---|---|---|
| none (today) | 78.8% | 111.0 MB | yes | ok |
| 1 (k114s only) | 94.0% | 31.6 MB | no | blocks |
| 2 (both kernels) | 109.1% | none | no | blocks |

One k114s snapshot plus the guard needs 167,500,800 bytes free, 56,478,720 bytes (53.9 MiB) more than now. Raising the limit
to 95 is not a fix: it leaves 31.6 MB free, below the guard, so package transactions stop. Keep the limit at 85.

Candidate `/etc/limine-snapper-sync.conf` settings once there is room (not applied; needs the replica test below):
`MAX_SNAPSHOT_ENTRIES=1`, `EXCLUDE_SNAPSHOT_ENTRIES="Windows*, windows*, *linux-aurora*"` so only the K114s kernel is
copied (halves the cost; whether the wildcard matches the generated entry name is untested), and `LIMIT_USAGE_PERCENT=85`.
The 2026-11-14 incident (a pruned snapshot UKI, `incident-2026-11-14-edge-refresh.md`) is why entries must be capped, not
"auto".

## Boot-menu request (model, to verify)

`systemctl reboot --boot-loader-menu` writes `LoaderConfigTimeoutOneShot`, which systemd-boot reads. Limine is not
systemd-boot and, to my knowledge, ignores it, so it may only reboot and boot the default (`Omarchy/linux-k114s`).
The efi-vars service only makes variables survive a reset; it does not make Limine read them. Unverified until the owner
step below. Limine's own menu is reachable by holding a key at the 5-second timeout (`timeout: 5`).

## Left

Offline, blocked on space: free about 54 MiB more ESP (candidate: nothing cheap is left; `vendorfw` is Linux firmware and
the repair image is already gone, see `esp-space.md`), then test the settings above in the replica (not done: there is no
free ESP to model against, and the replica route for limine-snapper-sync was not run in this pass).

## Owner steps (agent cannot do: needs reboot and a screen)

1. Menu request, safe (default boots anyway), now:
   `systemctl reboot --boot-loader-menu`
   After it: `sudo bash tests/hardware/k114s-snapshot-check.sh after-menu`. Report whether Limine's menu showed.
2. Snapshot boot, only after the ESP has room and a Snapshots entry for snapshot 3 or 4 exists (check:
   `sudo bash tests/hardware/k114s-snapshot-check.sh status`). Keep the power button ready to force off; pick the default
   entry on the next boot. After the boot: `sudo bash tests/hardware/k114s-snapshot-check.sh after`. Do not click "Restore".
