#!/usr/bin/python3
"""K114s repair, bundle r2c: apply to (or roll back from) the existing Omarchy ESP, from macOS.

Bundle r2c ("r2 compact") fits the ESP as installed (524 MB, about 139 MB free). It writes ONE
repair kernel image (r1 by default, or r1a), with the K114s Wi-Fi firmware inside that image's
own initramfs, instead of two images and a rewrite of both vendor firmware archives. The
image's vendor firmware, the installer's data and the original kernel image are not touched.
Linux-side files go to k114s-repair/r2c.

  status      read-only: which known state each boot file is in
  check       read-only: verify the live ESP, build every new file under work/, check the space
              step by step, write nothing
  apply       check, then back up and write (asks for one typed confirmation)
  kernel V    after apply: swap the repair kernel: r1 (trackpad fix B) | r1a (trackpad fix A)
  stage2 V    after apply: switch only the Stage 2 device tree: r1 | wifi | gp1c | trial1; or r3-gpu, the proven
              Stage 2 of the r3a promotion, from the bundle's promotion/ folder (docs/r3-display-d5-d9.md D9): the way
              back from the display Stage 2, whose loader differs (the whole file is written, loader bytes included)
  default V   after apply: which boot entry starts by default: repair | original, or after the r3a
              promotion (docs/r3a-promotion.md): k114s | aurora (written as an entry path)
  rollback    restore from the ESP backup:  rollback stage2  (device tree only)
              or  rollback all  (limine.conf and Stage 2; removes the repair kernel)
  restore-repair [--check] [IMAGE]
              after the r3a promotion (docs/r3a-promotion.md): put the static repair image back (IMAGE, default
              promotion/omarchy_linux-aurora-k114s.efi in this bundle, checked against the ESP's record) with the
              saved repair block as entry 1 and default_entry: 1; removes omarchy_linux-aurora.efi and its entry
              first when the space needs it. --check verifies everything and writes nothing.

If the original kernel image (EFI/Linux/omarchy_linux-aurora.efi) was removed from the ESP to make room
(the r3a kernel trial, docs/r3-integration.md), status, stage2, default repair and rollback stage2 keep
working; kernel, default original, rollback all and apply stop with a message and write nothing,
because each would need that image.
After the promotion (the repair image and its entry removed, default_entry the path Omarchy/linux-k114s) the ESP is
found by the r3a image (EFI/Linux/omarchy_linux-k114s.efi); status, stage2 r1, default k114s and default aurora work;
default repair, kernel, rollback all and apply stop with a message and write nothing; restore-repair puts the
repair image and entry back when both hook-built images fail.

Options: --kernel r1|r1a              which repair kernel apply installs (default r1)
         --stage2 r1|wifi|gp1c|keep   which device tree the Stage 2 gets at apply (default r1)
         --yes                   skip the typed confirmation
         --esp-dir DIR           test mode: treat DIR as the mounted ESP (no diskutil, no root)

A Stage 2 is recognised by its loader and U-Boot tail, both exact sha256 matches: the manifest's, KNOWN_LOADERS and KNOWN_TRAILERS
below, and k114s-repair/known-loaders.json on the ESP (docs/bundle-r2c.md, "Which Stage 2 the tool knows"). The copy of this
file on the ESP is put there by tools/k114s-repair-tool-install, run by root on Linux.

Nothing here repartitions, touches macOS volumes, the Linux root (LUKS), boot policy or NVRAM.
Python 3.9, standard library only.
"""
import hashlib
import io
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
BUNDLE = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import k114s_esp_tool as tool  # noqa: E402

UKI = "EFI/Linux/omarchy_linux-aurora.efi"
# The hook-built image of the linux-k114s package (r3a), the default after the promotion (docs/r3a-promotion.md).
K114S_UKI = "EFI/Linux/omarchy_linux-k114s.efi"
# default V for the promoted layout: the Limine entry path written as default_entry, and the image it must boot.
PATH_DEFAULTS = {"k114s": ("Omarchy/linux-k114s", K114S_UKI), "aurora": ("Omarchy/linux-aurora", UKI)}
# Stage 2 files built on this Mac outside the bundle (docs/r3-gpu-result.md, docs/r3-integration.md), named in status.
LOCAL_STAGE2 = {"9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc": "r3-gpu (GPU tree, not in this bundle)",
                "5164bb1e1be1fba39aee64229863b2f835828edd8b4f90e8cfa91e71a6fd8cd9": "r3a (r3a tree, not in this bundle)",
                "90b351377d6fcbad00ddc4c2fb74fce4313dd7fa5f4978ba895a7c41be523e30": "r3-display (pin loader + brightness tree, not in this bundle)"}
# A Stage 2 is  <loader> <device tree> <gzip U-Boot>  and the tree starts where the loader ends, so each loader has its
# own prefix length. A Stage 2 is known when its prefix is a loader below (or the manifest's, "installed") and its tail is a
# U-Boot below (or the manifest's): both are exact sha256 matches, so a loader or tail that is not listed is never guessed.
# (name, prefix bytes, sha256 of the prefix, which is the loader file itself)
KNOWN_LOADERS = (
    # the K114s-pin loader of the display Stage 2 (betizzel/omarchy-m5#18, docs/r3-display-d5-d9.md D9)
    ("pin", 4063232, "beceb683b63a6d421ce58061a55c14a6d09e0381a23c1a543df55f4cc8007392"),
    # Aura 1.0.0b13, the configured Stage 2 since 2026-11-23 (usr/lib/asahi-boot/m1n1.bin)
    ("aura-b13", 3932160, "4742dd6a11884e25c7817616a6a14ace98f82cf292904c58220545e77babe994"),
    # the self-built Aura b15 of docs/r3d-stage2.md, listed so a promoted b15 stays recognisable
    ("aura-b15", 3932160, "788277b6e5987034546e8eaeeefe29f5251379aaba4535f800270c9a1e710f94"),
)
# (name, sha256 of the gzip U-Boot tail after the device trees)
KNOWN_TRAILERS = (("aurora9", "6ee8bd9f81e5d409973b6f5cab69d67aa2ff292e0f570e3d97dd69e722b667af"),)
# More of both, from k114s-repair/known-loaders.json on the ESP: root writes it with tools/k114s-repair-tool-install, by hand, after a Stage 2 promotion:
# {"loaders": [{"name", "bytes", "sha256"}], "trailers": [{"name", "sha256"}]}. It only adds to the lists above.
KNOWN_JSON = "k114s-repair/known-loaders.json"
# Stage 2 files kept in the bundle's promotion/ folder (copied from the ESP's k114s-repair/promotion/ by the owner's macOS
# agent, D9): choice -> (file, tree file, sha256 of the file, sha256 of the tree, loader). Checked here, not in manifest.json,
# because the manifest belongs to the bundle and these files do not.
PROMOTED_STAGE2 = {"r3-gpu": ("boot-ctxr-gpu.bin", "k114s.dtb.gpu",
                              "9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc",
                              "2c870ba9f5963f5ae1ed18a7effa520daa234583997470d9552a795b4aafcda5", "installed")}
