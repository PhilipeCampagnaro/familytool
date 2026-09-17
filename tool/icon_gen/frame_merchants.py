#!/usr/bin/env python3
"""Re-frame assets/merchants/ so every logo can be drawn edge to edge in a
circle without losing a letter.

`BrandMark` draws a shop mark at the full diameter of its disc and clips it
round, which is what makes a badge logo read as the shop's own mark rather than
as a sticker floating on a white circle. A circle keeps only 79% of the square
it is inscribed in, though, so any ink in the corners is ink the clip eats:
drawn that way straight from the download, ALDI NORD loses the ends of its
wordmark and AliExpress two fifths of its logotype.

This pass makes the artwork safe for that clip, and it is the *asset* that is
fixed rather than the widget, for the same reason normalize.py exists: the
alternative is a hand-kept table of per-logo insets in Dart, and a logo dropped
into the folder would miss it.

Two kinds of file, told apart by what is along their edges:

  * A **badge** — REWE's red square, Lidl's blue one — has a flat colour at its
    sides. Its colour is extended to fill the whole frame (rounded corners
    included, which is why the corners are not what decides) and its logotype is
    scaled to fit the inscribed circle. Drawn round, the badge colour reaches
    the disc's edge and nothing is cropped.
  * A mark on **transparency** — a wordmark, a monogram — has no edge to bleed,
    so it is only re-scaled: its bounding box is fitted to the circle rather
    than to the square, which makes a wide wordmark like OTTO's noticeably
    bigger than the inscribed-square fit it had before.

A logo with a gradient or a pattern at its edges is left to fit inside the
circle untouched — there is no flat colour to extend, and inventing one would
put a seam across the mark.

    python3 tool/icon_gen/frame_merchants.py --report    # measure, change nothing
    python3 tool/icon_gen/frame_merchants.py --preview   # before/after contact sheet
    python3 tool/icon_gen/frame_merchants.py --apply     # rewrite assets/merchants/

Needs Pillow (`pip3 install Pillow`).
"""
import argparse, math, os, sys
from collections import Counter
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ASSETS = os.path.join(ROOT, 'assets', 'merchants')
PREVIEW = os.path.join(HERE, 'merchant_preview')

ALPHA_CUTOFF = 24       # below this a pixel is background, not ink
COLOUR_TOL = 20         # per-channel distance that still counts as "the badge colour"
EDGE_BAND = 0.03        # how much of each side is sampled to read the edge
EDGE_SPAN = 0.6         # the middle of each side, so rounded corners don't vote
EDGE_SHARE = 0.90       # how much of that sample has to agree
SAFETY = 0.98           # a hair of air between the artwork and the clip


def edge_pixels(im):
    """The middle stretch of all four sides — the part a rounded corner or a
    drop shadow doesn't reach."""
    w, h = im.size
    band_x, band_y = max(1, int(w * EDGE_BAND)), max(1, int(h * EDGE_BAND))
    lo_x, hi_x = int(w * (1 - EDGE_SPAN) / 2), int(w * (1 + EDGE_SPAN) / 2)
    lo_y, hi_y = int(h * (1 - EDGE_SPAN) / 2), int(h * (1 + EDGE_SPAN) / 2)
    px = im.load()
    out = []
    for x in range(lo_x, hi_x):
        out.append(px[x, 0]); out.append(px[x, h - 1])
        for y in range(band_y):
            out.append(px[x, y]); out.append(px[x, h - 1 - y])
    for y in range(lo_y, hi_y):
        out.append(px[0, y]); out.append(px[w - 1, y])
        for x in range(band_x):
            out.append(px[x, y]); out.append(px[w - 1 - x, y])
    return out


