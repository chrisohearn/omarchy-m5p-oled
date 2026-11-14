#!/usr/bin/env python3
"""Build apple/centauri/k114s-ftab.bin for the K114s from Apple's 26B8125 restore image.

Same checks as the installer engine's omarchy_centauri.prepare() (Engine/overlay/src/
omarchy_centauri.py, which gates on j714sap / board 0x08), run for the k114sap identity:
chip 0x6050, board 0x14, the "macOS Customer" variant, Wireless1 chip 0x2026, one trusted FTAB,
the non-personalized production ticket centauri.k114sap.im4m, every FTAB segment's SHA-384
equal to the ticket's digest. The engine's own parsing functions are imported unchanged.
usage: make_k114s_ftab.py ENGINE_OVERLAY_SRC BUILDMANIFEST MEMBER_DIR OUT REPORT
MEMBER_DIR holds the IPSW members fetched by remotezip.py ('/' replaced by '__').
"""
import hashlib, json, plistlib, struct, sys, os
sys.path.insert(0, sys.argv[1])
import omarchy_centauri as oc
manifest = plistlib.load(open(sys.argv[2], 'rb')); members, out, report = sys.argv[3:6]
DEVICE_CLASS, CHIP, BOARD, TARGET = 'k114sap', 0x6050, 0x14, 'k114s'
ids = [b for b in manifest['BuildIdentities'] if b['Info']['DeviceClass'] == DEVICE_CLASS and b['Info']['Variant'] == 'macOS Customer']
assert len(ids) == 1, 'expected exactly one macOS Customer identity'
identity = ids[0]; info = identity['Info']
assert oc._number(identity['ApChipID']) == CHIP and oc._number(identity['ApBoardID']) == BOARD
assert info['BuildNumber'] == manifest['ProductBuildVersion'] == '26B8125'
wchip, wboard = oc._number(identity['Wireless1,ChipID']), oc._number(identity['Wireless1,BoardID'])
assert wchip == 0x2026, hex(wchip)
components = [e for k, e in identity['Manifest'].items() if k.startswith('Wireless1,')]
assert components and all(e.get('Trusted') is True for e in components)
paths = {e['Info']['Path'] for e in components}
assert len(paths) == 1 and all(e['Info'].get('IsFTAB') is True for e in components)
path = paths.pop(); ticket_path = 'Firmware/Manifests/restore/macOS Customer/centauri/centauri.' + DEVICE_CLASS + '.im4m'
if len(sys.argv) > 6 and sys.argv[6] == '--paths':
    print(path); print(ticket_path); sys.exit(0)
rd = lambda p: open(os.path.join(members, p.replace('/', '__')), 'rb').read()
data, ticket = rd(path), rd(ticket_path)
ftab = oc.ftab_parse(data, 'input FTAB')
assert not any(ftab['hdr'][i] for i in range(2, 8)) and not ftab['unk6'] and ftab['data_end'] == len(data) and len(data) % 4 == 0, 'unsupported or already ticketed FTAB'
manp, images = oc.im4m_parse(ticket)
assert not any(k in manp for k in (b'ECID', b'BNCH', b'snon', b'Nonc')), 'personalized ticket'
assert oc.as_int(manp, b'CHIP') == wchip and oc.as_int(manp, b'BORD') == wboard and oc.as_bool(manp, b'CPRO') and oc.as_bool(manp, b'CSEC')
expected = sorted(e['Digest'] for e in components); actual = sorted(p[b'DGST'][1] for p in images.values())
assert actual and expected == actual and all(len(d) == 48 for d in actual), 'Wireless1/ticket digest sets differ'
entries = {e[0]: e for e in ftab['ents']}
for tag, props in images.items():
    _, off, size, _ = entries[tag]
    assert hashlib.sha384(data[off:off + size]).digest() == props[b'DGST'][1], 'segment digest mismatch ' + repr(tag)
result = bytearray(data); struct.pack_into('<II', result, 0x10, len(data), len(ticket)); result.extend(ticket)
assert len(result) <= oc.MAX_DRIVER
open(out, 'xb').write(result)
json.dump({'schema': 1, 'name': 'apple/centauri/' + TARGET + '-ftab.bin', 'ipsw': 'UniversalMac_27.2_26B8125_Restore.ipsw', 'identity': DEVICE_CLASS,
           'ap_chip': hex(CHIP), 'ap_board': hex(BOARD), 'wireless1_chip': hex(wchip), 'wireless1_board': hex(wboard),
           'ftab_member': path, 'ftab_member_sha256': hashlib.sha256(data).hexdigest(), 'ftab_bytes': len(data),
           'ftab_tags': [e[0].decode('ascii', 'replace') for e in ftab['ents']],
           'ticket_member': ticket_path, 'ticket_sha256': hashlib.sha256(ticket).hexdigest(), 'ticket_bytes': len(ticket),
           'ticket_images': sorted(t.decode('ascii', 'replace') for t in images), 'segments_verified_sha384': len(images),
           'output_sha256': hashlib.sha256(result).hexdigest(), 'output_bytes': len(result)}, open(report, 'w'), indent=1)
print(open(report).read())
