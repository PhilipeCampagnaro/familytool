// probe_candidates.ts — would-be provider rows (candidates.json) run through the
// real adapters: the towns each one lists, then one address read end to end.
// Nothing is written to the provider table; the output is candidate_probe.json.
//
//   deno run --allow-net --allow-read --allow-write --allow-env probe_candidates.ts
import { ABFALL_PROVIDERS } from "../../supabase/functions/_shared/abfall_providers.ts";
import type { AbfallConfig, AbfallProvider, GeoAddress, Town } from "../../supabase/functions/_shared/abfall/core.ts";

interface RegTown { ars: string; name: string; plz: string; pop: number; served: boolean }
interface Cand {
  id: string; families: string[]; state: string; key?: string; host?: string; client?: string; service?: string;
  reg_towns: RegTown[];
}

const TIMEOUT = 40_000;
const STEMS = ["haupt", "bahnhof", "kirch", "schul", "garten", "dorf", "berg"];
const NUMBERS = (Deno.env.get("NUMBERS") ?? "1,2,5,10").split(",");
const STREETS = ["Hauptstraße", "Bahnhofstraße", "Kirchstraße", "Schulstraße", "Marktplatz", "Dorfstraße"];

const within = <T>(p: Promise<T>, ms: number, what: string) =>
  Promise.race([p, new Promise<never>((_, rej) => setTimeout(() => rej(new Error(`timeout ${what}`)), ms))]);
const msg = (e: unknown) => (e instanceof Error ? e.message : String(e));
const geoName = (n: string) => n.split(",")[0].trim();
const lc = (s: string) => s.toLowerCase();

async function read(fam: string, cfg: AbfallConfig) {
  const events = await within(adapterFor(fam)!.read(cfg), TIMEOUT, "read");
  const days = events.map((e) => e.startsAt.slice(0, 10)).sort();
  return { events: events.length, from: days[0] ?? null, to: days.at(-1) ?? null,
    bins: [...new Set(events.map((e) => e.title))].slice(0, 8) };
}

