# r3: the floating-workspace titlebars plugin on hyprland-m5

Worker notes for the r3 candidate. Evidence labels as elsewhere in this repository:
**owner-observed**, **agent-run**, **emulator/replica**. Nothing here has been loaded into the
Mac's own session compositor yet.

## Summary

- The crash of 2026-11-14 (any mouse click once a workspace floats) is a struct-layout mismatch
  between the channel's `omarchy-hyprland-titlebars 0.4.0-1` and `hyprland-m5 0.57.2-2`. Neither
  Hyprland's plugin version check nor the package dependency can see it.
- `packaging/omarchy-hyprland-titlebars-m5/` builds the unchanged plugin source against the
  installed `hyprland-m5` headers as `omarchy-hyprland-titlebars 1:0.4.0+m5-1`.
- The rebuilt `titlebars.so` is byte-identical to the channel's except for its build ID and four
  instructions, all in `COmarchyFloatingHyprBar::inputIsValid()`, which now address
  `m_layerSurfaceLayers` at `0x7b0` instead of `0x790` (agent-run, disassembly).
- In a nested instance of the installed `hyprland-m5` binary with a background layer surface, the
  channel build crashes at the first titlebar press with the stack of the incident, and the
  rebuild passes all ten checks of the plugin's own verifier (agent-run, nested compositor on
  this Mac; not the session's compositor).
- Still to do, by the lead with root: install the package, and have the owner float a workspace
  and click. Until then the fix is **not owner-observed**.

## Cause

`hyprland-m5` is Omarchy's Hyprland 0.57.2-2 recipe plus two patches (betizzel/omarchy-m5
`installer/recipes/hyprland-m5`). Its `0001-direct-scanout-latch-failed-candidate.patch` adds three
members to `Monitor::CMonitor` in the public header `src/output/Monitor.hpp`, in the middle of the
class:

```cpp
PHLWINDOWREF m_dsFailedClient;                              // 0x5b0, 16 bytes
uint32_t     m_dsFailedFormat   = DRM_FORMAT_INVALID;       // 0x5c0
uint64_t     m_dsFailedModifier = DRM_FORMAT_MOD_INVALID;   // 0x5c8
```

Every member after them moves by 32 bytes. Measured with the plugin's compiler flags against both
header trees (agent-run, `abi-probe.cpp` and a wider probe of the same kind):

| `Monitor::CMonitor` | stock 0.57.2-2 headers | hyprland-m5 0.57.2-2 headers |
| --- | --- | --- |
| `m_position`, `m_size`, `m_scale`, `m_scheduledRecalc` (all the plugin reads besides the layers) | `0x10`, `0x38`, `0x94`, `0x260` | the same |
| `m_scanoutNeedsCursorUpdate` | `0x5a9` | `0x5a9` |
| `m_dsFailedClient` | absent | `0x5b0` |
| `m_specialFade` | `0x5b0` | `0x5d0` |
| `m_layerSurfaceLayers` | `0x790` | `0x7b0` |
| `sizeof` | `0x978` | `0x998` |

The installed Hyprland binary agrees with its headers: its `Monitor::CMonitor::attemptDirectScanout()`
reads and writes `this+0x5b0`, `+0x5c0` and `+0x5c8`, which the channel's Hyprland binary never
does (agent-run, disassembly of both).

The plugin's `inputIsValid()` passes `&monitor->m_layerSurfaceLayers[TOP]` and `[OVERLAY]` to
`Desktop::CViewHitTester::layerSurfaceAt()`. Compiled for the stock layout it passes
`monitor+0x7c0` and `+0x7d8`, which in hyprland-m5 are the middle of the BACKGROUND and BOTTOM
lists: a "vector" whose begin is the wallpaper list's capacity pointer and whose end is the empty
BOTTOM list's null begin. `layerSurfaceAt` walks it and faults. That needs one background layer
surface, which every real session has, and one click on a titlebar's window.

Why nothing stopped it:

