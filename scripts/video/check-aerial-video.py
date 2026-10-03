#!/usr/bin/env python3
"""Check that a .mov has the structure Apple's aerial engine needs.

Read-only. Usage: check-aerial-video.py VIDEO.mov
Exits 1 when a required property is missing. See scripts/video/README.md.
"""
import re
import struct
import sys


def find_moov(f):
    f.seek(0, 2)
    end = f.tell()
    offset = 0
    while offset + 8 <= end:
        f.seek(offset)
        size, kind = struct.unpack(">I4s", f.read(8))
        header = 8
        if size == 1:
            size = struct.unpack(">Q", f.read(8))[0]
            header = 16
        elif size == 0:
            size = end - offset
        if size < header:
            break
        if kind == b"moov":
            return f.read(size - header)
        offset += size
    return None


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__.strip())
    with open(sys.argv[1], "rb") as f:
        moov = find_moov(f)
    if moov is None:
        raise SystemExit("no moov box: not a QuickTime/MP4 file")

    results = []

    def check(label, ok, detail=""):
        results.append(ok)
        print(f"{'ok  ' if ok else 'FAIL'} {label}{': ' + detail if detail else ''}")

    check("HEVC sample entry tagged hvc1", b"hvc1" in moov,
          "hev1 found instead" if b"hev1" in moov else "")

    tscl = re.search(rb"sgpd(.)\x00\x00\x00tscl", moov, re.S)
    layers = 0
    if tscl:
        body = tscl.end()
        version = tscl.group(1)[0]
        count_at = body + 4 if version == 1 else body
        layers = struct.unpack(">I", moov[count_at:count_at + 4])[0]
    check("tscl temporal-layer description", layers >= 2, f"{layers} layer(s)")
    check("tscl sample mapping", re.search(rb"(csgm|sbgp)....tscl", moov, re.S) is not None)
    check("tsas sub-layer access group", re.search(rb"(sgpd|csgm|sbgp)....tsas", moov, re.S) is not None)
    check("no audio track", re.search(rb"hdlr.{8}soun", moov, re.S) is None)

    mvhd = moov.find(b"mvhd")
    stss = moov.find(b"stss")
    if mvhd >= 0 and stss >= 0:
        body = mvhd + 4
        if moov[body] == 1:
            timescale, duration = struct.unpack(">IQ", moov[body + 20:body + 32])
        else:
            timescale, duration = struct.unpack(">II", moov[body + 12:body + 20])
        seconds = duration / timescale
        keyframes = struct.unpack(">I", moov[stss + 8:stss + 12])[0]
        interval = seconds / keyframes if keyframes else seconds
        print(f"info {seconds:.1f} s, {keyframes} key frame(s), one every {interval:.1f} s (Apple: 5 s)")

    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
