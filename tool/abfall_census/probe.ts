// probe.ts — live end-to-end proof that every Abfall provider still delivers
// pickup dates. Read-only against the project; writes probe_results.json here.
import {
  aggregateTowns, searchStreets, readAbfallEvents, resolveAddress,
  type Town, type StreetOption, type AbfallConfig, type GeoAddress,
} from "../../supabase/functions/_shared/abfall.ts";
import { ABFALL_PROVIDERS } from "../../supabase/functions/_shared/abfall_providers.ts";

const OUT = new URL("./probe_results.json", import.meta.url).pathname;
const CONCURRENCY = 4;
const PROVIDER_TIMEOUT_MS = 25_000;
const STEMS = ["haupt", "schul", "bahnhof", "kirch", "garten", "berg", "dorf", "a"];

interface Result {
  provider: string; name: string; family: string;
  town: string | null; street: string | null;
  events: number; from: string | null; to: string | null; bins: string[];
  ms: number; error?: string; triedTowns: string[];
}

// Families that cannot be walked town -> street -> config, so the probe goes in
// through resolveAddress with a real address instead. C-Trace has no street
// enumeration at all; BSR and FES enumerate streets but plan per house, so a
// street alone yields no readable config.
const RESOLVE_FAMILIES = new Set(["ctrace", "bsr", "fes", "awm", "awbkoeln", "srh", "awsstuttgart", "awista"]);

const PROBE_ADDRESSES: Record<string, { street: string; town: string; postcode: string; houseNumber?: string }> = {
  "ctrace-bremen": { street: "Obernstraße", town: "Bremen", postcode: "28195" },
  "ctrace-arnsberg": { street: "Hauptstraße", town: "Arnsberg", postcode: "59821" },
  "ctrace-landau": { street: "Marktstraße", town: "Landau in der Pfalz", postcode: "76829" },
  "ctrace-oberursel": { street: "Hauptstraße", town: "Oberursel", postcode: "61440" },
  "bsr-berlin": { street: "Karl-Marx-Allee", town: "Berlin", postcode: "10178", houseNumber: "1" },
  "fes-frankfurt": { street: "Frankenallee", town: "Frankfurt am Main", postcode: "60327", houseNumber: "2" },
  // Spelled as the geocoder spells it, not as AWM does ("Francestr."): the
  // accent and the written-out "straße" are exactly what used to miss.
  "awm-muenchen": { street: "Francéstraße", town: "München", postcode: "80997", houseNumber: "10" },
  "awbkoeln-koeln": { street: "Bergisch Gladbacher Straße", town: "Köln", postcode: "51065", houseNumber: "100" },
  "srh-hamburg": { street: "Fränkelstraße", town: "Hamburg", postcode: "22307", houseNumber: "3" },
  // Deliberately the full "Straße": the city writes "Wachenheimer Str." and
  // will not find the unabbreviated form, so this exercises the stem lookup.
  "aws-stuttgart": { street: "Wachenheimer Straße", town: "Stuttgart", postcode: "70376", houseNumber: "3" },
  // Deliberately in the ae-spelling AWISTA does not index, so this also
  // exercises the title scan that finds "Askanierstraße 3" regardless.
  "awista-duesseldorf": { street: "Askanierstrasse", town: "Düsseldorf", postcode: "40547", houseNumber: "3" },
};
const CTRACE_FALLBACK_STREETS = ["Bahnhofstraße", "Kirchstraße"];
// Streets the vendor is known to hold, tried last, so a failure separates "wrong test address" from "provider down".
const CTRACE_EXTRA_STREETS: Record<string, string[]> = { "ctrace-landau": ["Königstr."], "ctrace-oberursel": ["Vorstadt"] };
// A per-house vendor needs its own street to keep its house number; the generic
// fallbacks below would carry no. 1 onto a street that may not have one.
const KEEPS_HOUSE_NUMBER = new Set(["bsr", "fes", "awm", "srh", "awsstuttgart", "awista"]);

const E2E_ADDRESSES: Array<{ label: string; street: string; town: string; postcode: string; houseNumber?: string }> = [
  { label: "Templergraben, 52062 Aachen", street: "Templergraben", town: "Aachen", postcode: "52062" },
  { label: "Bahnhofstraße, 71332 Waiblingen", street: "Bahnhofstraße", town: "Waiblingen", postcode: "71332" },
  { label: "Rheinstraße, 64283 Darmstadt", street: "Rheinstraße", town: "Darmstadt", postcode: "64283" },
  { label: "Weyher Straße, 28816 Stuhr", street: "Weyher Straße", town: "Stuhr", postcode: "28816" },
  { label: "Hauptstraße, 49536 Lienen", street: "Hauptstraße", town: "Lienen", postcode: "49536" },
  { label: "Karl-Marx-Allee 1, 10178 Berlin", street: "Karl-Marx-Allee", town: "Berlin", postcode: "10178", houseNumber: "1" },
  { label: "Frankenallee 2, 60327 Frankfurt am Main", street: "Frankenallee", town: "Frankfurt am Main", postcode: "60327", houseNumber: "2" },
  { label: "Francestr. 10, 80995 München", street: "Francestr.", town: "München", postcode: "80995", houseNumber: "10" },
];

