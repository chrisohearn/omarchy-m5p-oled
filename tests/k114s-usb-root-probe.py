#!/usr/bin/env python3
"""USB-C facts that only root can read on the running Mac. Read-only; nothing is written or sent.

    sudo python3 tests/k114s-usb-root-probe.py regs
    sudo python3 tests/k114s-usb-root-probe.py adt [--adt FILE] [--names NODE]

regs  The registers of the USB-C port controllers (SN201202x), through the driver's read-only
      debugfs file /sys/kernel/debug/usb/tipd/<controller>/regs. These are the same register
      reads the driver's own half-second poll makes. It answers: does the controller itself see
      a plug, in which role, and with which data connection? Run it with a device plugged in if
      tests/k114s-usb-check.sh shows the port IDLE although something is attached.

adt   The USB-C part of this boot's Apple device tree (ADT), which the loader keeps in memory and
      Linux shows as the MTD device named "adt" (/proc/mtd). It compares the addresses and bus
      positions the K114s Linux device tree uses with the ADT of this machine. The Linux tree
      took them from the K116s tree, on the repository's record that the two ADTs are identical;
      this reads them from the K114s itself.

Output is limited to register addresses, SPMI bus positions, port numbers, node names and the
values of a short list of properties. No serial number, hardware address or other property value
is printed, so the output can go into a public report. Do not publish the ADT itself.
"""
import glob
import os
import struct
import sys

# ---------------------------------------------------------------------------------------------
# regs: SN201202x registers, layout from drivers/usb/typec/tipd (tps6598x.h, core.c) at
# aurora-silicon/linux a34d26c255c2. Values are little-endian.

REG_MODE, REG_EVENT1, REG_MASK1, REG_STATUS, REG_POWER_STATUS, REG_DATA_STATUS = 0x03, 0x14, 0x16, 0x1a, 0x3f, 0x5f
CONN_STATE = {0: "no connection", 1: "port disabled", 2: "audio accessory", 3: "debug accessory",
              4: "no connection, Ra seen", 5: "reserved", 6: "connected, no Ra", 7: "connected, Ra seen"}


def decode_status(v):
    return ["plug present" if v & 1 else "NO plug",
            "connection state %d (%s)" % ((v >> 1) & 7, CONN_STATE[(v >> 1) & 7]),
            "plug upside down" if v & (1 << 4) else "plug upright",
            "power role source" if v & (1 << 5) else "power role sink",
            "data role host (DFP)" if v & (1 << 6) else "data role device (UFP)",
            "VCONN on" if v & (1 << 7) else "VCONN off"]


def decode_data_status(v):
    out = ["data connection" if v & 1 else "NO data connection"]
    for bit, name in ((4, "USB2"), (5, "USB3"), (6, "USB3 Gen 2"), (8, "DisplayPort"), (16, "Thunderbolt"),
                      (23, "USB4")):
        if v & (1 << bit):
            out.append(name)
    out.append("this port is the USB DEVICE on the link" if v & (1 << 7) else "this port is the USB host on the link")
    return out


def verdict(mode, status, data_status):
    """One sentence on what the controller reports, for the USB host question."""
    if mode not in (b"APP ", b"APP1", b"DBMa"):
        return "controller is in mode %r, not its application firmware" % mode.decode("ascii", "replace")
    if not status & 1:
        return "the controller sees no plug: nothing is attached, or the plug is not detected at the connector"
    if not data_status & ((1 << 4) | (1 << 5)):
        return "plug present without a USB2 or USB3 data connection (a charger, or a cable with no device)"
    if data_status & (1 << 7):
        return "plug present, but this Mac is the USB device on the link: the host-only port stays off"
    return "plug present with a USB host connection: xHCI must be up; if it is not, the fault is after the controller"


def read_reg(path, reg, length):
    fd = os.open(path, os.O_RDONLY)
    try:
        data = os.pread(fd, length, reg)
    finally:
        os.close(fd)
    if len(data) != length:
        raise OSError("short read of register 0x%02x" % reg)
    return data


