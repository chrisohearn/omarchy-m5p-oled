# r3: the kernel configuration delta

Worker key `config`, 2026-11-14. This note covers the configuration of the next K114s kernel:
what the running kernel lacks, what to turn on, how to apply it and how to check the result.

**Status: evaluated and integrated (source only).** The fragment was resolved with the kernel's
own Kconfig and the objects it touches were compiled (agent-run). No kernel was built from it and
nothing here has run on the Mac.

## Summary

1. **The K116s-parity hardware needs no configuration change.** Every driver the sound, display,
   GPU, USB-C, camera, sleep and input work needs is already built for the running kernel
   (`7.3.0-17.v272-4-ARCH`, K114S-R1), as a module or built in. "No sound cards", "no USB host
   controllers" and "display is the boot framebuffer" are device-tree and loader gaps, not
   missing options.
2. **The gaps are in ordinary laptop and distribution features.** The base configuration is an
   arm64 defconfig with the Apple drivers added, not a distribution configuration: 1,873 options
   that the Aurora project's own distribution kernel enables are off here (1,700 of them are on in
   all three reference distribution configurations that were read).
3. **Ten failures on this machine today trace to missing options** (table below): the firewall
   does not start, Tailscale's routing is degraded, Bluetooth hands-free and network profiles are
   refused, the out-of-memory daemon and foreign-binary support never start, two of Omarchy's
   network settings are rejected, and Wi-Fi private key parsing is missing.
4. **The delta is one merge fragment**: 248 options on (201 modules, 47 yes/no settings, most of
   them inside modules) and 4 pinned off. It resolves identically on the running kernel's source
   and on upstream `integration/aurora`. It is a selection, not "everything a distribution
   builds": 1,588 of those 1,873 options stay off (other hardware, servers, legacy devices, and
   the policy items listed under "Considered and left out").

## Files

| Path | What |
| --- | --- |
| `patches/linux/config/k114s-r3.config` | The delta: a Kconfig merge fragment, every option under a comment that says why, with an evidence label |
| `patches/linux/config/k114s-required.config` | The baseline: 133 options the K114s kernel must keep (boot path, hardware, what the installed system relies on). All true of the running kernel; merging it changes nothing |
| `build/validate-config.py` | Checks a resolved `.config` (or `/proc/config.gz`) against fragments |
| `tests/config/test_validate_config.py` | 9 software tests of the checker and of the fragments' shape |

## Failures seen on this machine that the delta addresses

Agent-run on the running kernel, 2026-11-14 (`journalctl -b`, `systemctl`, `sysctl`, `/proc`).
The right-hand column is the fix in the fragment; none of the fixes has been booted.

