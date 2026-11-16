#!/usr/bin/python3 -I
# SPDX-License-Identifier: MIT
"""k114s-adt-hdmi-facts.py: does this Mac's Apple device tree (ADT) describe the same HDMI route as the J714s?

    sudo python3 -I tests/k114s-adt-hdmi-facts.py            the "adt" MTD partition (root only)
    python3 -I tests/k114s-adt-hdmi-facts.py --adt FILE      a copy of it
    python3 -I tests/k114s-adt-hdmi-facts.py --self-test     the checks themselves, on a made-up ADT

Issue #24. The J714s HDMI port (betizzel patch 0017, FatBoy721, tested on a J714s with macOS 27.3
firmware) is: dcpext3 -> atc3 display crossbar -> ATC3 as a fixed four-lane DP PHY -> an on-board
DP-to-HDMI converter. The expected values below are the ones that patch quotes from the J714sAP ADT.
Read-only. Only pin numbers, endpoint numbers, port types and property NAMES are printed; no serial
numbers, MAC addresses or calibration data are read. Exit 0: every fact holds. 1: one does not. 2: ADT unreadable.
"""
import argparse
import importlib.util
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("soundfacts", os.path.join(HERE, "k114s-adt-sound-facts.py"))
sf = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sf)  # one ADT reader for all the fact scripts

GPIO = sf.GPIO_FOURCC