def probe_regs(root="/sys/kernel/debug/usb/tipd"):
    files = sorted(glob.glob(os.path.join(root, "*", "regs")))
    if not files:
        print("no %s/*/regs: not root, debugfs not mounted, or no port controller is bound" % root)
        return 2
    rc = 0
    for path in files:
        name = os.path.basename(os.path.dirname(path))
        try:
            mode = read_reg(path, REG_MODE, 4)
            status = struct.unpack("<I", read_reg(path, REG_STATUS, 4))[0]
            power = struct.unpack("<H", read_reg(path, REG_POWER_STATUS, 2))[0]
            data = struct.unpack("<I", read_reg(path, REG_DATA_STATUS, 4))[0]
            event = struct.unpack("<Q", read_reg(path, REG_EVENT1, 8))[0]
            mask = struct.unpack("<Q", read_reg(path, REG_MASK1, 8))[0]
        except OSError as e:
            print("%s: register read failed: %s" % (name, e))
            rc = 1
            continue
        print("%s: mode %r" % (name, mode.decode("ascii", "replace")))
        print("  status       0x%08x: %s" % (status, "; ".join(decode_status(status))))
        print("  power status 0x%04x: %s, %s" % (power, "connected" if power & 1 else "not connected",
                                                 "sink" if power & 2 else "source"))
        print("  data status  0x%08x: %s" % (data, "; ".join(decode_data_status(data))))
        print("  events 0x%016x pending, mask 0x%016x" % (event, mask))
        print("  => %s" % verdict(mode, status, data))
    return rc


# ---------------------------------------------------------------------------------------------
# adt: the Apple device tree. Format as in m1n1 src/adt.h: u32 property count, u32 child count,
# the properties (32-byte name, u32 size with a flag in the top bit, value padded to 4 bytes),
# then the children.

class Node:
    def __init__(self, name, props, children):
        self.name, self.props, self.children = name, props, children

    def child(self, name):
        return next((c for c in self.children if c.name == name), None)


def parse_adt(blob, pos=0, depth=0):
    if depth > 32:
        raise ValueError("ADT nested too deep")
    nprops, nchildren = struct.unpack_from("<II", blob, pos)
    if not 0 < nprops <= 4096 or nchildren > 4096:
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


