#!/usr/bin/env python3
"""Device tree lint for the K114s USB-C host ports.

    tests/lint-usb-dtb.py K114S.dtb [...] [--reference K116S.dtb]

Checks, for the left-front (ATC1) and right (ATC2) ports of every tree given:
  - the port controller, its bus, the PHY, its mailbox, dwc3 and both DARTs are enabled, and so
    is every power domain any of them needs (a disabled supplier keeps a driver from probing);
  - the connector graph is closed in both directions (controller <-> dwc3 for the USB2 pair and
    the role switch, controller <-> PHY for the SuperSpeed lanes and the Type-C mux);
  - the properties the drivers refuse to work without are there (usb-role-switch, mode-switch,
    orientation-switch, apple,guest-port-reserved, apple,port-index, four PHY power domains);
  - the port-controller buses and controllers carry no interrupt (the generation 4 SPMI driver
    refuses one; the controllers are polled) and at most two register windows;
  - the loader's aliases atcphy1/atcphy2 point at the two PHYs;
  - the left-back port (ATC0, the loader's debug port) is not described.
With --reference it also compares every one of those nodes, property by property, with the same
node of the reference tree (phandles resolved to node paths). Built from aurora-silicon/linux,
t6050-k116s.dtb is the tree whose USB-C ports Jens Axboe booted on a K116s.

Software check only: it says the description is complete and equal, not that a port works.
"""
import struct
import sys

SOC = "/soc@200000000"
PORTS = [
    # name, bus, controller, dwc3, phy, phy mailbox, DARTs, port index
    ("left-front", SOC + "/spmi@28a188000", "usb-pd@a", SOC + "/usb@2aa280000", SOC + "/phy@2ab000000",
     SOC + "/mailbox@2ab148000", (SOC + "/iommu@2aaf00000", SOC + "/iommu@2aaf80000"), 1),
    ("right", "/soc/spmi@28a1a8000", "usb-pd@c", SOC + "/usb@382280000", SOC + "/phy@383000000",
     SOC + "/mailbox@383148000", (SOC + "/iommu@382f00000", SOC + "/iommu@382f80000"), 2),
]
DEBUG_PORT = [SOC + "/spmi@28a188000/usb-pd@c", SOC + "/usb@2a2280000", SOC + "/phy@2a3000000"]
CELLS = {"power-domains": "#power-domain-cells", "phys": "#phy-cells", "iommus": "#iommu-cells",
         "mboxes": "#mbox-cells", "resets": "#reset-cells", "remote-endpoint": None}


def load(path):
    d = open(path, "rb").read()
    magic, _total, off_struct, off_strings = struct.unpack(">IIII", d[:16])
    if magic != 0xd00dfeed:
        raise ValueError("%s is not a device tree blob" % path)
    nodes, stack, p = {}, [], off_struct
    while True:
        tok = struct.unpack(">I", d[p:p + 4])[0]
        p += 4
        if tok == 1:
            e = d.index(b"\0", p)
            stack.append(d[p:e].decode())
            p = (e + 4) & ~3
            nodes["/" + "/".join(stack[1:])] = {}
        elif tok == 2:
            stack.pop()
        elif tok == 3:
            ln, no = struct.unpack(">II", d[p:p + 8])
            p += 8
            e = d.index(b"\0", off_strings + no)
            nodes["/" + "/".join(stack[1:])][d[off_strings + no:e].decode()] = d[p:p + ln]
            p = (p + ln + 3) & ~3
        elif tok == 9:
            break
    return nodes


