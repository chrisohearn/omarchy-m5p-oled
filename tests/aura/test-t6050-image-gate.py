#!/usr/bin/env python3
"""Host test of the loader's DCP image gate after the hand merge (patches/aura 0001).

    python3 tests/aura/test-t6050-image-gate.py AURA_TREE      (aura 22b71758 + betizzel's seven + patches/aura)

Upstream's host fixture does not model the T6050 hand-off, so nothing there runs the gate that
decides whether the panel leaves the boot framebuffer. This test takes the gate's own source text
out of AURA_TREE/src/kboot_display_handoff.c (the pin table, dcp6_is_uuid() and the block of
t6050_check_adt() from the OS firmware test to the "DCP image" log line), compiles it with the
host compiler around a small driver and runs it for each OS firmware and image. It checks which
images are admitted, which are refused, and whether the external engines would be handed off.
A replica test: it proves the logic of the merged text, not the loader on the Mac.
"""
import os
import re
import subprocess
import sys
import tempfile

DRIVER = r'''
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef uint32_t u32;
typedef uint64_t u64;
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
enum fw_version { V_UNKNOWN, V26_7, V27_0, V27_2, V27_3B };
struct fw_version_info { enum fw_version version; const char *string; u32 num[5]; size_t num_length; const char *iboot; };
static struct fw_version_info os_firmware;
static const struct fw_version_info t6050_compat_27_3 = {V27_3B, "27.3", {27, 3, 0}, 3, "compat"};
static struct { char uuid[40]; const struct fw_version_info *compat; bool ext; } t6050;
#define dlog(...) printf(__VA_ARGS__)
#define bail(...) do { printf(__VA_ARGS__); return -1; } while (0)
%(is_uuid)s
%(table)s
static int gate(const char *uuid, u32 len)
{
%(gate)s
    return 0;
}
int main(int argc, char **argv)
{
    static const struct fw_version_info fw[] = {
        {V26_7, "26.7", {26, 7, 0}, 3, ""}, {V27_0, "27.0", {27, 0, 0}, 3, ""},
        {V27_2, "27.2", {27, 2, 0}, 3, ""}, {V27_3B, "27.3 beta", {27, 3, 0}, 3, ""},
    };
    for (size_t i = 0; i < ARRAY_SIZE(fw); i++)
        if (!strcmp(argv[1], fw[i].string))
            os_firmware = fw[i];
    memset(&t6050, 0, sizeof(t6050));
    const char *uuid = argc > 2 && strcmp(argv[2], "-") ? argv[2] : NULL;
    int ret = gate(uuid, uuid ? (u32)strlen(uuid) + 1 : 0);
    printf("RESULT %%d ext=%%d uuid=%%s compat=%%s\n", ret, t6050.ext, t6050.uuid,
           ret ? "-" : t6050.compat->string);
    return 0;
}
'''

J27_0 = "64863924-B56B-3E32-87FE-038677F52709"
J27_2 = "C51FB0C8-C45D-39B0-85BC-520E600FC950"
K27_2 = "3D6C8857-E6F1-3D2E-9DFF-587028AE0C6E"
OTHER = "11111111-2222-3333-4444-555555555555"

# (OS firmware, image) -> (admitted, external engines handed off, firmware-compat published)
CASES = [
    ("27.0", J27_0, True, True, "27.0"),
    ("27.0", K27_2, False, None, None),     # a 27.2 image is not admitted under 27.0
    ("27.0", OTHER, False, None, None),
    ("27.2", J27_2, True, True, "27.2"),    # betizzel's J714s pin survives the merge, with its external engines
    ("27.2", K27_2, True, False, "27.2"),   # the K116s image of pull request 226: internal panel only
    ("27.2", J27_0, False, None, None),     # the 27.0 image is not admitted under 27.2
    ("27.2", OTHER, False, None, None),     # an unknown 27.2 image: refused, boot framebuffer
    ("27.2", "3d6c8857-e6f1-3d2e-9dff-587028ae0c6e", False, None, None),  # exact match only
    ("27.2", "3D6C8857-E6F1-3D2E-9DFF-587028AE0C6", False, None, None),   # malformed
    ("27.2", "-", False, None, None),       # no uuid property at all
    ("27.3 beta", OTHER, True, True, "27.3"),   # unpinned, as before the merge
    ("26.7", K27_2, False, None, None),     # an OS firmware the hand-off does not know
]


def extract(source):
    start = source.index("static bool dcp6_is_uuid(const char *s, u32 len)")
    is_uuid = source[start:source.index("\n}\n", start) + 3]
    m = re.search(r"static const struct \{\n    u32 os_fw;.*?\} t6050_images\[\] = \{.*?\n\};\n", source, re.S)
    if not m:
        raise SystemExit("no t6050_images table: is patches/aura 0001 applied?")
    start = source.index("    if (os_firmware.version != V27_0 && os_firmware.version != V27_2 &&")
    end_marker = 'dlog("DCP image %s, firmware-compat %s\\n", t6050.uuid, t6050.compat->string);\n'
    end = source.index(end_marker, start) + len(end_marker)
    return is_uuid, m.group(0), source[start:end]


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    source = open(os.path.join(sys.argv[1], "src", "kboot_display_handoff.c")).read()
    is_uuid, table, gate = extract(source)
    bad = 0
    with tempfile.TemporaryDirectory() as tmp:
        c_file, binary = os.path.join(tmp, "gate.c"), os.path.join(tmp, "gate")
        open(c_file, "w").write(DRIVER % {"is_uuid": is_uuid, "table": table, "gate": gate})
        subprocess.run([os.environ.get("CC", "cc"), "-std=gnu11", "-Wall", "-Wextra", "-Werror", "-O1",
                        "-fsanitize=address,undefined", "-fno-sanitize-recover=undefined", "-o", binary, c_file],
                       check=True)
        for fw, uuid, admitted, ext, compat in CASES:
            out = subprocess.run([binary, fw, uuid], check=True, capture_output=True, text=True).stdout
            result = re.search(r"RESULT (-?\d+) ext=(\d) uuid=(\S*) compat=(\S+)", out)
            ok = result is not None and (result.group(1) == "0") == admitted
            if ok and admitted:
                ok = (result.group(2) == "1") == ext and result.group(3) == uuid and result.group(4) == compat
            if ok and not admitted:
                # a refusal must say why, and must name a well-formed image so it can be reviewed
                ok = "is not" in out and (uuid in out or uuid == "-" or len(uuid) != 36 or "OS firmware" in out)
            print("%s  OS firmware %-9s image %-36s -> %s" % (
                "ok  " if ok else "FAIL", fw, uuid,
                ("admitted, external engines %s" % ("handed off" if ext else "left to iBoot")) if admitted else "refused"))
            if not ok:
                bad += 1
                print(out)
    print("loader image gate test:", "FAILED" if bad else "passed", "(%d cases)" % len(CASES))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
