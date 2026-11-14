#!/usr/bin/env python3
"""K114s repair: offline edits of ESP boot files, each verified by re-parsing its own output.

Python 3.9 compatible, standard library only (runs with /usr/bin/python3 on macOS).

  uki-info UKI
  uki-build OLD_UKI NEW_LINUX EXTRA_CPIO OUT   new UKI: .linux replaced, .initrd = old initrd + EXTRA_CPIO
  cpio-make OUT ARCNAME=FILE...                 an uncompressed newc archive of regular files
  fw-list FIRMWARE_CPIO                         names in a vendor firmware archive
  fw-add OLD_CPIO OUT ARCNAME=FILE...           copy of the archive with files added (never replaced)
  stage2-split COMBINED PREFIX_BYTES            report the parts of an Aura Stage 2
  stage2-build PREFIX DTB TRAILER OUT

Nothing here writes in place: every command writes a new file and refuses to overwrite.
"""
import gzip
import hashlib
import io
import json
import os
import re
import struct
import sys

FDT_MAGIC = b"\xd0\x0d\xfe\xed"


def fail(message):
    raise SystemExit("k114s_esp_tool: " + message)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def write_new(path, data):
    if os.path.lexists(path):
        fail("refusing to overwrite " + path)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
    with os.fdopen(fd, "wb") as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())


# --- PE / UKI ---------------------------------------------------------------

class Uki:
    """A unified kernel image: the systemd-stub PE with its data sections."""

    def __init__(self, data):
        self.data = data
        if data[:2] != b"MZ":
            fail("not a PE file")
        self.pe = struct.unpack_from("<I", data, 0x3C)[0]
        if data[self.pe:self.pe + 4] != b"PE\0\0":
            fail("no PE signature")
        self.nsec, = struct.unpack_from("<H", data, self.pe + 6)
        optsize, = struct.unpack_from("<H", data, self.pe + 20)
        self.opt = self.pe + 24
        if struct.unpack_from("<H", data, self.opt)[0] != 0x20B:
            fail("not PE32+")
        self.salign, self.falign = struct.unpack_from("<II", data, self.opt + 32)
        self.size_of_image, self.size_of_headers = struct.unpack_from("<II", data, self.opt + 56)
        ndirs, = struct.unpack_from("<I", data, self.opt + 108)
        if ndirs > 4:
            cert_va, cert_size = struct.unpack_from("<II", data, self.opt + 112 + 8 * 4)
            if cert_va or cert_size:
                fail("the UKI carries a certificate table (signed): not handled")
        self.table = self.opt + optsize
        self.sections = []
        for i in range(self.nsec):
            off = self.table + 40 * i
            name = data[off:off + 8].rstrip(b"\0").decode("ascii")
            vsize, va, rsize, raw = struct.unpack_from("<IIII", data, off + 8)
            self.sections.append({"name": name, "vsize": vsize, "va": va, "rsize": rsize, "raw": raw,
                                  "entry": off, "tail": data[off + 24:off + 40]})
        names = [s["name"] for s in self.sections]
        if len(set(names)) != len(names):
            fail("duplicate section names")

    def section(self, name):
        for s in self.sections:
            if s["name"] == name:
                return s
        fail("no section " + name)

    def content(self, name):
        s = self.section(name)
        if s["vsize"] > s["rsize"] and name in (".linux", ".initrd"):
            fail(name + " virtual size exceeds raw size")
        return self.data[s["raw"]:s["raw"] + min(s["vsize"], s["rsize"])]

    def info(self):
        return {"bytes": len(self.data), "sha256": sha256(self.data), "size_of_image": self.size_of_image,
                "sections": [{"name": s["name"], "va": s["va"], "vsize": s["vsize"], "raw": s["raw"],
                              "rsize": s["rsize"], "sha256": sha256(self.content(s["name"]))}
                             for s in self.sections]}


def align(value, to):
    return (value + to - 1) // to * to


