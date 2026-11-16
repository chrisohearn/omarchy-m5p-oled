#!/usr/bin/env python3
"""Replica test of build/k114s-adt.py firmware-report and tests/hardware/k114s-firmware-check.py.

    python3 tests/test-firmware-check.py

Builds a made-up ADT (a made-up board-id 0x14, made-up UUIDs) and a fake /lib/firmware with made-up
bytes, then proves the checker passes on a match and fails on: a changed file, a missing file, a
changed ADT UUID, a missing ADT node. It also fails if the report prints the made-up serial number.
No Apple data is used: this proves the reading and the comparisons, not anything about a real Mac.
"""
import hashlib
import importlib.util
import io
import json
import os
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)


def node(name, props=(), children=()):
    props = [("name", name.encode() + b"\0")] + list(props)
    p = b"".join(n.encode().ljust(32, b"\0") + struct.pack("<I", len(v)) + v + b"\0" * (-len(v) % 4) for n, v in props)
    return struct.pack("<II", len(props), len(children)) + p + b"".join(children)


def adt(uuid="11111111-2222-3333-4444-555555555555", with_aop=True):
    aop_nub = node("iop-aop-nub", [("serial-number", b"ZZTESTSERIAL0\0"), ("firmware-name", b"k114saop\0"), ("firmware-type", b"scrt\0"),
                                  ("uuid", uuid.encode() + b"\0"), ("segment-names", b"__TEXT;__DATA\0")])
    kids = [node("aop", children=[aop_nub])] if with_aop else []
    return node("device-tree", [("serial-number", b"ZZTESTSERIAL0\0")],
                [node("chosen", [("board-id", struct.pack("<I", 0x14))]), node("arm-io", children=kids)])


fails = 0


def check(cond, what):
    global fails
    print(("ok   " if cond else "FAIL ") + what)
    fails += 0 if cond else 1


with tempfile.TemporaryDirectory(prefix="k114fw.") as d:
    fw = os.path.join(d, "root", "lib", "firmware", "apple")
    os.makedirs(fw)
    blob = b"made-up firmware bytes"
    open(os.path.join(fw, "a.bin"), "wb").write(blob)
    open(os.path.join(fw, "cal-0001"), "wb").write(b"made-up calibration")
    open(os.path.join(fw, "pkg.bin"), "wb").write(b"pkg v1")
    man = {"files": [{"name": "apple/a.bin", "sha256": hashlib.sha256(blob).hexdigest(), "consumer": "test"},
                     {"name": "apple/cal-*", "per_unit": True, "consumer": "test cal"},
                     {"name": "apple/pkg.bin", "sha256": hashlib.sha256(b"pkg v1").hexdigest(), "package_owned": True, "consumer": "test pkg"}],
           "adt": [{"path": "/arm-io/aop/iop-aop-nub", "firmware_name": "k114saop", "firmware_type": "scrt",
                    "uuid": "11111111-2222-3333-4444-555555555555", "segment_names": ["__TEXT", "__DATA"]}]}
    mpath = os.path.join(d, "m.json")
    json.dump(man, open(mpath, "w"))

    def run(adt_bytes):
        ap = os.path.join(d, "adt.bin")
        open(ap, "wb").write(adt_bytes)
        r = subprocess.run([sys.executable, "-I", os.path.join(REPO, "tests/hardware/k114s-firmware-check.py"),
                            "--root", os.path.join(d, "root"), "--adt", ap, "--manifest", mpath],
                           capture_output=True, text=True)
        return r.returncode, r.stdout + r.stderr

    rc, out = run(adt())
    check(rc == 0 and "0 failed" in out, "matching files and ADT pass")
    check("ZZTESTSERIAL0" not in out, "the checker does not print the serial number")
    open(os.path.join(fw, "pkg.bin"), "wb").write(b"pkg v2")
    rc, out = run(adt())
    check(rc == 0 and "INFO file apple/pkg.bin" in out, "a changed package-owned file is INFO, not FAIL")
    open(os.path.join(fw, "cal-0001"), "wb").write(b"")
    rc, out = run(adt())
    check(rc == 1 and "missing or empty" in out, "an empty per-unit file fails")
    open(os.path.join(fw, "cal-0001"), "wb").write(b"other unit's calibration")
    rc, out = run(adt())
    check(rc == 0, "a per-unit file passes whatever its bytes")
    rc, out = run(adt(uuid="99999999-2222-3333-4444-555555555555"))
    check(rc == 1 and "differs in uuid" in out, "a changed ADT UUID fails")
    rc, out = run(adt(with_aop=False))
    check(rc == 1 and "node absent" in out, "a missing ADT node fails")
    open(os.path.join(fw, "a.bin"), "wb").write(blob + b"x")
    rc, out = run(adt())
    check(rc == 1 and "differs" in out, "a changed file fails")
    os.unlink(os.path.join(fw, "a.bin"))
    rc, out = run(adt())
    check(rc == 1 and "missing" in out, "a missing file fails")

    spec = importlib.util.spec_from_file_location("k", os.path.join(REPO, "build/k114s-adt.py"))
    k = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(k)
    ap = os.path.join(d, "adt2.bin")
    open(ap, "wb").write(adt())
    for extra in ([], ["--json"]):
        r = subprocess.run([sys.executable, os.path.join(REPO, "build/k114s-adt.py"), "--adt", ap, "firmware-report"] + extra,
                           capture_output=True, text=True)
        check(r.returncode == 0 and "k114saop" in r.stdout and "ZZTESTSERIAL0" not in r.stdout + r.stderr,
              f"firmware-report {' '.join(extra)}".strip() + " prints the identity and no serial number")
    root = k.parse(adt())[0]
    rows = k.firmware_identities(root)
    check(len(rows) == 1 and rows[0]["firmware_name"] == "k114saop" and rows[0]["segment_names"] == ["__TEXT", "__DATA"],
          "firmware_identities reads name, type, uuid, segments")

print(f"firmware-check tests: {'FAILED' if fails else 'passed'} ({fails} failed)")
sys.exit(1 if fails else 0)
