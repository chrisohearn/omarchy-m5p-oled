# K114s trackpad: palm reporting and gestures (issue #46)

Evidence labels: agent-run (read on the Mac, 2026-11-15, kernel r3a), upstream-reported (read from the upstream PRs).

## What the K114s kernel reports (agent-run)

Read from `/proc/bus/input/devices` with `tests/hardware/k114s-input-capture.sh status`, and `dmesg`:

- Device `Apple MTP multi-touch`, HID product 0x0361, `hid-magicmouse` on the #1568 path. Evidence: the MTP firmware `Personality: K2C1` line, and HID product 0x0361, not the 0x0362 that selects the TP26 path in the dispatch guard. The log line `multi-touch: clamping Report Size 524288 to 16384` is only the report-size clamp workaround (same idea as #1830's `dchid_clamp_report_size`), not proof of the 0x5a parser.
- ABS codes: slots, X, Y, TOUCH_MAJOR/MINOR, WIDTH_MAJOR/MINOR, ORIENTATION, PRESSURE. `ABS_MT_TOOL_TYPE` (55) is **not** advertised.
- Properties: POINTER, BUTTONPAD, PRESSUREPAD (bits 0, 2, 7). Not DIRECT, so libinput treats it as a touchpad.
- Keys: BTN_LEFT, BTN_TOOL_FINGER, DOUBLETAP, TRIPLETAP, QUADTAP, BTN_TOUCH. Force feedback bit 79.
- Hyprland 0.57.2, libinput 1.32.0. The workspace-swipe `hl.gesture` lines in the user `input.lua` are commented out (stock).

## Diff of the upstream palm and contact fields (upstream-reported)

| PR | Report | What feeds palms | Tool type advertised |
|---|---|---|---|
| #636 (T6041, merged) | MTP 0x75 records | Contact id and class in words 1 and 2 of each record (class 1 thumb, 2 and 3 finger, 6 and up palm), plus tool area over 2200, or over 1400 with a palm class; sticky until lift | yes, when `mtp_palms` |
| #1510 (J616s, merged) | same | same class test, no size rule (fingers reach 2475) | yes |
| #1830 (K116s 0x0362, merged) | Trackpad26 frames (0x5a 0x01) | `tp26_contact.class` (offset 2 of the 48-byte `tp26_contact`: 1 thumb, 2/3 finger, 7 palm) sets `MT_TOOL_PALM` | yes (`mtp_palms \|\| mtp_tp26`) |
| #1568 (K114c, draft, **what the K114s runs**) | report 0x5a, section at byte 48, 48-byte records | none: it reads phase, x, y, major, minor, force (the id byte is documented but unused; slots come from position) and always reports `MT_TOOL_FINGER` | **no** |

Reading: the #1568 record is the same 48-byte layout as the Trackpad26 contact, but #1568 counts offsets one byte later than #1830: id +1, phase +2, x +5, major +21, force +41 in #1568; id 0, state 1, class 2, x 4, major 20, force 40 in #1830's `tp26_contact`. So the class candidate is rec[+3] in #1568's terms (between phase at +2, which #1568 already reads, and the first float at +5). #1568 skips that byte and reports no tool type, so on the K114s libinput has only size, pressure and edge heuristics for palms. Whether the K114s controller fills the class byte like the K116s does is not known: no frames were captured on this board (#1568 comment says so too).

## Gap and proposal

