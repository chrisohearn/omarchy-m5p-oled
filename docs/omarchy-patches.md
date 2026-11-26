# Fixes to Omarchy's own scripts

Most of this repository is about the boot chain. This part is smaller: a few fixes to Omarchy's
user-space scripts that this machine needs before Omarchy ships them. Each one is an upstream
change that is still open, kept here as a patch with its authorship (see `NOTICE.md`).

The Omarchy package (`omarchy`, or `omarchy-dev` on the Edge channel) owns most of
`/usr/bin/omarchy-*`. `omarchy-mac` (the Apple Silicon platform data and audio rules) owns a few files that patches 0003 and 0004 change. Every update replaces those files. So a fix made by hand there is silently lost on the next
`omarchy update`. A pacman hook puts the patches back after every transaction that installs or
upgrades the package, and stops reapplying them once they no longer fit.

Patch paths are relative to `/usr`: `bin/omarchy-...` for Omarchy's `bin/`, and
`share/omarchy/shell/...` for its `shell/`, which installs as `/usr/share/omarchy/shell`. A patch
may also carry a local preference rather than an upstream fix; the table below says which.

## Install, refresh, undo

From a checkout of this repository, inside Linux:

```bash
sudo bash linux/omarchy-patches-install          # install, or refresh after a pull; applies now
sudo bash linux/omarchy-patches-install --undo   # take the fixes out and remove the hook
```

It installs:

| Installed as | From |
| --- | --- |
| `/usr/local/lib/omarchy-k114s/omarchy-patches/*.patch` | `patches/omarchy/` |
| `/usr/local/lib/omarchy-k114s/omarchy-patches/*.base/` | `patches/omarchy/*.base/` |
| `/usr/local/lib/omarchy-k114s/omarchy-patches-apply` | `linux/omarchy-patches-apply` |
| `/usr/local/lib/omarchy-k114s/omarchy-patches-lib.sh` | `linux/omarchy-patches-lib.sh` |
| `/etc/pacman.d/hooks/03-k114s-omarchy-patches.hook` | `linux/03-k114s-omarchy-patches.hook` |

It is independent of the repair bundles. It touches no boot file, package hold or EFI partition,
and `linux-persist.sh --undo` leaves it alone. It needs GNU `patch` (`sudo pacman -S patch`), which
Omarchy does not depend on. Without it, the installer refuses and the hook writes nothing and says so.

Script patches take effect on the next run. A patch to the shell's QML (such as 0002) is not
picked up by the running bar: run `omarchy-restart-shell` once after installing or after an update.

A patch may only change files the `omarchy`, `omarchy-dev` or `omarchy-mac` package installed (the three the hook
watches), as recorded in the package database. The installer refuses one that creates or deletes a
file (a file it created could later collide with one Omarchy ships and stop an update) or that changes
a file none of those three packages installed, such as one of `omarchy-settings-dev`'s.

## Base folders: the three-way merge

Each patch may have a base folder beside it, `patches/omarchy/NNNN-name.base/`, holding a copy of
every file the patch changes as it was in the Omarchy build the patch was written for (paths
relative to `/usr`). When Omarchy has since changed lines near the patch's, so that it no longer
applies exactly, the hook merges instead: `git merge-file` carries the patch's change (base to base
with the patch) into Omarchy's new files. A change that only sits near Omarchy's own goes in; one
that overlaps it is a conflict, and then nothing is written. Taking such a patch out reverses it
the same way. The installer refuses a base folder that does not hold every file the patch changes
or that the patch does not apply to exactly.

Write or refresh a base whenever a patch is refreshed against a new Omarchy build:

```bash
tools/omarchy-patch-base patches/omarchy/NNNN-name.patch [USR_DIR]   # USR_DIR defaults to /usr
```

`USR_DIR` holds the files the patch was written for, either as Omarchy ships them or with the patch
in place. For a patch to Omarchy's `bin/` or `shell/`, an export of omacom/omarchy at the build's
commit works, with `shell/` moved to `share/omarchy/shell`.

