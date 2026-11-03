# sheet.py <frames dir> <out.png> [columns]: a contact sheet of the frames
# where the picture changes, each labelled with its time, 30 fps.
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw

frames, out = sys.argv[1], sys.argv[2]
columns = int(sys.argv[3]) if len(sys.argv) > 3 else 8
files = sorted(f for f in os.listdir(frames) if f.endswith('.png'))
grey = [Image.open(os.path.join(frames, f)).convert('L') for f in files]
change = [0] + [float(np.asarray(ImageChops.difference(a, b)).mean()) for a, b in zip(grey, grey[1:])]
moving = [i for i, x in enumerate(change) if x > 0.3]
if not moving:
    sys.exit('no change')
first, last = max(0, moving[0] - 1), min(len(files) - 1, moving[-1] + 1)
print(f'changes from {moving[0] / 30:.2f} s to {moving[-1] / 30:.2f} s')
width, height = grey[0].size
picks = list(range(first, last + 1))
rows = (len(picks) + columns - 1) // columns
sheet = Image.new('RGB', (columns * (width + 6), rows * (height + 22)), 'white')
draw = ImageDraw.Draw(sheet)
for k, i in enumerate(picks):
    x, y = (k % columns) * (width + 6), (k // columns) * (height + 22)
    sheet.paste(Image.open(os.path.join(frames, files[i])).convert('RGB'), (x, y + 20))
    draw.text((x + 2, y + 4), f'{(i - first) * 33} ms', fill='black')
sheet.save(out)
