#!/usr/bin/python3 -I
# SPDX-License-Identifier: MIT
"""k114s-adt-sound-facts.py: does this Mac's Apple device tree (ADT) say what the sound trees assume?

dts/t6050-k114s-sound.dtsi was ported from the K116s tree, and its comments carry the K116s
ADT's addresses, pins, interrupts and stream IDs. This reads the K114s ADT and checks each one,
so "the K114s ADT has to confirm each one" (docs/r3-sound.md) is a command and not a table to
compare by eye.

    sudo python3 -I tests/k114s-adt-sound-facts.py            the "adt" MTD partition (root only)
    python3 -I tests/k114s-adt-sound-facts.py --adt FILE      a copy of it
    python3 -I tests/k114s-adt-sound-facts.py --self-test     the checks themselves, on a made-up ADT

Every expected value below is already public in the K116s tree of aurora-silicon/linux #1648
or in dts/t6050-k114s-sound.dtsi. Nothing of the ADT is printed except, on a mismatch, the
address, pin or interrupt number that differs. The amplifiers' levels are never printed.

Two groups. "jack and microphones" is what the r3 sound tree uses. "speakers" is what a later
speaker tree would use (and the pins the r3 tree must keep reserved); it is checked so that
the facts are on record, not because anything here enables the speakers.

Exit 0: every fact holds. Exit 1: at least one does not. Exit 2: the ADT could not be read.
"""
import argparse
import struct
import sys

BOARD_ID = 0x14
GPIO_FOURCC = 0x4750494F  # 'GPIO'
MAX_ADT = 8 << 20


class AdtError(Exception):
    pass


def parse(data, off=0, depth=0):
    if depth > 32 or off + 8 > len(data):
        raise AdtError("malformed ADT")
    nprops, nchildren = struct.unpack_from("<II", data, off)
    if nprops > 4096 or nchildren > 4096:
        raise AdtError("malformed ADT node")
    off += 8
    props = {}
    for _ in range(nprops):
        if off + 36 > len(data):
            raise AdtError("truncated ADT property")
        name = data[off:off + 32].split(b"\0", 1)[0].decode("ascii", "replace")
        size = struct.unpack_from("<I", data, off + 32)[0] & 0x7FFFFFFF
        off += 36
        if off + size > len(data):
            raise AdtError("truncated ADT value")
        props[name] = data[off:off + size]
        off += (size + 3) & ~3
    children = []
    for _ in range(nchildren):
        child, off = parse(data, off, depth + 1)
        children.append(child)
    name = props.get("name", b"").split(b"\0", 1)[0].decode("ascii", "replace")
    return {"name": name, "props": props, "children": children}, off


def mtd_path(name="adt", proc="/proc/mtd"):
    try:
        with open(proc) as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 4 and parts[3].strip('"') == name:
                    return "/dev/" + parts[0].rstrip(":") + "ro"
    except OSError:
        pass
    return None


def load(path):
    path = path or mtd_path()
    if not path:
        raise AdtError('the boot chain exposes no ADT (no "adt" partition in /proc/mtd); use --adt FILE')
    try:
        with open(path, "rb") as f:
            data = f.read(MAX_ADT)
    except OSError as e:
        raise AdtError(f"{path}: {e.strerror} (the partition is readable by root only)")
    root, _ = parse(data)
    return root


