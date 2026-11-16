# CPU frequency, governor and CLPC/PMP on the K114s

Evidence labels: **agent-run** (read on the Mac, 2026-11-15, nothing written), **upstream-reported**.
Issue #54. Nothing here changed a governor, profile, sysfs value or the boot chain.

## Why the governor is `performance` (agent-run)

The kernel is not the cause. The running r3a kernel has `CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y`
(from `/proc/config.gz`), `CONFIG_ARM_APPLE_SOC_CPUFREQ=y`, and every policy lists
`ondemand userspace performance schedutil`. The governor reads `performance` because
`omarchy-power-profiles-daemon` 0.30-9 switches it:

- The daemon binary contains `ppd-driver-cpufreq.c` with a scaling-driver check for `apple-cpufreq`,
  the messages "Could not switch %s to the %s governor" and "Setting the %s governor back", and the
  `schedutil` and `powersave` names (read with `strings`; its source was not read, so the exact
  profile-to-governor table is not confirmed).
- The Omarchy default (`omarchy-powerprofiles-set`, see [r3-power.md](r3-power.md) item 1 to 3) is
  `performance` on AC and `balanced` on battery. The Mac is on AC with no saved choice, so the
  profile is `performance`, and the governor and the `apple-clpc` platform profile both read
  `performance` with it.
- Consequence: all three policies sit at their maximum (cpus 0-5 and 6-11 at 4380 MHz, 12-17 at
  4608 MHz) while idle. This is the AC default working as designed, not a K114s fault. It costs idle
  power on AC only; on battery the default is `balanced`.

## What the daemon does not give us

Even under `balanced`, the schedutil frequency choice is only as good as the hardware loop behind
it. Not enabled in the K114s tree: the PMP nodes (`pmp0_report`), so the fast-die effort properties
in `dts/t6050-k114s-fast-die.dtsi` stay off (see [r3b-kernel.md](r3b-kernel.md)), and the CPU PMU and
CLPC link that K116s also holds back (linux `cd2c9f52`, per matrix.md). Without the PMP the cpufreq
driver holds each cluster at its fallback limit; whether that limit is below the 4.3+ GHz target is
not known until the PMP-off behaviour is measured on battery. No CPU thermal zone exists
(`thermal_zone0` is `macsmc-battery`), so thermal throttling cannot be read through cpufreq either.

## What is left

1. Owner, on battery, once, no reboot: unplug with no saved choice and no manual set, then
   `tests/hardware/k114s-cpufreq-log.sh 2 30 > cpufreq.log` idle, then again while a load runs
   (`yes > /dev/null &` on four cores, `kill %1` after). This records whether the shell flips to
   `balanced` by itself on unplug ([r3-power.md](r3-power.md) item 3, the #54 done-check) and
   whether the governor follows the daemon on battery (r3-power.md item 5). Only if the profile
   did not flip, run `powerprofilesctl set balanced` and sample again. Expected if the daemon
   switches governors: `schedutil`, idle near 300 MHz, load above 4 GHz. The idle=nop and
   PMP-disabled command-line limits (r3-power.md item 7) may keep idle above 300 MHz. Expected
   failure to report: governor stays `performance`, or load stays below the maximum (then the cap
   is the PMP-less fallback). Restore with `powerprofilesctl set performance` on AC, or delete the
   saved choice if one was made.
2. Agent, offline: confirm the profile-to-governor table in the daemon source (omarchy-pkgs).
3. Owner, boot trial (can hang): the PMP nodes and `K114S_R3B_FAST_DIE`, after the PMP tunables are
   available; shared T6050 kernel work belongs to TripleU613 and aurora-silicon (linux #481, #1324,
   #1326, #1789).
4. Backports #1951 and #2005 were not reviewed in this pass (no network task assigned).

## Script

`tests/hardware/k114s-cpufreq-log.sh [secs [n]]` is read-only: power profile, platform profile,
AC or battery, and per policy the governor, current and maximum MHz.
