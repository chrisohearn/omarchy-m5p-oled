#!/usr/bin/python3
"""K114s repair r1: apply to (or roll back from) the existing Omarchy ESP, from macOS.

  status      read-only: which known state each boot file is in
  check       read-only: verify the live ESP, build every new file under work/, write nothing
  apply       check, then back up and write (asks for one typed confirmation)
  stage2 V    after apply: switch only the Stage 2 device tree: r1 | wifi | gp1c | trial1
  default V   after apply: which boot entry starts by default: r1 | r1a | original
  rollback    restore from the ESP backup:  rollback stage2  (device tree only)
              or  rollback all  (limine.conf, Stage 2, vendor firmware; removes the repair kernels)

Options: --stage2 r1|wifi|gp1c|keep   which device tree the Stage 2 gets at apply (default r1)
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
from asahi_firmware.core import FWFile, FWPackage  # noqa: E402

UKI = "EFI/Linux/omarchy_linux-aurora.efi"
NEW_UKI = "EFI/Linux/omarchy_linux-aurora-k114s-r1.efi"
# The two repair kernels: (id, UKI on the ESP, kernel image, trackpad module, menu title, comment)
KERNELS = (
    ("r1", NEW_UKI, "Image-k114s-r1", "hid-magicmouse-r1.ko",
     "Omarchy K114s repair r1 (trackpad fix B)",
     "Repair kernel, trackpad series aurora-silicon/linux#1568 (tested on the 14-inch K114c)."),
    ("r1a", "EFI/Linux/omarchy_linux-aurora-k114s-r1a.efi", "Image-k114s-r1a", "hid-magicmouse-r1a.ko",
     "Omarchy K114s repair r1a (trackpad fix A)",
     "Repair kernel, upstream trackpad fix aurora-silicon/linux#1830 (K116s) plus product 0x0361."),
)
STAGE2_FILES = {"r1": ("boot-ctxr-k114s-r1.bin", "t6050-k114s-r1.dtb"),
                "wifi": ("boot-ctxr-k114s-r1-wifi.bin", "t6050-k114s-r1-wifi.dtb"),
                "gp1c": ("boot-ctxr-k114s-r1-gp1c.bin", "t6050-k114s-r1-gp1c.dtb"),
                "trial1": ("boot-ctxr-k114s-trial1.bin", "t6050-k114s-trial1.dtb")}
STAGE2 = "m1n1/boot-ctxr.bin"
LIMINE = "limine.conf"
VENDORFW = ("vendorfw/firmware.cpio", "vendorfw/firmware.tar", "vendorfw/manifest.txt")
REPAIR_DIR = "k114s-repair"
BACKUP_DIR = REPAIR_DIR + "/backup-before-r1"
LINUX_DIR = REPAIR_DIR + "/r1"
KVER = "7.3.0-17.v272-4-ARCH"
MODULE_ARC = "usr/lib/modules/" + KVER + "/kernel/drivers/hid/hid-magicmouse.ko"
import gzip  # noqa: E402
FTAB = "apple/centauri/k114s-ftab.bin"
TPMTFW = "apple/tpmtfw-k114s.bin"


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
    return all(os.path.isfile(os.path.join(mount, p)) for p in (UKI, STAGE2, LIMINE, "m1n1/boot.bin")) \
        and os.path.isdir(os.path.join(mount, "vendorfw"))


class Esp:
    """The one EFI system partition that holds the Omarchy boot files, found by content."""

    def __init__(self, test_dir=None):
        self.test_dir = test_dir
        self.device = None
        self.mount = None
        self.writable = False

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
        os.makedirs(os.path.dirname(target), exist_ok=True)
        temporary = target + ".k114s-new"
        try:
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
            raise Stop("writing %s failed (%s). The previous file is intact; run  status" % (rel, error))

    def free(self):
        stat = os.statvfs(self.mount)
        return stat.f_bavail * stat.f_frsize


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
            raise Stop("the ESP has no " + rel)
        state["files"][rel] = sha(esp.get(rel))
    uki = tool.Uki(esp.get(UKI))
    state["uki_uname"] = uki.content(".uname").rstrip(b"\0").decode()
    state["uki_linux_sha256"] = sha(uki.content(".linux"))
    state["kernel"] = {m["original_kernel_sha256"]: "original v272-4"}.get(state["uki_linux_sha256"], "unknown")
    state["stage2"] = stage2_state(esp.get(STAGE2), m)
    state["boot_bin"] = "image combined" if state["files"]["m1n1/boot.bin"] == m["stage2_sha256"]["image-combined"] else "other"
    names = [n for n, _ in tar_files(esp.get(VENDORFW[1]))]
    state["vendorfw_files"] = len(names)
    state["vendorfw_has_tpmtfw"] = TPMTFW in names
    state["vendorfw_has_ftab"] = FTAB in names
    state["new_uki_present"] = any(esp.has(k[1]) for k in KERNELS)
    limine = esp.get(LIMINE).decode("utf-8")
    state["limine_has_repair_entry"] = any(k[1] in limine for k in KERNELS)
    default = [l.split(":", 1)[1].strip() for l in limine.split("\n") if l.startswith("default_entry")]
    titles = [l.strip() for l in limine.split("\n") if l.lstrip().startswith("/")]
    state["limine_default"] = "%s -> %s" % (default[0], titles[int(default[0]) - 1].lstrip("/+")) \
        if default and default[0].isdigit() and 0 < int(default[0]) <= len(titles) else "unset"
    state["backup_present"] = esp.has(BACKUP_DIR + "/backup.json")
    state["free_bytes"] = esp.free()
    return state


def show(state):
    say("  ESP device:            %s" % state["device"])
    say("  installed kernel UKI:  %s (%s)" % (state["kernel"], state["uki_uname"]))
    say("  Stage 2 (boot-ctxr):   %s" % state["stage2"])
    say("  vendor firmware:       %d files; trackpad firmware %s; N1 firmware %s" % (
        state["vendorfw_files"], "present" if state["vendorfw_has_tpmtfw"] else "MISSING",
        "present" if state["vendorfw_has_ftab"] else "absent"))
    say("  repair UKI on ESP:     %s; Limine repair entry: %s" % (
        "yes" if state["new_uki_present"] else "no", "yes" if state["limine_has_repair_entry"] else "no"))
    say("  Limine default entry:  %s" % state["limine_default"])
    say("  backup on ESP:         %s; free space %.0f MB" % (
        "yes" if state["backup_present"] else "no", state["free_bytes"] / 1e6))


# --- building the new files --------------------------------------------------

def build_vendorfw(esp, m, work):
    old = tar_files(esp.get(VENDORFW[1]))
    names = [n for n, _ in old]
    adds = []
    if FTAB not in names:
        adds.append((FTAB, payload("k114s-ftab.bin", m)))
    if TPMTFW not in names:
        adds.append((TPMTFW, payload("tpmtfw-k114s.bin", m)))
    out = os.path.join(work, "vendorfw")
    os.makedirs(out)
    package = FWPackage(out)
    for name, data in old + adds:
        package.add_file(name, FWFile(name, data))
    package.close()
    new = {rel: read(os.path.join(out, os.path.basename(rel))) for rel in VENDORFW}
    again = dict(tar_files(new[VENDORFW[1]]))
    if list(again) != names + [n for n, _ in adds]:
        raise Stop("rebuilt vendor firmware does not list the same files")
    for name, data in old + adds:
        if again[name] != data:
            raise Stop("rebuilt vendor firmware changed " + name)
    entries, _ = tool.newc_parse(new[VENDORFW[0]])
    cpio_names = {e[0] for e in entries}
    for name, _ in old + adds:
        if "vendorfw/" + name not in cpio_names:
            raise Stop("rebuilt firmware.cpio lacks " + name)
    # The image's initrd reads firmware.cpio: prove the old archive's files are all still there.
    old_entries, _ = tool.newc_parse(esp.get(VENDORFW[0]))
    missing = {e[0] for e in old_entries} - cpio_names
    if missing:
        raise Stop("rebuilt firmware.cpio lost %s" % sorted(missing)[:3])
    return new, [n for n, _ in adds]


def stage2_payload(choice, m):
    data = payload(STAGE2_FILES[choice][0], m)
    prefix, trees, trailer = tool.stage2_split(data, m["aura_prefix_bytes"])
    if sha(prefix) != m["aura_prefix_sha256"] or sha(trailer) != m["uboot_trailer_sha256"] or len(trees) != 1 \
            or tool.fdt_root_compatible(trees[0])[0] != "apple,k114s" \
            or sha(trees[0]) != m["payload"][STAGE2_FILES[choice][1]]:
        raise Stop("the bundle's Stage 2 is not a K114s-only image of the installed loader")
    return data


def plan(esp, m, stage2_choice, work):
    state = live_state(esp, m)
    if state["uki_uname"] != KVER:
        raise Stop("the installed kernel is %s, not %s: this repair is built for that exact kernel"
                   % (state["uki_uname"], KVER))
    if state["kernel"] != "original v272-4":
        raise Stop("the installed UKI does not carry the original v272-4 kernel image; not touching it")
    if state["limine_has_repair_entry"] or state["new_uki_present"]:
        raise Stop("a K114s repair is already applied; use status or rollback")
    if state["stage2"] == "unknown" and stage2_choice != "keep":
        raise Stop("the live Stage 2 is not one this bundle knows; use --stage2 keep or investigate")
    new = {}
    for _, uki_rel, image, module, _, _ in KERNELS:
        extra = tool.cpio_make([(MODULE_ARC, payload(module, m))])
        new[uki_rel] = tool.uki_build(esp.get(UKI), payload(image, m), extra)
    text, cmdline = tool.limine_add(esp.get(LIMINE).decode("utf-8"),
                                    [("/" + k[1], k[4], k[5] + " The original entry is below, unchanged.")
                                     for k in KERNELS], "/" + UKI, 5)
    new[LIMINE] = text.encode("utf-8")
    firmware, added = build_vendorfw(esp, m, work)
    new.update(firmware)
    if stage2_choice != "keep":
        new[STAGE2] = stage2_payload(stage2_choice, m)
    linux = {}
    for name in ("linux-persist.sh", "update-boot-ctxr-k114s", "apply-holds", "README-linux.txt"):
        linux[name] = read(os.path.join(BUNDLE, "linux", name))
    for ident, _, image, module, _, _ in KERNELS:
        linux["hid-magicmouse-%s.ko" % ident] = payload(module, m)
        linux["vmlinuz-k114s-%s.gz" % ident] = gzip.compress(payload(image, m), 6, mtime=0)
    linux["SHA256SUMS"] = "".join("%s  %s\n" % (sha(v), k) for k, v in sorted(linux.items())).encode()
    for name, data in linux.items():
        new[LINUX_DIR + "/" + name] = data
    # The pinned device tree the Linux-side hook rebuilds the Stage 2 from follows the Stage 2.
    new[REPAIR_DIR + "/k114s.dtb"] = payload(STAGE2_FILES["trial1" if stage2_choice == "keep" else stage2_choice][1], m)
    backups = [LIMINE, STAGE2] + list(VENDORFW)
    replaced = [len(v) for r, v in new.items() if esp.has(r)]
    need = sum(len(v) for r, v in new.items() if not esp.has(r)) + sum(len(esp.get(b)) for b in backups) \
        + sum(max(0, len(v) - len(esp.get(r))) for r, v in new.items() if esp.has(r)) \
        + (max(replaced) if replaced else 0) + (8 << 20)
    if need > state["free_bytes"]:
        raise Stop("not enough free space on the ESP: need about %.0f MB, have %.0f MB"
                   % (need / 1e6, state["free_bytes"] / 1e6))
    for rel, data in new.items():
        target = os.path.join(work, "new", rel)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "wb") as stream:
            stream.write(data)
    summary = {"state_before": state, "stage2": stage2_choice, "firmware_added": added, "cmdline": cmdline,
               "writes": {rel: {"bytes": len(data), "sha256": sha(data)} for rel, data in sorted(new.items())},
               "backups": backups}
    with open(os.path.join(work, "plan.json"), "w") as stream:
        json.dump(summary, stream, indent=1)
    return state, new, summary


# --- apply / rollback --------------------------------------------------------

def save_live_copy(esp, work):
    for rel in (UKI, STAGE2, LIMINE, "m1n1/boot.bin") + VENDORFW:
        target = os.path.join(work, "live", rel)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copyfile(esp.path(rel), target)


def apply(esp, m, stage2_choice, work, assume_yes):
    esp.open(False)
    try:
        state, new, summary = plan(esp, m, stage2_choice, work)
        save_live_copy(esp, work)
    finally:
        esp.close()
    say("Verified the live ESP and built every new file under:\n  %s" % work)
    show(state)
    say("\nWill write to the ESP (%s):" % state["device"])
    for rel, item in summary["writes"].items():
        say("  %-58s %10d  %s" % (rel, item["bytes"], item["sha256"][:16]))
    say("Backups kept on the ESP in %s/ and on this Mac in work/.../live/." % BACKUP_DIR)
    say("The original kernel entry stays in the Limine menu; the repair entry becomes the default.")
    if not assume_yes:
        if input("\nType  apply  to write these files: ").strip() != "apply":
            raise Stop("nothing written")
    esp.open(True)
    try:
        after_check = live_state(esp, m)
        if after_check["files"] != state["files"]:
            raise Stop("the ESP changed between check and apply; nothing written")
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
        order = [r for r in new if r.startswith(REPAIR_DIR)] + [k[1] for k in KERNELS] + list(VENDORFW) \
            + ([STAGE2] if STAGE2 in new else []) + [LIMINE]
        for rel in order:
            esp.put(rel, new[rel])
        for rel in order:
            if sha(esp.get(rel)) != summary["writes"][rel]["sha256"]:
                raise Stop("%s does not verify after writing: run  rollback  now" % rel)
        esp.put(REPAIR_DIR + "/applied-r1.json", json.dumps(summary, indent=1).encode())
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
        wanted = {"stage2": [STAGE2], "all": [LIMINE, STAGE2] + list(VENDORFW)}[what]
        for rel in wanted:
            data = esp.get(BACKUP_DIR + "/" + rel)
            if sha(data) != record["files"][rel]:
                raise Stop("backup of %s is damaged; not restoring it" % rel)
        for rel in wanted:
            esp.put(rel, esp.get(BACKUP_DIR + "/" + rel))
            if sha(esp.get(rel)) != record["files"][rel]:
                raise Stop("restore of %s did not verify" % rel)
        # The pinned tree the Linux-side hook rebuilds the Stage 2 from goes back as well.
        esp.put(REPAIR_DIR + "/k114s.dtb", payload(STAGE2_FILES["trial1"][1], m))
        if what == "all":
            for kernel in KERNELS:
                if esp.has(kernel[1]):
                    os.remove(esp.path(kernel[1]))
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


def switch_default(esp, m, choice):
    esp.open(True)
    try:
        text = esp.get(LIMINE).decode("utf-8")
        if not all(k[1] in text for k in KERNELS):
            raise Stop("apply the repair first (limine.conf has no repair entries)")
        if choice in ("r1", "r1a"):
            index = [k[0] for k in KERNELS].index(choice) + 1
        elif choice == "original":
            old = esp.get(BACKUP_DIR + "/" + LIMINE).decode("utf-8")
            value = [l.split(":", 1)[1].strip() for l in old.split("\n") if l.startswith("default_entry")]
            index = (int(value[0]) if value and value[0].isdigit() else 1) + len(KERNELS)
        else:
            raise Stop("default must be r1, r1a or original")
        esp.put(LIMINE, tool.limine_default(text, index).encode("utf-8"))
        state = live_state(esp, m)
    finally:
        esp.close()
    say("Default boot entry changed.")
    show(state)


def main(argv):
    arguments = [a for a in argv[1:]]
    options = {"--stage2": "r1", "--esp-dir": None}
    assume_yes = "--yes" in arguments
    arguments = [a for a in arguments if a != "--yes"]
    for key in list(options):
        if key in arguments:
            index = arguments.index(key)
            if index + 1 >= len(arguments):
                raise Stop("%s needs a value" % key)
            options[key] = arguments[index + 1]
            del arguments[index:index + 2]
    if not arguments or arguments[0] not in ("status", "check", "apply", "rollback", "stage2", "default"):
        say(__doc__)
        return 2
    if options["--stage2"] not in ("r1", "wifi", "gp1c", "keep"):
        raise Stop("--stage2 must be r1, wifi, gp1c or keep")
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
    if command in ("stage2", "default"):
        if len(arguments) != 2:
            raise Stop("usage: %s VALUE" % command)
        (switch_stage2 if command == "stage2" else switch_default)(esp, m, arguments[1])
        return 0
    os.makedirs(os.path.join(BUNDLE, "work"), exist_ok=True)
    work = tempfile.mkdtemp(prefix=time.strftime("%Y%m%d-%H%M%S") + "-" + command + "-",
                            dir=os.path.join(BUNDLE, "work"))
    os.chmod(work, 0o755)
    try:
        if command == "check":
            esp.open(False)
            try:
                state, new, summary = plan(esp, m, options["--stage2"], work)
                save_live_copy(esp, work)
            finally:
                esp.close()
            show(state)
            say("\nCheck passed. Nothing was written to the ESP. Plan and built files: %s" % work)
            for rel, item in summary["writes"].items():
                say("  %-58s %10d  %s" % (rel, item["bytes"], item["sha256"][:16]))
        else:
            apply(esp, m, options["--stage2"], work, assume_yes)
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
