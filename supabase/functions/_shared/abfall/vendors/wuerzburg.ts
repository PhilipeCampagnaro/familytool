// abfall/vendors/wuerzburg.ts — Stadt Würzburg — the city's own open data
// (DL-DE-BY-2.0) for the dates, the city's own page for which street is where.

import {
  type AbfallConfig,
  type AbfallProvider,
  decodeEntities,
  fetchWithTimeout,
  type GeoAddress,
  inSpans,
  normStreet,
  type ResolveResult,
  splitSpans,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── Stadt Würzburg (Die Stadtreiniger) ──────────────────────────────────────
//
// Würzburg plans by **district** — 17 of them — and publishes the plan twice:
//
//   the Abfallkalender page    <select id="strlist"> of 1,113 streets whose
//                              value is the district id ("Abtsleitenweg" -> 19937)
//   the open-data portal       one row per district, bin and day, from today to
//                              31 December, refreshed daily:
//     GET wuerzburg.opendatasoft.com/api/explore/v2.1/catalog/datasets/
//         abfallkalender-wuerzburg/exports/json?where=stadtteil_id="19937"
//
// The ids agree exactly (checked 2026-09-18), so the page answers "which
// district" once, at connect time, and every refresh is one keyless open-data
// call. **The data is licensed DL-DE-BY-2.0, which requires naming the source**,
// so every event carries it in its notes.
//
// A handful of long streets are split by number in the street's own name
// ("Frankenstraße 1-197 ung./2-210 ger. Nr."); the household's number picks
// the entry, and an ambiguous one is asked. "Wertstoffmobil" rows are a mobile
// drop-off point with an hour and a car park, not a bin, and are left out.
//
// Rollover: the export is a rolling "today to 31 December", so the new year
// appears when the city's own feed reaches it. The page already offers 2027 in
// its year picker; worth checking in December that the export follows.
const PAGE = 'https://www.wuerzburg.de/themen/umwelt-klima/abfall-und-stadtreinigung/abfallkalender'
const DATA = 'https://wuerzburg.opendatasoft.com/api/explore/v2.1/catalog/datasets/abfallkalender-wuerzburg/exports/json'
const SOURCE = 'Quelle: Stadt Würzburg, Abfallkalender (Open Data, dl-de/by-2-0)'

interface Entry { name: string; district: string }

async function streetList(): Promise<Entry[]> {
  const res = await fetchWithTimeout(PAGE, { headers: { 'User-Agent': UA, Accept: 'text/html,*/*' } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const sel = (await res.text()).match(/<select[^>]*id="strlist"[^>]*>([\s\S]*?)<\/select>/i)?.[1] ?? ''
  return [...sel.matchAll(/<option[^>]*value="(\d+)"[^>]*>([^<]*)</gi)]
    .map((m) => ({ district: m[1], name: decodeEntities(m[2]).replace(/\s+/g, ' ').trim() }))
}

async function probeWue(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const target = normStreet(addr.street)
  const hits = (await streetList()).map((e) => ({ ...e, ...splitSpans(e.name) }))
    .filter((e) => normStreet(e.street) === target)
  if (!hits.length) return null
  const street = hits[0].street
  const cfg = { vendor: 'wuerzburg' as const, street }
  let pick = hits.length === 1 ? hits[0] : undefined
  if (!pick && addr.houseNumber) {
    const fit = hits.filter((h) => inSpans(h.spans, addr.houseNumber!))
    if (fit.length === 1) pick = fit[0]
  }
  if (pick) return { supported: true, town: town.name, street, config: { ...cfg, hnrId: pick.district } }
  // A split street and no number that decides it: each chip names its span,
  // and its id is the district the calendar is read by.
  return {
    supported: true, town: town.name, street, needsHouseNumber: true,
    hausNrList: hits.map((h) => ({ id: h.district, nr: h.name.slice(h.street.length).trim() })),
    config: cfg,
  }
}

interface Row { kategorie?: string; start?: string; stadtteil_id?: string }

async function readWue(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const district = cfg.hnrId != null ? String(cfg.hnrId) : ''
  if (!/^\d{1,9}$/.test(district)) throw new Error('reconnect_required')
  const res = await fetchWithTimeout(`${DATA}?where=${encodeURIComponent(`stadtteil_id="${district}"`)}`, {
    headers: { 'User-Agent': UA, Accept: 'application/json' },
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const rows = await res.json() as Row[]
  if (!Array.isArray(rows)) throw new Error('abfall upstream: unexpected open-data answer')
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const r of rows) {
    const title = (r.kategorie || '').trim()
    const day = (r.start || '').slice(0, 10)
    if (!title || !/^\d{4}-\d{2}-\d{2}$/.test(day) || /wertstoffmobil/i.test(title)) continue
    const k = `${day}:${title}`
    if (seen.has(k)) continue
    seen.add(k)
    const start = new Date(`${day}T00:00:00Z`)
    out.push({
      uid: `abfall:wuerzburg:${district}:${k}`,
      title,
      notes: SOURCE,
      location: cfg.label ?? null,
      startsAt: start.toISOString(),
      endsAt: new Date(start.getTime() + 86_400_000).toISOString(),
      allDay: true,
    })
  }
  return out
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'wuerzburg', name: p.town || 'Würzburg', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'wuerzburg',
  towns,
  probe: probeWue,
  read: readWue,
}
