#!/usr/bin/python3 -I
# SPDX-License-Identifier: MIT
"""k114s-adt-camera-facts.py: does this Mac's Apple device tree (ADT) describe the same camera as the K116s?

    sudo python3 -I tests/k114s-adt-camera-facts.py [--adt FILE]

Issue #33. Reads the ADT (the "adt" MTD partition, root only, or --adt FILE) and checks every
value that the K116s camera description (aurora-silicon/linux #1648, "The camera" block of
t6050-k116s.dts, and t6050-j716c-isp.dtsi) and aura's T6050 ISP hand-off (aura #188, function
dt_set_t6050_isp in src/kboot.c) depend on, then re-runs the loader's own gate on the ADT.

  "ok"/"FAIL" lines   a value both trees must agree on (K116s expected, K114s found)
  "DIFF" lines        a value that differs from the K116s on purpose: the sensor type
  "info" lines        a K114s fact with no counterpart; they never fail the run

Only addresses, interrupt numbers, stream ids, power-state offsets, the firmware uuid and the
sensor type are printed. Serial numbers, calibration and firmware bytes are never read.
Exit 0: every shared fact holds and the loader gate (sensor type 0xba, OS firmware V27_2) would pass.
Exit 1: a fact differs. Exit 2: the ADT is unreadable or is not a K114s.
"""
import importlib.util
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("soundfacts", os.path.join(HERE, "k114s-adt-sound-facts.py"))
sf = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sf)

K116S_SENSOR, K114C_SENSOR, K114S_SENSOR = 0xBC, 0xB9, 0xBA   # K114s: read from this ADT, not from upstream
OS_FW_V27_2 = "mBoot-20457.41.3"                               # aura firmware.c: V27_2 (the 27.2 OS stub); 27.3 beta 1 is mBoot-20457.60.65.0.1
UUID = "980F533B-34EA-3FBA-878C-809F6AF57345"                  # the isp_bni/adc-nyx-sck11pm firmware (K116s, aura #188)
SZ_16K = 0x4000


def hexs(v):
    if isinstance(v, (list, tuple)):
        return "[" + ", ".join(hexs(x) for x in v) + "]"
    if isinstance(v, bool):
        return "yes" if v else "no"
    if isinstance(v, int):
        return hex(v) if v >= 4096 else str(v)
    return repr(v)


def pmgr_device(t, name):
    """(id, parent id, power-state offset) of the pmgr device called @name (48-byte entries)."""
    d = t.prop("arm-io/pmgr", "devices") or b""
    for i in range(0, len(d) - 47, 48):
        if d[i + 32:i + 48].split(b"\0", 1)[0] == name.encode():
            return (struct.unpack_from("<H", d, i + 26)[0], struct.unpack_from("<H", d, i + 4)[0],
                    struct.unpack_from("<H", d, i + 16)[0])
    return None


def segments(t):
    """adt_segment_ranges: 32 bytes each, phys u64, iova u64, remap u64, size u32 + flags u32."""
    v = t.prop("arm-io/isp0", "segment-ranges") or b""
    return [dict(zip(("phys", "iova", "remap", "size"),
                     (struct.unpack_from("<QQQ", v, i) + (struct.unpack_from("<I", v, i + 24)[0],))))
            for i in range(0, len(v) - 31, 32)]