- **Hyprland's check.** `PLUGIN_INIT` compares `__hyprland_api_get_hash()` with the hash in the
  headers the plugin was compiled against. The hash is `GIT_COMMIT_HASH` plus the minor versions
  of five libraries. Hyprland's release tarball ships `src/version.h.in` with the commit hash
  already written in, so every build from the tarball reports
  `11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947`, patched or not.
- **The package dependency.** The plugin package depends on `hyprland=0.57.2`. `hyprland-m5`
  declares `provides=("hyprland=$pkgver")`, so pacman is satisfied.

## Header audit

All 624 files of the installed `/usr/include/hyprland` (agent-run, `diff -r` and `cmp`):

| Compared with | Files that differ | Effect on the plugin |
| --- | --- | --- |
| the channel's `hyprland 0.57.2-2` package headers (what the channel plugin was compiled against) | `src/output/Monitor.hpp` | the 32-byte shift above |
| | `src/render/shaders/Shaders.hpp` | none: the entries of one table in another order, and the table is sorted at compile time |
| upstream Hyprland 0.57.2 source (504 of the files exist there; the rest are generated) | `src/output/Monitor.hpp` | as above |
| | `src/protocols/core/Output.hpp` | none for this plugin, which does not include it. It is Omarchy's `wl-output-global-grace` patch (a virtual destructor and one member added to `CWLOutputProtocol`), present in the channel's Hyprland as well |

The generated protocol headers are identical to the channel's. The libraries whose headers the
plugin also compiles against (aquamarine, hyprutils, hyprlang, hyprgraphics, hyprcursor, pixman,
libdrm, libinput, wayland) are installed in exactly the versions the channel plugin's `.BUILDINFO`
lists, and the compiler is the same GCC 16.1.1.

So `Monitor::CMonitor` is the only layout difference, and of its shifted members the plugin uses
only `m_layerSurfaceLayers`.

## The rebuild

`packaging/omarchy-hyprland-titlebars-m5/PKGBUILD` is the recipe of omacom/omarchy-pkgs
`pkgbuilds/omarchy-hyprland-titlebars` (same source tarball and checksum, same CMake invocation,
same `!lto !debug`, flags from `/etc/makepkg.conf`), built against the installed headers.

Comparison of the result with the channel's `titlebars.so` (agent-run):

- same size, 395360 bytes; `.rodata`, `.data`, `.data.rel.ro`, `.eh_frame`, `.gcc_except_table`,
  `.dynsym`, `.dynstr`, `.rela.dyn`, `.rela.plt`, `.init_array` identical;
- 24 bytes differ: the 20 bytes of the build ID and one byte in each of four instructions;
- the four instructions, all in `COmarchyFloatingHyprBar::inputIsValid()`:

  | Address | channel build | rebuild |
  | --- | --- | --- |
  | `0x37188` | `add x2, x2, #0x7c0` | `add x2, x2, #0x7e0` |
  | `0x372dc` | `mov x2, #0x7c0` | `mov x2, #0x7e0` |
  | `0x372f8` | `add x2, x2, #0x7d8` | `add x2, x2, #0x7f8` |
  | `0x373d8` | `mov x2, #0x7d8` | `mov x2, #0x7f8` |

  `0x7e0` and `0x7f8` are `0x7b0 + 2*24` and `0x7b0 + 3*24`: the TOP and OVERLAY lists in the
  hyprland-m5 layout.

That the toolchain here reproduces the channel's binary to the byte apart from those offsets is
also the evidence that nothing else about the build differs.

Built package (agent-run, not installed): `omarchy-hyprland-titlebars-1:0.4.0+m5-1-aarch64.pkg.tar.xz`,
`titlebars.so` sha256 `e227dafbbd67e4e9d5435258bdeb3838976a3430eae85e7bc2cd7f1724c70c2f`,
build ID `7b64e7542917a805dc0542b30247ba01507ed9c9`. Two builds, one in the worker's environment
and one in the emptied environment of `build.sh`, gave the same `titlebars.so`.

## Nested test

