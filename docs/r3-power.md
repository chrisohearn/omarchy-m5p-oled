# Power on the K114s: charge limit, profiles, USB-C and MagSafe, fans

Evidence labels: **agent-run** (read on the Mac, 2026-11-15, nothing written), **replica** (a
script run against a made-up sysfs tree), **owner-observed**, **upstream-reported**. Issues #52,
#53, #55, #56, #57, #71. Nothing here was written to the SMC, sysfs or `/etc`.

## Owner-run and read-only scripts (`tests/hardware/`)

| Script | Needs | Writes | Issue |
|---|---|---|---|
| `k114s-charge-limit-test.sh status` | nothing | nothing | #53 |
| `sudo k114s-charge-limit-test.sh run` | **owner, sudo, on AC** | **SMC end threshold (80, then 100) and `/etc/udev/macsmc-battery.conf`**; 100 is restored on every exit | #53 |
| `k114s-battery-log.sh [secs [n]]` | unplug AC for the discharge part | nothing | #52, #56 |
| `k114s-plug-probe.sh [secs [label]]` | owner plugs and unplugs | nothing | #57, #71 |
| `k114s-thermal-log.sh [secs [n]]` | owner starts a load to spin the fans | nothing | #55 |

`tests/test-power-tools.sh` runs all of them, plus the installed `omarchy-battery-charge-limit`,
`/usr/lib/omarchy-mac/battery-charge-limit-restore`, the two udev rules and
`omarchy-powerprofiles-set`, against fake sysfs trees and stub `sudo`, `upower`, `busctl` and
`powerprofilesctl` (replica; 41 checks). It proves script logic, not that the T6050 SMC honours a
threshold.

## #53 charge limit

Installed pieces (agent-run): `omarchy-battery-charge-limit` (omarchy-mac), `battery-charge-limit-restore`,
udev rules `93-macsmc-battery-charge-control` (asahi-scripts) and `94-omarchy-mac-battery-charge-limit`.
`/etc/udev/macsmc-battery.conf` does not exist: no limit was ever set. `charge_control_end_threshold`
and `_start_threshold` read 100/100.

What the replica run shows:

- `limit 80` writes the end threshold, then demands end 80 and start 75 on readback, and only then
  saves `CHARGE_CONTROL_END_THRESHOLD=80`. If the driver ignores the write, the command exits 1 and
  saves nothing. Only `80` and `100` are accepted.
- The restore script applies a saved `80` or `100` and ignores anything else (including a
  malformed line), never fails the udev event, and does nothing off Apple Silicon.
- Rule 93 matches a two-digit saved value only, so a saved 100 is a no-op there; rule 94 calls the
  restore script on `add`. `udevadm verify` accepts both rules. They were syntax-checked, never
  executed.
- The boot restore is expected to fail on this kernel (agent-run). `udevadm info -p
  /class/power_supply/macsmc-battery` lists only DEVPATH and SUBSYSTEM: no tags, no properties, no
  `SYSTEMD_WANTS` (macsmc-ac has a full record). The kernel log twice shows `macsmc-battery: uevent:
  failed to send synthetic uevent: -95` at boot. That is the #1615 uevent defect: udev never handles
  the battery, so rules 93 and 94 never ran. The path unit
  `macsmc-battery-charge-control-end-threshold.path` belongs to asahi-scripts, is static and inactive
  on this boot, and was never pulled in. It is not needed to save a limit:
  `omarchy-battery-charge-limit` writes the saved file itself. On a kernel without #1615 a
  saved 80 is not restored at boot; do not blame the SMC for that.
