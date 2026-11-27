# Nightly rollout: the K114s on the latest upstream code, unattended

Owner's decision (T3 decision grill, 2026-11-24): "Tonight, then nightly". Each night an agent brings the Mac to the
newest upstream code, using the same reviewed, one-boot trial path as the manual rounds. It promotes what passes and
reports in the morning. This runbook is what that agent follows. The scheduled task points here; when the process
changes, change this file through a PR.

## Standing rules (every run)

- **Speakers stay off.** Never enable or play anything on them. Every kit runs `linux/audio/speaker-readiness.sh`
  before and after each change.
- **Never print disk-unlock details** (Limine `cmdline:` lines), MAC addresses or serial numbers.
- **Never write the SPI NOR or NVRAM.** Never change a guard except through a PR the owner approved.
- **No private data in this repository.** Run `build/check-publishable.sh` and the deny-list scan (counts only) before
  every push or post.
- **Reboots:** only through a gate script that refuses while a `cew-*` or `omarchy-managed-skills-adopt*` user unit is
  active, re-checks just before rebooting, and keeps the way back (a Limine one-shot for kernels, `aura-try` for Stage 2).
  The standing approval is the owner's "Reboot when ready, tell me" (2026-11-24). Nightly runs are unattended, so
  "tell me" means the morning report.
- **Window:** start at 09:00Z, which is 02:00 at the Mac. Reboot only while the session is idle (`loginctl`
  `IdleHint=yes`) or the lid is closed. If the owner is active, build and stage, but leave the reboots for the next
  night, and say so in the report.
- **After every boot:** check that `tailscale serve status --json` shows 443 `/` proxying to `http://127.0.0.1:3773`,
  read-only, for the factory coordinator 3. If it doesn't, message that thread and don't fix it.
- **Review gates are not optional.** Each new or changed kit gets a fresh, independent read-only review (Opus, high).
  Each PR gets the hosted Codex review, or the fallback reviewer from AGENTS.md. Fix P0 and P1 findings and delta-check
  them. P2 and P3 findings become issues.
- Use `mktemp` for temp files. Keep anything needed after a reboot in `~/k114s-build` or `~/.local/state`; the scratchpad
  is wiped on reboot.

## Kernel state

