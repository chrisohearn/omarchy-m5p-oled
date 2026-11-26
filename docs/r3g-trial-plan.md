# r3g Backup-slot one-shot trial

The candidate is `linux-k114s 7.3.0.r3g-1`, release
`7.3.0-17.v272-18-k114s-r3g-ARCH`. The trial replaces the r3e1 Backup
for one boot. The default entry remains r3f at `Omarchy/linux-k114s-r3b`.
Restore r3e1 after the trial regardless of the outcome. This plan is for a
separately approved, attended trial.

## Prepare on Main

1. Model the kit on the reviewed #3104 and #3105 owner sessions. Bind its
   inputs to the r3g archive hash in [the build record](r3g-kernel.md) and
   the current state of this Mac. Keep one trial lock and private, verified
   rollback copies of the r3e1 package, both UKIs, the complete Limine menu
   and configured Stage 2. Save the Main boot ID, failed units and a
   fingerprinted kernel-error baseline. Require independent kit review before
   marking it ready.
2. Confirm the running release is r3f, Backup is `linux-k114s 7.3.0.r3e1-1`,
   no other trial or package operation is active, and both one-shot stores are
   clear. Read back the default entry and both UKI hashes. Run the original
   P9 and speaker readiness checks. Verify the read-only QSPI state. Leave
   the original P9 file in place. If the kit needs a candidate version pin,
   use a private temporary copy during the trial and verify the original
   P9 hash again after restore.
3. Verify the configured K114s Stage 2 and its pinned DTB by digest. Use this
   tree for both boots. It provides the N1 nodes and firmware selection
   needed for Wi-Fi and remote checks. Confirm the packaged-DTB opt-in is
   absent. Review the installed kernel transaction and initcpio hooks so
   the two UKIs fit at every step and the configured Stage 2 stays in use.
   Confirm the exact staged UKI's allocated size against the current ESP
   free space and the guard, including the largest temporary copy or
   snapshot made by the active hook. Verify space for the r3e1 rollback.
4. Confirm a working one-shot arm, readback and cancellation path using the
   boot-once preflight, the current Main Tailscale endpoint and a way to
   return from a failed pre-userspace boot. Have Chris at the Mac for the
   trial and agree on a time limit and dead-man fallback before staging.

## Stage and boot once

1. Replace the Backup package with the verified r3g archive, using the
   reviewed kit. Verify a single-package transaction and check the new
   Backup UKI and Backup menu digest. Account for any package hook that
   regenerates Main's UKI. Compare Main's UKI with its saved digest, compare
   the menu with the saved menu plus the new Backup digest, and check the
   Stage 2 digest and both one-shot stores. If staging fails after any
   write, keep Main running and restore the original package and boot
   files before another boot.
2. Use the existing K114s boot-once tool to arm `Omarchy/linux-k114s` once.
   Read back the target in both the RAM EFI and ESP stores, then reboot.
   If arming or rebooting fails, clear and verify both stores before
   restoring Backup. Keep all speaker gates in force throughout. The trial
   uses the existing EFI one-shot mechanism and performs no NOR operations.

## Verify r3g

Check the release, Backup entry, fresh boot ID, consumed one-shot, configured
Stage 2, speaker readiness and read-only QSPI state before exercise. Record
pass, fail or unverified for every check.

| Check | Evidence |
| --- | --- |
| N1 Wi-Fi | Scan, reconnect to the approved saved network, and verify routing and a remote round trip. Repeat after s2idle. |
| N1 Bluetooth | Controller present and powered, scan, and reconnect to a known device if present. Keep the speaker path closed. |
| GPU and compositor | The desktop presents frames on the G17S renderer. Check for GPU faults, resets and software fallback. |
| Internal panel | Read back the active native mode at 120 Hz. Confirm brightness and preserve the configured HDR cap. |
| Camera | Stream for five seconds and verify the under-notch indicator appears during capture and clears after it. |
| Ambient light | Read the ALS before and after a controlled light change. |
| SEP and Touch ID | Check that SEP is ready and the existing Touch ID entry is listed. This check needs no enrollment or credential changes. |
| Trackpad | Check event delivery and have the seat operator verify click, scroll and gestures. |
| Suspend-to-idle | Confirm `s2idle` is selected, suspend and resume once with a bounded wake plan, then recheck display, input, Wi-Fi and Bluetooth. |
| System and kernel | Compare failed system and user units and new warnings or errors against the Main baseline. Inspect any new oops, DCP/AGX timeout or N1 firmware failure. |
| Tailscale | Confirm the service comes up and test the existing Serve endpoint from a peer, including after resume. |

## Return to Main and restore Backup

1. Confirm the one-shot is spent and Main is the saved default. Reboot into
   Main using the reviewed return gate. If r3g hangs before userspace, use
   the attended dead-man recovery from [the integration runbook](r3-integration.md)
   and verify the selected entry after power-on.
2. From r3f Main, restore the saved r3e1 package and the original UKIs and
   menu. Verify the package version, both UKI hashes, default entry,
   configured Stage 2 digest and clear one-shot stores. Run the original
   P9, speaker readiness, QSPI read-only and Tailscale checks again. Keep
   the rollback set private and retain the trial outcomes.
