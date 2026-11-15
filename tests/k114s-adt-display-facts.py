#!/usr/bin/env python3
"""Read the display and GPU facts candidate r3 depends on from the running Mac's Apple device tree.

    sudo python3 tests/k114s-adt-display-facts.py [--dtb t6050-k114s-r3.dtb] [--adt FILE] [--names NODE]

Read-only. The loader keeps the Apple device tree (ADT) of this boot in memory and Linux shows it
as the MTD device named "adt" (see /proc/mtd); only root can read it, so this needs sudo. Nothing
is written anywhere and nothing is sent anywhere.

It prints only the values named below: firmware image UUIDs (they identify an Apple firmware
build, not a machine), register addresses, clock ids, DART windows, the brightness scale and
property NAMES. It never prints serial numbers, MAC addresses or any other value of a property
that is not on its list, so the output can go into a public report. Do not publish the ADT
itself.

What it answers:
  1. Which display coprocessor (DCP) image did iBoot load? The loader hands the panel over only
     for an image it pins. Pull request 226 of aurora-silicon/aura pins the K116s image.
  2. Do the registers, streams and DART windows of the K114s tree match this machine's ADT?
     (--dtb; the loader makes the same comparison at boot and refuses on a mismatch.) And the
     display mailbox's four interrupts, which the loader does not compare?
  3. What does the ADT say about the panel (size, brightness scale, gamut)?
  4. Does the ADT carry the GPU ranges the loader fills in?

--names NODE lists a node's property names and sizes (no values), for follow-up questions.
"""
import re
import struct
import sys

PINNED = {
    "64863924-B56B-3E32-87FE-038677F52709": "macOS 27.0 image (J714s); pinned by aura",
    "C51FB0C8-C45D-39B0-85BC-520E600FC950": "macOS 27.2 26B123 image (J714s); pinned by betizzel's aura patch 0005, "
                                            "which is in the installed loader",
    "3D6C8857-E6F1-3D2E-9DFF-587028AE0C6E": "macOS 27.2 26B8125 image (K116s); pinned by aura pull request 226",
}
R3_IMAGE = "3D6C8857-E6F1-3D2E-9DFF-587028AE0C6E"
UUID = re.compile(rb"[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}")


class Node:
    def __init__(self, name, props, children):
        self.name, self.props, self.children = name, props, children

    def child(self, name):
        for c in self.children:
            if c.name == name:
                return c
        return None


def parse_adt(blob, pos=0, depth=0):
    """m1n1 src/adt.h: u32 property count, u32 child count, then the properties (32-byte name,
    u32 size with flags in the top bit, value padded to 4 bytes), then the children."""
    if depth > 32:
        raise ValueError("ADT nested too deep")
    nprops, nchildren = struct.unpack_from("<II", blob, pos)
    if nprops > 4096 or nchildren > 4096:
        raise ValueError("not an ADT node at 0x%x" % pos)
    pos += 8
    props = {}
    for _ in range(nprops):
        name = blob[pos:pos + 32].split(b"\0", 1)[0].decode("ascii", "replace")
        size = struct.unpack_from("<I", blob, pos + 32)[0] & 0x7FFFFFFF
        if pos + 36 + size > len(blob):
            raise ValueError("ADT property %s runs past the end" % name)
        props[name] = blob[pos + 36:pos + 36 + size]
        pos += 36 + ((size + 3) & ~3)
    children = []
    for _ in range(nchildren):
        child, pos = parse_adt(blob, pos, depth + 1)
        children.append(child)
    name = props.get("name", b"").split(b"\0", 1)[0].decode("ascii", "replace")
    return Node(name, props, children), pos


def find(root, path):
    """-> the list of nodes from the root down to `path`, or None."""
    trail = [root]
    for part in [p for p in path.split("/") if p]:
        nxt = trail[-1].child(part)
        if nxt is None:
            return None
        trail.append(nxt)
    return trail


