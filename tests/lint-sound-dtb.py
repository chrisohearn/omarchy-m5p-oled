#!/usr/bin/env python3
"""Speaker-safety lint for a compiled K114s tree with sound (dts/t6050-k114s-sound.dtsi).

Fails when the tree gives the speaker amplifiers any way to play:
  - an amplifier node, or anything at all on the two amp buses (i2c1, i2c3), or either bus enabled;
  - a reference to the amps' shutdown or fault line (AP pins 107, 106) or the speaker-ID pins
    (136, 137), or one of them outside gpio-reserved-ranges;
  - a "Speaker" link in the card, a link on the AOP's speaker back-end, or a card that is not
    "apple,k114-macaudio";
  - a "spkr" or "sense" DMA channel on the AOP audio node;
and when the pieces the jack needs are missing (codec, AOP, PMP with this Mac's values).

usage: lint-sound-dtb.py TREE.dtb [TREE.dtb ...]
"""
import struct
import sys

AMP_COMPATIBLES = ("ti,sn012776", "ti,tas2764", "ti,tas2770", "ti,tas5770l", "adi,ssm3515",
                   "maxim,max98360a", "maxim,max98357a")
AMP_BUSES = ("i2c@505014000", "i2c@50501c000")  # i2c1 (left amps), i2c3 (right amps)
JACK_BUS = "i2c@505018000"                      # i2c2
FORBIDDEN_PINS = {106: "amp fault", 107: "amp shutdown (SDZ)", 136: "speaker ID 0", 137: "speaker ID 1"}
SOUND_PINS = {134, 139}
AOP_SPKR_DAI = 3


def walk(b):
    magic, _total, ost, ostr, _, _ver, _, _, szstr, _szst = struct.unpack_from(">10I", b)
    assert magic == 0xD00DFEED, "not a device tree blob"
    strs = b[ostr:ostr + szstr]
    p, path, nodes = ost, [], {}
    while True:
        tok = struct.unpack_from(">I", b, p)[0]
        p += 4
        if tok == 1:
            e = b.index(b"\0", p)
            path.append(b[p:e].decode())
            p = (e + 4) & ~3
            nodes["/".join(path) or "/"] = {}
        elif tok == 3:
            ln, no = struct.unpack_from(">II", b, p)
            p += 8
            nodes["/".join(path) or "/"][strs[no:strs.index(b"\0", no)].decode()] = b[p:p + ln]
            p = (p + ln + 3) & ~3
        elif tok == 2:
            path.pop()
        elif tok == 9:
            return nodes


def strs(v):
    return [s.decode("ascii", "replace") for s in v.split(b"\0") if s] if v else []


