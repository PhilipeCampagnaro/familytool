# Grocery icon generation

Fills the gaps in `assets/grocery/` in the style of the icons already there.

The set shipped as an American grocery catalogue with German labels bolted on:
75 vegetables including jicama and fiddlehead ferns, but no Birne, no Quark, no
Tee, no Kekse and no Pflaster. `manifest.json` is the 100 icons a German
household actually types that currently return nothing.

## Setup

The scripts read `GEMINI_API_KEY` from the environment, and fall back to a
`.env` at the repo root. **Neither is ever committed** — `.gitignore` refuses
`.env`, and `.env.example` is the committed template.

```sh
cp .env.example .env          # from the repo root
# then put the key in .env, or export it in your shell instead
```

Get a key at <https://aistudio.google.com/apikey>. Image generation needs
billing enabled on the project; it is not on the free tier.

## Use

```sh
dart run tool/icon_gen/generate.dart --dry-run     # what it would do, and cost
dart run tool/icon_gen/generate.dart --limit 3     # try three before the lot
open tool/icon_gen/out                             # look, delete the misses
dart run tool/icon_gen/generate.dart               # refills whatever you deleted
dart run tool/icon_gen/install.dart                # resize to 512, copy across
```

`install.dart` also writes `catalog_lines.txt` — the `GroceryIcon(...)` lines to
paste into `lib/data/grocery_catalog.dart`. That paste is the one manual step,
and it has to happen: an icon nobody has named in German is an icon nobody can
find. Afterwards:

```sh
flutter analyze
dart tool/check_const_palette.dart
```

## How it works

`gemini-3.1-flash-image`, one request per icon, three existing icons of the same
*kind* sent along as style references. The set is a consistent studio packshot —
pure white ground, soft key from upper left, faint contact shadow — and words
get close to that but not identical; the reference images close the gap. The
model keeps three dedicated style-reference slots, which is why it is this model
and not the cheaper `flash-lite`.

Generating at 1K and downsizing to 512 on install gives visibly cleaner edges
than generating at 512 directly. Roughly $0.067 an icon, so about $6.70 for the
manifest, and realistically $10–12 once regenerations are counted.

Standard mode, not the Batch API. Batch is half price but asynchronous with up
to 24h turnaround, and the total saving here is about three dollars — not worth
losing the look-fix-retry loop over.

## Conventions that matter

**The file name carries the English label.** `grocery_catalog.dart` derives it by
stripping the category's shared underscore-prefix (`sharedFilePrefix`), so a new
file must keep its category's prefix: a fruit is `Fruits_…`, a dairy item
`Dairy_…`. Only the German label is written by hand.

**Two categories mix prefixes** — Getränke and Tierbedarf — so their files find
no shared prefix to strip and need a line in `_englishLabelOverrides`.
`install.dart` emits those too.

**No text, no brands.** Every prompt forbids lettering and packaging design.
The existing set has AI-reproduced Coca-Cola, Kellogg's and Pepsi packshots in
it, one with garbled text on the box; reproducing trade dress in a shipping app
is a risk worth not adding to.
