#!/usr/bin/env python3
"""Replica test of tests/k114s-adt-display-facts.py.

    python3 tests/test-adt-display-facts.py t6050-k114s-r3.dtb

Builds a synthetic Apple device tree (ADT) in the m1n1 wire format whose display and GPU nodes
are derived from the given K114s tree (addresses moved back through an arm-io "ranges" of
+0x2_0000_0000, as on the real machines), then runs the reader on it and on broken variants.
The synthetic ADT also carries a serial-number and a MAC-address property, and the test fails if
the reader prints either. No Apple data is used: this proves the reader's parsing, translation
and comparisons, not anything about the real machine.
"""
import importlib.util
import io
import os
import re
import struct
import sys
import tempfile
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("facts", os.path.join(HERE, "k114s-adt-display-facts.py"))
facts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(facts)

ARM_IO_OFFSET = 0x2_0000_0000
SECRET_SERIAL = b"ZZTESTSERIAL0\0"
SECRET_MAC = bytes([0x02, 0x11, 0x22, 0x33, 0x44, 0x55])


def prop(name, value):
    return name.encode().ljust(32, b"\0") + struct.pack("<I", len(value)) + value + b"\0" * (-len(value) % 4)


def node(name, props=(), children=()):
    props = [("name", name.encode() + b"\0")] + list(props)
    return struct.pack("<II", len(props), len(children)) + b"".join(prop(k, v) for k, v in props) + b"".join(children)


def cells(*values):
    return struct.pack("<%dI" % len(values), *values)


def reg(*pairs):
    """arm-io children: 2 address cells, 2 size cells, bus addresses."""
    return b"".join(struct.pack("<QQ", addr - ARM_IO_OFFSET, size) for addr, size in pairs)


def build(dtb, uuid=facts.R3_IMAGE, vm_size=0x300_0000_0000, drop_nits=False):
    nodes = facts.parse_fdt(dtb)
    aliases = {k: v.split(b"\0", 1)[0].decode() for k, v in nodes["/aliases"].items()}
    dcp = aliases["dcp"]
    names = nodes[dcp]["reg-names"].decode().rstrip("\0").split("\0")
    dreg = dict(zip(names, facts.fdt_reg(nodes, dcp)))
    by_phandle = {facts.fdt_cells(p["phandle"])[0]: n for n, p in nodes.items() if "phandle" in p}
    dart_dcp = facts.fdt_reg(nodes, by_phandle[facts.fdt_cells(nodes[dcp]["iommus"])[0]])[0]
    dart_disp = facts.fdt_reg(nodes, by_phandle[facts.fdt_cells(nodes[aliases["disp0"]]["iommus"])[0]])[0]
    gpu = facts.fdt_reg(nodes, aliases["gpu"])[0]
    mb = [facts.fdt_reg(nodes, n) for n in ("/soc/mailbox@2302600000", "/soc/mailbox@2302e00000")]
    irq = [facts.fdt_cells(nodes[n]["interrupts"]) for n in ("/soc/mailbox@2302600000", "/soc/mailbox@2302e00000")]
    coproc = dreg["coproc"]

    def dart(name, base, streams):
        return node(name, [("reg", reg(base)), ("vm-base", struct.pack("<Q", 0x100_0000_0000)),
                           ("vm-size", struct.pack("<Q", vm_size))] +
                    [("l1-tt-%d" % s, struct.pack("<QQ", 0x10000_0000 + s * 0x4000, 1)) for s in streams])

    def nub(name, image):
        return node("iop-%s-nub" % name, [("uuid", image.encode() + b"\0"), ("running", cells(1)),
                                          ("segment-ranges", b"\0" * 64)])

    sgx_props = [("reg", reg((gpu[0], gpu[1])))] + [
        (n, struct.pack("<Q", 0x10f_fff2_0000 + i * 0x4000)) for i, n in enumerate(
            ("gpu-region-base", "gpu-region-size", "gfx-shared-region-base", "gfx-shared-region-size",
             "gfx-shared-l2-region-base", "gfx-shared-l2-region-size", "gfx-handoff-base", "gfx-handoff-size",
             "gfx-data-base", "gfx1-data-shared-ro-base", "gfx1-data-shared-ro-size"))]
    arm_io = node("arm-io", [
        ("#address-cells", cells(2)), ("#size-cells", cells(2)),
        ("ranges", struct.pack("<QQQ", 0, ARM_IO_OFFSET, 0x100_0000_0000)),
    ], [
        node("dcp", [("reg", reg((coproc[0], 0x100000), dreg["iop-vbar"]))], [nub("dcp", uuid)]),
        node("disp0", [("reg", reg(*(dreg["disp-%d" % i] for i in range(5)))), ("clock-ids", cells(361, 458))]),
        node("dcpext0", [("reg", reg((0x2_b2e0_0000, 0x4000)))], [nub("dcpext0", uuid)]),
        dart("dart-dcp", dart_dcp, (23,)),
        dart("dart-disp0", dart_disp, (0, 16)),
        node("sgx", sgx_props),
        node("gfx-asc", [("reg", reg(mb[0][0], mb[0][1])), ("interrupts", cells(irq[0][2] + 1, irq[0][2], irq[0][6], irq[0][6] - 1))]),
        node("gfx1-asc", [("reg", reg(mb[1][0], mb[1][1])), ("interrupts", cells(irq[1][2] + 1, irq[1][2], irq[1][6], irq[1][6] - 1))]),
        node("wlan", [("local-mac-address", SECRET_MAC)]),
    ])
    children = [
        node("chosen", [("board-id", cells(0x14))]),
        arm_io,
        node("vram", [("reg", struct.pack("<QQ", 0x10f_d000_0000, 0x400_0000))]),
        node("product", [("artwork-display-gamut", b"P3\0"), ("raw-panel-serial-number", SECRET_SERIAL)]),
    ]
    if not drop_nits:
        children.append(node("backlight-override", [("user-accessible-max-nits", cells(1000 << 16))]))
    return node("device-tree", [("compatible", b"K114sAP\0MacBookPro\0"), ("#address-cells", cells(2)),
                                ("#size-cells", cells(2)), ("serial-number", SECRET_SERIAL)], children)


