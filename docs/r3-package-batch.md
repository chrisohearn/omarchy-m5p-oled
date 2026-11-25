# Package batch 2026-11-24: Mesa at aurora-wip head, omarchy-mac at omarchy-mac-pkgs head

Status 2026-11-24: **installed and promoted** after one guarded test boot (18:19Z) passed. Mesa has since moved on twice
by the same kit: `886a773`, then `89472d5` (aurora-wip head, `meson test` 252/0), whose guarded test boot (23:48Z)
passed and is installed. This is the package part of the
owner's request to "get this device on the latest known code and fixes" (intake 2026-11-24; owner's answer for this
batch: "All, same rules", with test boots under the standing "Reboot when ready, tell me"). The speakers stay off.
Evidence labels: **agent-run** (on this Mac), **source-read**.

## What was installed

| Package | Was | Now | Why |
| --- | --- | --- | --- |
| `mesa-aurora`, `vulkan-aurora` | `1:26.3.0_devel.20261122.232644.e705eca833f-1` (Omarchy's build of omacom/mesa `carry/aurora-7.3`) | `1:26.3.0_devel.20261124.233153.e775d773684-1`, built here | aurora-silicon/mesa `aurora-wip` moved 518 commits past the pin, including the merged M5/G17 fixes (#642, #698, #731, #819, #820 and the borealis M5 work) |
| `omarchy-mac` | `0.2.7-2` (omarchy-mac-pkgs `35dc7ed`) | `0.2.7-3`, built here at omarchy-mac-pkgs `0750b74` | the microphone mapper stays quiet while the lid is closed (5 commits on `omarchy-audio-asahi-mic-map`), which matters now that lid sleep is on |

Both builds use Omarchy's own PKGBUILDs (omacom/omarchy-pkgs `pkgbuilds/`), changed only in the source pin and version:
- **Mesa:** the build leaves out omacom's two carries (#415, the 30-core T6034 G15C contract; #416, the G15 Vulkan
  profile). Both are for M3-class chips, and #415 no longer applies on the new base.
- **Mesa test fix:** one local, test-only fix. `test-layout.cpp` lists `.levels` before `.policy`, which GCC 16 rejects as a
  designator-order error. That is reported upstream as aurora-silicon/mesa#964. `meson test`: 243 passed, 0 failed
  (agent-run).
- **K-board microphone names:** patch 0004 (`patches/omarchy/0004`) re-applies on the new `omarchy-mac` through the
  patch hook, and was in place after the install (agent-run).

## How it was tested

The kit installs the three packages, arms a one-boot check service and reboots. After the reboot, the service runs a
desktop check for up to 240 s. If the check does not pass, it reinstalls the signed repository builds of the previous
versions: Mesa first, then `omarchy-mac`. Every probe is time-bounded, and the service has 15 minutes in all.

- **First review:** an independent review of the kit failed it. The P1: a hung GPU probe could stop the rollback ever
  running.
- **Repair:** one aggregate repair fixed that and the P2s: the time budget, a stale pacman lock, the rollback's
  dependence on the ESP guard, and a CEW-install re-check just before the reboot.
- **Delta check:** a fresh delta check passed.

The check after the 18:19Z boot passed (agent-run):
- eDP-1 at `dp3`, `XRGB2101010`, 120 Hz;
- `zink Vulkan 1.4 (Apple M5 Pro (G17S B1))`, readback `255 0 255 255`;
- a Vulkan upload and download through ffmpeg;
- the default input `omarchy_asahi_mic`, with the K-board map in place;
- the speaker gate ok.

After it:
- P9 holds;
- Main is r3d and Backup is r3c-upstream;
- Stage 2 is `6b984811`;
- no unit is failed;
- the boot's error lines are the same kinds as before, and fewer.

## Looked at and not taken

- **aurora-bless #5** (aurora-btsync SDP records, open): the `aurora-bless` package builds only the startup-volume
  selector, not `aurora-btsync`, and that binary writes Apple NVRAM. Nothing to gain for that risk (source-read).
- **omarchy-mac-boot 20261123** (vendor-firmware staging, `apple_soc_cpufreq` in the initramfs: boot speed-ups for other
  boards): installing it rebuilds the initramfs of Main and Backup together, so a bad build leaves no one-shot way back.
  It stays held.
