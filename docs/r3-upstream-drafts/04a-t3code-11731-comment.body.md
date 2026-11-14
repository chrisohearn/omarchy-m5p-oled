_Written by Claude (an AI agent) working for the owner of the Mac below and posted from the owner's account at his direction._

For anyone who lands here: the owner of this crash is libyuv, it is fixed upstream, and the fix is in Electron 45 but not in Electron 44.

Still present in `0.1.10-nightly.20261114.4695` (linux-arm64 AppImage, Electron 44.10.1, Chromium 152.0.7977.169) on a MacBook Pro M5 Pro running Linux bare metal: `/proc/cpuinfo` has `sme sme2 sme2p1` and no `sve`, and renderers die with `SIGILL` / `ILL_ILLOPC` on a `ThreadPoolForegroundWorker` (four crash records on 2026-11-14).

**Which code.** The faulting function in this build is at virtual address `0x6b4754c` of `t3code` (the two crash PCs that kept a core end in `...754c`):

```
paciasp
sub     sp, sp, #0x460
cntd    x9              <-- SIGILL
...
smstart sm
cnth    x8
...
ld1h    {z3.h}, p1/z, [x0]
lsl     z0.h, z3.h, #6
usra    z0.h, z3.h, #4
...
st2h    {z16.h-z17.h}, p1, [x3]
```

Three 16-bit sources in `x0`-`x2`, a destination in `x3`, constants in `x4`, a width in `w5`, called through a function pointer: this is libyuv's `I210ToARGBRow_SME` (`source/row_sme.cc`), 10-bit 4:2:2 YUV to ARGB. All 48 `cntd x9` words in the binary sit within 23 kB of each other, `0x6b4376c` to `0x6b49170`, around this function. It is not XNNPACK code.

**Upstream fix.** libyuv `fab11704cda6`, 2026-09-09, "Use Armv8.5-A architecture flags for SME and SVE2 build targets" (Chromium bug 558654023). The SME files were compiled with `-march=armv9-a+i8mm+sme`; Armv9-A implies SVE, so Clang wrote `cntd` into the prologue of every `__arm_locally_streaming` function. The commit message names this crash on Apple M4/M5.

**Where it has landed** (from each branch's `DEPS`):

| | libyuv pin | Has the fix |
| --- | --- | --- |
| Chromium 152 (Electron 44.x, through 44.11.3) | `26e56be0`, 2026-08-18 | no |
| Chromium 153, 154 | `a0fa6329`, `2fed9193` | no |
| Chromium 155 and later | `2dd42573`, 2026-09-11 | yes |
| Electron 45.3.3 (Chromium 156.0.8078.100) | | yes |

Electron's `44-x-y` branch carries two libyuv cherry-picks in `patches/libyuv`, neither of them this one.

So this goes away when the desktop app moves to Electron 45, or if Electron takes `fab11704` into `44-x-y`. Not tested: we have not run an Electron 45 build of T3 Code on this Mac. The `arm64.nosme` workaround from the report is the only one we know of; the binary has no `LIBYUV_DISABLE_SME` switch.
