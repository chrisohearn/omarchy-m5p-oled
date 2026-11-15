#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Tests for build/validate-config.py and the fragments in patches/linux/config.

    python3 tests/config/test_validate_config.py

Software tests only: they exercise the checker and the shape of the fragments. They do
not resolve a kernel configuration (that needs a kernel tree and its toolchain; the
commands are in docs/r3-config.md) and they say nothing about hardware.
"""
import contextlib
import gzip
import importlib.util
import io
import json
import re
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FRAGMENTS = ROOT / 'patches' / 'linux' / 'config'
DELTA = FRAGMENTS / 'k114s-r3.config'
REQUIRED = FRAGMENTS / 'k114s-required.config'

spec = importlib.util.spec_from_file_location('validate_config', ROOT / 'build' / 'validate-config.py')
vc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vc)


def run(*argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = vc.main([str(a) for a in argv])
    return code, out.getvalue(), err.getvalue()


class Checker(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.tmp = Path(self.dir.name)

    def write(self, name, text):
        path = self.tmp / name
        path.write_text(text)
        return path

    def test_pass_and_module_or_better(self):
        config = self.write('.config', 'CONFIG_A=y\nCONFIG_B=y\nCONFIG_C=m\n# CONFIG_D is not set\n'
                                       'CONFIG_S="-ARCH"\nCONFIG_N=5\n')
        frag = self.write('f.config', '# why\nCONFIG_A=y\nCONFIG_B=m\nCONFIG_C=m\n'
                                      '# CONFIG_D is not set\n# CONFIG_E is not set\n'
                                      'CONFIG_S="-ARCH"\nCONFIG_N=5\n')
        code, out, _ = run(config, frag)
        self.assertEqual(code, 0, out)
        self.assertIn('7 requirements, 0 not met, 1 built in', out)
        code, out, _ = run('--exact', config, frag)
        self.assertEqual(code, 1)
        self.assertIn('FAIL CONFIG_B: wanted m, got y', out)

    def test_dropped_wrong_and_forbidden(self):
        config = self.write('.config', 'CONFIG_A=m\nCONFIG_F=y\nCONFIG_S="-x"\n# CONFIG_G is not set\n')
        frag = self.write('f.config', 'CONFIG_A=y\nCONFIG_MISSING=m\n# CONFIG_F is not set\n'
                                      'CONFIG_S="-ARCH"\nCONFIG_G=m\n')
        code, out, _ = run(config, frag)
        self.assertEqual(code, 1)
        for text in ('CONFIG_A: wanted y, got m', 'CONFIG_MISSING: wanted m, got absent',
                     'CONFIG_F: wanted n, got y', 'CONFIG_S: wanted "-ARCH", got "-x"',
                     'CONFIG_G: wanted m, got n', '5 requirements, 5 not met'):
            self.assertIn(text, out)

    def test_gzip_and_json(self):
        path = self.tmp / 'config.gz'
        path.write_bytes(gzip.compress(b'CONFIG_A=y\n'))
        frag = self.write('f.config', 'CONFIG_A=y\nCONFIG_B=m\n')
        code, out, _ = run('--json', path, frag)
        self.assertEqual(code, 1)
        report = json.loads(out)
        self.assertFalse(report['pass'])
        self.assertEqual(report['checked'], 2)
        self.assertEqual(report['failures'][0]['option'], 'CONFIG_B')

    def test_input_errors(self):
        config = self.write('.config', 'CONFIG_A=y\n')
        one = self.write('one.config', 'CONFIG_A=y\n')
        two = self.write('two.config', 'CONFIG_A=m\n')
        code, _, err = run(config, one, two)
        self.assertEqual(code, 2)
        self.assertIn('fragments disagree', err)
        trailing = self.write('t.config', 'CONFIG_A=y # because\n')
        code, _, err = run(config, trailing)
        self.assertEqual(code, 2)
        self.assertIn('comment after the value', err)
        junk = self.write('j.config', 'CONFIG_A=y\nselect FOO\n')
        self.assertEqual(run(config, junk)[0], 2)
        self.assertEqual(run(self.tmp / 'absent', one)[0], 2)
        self.assertEqual(run(self.write('empty', '# nothing\n'), one)[0], 2)


class Fragments(unittest.TestCase):
    def test_parse_and_agree(self):
        wanted, conflicts = vc.merge_fragments([REQUIRED, DELTA])
        self.assertEqual(conflicts, [])
        self.assertGreater(len(wanted), 300)

    def test_delta_does_not_repeat_the_baseline(self):
        both = set(vc.parse(REQUIRED, fragment=True)) & set(vc.parse(DELTA, fragment=True))
        self.assertEqual(both, set())

    def test_every_option_has_a_reason(self):
        """Each option line sits under a comment in its own paragraph."""
        for path in (DELTA, REQUIRED):
            commented = False
            for number, line in enumerate(path.read_text().splitlines(), 1):
                if not line.strip():
                    commented = False
                elif vc.ASSIGN.match(line) or vc.UNSET.match(line):
                    self.assertTrue(commented, f'{path.name}:{number}: {line} has no comment above it')
                elif line.startswith('#'):
                    commented = True

    def test_delta_carries_an_evidence_label_per_paragraph(self):
        labels = re.compile(r'\[(observed|installed|peripheral|common)\]')
        paragraph, start = [], 0
        lines = DELTA.read_text().splitlines() + ['']
        for number, line in enumerate(lines, 1):
            if line.strip():
                if not paragraph:
                    start = number
                paragraph.append(line)
                continue
            if any(vc.ASSIGN.match(item) for item in paragraph):
                self.assertTrue(any(labels.search(item) for item in paragraph),
                                f'{DELTA.name}:{start}: paragraph has options but no evidence label')
            paragraph = []

    def test_safety_lines(self):
        delta = vc.parse(DELTA, fragment=True)
        required = vc.parse(REQUIRED, fragment=True)
        # The release string and module compatibility are requirements, never changes.
        self.assertEqual(required['CONFIG_LOCALVERSION'], '"-ARCH"')
        self.assertEqual(required['CONFIG_MODVERSIONS'], 'n')
        for name in ('CONFIG_LOCALVERSION', 'CONFIG_MODVERSIONS', 'CONFIG_HZ', 'CONFIG_PREEMPT',
                     'CONFIG_SECURITY_LOCKDOWN_LSM', 'CONFIG_MODULE_SIG', 'CONFIG_DEBUG_INFO_BTF'):
            self.assertNotIn(name, delta)
        # SMB1 stays off unless someone decides otherwise.
        self.assertEqual(delta['CONFIG_CIFS_ALLOW_INSECURE_LEGACY'], 'n')
        # Nothing in the delta is an Apple sound, amplifier or codec driver: sound is a
        # device tree matter, and speaker outputs are gated there.
        self.assertFalse([name for name in delta if re.search(r'SND_SOC|TAS27|CS42L8|MACAUDIO', name)])


if __name__ == '__main__':
    unittest.main(verbosity=2)
