# Existing upstream fixes and whether they apply to K114s

Refreshed 2026-11-14 07:40–08:05 UTC, read-only. Raw PR text, review comments and the K-board device
trees at upstream head are in `evidence/`.

**The short version:** nobody has published a K114s board file or a K114s boot report. Almost
everything the K114s needs already exists for its 16-inch twin, the K116s (Jens Axboe's machine,
same M5 Pro, same 27.2 build 26B8125). That work merged into `integration/aurora` on 2026-11-14,
after our base. It is K116s-only as written, so each device-tree piece needs a K114s copy with this
board's values (board-id 0x14, panel size, firmware names). The driver pieces cherry-pick as they are.

## Pins and heads

| | Installed base | Upstream now |
| --- | --- | --- |
| Kernel | aurora-silicon/linux `a34d26c255c2` + `linux-j714s-27.2.patch` (19 patches) | `integration/aurora` `5b36eff41af7` (190 commits ahead, 0 behind) |
| Boot loader | aurora-silicon/aura `22b71758dfd0` + `aura-j714s-27.2.patch` (7 patches) | `main` `3351432dd632` (18 ahead, 0 behind) |
| Image recipes | betizzel/omarchy-m5 (local checkout `b3d9f31`) | `8e00209408b4`: adds kernel v272-5, the same series rebased onto `a31b32f72efd`, "Built only: NOT booted" |

How "in base" was checked: GitHub compare `a34d26c2...<sha>` (`behind` = in base; `ahead`/`diverged`
= not), a grep of the two patch files, and the driver files fetched at both SHAs. No patch was
test-applied, because there is no full kernel tree here. "Clean" below means that no other commit
between base and head touches the same files and our series does not touch them either.

## Table