def u32s(v):
    return list(struct.unpack("<%dI" % (len(v) // 4), v[:len(v) // 4 * 4])) if v else []


def u64(v, i=0):
    return struct.unpack_from("<Q", v, 8 * i)[0] if v and len(v) >= 8 * (i + 1) else None


def text(v):
    return v.split(b"\0", 1)[0].decode("ascii", "replace") if v else None


class Tree:
    def __init__(self, root):
        self.root = root
        self.by_phandle = {}
        self._index(root)
        arm_io = self.node("arm-io")
        cells = u32s(arm_io["props"].get("ranges", b"")) if arm_io else []
        # (child address, parent address, size), two cells each
        self.ranges = [(cells[i] | cells[i + 1] << 32, cells[i + 2] | cells[i + 3] << 32,
                        cells[i + 4] | cells[i + 5] << 32) for i in range(0, len(cells) - 5, 6)]

    def _index(self, node):
        ph = node["props"].get("AAPL,phandle")
        if ph and len(ph) == 4:
            self.by_phandle[struct.unpack("<I", ph)[0]] = node
        for c in node["children"]:
            self._index(c)

    def node(self, path):
        cur = self.root
        for part in path.split("/"):
            cur = next((c for c in cur["children"] if c["name"] == part), None)
            if cur is None:
                return None
        return cur

    def prop(self, path, name):
        n = self.node(path)
        return n["props"].get(name) if n else None

    def addr(self, path, index=0, translate=True):
        """The index-th reg address of @path, through /arm-io's ranges unless told not to."""
        a = u64(self.prop(path, "reg"), 2 * index)
        if a is None or not translate:
            return a
        for child, parent, size in self.ranges:
            if child <= a < child + size:
                return a - child + parent
        return a

    def size(self, path, index=0):
        return u64(self.prop(path, "reg"), 2 * index + 1)

    def function_gpio(self, path, name):
        """(controller node name, pin) of an ADT function-* GPIO property, or (None, None)."""
        w = u32s(self.prop(path, name))
        if len(w) < 3 or w[1] != GPIO_FOURCC:
            return None, None
        ctrl = self.by_phandle.get(w[0])
        return (ctrl["name"] if ctrl else None), w[2]

    def irq(self, path):
        """(interrupt parent node name, first interrupt number)."""
        w = u32s(self.prop(path, "interrupts"))
        parent = self.by_phandle.get((u32s(self.prop(path, "interrupt-parent")) or [None])[0])
        return (parent["name"] if parent else None), (w[0] if w else None)

    def children(self, path):
        n = self.node(path)
        return [c["name"] for c in n["children"]] if n else None

    def i2c_addr(self, path):
        return (u32s(self.prop(path, "reg")) or [None])[0]


AMP_GROUP = [  # ADT speaker-config (group) order: the K116s Speaker link's codec order
    ("i2c1/audio-speaker", 0x38), ("i2c3/audio-speaker-right-woofer-1", 0x3B),
    ("i2c1/audio-speaker-left-woofer-2", 0x39), ("i2c3/audio-speaker-right-woofer-2", 0x3C),
    ("i2c1/audio-speaker-left-tweeter", 0x3A), ("i2c3/audio-speaker-right-tweeter", 0x3D),
]


def hexs(v, small_hex=False):
    """Addresses in hex, pins and interrupts in decimal; I2C addresses (small_hex) in hex."""
    if isinstance(v, (list, tuple)):
        return "[" + ", ".join(hexs(x, small_hex) for x in v) + "]"
    if isinstance(v, bool):
        return "yes" if v else "no"
    if isinstance(v, int):
        return hex(v) if v >= 4096 or small_hex else str(v)
    return repr(v)


def facts(t):
    """[(group, what, expected, found)]. Expected values: the K116s tree / the sound fragment."""
    A = "arm-io/"
    J, S = "jack and microphones", "speakers (not enabled by the r3 tree)"
    out = []

    def fact(group, what, expected, found):
        out.append((group, what, expected, found))

    fact(J, "target-type", "K114s", text(t.root["props"].get("target-type")))
    fact(J, "/chosen board-id", BOARD_ID, (u32s(t.prop("chosen", "board-id")) or [None])[0])

    # the AP pin controller every pin below belongs to
    fact(J, "gpio0 address", 0x29C000000, t.addr(A + "gpio0"))
    fact(J, "gpio0 pin count", 221, (u32s(t.prop(A + "gpio0", "#gpio-pins")) or [None])[0])

    # jack codec: i2c2, 0x4b, reset AP pin 139, interrupt AP pin 134
    codec = A + "i2c2/audio-codec-output"
    fact(J, "i2c2 address", 0x505018000, t.addr(A + "i2c2"))
    fact(J, "i2c2 interrupt", 1377, t.irq(A + "i2c2")[1])
    fact(J, "i2c2 carries only the jack codec", ["audio-codec-output"], t.children(A + "i2c2"))
    fact(J, "jack codec compatible", "audio-control,cs42l84", text(t.prop(codec, "compatible")))
    fact(J, "jack codec I2C address", 0x4B, t.i2c_addr(codec))
    fact(J, "jack codec reset (controller, pin)", ("gpio0", 139), t.function_gpio(codec, "function-reset"))
    fact(J, "jack codec interrupt (controller, pin)", ("gpio0", 134), t.irq(codec))

    # the AOP, its mailboxes and DART
    fact(J, "aop ASC address", 0x290600000, t.addr(A + "aop", 0))
    fact(J, "aop SRAM window address", 0x290C00000, t.addr(A + "aop", 2))
    fact(J, "aop interrupts", [578, 579, 580, 581], sorted(u32s(t.prop(A + "aop", "interrupts"))))
    fact(J, "aop setup port address (untranslated)", 0x2D067C000,
         t.addr(A + "aop-exclave-mailbox", translate=False))
    fact(J, "dart-aop address", 0x290FC0000, t.addr(A + "dart-aop"))
    fact(J, "dart-aop interrupt", 616, t.irq(A + "dart-aop")[1])
    sid = u32s(t.prop(A + "dart-aop", "sid"))
    fact(J, "dart-aop AP streams include 0 (AOP) and 8 (admac-base-ns)", True, 0 in sid and 8 in sid)
    xsid = u32s(t.prop(A + "dart-aop", "exclave-sid"))
    fact(J, "dart-aop exclave streams include 1 (setup port) and 11 (leap-s)", True, 1 in xsid and 11 in xsid)
    fact(J, "dart-aop vm-base-11", 0x10040000000, u64(t.prop(A + "dart-aop", "vm-base-11")))
    fact(J, "dart-aop vm-size-11", 0xFFFF0000, u64(t.prop(A + "dart-aop", "vm-size-11")))

    # the ADMACs
    fact(J, "admac-base-ns address", 0x293800000, t.addr(A + "admac-base-ns"))
    fact(J, "admac-base-ns size", 0x34000, t.size(A + "admac-base-ns"))
    fact(J, "admac-base-ns interrupt", 637, t.irq(A + "admac-base-ns")[1])
    fact(J, "admac-base-ns TX/RX channels", (13, 13),
         ((u32s(t.prop(A + "admac-base-ns", "#dma-channels-tx")) or [None])[0],
          (u32s(t.prop(A + "admac-base-ns", "#dma-channels-rx")) or [None])[0]))
    fact(J, "admac-leap-s interrupt", 638, t.irq(A + "admac-leap-s")[1])
    fact(J, "admac-leap-s RX channels", 9, (u32s(t.prop(A + "admac-leap-s", "#dma-channels-rx")) or [None])[0])
    fact(J, "proxy ADMAC address (untranslated)", 0x2D3200000,
         t.addr(A + "admac-hp-mic-ec-proxy", translate=False))
    fact(J, "proxy ADMAC size", 0x34000, t.size(A + "admac-hp-mic-ec-proxy"))
    fact(J, "proxy ADMAC dma-channel", 0, (u32s(t.prop(A + "admac-hp-mic-ec-proxy", "dma-channel")) or [None])[0])

    # the firmware's streams (iop-audio-controller)
    C = A + "iop-audio-controller/"
    fact(J, "jack playback stream", "base-ns-adma-tx-2", text(t.prop(C + "audio-codec-output", "dma-provider-tx")))
    fact(J, "jack capture stream", "base-ns-adma-rx-2", text(t.prop(C + "audio-codec-input", "dma-provider-rx")))
    fact(J, "microphone stream", "leap-s-adma-rx-0", text(t.prop(C + "audio-hp-mic", "dma-provider-rx")))
    sel = t.prop(C + "audio-hp-mic/audio-hp-mic", "input-data-selectors") or b""
    fact(J, "microphones in the array", 3, len(sel) // 4)

    # the PMP the AOP's audio firmware needs
    fact(J, "pmp0 ASC address", 0x284E00000, t.addr(A + "pmp0", 0))
    fact(J, "pmp0 SRAM window address", 0x284500000, t.addr(A + "pmp0", 2))
    fact(J, "pmp0 has its firmware properties (iop-pmp0-nub)", True, t.node(A + "pmp0/iop-pmp0-nub") is not None)
    fact(J, "pmgr has pmc and pmc-pmgr", True,
         t.prop(A + "pmgr", "pmc") is not None and t.prop(A + "pmgr", "pmc-pmgr") is not None)

    # speakers: six SN012776 on i2c1 and i2c3, one shutdown line, one fault line, two ID straps
    lead = A + "i2c1/audio-speaker"
    fact(S, "i2c1 address", 0x505014000, t.addr(A + "i2c1"))
    fact(S, "i2c1 interrupt", 1376, t.irq(A + "i2c1")[1])
    fact(S, "i2c3 address", 0x50501C000, t.addr(A + "i2c3"))
    fact(S, "i2c3 interrupt", 1378, t.irq(A + "i2c3")[1])
    fact(S, "i2c1, i2c2 and i2c3 share one clock id", True,
         u32s(t.prop(A + "i2c1", "clock-ids")) == u32s(t.prop(A + "i2c2", "clock-ids"))
         == u32s(t.prop(A + "i2c3", "clock-ids")) != [])
    for path, addr in AMP_GROUP:
        fact(S, f"{path} I2C address", addr, t.i2c_addr(A + path))
        fact(S, f"{path} compatible", "audio-control,sn012776", text(t.prop(A + path, "compatible")))
    order = [t.i2c_addr(lead)]
    for k in range(1, 16):
        ph = u32s(t.prop(lead, f"speaker{k}"))
        if len(ph) != 1:
            break
        amp = t.by_phandle.get(ph[0])
        order.append((u32s(amp["props"].get("reg", b"")) or [None])[0] if amp else None)
    fact(S, "amp group order (I2C addresses)", [a for _, a in AMP_GROUP], order)
    fact(S, "amp shutdown line (controller, pin)", ("gpio0", 107), t.function_gpio(lead, "function-reset"))
    fact(S, "amp fault interrupt (controller, pin)", ("gpio0", 106), t.irq(lead))
    fact(S, "speaker ID strap 0 (controller, pin)", ("gpio0", 136), t.function_gpio(lead, "function-speaker-id0"))
    fact(S, "speaker ID strap 1 (controller, pin)", ("gpio0", 137), t.function_gpio(lead, "function-speaker-id1"))
    rows = t.prop(lead, "speaker-config") or b""
    fact(S, "speaker-config has one 4-byte row per amp", 4 * len(AMP_GROUP), len(rows))
    slots = [(rows[4 * n], rows[4 * n + 2], rows[4 * n + 3]) for n in range(len(rows) // 4)]
    fact(S, "speaker-config rows: (amp index, V slot 4N, I slot 4N+2)",
         [(n, 4 * n, 4 * n + 2) for n in range(len(AMP_GROUP))], slots)
    levels = {rows[4 * n + 1] & 0x1F for n in range(len(rows) // 4)}
    fact(S, "amp levels: one value for all amps, within the driver's range (not printed)", True,
         len(levels) == 1 and max(levels) <= 0x14)
    zd = t.prop(lead, "amp-tx-zd-config") or b""
    masks = [struct.unpack_from("<I", zd, 8 * n)[0] for n in range(min(2, len(zd) // 8))]
    fact(S, "amp-tx-zd-config rows 0 and 1 (sense idle masks)", [0xFFF0F0F0, 0xFF0F0F0F], masks)
    for name in ("bop-config", "amp-dcblocker-config"):
        fact(S, f"the group has {name} (the loader copies it; not printed)", True, bool(t.prop(lead, name)))
    fact(S, "speaker playback stream", "base-ns-adma-tx-0", text(t.prop(C + "audio-speaker", "dma-provider-tx")))
    fact(S, "speaker sense stream", "base-ns-adma-rx-0", text(t.prop(C + "audio-speaker", "dma-provider-rx")))
    spk = u32s(t.prop(C + "audio-speaker/audio-speaker", "reg"))
    fact(S, "speaker stream: playback slot mask, sense slot mask", (0x3F, 0xFFF),
         (spk[5], spk[6]) if len(spk) >= 7 else None)
    return out


def norm(v):
    return list(v) if isinstance(v, tuple) else v


def report(results, out=sys.stdout):
    bad = 0
    group = None
    for g, what, expected, found in results:
        if g != group:
            print(f"{g}:", file=out)
            group = g
        sh = "I2C address" in what
        if norm(expected) == norm(found):
            print(f"  ok    {what}: {hexs(expected, sh)}", file=out)
        else:
            bad += 1
            print(f"  FAIL  {what}: expected {hexs(expected, sh)}, the ADT says {hexs(found, sh)}", file=out)
    print(f"sound facts: {len(results) - bad} hold, {bad} do not", file=out)
    return bad


# ---- self-test: a made-up ADT with the expected structure, and one with a wrong pin -------------------------

def _prop(name, val):
    return name.encode().ljust(32, b"\0") + struct.pack("<I", len(val)) + val + b"\0" * (-len(val) % 4)


def _node(name, props=(), children=()):
    props = [("name", name.encode() + b"\0")] + list(props)
    return struct.pack("<II", len(props), len(children)) + b"".join(_prop(n, v) for n, v in props) + b"".join(children)


def _made_up(jack_reset_pin=139, sdz_pin=107):
    w = lambda *a: struct.pack("<%dI" % len(a), *a)
    q = lambda *a: struct.pack("<%dQ" % len(a), *a)
    s = lambda x: x.encode() + b"\0"
    gpio = lambda pin, ctl=1: w(10, GPIO_FOURCC, pin, ctl)
    amp = lambda name, ph, addr, extra=(): _node(name, [("AAPL,phandle", w(ph)), ("reg", w(addr, 0, 0, 0)),
                                                       ("compatible", s("audio-control,sn012776"))] + list(extra))
    # made-up level 7 for every amp: never a Mac's value
    rows = b"".join(bytes([n, 7, 4 * n, 4 * n + 2]) for n in range(6))
    lead = [("function-reset", gpio(sdz_pin)), ("interrupt-parent", w(10)), ("interrupts", w(106, 1)),
            ("function-speaker-id0", gpio(136)), ("function-speaker-id1", gpio(137)),
            ("speaker1", w(31)), ("speaker2", w(22)), ("speaker3", w(32)), ("speaker4", w(23)), ("speaker5", w(33)),
            ("speaker-config", rows), ("amp-tx-zd-config", w(0xFFF0F0F0, 0, 0xFF0F0F0F, 0) + bytes(32)),
            ("bop-config", b"\1\2"), ("amp-dcblocker-config", b"\1\2\3\4")]
    bus = lambda name, addr, irq, kids: _node(name, [("reg", q(addr, 0x4000)), ("interrupts", w(irq)),
                                                     ("clock-ids", w(4))], kids)
    stream = lambda name, **kw: _node(name, [(k.replace("_", "-"), s(v)) for k, v in kw.items()])
    arm_io = _node("arm-io", [("ranges", q(0, 0x200000000, 0x3C0000000))], [
        _node("gpio0", [("AAPL,phandle", w(10)), ("reg", q(0x9C000000, 0x44000)), ("#gpio-pins", w(221))]),
        bus("i2c1", 0x305014000, 1376, [amp("audio-speaker", 21, 0x38, lead),
                                        amp("audio-speaker-left-woofer-2", 22, 0x39),
                                        amp("audio-speaker-left-tweeter", 23, 0x3A)]),
        bus("i2c2", 0x305018000, 1377, [_node("audio-codec-output", [
            ("reg", w(0x4B, 0, 0, 0)), ("compatible", s("audio-control,cs42l84")),
            ("function-reset", gpio(jack_reset_pin)), ("interrupt-parent", w(10)), ("interrupts", w(134, 1))])]),
        bus("i2c3", 0x30501C000, 1378, [amp("audio-speaker-right-woofer-1", 31, 0x3B),
                                        amp("audio-speaker-right-woofer-2", 32, 0x3C),
                                        amp("audio-speaker-right-tweeter", 33, 0x3D)]),
        _node("aop", [("reg", q(0x90600000, 0x88000, 0x90650000, 0x4000, 0x90C00000, 0x2F0000)),
                      ("interrupts", w(579, 578, 581, 580))]),
        _node("aop-exclave-mailbox", [("reg", q(0x2D067C000, 0x4000))]),
        _node("dart-aop", [("reg", q(0x90FC0000, 0xC000)), ("interrupts", w(616)), ("sid", w(0, 16, 3, 8, 10)),
                           ("exclave-sid", w(1, 11, 9)), ("vm-base-11", q(0x10040000000)),
                           ("vm-size-11", q(0xFFFF0000))]),
        _node("admac-base-ns", [("reg", q(0x93800000, 0x34000)), ("interrupts", w(637)),
                                ("#dma-channels-tx", q(13)), ("#dma-channels-rx", q(13))]),
        _node("admac-leap-s", [("reg", q(0x93200000, 0x34000)), ("interrupts", w(638)), ("#dma-channels-rx", q(9))]),
        _node("admac-hp-mic-ec-proxy", [("reg", q(0x2D3200000, 0x34000)), ("dma-channel", w(0))]),
        _node("iop-audio-controller", [], [
            stream("audio-codec-output", dma_provider_tx="base-ns-adma-tx-2"),
            stream("audio-codec-input", dma_provider_rx="base-ns-adma-rx-2"),
            _node("audio-hp-mic", [("dma-provider-rx", s("leap-s-adma-rx-0"))],
                  [_node("audio-hp-mic", [("input-data-selectors", b"1imi2imi3imi")])]),
            _node("audio-speaker", [("dma-provider-tx", s("base-ns-adma-tx-0")),
                                    ("dma-provider-rx", s("base-ns-adma-rx-0"))],
                  [_node("audio-speaker", [("reg", w(0, 0, 0, 0, 0, 0x3F, 0xFFF, 0, 0))])]),
        ]),
        _node("pmp0", [("reg", q(0x84E00000, 0x88000, 0x84850000, 0x4000, 0x84500000, 0x100000))],
              [_node("iop-pmp0-nub")]),
        _node("pmgr", [("pmc", w(1)), ("pmc-pmgr", w(63))]),
    ])
    return _node("device-tree", [("target-type", s("K114s"))], [
        _node("chosen", [("board-id", w(BOARD_ID))]), arm_io])


def self_test():
    import io
    ok = True

    def check(what, cond):
        nonlocal ok
        print(("ok   " if cond else "FAIL ") + what)
        ok = ok and cond

    good = facts(Tree(parse(_made_up())[0]))
    sink = io.StringIO()
    check("a made-up ADT with the expected structure passes every fact", report(good, sink) == 0)
    if not ok:
        print(sink.getvalue())
    for what, kw, needle in (("a jack reset on another pin", {"jack_reset_pin": 138}, "jack codec reset"),
                             ("an amp shutdown line on another pin", {"sdz_pin": 108}, "amp shutdown line")):
        res = facts(Tree(parse(_made_up(**kw))[0]))
        failed = [w for _, w, e, f in res if norm(e) != norm(f)]
        check(f"{what} fails exactly that fact", len(failed) == 1 and needle in failed[0])
    try:
        parse(_made_up()[:200])
        check("a truncated ADT is refused", False)
    except AdtError:
        check("a truncated ADT is refused", True)
    sink = io.StringIO()
    report(good, sink)
    lines = [ln for ln in sink.getvalue().splitlines() if "level" in ln]
    check("the amplifier level is not in the output", len(lines) == 1 and lines[0].endswith(": yes"))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--adt", help='an ADT file instead of the "adt" MTD partition')
    ap.add_argument("--self-test", action="store_true", help="test the checks on a made-up ADT")
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    try:
        tree = Tree(load(args.adt))
    except (AdtError, struct.error) as e:
        print(f"k114s-adt-sound-facts: {e}", file=sys.stderr)
        return 2
    return 1 if report(facts(tree)) else 0


if __name__ == "__main__":
    sys.exit(main())