`packaging/omarchy-hyprland-titlebars-m5/nested-test.sh` runs the plugin repository's
`tools/verify.py`: a nested Hyprland (the installed `hyprland-m5` binary, Aquamarine's Wayland
backend, drawn as one window of the running session) with its own runtime directory and config,
`foot` windows inside it, and real pointer presses, drags and double clicks on their titlebars
through a virtual pointer of the nested instance. The script adds isolation the verifier does not
have: an empty home (Hyprland otherwise writes the cursor theme and size to the user's dconf and
its version files to the user's data directory), no session bus, `LIBSEAT_BACKEND=seatd` so that the
nested instance's DRM attempt fails without asking logind, Xwayland off, and a non-dumpable
nested process so that a crash there leaves no core dump and raises no crash notification.

The verifier as published cannot see this fault. Its nested instance has no layer surfaces, so
all four layer lists are empty and the misplaced read finds two null pointers. The script
therefore maps a background layer surface in the nested instance first.

Runs on this Mac, 2026-11-14, kernel `K114S-R1`, session on llvmpipe (agent-run):

| Run | Library | Layer surface | Result |
| --- | --- | --- | --- |
| 1 | rebuild | none | 10 of 10 checks pass (says nothing about the fault, see run 2) |
| 2 | channel `0.4.0-1` | none | 10 of 10 checks pass: the verifier alone is blind to the fault |
| 3 | channel `0.4.0-1` | background | the nested Hyprland dies with SIGSEGV at the first titlebar press (third check). Its crash report: `Desktop::CViewHitTester::layerSurfaceAt` called from `COmarchyFloatingHyprBar::inputIsValid()+0x414`, called from `onMouseButton`: the incident's stack |
| 4 | rebuild | background | 10 of 10 checks pass |

Each run took under 30 seconds. The session's compositor was not touched and kept running: no
`hyprctl` command was sent to it, its only window before and after was the one it had, and no
core dump was recorded.

Before the first run, the one thing a nested compositor asks of the session's compositor that
the clients running here did not appear to (they held no window-sized dmabufs) was tried in a
private process: a GBM buffer from the DRM node, exported as a dmabuf, imported into a second EGL
display as a texture, sampled and read back intact. No Wayland connection was involved.

What the nested test does not cover: the session's real configuration (Omarchy's
`workspace-modes.lua`, its theme colors and buttons, the bar and dock on the TOP layer, the
notification layer), touch input, more than one monitor, and the session compositor's DRM backend
instead of the Wayland one.

## Packaging decisions

- **Name.** `omarchy-hyprland-titlebars`, unchanged. Omarchy installs the plugin by that name
  (`omarchy-base.packages`, a migration) and asks pacman only whether a package of that name is
  installed, which a `provides` would not answer.
- **Version `1:0.4.0+m5-1`.** The epoch makes it newer than anything the channel publishes without
  one, so `pacman -Syu` never replaces it, with or without the hold. Checked against a copy of the
  package databases with this package marked installed: no upgrade is offered, with and without
  the `IgnorePkg` line (agent-run). `+m5` says which build it is. `pkgrel` counts rebuilds.
- **Hold.** `omarchy-hyprland-titlebars` is already in `/usr/local/lib/omarchy-k114s/holds.list`
  and stays there. The hold and the epoch cover upgrades. Neither stops an explicit
  `pacman -S --noconfirm omarchy-hyprland-titlebars`, which would put the channel build back;
  the optional hook below covers that.
- **Dependency.** `hyprland-m5=0.57.2-2`, release included, in place of `hyprland=0.57.2`. pacman
  then refuses to upgrade or replace `hyprland-m5` while this build is installed, which is the
  behavior the channel's pin was meant to have.
- **Build-time checks.** `build()` stops unless `/usr/include/hyprland` belongs to
  `hyprland-m5 0.57.2-2`, and unless `Monitor::CMonitor` has `m_dsFailedClient` at `0x5b0` and
  `m_layerSurfaceLayers` at `0x7b0`. A rebuilt `hyprland-m5` with another layout therefore stops
  the build until someone has looked.
