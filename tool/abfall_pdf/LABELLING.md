# Labelling a bin calendar PDF — ground truth for the parser

You are writing down, by eye, what one printed waste calendar says. Your answer is the ground truth
the PDF parser is scored against, and a parser that disagrees with you will be treated as wrong.
**So only write a date you have actually read in the image, and say so when you cannot read one.**
A missing label costs little; a wrong label teaches the parser to be wrong.

You will not see the parser's output and must not run it. Do not read `supabase/functions/`.

## What you get

- `tool/abfall_pdf/out/png/<id>/p<n>.png`: the whole page, for orientation.
- `tool/abfall_pdf/out/png/<id>/p<n>-<row><col>.png`: the page cut into overlapping tiles at high
  resolution. **Read dates from the tiles**, not from the whole page.
- `tool/abfall_pdf/label_set.json`: the publisher and towns for each id.

If a tile is still too small to read, render a closer crop yourself:
`<venv python> -c "import fitz;p=fitz.open('tool/abfall_pdf/corpus/<id>.pdf')[<n-1>];p.get_pixmap(dpi=300,clip=fitz.Rect(x0,y0,x1,y1)).save('<scratch>.png')"`
Coordinates are PDF points, with the origin at the top left of the page (the whole page is
`fitz.open(...)[i].rect`).

## What to label

1. **Is it a bin calendar?** It must give pickup dates for household bins. If it is a sorting
   guide, a form, a street list without dates, or only covers something like Sperrmüll on request,
   set `"calendar": false` and stop.
2. **Which district.** Many calendars cover several districts, tours, zones or villages. Pick
   one household by this rule, so that two labellers pick the same one:
   - If the PDF is for one district only (its title or header says so), label that one.
   - Otherwise, **if the calendar has a street or village list, take its first entry** and use
     whatever district each bin has there. This matters: calendars often run a separate tour
     system per bin (Restmüll tour B, Gelber Sack tour 1), and the first street gives a real
     mixed household, which is exactly what a parser gets wrong.
   - With no street list, take the smallest number or earliest letter of each system.
   - Write the district in words (`"district": "Adalbert-Stifter-Platz: Rest B, Bio B, Papier 1, Gelb 1"`)
     and per bin which code you read (`"per_bin": {"rest": "B", "bio": "AB", "papier": "1", "gelb": "1"}`).
   - Say whether the bins share one district system: `"shared_districts": true` if one number
     or letter means the same district for every bin (the legend lists "Bezirk 3: streets…" once),
     `false` if bins have separate tour lists, `null` if the calendar does not say.
3. **The window.** Label **every pickup in January, February and March**, and **every pickup in
   September**, for the year the calendar is for. If the PDF covers only part of the year, label
   what it covers within those months and set `"covers"` to what it covers.
4. **Per bin.** The four household bins, `rest`, `bio`, `papier` and `gelb`, are what the parser
   is held to: label every one of their pickups. Label the others only when they are a
   **collection at the household's door on a fixed date** (a Sperrmüll day for the district, a
   Christbaum pickup). Drop-off events (Giftmobil stops, Häckselaktion, Wertstoffhof days) and
   anything on request only are **not** labelled; mention them in `notes`. Keys:
   - `rest`: Restmüll, Restabfall, graue/schwarze Tonne
   - `bio`: Bioabfall, Biotonne, braune Tonne
   - `papier`: Papier, Altpapier, PPK, blaue Tonne
   - `gelb`: Gelber Sack, Gelbe Tonne, LVP, Wertstofftonne, DSD, grüner Punkt
   - `glas`: glass
   - `gruen`: Grünschnitt, Gartenabfälle, Grüngut, Christbaum, Strauchgut
   - `sperr`: Sperrmüll
   - `schadstoff`: only if it comes to the door; a Giftmobil stop is a drop-off, not labelled
   Anything else (Wertstoffhof opening hours, Altkleider, street cleaning) is **not** labelled.
   If the calendar marks bins with colours or letters, write the legend as you read it in
   `"legend"`, for example `{"B (green box)": "bio", "R (grey box)": "rest"}`.
5. **Dates** are `YYYY-MM-DD`. A pickup moved by a holiday is labelled on the day it is printed on,
   not the usual day.

## Honesty fields

- `"unsure": ["2026-02-13 papier: cell partly hidden by a logo", …]`: list every date you are
  not certain of. Unsure dates are left out of the ground truth, not counted against the parser.
- `"unreadable": true` plus a `"reason"` if you cannot label the calendar at all (for example
  text too blurry, or no way to tell which district a mark belongs to). That is a valid answer.

## Output

Write exactly one JSON file to `tool/abfall_pdf/truth/raw/<id>.<labeller>.json`:

```json
{
  "id": "14b6545e582a",
  "labeller": "a",
  "calendar": true,
  "year": 2026,
  "covers": "2026-01-01..2026-12-31",
  "district": "Tour A + Tour 1",
  "per_bin": {"rest": "A", "bio": "AB", "papier": "1", "gelb": "1"},
  "shared_districts": false,
  "legend": {"grey box": "rest", "brown box": "bio", "yellow box": "gelb", "blue box": "papier"},
  "window": ["2026-01", "2026-02", "2026-03", "2026-09"],
  "bins": {
    "rest": ["2026-01-12", "…"],
    "bio": ["…"],
    "papier": [],
    "gelb": []
  },
  "unsure": [],
  "notes": "one line on anything odd about the layout"
}
```

An empty list means *this bin has no pickup for this district in the window*. Leave a bin out
entirely if the calendar does not cover that bin at all.
