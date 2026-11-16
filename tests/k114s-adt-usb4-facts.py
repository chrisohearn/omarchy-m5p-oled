#!/usr/bin/python3 -I
# SPDX-License-Identifier: MIT
"""k114s-adt-usb4-facts.py: do the USB4/Thunderbolt router nodes agree with this Mac's Apple device tree?

    sudo python3 -I tests/k114s-adt-usb4-facts.py t6050-k114s-r3-usb4.dtb [--adt FILE]

The tree is dts/t6050-k114s-r3-usb4.dts compiled against a kernel tree that has the J714s
left-front router (aurora-silicon/linux #1791) and the right-port router (#1841). For both
routers (ATC1 = /arm-io/acio1, ATC2 = /arm-io/acio2) every address, interrupt and pin of the
compiled nodes is read back and compared with the ADT, which is read from the "adt" MTD
partition (root only) or from --adt FILE. Also compared: the router, PCIe adapter, firmware, NHI,
DART, PHY RX_TOP CIO and PCIe tunnel tunables, the host DROM of a router that has one, and that
both LSTX pins are outside the AOP pin controller's reserved ranges. Only addresses, interrupt
numbers and pin numbers are printed; tunables and the DROM (router UUID) are compared and reported
as yes/no, never printed.

Exit 0: every fact holds. Exit 1: at least one does not. Exit 2: ADT or tree unreadable.
"""
import importlib.util
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name, file):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, file))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


sf = _load("soundfacts", "k114s-adt-sound-facts.py")
pf = _load("parityfacts", "k114s-adt-parity-facts.py")

AIC_IRQ = 0
# (name, ADT router node, ADT cpu node, ADT dart node, ADT PHY node, ADT PCIe tunnel controller node)
ROUTERS = [("ATC1 left-front", "acio1", "acio-cpu1", "dart-acio1", "atc-phy1", "apciec1"),
           ("ATC2 right", "acio2", "acio-cpu2", "dart-acio2", "atc-phy2", "apciec2")]


def adt_tun(adt, path, name, base=0):
    """An ADT tunables property as (offset + base, mask, value) triples: 6 words each, offset, size, 64-bit mask and value."""
    v = sf.u32s(adt.prop(path, name)) or []
    return [((v[i] + base) & 0xffffffff, v[i + 2], v[i + 4]) for i in range(0, len(v) - 5, 6)]


def fdt_tun(t, node, name):
    c = t.cells(t.nodes[node].get(name, b""))
    return [tuple(c[i:i + 3]) for i in range(0, len(c) - 2, 3)]


