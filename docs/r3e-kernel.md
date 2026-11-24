# r3e: the K114s kernel on aurora-silicon/linux `main` `c3369f48`

Status 2026-11-24: **superseded by r3f ([r3f-kernel.md](r3f-kernel.md)), which is Main; r3e1 is Backup, the way back.**
r3e1 (r3e + 0076, the small camera indicator) was Main, with r3e as Backup. The r3e trial passed and was promoted, then r3e1's trial (`R3E1-CHECK: PASS`, with a 5 s camera stream binding the indicator) passed and was promoted. The text below records the build.
the new upstream `main`. aurora-silicon/linux removed its `integration/aurora` branch; pull requests now target `main`,
which contains the r3d base `0bbe021a28bd` (399 commits earlier than `c3369f48`). The speakers stay off. Deep sleep
stays compiled out (`CONFIG_APPLE_SOC_SLEEP` off), as in r3d. Evidence labels as in [r3d-kernel.md](r3d-kernel.md):
**agent-run**, **emulator/replica**, **upstream-reported**.

## 1. What r3e is

| | r3d (Main since 2026-11-24) | r3e |
| --- | --- | --- |
| Base | integration/aurora `0bbe021a28bd` | aurora-silicon/linux `main` `c3369f4855e9b5b9cb5024148f65ef2a704018b1` |
| Series | `patches/linux/r3d.series`: 93 patches | `patches/linux/r3e.series`: 75 patches (`patches/linux/r3e/`): the 74 rebased ones plus `0075`, the camera without a described light (section 2a) |
| Release | `7.3.0-17.v272-18-k114s-r3d-ARCH` | `7.3.0-17.v272-18-k114s-r3e-ARCH` |
| Package | `linux-k114s 7.3.0.r3d-1` (Main) | `linux-k114s-r3b 7.3.0.r3e-1`: the Backup slot, replacing r3c-upstream there, so r3d stays the way back while r3e is tried by a one-shot (the PKGBUILD and `check-package.sh` know it) |

The 93 r3d patches became: **71 kept as they were, 3 re-cut, 19 dropped**. Each dropped patch is in `main` (the same
commit, or a newer version of the same PR), or is made obsolete by a design `main` now carries. Nothing was dropped
because it conflicted. The 74 patches were applied with `git am --3way`; the exported series was applied again to a
clean `origin/main` and gives the same git tree (`fbbba21a4af0`) as the tree that was built (agent-run).

### Merged upstream since the r3d base (now in `main`)

#1173 (the G17S 27.2 InitData), #1650 (the K114/K116 26B8125 firmware identity) and #2185 (the M5 Max 26B123 identity);
#2187 (J716c external displays and display sleep on 27.2, r3d `0033`-`0035`); #2488 and #2729 (adopted PCIe links across
s2idle, r3d `0046`-`0050`); #2518, #2538, #2539 and #2540 (the system cache controller and the display takeover
completion, r3d `0042`-`0045`); #2817 and #2772 (NVRAM writes by DT partition and flash part, replacing r3d
`0027`-`0029`); #1615 (the battery manufacture date, r3d `0023`); #2953 (display state across s2idle), #3065 (T6050 sleep
lock checks), #2574 (private L2 per P core), #2766 (ATC COMMON parents), #2760 (the DP PHY power domain), #2294 (AFR and
GFX auto-PM), #1971 (no Air power budget on fan-cooled boards), #3019 (the NVMe polled I/O queue), #2206 (the Wi-Fi Beta
function) and #2782 (the SMC WKTP full-wake state). The last group changes `main`; no r3d patch is the same commit as any of them. `de0a438a022` changed the adaptive-sync code that r3d `0010` edits (see the re-cuts). Whether the last group touches the files of a carried patch was not checked beyond what `git am --3way` and a subject and patch-id match against `main` showed.

## 2. Disposition of the r3d patches

"kept" means it applied with `git am --3way` and no hand edit. The r3e number is the patch's place in `r3e.series`.

