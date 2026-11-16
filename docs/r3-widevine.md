# Widevine on the K114s (issue #31)

Parity target: M1/M2 Omarchy installs `widevine` (aarch64 CDM) so Chromium and Firefox can play DRM streams.

## Agent-run evidence (2026-11-15, r3a on the GPU Stage 2)

| Check | Result |
|---|---|
| `pacman -Q widevine` | 4.10.2891.0-1 |
| CDM file | `/opt/WidevineCdm/chromium/_platform_specific/linux_arm64/libwidevinecdm.so`, ELF aarch64, 10.3 MB; the `linux_x64` file is an empty placeholder |
| ELF load alignment | 0x10000 (64 KiB) on every LOAD segment, so it maps on the 16 KiB-page kernel |
| `dlopen` from Python (`ctypes.CDLL`) | loads; exports `CreateCdmInstance`, no `INITIALIZE_CDM_MODULE` symbol |
| Manifest | version 4.10.2891.0, codecs vp8, vp9.0, avc1, av01, host and interface version 10 |
| Chromium 157.0.8103.38 component registration (`--enable-logging --v=1`) | "Preinstalled component found for Widevine Content Decryption Module at /usr/lib/chromium/WidevineCdm with version 4.10.2891.0", then "Component ready" |
| Headless key-system probe (`tests/hardware/k114s-widevine-probe.sh`, profile warmed by one earlier launch) | **PASS** on the first try: `requestMediaKeySystemAccess('com.widevine.alpha')` is `ok` for avc1 with and without `SW_SECURE_CRYPTO`; `org.w3.clearkey` is `ok`. A vp9 config (`vp09.00.10.08`) still gives `NotSupportedError`; it is not a failure signal, since avc1 works |

## Why a first probe fails

Chromium on Linux uses a component-registered CDM only after a restart. The first launch of a profile writes `WidevineCdm/latest-component-updated-widevine-cdm` (here `{"Path":"/opt/WidevineCdm/chromium"}`); the next launch reads it before the zygote forks. A probe on a brand-new profile therefore always gets `NotSupportedError`, headless or headed, with `clearkey` ok. The probe script now warms its throwaway profile with one headless launch first. The "Widevine enabled but no library found" log line at start-up is harmless. The CDM (host interface 10) works with Chromium 157, so this is not a packaging fault.

## Owner steps

Only the real-stream check is left, and it needs the panel:

Open a DRM page (Shaka Player's demo with a Widevine asset, or a streaming service the owner signs in to) in Chromium and say whether video plays or the frames are blank.
`~/.config/chromium-flags.conf` already disables `AcceleratedVideoDecoder`, so decode is the software path, as on the M1/M2.
`bash tests/hardware/k114s-widevine-probe.sh --headed` repeats the key-system probe in a real window if needed; add `--user-data-dir="$(mktemp -d)"` to any manual `chromium --enable-logging=stderr --v=1` run, and keep the `grep -i -E 'cdm|widevine'`.
