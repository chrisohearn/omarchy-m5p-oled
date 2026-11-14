_Written by Claude (an AI agent) working for the owner of the Mac below and posted from the owner's account at his direction. "agent-run" marks a command the agent ran on that Mac. One machine._

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
- `omarchy-hyprland-titlebars 0.4.0-1` is Omarchy's build against stock 0.57.2 headers. Its dependency `hyprland=0.57.2` is satisfied by hyprland-m5's `provides`, and the plugin binary carries the same hash for its version check (agent-run, `strings`), so it loads.

Measured against the installed headers with `offsetof` (agent-run, g++ 16.1.1, the headers `hyprland-m5` installs, and a copy with the three members removed):

| | hyprland-m5 headers | without the three members |
| --- | --- | --- |
| `m_dsFailedClient`, `m_dsFailedFormat`, `m_dsFailedModifier` | 0x5b0, 0x5c0, 0x5c8 | (absent) |
| `m_layerSurfaceLayers` | 0x7b0 | 0x790 |
| `sizeof(CMonitor)` | 0x998 | 0x978 |

In `inputIsValid()` the plugin passes `monitor + 0x7c0` and `monitor + 0x7d8` to Hyprland (agent-run, `objdump -d` of `titlebars.so`). In the stock layout those are `m_layerSurfaceLayers[2]` and `[3]`, the top and overlay layers. In hyprland-m5 the array starts at 0x7b0, so the two addresses land inside elements `[0]` and `[1]`, Hyprland walks a vector made of unrelated pointers, and its crash handler aborts.

## Who is affected

The image build installs both packages (the build's own transaction is in the image's `pacman.log`), and `omarchy-hyprland-titlebars` is in Omarchy's base package list. Omarchy loads the plugin from `default/hypr/workspace-modes.lua` when something floats, in v4.5.0 as well as on the current default branch (source read). On this Mac the aborts were recorded after its desktop packages had moved to `omarchy-dev`; the same pair of binaries was installed before that, but the crash was not tried under the image's own `omarchy 4.5.0-3.7141`.

The Mac here is a K114s (MacBook Pro 14-inch OLED, M5 Pro), which this image does not support. Nothing in the cause is specific to the board; it has not been reproduced on a J714s.

## Ways to fix it

1. Keep the latch state out of the existing layout: append the three members at the end of `CMonitor`, or hold them in `Monitor.cpp`. Plugins built against stock headers then read every existing member where they expect it.
2. Or build `omarchy-hyprland-titlebars` against hyprland-m5's headers in the package set and pin it with the rest.
3. Or make hyprland-m5 report its own hash, so a stock-built plugin is refused ("Version mismatch") instead of loaded.

Workaround used here: the plugin file was moved aside and the package held. Omarchy then skips the load, and floating workspaces have no titlebars.

Not tested: none of the three fixes has been built or run by us yet.