| r3d | Patch | Outcome | Upstream commit / reason |
| --- | --- | --- | --- |
| 0001 | drm/asahi: M5: InitData for the macOS 27.2 and 27.3 firmware (#1173) | dropped | `84b324dec6e`: #1173 merged (upstream's squash; the 27.3 beta graph is not carried, not needed on 27.2) |
| 0002 | drm/apple: Name the firmware 27 adaptive sync parameter | kept (r3e 0001) | |
| 0003 | drm/apple: Refuse panel brightness once the display processor crashed | kept (r3e 0002) | |
| 0004 | drm/asahi: t6050: identify the 27.2 (26B8125) G17S firmware of the K114/K116 | dropped | `8d7770f82a0`: #1650 merged: same commit (Jens Axboe, same date) |
| 0005 | media: apple: isp: Tune the J714c IMX958 with setfile 2226_02 | kept (r3e 0003) | |
| 0006 | media: apple: isp: Set the J714c lens shading target and scene metering | kept (r3e 0004) | |
| 0007 | media: apple: isp: Drive the J714c camera light from the driver | kept (r3e 0005) | |
| 0008 | media: apple: isp: Turn the J714c camera light off after a firmware halt | kept (r3e 0006) | |
| 0009 | arm64: dts: apple: t6050-j714s: Describe the camera light | kept (r3e 0007) | |
| 0010 | drm/apple: Offer VRR on the firmware 27 panel and apply VRR_ENABLED (J716s daily) | re-cut (r3e 0008) | conflicts with upstream's VRR rework (#3052 / de0a438a022): merged `vrr_on` into the adaptive-sync call that now also clears VRR on fixed modes |
| 0011 | accel/ane, media: apple: ave: T6050 Neural Engine and encoder on macOS 27.2 | kept (r3e 0009) | |
| 0012 | arm64: dts: apple: t6050-j714s: Describe the HDMI port | kept (r3e 0010) | |
| 0013 | drm/apple: T6050 HDMI: complete flips locally while the output connects | kept (r3e 0011) | |
| 0014 | HID: dockchannel-hid: clamp Report Size items where the descriptor arrives | kept (r3e 0012) | |
| 0015 | HID: dockchannel-hid: pad short reports to the clamped report size | kept (r3e 0013) | |
| 0016 | ASoC: apple: macaudio: Add K114 with the speakers off | kept (r3e 0014) | |
| 0017 | PCI: apple: qualify the K114s for suspend-to-idle over the adopted N1 link | dropped | `7946d189a56`: #2488 merged: it removed the per-board s2idle list; t6050_hw sets adopt_link, so the K114s qualifies with no patch |
| 0018 | dt-bindings: display: apple,dcp: optional panel brightness floor | kept (r3e 0015) | |
| 0019 | drm/apple: hold brightness requests at the panel's floor | kept (r3e 0016) | |
| 0020 | drm/apple: describe an internal panel without a known gamut as Display P3 | kept (r3e 0017) | |
| 0021 | drm/apple: cap the panel peak a firmware 27 panel's EDR may use | kept (r3e 0018) | |
| 0022 | drm/apple: K114s: no panel EDR above 500 nits by default | kept (r3e 0019) | |
| 0023 | power: supply: macsmc: skip an unreadable manufacture date quietly | dropped | `b9a7edd8029`: same commit, merged in main |
| 0024 | drm/apple: no EDR when a cap is set and the SDR maximum is unknown | kept (r3e 0020) | |
| 0025 | soc: apple: sep: Admit the K114s to the T6050 profile | kept (r3e 0021) | |
| 0026 | soc: apple: aop: Send the 14-inch M5 Max sensor its 193-byte calibration | kept (r3e 0022) | |
| 0027 | spi: apple-qspi: admit verified NVRAM writes on the J716s | dropped | `595384bd317`: #2817 merged: NVRAM writes now follow the DT nvram partition and a known flash part (apple_qspi_find_part), with no per-board rows; the J716s row is obsolete |
| 0028 | spi: apple-qspi: log the flash ID and status when a write is refused | dropped | `595384bd317`: #2817 merged: its "NVRAM denied: reason=..." log covers a refused write, with the flash ID in the part check |
| 0029 | spi: apple-qspi: admit the K114s NVRAM, fail-closed on its flash ID | dropped | `595384bd317`: #2817 merged. The K114s flash ID 0xc88317 is not in the part table, and `read_only` defaults to Y, so every write is refused before WREN (read-only, as r3d) |
| 0030 | mfd: macsmc: count a port's dark wake on every board with a sleep policy | kept (r3e 0023) | |
| 0031 | wifi: apple: centauri: t6050: harden keep-alive sleep fallback and PME gating | kept (r3e 0024) | |
| 0032 | wifi: apple: centauri: t6050: try full TLV 280 event mask on wake with legacy fallback | kept (r3e 0025) | |
| 0033 | drm/apple: send a paired mode set's calls in the engine's firmware 27 build | dropped | `39ae54d0eac`: same commit, merged with #2187 |
| 0034 | drm/apple: send the firmware 27 calls named by ID in the engine's build | dropped | `795bd7727eb`: same commit, merged in main |
| 0035 | drm/apple: admit the T6050 display sleep transport by method table | dropped | `a56f2a5df8d`: same commit, merged in main |
| 0036 | arm64: dts: apple: t6050: share the keyboard backlight, add it to J716c | kept (r3e 0026) | |
| 0037 | arm64: dts: apple: t6050-k114-k116: SMC fans and sensors on all four boards | kept (r3e 0027) | |
| 0038 | arm64: dts: apple: t6050: share the G17S GPU description | kept (r3e 0028) | |
| 0039 | arm64: dts: apple: t6050: share the G17C GPU description | kept (r3e 0029) | |
| 0040 | arm64: dts: apple: t6050: describe the GPU on J714c, J873s, K114s, K116c | kept (r3e 0030) | |
| 0041 | arm64: dts: apple: t6050: give the G17C OPP tables schema-valid names | kept (r3e 0031) | |
| 0042 | soc: apple: mcc: let the T6050 system level cache allocate | dropped | `e6fdaf6d4b2`: #2518 merged: same commit (patch-id equal) |
| 0043 | soc: apple: mcc: wait for display controllers to retire boot scanout | dropped | `5b302458524`: #2538 merged: same commit (patch-id equal) |
| 0044 | drm/apple: publish completion of native display takeover | dropped | `7803302be7e`: #2539 merged: same commit (patch-id equal) |
| 0045 | arm64: dts: apple: t6050: describe the single-die system cache controller | dropped | `08fa2535365`: #2540 merged, at a newer head: main's DT keeps the system-cache controller status = "disabled" until a board enables it (r3d carried the older head with it enabled) |
| 0046 | PCI: apple: keep adopted links across s2idle on every adopted host | dropped | `d1571ebf734`: #2488 merged (7946d189a56): upstream's version replaces our re-cut on r3c/0001; the K114s qualifies through t6050_hw.adopt_link |
| 0047 | PCI: apple: refuse an adopted-link sleep in prepare, before devices suspend | dropped | `410f5bebf1f`: #2729 merged: same commit (patch-id equal) |
| 0048 | PCI: apple: decide the adopted-link s2idle check by one predicate | dropped | `ce21cd4eded`: #2729 merged: same commit (patch-id equal) |
| 0049 | PCI: apple: refuse a firmware suspend the adopted host can't take, and skip parked ports | dropped | `c8a1558ca87`: #2729 merged: same commit (patch-id equal) |
| 0050 | tools/asahi: pciec-policy-tests: cover adopted-link prepare refusals | dropped | `8f3d074923d`: #2729 merged: same commit (patch-id equal) |
| 0051 | soc: apple: rtkit: a mailbox named by a property of its own | re-cut (r3e 0032) | upstream added a trailing `session` parameter to `__apple_rtkit_init()`; the new callers pass it |
| 0052 | soc: apple: rtkit: a step between the AP idle and the IOP idle | kept (r3e 0033) | |
| 0053 | drm/apple: V27 sleep: the DCP's secure port (firmware 27.2) | kept (r3e 0034) | |
| 0054 | drm/apple: V27 sleep: wait out a busy endpoint before closing it | kept (r3e 0035) | |
| 0055 | drm/apple: V27 wake: mode set once the firmware has reported the panel | kept (r3e 0036) | |
| 0056 | soc: apple: rtkit: serve an endpoint's first buffer under the ANS hold | kept (r3e 0037) | |
| 0057 | soc: apple: sleep: tell whether a T6050 machine describes the sleep | kept (r3e 0038) | |
| 0058 | dt-bindings: soc: apple,t6050-sleep: add apple,display-method-sleep | kept (r3e 0039) | |
| 0059 | dt-bindings: mfd: apple,smc: add the wake reasons' numbering | kept (r3e 0040) | |
| 0060 | arm64: dts: apple: t6050-j714s: the display's sleep method and the SMC's wake reasons | kept (r3e 0041) | |
| 0061 | soc: apple: sleep: check a profile's CPU inventory, not its board's name | kept (r3e 0042) | |
| 0062 | irqchip/apple-aic: keep the T6050 controller where the sleep is described | kept (r3e 0043) | |
| 0063 | mfd: macsmc: the T6050 saved-context path where the sleep is described | re-cut (r3e 0044) | upstream's #2782 added the WKTP full-wake helpers beside the same spot; both kept |
| 0064 | soc: apple: rtkit: acknowledge the v2 PMP's CoreAnalytics events on any board | kept (r3e 0045) | |
| 0065 | dmaengine: apple-sio: the T6050 description where the sleep is described | kept (r3e 0046) | |
| 0066 | nvme: apple: the T6050 ANS2 sleep attachment where the sleep is described | kept (r3e 0047) | |
| 0067 | PCI: apple: T6050: the radio host's deep sleep where the sleep is described | kept (r3e 0048) | |
| 0068 | iommu/apple-dart: the T6050 sleep rules where the sleep is described | kept (r3e 0049) | |
| 0069 | phy: apple: atc-t6050: the combo PHY's deep-sleep rules where the sleep is described | kept (r3e 0050) | |
| 0070 | usb: dwc3: apple: T6050's sleep lines where the sleep is described | kept (r3e 0051) | |
| 0071 | drm/asahi: g17: the M5 commit stop where the sleep is described | kept (r3e 0052) | |
| 0072 | drm/apple: v27: the J714s's sleep and panel paths by the sleep's description | kept (r3e 0053) | |
| 0073 | arm64: dts: apple: t6050-k116s: Add the PMU's RTC | kept (r3e 0054) | |
| 0074 | arm64: dts: apple: t6050-k116s: enable the video encoder's power states | kept (r3e 0055) | |
| 0075 | arm64: dts: apple: t6050-j714s-sleep-soc: make the CIO sleep part optional | kept (r3e 0056) | |
| 0076 | dt-bindings: mailbox: apple: add the T6050 secure RTBuddy port | kept (r3e 0057) | |
| 0077 | dt-bindings: soc: apple,t6050-sleep: allow an empty apple,pinctrl-skip-pins | kept (r3e 0058) | |
| 0078 | dt-bindings: display: apple,dcp: add apple,secure-mbox | kept (r3e 0059) | |
| 0079 | arm64: dts: apple: t6050-k116s: describe and enable the deep sleep | kept (r3e 0060) | |
| 0080 | dt-bindings: display: apple,dcp: add apple,merged-mode-limit | kept (r3e 0061) | |
| 0081 | arm64: dts: apple: t6050-j714s: the merged-mode limit of the external display coprocessors | kept (r3e 0062) | |
| 0082 | drm/apple: v27: the merged-mode limit by the coprocessor's own property | kept (r3e 0063) | |
| 0083 | drm/apple: T6050: refuse deep sleep at .prepare where the firmware 27 display sleep is not known | kept (r3e 0064) | |
| 0084 | soc: apple: sep: select the platform profile by SoC | kept (r3e 0065) | |
| 0085 | soc: apple: sep: leave the SEP off where the board keeps its mailbox disabled | kept (r3e 0066) | |
| 0086 | arm64: dts: apple: t6050: share the K boards' N1 and USB-C ports, add K114s and K116c | kept (r3e 0067) | |
| 0087 | arm64: dts: apple: t6050: expose the K boards' jack pins with the PCIe PERST# pin | kept (r3e 0068) | |
| 0088 | arm64: dts: apple: t6050: Share the camera, add J714c, J716s, K114s, K116c | kept (r3e 0069) | |
| 0089 | arm64: dts: apple: t6050: describe the AOP on every MacBook Pro | kept (r3e 0070) | |
| 0090 | arm64: dts: apple: t6050: enable the media engines on every board | kept (r3e 0071) | |
| 0091 | arm64: dts: apple: t6050: name the second window of the AVE and JPEG DARTs | kept (r3e 0072) | |
| 0092 | arm64: dts: apple: t6050: describe the Neural Engine in a SoC-level dtsi | kept (r3e 0073) | |
| 0093 | arm64: dts: apple: t6050: enable the Neural Engine on J714c, J716s, J873s, K114s, K116c and K116s | kept (r3e 0074) | |

### The re-cuts

- **r3d 0010 (VRR on the firmware 27 panel, r3e 0008).** `main` now clears adaptive sync when a fixed mode follows a VRR
  mode (`de0a438a022`) and its `iomfb_modeset()` passes `mode->vrr && crtc_state->vrr_enabled`. The patch's `vrr_on`
  (VRR_ENABLED and `dcp_vrr_allowed()`) now goes into that call. The panel stays fixed unless `fw27_panel_vrr` is set.
- **r3d 0051 (a mailbox named by a property, r3e 0032).** `__apple_rtkit_init()` gained a trailing `session` argument in
  `main`; the new callers pass it, and the patch's own `apple_rtkit_init_mbox_prop()` passes `NULL` for it.
- **r3d 0063 (the macsmc saved-context path, r3e 0044).** #2782 added the WKTP helpers at the same spot in `macsmc.c`;
  both stay.

### The K114s-specific patches, checked one by one

- **r3d 0017 (the K114s s2idle qualification): dropped.** #2488 removed the per-board list. `t6050_hw` sets `adopt_link`,
  so the K114s takes the adopted-link s2idle path with no patch. The PKGBUILD guard checks that.
- **r3d 0027-0029 (NVRAM): dropped; the K114s stays read-only.** #2817 admits a write only where the device tree
  describes an `nvram` partition on the flash and the flash's JEDEC ID is in `apple_qspi_find_part()`'s table. The
  kernel's own `t6050-k114s.dts` and `t6050-k114-k116.dtsi` describe no `nvram` partition. But the Stage 2 tree the Mac
  actually boots (ours, `a0897a5a`) does: `flash@0/partitions/partition@700000`, labelled `nvram`, 0xc0000 bytes, not
  `read-only`. That layout passes the driver's window check. Writes are still refused, for two reasons: the
  `read_only` module parameter defaults to Y (nothing on this Mac sets it), and `0xc88317` is not in the part table
  (W25Q64, MX 2B27, W25Q16, GD25UF16E). The refusal is logged ("NVRAM denied: reason=..."). So r3d's assumed-ID K114s
  row is replaced by the part check: no row admits the K114s. The write-enabling rows of r3d (J716s, K114s) are gone.
  **Decision for the owner:** if a K114s NVRAM write is ever wanted, it needs a DT partition and a table row from a read
  flash ID; r3d's assumed-ID row is not carried.
- **r3d 0063 (macsmc saved context): re-cut,** see above.
- **Sound (r3d 0016, `apple,k114-macaudio`, speakers off), `sep` (0025, 0084, 0085), hdr (0020-0022, 0024) and
  brightness (0018, 0019):** applied as they were. The speaker refusals and the admission test in 0016 are untouched.
- **r3d 0004 (the 26B8125 G17S firmware entry): dropped, as the entry is in `main`** (`8d7770f82a0`, the same commit by the
  same author, merged with #1650). Applied on `main` it would have added the entry a second time. The tree has it once
  (the PKGBUILD guard counts it).
- **r3d 0045 (the system cache controller DT): dropped for #2540's newer head.** `main`'s version keeps the controller node
  `status = "disabled"` until a board enables it (the older head r3d carried had it enabled). The K114s therefore has no
  system-level-cache allocation until a board enables it. The Mac boots its Stage 2 tree anyway (r3d-kernel.md section 3).

## 2a. One new patch: the camera without a described light (0075)

The owner asked for the built-in camera for meetings (2026-11-24). In the T6050 ISP driver, the probe refuses unless the
device tree describes the camera light (a `cil` register and `apple,cil-config`). The K114s ADT describes no light pin
(eic `cil` with no `cil-gpio-offset`, as on the K114c), so the camera never probed. This was the November 18 trial's
`ENODEV` ([r3-camera.md](r3-camera.md)). The owner chose (T3 decision grill, 2026-11-24, "Run it, on-screen dot") to
run the camera with the display's best-effort indicator (#2561) rather than wait for the light to be traced from macOS.

`0075` adds an opt-in device-tree property, `apple,camera-light-undescribed`. Only a tree that sets it runs the ISP
with no light control: the probe does not ask for `cil`, no stream is refused on the light, and the capture watchdog
runs as on the ISPs without a light. Every other board keeps the gate. The r3e trial tree leaves the ISP disabled, as
r3d does, so `0075` changes nothing until a camera tree sets the property. Built: `Image` unchanged (`f9ed2bc5`), and
`apple-isp.ko` carries the property (agent-run). The series applied to a clean `main` gives the built tree
`e0a0aa34` (agent-run).

## 2b. r3e1: the camera indicator small and under the notch (0076)

The owner saw the camera indicator (a 48x48 green square with a black border, top right) and asked for it "much smaller
and near the camera" (2026-11-24). `0076` makes it, on `apple,k114s` only, a solid 32x32 square (DCP rejects blended
surfaces smaller than 32x32) centred horizontally just below the 96-row notch that holds the camera (y = 104).
The 48x48 buffer is kept, and only its top-left 32x32 is scanned out. Every other board keeps the corner square.
`dcp-indicator-test.c` passes as a plain program.

r3e1 is `patches/linux/r3e1.series` (r3e plus `0076`), built with release `7.3.0-17.v272-18-k114s-r3e1-ARCH` and packaged
as `linux-k114s 7.3.0.r3e1-1`: the `linux-k114s` slot, the Backup since r3e became Main, replacing r3d there. r3e stays the
way back while r3e1 is tried once through a Limine one-shot, and is promoted if every check passes. The series applied to a
clean `main` gives the built tree `448a618e`. Built 302 s: `Image` sha256 `c4cf8fe1…`; `validate-config.py` passes (385 requirements, 0 not met), and `check-package.sh`
passes against `linux-aurora` and `linux-k114s-r3b` (agent-run).

## 3. Open pull requests r3d carried

| PR | r3d patches | State on 2026-11-24 | In r3e |
| --- | --- | --- | --- |
| #2559 | 0030 | open, same head `af97a52c` | kept |
| #2877 | 0031, 0032 | open, same head `8ecf51d2` | kept |
| #2631 | 0084, 0085 | open, same head `4ae8c061` | kept (our `sep` 0025 / #2115 stays redundant) |
| #2201 | 0051-0082 | open, **newer head `a01d61c1f397`** (was `ecf92666`) | **older head kept**, see below |
| #2070 | 0083 | open, **newer head `f0d63f6f7c44`** (was `df8aaf54`) | **older head kept**, see below |
| #2280, #2275, #2285, #2278, #2293 | 0086-0093 | open drafts (but #2275), same heads | kept |
| #2282, #2281, #2276 | 0036-0041 | open drafts, same heads | kept |
| #2798 | 0020 | open draft, identical to our patch (line for line) | kept |
| #2540, #2488, #2729, #2187 | see section 2 | merged | dropped |

**#2201's newer head** differs from the copy r3d carries in five of 35 commits (the other 30 have the same changes):
the secure-port poller is stopped only once the sleep is armed and started again when the firmware never stopped
(r3d `0053`), the wake's completions are re-armed before the call that brings the panel up (`0055`), the rtkit
AP-idle step returns `-EPROTO` unless the state is IDLE (`0052`), a comment in the K116s DT, and the `__apple_rtkit_init()`
callers (`0051`, already adapted here). **Not taken:** all of these are in the firmware 27 deep-sleep path (`dcp_v27_sleep_*`,
the rtkit v27 idle scope, a K116s-only DT) that the K114s does not run: deep sleep is compiled out and no K114s DT
describes the sleep. They are real fixes for deep sleep. Recommendation: take that head when deep sleep is considered.

**#2070's newer head** replaces the "known sleep" flag r3d's re-cut takes from the selected method table with a check that
the 27.0 table carries the sleep's IDs; it refuses a deep sleep on **every** 27.2 build, the K114s too. r3d took the
other way on purpose (the review asked for it). **Not taken**, and with deep sleep compiled out it changes nothing
at runtime. Recommendation: keep r3d's re-cut unless deep sleep is wanted.

### Candidates not added (plain bug fixes for T6050 or K114 code r3d already uses)

Nothing below is in r3e. Each was read by its title and description only, not built.

| PR | What | Recommendation |
| --- | --- | --- |
| #2528 (open) | `aop_als`: arm the CT817 light sensor again after system sleep (found on the J700) | add once a K114s suspend shows the light sensor frozen; r3d carries the light-sensor path |
| #2935 (open) | macsmc: initialise the completions before the RTKit, as the receive callback can run during probe | add: small, no behaviour change |
| #2987 (draft) | macsmc-power: set up the work before the notifier, wait for it on remove | wait for the on-Mac run it asks for |
| #2906 (open) | `t6050-aop`: one ring buffer per endpoint (a repeated GETBUF leaked one each time) | add if the AOP log shows repeated GETBUF |
| #2800 (draft) | aop: refuse EPIC calls once the firmware crashed | wait |
| #2872, #2884 (open) | Wi-Fi centauri on the T6050: WPA/WPA2 mixed networks, 6 GHz networks behind another beacon | add for users of such networks; no K114s-specific need seen |
| #2694 (open) | internal-panel HDR only on panels with EDR headroom | review against our 500-nit cap (r3d `0021`, `0022`, `0024`) before adding; it touches the same code |
| #2798 (draft) | the Display P3 EDID default, identical to r3d `0020` | nothing to do; drop `0020` when it merges |
| #2115 (open) | our own `sep` 0025 | redundant with #2631 |

## 4. Build and checks

    git worktree add -b r3e <tree> origin/main     # c3369f4855e9b5b9cb5024148f65ef2a704018b1
    grep -v '^#' patches/linux/r3e.series | grep . | while read p; do git am --3way patches/linux/$p; done
    printf -- '-17.v272-18-k114s-r3e' > localversion.10-pkgrel
    cp $RECIPE/installer/recipes/linux-aurora-j714s/config $O/.config
    scripts/kconfig/merge_config.sh -m -O $O $O/.config patches/linux/config/k114s-r3.config; kmake O=$O olddefconfig
    K114S_LABEL=K114S-R3E kmake O=$O -j16 Image modules dtbs

| Check | Result | Label |
| --- | --- | --- |
| Build (clang 23.1.3, Rust 1.98.1) | 322 s; `Image` 54,413,824 bytes, sha256 `f9ed2bc508ececf35c8189db5ec055fcd82e70ac8c802c10659b74b788afa749`; 74 commits on `main` | agent-run |
| `build/validate-config.py` with `k114s-required.config` and `k114s-r3.config` | pass: 385 requirements, 0 not met | agent-run |
| The recipe's `validate-config.py` with `j714s-required.config` | exit 0 | agent-run |
| QEMU `k114s-qemu-smoke shell` | PASS, `7.3.0-17.v272-18-k114s-r3e-ARCH` | emulator/replica |
| QEMU, every module | `ok=1966 failed=7`: the same seven as r3d and every earlier kernel (tcrypt ipmi_si cppc_cpufreq sun50i-cpufreq-nvmem stratix10-soc apple-pmp-j613-hwmon xen-pciback) | emulator/replica |
| `check-package.sh` on a staged package tree (no package file was made; see below) | all passed, 23 checks | agent-run |
| The PKGBUILD's r3e source guard | pass: brightness floor, 500-nit EDR cap, Display P3, unknown-SDR EDR guard, battery-date fix, light-sensor blob, `main`'s adopted-link predicate with `adopt_link` on `t6050_hw`, #2817's NVRAM path with no K114s row, no `nvram` partition in the K114s DT, `apple,k114-macaudio`, the 26B8125 G17S entry exactly once | agent-run |
| `build/check-publishable.sh` | ok | agent-run |
| `tests/linux/run-r3.sh` | 1725 passed, 1 failed. The failure is a host audit ("covers every boot-file hook installed on this machine": `92-omarchy-mac-display-gate.conf` is not in the space guard's triggers); it fails the same without this change. `tests/config` 9 passed | agent-run |

`check-package.sh` unpacks a package file. None was made, so it ran on a staged tree built as the PKGBUILD's `package()`
does (`modules_install`, the 46 dtbs, the config, `pkgbase`), through a copy of the script that skips the unpack. Its one
check against an installed package of another kernel (no file in common) therefore had an empty file list. Run the
real script on the real package.

Warnings: 40 compiler warnings, all Rust dead-code lints in code from upstream.

## 5. Packaging

`PKGBUILD` got an `r3e` case (`linux-k114s-r3b`, `7.3.0.r3e-1`, in the Backup slot beside r3d) and the r3e source guard above.
`check-package.sh` accepts the `-k114s-r3e-ARCH` release and checks the r3e NVRAM form (the module has #2817's refusal
log and no K114s row). The r3d and older checks stay. To package: `K114S_CAND=r3e makepkg -f --nodeps --skipinteg` with
`K114S_SRC=$B/src/r3e K114S_OUT=$B/out/r3e`.

## 6. Left for later

- The trial: Stage 2, one-shot boot and gates are r3d's (r3d-kernel.md section 3); nothing of r3e has run on the Mac.
- The r3d series (`r3d.series`, `r3d/`) stays in the repository: it is the booted kernel's record.
