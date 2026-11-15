#!/usr/bin/python3 -I
"""Build a small flattened device tree for the r3 tests (the image has no dtc).

usage: mkfdt.py OUT VARIANT     VARIANT: k114s-full | k114s-bare | j714s
"""
import struct
import sys


def fdt(tree):
    strings = b""
    offsets = {}

    def name_offset(name):
        nonlocal strings
        if name not in offsets:
            offsets[name] = len(strings)
            strings += name.encode() + b"\0"
        return offsets[name]

    def pad(data):
        return data + b"\0" * (-len(data) % 4)

    def node(name, body):
        out = struct.pack(">I", 1) + pad(name.encode() + b"\0")
        for key, value in body.items():
            if isinstance(value, dict):
                continue
            if isinstance(value, str):
                value = value.encode() + b"\0"
            elif isinstance(value, list):
                value = b"".join(v.encode() + b"\0" for v in value)
            elif isinstance(value, int):
                value = struct.pack(">I", value)
            out += struct.pack(">III", 3, len(value), name_offset(key)) + pad(value)
        for key, value in body.items():
            if isinstance(value, dict):
                out += node(key, value)
        return out + struct.pack(">I", 2)

    structure = node("", tree) + struct.pack(">I", 9)
    reserve = b"\0" * 16
    off_reserve = 40
    off_struct = off_reserve + len(reserve)
    off_strings = off_struct + len(structure)
    total = off_strings + len(strings)
    header = struct.pack(">10I", 0xD00DFEED, total, off_struct, off_strings, off_reserve, 17, 16, 0, len(strings), len(structure))
    return header + reserve + structure + strings


def k114s(full):
    usb = "okay" if full else "disabled"
    soc = {
        "usb@382280000": {"compatible": ["apple,t6050-dwc3", "apple,t8103-dwc3"], "status": usb},
        "usb@2aa280000": {"compatible": ["apple,t6050-dwc3", "apple,t8103-dwc3"], "status": usb},
        "usb@38a280000": {"compatible": ["apple,t6050-dwc3", "apple,t8103-dwc3"], "status": "disabled"},
        "smc@28c600000": {"compatible": "apple,smc", "hwmon": {"compatible": "apple,smc-hwmon", "status": "okay" if full else "disabled"}},
        "fifo@294b14000": {"compatible": "apple,dockchannel", "input@8000": {"compatible": "apple,dockchannel-hid"}},
    }
    tree = {"compatible": ["apple,k114s", "apple,t6050", "apple,arm-platform"], "soc": soc}
    if full:
        soc["spmi@28a188000"] = {"status": "okay", "usb-pd@a": {"compatible": "apple,sn201202x"}}
        soc["spmi@28a1a8000"] = {"status": "okay", "usb-pd@c": {"compatible": "apple,sn201202x"}}
        tree["pcie@1cb0000000"] = {
            "compatible": "apple,t6050-pcie", "status": "okay",
            "pci@0,0": {"status": "disabled",
                        "control@0,0": {"compatible": "pci106b,1900", "firmware-name": "apple/centauri/k114s-ftab.bin",
                                        "apple,centauri-platform-id": 0x00146050},
                        "wifi@0,1": {"compatible": "pci106b,1902"},
                        "bluetooth@0,2": {"compatible": "pci106b,1903"}}}
    return tree


VARIANTS = {
    "k114s-full": lambda: k114s(True),
    "k114s-bare": lambda: k114s(False),
    "j714s": lambda: {"compatible": ["apple,j714s", "apple,t6050", "apple,arm-platform"], "soc": {}},
}

if __name__ == "__main__":
    with open(sys.argv[1], "wb") as handle:
        handle.write(fdt(VARIANTS[sys.argv[2]]()))