def router_facts(adt, t, name, acio, cpu, dart, phy, apciec):
    A = "arm-io/"
    out = []
    fact = lambda what, dtb, a: out.append((what, dtb, a))
    # ADT reg: [0] NHI, [1] rc, [2] ..., [4] PCIe adapter, [5] router AP firmware. CPU reg: [0] mailbox, [1] wrapper.
    node = None
    for n in t.find("apple,t6050-usb4-acio"):
        if t.regs(n) and t.regs(n)[0][0] == adt.addr(A + acio, 1):
            node = n
    fact("%s: a router node exists at the ADT's rc address" % name, node is not None, True)
    if node is None:
        return out
    r = t.regs(node)
    fact("%s: rc" % name, r[0][0], adt.addr(A + acio, 1))
    fact("%s: PCIe adapter" % name, r[2][0], adt.addr(A + acio, 4))
    fact("%s: CPU wrapper" % name, r[3][0], adt.addr(A + cpu, 1))
    fact("%s: router AP firmware" % name, r[4][0], adt.addr(A + acio, 5))
    mbox, _ = t.target(node, "mboxes", stride=1)
    fact("%s: mailbox" % name, t.regs(mbox)[0][0] if mbox else None, adt.addr(A + cpu, 0))
    fact("%s: mailbox interrupts" % name, sorted(t.irqs(mbox)) if mbox else None,
         sorted(sf.u32s(adt.prop(A + cpu, "interrupts"))))
    w = t.cells(t.prop(node, "lstx-gpios") or b"")
    fact("%s: LSTX pin of the AOP GPIO controller" % name, w[1] if len(w) > 1 else None,
         sf.u32s(adt.prop(A + acio, "gpio-lstx"))[0])
    nhi = next((n for n in t.nodes if n.startswith(node + "/nhi@")), None)
    ints = sf.u32s(adt.prop(A + acio, "interrupts"))
    fact("%s: NHI interrupts" % name, sorted(t.irqs(nhi)) if nhi else None, sorted(ints))
    fact("%s: NHI register block" % name, int(nhi.rsplit("@", 1)[1], 16) if nhi else None,
         adt.addr(A + acio, 0) & 0xffffff)
    d = next((n for n in t.nodes if n.startswith(node + "/iommu@")), None)
    fact("%s: DART interrupt" % name, t.irqs(d)[0] if d else None, sf.u32s(adt.prop(A + dart, "interrupts"))[0])
    fact("%s: five power domains" % name, len(t.cells(t.prop(node, "power-domains"))), 5)
    fact("%s: router enabled" % name, t.enabled(node), True)
    # Tunables: compared as sorted (offset, mask, value) sets; only yes/no is printed, never a value.
    # The ADT groups the router's blocks at these base offsets inside the rc and the NHI.
    P = A + acio
    same = lambda what, tree, adtv: fact("%s: %s equal the ADT's" % (name, what), sorted(tree) == sorted(adtv) and bool(adtv), True)
    same("router rc tunables", fdt_tun(t, node, "apple,tunable-rc"),
         adt_tun(adt, P, "top_tunables") + adt_tun(adt, P, "hbw_fabric_tunables", 0x4000) +
         adt_tun(adt, P, "lbw_fabric_tunables", 0x8000))
    same("PCIe adapter tunables", fdt_tun(t, node, "apple,tunable-pcie-adapter"), adt_tun(adt, P, "pcie_adapter_regs_tunables"))
    same("router AP firmware tunables", fdt_tun(t, node, "apple,tunable-router-ap-fw"), adt_tun(adt, P, "pcie_router_ap_fw"))
    if nhi:
        same("NHI tunables", fdt_tun(t, nhi, "apple,tunable-nhi"),
             adt_tun(adt, P, "fw_int_ctl_management_tunables", 0x4000) +
             adt_tun(adt, P, "hi_up_merge_fabric_tunables", 0xf8000) + adt_tun(adt, P, "hi_dn_merge_fabric_tunables", 0xfc000))
        drom = t.nodes[nhi].get("apple,thunderbolt-drom")
        if drom is None:
            out.append(("%s: host DROM (none in the tree, not checked)" % name, True, True))
        else:
            fact("%s: host DROM equals the ADT's" % name, drom == adt.prop(P, "thunderbolt-drom"), True)
    same("DART tunables", fdt_tun(t, d, "apple,tunable") if d else [], adt_tun(adt, A + dart, "dart-tunables-instance-0"))
    # the PHY's CIO RX_TOP tunables; the ADT offset word carries a register index in its top bits
    ph = next((n for n, p in t.nodes.items() if "apple,tunable-lane0-rx-top-cio" in p
               and t.regs(n)[0][0] == adt.addr(A + phy, 2)), None)
    for lane in (0, 1):
        v = sf.u32s(adt.prop(A + phy, "tunable_LN%d_RX_TOP_CIO_DFLT" % lane)) or []
        fact("%s: PHY lane %d RX_TOP CIO tunable equals the ADT's" % (name, lane),
             ph is not None and fdt_tun(t, ph, "apple,tunable-lane%d-rx-top-cio" % lane) == [(v[0] & 0xffffff, v[1], v[2])] if len(v) == 3 else False, True)
    # the PCIe tunnel behind the router
    tun = t.ph.get((t.cells(t.prop(node, "apple,pcie-tunnel") or b"") or [None])[0])
    pcie = next((n for n in t.nodes if tun and n.startswith(tun + "/pcie@") and n.count("/") == 2), None)
    port = next((n for n in t.nodes if pcie and n.startswith(pcie + "/pci@")), None)
    for what, n, prop, aprop in (("debug", pcie, "apple,tunable-debug", "atc-apcie-debug-tunables"),
                                 ("rc", pcie, "apple,tunable-rc", "atc-apcie-rc-tunables"),
                                 ("fabric", pcie, "apple,tunable-fabric", "atc-apcie-fabric-tunables"),
                                 ("config", port, "apple,tunable", "apcie-config-tunables")):
        same("tunnel %s tunables" % what, fdt_tun(t, n, prop) if n else [], adt_tun(adt, A + apciec, aprop))
    td = next((n for n in t.nodes if tun and n.startswith(tun + "/iommu@")), None)
    same("tunnel DART tunables", fdt_tun(t, td, "apple,tunable") if td else [], adt_tun(adt, A + "dart-" + apciec, "dart-tunables-instance-0"))
    # both routers' LSTX pins must stay out of the AOP pin controller's reserved ranges
    gc, _ = t.target(node, "lstx-gpios", stride=2)
    rr = t.cells(t.prop(gc, "gpio-reserved-ranges") or b"") if gc else []
    pin = sf.u32s(adt.prop(P, "gpio-lstx"))[0]
    fact("%s: LSTX pin %d is not in the pin controller's reserved ranges" % (name, pin),
         gc is not None and not any(rr[i] <= pin < rr[i] + rr[i + 1] for i in range(0, len(rr) - 1, 2)), True)
    return out


def main(argv):
    args, adt_path, dtb = argv, None, None
    while args:
        a = args.pop(0)
        if a == "--adt":
            adt_path = args.pop(0)
        elif dtb is None:
            dtb = a
        else:
            print(__doc__)
            return 2
    if not dtb:
        print(__doc__)
        return 2
    try:
        adt = sf.Tree(sf.load(adt_path))
        board = (sf.u32s(adt.prop("chosen", "board-id")) or [None])[0]
        if board != sf.BOARD_ID:
            print("this ADT is board-id %s, not the K114s (0x14); refusing" % board)
            return 2
        t = pf.Fdt(open(dtb, "rb").read())
    except (sf.AdtError, OSError, ValueError, KeyError) as e:
        print("k114s-adt-usb4-facts: %s: %s" % (type(e).__name__, e), file=sys.stderr)
        return 2
    bad = 0
    for r in ROUTERS:
        for what, dtbv, found in router_facts(adt, t, *r):
            if dtbv == found:
                print("  ok    %s: %s" % (what, pf.hexs(dtbv)))
            else:
                bad += 1
                print("  FAIL  %s: the tree says %s, the ADT says %s" % (what, pf.hexs(dtbv), pf.hexs(found)))
    print("usb4 facts: %s" % ("every fact holds" if not bad else "%d do not hold" % bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
