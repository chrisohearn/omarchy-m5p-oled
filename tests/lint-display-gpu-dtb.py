#!/usr/bin/env python3
"""Device tree lint for the K114s display and GPU hand-offs (candidate r3).

usage: lint-display-gpu-dtb.py [--k116s K116S.dtb] K114S.dtb...

For each tree it repeats, offline, the device-tree side of the checks the loader makes before it
hands the panel and the GPU over (aura src/kboot_display_handoff.c t6050_check_dt() and
t6050_check_darts(), src/kboot_gpu.c t6050_gpu_check() and t6050_gpu_enable(), at aura 22b71758
plus betizzel/omarchy-m5's seven patches). It cannot repeat the checks against the Apple device
tree or the live registers: those run on the Mac, in the loader.

With --k116s it also compares the display and GPU nodes with the K116s tree of
aurora-silicon/linux, property by property, and fails on any difference that is not one of the
named K114s differences.

A tree without the "dcp"/"disp0" aliases is checked to leave the display to the boot framebuffer;
one without the "gpu" alias to leave the GPU alone. This is a software check, not hardware proof.
"""
import struct
import sys


def parse(blob):
    magic, _total, off_struct, off_strings, _, _ver, _, _, size_strings, _ = struct.unpack_from(">10I", blob)
    assert magic == 0xD00DFEED, "not a device tree blob"
    strings = blob[off_strings:off_strings + size_strings]
    pos, path, nodes = off_struct, [], {}
    while True:
        token = struct.unpack_from(">I", blob, pos)[0]
        pos += 4
        if token == 1:
            end = blob.index(b"\0", pos)
            path.append(blob[pos:end].decode())
            pos = (end + 4) & ~3
            nodes["/" + "/".join(path[1:])] = {}
        elif token == 3:
            length, name_off = struct.unpack_from(">II", blob, pos)
            pos += 8
            value = blob[pos:pos + length]
            pos = (pos + length + 3) & ~3
            name = strings[name_off:strings.index(b"\0", name_off)].decode()
            nodes["/" + "/".join(path[1:])][name] = value
        elif token == 2:
            path.pop()
        elif token == 9:
            return nodes