## What the hook does after each update

Each patch is checked as a whole before anything is written, and without fuzz:

- **applied**: the package put its own files back and the patch fits them exactly. Beside the
  patch, a record (`<patch>.applied`) lists each file it touches with the sha256 the package
  database (the `omarchy` or `omarchy-dev` entry under `/var/lib/pacman/local/`) had for that
  file at that moment.
- **in place**: the files have it and the record still matches the package database, so the
  package has not replaced them since. Nothing is written.
- **Omarchy ships this change itself now**: the files have it, but the package has installed new
  versions of them since it was applied here. The change in them is the package's own. Nothing is
  written. Retire the patch.
- **applied by a three-way merge**: the patch no longer fits exactly, but its base folder merges
  cleanly with Omarchy's changes. The record is written as for **applied**, and later runs report
  **in place (merged with this Omarchy build's changes)**.
- **Omarchy ships part of this change itself now**: with a base folder, the merge would change the
  files, but taking the change out of the result again would not give them back exactly: some of
  it (a hunk, in the same file or another) is already there. Nothing is written, because a later
  take-out would remove Omarchy's part too. Refresh or retire the patch.
- **does not fit this Omarchy build**: Omarchy changed those lines (with a base folder: the same
  lines, so the merge conflicts). Nothing is written, and the update carries on, with that fix
  missing until the patch is refreshed or retired.

A merge writes its files only after every one of them merged cleanly. If a write still fails, each
file already written is put back as it was, and the patch counts as not applied. If putting a file
back fails too, copies of the originals are saved in a new `<patch>.rescue.XXXXXX/` directory beside
the installed patch. If the copy fails, the work directory holding the originals is kept. The hook
or installer reports the exact location and says to reinstall the Omarchy package. A patch that does
not fit, is partly shipped or fails while applying also raises one desktop notification after the
update, to each signed-in user, naming it: Omarchy's own behaviour is back until it is refreshed.
The notification is best effort and never fails the hook.

The hook runs after the transaction and can never stop an update. It leaves no `.orig` or `.rej`
files. `pacman -Qkk omarchy-dev` lists the patched files as modified, which is expected.

## Refreshing without asking (owner's standing rule)

This Mac follows Omarchy's Edge channel on purpose (`omarchy-channel-current` prints `edge`), to get
Apple Silicon changes early, so Omarchy changes the patched lines often. When the hook reports a
patch as **does not fit this Omarchy build** or **Omarchy ships part of this change itself now**,
the agent that sees it refreshes the patch (or retires it, if Omarchy now has the fix) straight
away: new patch and base against the installed build, its test, a PR with the hosted review, merge
and `omarchy-patches-install`, then a check that the hook reports it **applied** or **in place**. No
approval is asked first; the owner is told afterwards (owner's decision, 2026-11-25). The patch's
own safety rules still apply, and a refresh that would change what the patch does, rather than
carry it onto the new lines, is a new decision.

## Retiring a patch

When the upstream change is merged and the Edge build carries it, the hook reports **Omarchy
ships this change itself now**. Delete the file from `patches/omarchy/`, then run
`linux/omarchy-patches-install` again. To retire the last patch, run it with `--undo` instead.
If Omarchy merged a different version of the change, the hook reports **does not fit**. Check
that the problem is fixed upstream, then retire the patch the same way.

Taking a patch out (a refresh without it, a change to the patch or its base, or `--undo`) reverses it only
while its record shows the change was made here. Once the package has replaced the files, the
change in them is the package's and is left alone, so retiring a merged fix never takes Omarchy's
own fix back out, even when other patches share those files. A patch applied by the first
version of this tool, which kept no record, is adopted once, by the next install, refresh or undo,
when every file it touches differs from the package's. After that the install is marked
(`.records`) and nothing is adopted again. Patches stack in name order. Before the set changes,
every installed patch from the lowest one the change reaches is taken out from the top down, and
the wanted set goes back on from the bottom up.

## The patches

| Patch | Fixes | Upstream | State |
| --- | --- | --- | --- |
| `0001-claude-account-by-user-and-organization.patch` | The agents panel keys a Claude account by the claude.ai user alone. One user who belongs to two organizations (a personal plan and a Team) cannot add the second one ("That's Main ..., sign in as the other account"), and both would share one usage cache. The patch keys the account by user and organization in the account registry, the account copy and the Claude usage cache, and checks the organization when an account signs in again. | [omacom/omarchy#18681](https://github.com/omacom/omarchy/pull/18681) (head `560ce87ad93b`), carrying [#16144](https://github.com/omacom/omarchy/pull/16144) onto `quattro`; reconciled here with quattro's login seating and collector locking at `a490d5bdb` (omarchy-dev `4.0.0.r8044`) | open upstream; applied here 2026-11-14; refreshed 2026-11-18 after r8044 changed its lines, and 2026-11-24 after r8296 added the account email (#243) |
| `0002-agents-panel-room-left-pace-and-model-rows.patch` | Local preference, not an upstream fix. In the agents panel every limit meter reads as room left (it drains), as T3 Code's usage view does, so Claude's and Codex's bars move the same way. A hairline marks even pace (the share of the window's time left), and the tooltip says ahead of, on or under pace within 5 points. A model-scoped window such as Fable Weekly gets its own row instead of a tick on the Weekly bar. For Claude and Codex, an exhausted weekly allowance blocks the session bar and removes its pace marker. The panel marks retained readings as Stale after failed refreshes. The usage records still hold the share used. | none (local display policy) | applied here 2026-11-15 |
| `0003-omarchy-mac-k114s-display-cutout.patch` | The bar has no notch floor on the K114s: omarchy-mac's `display-cutouts.json` has no 3024x1986 entry. Two lines: `eDP` (for upstream) and `Unknown-1` (local only: the boot framebuffer's name). `top = 96` is derived, not measured. | to be sent to omacom/omarchy-mac-pkgs ([draft](platform-data.md#upstream-draft-omacomomarchy-mac-pkgs)) | written 2026-11-15, not installed |
| `0004-omarchy-mac-k-board-audio-names.patch` | The M5 MacBook Pros are K boards (`AppleK114`, `effect_output.k114-mic`), so omarchy-mac's jNNN patterns miss them: the stereo microphone mapper, `audio.json`, the microphone name and the no-suspend rule. | same draft | written 2026-11-15, not installed |
| `0005-factory-reset-off-on-k114s-until-qualified.patch` | Local safety switch. The stock `Remove > Factory Reset` action (`remove.factory-reset`) calls `omarchy-system-factory-reset` on btrfs roots. On the K114s the stock reset would replace the Limine menu (dropping the K114s repair entry), rebuild the boot files from the image and erase the system. The patch stops the command before sudo and before any change when the device tree says `apple,k114s` and `/etc/omarchy-k114s/factory-reset-qualified` does not exist. The menu row is owned by `omarchy-settings-dev`. The [platform audit](platform-audit.md#factory-reset-69) gives the user extension that hides it. | none (this machine's choice) | Gate present in `/usr/bin/omarchy-system-factory-reset` on `omarchy-mac` (read-only, 2026-11-20). Menu visibility remains unverified and a real reset remains unqualified. |
| `0006-boot-screen-rebuilds-only-k114s-images.patch` | Local safety switch. `omarchy-plymouth-set` (the boot screen, set by theme or by colours) ends with `sudo omarchy-boot-rebuild`, which on a Limine machine runs a bare `limine-mkinitcpio` and rebuilds the image of every installed kernel, the held stock `linux-aurora` included. On 2026-11-24 one boot screen change put that 79 MB image back on the EFI partition (`docs/esp-space.md` keeps it off), added a third menu entry, left 43 MB free and stopped the next update at the space guard. On the K114s (`apple,k114s` in the device tree), while Limine is the only boot loader Omarchy manages, the rebuild names the installed `linux-k114s*` kernels instead, one kernel at a time through `omarchy-boot-rebuild` (never `mkinitcpio -P`; with any other backend it refuses); before each it checks that the partition is mounted and has the space guard's minimum plus the boot theme's size free (a new image is written beside the old one, and a large custom logo grows it), reading the free space under Limine's boot-partition lock so a running snapshot sync or rebuild finishes first, and otherwise refuses with the command to run later. `limine-mkinitcpio` takes that lock itself to write, so the patch cannot hold it across the rebuild: a writer that starts in between is the remaining gap (#272). | none (this machine's choice) | Tested with stub commands (`tests/linux/test-boot-screen-rebuild.sh`, 2026-11-24); refreshed 2026-11-26 for omarchy-dev r8379, which replaced the bare `limine-mkinitcpio` with `omarchy-boot-rebuild`; not yet run by a real boot screen change. |

Tests: `node tests/linux/test-agents-panel.mjs` exercises the display rules in the patched panel.
`tests/test-platform-data.sh` runs 0003 and 0004 through the installer in a fake root and checks the K114s names against them (docs/platform-data.md).
`tests/linux/test-factory-reset-gate.sh` runs 0005 against the installed command. `tests/linux/test-boot-screen-rebuild.sh` runs 0006's rebuild block against the installed `omarchy-plymouth-set` with stub commands. `tests/linux/test-omarchy-patches.sh linux [OMARCHY_SRC]` runs the mechanism in a fake
root. With `OMARCHY_SRC`, an omacom/omarchy checkout at the installed revision, it also checks that
each real patch applies to it without fuzz and comes out again byte for byte. For 0001 against
`a490d5bdb` (the Edge build `4.0.0.r8044`), Omarchy's own account tests pass on the reconciled
change (`agent-account-test`, `agent-account-copy-test`, `agent-usage-accounts-test`,
`agent-account-recovery-test`, `agent-account-autoswitch-test`, `agent-account-exec-test`: 128
checks, one of them new for signing in again in another organization). Patches to omarchy-mac's
files (0003, 0004) have no counterpart in an omacom/omarchy tree, so that run skips them and says so.

## On another Omarchy machine

0001 and 0002 are not specific to the K114s. A second machine of the owner's (x86_64, Omarchy
stable 4.5.0, package `omarchy`) runs those two, installed on 2026-11-15 from a copy of
this repository with the source narrowed to them. The same 0002 patch carries the provider
through the nested account rows on Stable and older Edge layouts.

**The 0001 refreshed on 2026-11-18 targets the Edge build (r8044) and does not fit `v4.5.0`.**
Installing it there would take the working 0001 out and skip the new one. Until that machine's
stable build carries the Edge code the new 0001 expects, a reinstall there uses the 0001 it was
written for, from commit `050dd93`, as below. The K114s patches (0003 and later) must never go
there; a plain install from the checkout would add them.

```bash
W=$(mktemp -d) && mkdir "$W/src" &&
  git cat-file -e 050dd93 &&   # a shallow clone may lack it: git fetch --unshallow first
  git show 050dd93:patches/omarchy/0001-claude-account-by-user-and-organization.patch \
    > "$W/src/0001-claude-account-by-user-and-organization.patch" &&   # the stable-build 0001
  cp patches/omarchy/0002-*.patch "$W/src/" &&
  cp -r patches/omarchy/0002-*.base "$W/src/" &&
  sudo env K114S_OMARCHY_PATCHES_SRC="$W/src" bash linux/omarchy-patches-install &&
  omarchy-restart-shell
```

Both applied to `v4.5.0` without fuzz on 2026-11-15, and `tests/linux/test-omarchy-patches.sh`
passed with only those two in the source against an export of that tag (74 checks). The hook
keeps the installed copies through Omarchy updates. A change to 0002 here reaches that machine
when the install is run there again.