def classify(im):
    """('badge', (r, g, b)) | ('bare', None) | ('complex', None)."""
    sample = edge_pixels(im)
    if not sample:
        return 'complex', None
    clear = sum(1 for p in sample if p[3] < ALPHA_CUTOFF)
    if clear >= len(sample) * EDGE_SHARE:
        return 'bare', None
    opaque = [p for p in sample if p[3] >= ALPHA_CUTOFF]
    modal = Counter((p[0] // 8, p[1] // 8, p[2] // 8) for p in opaque).most_common(1)[0][0]
    near = [p for p in opaque if all(abs(p[i] - (modal[i] * 8 + 4)) <= COLOUR_TOL for i in range(3))]
    if len(near) < len(sample) * EDGE_SHARE:
        return 'complex', None
    mean = tuple(round(sum(p[i] for p in near) / len(near)) for i in range(3))
    return 'badge', mean


def content_box(im, kind, colour):
    """The bounding box of what the logo actually says — the logotype on a
    badge, the whole mark on transparency."""
    if kind == 'badge':
        r, g, b = colour
        bands = im.split()
        mask = Image.new('L', im.size, 0)
        mp, ap = mask.load(), im.load()
        w, h = im.size
        for y in range(h):
            for x in range(w):
                pr, pg, pb, pa = ap[x, y]
                if pa < ALPHA_CUTOFF:
                    continue            # a rounded corner is the badge too
                if abs(pr - r) <= COLOUR_TOL and abs(pg - g) <= COLOUR_TOL and abs(pb - b) <= COLOUR_TOL:
                    continue
                mp[x, y] = 255
        del bands
        return mask.getbbox()
    return im.getchannel('A').point(lambda a: 255 if a > ALPHA_CUTOFF else 0).getbbox()


def reframe(im):
    """The logo re-framed for a circular clip, plus what was done to it."""
    im = im.convert('RGBA')
    kind, colour = classify(im)
    box = content_box(im, kind, colour)
    if box is None:
        return im, kind, 1.0
    size = max(im.size)
    cw, ch = box[2] - box[0], box[3] - box[1]
    diagonal = math.hypot(cw, ch)
    if kind == 'complex':
        # Nothing to bleed: fit the whole frame inside the circle and leave the
        # art alone.
        scale = size * SAFETY / math.hypot(*im.size)
        out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        art = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.LANCZOS)
        out.paste(art, ((size - art.width) // 2, (size - art.height) // 2), art)
        return out, kind, scale
    scale = size * SAFETY / diagonal
    art = im.crop(box)
    art = art.resize((max(1, round(cw * scale)), max(1, round(ch * scale))), Image.LANCZOS)
    ground = (*colour, 255) if kind == 'badge' else (0, 0, 0, 0)
    out = Image.new('RGBA', (size, size), ground)
    out.paste(art, ((size - art.width) // 2, (size - art.height) // 2), art)
    return out, kind, scale


def files():
    return sorted(f for f in os.listdir(ASSETS) if f.lower().endswith('.png'))


def disc(im, px, full):
    """The mark as the app draws it: a white disc with a hairline, the artwork
    at [full] of the diameter, clipped round."""
    tile = Image.new('RGBA', (px, px), (0, 0, 0, 0))
    ImageDraw.Draw(tile).ellipse((0, 0, px - 1, px - 1), fill=(255, 255, 255, 255), outline=(228, 228, 232, 255))
    art = im.convert('RGBA').copy()
    art.thumbnail((round(px * full), round(px * full)), Image.LANCZOS)
    tile.alpha_composite(art, ((px - art.width) // 2, (px - art.height) // 2))
    mask = Image.new('L', (px, px), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, px - 1, px - 1), fill=255)
    tile.putalpha(mask)
    card = Image.new('RGBA', (px, px), (255, 255, 255, 255))
    card.alpha_composite(tile)
    return card


def preview(names, columns=8, px=96):
    os.makedirs(PREVIEW, exist_ok=True)
    pad, rows = 10, math.ceil(len(names) / columns)
    sheet = Image.new('RGBA', (columns * (px + pad) + pad, rows * (2 * px + 3 * pad) + pad), (243, 243, 246, 255))
    for i, name in enumerate(names):
        im = Image.open(os.path.join(ASSETS, name))
        after, kind, _ = reframe(im)
        col, row = i % columns, i // columns
        x = pad + col * (px + pad)
        y = pad + row * (2 * px + 3 * pad)
        sheet.alpha_composite(disc(im, px, 0.68), (x, y))            # today
        sheet.alpha_composite(disc(after, px, 1.0), (x, y + px + pad))  # proposed
    out = os.path.join(PREVIEW, 'sheet.png')
    sheet.convert('RGB').save(out)
    print(f'wrote {out} — top row as drawn today, bottom row as this pass would draw it')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--report', action='store_true')
    ap.add_argument('--preview', action='store_true')
    ap.add_argument('--apply', action='store_true')
    ap.add_argument('--only', nargs='*', help='file names, for a preview of a few')
    args = ap.parse_args()
    names = args.only or files()
    if args.preview:
        preview(names)
        return
    kinds = Counter()
    for name in names:
        im = Image.open(os.path.join(ASSETS, name))
        out, kind, scale = reframe(im)
        kinds[kind] += 1
        if args.report:
            print(f'{name:44s} {kind:8s} ×{scale:.2f}')
        if args.apply:
            out.save(os.path.join(ASSETS, name))
    print(dict(kinds), f'({len(names)} files)')


if __name__ == '__main__':
    sys.exit(main())