async function tryFamily(c: Cand, fam: string) {
  const adapter = adapterFor(fam);
  if (!adapter) return { family: fam, error: "no adapter" };
  const p: AbfallProvider = { id: c.id, name: c.id, family: fam as AbfallProvider["family"], state: c.state,
    ...(c.key ? { key: c.key } : {}), ...(c.host ? { host: c.host } : {}), ...(c.client ? { client: c.client } : {}),
    ...(c.service ? { service: c.service } : {}) };
  // Single-town families (muellmax, c-trace) name their town in the row: the county's largest.
  if ((fam === "muellmax" || fam === "ctrace") && !(c as any).town) {
    let last: Record<string, unknown> = { family: fam, error: "no unserved town" };
    for (const r of c.reg_towns.filter((t) => !t.served).slice(0, 3)) {
      const town = geoName(r.name);
      const q = { ...c, reg_towns: [r] } as Cand;
      (q as any).town = town;
      last = await tryFamily(q, fam);
      if (!("error" in last)) return last;
    }
    return last;
  }
  if ((c as any).town) {
    p.town = (c as any).town;
    if (fam === "ctrace") { p.ort = p.town; p.icalFile = c.host?.startsWith("apps.") ? "downloadcal" : "cal"; }
  }
  let towns: Town[] = [];
  try {
    towns = adapter.towns ? await within(Promise.resolve(adapter.towns(p)), TIMEOUT, "towns") : [];
  } catch (e) { return { family: fam, error: `towns: ${msg(e)}` }; }
  // An Athos city tenant has no Ort list: the row names its one town.
  if (!towns.length && fam === "athos" && !p.town) {
    p.town = geoName(c.reg_towns[0]?.name ?? "");
    towns = await Promise.resolve(adapter.towns!(p)).catch(() => []);
  }
  const out: Record<string, unknown> = { family: fam, towns: towns.map((t) => t.name) };
  if (!towns.length) return { ...out, error: "no towns" };
  // Pick up to three register towns the adapter lists, largest first.
  const picks: Array<{ reg: RegTown; town: Town }> = [];
  for (const r of c.reg_towns) {
    const want = lc(geoName(r.name));
    const t = towns.find((t) => lc(t.name) === want) ?? towns.find((t) => lc(t.name).startsWith(want));
    if (t) picks.push({ reg: r, town: t });
    if (picks.length >= 3) break;
  }
  if (!picks.length) picks.push({ reg: c.reg_towns[0], town: towns[0] });
  let lastErr = "";
  for (const { reg, town } of picks) {
    if (adapter.searchStreets && !adapter.probe) {
      for (const q of STEMS) {
        try {
          const opts = await within(adapter.searchStreets(town, q), TIMEOUT, "streets");
          const o = opts.find((o) => lc(o.name) !== lc(town.name)) ?? opts[0];
          if (!o) continue;
          const cfg: AbfallConfig = { ...o.config };
          if (o.hausNrList?.length) cfg.hnrId = o.hausNrList[0].id;
          const r = await read(fam, cfg);
          if (r.events) return { ...out, town: town.name, street: o.name, ...r };
          lastErr = `0 events for ${o.name}`;
        } catch (e) { lastErr = msg(e); }
      }
      continue;
    }
    for (const street of STREETS) for (const nr of NUMBERS) {
      const addr: GeoAddress = { label: `${street} ${nr}, ${reg.plz} ${town.name}`, street, houseNumber: nr,
        town: town.name, postcode: reg.plz };
      try {
        let res = adapter.probe ? await within(adapter.probe(town, addr), TIMEOUT, "probe") : null;
        if (!res && adapter.searchStreets) {
          const opts = await within(adapter.searchStreets(town, street.slice(0, 5)), TIMEOUT, "streets");
          if (opts[0]) res = { supported: true, town: town.name, street: opts[0].name, config: opts[0].config };
        }
        if (!res?.config) { lastErr = `no config for ${street}, ${town.name}`; break; }
        if (res.needsHouseNumber && !res.hausNrList?.length) { lastErr = `no house ${nr} in ${street}, ${town.name}`; continue; }
        const cfg = { ...res.config } as AbfallConfig;
        if (res.hausNrList?.length && cfg.hnrId == null) cfg.hnrId = res.hausNrList[0].id;
        const r = await read(fam, cfg);
        if (r.events) return { ...out, town: town.name, street: res.street ?? street, asked: street, nr, plz: reg.plz, ...r };
        lastErr = `0 events for ${street}, ${town.name}`;
        break;
      } catch (e) { lastErr = msg(e); break; }
    }
  }
  return { ...out, error: lastErr || "nothing read" };
}

const ONLY = Deno.args.length ? new Set(Deno.args) : null;
const cands: Cand[] = (JSON.parse(await Deno.readTextFile("candidates.json")) as Cand[]).filter((c) => !ONLY || ONLY.has(c.id));
// Athos only talks to tenants in the table (TENANTS in athos.ts, built when the
// module loads), so the candidates go into the table first and the adapters are
// imported after.
for (const c of cands) if (c.host?.startsWith("http")) ABFALL_PROVIDERS.push({ id: c.id, name: c.id, family: "athos", host: c.host });
const { adapterFor } = await import("../../supabase/functions/_shared/abfall/registry.ts");
const results: Record<string, unknown>[] = [];
let next = 0;
async function worker() {
  while (next < cands.length) {
    const c = cands[next++];
    const tries = [];
    for (const fam of c.families) {
      const r = await tryFamily(c, fam).catch((e) => ({ family: fam, error: msg(e) }));
      tries.push(r);
      if (!("error" in r)) break;
    }
    const ok = tries.find((t) => !("error" in t));
    results.push({ id: c.id, ok: !!ok, result: ok ?? tries });
    console.log(ok ? "OK  " : "FAIL", c.id, ok ? `${(ok as any).family} ${(ok as any).events} events, ${(ok as any).towns.length} towns` : JSON.stringify(tries.map((t: any) => t.error)).slice(0, 200));
  }
}
await Promise.all(Array.from({ length: 6 }, worker));
await Deno.writeTextFile("candidate_probe.json", JSON.stringify(results, null, 1));
