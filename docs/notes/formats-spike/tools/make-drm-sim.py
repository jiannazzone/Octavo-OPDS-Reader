#!/usr/bin/env python3
"""Makes a stand-in for a DRM-protected MOBI (formats spike).

    python3 -I make-drm-sim.py IN.mobi OUT.mobi

Sets record 0's encryption field to 2 (Mobipocket DRM) and scrambles the
text records, as real DRM leaves them. Not real DRM: only for checking what
the reader does with such a file (foliate opens it without an error).
"""
import struct
import sys

data = bytearray(open(sys.argv[1], 'rb').read())
count = struct.unpack_from('>H', data, 76)[0]
offsets = [struct.unpack_from('>I', data, 78 + 8 * i)[0] for i in range(count)] + [len(data)]
struct.pack_into('>H', data, offsets[0] + 12, 2)
for i in range(1, struct.unpack_from('>H', data, offsets[0] + 8)[0] + 1):
    for j in range(offsets[i], offsets[i + 1]):
        data[j] ^= 0x5A
open(sys.argv[2], 'wb').write(data)
