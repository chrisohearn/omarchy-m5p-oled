#!/usr/bin/env python3
"""List what differs between two compiled device trees, node by node.

usage: dtb-node-diff.py OLD.dtb NEW.dtb

Prints nodes only in NEW (with their properties' names), nodes only in OLD, and for nodes in both
the properties added, removed or changed. Property values are shown when short (up to 24 bytes),
by size otherwise. Phandle numbers are compared by the node they point at, because dtc
renumbers them when a node is added; the phandle properties themselves are not listed.
"""
import struct, sys


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
            v = b[p:p + ln]
            p = (p + ln + 3) & ~3
            nodes["/".join(path) or "/"][strs[no:strs.index(b"\0", no)].decode()] = v
        elif tok == 2:
            path.pop()
        elif tok == 9:
            break
    return nodes


def phandle_map(nodes):
    return {struct.unpack(">I", props["phandle"])[0]: path for path, props in nodes.items() if "phandle" in props}


def canon(v, pmap):
    """A value with every cell that names a phandle replaced by the node's path, so that dtc
    renumbering phandles after a node was added is not reported as a change."""
    if len(v) % 4 or not v:
        return v
    cells = struct.unpack(">%dI" % (len(v) // 4), v)
    return tuple(pmap.get(c, c) if c > 0x40 else c for c in cells)


def show(v):
    if len(v) > 24:
        return "%d bytes" % len(v)
    if v and v.endswith(b"\0") and all(32 <= c < 127 or c == 0 for c in v):
        return '"%s"' % v[:-1].decode().replace("\0", '", "')
    return "<" + " ".join("0x%x" % x for x in struct.unpack(">%dI" % (len(v) // 4), v)) + ">" if len(v) % 4 == 0 else v.hex()


def main(a, b):
    old, new = walk(open(a, "rb").read()), walk(open(b, "rb").read())
    pold, pnew = phandle_map(old), phandle_map(new)
    only_new = [n for n in new if n not in old]
    only_old = [n for n in old if n not in new]
    for n in only_new:
        print("ADDED   %s  (%s)" % (n, ", ".join(sorted(new[n]))))
    for n in only_old:
        print("REMOVED %s" % n)
    for n in new:
        if n not in old:
            continue
        o, m = old[n], new[n]
        for k in sorted(set(o) | set(m)):
            if k in o and k in m and (o[k] == m[k] or (k != "phandle" and canon(o[k], pold) == canon(m[k], pnew))):
                continue
            if k == "phandle":
                continue
            if k not in o:
                print("PROP+   %s  %s = %s" % (n, k, show(m[k])))
            elif k not in m:
                print("PROP-   %s  %s (was %s)" % (n, k, show(o[k])))
            else:
                print("PROP~   %s  %s: %s -> %s" % (n, k, show(o[k]), show(m[k])))
    print("summary: %d nodes added, %d removed" % (len(only_new), len(only_old)))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
