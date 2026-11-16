#!/usr/bin/python3 -I
# SPDX-License-Identifier: MIT
"""k114s-adt-kiwi-facts.py: does this Mac's Apple device tree (ADT) give the touchscreen the same pins as the K114c?

    sudo python3 -I tests/k114s-adt-kiwi-facts.py [--adt FILE]
    python3 -I tests/k114s-adt-kiwi-facts.py --self-test

Issue #48. aurora-silicon/linux #1605 enables the "kiwi" touchscreen on the K114c with: 24 MHz clock pad
on NUB GPIO 22, display-sync pad on AP GPIO 11, reset on NUB GPIO 25 and power on NUB GPIO 26. This reads
those four lines, the SMC power reference and the image tag from the K114s ADT ("adt" MTD partition, root
only, read-only) and compares them. It prints pin numbers and fourcc tags only. It never reads the
fdr-classes calibration property or any firmware bytes.

Exit 0: every fact holds. Exit 1: at least one does not. Exit 2: ADT unreadable.
"""
import argparse
import importlib.util
import io
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("soundfacts", os.path.join(HERE, "k114s-adt-sound-facts.py"))
sf = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sf)

KIWI = "arm-io/dockchannel-mtp/mtp-transport/kiwi"
GPIO = struct.unpack("<I", b"OIPG")[0]

# function-* property -> (expected controller node, expected pin) from linux #1605 (K114c)
LINES = (("function-clock_24MHz_enable", "nub-gpio0", 22, "24 MHz clock pad"),
         ("function-display_sync", "gpio0", 11, "display-sync pad"),
         ("function-power", "nub-gpio0", 26, "touch power enable"),
         ("function-reset", "nub-gpio0", 25, "touch reset"))


def facts(t):
    n = t.node(KIWI)
    if n is None:
        return [("kiwi", "the ADT has a kiwi interface under the MTP transport", True, False)]
    res = [("kiwi", "the ADT has a kiwi interface under the MTP transport", True, True)]
    for prop, ctrl, pin, what in LINES:
        c, p = t.function_gpio(KIWI, prop)
        res.append(("kiwi", f"{what} controller", ctrl, c))
        res.append(("kiwi", f"{what} pin", pin, p))
    w = sf.u32s(n["props"].get("function-power_refcnt", b""))
    res.append(("kiwi", "SMC power reference key", "rCIO", struct.pack(">I", w[2]).decode("ascii", "replace") if len(w) > 2 else None))
    res.append(("kiwi", "firmware image tag", "fsat", sf.text(n["props"].get("image-tag"))))
    res.append(("kiwi", "firmware bootloader", "CBOR", sf.text(n["props"].get("bootloader-type"))))
    return res


def report(results, out=sys.stdout):
    bad = 0
    for _g, what, expected, found in results:
        if expected == found:
            print(f"  ok    {what}: {expected}", file=out)
        else:
            bad += 1
            print(f"  FAIL  {what}: expected {expected}, the ADT says {found}", file=out)
    print(f"kiwi facts: {len(results) - bad} hold, {bad} do not", file=out)
    return bad


def _made_up(reset_pin=25):
    w = lambda *a: struct.pack("<%dI" % len(a), *a)
    ph = lambda n: ("AAPL,phandle", w(n))
    gp = lambda c, pin, f: w(c, GPIO, pin, f)
    kiwi = sf._node("kiwi", [("function-clock_24MHz_enable", gp(1, 22, 0x2000101)),
                             ("function-display_sync", gp(2, 11, 0x2000101)),
                             ("function-power", gp(1, 26, 0x101)),
                             ("function-reset", gp(1, reset_pin, 0x10001)),
                             ("function-power_refcnt", w(3, struct.unpack("<I", b"4WKp")[0], 0x7243494F, 0x20000)),
                             ("image-tag", b"fsat\0"), ("bootloader-type", b"CBOR\0"),
                             ("fdr-classes", b"MADE-UP-CALIBRATION\0")])
    tr = sf._node("mtp-transport", [], [kiwi])
    dc = sf._node("dockchannel-mtp", [], [tr])
    io_ = sf._node("arm-io", [("ranges", w(0, 0, 0, 0, 0, 0))],
                   [dc, sf._node("nub-gpio0", [ph(1)]), sf._node("gpio0", [ph(2)]), sf._node("smc-pmu", [ph(3)])])
    return sf.parse(sf._node("device-tree", [], [io_]))[0]


def self_test():
    ok = True

    def check(what, cond):
        nonlocal ok
        print(("ok   " if cond else "FAIL ") + what)
        ok = ok and cond

    good = facts(sf.Tree(_made_up()))
    sink = io.StringIO()
    check("a made-up ADT with the K114c pins passes every fact", report(good, sink) == 0)
    bad = facts(sf.Tree(_made_up(reset_pin=24)))
    failed = [w for _, w, e, f in bad if e != f]
    check("a reset on another pin fails exactly that fact", failed == ["touch reset pin"])
    check("the calibration property is not in the output", "CALIBRATION" not in sink.getvalue())
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--adt", help='an ADT file instead of the "adt" MTD partition')
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        return self_test()
    try:
        t = sf.Tree(sf.load(a.adt))
    except (sf.AdtError, struct.error) as e:
        print(f"k114s-adt-kiwi-facts: {e}", file=sys.stderr)
        return 2
    return 1 if report(facts(t)) else 0


if __name__ == "__main__":
    sys.exit(main())
