// Live check of every covered big city: each test address in city_meta.json
// through resolveAddress + readAbfallEvents, plus an invented street that must
// be refused. Writes city_checks.json, which build_artifact.py rates from.
//   TZ=UTC deno run -A city_check.ts
import { readAbfallEvents, resolveAddress } from "../../supabase/functions/_shared/abfall.ts";

// The geocoder always names the Bundesland, and the resolver's state guard
// depends on it — without it a Stuttgart-Münster postcode finds Bavarian Münster.
const STATES: Record<string, string> = {
  BW: "Baden-Württemberg", BY: "Bayern", BE: "Berlin", BB: "Brandenburg", HB: "Bremen", HH: "Hamburg",
  HE: "Hessen", MV: "Mecklenburg-Vorpommern", NI: "Niedersachsen", NW: "Nordrhein-Westfalen",
  RP: "Rheinland-Pfalz", SL: "Saarland", SN: "Sachsen", ST: "Sachsen-Anhalt", SH: "Schleswig-Holstein", TH: "Thüringen",
};
const growth = JSON.parse(await Deno.readTextFile(new URL("./growth.json", import.meta.url))) as { cities: Array<{ city: string; state: string }> };
const stateOf = new Map(growth.cities.map((c) => [c.city, STATES[c.state]]));

const meta = JSON.parse(await Deno.readTextFile(new URL("./city_meta.json", import.meta.url))) as
  Record<string, { tests: Array<{ street: string; nr: string; plz: string }> }>;

type Check = { address: string; outcome: "ok" | "pick" | "none" | "error"; events?: number; bins?: string[]; next?: string; error?: string; numbers?: string[] };

async function one(city: string, street: string, nr: string, plz: string): Promise<Check> {
  const address = `${street} ${nr}, ${plz} ${city}`.replace(/\s+,/, ",");
  try {
    const r = await resolveAddress({ label: address, street, houseNumber: nr || undefined, postcode: plz, town: city, state: stateOf.get(city) } as never);
    if (!r.supported || !r.config) return { address, outcome: "none" };
    let cfg = r.config;
    if (r.needsHouseNumber) {
      if (!r.hausNrList?.length) return { address, outcome: "pick" };
      cfg = { ...cfg, hnrId: r.hausNrList[0].id };
    }
    const es = await readAbfallEvents(cfg);
    const now = new Date().toISOString();
    return {
      address, outcome: r.needsHouseNumber ? "pick" : (es.length ? "ok" : "error"), events: es.length,
      ...(r.needsHouseNumber ? { numbers: r.hausNrList!.slice(0, 5).map((h) => h.nr) } : {}),
      bins: [...new Set(es.map((e) => e.title))].slice(0, 8),
      next: es.map((e) => e.startsAt).filter((d) => d >= now).sort()[0]?.slice(0, 10),
      ...(es.length ? {} : { error: "0 Termine" }),
    };
  } catch (e) {
    return { address, outcome: "error", error: e instanceof Error ? e.message : String(e) };
  }
}

// `deno run … city_check.ts Trier Wolfsburg` re-checks only those and keeps the rest.
const only = new Set(Deno.args);
const out: Record<string, { at: string; checks: Check[]; fakeRefused: boolean }> = only.size
  ? JSON.parse(await Deno.readTextFile(new URL("./city_checks.json", import.meta.url)).catch(() => "{}"))
  : {};
await Promise.all(Object.entries(meta).filter(([city, m]) => m.tests?.length && (!only.size || only.has(city))).map(async ([city, m]) => {
  const checks = []
  for (const t of m.tests) checks.push(await one(city, t.street, t.nr, t.plz));
  const fake = await one(city, "Quatschstraße", "1", m.tests[0].plz);
  out[city] = { at: new Date().toISOString().slice(0, 10), checks, fakeRefused: fake.outcome === "none" };
  console.log(city.padEnd(22), checks.map((c) => `${c.outcome}${c.events != null ? `(${c.events})` : ""}${c.error ? `[${c.error.slice(0, 40)}]` : ""}`).join("  "), out[city].fakeRefused ? "" : "FAKE-ACCEPTED");
}));
await Deno.writeTextFile(new URL("./city_checks.json", import.meta.url), JSON.stringify(out, null, 1));