function withTimeout<T>(p: Promise<T>, ms: number, what: string): Promise<T> {
  let t: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, rej) => {
    t = setTimeout(() => rej(new Error(`timeout after ${ms}ms (${what})`)), ms);
  });
  return Promise.race([p, timeout]).finally(() => clearTimeout(t));
}

function summarise(events: Array<{ startsAt: string; title: string }>) {
  const dates = events.map((e) => e.startsAt.slice(0, 10)).sort();
  const bins = [...new Set(events.map((e) => e.title))].slice(0, 6);
  return { events: events.length, from: dates[0] ?? null, to: dates[dates.length - 1] ?? null, bins };
}

const errMsg = (e: unknown) => (e instanceof Error ? e.message : String(e));

// Street pick + config merge, exactly the way the client would do it.
async function pickStreet(town: Town): Promise<{ option: StreetOption; config: AbfallConfig; query: string } | null> {
  let lastErr: unknown = null;
  for (const q of STEMS) {
    let options: StreetOption[];
    try {
      options = await searchStreets(town, q);
    } catch (e) { lastErr = e; continue; }
    if (!options.length) continue;
    const tn = town.name.trim().toLowerCase();
    const option = options.find((o) => o.name.trim().toLowerCase() !== tn) ?? options[0];
    const config: AbfallConfig = { ...option.config, label: `${option.name}, ${town.name}` };
    if (option.hausNrList?.length) config.hnrId = option.hausNrList[0].id;
    return { option, config, query: q };
  }
  if (lastErr) throw lastErr;
  return null;
}

async function probeProvider(
  p: typeof ABFALL_PROVIDERS[number], towns: Town[],
): Promise<Result> {
  const t0 = Date.now();
  const base: Result = {
    provider: p.id, name: p.name, family: p.family, town: null, street: null,
    events: 0, from: null, to: null, bins: [], ms: 0, triedTowns: [],
  };
  const done = (r: Partial<Result>): Result => ({ ...base, ...r, ms: Date.now() - t0 });

  try {
    if (RESOLVE_FAMILIES.has(p.family)) {
      const addr = PROBE_ADDRESSES[p.id];
      if (!addr) return done({ error: `no probe address configured for this ${p.family} provider` });
      const tried: string[] = [];
      let lastErr: string | undefined;
      const streets = KEEPS_HOUSE_NUMBER.has(p.family)
        ? [addr.street]
        : [addr.street, ...CTRACE_FALLBACK_STREETS, ...(CTRACE_EXTRA_STREETS[p.id] ?? [])];
      for (const street of streets) {
        tried.push(street);
        const geo: GeoAddress = {
          label: `${street}${addr.houseNumber ? ` ${addr.houseNumber}` : ""}, ${addr.postcode} ${addr.town}`,
          street, town: addr.town, postcode: addr.postcode,
          ...(addr.houseNumber ? { houseNumber: addr.houseNumber } : {}),
        };
        let res;
        try {
          res = await withTimeout(resolveAddress(geo), PROVIDER_TIMEOUT_MS, `resolve ${p.id}`);
        } catch (e) { lastErr = errMsg(e); continue; }
        if (!res.supported || !res.config) { lastErr = `resolveAddress: unsupported (town=${res.town})`; continue; }
        try {
          const events = await withTimeout(readAbfallEvents(res.config), PROVIDER_TIMEOUT_MS, `read ${p.id}`);
          return done({ town: res.town, street: res.street ?? street, ...summarise(events), triedTowns: tried,
            ...(events.length ? {} : { error: "resolved but readAbfallEvents returned 0 events" }) });
        } catch (e) { lastErr = errMsg(e); }
      }
      return done({ town: addr.town, triedTowns: tried, error: lastErr ?? "no street accepted" });
    }

    const mine = towns.filter((t) => t.provider === p.id);
    if (!mine.length) return done({ error: "aggregateTowns returned no towns for this provider" });
    const tried: string[] = [];
    let lastErr: string | undefined;
    let lastTown: string | null = null;
    let lastStreet: string | null = null;
    for (const town of mine.slice(0, 3)) {
      tried.push(town.name);
      lastTown = town.name;
      lastStreet = null;
      const remaining = PROVIDER_TIMEOUT_MS - (Date.now() - t0);
      if (remaining <= 0) { lastErr = `timeout after ${PROVIDER_TIMEOUT_MS}ms (budget spent)`; break; }
      try {
        const picked = await withTimeout(pickStreet(town), remaining, `streets ${p.id}/${town.name}`);
        if (!picked) { lastErr = `no street options for any query stem in ${town.name}`; continue; }
        lastStreet = picked.option.name;
        const left = PROVIDER_TIMEOUT_MS - (Date.now() - t0);
        if (left <= 0) { lastErr = `timeout after ${PROVIDER_TIMEOUT_MS}ms (budget spent)`; break; }
        const events = await withTimeout(readAbfallEvents(picked.config), left, `read ${p.id}/${town.name}`);
        if (events.length) {
          return done({ town: town.name, street: picked.option.name, ...summarise(events), triedTowns: tried });
        }
        lastErr = `readAbfallEvents returned 0 events (street "${picked.option.name}" via stem "${picked.query}")`;
      } catch (e) {
        lastErr = errMsg(e);
        if (/timeout after/.test(lastErr)) break;
      }
    }
    return done({ town: lastTown, street: lastStreet, triedTowns: tried, error: lastErr ?? "unknown" });
  } catch (e) {
    return done({ error: errMsg(e) });
  }
}

