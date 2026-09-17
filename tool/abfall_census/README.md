# Abfall coverage census

What builds the **Abfall Coverage** artifact linked from `docs/production-plan.md`: which German
waste-collection calendars the app can connect from an address, per Bundesland, provider and big
city. Re-run after touching `supabase/functions/_shared/abfall_providers.ts` or any adapter in
`supabase/functions/_shared/abfall/vendors/`. `probe.ts` doubles as the live regression test for
that directory: diff its output against a pre-change run before believing a refactor. Needs Deno
(`brew install deno` or the install script into a scratch dir) and Python 3.

```
cd tool/abfall_census
deno run --allow-net --allow-read --allow-write --allow-env census.ts     # → census_raw.json (2 s)
deno run --allow-net --allow-read --allow-write --allow-env probe.ts      # → probe_results.json (~30 s, one real address per provider)
python3 finish_states.py                                                  # → census_states.json + growth.json cities (Photon cache, Nominatim for the rest)
python3 build_artifact.py                                                 # → abfall_coverage.html
```

Then republish `abfall_coverage.html` to the artifact URL in the plan.

`town_states.json` holds the Bundesland of each town for the providers whose towns span states, and
`finish_states.py` prefers it over geocoding. It was built by resolving each ambiguous town against
the **Landkreis** its provider demonstrably serves, because the geocoder's top hit put Dahlem in
Berlin (it is Kreis Euskirchen), Lichtenau in Landkreis Ansbach (Kreis Paderborn) and Goldbach in
Thüringen (Landkreis Aschaffenburg). A town missing from the file falls back to geocoding. `census_states.py` holds
the hand-assigned Bundesland per provider (`ASSIGN`); a new provider needs a line there, or it is
grouped under whatever `state` the registry gives it. `growth.json` is the vendor survey
(mampfes/hacs_waste_collection_schedule, 2026-09) and is edited by hand.

Photon (photon.komoot.io) refused connections for the rest of the session after the first bulk
run of a few hundred town lookups on 2026-09-17; `finish_states.py` therefore reads the cache and
asks Nominatim for what is missing, one request a second, with a contact in the User-Agent.
Don't hammer either.
