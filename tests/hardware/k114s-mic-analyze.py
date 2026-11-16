#!/usr/bin/env python3
"""Per-channel analysis of a K114s microphone recording (WAV, 16/24/32-bit PCM or 32-bit float).
  k114s-mic-analyze.py FILE [--expect-channels N] [--silent-dbfs -70] [--self-test]
Prints, per channel: peak and RMS in dBFS, DC offset, clipping count, and, for a multichannel file,
the correlation with channel 0 and whether the channel is silent. Verdict lines: ok / BAD / info.
Exit 0 when every channel carries signal, 1 when a channel is silent or clips, 2 on bad input."""
import math, struct, sys, argparse, tempfile, os, random, io, contextlib


def read_wav(path):
    d = open(path, "rb").read()
    if d[:4] != b"RIFF" or d[8:12] != b"WAVE":
        raise ValueError("not a RIFF/WAVE file")
    pos, fmt, data = 12, None, None
    while pos + 8 <= len(d):
        cid, sz = d[pos:pos + 4], struct.unpack("<I", d[pos + 4:pos + 8])[0]
        body = d[pos + 8:pos + 8 + sz]
        if cid == b"fmt ":
            tag, ch, rate, _, _, bits = struct.unpack("<HHIIHH", body[:16])
            if tag == 0xFFFE and len(body) >= 26:
                tag = struct.unpack("<H", body[24:26])[0]
            fmt = (tag, ch, rate, bits)
        elif cid == b"data":
            data = body if sz != 0xFFFFFFFF else d[pos + 8:]
        pos += 8 + sz + (sz & 1)
    if not fmt or data is None:
        raise ValueError("missing fmt or data chunk")
    tag, ch, rate, bits = fmt
    if ch < 1:
        raise ValueError("no channels")
    if tag == 3 and bits == 32:
        n = len(data) // 4
        s = struct.unpack("<%df" % n, data[:n * 4])
    elif tag == 1 and bits == 16:
        n = len(data) // 2
        s = [x / 32768.0 for x in struct.unpack("<%dh" % n, data[:n * 2])]
    elif tag == 1 and bits == 32:
        n = len(data) // 4
        s = [x / 2147483648.0 for x in struct.unpack("<%di" % n, data[:n * 4])]
    elif tag == 1 and bits == 24:
        n = len(data) // 3
        s = [int.from_bytes(data[i * 3:i * 3 + 3], "little", signed=True) / 8388608.0 for i in range(n)]
    else:
        raise ValueError("unsupported format tag %d, %d bits" % (tag, bits))
    frames = len(s) // ch
    return ch, rate, [s[c:frames * ch:ch] for c in range(ch)]


def db(x):
    return -200.0 if x <= 0 else 20 * math.log10(x)


def analyze(path, expect=None, silent=-70.0):
    ch, rate, chans = read_wav(path)
    n = len(chans[0])
    print("info    %s: %d channel(s), %d Hz, %.2f s" % (os.path.basename(path), ch, rate, n / rate if rate else 0))
    bad = 0
    if expect is not None and ch != expect:
        print("BAD     expected %d channels, file has %d" % (expect, ch))
        bad = 1
    if n == 0:
        print("BAD     no samples")
        return 1
    stats = []
    for i, x in enumerate(chans):
        pk = max(abs(v) for v in x)
        mean = sum(x) / n
        rms = math.sqrt(sum(v * v for v in x) / n)
        clip = sum(1 for v in x if abs(v) >= 0.999)
        stats.append((rms, x, mean))
        line = "ch%d  peak %7.1f dBFS  rms %7.1f dBFS  dc %+.5f  clipped %d" % (i, db(pk), db(rms), mean, clip)
        if db(rms) < silent:
            print("BAD     %s  (silent: below %.0f dBFS)" % (line, silent))
            bad = 1
        elif clip:
            print("BAD     %s  (clips: lower the gain)" % line)
            bad = 1
        else:
            print("ok      %s" % line)
    if ch > 1:
        r0, x0, m0 = stats[0]
        same = True
        for i in range(1, ch):
            ri, xi, mi = stats[i]
            v0 = sum((a - m0) ** 2 for a in x0) / n
            vi = sum((b - mi) ** 2 for b in xi) / n
            if v0 <= 0 or vi <= 0:
                continue
            c = sum((a - m0) * (b - mi) for a, b in zip(x0, xi)) / n
            corr = c / math.sqrt(v0 * vi)
            print("info    corr(ch0,ch%d) = %+.2f   level difference %+.1f dB" % (i, corr, db(ri) - db(r0)))
            same = same and abs(corr) >= 0.999 and abs(db(ri) - db(r0)) < 0.1
        if same:
            print("BAD     channels identical: upmixed or fallback source, not separate microphones")
            bad = 1
        rm = [r for r, _, _ in stats]
        if min(rm) > 0 and db(max(rm)) - db(min(rm)) > 12:
            print("info    channels differ by more than 12 dB: a blocked port or a gain error; report which one")
    return bad