- Not tested: whether the SMC accepts 80 and derives start 75, whether charging stops on AC at 80,
  and the boot restore (which depends on #1615). Owner step: `sudo
  tests/hardware/k114s-charge-limit-test.sh run` on AC, then `omarchy battery charge limit 80`,
  reboot, `k114s-charge-limit-test.sh status` (expect 100 until #1615 is booted), then
  `omarchy battery charge limit 100`.

## #52 battery status

The logger prints sysfs and UPower side by side and flags `MISMATCH` when they disagree on
charging or discharging, which is the 92 % versus 97 % case of #52.

**The -95 defect is fixed on r3a (agent-run, 2026-11-15, kernel `7.3.0-17.v272-4-k114s-r3a-ARCH`,
which carries sleep-lid/0007 = #1615).** Read-only checks on the booted r3a:

- `cat .../macsmc-battery/manufacture_year` returns "No data available" (-ENODATA, was -95).
- `cat .../macsmc-battery/uevent` prints 31 `POWER_SUPPLY_*` lines (it was empty).
- `journalctl -k -b` holds 0 lines with `manufacture_year` and 0 with `synthetic uevent` or `-95`.
- `udevadm info` on the battery now has a full record (`TAGS=:systemd:`, `SYSTEMD_WANTS` set to the
  charge-control path unit), and that path unit is active (waiting). So udev handles the battery and
  rules 93 and 94 can run (see the boot-restore note above; #53 still needs its owner run).
- Charging at 71 %: sysfs `Charging` / 71 and UPower `charging` / 70.18 % agree.

Not yet proven: UPower against sysfs during a discharge. Owner step: unplug AC and run
`tests/hardware/k114s-battery-log.sh 30 > battery.log` for a few minutes, plug back in, and confirm
no `MISMATCH` line. The #1615 PR is still an open draft upstream, so r3a carries it as a patch.

## #56 why the profile is `performance`, and what it is on battery

Source: `omarchy-powerprofiles-init`, `-set`, `-list`, `-floor` (omarchy-mac 4.5.0).

1. Hyprland autostart runs `omarchy-powerprofiles-init`, which is `omarchy-powerprofiles-set autodetect`.
   The shell battery service runs `omarchy-powerprofiles-set ac|battery` whenever UPower's
   `onBattery` changes (`shell/plugins/services/battery/Service.qml`), so the flip on unplug is the
   shell's job, not a udev rule or a daemon's.
2. `set` decides the source from UPower `OnBattery`, then looks for a saved choice in
   `~/.local/state/omarchy/powerprofiles/<ac|battery>`. That directory does not exist here (agent-run):
   no profile was ever picked in the panel.
3. With no saved choice, the default is **`performance` on AC** (when the daemon lists it, and it
   does) and **`balanced` on battery**. `power-saver` is never a default. So `performance` now is
   the AC default, not a K114s setting, and on battery it should be `balanced` unless a choice is
   saved. A choice made in the panel or menu is saved per source and wins (replica: six cases).
4. `omarchy-powerprofiles-floor` (uclamp minimum 1024 / 768 / 0 for performance / balanced /
   power-saver) is not running here (agent-run: no process, no unit); its comments describe
   Snapdragon and schedutil.
5. K114s specifics (agent-run): the CPU governor reads `performance` (driver `apple-cpufreq`) and the
   `apple-clpc` platform profile reads `performance` (choices low-power, balanced, performance).
   Whether the governor and platform profile follow the daemon on battery is not known; the
   battery logger and plug probe record both so the owner run answers it.
6. Draw on AC at idle, performance profile (agent-run, two samples of the SMC rails): total system
   power about 10 to 14 W, AC input about 10 to 16 W. The battery's `power_now` reads -0.27 W
   when Full, so its sign and scale need the discharge run.
7. Battery life stays limited by `pd_ignore_unused`, `clk_ignore_unused`, `m5_pmgr_ro` (with
   `m5_pmgr_allow=...`) and `idle=nop` on the kernel command line, and a disabled PMP. They can be
   dropped only after PMGR support lands. Not changed here.

## #57 and #71 USB-C and MagSafe

Agent-run: `macsmc-ac` online, `input_power_limit` **59 800 000 µW (59.8 W)**. `typec` port0 and
port1: `power_operation_mode` default, no `portN-partner`, role `[sink]` selectable as source,
data `host [device]`, PD revision 2.0. Both `tps6598x-source-psy-*` supplies are `online` 0. There is
no `usb_power_delivery` class. So the charger is not on a described USB-C port: it is on MagSafe or
the undescribed left-back port. The 59.8 W is the SMC's input limit for whatever is plugged in, not a
PD contract. `k114s-plug-probe.sh` records all of this and its changes during a plug cycle; the
owner names the connector and the LED colour. The MagSafe controller (hpm5) has no node; this
worker did not search upstream trees (read-only, no network task assigned).

## #55 fans and thermals

Agent-run: `macsmc_hwmon` has 275 temperature channels, 4 power rails, 2 voltages and 1 current (for example Total System
Power, AC Input Power, 3.8 V Rail, Heatpipe), fan1 and fan2 at 0 RPM (min 2000, max 8400 and 9072),
`fanN_target` 0. TAOC, TAOI, TAOJ, TAOP read -127 °C (absent sensors by value); TfCB and a handful of
others (Tz11 to Tz18, Tz1j, TNLc, TNSz, TNVn) read 0. The logger lists these once as absent and
leaves them out of the hottest list. The hottest channels at idle were TVDM, TVDC, TVD0, TCMb at
about 51 °C. No CPU thermal zone (only `thermal_zone0`, the battery). Masking the TAO keys needs the
ADT key list and a dts change: not done. The #1944 property is ported as an off-by-default macro in `dts/t6050-k114s-fan.dtsi` (see `docs/r3b-kernel.md`).

Update 2026-11-15 (agent-run, r3a kernel on the GPU desktop, no load generated): the fans now spin. Three samples
10 s apart with `tests/hardware/k114s-thermal-log.sh 10 3` read fan1 2198 to 2201 RPM and fan2 2370 to 2379 RPM
(min 2000, max 8400 and 9072; `fanN_target` 2200 and 2376, read only) at 22 to 26 W total system power with the
hottest channels TVDM, TVDC, TVD0 and TCMb at 68 to 69 C (one TCMb spike to 82.8 C). So a fan reading above its
minimum is now logged, but at desktop load, not a sustained load. Absent channels at this boot: TfCB, TAOC, TAOI,
TAOJ, TAOP, Tz11 to Tz18, Tz1j, TNLc, TNSz, TNVn (-127 or 0); the logger already keeps them out of the hottest list.
Still open: a sustained-load run with the logger (owner), the ADT key list for the TAO* keys, and CPU thermal zones.

