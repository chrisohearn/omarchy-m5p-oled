#!/usr/bin/env python3
"""Read the speaker facts that protection depends on from the running Mac's Apple device tree.

    sudo python3 -I tests/k114s-adt-speaker-facts.py [--adt FILE] [--names]
    python3 -I tests/k114s-adt-speaker-facts.py --selftest

Read-only. The loader keeps the Apple device tree (ADT) of this boot in memory and Linux shows it
as the MTD device named "adt" (see /proc/mtd); only root can read it, so this needs sudo. Nothing
is written anywhere and nothing is sent anywhere.

It prints what identifies the speaker hardware and how macOS selects its tuning: the acoustic ID,
the amplifier chips, their buses, addresses and order, the pins, the speaker IDs this model is
built with, and yes/no answers about the layout of the amplifier configuration. It never prints a
calibration or tuning payload (the per-unit speaker record, the brownout block, the amplifier
rows) or a serial number: those are reported by name and length only. Do not publish the ADT
itself.

What it answers, for docs/r3-audio-protection.md:
  1. Which tuning does macOS use on this Mac (acoustic-id -> /System/Library/Audio/Tunings/AID<n>)?
  2. Are the amplifiers the ones the K116s tree describes (six SN012776, same addresses, same
     group order, same row layout: receive slot = index, one level, V sense at 4N, I at 4N+2)?
  3. Does this unit carry the per-unit speaker record, and which speaker IDs are valid?

--names also lists every property name and size of the nodes it reads (no values).
"""
import struct
import sys

AMP_COMPAT = "audio-control,sn012776"
# The level the K116s tree documents for its amplifiers (aurora-silicon/linux t6050-k116s.dts:
# "Each amp's operating level (AMP_LEVEL 15 here) is its row of the ADT speaker-config").
K116S_DOCUMENTED_LEVEL = 15
ROW = 4  # speaker-config: receive slot, level, V sense slot, I sense slot (aura src/kboot_audio.c)


class Node:
    def __init__(self, name, props, children):
        self.name, self.props, self.children = name, props, children


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


def walk(node, path=None):
    p = "" if path is None else path + "/" + node.name
    yield p or "/", node
    for c in node.children:
        yield from walk(c, p)


def strs(v):
    return [s.decode("ascii", "replace") for s in v.rstrip(b"\0").split(b"\0")]


