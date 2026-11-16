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
| Headless key-system probe (`tests/hardware/k114s-widevine-probe.sh`) | **FAIL**: `requestMediaKeySystemAccess('com.widevine.alpha')` gives `NotSupportedError` for avc1, vp9, and with or without `SW_SECURE_CRYPTO`, on every try for 20 s. `org.w3.clearkey` succeeds in the same page, so EME and a secure context (`localhost`) work |

Chromium also logs "Widevine enabled but no library found" from `cdm_registration.cc` at start-up, before the component registers.

## What this does and does not show

The CDM is installed, loadable and registered as a component, but Chromium did not offer it as a key system in headless mode. Two readings fit, and headless alone cannot tell them apart:

1. Headless Chromium does not hand the registered CDM to the key-system list (a headless limitation). A headed run would pass.
2. The CDM (host interface version 10, built September 2025) is rejected by Chromium 157 (interface mismatch, or a missing CDM library path in the Arch ARM build). A headed run would fail the same way.

The headed run decides it. It opens a Chromium window for a few seconds, so it is an owner step.

## Owner steps

```
bash tests/hardware/k114s-widevine-probe.sh --headed
```

PASS means the key system works in a real browser. FAIL with `clearkey ok` means reading 2; then run
`chromium --enable-logging=stderr --v=1 2>&1 | grep -i -E 'cdm|widevine'` once and attach the lines to the issue.
On PASS, open a DRM page (Shaka Player's demo with a Widevine asset, or a streaming service the owner signs in to) and say whether video plays or the frames are blank.
`~/.config/chromium-flags.conf` already disables `AcceleratedVideoDecoder`, so decode is the software path, as on the M1/M2.

## Owner

If reading 2 is confirmed, the owner of the fix is the `widevine` / `chromium` packaging on Arch Linux ARM (and omacom for the Omarchy package list), not the K114s kernel.
