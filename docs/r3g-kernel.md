# r3g kernel candidate

r3g rebases [r3f](r3f-kernel.md) onto Aurora Silicon's main at
[`2094ccb2a03610eec4362ee3a47f8cf0aeba58e1`](https://github.com/aurora-silicon/linux/commit/2094ccb2a03610eec4362ee3a47f8cf0aeba58e1).
The candidate is `linux-k114s 7.3.0.r3g-1`, release `7.3.0-17.v272-18-k114s-r3g-ARCH`.
It is intended for the r3e1 Backup slot. r3f remains the running Main kernel.
See the [one-shot trial plan](r3g-trial-plan.md) for the hardware checks and restore.

## Patch disposition

Of the 74 r3f patches, 36 are carried forward and 38 are replaced by upstream.
Of the drops, 29 share a stable patch ID and nine were matched by content.
The 37th patch in [r3g.series](../patches/linux/r3g.series) preserves the r3f NOR write gates.
Applying the series to the pinned base produces source tree
`f45454184c59f53589474c89e0b96fa8839b4daa`.

The display, input and board-tree carries retain their r3f behavior across upstream
changes. The VRR watchdog includes upstream's external pipe handling. The T6050
HDMI present hold uses the shared fixed-HDMI reconnect path at initial bring-up.
The DockChannel parser keeps both the upstream descriptor-replacement test and
the local clamp test. The board includes carry both upstream and local descriptions
until the final patch removes the new K114s NVRAM description. The ALS carry
(r3f 0021, r3g 0019) keeps the K114c DT property and drops the duplicate
`firmware-name` binding hunk already in upstream `242ce586c508`. That duplicate
key prevented schema validation of the ALS node in r3f.

The sound driver and binding are identical to the pinned upstream tree. The
K114 profile disables speakers, sets a safe level of zero and keeps the
jack-only admission test. The trial uses the existing speaker-disabled Stage 2
tree and userspace guards. The packaged DTB is an independently built kernel-tree
DTB.

r3f kept boot NOR writes closed through three independent checks. r3g keeps the
read-only QSPI default and its existing fail-closed policy, removes the new K114s
NVRAM partition from the packaged tree, and reverses the GD25UF64E allowlist
addition so the controller still refuses that part even when the configured
Stage 2 describes its read-only NVRAM partition. Patch 0037 records the local
reversals of `59c72f163caa` and `0cb67690b3f5`. Deep sleep stays compiled out
with `CONFIG_APPLE_SOC_SLEEP` disabled, and the r3f DCP refusal for unsupported
deep sleep is carried forward.

### Drops and their replacements

| r3f patch | Upstream PR | Replacement commit | Match or upstream change |
| --- | --- | --- | --- |
| 0014 | [#3104](https://github.com/aurora-silicon/linux/pull/3104) | `fb544885d926`, `9d3eeaa5d8dd` | Binding and jack-only profile split into two commits. The upstream profile also sets `.safe_vol = 0`. |
| 0020 | [#2631](https://github.com/aurora-silicon/linux/pull/2631) | `52dabe33448b`, `4ae8c061c84a` | T6050 SoC matching supersedes the board allowlist. The SEP mailbox must be enabled. |
| 0022 | [#2877](https://github.com/aurora-silicon/linux/pull/2877) | `6fb60db5532e` | Stable patch ID. |
| 0023 | [#2877](https://github.com/aurora-silicon/linux/pull/2877) | `8ecf51d29987` | Stable patch ID. |
| 0030 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `346d605686aa` | Stable patch ID. |
| 0031 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `170449e2c714` | Upstream also checks the AP idle acknowledgment state. |
| 0032 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `7421a1a79e07` | Upstream stops secure polling when sleep arms and restarts it on disarm. |
| 0033 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `143d1f3a964d` | Stable patch ID. |
| 0034 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `d7a03887c98b` | Upstream primes both wake completions before panel power-on. |
| 0035 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `2d9df0f1e607` | Stable patch ID. |
| 0036 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `ec721590b804` | Stable patch ID. |
| 0037 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `c048e783897c` | Stable patch ID. |
| 0038 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `b777c1c56ccc` | Stable patch ID. |
| 0039 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `7ef2687fa382` | Stable patch ID. |
| 0040 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `702d2f151788` | Stable patch ID. |
| 0041 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `b3337cac2dcb` | Stable patch ID. |
| 0042 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `36692dbd26ab` | Upstream keeps the counted dark-wake path when adding the saved-context rules. |
| 0043 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `7fc2cf790107` | Stable patch ID. |
| 0044 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `ff9cd2204f95` | Stable patch ID. |
| 0045 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `005028ce2115` | Stable patch ID. |
| 0046 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `28994e4d3eaa` | Stable patch ID. |
| 0047 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `c01b3d33f098` | Stable patch ID. |
| 0048 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `827ec97a92d9` | Stable patch ID. |
| 0049 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `bb339b549430` | Stable patch ID. |
| 0050 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `c4e6e7af3478` | Stable patch ID. |
| 0051 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `c4ba4a3a90d3` | Stable patch ID. |
| 0052 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `f35f68016160` | Stable patch ID. |
| 0053 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `747379cb3980` | Stable patch ID. |
| 0054 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `8d0d34bcaa5b` | Stable patch ID. |
| 0055 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `6e836d8f6815` | Stable patch ID. |
| 0056 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `2b672b1501e7` | Stable patch ID. |
| 0057 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `59236983556e` | Stable patch ID. |
| 0058 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `5b8f42b4109d` | Only the secure-mailbox comment differs in the patch content. |
| 0059 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `c115ae9eea44` | Stable patch ID. |
| 0060 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `c4ff2269ee60` | Stable patch ID. |
| 0061 | [#2201](https://github.com/aurora-silicon/linux/pull/2201) | `a01d61c1f397` | Stable patch ID. |
| 0063 | [#2631](https://github.com/aurora-silicon/linux/pull/2631) | `52dabe33448b` | Same SoC selection, against the upstream starting allowlist. |
| 0064 | [#2631](https://github.com/aurora-silicon/linux/pull/2631) | `4ae8c061c84a` | Same enabled-mailbox check and K114s selection test. |

## Upstream changes since r3f

The changes below are in the pinned base. Hardware behavior on the K114s
remains to be verified in the trial.

| Area | Changes |
| --- | --- |
| N1 Wi-Fi and Bluetooth | [#3120](https://github.com/aurora-silicon/linux/pull/3120) fixes scan stop and abort synchronization and reschedules Bluetooth ring work. [#3110](https://github.com/aurora-silicon/linux/pull/3110) gates Centauri commands during host sleep. [#2884](https://github.com/aurora-silicon/linux/pull/2884) handles 6 GHz multiple-BSSID beacons and disabled channels. [#2908](https://github.com/aurora-silicon/linux/pull/2908) preserves the length of station counters. |
| G17 GPU | [#3170](https://github.com/aurora-silicon/linux/pull/3170) keeps firmware-mutable pool state uncached. [#2501](https://github.com/aurora-silicon/linux/pull/2501) accounts render-target memory, checks compact-window fit and preserves render pairs. [#2949](https://github.com/aurora-silicon/linux/pull/2949) clears pool storage on VM handoff. [#2955](https://github.com/aurora-silicon/linux/pull/2955), [#2969](https://github.com/aurora-silicon/linux/pull/2969) and [#3024](https://github.com/aurora-silicon/linux/pull/3024) add direct submission and reduce locking on submission and completion. |
| AOP and input | [#2906](https://github.com/aurora-silicon/linux/pull/2906) restarts AOP endpoint rings cleanly on GETBUF. [#2934](https://github.com/aurora-silicon/linux/pull/2934) fixes ADMAC config ownership and validates LPAI period and ring sizes. [#2899](https://github.com/aurora-silicon/linux/pull/2899) synchronizes DockChannel descriptors and commands. [#2952](https://github.com/aurora-silicon/linux/pull/2952) uses the MTP actuator's firmware click. [#3039](https://github.com/aurora-silicon/linux/pull/3039) exposes Force Click as `KEY_INFO` by default. |
| SEP | [#2900](https://github.com/aurora-silicon/linux/pull/2900) restricts the xART store to internal NVMe. [#2903](https://github.com/aurora-silicon/linux/pull/2903) lets a biometric capture end a pending key-touch wait. [#3168](https://github.com/aurora-silicon/linux/pull/3168) notifies sysfs on keystore and Touch ID diagnostic transitions. |
| USB-C | [#3014](https://github.com/aurora-silicon/linux/pull/3014) retries selection sooner during SN201202x wake. [#2299](https://github.com/aurora-silicon/linux/pull/2299) selects DWC3 idle runtime PM by DT power domains. [#3018](https://github.com/aurora-silicon/linux/pull/3018) allows NHI router DMA-credit preferences. [#2983](https://github.com/aurora-silicon/linux/pull/2983) releases the Thunderbolt control hold before connection-manager resume. |
| Idle | [#2190](https://github.com/aurora-silicon/linux/pull/2190) defers `idle=nop` until built-in drivers probe. [#3011](https://github.com/aurora-silicon/linux/pull/3011) waits for pending PMC votes on DCS writes. |

## Reproduce the package

Use the native K114s build environment and an r3g checkout at the pinned
upstream base. Set `repo` to this repository's checkout.

```bash
source "$HOME/k114s-build/env.sh"
src="$B/src/r3g"
out="$B/out/r3g"
mapfile -t series < <(sed '/^#/d; /^$/d' "$repo/patches/linux/r3g.series")
for index in "${!series[@]}"; do
    series[$index]="$repo/patches/linux/${series[index]}"
done
git -C "$src" am "${series[@]}"
cd "$src"
printf -- '-17.v272-18-k114s-r3g' > localversion.10-pkgrel
mkdir -p "$out"
cp "$B/out/r3f/.config" "$out/.config"
kmake O="$out" olddefconfig
K114S_LABEL=K114S-R3G kmake O="$out" -j12 Image modules dtbs

dest=$(mktemp -d "$B/build/r3g-evidence.XXXXXX")
cd "$repo/packaging/linux-k114s"
K114S_CAND=r3g K114S_SRC="$src" K114S_OUT="$out" \
    BUILDDIR="$dest/makepkg" PKGDEST="$dest" makepkg --nodeps --skipinteg
```

## Offline checks

- The complete series replayed from the pinned base and produced the tree
  required by the PKGBUILD source guard. That guard rejected the r3f source and
  a fixture that enabled `CONFIG_APPLE_SOC_SLEEP`.
- `olddefconfig` kept the r3f config byte-for-byte. The validator checked 385
  requirements from the two K114s fragments. All passed, with 21 requested
  modules already built in.
- `CHECK_DTBS=1 apple/t6050-k114s.dtb` completed without diagnostics with
  dtschema 2026.9. The resulting DTB matched the package build's byte-for-byte.
  The K114s DTB contains no NVRAM partition or SPI-NOR device.
- The camera indicator passed the same 11 standalone cases recorded for
  r3f. The r3f checks used the standalone build of the suite. No kernel was
  booted to run in-kernel KUnit for this candidate.
- The QSPI userspace policy tests passed with simulated inputs. The kernel
  QSPI sources match r3f, and the sound driver and binding match the pinned
  upstream base.
- `check-package.sh` passed against the installed `linux-aurora` and
  `linux-k114s-r3b` packages. There were no file collisions or unresolved
  module symbols. All 1,973 modules had the r3g vermagic and the archive
  contained the 46 expected DTBs. The unpacked Image, embedded config,
  separate config and K114s DTB matched the build inputs and outputs.
- `build/check-publishable.sh` passed.

## Build record

Native build on the K114s on 2026-11-26, using Clang 23.1.3 and Rust 1.98.1.
Image, modules and DTBs took 397.361 seconds. Packaging took 35.998 seconds.

| Item | Value |
| --- | --- |
| Package file | `linux-k114s-7.3.0.r3g-1-aarch64.pkg.tar.xz` |
| Package size | 32,652,016 bytes |
| Package SHA-256 | `2bf59bfea2576a6df0b0c3b8e587990d43bf4e13a4646a17212ff526a65f3e57` |
| Raw Image size | 54,675,968 bytes |
| Raw Image SHA-256 | `3f642bde5267f4e8f3ac09902d7d33192ca81517d469287de1f5b54b7e3d707d` |
| Stripped modules | 1,973 files, 113,420,112 bytes total |
| Packaged config SHA-256 | `28e3c445bf9321bb65d3d76756dc9eac1d45a2cfee44b5309dd3f78d7a9a210a` |
| Packaged K114s DTB SHA-256 | `5079fc3667db51aecc4b12aba91d57db4d1895a8636267eee843bf2dfe59ae24` |

Clang produced upstream diagnostics, including thread-safety warnings in
Apple NVMe and a missing prototype in the Type-C driver. The build completed.
The Backup-slot boot and hardware checks are pending.

## ESP estimate

The saved r3e1 Backup UKI is 79,808,000 bytes. Its PE `.linux` section
contains the 54,413,824-byte raw Image. The r3g Image is 262,144 bytes
larger. With the same initramfs and PE overhead, the Backup UKI would be
about **80,070,144 bytes** (76.36 MiB).

The ESP had 128,114,688 bytes free. Replacing r3e1 in its existing slot
at that estimate would leave 127,852,544 bytes free, about 39.8 MB above
the 88,080,384-byte guard. One full temporary UKI copy would leave about
48 MB available until the old file is replaced. Two full temporary UKIs
would exceed the available space. The trial preflight needs the actual
UKI size and peak use of the installed hooks. See [ESP space](esp-space.md).
