# N1 Wi-Fi: 6 GHz and resume gating (issue #58)

Agent-run reads on the K114s (runtime only: `iw phy`, iwd and journal output; the pinned driver source (#1725) was not read for its 6 GHz or SAE paths), r3a default kernel on the GPU Stage 2, 2026-11-15. Nothing was written, joined or changed.

## Findings

| Question | Answer | Evidence |
|---|---|---|
| Is the N1 on omarchy-mac's resume-fix path? | No, and it cannot be | The N1 Wi-Fi driver (`apple_centauri_t6050`) binds function 0 (`106b:1900`); `106b:1902` is the 5 GHz controller function and has no bound driver (lspci -nn, `/sys/bus/pci/devices/*/driver`). `/usr/lib/omarchy-mac/wifi-supported` needs `omarchy-hw-apple-silicon` and a PCI ID in `14e4:(4425\|4433\|4434)`; it exits non-zero here. `omarchy-wifi-resume-fix.service` is disabled, and its `ExecCondition` is the same test, so it could not run even if enabled |
| Does omarchy-mac's 6 GHz-off default apply? | No. This image replaces it for the N1 | `systemctl show iwd -p Environment` gives `CONFIGURATION_DIRECTORY=/etc/iwd:/usr/lib/omarchy-aurora/iwd-n1`. Drop-in `30-aurora-n1-6ghz.conf` (omarchy-aurora-firmware) sorts after omarchy-mac's `20-omarchy-mac.conf`. The N1 `main.conf` sets no `BandModifier6GHz`, so iwd's default (1.0) applies and 6 GHz is on. The omarchy-mac file still says `0.0` but iwd never reads it. No `/etc/iwd/main.conf` override |
| Does the radio offer 6 GHz? | Yes | `iw phy`: 59 channels from 5955 MHz, marked `(no IR)` (passive until a beacon is heard, normal for 6 GHz) |
| Security path | Firmware SAE | `iw phy` lists `SAE_OFFLOAD`; ciphers CCMP-128 and CMAC only. Current link is WPA3-Personal on 5 GHz channel 36 (`iwctl station wlan0 show`), DHCP and gateway ping fine |
| Is a 6 GHz BSS visible here? | No | `iw dev wlan0 scan dump`: the cache holds 5 GHz BSSes only. The join test needs a 6 GHz AP |
| iwd profiles | One WPA profile plus a `hotspot` directory in `/var/lib/iwd` (root read) | `sudo ls /var/lib/iwd`. The profile for the joined network exists, so `wifi-iwd-profiles` conversion is not blocking the current join |
| Frame watch errors | `Could not register frame watch type 00b0 / 00d0: -95` in iwd's log at start | `journalctl -u iwd`; `-95` is EOPNOTSUPP. Does not stop joins; relates to SAE/auth frame handling in the offload path. Not shown to stop joins here (they succeed), but the cause is not confirmed. Noted for upstream |

## What this means for omarchy-mac

1. The 6 GHz-off default is moot on this image: the N1 drop-in replaces it (source: edimoldovan/omarchy-mac-pkgs `702a6ec363`, reported working on a J714c). Whether 6 GHz really works on the K114s is the open test below.
2. `wifi-supported` is BCM-only by design (its comment names BCM4378/4387/4388). On an M5 image the resume handling is chosen by omitting the unit, not deliberately. When suspend is unmasked we need either an N1 resume path or a conscious "none". Linux #1722 and #1729 (D0 across s2idle, reset on firmware death) are the driver-side answer, so the brcmfmac reload that the BCM fix does is the wrong tool for the N1 (there is no brcmfmac here; the driver is `apple_centauri_t6050`).
3. Proposed upstream ask (omacom): make the gate driver-based (any PCI function bound to `brcmfmac`; do not key on the `106b:1902` function, it has no driver link) instead of an ID list, so the N1 is excluded on purpose, and let `omarchy-hw-apple-silicon` machines with the N1 ship the 6 GHz-on iwd default. Draft in the PR description.

## Owner steps

6 GHz join test (needs a 6 GHz AP; no reboot, no power-off):

```
bash tests/hardware/k114s-wifi-check.sh status
# join the 6 GHz network from the Wi-Fi menu, then:
bash tests/hardware/k114s-wifi-check.sh 6ghz
```

PASS needs a 6 GHz link, the gateway answering and no join or firmware failure this boot. Journal lines are shown with MACs, IPs and quoted names redacted. If it joins but the gateway is silent, that is the BCM4388 symptom and the 6 GHz-off default should apply to the N1 too.

Post-resume check, once suspend is unblocked (docs/r3-sleep-lid.md):

```
bash tests/hardware/k114s-wifi-check.sh resume
```

`resume` FAILs when no suspend/resume is logged this boot, and only counts failures logged since the last resume.

## Status

Offline audit done. Remaining: the 6 GHz AP join test and the post-resume check (both owner), and the omacom issue (not filed from here).
