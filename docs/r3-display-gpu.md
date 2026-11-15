# r3 candidate: the internal OLED panel on the display coprocessor, and the GPU

Worker notes for branch `r3/display-gpu`, 2026-11-14. Scope: move the K114s panel from the boot
framebuffer to the display coprocessor (DCP: native mode, 120 Hz, `apple-drm`) and turn on the GPU
(AGX G17S), both at the level the 16-inch twin (K116s) has upstream.

> **Status (2026-11-15).** Step 2 (the GPU tree on the installed loader and the running kernel)
> has run on the K114s and works: see [r3-gpu-result.md](r3-gpu-result.md). Steps 1, 3 and 4, both
> patch series and the r3 loader are an **untested design**. Do not run step 3 or 4 as written:
> their macOS rollback for loader variants is not implemented, and the loader's one-boot trial
> (`aura-try`) is the intended route. The text below is the design as written before step 2 ran.

**When this was written, nothing in this branch had run on a K114s.** Everything below is source review, compilation and
replica tests, plus read-only observations on the running machine. Evidence labels: *owner-observed*,
*agent-run* (a command the agent ran on this Mac or in its build area), *replica* (software test with
no Apple hardware or data behind it).

## What is in the branch

| Path | What |
| --- | --- |
| `patches/linux/display-gpu/0001`–`0010` | Kernel series: upstream commits, cherry-picked unchanged onto the running kernel's source |
| `patches/aura/0001`–`0003` | Loader (Stage 2) series: upstream's K116s panel hand-off hand-merged with betizzel's 27.2 patch, the GPU firmware hint, a test stub fix |
| `dts/t6050-k114s-display-gpu.dtsi` | K114s copies of the K116s display and GPU sections, in three switchable parts |
| `dts/t6050-k114s-r3-edp.dts`, `-r3-gpu.dts`, `-r3.dts` | Three trees for the staged test: r1 + eDP mark; r1 + GPU; everything |
| `tests/lint-display-gpu-dtb.py` | Repeats the device-tree side of the loader's checks; compares the nodes with the K116s tree |
| `tests/k114s-adt-display-facts.py` | Root-run, read-only: reads this Mac's Apple device tree (ADT) and answers the open questions |
| `tests/test-adt-display-facts.py` | Replica test of that reader on a synthetic ADT |
| `tests/aura/test-t6050-image-gate.py` | Host test of the merged loader gate that admits or refuses a DCP firmware image |

## Findings that change the plan

