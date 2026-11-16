# K114s firmware inventory (issue #66)

Which firmware this Mac needs, where each piece comes from, and how to check it. Hashes and names only:
no Apple bytes are in this repository (`manifests/k114s-firmware.json`).

## What the issue assumed, and what is true

The issue said AOP, ISP and AVD firmware were "not extracted or checked". Read from the running system
on 2026-11-15 (agent-run):

| Firmware | Where it comes from | State |
|---|---|---|
| Wi-Fi ftab, Bluetooth, trackpad (`tpmtfw-k114s.bin`) | extracted from Apple's 27.2 image on the owner's side | in the vendor tarball; checked |
| ISP (`isp_*.dat`, six files) | the same vendor tarball | **already extracted**; hashes recorded. Which of the six this Mac's sensor uses is not known; there is no camera node in the booted tree and no `/dev/video*` |
| Ambient-light sensor factory calibration (`aop-als-cal.bin` and the raw `HmCA-*` file; Asahi's `asahi_firmware/als.py` copies both from macOS factory data) | the same vendor tarball | already extracted. Per-unit data: **no hash or file suffix is recorded**; the check only needs a non-empty match |
| ASMedia USB | the same vendor tarball | already extracted; hash recorded |
| AVD (`avd-fw-*.bin`, seven files) | the `avd-fw` package, Asahi's **open replacement**, not Apple's | nothing to extract; owned by the package, so a changed hash is reported as INFO, not FAIL (refresh the manifest after an `avd-fw` update) |
| AOP coprocessor image (ADT firmware name `k114saop`) | loaded by iBoot from macOS's own copy; Linux's `aop` driver talks to the running image | **no file exists to extract**; the ADT identity (build UUID, segment names) is recorded instead |
| PMP, SMC, MTP, DCP, SIO, ANS, ANE | iBoot-loaded; no Linux file | ADT identity recorded |
| GPU | from the GPU tree | not part of this inventory |

So the extraction gap is smaller than the issue said: the owner's earlier extraction already produced
the ISP and ALS calibration files. What was missing was the record and a check, which this PR adds.
The vendor tarball on the ESP (names and hashes of its 465 lines, Wi-Fi and Bluetooth included) is what
the `omarchy-vendor-firmware` unit unpacks; `vendor firmware unchanged` is that unit saying the tarball
is no newer than the last unpack.

## Tools

- `sudo build/k114s-adt.py firmware-report [--json]`: lists every ADT node that names a firmware image:
  firmware name, type, build UUID and segment names. Address ranges are left out (this boot's memory
  layout). Read only.
- `sudo python3 -I tests/hardware/k114s-firmware-check.py`: hashes the files under `/lib/firmware` and
  compares the ADT identities with the manifest. Exit 0 means all match.
- `python3 tests/test-firmware-check.py`: replica test with a made-up ADT and made-up bytes. It proves
  the comparisons, not a real machine.

Result on this Mac (agent-run, 2026-11-15): 17 files and 13 ADT identities, 0 failed.

## Findings

- The AOP firmware is a board image (`k114saop`) with a build UUID of its own (see
  `docs/r3-audio-kernel.md`). It cannot be extracted as a file; the question for audio is whether the
  `aop` driver's endpoint set matches this image, which needs the owner's sound trial, not extraction.
- Every boot logs `dockchannel-hid ... Direct firmware load for apple/tpmtfw-k114s.bin failed with
  error -2` about 0.9 s in, then the multi-touch interface comes up at about 1.4 s. The file is in the
  tarball and passes the hash check; the first attempt happens before the unpack. Worth a look in the
  initramfs ordering, not a missing file.
- The Linux stub stays 27.2 while macOS is 27.3. The recorded ADT UUIDs are those the boot chain
  handed over now; after a macOS update run the check again: a changed UUID there means the board
  images changed and the extraction should be redone from the matching restore image.

## Left for the owner

Nothing is needed to keep the current state. To refresh after macOS moves to 27.3: provide the 27.3
restore image (or run the extraction from macOS), then run the check above and send the output.
Camera work needs a camera node first (a separate issue), then the ISP file in use can be named.