def facts(t):
    out = []

    def add(what, expected, found):
        out.append(("hdmi", what, expected, found))

    def cell(path, name, i=0):
        w = sf.u32s(t.prop(path, name) or b"")
        return w[i] if len(w) > i else None

    add("/port-hdmi0 exists (a Type-C-less HDMI port)", True, t.node("port-hdmi0") is not None)
    add("atc3-dpphy compatible", "atc-dpphy,t602x", sf.text(t.prop("arm-io/atc3-dpphy", "compatible") or b""))
    add("atc3-dpphy port-type", 6, cell("arm-io/atc3-dpphy", "port-type"))
    add("atc3-dpphy dp-switch-dfp-endpoint", 3, cell("arm-io/atc3-dpphy", "dp-switch-dfp-endpoint"))
    add("atc3-dpphy dp-switch-dfp-port", 0, cell("arm-io/atc3-dpphy", "dp-switch-dfp-port"))
    conv = t.node("arm-io/dp2hdmi-gpio0")
    ph = sf.u32s(t.prop("arm-io/dp2hdmi-gpio0", "AAPL,phandle") or b"")
    add("atc3-dpphy dp2hdmi-gpio-parent is dp2hdmi-gpio0", True,
        bool(conv and ph and cell("arm-io/atc3-dpphy", "dp2hdmi-gpio-parent") == ph[0]))
    ctrl, pin = t.function_gpio("arm-io/dp2hdmi-gpio0", "function-hdmi_hpd")
    add("hdmi_hpd controller", "aop-gpio0", ctrl)
    add("hdmi_hpd pin", 14, pin)
    ctrl, pin = t.function_gpio("arm-io/dp2hdmi-gpio0", "function-force-dpfu")
    add("force-dpfu controller", "aop-gpio0", ctrl)
    add("force-dpfu pin", 15, pin)
    add("hdmi_hpd interrupt (pin, flags)", (14, 0x05000004), tuple(sf.u32s(t.prop("arm-io/dp2hdmi-gpio0", "interrupts") or b"")[:2]))
    for fn, want in (("function-hdmi_pwr_en", (0x800000, 0xF0000)), ("function-dp2hdmi_pwr_en", (0x0, 0x1A0000))):
        w = sf.u32s(t.prop("arm-io/dp2hdmi-gpio0", fn) or b"")
        # the property is (phandle, 'pKW8', 'pcIO', a, b): the SMC pcIO output command words
        pm = t.by_phandle.get(w[0]) if w else None
        add(f"{fn} provider", "smc-pmu", pm["name"] if pm else None)
        add(f"{fn} command (a, b)", want, tuple(w[3:5]))
        add(f"{fn} key words ('pKW8', 'pcIO')", (0x704B5738, 0x7063494F), tuple(w[1:3]))
    # the six reg windows of dts/t6050-k114s-hdmi.dtsi (core, reset, fabric, axi2af, lioa, common-cfg)
    regs = {t.addr("arm-io/atc-phy3", i) for i in range((len(t.prop("arm-io/atc-phy3", "reg") or b"")) // 16)}
    for nm, a in (("core", 0x38B000000), ("reset", 0x38B200000), ("fabric", 0x38B244000),
                  ("axi2af", 0x388000000), ("lioa", 0x388020000), ("common-cfg", 0x38B250000)):
        add(f"atc-phy3 has the draft's {nm} window {a:#x}", True, a in regs)
    add("dcpext3 dp-switch-ufp-endpoint", 3, cell("arm-io/dcpext3", "dp-switch-ufp-endpoint"))
    add("dcpext3 dp-switch-ufp-port", 0, cell("arm-io/dcpext3", "dp-switch-ufp-port"))
    add("atc3-dpxbar compatible", "atc-dpxbar,t6050", sf.text(t.prop("arm-io/atc3-dpxbar", "compatible") or b""))
    add("no USB controller on ATC3 (no usb-drd3 / atc3-usb node)", [],
        [c["name"] for c in t.node("arm-io")["children"] if c["name"].startswith(("usb-drd3", "atc3-usb", "usb3"))])
    return out


def _made_up(hpd_pin=14, pcio=0x7063494F):
    w = lambda *a: struct.pack("<%dI" % len(a), *a)
    s = lambda x: x.encode() + b"\0"
    P, N = sf._prop, sf._node
    kids = [
        N("atc3-dpphy", [("AAPL,phandle", w(5)), ("compatible", s("atc-dpphy,t602x")), ("port-type", w(6)),
                         ("dp-switch-dfp-endpoint", w(3)), ("dp-switch-dfp-port", w(0)), ("dp2hdmi-gpio-parent", w(7))]),
        N("atc3-dpxbar", [("compatible", s("atc-dpxbar,t6050"))]),
        N("atc-phy3", [("reg", b"".join(struct.pack("<QQ", a, 0x4000) for a in (
            0x38B000000, 0x38B200000, 0x38B244000, 0x388000000, 0x388020000, 0x38B250000)))]),
        N("aop-gpio0", [("AAPL,phandle", w(1))]),
        N("smc-pmu", [("AAPL,phandle", w(2))]),
        N("dp2hdmi-gpio0", [("AAPL,phandle", w(7)), ("function-hdmi_hpd", w(1, GPIO, hpd_pin, 0x100)),
                            ("function-force-dpfu", w(1, GPIO, 15, 1)), ("interrupts", w(14, 0x05000004)),
                            ("function-hdmi_pwr_en", w(2, 0x704B5738, pcio, 0x800000, 0xF0000)),
                            ("function-dp2hdmi_pwr_en", w(2, 0x704B5738, pcio, 0x0, 0x1A0000))]),
        N("dcpext3", [("dp-switch-ufp-endpoint", w(3)), ("dp-switch-ufp-port", w(0))],
          [N("iop-dcpext3-nub", [("external-index", w(4))])]),
    ]
    arm = N("arm-io", [("ranges", w(0, 0, 0, 0, 0, 0))], kids)
    return N("device-tree", [], [arm, N("port-hdmi0")])


def self_test():
    import io
    ok = True

    def check(what, cond):
        nonlocal ok
        print(("ok   " if cond else "FAIL ") + what)
        ok = ok and cond

    sink = io.StringIO()
    check("a made-up ADT with the J714s HDMI route passes every fact", sf.report(facts(sf.Tree(sf.parse(_made_up())[0])), sink) == 0)
    if not ok:
        print(sink.getvalue())
    res = facts(sf.Tree(sf.parse(_made_up(hpd_pin=13))[0]))
    bad = [wh for _, wh, e, f in res if sf.norm(e) != sf.norm(f)]
    badk = [wh for _, wh, e, f in facts(sf.Tree(sf.parse(_made_up(pcio=0x70634F49))[0])) if sf.norm(e) != sf.norm(f)]
    check("a converter power line on another SMC key fails the key-word facts", len(badk) == 2 and all("key words" in b for b in badk))
    check("an HPD on another pin fails exactly that fact", bad == ["hdmi_hpd pin"])
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--adt", help='an ADT file instead of the "adt" MTD partition')
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        return self_test()
    try:
        tree = sf.Tree(sf.load(a.adt))
    except (sf.AdtError, struct.error) as e:
        print(f"k114s-adt-hdmi-facts: {e}", file=sys.stderr)
        return 2
    return 1 if sf.report(facts(tree)) else 0


if __name__ == "__main__":
    sys.exit(main())
