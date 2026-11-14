HOLD: Electron's AI Tool Policy (electron/governance policy/ai.md) requires a human in the loop and
does not allow an agent to post issues by itself. This text is a draft for the owner to read, check
against the evidence, edit and file himself through the bug report form at
https://github.com/electron/electron/issues/new/choose. The headings below are the form's fields.
Remove these four lines before filing.

**Title:** [Bug]: 44-x-y: renderer SIGILL on Arm CPUs with SME but no SVE (Linux on Apple M4/M5); libyuv fix fab11704 is not in Chromium 152

### Electron Version

44.10.1 (also 44.11.3 by source: same Chromium and the same `patches/libyuv`)

### What operating system(s) are you using?

Other Linux

### Operating System Version

Arch Linux ARM, kernel 7.3.0 (aarch64, 4 kB pages), Wayland (Hyprland), on a MacBook Pro with Apple M5 Pro

### What arch are you using?

arm64 (including Apple Silicon)

### Last Known Working Electron version

Not known. By source, 45.x has the fix (Chromium 156); not run here.

### Does the issue also appear in Chromium / Google Chrome?

Fixed there already: libyuv commit `fab11704cda62ff2d6b5e308b741e759ae816035` (2026-09-09, Chromium bug 558654023) is in Chromium 155 and later. Chromium 152, which 44-x-y ships, pins libyuv `26e56be0` from 2026-08-18 and does not have it.

### Expected Behavior

Renderer processes run on a CPU that has SME and no SVE.

### Actual Behavior

Renderer processes die with `SIGILL` (`ILL_ILLOPC`) on a `ThreadPoolForegroundWorker` thread. The CPU reports `sme sme2 sme2p1` and no `sve` in `/proc/cpuinfo`.

The faulting instruction is `cntd x9` in the prologue of libyuv's `I210ToARGBRow_SME`, before `smstart sm`:

```
paciasp
sub     sp, sp, #0x460
cntd    x9              <-- SIGILL: SVE instruction outside streaming mode
stp     d15, d14, [sp]
...
smstart sm
cnth    x8
```

libyuv built its SME sources with `-march=armv9-a+i8mm+sme`. Armv9-A implies SVE, so Clang emitted `cntd` in the prologue of its `__arm_locally_streaming` functions (48 `cntd x9` words in this binary). The upstream commit changes the flag to `-march=armv8.5-a+i8mm+sme` and names this crash on Apple M4/M5 in its message.

### Testcase Gist URL

None. The crash was seen in a packaged app (T3 Code nightly, pingdotgg/t3code#11731); the content that reaches the 10-bit 4:2:2 conversion was not isolated, and no Fiddle has been written.

### Additional Information

Request: cherry-pick libyuv `fab11704` into `patches/libyuv` on `44-x-y`, beside the two cherry-picks already there. It changes build flags only (`BUILD.gn`, `CMakeLists.txt`, `BUILD.bazel`).

Not checked: whether 43-x-y (Chromium 150) has the same code, and whether an Electron build with the patch runs on this machine.

Affected hardware is small: Linux on Apple M4 and M5 family chips, bare metal or in a VM that passes SME through. macOS builds were not looked at.

This report was drafted with an AI assistant (Claude) from the machine's crash records and the binary's disassembly, and reviewed by the person filing it.
