# Abfall authorities — the official calendar page for every town

The census in `../abfall_census/` counts what the app can connect by address. This directory is
for everything else: for each German municipality, the official page where a resident gets their
bin calendar, so an unserved town gets the in-app page browser and upload instead of "Anfragen".

- `gv.xlsx` — Destatis Gemeindeverzeichnis (AuszugGV2QAktuell, Gebietsstand 30.06.2026).
- `build_register.py` → `register.json`: 401 Kreise, 10,940 Gemeinden, with official key (ARS),
  population and postcode. The first five digits of an ARS are its Kreis.
  Needs `openpyxl` (a venv is enough).
- `pilot_nrw_batches.json` — the 153 NRW towns no provider serves, packed by county into eight
  batches, one research agent each.

Official sources only: a page counts if it is on the authority's own domain, or on a calendar
vendor the authority's own site links to as its calendar.

## From atlas to provider rows

A county whose own page embeds a vendor the registry already reads becomes one provider row.

```
python3 find_configs.py <atlas.html>     # → vendor_configs.json: keys, hosts, clients found on each page
python3 build_candidates.py              # → candidates.json: configs not in abfall_providers.ts yet
deno run -A probe_candidates.ts [ids]    # → candidate_probe.json: towns + one address read per candidate
python3 gate_candidates.py               # → candidate_gate.json: robots.txt for the adapter's path, terms
python3 coverage_candidates.py           # → candidate_coverage.json: unserved towns each would add
```

Then write the rows, add a test address to `../abfall_census/probe.ts` and run it: only
`resolveAddress` proves the app finds the town. `served.py` is the stricter town match the atlas
uses on top of the census names ("Altenbeken-Buke" is Altenbeken). `.page_cache/` holds fetched
pages and can be deleted.

## From atlas to the app

```
python3 build_tracker.py <atlas.html>    # also writes town_pages.json: the page each unserved town gets
python3 gen_town_pages.py                # → supabase/functions/_shared/abfall/town_pages.ts
```

`resolveAddress` answers with this table last, after every provider, so a town that later gets a
provider row simply stops reaching it. The keys are `town_key`/`town_head` here and
`townKey`/`townHead` in `abfall/core.ts`; change both or neither. Deploy `abfall-lookup` and
`calendar-link` after regenerating.