def resolve(nodes):
    """Phandle-bearing properties as lists of (target path, argument cells); phandle dropped."""
    by_handle = {struct.unpack(">I", v["phandle"])[0]: k for k, v in nodes.items() if len(v.get("phandle", b"")) == 4}
    out = {}
    for path, props in nodes.items():
        o = {}
        for k, v in props.items():
            if k == "phandle":
                continue
            if k in CELLS and len(v) % 4 == 0:
                c, i, refs = list(struct.unpack(">%dI" % (len(v) // 4), v)), 0, []
                while i < len(c) and c[i] in by_handle:
                    tgt = by_handle[c[i]]
                    n = struct.unpack(">I", nodes[tgt][CELLS[k]])[0] if CELLS[k] and CELLS[k] in nodes[tgt] else 0
                    refs.append((tgt, tuple(c[i + 1:i + 1 + n])))
                    i += 1 + n
                if i == len(c):
                    v = refs
            o[k] = v
        out[path] = o
    return out


def enabled(tree, path):
    return path in tree and tree[path].get("status", b"okay\0") in (b"okay\0", b"ok\0")


def closure(tree, start):
    """Every node the start nodes need through a power domain, PHY, IOMMU, mailbox or reset."""
    seen, todo = set(), list(start)
    while todo:
        p = todo.pop()
        for k in ("power-domains", "phys", "iommus", "mboxes", "resets"):
            v = tree.get(p, {}).get(k)
            if isinstance(v, list):
                for tgt, _args in v:
                    if tgt not in seen:
                        seen.add(tgt)
                        todo.append(tgt)
    return seen


def lint(path, tree, ref):
    bad = []

    def need(cond, msg):
        if not cond:
            bad.append(msg)

    compat = tree.get("/", {}).get("compatible", b"").split(b"\0")[0].decode()
    need(compat == "apple,k114s", "root compatible is %s" % compat)
    compared = 0
    for name, bus, ctl, usb, phy, mbox, darts, index in PORTS:
        pd = bus + "/" + ctl
        con = pd + "/connector"
        before = len(bad)
        for n in (bus, usb, phy, mbox) + darts:
            need(enabled(tree, n), "%s: %s is missing or disabled" % (name, n))
        need(pd in tree and tree[pd].get("compatible") == b"apple,sn201202x\0", "%s: no %s" % (name, pd))
        if len(bad) > before:
            continue
        need("interrupts" not in tree[bus] and "interrupts-extended" not in tree[bus],
             "%s: the bus has an interrupt, which the generation 4 SPMI driver refuses" % name)
        need(len(tree[bus].get("reg", b"")) in (16, 32), "%s: the bus has %d register cells, expected 4 or 8"
             % (name, len(tree[bus].get("reg", b"")) // 4))
        need("interrupts" not in tree[pd] and "interrupts-extended" not in tree[pd],
             "%s: the port controller has interrupts; this bus is polled" % name)
        need(tree.get(con, {}).get("compatible") == b"usb-c-connector\0", "%s: no usb-c-connector" % name)
        # graph: connector port@0 <-> dwc3, connector port@1 <-> PHY
        for port, far, what in ((con + "/ports/port@0/endpoint", usb + "/port/endpoint", "USB2/role switch"),
                                (con + "/ports/port@1/endpoint", phy + "/port/endpoint", "SuperSpeed/mux")):
            a, b = tree.get(port, {}).get("remote-endpoint"), tree.get(far, {}).get("remote-endpoint")
            need(a == [(far, ())] and b == [(port, ())], "%s: %s graph is not closed (%s <-> %s)" % (name, what, port, far))
        u, ph = tree[usb], tree[phy]
        need(b"apple,t6050-dwc3\0" in u.get("compatible", b""), "%s: dwc3 compatible" % name)
        need("usb-role-switch" in u, "%s: dwc3 has no usb-role-switch" % name)
        need(isinstance(u.get("phys"), list) and len(u["phys"]) == 2 and all(t == phy for t, _ in u["phys"]),
             "%s: dwc3 does not take its two PHYs from %s" % (name, phy))
        need(isinstance(u.get("iommus"), list) and [t for t, _ in u["iommus"]] == list(darts),
             "%s: dwc3 iommus are not %s" % (name, " ".join(darts)))
        need(isinstance(u.get("resets"), list) and [t for t, _ in u["resets"]] == [phy],
             "%s: dwc3 reset is not the PHY's" % name)
        need(b"apple,t6050-combo-phy\0" in ph.get("compatible", b""), "%s: PHY compatible" % name)
        for p in ("mode-switch", "orientation-switch", "apple,guest-port-reserved"):
            need(p in ph, "%s: PHY has no %s" % (name, p))
        need(ph.get("apple,port-index") == struct.pack(">I", index), "%s: PHY apple,port-index is not %d" % (name, index))
        need(ph.get("mboxes") == [(mbox, ())], "%s: PHY mailbox is not %s" % (name, mbox))
        need(isinstance(ph.get("power-domains"), list) and len(ph["power-domains"]) == 4 and
             ph.get("power-domain-names") == b"usb-aon\0common\0wrapper\0usb\0",
             "%s: PHY does not name the four domains usb-aon, common, wrapper, usb" % name)
        alias = tree.get("/aliases", {}).get("atcphy%d" % index, b"")
        need(alias == phy.encode() + b"\0", "%s: alias atcphy%d is %r" % (name, index, alias))
        nodes = [bus, pd, con, usb, phy, mbox, *darts]
        nodes += [k for k in tree if k.startswith(con + "/") or k.startswith(usb + "/") or k.startswith(phy + "/")]
        suppliers = closure(tree, nodes)
        for s in sorted(suppliers):
            need(enabled(tree, s), "%s: supplier %s is disabled" % (name, s))
        if ref is not None:
            for n in sorted(set(nodes) | suppliers):
                if n not in ref:
                    bad.append("%s: %s is not in the reference tree" % (name, n))
                    continue
                for k in sorted(set(tree[n]) | set(ref[n])):
                    if tree[n].get(k) != ref[n].get(k):
                        bad.append("%s: %s %s differs from the reference tree" % (name, n, k))
                compared += 1
    for n in DEBUG_PORT:
        # the controller node must not exist; the SoC's dwc3 and PHY nodes may, disabled
        described = n in tree and (n.rsplit("/", 1)[-1].startswith("usb-pd@") or enabled(tree, n))
        need(not described, "left-back port is described (%s): it is the loader's debug port" % n)
    for b in bad:
        print("FAIL %s: %s" % (path, b))
    if not bad:
        print("  %s: both ports complete%s" % (path.rsplit("/", 1)[-1],
                                             ", %d nodes equal to the reference" % compared if ref is not None else ""))
    return len(bad)


def main(argv):
    args, ref = argv[1:], None
    if "--reference" in args:
        i = args.index("--reference")
        ref = resolve(load(args[i + 1]))
        del args[i:i + 2]
    if not args:
        print(__doc__)
        return 64
    bad = sum(lint(a, resolve(load(a)), ref) for a in args)
    print("usb dtb lint:", "FAILED" if bad else "passed", "(%d trees)" % len(args))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