def cells(value):
    return list(struct.unpack(">%dI" % (len(value) // 4), value))


def strs(value):
    return value.decode().rstrip("\0").split("\0")


class Tree:
    def __init__(self, path):
        self.file = path
        self.nodes = parse(open(path, "rb").read())
        self.by_phandle = {cells(p["phandle"])[0]: n for n, p in self.nodes.items() if "phandle" in p}
        self.errors = []
        self.notes = []

    def fail(self, text):
        self.errors.append(text)

    def alias(self, name):
        value = self.nodes.get("/aliases", {}).get(name)
        return strs(value)[0] if value else None

    def prop(self, node, name):
        return self.nodes.get(node, {}).get(name)

    def disabled(self, node):
        status = self.prop(node, "status")
        return status is not None and strs(status)[0] == "disabled"

    def compatible(self, node, want):
        value = self.prop(node, "compatible")
        return value is not None and want in strs(value)

    def parent(self, node):
        return node.rsplit("/", 1)[0] or "/"

    def target(self, phandle):
        return self.by_phandle.get(phandle)

    def reg64(self, node):
        value = cells(self.prop(node, "reg") or b"")
        return [(value[i] << 32 | value[i + 1], value[i + 2] << 32 | value[i + 3]) for i in range(0, len(value) - 3, 4)]


DCP_REGS = ["coproc", "iop-vbar", "disp-0", "disp-1", "disp-2", "disp-3", "disp-4"]
GPU_RESERVATIONS = ["uat-ttbs", "uat-pagetables", "uat-l2-pagetables", "uat-handoff", "gpu-fw-text", "gpu-fw-data"]
GPU_ENABLE = ["/soc/power-management@2300e80000", "/soc/power-management@2300e80000/power-controller@0",
              "/soc/power-management@2300e80000/power-controller@100",
              "/soc/power-management@2300e80000/power-controller@110", "/soc/mailbox@2302600000",
              "/soc/mailbox@2302e00000"]
DMA_RANGE = [0x100, 0x0, 0x300, 0x0]  # vm-base 1 TiB, vm-size 3 TiB


def check_iommu(t, user, what, sid):
    """aura dcp6_check_iommu(): <&dart sid>, a t8110 DART with one cell and the ADT's DVA window."""
    value = cells(t.prop(user, "iommus") or b"")
    if len(value) != 2 or value[1] != sid:
        t.fail("%s: iommus is not <&dart %d>" % (what, sid))
        return None
    dart = t.target(value[0])
    if dart is None or not t.compatible(dart, "apple,t8110-dart"):
        t.fail("%s: iommus does not point to a t8110 DART" % what)
        return None
    if cells(t.prop(dart, "#iommu-cells") or b"") != [1]:
        t.fail("%s: DART #iommu-cells is not 1" % what)
    if cells(t.prop(dart, "apple,dma-range") or b"") != DMA_RANGE:
        t.fail("%s: DART %s apple,dma-range is not <0x100 0x0 0x300 0x0>" % (what, dart))
    if not t.disabled(dart):
        t.fail("%s: DART %s is not disabled in the tree (the loader enables it)" % (what, dart))
    return dart


def check_display(t):
    dcp, disp = t.alias("dcp"), t.alias("disp0")
    if dcp is None and disp is None:
        if any(t.compatible(n, "apple,display-subsystem") for n in t.nodes):
            t.fail("a display-subsystem node without the dcp/disp0 aliases")
        t.notes.append("display: no dcp/disp0 aliases, the loader makes no hand-off (boot framebuffer)")
        return
    if dcp is None or disp is None or dcp not in t.nodes or disp not in t.nodes:
        t.fail("only one of the dcp/disp0 aliases, or an alias that names no node")
        return
    if not t.compatible(dcp, "apple,t6050-dcp") or not t.compatible(disp, "apple,display-subsystem"):
        t.fail("aliases dcp and disp0 are not apple,t6050-dcp and apple,display-subsystem")
    parent = t.parent(dcp)
    if (cells(t.prop(parent, "#address-cells") or b"") != [2] or cells(t.prop(parent, "#size-cells") or b"") != [2]
            or t.prop(parent, "ranges") != b""):
        t.fail("dcp is not on an identity-mapped bus with 2 address and 2 size cells")
    panel = dcp + "/panel"
    if panel not in t.nodes:
        t.fail("dcp has no panel child")
    else:
        if not t.compatible(panel, "apple,panel"):
            t.fail("panel is not compatible with apple,panel")
        for name in ("width-mm", "height-mm"):
            value = cells(t.prop(panel, name) or b"")
            if len(value) != 1 or not 0 < value[0] <= 2550:
                t.fail("panel %s missing or out of range (the kernel treats a panel without a width as absent)" % name)
        if t.prop(panel, "apple,max-brightness") is not None:
            t.notes.append("display: panel carries apple,max-brightness, so the loader keeps it instead of the ADT's")
    for node, what in ((dcp, "dcp"), (disp, "disp0")):
        if not t.disabled(node):
            t.fail("%s is not status \"disabled\"" % what)
        if t.prop(node, "memory-region") is not None:
            t.fail("%s already has a memory-region" % what)
    for name in ("clocks", "apple,bw-scratch"):
        if t.prop(dcp, name) is not None:
            t.fail("dcp already has %s (the loader adds it and refuses a tree that has it)" % name)
    names = strs(t.prop(dcp, "reg-names") or b"\0")
    regs = t.reg64(dcp)
    for name in DCP_REGS:
        if name not in names or names.index(name) >= len(regs):
            t.fail("dcp has no reg named %s" % name)
    coproc = regs[names.index("coproc")][0] if "coproc" in names and regs else None
    mboxes = cells(t.prop(dcp, "mboxes") or b"")
    mbox = t.target(mboxes[0]) if len(mboxes) == 1 else None
    if mbox is None or not t.compatible(mbox, "apple,asc-mailbox-v4") or not t.disabled(mbox):
        t.fail("dcp mboxes is not one disabled apple,asc-mailbox-v4 node")
    elif coproc is None or not t.reg64(mbox) or t.reg64(mbox)[0][0] != coproc + 0x8000:
        t.fail("dcp mailbox is not at coproc + 0x8000")
    piodma = dcp + "/piodma"
    if piodma not in t.nodes:
        t.fail("dcp has no piodma child")
        return
    dart_dcp = check_iommu(t, dcp, "dcp", 23)
    dart_disp = check_iommu(t, disp, "disp0", 0)
    dart_pio = check_iommu(t, piodma, "piodma", 16)
    if dart_disp is not None and (dart_disp != dart_pio or dart_disp == dart_dcp):
        t.fail("display and piodma must share one DART, dcp another")
    # what the loader adds must not be there yet
    pmc = regs[names.index("disp-4")][0] if "disp-4" in names and len(regs) > names.index("disp-4") else None
    if pmc is not None and "%s/pmc-metadata@%x" % (parent.rstrip("/"), pmc) in t.nodes:
        t.fail("%s/pmc-metadata@%x exists already: the loader could not add it" % (parent, pmc))
    if any(n.startswith("/clock-dcp-firmware-") for n in t.nodes):
        t.fail("a /clock-dcp-firmware-N node exists already: the loader adds them")
    if "/reserved-memory" not in t.nodes:
        t.fail("no /reserved-memory for the loader's framebuffer reservation")
    t.notes.append("display: described for the hand-off (dcp %s, panel %s x %s mm)" % (
        dcp, cells(t.prop(panel, "width-mm") or b"\0\0\0\0")[0], cells(t.prop(panel, "height-mm") or b"\0\0\0\0")[0]))


def check_gpu(t):
    gpu = t.alias("gpu")
    if gpu is None:
        for name in GPU_RESERVATIONS:
            if "/reserved-memory/" + name in t.nodes:
                t.fail("GPU reservation %s without the gpu alias" % name)
        t.notes.append("gpu: no gpu alias, the loader leaves the GPU alone")
        return
    if gpu not in t.nodes or not t.compatible(gpu, "apple,agx-g17s"):
        t.fail("alias gpu is not an apple,agx-g17s node")
        return
    if not t.disabled(gpu):
        t.fail("gpu is not status \"disabled\" (the loader enables it last)")
    for name in GPU_RESERVATIONS:
        node = "/reserved-memory/" + name
        if node not in t.nodes:
            t.fail("no %s" % node)
            continue
        if cells(t.prop(node, "reg") or b"") != [0, 0, 0, 0] or t.prop(node, "no-map") is None or not t.disabled(node):
            t.fail("%s is not an empty, disabled no-map reservation" % node)
    for node in GPU_ENABLE:
        if node not in t.nodes:
            t.fail("no %s (the loader enables it by this exact path)" % node)
        elif not t.disabled(node):
            t.fail("%s is not disabled in the tree" % node)
    regions = [t.target(p) for p in cells(t.prop(gpu, "memory-region") or b"")]
    names = strs(t.prop(gpu, "memory-region-names") or b"\0")
    want = {"ttbs": "uat-ttbs", "pagetables": "uat-pagetables", "handoff": "uat-handoff", "fw-data": "gpu-fw-data",
            "l2-pagetables": "uat-l2-pagetables", "fw-text": "gpu-fw-text"}
    if len(regions) != 6 or sorted(names) != sorted(want) or any(
            regions[i] != "/reserved-memory/" + want[n] for i, n in enumerate(names) if n in want and i < len(regions)):
        t.fail("gpu memory-region/-names do not name the six reservations")
    mboxes = [t.target(p) for p in cells(t.prop(gpu, "mboxes") or b"")]
    if mboxes != ["/soc/mailbox@2302600000", "/soc/mailbox@2302e00000"]:
        t.fail("gpu mboxes are not the GFX and GFX1 mailboxes, in that order")
    for node in mboxes:
        if node and (not cells(t.prop(node, "interrupts") or b"") or
                     strs(t.prop(node, "interrupt-names") or b"\0") != ["send-empty", "recv-not-empty"]):
            t.fail("%s: not the send-empty and recv-not-empty interrupts" % node)
    if t.prop(gpu, "interrupts") is not None:
        t.fail("gpu still has the inventory interrupts")
    domain = [t.target(p) for p in cells(t.prop(gpu, "power-domains") or b"")]
    if domain == ["/soc/power-management@2300e80000/power-controller@110"]:
        t.notes.append("gpu: on ps_gfx directly (no PMP report)")
    elif len(domain) == 1 and domain[0] and domain[0].endswith("/report@f"):
        report = t.parent(domain[0])
        if t.disabled(report):
            t.fail("gpu sits on the PMP report entry, but the PMP report is disabled: the GPU would never probe")
        t.notes.append("gpu: on the PMP report entry")
    else:
        t.fail("gpu power-domains is neither ps_gfx nor the PMP report entry")
    for node in ("/soc/gpu-coproc@2302600000", "/soc/gpu-coproc@2302e00000"):
        if node in t.nodes:
            t.fail("%s still exists beside the mailbox for the same window" % node)
    t.notes.append("gpu: described for the hand-off (%s)" % gpu)


# property -> the cells that are phandles (resolved to paths before two trees are compared)
PHANDLE_PROPS = {"iommus": 2, "mboxes": 1, "power-domains": 1, "memory-region": 1, "apple,clpc": 1,
                 "interrupt-parent": 1}
# compared only when the tree describes that hand-off (its aliases exist)
PARITY_DISPLAY = ["/display-subsystem", "/soc/dcp@48ae00000", "/soc/dcp@48ae00000/panel", "/soc/dcp@48ae00000/piodma",
                  "/soc/mailbox@48ae08000", "/soc/iommu@48a300000", "/soc/iommu@48a340000"]
PARITY_GPU = ["/soc/gpu@2300000000"] + GPU_ENABLE + ["/reserved-memory/" + n for n in GPU_RESERVATIONS]
# (node, property): why the K114s tree differs from the K116s tree there
EXPECTED = {
    ("/soc/dcp@48ae00000/panel", "compatible"): "this board's panel name",
    ("/soc/dcp@48ae00000/panel", "width-mm"): "the 14-inch panel",
    ("/soc/dcp@48ae00000/panel", "height-mm"): "the 14-inch panel",
    ("/soc/dcp@48ae00000", "apple,clock-ids"): "left to the loader, which writes it from the ADT either way",
    ("/soc/gpu@2300000000", "power-domains"): "ps_gfx directly: r3 does not run the PMP",
}


def resolved(t, node, name, value):
    if name == "phandle":
        return "<phandle>"
    stride = PHANDLE_PROPS.get(name)
    if stride and len(value) % 4 == 0:
        out = cells(value)
        return tuple(t.target(v) if i % stride == 0 else v for i, v in enumerate(out))
    return value


def compare(t, ref):
    wanted = (PARITY_DISPLAY if t.alias("dcp") else []) + (PARITY_GPU if t.alias("gpu") else [])
    for node in wanted:
        if node not in t.nodes:
            t.fail("parity: no %s" % node)
            continue
        if node not in ref.nodes:
            t.fail("parity: %s is not in the K116s tree" % node)
            continue
        ours, theirs = t.nodes[node], ref.nodes[node]
        for name in sorted(set(ours) | set(theirs)):
            a = resolved(t, node, name, ours[name]) if name in ours else None
            b = resolved(ref, node, name, theirs[name]) if name in theirs else None
            if a == b:
                continue
            why = EXPECTED.get((node, name))
            if why:
                t.notes.append("parity: %s %s differs from the K116s tree (%s)" % (node, name, why))
            else:
                t.fail("parity: %s %s differs from the K116s tree: %r / %r" % (node, name, a, b))
    for name in ("dcp", "disp0", "gpu"):
        if t.alias(name) is not None and t.alias(name) != ref.alias(name):
            t.fail("parity: alias %s is %s, K116s has %s" % (name, t.alias(name), ref.alias(name)))


def main(argv):
    ref = None
    if argv[:1] == ["--k116s"]:
        ref, argv = Tree(argv[1]), argv[2:]
    if not argv:
        print(__doc__)
        return 2
    bad = 0
    for path in argv:
        t = Tree(path)
        root = strs(t.nodes["/"]["compatible"])[0]
        if root != "apple,k114s":
            t.fail("root compatible is %s" % root)
        check_display(t)
        check_gpu(t)
        if ref is not None:
            compare(t, ref)
        name = path.rsplit("/", 1)[-1]
        for note in t.notes:
            print("  %s: %s" % (name, note))
        for error in t.errors:
            print("FAIL %s: %s" % (name, error))
        bad += len(t.errors)
    print("display/GPU dtb lint:", "FAILED" if bad else "passed", "(%d trees%s)" % (
        len(argv), ", compared with the K116s tree" if ref else ""))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
