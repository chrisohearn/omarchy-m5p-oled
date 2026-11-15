#!/usr/bin/env python3
"""Replica test of tests/k114s-adt-parity-facts.py.

    python3 tests/test-adt-parity-facts.py DIR        (tests/test-parity-dtb.sh builds DIR)

Builds a made-up Apple device tree (ADT) in the m1n1 wire format from the K116s values the
fragments are ported from (all public in aurora-silicon/linux #1648, #1719 and #1856), runs the
checker on the trees in DIR, and proves it also fails: every neg-GROUP-*.dtb tree has one wrong
value and must produce a FAIL in GROUP. The made-up ADT carries a serial number and a MAC
address, and the test fails if the checker prints either. No Apple data is used: this proves the
checker's reading and comparisons, not anything about a real machine.
"""
import glob
import importlib.util
import io
import os
import struct
import sys
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("parity", os.path.join(HERE, "k114s-adt-parity-facts.py"))
parity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(parity)
sf = parity.sf

SERIAL, MAC = b"ZZTESTSERIAL0\0", bytes([2, 0x11, 0x22, 0x33, 0x44, 0x55])
node, prop = sf._node, sf._prop


def cells(*v):
    return struct.pack("<%dI" % len(v), *v)


def regs(*pairs):
    return b"".join(struct.pack("<QQ", a, s) for a, s in pairs)


def ph(n):
    return ("AAPL,phandle", cells(n))


def device(name, ident, parent, offset=0):
    e = bytearray(48)
    struct.pack_into("<H", e, 4, parent)
    struct.pack_into("<H", e, 16, offset)
    struct.pack_into("<H", e, 26, ident)
    e[32:32 + len(name)] = name.encode()
    return bytes(e)


def tunable(*rows):
    return b"".join(struct.pack("<IIIIII", o, 4, m, 0, v, 0) for o, m, v in rows)


def build(avd_irq=2417, pin=81, sd_irq=1531, fab_offset=0x1b0, window=0x1404000, no_als=False):
    pci_cfg = [(0x1C_B000_0000, 0x1000_0000)] + [(0x2_1400_0000, 0x4000), (0, 0), (0x2_1702_0000, 0x4000)] + [(0, 0)] * 12
    pci_cfg += [(0x2_1002_8000, 0x8000), (0, 0), (0x2_1701_0000, 0x4000), (0x2_1002_4000, 0x4000), (0, 0), (0, 0),
                (0x2_1102_8000, 0x8000), (0, 0), (0x2_1701_4000, 0x4000), (0x2_1102_4000, 0x4000)]
    ranges = struct.pack("<18I", 0, 0, 0, 2, 0xC000_0000, 3, 0x2000_0000, 0x20, 0x2000_0000, 0x22, 0xE000_0000, 1,
                         0xB000_0000, 0x1C, 0xB000_0000, 0x1C, 0x1000_0000, 0)
    devices = b"".join([device("FAB1_SOC", 0x181, 0x17F, fab_offset), device("AVD_SYS", 0x186, 0x181, 0x1D8),
                        device("AVD_SOC_DART", 0x255, 0x186), device("AVD_SYS_V", 0x258, 0x186)])
    nub = [node("als", [("device_type", b"als\0"), ("harmony-db-version", cells(3))])] if not no_als else []
    nub += [node("accel"), node("gyro")]
    bridge1 = node("pci-bridge1", [
        ("apcie-port", cells(1)), ("function-perst", cells(0x1CC, sf.GPIO_FOURCC, pin, 0)),
        ("apcie-config-tunables", tunable((0x140, 1, 1), (0x144, 0xFFFFFF, 0x253770), (0x8A8, 1, 1), (0x8AC, 1, 1))),
        ("pcie-rc-tunables", tunable((0x78, 0x7000, 0), (0x194, 2, 2), (0xB80, 0x7F3F3F, 0x7F1E1E), (0xB88, 0x7F3F3F, 0x7F1E1E))),
        ("pcie-rc-gen3-shadow-tunables", tunable((0x154, 0xF0F0F0F, 0x5050505), (0x890, 0x3000000, 0), (0x8A8, 0xFFFF0F, 1))),
        ("pcie-rc-gen4-shadow-tunables", tunable((0x178, 0xFFFF, 0x5555), (0x890, 0x3000000, 0x1000000), (0x8A8, 0xFFFF0F, 1))),
        ("pcie-rc-gen5-shadow-tunables", tunable((0x1AC, 0xFFFF, 0x5555), (0x890, 0x3000000, 0x2000000), (0x8A8, 0xFFFF0F, 1))),
    ], [node("pcie-sdreader", [
        ("card-detect-polarity", cells(1)), ("write-protect-polarity", cells(1)), ("gl9755-ssc_enable", cells(1)),
        ("function-sd_pwr_en", cells(0x291, 0x704B5738, 0x7063494F, 0, 0x190000)),
        ("expected-link-speed", cells(2)), ("initial-link-speed", cells(1))])])
    return node("device-tree", [("serial-number", SERIAL)], [
        node("chosen", [("board-id", cells(0x14))]),
        node("arm-io", [("#address-cells", cells(2)), ("#size-cells", cells(2)), ("ranges", ranges)], [
            node("avd0", [("reg", regs((0x21_0800_0000, window))), ("interrupts", cells(avd_irq, 2418)),
                          ("avd-version", cells(4)), ("avd-ads-keytype-version", cells(3)),
                          ("compatible", b"avd,t8103\0"), ("power-gates", cells(0x258))]),
            node("dart-avd0", [("reg", regs((0x21_0902_0000, 0x20000))), ("interrupts", cells(2424)),
                               ("sid", cells(0, 1, 2)), ("power-gates", cells(0x255))]),
            node("pmgr", [("reg", regs(*[(0, 0)] * 46 + [(0x21_8060_0000, 0x1E8000)])), ("devices", devices)]),
            node("gpio0", [("reg", regs((0x9C00_0000, 0x4_0000))), ("#gpio-pins", cells(221))]),
            node("apcie0", [("reg", regs(*pci_cfg)), ("interrupts", cells(1523, sd_irq, 1539))], [bridge1]),
            node("dart-apcie1", [("reg", regs((0x2_1100_0000, 0x20000))), ("interrupts", cells(1532)),
                                 ("manual-availability", cells(1)), ("sid", cells(0x10, 0x11, 0x12))]),
            node("aop", [("reg", regs((0x9060_0000, 0x88000), (0x9065_0000, 0x4000), (0x90C0_0000, 0x2F_0000))),
                         ("interrupts", cells(579, 578, 581, 580))], [node("iop-aop-nub", [], nub)]),
            node("aop-exclave-mailbox", [("reg", regs((0x2_D067_C000, 0x4000)))]),
            node("dart-aop", [("reg", regs((0x90FC_0000, 0xC000))), ("interrupts", cells(616)),
                              ("sid", cells(0, 0x10, 3, 8, 0xA)), ("exclave-sid", cells(1, 0xB, 9))]),
            node("wlan", [("local-mac-address", MAC)]),
        ])])