1. **The installed loader already has both hand-offs.** (*agent-run*: source of aura `22b71758` plus
   betizzel's seven patches, the build this Mac boots, `asahi,m1n1-stage2-version`
   `1.0.0b13-g22b71758-dirty`.)
   - GPU: `src/kboot_gpu.c` admits a firmware build by digest, not by board, and the K114/K116 build
     `26B8125` is in its table (aura #187). A tree that describes the GPU is enough. **The GPU needs
     no new loader.**
   - Display: `t6050_handoff()` runs whenever the tree has the `dcp` and `disp0` aliases. There is no
     `chosen` switch to arm it. On 27.2 the installed loader pins one image, the J714s one
     (`C51FB0C8-…`, betizzel's patch 0005). For any other image it refuses and the boot framebuffer
     keeps the panel. **The panel needs the new loader, and the old loader is a ready-made test of
     the refusal path.**
2. **The Mac's own ADT is readable from Linux, as root.** `/proc/mtd` lists `mtd2 "adt"`
   (0xbc000 bytes) and `mtd1 "aura_stage2.log"` (*agent-run*). The image question needs no reboot.
3. **The kernel configuration needs nothing.** See "Kernel configuration".
4. **The session switches itself.** `omarchy-aurora-firmware j714s9`, installed here, has a systemd
   user environment generator (`60-aurora-m5-display`): when the card
   `/dev/dri/by-path/platform-display-subsystem-card` exists it exports `AQ_DRM_DEVICES` (scan out on
   the DCP card), `AQ_NO_MODIFIERS=1`, `MESA_LOADER_DRIVER_OVERRIDE=zink` and `ASAHI_M5_BRINGUP=1`.
   So a panel hand-off **without** the GPU would leave Hyprland asking zink for a Vulkan device that
   is not there. The plan therefore never enables the panel before the GPU.
5. **The EFI partition has about 88 MB free** (*agent-run*, `df /boot/efi`). An r3 kernel image as a
   second 112 MB file does not fit beside the repair kernel. A device tree or a whole Stage 2 does
   (about 4 MB). This shapes the order below.
6. **The r3 loader is 64 KiB larger** than the installed one (4063232 against 3997696 bytes,
   *agent-run* build): 208 bytes of new strings push the relocation table over a 64 KiB boundary.
   The macOS tool splits `boot-ctxr.bin` at `aura_prefix_bytes` from the manifest; a Stage 2 variant
   with the new loader needs its own value.

## Sources, commit by commit

All read in full upstream. "Clean" means `git cherry-pick` applied with no conflict onto
`a34d26c2` + betizzel `linux-j714s-27.2.patch` (v272-4, 19 patches) + pull request 1568, the source of
the running `K114S-R1` kernel (*agent-run*).

| Piece | Upstream | Author | What it does | Here |
| --- | --- | --- | --- | --- |
| GPU mailboxes by interrupt | linux #1844: `41c359da8175`, `788441e0890e` | Erik Bourget, DjDeveloperr | `drivers/soc/apple/mailbox.c` goes back to interrupt-driven receive for the T6050 GPU mailboxes; removes the polling that panics at suspend with the lid open (#1843) | `0001`, `0002`, clean |
| Only the 120 Hz mode | linux #1868: `a4a0fb67bfe8`, `10f14b7ff802`, `3176918ba21e`, `84b3b93c04e6` | Joshua Warren | `dcp_mode_settable()` refuses every mode but 120 Hz on the T6050 internal DCP (`only_120hz_modes`). A 60 Hz modeset crashed the DCP on the OLED K114c | `0003`–`0006`, clean. **Required** before the panel moves |
| Boot framebuffer as eDP | linux #1688: `1006491abe42`, `76c5ea390d74` | ed (Eduard Moldovan), Joshua Warren | simpledrm gives a framebuffer node with `apple,internal-panel` an eDP connector; the shared K114/K116 file gets the property | `0007`, `0008`, clean. Draft upstream, "not booted in this form" |
| Panel binding | linux #1648: `3adc985b5a61` | Thomas Glanzmann | binding accepts `apple,panel-k<n>` | `0009`, clean, documentation only |
| GPU binding | linux #1648: `8f418a490a97` | Thomas Glanzmann | binding tells the two G17S layouts apart | `0010`, clean, documentation only |
| K116s display nodes | linux #1648 `377b2a2decf1`, as #1859 `59ea61054b1e` leaves them | Jens Axboe | aliases, display subsystem, DART windows, panel; no `clocks`, no `apple,bw-scratch` | K114s copy in `dts/` (not a kernel patch) |
| K116s GPU nodes | linux #1648 `e3373ad8f86a` | Jens Axboe | GPU, two mailboxes, six reservations, GPX/AFR always on | K114s copy in `dts/` |
| K116s panel hand-off | aura #226 `023eb3a01a61` | Jens Axboe | pin table keyed by OS firmware; adds the 26B8125 image `3D6C8857-…`; internal panel only on 27.2 | `patches/aura/0001`, **hand merge**, see below |
| GPU firmware hint | aura #230 `5d2ec8f00e99` | Jens Axboe | `apple,firmware-version` on the GPU node, so the driver tries the right build first and logs no false errors | `patches/aura/0002`, clean |
| OLED alpha plane | linux #1873 `e2ebdd70f46e`, open draft | Joshua Warren | alpha-only primary plane on T6050 | **not taken**, see "OLED risks" |
| Log noise, brightness | linux #1646, #1696, open | Jens Axboe / Thomas Glanzmann | PMU temperature answer on OLED; presents without a surface | not taken; candidates once the panel is up |

Already in the running kernel (betizzel's series): the 27.2 DCP method table (`dcp_methods_27_2`,
chosen by `apple,firmware-compat = "27.2.0"`), the G17S driver with the `26B8125` firmware identity
(#1173, #1650), the VRR patch (0014).

### The loader merge (`patches/aura/0001`)

betizzel's patch 0005 and upstream's #226 rewrite the same lines of `t6050_check_adt()`:

| | Admits | Image | External engines |
| --- | --- | --- | --- |
| betizzel 0005 (installed) | 27.0, 27.2, 27.3 beta 1 | 27.0 pinned; 27.2 pinned to `C51FB0C8-…` (J714s, 26B123); 27.3 any | always attempted |
| upstream #226 | 27.0, 27.2 | 27.0 pinned; 27.2 pinned to `3D6C8857-…` (K116s, 26B8125) | 27.0 only |
| merged | 27.0, 27.2, 27.3 beta 1 | table: 27.0 image; **both** 27.2 images; 27.3 any | 27.0, J714s 27.2 and 27.3 as before; **not** for the K116s image |

betizzel's structure is kept (the UUID is copied from the ADT, `apple,firmware-compat` comes from the
running firmware); upstream's table and its per-image `ext` flag are added. The commit keeps Jens
Axboe as author and says in its message what was merged. `patches/aura/0003` is ours: the host test's
`firmware.h` stand-in lacked `V27_3B`, so upstream's display host test did not compile on betizzel's
series at all.

Tested (*replica*):
- `tests/aura/test-t6050-image-gate.py` compiles the merged gate's own text and runs 12 cases: the
  three pinned images are admitted only under their OS firmware, the K116s image without external
  engines, an unknown, lower-case or malformed UUID is refused with the UUID in the message.
- aura's `tests/run-t8122-display-handoff.sh` passes on the merged tree (it covers the T8122 paths;
  upstream's fixture does not model the T6050).
- The Stage 2 builds with the recipe's flags (`RELEASE=1 CHAINLOADING=1 ESP_STAGE2=1`), 4063232 bytes.

## The DCP firmware image question

**Does the K114s load `3D6C8857-E6F1-3D2E-9DFF-587028AE0C6E`, as the K116s does?** Not known yet.
What speaks for it: both boards restore from the same 27.2 image (26B8125), and the DCP firmware in a
restore image is one file per chip family (`Firmware/dcp/t605xdcp.im4p` in betizzel's notes), not per
board. That is inference, not a reading.

**How to find out, cheapest first:**

1. Now, no reboot (root): `sudo python3 tests/k114s-adt-display-facts.py`. It reads
   `/arm-io/dcp/iop-dcp-nub` `uuid` from this boot's ADT and says which loader pins it.
2. Without root, at any boot of a tree that has the display aliases:
   `cat /proc/device-tree/chosen/asahi,t6050-dcp-handoff` is `published` or `refused` (the property
   is absent today, because the r1 tree has no aliases: *agent-run*). After a hand-off the UUID is in
   `/proc/device-tree/soc/dcp@48ae00000/apple,firmware-uuid`.
3. The loader's own words (root): `sudo cat /dev/mtd1ro | tr -d '\0' | grep -E 'DCP:|GPU:'`. Expect
   `DCP: T6050: DCP image <uuid>, firmware-compat 27.2`, then either
   `internal display handed off: firmware 27.2, …` and
   `external display engines not handed off on firmware 27.2`, or
   `DCP image <uuid> is not one pinned for OS firmware 27.2` and
   `internal display handoff refused; the boot framebuffer keeps the panel`. The log is a 16 KiB
   buffer; whether late lines survive a long boot log is not verified.

**If it differs:** `t6050_check_adt()` returns before anything is written. The display nodes stay
disabled, `/chosen/asahi,t6050-dcp-handoff` is `refused`, the kernel never loads `appledrm` for the
panel and simpledrm keeps the picture: the state this Mac is in today. The gate test above covers
that path. A different image must **not** simply be added to the table: the kernel talks to the
27.2 firmware with method numbers confirmed on the K116s image (AppleDCP-1317.40.16), and the firmware
answers an unknown number with a panic. A new UUID means checking that image's method table first.

## Device tree

`dts/t6050-k114s-display-gpu.dtsi` is included after `t6050-k114s-common.dtsi` and has three parts:

| Define | Adds | Compared with the K116s tree (`0b03fe43`) |
| --- | --- | --- |
| `K114S_R3_EDP` | `apple,internal-panel` on `framebuffer0` | same property (via the shared file upstream) |
| `K114S_R3_DISPLAY` | aliases `dcp`, `disp0`; `display-subsystem`; `apple,dma-range` on both DARTs; `panel` | identical except the panel node and `apple,clock-ids` |
| `K114S_R3_GPU` | alias `gpu`; six empty reservations; `gfx_mbox`, `gfx1_mbox`; GPX/AFR always on; `sgx` as `apple,agx-g17s` | identical except the GPU's power domain |
| `K114S_R3_GPU_PMP` | GPU on the PMP report entry | the K116s form; off, see below |

`tests/lint-display-gpu-dtb.py --k116s` checks that statement property by property (*agent-run*,
passes: the only differences are the five listed in the script).

**The 14-inch panel.** Upstream has no 14-inch OLED panel node: `t6050-k114c.dts` describes no
display at all, and the shared `t6050-k114-k116.dtsi` only the boot framebuffer. The K116s node is
`"apple,panel-k116", "apple,panel"`, 345 x 223 mm, with the comment "The ADT carries no dimensions;
these are the panel's active area, for the DPI only". The K114s node here:

- `compatible = "apple,panel-k114", "apple,panel"` (binding `3adc985b`). Not `apple,panel-mini-led`:
  that selects the mini-LED backlight path.
- `width-mm = <302>`, `height-mm = <198>`: 3024 x 1986 pixels at 254 per inch is 302.4 x 198.6 mm.
  3024x1986 is this Mac's boot framebuffer (*agent-run*: `/sys/class/graphics/fb0/virtual_size`).
  254 ppi is the figure joshuaswarren derived for the K114c (254.6), not a measurement. The values
  set the reported DPI only; the kernel replaces them when the ADT has a panel node with sizes and
  logs `panel ADT: parsed, panel node present|absent, dimensions WxH mm`.
- No `adj-height-mm`: the loader shows the notch rows (`asahi,show-notch = "1"`, *agent-run*).
- No `apple,clock-ids`: the loader writes it from the ADT in every hand-off, so the tree carries one
  unverified value less.

**The GPU's power domain.** The K116s puts the GPU on the PMP's report entry (`pmp0_gfx`), which
needs the PMP running with K116s tunables read from its ADT. r3 does not run the PMP on the K114s
(that is the sound/power candidate, and it needs this board's tunables), so the GPU sits on `ps_gfx`
directly: the form `t6050-k114c-gpu.dtsi` uses in the same base, and the J714s used before its PMP
work. With `K114S_R3_GPU_PMP` and no PMP the GPU would wait for its supplier forever; the lint fails
such a tree.

**One difference outside the compared nodes.** The GPU node points at the CLPC (`apple,clpc`,
"raises the DRAM and fabric floors while GPU work is in flight"). The K116s tree holds two things
back as untried on that board (linux `cd2c9f52`): the CLPC's SMC link and the CPU PMU. The K114s
r1 tree has both, and this Mac runs with them today (*agent-run*: `apple-clpc` is bound, the tree
has `apple,smc` on it). So the K114s GPU meets a CLPC in a state the K116s did not test. If the GPU
step misbehaves under load, removing `apple,smc` from `&clpc`, as the K116s tree does, is the first
thing to try.

**What must come from this Mac's ADT** (and who reads it):

| Value | Read by | In the tree? |
| --- | --- | --- |
| DCP image UUID, "running" | loader, every boot | no |
| `/vram`, DCP segments | loader | no |
| bandwidth scratch (PMGR `bwr-agent`, disp0 `function-bw_req_interrupt0`) | loader | no |
| disp0 `clock-ids` and `/arm-io` `clock-frequencies` | loader | no |
| `/backlight-override` `user-accessible-max-nits` (brightness scale; 1000 on the K116s) | loader; refuses without it | no |
| `/product` `artwork-display-gamut` | loader | no |
| dcp and disp0 registers, DART bases, DVA windows, stream roots `l1-tt-23/0/16` | loader compares with the tree, refuses on a mismatch | yes, from upstream's inventory |
| GPU firmware and UAT ranges, firmware digest, leakage calibration words | loader | no (reservations are empty) |
| GPU and mailbox registers and interrupts | nobody at boot | yes, K116s values |
| Panel size, panel identity | kernel, from the ADT if present | fallback 302 x 198 |

The last-but-one row is the one the loader does not protect: a wrong GPU mailbox interrupt would not
be refused. `tests/k114s-adt-display-facts.py --dtb` compares exactly those values with the ADT.

## Kernel configuration

No option has to change (*agent-run*: `/proc/config.gz` against the Kconfig of the series).

| Needed | Running kernel |
| --- | --- |
| `CONFIG_DRM_APPLE` (module `appledrm`, aliases `apple,t6050-dcp`, `apple,display-subsystem`) | `=m`, module installed |
| `CONFIG_DRM_ASAHI` (module name `aurora`; the T6050 G17S backend is part of it) | `=y` |
| `CONFIG_DRM_ASAHI_M5` | not set, correctly: it is the T8142 (MacBook Air) backend |
| `CONFIG_RUST`, `CONFIG_RUST_APPLE_RTKIT`, `CONFIG_RUST_APPLE_MAILBOX` | `=y` |
| `CONFIG_APPLE_MAILBOX`, `CONFIG_APPLE_RTKIT`, `CONFIG_APPLE_DART`, `CONFIG_APPLE_PMGR_PWRSTATE` | `=y` |
| `CONFIG_APPLE_PMP_REPORT` (selected by both drivers), `CONFIG_APPLE_PMP` | `=y`, `=m` |
| `CONFIG_DRM_SIMPLEDRM` (the fallback picture), `CONFIG_BACKLIGHT_CLASS_DEVICE` | `=y` |
| `appledrm` soft dependencies `mux-apple-display-crossbar`, `atc-t6050-dp`, `macsmc-power` | modules present, last built in |
| `CONFIG_MTD_PHRAM` (the `adt` and loader log devices) | `=m`, loaded |
| `CONFIG_KUNIT` | not set: the test added by `0003`/`0004`/`0006` is not built |

Compile check (*agent-run*): with the running configuration, `drivers/soc/apple/mailbox.o`,
`drivers/gpu/drm/sysfb/simpledrm.o` and all of `drivers/gpu/drm/apple/` (36 objects, `appledrm.o`
linked) build without warnings from the patched source, clang 23.1.3.

## OLED-specific risks

1. **60 Hz modeset crashes the DCP** (K114c, #1868). Covered by `0003`–`0006`: only 3024x1986@120
   is offered. Never boot the panel hand-off on a kernel without them.
2. **XRGB8888's fourth byte is read as alpha** (K114c, #1873; betizzel saw the same on the J714s
   console: "only pixels with the fourth byte set to 0xff were visible"). In our base the T6050
   primary plane still advertises XRGB8888. What that means here:
   - Console: on firmware 27 the driver gives fbcon an ARGB surface (`apple_drm_fbdev_probe()` in
     the base: "an XRGB console with X = 0 stays black"), so console text is visible. The Plymouth
     passphrase screen draws through its own buffers; if `appledrm` is in the initramfs it is shown
     through the DCP, and nobody has reported that on an OLED K-board.
   - Hyprland: `hyprland-m5` 0.57.2 is installed. Its patch chooses ARGB only when the plane offers no
     XRGB; on our kernel it will pick XRGB8888. On the K114c, stock Hyprland's XRGB buffers had the
     red byte copied into the fourth, so "the panel lights only where the pixel has red". Whether
     the J714s-style two-card session (zink on the GPU, linear buffers) writes 0xff there on this
     panel is **not known**. Expect possibly wrong colours at the first panel boot; that is a
     picture, not a crash.
   - #1873 would fix it by removing XRGB from the plane, which `hyprland-m5` then handles (that is
     what its patch was written for). It is an open draft whose own boot check is "not verified yet",
     so it is not in this series. It is the first follow-up if colours are wrong: one small patch,
     same file set as `0006`.
3. **Variable refresh.** `omarchy-aurora-firmware` installs `options appledrm fw27_panel_vrr=1`
   (betizzel's patch 0014, tested on the J714s LCD only). It only advertises a range, and Hyprland's
   VRR is off in this user's configuration, but the K116s was not tested with it. First panel boots
   should carry `appledrm.fw27_panel_vrr=0` on the kernel command line (expected to override the
   installed modprobe option; `/sys/module/appledrm/parameters/fw27_panel_vrr` must then read `N`).
4. **Brightness.** Nobody has reported OLED brightness control working. The K116s log shows a fixed
   1000 nits scale. Expect a panel at whatever level iBoot left, and a `apple-panel-bl` device that
   may do nothing. Static desktop elements at a fixed high level are a burn-in concern on OLED: keep
   first sessions short and do not leave the machine idle on a static screen until brightness and
   idle blanking are confirmed.
5. **External displays** stay off on 27.2 (aura #226: `dcpext0` delays the display by 16 s).
6. **Mode and notch.** The K116s reported 3472x2170 with a 96-pixel notch through this loader and
   3472x2266 through an earlier one; Jens did not find out which property makes the difference. The
   K114s may likewise come up with a height other than 1986.

## Mesa and the session

- Installed: `mesa-aurora` and `vulkan-aurora` `26.3.0_devel.20261109.j714s2.043a4c5`, ICD
  `/usr/share/vulkan/icd.d/asahi_icd.aarch64.json`, `aquamarine 0.16.0-1.1`, `hyprland-m5 0.57.2-2`.
- **Yes, it needs `ASAHI_M5_BRINGUP=1`**: both `libgallium` and `libvulkan_asahi.so` test it, and
  the package's own `/usr/lib/environment.d/90-omarchy-j714s-gpu.conf` says "the pinned driver still
  requires explicit M5 admission". It is already set: that file exports it to every systemd user
  session (*agent-run*: it is in this session's environment), and the display generator sets it for
  the SDDM greeter once the DCP card exists. In a shell outside a user session (ssh, a text console)
  set it by hand.
- With the GPU but without the panel hand-off the generator sets nothing. Whether Hyprland then
  renders on the GPU or stays on llvmpipe over simpledrm is not known; the GPU step is judged by
  `dmesg` and `vulkaninfo`, not by the desktop.
- Nothing in Mesa is board-specific as far as the strings and the K116s report show (Jens: "Vulkan
  works (vkcube) and Plasma composites on it, with `ASAHI_M5_BRINGUP=1`"). His Mesa build is not
  betizzel's `j714s2`; that pairing is untested.

## Staged test plan

The Stage 2 (`m1n1/boot-ctxr.bin` = loader + one device tree + U-Boot) is shared by every boot entry.
Each new Stage 2 is a separately selectable variant and r1 stays on the partition; `stage2 r1` from
macOS must restore **the loader bytes as well as the tree** once a variant carries a new loader.

Ranked by how little can go wrong. Each step changes one thing.

| Step | Change | Boots with | What to look at | If it goes wrong (a picture remains) |
| --- | --- | --- | --- | --- |
| 0 | none | now, no reboot | `sudo python3 tests/k114s-adt-display-facts.py --dtb <r3.dtb>`; loader log | nothing can |
| 1 | r3 kernel, Stage 2 unchanged | r1 tree, installed loader | `uname -v`; `dmesg` as before. The patches only act on GPU mailboxes, a bound DCP and a marked framebuffer, none of which exist with the r1 tree | boot the r1 kernel entry (same Stage 2) |
| 2 | tree `r3-gpu`, installed loader | r3 kernel preferred (see note) | loader: `FDT: GPU: T6050 G17S 26B8125 enabled`; `dmesg \| grep -i aurora`: firmware build 26B8125, no error; `/dev/dri/renderD*`; `ASAHI_M5_BRINGUP=1 vulkaninfo --summary` names the Apple GPU. Panel still simpledrm | macOS: `stage2 r1`. The display path is untouched, so a GPU that fails to start still leaves the console |
| 3 | tree `r3`, **installed** loader | r3 kernel | `/proc/device-tree/chosen/asahi,t6050-dcp-handoff` = `refused` (expected when step 0 found `3D6C8857-…`); connector is `eDP-1`; GPU as in step 2 | macOS: `stage2 r3-gpu` or `r1` |
| 4 | tree `r3`, **r3 loader** | r3 kernel, command line `appledrm.fw27_panel_vrr=0` | `asahi,t6050-dcp-handoff` = `published`; `dmesg`: `Initialized apple`, `panel ADT: …`; `card*-eDP-1` at 3024x…@120 only; Hyprland on the DCP card through zink | first a second boot entry with `module_blacklist=appledrm` (see below); then macOS: `stage2` back to step 3's variant |

Notes on the steps:

- **Step 1 and the space problem.** A second kernel image does not fit on the EFI partition today.
  Either make room first (the update-tooling work), or replace the repair image with the r3 one,
  which removes step 1's own fallback. Steps 0, 2 and 3 need no new kernel image.
- **Step 2 on the current kernel.** The GPU can be started on the running `K114S-R1` kernel: the
  K116s ran its GPU on kernels from before #1844. Without `0001`/`0002` the mailboxes are polled, and the
  known failure is a panic when suspending with the lid open and the GPU active (#1843). Suspend is
  refused on this Mac today (N1 link), so the path is closed for now, but it opens when the
  sleep work lands. Prefer the r3 kernel; if space forces the order, do not suspend.
- **Step 3 is a real test, not a formality:** it shows on this hardware that a refused panel
  hand-off costs nothing, before the step that can cost the picture.
- **Step 4 fallback entry.** With the hand-off published the DCP, its mailbox and DARTs are enabled
  in the tree, but only `appledrm` drives them. A boot entry with `module_blacklist=appledrm` should
  leave simpledrm on the panel with the same Stage 2. This follows from the loader source (it writes
  no DCP, DART or power register) and is **not tested**; the macOS rollback is the fallback that does
  not depend on it. The disk passphrase prompt comes before the desktop: if the screen is black at
  that point, type it blind once, then use the fallback entry.
- A panel hand-off without the GPU is deliberately not a step (finding 4).
- Stop conditions: any `refused` in step 4, `RTKit: co-processor has crashed`, `DCP has crashed`, an
  SError or Oops. Roll back one step and keep the log.

## Maintainer procedure (design, not yet run)

Read-only, now:

```sh
cd <checkout of r3/display-gpu>
sudo python3 tests/k114s-adt-display-facts.py --dtb <built t6050-k114s-r3.dtb>
sudo cat /dev/mtd1ro | tr -d '\0' | grep -E 'DCP:|GPU:|T6050'
sudo lsinitcpio /boot/initramfs-linux-aurora.img | grep -c -E 'appledrm|dcp-fabric'   # is the panel driver in the initramfs?
```

The first prints UUIDs, register addresses and property names only; it never prints a serial number
or a MAC address (the replica test checks that), so its output may be published. The raw ADT and the
raw log may not.

Building (no root): the trees with `build/build-dtb.sh` after copying `dts/*` into a kernel tree,
or any kernel-style `cpp` + `dtc` with `dts/` ahead of `arch/arm64/boot/dts/apple` on the include
path (the buildenv worker found that the repository script's `-Wno-graph_child_address` is unknown
to dtc 1.8.1). The kernel: `git am patches/linux/display-gpu/*.patch` on the running kernel's
source. The loader: `git am patches/aura/*.patch` on aura `22b71758` + betizzel's seven, then the
recipe's `make RELEASE=1 CHAINLOADING=1 USE_CLANG=1 ESP_STAGE2=1` with its logo arguments.

Writing a Stage 2 variant or a kernel image to the EFI partition is the lead's and the macOS tool's
job; the tool needs variants that replace the loader prefix, with `aura_prefix_bytes` per variant.

## What was verified, and how

| Claim | Evidence |
| --- | --- |
| Both patch series apply with `git am` on their stated bases and reproduce the working branches | agent-run |
| The patched kernel files compile with the running configuration | agent-run |
| The r3 loader builds; the merged gate admits and refuses as tabulated | agent-run build; replica test, 12 cases |
| The r1 tree built by this procedure has the manifest's SHA-256 (`2ea22d26…`) | agent-run: the procedure matches the delivered one |
| `r3-edp` differs from r1 by one property; `r3` and `r3-gpu` pass the loader-side lint | agent-run, replica |
| Display and GPU nodes equal the K116s tree's except five named differences | agent-run comparison with upstream `0b03fe43` |
| The ADT reader parses, translates through `ranges`, compares and leaks no identifier | replica, 14 checks on a synthetic ADT |
| Boot framebuffer 3024x1986; connector `Unknown-1`; no `dcp-handoff` property; ADT and log MTD devices exist; session has `ASAHI_M5_BRINGUP=1`; 88 MB free on the EFI partition | agent-run on this Mac, 2026-11-14 |

## What could not be determined without the Apple device tree

1. The DCP image UUID this Mac loads (step 0 answers it).
2. Whether every register, interrupt and stream of the display and GPU nodes equals the K116s
   values on this board. The repository records the two 27.2 ADTs as identical node for node; that
   comparison was not repeated here, and the tree's values are upstream's.
3. Whether the K114s ADT has a panel node with dimensions, the brightness scale, the gamut.
4. The GPU's leakage calibration words and whether the driver's J714 voltage tables suit this part
   (on the K116s they are 5 mV low at eight of fourteen states; the loader passes the words and the
   driver applies its J714 controller configuration only when they match).
5. The PMP tunables for this board, needed before the GPU can sit on the PMP report as on the K116s.

Also not determined, for other reasons: whether the repair image's initramfs contains `appledrm`
(root); whether `module_blacklist=appledrm` keeps simpledrm alive after a published hand-off;
colours with XRGB scanout on this panel; any OLED brightness control; behaviour with
`mesa-aurora j714s2` on a K-board.

## Overlap with other r3 work

- `r3/sleep-lid` also carries #1844 and #1688. They are the same upstream commits as `0001`, `0002`,
  `0007`, `0008` here; apply them once.
- `K114S_R3_EDP` changes the connector name from `Unknown-1` to `eDP-1`. Omarchy then treats the
  panel as built in and lid close asks for suspend, which this kernel refuses while the N1 link is
  up. Coordinate with the sleep work before step 3.
- The sound/power candidate's PMP section is what `K114S_R3_GPU_PMP` waits for.
- The three patch headers whose author addresses are replaced by a placeholder: this repository
  publishes no personal e-mail addresses (`build/check-publishable.sh`); the upstream commits named
  in each patch carry them.
