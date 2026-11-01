#!/usr/bin/env python3
"""sheet.py <in.mov> <out.png> <inner|outer> [cols] [start] [end]: a contact sheet of a
recording's distinct frames (ffmpeg mpdecimate), each labelled with its time. Needs ffmpeg and Pillow."""
import subprocess, sys, os, re, tempfile, glob
from PIL import Image, ImageDraw, ImageFont
src, out, kind = sys.argv[1:4]
cols = int(sys.argv[4]) if len(sys.argv) > 4 else 5
start = float(sys.argv[5]) if len(sys.argv) > 5 else 0
end = float(sys.argv[6]) if len(sys.argv) > 6 else 1e9
rot = "transpose=1," if kind == "inner" else "transpose=2,"
W = int(os.environ.get("W", "380"))
tmp = tempfile.mkdtemp()
log = subprocess.run(["ffmpeg", "-v", "info", "-y", "-i", src, "-fps_mode", "passthrough", "-vf",
    f"{rot}scale={W}:-1,mpdecimate=hi=64*12:lo=64*5:frac=0.05,showinfo", f"{tmp}/f%04d.png"], capture_output=True, text=True).stderr
times = [float(m) for m in re.findall(r"pts_time:([\d.]+)", log)]
files = sorted(glob.glob(f"{tmp}/f*.png"))
pairs = [(t, f) for t, f in zip(times, files) if start <= t <= end]
if not pairs: sys.exit("no frames")
ims = [Image.open(f) for _, f in pairs]
w, h = ims[0].size
rows = (len(ims) + cols - 1) // cols
sheet = Image.new("RGB", (cols * (w + 6) + 6, rows * (h + 6) + 6), "gray")
font = ImageFont.load_default(size=22)
for i, ((t, _), im) in enumerate(zip(pairs, ims)):
    x, y = 6 + (i % cols) * (w + 6), 6 + (i // cols) * (h + 6)
    sheet.paste(im, (x, y))
    d = ImageDraw.Draw(sheet)
    d.rectangle([x, y, x + 92, y + 28], fill="red")
    d.text((x + 6, y + 2), f"{t:.3f}s", fill="white", font=font)
sheet.save(out)
print(len(ims), "frames", sheet.size)
