#!/usr/bin/env python3
"""Replica test of tests/hardware/k114s-external-display-adt.py.

    python3 tests/hardware/test-external-display-adt.py

Builds a small synthetic m1n1-format ADT whose root is named "device-tree" (as on a real machine),
with dcpext, dispext, dart and atc nodes, a dcpext without a nub, and a planted serial number.
Asserts that registers are translated, phandle targets resolve, a "watchdog" node is not listed,
and the serial never appears. No Apple data is used.
"""
import importlib.util
import io
import os
import struct
import sys
import tempfile
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("ext", os.path.join(HERE, "k114s-external-display-adt.py"))
ext = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ext)

OFFSET = 0x2_0000_0000
SECRET = b"ZZTESTSERIAL0\0"


def prop(name, value):
    return name.encode().ljust(32, b"\0") + struct.pack("<I", len(value)) + value + b"\0" * (-len(value) % 4)


def node(name, props=(), children=()):
    props = [("name", name.encode() + b"\0")] + list(props)
    return struct.pack("<II", len(props), len(children)) + b"".join(prop(k, v) for k, v in props) + b"".join(children)


def cells(*v):
    return struct.pack("<%dI" % len(v), *v)


def reg(addr, size):
    return struct.pack("<QQ", addr - OFFSET, size)


def build():
    ranges = struct.pack("<QQQ", 0, OFFSET, 0x1_0000_0000)
    dcp0 = node("dcpext0", [("reg", reg(OFFSET + 0x1000, 0x10)), ("role", b"DCPEXT\0"),
                            ("dp-switch-parent", cells(7)), ("audio", cells(8)),
                            ("serial-number", SECRET)],
                [node("iop-dcpext0-nub", [("uuid", b"IMG\0"), ("running", cells(1))])])
    dcp1 = node("dcpext1", [("reg", reg(OFFSET + 0x2000, 0x10))])  # no nub
    arm = node("arm-io", [("#address-cells", cells(2)), ("#size-cells", cells(2)), ("ranges", ranges)], [
        dcp0, dcp1,
        node("dispext0", [("reg", reg(OFFSET + 0x3000, 0x20))]),
        node("dart-dcpext0", [("reg", reg(OFFSET + 0x4000, 0x30))]),
        node("atc0-dpxbar", [("reg", reg(OFFSET + 0x5000, 0x10))]),
        node("watchdog", [("reg", reg(OFFSET + 0x6000, 0x10))]),
        node("display-crossbar0", [("AAPL,phandle", cells(7))]),
        node("dcpext-audio", [("AAPL,phandle", cells(8))]),
    ])
    return node("device-tree", [("#address-cells", cells(2)), ("#size-cells", cells(1))], [arm])


def run(argv):
    out = io.StringIO()
    with redirect_stdout(out):
        code = ext.main(argv)
    return code, out.getvalue()


def main():
    with tempfile.NamedTemporaryFile(suffix=".adt") as h:
        h.write(build())
        h.flush()
        code, out = run(["--adt", h.name])
    checks = {
        "exit 0": code == 0,
        "dcpext0 reg translated": "dcpext0 reg0 0x200001000" in out,
        "dp-switch-parent resolved": "dp-switch-parent=/arm-io/display-crossbar0" in out,
        "audio resolved": "audio=/arm-io/dcpext-audio" in out,
        "dispext regs": "dispext0 regs: 0x200003000" in out,
        "dart reg": "dart-dcpext0 reg0 0x200004000" in out,
        "dpxbar listed with reg": "/arm-io/atc0-dpxbar  reg0 0x200005000" in out,
        "missing nub reported": "no nub" in out,
        "missing dcpext2 reported": "dcpext2: missing" in out,
        "watchdog not listed": "watchdog" not in out,
        "no root name in paths": "/device-tree" not in out,
        "no serial printed": "ZZTESTSERIAL" not in out,
    }
    code, out = run(["--adt", "/nonexistent/adt"])
    checks["unreadable file is a message, not a traceback"] = code == 2 and "cannot read" in out
    failures = [k for k, v in checks.items() if not v]
    for k, v in checks.items():
        print("%s  %s" % ("ok  " if v else "FAIL", k))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