| Seen | Cause | Fragment section |
| --- | --- | --- |
| `ufw.service` failed: "Extension hl revision 0 not supported", "Extension rt revision 0 not supported" | `NETFILTER_XT_MATCH_HL`, `IP6_NF_MATCH_RT` off. `/etc/ufw/before6.rules` uses `-m hl` 22 times and `-m rt` 3 times | 2 |
| bluetoothd: "RFCOMM server failed for Hands-Free Voice gateway ... Protocol not supported" (also Hands-Free unit) | `BT_RFCOMM` off | 1 |
| bluetoothd: "kernel lacks bnep-protocol support" | `BT_BNEP` off | 1 |
| systemd-modules-load: "Failed to find module 'pkcs8_key_parser'" (iwd asks for it) | `PKCS8_PRIVATE_KEY_PARSER` off | 8 |
| tailscaled: "error querying IP rules (does kernel have IP_MULTIPLE_TABLES?)" and "disabling tunneled IPv6 ... kernel doesn't support IPv6 policy routing" | `IP_MULTIPLE_TABLES`, `IPV6_MULTIPLE_TABLES` off | 3 |
| tailscaled: "Extension CONNMARK revision 0 not supported", "unknown option --nfmask", MASQUERADE rule "RULE_APPEND failed" | `NETFILTER_XT_CONNMARK`, `NETFILTER_XT_TARGET_MASQUERADE` and the mark front ends off | 3 |
| systemd-sysctl: "Couldn't write 'fq' to 'net/core/default_qdisc'", "Couldn't write 'bbr' to 'net/ipv4/tcp_congestion_control'" (Omarchy's own `99-omarchy-sysctl.conf`); in effect: `pfifo_fast`, `cubic` | `NET_SCH_FQ`, `TCP_CONG_BBR` off | 4 |
| `systemd-oomd` enabled but skipped: "unmet condition ConditionPathExists=/proc/pressure/memory" | `PSI` off | 8 |
| `systemd-binfmt` and the binfmt_misc mount skipped: "ConditionPathExists=/proc/sys/fs/binfmt_misc" (`qemu-user-static-binfmt` is installed) | `BINFMT_MISC` off | 5 |
| No `/dev/uinput`, no joystick nodes, no HID vendor drivers, no exFAT/NTFS/ISO/UDF/CIFS, no UAS | not built | 9, 10, 11 |

Not caused by the configuration, noted while reading the same log (for the workers who own them):

- `dockchannel-hid ... Direct firmware load for apple/tpmtfw-k114s.bin failed with error -2`,
  twice, early in boot (the lines still carry the initramfs host name). The file is installed
  under `/usr/lib/firmware/apple/`; `HID_DOCKCHANNEL` is built in, so it asks before the root file
  system is mounted. The trackpad works regardless. Whether the initramfs should carry the file is
  a question for the trackpad row, not a configuration change.
- `macsmc-battery: driver failed to report 'manufacture_year' property: -95`, repeated, and
  "failed to send uevent". This is what linux pull request 1615 fixes.
- `iwd: DEL_INTERFACE failed: Operation not supported`: the N1 driver's interface model, not an option.
- The udev rule that sets the `kyber` I/O scheduler fails with "Device or resource busy"; kyber is
  built (`/sys/block/nvme0n1/queue/scheduler` lists it).
- `speakersafetyd` is skipped for want of `/usr/share/speakersafetyd/apple/k114.conf`, and the
  speaker services for want of `/proc/device-tree/sound`. That is the intended state.

## Hardware subsystems: what the configuration already has

Checked against `/proc/config.gz`, the module tree of the running kernel and `lsmod`.

| Subsystem | Options (state in the running kernel) | Gap |
| --- | --- | --- |
| Sound: card, bus, clocks | `SND_SOC_APPLE_MACAUDIO`, `SND_SOC_APPLE_MCA`, `APPLE_ADMAC`, `COMMON_CLK_APPLE_NCO`, `I2C_APPLE` (all m; `snd-soc-macaudio.ko`, `snd-soc-apple-mca.ko`, `apple-admac.ko`, `clk-apple-nco.ko` are installed) | None. Needs the K114s sound nodes and an `apple,k114-macaudio` entry |
| Sound: jack, amplifiers | `SND_SOC_CS42L84`, `SND_SOC_CS42L83`, `SND_SOC_TAS2764` (m; tas2764 also drives the sn012776), `SND_SOC_TAS2770`, `SND_SOC_MAX98357A` (m, selected by macaudio) | None. The amplifier driver being present is harmless: it binds only to device-tree nodes, and those stay disabled until this model has protection data |
| Sound: microphones | `APPLE_AOP`, `SND_SOC_APPLE_AOP_AUDIO`, `SND_SOC_APPLE_T8152_AOP_AUDIO` (m; `aop` is loaded) | None |
| Display coprocessor | `DRM_APPLE` (m), `DRM_APPLE_DCP_T8132`, `DRM_APPLE_AUDIO`, `DRM_APPLE_DCP_T6030_AUDIO`, `APPLE_DART_J713_DCP`, `APPLE_DISPLAY_GATE` (y), `PHY_APPLE_DPTX`, `PHY_APPLE_T6050_DP`, `MUX_APPLE_DPXBAR`, `BACKLIGHT_APPLE_DWI` (m) | None. `drivers/gpu/drm/apple/Kconfig` has no T6050 or T8142 option: the T6050 uses the T8132 method-table family, which is on |
| GPU (G17S) | `DRM_ASAHI=y`, `RUST_APPLE_RTKIT`, `APPLE_PMP` (m, loaded), `APPLE_PMP_REPORT`, `APPLE_CLPC` | None. The T6050 path (`gpu,t6050`, `apple,agx-g17s`) is compiled into the driver unconditionally. `DRM_ASAHI_M5` is the T8142 MacBook Air (G17G) backend and `DRM_ASAHI_G18`, `_G16`, `_G15`, `_M3_T8122` are other chips: not needed |
| USB-C host | `USB_DWC3=y` in dual-role mode, `USB_DWC3_APPLE`, `PHY_APPLE_ATC`, `TYPEC`, `TYPEC_TPS6598X`, `TYPEC_SN201202X` (m), `USB_XHCI_PLATFORM=y`, `USB_ROLE_SWITCH=y` | None. `dwc3_apple`, `phy_apple_atc`, `sn201202x`, `tps6598x_core`, `typec`, `atc_t6050_dp` are loaded and still no host registers: look in the device tree and the driver, not here |
| USB4 / Thunderbolt | `USB4`, `USB4_APPLE_SOC`, `USB4_CONFIGFS`, `TYPEC_DP_ALTMODE` (m) | None for bring-up. `USB4_NET` (Thunderbolt networking) and `TYPEC_TBT_ALTMODE` are off; add them when a router works |
| Camera | `VIDEO_APPLE_ISP` (m) | None |
| Video, Neural Engine | `VIDEO_APPLE_AVD`, `_AVE`, `_JPEG`, `_PRORES`, `_SCALER`, `DRM_ACCEL_ANE` (m) | None |
| Keyboard, trackpad | `HID_DOCKCHANNEL=y`, `APPLE_DOCKCHANNEL=y`, `HID_APPLE`, `HID_MAGICMOUSE`, `HID_APPLE_MTP_HAPTIC` (m) | None. The touchscreen driver (pull request 1605) is not merged and adds no option yet |
| Wi-Fi, Bluetooth | `APPLE_CENTAURI`, `APPLE_CENTAURI_T6050` (m), `APPLE_CENTAURI_T6050_WIFI=y`, `BT_HCICENTAURI` (m) | None for the radio. Profiles: section 1 |
| SMC | `MFD_MACSMC`, `GPIO_MACSMC`, `SENSORS_MACSMC_HWMON`, `MACSMC_POWER`, `RTC_DRV_MACSMC` (y), `POWER_RESET_MACSMC`, `INPUT_MACSMC_INPUT` (m) | None |
| Sleep, lid | `SUSPEND`, `PM_DEBUG`, `PM_SLEEP_DEBUG` (y; `/sys/power/mem_sleep` is `[s2idle]`), `IIO_AOP_SENSOR_LAS` (m), `INPUT_MACSMC_INPUT` (m) | None. Pull requests 1647, 1844, 1688 and 1789 add no option |
| SD card reader (GL9755 on PCIe port 1) | `MMC_SDHCI_PCI` (m) | None |

### Upstream's Apple fragment, compared

`arch/arm64/configs/asahi.config` at upstream `0b03fe43` (2026-11-14, "include every native hardware
driver in shared defaults", pull request 1939) against the running configuration. Where it asks for
a module and the K114s has the driver built in, the K114s keeps its choice. What it enables and the
K114s does not:

| Option | What it is | Decision |
| --- | --- | --- |
| `APPLE_SOC_SLEEP` | Suspend-to-RAM at EL2; match data for T8140 (and T8132 at head) only, inert without `/chosen/aurora,s2r-mailbox` | Not added: no T6050 support; s2idle is the system sleep here |
| `PCIE_APPLE_MSI` | MSIs for a loader-trained port "as a generic ECAM host (T8142 Wi-Fi)" | Not added: Wi-Fi works on this machine without it |
| `BT_CENTAURI` | N1 Bluetooth transport for J813 | Not added: the T6050 uses `BT_HCICENTAURI`, which is on |
| `MT7932_AWDL`, `DRM_ASAHI_G15/G16/G18/M5/M3_T8122` | Other chips | Not added |
| `I2C_DP855` | Panel bus behind a Parade DP855 timing controller | Not added: `t6050-k114-k116.dtsi` states these boards have "no dp855 TCON" |
| `SENSORS_APPLE_AON_PTD`, `SENSORS_TMP103`, `CRYPTO_DEV_APPLE_SIO_AES` | M4 Pro battery telemetry; a sensor no K114 tree names; an AES engine for T6000/T8112/T6040/T8140 | Not added |
| `SECURITY_LOCKDOWN_LSM`, `_EARLY`, `LOCK_DOWN_KERNEL_FORCE_NONE`, `APPLE_AURORA_BOOT_SECURITY_LOCKDOWN` | Raises kernel lockdown to "integrity" on a verified boot | Not added: a security-policy change, and modules here are unsigned. betizzel's J714s kernels leave it off too. The lead's decision if wanted |

betizzel's packaged configuration is the same file for v272-4, v272-5 and v272-6 (unchanged since
`0b813e9`); against the running kernel it differs in three lines that `olddefconfig` adds. So
v272-5 enables nothing the K114s lacks.

## The delta, by section

| # | Section | On (modules + yes/no) | Evidence |
| --- | --- | --- | --- |
| 1 | Bluetooth profiles: RFCOMM with TTY, BNEP | 2 + 3 | observed |
| 2 | ufw's IPv6 rules: hop limit, routing header, and the other header matches | 15 + 0 | observed (2), installed |
| 3 | Policy routing and packet marks (Tailscale): rules tables, connmark, mark, masquerade, NAT, MSS clamp | 10 + 5 | observed |
| 4 | Network defaults Omarchy sets: BBR, fq, fq_codel, CAKE | 4 + 2 (3 pinned off) | observed |
| 5 | Docker: conntrack netlink, nftables expressions, ip_vs protocols, VXLAN, CPU and I/O limits, binfmt_misc | 19 + 7 | installed; binfmt_misc observed |
| 6 | Standard iptables extensions | 32 + 0 | common |
| 7 | VPN: WireGuard, PPP, L2TP | 10 + 0 | common |
| 8 | System services: PSI, PKCS#8 parser, compressed firmware | 1 + 4 | observed (2), common |
| 9 | Input: uinput, hiddev, HID battery, Logitech and 67 other HID drivers, game controllers | 73 + 8 | installed, peripheral |
| 10 | USB storage: UAS, Realtek readers, optical, SCSI generic | 4 + 0 | peripheral |
| 11 | File systems: exFAT, NTFS, HFS+, ISO, UDF, FAT, XFS, F2FS, CIFS, squashfs codecs, Apple partition map | 10 + 15 (1 pinned off) | installed, peripheral |
| 12 | USB network adapters, phone tethering, modems, serial adapters, usbmon, device announcements, DisplayLink USB 2 | 14 + 2 | peripheral, common |
| 13 | MIDI: ALSA sequencer | 4 + 1 | common |
| 14 | Virtual machines: vhost-net, vsock | 3 + 0 | common |

Of the 248 options turned on, 244 are also on in the Aurora project's own distribution kernel
configuration (aurora-silicon/alarm-aurora, `linux-aurora` 7.3.0 at `d89d8c0c`), which is built
from the same kernel tree family. The four that are not (`HID_LENOVO`, `HID_RAZER`, `F2FS_FS`,
`DRM_UDL`) are on in Arch Linux ARM's generic kernel 7.3.4.

### What ends up built into the kernel image

The EFI partition had 88 MB free on 2026-11-14 and the image is 54,086,144 bytes, so additions are
modules wherever Kconfig allows. These are the ones that add code to the image itself:

- policy routing: `FIB_RULES` (selected), `IP_MULTIPLE_TABLES`, `IPV6_MULTIPLE_TABLES`, `IPV6_SUBTREES`
- `PSI`, `CFS_BANDWIDTH`, `BLK_DEV_THROTTLING`, `BINFMT_MISC`
- `NF_CONNTRACK_MARK`, `NF_TABLES_NETDEV`, `NF_NAT_REDIRECT` (selected), inside the built-in netfilter core
- `FW_LOADER_COMPRESS` with zstd and xz (both decompressors are already built in)
- `USB_HIDDEV`, `HID_BATTERY_STRENGTH`, inside the built-in HID core; `USB_ANNOUNCE_NEW_DEVICES`
  inside the built-in USB core
- `SQUASHFS_XZ`, `SQUASHFS_ZSTD`, `SQUASHFS_XATTR`, inside the built-in squashfs
- `PARTITION_ADVANCED` with `MAC_PARTITION`
- `TEXTSEARCH` and `VHOST_TASK` (selected by the string match and by vhost)

Measured (agent-run, see "Compile check"): the built-in object code of the directories this
touches grows by about 118 kB (text + data + bss of the object files, before linking). Smaller
effects elsewhere (PSI hooks in `mm/` and `kernel/cgroup/`, structure sizes) are not in that
figure, and **no image was linked**: compare the new `Image` size with the number above.

The initramfs should not grow: `autodetect` runs before `keyboard` in this machine's mkinitcpio
hooks, so the new HID modules are not swept in. Not verified by building one.

Resolved against the running configuration, 415 options differ: 67 become `y` (22 of them by
`select` or default, all listed above or bits inside modules), 233 become `m` (32 by `select` or
default, such as `CDROM`, `SND_SEQ_MIDI`, `NFT_FIB`, the WireGuard crypto libraries), 113 become
visible and stay off, and two get a value (`EXFAT_DEFAULT_IOCHARSET="utf8"`, `PPPOE_HASH_BITS=4`).
Nothing that was on is lost, and no existing string or number changes.

## How to apply

In the kernel build, after the base configuration is in place and before `prepare`
(`$REPO` is this repository, `$O` the output directory, `kmake` the pinned-toolchain `make`):

```sh
cp base-config "$O/.config"                 # the running kernel's config, or the recipe's
scripts/kconfig/merge_config.sh -m -O "$O" "$O/.config" "$REPO/patches/linux/config/k114s-r3.config"
kmake O="$O" olddefconfig
python3 "$REPO/build/validate-config.py" "$O/.config" \
    "$REPO/patches/linux/config/k114s-required.config" \
    "$REPO/patches/linux/config/k114s-r3.config"
```

Expected last line: `validate-config: passed: 385 requirements, 0 not met, 21 built in where a
module was requested` (the 21 are baseline options the K114s builds in). The toolchain must be the
real one: without Rust and bindgen, `olddefconfig` drops `CONFIG_RUST` and with it the GPU, AOP and
SEP drivers, and the validator says so.

After the first boot of the new kernel, the same check runs against the kernel itself:

```sh
python3 build/validate-config.py /proc/config.gz \
    patches/linux/config/k114s-required.config patches/linux/config/k114s-r3.config
```

### The module tree must be replaced as a whole

Several of these options change the layout of core structures (`PSI`, `CFS_BANDWIDTH`,
`BLK_DEV_THROTTLING`, `NF_CONNTRACK_MARK`, policy routing). The kernel has no symbol versioning
(`MODVERSIONS` is off), so a module built for the r1 configuration loads into an r3 kernel with the
same release string without complaint and then reads structures at the wrong offsets.

- Install the new image, the complete new `/usr/lib/modules/<release>` tree and a regenerated
  initramfs together. Never a new image over the old module tree, and never the r1 route of
  dropping one rebuilt module into `updates/`.
- If the release string stays `7.3.0-17.v272-4-ARCH`, the rollback copy has to include the old
  module tree and initramfs, not just the old image.
- A distinct release string for r3 would let both trees sit side by side and make the wrong
  pairing impossible. It must still end in `-ARCH`. That is the integrator's decision.

## What changes for the owner at the first boot

Expected from the configuration, none of it observed yet:

- `ufw` starts completely, IPv6 rules included.
- Omarchy's network settings take effect: the default queueing discipline becomes `fq` and TCP
  congestion control becomes BBR. Until now they silently stayed `pfifo_fast` and `cubic`.
- Tailscale gets policy routing, its connection-mark and masquerade rules, and tunnelled IPv6.
- `systemd-oomd` starts. Pressure accounting has a small scheduler cost; `psi=0` on the kernel
  command line turns it off.
- x86-64 and other foreign binaries start through `qemu-user-static` (containers included).
- bluetoothd registers the hands-free, headset and network profiles. **Hands-free call audio will
  still not work on the built-in radio:** `BT_HCICENTAURI`'s own description says "SCO and ISO are
  not implemented". RFCOMM gives the control channel; the voice link is a driver matter upstream.
  A2DP music playback does not use either and is unaffected.
- `/dev/usb/hiddev*` and `/dev/uinput` exist; wireless input devices report battery levels.

Checks after boot (no root needed):

```sh
systemctl --failed
journalctl -b | grep -E "missing kernel module|Protocol not supported|Couldn't write|Failed to find module|lacks bnep|IP_MULTIPLE_TABLES"
sysctl net.core.default_qdisc net.ipv4.tcp_congestion_control
ls /proc/pressure /proc/sys/fs/binfmt_misc
systemctl is-active ufw systemd-oomd
```

## Considered and left out

| Left out | Why | To add it |
| --- | --- | --- |
| IPsec (strongSwan, libreswan) | Cannot be modules only: builds the XFRM core into the image, and nothing installed uses it | `CONFIG_XFRM_USER=m`, `CONFIG_INET_ESP=m`, `CONFIG_INET6_ESP=m`, `CONFIG_XFRM_INTERFACE=m`, `CONFIG_NETFILTER_XT_MATCH_POLICY=m` (resolved through Kconfig here; adds `XFRM=y`) |
| SMB1 / NTLMv1 for CIFS | Insecure protocol; on by default with CIFS, so pinned off | Remove the `CIFS_ALLOW_INSECURE_LEGACY` line; `CIFS_POSIX` then becomes available |
| ipvlan | Its mandatory "l3s" mode builds `NET_L3_MASTER_DEV` into the core IP paths | `CONFIG_IPVLAN=m` |
| PPTP | Obsolete; needs GRE demultiplexing for itself | `CONFIG_NET_IPGRE_DEMUX=m`, `CONFIG_PPTP=m` |
| Legacy iptables tables (`IP_NF_FILTER`, `IP_NF_NAT`, ...) | `/usr/bin/iptables` is iptables-nft; nothing here uses `iptables-legacy`. Docker's checker lists them and will show them as missing | `CONFIG_NETFILTER_XTABLES_LEGACY=y` and the `IP_NF_*`/`IP6_NF_*` tables |
| `HZ`, preemption model, `NO_HZ_FULL`, cpuidle and thermal governors, the soft lockup detector | Scheduling, power and debugging policy; this delta changes none | The lead's decision |
| Lockdown, Yama, AppArmor, module signing | Security policy. Note the base's `CONFIG_LSM` string already names `lockdown` and `yama` although neither is built; only `capability,landlock` are active | The lead's decision |
| `DEBUG_INFO_BTF` (bpftrace, CO-RE tools) | Larger image and longer build | |
| USB Wi-Fi and DVB/TV adapters, ebtables, ipset, extra `ip_vs` schedulers, NFS server, iSCSI, software RAID, LVM thin/snapshot targets, `ZSWAP`, `LRU_GEN`, `USERFAULTFD`, `NTSYNC`, `FS_ENCRYPTION`, `TLS`, `MPTCP`, `USBIP`, `USB_PRINTER` (CUPS uses libusb) | No consumer on this machine | |
| `USB4_NET`, `TYPEC_TBT_ALTMODE`, `HOTPLUG_PCI_PCIE` (PCIe devices behind Thunderbolt) | USB4 is not working on the K114s yet | With the USB4 candidate |

One existing setting the sleep work should know about, unchanged here: `DPM_WATCHDOG=y` with
`DPM_WATCHDOG_TIMEOUT=15`. A device suspend or resume callback that takes longer than 15 seconds
panics the kernel (upstream's default is 120).

## How this was checked

All agent-run on the K114s itself, 2026-11-14, with user-local tools only.

- **Reference sources read:** `/proc/config.gz`; upstream `asahi.config`, `defconfig`,
  `hardening.config`, `j813.config` at `a34d26c2`, `b9ac02af` and `0b03fe43`; betizzel/omarchy-m5
  `linux-aurora-j714s` (config, `j714s-required.config`, `validate-config.py`, PKGBUILD) through
  v272-6; aurora-silicon/alarm-aurora `linux-aurora` config; the asahi-alarm 7.2.12 and Arch Linux
  ARM 7.3.4 configs; moby `contrib/check-config.sh` (read, not run).
- **Kconfig reproduction:** `/proc/config.gz` through `olddefconfig` in the running kernel's source
  (aurora-silicon/linux `a34d26c2` + the 19-patch J714s series + pull request 1568) comes back
  unchanged apart from the compiler version string and `CC_CAN_LINK`. So that tree and toolchain
  reproduce the running configuration.
- **Fragment resolution:** running configuration + `k114s-r3.config` through
  `merge_config.sh -m` and `olddefconfig`, in that tree and in upstream `b9ac02af`: the validator
  passes in both (385 requirements, 0 not met; 252 of them the fragment's own, all exact), and the
  two resolved configurations are identical. The three trees (base, running source, upstream head)
  define the same 22,098 Kconfig symbols.
- **The check bites:** against the running kernel's `/proc/config.gz`, the baseline passes
  (133 of 133) and the delta fails 246 of its 252 lines (the other six are the pins that are
  already true). After r3 both must pass.
- **Compile check:** see the next section.
- **Unit tests:** `python3 tests/config/test_validate_config.py`, 9 tests, pass.

### Compile check of the touched objects

Not a kernel build: no image, no module was linked into a `.ko`, nothing was installed.

- Tree and configuration: the running kernel's source with the resolved r3 configuration, clang
  23.1.3, rustc 1.98.1, the pinned bindgen; `modules_prepare`, then the directories and single
  objects the fragment adds to or changes: `drivers/hid`, `net/netfilter`, `net/ipv4`, `net/ipv6`,
  `net/sched`, `net/bluetooth/rfcomm`, `net/bluetooth/bnep`, `net/l2tp`, `net/vmw_vsock`,
  `kernel/sched`, `block`, `fs/exfat`, `fs/ntfs3`, `fs/hfsplus`, `fs/udf`, `fs/isofs`, `fs/f2fs`,
  `fs/xfs`, `fs/smb/client`, `fs/fat`, `fs/squashfs`, `fs/nls`, `drivers/net/ppp`,
  `drivers/net/wireguard`, `drivers/net/vxlan`, `drivers/net/usb`, `drivers/usb/serial`,
  `drivers/usb/storage`, `drivers/usb/class`, `drivers/usb/mon`, `drivers/usb/core`,
  `drivers/input/joystick`, `drivers/gpu/drm/udl`, `drivers/vhost`, `drivers/cdrom`,
  `drivers/base/firmware_loader`, `sound/core/seq`, `crypto/asymmetric_keys`, and the objects for
  binfmt_misc, fib rules, uinput, joydev, sr, sg, the fast-charge driver, the hrtimer and virmidi
  sound modules, vhost_task and textsearch.
- Result: 987 C objects compiled (649 of them module objects), exit status 0, no compiler
  warning and no error from kernel sources. That includes the four drivers the Aurora distribution
  configuration does not build (`hid-lenovo`, `hid-razer`, `f2fs`, `udl`).
- Size: the same directories were compiled once more with the running configuration. Built-in
  object code in them: 2,778,472 bytes before, 2,870,338 after (+91,866), largest in
  `kernel/sched` (+26,926: PSI, CFS bandwidth), `block` (+17,947: throttling, partition tables),
  `drivers/hid` (+16,240: hiddev, battery) and `net/ipv6` (+10,849: policy routing). The new
  built-in objects outside those directories add 25,890 (binfmt_misc 11,639; fib rules core
  12,019; vhost_task 1,146; textsearch 1,086).

## Not verified

- No kernel image or module tree was built or linked from this configuration, and nothing was
  booted. Whether each failure in the table above goes away is for the owner's boot to show.
- Image size growth and initramfs size were not measured.
- The fragment was not resolved on betizzel's v272-5/v272-6 source or on upstream `0b03fe43`.
  Read instead: v272-6 uses the same configuration file, its upstream pin `a5ebec5f` is three
  commits before `b9ac02af` with no Kconfig file changed between them, and its patch series
  touches no Kconfig file; `0b03fe43` is one commit after `b9ac02af` and changes only
  `asahi.config` and two test tools. So the same result is expected there, not shown.
- The [peripheral] and [common] entries were chosen from what distributions build and what is
  commonly plugged in. No such device was attached.
- Whether Docker starts cleanly was not tested (starting the daemon changes the firewall).

## Root steps

None for this work. The fragment is consumed by the kernel build; installing that kernel is the
integrator's step.
