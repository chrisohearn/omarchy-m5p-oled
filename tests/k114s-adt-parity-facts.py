#!/usr/bin/python3 -I
# SPDX-License-Identifier: MIT
"""k114s-adt-parity-facts.py: do the draft fragments agree with this Mac's Apple device tree (ADT)?

    sudo python3 -I tests/k114s-adt-parity-facts.py avd=A.dtb sd=B.dtb aop=C.dtb [--adt FILE]

Each GROUP=DTB is a K114s tree compiled with one fragment (tests/test-parity-dtb.sh builds them):
    avd  dts/t6050-k114s-avd.dtsi           issue #30, hardware video decode
    sd   dts/t6050-k114s-sd.dtsi            issue #62, SD card reader
    aop  dts/t6050-k114s-aop-sensors.dtsi   issue #67, ambient light and lid angle sensors
Every register, interrupt, pin, power command and tunable the fragment puts into the tree is
read back from the compiled tree and compared with the ADT, which is read from the "adt" MTD
partition (root only) or from --adt FILE. "info" lines print an ADT fact the fragment cannot
check or that has no counterpart; they never fail the run. Only addresses, interrupt numbers,
pin numbers, offsets and the K114s' board-level facts are printed. Calibration, serials and
firmware bytes are never read.

Exit 0: every fact holds. Exit 1: at least one does not. Exit 2: ADT or tree unreadable.
"""
import importlib.util
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("soundfacts", os.path.join(HERE, "k114s-adt-sound-facts.py"))
sf = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sf)  # Tree, parse, load, u32s, u64, text (the ADT side; one reader for all)

# ---- the compiled tree ------------------------------------------------------------------------------------