# The one repair kernel image. Whichever variant is installed lives at this path.
REPAIR_UKI = "EFI/Linux/omarchy_linux-aurora-k114s.efi"
# Paths bundles r1 and r2 would have used (never applied on this Mac); recognised and removed by rollback.
OLD_REPAIR_UKIS = ("EFI/Linux/omarchy_linux-aurora-k114s-r1.efi", "EFI/Linux/omarchy_linux-aurora-k114s-r1a.efi")
# The repair kernels: id -> (kernel image, trackpad module, menu title, comment)
VARIANTS = {
    "r1": ("Image-k114s-r1", "hid-magicmouse-r1.ko", "Omarchy K114s repair r1 (trackpad fix B)",
           "Repair kernel, trackpad series aurora-silicon/linux#1568 (tested on the 14-inch K114c)."),
    "r1a": ("Image-k114s-r1a", "hid-magicmouse-r1a.ko", "Omarchy K114s repair r1a (trackpad fix A)",
            "Repair kernel, upstream trackpad fix aurora-silicon/linux#1830 (K116s) plus product 0x0361."),
}
STAGE2_FILES = {"r1": ("boot-ctxr-k114s-r1.bin", "t6050-k114s-r1.dtb"),
                "wifi": ("boot-ctxr-k114s-r1-wifi.bin", "t6050-k114s-r1-wifi.dtb"),
                "gp1c": ("boot-ctxr-k114s-r1-gp1c.bin", "t6050-k114s-r1-gp1c.dtb"),
                "trial1": ("boot-ctxr-k114s-trial1.bin", "t6050-k114s-trial1.dtb")}
STAGE2 = "m1n1/boot-ctxr.bin"
LIMINE = "limine.conf"
VENDORFW = ("vendorfw/firmware.cpio", "vendorfw/firmware.tar", "vendorfw/manifest.txt")
REPAIR_DIR = "k114s-repair"
REV = "r2c"
# The backup of the boot files as they were before any repair (the name is r1's).
BACKUP_DIR = REPAIR_DIR + "/backup-before-r1"
LINUX_DIR = REPAIR_DIR + "/" + REV
APPLIED = REPAIR_DIR + "/applied-" + REV + ".json"
KVER = "7.3.0-17.v272-4-ARCH"
MODULE_ARC = "usr/lib/modules/" + KVER + "/kernel/drivers/hid/hid-magicmouse.ko"
FTAB = "apple/centauri/k114s-ftab.bin"
TPMTFW = "apple/tpmtfw-k114s.bin"
# The Wi-Fi firmware goes into the repair kernel's own initramfs, under /vendorfw: the image's
# initramfs unit omarchy-vendorfw.service copies /vendorfw to the installed system's
# /lib/firmware/vendor (a tmpfs) before switching root, the first place the kernel looks.
FTAB_ARC = "vendorfw/" + FTAB
FTAB_DIRS = ("vendorfw", "vendorfw/apple", "vendorfw/apple/centauri")
UKI_RECORD = "repair-uki.txt"
# Kept free on the ESP after every step: directory entries, FAT bookkeeping, a margin.
RESERVE = 8 << 20


class Stop(Exception):
    pass


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read(path):
    with open(path, "rb") as stream:
        return stream.read()


def say(text=""):
    print(text, flush=True)


def manifest():
    return json.load(open(os.path.join(BUNDLE, "manifest.json")))


def payload(name, m):
    data = read(os.path.join(BUNDLE, "payload", name))
    if sha(data) != m["payload"][name]:
        raise Stop("bundle file payload/%s does not match manifest.json" % name)
    return data


# --- finding and mounting the ESP -------------------------------------------

def run(*command):
    return subprocess.run(command, check=True, capture_output=True).stdout


def is_omarchy_esp(mount):
    have = lambda p: os.path.isfile(os.path.join(mount, p))
    # The original kernel image may be gone on purpose (the r3a slot swap, docs/r3-integration.md); the
    # repair image then stands in for it, and after the promotion (docs/r3a-promotion.md) the r3a image does.
    return (have(UKI) or have(REPAIR_UKI) or have(K114S_UKI)) and all(have(p) for p in (STAGE2, LIMINE, "m1n1/boot.bin")) \
        and os.path.isdir(os.path.join(mount, "vendorfw"))


class Esp:
    """The one EFI system partition that holds the Omarchy boot files, found by content."""

    def __init__(self, test_dir=None):
        self.test_dir = test_dir
        self.device = None
        self.mount = None
        self.writable = False
        self.appledouble_before = set()

    def _note_appledouble(self):
        """macOS keeps a file's extended attributes on FAT in a '._NAME' file beside it, and may
        tag files a process creates. Remember the ones already there; drop only our own."""
        self.appledouble_before = {os.path.join(d, f) for d, _, files in os.walk(self.mount)
                                   for f in files if f.startswith("._")}

    def drop_appledouble(self, path):
        companion = os.path.join(os.path.dirname(path), "._" + os.path.basename(path))
        if companion not in self.appledouble_before and os.path.isfile(companion) \
                and os.path.getsize(companion) <= (64 << 10):
            os.remove(companion)

    def makedirs(self, path):
        missing = []
        while not os.path.isdir(path):
            missing.append(path)
            path = os.path.dirname(path)
        for directory in reversed(missing):
            os.mkdir(directory)
            self.drop_appledouble(directory)

    def remove(self, rel):
        os.remove(self.path(rel))
        self.drop_appledouble(self.path(rel))

    def _efi_partitions(self):
        listing = plistlib.loads(run("/usr/sbin/diskutil", "list", "-plist"))
        found = []
        for disk in listing.get("AllDisksAndPartitions", []):
            for part in disk.get("Partitions", []):
                if part.get("Content") == "EFI":
                    found.append(part["DeviceIdentifier"])
        return found

    def _mount(self, device, writable):
        info = plistlib.loads(run("/usr/sbin/diskutil", "info", "-plist", device))
        if info.get("MountPoint"):
            run("/usr/sbin/diskutil", "unmount", device)
        point = tempfile.mkdtemp(prefix="k114s-esp-")
        command = ["/usr/sbin/diskutil", "mount"] + ([] if writable else ["readOnly"]) + ["-mountPoint", point, device]
        try:
            run(*command)
        except subprocess.CalledProcessError as error:
            os.rmdir(point)
            raise Stop("could not mount %s: %s" % (device, error.stderr.decode().strip()))
        return point

    def open(self, writable=False):
        if self.test_dir:
            self.mount, self.device, self.writable = self.test_dir, "test-dir", True
            if not is_omarchy_esp(self.mount):
                raise Stop("%s is not an Omarchy ESP" % self.mount)
            self._note_appledouble()
            return self
        if os.geteuid() != 0:
            raise Stop("run this with sudo (mounting the EFI system partition needs root)")
        target = run("/usr/sbin/sysctl", "-n", "hw.targettype").decode().strip()
        if target != "K114s":
            raise Stop("this Mac is %r, not a K114s: refusing" % target)
        if self.device is None:
            matches = []
            for device in self._efi_partitions():
                point = self._mount(device, False)
                try:
                    if is_omarchy_esp(point):
                        matches.append(device)
                finally:
                    self._unmount(device, point)
            if len(matches) != 1:
                raise Stop("expected exactly one Omarchy ESP, found %d (%s)" % (len(matches), ", ".join(matches)))
            self.device = matches[0]
        self.mount = self._mount(self.device, writable)
        self.writable = writable
        if writable:
            self._note_appledouble()
        return self

    def _unmount(self, device, point):
        subprocess.run(["/bin/sync"])
        subprocess.run(["/usr/sbin/diskutil", "unmount", device], capture_output=True)
        try:
            os.rmdir(point)
        except OSError:
            pass

    def close(self):
        if self.mount and not self.test_dir:
            self._unmount(self.device, self.mount)
        self.mount = None

    def path(self, rel):
        return os.path.join(self.mount, rel)

    def get(self, rel):
        return read(self.path(rel))

    def has(self, rel):
        return os.path.isfile(self.path(rel))

    def put(self, rel, data):
        """Write beside the target, read back, then rename over it."""
        if not self.writable:
            raise Stop("internal: ESP is not mounted writable")
        target = self.path(rel)
        temporary = target + ".k114s-new"
        try:
            self.makedirs(os.path.dirname(target))
            with open(temporary, "wb") as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
            if sha(read(temporary)) != sha(data):
                raise OSError("did not read back")
            os.replace(temporary, target)
        except OSError as error:
            if os.path.lexists(temporary):
                os.remove(temporary)
            self.drop_appledouble(temporary)
            raise Stop("writing %s failed (%s). The previous file is intact; run  status" % (rel, error))
        self.drop_appledouble(temporary)
        self.drop_appledouble(target)

    def free(self):
        stat = os.statvfs(self.mount)
        return stat.f_bavail * stat.f_frsize

    def cluster(self):
        return os.statvfs(self.mount).f_frsize or 4096


