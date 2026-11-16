#!/usr/bin/env python3
"""List the K114s ADT display-audio nodes (dp-audio0..N) against the merged T602x pattern.

    sudo python3 tests/k114s-adt-dp-audio.py [--adt FILE]

Read-only. Prints node names, compatible strings, register windows, numeric gate, DMA and interrupt cells
and property NAMES of the dp-audio, dcpext, admac-disp* and sio nodes. No serial numbers or MACs.
Reuses the parser in tests/k114s-adt-display-facts.py.
"""
import importlib.util
import os
import sys

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("facts", os.path.join(here, "k114s-adt-display-facts.py"))
facts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(facts)


def walk(node, trail):
    yield trail + [node]
    for c in node.children:
        yield from walk(c, trail + [node])


def main(argv):
    src = argv[1] if len(argv) > 1 and argv[0] == "--adt" else facts.find_adt_device()
    if src is None:
        print("no ADT source; give --adt FILE")
        return 2
    try:
        blob = open(src, "rb").read()
    except PermissionError:
        print("run with sudo")
        return 2
    root, _ = facts.parse_adt(blob)
    for trail in walk(root, []):
        n = trail[-1]
        if not (n.name.startswith(("dp-audio", "dcpext", "admac-disp", "sio", "dart-sio"))):
            continue
        full = trail
        path = "/".join(x.name for x in full[1:])
        print("%s" % path)
        print("  compatible: %s" % facts.text(n.props.get("compatible")))
        reg = facts.get_reg(full, 0) if "reg" in n.props and len(full) > 1 else None
        print("  reg[0]: %s" % (("0x%x size 0x%x" % reg) if reg else "none"))
        for key in ("audio", "dma-channels", "dma-parent", "power-gates", "clock-gates", "interrupts"):
            if key in n.props and len(n.props[key]) % 4 == 0:
                print("  %s: %s" % (key, facts.u32s(n.props[key])))
        print("  props: %s" % ", ".join(sorted(k for k in n.props)))
        print("  children: %s" % ", ".join(c.name for c in n.children))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