def uki_build(old, new_linux, extra_cpio):
    """Replace .linux and extend .initrd. Every other byte of the stub and its sections is kept."""
    uki = Uki(old)
    order = sorted(uki.sections, key=lambda s: s["va"])
    names = [s["name"] for s in order]
    if names[-2:] != [".linux", ".initrd"]:
        fail("expected .linux and .initrd to be the last two sections, got " + ",".join(names))
    by_raw = sorted(uki.sections, key=lambda s: s["raw"])
    if [s["name"] for s in by_raw[-2:]] != [".linux", ".initrd"]:
        fail(".linux and .initrd are not the last raw data")
    linux, initrd = uki.section(".linux"), uki.section(".initrd")
    if initrd["raw"] + initrd["rsize"] != len(old):
        fail("unexpected data after .initrd")
    if new_linux[:2] != b"MZ" or new_linux[0x38:0x3C] != b"ARMd":
        fail("the new kernel is not an arm64 EFI Image")
    old_initrd = uki.content(".initrd")
    if extra_cpio[:6] != b"070701":
        fail("the extra archive is not newc cpio")
    # The kernel skips NUL padding between concatenated archives; keep the join 4-byte aligned.
    new_initrd = old_initrd + b"\0" * (-len(old_initrd) % 4) + extra_cpio
    head = bytearray(old[:linux["raw"]])
    out = io.BytesIO()
    out.write(head)
    va = linux["va"]
    placed = []
    for sec, body in ((linux, new_linux), (initrd, new_initrd)):
        raw = out.tell()
        if raw % uki.falign:
            fail("section data is not file aligned")
        out.write(body)
        out.write(b"\0" * (-len(body) % uki.falign))
        placed.append((sec, va, len(body), raw, align(len(body), uki.falign)))
        va = align(va + len(body), uki.salign)
    result = bytearray(out.getvalue())
    for sec, sva, vsize, raw, rsize in placed:
        struct.pack_into("<IIII", result, sec["entry"] + 8, vsize, sva, rsize, raw)
    struct.pack_into("<I", result, uki.opt + 56, va)  # SizeOfImage
    result = bytes(result)
    # Verify by re-parsing.
    check = Uki(result)
    if check.content(".linux") != new_linux or check.content(".initrd") != new_initrd:
        fail("rebuilt UKI does not carry the intended kernel/initrd")
    for s in uki.sections:
        if s["name"] in (".linux", ".initrd"):
            continue
        t = check.section(s["name"])
        if (t["va"], t["vsize"], t["raw"], t["rsize"]) != (s["va"], s["vsize"], s["raw"], s["rsize"]) \
                or check.content(s["name"]) != uki.content(s["name"]):
            fail("section " + s["name"] + " changed")
    spans = sorted((s["va"], s["va"] + max(s["vsize"], 1)) for s in check.sections)
    if any(b[0] < a[1] for a, b in zip(spans, spans[1:])) or spans[-1][1] > check.size_of_image:
        fail("section layout overlaps")
    # Everything before the kernel data is unchanged except SizeOfImage and the two sections'
    # size/address fields.
    masked_old, masked_new = bytearray(old[:linux["raw"]]), bytearray(result[:linux["raw"]])
    for start, length in [(uki.opt + 56, 4), (linux["entry"] + 8, 16), (initrd["entry"] + 8, 16)]:
        masked_old[start:start + length] = b"\0" * length
        masked_new[start:start + length] = b"\0" * length
    if masked_old != masked_new:
        fail("header or stub changed unexpectedly")
    return result


# --- newc cpio --------------------------------------------------------------

def newc_entry(name, data, mode, ino):
    name_b = name.encode() + b"\0"
    fields = [ino, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(name_b), 0]
    head = b"070701" + b"".join(b"%08X" % f for f in fields) + name_b
    head += b"\0" * (-len(head) % 4)
    return head + data + b"\0" * (-len(data) % 4)


def newc_parse(data):
    """-> list of (name, mode, filesize, header_offset, data_offset, end_offset) up to TRAILER."""
    entries, off = [], 0
    while True:
        if data[off:off + 6] != b"070701":
            fail("cpio: bad magic at %d" % off)
        f = [int(data[off + 6 + 8 * i:off + 14 + 8 * i], 16) for i in range(13)]
        name_size, file_size = f[11], f[6]
        name = data[off + 110:off + 110 + name_size - 1].decode()
        data_off = align(off + 110 + name_size, 4)
        end = align(data_off + file_size, 4)
        if end > len(data):
            fail("cpio: truncated entry " + name)
        entries.append((name, f[1], file_size, off, data_off, end))
        off = end
        if name == "TRAILER!!!":
            return entries, off


def cpio_make(items):
    """items: [(arcname, bytes)] -> newc archive of regular files (parents must exist already)."""
    out = b""
    for index, (name, data) in enumerate(items):
        if name.startswith("/") or ".." in name.split("/"):
            fail("bad archive name " + name)
        mode = 0o100644
        if name.endswith("+x"):  # ARCNAME+x: an executable (used by the QEMU test init only)
            name, mode = name[:-2], 0o100755
        out += newc_entry(name, data, mode, 0x4B114500 + index)
    out += newc_entry("TRAILER!!!", b"", 0, 0)
    out += b"\0" * (-len(out) % 512)
    entries, _ = newc_parse(out)
    if [e[0] for e in entries] != [n[:-2] if n.endswith("+x") else n for n, _ in items] + ["TRAILER!!!"]:
        fail("cpio self-check failed")
    return out


