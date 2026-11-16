#!/usr/bin/python3 -I
# SPDX-License-Identifier: MIT
"""k114s-firmware-check.py: compare this Mac's firmware files and ADT firmware identities with
manifests/k114s-firmware.json. Read only; prints names, hashes and PASS/FAIL, never firmware bytes.

    sudo python3 -I tests/hardware/k114s-firmware-check.py [--root /] [--adt FILE] [--manifest FILE]

Exit 0 when every file and every ADT identity matches, 1 otherwise, 2 when an input cannot be read.
With --root the files are read under that directory (the replica test uses a fake root).
"""
import argparse
import hashlib
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))


def load_adt_module():
    spec = importlib.util.spec_from_file_location("k114s_adt", os.path.join(REPO, "build", "k114s-adt.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="/")
    ap.add_argument("--adt")
    ap.add_argument("--manifest", default=os.path.join(REPO, "manifests", "k114s-firmware.json"))
    args = ap.parse_args()
    with open(args.manifest) as f:
        man = json.load(f)
    bad = 0

    def report(ok, what):
        nonlocal bad
        print(("PASS " if ok else "FAIL ") + what)
        bad += 0 if ok else 1

    for e in man["files"]:
        p = os.path.join(args.root, "lib/firmware", e["name"])
        if not os.path.isfile(p):
            report(False, f"file {e['name']}: missing")
            continue
        try:
            got = sha256(p)
        except PermissionError:
            print(f"cannot read {p}: run with sudo", file=sys.stderr)
            return 2
        report(got == e["sha256"], f"file {e['name']} ({e['consumer']})" + ("" if got == e["sha256"] else f": sha256 {got[:12]} differs"))

    adt = load_adt_module()
    try:
        root = adt.load(args.adt)
        _, board = adt.check_board(root, False)
    except adt.AdtError as e:
        print(f"k114s-firmware-check: {e}", file=sys.stderr)
        return 2
    live = {r["path"]: r for r in adt.firmware_identities(root)}
    for e in man["adt"]:
        r = live.get(e["path"])
        if r is None:
            report(False, f"adt {e['path']}: node absent")
            continue
        diffs = [k for k in ("firmware_name", "firmware_type", "uuid", "segment_names") if r.get(k) != e.get(k)]
        report(not diffs, f"adt {e['path']} {e.get('firmware_name', '')}".rstrip() + (f": differs in {', '.join(diffs)}" if diffs else ""))
    print(f"firmware check: board 0x{board:x}, {len(man['files'])} files, {len(man['adt'])} ADT identities, {bad} failed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
