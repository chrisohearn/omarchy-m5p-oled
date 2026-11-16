#!/usr/bin/python3 -I
# SPDX-License-Identifier: MIT
"""k114s-adt-usb4-facts.py: do the USB4/Thunderbolt router nodes agree with this Mac's Apple device tree?

    sudo python3 -I tests/k114s-adt-usb4-facts.py t6050-k114s-r3-usb4.dtb [--adt FILE]

The tree is dts/t6050-k114s-r3-usb4.dts compiled against a kernel tree that has the J714s
left-front router (aurora-silicon/linux #1791) and the right-port router (#1841). For both
routers (ATC1 = /arm-io/acio1, ATC2 = /arm-io/acio2) every address, interrupt and pin of the
compiled nodes is read back and compared with the ADT, which is read from the "adt" MTD
partition (root only) or from --adt FILE. Only addresses, interrupt numbers, pin numbers and
the K114s' board-level facts are printed: tunables, the host DROM (router UUID) and firmware are
never read or printed.

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
# (name, ADT router node, ADT cpu node, ADT dart node, AOP GPIO pin of the LSTX line)
ROUTERS = [("ATC1 left-front", "acio1", "acio-cpu1", "dart-acio1", 79),
           ("ATC2 right", "acio2", "acio-cpu2", "dart-acio2", 81)]


def router_facts(adt, t, name, acio, cpu, dart, lstx):
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
    for name, acio, cpu, dart, lstx in ROUTERS:
        for what, dtbv, found in router_facts(adt, t, name, acio, cpu, dart, lstx):
            if dtbv == found:
                print("  ok    %s: %s" % (what, pf.hexs(dtbv)))
            else:
                bad += 1
                print("  FAIL  %s: the tree says %s, the ADT says %s" % (what, pf.hexs(dtbv), pf.hexs(found)))
    print("usb4 facts: %s" % ("every fact holds" if not bad else "%d do not hold" % bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
