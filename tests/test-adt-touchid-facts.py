#!/usr/bin/env python3
"""Replica test of tests/k114s-adt-touchid-facts.py (no hardware, no kernel tree).

    python3 tests/test-adt-touchid-facts.py

Builds a made-up ADT in the m1n1 wire format and a made-up tree whose values agree with it, runs
check() and expects no failure, then changes one ADT pin or one tree pin at a time and expects a FAIL.
Also expects a missing ADT property to exit 2, not crash. No Apple data is used.
"""
import contextlib
import importlib.util
import io
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("touchid", os.path.join(HERE, "k114s-adt-touchid-facts.py"))
tf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tf)
sf = tf.sf
node = sf._node
prop = lambda n, v: (n, v)
u = lambda *v: struct.pack("<%dI" % len(v), *v)
q = lambda *v: struct.pack("<%dQ" % len(v), *v)
b = lambda *v: struct.pack(">%dI" % len(v), *v)
GPIO = sf.GPIO_FOURCC


def adt(pwr_pin=21, dr_pin=138, mesa_extra=(), spi2_clock=True):
    spi2 = [prop("reg", q(0x505108000, 0x4000)), prop("interrupts", u(1369))]
    if spi2_clock:
        spi2.append(prop("clock-ids", u(451)))
    mesa = [prop("sensor-id", u(0x3356)), prop("spi-frequency", u(8000000)), prop("AAPL,phandle", u(7)),
            prop("function-mesa_pwr", u(5, GPIO, pwr_pin)), prop("interrupt-parent", u(6)), prop("interrupts", u(dr_pin))]
    io_ = [node("spi2", spi2, [node("mesa", mesa)]),
           node("nub-gpio0", [prop("reg", q(0x2881e4000, 0x4000)), prop("#gpio-pins", u(61)), prop("AAPL,phandle", u(5))]),
           node("gpio0", [prop("AAPL,phandle", u(6))]),
           node("sep", [prop("reg", q(0x502600000, 0x4000, 0x502050000, 0x4000)), prop("interrupts", u(533, 534, 535, 536)),
                        prop("clock-ids", u(447))]),
           node("dart-sep", [prop("reg", q(0x500b80000, 0x20000)), prop("interrupts", u(543)),
                             prop("vm-base-0", u(0x4000, 0x100)), prop("vm-size-0", u(0xffff0000))])]
    return sf.Tree(sf.parse(node("device-tree", [], [node("arm-io", [prop("ranges", u(0, 0, 0, 0, 0, 0))], io_)]))[0])


def tree(pwr_pin=21, dr_pin=138):
    return type("F", (), {"nodes": {
        "/soc/spi@505108000": {"reg": b(5, 0x05108000, 0, 0x4000), "interrupts": b(0, 0, 1369)},
        "/soc/spi@505108000/fingerprint@0": {"reg": b(0), "spi-max-frequency": b(8000000),
                                             "enable-gpios": b(1, pwr_pin, 0), "interrupts": b(dr_pin, 1)},
        "/soc/pinctrl@2881e4000": {"reg": b(2, 0x881e4000, 0, 0x4000), "apple,npins": b(61)},
        "/soc/sep@502600000": {"reg": b(5, 0x02600000, 0, 0x4000, 5, 0x02050000, 0, 0x4000), "clocks": b(1, 447)},
        "/soc/mailbox@502608000": {"reg": b(5, 0x02608000, 0, 0x4000),
                                   "interrupts": b(0, 0, 533, 0, 0, 0, 534, 0, 0, 0, 535, 0, 0, 0, 536, 0)},
        "/soc/iommu@500b80000": {"reg": b(5, 0x00b80000, 0, 0x20000), "interrupts": b(0, 0, 543),
                                 "apple,dma-range": b(0x100, 0x4000, 0, 0xffff0000)},
    }})()


def run(t, f):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        bad = tf.check(t, f)
    return bad, out.getvalue()


bad, out = run(adt(), tree())
assert bad == 0, out
for what, a, f in (("ADT power pin", adt(pwr_pin=22), tree()), ("tree power pin", adt(), tree(pwr_pin=22)),
                   ("ADT data-ready pin", adt(dr_pin=139), tree()), ("tree data-ready pin", adt(), tree(dr_pin=139))):
    bad, out = run(a, f)
    assert bad and "FAIL" in out, what
# a missing ADT property is "unreadable" (exit 2), not a traceback
sys.argv = ["x", "/dev/null"]
try:
    run(adt(spi2_clock=False), tree())
except IndexError:
    pass
else:
    raise SystemExit("missing clock-ids should raise IndexError for main() to map to exit 2")
print("test-adt-touchid-facts: all passed")