# --- reading the live state --------------------------------------------------

def known_entries(extra):
    """The valid loader and trailer entries from a decoded known-loaders.json."""
    raw_loaders, raw_trailers = extra.get("loaders", []), extra.get("trailers", [])
    if not isinstance(raw_loaders, list) or not isinstance(raw_trailers, list):
        raise TypeError("loaders and trailers must be lists")

    def valid(entry, reserved_name):
        if not isinstance(entry, dict):
            return False
        name, digest = entry.get("name"), entry.get("sha256")
        return (isinstance(name, str) and 0 < len(name) <= 32 and name != reserved_name
                and all(c.isalnum() or c in "._-" for c in name)
                and isinstance(digest, str) and len(digest) == 64
                and all(c in "0123456789abcdef" for c in digest))

    loaders = []
    for entry in raw_loaders:
        if valid(entry, "installed"):
            size = entry.get("bytes")
            if type(size) is int and 0 < size <= 16 << 20:
                loaders.append(entry)
    trailers = [entry for entry in raw_trailers if valid(entry, "bundle")]
    return loaders, trailers


def known_sets(m, esp=None):
    """(loaders, trailers, json note): the built-in lists, the manifest's loader and U-Boot, and the entries of the ESP's
    KNOWN_JSON. A missing file adds nothing; a damaged one or an entry that is not well formed is ignored, never fatal."""
    loaders = [("installed", m["aura_prefix_bytes"], m["aura_prefix_sha256"])] + list(KNOWN_LOADERS)
    trailers = [("bundle", m["uboot_trailer_sha256"])] + list(KNOWN_TRAILERS)
    if esp is None or not esp.has(KNOWN_JSON):
        return loaders, trailers, "absent"
    try:
        extra = json.loads(esp.get(KNOWN_JSON).decode("utf-8"))
        add_loaders, add_trailers = known_entries(extra)
    except (ValueError, TypeError, AttributeError):
        return loaders, trailers, "damaged, ignored"
    loaders.extend((e["name"], e["bytes"], e["sha256"]) for e in add_loaders)
    trailers.extend((e["name"], e["sha256"]) for e in add_trailers)
    return loaders, trailers, "%d loaders, %d U-Boot tails" % (len(add_loaders), len(add_trailers))


def split_known(data, m, esp=None):
    """(loader name, prefix, trees, trailer) of a Stage 2 whose loader and U-Boot tail are both known (known_sets), else
    None. The loader is named "installed" (the manifest's) or by its entry ("pin", "aura-b13", ...)."""
    loaders, trailers, _ = known_sets(m, esp)
    tails = {digest for _, digest in trailers}
    for name, size, digest in loaders:
        try:
            prefix, trees, trailer = tool.stage2_split(data, size)
        except (SystemExit, Exception):   # a damaged file (a short tree, a bad gzip tail) is not a known Stage 2
            continue
        if sha(prefix) == digest and sha(trailer) in tails:
            return name, prefix, trees, trailer
    return None


def stage2_state(data, m, esp=None):
    known = {v: k for k, v in m["stage2_sha256"].items()}
    digest = sha(data)
    if digest in known:
        return known[digest]
    if digest in LOCAL_STAGE2:
        return LOCAL_STAGE2[digest]
    hit = split_known(data, m, esp)
    if hit is None:
        return "unknown"
    return ("same-loader-other-trees(%d)" if hit[0] == "installed" else hit[0] + "-loader-other-trees(%d)") % len(hit[2])


def tar_files(data):
    """[(name, bytes)] of a vendor firmware tar, links resolved to their data, in order."""
    out = []
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        for member in archive.getmembers():
            if member.isdir():
                continue
            handle = archive.extractfile(member)
            if handle is None:
                raise Stop("vendor firmware tar has an unreadable member " + member.name)
            out.append((member.name, handle.read()))
    return out


def live_state(esp, m):
    state = {"device": esp.device, "files": {}}
    for rel in (UKI, STAGE2, LIMINE, "m1n1/boot.bin") + VENDORFW:
        if not esp.has(rel):
            if rel == UKI and (esp.has(REPAIR_UKI) or esp.has(K114S_UKI)):
                continue   # removed on purpose to make room (docs/r3-integration.md); not an error
            raise Stop("the ESP has no " + rel)
        state["files"][rel] = sha(esp.get(rel))
    if UKI in state["files"]:
        try:
            uki = tool.Uki(esp.get(UKI))
            state["uki_uname"] = uki.content(".uname").rstrip(b"\0").decode()
            state["uki_linux_sha256"] = sha(uki.content(".linux"))
        except SystemExit:   # status must not die on the way back: report it, the commands that need it check "kernel"
            state["uki_uname"], state["uki_linux_sha256"] = None, None
        state["kernel"] = {m["original_kernel_sha256"]: "original v272-4"}.get(state["uki_linux_sha256"], "unknown")
    else:
        state["uki_uname"], state["uki_linux_sha256"], state["kernel"] = None, None, "removed"
    state["stage2"] = stage2_state(esp.get(STAGE2), m, esp)
    state["known_loaders_json"] = known_sets(m, esp)[2]
    state["boot_bin"] = "image combined" if state["files"]["m1n1/boot.bin"] == m["stage2_sha256"]["image-combined"] else "other"
    names = [n for n, _ in tar_files(esp.get(VENDORFW[1]))]
    state["vendorfw_files"] = len(names)
    state["vendorfw_has_tpmtfw"] = TPMTFW in names
    state["vendorfw_has_ftab"] = FTAB in names
    state["new_uki_present"] = any(esp.has(p) for p in (REPAIR_UKI,) + OLD_REPAIR_UKIS)
    state["repair_variant"] = repair_variant(esp, m)
    limine = esp.get(LIMINE).decode("utf-8")
    state["limine_has_repair_entry"] = tool.LIMINE_MARKER in limine or any(
        p in limine for p in (REPAIR_UKI,) + OLD_REPAIR_UKIS)
    state["limine_default"] = default_text(limine)
    state["k114s_uki_present"] = esp.has(K114S_UKI)
    state["backup_present"] = esp.has(BACKUP_DIR + "/backup.json")
    state["linux_revisions"] = [r for r in ("r1", "r2", "r2c") if esp.has(REPAIR_DIR + "/" + r + "/SHA256SUMS")]
    state["free_bytes"] = esp.free()
    state["cluster_bytes"] = esp.cluster()
    return state