def fw_add(old, items):
    """Add files to a vendor firmware archive. Existing entries are kept byte for byte."""
    entries, end = newc_parse(old)
    names = {e[0] for e in entries}
    trailer = entries[-1]
    body = old[:trailer[3]]
    prefix = "vendorfw/" if any(n == "vendorfw" or n.startswith("vendorfw/") for n in names) else ""
    dirs_used = any((e[1] & 0o170000) == 0o040000 for e in entries)
    added = b""
    ino = 0x4B114600
    for name, data in items:
        full = prefix + name
        if full in names:
            fail("archive already has " + full)
        if dirs_used:
            parts = full.split("/")[:-1]
            for depth in range(1, len(parts) + 1):
                d = "/".join(parts[:depth])
                if d not in names:
                    added += newc_entry(d, b"", 0o040755, ino)
                    names.add(d)
                    ino += 1
        added += newc_entry(full, data, 0o100644, ino)
        names.add(full)
        ino += 1
    new = body + added + newc_entry("TRAILER!!!", b"", 0, 0)
    new += b"\0" * (-len(new) % 512)
    check, _ = newc_parse(new)
    old_names = [e[0] for e in entries[:-1]]
    if [e[0] for e in check[:len(old_names)]] != old_names or new[:trailer[3]] != old[:trailer[3]]:
        fail("existing firmware entries changed")
    for name, data in items:
        hit = [e for e in check if e[0] == prefix + name]
        if len(hit) != 1 or new[hit[0][4]:hit[0][4] + hit[0][2]] != data:
            fail("added firmware entry does not read back")
    return new, prefix


# --- limine.conf ------------------------------------------------------------

LIMINE_MARKER = "### K114s repair"


def limine_cmdline(conf, from_efi):
    lines = conf.split("\n")
    hits = [i for i, l in enumerate(lines) if l.strip().startswith("path:") and from_efi in l]
    if len(hits) != 1:
        fail("expected exactly one entry for %s, found %d" % (from_efi, len(hits)))
    for l in lines[hits[0] + 1:hits[0] + 6]:
        if l.strip().startswith("cmdline:"):
            return l.strip()[len("cmdline:"):].strip()
        if l.lstrip().startswith("/"):
            break
    fail("the existing entry has no cmdline line")


def limine_set_option(lines, key, value):
    first = next(i for i, l in enumerate(lines) if l.startswith("/"))
    idx = [i for i, l in enumerate(lines[:first]) if re.match(r"\s*" + key + r"\s*:", l)]
    if len(idx) > 1:
        fail("more than one %s line" % key)
    if idx:
        lines[idx[0]] = "%s: %s" % (key, value)
    else:
        lines.insert(0, "%s: %s" % (key, value))


def limine_add(conf, entries, from_efi, timeout):
    """Add first, top-level entries [(efi_path, title, comment)] that boot with the command line
    of the entry that boots FROM_EFI; make the first one the default and set the timeout.
    Every existing entry and line stays as it is."""
    lines = conf.split("\n")
    if any(LIMINE_MARKER in l for l in lines) or any(e[0] in conf for e in entries):
        fail("limine.conf already has a K114s repair entry")
    cmdline = limine_cmdline(conf, from_efi)
    first = next((i for i, l in enumerate(lines) if l.startswith("/")), None)
    if first is None:
        fail("limine.conf has no entries")
    block = []
    for efi_path, title, comment in entries:
        block += [LIMINE_MARKER + " (added from macOS; remove this block to undo)",
                  "/" + title,
                  "  comment: " + comment,
                  "  protocol: efi",
                  "  path: boot():" + efi_path,
                  "  cmdline: " + cmdline,
                  ""]
    new = lines[:first] + block + lines[first:]
    limine_set_option(new, "default_entry", "1")
    limine_set_option(new, "timeout", str(timeout))
    # Limine's quiet mode hides the menu during the timeout; show it so an entry can be chosen.
    limine_set_option(new, "quiet", "no")
    text = "\n".join(new)
    original_entries = [l for l in lines if l.startswith("/")]
    if [l for l in new if l.startswith("/")][len(entries):] != original_entries \
            or any(text.count(e[0]) != 1 for e in entries):
        fail("limine.conf self-check failed")
    return text, cmdline


def limine_default(conf, index):
    """The same limine.conf with default_entry set to INDEX (1-based)."""
    lines = conf.split("\n")
    # Limine numbers every entry in file order, directories and their sub-entries included.
    count = len([l for l in lines if l.lstrip().startswith("/")])
    if not 1 <= index <= count:
        fail("default entry %d is out of range" % index)
    limine_set_option(lines, "default_entry", str(index))
    return "\n".join(lines)


