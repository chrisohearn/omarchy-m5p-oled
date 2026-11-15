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
  stage2 V    after apply: switch only the Stage 2 device tree: r1 | wifi | gp1c | trial1
  default V   after apply: which boot entry starts by default: repair | original
  rollback    restore from the ESP backup:  rollback stage2  (device tree only)
              or  rollback all  (limine.conf and Stage 2; removes the repair kernel)

If the original kernel image (EFI/Linux/omarchy_linux-aurora.efi) was removed from the ESP to make room
(the r3a kernel trial, docs/r3-integration.md), status, stage2, default repair and rollback stage2 keep
working; kernel, default original, rollback all and apply stop with a message and write nothing,
because each would need that image.

Options: --kernel r1|r1a              which repair kernel apply installs (default r1)
         --stage2 r1|wifi|gp1c|keep   which device tree the Stage 2 gets at apply (default r1)
         --yes                   skip the typed confirmation
         --esp-dir DIR           test mode: treat DIR as the mounted ESP (no diskutil, no root)

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
    # repair image then stands in for it.
    return (have(UKI) or have(REPAIR_UKI)) and all(have(p) for p in (STAGE2, LIMINE, "m1n1/boot.bin")) \
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

def stage2_state(data, m):
    known = {v: k for k, v in m["stage2_sha256"].items()}
    digest = sha(data)
    if digest in known:
        return known[digest]
    try:
        prefix, trees, trailer = tool.stage2_split(data, m["aura_prefix_bytes"])
    except SystemExit:
        return "unknown"
    if sha(prefix) == m["aura_prefix_sha256"] and sha(trailer) == m["uboot_trailer_sha256"]:
        return "same-loader-other-trees(%d)" % len(trees)
    return "unknown"


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
            if rel == UKI and esp.has(REPAIR_UKI):
                continue   # removed on purpose to make room (docs/r3-integration.md); not an error
            raise Stop("the ESP has no " + rel)
        state["files"][rel] = sha(esp.get(rel))
    if UKI in state["files"]:
        uki = tool.Uki(esp.get(UKI))
        state["uki_uname"] = uki.content(".uname").rstrip(b"\0").decode()
        state["uki_linux_sha256"] = sha(uki.content(".linux"))
        state["kernel"] = {m["original_kernel_sha256"]: "original v272-4"}.get(state["uki_linux_sha256"], "unknown")
    else:
        state["uki_uname"], state["uki_linux_sha256"], state["kernel"] = None, None, "removed"
    state["stage2"] = stage2_state(esp.get(STAGE2), m)
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
    default = [l.split(":", 1)[1].strip() for l in limine.split("\n") if l.startswith("default_entry")]
    titles = [l.strip() for l in limine.split("\n") if l.lstrip().startswith("/")]
    state["limine_default"] = "%s -> %s" % (default[0], titles[int(default[0]) - 1].lstrip("/+")) \
        if default and default[0].isdigit() and 0 < int(default[0]) <= len(titles) else "unset"
    state["backup_present"] = esp.has(BACKUP_DIR + "/backup.json")
    state["linux_revisions"] = [r for r in ("r1", "r2", "r2c") if esp.has(REPAIR_DIR + "/" + r + "/SHA256SUMS")]
    state["free_bytes"] = esp.free()
    state["cluster_bytes"] = esp.cluster()
    return state


def show(state):
    say("  ESP device:            %s" % state["device"])
    if state["kernel"] == "removed":
        say("  installed kernel UKI:  REMOVED (the original image is not on the ESP; the repair image is the only Linux image)")
    else:
        say("  installed kernel UKI:  %s (%s)" % (state["kernel"], state["uki_uname"]))
    say("  Stage 2 (boot-ctxr):   %s" % state["stage2"])
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
    if choice not in STAGE2_FILES:
        raise Stop("stage2 must be one of: " + ", ".join(STAGE2_FILES))
    data = stage2_payload(choice, m)
    esp.open(True)
    try:
        if not esp.has(BACKUP_DIR + "/backup.json"):
            raise Stop("apply the repair first (no backup on the ESP yet)")
        if stage2_state(esp.get(STAGE2), m) == "unknown":
            raise Stop("the live Stage 2 is not one this bundle knows; not replacing it")
        esp.put(STAGE2, data)
        esp.put(REPAIR_DIR + "/k114s.dtb", payload(STAGE2_FILES[choice][1], m))
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
        if REPAIR_UKI not in text:
            raise Stop("apply the repair first (limine.conf has no repair entry)")
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
            raise Stop("default must be repair or original")
        esp.put(LIMINE, tool.limine_default(text, index).encode("utf-8"))
        state = live_state(esp, m)
    finally:
        esp.close()
    say("Default boot entry changed.")
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
    if not arguments or arguments[0] not in ("status", "check", "apply", "rollback", "stage2", "default", "kernel"):
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