def limine_entries(text):
    """[(index, path, efi)] in Limine's numbering (every entry line counts, folders too). The path joins the names
    with '/'; the '+' of an expanded folder is not part of a name, the name is the rest of the line after blanks, as
    Limine 12.9.6 reads it (common/lib/config.c). efi is the file of its path: line ('' for a folder)."""
    out, names = [], {}
    for raw in text.split("\n"):
        line = raw.lstrip(" \t")
        if line.startswith("/"):
            depth = len(line) - len(line.lstrip("/"))
            name = line[depth:]
            name = (name[1:] if name.startswith("+") else name).lstrip(" \t")
            names[depth] = name
            out.append([len(out) + 1, "/".join(names[d] for d in range(1, depth + 1)), ""])
        elif out and line.startswith("path:"):
            out[-1][2] = line[5:].strip().split("boot():/", 1)[-1]
    return out


def default_value(text):
    for line in text.split("\n"):
        if line[:14].lower() == "default_entry:":
            return line[14:].lstrip(" \t")
    return None


def default_entry(text):
    """The entry default_entry names, as Limine resolves it, or None."""
    value, entries = default_value(text), limine_entries(text)
    if value is None:
        return None
    if value.isdigit():
        return entries[int(value) - 1] if 0 < int(value) <= len(entries) else None
    return next((e for e in entries if e[1] == value), None)


def default_text(text):
    value, hit = default_value(text), default_entry(text)
    if value is None:
        return "unset"
    if hit is None:
        return "%s -> NAMES NO ENTRY (Limine would stop at the menu)" % value
    if not hit[2]:
        return "%s -> a folder (Limine would stop at the menu)" % value
    return "%s -> %s (entry %d)" % (value, hit[1].split("/")[-1], hit[0])


def show(state):
    say("  ESP device:            %s" % state["device"])
    if state["kernel"] == "removed":
        say("  installed kernel UKI:  REMOVED (the original image is not on the ESP; %s)"
            % ("the r3a image omarchy_linux-k114s.efi is" if state.get("k114s_uki_present") else "the repair image is the only Linux image"))
    else:
        say("  installed kernel UKI:  %s (%s)" % (state["kernel"], state["uki_uname"]))
    say("  Stage 2 (boot-ctxr):   %s" % state["stage2"])
    say("  known-loaders.json:    %s" % state["known_loaders_json"])
    say("  vendor firmware:       %d files; trackpad firmware %s; N1 firmware %s" % (
        state["vendorfw_files"], "present" if state["vendorfw_has_tpmtfw"] else "MISSING",
        "present" if state["vendorfw_has_ftab"] else "absent"))
    say("  repair UKI on ESP:     %s; Limine repair entry: %s" % (
        state["repair_variant"] or ("other" if state["new_uki_present"] else "no"),
        "yes" if state["limine_has_repair_entry"] else "no"))
    say("  Limine default entry:  %s" % state["limine_default"])
    say("  Linux-side files:      %s" % (", ".join(state["linux_revisions"]) or "none"))
    say("  backup on ESP:         %s; free space %.0f MB" % (
        "yes" if state["backup_present"] else "no", state["free_bytes"] / 1e6))


# --- building the new files --------------------------------------------------

def repair_variant(esp, m):
    """Which repair kernel REPAIR_UKI carries: r1, r1a, or None (absent or not this bundle's)."""
    if not esp.has(REPAIR_UKI):
        return None
    try:
        digest = sha(tool.Uki(esp.get(REPAIR_UKI)).content(".linux"))
    except SystemExit:
        return None
    for ident, item in VARIANTS.items():
        if m["payload"][item[0]] == digest:
            return ident
    return None


def build_repair_uki(original, variant, m):
    """-> (UKI bytes, record text): the original UKI with the variant's kernel, and the trackpad
    module and the Wi-Fi firmware appended to its initramfs. The record gives the byte range and
    hash of each payload inside the file, so Linux can take them out without parsing it."""
    image_name, module_name = VARIANTS[variant][0], VARIANTS[variant][1]
    image, module, ftab = payload(image_name, m), payload(module_name, m), payload("k114s-ftab.bin", m)
    extra = tool.cpio_make([(d, None) for d in FTAB_DIRS] + [(FTAB_ARC, ftab), (MODULE_ARC, module)])
    data = tool.uki_build(original, image, extra)
    uki = tool.Uki(data)
    old_initrd = len(tool.Uki(original).content(".initrd"))
    start = uki.section(".initrd")["raw"] + old_initrd + (-old_initrd % 4)
    if data[start:start + len(extra)] != extra:
        raise Stop("internal: the appended archive is not where it was placed")
    where = {"kernel": (uki.section(".linux")["raw"], len(image), m["payload"][image_name])}
    for name, _, size, _, offset, _ in tool.newc_parse(extra)[0]:
        if name == FTAB_ARC:
            where["ftab"] = (start + offset, size, m["payload"]["k114s-ftab.bin"])
        elif name == MODULE_ARC:
            where["module"] = (start + offset, size, m["payload"][module_name])
    for key, (offset, size, digest) in where.items():
        if sha(data[offset:offset + size]) != digest:
            raise Stop("internal: the %s range in the repair kernel image does not verify" % key)
    lines = ["# K114s bundle %s: the repair kernel image on the ESP and the byte ranges of its payloads" % REV,
             "variant %s" % variant, "uki %s %d %s" % (REPAIR_UKI, len(data), sha(data))]
    lines += ["%s %d %d %s" % (key, *where[key]) for key in ("kernel", "ftab", "module")]
    return data, ("\n".join(lines) + "\n").encode()


def stage2_payload(choice, m):
    data = payload(STAGE2_FILES[choice][0], m)
    prefix, trees, trailer = tool.stage2_split(data, m["aura_prefix_bytes"])
    if sha(prefix) != m["aura_prefix_sha256"] or sha(trailer) != m["uboot_trailer_sha256"] or len(trees) != 1 \
            or tool.fdt_root_compatible(trees[0])[0] != "apple,k114s" \
            or sha(trees[0]) != m["payload"][STAGE2_FILES[choice][1]]:
        raise Stop("the bundle's Stage 2 is not a K114s-only image of the installed loader")
    return data


def promoted_payload(choice, m):
    """(Stage 2 bytes, tree bytes) of a choice kept in the bundle's promotion/ folder, checked against this tool's hashes."""
    name, tree, want, want_tree, loader = PROMOTED_STAGE2[choice]
    try:
        data = read(os.path.join(BUNDLE, BUNDLE_PROMOTION, name))
        dtb = read(os.path.join(BUNDLE, BUNDLE_PROMOTION, tree))
    except OSError as error:
        raise Stop("the bundle's %s/ has no %s (%s): copy it from the ESP's %s/ first (docs/r3-display-d5-d9.md M9)"
                   % (BUNDLE_PROMOTION, os.path.basename(error.filename or name), error.strerror, PROMOTION_DIR))
    hit = split_known(data, m)
    if sha(data) != want or sha(dtb) != want_tree or hit is None or hit[0] != loader or len(hit[2]) != 1 or sha(hit[2][0]) != want_tree:
        raise Stop("%s/%s and %s are not the %s Stage 2 and tree this tool knows (sha256 %s...)"
                   % (BUNDLE_PROMOTION, name, tree, choice, want[:8]))
    return data, dtb


def linux_files(m, variant, record):
    """The Linux-side files this bundle puts on the ESP, each checked against manifest.json."""
    out = {}
    for name, digest in sorted(m["linux"].items()):
        data = read(os.path.join(BUNDLE, "linux", name))
        if sha(data) != digest:
            raise Stop("bundle file linux/%s does not match manifest.json" % name)
        out[name] = data
    out["hid-magicmouse-%s.ko" % variant] = payload(VARIANTS[variant][1], m)
    out[UKI_RECORD] = record
    out["SHA256SUMS"] = "".join("%s  %s\n" % (sha(v), k) for k, v in sorted(out.items())).encode()
    return out


