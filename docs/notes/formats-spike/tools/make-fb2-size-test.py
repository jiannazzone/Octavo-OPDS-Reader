#!/usr/bin/env python3
"""Two synthetic FB2s for fb2.js's section-size bug (formats spike).

    python3 -I make-fb2-size-test.py OUT_DIR

Both have a 400 KB stand-in image (random bytes, base64 on one line) and the
same ten chapters. In `top-level-image.fb2` the image is a direct child of
<body>; in `image-in-section.fb2` it is inside a <section>. Open each with
probe.swift and section-sizes.js to see the first section's share of the book.
"""
import base64
import os
import sys

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
image = base64.b64encode(os.urandom(300000)).decode()
text = ''.join(f'<section><title><p>Chapter {i}</p></title>'
               + '<p>Ordinary running text for the size check.</p>' * 200 + '</section>' for i in range(10))
for name, body in [('top-level-image', f'<image l:href="#c"/>{text}'),
                   ('image-in-section', f'<section><image l:href="#c"/></section>{text}')]:
    with open(os.path.join(out, f'{name}.fb2'), 'w') as f:
        f.write(f'''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
<description><title-info><book-title>{name}</book-title><lang>en</lang></title-info></description>
<body>{body}</body>
<binary id="c" content-type="image/png">{image}</binary>
</FictionBook>''')
