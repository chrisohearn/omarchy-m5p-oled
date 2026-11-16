#!/usr/bin/env python3
"""List the external-display (dcpext / dispext / DP) facts of the running K114s's Apple device tree.

    sudo python3 -I tests/hardware/k114s-external-display-adt.py [--adt FILE]

Read-only; same parser and same disclosure rules as tests/k114s-adt-display-facts.py (register
addresses, phandle targets, node names, property names; no serials, MACs or other values).
Issue #23: the data to compare against the K116s (aurora-silicon/linux) external-display tree.
"""
import importlib.util
import os
import sys

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("adtf", os.path.join(here, "..", "k114s-adt-display-facts.py"))
adtf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adtf)


def walk(node, trail=None):
    """Yield (path, trail): the path leaves out the root's own name; the trail is the node list from the root."""
    trail = (trail or []) + [node]
    yield "/" + "/".join(n.name for n in trail[1:]), trail
    for c in node.children:
        yield from walk(c, trail)


def main(argv):
    if argv[:1] == ["--adt"] and len(argv) == 2:
        src = argv[1]
    elif not argv:
        src = adtf.find_adt_device()
    else:
        print(__doc__)
        return 2
    if src is None:
        print('no MTD device named "adt" in /proc/mtd; give the ADT with --adt FILE')
        return 2
    try:
        blob = open(src, "rb").read()
    except PermissionError:
        print("cannot read %s: run this with sudo" % src)
        return 2
    except OSError as e:
        print("cannot read %s: %s" % (src, e.strerror))
        return 2
    root, _ = adtf.parse_adt(blob)
    nodes = list(walk(root))
    by_phandle = {}
    for path, trail in nodes:
        v = trail[-1].props.get("AAPL,phandle")
        if v and len(v) >= 4:
            by_phandle[adtf.u32s(v)[0]] = path

    def target(n, prop):
        v = n.props.get(prop)
        return by_phandle.get(adtf.u32s(v)[0], "?") if v and len(v) >= 4 else "absent"

    def reg(trail, k=0):
        pair = adtf.get_reg(trail, k) if trail and len(trail) > 1 else None
        return adtf.hexpair(pair) if pair else "none"

    arm = adtf.find(root, "/arm-io")
    if not arm:
        print("no /arm-io node in this ADT")
        return 1
    for i in range(4):
        trail = adtf.find(root, "/arm-io/dcpext%d" % i)
        if not trail:
            print("dcpext%d: missing" % i)
            continue
        d = trail[-1]
        print("dcpext%d reg0 %s  role=%s  dp-switch-parent=%s  ufp-port=%s ufp-endpoint=%s  audio=%s" % (
            i, reg(trail), adtf.text(d.props.get("role")), target(d, "dp-switch-parent"),
            adtf.cells_of(d, "dp-switch-ufp-port", None), adtf.cells_of(d, "dp-switch-ufp-endpoint", None),
            target(d, "audio")))
        nub = d.child("iop-dcpext%d-nub" % i)
        if nub:
            print("   nub image %s running=%s" % (adtf.text(nub.props.get("uuid")), adtf.cells_of(nub, "running", None)))
        else:
            print("   no nub")
        t = adtf.find(root, "/arm-io/dispext%d" % i)
        if t:
            print("   dispext%d regs: %s" % (i, "; ".join(reg(t, k) for k in range(5))))
        for nm in ("dart-dcpext%d" % i, "dart-dispext%d" % i):
            t = adtf.find(root, "/arm-io/" + nm)
            if t:
                print("   %s reg0 %s" % (nm, reg(t)))
    print("-- nodes named atc*, dptx*, dpxbar*, dp-switch*, dpphy*, dp-phy* or usb-drd*")
    for path, trail in nodes:
        name = trail[-1].name
        if name.startswith(("atc", "dptx", "dpxbar", "dp-switch", "dpphy", "dp-phy", "usb-drd")):
            print("  %s  reg0 %s" % (path, reg(trail)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
