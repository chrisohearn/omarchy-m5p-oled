# GPU qualification on the K114s (issue #34)

2026-11-15. Evidence labels: **agent-run** (read on this Mac), **upstream-reported** (pull request state read at the source),
**owner-needed** (not yet run). Kernel `7.3.0-17.v272-4-k114s-r3a-ARCH`, the promoted default, on the GPU Stage 2.

## State of the three gates in the issue

| Gate | State | Evidence |
| --- | --- | --- |
| GPU mailbox receive interrupt (aurora-silicon/linux #1844, `sleep-lid/0009`, `0010`) | **Proven on the K114s.** `2302600000.mailbox-recv` count over 1 million across 18 CPUs this boot; rate 218-303/s idle in three samples | agent-run (`/proc/interrupts`, `tests/hardware/k114s-gpu-qualify.sh`). #1844 merged 2026-11-13, upstream-reported |
| Desktop on the GPU tree as the configured Stage 2 | **Done.** r3a promoted with the GPU tree; no fault, timeout, hang or error line from `aurora` this boot | agent-run (`journalctl -k -b`, count 0); promotion in `docs/r3a-promotion.md` |
| Suspend with the GPU active | **Open, blocked.** Sleep targets stay masked. J714s suspend to RAM (#1963) merged 2026-11-15; K116s s2idle (#1647) still open. Needs r3b (carries #1844 in full) and an attended test | upstream-reported; owner-needed |
| Power, frequency, thermals | **Not available from the driver.** See below | agent-run |

## What the driver reports today (agent-run, root read of `/sys/class/drm/card1/device`)

`agx_stats` on this kernel: `utilisation_status valid` (source firmware-statistics-tag-0x13; device, renderer and tiler
percent and `busy_ns` read); but `pstate_status unavailable`, `pstate`, `requested_frequency_hz`, `achieved_frequency_hz`,
`power_mw` and `temperature_raw` all read `unsupported`. `power/runtime_status` reads `unsupported`, `runtime_active_time` and
`runtime_suspended_time` stay 0, `idle_off_delay_ms` is 2. There is no `/sys/class/devfreq` entry. So there is no GPU
frequency scaling, no GPU power figure and no GPU die temperature on the G17S today: "qualified" in the sense of the M1/M2
baseline cannot be claimed, and no script can measure the missing values. Whole-machine power (SMC total system power) and the
SMC temperatures are readable and are what the harness records around a load.

The two known kernel lines are unchanged: `unsupported GPU firmware build ... GPU firmware image not admitted: EINVAL` for
26C5035r, then `GPU firmware build: 26B8125 ... G17S` admitted. Not a fault; upstream's G17S 27.2 identification is still draft
(#1173, #1650). The "unqualified" Mesa warning is upstream's.

Upstream owners for the remaining gaps: aurora-silicon (G17S power and DVFS reporting, #1173/#1650), omacom (Mesa qualification).

## Harness (offline work, this PR)

`tests/hardware/k114s-gpu-qualify.sh [INTERVAL [SAMPLES]]` is read-only. It samples GPU utilisation, the GPU mailbox interrupt rate,
the hottest SMC temperature, fans, total system power and the count of `aurora` fault lines, prints which telemetry is
`unsupported`, and ends `RESULT: PASS` or `RESULT: FAIL`. `tests/hardware/test-gpu-qualify.sh` tests its logic against a fake
sysfs. Agent-run on the live GPU desktop for 3 samples at idle: PASS, 0 fault lines, 15.9-21 W total, hottest SMC channel
about 72 C, fans about 2200 RPM.

## Owner steps (not run; they load the GPU)

```sh
# 1. In a terminal at the Mac: record 10 minutes while you load the GPU yourself, for example
#    by opening a WebGL demo in the browser, or switching workspaces with animations on.
sudo bash tests/hardware/k114s-gpu-qualify.sh 5 120 | tee gpu-soak.log
# 2. Afterwards: the RESULT line and any new aurora line
tail -1 gpu-soak.log
sudo journalctl -k -b --no-pager | grep -i -E 'aurora.*(fault|timeout|hang|error)'
```

A GPU hang during step 1 would be new information and may need a forced power-off. Suspend stays blocked until r3b has booted on
the GPU tree (`docs/r3b-kernel.md`); the attended suspend test is its own step there.

## Proposed index changes (not edited here)

- `docs/matrix.md` GPU row: mailbox interrupt gate proven on the K114s (2026-11-15); frequency scaling, power and temperature
  `unsupported` by the driver; suspend with the GPU still open.
- `docs/r3-sleep-lid.md` 0009-0010 row: the gate that kept `0010` out of r3a is met by step G; r3b may carry it.