Proposed upstream change (small, on top of #1568 once it lands): in the 0x5a parser, read the class byte of each record, report `MT_TOOL_PALM` for class 7 (and sticky until lift, as #636 does), and advertise `ABS_MT_TOOL_TYPE`. Needs one capture to confirm that class 7 shows up for a resting palm on the K114s.

## Attended class-byte capture (#218)

On the K114s, use the `hidrawN` under the already identified trackpad HID instance's
`hidraw/` directory in sysfs. Replace `N` with its current number. The reader checks
the selected node for the `Apple MTP multi-touch` name and the bus, vendor and
product tuple `0019:05ac:0361` before opening it read-only. The session must already
have read access to that node. If access is denied, stop the capture.

```sh
python3 tests/hardware/k114s-palm-class.py /dev/hidrawN finger
python3 tests/hardware/k114s-palm-class.py /dev/hidrawN resting-palm
```

Wait for each prompt. Move one finger during the first pass. Lift it, then rest
your palm during the second pass. Each pass lasts 10 seconds by default
(`--seconds` accepts 1–30) and opens its own reader. The JSON output gives the
pass label, status, and a count for each observed value of `rec[3]`. These totals
count active contact records over all frames, so a steady contact can contribute
many times. The reader discards the reports in memory and emits no raw reports,
coordinates or contact IDs.

The [pinned #1568 patch](../patches/linux/r3b/0004-HID-magicmouse-parse-the-0x5a-MTP-report-of-the-K114.patch)
documents the supported K2C1 framing from K114c captures. Report ID `0x5a` has
its contact section at byte 48, the first 48-byte record at byte 60, and
`113 + 48 × count` total bytes. The reader checks the section tag and lengths
before counting phases 3 and 4, as the pinned parser does. The existing
`k114s-input-capture.sh gestures` reads evdev and remains the separate check for
contact count, tool type and gestures. In that check, rest a palm while typing,
then try 2-, 3- and 4-finger swipes, a pinch and a click.

`observed` means the pass found eligible records. `no-data` means it found no
eligible contacts, and `unsupported` means reports arrived but none matched the
supported framing. Those two outcomes exit 1. Device or read errors exit 2.
The offline fixture exercises synthetic reports and identities. A physical
finger and resting-palm comparison on K114s is still pending under #46.

```sh
python3 -B tests/hardware/test-palm-class.py
```

To judge gestures after that, uncomment the `hl.gesture` workspace line in the user `input.lua` (a config change, the owner's call).

## Done when

A capture shows contacts, and either palm rejection works or the missing class/tool type is filed upstream (see "Gap and proposal" above).

## Swipe direction: Mac style (the owner's preference, 2026-11-16)

Omarchy now ships default gestures (`default/hypr/gestures.lua`, omacom/omarchy#16891, merged 2026-10-28): three fingers
left and right go to the previous and next workspace, and four fingers move the active window the same way. That is a
deliberate choice upstream, so it was not reported as a bug. On this Mac the owner wants the macOS direction, where the
desktop follows the fingers: a swipe left goes to the next workspace.

Since 2026-11-16 that preference lives in the owner's own settings, which every one of the owner's Omarchy machines
shares, as plain lines in `~/.config/hypr/input.lua`. This repo no longer installs it: the `linux/input/k114s-mac-swipes`
installer and its marked block were retired the same day, after the block was removed from this Mac, so only one copy of
each gesture is ever loaded (Hyprland rejects a second gesture on the same fingers and direction). Owner-observed while the
installer ran: the swipes go the right way, and `hyprctl configerrors` was empty (agent-run).

To get the same swipes on another K114s, add these lines to `~/.config/hypr/input.lua`, which loads after Omarchy's
defaults. Each default is unset first:

```lua
for _, f in ipairs({ 3, 4 }) do
  hl.gesture({ fingers = f, direction = "left", action = "unset" })
  hl.gesture({ fingers = f, direction = "right", action = "unset" })
end
hl.gesture({ fingers = 3, direction = "left", action = function() hl.dispatch(hl.dsp.focus({ workspace = "r+1" })) end })
hl.gesture({ fingers = 3, direction = "right", action = function() hl.dispatch(hl.dsp.focus({ workspace = "r-1" })) end })
hl.gesture({ fingers = 4, direction = "left", action = function() hl.dispatch(hl.dsp.window.move({ workspace = "r+1" })) end })
hl.gesture({ fingers = 4, direction = "right", action = function() hl.dispatch(hl.dsp.window.move({ workspace = "r-1" })) end })
```
