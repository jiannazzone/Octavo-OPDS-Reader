#!/usr/bin/env python3
"""Prints what kind of Kindle file each argument is (formats spike).

    python3 -I mobi-info.py FILE...

For each file: the PalmDB type, the MOBI header version, text encoding and
compression, and whether it is MOBI 6 only, KF8 only, or joint (MOBI 6 plus a
KF8 part after EXTH record 121, which foliate's mobi.js reads in place of the
MOBI 6 part). Also the EXTH title, author and cover offset. Reads the files
as untrusted bytes; nothing is executed.
"""
import struct
import sys

COMPRESSION = {1: 'none', 2: 'PalmDOC', 17480: 'HUFF/CDIC'}
ENCODING = {1252: 'cp1252', 65001: 'utf-8'}


def u16(b, o): return struct.unpack_from('>H', b, o)[0]
def u32(b, o): return struct.unpack_from('>I', b, o)[0]


def records(data):
    count = u16(data, 76)
    offsets = [u32(data, 78 + 8 * i) for i in range(count)] + [len(data)]
    return [data[offsets[i]:offsets[i + 1]] for i in range(count)]


def header(rec):
    """PalmDOC + MOBI header of a record 0 (or the KF8 boundary's record)."""
    if rec[16:20] != b'MOBI':
        return None
    length = u32(rec, 20)
    h = {
        'compression': COMPRESSION.get(u16(rec, 0), u16(rec, 0)),
        'textRecords': u16(rec, 8),
        'encryption': u16(rec, 12),
        'encoding': ENCODING.get(u32(rec, 28), u32(rec, 28)),
        'version': u32(rec, 36),
        'exth': {},
    }
    if u32(rec, 128) & 0x40:
        o = 16 + length
        if rec[o:o + 4] == b'EXTH':
            n = u32(rec, o + 8)
            p = o + 12
            for _ in range(n):
                kind, size = u32(rec, p), u32(rec, p + 4)
                h['exth'].setdefault(kind, []).append(rec[p + 8:p + size])
                p += size
    return h


def text(values):
    return values[0].decode('utf-8', 'replace') if values else None


def number(values):
    return u32(values[0], 0) if values and len(values[0]) == 4 else None


def main():
    for path in sys.argv[1:]:
        data = open(path, 'rb').read()
        kind = data[60:68].decode('latin-1')
        if kind != 'BOOKMOBI':
            print(f'{path}: not a MOBI ({kind!r})')
            continue
        recs = records(data)
        h0 = header(recs[0])
        boundary = number(h0['exth'].get(121))
        kf8 = header(recs[boundary]) if boundary is not None and boundary < len(recs) else None
        if h0['version'] >= 8:
            layout = 'KF8 only'
        elif kf8:
            layout = f'joint (MOBI {h0["version"]} + KF8 v{kf8["version"]} at record {boundary})'
        else:
            layout = f'MOBI {h0["version"]} only'
        e = h0['exth']
        print(f'{path}: {layout}; {len(recs)} records; {h0["textRecords"]} text records, '
              f'{h0["compression"]}, {h0["encoding"]}, encryption {h0["encryption"]}; '
              f'title {text(e.get(503))!r}; author {text(e.get(100))!r}; '
              f'cover offset {number(e.get(201))}; creator {text(e.get(108))!r}')


if __name__ == '__main__':
    main()
