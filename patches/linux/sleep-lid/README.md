# Kernel patches: suspend-to-idle and lid (K114s r3)

Ten patches for the installed kernel source (aurora-silicon/linux `a34d26c2` + betizzel/omarchy-m5
`linux-j714s-27.2.patch`, with either trackpad series on top). Nine are upstream commits, taken
unchanged; one is this repository's. What each is for, what it depends on and how to test it is in
[docs/r3-sleep-lid.md](../../../docs/r3-sleep-lid.md). Order and overlap with `r3/display-gpu`
are in [`series`](series).

| # | Upstream commit | Source | Author | Patch-id (stable) |
| --- | --- | --- | --- | --- |
| 0001 | `aa16d423cf8a10e6bee0a79313a13fa9565292c6` | aurora-silicon/linux pull request 1647, open | Jens Axboe; rebased by Thomas Glanzmann | `2db0e3fe9acb82f1` |
| 0002 | `70bf8ed1867b2b322c89f3a74e4f51a6547dc1fe` | pull request 1647, open (its head) | Jens Axboe; narrowed by Thomas Glanzmann | `8029c228de43e9ce` |
| 0003 | none: written here | this repository | repository owner, with Claude | `686e203da2821215` |
| 0004 | `1006491abe42bbbdecc4491e68815bfe77093202` | pull request 1688, open draft; first in omacom/linux-aurora `9dee12b1266c` | ed (edimoldovan); submitted by Joshua Warren | `9aee1d80ed837310` |
| 0005 | `76c5ea390d74c77fab63fb7a1ad98a7013ee386f` | pull request 1688, open draft | Joshua Warren | `71f8850f2a97f0c5` |
| 0006 | `67e63a577af4eab860779d28f225247041ae337a` | pull request 1688, open draft (its head) | Joshua Warren | `4479c376fc18968a` |
| 0007 | `089b082fa3290813235729582b3d854d602a4d21` | pull request 1615, open draft | Joshua Warren | `a9cbf185c6e08ac9` |
| 0008 | `f61eb4550a95208ea2acd3a5bc614944735a4ff9` | pull request 1789, open | Jens Axboe; edited by Thomas Glanzmann | `ab14ec71d960ab51` |
| 0009 | `41c359da81755d96315191bc650872e4ec92d94a` | pull request 1844, merged as `adb5a7e344f5` | Erik Bourget | `c9d1b53f23e791b0` |
| 0010 | `788441e0890e18493d72e7df1445f01a844f1061` | pull request 1844, merged as `adb5a7e344f5` | Diljit Singh (DjDeveloperr) | `a52a8061d56fa3cb` |

All are GPL-2.0 (Linux kernel); 0005 and 0008 change device tree sources that are GPL-2.0+ OR MIT.

## How the files were made

- Each upstream patch was taken from the pull request's patch file and applied with `git am` on
  the installed source. Its `git patch-id --stable` equals the upstream commit's, so the change is
  the upstream change (0007 applies 73 lines further down; the content is the same).
- Two lines were added at the end of each upstream message: `(cherry picked from commit ...)` and a
  `[k114s: ...]` note with the pull request. Nothing else in a message was changed. No
  `Signed-off-by` or `Tested-by` was added for anyone.
- `build/check-publishable.sh` refuses e-mail addresses in five of the common domains. In 0004,
  0009 and 0010 the author's mailbox is therefore replaced by
  `mailbox-in-upstream-commit-<sha>@redacted.invalid` (five lines). The author's name is kept and
  the upstream commit named there holds the real address.
- The first line of each file is `From 0000000...`: the local commit IDs mean nothing outside the
  build tree.

## Applying

```
cd <kernel source tree>
git am <this directory>/00*.patch          # or: for p in ...; do patch -Np1 < "$p"; done
```

On a tree that already has pull requests 1688 and 1844 (the `r3/display-gpu` kernel), skip 0004,
0005, 0009 and 0010; the other six apply there as they are (checked with `git apply --check`).