def u32s(v):
    return list(struct.unpack("<%dI" % (len(v) // 4), v[:len(v) // 4 * 4]))


def adt_path(proc="/proc/mtd"):
    with open(proc) as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 4 and parts[3].strip('"') == "adt":
                return "/dev/%sro" % parts[0].rstrip(":")
    raise SystemExit("no MTD device named adt in /proc/mtd: this loader does not expose the ADT")


def gpio(v):
    w = u32s(v)
    return "pin %d" % w[2] if len(w) == 4 else "unreadable"


def report(root, names=False, out=print):
    """-> the number of answers that are not the expected ones."""
    nodes = dict(walk(root))
    by_phandle = {}
    for path, n in nodes.items():
        ph = n.props.get("AAPL,phandle", b"")
        if len(ph) == 4:
            by_phandle[u32s(ph)[0]] = (path, n)
    odd = 0

    out("target-type %s, model %s" % (strs(root.props.get("target-type", b"?"))[0],
                                      strs(root.props.get("model", b"?"))[0]))
    audio = nodes.get("/product/audio")
    if audio is None or len(audio.props.get("acoustic-id", b"")) != 4:
        out("NO /product/audio acoustic-id: the tuning cannot be selected")
        return 1
    aid = u32s(audio.props["acoustic-id"])[0]
    out("acoustic-id %d: macOS uses /System/Library/Audio/Tunings/AID%d" % (aid, aid))
    spts = audio.props.get("speaker-thiele-small")
    out("per-unit speaker record (speaker-thiele-small): %s"
        % ("present, %d bytes (not shown)" % len(spts) if spts else "ABSENT"))

    groups = [(p, n) for p, n in nodes.items()
              if AMP_COMPAT in strs(n.props.get("compatible", b"")) and "speaker-config" in n.props]
    out("amplifier groups (a node with speaker-config): %d" % len(groups))
    if len(groups) != 1:
        return odd + 1
    gpath, g = groups[0]
    amps = [(gpath, g)]
    k = 1
    while "speaker%d" % k in g.props:
        ph = u32s(g.props["speaker%d" % k])[0]
        if ph not in by_phandle:
            out("speaker%d names no node" % k)
            return odd + 1
        amps.append(by_phandle[ph])
        k += 1
    out("amplifiers in group order (the order of macOS's protection channels): %d" % len(amps))
    for i, (p, n) in enumerate(amps):
        out("  %d  %-45s  0x%02x  %s" % (i, p, u32s(n.props["reg"])[0], " ".join(strs(n.props["compatible"]))))
        if AMP_COMPAT not in strs(n.props["compatible"]):
            odd += 1

    rows = g.props["speaker-config"]
    n = len(amps)
    ok_len = len(rows) == ROW * n
    out("speaker-config: %d bytes for %d amplifiers: %s" % (len(rows), n, "one 4-byte row each" if ok_len else "UNEXPECTED"))
    if ok_len:
        r = [rows[i * ROW:(i + 1) * ROW] for i in range(n)]
        levels = {x[1] & 0x1f for x in r}
        checks = [
            ("receive slot = group index", all(x[0] == i for i, x in enumerate(r))),
            ("one level for every amplifier", len(levels) == 1),
            ("the level is the one the K116s tree documents", levels == {K116S_DOCUMENTED_LEVEL}),
            ("V sense slot 4N, I sense slot 4N+2", all(x[2] == 4 * i and x[3] == 4 * i + 2 for i, x in enumerate(r))),
        ]
        for text, ok in checks:
            out("  %-48s %s" % (text, "yes" if ok else "NO"))
            odd += not ok
    else:
        odd += 1
    zd = g.props.get("amp-tx-zd-config", b"")
    out("amp-tx-zd-config: %d bytes (%s)" % (len(zd), "one 8-byte row each" if len(zd) == 8 * n else "UNEXPECTED"))
    odd += len(zd) != 8 * n
    for name in ("bop-config", "amp-dcblocker-config"):
        out("%s: %s" % (name, "%d bytes (not shown)" % len(g.props[name]) if name in g.props else "ABSENT"))

    find = u32s(g.props.get("find-speaker-id", b"\0\0\0\0"))[0]
    out("find-speaker-id %d; valid-speaker-ids %s" % (find, u32s(g.props.get("valid-speaker-ids", b""))))
    for name, what in (("function-reset", "shared shutdown line"), ("function-speaker-id0", "speaker ID bit 0"),
                       ("function-speaker-id1", "speaker ID bit 1")):
        if name in g.props:
            out("%s (%s): %s" % (name, what, gpio(g.props[name])))
    if len(g.props.get("interrupts", b"")) >= 4:
        out("fault interrupt: pin %d" % u32s(g.props["interrupts"])[0])
    if names:
        for p, node in [(gpath, g), ("/product/audio", audio)]:
            out("property names of %s:" % p)
            for key in sorted(node.props):
                out("  %s (%d)" % (key, len(node.props[key])))
    return odd


def prop(name, value):
    return name.encode().ljust(32, b"\0") + struct.pack("<I", len(value)) + value + b"\0" * (-len(value) % 4)


def node(name, props, children=()):
    props = [("name", name.encode() + b"\0")] + list(props)
    return struct.pack("<II", len(props), len(children)) + b"".join(prop(k, v) for k, v in props) + b"".join(children)


def made_up_adt(level=15, swap=False, spts=True):
    """A made-up ADT with the K116s layout; nothing in it comes from a Mac."""
    u = lambda *w: struct.pack("<%dI" % len(w), *w)  # noqa: E731
    compat = AMP_COMPAT.encode() + b"\0"
    rows = b"".join(bytes([i, level, 4 * i + (2 if swap else 0), 4 * i + (0 if swap else 2)]) for i in range(6))
    others = [("audio-speaker-right-woofer-1", 0x3B, 0x52), ("audio-speaker-left-woofer-2", 0x39, 0x4D),
              ("audio-speaker-right-woofer-2", 0x3C, 0x53), ("audio-speaker-left-tweeter", 0x3A, 0x4E),
              ("audio-speaker-right-tweeter", 0x3D, 0x54)]
    first = node("audio-speaker", [("compatible", compat), ("reg", u(0x38, 0, 0, 0)), ("AAPL,phandle", u(0x4C)),
                                   ("speaker-config", rows), ("amp-tx-zd-config", bytes(48)),
                                   ("bop-config", bytes(24)), ("amp-dcblocker-config", u(0)),
                                   ("find-speaker-id", u(1)), ("valid-speaker-ids", u(0, 3)),
                                   ("function-reset", u(1, 0x4750494F, 107, 0)), ("interrupts", u(106, 1))]
                 + [("speaker%d" % (i + 1), u(ph)) for i, (_, _, ph) in enumerate(others)])
    amp = {nm: node(nm, [("compatible", compat), ("reg", u(addr, 0, 0, 0)), ("AAPL,phandle", u(ph))])
           for nm, addr, ph in others}
    i2c1 = node("i2c1", [], [first, amp["audio-speaker-left-woofer-2"], amp["audio-speaker-left-tweeter"]])
    i2c3 = node("i2c3", [], [amp["audio-speaker-right-woofer-1"], amp["audio-speaker-right-woofer-2"],
                             amp["audio-speaker-right-tweeter"]])
    audio = node("audio", [("acoustic-id", u(49))] + ([("speaker-thiele-small", bytes(138))] if spts else []))
    return node("device-tree", [("target-type", b"K114s\0"), ("model", b"Mac17,13\0")],
                [node("arm-io", [], [i2c1, i2c3]), node("product", [], [audio])])


def selftest():
    cases = [("the K116s layout", {}, 0), ("another level", {"level": 12}, 1), ("V and I swapped", {"swap": True}, 1)]
    bad = 0
    for text, kw, want in cases:
        lines = []
        got = report(parse_adt(made_up_adt(**kw))[0], out=lines.append)
        ok = got == want and any("0x3d" in line for line in lines) and not any("\\x" in line for line in lines)
        print("%s  %s: %d unexpected answer(s), want %d" % ("ok  " if ok else "FAIL", text, got, want))
        bad += not ok
    lines = []
    report(parse_adt(made_up_adt(spts=False))[0], out=lines.append)
    ok = any("ABSENT" in line for line in lines)
    print("%s  a unit without the speaker record is reported" % ("ok  " if ok else "FAIL"))
    return bad + (not ok)


def main(argv):
    if "--selftest" in argv:
        return 1 if selftest() else 0
    path = argv[argv.index("--adt") + 1] if "--adt" in argv else adt_path()
    try:
        with open(path, "rb") as f:
            blob = f.read(8 << 20)
    except PermissionError:
        raise SystemExit("%s: only root can read it (sudo)" % path)
    odd = report(parse_adt(blob)[0], names="--names" in argv)
    print("%d answer(s) differ from the K116s layout" % odd if odd else "every answer matches the K116s layout")
    return 1 if odd else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