def u32s(value):
    return list(struct.unpack("<%dI" % (len(value) // 4), value[:len(value) // 4 * 4]))


def cell_value(cells):
    return sum(c << (32 * i) for i, c in enumerate(cells))


def cells_of(node, name, default):
    value = node.props.get(name)
    return u32s(value)[0] if value and len(value) >= 4 else default


def get_reg(trail, index, prop="reg"):
    """m1n1 adt_get_reg(): entry `index` of the node's reg, translated through every parent's ranges."""
    node, parent = trail[-1], trail[-2]
    a_cells, s_cells = cells_of(parent, "#address-cells", 2), cells_of(parent, "#size-cells", 1)
    reg = u32s(node.props.get(prop, b""))
    width = a_cells + s_cells
    if (index + 1) * width > len(reg):
        return None
    entry = reg[index * width:(index + 1) * width]
    addr, size = cell_value(entry[:a_cells]), cell_value(entry[a_cells:])
    for depth in range(len(trail) - 2, 0, -1):
        bus, above = trail[depth], trail[depth - 1]
        ranges = bus.props.get("ranges")
        if not ranges:
            continue
        ca, cs = cells_of(bus, "#address-cells", 2), cells_of(bus, "#size-cells", 1)
        pa = cells_of(above, "#address-cells", 2)
        cells = u32s(ranges)
        step = ca + pa + cs
        for i in range(0, len(cells) - step + 1, step):
            child_base = cell_value(cells[i:i + ca])
            parent_base = cell_value(cells[i + ca:i + ca + pa])
            length = cell_value(cells[i + ca + pa:i + step])
            if child_base <= addr < child_base + length:
                addr = addr - child_base + parent_base
                break
    return addr, size


def text(value):
    return value.split(b"\0", 1)[0].decode("ascii", "replace") if value is not None else None


def u64(value):
    return struct.unpack_from("<Q", value)[0] if value is not None and len(value) >= 8 else None


# ---- the flattened device tree side (only with --dtb) ----

def parse_fdt(blob):
    magic, _total, off_struct, off_strings, _, _ver, _, _, size_strings, _ = struct.unpack_from(">10I", blob)
    if magic != 0xD00DFEED:
        raise ValueError("--dtb is not a device tree blob")
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
            nodes["/" + "/".join(path[1:])][strings[name_off:strings.index(b"\0", name_off)].decode()] = \
                blob[pos:pos + length]
            pos = (pos + length + 3) & ~3
        elif token == 2:
            path.pop()
        elif token == 9:
            return nodes


def fdt_cells(value):
    return list(struct.unpack(">%dI" % (len(value) // 4), value)) if value else []


def strs_of(value):
    return value.decode().rstrip("\0").split("\0") if value else []


def fdt_reg(nodes, node):
    c = fdt_cells(nodes.get(node, {}).get("reg"))
    return [(c[i] << 32 | c[i + 1], c[i + 2] << 32 | c[i + 3]) for i in range(0, len(c) - 3, 4)]


class Report:
    def __init__(self):
        self.failed = 0

    def fact(self, what, value):
        print("  %-34s %s" % (what, value))

    def check(self, ok, what):
        print("  %s  %s" % ("PASS" if ok else "FAIL", what))
        self.failed += 0 if ok else 1


def hexpair(pair):
    return "missing" if pair is None else "0x%x + 0x%x" % pair


def report(root, dtb, out):
    print("== identity (already public for this board)")
    chosen = find(root, "/chosen")
    out.fact("root compatible", ", ".join(root.props.get("compatible", b"").decode("ascii", "replace").strip("\0").split("\0")))
    if chosen:
        out.fact("/chosen board-id", "0x%x" % cells_of(chosen[-1], "board-id", 0))

    print("== 1. display coprocessor firmware image")
    image = None
    for name in ("dcp", "dcpext0", "dcpext1", "dcpext2", "dcpext3"):
        nub = find(root, "/arm-io/%s/iop-%s-nub" % (name, name))
        if nub is None:
            out.fact(name, "no iop-%s-nub in the ADT" % name)
            continue
        uuid = text(nub[-1].props.get("uuid"))
        running = cells_of(nub[-1], "running", None)
        out.fact("%s image" % name, "%s, running=%s" % (uuid or "(no uuid)", running))
        if name == "dcp":
            image = uuid
            segments = nub[-1].props.get("segment-ranges", b"")
            out.fact("dcp segment-ranges", "%d entries" % (len(segments) // 32))
    if image:
        out.fact("this image is", PINNED.get(image, "NOT pinned by any loader this repository knows"))
        if image == R3_IMAGE:
            print("  -> the r3 loader (aura + pull request 226) admits it: the K114s runs the K116s image.")
        elif image in PINNED:
            print("  -> the r3 loader admits it, as another board's image. Unexpected for a K114s: stop and report.")
        else:
            print("  -> the r3 loader REFUSES the panel hand-off and the boot framebuffer keeps the panel.")
            print("     This UUID has to be reviewed and added to the loader before the panel can move.")
    disp0 = find(root, "/arm-io/disp0")
    if disp0:
        out.fact("disp0 is external", "yes (unexpected)" if "external" in disp0[-1].props else "no")
        out.fact("disp0 clock-ids", u32s(disp0[-1].props.get("clock-ids", b"")))

    print("== 2. registers and DART windows")
    regs = {}
    for label, path, index in (("coproc", "/arm-io/dcp", 0), ("iop-vbar", "/arm-io/dcp", 1),
                               ("disp-0", "/arm-io/disp0", 0), ("disp-1", "/arm-io/disp0", 1),
                               ("disp-2", "/arm-io/disp0", 2), ("disp-3", "/arm-io/disp0", 3),
                               ("disp-4", "/arm-io/disp0", 4)):
        trail = find(root, path)
        regs[label] = get_reg(trail, index) if trail else None
        out.fact("%s (%s reg[%d])" % (label, path.rsplit("/", 1)[1], index), hexpair(regs[label]))
    darts = {}
    for path, streams in (("/arm-io/dart-dcp", (23,)), ("/arm-io/dart-disp0", (0, 16))):
        trail = find(root, path)
        if trail is None:
            out.fact(path, "missing")
            continue
        base = get_reg(trail, 0)
        vm_base, vm_size = u64(trail[-1].props.get("vm-base")), u64(trail[-1].props.get("vm-size"))
        roots = ["l1-tt-%d %s" % (s, "present" if trail[-1].props.get("l1-tt-%d" % s) else "MISSING") for s in streams]
        darts[path] = (base, vm_base, vm_size)
        out.fact(path, "%s, vm-base %s vm-size %s, %s" % (
            hexpair(base), hex(vm_base) if vm_base is not None else "missing",
            hex(vm_size) if vm_size is not None else "missing", ", ".join(roots)))
    dcp_trail = find(root, "/arm-io/dcp")
    dcp_irqs = u32s(dcp_trail[-1].props.get("interrupts", b"")) if dcp_trail else []
    out.fact("dcp interrupts (first four)", dcp_irqs[:4] if dcp_irqs else "missing")
    vram = find(root, "/vram")
    out.fact("/vram", hexpair(get_reg(vram, 0)) if vram else "missing")

    print("== 3. panel")
    backlight = find(root, "/backlight-override")
    if backlight and backlight[-1].props.get("user-accessible-max-nits"):
        nits = u32s(backlight[-1].props["user-accessible-max-nits"])[0]
        out.fact("user-accessible-max-nits", "%d (16.16: %d nits)" % (nits, nits >> 16))
    else:
        out.fact("user-accessible-max-nits", "missing: the loader refuses the hand-off without it")
    product = find(root, "/product")
    if product:
        out.fact("artwork-display-gamut", text(product[-1].props.get("artwork-display-gamut")) or "missing")
    panels = [n for n in ([root.child("panel")] + ([product[-1].child("panel")] if product else [])) if n]
    if not panels:
        out.fact("panel node", "none (the kernel then uses the tree's width-mm and height-mm)")
    for node in panels:
        for name in ("width-mm", "height-mm"):
            value = node.props.get(name)
            out.fact("panel %s" % name, u32s(value)[0] if value and len(value) == 4 else "not in the ADT")
        out.fact("panel property names", ", ".join(sorted(node.props)))

    print("== 4. GPU")
    sgx = find(root, "/arm-io/sgx")
    if sgx is None:
        out.fact("/arm-io/sgx", "missing")
    else:
        out.fact("sgx reg[0]", hexpair(get_reg(sgx, 0)))
        for name in ("gpu-region-base", "gpu-region-size", "gfx-shared-region-base", "gfx-shared-region-size",
                     "gfx-shared-l2-region-base", "gfx-shared-l2-region-size", "gfx-handoff-base",
                     "gfx-handoff-size", "gfx-data-base", "gfx1-data-shared-ro-base", "gfx1-data-shared-ro-size"):
            value = u64(sgx[-1].props.get(name))
            out.fact(name, hex(value) if value else "MISSING: the loader leaves the GPU off")
    for name in ("gfx-asc", "gfx1-asc"):
        trail = find(root, "/arm-io/" + name)
        out.fact("%s reg[0], reg[1]" % name, "%s; %s" % (hexpair(get_reg(trail, 0)), hexpair(get_reg(trail, 1)))
                 if trail else "missing")
        if trail:
            out.fact("%s interrupts" % name, u32s(trail[-1].props.get("interrupts", b"")))

    if dtb is None:
        print("== tree comparison skipped (no --dtb)")
        return
    print("== 5. the K114s tree against this ADT (what the loader compares at boot)")
    nodes = parse_fdt(dtb)
    aliases = {k: v.split(b"\0", 1)[0].decode() for k, v in nodes.get("/aliases", {}).items()}
    dcp = aliases.get("dcp")
    if dcp and dcp in nodes:
        names = nodes[dcp].get("reg-names", b"").decode().rstrip("\0").split("\0")
        dreg = fdt_reg(nodes, dcp)
        for i, label in enumerate(("coproc", "iop-vbar", "disp-0", "disp-1", "disp-2", "disp-3", "disp-4")):
            have = dreg[names.index(label)] if label in names and names.index(label) < len(dreg) else None
            want = regs.get(label)
            # the loader: same address; the tree's size not above the ADT's, and equal except for coproc
            ok = bool(have and want and have[0] == want[0] and have[1] <= want[1] and (i == 0 or have[1] == want[1]))
            out.check(ok, "dcp %s: tree %s, ADT %s" % (label, hexpair(have), hexpair(want)))
        by_phandle = {fdt_cells(p["phandle"])[0]: n for n, p in nodes.items() if "phandle" in p}
        disp = aliases.get("disp0")
        for user, sid, adt_dart in ((dcp, 23, "/arm-io/dart-dcp"), (disp, 0, "/arm-io/dart-disp0"),
                                    (dcp + "/piodma", 16, "/arm-io/dart-disp0")):
            io = fdt_cells(nodes.get(user, {}).get("iommus"))
            dart = by_phandle.get(io[0]) if len(io) == 2 else None
            want = darts.get(adt_dart)
            have_reg = fdt_reg(nodes, dart)[0][0] if dart and fdt_reg(nodes, dart) else None
            window = fdt_cells(nodes.get(dart, {}).get("apple,dma-range")) if dart else []
            have_window = (window[0] << 32 | window[1], window[2] << 32 | window[3]) if len(window) == 4 else None
            ok = bool(want and want[0] and len(io) == 2 and io[1] == sid and have_reg == want[0][0]
                      and have_window == (want[1], want[2]))
            out.check(ok, "%s stream %d on %s: tree DART at %s window %s" % (
                user, sid, adt_dart, hex(have_reg) if have_reg else "missing", have_window and tuple(map(hex, have_window))))
        mbox = by_phandle.get((fdt_cells(nodes[dcp].get("mboxes")) or [0])[0])
        coproc = regs.get("coproc")
        out.check(bool(mbox and coproc and fdt_reg(nodes, mbox) and fdt_reg(nodes, mbox)[0][0] == coproc[0] + 0x8000),
                  "dcp mailbox at coproc + 0x8000")
        # The loader checks the mailbox's register but not its interrupts, so a wrong number here would
        # only show as a DCP that never answers. The ADT lists the ASC's four mailbox interrupts first,
        # in the order the GPU mailboxes show (gfx-asc above): [send-not-empty, send-empty,
        # recv-not-empty, recv-empty]. The tree names each one; compare by name.
        names = strs_of(nodes.get(mbox, {}).get("interrupt-names")) if mbox else []
        tree = fdt_cells(nodes.get(mbox, {}).get("interrupts")) if mbox else []
        tree_by_name = {n: tree[4 * i + 2] for i, n in enumerate(names) if 4 * i + 3 < len(tree)} \
            if len(tree) == 4 * len(names) else {}
        adt_by_name = dict(zip(("send-not-empty", "send-empty", "recv-not-empty", "recv-empty"), dcp_irqs[:4])) \
            if len(dcp_irqs) >= 4 else {}
        ok = bool(adt_by_name) and len(tree_by_name) == 4 and tree_by_name == adt_by_name
        out.check(ok, "dcp mailbox interrupts: tree %s, ADT %s" % (
            ", ".join("%s %s" % (n, tree_by_name[n]) for n in sorted(tree_by_name)) or "missing",
            ", ".join("%s %s" % (n, adt_by_name[n]) for n in sorted(adt_by_name)) or "missing"))
    else:
        print("  the tree has no dcp alias: no panel hand-off is described")
    gpu = aliases.get("gpu")
    if gpu and gpu in nodes and sgx:
        want = get_reg(sgx, 0)
        have = fdt_reg(nodes, gpu)[0] if fdt_reg(nodes, gpu) else None
        out.check(bool(want and have and have[0] == want[0] and have[1] <= want[1]),
                  "gpu reg: tree %s, ADT sgx reg[0] %s" % (hexpair(have), hexpair(want)))
        for name, node in (("gfx-asc", "/soc/mailbox@2302600000"), ("gfx1-asc", "/soc/mailbox@2302e00000")):
            trail = find(root, "/arm-io/" + name)
            adt_regs = (get_reg(trail, 0), get_reg(trail, 1)) if trail else (None, None)
            tree_regs = fdt_reg(nodes, node)
            ok = bool(len(tree_regs) == 2 and adt_regs[0] and adt_regs[1] and tree_regs[0][0] == adt_regs[0][0]
                      and tree_regs[1][0] == adt_regs[1][0])
            out.check(ok, "%s: tree %s, ADT %s; %s" % (name, [hexpair(r) for r in tree_regs], hexpair(adt_regs[0]),
                                                       hexpair(adt_regs[1])))
            irqs = u32s(trail[-1].props.get("interrupts", b"")) if trail else []
            tree_irqs = fdt_cells(nodes.get(node, {}).get("interrupts"))
            # ADT order: [send-not-empty?, send-empty, recv-not-empty, recv-empty?]; the tree takes the 2nd and 3rd
            ok = len(irqs) == 4 and len(tree_irqs) == 8 and tree_irqs[2] == irqs[1] and tree_irqs[6] == irqs[2]
            out.check(ok, "%s interrupts: tree uses %s, ADT lists %s" % (
                name, [tree_irqs[2], tree_irqs[6]] if len(tree_irqs) == 8 else tree_irqs, irqs))
    elif gpu:
        out.check(False, "the tree describes the GPU but the ADT has no /arm-io/sgx")
    else:
        print("  the tree has no gpu alias: no GPU hand-off is described")


def find_adt_device():
    try:
        for line in open("/proc/mtd"):
            if '"adt"' in line:
                return "/dev/%sro" % line.split(":", 1)[0]
    except OSError:
        pass
    return None


def main(argv):
    args = {"--dtb": None, "--adt": None, "--names": None}
    while argv:
        key = argv.pop(0)
        if key in args and argv:
            args[key] = argv.pop(0)
        else:
            print(__doc__)
            return 2
    source = args["--adt"] or find_adt_device()
    if source is None:
        print('no MTD device named "adt" in /proc/mtd; give the ADT with --adt FILE')
        return 2
    try:
        blob = open(source, "rb").read()
    except PermissionError:
        print("cannot read %s: run this with sudo" % source)
        return 2
    dtb = open(args["--dtb"], "rb").read() if args["--dtb"] else None
    print("ADT from %s (%d bytes)" % (source, len(blob)))
    try:
        root, _ = parse_adt(blob)
    except (ValueError, struct.error) as err:
        # still answer question 1 from the raw bytes
        print("could not parse the ADT (%s). Known image UUIDs found in the raw bytes:" % err)
        seen = sorted(set(m.group().decode() for m in UUID.finditer(blob)) & set(PINNED))
        for uuid in seen:
            print("  %s  %s" % (uuid, PINNED[uuid]))
        if not seen:
            print("  none")
        return 1
    if args["--names"]:
        trail = find(root, args["--names"])
        if trail is None:
            print("no node %s" % args["--names"])
            return 1
        for name, value in sorted(trail[-1].props.items()):
            print("  %-40s %d bytes" % (name, len(value)))
        print("  children: %s" % ", ".join(c.name for c in trail[-1].children))
        return 0
    out = Report()
    report(root, dtb, out)
    print("== result: %s" % ("%d comparison(s) FAILED: do not stage this tree" % out.failed if out.failed
                             else "no comparison failed" if dtb else "facts only"))
    return 1 if out.failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
