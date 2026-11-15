#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Check a resolved kernel .config against one or more requirement fragments.

    build/validate-config.py [options] CONFIG FRAGMENT [FRAGMENT ...]

CONFIG is a resolved configuration: a build tree's .config, /proc/config.gz, or any
file in that format (a .gz is read as gzip). Each FRAGMENT is a Kconfig merge fragment
such as patches/linux/config/k114s-r3.config.

Kconfig drops a requested option without an error when one of its dependencies is off
or the symbol does not exist in the tree. This script is the check that nothing asked
for was lost that way. It follows the method of betizzel/omarchy-m5's validate-config.py
(installer/recipes/linux-aurora-j714s) and adds: several fragments, "m or better",
"must stay off", a gzip reader and a machine-readable report.

How a fragment line is judged:

    CONFIG_FOO=y              FOO must be y
    CONFIG_FOO=m              FOO must be m, or y (built in is accepted and counted;
                              --verbose lists them, --exact refuses them)
    CONFIG_FOO="text" / =123  FOO must have exactly that value
    # CONFIG_FOO is not set   FOO must be off or absent

Any other line starting with '#' is a comment. A symbol requested with two different
values (in one fragment or across fragments) is an error in the fragments themselves.

Exit status: 0 all requirements hold, 1 at least one does not, 2 usage or input error.
"""
import argparse
import gzip
import json
import re
import sys
from pathlib import Path

ASSIGN = re.compile(r'^(CONFIG_[A-Za-z0-9_]+)=(.*)$')
UNSET = re.compile(r'^# (CONFIG_[A-Za-z0-9_]+) is not set$')


class InputError(Exception):
    """A file could not be read as a kernel configuration or fragment."""


def read_text(path):
    data = Path(path).read_bytes()
    if data[:2] == b'\x1f\x8b':
        data = gzip.decompress(data)
    return data.decode('utf-8', errors='replace')


def parse(path, fragment=False):
    """Return {CONFIG_NAME: value}; an option that is off has the value 'n'.

    For a fragment, a second, different request for one symbol raises InputError.
    A resolved .config never has duplicates, so the last value simply wins there.
    """
    values = {}
    try:
        text = read_text(path)
    except OSError as error:
        raise InputError(f'{path}: {error.strerror}') from error
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        match = ASSIGN.match(line)
        if match:
            name, value = match.group(1), match.group(2)
        else:
            match = UNSET.match(line)
            if not match:
                if line and not line.startswith('#'):
                    raise InputError(f'{path}:{number}: not a configuration line: {raw!r}')
                continue
            name, value = match.group(1), 'n'
        if fragment:
            if not re.fullmatch(r'[ymn]|-?\d+|0[xX][0-9a-fA-F]+|"[^"]*"', value):
                raise InputError(f'{path}:{number}: {name} has an unusable value {value!r} '
                                 '(a comment after the value is not allowed in a fragment)')
            if name in values and values[name] != value:
                raise InputError(f'{path}:{number}: {name} requested as {value}, '
                                 f'earlier as {values[name]}')
        values[name] = value
    return values


def merge_fragments(paths):
    """Union of the fragments. Returns ({name: (value, path)}, [conflict text])."""
    wanted, conflicts = {}, []
    for path in paths:
        for name, value in parse(path, fragment=True).items():
            if name in wanted and wanted[name][0] != value:
                conflicts.append(f'{name}: {wanted[name][1]} wants {wanted[name][0]}, '
                                 f'{path} wants {value}')
                continue
            wanted[name] = (value, str(path))
    return wanted, conflicts


def judge(wanted, actual, exact=False):
    """Compare. Returns (failures, promoted): lists of dicts."""
    failures, promoted = [], []
    for name, (value, source) in wanted.items():
        got = actual.get(name, 'n')
        shown = got if name in actual else 'absent'
        if got == value:
            continue
        if value == 'm' and got == 'y' and not exact:
            promoted.append({'option': name, 'wanted': value, 'got': got, 'fragment': source})
            continue
        failures.append({'option': name, 'wanted': value, 'got': shown, 'fragment': source})
    return failures, promoted


def main(argv=None):
    parser = argparse.ArgumentParser(
        description='Check a resolved kernel .config against requirement fragments.',
        epilog='Exit status: 0 pass, 1 a requirement is not met, 2 usage or input error.')
    parser.add_argument('config', help='resolved configuration (.config, or a .gz such as /proc/config.gz)')
    parser.add_argument('fragments', nargs='+', metavar='fragment', help='requirement fragment(s)')
    parser.add_argument('--exact', action='store_true',
                        help='refuse y where a fragment asks for m')
    parser.add_argument('--json', action='store_true', help='print the result as JSON')
    parser.add_argument('--quiet', action='store_true', help='print failures only')
    parser.add_argument('--verbose', action='store_true',
                        help='also list each option that is built in where m was requested')
    args = parser.parse_args(argv)

    try:
        actual = parse(args.config)
        wanted, conflicts = merge_fragments(args.fragments)
    except InputError as error:
        print(f'validate-config: {error}', file=sys.stderr)
        return 2
    if not actual:
        print(f'validate-config: {args.config}: no CONFIG_ lines found', file=sys.stderr)
        return 2
    if conflicts:
        for text in conflicts:
            print(f'validate-config: fragments disagree: {text}', file=sys.stderr)
        return 2

    failures, promoted = judge(wanted, actual, exact=args.exact)
    if args.json:
        print(json.dumps({'config': args.config, 'fragments': args.fragments,
                          'checked': len(wanted), 'failures': failures,
                          'built_in_where_module_requested': promoted,
                          'pass': not failures}, indent=2))
        return 1 if failures else 0

    for item in failures:
        print(f"FAIL {item['option']}: wanted {item['wanted']}, got {item['got']} "
              f"({item['fragment']})")
    if args.verbose:
        for item in promoted:
            print(f"note {item['option']}: asked for m, is built in (y)")
    status = 'FAILED' if failures else 'passed'
    if failures or not args.quiet:
        print(f'validate-config: {status}: {len(wanted)} requirements, {len(failures)} not met, '
              f'{len(promoted)} built in where a module was requested')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