def clusters(size, cluster):
    return -(-size // cluster) * cluster


def space_plan(esp, steps, free, cluster, new_dirs):
    """Walk the writes in order. A new file adds its clusters; a replacement first needs room
    for the new copy beside the old one, then gives back the old one's clusters. Returns the
    peak extra space, the final extra space and a per-step table."""
    used = new_dirs * cluster
    peak, table = used, []
    for rel, size in steps:
        if esp.has(rel):
            old = clusters(len(esp.get(rel)), cluster)
            peak = max(peak, used + clusters(size, cluster))
            used += clusters(size, cluster) - old
        else:
            used += clusters(size, cluster)
            peak = max(peak, used)
        table.append((rel, size, used, peak))
    return peak, used, table


def plan(esp, m, stage2_choice, variant, work):
    state = live_state(esp, m)
    if state["kernel"] == "removed":
        raise Stop("the original kernel image is not on the ESP; apply needs it. Nothing written")
    if state["uki_uname"] != KVER:
        raise Stop("the installed kernel is %s, not %s: this repair is built for that exact kernel"
                   % (state["uki_uname"], KVER))
    if state["kernel"] != "original v272-4":
        raise Stop("the installed UKI does not carry the original v272-4 kernel image; not touching it")
    if state["limine_has_repair_entry"] or state["new_uki_present"] or esp.has(APPLIED):
        raise Stop("a K114s repair is already applied; use status, kernel or rollback")
    if not state["vendorfw_has_tpmtfw"]:
        raise Stop("the ESP's vendor firmware has no %s (the trackpad firmware); not continuing" % TPMTFW)
    if state["stage2"] == "unknown" and stage2_choice != "keep":
        raise Stop("the live Stage 2 is not one this bundle knows; use --stage2 keep or investigate")
    uki, record = build_repair_uki(esp.get(UKI), variant, m)
    text, cmdline = tool.limine_add(esp.get(LIMINE).decode("utf-8"),
                                    [("/" + REPAIR_UKI, VARIANTS[variant][2],
                                      VARIANTS[variant][3] + " The original entry is below, unchanged.")],
                                    "/" + UKI, 5)
    new = {}
    for name, data in linux_files(m, variant, record).items():
        new[LINUX_DIR + "/" + name] = data
    # The pinned device tree the Linux-side hook rebuilds the Stage 2 from follows the Stage 2.
    new[REPAIR_DIR + "/k114s.dtb"] = payload(STAGE2_FILES["trial1" if stage2_choice == "keep" else stage2_choice][1], m)
    new[REPAIR_UKI] = uki
    if stage2_choice != "keep":
        new[STAGE2] = stage2_payload(stage2_choice, m)
    new[LIMINE] = text.encode("utf-8")
    backups = [LIMINE, STAGE2]
    # The exact order apply writes in: backups, small files, the repair kernel, Stage 2, the menu.
    steps = [(BACKUP_DIR + "/" + b, len(esp.get(b))) for b in backups] + [(BACKUP_DIR + "/backup.json", 512)]
    steps += [(rel, len(data)) for rel, data in new.items()] + [(APPLIED, 64 << 10)]
    new_dirs = sum(1 for d in (REPAIR_DIR, BACKUP_DIR, BACKUP_DIR + "/m1n1", LINUX_DIR) if not os.path.isdir(esp.path(d)))
    cluster = state["cluster_bytes"]
    peak, final, table = space_plan(esp, steps, state["free_bytes"], cluster, new_dirs)
    # After apply, every later command must still fit: rollback rewrites Stage 2 and limine.conf
    # (after deleting the repair kernel), and  kernel  deletes the repair kernel before writing
    # the other one, which is at most a few clusters larger.
    after = state["free_bytes"] - final
    later = max(clusters(len(esp.get(STAGE2)), cluster) + clusters(len(esp.get(LIMINE)), cluster), 64 * cluster)
    budget = {"free_bytes": state["free_bytes"], "cluster_bytes": cluster, "peak_bytes": peak,
              "final_bytes": final, "reserve_bytes": RESERVE, "free_after_bytes": after,
              "later_commands_need_bytes": later, "steps": table}
    if peak + RESERVE > state["free_bytes"] or after < later + RESERVE:
        raise Stop("not enough free space on the ESP: the writes need %.1f MB at their peak plus a %.1f MB margin, "
                   "and %.1f MB must stay free afterwards; the ESP has %.1f MB free. Nothing was written."
                   % (peak / 1e6, RESERVE / 1e6, (later + RESERVE) / 1e6, state["free_bytes"] / 1e6))
    for rel, data in new.items():
        target = os.path.join(work, "new", rel)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "wb") as stream:
            stream.write(data)
    summary = {"revision": REV, "mode": "full", "variant": variant,
               "state_before": state, "stage2": stage2_choice, "cmdline": cmdline, "space": budget,
               "writes": {rel: {"bytes": len(data), "sha256": sha(data)} for rel, data in new.items()},
               "order": list(new), "backups": backups}
    with open(os.path.join(work, "plan.json"), "w") as stream:
        json.dump(summary, stream, indent=1)
    return state, new, summary


def show_space(summary):
    b = summary["space"]
    say("  space on the ESP:      %.1f MB free; the writes need %.1f MB at their peak + %.1f MB margin;"
        % (b["free_bytes"] / 1e6, b["peak_bytes"] / 1e6, b["reserve_bytes"] / 1e6))
    say("                         %.1f MB stays free afterwards (later rollback or kernel swap needs %.1f MB)"
        % (b["free_after_bytes"] / 1e6, (b["later_commands_need_bytes"] + b["reserve_bytes"]) / 1e6))


# --- apply / rollback --------------------------------------------------------

def save_live_copy(esp, work, state):
    """Keep the boot files as they are now on this Mac, off the ESP, and check each copy."""
    for rel in (UKI, STAGE2, LIMINE, "m1n1/boot.bin") + VENDORFW:
        target = os.path.join(work, "live", rel)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copyfile(esp.path(rel), target)
        if sha(read(target)) != state["files"][rel]:
            raise Stop("the copy of %s kept on this Mac did not verify; nothing written" % rel)


def apply(esp, m, stage2_choice, variant, work, assume_yes):
    esp.open(False)
    try:
        state, new, summary = plan(esp, m, stage2_choice, variant, work)
        save_live_copy(esp, work, state)
    finally:
        esp.close()
    say("Verified the live ESP and built every new file under:\n  %s" % work)
    show(state)
    show_space(summary)
    say("\nWill write to the ESP (%s):" % state["device"])
    for rel, item in summary["writes"].items():
        say("  %-58s %10d  %s" % (rel, item["bytes"], item["sha256"][:16]))
    say("Backups kept on the ESP in %s/ and on this Mac in work/.../live/ (verified)." % BACKUP_DIR)
    say("The original kernel entry stays in the Limine menu; the repair entry becomes the default.")
    say("Nothing else on the ESP is changed: the vendor firmware, the installer's data and the original")
    say("kernel image stay as they are.")
    if not assume_yes:
        if input("\nType  apply  to write these files: ").strip() != "apply":
            raise Stop("nothing written")
    esp.open(True)
    try:
        after_check = live_state(esp, m)
        if after_check["files"] != state["files"]:
            raise Stop("the ESP changed between check and apply; nothing written")
        if esp.free() != state["free_bytes"]:
            raise Stop("the ESP's free space changed between check and apply; nothing written")
        if not esp.has(BACKUP_DIR + "/backup.json"):
            # No complete backup yet (none, or an earlier run stopped while making it; nothing
            # has been changed in that case, because the backup comes before every other write).
            for rel in summary["backups"]:
                esp.put(BACKUP_DIR + "/" + rel, esp.get(rel))
                if sha(esp.get(BACKUP_DIR + "/" + rel)) != state["files"][rel]:
                    raise Stop("backup of %s did not verify; nothing else written" % rel)
            record = {"created": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "files": {r: state["files"][r] for r in summary["backups"]},
                      "stage2_state": state["stage2"]}
            esp.put(BACKUP_DIR + "/backup.json", json.dumps(record, indent=1).encode())
        order = summary["order"]
        if sorted(order) != sorted(new) or order[-1] != LIMINE:
            raise Stop("internal: the write order does not cover the plan; nothing written")
        for rel in order:
            esp.put(rel, new[rel])
            if esp.free() < RESERVE:
                raise Stop("the ESP ran low on space after writing %s; stopping. Run  rollback all" % rel)
        for rel in order:
            if sha(esp.get(rel)) != summary["writes"][rel]["sha256"]:
                raise Stop("%s does not verify after writing: run  rollback  now" % rel)
        esp.put(APPLIED, json.dumps(summary, indent=1).encode())
        final = live_state(esp, m)
    finally:
        esp.close()
    say("\nApplied and verified.")
    show(final)
    return summary


