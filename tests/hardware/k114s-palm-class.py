#!/usr/bin/env python3
"""Count candidate class bytes from one attended K114s trackpad pass."""

import argparse
from collections import Counter
from contextlib import contextmanager
import json
import os
from pathlib import Path
import re
import select
import stat
import sys
import time


TRACKPAD_IDENTITY = {"HID_ID=0019:000005AC:00000361", "HID_NAME=Apple MTP multi-touch"}
SECTION = 48
SECTION_HEADER = bytes((0x02, 8, 48))
FIRST_RECORD = 60
RECORD_SIZE = 48
EMPTY_REPORT_SIZE = 113  # Includes the 53 bytes after the contact section.


def contact_classes(report):
    """Return active record classes, or None for an unsupported frame."""
    # K2C1 layout from the pinned #1568 parser (patches/linux/r3b/0004-*).
    if (len(report) < EMPTY_REPORT_SIZE or report[0] != 0x5A
            or report[SECTION:SECTION + 3] != SECTION_HEADER):
        return None
    count = report[53]
    if (report[51] != 8 + count * RECORD_SIZE
            or len(report) != EMPTY_REPORT_SIZE + count * RECORD_SIZE):
        return None
    return tuple(
        report[offset + 3]
        for offset in range(FIRST_RECORD, FIRST_RECORD + count * RECORD_SIZE, RECORD_SIZE)
        if report[offset + 2] in (3, 4)
    )


def verify_trackpad(device):
    if not stat.S_ISCHR(device.st_mode):
        raise ValueError("unsupported device: expected a hidraw character device")
    uevent = Path(f"/sys/dev/char/{os.major(device.st_rdev)}:{os.minor(device.st_rdev)}/device/uevent")
    try:
        fields = uevent.read_text().splitlines()
    except OSError as exc:
        raise ValueError("unsupported device: hidraw identity unavailable") from exc
    if not TRACKPAD_IDENTITY.issubset(fields):
        raise ValueError("unsupported device: expected Apple MTP multi-touch (0019:05ac:0361)")


@contextmanager
def open_trackpad(path):
    if not re.fullmatch(r"/dev/hidraw[0-9]+", path):
        raise ValueError("expected one explicit /dev/hidrawN path")
    device = os.lstat(path)
    verify_trackpad(device)
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW | os.O_NOCTTY)
    try:
        opened = os.fstat(fd)
        if (opened.st_dev, opened.st_ino, opened.st_rdev) != (
                device.st_dev, device.st_ino, device.st_rdev):
            raise ValueError("hidraw node changed while opening")
        verify_trackpad(opened)
        yield fd
    finally:
        os.close(fd)


def capture(fd, seconds):
    counts = Counter()
    supported = unsupported = False
    deadline = time.monotonic() + seconds
    while (remaining := deadline - time.monotonic()) > 0:
        if not select.select([fd], [], [], remaining)[0]:
            break
        try:
            report = os.read(fd, 4096)
        except BlockingIOError:
            continue
        if not report:
            raise OSError("hidraw stopped delivering reports")
        classes = contact_classes(report)
        del report
        if classes is None:
            unsupported = True
        else:
            supported = True
            counts.update(classes)
    if counts:
        return "observed", counts
    return ("unsupported" if unsupported and not supported else "no-data"), counts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("device", metavar="/dev/hidrawN")
    parser.add_argument("pass_name", choices=("finger", "resting-palm"))
    parser.add_argument("--seconds", type=int, default=10, help="capture duration (1–30, default 10)")
    args = parser.parse_args()
    if not 1 <= args.seconds <= 30:
        parser.error("--seconds must be between 1 and 30")

    try:
        with open_trackpad(args.device) as fd:
            action = {"finger": "Move one finger on the trackpad",
                      "resting-palm": "Rest your palm on the trackpad"}[args.pass_name]
            print(f"{action} for {args.seconds} seconds now.", file=sys.stderr, flush=True)
            status, counts = capture(fd, args.seconds)
    except (ValueError, OSError) as exc:
        print(f"capture unavailable: {exc}", file=sys.stderr)
        return 2

    print(json.dumps({"pass": args.pass_name, "status": status, "class_counts": counts},
                     sort_keys=True))
    return 0 if status == "observed" else 1


if __name__ == "__main__":
    sys.exit(main())
