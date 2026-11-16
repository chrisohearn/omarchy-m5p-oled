#!/usr/bin/python3 -I
# SPDX-License-Identifier: MIT
"""k114s-adt.py: read this Mac's Apple device tree (ADT) from Linux, read only.

The boot chain keeps the ADT iBoot handed over and exposes it as the MTD partition "adt"
(/proc/mtd). Its device node is readable by root only, so run this with sudo, or give it a copy
with --adt FILE. Nothing is written except the output file you name.

    sudo build/k114s-adt.py show NAME [NAME...]       print the nodes with these names
    sudo build/k114s-adt.py sound-report              print the nodes the sound port relies on
    sudo build/k114s-adt.py firmware-report [--json]  list every coprocessor firmware identity (names, build UUIDs, segments)
    sudo build/k114s-adt.py pmp-dtsi --names-from KTREE/arch/arm64/boot/dts/apple/t6050-j714s-pmp-tunables.dtsi \
                                     -o KTREE/arch/arm64/boot/dts/apple/t6050-k114s-pmp-tunables.dtsi

The ADT and everything printed from it are Apple's data about one Mac: keep dumps and the
generated file out of the repository (docs/r3-sound.md).
"""
import argparse
import fnmatch
import re
import struct
import sys

MAX_ADT = 8 << 20
BOARD_ID_K114S = 0x14

# Nodes the sound port takes values from (docs/r3-sound.md, "Values to confirm").
SOUND_NODES = [
    "audio-codec-output", "audio-speaker*", "admac-base-ns", "admac-hp-mic-ec-proxy",
    "admac-leap-s", "audio-hp-mic", "aop", "aop-exclave-mailbox", "dart-aop", "pmp0", "dart-pmp0",
    "iop-audio-controller", "audio",
]


class AdtError(Exception):
    pass


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


def parse(data, off=0, depth=0):
    """One node at @off: ({"name", "props", "children"}, end offset)."""
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


def load(path=None):
    path = path or mtd_path()
    if not path:
        raise AdtError("the boot chain exposes no ADT (no \"adt\" partition in /proc/mtd); use --adt FILE")
    try:
        with open(path, "rb") as f:
            data = f.read(MAX_ADT)
    except PermissionError:
        raise AdtError(f"cannot read {path}: run with sudo") from None
    except OSError as e:
        raise AdtError(f"cannot read {path}: {e}") from None
    return parse(data)[0]


def walk(node, path=""):
    here = path + "/" + node["name"] if path or node["name"] != "device-tree" else ""
    yield here or "/", node
    for c in node["children"]:
        yield from walk(c, here)


def by_path(root, path):
    node = root
    for part in [p for p in path.split("/") if p]:
        for c in node["children"]:
            if c["name"] == part:
                node = c
                break
        else:
            return None
    return node


def u32(node, prop, where):
    v = node["props"].get(prop) if node else None
    if v is None or len(v) != 4:
        raise AdtError(f"ADT {where} has no 4-byte {prop!r}")
    return struct.unpack("<I", v)[0]


def hexbytes(v):
    return " ".join(f"{b:02x}" for b in v)


def fmt_value(v, limit):
    text = ""
    body = v.rstrip(b"\0")
    if body and all(32 <= b < 127 or b == 0 for b in body) and len(v) - len(body) <= 4:
        text = "  \"" + body.replace(b"\0", b"\\0").decode("ascii") + "\""
    shown = v if limit is None or len(v) <= limit else v[:limit]
    more = "" if len(shown) == len(v) else f" ... ({len(v)} bytes)"
    return f"[{hexbytes(shown)}]{more}{text}"


def check_board(root, any_board):
    chosen = by_path(root, "/chosen")
    board = u32(chosen, "board-id", "/chosen")
    if board != BOARD_ID_K114S and not any_board:
        raise AdtError(f"this ADT is board-id 0x{board:x}, not the K114s (0x{BOARD_ID_K114S:x}); "
                       "refusing (--any-board overrides)")
    return chosen, board


def cmd_show(root, args):
    pats = args.names
    n = 0
    for path, node in walk(root):
        if not any(fnmatch.fnmatchcase(node["name"], p) for p in pats):
            continue
        n += 1
        print(path)
        for name in sorted(node["props"]):
            if name in ("name", "AAPL,phandle") and not args.all:
                continue
            print(f"    {name} = {fmt_value(node['props'][name], None if args.full else 64)}")
    if not n:
        print("no node with that name", file=sys.stderr)
        return 1
    return 0


def tunable_names(path):
    names = []
    with open(path) as f:
        for line in f:
            m = re.match(r"\s*apple,tunable-([A-Za-z0-9_,.+-]+)\s*(=|;)", line)
            if m and m.group(1) not in names:
                names.append(m.group(1))
    if not names:
        raise AdtError(f"{path} names no apple,tunable-* property")
    return names


