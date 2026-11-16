#!/usr/bin/env python3
"""List the K114s ADT display-audio nodes (dp-audio0..N) against the merged J714s (T6050) pattern.

    sudo python3 tests/k114s-adt-dp-audio.py [--adt FILE]

Read-only. Prints node names, compatible strings, register windows, numeric gate, DMA and interrupt cells
and property NAMES of the dp-audio, dcpext, admac-disp* and sio nodes. No serial numbers or MACs.
Reuses the parser in tests/k114s-adt-display-facts.py.
"""
import importlib.util
import os
import struct
import sys

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("facts", os.path.join(here, "k114s-adt-display-facts.py"))
facts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(facts)


USAGE = "usage: sudo python3 tests/k114s-adt-dp-audio.py [--adt FILE]"


def walk(node, trail):
    yield trail + [node]
    for c in node.children:
        yield from walk(c, trail + [node])


def main(argv):
    if argv and not (len(argv) == 2 and argv[0] == "--adt"):
        print(USAGE)
        return 2
    src = argv[1] if argv else facts.find_adt_device()
    if src is None:
        print("no ADT source; give --adt FILE")
        return 2
    try:
        blob = open(src, "rb").read()
    except PermissionError:
        print("run with sudo")
        return 2
    try:
        root, _ = facts.parse_adt(blob)
    except (ValueError, struct.error) as err:
        print("could not parse the ADT (%s)" % err)
        return 1
    by_phandle = {facts.u32s(t[-1].props["AAPL,phandle"])[0]: t[-1].name
                  for t in walk(root, []) if len(t[-1].props.get("AAPL,phandle", b"")) == 4}
    for trail in walk(root, []):
        n = trail[-1]
        if not (n.name.startswith(("dp-audio", "dcpext", "admac-disp", "sio", "dart-sio"))):
            continue
        path = "/".join(x.name for x in trail[1:])
        print("%s" % path)
        print("  compatible: %s" % facts.text(n.props.get("compatible")))
        reg = facts.get_reg(trail, 0) if "reg" in n.props and len(trail) > 1 else None
        print("  reg[0]: %s" % (("0x%x size 0x%x" % reg) if reg else "none"))
        dp = n.props.get("dma-parent")
        if dp is not None:
            # a name string on some ADTs, a phandle on others
            if len(dp) == 4:
                target = by_phandle.get(facts.u32s(dp)[0])
                print("  dma-parent: %s" % (target or "phandle %d" % facts.u32s(dp)[0]))
            else:
                print("  dma-parent: %s" % facts.text(dp))
        for key in ("audio", "dma-channels", "power-gates", "clock-gates", "interrupts"):
            if key in n.props and len(n.props[key]) % 4 == 0:
                print("  %s: %s" % (key, facts.u32s(n.props[key])))
        print("  props: %s" % ", ".join(sorted(k for k in n.props)))
        print("  children: %s" % ", ".join(c.name for c in n.children))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
