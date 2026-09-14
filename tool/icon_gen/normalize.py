#!/usr/bin/env python3
"""Re-frame assets/grocery/ so every icon's subject fills the same share of its
square, which is what actually decides how big it looks in a list row.

IconImage draws with BoxFit.contain, so the *image's own* margin is rendered
margin: an icon whose subject fills 47% of its frame (Hygiene_Tampons) comes
out half the size of one that fills 85% (Baking_Supplies_Eggs), even though
both are 512px and both are sharp. That reads as "low quality", but resolution
has nothing to do with it — the 200px and 512px icons have an identical median
fill of 83%.

This crops each icon to its content and re-pads it to a fixed fill, leaving
resolution alone. The contact shadow is part of the content and stays.

    python3 tool/icon_gen/normalize.py --report        # measure, change nothing
    python3 tool/icon_gen/normalize.py --preview       # worst offenders, before/after
    python3 tool/icon_gen/normalize.py --apply         # rewrite assets/grocery/

Needs Pillow (`pip3 install Pillow`). Python rather than Dart because the repo
has no Dart image library and this is a one-off asset pass; adding a pubspec
dependency for it would cost more than it saves.
"""
import argparse, os, statistics, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ASSETS = os.path.join(ROOT, 'assets', 'grocery')
TARGET_FILL = 0.86      # a touch fuller than today's 83% median
WHITE_CUTOFF = 244      # anything darker than this counts as content
ALPHA_CUTOFF = 12


def content_box(im):
    """Bounding box of the subject, shadow included."""
    if im.mode in ('RGBA', 'LA') and im.getchannel('A').getextrema()[0] < 250:
        mask = im.getchannel('A').point(lambda a: 255 if a > ALPHA_CUTOFF else 0)
    else:
        mask = im.convert('L').point(lambda p: 255 if p < WHITE_CUTOFF else 0)
    return mask.getbbox()


def fill_of(im, box):
    w, h = im.size
    return max((box[2] - box[0]) / w, (box[3] - box[1]) / h)


def reframe(im):
    """Crop to content, re-pad square so the long side is TARGET_FILL of it."""
    box = content_box(im)
    if not box:
        return None
    sub = im.crop(box)
    sw, sh = sub.size
    side = int(round(max(sw, sh) / TARGET_FILL))
    has_alpha = im.mode in ('RGBA', 'LA')
    canvas = Image.new('RGBA' if has_alpha else 'RGB', (side, side),
                       (0, 0, 0, 0) if has_alpha else (255, 255, 255))
    canvas.paste(sub, ((side - sw) // 2, (side - sh) // 2),
                 sub if has_alpha else None)
    # Back to the source's own pixel size — never upscale a 200px icon.
    return canvas.resize(im.size, Image.LANCZOS)


def each():
    for f in sorted(os.listdir(ASSETS)):
        if f.endswith('.png'):
            yield f


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument('--report', action='store_true')
    g.add_argument('--preview', action='store_true')
    g.add_argument('--apply', action='store_true')
    ap.add_argument('--worst', type=int, default=24)
    a = ap.parse_args()

    rows = []
    for f in each():
        im = Image.open(os.path.join(ASSETS, f))
        box = content_box(im)
        if box:
            rows.append((fill_of(im, box), im.size[0], f))
    rows.sort()
    vals = [r for r, _, _ in rows]

    if a.report:
        print(f"{len(rows)} icons — subject fill of frame")
        print(f"  median {statistics.median(vals):.0%}   mean {statistics.mean(vals):.0%}")
        print(f"  under 70%: {sum(1 for v in vals if v < .70)}"
              f"   under 55%: {sum(1 for v in vals if v < .55)}")
        print(f"\nworst {a.worst}:")
        for r, px, f in rows[:a.worst]:
            print(f"  {r:5.0%}  {px}px  {f[:-4]}")
        return

    if a.preview:
        out = os.path.join(HERE, 'reframe_preview')
        os.makedirs(out, exist_ok=True)
        for r, px, f in rows[:a.worst]:
            im = Image.open(os.path.join(ASSETS, f))
            new = reframe(im)
            if new is None:
                continue
            pair = Image.new('RGB', (px * 2 + 24, px), (235, 235, 240))
            pair.paste(im.convert('RGB'), (0, 0))
            pair.paste(new.convert('RGB'), (px + 24, 0))
            pair.save(os.path.join(out, f))
        print(f"wrote {min(a.worst, len(rows))} before/after pairs to")
        print(f"  {os.path.relpath(out, ROOT)}   (left = now, right = re-framed)")
        return

    changed = 0
    for r, px, f in rows:
        if r >= TARGET_FILL - 0.02:
            continue
        p = os.path.join(ASSETS, f)
        new = reframe(Image.open(p))
        if new is not None:
            new.save(p)
            changed += 1
    print(f"re-framed {changed} icon(s) in assets/grocery/ to ~{TARGET_FILL:.0%} fill")


if __name__ == '__main__':
    sys.exit(main())
