#!/usr/bin/env python3
"""The contrast of what's in a rect of a screenshot, read from its pixels.

contrast.py <png> <screen width in points> <x> <y> <w> <h>

The background is the rect's median brightness, and the text is whichever of its
1st and 99th percentiles is further from that. Needs Pillow and NumPy.
"""
import sys

import numpy as np
from PIL import Image

path, points = sys.argv[1], float(sys.argv[2])
x, y, w, h = map(float, sys.argv[3:7])
image = np.asarray(Image.open(path).convert("RGB"), dtype=np.float64) / 255
linear = np.where(image <= 0.04045, image / 12.92, ((image + 0.055) / 1.055) ** 2.4)
brightness = linear @ np.array([0.2126, 0.7152, 0.0722])
scale = image.shape[1] / points
crop = brightness[int(y * scale):int((y + h) * scale), int(x * scale):int((x + w) * scale)]
background = np.median(crop)
low, high = np.percentile(crop, 1), np.percentile(crop, 99)
text = low if abs(background - low) > abs(high - background) else high
print(f"{(max(background, text) + 0.05) / (min(background, text) + 0.05):.2f}:1")