def u32s(value):
    return list(struct.unpack("<%dI" % (len(value) // 4), value[:len(value) // 4 * 4]))


def cells(node, name, default):
    v = node.props.get(name)
    return u32s(v)[0] if v and len(v) >= 4 else default


def join(parts):
    return sum(c << (32 * i) for i, c in enumerate(parts))


def trail(root, path):
    t = [root]
    for part in [p for p in path.split("/") if p]:
        nxt = t[-1].child(part)
        if nxt is None:
            return None
        t.append(nxt)
    return t


def regs(t):
    """Every reg entry of the last node of trail t as (address, size), translated through the ranges
    of its parents, as m1n1's adt_get_reg() does."""
    node, parent = t[-1], t[-2]
    ac, sc = cells(parent, "#address-cells", 2), cells(parent, "#size-cells", 1)
    raw = u32s(node.props.get("reg", b""))
    out = []
    for i in range(0, len(raw) - (ac + sc) + 1, ac + sc):
        addr, size = join(raw[i:i + ac]), join(raw[i + ac:i + ac + sc])
        for depth in range(len(t) - 2, 0, -1):
            bus, above = t[depth], t[depth - 1]
            rng = bus.props.get("ranges")
            if not rng:
                continue
            ca, cs, pa = cells(bus, "#address-cells", 2), cells(bus, "#size-cells", 1), cells(above, "#address-cells", 2)
            r = u32s(rng)
            step = ca + pa + cs
            for j in range(0, len(r) - step + 1, step):
                cbase, pbase, rsize = join(r[j:j + ca]), join(r[j + ca:j + ca + pa]), join(r[j + ca + pa:j + step])
                if cbase <= addr < cbase + rsize:
                    addr = addr - cbase + pbase
                    break
        out.append((addr, size))
    return out


# What dts/t6050-k114s-common.dtsi (section K114S_R1_USB) and the shared T6050 files use.
# node: {address the Linux tree uses: what it is there}
EXPECT_REG = {
    "/arm-io/nub-spmi-a0": {0x28a188000: "spmi@28a188000 reg[0]",
                            0x28a184000: "fault queue (only with K114S_R3_USB_SPMI_FAULTS)"},
    "/arm-io/nub-spmi-a1": {0x28a1a8000: "spmi@28a1a8000 reg[0]",
                            0x28a1a4000: "fault queue (only with K114S_R3_USB_SPMI_FAULTS)"},
    "/arm-io/usb-drd1": {0x2aa280000: "usb@2aa280000 dwc3-core"},
    "/arm-io/usb-drd2": {0x382280000: "usb@382280000 dwc3-core"},
    "/arm-io/atc-phy1": {0x2ab000000: "phy@2ab000000 core"},
    "/arm-io/atc-phy2": {0x383000000: "phy@383000000 core"},
}
# port controller: (bus, SPMI address, role in the Linux tree)
EXPECT_HPM = {
    "hpm0": ("nub-spmi-a0", 0x0c, "left-back port, the debug port: not described"),
    "hpm1": ("nub-spmi-a0", 0x0a, "left-front port: usb-pd@a"),
    "hpm2": ("nub-spmi-a1", 0x0c, "right port: usb-pd@c"),
    "hpm5": ("nub-spmi-a0", 0x08, "MagSafe: not described"),
}
# Small values that identify a port, never a unit.
PRINT_VALUES = ("port-type", "port-number", "features-supported")
PRESENCE = ["/arm-io/usb-drd0", "/arm-io/usb-drd1", "/arm-io/usb-drd2", "/arm-io/usb-drd3",
            "/arm-io/atc-phy0", "/arm-io/atc-phy1", "/arm-io/atc-phy2", "/arm-io/atc-phy3",
            "/arm-io/acio0", "/arm-io/acio1", "/arm-io/acio2", "/arm-io/acio3"]


def find_adt():
    try:
        with open("/proc/mtd") as f:
            for line in f:
                dev, _size, _erase, name = line.split(None, 3)
                if name.strip().strip('"') == "adt":
                    return "/dev/" + dev.rstrip(":") + "ro"
    except (OSError, ValueError):
        pass
    return None


def probe_adt(path, names=None):
    try:
        with open(path, "rb") as f:
            blob = f.read()
    except OSError as e:
        print("cannot read %s: %s (root is needed)" % (path, e))
        return 2
    root, _ = parse_adt(blob)
    if names:
        t = trail(root, names)
        if not t:
            print("%s: not in the ADT" % names)
            return 1
        print("%s: %d properties, %d children" % (names, len(t[-1].props), len(t[-1].children)))
        for k in sorted(t[-1].props):
            print("  %-36s %5d bytes" % (k, len(t[-1].props[k])))
        for c in t[-1].children:
            print("  child %s" % c.name)
        return 0
    rc = 0
    compat = root.props.get("compatible", b"").split(b"\0")[0].decode("ascii", "replace")
    print("ADT target: %s" % compat)
    for path_, expect in EXPECT_REG.items():
        t = trail(root, path_)
        if not t:
            print("%s: MISSING from the ADT" % path_)
            rc = 1
            continue
        have = regs(t)
        print("%s: %d reg entries: %s" % (path_, len(have), " ".join("0x%x+0x%x" % r for r in have)))
        for addr, what in expect.items():
            idx = [i for i, (a, _s) in enumerate(have) if a == addr]
            if idx:
                print("  ok       0x%x is reg[%d]  (%s)" % (addr, idx[0], what))
            else:
                print("  MISMATCH 0x%x is not a reg entry  (%s)" % (addr, what))
                rc = 1
    seen = {}
    arm_io = trail(root, "/arm-io")
    for bus in arm_io[-1].children if arm_io else []:
        if not bus.name.startswith(("nub-spmi", "spmi")):
            continue
        for dev in bus.children:
            reg = u32s(dev.props.get("reg", b""))
            seen[dev.name] = (bus.name, reg[0] if reg else None)
            extra = ", ".join("%s %s" % (k, u32s(dev.props[k])) for k in PRINT_VALUES
                              if k in dev.props and len(dev.props[k]) <= 8)
            print("%s/%s: SPMI address %s%s" % (bus.name, dev.name,
                                                 "0x%02x" % reg[0] if reg else "none", ", " + extra if extra else ""))
    for name, (bus, addr, what) in EXPECT_HPM.items():
        if name not in seen:
            print("  MISMATCH %s is not in the ADT  (%s)" % (name, what))
            rc = 1
        elif seen[name] != (bus, addr):
            print("  MISMATCH %s is on %s at %s, the tree expects %s at 0x%02x  (%s)" %
                  (name, seen[name][0], "0x%02x" % seen[name][1] if seen[name][1] is not None else "none",
                   bus, addr, what))
            rc = 1
        else:
            print("  ok       %s on %s at 0x%02x  (%s)" % (name, bus, addr, what))
    present = [p.rsplit("/", 1)[1] for p in PRESENCE if trail(root, p)]
    print("present in the ADT: %s" % " ".join(present))
    print("adt: %s" % ("every USB-C value of the K114s tree matches this machine" if rc == 0 else
                       "DIFFERENCES above: do not rely on the K116s values for this board"))
    return rc


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help") or argv[1] not in ("regs", "adt"):
        print(__doc__)
        return 64
    if argv[1] == "regs":
        return probe_regs(argv[2] if len(argv) > 2 else "/sys/kernel/debug/usb/tipd")
    path, names, args = None, None, argv[2:]
    while args:
        if args[0] == "--adt" and len(args) > 1:
            path, args = args[1], args[2:]
        elif args[0] == "--names" and len(args) > 1:
            names, args = args[1], args[2:]
        else:
            print("unknown argument: %s" % args[0])
            return 64
    path = path or find_adt()
    if not path:
        print('no MTD device named "adt" in /proc/mtd: this loader does not keep the ADT')
        return 2
    return probe_adt(path, names)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