def loader_gate(t, want_sensor):
    """aura dt_set_t6050_isp, ADT side (aura 22b71758): why it would refuse, or None if it would pass."""
    ch, seg = t.node("chosen"), segments(t)
    if ch is None or t.node("arm-io/isp0") is None:
        return "no /chosen or isp0"
    ram, ram_size = sf.u64(ch["props"].get("dram-base")), sf.u64(ch["props"].get("dram-size"))
    sensor = (sf.u32s(t.prop("arm-io/isp0", "sensor-type")) or [None])[0]
    if ram is None or not ram_size:
        return "no dram range"
    os_fw = sf.text(ch["props"].get("firmware-version"))   # the table's firmware key (aura os_firmware), not system-firmware-version
    if os_fw != OS_FW_V27_2:
        return "OS firmware %s is not %s (V27_2): the row is keyed to it" % (os_fw, OS_FW_V27_2)
    if sensor != want_sensor:
        return "sensor type %s is not 0x%x" % (hex(sensor) if sensor is not None else None, want_sensor)
    if len(seg) != 2 or len(t.prop("arm-io/isp0", "segment-ranges")) != 64:
        return "not two segments"
    total = 0
    for i, s in enumerate(seg):
        size = (s["size"] + SZ_16K - 1) & ~(SZ_16K - 1)
        if not size or s["phys"] & (SZ_16K - 1) or s["phys"] < ram or s["phys"] - ram >= ram_size \
                or size > ram_size - (s["phys"] - ram):
            return "segment %d outside RAM or unaligned" % i
        total += size
        for j in range(i):
            p = (seg[j]["size"] + SZ_16K - 1) & ~(SZ_16K - 1)
            if s["phys"] < seg[j]["phys"] + p and seg[j]["phys"] < s["phys"] + size:
                return "segments overlap"
    if total > 64 << 20:
        return "segments above 64 MiB"
    if not (seg[0]["iova"] == 0 and seg[0]["size"] == 0xC1C000 and seg[1]["iova"] == 0xC1C000
            and seg[1]["size"] == 0x13D0000 and seg[0]["remap"] == 0x10000000000
            and seg[1]["remap"] == 0x10000C1C000):
        return "segment layout is not the K116s one"
    return None


def facts(t):
    """[(kind, what, expected, found)] kind: 'eq' must match the K116s, 'diff' differs on purpose."""
    A, D = "arm-io/isp0", "arm-io/dart-isp0"
    out = []
    eq = lambda what, exp, found: out.append(("eq", what, exp, found))
    ch = t.node("chosen")
    eq("target-type", "K114s", sf.text(t.root["props"].get("target-type")))
    eq("isp0 reg[0] (translated) + size", [0x580000000, 0x3FF0000], [t.addr(A, 0), t.size(A, 0)])
    eq("isp0 reg[1] pmgr-side window", [0x280900000, 0x3F4], [t.addr(A, 1), t.size(A, 1)])
    eq("isp0 interrupts", [513, 514, 515, 516, 526], sf.u32s(t.prop(A, "interrupts")))
    eq("isp0 firmware uuid", UUID, sf.text(t.prop(A, "uuid")))
    eq("isp0 segment-names", "__TEXT;__DATA", sf.text(t.prop(A, "segment-names")))
    eq("isp0 cam-connections-scheme", 0x10, (sf.u32s(t.prop(A, "cam-connections-scheme")) or [None])[0])
    eq("isp0 active-mcc-bit-vector", 0xF, (sf.u32s(t.prop(A, "active-mcc-bit-vector")) or [None])[0])
    eq("eic mmio-wd-isp (window, size)", [0x5C3B50000, 0x8000],
       [sf.u64(t.prop("arm-io/eic", "mmio-wd-isp"), 0), sf.u64(t.prop("arm-io/eic", "mmio-wd-isp"), 1)])
    out.append(("diff", "isp0 sensor-type (K116s 0xbc, K114c 0xb9)", K116S_SENSOR,
                (sf.u32s(t.prop(A, "sensor-type")) or [None])[0]))
    eq("dart-isp0 instances", [0x5828C0000, 0x5828E0000, 0x582900000], [t.addr(D, i) for i in (0, 1, 2)])
    eq("dart-isp0 instance size", 0xC000, t.size(D, 0))
    eq("dart-isp0 address filter (dapf)", 0x5828D0000, t.addr(D, 5))
    eq("dart-isp0 interrupt", 531, (sf.u32s(t.prop(D, "interrupts")) or [None])[0])
    eq("dart-isp0 host streams (sid)", [0, 12], sf.u32s(t.prop(D, "sid")))
    eq("dart-isp0 exclave streams", [4, 5, 8, 9], sf.u32s(t.prop(D, "exclave-sid")))
    eq("dart-isp0 remap", [1, 6, 7, 10, 11], sf.u32s(t.prop(D, "remap")))
    eq("dart-isp0 vm-base, vm-size", [0x10000000000, 0x30000000000],
       [sf.u64(t.prop(D, "vm-base")), sf.u64(t.prop(D, "vm-size"))])
    for name, offset in (("FAB9_SOC", 0x398), ("ISP_SYS", 0x3A0), ("ISPSENS0", 0x100)):
        d = pmgr_device(t, name)
        eq("pmgr %s power-state offset" % name, offset, d[2] if d else None)
    isp_sys = (pmgr_device(t, "ISP_SYS") or (None,))[0]
    eq("pmgr ISP_SYS id (the K116s dtsi's 0xda)", 0xDA, isp_sys)
    eq("pmgr ISP_CPU/FE parent is ISP_SYS", [isp_sys, isp_sys],
       [(pmgr_device(t, n) or (0, None))[1] for n in ("ISP_CPU", "ISP_FE")])
    seg = segments(t)
    eq("firmware segments: size, iova, remap", [[0xC1C000, 0, 0x10000000000], [0x13D0000, 0xC1C000, 0x10000C1C000]],
       [[s["size"], s["iova"], s["remap"]] for s in seg])
    return out


