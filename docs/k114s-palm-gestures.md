# K114s trackpad: palm reporting and gestures (issue #46)

Evidence labels: agent-run (read on the Mac, 2026-11-15, kernel r3a), upstream-reported (read from the upstream PRs).

## What the K114s kernel reports (agent-run)

Read from `/proc/bus/input/devices` with `tests/hardware/k114s-input-capture.sh status`, and `dmesg`:

- Device `Apple MTP multi-touch`, HID product 0x0361, `hid-magicmouse` built from the #1568 path (log line `multi-touch: clamping Report Size 524288 to 16384`).
- ABS codes: slots, X, Y, TOUCH_MAJOR/MINOR, WIDTH_MAJOR/MINOR, ORIENTATION, PRESSURE. `ABS_MT_TOOL_TYPE` (55) is **not** advertised.
- Properties: POINTER, BUTTONPAD, PRESSUREPAD (bits 0, 2, 7). Not DIRECT, so libinput treats it as a touchpad.
- Keys: BTN_LEFT, BTN_TOOL_FINGER, DOUBLETAP, TRIPLETAP, QUADTAP, BTN_TOUCH. Force feedback bit 79.
- Hyprland 0.57.2, libinput 1.32.0. The workspace-swipe `hl.gesture` lines in the user `input.lua` are commented out (stock).

## Diff of the upstream palm and contact fields (upstream-reported)

| PR | Report | What feeds palms | Tool type advertised |
|---|---|---|---|
| #636 (T6041, merged) | MTP 0x75 records | Contact id and class in words 1 and 2 of each record (class 1 thumb, 2 and 3 finger, 6 and up palm), plus tool area over 2200, or over 1400 with a palm class; sticky until lift | yes, when `mtp_palms` |
| #1510 (J616s, merged) | same | same class test, no size rule (fingers reach 2475) | yes |
| #1830 (K116s 0x0362, merged) | Trackpad26 frames (0x5a 0x01) | `tp26_contact.class` (byte 3 of the 48-byte record: 1 thumb, 2/3 finger, 7 palm) sets `MT_TOOL_PALM` | yes (`mtp_palms \|\| mtp_tp26`) |
| #1568 (K114c, draft, **what the K114s runs**) | report 0x5a, section at byte 48, 48-byte records | none: it reads id, phase, x, y, major, minor, force and always reports `MT_TOOL_FINGER` | **no** |

Reading: the #1568 record is the same 48-byte layout as the Trackpad26 contact (id, phase/state, then a byte that #1830 names `class`, then floats). #1568 skips that byte and reports no tool type, so on the K114s libinput has only size, pressure and edge heuristics for palms. Whether the K114s controller fills the class byte like the K116s does is not known: no frames were captured on this board (#1568 comment says so too).

## Gap and proposal

Proposed upstream change (small, on top of #1568 once it lands): in the 0x5a parser, read the class byte of each record, report `MT_TOOL_PALM` for class 7 (and sticky until lift, as #636 does), and advertise `ABS_MT_TOOL_TYPE`. Needs one capture to confirm that class 7 shows up for a resting palm on the K114s.

## Owner capture (not yet run)

```
bash tests/hardware/k114s-input-capture.sh status
sudo bash tests/hardware/k114s-input-capture.sh gestures 60
```

During the 60 s: type a sentence with a palm resting on the pad, then 2-, 3- and 4-finger swipes, a pinch, one click. The script prints the maximum contact count, the tool-type values seen (expected: none), the largest touch major and pressure, and the button counts. It reads only.

To judge gestures after that, uncomment the `hl.gesture` workspace line in the user `input.lua` (a config change, the owner's call).

## Done when

A capture shows contacts, and either palm rejection works or the missing class/tool type is filed upstream (draft below).