- **`titlebars.abi`.** Installed beside the plugin: the Hyprland package, version and binary build
  ID it was compiled against, and the offsets. The build ID names one binary exactly, which the
  commit hash does not. `titlebars-abi-check` compares it with the installed Hyprland.
- **Source.** Unchanged upstream `v0.4.0`. No runtime check was added to the plugin: a change to
  code that runs inside the compositor was not worth making for a guard that packaging can give.

## Install and rollback (the lead, as root)

Installing arms the plugin: Omarchy calls `hl.plugin.load()` on
`/usr/lib/omarchy-hyprland-titlebars/titlebars.so` the next time a workspace is set to float, or
at the next config load when a floating workspace is already saved. Do it when the owner is at
the machine and has nothing unsaved in the session.

```bash
P=~/k114s-build/titlebars/pkg/omarchy-hyprland-titlebars-1:0.4.0+m5-1-aarch64.pkg.tar.xz
pacman -Qp "$P"                       # omarchy-hyprland-titlebars 1:0.4.0+m5-1
sudo pacman -U "$P"                   # the package is held: answer Y to "is in IgnorePkg ... Install anyway?"
packaging/omarchy-hyprland-titlebars-m5/titlebars-abi-check     # expect "ok: ... compiled against the installed Hyprland"
sudo rm /usr/lib/omarchy-hyprland-titlebars/titlebars.so.disabled-k114s   # the channel build that was moved aside; nothing owns it any more
```

