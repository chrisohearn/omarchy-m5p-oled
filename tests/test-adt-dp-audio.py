#!/usr/bin/env python3
"""Replica test of tests/k114s-adt-dp-audio.py.

    python3 tests/test-adt-dp-audio.py

Builds a synthetic ADT in the m1n1 wire format with dp-audio nodes (one dma-parent as a name, one as a
phandle), plus a serial-number and a MAC-address property, runs the reader and fails if either secret is
printed, if dma-parent is not shown, or if bad arguments or a broken ADT are not rejected cleanly.
No Apple data is used.
"""
import importlib.util
import io
import os
import struct
import sys
import tempfile
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("dpaudio", os.path.join(HERE, "k114s-adt-dp-audio.py"))
dpaudio = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dpaudio)

SECRET_SERIAL = b"ZZTESTSERIAL0\0"
SECRET_MAC = bytes([0x02, 0x11, 0x22, 0x33, 0x44, 0x55])


def prop(name, value):
    return name.encode().ljust(32, b"\0") + struct.pack("<I", len(value)) + value + b"\0" * (-len(value) % 4)


def node(name, props=(), children=()):
    props = [("name", name.encode() + b"\0")] + list(props)
    return struct.pack("<II", len(props), len(children)) + b"".join(prop(k, v) for k, v in props) + b"".join(children)


def build():
    kids = [
        node("dp-audio0", [("dma-parent", b"admac-disp0\0"), ("wifi-mac", SECRET_MAC)]),
        node("dp-audio1", [("dma-parent", struct.pack("<I", 7))]),
        node("admac-dispext0", [("compatible", b"admac,t6050\0"), ("AAPL,phandle", struct.pack("<I", 7))]),
    ]
    return node("device-tree", [("serial-number", SECRET_SERIAL), ("#address-cells", struct.pack("<I", 2)),
                                ("#size-cells", struct.pack("<I", 2))], kids)


def run(args):
    out = io.StringIO()
    with redirect_stdout(out):
        code = dpaudio.main(args)
    return code, out.getvalue()


def main():
    failures = []

    def expect(name, cond, output):
        print("%s  %s" % ("ok  " if cond else "FAIL", name))
        if not cond:
            failures.append(name)
            print(output)

    with tempfile.NamedTemporaryFile(suffix=".adt") as handle:
        handle.write(build())
        handle.flush()
        code, text = run(["--adt", handle.name])
        expect("good ADT: exit 0", code == 0, text)
        expect("string dma-parent printed", "dma-parent: admac-disp0" in text, text)
        expect("phandle dma-parent resolved", "dma-parent: admac-dispext0" in text, text)
        for secret, what in ((SECRET_SERIAL.rstrip(b"\0").decode(), "serial number"), ("02:11:22", "MAC address"),
                             ("0x02, 0x11", "MAC bytes"), (str(list(SECRET_MAC)), "MAC cells")):
            expect("no %s in the output" % what, secret not in text, text)
        code, text = run(["--adt", handle.name, "--bogus"])
        expect("unknown argument: usage, exit 2", code == 2 and "usage" in text, text)
    with tempfile.NamedTemporaryFile(suffix=".adt") as handle:
        handle.write(b"\xff" * 64)
        handle.flush()
        code, text = run(["--adt", handle.name])
        expect("broken ADT: handled message, exit 1", code == 1 and "could not parse" in text, text)
    print("dp-audio reader replica test:", "FAILED" if failures else "passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
