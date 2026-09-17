import { aggregateTowns } from "../../supabase/functions/_shared/abfall.ts";
import { ABFALL_PROVIDERS } from "../../supabase/functions/_shared/abfall_providers.ts";
const t0 = Date.now();
const towns = await aggregateTowns();
const byProvider: Record<string, string[]> = {};
for (const t of towns) (byProvider[t.provider] ??= []).push(t.name);
const out = ABFALL_PROVIDERS.map((p) => ({
  id: p.id, name: p.name, family: p.family, state: p.state ?? null,
  towns: (byProvider[p.id] ?? []).sort((a, b) => a.localeCompare(b, "de")),
}));
await Deno.writeTextFile("census_raw.json", JSON.stringify({ at: new Date().toISOString(), ms: Date.now() - t0, providers: out }, null, 1));
const dead = out.filter((p) => p.towns.length === 0).map((p) => p.id);
console.log(`providers=${out.length} towns=${towns.length} dead=${dead.length} ${dead.join(",")} in ${Date.now() - t0}ms`);
