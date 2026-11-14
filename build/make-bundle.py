#!/usr/bin/env python3
"""Assemble an apply-ready bundle from this repository plus the binary payload.

    make-bundle.py REPO PAYLOAD_DIR OUT_DIR

REPO         this repository
PAYLOAD_DIR  the built binaries (kernels, modules, device trees, Stage 2 files, firmware). They
             are not in the repository: kernel and loader binaries are built from the pinned
             sources, and the Apple firmware is extracted from Apple's restore image on the
             owner's side. Every file is checked against manifests/payload-r1.json.
OUT_DIR      must not exist; becomes the bundle (k114s-repair, tools/, linux/, src/, payload/,
             manifest.json, README.md, SHA256SUMS)

Also writes REPO/manifests/<revision>.json: the bundle's manifest, hashes only.
Python 3.9, standard library only.
"""
import hashlib
import json
import os
import shutil
import sys
import time

REVISION = "r2"
LINUX = ("linux-persist.sh", "update-boot-ctxr-k114s", "apply-holds", "hold-guard", "00-k114s-hold-guard.hook",
         "k114s-booted-esp", "k114s-edge-check", "README-linux.txt")


def sha(path):
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def main(repo, payload_dir, out):
    if os.path.exists(out):
        sys.exit("make-bundle: %s already exists; a bundle is never rebuilt in place" % out)
    base = json.load(open(os.path.join(repo, "manifests", "payload-r1.json")))
    for name, digest in sorted(base["payload"].items()):
        if sha(os.path.join(payload_dir, name)) != digest:
            sys.exit("make-bundle: payload file %s does not match manifests/payload-r1.json" % name)
    os.makedirs(os.path.join(out, "payload"))
    for name in sorted(base["payload"]):
        shutil.copyfile(os.path.join(payload_dir, name), os.path.join(out, "payload", name))
    shutil.copytree(os.path.join(repo, "macos", "tools"), os.path.join(out, "tools"),
                    ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copy2(os.path.join(repo, "macos", "k114s-repair"), os.path.join(out, "k114s-repair"))
    os.makedirs(os.path.join(out, "linux"))
    for name in LINUX:
        shutil.copy2(os.path.join(repo, "linux", name), os.path.join(out, "linux", name))
    os.makedirs(os.path.join(out, "src"))
    for folder in ("dts", os.path.join("patches", "linux")):
        for name in sorted(os.listdir(os.path.join(repo, folder))):
            shutil.copy2(os.path.join(repo, folder, name), os.path.join(out, "src", name))
    shutil.copy2(os.path.join(repo, "build", "kernel-build-scripts.txt"), os.path.join(out, "src", "build-scripts.txt"))
    shutil.copy2(os.path.join(repo, "docs", "bundle-" + REVISION + ".md"), os.path.join(out, "README.md"))

    manifest = dict(base)
    manifest["name"] = "K114s repair " + REVISION
    manifest["revision"] = REVISION
    manifest["built"] = time.strftime("%Y-%m-%d")
    manifest["boot_files"] = "identical to r1 (same payload hashes)"
    manifest["linux"] = {name: sha(os.path.join(out, "linux", name)) for name in LINUX}
    sources = dict(base["sources"])
    sources["linux_side"] = ("omarchy-m5p-oled linux/: hold set and guard hook, owner-boot-chain declaration "
                             "(omacom/omarchy-mac-pkgs 7e50e937 update-verify), booted-ESP check adapted from "
                             "betizzel/omarchy-m5 aurora-boot-mounts-generator (0abeef96, MIT), read-only upgrade "
                             "solve after nickfoy/omarchy-m3-max lib/update_preflight.py (8c16310)")
    manifest["sources"] = sources
    with open(os.path.join(out, "manifest.json"), "w") as stream:
        json.dump(manifest, stream, indent=1)
        stream.write("\n")

    lines = []
    for folder, _, files in sorted(os.walk(out)):
        for name in sorted(files):
            path = os.path.join(folder, name)
            lines.append("%s  ./%s\n" % (sha(path), os.path.relpath(path, out)))
    with open(os.path.join(out, "SHA256SUMS"), "w") as stream:
        stream.writelines(lines)
    shutil.copyfile(os.path.join(out, "manifest.json"), os.path.join(repo, "manifests", REVISION + ".json"))
    print("make-bundle: %s (%d files); manifest copied to manifests/%s.json" % (out, len(lines) + 1, REVISION))


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
