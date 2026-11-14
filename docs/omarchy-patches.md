# Fixes to Omarchy's own scripts

Most of this repository is about the boot chain. This part is smaller: a few fixes to Omarchy's
user-space scripts that this machine needs before Omarchy ships them. Each one is an upstream
change that is still open, kept here as a patch with its authorship (see `NOTICE.md`).

The Omarchy package (`omarchy`, or `omarchy-dev` on the Edge channel) owns most of
`/usr/bin/omarchy-*`, and every update replaces those files. So a fix made by hand there is silently lost on the next
`omarchy update`. A pacman hook puts the patches back after every transaction that installs or
upgrades the package, and stops reapplying them once they no longer fit.

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
| `/usr/local/lib/omarchy-k114s/omarchy-patches-apply` | `linux/omarchy-patches-apply` |
| `/usr/local/lib/omarchy-k114s/omarchy-patches-lib.sh` | `linux/omarchy-patches-lib.sh` |
| `/etc/pacman.d/hooks/03-k114s-omarchy-patches.hook` | `linux/03-k114s-omarchy-patches.hook` |

It is independent of the repair bundles. It touches no boot file, package hold or EFI partition,
and `linux-persist.sh --undo` leaves it alone. It needs GNU `patch` (`sudo pacman -S patch`), which
Omarchy does not depend on. Without it, the installer refuses and the hook writes nothing and says so.

A patch may only change files the `omarchy` or `omarchy-dev` package installed (the two the hook
watches), as recorded in the package database. The installer refuses one that creates or deletes a
file (a file it created could later collide with one Omarchy ships and stop an update) or that changes
a file neither package installed, such as one of `omarchy-settings-dev`'s.

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
- **does not fit this Omarchy build**: Omarchy changed those lines. Nothing is written, and the
  update carries on, with that fix missing until the patch is refreshed or retired.

The hook runs after the transaction and can never stop an update. It leaves no `.orig` or `.rej`
files. `pacman -Qkk omarchy-dev` lists the patched files as modified, which is expected.

## Retiring a patch

When the upstream change is merged and the Edge build carries it, the hook reports **Omarchy
ships this change itself now**. Delete the file from `patches/omarchy/`, then run
`linux/omarchy-patches-install` again. To retire the last patch, run it with `--undo` instead.
If Omarchy merged a different version of the change, the hook reports **does not fit**. Check
that the problem is fixed upstream, then retire the patch the same way.

Taking a patch out (a refresh without it, a changed version of it, or `--undo`) reverses it only
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
| `0001-claude-account-by-user-and-organization.patch` | The agents panel keys a Claude account by the claude.ai user alone. One user who belongs to two organizations (a personal plan and a Team) cannot add the second one ("That's Main ..., sign in as the other account"), and both would share one usage cache. The patch keys the account by user and organization in the account registry, the account copy and the Claude usage cache. | [omacom/omarchy#18681](https://github.com/omacom/omarchy/pull/18681) (head `0d6d7c27a790`), carrying [#16144](https://github.com/omacom/omarchy/pull/16144) onto `quattro` | open upstream; applied here 2026-11-14 |

Tests: `tests/linux/test-omarchy-patches.sh linux [OMARCHY_SRC]` runs the mechanism in a fake
root. With `OMARCHY_SRC`, an omacom/omarchy checkout at the installed revision, it also checks that
each real patch applies to it without fuzz and comes out again byte for byte. For 0001 against
`9ac0883` (the Edge build `4.0.0.r7859.g9ac0883`), the pull request's own tests
(`agent-account-test`, `agent-account-copy-test`, `agent-usage-accounts-test`) also pass, with 58
assertions (agent-run).