# --- Aura Stage 2 -----------------------------------------------------------

def stage2_split(combined, prefix_bytes):
    if combined[prefix_bytes:prefix_bytes + 4] != FDT_MAGIC:
        fail("no device tree right after the %d byte Aura prefix" % prefix_bytes)
    off, trees = prefix_bytes, []
    while combined[off:off + 4] == FDT_MAGIC:
        size, = struct.unpack_from(">I", combined, off + 4)
        if size < 40 or off + size > len(combined):
            fail("bad device tree length")
        trees.append(combined[off:off + size])
        off += size
    trailer = combined[off:]
    if not trailer.startswith(b"\x1f\x8b\x08"):
        fail("no gzip next stage after the device trees")
    gzip.GzipFile(fileobj=io.BytesIO(trailer)).read()
    return combined[:prefix_bytes], trees, trailer


def fdt_root_compatible(blob):
    magic, total, structure, strings = struct.unpack_from(">4I", blob)
    cursor = (structure + 8) & ~3
    while True:
        token, = struct.unpack_from(">I", blob, cursor)
        cursor += 4
        if token == 4:
            continue
        if token != 3:
            fail("device tree root has no compatible")
        size, name = struct.unpack_from(">II", blob, cursor)
        cursor += 8
        key = blob[strings + name:blob.index(b"\0", strings + name)]
        value = blob[cursor:cursor + size]
        cursor = (cursor + size + 3) & ~3
        if key == b"compatible":
            return [v.decode() for v in value.split(b"\0") if v]


def stage2_build(prefix, dtb, trailer):
    if dtb[:4] != FDT_MAGIC or struct.unpack_from(">I", dtb, 4)[0] != len(dtb):
        fail("not a single device tree blob")
    compat = fdt_root_compatible(dtb)
    if compat[:2] != ["apple,k114s", "apple,t6050"]:
        fail("device tree is not apple,k114s: %r" % compat)
    image = prefix + dtb + trailer
    if len(image) > 16 << 20:
        fail("Stage 2 exceeds Aura's 16 MiB slot")
    p, trees, t = stage2_split(image, len(prefix))
    if p != prefix or trees != [dtb] or t != trailer:
        fail("Stage 2 self-check failed")
    return image


# --- command line -----------------------------------------------------------

def read(path):
    with open(path, "rb") as stream:
        return stream.read()


def pairs(arguments):
    out = []
    for item in arguments:
        name, _, path = item.partition("=")
        if not name or not path:
            fail("expected ARCNAME=FILE, got " + item)
        out.append((name, read(path)))
    return out


def main(argv):
    if len(argv) < 2:
        fail(__doc__)
    cmd, args = argv[1], argv[2:]
    if cmd == "uki-info":
        print(json.dumps(Uki(read(args[0])).info(), indent=1))
    elif cmd == "uki-build":
        old, linux, extra, out = args
        result = uki_build(read(old), read(linux), read(extra))
        write_new(out, result)
        print(json.dumps({"out": out, "bytes": len(result), "sha256": sha256(result)}))
    elif cmd == "cpio-make":
        result = cpio_make(pairs(args[1:]))
        write_new(args[0], result)
        print(json.dumps({"out": args[0], "bytes": len(result), "sha256": sha256(result)}))
    elif cmd == "fw-list":
        entries, _ = newc_parse(read(args[0]))
        for name, mode, size, _, data_off, _ in entries:
            print("%06o %9d %s" % (mode, size, name))
    elif cmd == "fw-add":
        result, prefix = fw_add(read(args[0]), pairs(args[2:]))
        write_new(args[1], result)
        print(json.dumps({"out": args[1], "bytes": len(result), "sha256": sha256(result), "prefix": prefix}))
    elif cmd == "stage2-split":
        prefix, trees, trailer = stage2_split(read(args[0]), int(args[1]))
        print(json.dumps({"prefix_sha256": sha256(prefix), "trailer_sha256": sha256(trailer),
                          "trees": [{"compatible": fdt_root_compatible(t)[0], "bytes": len(t),
                                     "sha256": sha256(t)} for t in trees]}, indent=1))
    elif cmd == "stage2-build":
        image = stage2_build(read(args[0]), read(args[1]), read(args[2]))
        write_new(args[3], image)
        print(json.dumps({"out": args[3], "bytes": len(image), "sha256": sha256(image)}))
    else:
        fail("unknown command " + cmd)


if __name__ == "__main__":
    main(sys.argv)
