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


def walk(node, path=""):
    yield path + "/" + node.name if path or node.name else "/", node
    for c in node.children:
        yield from walk(c, path + "/" + node.name if node.name else path)


def main():
    src = sys.argv[2] if len(sys.argv) > 2 and sys.argv[1] == "--adt" else adtf.find_adt_device()
    blob = open(src, "rb").read()
    root, _ = adtf.parse_adt(blob)
    by_phandle = {}
    for path, n in walk(root):
        v = n.props.get("AAPL,phandle")
        if v:
            by_phandle[adtf.u32s(v)[0]] = path
    def target(n, prop):
        v = n.props.get(prop)
        return by_phandle.get(adtf.u32s(v)[0], "?") if v and len(v) >= 4 else "absent"
    arm = adtf.find(root, "/arm-io")[-1]
    for i in range(4):
        d = arm.child("dcpext%d" % i)
        if not d:
            print("dcpext%d: missing" % i); continue
        trail = adtf.find(root, "/arm-io/dcpext%d" % i)
        print("dcpext%d reg0 %s  role=%s  dp-switch-parent=%s  ufp-port=%s ufp-endpoint=%s  audio=%s" % (
            i, adtf.hexpair(adtf.get_reg(trail, 0)), adtf.text(d.props.get("role")),
            target(d, "dp-switch-parent"),
            adtf.cells_of(d, "dp-switch-ufp-port", None), adtf.cells_of(d, "dp-switch-ufp-endpoint", None),
            target(d, "audio")))
        nub = d.child("iop-dcpext%d-nub" % i)
        print("   nub image %s running=%s" % (adtf.text(nub.props.get("uuid")), adtf.cells_of(nub, "running", None)))
        e = arm.child("dispext%d" % i)
        if e:
            t = adtf.find(root, "/arm-io/dispext%d" % i)
            print("   dispext%d regs: %s" % (i, "; ".join(adtf.hexpair(adtf.get_reg(t, k)) for k in range(5))))
        for nm in ("dart-dcpext%d" % i, "dart-dispext%d" % i):
            dn = arm.child(nm)
            if dn:
                print("   %s reg0 %s" % (nm, adtf.hexpair(adtf.get_reg(adtf.find(root, "/arm-io/" + nm), 0))))
    print("-- nodes whose name mentions atc, dp, dptx, phy, usb-drd, or dp-switch/dpxbar")
    for path, n in walk(root):
        low = n.name.lower()
        if any(k in low for k in ("atc", "dptx", "dpxbar", "dp-switch", "dpphy", "dp-phy", "usb-drd")) and n.name:
            try:
                r = adtf.get_reg(adtf.find(root, path), 0)
            except Exception:
                r = None
            print("  %s  reg0 %s" % (path, adtf.hexpair(r) if r else "none"))

if __name__ == "__main__":
    main()