| Area | Fix (repo, PR state, head/commit SHA) | What it changes | Tested on which board, by whom | Relation to our base |
| --- | --- | --- | --- | --- |
| 1 Trackpad | linux #1830, MERGED 2026-11-14 (merge `948f87197a86`); commits `07687621d1ce`, `a68b43218e41` | Kernel driver. dockchannel-hid clamps the 0x80000-bit Report Size the HID core rejects; hid-magicmouse parses the "5a 01" Trackpad26 frames, gated on HID product 0x0362 | K116s, Jens Axboe: without it "`hid-generic 0019:05AC:0362.0002: invalid report_size 524288`" and "no trackpad"; with it "binds, haptics initialise, pointer, click and two-finger scroll work" | CLEAN BACKPORT CANDIDATE. Not in base (0 `tp26` matches in base hid-magicmouse.c). The gate is product 0x0362; the K114s product ID is unknown |
| 1 Trackpad | linux #1648 commit `377b2a2decf1` (trackpad part) | Device tree. AFE reset moved from SMC pcIO output 2 to SMC GPIO gp1c: `apple,afe-reset-gpios = <&smc_gpio_low 28 GPIO_ACTIVE_LOW>` | K116s tree comment: "through the pcIO outputs the multi-touch interface never comes up". J714s uses the same line | CLEAN BACKPORT CANDIDATE as a K114s override. `smc_gpio_low` exists in base and the base J714s tree already uses it. The K114s tree in base still uses pcIO |
| 1 Trackpad | linux #1568, OPEN draft, head `1e065585d3da` (joshuaswarren `w7c/up-k114c-trackpad`) | Kernel driver. Clamp, plus report 0x5a parsed for every dockchannel trackpad (no product gate) | K114c, joshuaswarren: "929 frames, X from -5896 to 5875, four clicks and the two-finger tool bit". M2, J616s, Neo regression rows PASS (RyanTheTide); J714s row pending | Fallback only if the K114s is not product 0x0362. Edits the same functions as #1830, so take one or the other |
| 1 Trackpad | linux #1737, OPEN draft, head `99a806177302` | Kernel driver. Clamp plus zero-padding of short reports | K116s, Jens: works with #1830's second commit, but logs "`hid_field_extract() called with n (16384) > 32`" once per boot | NOT APPLICABLE: #1830's clamp covers it |
| 1 Touchscreen | linux #1605, OPEN draft, head `ea00ed34c45f`; joshuaswarren/m5max-touch-firmware `e19186f4769e` | Kernel driver + device tree + firmware tool (`tpkiwifw-k114c.bin`) | K114c: "`Kiwi interface ready with status:0` … 17861-byte frames at about 123 Hz"; "Finger events are not verified yet" | NEEDS NEWER BASE: sits on #1568, K114c pins only, firmware taken from the 27.3 image. Leave `kiwi` disabled |
| 2 N1 Wi-Fi | linux #1648 commits `b0d53446f84d`, `24c62c0cf4bf` (MERGED 2026-11-14, landed through #1856 merge `0a8f5f95921b`) | Device tree. Host `iommu-map`/`bus-range` in the shared K114/K116 file; K116s port 0 with the three N1 functions, `firmware-name = "apple/centauri/k116s-ftab.bin"`, platform ID `0x00166050` (board-id << 16 \| 0x6050), protocol 27, PERST# GPIO 80, `wifi0`/`bluetooth0` aliases | K116s, Jens: "the loader trains the link, the N1 enumerates at 01:00.0-2, apple_centauri_t6050 boots the ticketed firmware table from the 27.2 IPSW and wlp1s0f0 associates and gets DHCP" | CLEAN BACKPORT CANDIDATE. The K114s needs its own copy: `k114s-ftab.bin`, `0x00146050`. Commit says "The K114s keeps the host disabled until its board ID is known" |
| 2 N1 Wi-Fi | linux #1725, MERGED 2026-11-12 (merge `ed889dd8821d`) | Kernel driver. NetworkManager default profiles connect; 6 GHz BSSes hidden for two minutes after a failed 6 GHz join | K116s, Jens: "On the K116s every 6 GHz join failed … while SAE on the same APs' 5 GHz BSSes worked" | ALREADY IN BASE (behind 181) |
| 2 N1 loader | aura `src/pcie_t6050.c` | Boot loader. Trains port 0 itself and refuses the hand-off without a host `iommu-map`, and without a one-bus `bus-range` and map entry for each port the tree describes | Same K116s boots | ALREADY IN BASE (file identical at `22b71758` and `main`). No kernel command line is needed. `chosen.asahi,t6050-n1=2` in joshuaswarren's K114c guide belongs to the omacom m1n1 loader: NOT APPLICABLE |
| 2 N1 userspace | omarchy-aurora-firmware `aurora-peripheral-firmware.sh` (our own package) | Userspace. `apple_centauri` is blacklisted and loaded by hand only when the machine is `apple,j714s` | n/a | No upstream fix. On K114s the driver is never loaded even with a correct tree. Needs our own one-line admission |
| 2 N1 + sleep | linux #1647, OPEN, head `70bf8ed1867b`; commits `aa16d423cf8a`, `70bf8ed1867b` | Kernel driver. Admits the K116s to s2idle over the loader-trained N1 link | K116s, Jens: "One s2idle cycle with Wi-Fi up, lid close/open, 18.5 s asleep: `suspend_stats` success 1, fail 0" | CLEAN BACKPORT CANDIDATE plus an `apple,k114s` line. Base admits only J716c and K114c, so suspend returns -EBUSY once the N1 is on |
| 2 N1 scan | linux #1801, MERGED 2026-11-14 (merge `1b12994993cf`) | Kernel driver | J815 | NOT APPLICABLE: it changes the T8142 driver, not `centauri/t6050/` |
| 3 USB-C | linux #1648 commit `377b2a2decf1` (USB part) | Device tree. Left-front and right ports: SN201202x controllers on nub-spmi-a0/a1, ATC1/ATC2 PHYs, dwc3, DARTs, `atcphy1`/`atcphy2` aliases | K116s, Jens (PR): "N1 Wi-Fi associates, USB-C, SMC sensors, panel, speakers (with speakersafetyd) …" | CLEAN BACKPORT CANDIDATE as a K114s copy |
| 3 USB-C | linux #1714, MERGED 2026-11-13 (merge `ac601eaaa114`); `3cfb8158eb44`, `6fd895b4776e` | Device tree, K114c | K114c, joshuaswarren: "a Realtek RTL8156 USB Ethernet adapter … enumerated as SuperSpeed … ssh over the adapter worked"; right-port data device "not tested" | ALREADY IN BASE (behind 221), K114c only. A second worked example |
| 4 Display | aura #226, MERGED 2026-11-13 (merge `6ba9efc90858`), commit `023eb3a01a61` | Boot loader. Admits the 27.2 DCP image `3D6C8857-E6F1-3D2E-9DFF-587028AE0C6E`; internal panel only | K116s, Jens: "`Initialized apple` at 2.2 s, eDP-1 connected at 3472x2170, no USB-C controller errors" | CLEAN BACKPORT CANDIDATE with a hand merge: our aura patch 0005 edits the same gate and pins `C51FB0C8-…` (the J714s image) for 27.2. Keep both |
| 4 Display | linux #1648 `377b2a2decf1` + `3adc985b5a61`; #1859 MERGED 2026-11-14 (merge `292773fcbd65`), commit `59ea61054b1e` | Device tree. `dcp`/`disp0` aliases, display subsystem, DART ranges, `apple,clock-ids = <361 458>`, panel node. #1859 removes `clocks` and `apple,bw-scratch`, which the loader adds and otherwise refuses | K116s, Jens: "the panel is handed over, apple-drm initialises at 2.1 s, desktop at 3472x2170; GPU, Wi-Fi, sound and KVM come up" | CLEAN BACKPORT CANDIDATE as a K114s copy. The kernel's 27.2 method table is ALREADY IN BASE |
| 4 Display | linux #1868, MERGED 2026-11-14 (merge `1177fdf5f98c`); `a4a0fb67bfe8`, `10f14b7ff802`, `3176918ba21e`, `84b3b93c04e6` | Kernel driver. Only the 120 Hz mode on the T6050 internal panel | K114c: "a modeset to 3024x1986 at 60 Hz crashed the internal DCP" | CLEAN BACKPORT CANDIDATE. **OLED crash report.** Shares three files with our series; betizzel's rebase onto head kept those patches unchanged |
| 4 Display | linux #1873, OPEN draft, head `e2ebdd70f46e` | Kernel driver. Alpha-only formats on the internal primary plane | K114c: "the panel lights only where the pixel has red"; with the PR "Hyprland with stock Aquamarine aborts" | Do not backport. Userspace half is ALREADY IN BASE (hyprland-m5 alpha-scanout patch). **OLED problem report** |
| 4 Display, lid | linux #1688, OPEN draft, head `67e63a577af4`; commits `1006491abe42`, `76c5ea390d74` | Kernel driver + device tree. simpledrm reports the built-in panel as eDP | K114c: "connector is Unknown-1, so Omarchy counts it as an external monitor … Closing the lid never suspends"; earlier boot showed "card0-eDP-1" | CLEAN BACKPORT CANDIDATE. Matters today, while K114s is on the boot framebuffer. Not booted in this form |
| 4 Display logs | linux #1646, OPEN, head `907bb7ec5990` | Kernel driver. Answers the panel temperature request on OLED, quiets 27.2 D590 | K116s, Jens | Optional. Changes what the firmware is told on OLED |
| 4 Brightness | linux #1696, OPEN, head `55d5f6d05618` | Kernel driver. Firmware 27 presents no longer dropped by the backlight path | J813 only | Optional. No OLED brightness result exists anywhere |
| 5 SMC | linux #1648 commit `377b2a2decf1` (hwmon part) | Device tree. `smc_hwmon` on, dual-fan and laptop includes, fan mode keys `F0md`/`F1md`, die-temperature keys removed | K116s, Jens ("SMC sensors") | CLEAN BACKPORT CANDIDATE as a K114s copy |
| 5 Battery | linux #1615, OPEN draft, head `089b082fa329` | Kernel driver. Unreadable manufacture date no longer aborts the battery uevent | K114c: battery "already reports charge, status, power and time left"; but "uevent prints nothing" and 44 error lines. Fix "Not yet booted" upstream; on our r3a it is booted and the errors are gone (agent-run, `r3-power.md` #52) | Optional small backport |
| 5 PMP | linux #1789, OPEN, head `f61eb4550a95` | Device tree. PMP power domains always on | K116s, Jens: PMP crashed at wake "in 3 of the 4 suspends"; with it "4 s2idle cycles so far, all clean" | Take it together with the PMP nodes (`7e584a680b77`) if sound is enabled |
| 6 GPU kernel | linux #1650, OPEN draft, head `4ac2c69dd0b8` (on #1173, OPEN draft, `d8ca53c82e52`) | Kernel driver. Identifies the 26B8125 G17S firmware | K116s, Jens: "Vulkan works (vkcube) and Plasma composites on it, with `ASAHI_M5_BRINGUP=1`" | ALREADY IN BASE as patches 0001 and 0005 (digest `af68d034…` is in the patch). Upstream head still lacks it |
| 6 GPU loader | aura #187, MERGED 2026-11-13 (merge `0f87f1fcb1cc`) | Boot loader. Admits the 26B8125 G17S build | K116s: "`T6050 G17S 26B8125 enabled`" | ALREADY IN BASE (behind 3) |
| 6 GPU tree | linux #1648 commits `e3373ad8f86a`, `8f418a490a97` | Device tree. GPU, mailboxes and reservations for the loader; compatible `apple,agx-g17s` | K116s, Jens. Uses the J714 voltage tables, "5 mV below this unit's ADT voltages at eight of the 14 states" | CLEAN BACKPORT CANDIDATE as a K114s copy |
| 6/7 GPU + sleep | linux #1844, MERGED 2026-11-13 (merge `adb5a7e344f5`); `41c359da8175`, `788441e0890e` | Kernel driver. GPU mailboxes by interrupt | K116s, Jens (#1843, on `aa68b3c81830`, 40 commits before our base; he cherry-picked his fix "onto a34d26c255c2"): suspend with the lid open "never wakes, 2 of 2". With #1844: "18.1 s asleep, woken by a key, `suspend_stats` success 1" | CLEAN BACKPORT CANDIDATE (`mailbox.c` only). **The polling code that panics is still in our base, so expect it once the GPU is on** |
| 7 Deep sleep | linux #1772–#1785 withdrawn; aura #214, OPEN draft, `dc1b4f3424c3` | Kernel + loader | J714s only. Jens: on 27.2 "it would send the wrong calls" | NOT APPLICABLE |
| 8 Sound | linux #1648 commits `45f4de446485`, `dac02289da54`, `8f5a2223fd3a`, `f25b8eb19c92`, `7e584a680b77` | Kernel + device tree. K116 sound card on the J714 configuration; amps, jack, microphones; PMP. The loader copies each amp's `apple,speaker-config` | K116s, Jens: speakers "with speakersafetyd"; jack codec probes; microphone commit says "not tested on the hardware yet" | NEEDS our own `apple,k114-macaudio` entry. AOP start on 27.2 (#1645) is ALREADY IN BASE as patch 0019 |
| 8 Sound | linux #1787, OPEN, head `48243e8f3d32` | Kernel driver. No "Bus stuck" on the amp buses at boot | K116s, Jens: "11 of 11 boots clean since" | Take with sound |
| 8 Camera | aura #188, MERGED (is `22b71758`) | Boot loader. Camera row for K116s, sensor 0xbc, 27.2 | K116s | ALREADY IN BASE, but K116s-gated. K114s needs its own row and sensor type |
| 9 Updates | omarchy-m5 installer patch 0019 | Image. `IgnorePkg` pins kernel, loader and firmware packages | CI update check | ALREADY IN BASE. It does not stop a manual `pacman -U` of the J714s packages |
| 9 Updates | omarchy-m5 `0abeef96d6` (firmware j714s10, release omarchy-j714s 4) | Userspace. Mounts `/boot` and `/boot/efi` from the partitions the system booted from | J714s: "Not yet tried across a restart" | In the recipe folder; check which version the trial image installed |
| 9 Updates | joshuaswarren/m5-omarchy-install `b9d08697efd4` | Userspace script, K114c. Ignores `linux-aurora* linux-asahi* m1n1* grub limine* uboot-asahi omarchy-mac-boot`; masks `first-boot.service` and `linux-modules-cleanup.service` | K114c | Useful only if the repair kernel is installed outside pacman |
| 9 Newer base | betizzel/omarchy-m5 `9f943c0f1d06` (v272-5) | Recipe. Our series rebased onto `a31b32f72efd`, which already holds #1830, #1648, #1859, #1844 and #1868 | "NOT booted, NOT installed, NOT in any release" | Alternative to cherry-picking. `a31b32f7` contains `f8a53798bbfd`, which upstream reverted at 07:59 UTC the same morning (#1885: GPU firmware crashes under sustained Vulkan on M1 Pro). Pin `5b36eff41af7` or later instead |

