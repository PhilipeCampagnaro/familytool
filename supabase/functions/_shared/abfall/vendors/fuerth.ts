// abfall/vendors/fuerth.ts — Stadt Fürth, Amt für Abfallwirtschaft — the
// city's own street/house lookup and an ICS per house.

import {
  type AbfallConfig,
  type AbfallProvider,
  dayEvents,
  fetchWithTimeout,
  type GeoAddress,
  icsDays,
  normStreet,
  type ResolveResult,
  streetStem,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── Stadt Fürth ─────────────────────────────────────────────────────────────
//
//   GET abfallwirtschaft.fuerth.eu/?c=<prefix>     -> [{"value":"Königstraße"}]
//   GET abfallwirtschaft.fuerth.eu/?r=<street>     -> [{"i":"94199001","n":"   1 "}]
//   GET abfallwirtschaft.fuerth.eu/?icalexport=<i> -> text/calendar, VALUE=DATE
//
// The city only — the Landkreis Fürth is a different authority on Athos. The
// street search is a prefix match; the house list is exact and padded. The ICS
// is the current calendar year with holiday shifts already applied; an unknown
// id is an empty calendar. Rhythm is fixed per house.
const ORIGIN = 'https://abfallwirtschaft.fuerth.eu/'

async function json<T>(params: Record<string, string>): Promise<T> {
  const res = await fetchWithTimeout(`${ORIGIN}?${new URLSearchParams(params)}`, {
    headers: { 'User-Agent': UA, Accept: 'application/json, */*' },
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return await res.json() as T
}

async function probeFue(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const target = normStreet(addr.street)
  // Prefix search: ask by the stem so "Königstr." and "Königstraße" both land.
  const hits = await json<Array<{ value: string }>>({ c: streetStem(addr.street).slice(0, 30) })
  const street = hits.map((h) => h.value).find((v) => normStreet(v) === target)
  if (!street) return null
  const houses = (await json<Array<{ i: string; n: string }>>({ r: street }))
    .map((h) => ({ id: h.i, nr: h.n.replace(/\s+/g, ' ').trim() }))
  const cfg = { vendor: 'fuerth' as const, street }
  const want = (addr.houseNumber || '').toLowerCase().replace(/\s+/g, '')
  const hit = houses.find((h) => h.nr.toLowerCase().replace(/\s+/g, '') === want)
  if (hit) return { supported: true, town: town.name, street, config: { ...cfg, hnrId: hit.id } }
  return { supported: true, town: town.name, street, needsHouseNumber: true, hausNrList: houses, config: cfg }
}

async function readFue(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const id = cfg.hnrId != null ? String(cfg.hnrId) : ''
  if (!/^\d{1,12}$/.test(id)) throw new Error('reconnect_required')
  const res = await fetchWithTimeout(`${ORIGIN}?icalexport=${id}`, { headers: { 'User-Agent': UA, Accept: 'text/calendar, */*' } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const days = icsDays(await res.text())
  if (!days.length) throw new Error('reconnect_required')
  return dayEvents(days, `abfall:fuerth:${id}`, cfg.label ?? null)
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'fuerth', name: p.town || 'Fürth', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'fuerth',
  towns,
  probe: probeFue,
  read: readFue,
}