def cmd_pmp_dtsi(root, args):
    chosen, board = check_board(root, args.any_board)
    dram = u32(chosen, "dram-vendor-id", "/chosen")
    pmgr = by_path(root, "/arm-io/pmgr")
    pmc = args.pmc if args.pmc is not None else u32(pmgr, "pmc", "/arm-io/pmgr")
    pmc_pmgr = args.pmc_pmgr if args.pmc_pmgr is not None else u32(pmgr, "pmc-pmgr", "/arm-io/pmgr")
    nub = by_path(root, "/arm-io/pmp0/iop-pmp0-nub")
    if nub is None:
        raise AdtError("ADT has no /arm-io/pmp0/iop-pmp0-nub")
    names = tunable_names(args.names_from)
    missing = [n for n in names if n not in nub["props"]]
    extra = sorted(set(nub["props"]) - set(names) - {"name", "AAPL,phandle", "compatible"})
    out = [
        "// SPDX-License-Identifier: GPL-2.0+ OR MIT",
        "/*",
        " * K114s PMP values: /chosen, /arm-io/pmgr and the /arm-io/pmp0/iop-pmp0-nub properties the",
        " * firmware queries by name at boot (pmp.rs serves apple,tunable-<name>). Raw ADT bytes,",
        " * generated by build/k114s-adt.py pmp-dtsi from this Mac's own ADT. One Mac's data: not",
        " * part of the repository.",
        " */",
        "",
        "&pmp0 {",
        "\t/* ADT /chosen board-id, dram-vendor-id */",
        f"\tapple,board-id = <{board}>;",
        f"\tapple,dram-vendor-id = <{dram}>;",
        "\t/* ADT /arm-io/pmgr pmc, pmc-pmgr */",
        f"\tapple,pmc = <{pmc}>;",
        f"\tapple,pmc-pmgr = <{pmc_pmgr}>;",
    ]
    for n in names:
        if n in missing:
            continue
        v = nub["props"][n]
        out.append(f"\tapple,tunable-{n} = [{hexbytes(v)}];" if v else f"\tapple,tunable-{n};")
    out += ["};", ""]
    text = "\n".join(out)
    if args.output and args.output != "-":
        with open(args.output, "w") as f:
            f.write(text)
    else:
        sys.stdout.write(text)
    log = sys.stderr
    print(f"k114s-adt: board-id {board}, dram-vendor-id {dram}, pmc {pmc}, pmc-pmgr {pmc_pmgr}, "
          f"{len(names) - len(missing)} of {len(names)} firmware properties", file=log)
    if extra:
        print("k114s-adt: in the ADT but not in the name list (not written): " + " ".join(extra), file=log)
    if missing:
        print("k114s-adt: in the name list but not in this ADT: " + " ".join(missing), file=log)
        if not args.allow_missing:
            print("k114s-adt: refusing to call that complete (--allow-missing accepts it)", file=log)
            return 1
    return 0


def cmd_sound_report(root, args):
    chosen, board = check_board(root, args.any_board)
    print(f"/chosen board-id = 0x{board:x}")
    for p in ("dram-vendor-id", "chip-id"):
        if p in chosen["props"]:
            print(f"/chosen {p} = {fmt_value(chosen['props'][p], 64)}")
    args.names, args.all = SOUND_NODES, False
    return cmd_show(root, args)


FW_PROPS = ("firmware-name", "firmware-type", "uuid", "segment-names")


def _cstr(v):
    return v.split(b"\0", 1)[0].decode("ascii", "replace")


def firmware_identities(root):
    """Every ADT node that names a firmware image: path, firmware-name, type, build UUID, segment names.

    Identity only: the ADT also holds segment address ranges and the loaded images' sizes, which are
    this boot's memory layout and are not reported. No firmware bytes are read or written.
    """
    rows = []
    for path, node in walk(root):
        pr = node["props"]
        if "uuid" not in pr and "firmware-name" not in pr:
            continue
        row = {"path": path}
        for k in FW_PROPS:
            if k in pr:
                v = _cstr(pr[k])
                row[k.replace("-", "_")] = v.split(";") if k == "segment-names" else v
        rows.append(row)
    return rows


def cmd_firmware_report(root, args):
    chosen, board = check_board(root, args.any_board)
    rows = firmware_identities(root)
    if args.json:
        import json
        print(json.dumps({"board_id": hex(board), "firmware": rows}, indent=1, sort_keys=True))
        return 0
    print(f"/chosen board-id = 0x{board:x}; {len(rows)} nodes name a firmware image")
    for r in rows:
        print(r["path"])
        for k in ("firmware_name", "firmware_type", "uuid"):
            if k in r:
                print(f"    {k.replace('_', '-')} = {r[k]}")
        if "segment_names" in r:
            print("    segments = " + " ".join(r["segment_names"]))
    return 0


def main():
    ap = argparse.ArgumentParser(prog="k114s-adt.py", description=__doc__.split("\n\n")[0])
    ap.add_argument("--adt", help="an ADT file instead of the \"adt\" MTD partition")
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("show", help="print the nodes with these names (shell patterns)")
    s.add_argument("names", nargs="+")
    s.add_argument("--full", action="store_true", help="do not shorten long values")
    s.add_argument("--all", action="store_true", help="also print name and AAPL,phandle")
    s = sub.add_parser("sound-report", help="print the nodes the sound port relies on")
    s.add_argument("--full", action="store_true")
    s.add_argument("--any-board", action="store_true")
    s = sub.add_parser("firmware-report", help="list the firmware identities the ADT names (no firmware bytes)")
    s.add_argument("--json", action="store_true")
    s.add_argument("--any-board", action="store_true")
    s = sub.add_parser("pmp-dtsi", help="write t6050-k114s-pmp-tunables.dtsi from this ADT")
    s.add_argument("--names-from", required=True,
                   help="an upstream t6050-*-pmp-tunables.dtsi: its property names are the ones written")
    s.add_argument("-o", "--output", default="-")
    s.add_argument("--pmc", type=lambda x: int(x, 0), help="override ADT /arm-io/pmgr pmc")
    s.add_argument("--pmc-pmgr", type=lambda x: int(x, 0), help="override ADT /arm-io/pmgr pmc-pmgr")
    s.add_argument("--allow-missing", action="store_true")
    s.add_argument("--any-board", action="store_true")
    args = ap.parse_args()
    try:
        root = load(args.adt)
        return {"show": cmd_show, "sound-report": cmd_sound_report, "pmp-dtsi": cmd_pmp_dtsi,
                "firmware-report": cmd_firmware_report}[args.cmd](root, args)
    except AdtError as e:
        print(f"k114s-adt: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