async function e2e(a: typeof E2E_ADDRESSES[number]): Promise<Result> {
  const t0 = Date.now();
  const base: Result = {
    provider: `e2e:${a.town}`, name: a.label, family: "resolveAddress", town: a.town, street: a.street,
    events: 0, from: null, to: null, bins: [], ms: 0, triedTowns: [a.town],
  };
  const done = (r: Partial<Result>): Result => ({ ...base, ...r, ms: Date.now() - t0 });
  try {
    const res = await withTimeout(resolveAddress({ label: a.label, street: a.street, town: a.town, postcode: a.postcode, ...(a.houseNumber ? { houseNumber: a.houseNumber } : {}) }), PROVIDER_TIMEOUT_MS, `resolve ${a.town}`);
    if (!res.supported || !res.config) return done({ error: `resolveAddress: unsupported (town=${res.town})` });
    const cfg: AbfallConfig = { ...res.config, label: a.label };
    if (res.hausNrList?.length) cfg.hnrId = res.hausNrList[0].id;
    const events = await withTimeout(readAbfallEvents(cfg), PROVIDER_TIMEOUT_MS, `read ${a.town}`);
    return done({
      provider: `e2e:${a.town} (${cfg.vendor})`, town: res.town, street: res.street ?? a.street,
      ...summarise(events),
      ...(events.length ? {} : { error: "resolved but readAbfallEvents returned 0 events" }),
    });
  } catch (e) { return done({ error: errMsg(e) }); }
}

// ── main ─────────────────────────────────────────────────────────────────────
const started = Date.now();
const results: Result[] = [];
const e2eResults: Result[] = [];
async function flush() {
  await Deno.writeTextFile(OUT, JSON.stringify({
    at: new Date().toISOString(), elapsedMs: Date.now() - started,
    results, e2e: e2eResults,
  }, null, 1));
}

console.log("aggregating towns…");
const towns = await aggregateTowns();
console.log(`towns=${towns.length} in ${Date.now() - started}ms; probing ${ABFALL_PROVIDERS.length} providers with concurrency ${CONCURRENCY}`);

let next = 0;
async function worker() {
  while (next < ABFALL_PROVIDERS.length) {
    const p = ABFALL_PROVIDERS[next++];
    const r = await probeProvider(p, towns);
    results.push(r);
    console.log(`[${results.length}/${ABFALL_PROVIDERS.length}] ${r.provider} ${r.family} town=${r.town} street=${r.street} events=${r.events} ${r.from}..${r.to} ${r.ms}ms${r.error ? ` ERROR: ${r.error}` : ""}`);
    await flush();
  }
}
await Promise.all(Array.from({ length: CONCURRENCY }, worker));

console.log("e2e resolveAddress runs…");
for (const a of E2E_ADDRESSES) {
  const r = await e2e(a);
  e2eResults.push(r);
  console.log(`e2e ${r.provider} town=${r.town} street=${r.street} events=${r.events} ${r.from}..${r.to} ${r.ms}ms${r.error ? ` ERROR: ${r.error}` : ""}`);
  await flush();
}
const bad = results.filter((r) => r.error || r.events === 0);
console.log(`done in ${Date.now() - started}ms; providers=${results.length} bad=${bad.length}: ${bad.map((r) => r.provider).join(",")}`);
Deno.exit(0);
