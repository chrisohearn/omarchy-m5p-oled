#!/usr/bin/env python3
"""Software test of tests/k114s-usb-root-probe.py with a made-up ADT and made-up register files.
No hardware and no root involved."""
import contextlib
import importlib.util
import io
import os
import struct
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("probe", os.path.join(HERE, "k114s-usb-root-probe.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


def prop(name, value):
    return name.encode().ljust(32, b"\0") + struct.pack("<I", len(value)) + value + b"\0" * (-len(value) % 4)


def node(name, props=(), children=()):
    props = [("name", name.encode() + b"\0")] + list(props)
    return struct.pack("<II", len(props), len(children)) + b"".join(prop(k, v) for k, v in props) + b"".join(children)


def u32(*v):
    return struct.pack("<%dI" % len(v), *v)


def reg64(*pairs):  # (address, size) pairs below /arm-io, 2 address cells and 2 size cells
    return b"".join(u32(a & 0xffffffff, a >> 32, s, 0) for a, s in pairs)


def adt(spmi_a0_regs=((0x8a188000, 0x4000), (0x8a184000, 0x4000)), hpm1_addr=0x0a, with_hpm5=True):
    hpms_a0 = [node("hpm0", [("reg", u32(0x0c)), ("port-type", u32(2))]),
               node("hpm1", [("reg", u32(hpm1_addr)), ("port-type", u32(2)), ("port-number", u32(2))])]
    if with_hpm5:
        hpms_a0.append(node("hpm5", [("reg", u32(0x08)), ("port-type", u32(0x11)), ("features-supported", u32(3))]))
    arm_io = node("arm-io", [
        ("#address-cells", u32(2)), ("#size-cells", u32(2)),
        # child 0x0 -> parent 0x2_00000000, 16 GiB
        ("ranges", u32(0, 0, 0, 2, 0, 4)),
    ], [
        node("nub-spmi-a0", [("reg", reg64(*spmi_a0_regs)), ("#address-cells", u32(1)), ("#size-cells", u32(0))], hpms_a0),
        node("nub-spmi-a1", [("reg", reg64((0x8a1a8000, 0x4000), (0x8a1a4000, 0x4000), (0x8a1a0000, 0x4000))),
                             ("#address-cells", u32(1)), ("#size-cells", u32(0))],
             [node("hpm2", [("reg", u32(0x0c)), ("port-type", u32(2))])]),
        node("usb-drd1", [("reg", reg64((0xaa280000, 0x18000), (0xaa200000, 0x4000)))]),
        node("usb-drd2", [("reg", reg64((0x182280000, 0x18000)))]),
        node("atc-phy1", [("reg", reg64((0xaa800000, 0x4000), (0xab000000, 0x2c000)))]),
        node("atc-phy2", [("reg", reg64((0x183000000, 0x2c000)))]),
        node("acio1", [("reg", reg64((0xa8000000, 0x4000)))]),
    ])
    return node("device-tree", [("compatible", b"K114sAP\0MacBookPro\0"), ("#address-cells", u32(2)),
                                ("#size-cells", u32(2)), ("serial-number", b"SECRETSERIAL0001\0")], [arm_io])


def run(fn, *args):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        rc = fn(*args)
    return rc, out.getvalue()


class Adt(unittest.TestCase):
    def write(self, blob):
        f = tempfile.NamedTemporaryFile(delete=False)
        f.write(blob)
        f.close()
        self.addCleanup(os.unlink, f.name)
        return f.name

    def test_matching_adt(self):
        rc, out = run(probe.probe_adt, self.write(adt()))
        self.assertEqual(rc, 0, out)
        self.assertIn("ADT target: K114sAP", out)
        self.assertIn("ok       0x28a188000 is reg[0]", out)
        self.assertIn("ok       0x28a184000 is reg[1]", out)
        self.assertIn("ok       0x2aa280000 is reg[0]", out)
        self.assertIn("ok       0x2ab000000 is reg[1]", out)       # the core block need not be reg[0]
        self.assertIn("ok       0x382280000 is reg[0]", out)
        self.assertIn("ok       hpm1 on nub-spmi-a0 at 0x0a", out)
        self.assertIn("ok       hpm2 on nub-spmi-a1 at 0x0c", out)
        self.assertIn("nub-spmi-a0/hpm5: SPMI address 0x08, port-type [17], features-supported [3]", out)
        self.assertIn("present in the ADT: usb-drd1 usb-drd2 atc-phy1 atc-phy2 acio1", out)
        self.assertIn("every USB-C value of the K114s tree matches", out)
        self.assertNotIn("SECRETSERIAL", out)

    def test_differences_are_reported(self):
        rc, out = run(probe.probe_adt, self.write(adt(spmi_a0_regs=((0x8a188000, 0x4000),), hpm1_addr=0x0b,
                                                     with_hpm5=False)))
        self.assertEqual(rc, 1, out)
        self.assertIn("MISMATCH 0x28a184000 is not a reg entry", out)
        self.assertIn("MISMATCH hpm1 is on nub-spmi-a0 at 0x0b, the tree expects nub-spmi-a0 at 0x0a", out)
        self.assertIn("MISMATCH hpm5 is not in the ADT", out)
        self.assertIn("DIFFERENCES above", out)

    def test_names_lists_no_values(self):
        rc, out = run(probe.probe_adt, self.write(adt()), "/")
        self.assertEqual(rc, 0, out)
        self.assertIn("serial-number", out)
        self.assertNotIn("SECRETSERIAL", out)

    def test_garbage_is_refused(self):
        with self.assertRaises(ValueError):
            probe.parse_adt(b"\xff" * 64)


class Regs(unittest.TestCase):
    def controller(self, root, name, mode, status, power, data):
        os.makedirs(os.path.join(root, name))
        buf = bytearray(0x80)
        buf[0x03:0x07] = mode
        buf[0x1a:0x1e] = struct.pack("<I", status)
        buf[0x3f:0x41] = struct.pack("<H", power)
        buf[0x5f:0x63] = struct.pack("<I", data)
        with open(os.path.join(root, name, "regs"), "wb") as f:
            f.write(buf)

    def test_decoding(self):
        with tempfile.TemporaryDirectory() as root:
            self.controller(root, "1-0a", b"APP ", 0, 0, 0)
            # plug, connected no Ra, source, host; USB2 + USB3 host connection
            self.controller(root, "2-0c", b"APP ", 0x1 | (6 << 1) | (1 << 5) | (1 << 6), 0x1, 0x1 | (1 << 4) | (1 << 5))
            rc, out = run(probe.probe_regs, root)
        self.assertEqual(rc, 0, out)
        idle, host = out.split("2-0c:")
        self.assertIn("NO plug", idle)
        self.assertIn("the controller sees no plug", idle)
        self.assertIn("plug present; connection state 6 (connected, no Ra)", host)
        self.assertIn("data role host (DFP)", host)
        self.assertIn("data connection; USB2; USB3; this port is the USB host on the link", host)
        self.assertIn("xHCI must be up", host)

    def test_verdicts(self):
        self.assertIn("not its application firmware", probe.verdict(b"BOOT", 1, 0))
        self.assertIn("charger", probe.verdict(b"APP ", 1, 1))
        self.assertIn("host-only port stays off", probe.verdict(b"APP ", 1, (1 << 4) | (1 << 7)))

    def test_no_debugfs(self):
        with tempfile.TemporaryDirectory() as root:
            rc, out = run(probe.probe_regs, root)
        self.assertEqual(rc, 2)
        self.assertIn("not root", out)


if __name__ == "__main__":
    unittest.main()
