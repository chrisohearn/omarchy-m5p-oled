#!/usr/bin/env python3
# K114s (omarchy-m5p-oled): list the property names of a DRM device's CRTCs, connectors and
# planes. Read-only: GETRESOURCES/GETPROPERTIES ioctls on a private file descriptor, no modeset,
# no DRM master. Use it to see whether a display driver offers any brightness or colour control
# (a "CTM", "GAMMA_LUT" or backlight-like property). The boot framebuffer (simpledrm) offers none.
#
#     python3 tools/brightness/drm-props.py [/dev/dri/card0]
import fcntl, os, struct, ctypes, sys
fd = os.open(sys.argv[1] if len(sys.argv) > 1 else "/dev/dri/card0", os.O_RDWR | os.O_CLOEXEC)
def IOWR(nr, size): return (3 << 30) | (size << 16) | (ord('d') << 8) | nr
def IOW(nr, size): return (1 << 30) | (size << 16) | (ord('d') << 8) | nr
# DRM_IOCTL_SET_CLIENT_CAP: atomic (3) and universal planes (2), on this fd only
for cap in (2, 3):
    try: fcntl.ioctl(fd, IOW(0x0d, 16), struct.pack("QQ", cap, 1))
    except OSError as e: print("cap", cap, e)
def getres():
    b = bytearray(struct.pack("QQQQIIIIIIII", 0,0,0,0, 0,0,0,0, 0,0,0,0))
    fcntl.ioctl(fd, IOWR(0xA0, len(b)), b)
    fbp, crp, cop, enp, nfb, ncr, nco, nen, *_ = struct.unpack("QQQQIIIIIIII", b)
    crs = (ctypes.c_uint32 * ncr)(); cos = (ctypes.c_uint32 * nco)(); ens = (ctypes.c_uint32 * nen)()
    b = bytearray(struct.pack("QQQQIIIIIIII", 0, ctypes.addressof(crs), ctypes.addressof(cos), ctypes.addressof(ens), 0, ncr, nco, nen, 0,0,0,0))
    fcntl.ioctl(fd, IOWR(0xA0, len(b)), b)
    return list(crs), list(cos)
def planes():
    b = bytearray(struct.pack("QI4x", 0, 0)); fcntl.ioctl(fd, IOWR(0xB5, len(b)), b)
    _, n = struct.unpack("QI4x", b); arr = (ctypes.c_uint32 * n)()
    b = bytearray(struct.pack("QI4x", ctypes.addressof(arr), n)); fcntl.ioctl(fd, IOWR(0xB5, len(b)), b)
    return list(arr)
def props(obj, typ):
    b = bytearray(struct.pack("QQIII", 0, 0, 0, obj, typ))
    fcntl.ioctl(fd, IOWR(0xB9, len(b)), b)
    _, _, n, _, _ = struct.unpack("QQIII", b)
    ids = (ctypes.c_uint32 * n)(); vals = (ctypes.c_uint64 * n)()
    b = bytearray(struct.pack("QQIII", ctypes.addressof(ids), ctypes.addressof(vals), n, obj, typ))
    fcntl.ioctl(fd, IOWR(0xB9, len(b)), b)
    out = []
    for i, v in zip(ids, vals):
        p = bytearray(struct.pack("QQII32sII", 0, 0, i, 0, b"", 0, 0))
        fcntl.ioctl(fd, IOWR(0xAA, len(p)), p)
        name = struct.unpack("QQII32sII", p)[4].split(b"\0")[0].decode()
        out.append(name)
    return out
crtcs, conns = getres()
for c in crtcs: print("CRTC", c, props(c, 0xcccccccc))
for c in conns: print("CONNECTOR", c, props(c, 0xc0c0c0c0))
for p in planes(): print("PLANE", p, props(p, 0xeeeeeeee))