def check(adt_bytes, trees, with_audio=False):
    import tempfile
    with tempfile.NamedTemporaryFile(suffix=".adt") as f:
        f.write(adt_bytes)
        f.flush()
        buf = io.StringIO()
        with redirect_stdout(buf):
            adt = sf.Tree(sf.load(f.name))
            bad = parity.run(adt, trees, with_audio)
    return bad, buf.getvalue()


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    d = sys.argv[1]
    path = lambda n: os.path.join(d, n + ".dtb")
    fails = []

    def expect(name, cond, text=""):
        print("%s  %s" % ("ok  " if cond else "FAIL", name))
        if not cond:
            fails.append(name)
            print(text)

    good = [("avd", path("avd")), ("sd", path("sd")), ("aop", path("aop-sensors"))]
    bad, text = check(build(), good)
    expect("matching ADT: every fact of the three fragments holds", bad == 0 and text.count("  ok ") >= 60, text)
    expect("matching ADT: the K114s' lid angle gap is reported, not failed", "las (lid angle): ABSENT" in text, text)
    for secret in (SERIAL.rstrip(b"\0").decode(), "02:11:22", "021122334455"):
        expect("no test serial or MAC address in the output (%s)" % secret[:8], secret.lower() not in text.lower(), text)

    bad, text = check(build(), [("sd", path("sd-with-sound"))])
    expect("SD tree built beside the sound fragment keeps pins 80 and 81 exposed and 112 reserved", bad == 0, text)
    bad, text = check(build(), [("aop", path("aop-with-audio"))], with_audio=True)
    expect("AOP with audio left on but the speaker channels in place: refused", bad == 1 and "speaker DMA channel" in text, text)

    # a fragment enables the nodes it names and nothing else
    base = parity.Fdt(open(path("r1"), "rb").read())
    named = {"avd": ["avd@2309080000", "iommu@2309020000", "power-controller@1b0", "power-controller@1d8", "power-management@2380600000"],
             "sd": ["iommu@411000000", "mmc@0,0", "pci@1,0"],
             "aop-sensors": ["als", "aop@290c00000", "iommu@290fc0000", "las", "mailbox@290608000", "mailbox@2d067c000"]}
    for n, want in named.items():
        t = parity.Fdt(open(path(n), "rb").read())
        got = sorted(x.rsplit("/", 1)[-1] for x in t.nodes if t.enabled(x) and not (x in base.nodes and base.enabled(x)))
        expect("%s enables exactly its named nodes" % n, got == want, "%s" % got)

    # the same trees against ADTs that differ in one value
    for what, kw, group, pat in (
            ("avd0 interrupt", dict(avd_irq=2420), "avd", "avd0 interrupts"),
            ("avd0 window", dict(window=0x1000000), "avd", "avd0 window"),
            ("FAB1_SOC offset", dict(fab_offset=0x1b8), "avd", "FAB1_SOC power state offset"),
            ("PERST# pin", dict(pin=83), "sd", "PERST# pin"),
            ("port 1 interrupt", dict(sd_irq=1533), "sd", "host interrupts"),
            ("no als node", dict(no_als=True), "aop", "ADT has an als service node")):
        tree = {"avd": "avd", "sd": "sd", "aop": "aop-sensors"}[group]
        bad, text = check(build(**kw), [(group, path(tree))])
        expect("ADT with another %s: FAIL, not a pass" % what, bad >= 1 and pat in text and "  FAIL  " in text, text)

    # trees with one wrong value each (built by tests/test-parity-dtb.sh)
    negatives = sorted(glob.glob(os.path.join(d, "neg-*.dtb")))
    expect("negative trees were built", len(negatives) >= 10, str(negatives))
    for f in negatives:
        group = os.path.basename(f).split("-")[1]
        bad, text = check(build(), [(group, f)])
        expect("%s: the checker fails it" % os.path.basename(f)[:-4], bad >= 1 and "  FAIL  " in text, text)

    print("parity checker replica test:", "FAILED" if fails else "passed")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
