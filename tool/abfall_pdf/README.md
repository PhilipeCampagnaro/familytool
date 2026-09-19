# Abfall PDF parser — corpus, ground truth and the regression run

> **Status: parked 2026-09-19. Built, not deployed.** `pdfUploadAvailable` stays `false`. What
> is left before shipping: colour legends (the largest refusal group) and a labelled set of about
> 40 or more PDFs with 0 wrong dates. There is also an open UX point: one district question per
> bin instead of up to 16 combined choices. Why parked: PDF-only is about 7% of unserved atlas
> towns, mostly small ones, and they still get their official page. Revisit if households in
> PDF-only towns ask for it, or a major publisher turns out to be PDF-only. The full record is
> the "PDF plans" item in docs/production-plan.md.

The parser lives in `supabase/functions/_shared/abfall/pdf/` and is reached through
`calendar-link` (`{action, provider: "ical", pdf, abfall_town, choice?}`). This directory is what
it is held to. **The bar before `pdfUploadAvailable` is switched on is zero wrong dates on the
four household bins (Rest, Bio, Papier, Gelb) wherever the parser answers.** Everything it cannot
read safely it refuses, with a reason.

```
python3 fetch_corpus.py        # atlas pdf_only pages → corpus/<sha>.pdf + manifest.json (needs requests, bs4)
node extract.mjs               # corpus → out/tokens/<id>.json (the same extract.ts the Edge Function runs)
node run.mjs                   # parse all, score against truth/, exit 1 on any wrong date
node run.mjs <id> …            # one PDF, with its choices and January pickups
```

After changing anything under `_shared/abfall/pdf/`, run `node run.mjs` and leave it at
`wrong dates (rest/bio/papier/gelb): 0`. `node extract.mjs` only needs re-running when `extract.ts`
changes (then delete `out/tokens/` first).

## Ground truth

- `label_set.json` (`node select_labels.mjs [per_publisher]`): the PDFs to label, one per
  publisher, including ones the parser does not read yet.
- `render.py` (needs pymupdf) renders them to `out/png/<id>/`: whole pages plus 220 dpi tiles.
- `LABELLING.md` is the brief for the labellers. Each PDF is labelled **twice, independently**,
  from the images only (never the text layer the parser reads), into `truth/raw/<id>.<a|b>.json`.
- `node merge_truth.mjs` keeps a date as truth only when both labellers have it and neither was
  unsure. Everything else goes to `excluded` and counts neither way. `truth/agreement.json` lists
  every dispute.
- `deno_smoke.ts` runs the upload path under Deno, the Edge runtime:
  `node_modules/.bin/deno run -A deno_smoke.ts corpus/<id>.pdf` (`npm i --no-save deno` first).

`corpus/`, `out/` and `node_modules/` are gitignored. The PDFs are the towns' documents, and
`manifest.json` records where each one came from.

## What the pilot showed (2026-09-19, 12 PDFs, one per layout family)

- The labellers (one Opus, one Sonnet) agreed on 369 of 373 dates. All 4 disagreements were extras
  (Grünschnitt, Schadstoff) that one labeller counted as pickups and the other did not.
- Parser: 4 of the 12 were read (2 exact; 2 with one extra missed each), and 8 were refused.
  **0 wrong dates.**
- Across one calendar per publisher (65 publishers), it reads 12. Refusals: colour-only
  legend 17, not a calendar or an unknown layout 11, unsupported layout 8, separate tours per
  bin 6, month not fully readable 6, weekday mismatch 4, no household bins 1.
- Three wrong-date traps turned up in development, and each is now a refusal or a fix:
  - **Bins with their own tour systems** (Datteln, Willingen, Gräfelfing). Each bin is treated as
    its own district system unless the calendar ties them together. Even the two labellers
    disagreed on whether Datteln has one system or four.
  - **Week numbers printed in Monday cells** (Hohenfels, Gaienhofen). These are stripped, not
    read as districts.
  - **Weekday cells misread as a legend** ("Mo Bio" taken as MO = Bio), and codes of bins the
    legend never defines (AH = Altholz). These are no longer read as bins or districts.