## (a) Five most valuable backports, in order

1. **Trackpad.** K114s tree override from `377b2a2decf18868da7fad51ea9942500a3ba00f` (AFE reset on
   `smc_gpio_low 28`, active low), then `07687621d1ce326d88680643245cb99d04b6eeb6` and
   `a68b43218e4143595997c5c792b927daefd3b6fb`.
2. **Wi-Fi.** `b0d53446f84db5a452b782fdca6cb64ae2d1c1b0`, a K114s port 0 modelled on
   `24c62c0cf4bfcbb9a30bc3666b1dd0b12817e01c` (`0x00146050`, `apple/centauri/k114s-ftab.bin`), our
   own `apple,k114s` admission in `aurora-peripheral-firmware.sh`, then
   `aa16d423cf8a10e6bee0a79313a13fa9565292c6` with a K114s line so suspend still works.
3. **USB-C and SMC sensors.** The USB and hwmon parts of `377b2a2decf1…`, as a K114s copy. This
   also gives a wired recovery path (USB Ethernet, keyboard, mouse).
4. **Internal display.** aura `023eb3a01a61c4c6c906709c8436092f111d3108` merged with our patch 0005;
   the display nodes of `377b2a2decf1…` in the form `59ea61054b1e601a5c32fb11d6906be51f23587a` leaves
   them; binding `3adc985b5a61d091eb869343c9b29e0eb1407cc0`; then #1868's four commits
   `a4a0fb67bfe8e1eb4023533745aa81dd412fb885`, `10f14b7ff802a824c60cfa171848a468edb95d50`,
   `3176918ba21e898d007ee9c45c4f8ca41ed548cd`, `84b3b93c04e68f7e7e5c9cffcded47d4ddd579fb`.
