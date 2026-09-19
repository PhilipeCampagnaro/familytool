"""Render corpus PDFs to PNG for labelling: python3 render.py [<id> ...]   (default: label_set.json)

Each page becomes out/png/<id>/p<n>.png (whole page, 90 dpi, for orientation) and
out/png/<id>/p<n>-<row><col>.png, a 3×2 grid of tiles at 220 dpi with a little overlap: a day
cell in a year grid is a few points tall, and a labeller reading it at page scale guesses.
Needs pymupdf.
"""
import json
import os
import sys

import fitz

HERE = os.path.dirname(os.path.abspath(__file__))
ids = sys.argv[1:] or [x["id"] for x in json.load(open(os.path.join(HERE, "label_set.json")))]
for pid in ids:
    out = os.path.join(HERE, "out", "png", pid)
    os.makedirs(out, exist_ok=True)
    doc = fitz.open(os.path.join(HERE, "corpus", pid + ".pdf"))
    for n, page in enumerate(doc, 1):
        if n > 16:
            break
        r = page.rect
        page.get_pixmap(dpi=90).save(f"{out}/p{n}.png")
        rows, cols = (3, 2) if r.height >= r.width else (2, 3)
        tw, th = r.width / cols, r.height / rows
        pad = 12
        for i in range(rows):
            for j in range(cols):
                clip = fitz.Rect(r.x0 + j * tw - pad, r.y0 + i * th - pad, r.x0 + (j + 1) * tw + pad, r.y0 + (i + 1) * th + pad) & r
                page.get_pixmap(dpi=220, clip=clip).save(f"{out}/p{n}-{'abc'[i]}{j + 1}.png")
    print(pid, len(doc), file=sys.stderr)
