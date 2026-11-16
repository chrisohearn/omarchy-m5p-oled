# Chromium GPU process on the K114s (issue #28)

Parity target: with a render node, Chromium and Electron apps use the GPU. omarchy-mac forces software GL only while no render node exists.

## Agent-run result (2026-11-15, r3a kernel on the GPU Stage 2, no window opened)

`tests/hardware/chromium-gpu-report.sh` starts Chromium 157.0.8103.38 headless with a temp profile and reads `chrome://gpu` over the DevTools protocol (loopback port, deleted on exit). It reads only; the owner's session is untouched.

GPU run (no `LIBGL_ALWAYS_SOFTWARE`):

| Item | Result |
|---|---|
| Canvas, Compositing, Rasterization, WebGL, WebGPU | Hardware accelerated |
| OpenGL | Enabled, `gl=egl-angle,angle=opengl`, display type `ANGLE_OPENGL_EGL` |
| 2D backend | Skia (Ganesh GL), GPU process not in-process, not crashed |
| GL_RENDERER | `ANGLE (Mesa, AGX G13/G14, OpenGL ES 3.2 Mesa 26.3.0-devel ...)` |
| Video decode / encode | Software only (`--disable-features=AcceleratedVideoDecoder` in `chromium-flags.conf`, the omarchy-mac setting) |
| Vulkan, Skia Graphite, WebNN | Disabled (Chromium defaults) |
| GPU-process crash lines in the log | 0 |

Notes:

- Chromium's ANGLE reports the Mesa renderer as "AGX G13/G14", not "Apple M5 Pro" (the name `vulkaninfo` and Mesa GLES give). It is a string mapping, not a different device. Do not grep for "Apple M5 Pro" in a Chromium report; `media-smoke.sh --chromium` does, and cannot read the page anyway (see below).
- `--dump-dom chrome://gpu`, used by `media-smoke.sh --chromium`, needs `--allow-chrome-scheme-url` in headless mode and even then returns only the unrendered page shell. Use the new script instead. `media-smoke.sh` no longer has a `--chromium` mode.
- In a session the guard keeps on the CPU, the GPU run prints SKIP (exit 2) instead of a hardware FAIL; it never overrides the guard.
- The script lets Chromium pick its own DevTools port, reads it from the profile, and still reads the user's `chromium-flags.conf` and may touch `~/.pki/nssdb`.
- `tests/hardware/test-chromium-gpu-report.sh` tests the script's logic with stubs.
- Software fallback (`--software`: the environment the repo's `70-k114s-gpu-desktop` guard sets, `LIBGL_ALWAYS_SOFTWARE=1 GBM_ALWAYS_SOFTWARE=1 ASAHI_M5_BRINGUP=0`; the omarchy-mac wrapper's own behaviour is not verified here): Canvas, Compositing, Rasterization software only, WebGL and WebGPU disabled, no crash lines. The fallback path works.
- The flags file also loads the Omarchy extensions; they start fine headless.

## Left for the owner

Confirm a real window draws in the live Hyprland session (no blank window, no GPU-process crash): open Chromium, load `chrome://gpu` and a WebGL page, and watch for a "GPU process crashed" infobar. Headless proves the GPU process and the GL backend, not the Wayland surface path.