def cells(v):
    return list(struct.unpack(">%dI" % (len(v) // 4), v[:len(v) // 4 * 4])) if v else []


def status(props):
    return strs(props.get("status")) [0] if props.get("status") else "okay"


def lint(f):
    errs = []
    nodes = walk(open(f, "rb").read())
    root = nodes.get("/") or nodes.get("")

    def err(msg):
        errs.append(msg)

    def find(last):
        return [(p, pr) for p, pr in nodes.items() if p.split("/")[-1] == last]

    def children(path):
        return [(p, pr) for p, pr in nodes.items() if p.startswith(path + "/") and "/" not in p[len(path) + 1:]]

    if strs(root.get("compatible"))[:1] != ["apple,k114s"]:
        err(f"root compatible is {strs(root.get('compatible'))[:1]}, not apple,k114s")

    by_phandle = {cells(pr["phandle"])[0]: p for p, pr in nodes.items() if "phandle" in pr}

    # 1. no amplifier anywhere
    for p, pr in nodes.items():
        hit = [c for c in strs(pr.get("compatible")) if c in AMP_COMPATIBLES]
        if hit:
            err(f"speaker amplifier node {p} ({hit[0]})")
        if strs(pr.get("compatible"))[:1] == ["regulator-fixed"] and b"sdz" in pr.get("regulator-name", b"").lower():
            err(f"amp shutdown regulator {p}")
        if "apple,speaker-config" in pr or "SDZ-supply" in pr:
            err(f"amp property on {p}")

    # 2. the amp buses stay off and empty; the jack bus carries the codec only
    for bus in AMP_BUSES:
        hits = find(bus)
        if not hits:
            err(f"{bus} not found (the lint no longer knows the amp buses)")
        for p, pr in hits:
            if status(pr) != "disabled":
                err(f"amp bus {p} is {status(pr)}, must be disabled")
            for c, _ in children(p):
                err(f"device on an amp bus: {c}")
    codec_phandle = None
    for p, pr in find(JACK_BUS):
        if status(pr) != "okay":
            err(f"jack bus {p} is {status(pr)}")
        kids = children(p)
        if [c.split("/")[-1] for c, _ in kids] != ["codec@4b"]:
            err(f"jack bus {p} carries {[c.split('/')[-1] for c, _ in kids]}, expected only codec@4b")
        for c, cp in kids:
            if strs(cp.get("compatible")) != ["cirrus,cs42l84"]:
                err(f"{c} is {strs(cp.get('compatible'))}, expected cirrus,cs42l84")
            codec_phandle = cells(cp.get("phandle", b""))[0] if cp.get("phandle") else None
    if codec_phandle is None:
        err("no jack codec with a phandle")

    # 3. AP pins: the amp and speaker-ID lines are reserved and named nowhere
    ap = [(p, pr) for p, pr in nodes.items() if "apple,npins" in pr and cells(pr["apple,npins"]) == [221]]
    if len(ap) != 1:
        err(f"expected one 221-pin AP pin controller, found {len(ap)}")
    else:
        ap_path, ap_props = ap[0]
        r = cells(ap_props.get("gpio-reserved-ranges", b""))
        reserved = set()
        for start, count in zip(r[0::2], r[1::2]):
            if start + count > 221:
                err(f"gpio-reserved-ranges <{start} {count}> runs past the last pin and would be ignored")
            reserved |= set(range(start, start + count))
        exposed = set(range(221)) - reserved
        for pin, what in FORBIDDEN_PINS.items():
            if pin in exposed:
                err(f"AP pin {pin} ({what}) is not reserved")
        if 112 in exposed:
            err("AP pin 112 is exposed (reading it takes an SError)")
        if not SOUND_PINS <= exposed:
            err(f"jack codec pins {sorted(SOUND_PINS - exposed)} are reserved")
        ap_ph = cells(ap_props.get("phandle", b""))[:1]
        named = set()

        def irq_parent(path):
            # the interrupt-parent in force at a node: its own, else the nearest ancestor's
            while True:
                ip = cells(nodes.get(path or "/", {}).get("interrupt-parent", b""))[:1]
                if ip or path in ("", "/"):
                    return ip
                path = path.rsplit("/", 1)[0]

        for p, pr in nodes.items():
            # interrupts = <pin flags ...> under an interrupt-parent that is the AP pin controller
            if "interrupts" in pr and ap_ph and irq_parent(p) == ap_ph:
                n = cells(ap_props.get("#interrupt-cells", b""))[:1]
                if not n:
                    err(f"{p} interrupts: the AP pin controller has no #interrupt-cells")
                else:
                    for pin in cells(pr["interrupts"])[0::n[0]]:
                        named.add(pin)
                        if pin in FORBIDDEN_PINS:
                            err(f"{p} interrupts names AP pin {pin} ({FORBIDDEN_PINS[pin]})")
            for name, v in pr.items():
                # <&controller pin flags ...> lists: walk them by each controller's cell count
                if name.endswith(("-gpios", "-gpio")) or name in ("gpios", "gpio"):
                    ncells = "#gpio-cells"
                elif name == "interrupts-extended":
                    ncells = "#interrupt-cells"
                else:
                    continue
                c, i = cells(v), 0
                while i < len(c):
                    if c[i] == 0:  # an empty entry
                        i += 1
                        continue
                    ctrl = nodes.get(by_phandle.get(c[i]), {})
                    n = cells(ctrl.get(ncells, b""))[:1]
                    if not n:
                        err(f"{p} {name}: cell {i} is not a controller with {ncells}")
                        break
                    if ap_ph and c[i] == ap_ph[0] and n[0] >= 1 and i + 1 < len(c):
                        named.add(c[i + 1])
                        if c[i + 1] in FORBIDDEN_PINS:
                            err(f"{p} {name} names AP pin {c[i + 1]} ({FORBIDDEN_PINS[c[i + 1]]})")
                    i += 1 + n[0]
        if named - exposed:
            err(f"pins named but reserved: {sorted(named - exposed)}")
        if exposed - named:
            err(f"pins exposed but named by no node: {sorted(exposed - named)}")
        print(f"  {f.split('/')[-1]}: AP pins exposed {sorted(exposed)}, named {sorted(named)}")

    # 4. the AOP audio node has no speaker stream
    audio = [(p, pr) for p, pr in nodes.items() if "apple,t6050-aop-audio" in strs(pr.get("compatible"))]
    audio_ph = None
    if len(audio) != 1:
        err(f"expected one apple,t6050-aop-audio node, found {len(audio)}")
    else:
        p, pr = audio[0]
        names = strs(pr.get("dma-names"))
        for n in names:
            if n not in ("cout", "cin", "hpai"):
                err(f"{p} has DMA channel {n!r}: only cout, cin and hpai are allowed")
        if names[:2] != ["cout", "cin"]:
            err(f"{p} dma-names {names}: the jack needs cout and cin")
        if len(cells(pr.get("dmas", b""))) != 2 * len(names):
            err(f"{p}: {len(cells(pr.get('dmas', b''))) // 2} dmas for {len(names)} names")
        if strs(pr.get("apple,chassis-name")) != ["K114"]:
            err(f"{p} apple,chassis-name is {strs(pr.get('apple,chassis-name'))}, expected K114")
        if "apple,speaker-amps" in pr:
            err(f"{p} has apple,speaker-amps")
        audio_ph = cells(pr.get("phandle", b""))[0] if pr.get("phandle") else None
        parent = nodes[p.rsplit("/", 1)[0]]
        if status(parent) != "okay":
            err("the AOP is not enabled")

    # 5. the card: K114, the jack link only
    cards = [(p, pr) for p, pr in nodes.items() if "apple,macaudio" in strs(pr.get("compatible"))]
    if len(cards) != 1:
        err(f"expected one apple,macaudio card, found {len(cards)}")
    for p, pr in cards:
        if strs(pr.get("compatible")) != ["apple,k114-macaudio", "apple,macaudio"]:
            err(f"card {p} is {strs(pr.get('compatible'))}: only apple,k114-macaudio refuses the speakers in the driver")
        if strs(pr.get("model")) != ["MacBook Pro K114"]:
            err(f"card model is {strs(pr.get('model'))}")
        if "speaker-id-gpios" in pr:
            err("card has speaker-id-gpios")
        links = children(p)
        if [strs(lp.get("link-name")) for _, lp in links] != [["Headphone Jack"]]:
            err(f"card links are {[strs(lp.get('link-name')) for _, lp in links]}, expected only Headphone Jack")
        for lpath, lp in links:
            if strs(lp.get("link-name"))[:1] in (["Speaker"], ["Speakers"]):
                err(f"speaker link {lpath}")
            cpu = cells(nodes.get(lpath + "/cpu", {}).get("sound-dai", b""))
            codec = cells(nodes.get(lpath + "/codec", {}).get("sound-dai", b""))
            if cpu != [audio_ph, 0]:
                err(f"{lpath} cpu is {cpu}, expected the AOP audio node's DAI 0")
            if AOP_SPKR_DAI in cpu[1::2]:
                err(f"{lpath} uses the AOP speaker back-end (DAI {AOP_SPKR_DAI})")
            if codec != [codec_phandle]:
                err(f"{lpath} codec is {[by_phandle.get(c, c) for c in codec]}, expected the jack codec")

    # 6. the PMP runs with this Mac's values; the loader must not find a "pmp" alias
    pmp = [(p, pr) for p, pr in nodes.items() if "apple,t6050-pmp-v2" in strs(pr.get("compatible"))]
    if len(pmp) != 1:
        err(f"expected one PMP node, found {len(pmp)}")
    else:
        p, pr = pmp[0]
        if status(pr) != "okay":
            err("the PMP is not enabled: the AOP's audio service does not come up without it")
        if cells(pr.get("apple,board-id", b"")) != [0x14]:
            err(f"PMP apple,board-id is {cells(pr.get('apple,board-id', b''))}, expected 20")
        ntun = sum(1 for n in pr if n.startswith("apple,tunable-"))
        if "apple,dram-vendor-id" not in pr or not ntun:
            err("the PMP has no apple,dram-vendor-id or no apple,tunable-* values (t6050-k114s-pmp-tunables.dtsi)")
        print(f"  {f.split('/')[-1]}: PMP with {ntun} firmware properties")
    for label in ("pms", "pmp", "pms-sram"):
        ps = [(p, pr) for p, pr in nodes.items() if strs(pr.get("label")) == [label] and "#power-domain-cells" in pr]
        if len(ps) != 1 or status(ps[0][1]) != "okay" or "apple,always-on" not in ps[0][1]:
            err(f"PMP power state {label!r} is not enabled and always on")
    aliases = nodes.get("aliases") or nodes.get("/aliases") or {}
    if "pmp" in aliases:
        err("alias pmp: the loader's dt_set_pmp() would look for an ADT path this SoC does not have and stop the boot")

    return errs


bad = 0
for f in sys.argv[1:]:
    errs = lint(f)
    for e in errs:
        print(f"FAIL {f}: {e}")
    bad += len(errs)
print("sound dtb lint:", "FAILED" if bad else "passed", f"({len(sys.argv) - 1} trees)")
sys.exit(1 if bad else 0)