The transaction runs no boot-chain hook. Of the installed hooks, its package name and files match
only the three pre-transaction guards that run for every package (Omarchy's update guard, the
K114s ESP free-space guard, the limine-snapper lock) and systemd's `35-systemd-update.hook`
(agent-run: the hook triggers evaluated against the package's file list, not a pacman run). The
ESP guard can stop this transaction like any other when the ESP is below its limit; that is its
own matter.

Then the owner's check, which is the one that counts: float a workspace, click in a window, drag
it by its titlebar, use the three buttons.

Rollback, from a TTY or over SSH when the session is gone:

```bash
sudo mv /usr/lib/omarchy-hyprland-titlebars/titlebars.so /usr/lib/omarchy-hyprland-titlebars/titlebars.so.disabled-k114s
```

Floating workspaces then work without titlebars, as they do now. The package can stay installed.

## Optional guard

`02-k114s-titlebars-abi.hook` with `titlebars-abi-check --disarm` is a PostTransaction pacman
hook for the K114s guard set (`/etc/pacman.d/hooks/`, script in `/usr/local/lib/omarchy-k114s/`).
After any transaction that installs or upgrades the plugin or a Hyprland it compares the plugin's
`titlebars.abi` with the installed Hyprland's build ID and moves a mismatched `titlebars.so` to
`titlebars.so.disabled-k114s`, which is what was done by hand on 2026-11-14. It would have caught
the edge refresh that started this: a plugin without `titlebars.abi` beside a Hyprland that is not
the channel's own `hyprland` package. It never arms anything. 17 tests in `test-abi-check.sh`
pass (agent-run, throwaway roots; not run under pacman).

It is not installed and `linux/linux-persist.sh` does not know it; whether it joins the guard set
is the lead's decision. For the lead:

```bash
sudo install -m 755 packaging/omarchy-hyprland-titlebars-m5/titlebars-abi-check /usr/local/lib/omarchy-k114s/titlebars-abi-check
sudo install -m 644 packaging/omarchy-hyprland-titlebars-m5/02-k114s-titlebars-abi.hook /etc/pacman.d/hooks/02-k114s-titlebars-abi.hook
```

## What to report upstream

Not sent. Drafts of the substance:

**To betizzel/omarchy-m5 (`installer/recipes/hyprland-m5`).**

1. `hyprland-m5 0.57.2-2` changes the layout of a public class and stays indistinguishable from
   stock Hyprland. `0001-direct-scanout-latch-failed-candidate.patch` puts three members into the
   middle of `Monitor::CMonitor`; everything after them moves 32 bytes
   (`m_layerSurfaceLayers` `0x790` to `0x7b0`). The package still reports the release tarball's
   commit hash and `provides=("hyprland=$pkgver")`, so Omarchy's `omarchy-hyprland-titlebars`
   (built for stock headers, `depends=hyprland=0.57.2`, in `omarchy-base.packages`) installs and
   loads, and the first click on a floating workspace crashes the compositor in
   `CViewHitTester::layerSurfaceAt`.
2. Smallest fix: keep the layout. Hold the latch state outside the header (a static map in
   `Monitor.cpp` keyed by monitor), or at least at the end of `CMonitor`: plugins never construct
   or copy a `CMonitor`, so members appended at the end move nothing a plugin reads. Stock-built
   plugins then keep working.
3. Otherwise make the difference visible and ship the pair: change `GIT_COMMIT_HASH` in
   `src/version.h.in` in `prepare()` (for example append `-m5.$pkgrel`), so Hyprland refuses a
   stock-built plugin with a message instead of running it; do not provide the bare
   `hyprland=$pkgver` that the stock plugin depends on, or conflict with it; and build the
   titlebars plugin against `hyprland-m5` in the same recipe set, as the PKGBUILD's own comment
   about x86_64 ("move with the titlebars plugin") suggests was intended.
4. Evidence to attach: the offset table, the four-instruction difference, the nested
   reproduction, and the recipe in this directory.

**To Omarchy (omacom/omarchy-pkgs, omacom/omarchy-hyprland-titlebars).**

1. `depends=('hyprland=0.57.2')` is satisfied by any package that provides `hyprland=0.57.2`, and
   by any pkgrel of Omarchy's own. The README says the package "always demands the Hyprland it
   loads into"; it demands a version string. Omarchy's own `hyprland` already differs from
   upstream headers (`protocols/core/Output.hpp`, the wl-output grace patch) under the upstream
   commit hash, so the same class of fault is one patch away inside the channel as well. A pin
   that means "this build" needs something only that build provides, for example a
   `hyprland-abi=<digest of the installed header tree>` provide that the plugin depends on, or a
   commit-hash suffix per patched release, which Hyprland's own load check then enforces.
2. `tools/verify.py` cannot detect a `CMonitor` layout mismatch: its nested instance has no layer
   surfaces, so the lists `inputIsValid()` reads are empty wherever it reads them. The channel
   build passes all ten checks on `hyprland-m5`. With one background layer surface mapped before
   the first press it crashes at the third check. A wallpaper-like layer surface in the verifier
   would make it sensitive to this.
3. `verify.py` runs the nested Hyprland with the user's home and session bus, so that instance
   writes the cursor theme to the user's dconf. An empty `HOME` and no bus address avoid it.

**To Hyprland, as background for both.** The release tarball's `version.h.in` carries the commit
hash, so a downstream build with header-changing patches passes the plugin hash check. A layout
fingerprint of the plugin-visible classes in the check would catch it.

## Not verified, and risks

- **Not owner-observed.** The rebuilt plugin has not been loaded into the session's compositor.
  The nested instance uses the same Hyprland binary and the same plugin file, but not the session's
  configuration, layers or DRM backend.
- **Not run under pacman.** The package was built and inspected, and pacman resolves it
  (`pacman -U --print`), but it was not installed. The hook was tested only by calling its script.
- **Tied to one Hyprland build.** Any new `hyprland-m5` needs a rebuild of this package first;
  the dependency makes pacman say so instead of crashing later. A `hyprland-m5` rebuilt under the
  same version and release with another layout would get past pacman; the build-time pins and
  `titlebars-abi-check` catch that, the dependency does not.
- **The epoch is sticky.** Going back to the channel's plugin, once `hyprland-m5` is fixed or
  gone, is an explicit `pacman -S omarchy/omarchy-hyprland-titlebars` (a downgrade in pacman's
  eyes) after the hold is lifted.
- **Other plugins.** Any other Hyprland plugin built for stock headers has the same problem on
  `hyprland-m5` if it touches `CMonitor` members after `m_scanoutNeedsCursorUpdate`. None is
  installed on this machine besides this one.
