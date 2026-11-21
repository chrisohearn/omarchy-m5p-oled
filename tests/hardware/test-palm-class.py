#!/usr/bin/env python3
"""Synthetic HID frames and device identities. No real devices are opened."""

import contextlib
import errno
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
from types import SimpleNamespace
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "palm_class", Path(__file__).with_name("k114s-palm-class.py"))
palm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(palm)

TRACKPAD_UEVENT = "HID_ID=0019:000005AC:00000361\nHID_NAME=Apple MTP multi-touch\n"


def frame(*contacts):
    report = bytearray(113 + len(contacts) * 48)
    report[0] = 0x5A
    report[48:54] = bytes((0x02, 8, 48, 8 + len(contacts) * 48, 0, len(contacts)))
    for i, (phase, value) in enumerate(contacts):
        offset = 60 + 48 * i
        report[offset:offset + 9] = bytes((0, 99, phase, value, 0, 0xCA, 0xFE, 0xDE, 0xAD))
    return bytes(report)


class PalmClassTest(unittest.TestCase):
    def test_multiple_contacts_and_lift(self):
        self.assertEqual(palm.contact_classes(frame((3, 2), (4, 7), (5, 42))), (2, 7))
        self.assertEqual(palm.contact_classes(frame()), ())

    def test_rejects_unrelated_and_truncated_reports(self):
        valid = frame((4, 7))
        for report in (b"", valid[:107], valid[:-1], valid + b"\x00", b"\x75" + valid[1:],
                       valid[:48] + b"\x03" + valid[49:],
                       valid[:49] + b"\x07" + valid[50:],
                       valid[:50] + b"\x2f" + valid[51:],
                       valid[:51] + b"\x08" + valid[52:]):
            with self.subTest(length=len(report)):
                self.assertIsNone(palm.contact_classes(report))

    def test_rejects_other_devices_before_opening(self):
        device = SimpleNamespace(st_mode=stat.S_IFCHR, st_rdev=os.makedev(240, 0))
        for identity in (TRACKPAD_UEVENT.replace("multi-touch", "keyboard"),
                         TRACKPAD_UEVENT.replace("0361", "0362"),
                         TRACKPAD_UEVENT.replace("05AC", "1234"),
                         TRACKPAD_UEVENT.replace("0019", "0003"), "",
                         FileNotFoundError()):
            with (self.subTest(identity=identity),
                  patch.object(palm.os, "lstat", return_value=device),
                  patch.object(palm.Path, "read_text", side_effect=[identity]),
                  patch.object(palm.os, "open") as open_device):
                with self.assertRaises(ValueError), palm.open_trackpad("/dev/hidraw0"):
                    self.fail("unverified device was accepted")
                open_device.assert_not_called()

    def run_pass(self, name, reports):
        device = SimpleNamespace(st_mode=stat.S_IFCHR, st_rdev=os.makedev(240, 0),
                                 st_dev=5, st_ino=12)
        stdout, stderr = io.StringIO(), io.StringIO()
        with (patch.object(palm.sys, "argv", ["palm-class", "/dev/hidraw0", name]),
              patch.object(palm.os, "lstat", return_value=device),
              patch.object(palm.os, "fstat", return_value=device),
              patch.object(palm.Path, "read_text", return_value=TRACKPAD_UEVENT),
              patch.object(palm.os, "open", return_value=12) as open_device,
              patch.object(palm.os, "close") as close_device,
              patch.object(palm.select, "select",
                           side_effect=[([12], [], [])] * len(reports) + [([], [], [])]),
              patch.object(palm.os, "read", side_effect=reports),
              contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr)):
            status = palm.main()
        open_device.assert_called_once_with(
            "/dev/hidraw0", os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW | os.O_NOCTTY)
        close_device.assert_called_once_with(12)
        return status, json.loads(stdout.getvalue()) if stdout.getvalue() else None

    def test_passes_return_only_aggregate_counts(self):
        status, result = self.run_pass("finger", [frame((3, 2), (4, 3)), frame((4, 2))])
        self.assertEqual(status, 0)
        self.assertEqual(result, {"pass": "finger", "status": "observed",
                                  "class_counts": {"2": 2, "3": 1}})
        status, result = self.run_pass("resting-palm", [frame((4, 7)), frame((6, 2))])
        self.assertEqual(status, 0)
        self.assertEqual(result, {"pass": "resting-palm", "status": "observed",
                                  "class_counts": {"7": 1}})

    def test_empty_unsupported_and_interrupted_passes(self):
        for reports, outcome in (([], "no-data"), ([frame()], "no-data"),
                                 ([b"\x75", frame((4, 7))[:-1]], "unsupported")):
            with self.subTest(outcome=outcome):
                status, result = self.run_pass("finger", reports)
                self.assertEqual(status, 1)
                self.assertEqual(result, {"pass": "finger", "status": outcome, "class_counts": {}})
        self.assertEqual(self.run_pass("finger", [frame((4, 2)), OSError(errno.ENODEV)]),
                         (2, None))

    def test_deadline_stops_reading_when_reports_are_still_ready(self):
        with (patch.object(palm.time, "monotonic", side_effect=[0, 0, 10]),
              patch.object(palm.select, "select", return_value=([12], [], [])),
              patch.object(palm.os, "read", return_value=frame((4, 2))) as read):
            self.assertEqual(palm.capture(12, 10), ("observed", {2: 1}))
        read.assert_called_once()


if __name__ == "__main__":
    unittest.main()
