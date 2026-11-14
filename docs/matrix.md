# Subsystem matrix: MacBook Pro 14-inch OLED, M5 Pro (Mac17,13, `apple,k114s`)

One row per subsystem: what upstream has, whether it applies to the K114s, and where it stands
here. Scope is the whole machine, not one feature. Last full pass: 2026-11-14.

**States**, in order: `evaluated` (source read, applicability decided) → `integrated` (in this
repository's sources) → `built/tested` (builds, passes the software tests named) → `staged` (in an
apply-ready bundle) → `applied` (written to the Mac) → `hardware-verified` (seen working on a
K114s). A software test is never recorded as hardware proof.

**Base in use.** Kernel aurora-silicon/linux `a34d26c2` + betizzel/omarchy-m5 `linux-j714s-27.2.patch`
(v272-4); loader aura `22b71758` + `aura-j714s-27.2.patch`; Linux stub firmware 27.2 (26B8125);
image set `j714s-dev-runtime-7cd4572ff7ef` (betizzel release 3). The 27.2 Apple device trees of the
K114s and the K116s (16-inch M5 Pro) are identical node for node, so K116s work is the closest
source; each device-tree piece still needs this board's identity (board-id 0x14, firmware names,
panel).

| Subsystem | Upstream source (who tested it, on what) | K114s applicability and dependencies | State here | Gap / next step |
| --- | --- | --- | --- | --- |
| Boot chain: Stage 1, Aura Stage 2, U-Boot, Limine, UKI | betizzel/omarchy-m5 J714s 27.2 line, release 3 (TripleU, J714s) | Same SoC and stub route. The installer admits only J714s; two small patches admit `apple,k114s` (`installer/`) | **hardware-verified** (owner-observed 2026-11-14: boots to the Hyprland desktop) | Offer the admission upstream once the trackpad/Wi-Fi boot is confirmed |
| CPU/SMP, NVMe, IOMMU | aurora-silicon/linux #1025 preliminary K-board trees (ADT-derived, unbooted upstream) | As is | **hardware-verified** for boot from the encrypted NVMe root; core count not recorded | Record `nproc`/`lscpu` at the next boot |
| Keyboard | same tree (MTP HID transport) | As is | **hardware-verified** (owner-observed) | Keyboard backlight (`fpwm0`) is enabled in the tree, not yet observed |
| Internal display, boot framebuffer | same tree | As is | **hardware-verified** (desktop visible) | Fixed brightness and no acceleration until the DCP/GPU rows land |
| Trackpad | linux #1830, merged (Jens Axboe, K116s, product 0x0362); linux #1568, draft (joshuaswarren, K114c, no product gate); AFE reset on SMC `gp1c` in #1648 | K114s reports product 0x0361 and the same "invalid report_size 524288". Both fixes built: r1 = #1568, r1a = #1830 + 0x0361. A `gp1c` Stage 2 variant is included | **staged** (bundle r2; QEMU boot, module present) | Apply, boot, report which of r1/r1a/gp1c works; then send product 0x0361 to #1830's authors |
| Touchscreen ("kiwi") | linux #1605, draft (joshuaswarren, K114c): frames stream, finger events unverified; firmware tool `m5max-touch-firmware` | Needs #1568 underneath, K114s pins and its firmware from the 27.2 image | evaluated | Leave disabled until upstream has finger events; then port |
| Wi-Fi (N1) | linux #1648, merged (Jens Axboe, K116s: associates, DHCP); driver `apple_centauri_t6050` and #1725 already in base | Ported with this board's platform ID `0x00146050` and `k114s-ftab.bin` built from Apple's 27.2 image. Upstream keeps the K114s port disabled "until its board ID is known" | **staged** (bundle r2) | Apply, boot, join a network. 6 GHz joins fail on the K116s; expect 5 GHz |
| Bluetooth (N1) | same port; works on J714s; no K-board report | Described by the same ported nodes (`bluetooth0`) | staged, expectation unknown | Check `bluetoothctl` at the next boot |
| USB-C host (left-front, right) | linux #1648 USB part (K116s); linux #1714 (K114c: USB Ethernet works) | Ported as a K114s copy. Left-back stays the debug port | **staged** (bundle r2) | Plug a USB device. `218e3f85` (tipd async probe) is not in base: look there first if ports do not enumerate |
| USB4 / Thunderbolt | linux #1841 (K114c right port router), #1791 (J714s left-front) | Needs the USB-C controllers up first; K114s pins from its ADT | evaluated | After USB host is confirmed |
| Internal display through the display coprocessor (native mode, 120 Hz) | aura #226 `023eb3a0` + linux #1648 display nodes, #1859, #1868 (Jens Axboe, K116s: `apple-drm` at 3472x2170) | Needs a rebuilt loader (hand merge with betizzel's aura patch 0005), the K114s panel node, and confirmation that the K114s loads the same 27.2 display image as the K116s. A 60 Hz modeset crashed the coprocessor on K114c: #1868 is required | evaluated | **Next candidate (r3)**, with the GPU row |
| OLED brightness | linux #1696, open (J813 only) | Nobody reports OLED brightness working; K116s log shows a fixed "1000 nits" | evaluated | Needs upstream work or K114s investigation after DCP |
| Refresh / VRR | betizzel series patch 0014 (opt-in VRR, J714s LCD panel) | Panel-specific; depends on DCP | evaluated | After DCP |
| HDR / colour | none found | The OLED reads XRGB as alpha (linux #1873, K114c); the image's `hyprland-m5` writes alpha | evaluated | Keep `hyprland-m5`; nothing to integrate |
| HDMI | betizzel series 0017-0019, FatBoy721's HDMI v2 in v272-5 (J714s, on 27.3) | Same HDMI power lines in the K114s ADT; depends on DCP | evaluated | After DCP |
| External displays over USB-C, docks | aura #226 note (K116s on 27.2: `dcpext0` times out, internal panel only); linux #1921, open (J714s dock third display) | Blocked on the 27.2 external-display path upstream | evaluated | Track upstream |
| GPU (G17S), OpenGL/Vulkan | linux #1173/#1650 (in base as series 0001/0005), aura #187 (in base), aura #230, linux `e3373ad8` + `8f418a49` device tree, #1844 mailbox interrupts (Jens Axboe, K116s: vkcube, Plasma composites) | Needs a K114s copy of the GPU nodes and #1844 in the same build (without it, suspend with the lid open panics). Mesa in the image is betizzel's `mesa-aurora` j714s2 | evaluated | **Next candidate (r3)** |
| Video decode | linux #1856 (K116s decoder enabled); `avd-fw` v5-t2 in the image's firmware package | Needs the decoder node and the K114s ADT's AVD version/tier checked | evaluated | With r3 or after |
| Video encode, Neural Engine | betizzel series 0006/0015/0016 (J714s 27.2 build 26B123 layouts and a pin read from a J714s boot); linux #1607 (K114c) | The K114s runs build 26B8125: the J714s pins do not transfer. Needs values read on a K114s | evaluated | After GPU; needs a K114s boot log |
| Speakers | linux #1648 `dac02289`, `45f4de44` (K116s, with speakersafetyd); `speakerguardd-v2` in the image is tuned for J714 | Needs an `apple,k114-macaudio` entry and K114s protection data. Never played unprotected | evaluated | Not before protection is confirmed for this model |
| Headphone jack, microphones | linux #1648 `dac02289`, `f25b8eb1` (K116s: jack codec probes; microphones "not tested") | K114s copy of the nodes | evaluated | With sound |
| Camera | aura #188 (K116s sensor row), linux `5dd1d096` | Loader row is K116s-gated; needs the K114s sensor type from its ADT | evaluated | After DCP |
| Ambient light, lid and other AOP sensors | linux #1645 (in base as series 0019); linux #1688, draft (K114c: built-in panel as eDP so lid close suspends) | #1688 applies while the panel is the boot framebuffer | evaluated | With the sleep row |
| Touch ID / Secure Enclave | linux #1649 (K116s SEP profile); `aurora-sep`, `libfprint-aurora` in the image | Research only. No enrollment and no Secure Enclave writes | evaluated | None planned |
| Battery, charging | K114c reports charge and status; linux #1615, open (uevent fix, not booted) | Should behave as K114c | evaluated | Record `upower -d` at the next boot |
| Fans, thermals (SMC sensors) | linux #1648 hwmon part (K116s) | Ported as a K114s copy | **staged** (bundle r2) | Read `sensors` at the next boot |
| Power management, performance | linux `cd2c9f52` (K116s holds back the CPU PMU and CLPC link); #1789, open (PMP domains) | Follow the K116s | evaluated | With r3 |
| Sleep, resume, lid | linux #1647, open (K116s s2idle with the N1 up), #1844, #1789, #1688 | With the N1 on, the current kernel refuses suspend. Needs #1647 plus an `apple,k114s` line. Deep sleep does not exist on 27.2 | evaluated | Kernel candidate after the trackpad/Wi-Fi boot |
| SD card reader | linux `54348df1` (K116s: probes, no card tested); #1719 (K114c) | K114s copy | evaluated | Low priority |
| Updates on the Edge channel | omacom/omarchy v4.5.0 update flow, omarchy-mac-boot `7e50e937`; betizzel release 4 boot-partition check; nickfoy/omarchy-m3-max preflight method | K114s additions must survive `omarchy update` and a channel refresh | **staged** (bundle r2): 77 + 18 + 85 software tests, plus a run inside a copy of the installed image ([edge-update-path.md](edge-update-path.md)) | Hardware: run `linux-persist.sh`, then one `omarchy update` |
| Omarchy desktop, Hyprland | image set: `omarchy` 4.5.0-3.7141 and `hyprland-m5`, pinned by the image | Switching the desktop to Edge's `omarchy-dev` is not yet proven on this stack | evaluated | See [edge-update-path.md](edge-update-path.md) |
| Firmware collection and versions | Apple 27.2 restore image (26B8125), `k114sap` identity | Trackpad and N1 firmware extracted on the owner's side; never redistributed here | staged | macOS is 27.3; the Linux stub stays 27.2 |
| Installer | betizzel/omarchy-m5 release 4 (J714s only) | K114s admission patches in `installer/` | hardware-verified as a boot route (trial 1) | Upstream offer after the r2 boot |

## Next candidate: r3 (display and GPU at K116s parity)

1. Kernel on the installed base, same release string: add #1844 (`41c359da`, `788441e0`), #1868
   (four commits), #1647 with an `apple,k114s` line, #1688, keeping r1a's trackpad change.
2. Device tree: K114s copies of the K116s display, GPU, PMP/SEP and decoder sections, with the
   K114s panel values from its own ADT.
3. Loader: aura `023eb3a0` merged with betizzel's aura patch 0005, plus aura #230; a rebuilt
   Stage 2, kept as a separate Stage 2 variant so `rollback stage2` returns to the r2 tree.
4. Tests: device-tree lint, QEMU boot, replica apply and rollback. Then hardware.

Sound, camera, touchscreen and sleep follow as their own candidates. A row moves only on evidence.