def write_wav(path, chans, rate=48000):
    ch, n = len(chans), len(chans[0])
    inter = [chans[c][i] for i in range(n) for c in range(ch)]
    data = struct.pack("<%df" % len(inter), *inter)
    hdr = b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVEfmt " + struct.pack("<IHHIIHH", 16, 3, ch, rate, rate * ch * 4, ch * 4, 32)
    open(path, "wb").write(hdr + b"data" + struct.pack("<I", len(data)) + data)


def self_test():
    d = tempfile.mkdtemp()
    fails = 0

    def chk(name, cond):
        nonlocal fails
        print(("ok   " if cond else "FAIL ") + name)
        fails += 0 if cond else 1

    def run(path, **k):
        b = io.StringIO()
        with contextlib.redirect_stdout(b):
            r = analyze(path, **k)
        return r, b.getvalue()

    rnd = random.Random(1)
    n = 48000
    tone = [0.2 * math.sin(2 * math.pi * 440 * i / 48000) for i in range(n)]
    noise = [0.05 * rnd.uniform(-1, 1) for _ in range(n)]
    p = os.path.join(d, "good.wav")
    write_wav(p, [tone, [v * 0.5 for v in tone], noise])
    r, o = run(p, expect=3)
    chk("three live channels pass", r == 0 and "corr(ch0,ch1) = +1.00" in o)
    r, o = run(p, expect=1)
    chk("a wrong channel count is BAD", r == 1)
    p5 = os.path.join(d, "same.wav")
    write_wav(p5, [tone, tone, tone])
    r, o = run(p5, expect=3)
    chk("identical channels (upmixed mono) are BAD", r == 1 and "channels identical" in o)
    p2 = os.path.join(d, "silent.wav")
    write_wav(p2, [tone, [0.0] * n, noise])
    r, o = run(p2, expect=3)
    chk("a silent channel is BAD and named", r == 1 and "BAD     ch1" in o)
    p3 = os.path.join(d, "clip.wav")
    write_wav(p3, [[1.0 if i % 2 else -1.0 for i in range(n)]])
    r, o = run(p3)
    chk("a clipping channel is BAD", r == 1 and "clips" in o)
    p4 = os.path.join(d, "bad.wav")
    open(p4, "wb").write(b"nope")
    try:
        read_wav(p4)
        chk("a non-WAV file is refused", False)
    except ValueError:
        chk("a non-WAV file is refused", True)
    return 1 if fails else 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("file", nargs="?")
    ap.add_argument("--expect-channels", type=int)
    ap.add_argument("--silent-dbfs", type=float, default=-70.0)
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        sys.exit(self_test())
    if not a.file:
        ap.error("a file or --self-test")
    try:
        sys.exit(analyze(a.file, a.expect_channels, a.silent_dbfs))
    except (OSError, ValueError) as e:
        print("BAD     %s" % e)
        sys.exit(2)