def run(t, out=sys.stdout):
    bad = 0
    for kind, what, exp, found in facts(t):
        if kind == "eq":
            ok = exp == found
            bad += not ok
            print("%-4s %s: expected %s, found %s" % ("ok" if ok else "FAIL", what, hexs(exp), hexs(found)), file=out)
        else:
            print("DIFF %s: K116s %s, this ADT %s" % (what, hex(exp), hex(found) if found is not None else None), file=out)
    seg = segments(t)
    ch = t.node("chosen")
    for i, s in enumerate(seg):
        print("info segment %d: phys %s size %s (iBoot places these; they move after an update)"
              % (i, hexs(s["phys"]), hexs(s["size"])), file=out)
    print("info chosen firmware-version (OS, the loader table's key; V27_2 is %s): %s"
          % (OS_FW_V27_2, sf.text(ch["props"].get("firmware-version"))), file=out)
    print("info chosen system-firmware-version (system iBoot, not part of the key): %s"
          % sf.text(ch["props"].get("system-firmware-version")), file=out)
    print("info /product/camera camera-hdr-version: %s" % hexs((sf.u32s(t.prop("product/camera", "camera-hdr-version")) or [None])[0]), file=out)
    print("info isp0 children (sensor nodes): %s" % hexs(t.children("arm-io/isp0")), file=out)
    print("info K114c row 0xb9 does NOT match this ADT: %s" % loader_gate(t, K114C_SENSOR), file=out)
    gate = loader_gate(t, K114S_SENSOR)
    bad += gate is not None
    print("%-4s loader gate (aura dt_set_t6050_isp) with a K114s row of 0x%x: %s"
          % ("ok" if gate is None else "FAIL", K114S_SENSOR, "would pass" if gate is None else "refuses: " + gate), file=out)
    return bad


def main(argv):
    path = None
    if argv[:1] == ["--adt"] and len(argv) == 2:
        path = argv[1]
    elif argv:
        print(__doc__)
        return 2
    try:
        t = sf.Tree(sf.load(path))
        if (sf.u32s(t.prop("chosen", "board-id")) or [None])[0] != sf.BOARD_ID:
            print("this ADT is not the K114s (board-id 0x14); refusing")
            return 2
        return 1 if run(t) else 0
    except (sf.AdtError, OSError, ValueError, KeyError) as e:
        print("k114s-adt-camera-facts: %s: %s" % (type(e).__name__, e), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
