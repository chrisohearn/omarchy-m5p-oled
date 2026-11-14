_Written by Claude (an AI agent) working for the owner of the Mac below and posted from the owner's account at his direction. "agent-run" marks a command the agent ran on that Mac; "source read" marks a file read in the named repository. One machine._

## What happens

With the release 3 package set, Hyprland aborts on a mouse click once a workspace has been switched to floating. Five aborts were recorded in 22 minutes (14:26 to 14:48 on 2026-11-14), each from the same frame (agent-run, `coredumpctl`):

```
#2  abort (libc.so.6)
#3  Hyprland + 0x301bcc
#6  COmarchyFloatingHyprBar::inputIsValid() (titlebars.so + 0x371b4)
```

## Cause

`hyprland-m5 0.57.2-2` and `omarchy-hyprland-titlebars 0.4.0-1` do not agree on the layout of `CMonitor`, and nothing stops the plugin from loading.

- `0001-direct-scanout-latch-failed-candidate.patch` adds three members to `CMonitor` in `src/output/Monitor.hpp` (`m_dsFailedClient`, `m_dsFailedFormat`, `m_dsFailedModifier`), in the middle of the class. Every member after them moves by 32 bytes.
- The package is built from the v0.57.2 release tarball, so it reports stock Hyprland's commit: `Hyprland --version` prints `commit 11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947`, which is the upstream `v0.57.2` tag, and the ABI string starts with that hash (agent-run).
- `omarchy-hyprland-titlebars 0.4.0-1` is Omarchy's build, compiled against Omarchy's own `hyprland 0.57.2-2` (its `.BUILDINFO`), whose `Monitor.hpp` is hyprland-m5's without the three members. Its dependency `hyprland=0.57.2` is satisfied by hyprland-m5's `provides`, and the plugin binary carries the same hash for its version check (agent-run, `strings`), so it loads.

Measured with `offsetof` (agent-run, g++ 16.1.1) against the headers `hyprland-m5` installs and against the headers of Omarchy's `hyprland 0.57.2-2` package:

| | hyprland-m5 headers | Omarchy's hyprland 0.57.2-2 headers |
| --- | --- | --- |
| `m_dsFailedClient`, `m_dsFailedFormat`, `m_dsFailedModifier` | 0x5b0, 0x5c0, 0x5c8 | (absent) |
| `m_layerSurfaceLayers` | 0x7b0 | 0x790 |
| `sizeof(CMonitor)` | 0x998 | 0x978 |

On a left button press the plugin's `onMouseButton` calls `inputIsValid()` (source read, plugin v0.4.0), which passes `monitor + 0x7c0` and `monitor + 0x7d8` to `Desktop::CViewHitTester::layerSurfaceAt()` (agent-run, `objdump -d` of `titlebars.so`). In the layout the plugin was built for those are `m_layerSurfaceLayers[2]` and `[3]`, the top and overlay layers. In hyprland-m5 the array starts at 0x7b0, so the two addresses land inside elements `[0]` and `[1]`, Hyprland walks a vector made of unrelated pointers, and its crash handler aborts. In the one core opened with `gdb`, the fault is in `layerSurfaceAt()`, walking back from a null end pointer with a heap pointer as begin (agent-run). It needs a surface on the background layer (a wallpaper); with all four layer lists empty the misplaced read finds only null pointers and nothing happens.

## Who is affected

The image build installs both packages (the build's own transaction is in the image's `pacman.log`), and `omarchy-hyprland-titlebars` is in Omarchy's base package list. Omarchy loads the plugin from `default/hypr/workspace-modes.lua` when something floats, in v4.5.0 as well as on the current default branch (source read). On this Mac the aborts were recorded after its desktop packages had moved to `omarchy-dev`; the same pair of binaries was installed before that, but the crash was not tried under the image's own `omarchy 4.5.0-3.7141`.

Release 4's notes say it differs from release 3 in one other package, and the `hyprland-m5` recipe on `main` (`42edf84`) is still 0.57.2-2 with this patch (source read). Release 4 has not been installed here.

The Mac here is a K114s (MacBook Pro 14-inch OLED, M5 Pro), which this image does not support. Nothing in the cause is specific to the board; it has not been reproduced on a J714s.

## Ways to fix it

1. Keep the latch state out of the existing layout: append the three members at the end of `CMonitor`, or hold them in `Monitor.cpp`. Plugins built against stock headers then read every existing member where they expect it.
2. Or build `omarchy-hyprland-titlebars` against hyprland-m5's headers in the package set and pin it with the rest.
3. Or make hyprland-m5 report its own hash, so the plugin's own check refuses a stock-built plugin ("Version mismatch") instead of running it.

Workaround used here: the plugin file was moved aside and the package held. Omarchy then skips the load, and floating workspaces have no titlebars.

What has been tried:

- Fix 2 was built here from the unchanged v0.4.0 source and Omarchy's recipe, against hyprland-m5's installed headers. The result differs from Omarchy's `titlebars.so` in its build ID and in four instructions, all in `inputIsValid()`: 0x7c0 becomes 0x7e0 and 0x7d8 becomes 0x7f8 (agent-run, `cmp` and `objdump -d`).
- In a nested instance of the installed hyprland-m5 binary with a background layer surface, Omarchy's build died with SIGSEGV on the first titlebar press, with `layerSurfaceAt` called from `inputIsValid()+0x414` called from `onMouseButton` in the crash report. The rebuild ran the plugin's own verifier (`tools/verify.py`) to the end (agent-run, a nested compositor on this Mac, not its session).
- The rebuild has not been installed or loaded into the Mac's own session, so nobody has clicked on it yet. Fixes 1 and 3 have not been built.
