# r3i kernel candidate

r3i rebases the K114s series onto Aurora Silicon Linux `main` at
[`85cde3ca97c8`](https://github.com/aurora-silicon/linux/commit/85cde3ca97c8da78cf7c3a7e77c99319d8cf0770).
The candidate source is commit `67bea3896a827ffc12c762370625475661b0cb15`,
tree `c1dfbeeb56ed282ebb30717a8b27b9a0f30a4f8d`, with 31 patches in
[`r3i.series`](../patches/linux/r3i.series).

r3i is intended for the Backup slot as `linux-k114s 7.3.0.r3i-1`. Main remains
`linux-k114s-r3b 7.3.0.r3g-1`, and Backup remains
`linux-k114s 7.3.0.r3f-1`. r3i has not been installed or booted on the K114s;
its build and emulator checks are offline evidence only. The current boot pair
and Stage 2 remain unchanged.

## Patch disposition

The replay dropped four r3h patches already carried by upstream:

| r3h patch | Upstream replacement |
| --- | --- |
| `0002-drm-apple-Refuse-panel-brightness-once-the-display-p.patch` | `1e5eebd9656d`, including a new selftest |
| `0012-HID-dockchannel-hid-clamp-Report-Size-items-where-th.patch` | `d4b57f3332d6`, including the parser test |
| `0013-HID-dockchannel-hid-pad-short-reports-to-the-clamped.patch` | `ccf90dc84ec2`; `3a408344e12b` sizes the buffer to `HID_MAX_BUFFER_SIZE` |
| `0016-drm-apple-describe-an-internal-panel-without-a-known.patch` | `128023ecf2f7`, including the parser tests |

The DTS patches were re-cut for the new shared files: r3i `0017` (fans and
sensors), `0019` (GPU plus PMIC), `0022` (camera, Touch ID and NVRAM layout),
and `0023` (AOP and speaker include). Dependent patches `0028`, `0030` and
`0031` were rechecked against those changes. Firmware 27 keeps the upstream
no-PQ behavior; there is no 500-nit EDR cap.

The package keeps the owner's safety choices:

- K114s audio uses the jack-only profile and denies speaker admission. The
  K114c profile remains separate.
- The QSPI controller defaults to read-only. The final K114s DTB has no SPI NOR
  client, NVRAM partition or alias, and `GD25UF64E` is not in the write
  allowlist. No SPI NOR or NVRAM writes were attempted.
- Apple SoC deep sleep stays disabled, and the DCP `.prepare` path refuses the
  unsupported firmware 27 deep-sleep step. Suspend-to-idle remains available.
- The camera has no described light. Its solid 32×32 indicator remains centered
  under the notch at y=104.

## Offline checks

The build used Clang 23.1.3 and Rust 1.98.1.

| Check | Result |
| --- | --- |
| `olddefconfig` from r3g | Passed; enabled `CONFIG_APPLE_SEP_HDCP_INTERFACE=y`. |
| `build/validate-config.py` | Passed: 385 requirements met, including 21 requested modules built in. |
| `CHECK_DTBS=1 apple/t6050-k114s.dtb` and direct `dt-validate` | Passed with dtschema 2026.9 and no diagnostics. |
| `Image modules dtbs` | Passed in 462 seconds; built 1,973 modules and 1,952 DTBs. Clang and Rust emitted warnings. |
| QEMU shell smoke | Passed; userspace ran and the guest powered off. |
| QEMU all-module smoke | Passed: 1,966 successful `modprobe` calls and no Oops or panic. |
| QSPI NVRAM policy harness | Passed: 37 checks, including 27 mutation controls. |
| `macaudio` KUnit in QEMU | Passed: all 71 tests, including denial of K114 speaker admission. |
| `check-package.sh` vs `linux-aurora` and `linux-k114s-r3b` | Passed. The archive has 1,973 modules with the candidate vermagic, no unresolved symbols or file collisions, and the expected K114s DTB policy. |

The seven QEMU module-load failures were `tcrypt`, `ipmi_si`,
`cppc_cpufreq`, `sun50i-cpufreq-nvmem`, `stratix10-soc`,
`apple-pmp-j613-hwmon`, and `xen-pciback`; this is the same set as r3h.

The package was built as
`linux-k114s-7.3.0.r3i-1-aarch64.pkg.tar.xz`, with kernel release
`7.3.0-17.v272-20-k114s-r3i-ARCH`.

| Artifact | SHA-256 |
| --- | --- |
| Package | `e2ff16a90d9d9cba56f842366867e5149502344debbbf69977960b41255d4c4b` |
| Image | `e108aa7bbb3eecd1cd643090b9736c799c377ff836509b14e711c9917b46900f` |
| Config | `a81a292efc6ba16949a4f451705a2aba39bba27c7fbbc421b1f042d4f9708a59` |
| Packaged K114s DTB | `0356415688766db6bee28db118e5cdde3ea4b622222c585e273c9501dfdbf962` |

The package archive passed `check-package.sh` after `makepkg` completed with
exit 0; makepkg emitted two `libfakeroot` payload warnings. Build commands,
exit codes and full artifact hashes remain in the local evidence directory
`$HOME/k114s-build/build/r3i-20261128-logs.Om5pYC/`.

## Next step

The kernel PR and the recovery kit require independent review before Backup
staging. The kit changes only the Backup package, UKI and menu entry, then
updates P9's Backup package-version check. Main r3g and Stage 2 must remain
byte-identical. The staging path does not arm or reboot. Hardware comparisons,
the attended trial, P9 and Tailscale checks after boot, and any promotion remain
pending. No PR-head boot is authorized by this candidate record.