5. **GPU.** `8f418a490a97dfff028df87a191c65ae8fe0b3aa`, a K114s copy of
   `e3373ad8f86a46d858fdbcb98196d7f6230ee3b5`, and `41c359da81755d96315191bc650872e4ec92d94a` +
   `788441e0890e18493d72e7df1445f01a844f1061` in the same build, or lid-open suspend panics.

Cheap extra while the panel is still the boot framebuffer: `1006491abe42bbbdecc4491e68815bfe77093202`
and `76c5ea390d74c77fab63fb7a1ad98a7013ee386f` (#1688), so closing the lid can suspend.

## (b) Reported as not working on K114c or K116s today

K114c (joshuaswarren, M5 Max, 27.3 beta 1):
- "Not working yet: sound, the display backlight, the camera, Touch ID, deep sleep" (kernel release notes, 2026-11-11).
- Bluetooth: "the function enumerates (106b:1903) but no driver binds yet" (#1603).
- Touchscreen: frames stream, finger events unverified; the unit went away for a "touch hardware fix" (#1605).
- Lid close never suspends on the boot framebuffer (#1688).
- A 60 Hz modeset crashes the display coprocessor (#1868, fixed upstream after our base).
- XRGB8888 is read as alpha: wrong colours unless the compositor writes alpha (#1873).
- Right USB-C port: no data device tested; no USB4 device ever plugged in (#1714, #1841).
- Keeping NVMe live across s2idle crashed the storage firmware about 60 s in (#1698).

K116s (Jens Axboe, M5 Pro, 27.2 26B8125):
- Suspend with the lid open and the GPU active panics on `a34d26c2` (#1843; fixed by #1844).
- The PMP crashes at wake in 3 of 4 suspends without #1789; s2idle is refused without #1647.
- Every 6 GHz join fails; the cause is unknown, a workaround is in base (#1725).
- External displays on 27.2: `dcpext0` hits the deferred-probe timeout and delays the display by 16 s, so the loader hands off the internal panel only (aura #226).
- "Bus stuck" errors on the speaker buses on some boots (#1787).
- Touchscreen disabled: its pins are not described. SD reader probes, no card tested. CPU PMU and the CLPC's SMC link held back as untested.
- Deep sleep cannot run on 27.2 (aura #214 comments).

## (c) Open questions

1. Which HID product does the K114s trackpad report? #1830 only handles 0x0362. `dmesg | grep -iE 'magicmouse|report_size'` on the Mac answers it.
2. Does the K114s load the same 27.2 display image as the K116s (`3D6C8857-…`)? Its own ADT has to confirm, along with the camera sensor type and panel size. joshuaswarren's K114c values are 3024x1986, 254.6 ppi, 302 x 198 mm (derived, unverified).
3. Bluetooth on K-boards: no confirmed working report. It works on J714s with the same driver.
4. OLED brightness control: nobody has reported it working. The K116s log shows only "1000 nits".
5. Whether `apple/tpmtfw-k114s.bin` and `apple/centauri/k114s-ftab.bin` exist on the installed system, and which firmware package version the trial image carries.
6. None of the cherry-picks was test-applied. The v272-5 rebase has not booted anywhere.

## Addendum 2026-11-14 (evening): betizzel `886269a`, nickfoy `8c16310`, upstream `7c71d6df`

Read-only source review after two leads from the owner: nickfoy/omarchy-m3-max, then betizzel/omarchy-m5
("seems better"). Nothing here was built, applied or booted. Bundle r1 is unchanged (36 of 36
checksums match). The gaps this review found are listed in `edge-update-path.md`.

### Heads read

| Source | Head | What it is for us |
| --- | --- | --- |
| betizzel/omarchy-m5 | `886269a95914` (2026-11-14) | Primary M5 integration reference and our installer base. Release 4 is J714s-only: `installer/app/make-release-inputs.py` has `BOARD = "apple,j714s"`, `DEVICE_CLASS = "j714sap"`. Its stock installer must not be run on the K114s |
| aurora-silicon/linux `integration/aurora` | `7c71d6df6563` | 48 commits past `5b36eff41af7` (32 non-merge): GPU g17 and drm/apple only. `t6050-k114s.dts` unchanged since Nov 8; the K114s PCIe host is still disabled upstream |
| aurora-silicon/aura `main` | `be9469167b91` | 155 commits past `3351432dd632`: SPTM and auractl work. No K114/K116 change |
| nickfoy/omarchy-m3-max | `8c16310fb578` (3 commits) | Mac15,10 / J514M / T6034 (M3 Max). Maintenance and recovery tooling only; installs nothing |
| omacom/omarchy | `a948d8a6871f` (v4.5.0) | The Omarchy the image set was built from (`omarchy 4.5.0-3.7141`); read for the refresh and update scripts |
| omacom/omarchy-mac-pkgs | `7e50e937b5f3` | The set's `omarchy-mac-boot 20261104-1`; read for the post-update boot check |

### betizzel release 4: boot partitions found by partition ID

- What it fixes: every image carries the same filesystem IDs (ESP `4F4D-5801`, `/boot`
  `4f4d5801-424f-4f54-8000-000000000001`) and `/etc/fstab` mounts by them. With two Omarchy installs
  on one disk a kernel update can land on the other install's partitions. Firmware `j714s10` adds
  `aurora-boot-mounts-generator`, which mounts the ESP named in
  `/proc/device-tree/chosen/asahi,efi-system-partition` and the ext4 `OMARCHY_BOOT` partition after
  it, by `PARTUUID`. Tested on their J714s as a dry run, reload and remount; not across a restart.
- This Mac: one install. `diskutil list disk0` shows one Linux ESP (`disk0s4`), one 2.1 GB `/boot`
  (`disk0s5`) and one root (`disk0s6`). The authors state a single install is not affected.
- It does not explain the trackpad error or the missing radio. Those are the driver and device-tree
  items in rows 1 and 2 above.
- The trial image carries firmware `j714s9`, so the generator is not installed.
- Our scripts: the macOS tool finds the ESP by its contents and checks the installed kernel hash.
  The Linux-side `update-boot-ctxr-k114s` and `linux-persist.sh` trust whatever is mounted at
  `/boot/efi`. They check that `boot.bin` starts with the installed m1n1, but not that the mount is
  the ESP this boot came from.
- Reuse: only the identity check (about ten lines: booted-ESP `PARTUUID`, next partition is ext4
  with label `OMARCHY_BOOT`), as a refuse-to-write guard in a later revision of the Linux scripts.
  Not the `j714s10` package: it also carries J714 audio, camera and display files, and its fix
  procedure reinstalls the J714s kernel and loader packages.

### betizzel v272-5 (`9f943c0f1d06`): nothing missing for the trackpad or Wi-Fi

- The rebase range `a34d26c255c2..a31b32f72efd` is 188 commits here (the author counts 190). Built
  with `check()` 35 OK; "NOT booted, NOT installed, NOT in any release".
- For what r1 repairs, the range holds #1830 (in r1a, with product 0x0361 admitted) and the #1648
  device-tree commits (ported in the r1 tree with K114s identity). Nothing else in the range is
  needed for the trackpad, the N1 or the USB-C host ports.
- Checked and ruled out: `6da90cd1fee` and `f281cf9a41d` ("wifi: apple: centauri: …") change
  `centauri/centauri_ipc.c` and `centauri/centauri_wifi.c`. The M5 Pro driver
  `apple_centauri_t6050` is built from its own copies in `centauri/t6050/` (Makefiles at
  `a34d26c2`), so neither reaches the K114s radio.
- One driver difference touches hardware r1 turns on: `218e3f8550b` (tipd `sn201202x`, probe
  asynchronously, `drivers/usb/typec/tipd/spmi.c`). It is a probe-order change, not a reported K116s
  fix. Look at it first if the USB-C ports do not enumerate on r1.
- Still missing everywhere: #1647 (`aa16d423cf8a`, `70bf8ed1867b`), suspend with the N1 link up.
  It is in neither `a31b32f7` nor head `7c71d6df`. With the N1 on, suspend is refused on our base
  and would be on v272-5 too.
- The rest of the series delta is J714s HDMI (v2 hold, IRQ_HPD forwarder) and the AOP patch going
  upstream. The K114s display is the boot framebuffer in r1, so none of it applies yet.
- `a31b32f7` still contains `f8a53798bbfd`, reverted upstream by `018c588abf8`. A K114s package
  build should pin `5b36eff41af7` or later, as noted above.
- Decision: no rebase before the hardware test. v272-5 stays the candidate base for the packaged
  kernel in the Edge plan, with the same "never booted" label its author gives it.

### nickfoy/omarchy-m3-max: what carries over

It does not install an OS. Its update preflight is report-only, runs against a private copy of the
package database, and by its own text cannot see file lists, scriptlets or removals: a clean solve
still comes back REVIEW REQUIRED. Its pre-transaction guard is a proposal, not installed. It is not
a turnkey Edge updater, and its AGENTS text carries no authority here.

| Idea | Where | Use for the K114s |
| --- | --- | --- |
| Solve the pending upgrade in a private database copy: `fakeroot pacman -Sy --dbpath COPY`, then `pacman -Sup --dbpath COPY --print-format '%n\|%v\|…'` | `lib/update_preflight.py` | Reusable as written (plain pacman). Shows exactly which packages an update would change before anything is touched |
| Compare installed versions with the repository's and flag "local newer" | same | Useful: several set packages are local builds that Edge may sort above or below |
| A recovery set is root snapshot + `/boot` + ESP + package database and archives from the same moment | `docs/recovery.md` | Applies: our backup covers only the ESP files the repair changes |
| Reinstall only from a named, matched archive set, never a glob or the whole cache | `docs/recovery.md` | Applies to the three coupled packages |
| Lists of boot-coupled and display-coupled package names and protected paths | `config/pacman/protection-policy.json` | A checklist for our hold set. M3 names differ |
| The installed boot check and `update-verify` may rebuild boot files after a snapshot restore | `docs/recovery.md`, `docs/update-policy.md` | Confirmed in the set's own `omarchy-mac-boot` source; see the hold audit |
| Treats any `IgnorePkg` as a blocker (partial upgrade) | `lib/update_preflight.py` line 28 | The opposite of what betizzel and we do. Holds stay necessary while Edge has no K114s packages, but they must cover the whole coupled set |
| M3 GPU, device-tree, firmware, lid and sleep settings; an approval step per update | docs, manifests | Do not copy |