def run(adt, dtb_path, extra=()):
    with tempfile.NamedTemporaryFile(suffix=".adt") as handle:
        handle.write(adt)
        handle.flush()
        out = io.StringIO()
        with redirect_stdout(out):
            code = facts.main(["--adt", handle.name] + (["--dtb", dtb_path] if dtb_path else []) + list(extra))
    return code, out.getvalue()


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    dtb_path = sys.argv[1]
    dtb = open(dtb_path, "rb").read()
    failures = []

    def expect(name, cond, output):
        print("%s  %s" % ("ok  " if cond else "FAIL", name))
        if not cond:
            failures.append(name)
            print(output)

    code, text = run(build(dtb), dtb_path)
    expect("matching ADT: every comparison passes", code == 0 and "FAIL" not in text and text.count("  PASS  ") == 16, text)
    expect("matching ADT: the K116s image is reported as admitted", "the r3 loader (aura + pull request 226) admits it" in text, text)
    expect("matching ADT: translated through the arm-io ranges", re.search(r"coproc \(dcp reg\[0\]\)\s+0x48ae00000 \+", text) is not None, text)
    expect("matching ADT: brightness scale read", "1000 nits" in text, text)
    for secret, what in ((SECRET_SERIAL.rstrip(b"\0").decode(), "serial number"), ("02:11:22", "MAC address"),
                         ("021122334455", "MAC address (hex)")):
        expect("no %s in the output" % what, secret.lower() not in text.lower(), text)

    code, text = run(build(dtb, uuid="11111111-2222-3333-4444-555555555555"), dtb_path)
    expect("unknown image: reported as refused", "REFUSES the panel hand-off" in text and "NOT pinned" in text, text)

    code, text = run(build(dtb, uuid="C51FB0C8-C45D-39B0-85BC-520E600FC950"), dtb_path)
    expect("J714s image: reported as another board's", "another board's image" in text, text)

    code, text = run(build(dtb, vm_size=0x10_0000_0000), dtb_path)
    expect("different DART window: comparison fails, exit 1", code == 1 and text.count("  FAIL  ") == 3, text)

    code, text = run(build(dtb, drop_nits=True), dtb_path)
    expect("no brightness scale: said so", "the loader refuses the hand-off without it" in text, text)

    code, text = run(build(dtb), None)
    expect("without --dtb: facts only, exit 0", code == 0 and "tree comparison skipped" in text, text)

    code, text = run(build(dtb), None, ["--names", "/product"])
    expect("--names lists names and sizes only", "raw-panel-serial-number" in text and "ZZTEST" not in text, text)

    broken = b"\xff" * 64 + facts.R3_IMAGE.encode() + b"\0" * 16
    code, text = run(broken, dtb_path)
    expect("unparsable ADT: falls back to a UUID scan", code == 1 and facts.R3_IMAGE in text, text)

    print("ADT reader replica test:", "FAILED" if failures else "passed", "(%d checks)" % 14)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