def rollback(esp, m, what):
    esp.open(True)
    try:
        if not esp.has(BACKUP_DIR + "/backup.json"):
            raise Stop("the ESP has no %s: nothing to roll back to" % BACKUP_DIR)
        record = json.loads(esp.get(BACKUP_DIR + "/backup.json").decode())
        if what not in ("stage2", "all"):
            raise Stop("rollback takes  stage2  or  all")
        if what == "all" and REPAIR_UKI not in esp.get(LIMINE).decode("utf-8"):
            raise Stop("limine.conf has no repair entry (the r3a promotion removed it on purpose). rollback all would put back "
                       "the menu from before the repair, whose entry names an image that is no longer the one on the ESP. "
                       "Nothing written. Use  stage2 r1  or  default k114s / default aurora  instead")
        if what == "all" and not esp.has(UKI):
            raise Stop("the original kernel image (%s) is not on the ESP. rollback all would restore a menu that points "
                       "at it and delete the repair image, leaving no Linux entry that starts. Nothing written. "
                       "Use  rollback stage2  and  default repair  instead" % UKI)
        wanted = [STAGE2] if what == "stage2" else [r for r in [LIMINE, STAGE2] + list(VENDORFW) if r in record["files"]]
        for rel in wanted:
            data = esp.get(BACKUP_DIR + "/" + rel)
            if sha(data) != record["files"][rel]:
                raise Stop("backup of %s is damaged; not restoring it" % rel)

        def restore(rel):
            esp.put(rel, esp.get(BACKUP_DIR + "/" + rel))
            if sha(esp.get(rel)) != record["files"][rel]:
                raise Stop("restore of %s did not verify" % rel)
        if what == "all":
            # The menu first, so no entry points at a file that is about to go; then the repair
            # kernel, which frees the space the rest of the restore needs.
            restore(LIMINE)
            for path in (REPAIR_UKI,) + OLD_REPAIR_UKIS:
                if esp.has(path):
                    esp.remove(path)
            if esp.has(APPLIED):
                os.replace(esp.path(APPLIED), esp.path(APPLIED + ".rolled-back"))
        for rel in wanted:
            if rel != LIMINE or what != "all":
                restore(rel)
        # The pinned tree the Linux-side hook rebuilds the Stage 2 from goes back as well.
        esp.put(REPAIR_DIR + "/k114s.dtb", payload(STAGE2_FILES["trial1"][1], m))
        state = live_state(esp, m)
    finally:
        esp.close()
    say("Rolled back: %s" % ", ".join(wanted))
    show(state)


def switch_stage2(esp, m, choice):
    if choice in PROMOTED_STAGE2:
        data, dtb = promoted_payload(choice, m)
    elif choice in STAGE2_FILES:
        data, dtb = stage2_payload(choice, m), payload(STAGE2_FILES[choice][1], m)
    else:
        raise Stop("stage2 must be one of: " + ", ".join(list(STAGE2_FILES) + list(PROMOTED_STAGE2)))
    esp.open(True)
    try:
        if not esp.has(BACKUP_DIR + "/backup.json"):
            raise Stop("apply the repair first (no backup on the ESP yet)")
        if stage2_state(esp.get(STAGE2), m, esp) == "unknown":
            raise Stop("the live Stage 2 is not one this bundle knows (its loader or U-Boot tail is not listed, KNOWN_LOADERS in this tool and %s on the ESP); not replacing it" % KNOWN_JSON)
        esp.put(STAGE2, data)
        esp.put(REPAIR_DIR + "/k114s.dtb", dtb)
        if sha(esp.get(STAGE2)) != sha(data):
            raise Stop("Stage 2 did not verify after writing: run  rollback stage2")
        state = live_state(esp, m)
    finally:
        esp.close()
    say("Stage 2 is now: %s" % choice)
    show(state)


def switch_kernel(esp, m, variant):
    if variant not in VARIANTS:
        raise Stop("kernel must be one of: " + ", ".join(VARIANTS))
    esp.open(True)
    try:
        current = repair_variant(esp, m)
        text = esp.get(LIMINE).decode("utf-8")
        if current is None or REPAIR_UKI not in text or not esp.has(APPLIED):
            raise Stop("apply the repair first (no repair kernel of this bundle on the ESP)")
        if not esp.has(UKI):
            raise Stop("the repair kernel is built from the original kernel image, which is not on the ESP. Nothing written")
        if current == variant:
            raise Stop("the repair kernel is already %s" % variant)
        uki, record = build_repair_uki(esp.get(UKI), variant, m)
        cluster = esp.cluster()
        if esp.free() + clusters(len(esp.get(REPAIR_UKI)), cluster) < clusters(len(uki), cluster) + RESERVE:
            raise Stop("not enough free space on the ESP to swap the repair kernel; nothing written")
        title_old, title_new = "/" + VARIANTS[current][2], "/" + VARIANTS[variant][2]
        lines = text.split("\n")
        at = lines.index(title_old) if title_old in lines else -1
        if at < 0 or not lines[at + 1].startswith("  comment: "):
            raise Stop("limine.conf's repair entry is not as this tool wrote it; not changing it")
        lines[at], lines[at + 1] = title_new, "  comment: " + VARIANTS[variant][3] + " The original entry is below, unchanged."
        linux = linux_files(m, variant, record)
        # The old image goes first: there is no room for both. Until the new one is written the
        # repair entry has no file to start; the original entry is not affected.
        esp.remove(REPAIR_UKI)
        esp.put(REPAIR_UKI, uki)
        if sha(esp.get(REPAIR_UKI)) != sha(uki):
            raise Stop("the new repair kernel did not verify after writing: run  rollback all")
        esp.put(LIMINE, "\n".join(lines).encode("utf-8"))
        old_module = LINUX_DIR + "/hid-magicmouse-%s.ko" % current
        for name, data in linux.items():
            esp.put(LINUX_DIR + "/" + name, data)
        if esp.has(old_module):
            esp.remove(old_module)
        applied = json.loads(esp.get(APPLIED).decode())
        applied["variant"] = variant
        applied.setdefault("history", []).append({"kernel": variant, "at": time.strftime("%Y-%m-%dT%H:%M:%S%z")})
        esp.put(APPLIED, json.dumps(applied, indent=1).encode())
        state = live_state(esp, m)
    finally:
        esp.close()
    say("Repair kernel is now: %s" % variant)
    show(state)


