# Draft, not posted: follow-up comment for betizzel/omarchy-m5 PR #18

Correction to our earlier correction here: the DCP hand-off works on the K114s. The black screen we reported after it was
Hyprland colour management, not the hand-off. With `render:cm_enabled` off the desktop shows on the DCP at 3024x1986, 120 Hz
(owner-observed), and `modetest` patterns (run without a compositor) lit the panel. Our earlier check of the hand-off
had read the device tree, the loader log and the connector but nobody had looked at the picture, so it missed the black.
Details and the workaround are in a new issue.