class Fdt:
    def __init__(self, blob):
        magic, _t, off_s, off_str, _r, _v, _l, _b, size_str, _ss = struct.unpack_from(">10I", blob)
        if magic != 0xD00DFEED:
            raise ValueError("not a device tree blob")
        strs = blob[off_str:off_str + size_str]
        pos, path, self.nodes = off_s, [], {}
        while True:
            tok = struct.unpack_from(">I", blob, pos)[0]
            pos += 4
            if tok == 1:
                end = blob.index(b"\0", pos)
                path.append(blob[pos:end].decode())
                pos = (end + 4) & ~3
                self.nodes["/".join(path[1:]) and "/" + "/".join(path[1:]) or "/"] = {}
            elif tok == 3:
                ln, no = struct.unpack_from(">II", blob, pos)
                pos += 8
                self.nodes["/" + "/".join(path[1:])][strs[no:strs.index(b"\0", no)].decode()] = blob[pos:pos + ln]
                pos = (pos + ln + 3) & ~3
            elif tok == 2:
                path.pop()
            elif tok == 9:
                break
        self.ph = {self.cells(p["phandle"])[0]: n for n, p in self.nodes.items() if "phandle" in p}

    @staticmethod
    def cells(v):
        return list(struct.unpack(">%dI" % (len(v) // 4), v)) if v else []

    def node(self, path):
        return self.nodes.get(path)

    def find(self, compat):
        return [n for n, p in self.nodes.items() if compat in (p.get("compatible", b"").decode().split("\0"))]

    def one(self, compat):
        found = self.find(compat)
        return found[0] if len(found) == 1 else None

    def parent(self, path):
        return path.rsplit("/", 1)[0] or "/"

    def enabled(self, path):
        """Not "disabled" itself and no ancestor is."""
        while path and path != "/":
            st = self.nodes.get(path, {}).get("status", b"okay\0")
            if st.rstrip(b"\0") not in (b"okay", b"ok"):
                return False
            path = self.parent(path)
        return True

    def regs(self, path):
        """[(addr, size)] with two address and two size cells (every node used here)."""
        c = self.cells(self.nodes[path].get("reg", b""))
        return [(c[i] << 32 | c[i + 1], c[i + 2] << 32 | c[i + 3]) for i in range(0, len(c) - 3, 4)]

    def irqs(self, path):
        c = self.cells(self.nodes[path].get("interrupts", b""))
        return [c[i + 2] for i in range(0, len(c) - 3, 4)]  # AIC_IRQ, die, number, flags

    def prop(self, path, name):
        return self.nodes.get(path, {}).get(name)

    def target(self, path, name, index=0, stride=2):
        """Node a phandle list property (cells: phandle + stride-1 argument cells) points at."""
        c = self.cells(self.nodes[path].get(name, b""))
        return (self.ph.get(c[index * stride]), c[index * stride + 1:(index + 1) * stride]) if len(c) > index * stride else (None, None)


def hexs(v):
    if isinstance(v, (list, tuple)):
        return "[" + ", ".join(hexs(x) for x in v) + "]"
    if isinstance(v, bool):
        return "yes" if v else "no"
    if isinstance(v, int):
        return hex(v) if v >= 4096 else str(v)
    return repr(v)


# ---- the facts ---------------------------------------------------------------------------------------------

def pmgr_device(adt, name):
    """(id, parent id, offset) of the pmgr device table entry called @name. 48-byte entries: flags
    and parent (u16 at +4), the power state's offset (u16 at +16), the id (u16 at +26), a name at +32."""
    d = adt.prop("arm-io/pmgr", "devices") or b""
    for i in range(0, len(d) - 47, 48):
        if d[i + 32:i + 48].split(b"\0", 1)[0] == name.encode():
            return struct.unpack_from("<H", d, i + 26)[0], struct.unpack_from("<H", d, i + 4)[0], struct.unpack_from("<H", d, i + 16)[0]
    return None


def pmgr_device_by_id(adt, ident):
    d = adt.prop("arm-io/pmgr", "devices") or b""
    for i in range(0, len(d) - 47, 48):
        if struct.unpack_from("<H", d, i + 26)[0] == ident:
            return d[i + 32:i + 48].split(b"\0", 1)[0].decode(), struct.unpack_from("<H", d, i + 4)[0]
    return None


def avd_facts(adt, t):
    A = "arm-io/"
    out, info = [], []
    fact = lambda what, dtb, a: out.append((what, dtb, a))
    avd, dart = t.one("apple,t6050-avd"), None
    if avd is None:
        return [("tree has exactly one avd node", True, False)], info
    dart = t.target(avd, "iommus")[0]
    ps_avd = t.target(avd, "power-domains", stride=1)[0]
    ps_fab = t.target(ps_avd, "power-domains", stride=1)[0] if ps_avd else None
    pmgr4 = t.parent(ps_avd) if ps_avd else None
    for n, what in ((avd, "avd0"), (dart, "dart-avd0"), (ps_avd, "AVD_SYS power state"), (ps_fab, "FAB1_SOC power state"),
                    (pmgr4, "pmgr4")):
        fact(what + " is enabled", True, bool(n) and t.enabled(n))
    fact("FAB1_SOC is always on (macOS never gates it)", True, bool(ps_fab) and "apple,always-on" in t.nodes[ps_fab])

    # avd0: one window, four sub-blocks inside it, two interrupts
    soc = t.parent(avd)
    rng = t.cells(t.nodes[soc]["ranges"])
    window = (rng[0] << 32 | rng[1], rng[4] << 32 | rng[5])
    base = (adt.addr(A + "avd0"), adt.size(A + "avd0"))
    fact("avd0 window (address, size)", window, base)
    fact("avd0 sub-blocks (code, sram, mbox, ctrl) lie inside the window", True,
         all(base[0] <= a and a + s <= base[0] + base[1] for a, s in t.regs(avd)))
    fact("avd0 interrupts", t.irqs(avd), sf.u32s(adt.prop(A + "avd0", "interrupts")))
    fact("avd0 IOMMU streams", sorted(t.target(avd, "iommus", i)[1][0] for i in range(3)), sorted(sf.u32s(adt.prop(A + "dart-avd0", "sid"))[:3]))
    fact("dart-avd0 (address, size)", t.regs(dart)[0], (adt.addr(A + "dart-avd0"), adt.size(A + "dart-avd0")))
    fact("dart-avd0 interrupt", t.irqs(dart)[0], adt.irq(A + "dart-avd0")[1])

    # pmgr4 and its two power states
    reg46 = adt.addr(A + "pmgr", 46)
    fact("pmgr4 base = ADT pmgr reg[46]", t.regs(pmgr4)[0][0], reg46)
    fact("pmgr4 window fits inside reg[46]", True, t.regs(pmgr4)[0][1] <= adt.size(A + "pmgr", 46))
    for ps, name in ((ps_fab, "FAB1_SOC"), (ps_avd, "AVD_SYS")):
        dev = pmgr_device(adt, name)
        fact("%s power state offset" % name, (t.cells(t.nodes[ps]["reg"]) or [None])[0] if ps else None, dev[2] if dev else None)
    fab, avs = pmgr_device(adt, "FAB1_SOC"), pmgr_device(adt, "AVD_SYS")
    fact("AVD_SYS is a child of FAB1_SOC (ADT) as the tree says", True,
         bool(fab and avs and avs[1] == fab[0] and ps_fab and t.target(ps_avd, "power-domains", stride=1)[0] == ps_fab))
    for node, what in ((A + "avd0", "avd0"), (A + "dart-avd0", "dart-avd0")):
        gate = (sf.u32s(adt.prop(node, "power-gates")) or [None])[0]
        dev = pmgr_device_by_id(adt, gate) if gate else None
        fact("%s's power gate hangs off AVD_SYS" % what, True, bool(dev and avs and dev[1] == avs[0]))
    v = sf.u32s(adt.prop(A + "avd0", "avd-version"))
    info.append("ADT avd-version %s, avd-ads-keytype-version %s, compatible %s (tree: apple,t8142-avd generation; avd-fw v5-t2)" % (
        v[0] if v else "?", (sf.u32s(adt.prop(A + "avd0", "avd-ads-keytype-version")) or ["?"])[0],
        (sf.text(adt.prop(A + "avd0", "compatible")) or "?") + ", ..."))
    info.append("pmgr power-state register block: the tree's psreg-to-reg[46] step is upstream's (#1856), not derivable from the ADT")
    return out, info


def tunables(adt, name):
    v = sf.u32s(adt.prop("arm-io/apcie0/pci-bridge1", name))
    return [(v[i], v[i + 1], v[i + 3] << 32 | v[i + 2], v[i + 5] << 32 | v[i + 4]) for i in range(0, len(v) - 5, 6)]


def sd_facts(adt, t):
    A = "arm-io/"
    out, info = [], []
    fact = lambda what, dtb, a: out.append((what, dtb, a))
    ports = [n for n in t.nodes if n.endswith("/pci@1,0")]
    if len(ports) != 1:
        return [("tree has exactly one port 1 node", True, False)], info
    port = ports[0]
    host = t.parent(port)
    reader = [n for n in t.nodes if t.parent(n) == port]
    reader = reader[0] if len(reader) == 1 else None
    P = A + "apcie0/"
    fact("host and port 1 are enabled", True, t.enabled(host) and t.enabled(port))
    # registers and interrupts of the root complex, by the names the tree gives them
    names = t.prop(host, "reg-names").decode().rstrip("\0").split("\0")
    idx = {"config": 0, "rc": 1, "port0": 16, "phy0": 18, "intr2axi0": 19, "port1": 22, "phy1": 24, "intr2axi1": 25, "phy-shared": 3}
    for n, reg in zip(names, t.regs(host)):
        # ADT reg[0] (the config window) is not translated by the arm-io ranges; the others are
        fact("host reg %s (ADT apcie0 reg[%d])" % (n, idx[n]), reg, (adt.addr(P[:-1], idx[n]), adt.size(P[:-1], idx[n])))
    fact("host has every register window port 1 needs", True, {"port1", "phy1", "intr2axi1", "phy-shared"} <= set(names))
    ints = sf.u32s(adt.prop(P[:-1], "interrupts"))
    fact("host interrupts (port0, port1)", t.irqs(host), ints[:2])
    fact("port 1 sits at device number = ADT port-number", (sf.u32s(adt.prop(P + "pci-bridge1", "apcie-port")) or [None])[0],
         (t.cells(t.nodes[port]["reg"])[0] >> 11) & 0x1F)

    # pins and power
    gpio_ph = t.target(port, "reset-gpios", stride=3)
    gpio, pin = gpio_ph[0], (gpio_ph[1][0] if gpio_ph[1] else None)
    perst = sf.u32s(adt.prop(P + "pci-bridge1", "function-perst"))
    fact("PERST# pin (ADT pci-bridge1 function-perst)", pin, perst[2] if len(perst) > 2 and perst[1] == sf.GPIO_FOURCC else None)
    fact("PERST# controller is the AP pin controller (ADT gpio0)", t.regs(gpio)[0][0] if gpio else None, adt.addr(A + "gpio0"))
    reserved = set()
    rr = t.cells(t.prop(gpio, "gpio-reserved-ranges") or b"") if gpio else []
    for s, c in zip(rr[0::2], rr[1::2]):
        reserved |= set(range(s, s + c))
    npins = (sf.u32s(adt.prop(A + "gpio0", "#gpio-pins")) or [0])[0]
    fact("pins 80 and 81 exposed, pin 112 (SError on read) reserved", (False, False, True), (80 in reserved, 81 in reserved, 112 in reserved))
    fact("no reserved range runs past the controller's pin count", True, bool(rr) and all(s + c <= npins for s, c in zip(rr[0::2], rr[1::2])))
    pw = sf.u32s(adt.prop(P + "pci-bridge1/pcie-sdreader", "function-sd_pwr_en"))
    smc, arg = t.target(port, "pwren-gpios", stride=3)
    cmds = t.cells(t.prop(smc, "apple,output-commands") or b"") if smc else []
    cmds = [cmds[i] << 32 | cmds[i + 1] for i in range(0, len(cmds) - 1, 2)]
    want = (pw[4] << 32 | pw[3]) if len(pw) >= 5 else None
    fact("SMC command of sd_pwr_en: pKW8('pcIO', lo, hi) as hi<<32|lo, at the index pwren-gpios names",
         cmds[arg[0]] if arg and cmds and arg[0] < len(cmds) else None, want)
    fact("sd_pwr_en is a pKW8 pcIO command", (0x704B5738, 0x7063494F), tuple(pw[1:3]))

    # the DART
    m = t.cells(t.prop(host, "iommu-map") or b"")
    dart = t.ph.get(m[5]) if len(m) >= 8 else None
    fact("iommu-map entry 2 starts at requester ID 0x200 (bus 2)", 0x200, m[4] if len(m) >= 8 else None)
    fact("dart_apcie1 is enabled", True, bool(dart) and t.enabled(dart))
    fact("dart_apcie1 (address, size)", t.regs(dart)[0] if dart else None, (adt.addr(A + "dart-apcie1"), adt.size(A + "dart-apcie1")))
    fact("dart_apcie1 interrupt", t.irqs(dart)[0] if dart else None, adt.irq(A + "dart-apcie1")[1])
    fact("dart_apcie1 manual-availability (ADT dart-apcie1)", bool(adt.prop(A + "dart-apcie1", "manual-availability")),
         bool(dart) and "apple,manual-availability" in t.nodes[dart])
    fact("host waits for no provider that only probes after port 1 (post-init-providers = the DART)", True,
         bool(dart) and (t.cells(t.prop(host, "post-init-providers") or b"") or [None])[0] == t.cells(t.nodes[dart].get("phandle", b""))[0])

    # link tunables
    for name in ("apcie-config-tunables", "pcie-rc-tunables", "pcie-rc-gen3-shadow-tunables", "pcie-rc-gen4-shadow-tunables",
                 "pcie-rc-gen5-shadow-tunables"):
        c = t.cells(t.prop(port, "apple," + name) or b"")
        fact("port 1 %s (offset, size, mask, value)" % name, [(c[i], c[i + 1], c[i + 2], c[i + 3]) for i in range(0, len(c) - 3, 4)], tunables(adt, name))

    # the reader itself
    S = P + "pci-bridge1/pcie-sdreader"
    fact("reader: card-detect polarity (ADT 1 = cd-inverted)", (sf.u32s(adt.prop(S, "card-detect-polarity")) or [None])[0] == 1,
         bool(reader) and "cd-inverted" in t.nodes[reader])
    fact("reader: write-protect polarity (ADT 1 = wp-inverted)", (sf.u32s(adt.prop(S, "write-protect-polarity")) or [None])[0] == 1,
         bool(reader) and "wp-inverted" in t.nodes[reader])
    node = adt.node(S)
    fact("reader is a GL9755 (ADT carries gl9755-* properties; tree: pci17a0,9755)", True,
         bool(node) and any(k.startswith("gl9755-") for k in node["props"]) and bool(reader) and
         t.nodes[reader].get("compatible") == b"pci17a0,9755\0")
    info.append("ADT dart-apcie1 sid %s, pcie-sdreader iommu-parent is the DART; no stream is named for the reader: tree uses stream 1 (K114c, J714s)" %
                hexs(sf.u32s(adt.prop(A + "dart-apcie1", "sid"))))
    info.append("ADT pcie-sdreader expected-link-speed %s, initial-link-speed %s" % (
        (sf.u32s(adt.prop(S, "expected-link-speed")) or ["?"])[0], (sf.u32s(adt.prop(S, "initial-link-speed")) or ["?"])[0]))
    return out, info


def aop_facts(adt, t, allow_audio=False):
    A = "arm-io/"
    out, info = [], []
    fact = lambda what, dtb, a: out.append((what, dtb, a))
    aop = t.one("apple,t6050-aop")
    if aop is None:
        return [("tree has exactly one aop node", True, False)], info
    mbox, setup = t.target(aop, "mboxes", 0, 1)[0], t.target(aop, "mboxes", 1, 1)[0]
    dart = t.target(aop, "iommus")[0]
    for n, what in ((aop, "aop"), (mbox, "aop mailbox"), (setup, "aop setup mailbox"), (dart, "dart-aop")):
        fact(what + " is enabled", True, bool(n) and t.enabled(n))
    (mmio, asc) = t.regs(aop)[:2]
    fact("aop SRAM window address (ADT aop reg[2])", mmio[0], adt.addr(A + "aop", 2))
    fact("aop SRAM window fits inside the ADT's", True, mmio[1] <= adt.size(A + "aop", 2))
    fact("aop ASC address (ADT aop reg[0])", asc[0], adt.addr(A + "aop", 0))
    fact("aop ASC window fits inside the ADT's", True, asc[1] <= adt.size(A + "aop", 0))
    fact("aop mailbox interrupts (ADT aop interrupts, as a set)", sorted(t.irqs(mbox)), sorted(sf.u32s(adt.prop(A + "aop", "interrupts"))))
    fact("aop setup mailbox address (ADT aop-exclave-mailbox, untranslated)", t.regs(setup)[0][0], adt.addr(A + "aop-exclave-mailbox", translate=False))
    fact("dart-aop address", t.regs(dart)[0][0], adt.addr(A + "dart-aop"))
    fact("dart-aop interrupt", t.irqs(dart)[0], adt.irq(A + "dart-aop")[1])
    fact("dart-aop stream of the AOP is one of the ADT's", True, t.target(aop, "iommus")[1][0] in sf.u32s(adt.prop(A + "dart-aop", "sid")))
    fact("dart-aop stream of the setup port is an exclave stream", True,
         t.target(setup, "iommus")[1][0] in sf.u32s(adt.prop(A + "dart-aop", "exclave-sid")))

    kids = {n: t.nodes[n].get("compatible", b"").decode().split("\0")[0] for n in t.nodes if t.parent(n) == aop}
    als = [n for n, c in kids.items() if c.startswith("apple,t6050-aop-als")]
    las = [n for n, c in kids.items() if c.startswith("apple,t6050-aop-las")]
    fact("als service node comes up with the AOP", True, len(als) == 1 and t.enabled(als[0]))
    fact("las service node comes up with the AOP", True, len(las) == 1 and t.enabled(las[0]))
    nub = A + "aop/iop-aop-nub/"
    fact("ADT has an als service node (the sensor's presence)", True, adt.node(nub + "als") is not None)
    info.append("ADT las (lid angle): %s; nodes under iop-aop-nub: %s" % (
        "present" if adt.node(nub + "las") else "ABSENT (the firmware announces services at run time; open)",
        hexs(adt.children(nub[:-1]))))
    info.append("ADT als: harmony-db-version %s; no calibration property (the driver loads apple/aop-als-cal.bin: open)" %
                (sf.u32s(adt.prop(nub + "als", "harmony-db-version")) or ["?"])[0])

    # what this fragment must not start: the audio service, any amplifier
    audio = [n for n, c in kids.items() if c == "apple,t6050-aop-audio"]
    if not allow_audio:
        fact("audio service stays disabled (the fragment is sensors only)", True, bool(audio) and not t.enabled(audio[0]))
    amps = [n for n in t.nodes if "sn012776" in t.nodes[n].get("compatible", b"").decode()]
    fact("no speaker amplifier node in the tree", [], amps)
    spk = [n for n in t.nodes if t.nodes[n].get("dma-names") and b"spkr" in t.nodes[n]["dma-names"] and t.enabled(n)]
    fact("no enabled node asks for the speaker DMA channel", [], spk)
    return out, info


def run(adt, trees, allow_audio=False, out=None):
    out = out or sys.stdout
    bad = 0
    for group, path in trees:
        print("%s (%s):" % (group, os.path.basename(path)), file=out)
        t = Fdt(open(path, "rb").read())
        if group == "avd":
            facts_, info = avd_facts(adt, t)
        elif group == "sd":
            facts_, info = sd_facts(adt, t)
        else:
            facts_, info = aop_facts(adt, t, allow_audio)
        for what, dtb, found in facts_:
            if dtb == found or (isinstance(dtb, (list, tuple)) and list(dtb) == list(found or [])):
                print("  ok    %s: %s" % (what, hexs(dtb)), file=out)
            else:
                bad += 1
                print("  FAIL  %s: the tree says %s, the ADT says %s" % (what, hexs(dtb), hexs(found)), file=out)
        for line in info:
            print("  info  " + line, file=out)
    print("parity facts: %s" % ("every fact holds" if not bad else "%d do not hold" % bad), file=out)
    return bad


def main(argv):
    args, adt_path, trees, allow_audio = argv, None, [], False
    while args:
        a = args.pop(0)
        if a == "--adt":
            adt_path = args.pop(0)
        elif a == "--with-audio":
            allow_audio = True
        elif "=" in a and a.split("=", 1)[0] in ("avd", "sd", "aop"):
            trees.append(tuple(a.split("=", 1)))
        else:
            print(__doc__)
            return 2
    if not trees:
        print(__doc__)
        return 2
    try:
        adt = sf.Tree(sf.load(adt_path))
        board = (sf.u32s(adt.prop("chosen", "board-id")) or [None])[0]
        if board != sf.BOARD_ID:
            print("this ADT is board-id %s, not the K114s (0x14); refusing" % board)
            return 2
        return 1 if run(adt, trees, allow_audio) else 0
    except (sf.AdtError, OSError, ValueError, KeyError) as e:
        print("k114s-adt-parity-facts: %s: %s" % (type(e).__name__, e), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
