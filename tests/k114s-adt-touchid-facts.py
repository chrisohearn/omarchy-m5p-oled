#!/usr/bin/python3 -I
# SPDX-License-Identifier: MIT
"""k114s-adt-touchid-facts.py: does dts/t6050-k114s-touchid.dtsi agree with this Mac's Apple device tree (ADT)?

    sudo python3 -I tests/k114s-adt-touchid-facts.py TREE.dtb [--adt FILE]

TREE.dtb is a K114s tree compiled with K114S_R3_TOUCHID (tests/test-touchid-dtb.sh builds one). Every
register, interrupt, pin and frequency the fragment puts into the tree is read back from it and compared
with the ADT, read from the "adt" MTD partition (root only) or from --adt FILE. Read only. Only addresses,
interrupt numbers, pin numbers and the sensor generation id are printed: no calibration, key, serial or
identifier is read or shown.

Exit 0: every fact holds. Exit 1: one does not. Exit 2: ADT or tree unreadable.
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name, fn):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, fn))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


sf = _load("soundfacts", "k114s-adt-sound-facts.py")
pf = _load("parityfacts", "k114s-adt-parity-facts.py")


def one(fdt, suffix):
    hit = [p for p in fdt.nodes if p.endswith(suffix)]
    return fdt.nodes[hit[0]] if len(hit) == 1 else None


def main():
    args = sys.argv[1:]
    adt_file = None
    if "--adt" in args:
        i = args.index("--adt")
        adt_file = args[i + 1]
        del args[i:i + 2]
    if len(args) != 1:
        print(__doc__)
        return 2
    try:
        t = sf.Tree(sf.load(adt_file))
        fdt = pf.Fdt(open(args[0], "rb").read())
        bad = check(t, fdt)
    except (sf.AdtError, OSError, ValueError, IndexError, KeyError, TypeError) as e:
        # a missing node or property in the ADT or the tree is "unreadable", not a crash
        print(f"k114s-adt-touchid-facts: unreadable: {type(e).__name__} {e}", file=sys.stderr)
        return 2
    if bad is None:
        return 1
    print("k114s-adt-touchid-facts:", "FAILED" if bad else "every fact holds")
    return 1 if bad else 0


def check(t, fdt):
    """Compare ADT t with tree fdt; returns the number of failed facts, or None if the tree lacks a node."""
    cells = pf.Fdt.cells
    bad = 0

    def fact(what, expected, found):
        nonlocal bad
        ok = expected == found
        bad += not ok
        print(("ok   " if ok else "FAIL ") + what + (f": {found}" if ok else f": ADT says {expected}, tree has {found}"))

    # the tree side is addressed as (hi, lo, size-hi, size-lo) cells
    def reg(node, i=0):
        c = cells(node["reg"])
        return (c[4 * i] << 32 | c[4 * i + 1], c[4 * i + 2] << 32 | c[4 * i + 3])

    spi = one(fdt, "spi@505108000")
    mesa = one(fdt, "spi@505108000/fingerprint@0")
    nub = one(fdt, "pinctrl@2881e4000")
    sep = one(fdt, "sep@502600000")
    mbox = one(fdt, "mailbox@502608000")
    dart = one(fdt, "iommu@500b80000")
    if None in (spi, mesa, nub, sep, mbox, dart):
        print("FAIL the tree lacks spi2, the sensor, nub-gpio0, sep, its mailbox or its dart (compiled without K114S_R3_TOUCHID?)")
        return None
    fact("spi2 window", (t.addr("arm-io/spi2"), t.size("arm-io/spi2")), reg(spi))
    fact("spi2 interrupt", t.irq("arm-io/spi2")[1], cells(spi["interrupts"])[2])
    # ADT-only checks of a constant the fragment relies on (the tree carries no copy of these)
    fact("spi2 clock-ids (the 24 MHz reference, no clock driver)", 451, sf.u32s(t.prop("arm-io/spi2", "clock-ids"))[0])
    fact("sensor generation id (Mesa V3)", 0x3356, sf.u32s(t.prop("arm-io/spi2/mesa", "sensor-id"))[0])
    fact("sensor SPI frequency", sf.u32s(t.prop("arm-io/spi2/mesa", "spi-frequency"))[0],
         cells(mesa["spi-max-frequency"])[0])
    # tree-only: the ADT's function-spi_cs0 is a null gpio, so chip select 0 is the controller's own and not read here
    fact("sensor chip select 0", 0, cells(mesa["reg"])[0])
    ctrl, pin = t.function_gpio("arm-io/spi2/mesa", "function-mesa_pwr")
    fact("sensor power in the ADT: bank and pin", ("nub-gpio0", 21), (ctrl, pin))
    fact("sensor power: ADT pin equals tree pin", pin, cells(mesa["enable-gpios"])[1])
    fact("nub-gpio0 window", (t.addr("arm-io/nub-gpio0"), t.size("arm-io/nub-gpio0")), reg(nub))
    fact("nub-gpio0 pin count", sf.u32s(t.prop("arm-io/nub-gpio0", "#gpio-pins"))[0], cells(nub["apple,npins"])[0])
    bank, dr = t.irq("arm-io/spi2/mesa")
    fact("sensor data ready in the ADT: bank and pin", ("gpio0", 138), (bank, dr))
    fact("sensor data ready: ADT pin equals tree pin", dr, cells(mesa["interrupts"])[0])
    fact("sep windows", (t.addr("arm-io/sep"), t.size("arm-io/sep"), t.addr("arm-io/sep", 1), t.size("arm-io/sep", 1)),
         reg(sep, 0) + reg(sep, 1))
    mb = sorted(sf.u32s(t.prop("arm-io/sep", "interrupts")))
    fact("sep mailbox interrupts (set)", mb, sorted(cells(mbox["interrupts"])[4 * i + 2] for i in range(4)))
    fact("sep mailbox at sep + 0x8000", t.addr("arm-io/sep") + 0x8000, reg(mbox)[0])
    fact("sep clock-ids", sf.u32s(t.prop("arm-io/sep", "clock-ids"))[0], cells(sep["clocks"])[1])
    fact("dart-sep window", (t.addr("arm-io/dart-sep"), t.size("arm-io/dart-sep")), reg(dart))
    fact("dart-sep interrupt", sf.u32s(t.prop("arm-io/dart-sep", "interrupts"))[0], cells(dart["interrupts"])[2])
    vb = sf.u32s(t.prop("arm-io/dart-sep", "vm-base-0"))
    vs = sf.u32s(t.prop("arm-io/dart-sep", "vm-size-0"))
    dma = [x for x in (cells(dart["apple,dma-range"]) if "apple,dma-range" in dart else [])]
    fact("dart-sep DMA window (base, size)", (vb[1] << 32 | vb[0], vs[0]), (dma[0] << 32 | dma[1], dma[2] << 32 | dma[3]) if len(dma) >= 4 else None)
    return bad


if __name__ == "__main__":
    sys.exit(main())