def switch_default(esp, m, choice):
    esp.open(True)
    try:
        text = esp.get(LIMINE).decode("utf-8")
        if choice in PATH_DEFAULTS:
            # The promoted layout (docs/r3a-promotion.md): written as an entry path, which keeps naming the same
            # entry when the Linux hook adds or removes entries in front of it.
            value, efi = PATH_DEFAULTS[choice]
            hit = next((e for e in limine_entries(text) if e[1] == value), None)
            if hit is None or hit[2].split("#", 1)[0] != efi:
                raise Stop("limine.conf has no entry %s that boots %s; nothing written" % (value, efi))
            if not esp.has(efi):
                raise Stop("%s is not on the ESP, so that entry cannot start; nothing written" % efi)
            if "#" in hit[2] and hashlib.blake2b(esp.get(efi)).hexdigest() != hit[2].split("#", 1)[1]:
                raise Stop("%s does not match its hash in limine.conf (Limine would wait for a key the keyboard cannot "
                           "give); nothing written" % efi)
            lines = text.split("\n")
            at = [i for i, l in enumerate(lines) if l[:14].lower() == "default_entry:"]
            if len(at) != 1:
                raise Stop("limine.conf has %d default_entry lines, not one; nothing written" % len(at))
            lines[at[0]] = "default_entry: " + value
            new = "\n".join(lines)
            if default_entry(new) is None or default_entry(new)[2] != hit[2]:
                raise Stop("internal: the new default does not resolve; nothing written")
            esp.put(LIMINE, new.encode("utf-8"))
        else:
            if REPAIR_UKI not in text:
                raise Stop("limine.conf has no repair entry (after the r3a promotion it is gone on purpose); nothing written. "
                           "Use  default k114s  or  default aurora")
            titles = [l for l in text.split("\n") if l.lstrip().startswith("/")]
            if not titles or titles[0] not in ["/" + v[2] for v in VARIANTS.values()]:
                raise Stop("the repair entry is not the first menu entry; not changing the default")
            if choice in ("repair", "r1", "r1a"):
                index = 1
            elif choice == "original":
                if not esp.has(UKI):
                    raise Stop("the original kernel image is not on the ESP, so that entry cannot start. Nothing written. "
                               "Use  default repair")
                old = esp.get(BACKUP_DIR + "/" + LIMINE).decode("utf-8")
                value = [l.split(":", 1)[1].strip() for l in old.split("\n") if l.startswith("default_entry")]
                index = (int(value[0]) if value and value[0].isdigit() else 1) + 1
            else:
                raise Stop("default must be repair, original, k114s or aurora")
            esp.put(LIMINE, tool.limine_default(text, index).encode("utf-8"))
        state = live_state(esp, m)
    finally:
        esp.close()
    say("Default boot entry changed.")
    show(state)


# --- restore-repair: the static repair image back from macOS after the promotion -------------------------------------
# docs/r3a-promotion.md: the promotion removes the repair image and its entry from the ESP. Both images left there are
# built by the Linux hook from the same initramfs state, so one bad update can break both. The owner keeps the repair
# image in the bundle folder (promotion/, step P4b), and the runbook keeps the exact repair block, command line
# included, in a root-only file on the ESP (step P0e) and the owner a copy beside the image. This puts them back.
PROMOTION_DIR = REPAIR_DIR + "/promotion"
SAVED_BLOCK = PROMOTION_DIR + "/repair-block.conf"
BUNDLE_PROMOTION = "promotion"
REPAIR_TITLES = ["/" + v[2] for v in VARIANTS.values()]


def repair_record(esp):
    """(size, sha256) of the repair image as apply wrote it, from the record on the ESP."""
    rel = LINUX_DIR + "/" + UKI_RECORD
    if not esp.has(rel):
        raise Stop("the ESP has no %s, so the repair image cannot be checked; nothing written" % rel)
    for line in esp.get(rel).decode("utf-8", "replace").split("\n"):
        words = line.split()
        if len(words) == 4 and words[0] == "uki" and words[1] == REPAIR_UKI and words[2].isdigit():
            return int(words[2]), words[3]
    raise Stop("%s does not name %s; nothing written" % (rel, REPAIR_UKI))


def check_repair_block(text):
    """The saved block must be one flat repair entry, exactly as apply wrote it: the marker, a repair title, one path
    line naming the repair image, one command line. It is never printed (its command line is this Mac's)."""
    lines = text.split("\n")
    if not text.endswith("\n") or lines[0] != tool.LIMINE_MARKER + " (added from macOS; remove this block to undo)":
        raise Stop("the saved repair block does not start with the repair marker; nothing written")
    if len(lines) < 2 or lines[1] not in REPAIR_TITLES:
        raise Stop("the saved repair block's second line is not a repair entry title; nothing written")
    if [l for l in lines[1:] if l.lstrip().startswith("/")] != [lines[1]] or any(l.startswith("###") for l in lines[1:]):
        raise Stop("the saved repair block holds more than one entry; nothing written")
    if [l.strip() for l in lines if l.strip().startswith("path:")] != ["path: boot():/" + REPAIR_UKI]:
        raise Stop("the saved repair block does not boot exactly %s; nothing written" % REPAIR_UKI)
    cmd = [l.strip() for l in lines if l.strip().startswith("cmdline:")]
    if len(cmd) != 1 or not cmd[0][8:].strip():
        raise Stop("the saved repair block has no command line; nothing written")


def saved_repair_block(esp):
    """The saved block from the ESP and/or the bundle folder; when both exist they must be the same bytes."""
    found = {}
    if esp.has(SAVED_BLOCK):
        found["the ESP's " + SAVED_BLOCK] = esp.get(SAVED_BLOCK)
    local = os.path.join(BUNDLE, BUNDLE_PROMOTION, "repair-block.conf")
    if os.path.isfile(local):
        found["the bundle's " + BUNDLE_PROMOTION + "/repair-block.conf"] = read(local)
    if not found:
        raise Stop("no saved repair block (%s on the ESP, or %s/repair-block.conf in the bundle); nothing written"
                   % (SAVED_BLOCK, BUNDLE_PROMOTION))
    if len(set(found.values())) != 1:
        raise Stop("the saved repair blocks differ (%s); nothing written" % ", ".join(sorted(found)))
    text = next(iter(found.values())).decode("utf-8")
    check_repair_block(text)
    return text, sorted(found)


def drop_sub_entry(text, name):
    """TEXT without the sub-entry '//NAME' (its line up to the next entry line)."""
    out, skip = [], False
    for line in text.split("\n"):
        stripped = line.strip(" \t")
        if stripped.startswith("/"):
            skip = stripped == "//" + name
        if not skip:
            out.append(line)
    return "\n".join(out)


def with_repair_block(text, block):
    """TEXT with BLOCK as the first menu entry (before any '###' lines directly above the first entry, where the
    promotion cut it from) and default_entry 1."""
    lines = text.split("\n")
    first = next((i for i, l in enumerate(lines) if l.startswith("/")), None)
    if first is None:
        raise Stop("limine.conf has no menu entry; nothing written")
    while first > 0 and lines[first - 1].startswith("###"):
        first -= 1
    at = [i for i, l in enumerate(lines[:first]) if l[:14].lower() == "default_entry:"]
    if len(at) != 1:
        raise Stop("limine.conf has %d default_entry lines before its first entry, not one; nothing written" % len(at))
    lines[at[0]] = "default_entry: 1"
    new = "\n".join(lines[:first] + block.split("\n")[:-1] + lines[first:])
    hit = default_entry(new)
    if hit is None or hit[0] != 1 or hit[2] != REPAIR_UKI or new.count(REPAIR_UKI) != 1:
        raise Stop("internal: the restored menu does not start the repair entry; nothing written")
    return new


