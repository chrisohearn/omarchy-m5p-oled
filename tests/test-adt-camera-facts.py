#!/usr/bin/env python3
"""Replica test of tests/k114s-adt-camera-facts.py (issue #33).

    python3 tests/test-adt-camera-facts.py

Builds a made-up ADT (with a planted serial number and MAC address, which must never be printed) in the m1n1 wire format from the K116s camera values that are public in
aurora-silicon/linux #1648 and aura #188 (kboot.c), checks that the checker passes it with a K114s
sensor type, and that it fails (or the loader gate refuses) on a wrong sensor type, a wrong segment
layout, a segment outside RAM, a wrong interrupt and a wrong power-state offset. No Apple data
is used: this proves the checker's reading and comparisons, not anything about a real machine.
"""
import importlib.util
import io
import os
import struct
import sys
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("cam", os.path.join(HERE, "k114s-adt-camera-facts.py"))
cam = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cam)
sf = cam.sf
node, prop = sf._node, sf._prop
w = lambda *a: struct.pack("<%dI" % len(a), *a)
q = lambda *a: struct.pack("<%dQ" % len(a), *a)
s = lambda x: x.encode() + b"\0"
SECRET_SERIAL = b"ZZTESTSERIAL0001\0"
SECRET_MAC = bytes.fromhex("021122334455")


def device(name, ident, parent, offset=0):
    e = bytearray(48)
    struct.pack_into("<H", e, 4, parent)
    struct.pack_into("<H", e, 16, offset)
    struct.pack_into("<H", e, 26, ident)
    e[32:32 + len(name)] = name.encode()
    return bytes(e)


def build(sensor=0xBA, irq0=513, isp_sys_off=0x3A0, phys0=0x1000109C000, remap1=0x10000C1C000, board=0x14, os_fw="mBoot-20457.41.3"):
    ram = 0x10000000000
    seg = struct.pack("<QQQII", phys0, 0, 0x10000000000, 0xC1C000, 1) + \
        struct.pack("<QQQII", 0x100026A0000, 0xC1C000, remap1, 0x13D0000, 0)
    devices = b"".join([device("FAB9_SOC", 217, 49, 0x398), device("ISP_SYS", 218, 217, isp_sys_off),
                        device("ISPSENS0", 134, 0, 0x100), device("ISP_CPU", 220, 218), device("ISP_FE", 221, 218)])
    root = node("device-tree", [("target-type", s("K114s")), ("compatible", s("K114sAP")),
                                ("serial-number", SECRET_SERIAL)], [
        node("chosen", [("board-id", w(board, 0)), ("dram-base", q(ram)), ("dram-size", q(0x1000000000)),
                        ("firmware-version", s(os_fw)),
                        ("system-firmware-version", s("mBoot-20457.60.65.0.1"))]),
        node("wlan", [("local-mac-address", SECRET_MAC)]),
        node("product", [], [node("camera", [("camera-hdr-version", w(3))])]),
        node("arm-io", [], [
            node("pmgr", [("devices", devices)]),
            node("eic", [("mmio-wd-isp", q(0x5C3B50000, 0x8000))]),
            node("isp0", [("reg", w(0x80000000, 0x3, 0x3FF0000, 0, 0x80900000, 0x2, 0x3F4, 0, 0x80920000, 0x2, 0x4000, 0)),
                          ("interrupts", w(irq0, 514, 515, 516, 526)), ("uuid", s(cam.UUID)),
                          ("segment-names", s("__TEXT;__DATA")), ("cam-connections-scheme", w(0x10)),
                          ("active-mcc-bit-vector", w(0xF)), ("sensor-type", w(sensor)), ("segment-ranges", seg)]),
            node("dart-isp0", [("reg", q(0x5828C0000, 0xC000, 0x5828E0000, 0xC000, 0x582900000, 0xC000,
                                         0x5828F4000, 0x4000, 0x582914000, 0x4000, 0x5828D0000, 0x4000)),
                               ("interrupts", w(531)), ("sid", w(0, 12)), ("exclave-sid", w(4, 5, 8, 9)),
                               ("remap", w(1, 6, 7, 10, 11)), ("vm-base", q(0x10000000000)),
                               ("vm-size", q(0x30000000000))]),
        ]),
    ])
    return sf.Tree(sf.parse(root)[0])


def result(t):
    buf = io.StringIO()
    with redirect_stdout(buf):
        bad = cam.run(t, out=buf)
    return bad, buf.getvalue()


def main():
    fails = 0

    def check(name, cond):
        nonlocal fails
        print(("ok   " if cond else "FAIL ") + name)
        fails += not cond

    t = build()
    # the made-up arm-io has no ranges property: give the tree the two translations the checker uses
    t.ranges = [(0x3_8000_0000, 0x5_8000_0000, 0x1_0000_0000), (0x0_8000_0000, 0x2_8000_0000, 0x1_0000_0000)]
    bad, out = result(t)
    outputs = [("passing run", out)]
    check("K114s sensor 0xba: no FAIL, loader gate passes", bad == 0 and "would pass" in out)
    check("sensor-type is reported as a DIFF, not a failure", "DIFF isp0 sensor-type" in out)
    check("the K114c row 0xb9 is reported as not matching", "K114c row 0xb9 does NOT match" in out)
    for name, kw, needle in (("sensor type 0xbc", dict(sensor=0xBC), "refuses: sensor type"),
                             ("wrong interrupt", dict(irq0=600), "FAIL isp0 interrupts"),
                             ("wrong ISP_SYS offset", dict(isp_sys_off=0x3A8), "FAIL pmgr ISP_SYS power-state"),
                             ("segment below RAM", dict(phys0=0x1000), "outside RAM"),
                             ("wrong data remap", dict(remap1=0x10000C20000), "segment layout"),
                             ("OS firmware 27.3 beta 1 (system firmware is not the key)",
                              dict(os_fw="mBoot-20457.60.65.0.1"), "is not mBoot-20457.41.3 (V27_2)")):
        t = build(**kw)
        t.ranges = [(0x3_8000_0000, 0x5_8000_0000, 0x1_0000_0000), (0x0_8000_0000, 0x2_8000_0000, 0x1_0000_0000)]
        bad, out = result(t)
        outputs.append((name, out))
        check("%s: fails (%s)" % (name, needle), bad > 0 and needle in out)
    # the passing run, and every variant above, must print neither planted secret
    for what, text in outputs:
        check("%s: output has no serial number or MAC address" % what,
              "ZZTEST" not in text and "02:11:22" not in text and "021122" not in text.replace(":", ""))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
