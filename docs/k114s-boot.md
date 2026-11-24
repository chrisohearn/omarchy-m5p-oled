# Which kernel is Main: `k114s-boot status`

The Mac keeps two kernels, in two Limine entries named after their packages: `Omarchy/linux-k114s` and
`Omarchy/linux-k114s-r3b`. Each update swaps their roles, so the names don't say which is which. `k114s-boot status` does
(read only; it needs root to read the ESP, and re-runs itself with `sudo -n`):

    K114s boot
      Main    Omarchy/linux-k114s          7.3.0-17.v272-18-k114s-r3d-ARCH   <- running now
      Backup  Omarchy/linux-k114s-r3b      7.3.0-17.v272-18-k114s-r3c-upstream-ARCH
      Next boot: Main (no test boot pending)
      Stage 2: the configured m1n1/boot-ctxr.bin (d1254de6)

- **Main** is the entry `default_entry` names: what every ordinary boot starts.
- **Backup** is the other kernel entry: the way back.
- **Test** is the entry a pending Limine one-shot names (`k114s-boot-once arm`). The next boot starts it once, then
  Main again.
- An armed Stage 2 test file (`aura-try`) and a Stage 2 test boot are shown too.

Why the menu keeps the package names (owner's choice, 2026-11-24):
- The built-in keyboard does not work in the Limine menu on this Mac, so the menu only ever boots the default.
- The macOS repair tool (`macos/tools/k114s_repair.py`) and the boot checks find entries by those names.
- `limine-snapper-sync` reserves names like "Backup".
- So renaming the entries would have cost a change to the repair tool and every check, for labels that are rarely seen.

Install: `k114s-tooling-install` puts it at `/usr/local/bin/k114s-boot` (`--refresh` copies it again, `--undo` removes it).
It also handles:
- an index `default_entry`, counted as Limine counts it;
- a missing, past-the-end or directory `default_entry`, or one that names no kernel entry: no entry is Main, and the
  output says what Limine does (boots entry 1 if it is a kernel, else stops at the menu, where the built-in keyboard
  does not work). The value is taken verbatim, as Limine takes it;
- `remember_last_entry`;
- a one-shot held only in U-Boot's variable file (a value that is not an entry id is reported as present but undecoded);
- the running entry, read from `LoaderEntrySelected`, with the kernel version as the fallback (and a note when the booted entry's version is not `uname -r`).

Test: `tests/linux/test-k114s-boot.sh` (fake ESPs).
