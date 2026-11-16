# Bluetooth audio on the K114s (issue #41)

Parity target: Asahi M1/M2 Bluetooth audio (A2DP and HFP through bluez and PipeWire).

## State on the r3a kernel (agent-run, read-only, 2026-11-15)

| Check | Result |
|---|---|
| Kernel | 7.3.0-17.v272-4-k114s-r3a-ARCH |
| Controller | hci0 bound to `btcentauri_t6050` (with `apple_centauri_t6050`), powered, not rfkill-blocked |
| RFCOMM | `CONFIG_BT_RFCOMM=m`, `rfcomm.ko` loaded at bluetoothd start; kernel log "RFCOMM ver 1.11" |
| bluetoothd journal | no `RFCOMM server failed` or `Protocol not supported` (the old kernel logged both) |
| bluez UUIDs | A2DP sink and source, Hands-Free, Hands-Free AG, AVRCP; Headset (HSP) is not advertised (bluez 5.88 with HFP native; not a fault) |
| Stack | bluez 5.88, pipewire 1.6.11, wireplumber 0.5.19; `libspa-bluez5` has SBC, AAC, aptX, LDAC, Opus, LC3 and the HFP mSBC, CVSD, LC3 codec plugins |
| A2DP endpoints | SBC, AAC, aptX, aptX HD, LDAC, Opus registered with bluetoothd |
| Paired devices | none |

Not done offline: `btvirt` (a virtual controller) is not packaged on this system, so profile enumeration against a
virtual peer was not run. WirePlumber's default A2DP codec priority was not checked either (pending; the codec plugins above are installed, the order they are chosen in is unverified). Whether the controller reports mSBC (eSCO) capability shows only once a headset connects.

## Owner steps

1. Run `bash tests/hardware/k114s-bt-audio-check.sh --no-save` (read-only; expect 0 BAD).
2. Put a headset in pairing mode. In `bluetoothctl`: `scan on`, `pair <address>`, `trust <address>`, `connect <address>`.
3. `bash tests/hardware/k114s-bt-audio-check.sh --listen`: play music 60 s over A2DP, run a download beside it, note dropouts.
4. Hands-free: `pactl set-card-profile <card> headset-head-unit`, record or call, note whether the mic works.
5. Paste the report into the issue.

This script is separate from `k114s-r3a-audio-check.sh` because that one stops at its speaker tripwires on the
GPU-tree Stage 2, where no sound tree is present. Bluetooth audio does not use the speaker path.

Done when (owner-observed): A2DP plays without dropouts and the HFP microphone works.