def restore_repair(esp, m, image_path, check_only):
    image_path = image_path or os.path.join(BUNDLE, BUNDLE_PROMOTION, os.path.basename(REPAIR_UKI))
    if not os.path.isfile(image_path):
        raise Stop("no repair image at %s (copied there in step P4b of docs/r3a-promotion.md); nothing written" % image_path)
    image = read(image_path)
    esp.open(not check_only)
    try:
        size, digest = repair_record(esp)
        if len(image) != size or sha(image) != digest:
            raise Stop("%s is not the repair image the ESP's record names (%d bytes, sha256 %s...); nothing written"
                       % (image_path, size, digest[:16]))
        block, sources = saved_repair_block(esp)
        text = esp.get(LIMINE).decode("utf-8")
        present = tool.LIMINE_MARKER in text or REPAIR_UKI in text
        cluster, free = esp.cluster(), esp.free()
        have_image = esp.has(REPAIR_UKI) and sha(esp.get(REPAIR_UKI)) == digest
        need = 0 if have_image else clusters(size, cluster) + RESERVE
        make_room = free < need
        new = None
        if not present:   # the menu is built before any write (and in --check), so a refusal leaves the ESP as it was
            new = text if esp.has(UKI) and not make_room else drop_sub_entry(text, "linux-aurora")
            new = with_repair_block(new, block)
        if check_only:
            say("restore-repair check (nothing written):")
            say("  repair image:   %s matches the ESP's record (%d bytes, sha256 %s...)" % (image_path, size, digest[:16]))
            say("  saved block:    %s, one repair entry (%s)" % (" and ".join(sources), block.split("\n")[1].lstrip("/")))
            if present:
                if block not in text:
                    raise Stop("limine.conf has a repair entry that is not the saved block: the saved copy is not the one "
                               "that boots. Make the saved copy again (docs/r3a-promotion.md, P0e)")
                say("  limine.conf:    the repair entry is in it now and is exactly the saved block (restore-repair is for after P5)")
            else:
                say("  limine.conf:    no repair entry; restore-repair would put the saved block first, with default_entry: 1")
            say("  space:          %.1f MB free, %.1f MB needed; %s" % (free / 1e6, need / 1e6,
                "omarchy_linux-aurora.efi and its entry would be removed to make room" if make_room and esp.has(UKI) else
                ("enough as it is" if not make_room else "NOT ENOUGH, and no omarchy_linux-aurora.efi to remove")))
            say("restore-repair check passed." if not make_room or esp.has(UKI) else "restore-repair check: short of space.")
            return
        if present:
            raise Stop("limine.conf already has a repair entry: use  default repair  instead; nothing written")
        if make_room and not esp.has(UKI):
            raise Stop("%.1f MB free, %.1f MB needed, and no omarchy_linux-aurora.efi to remove; nothing written"
                       % (free / 1e6, need / 1e6))
        if make_room:
            # The hook-built linux-aurora image goes first: it is built the same way as the image that failed. Its
            # entry goes in the menu write below, and a run stopped in between is finished by running this again.
            esp.remove(UKI)
            say("removed %s to make room" % UKI)
        if not have_image:
            if esp.has(REPAIR_UKI):
                esp.remove(REPAIR_UKI)   # not named by limine.conf (checked above), and not the recorded image
            esp.put(REPAIR_UKI, image)
            if sha(esp.get(REPAIR_UKI)) != digest:
                raise Stop("%s does not verify after writing; limine.conf is unchanged. Run this again" % REPAIR_UKI)
        esp.put(LIMINE, new.encode("utf-8"))
        if esp.get(LIMINE).decode("utf-8") != new:
            raise Stop("limine.conf does not read back as written: run this again")
        state = live_state(esp, m)
    finally:
        esp.close()
    say("Restored the repair entry as entry 1 and the default (default_entry: 1), booting %s." % REPAIR_UKI)
    say("Start Linux: the repair kernel runs on the configured Stage 2. Then see docs/r3a-promotion.md, section 5.")
    show(state)


def main(argv):
    arguments = [a for a in argv[1:]]
    options = {"--stage2": "r1", "--kernel": "r1", "--esp-dir": None}
    assume_yes = "--yes" in arguments
    arguments = [a for a in arguments if a != "--yes"]
    for key in list(options):
        if key in arguments:
            index = arguments.index(key)
            if index + 1 >= len(arguments):
                raise Stop("%s needs a value" % key)
            options[key] = arguments[index + 1]
            del arguments[index:index + 2]
    if not arguments or arguments[0] not in ("status", "check", "apply", "rollback", "stage2", "default", "kernel", "restore-repair"):
        say(__doc__)
        return 2
    if options["--stage2"] not in ("r1", "wifi", "gp1c", "keep"):
        raise Stop("--stage2 must be r1, wifi, gp1c or keep")
    if options["--kernel"] not in VARIANTS:
        raise Stop("--kernel must be r1 or r1a")
    m = manifest()
    esp = Esp(options["--esp-dir"])
    command = arguments[0]
    if command == "status":
        esp.open(False)
        try:
            show(live_state(esp, m))
        finally:
            esp.close()
        return 0
    if command == "restore-repair":
        rest = arguments[1:]
        check_only = "--check" in rest
        rest = [a for a in rest if a != "--check"]
        if len(rest) > 1:
            raise Stop("usage: restore-repair [--check] [REPAIR_IMAGE]")
        restore_repair(esp, m, rest[0] if rest else None, check_only)
        return 0
    if command == "rollback":
        rollback(esp, m, arguments[1] if len(arguments) > 1 else "all")
        return 0
    if command in ("stage2", "default", "kernel"):
        if len(arguments) != 2:
            raise Stop("usage: %s VALUE" % command)
        {"stage2": switch_stage2, "default": switch_default, "kernel": switch_kernel}[command](esp, m, arguments[1])
        return 0
    os.makedirs(os.path.join(BUNDLE, "work"), exist_ok=True)
    work = tempfile.mkdtemp(prefix=time.strftime("%Y%m%d-%H%M%S") + "-" + command + "-",
                            dir=os.path.join(BUNDLE, "work"))
    os.chmod(work, 0o755)
    try:
        if command == "check":
            esp.open(False)
            try:
                state, new, summary = plan(esp, m, options["--stage2"], options["--kernel"], work)
                save_live_copy(esp, work, state)
            finally:
                esp.close()
            show(state)
            show_space(summary)
            say("\nCheck passed. Nothing was written to the ESP. Plan and built files: %s" % work)
            for rel, item in summary["writes"].items():
                say("  %-58s %10d  %s" % (rel, item["bytes"], item["sha256"][:16]))
        else:
            apply(esp, m, options["--stage2"], options["--kernel"], work, assume_yes)
    finally:
        uid, gid = os.environ.get("SUDO_UID"), os.environ.get("SUDO_GID")
        if uid and gid and os.geteuid() == 0:
            subprocess.run(["/usr/sbin/chown", "-R", "%s:%s" % (uid, gid), os.path.join(BUNDLE, "work")])
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Stop as stop:
        say("k114s-repair: STOPPED: %s" % stop)
        sys.exit(1)
    except SystemExit:
        raise
    except subprocess.CalledProcessError as error:
        say("k114s-repair: STOPPED: %s failed: %s" % (error.cmd, (error.stderr or b"").decode().strip()))
        sys.exit(1)