Since 2026-11-26: r3g is Main (`linux-k114s-r3b 7.3.0.r3g-1`) and r3f is Backup (`linux-k114s 7.3.0.r3f-1`). P9's
slot pins were changed with the promotion (the old guard is kept in the promotion kit's rollback set). The Limine menu's
`Kernel version` comments still name the previous versions (r3f on Main, r3e1 on Backup) because the promotion
rendered the menu from its saved copy, so `k114s-boot` notes a mismatch; the entries, hashes and default are correct.
Leave the comments to Limine's own tools: the config may be hash-enrolled, so never hand-edit `limine.conf`. See the
[r3g promotion record](r3g-kernel.md).

## Steps

1. **Packages.** From a fresh checkout of the nightly runbook, create a temporary file with `mktemp` and keep its path
   as `update_proof`. Run `tools/k114s-edge-update-check preflight > "$update_proof"` before `omarchy update -y`.
   Preflight uses a private pacman database. It verifies the planned Edge archives against the repository digests and
   trusted signatures, then applies the Omarchy patches in a disposable root. If a patch conflicts, refresh or retire
   it through the [existing patch workflow](omarchy-patches.md#refreshing-without-asking-owners-standing-rule), then rerun
   preflight. If preflight still fails, skip the package update and report the reason.

   Run `omarchy update -y` as soon as preflight passes. Use `tools/k114s-edge-update-check report "$update_proof"` after
   it returns. The report compares the installed package versions and manifests with preflight, runs P9, and prints the
   verified Main, Backup and Stage 2 state and whether the new root snapshot has a Limine menu entry. Omarchy refreshes
   its own package lists, so Edge can publish another build in the interval between the two commands. A mismatched build
   or a failed P9 holds reboots. Diagnose it, qualify the installed build and rerun verification before proceeding. Use
   `preflight --current` for the installed build when it is still available from Edge. If it has been superseded, verify
   the live patch set and P9, and qualify the replacement before the next update. Remove the temporary proof file at the
   end of the package step. Then check:
   - Verify that `checkupdates` lists no packages after `omarchy update -y`. Record the UTC timestamp and result. This records the package state at that time.
   - If a later `checkupdates` run lists packages, record its timestamp and list separately. It does not turn the earlier empty result into a failure. Run the package step again in the next nightly window.
   - count the boots since the local Plymouth went on with no `plymouth-start` core dump, and close #262 at six in a row
     ([Plymouth on K114s](plymouth-k114s.md#closing-262));
   - run `linux/plymouth-k114s-status` and rebuild the local Plymouth package when Arch Linux ARM ships a newer release, per [Plymouth on K114s](plymouth-k114s.md) (a `plymouth` line in the pre-update `checkupdates` means the update will replace the local build; record it in the report);
   - `sudo -n /usr/local/lib/omarchy-k114s/omarchy-patches-apply` shows all patches in place, or refresh any that
     don't fit, as PR #248 did;
   - the speaker gate passes and `systemctl --failed` is empty;
   - `/lib/firmware/apple/isp_2226_02XX.dat` is present. If it is gone, re-carve it as `docs/r3-camera.md` describes.
2. **Upstream deltas** against what is running:
   - aurora-silicon/linux `main` (the base in the newest `patches/linux/r3*.series` header);
   - aurora-silicon/mesa `aurora-wip` (the installed `mesa-aurora` version names the commit);
   - aurora-silicon/aura `main`, against the configured loader b15 with the K114s camera row;
   - omacom/omarchy-mac-pkgs, and the omacom/omarchy-pkgs `pkgbuilds/` for the packages we install.

   Pick out the changes that touch the T6050, K114/K116, M5, G17 or AGX3 hardware, or code our series uses. If nothing
   relevant changed, skip steps 3 to 7 for the update and say so in the report, but still run step 8.
3. **Kernel** (when relevant). Rebase the current series onto the new `main`:
   - drop what main now carries and re-cut what conflicts, as `docs/r3e-kernel.md` sections 1 and 2 describe;
   - keep the owner's choices: the camera runs without a described light (`0075`), the small indicator sits under the
     notch (`0076`), and the panel HDR headroom is upstream's (#2694; our 500-nit cap is dropped);
   - build with a new release name, and package it into the **Backup** slot (whichever of `linux-k114s` and
     `linux-k114s-r3b` is not Main);
   - add the PKGBUILD and `check-package.sh` cases, then run `validate-config.py`, the QEMU smoke test and
     `check-package.sh` against both other kernels;
   - open a PR, and merge it after the hosted review.
4. **Mesa** (when relevant). Build `mesa-aurora` and `vulkan-aurora` at the new `aurora-wip`, as the
   `~/k114s-build/build/mesa-*` builds did. `meson test` must show 0 failures.
5. **Loader** (when Aura has relevant changes and `main` builds as an ESP Stage 2; aura#509 and #511). Build Aura `main`
   with the K114s camera row (`patches/aura/camera-b15/0001`, re-placed if needed) and the Omarchy logo. Assemble a Stage 2
   test file with the pinned tree and the configured trailer, and check that the same recipe rebuilds the configured
   file byte for byte.
6. **Kits.** Copy the newest kits in `~/.local/state/k114s-recovery/`:
   - `owner-session-r3e1` for a kernel (stage, arm, gate, check, promote), with the slots swapped for the new Backup;
   - `owner-session-mesa2` for packages;
   - `owner-session-camera` for a Stage 2 (arm, gate, check, promote).

   Update every hash, version and slot name. Each kit gets a fresh independent review before use.
7. **Trials, one at a time.** After each boot, run the kit's check. Promote only on PASS. On FAIL, the next boot falls
   back by itself: record the failing gates, file an issue, and leave the promoted state as it was.
   1. packages (Mesa): a guarded ordinary reboot with automatic rollback;
   2. kernel: stage into Backup from an ordinary boot, then a one-shot trial, then promote;
   3. Stage 2: an `aura-try` trial, then promote.
8. **One upstream PR head per night** (owner's decision, 2026-11-25: "Fold into nightly"). Our draft upstream PRs need a
   hardware result from a boot of their exact head before they leave draft. They are the `ledger/outgoing.json` rows
   with these ids, while no `kind: "hardware result (PR head)"` row for that PR's current head is recorded (a posted
   report stays `submitted`; a new head needs a new row): `linux-k114s-nvram-2026-11-25` (#3103),
   `linux-k114-macaudio-jack-2026-11-25` (#3104), `linux-k114s-brightness-floor-2026-11-25` (#3105),
   `linux-2115-sep-dt-rework-2026-11-25` (#2115), `aura-k114s-camera-row-2026-11-25` (aura#515) and
   `linux-k114s-min-brightness-2026-11-26` (#3181, stacked on #2009 and #3105: it waits until a display hand-off lets
   its exact head drive the panel, and is rebased when #2009 or #3105 changes).

   **The nightly run prepares; the boot is attended.** A PR head that hangs before userspace is not recovered by the
   Limine one-shot or `aura-try` alone: someone has to hold the power button (the loader's trial watchdog does not arm
   on this Mac, `docs/r3-integration.md`). So each night take the oldest PR that has no head result yet, prepare it, and
   ask in the morning report for an attended window; boot it only while the owner is at the Mac and says go:
   - **Kernel PRs** (#3104, #3105): build the head as upstream would (a kernel from the PR branch with this Mac's config),
     keeping the K114s patches the head needs to boot and naming each one in the result, and package it into the
     **Backup** slot through a stage kit whose rollback set holds the current Backup package, image and `limine.conf`.
     Boot it once by a Limine one-shot under the same gates as step 7.
   - **Device-tree PRs** (#3103, #2115): the tree comes from the Stage 2, not the kernel package, so build a Stage 2 test
     file whose tree is the K114s board file at the PR head (with the includes the head needs) and boot it once by
     `aura-try`, with the running kernel. The upstream board file has no Wi-Fi node, so the trial boot has no network
     and the agent cannot reach it: the kit must reboot back to Main by itself once its check unit has written the
     result (as the #3103 kit did). The #2115 kit on 2026-11-25 did not, and the Mac sat on the trial boot until the
     owner rebooted it. On such a trial boot (a PR tree with no Wi-Fi node) the after-boot Tailscale check is
     recorded as "no network, expected" and the coordinator is not messaged (owner's rule, 2026-11-26); the check on
     the boot back to Main stays strict.
   - **Loader PRs** (aura#515): a Stage 2 test file built from the PR head, booted once by `aura-try`.
   - **Never promote a PR-head build**: Main and the configured Stage 2 stay as they were, and the next boot returns to
     them.
   - **Put the known-good Backup back from Main**: after the result is recorded, first return to an ordinary boot of
     Main (the one-shot is spent; reboot through the ordinary-reboot gate if needed), then reinstall the saved Backup
     package from Main, restore Main's image and block as the stage kits do, and check that P9 holds with the original
     Backup pin before any other boot. A PR-head build never stays installed past its window.
   - run the checks that PR's text says are open (its "Not yet" list) and the kit's usual gates;
   - post the result on the PR as a hardware row for that head SHA, following the destination's rules (no AI
     attribution in aurora-silicon repos), after an independent review of the draft. Mark the PR ready only when the
     row covers everything its "Not yet" list asked for;
   - record the post in `ledger/outgoing.json`. Linux#2115 waits until #2631 merges.

   The speakers stay off for #3104: its head has no speaker path, and the speaker gate runs before and after as usual.
9. **Docs.** Update the status lines of the docs that changed (kernel, Stage 2, camera, matrix rows) through a docs PR.
10. **Report** in the morning to the owner's K114s thread and to Jarvis's inbox. List what was promoted, what was tried
   and failed (with the failing gates), what was skipped and why, what is new upstream, and anything that needs the
   owner.
11. **Verify and close.** A fresh GPT-6.2 Sol (xhigh) verifier checks the night's done-checks against the live Mac. Record
    the result on the run's ledger row (`k114s/nightly-<date>`).

## Way back

Each kit keeps its rollback set under `/var/lib/k114s-recovery/<kit>/`:
- **kernel:** the previous image, `limine.conf` and the package;
- **Stage 2:** the previous `boot-ctxr.bin`, loader override and pinned trees, in `promote-before/`;
- **packages:** the signed or previous local builds.

The Backup kernel entry and the macOS repair tool (`docs/k114s-boot.md`) remain the last resort.
