// abfall/vendors/art.ts — A.R.T. Zweckverband Abfallwirtschaft Region Trier —
// the authority's own street search (Strapi) and a per-street ICS feed.

import {
  type AbfallConfig,
  type AbfallProvider,
  fetchWithTimeout,
  type GeoAddress,
  normStreet,
  streetStem,
  parseIcs,
  type ResolveResult,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── A.R.T. (Stadt Trier + Landkreise Trier-Saarburg, Bernkastel-Wittlich,
//    Vulkaneifel, Eifelkreis Bitburg-Prüm) ────────────────────────────────────
//
// art-trier.de/abfuhrtermin is a Next.js page over the authority's own API:
//
//   GET redaktion.art-trier.de/api/abfuhrtermine/search?strasse=&ort=
//        -> {data:[{plz, ort, strasse, ortsteil, verbandsgemeinde, key}]}
//   GET www.art-trier.de/ics-feed/<key>@.ics     (after "@": a reminder, empty)
//
// `key` is "54290:Trier:Saarstraße:Süd" — PLZ, Ort, street, Ortsteil — so the
// schedule is per street, never per house. **A village with one schedule for
// all of it has a row with no street** ("54329:Konz-Kommlingen::"); any street
// there takes that row. 848 Orte in 2,289 rows (2026-09-18), read whole at
// town-list time, which the resolver caches for six hours.
//
// **The feed never says no.** An unknown key is a 200 with one event, "A.R.T.
// Wichtiger Hinweis!", so a calendar with nothing else in it is "not found".
// Titles read "Restabfall - Saarstraße, Trier - A.R.T. Abfuhrtermin"; the part
// before the first " - " is the bin. Paper and the yellow sack go out together
// and are one title ("Papier & Gelber Sack"). The feed runs from a few weeks
// back to 31 December; next year appears when A.R.T. publishes it.
const API = 'https://redaktion.art-trier.de/api/abfuhrtermine/search'
const FEED = 'https://www.art-trier.de/ics-feed/'

interface Row { plz: string; ort: string; strasse: string | null; ortsteil: string | null; key: string }

async function search(params: Record<string, string>, pageSize = 100, page = 1): Promise<{ rows: Row[]; pages: number }> {
  const q = new URLSearchParams({ ...params, 'pagination[page]': String(page), 'pagination[pageSize]': String(pageSize) })
  const res = await fetchWithTimeout(`${API}?${q}`, { headers: { 'User-Agent': UA, Accept: 'application/json' } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const body = await res.json() as { data?: Row[]; meta?: { pagination?: { pageCount?: number } } }
  return { rows: Array.isArray(body.data) ? body.data : [], pages: body.meta?.pagination?.pageCount ?? 1 }
}

async function towns(p: AbfallProvider): Promise<Town[]> {
  const names = new Set<string>()
  const first = await search({ fulltext: '' }, 500)
  first.rows.forEach((r) => names.add(r.ort))
  for (let page = 2; page <= Math.min(first.pages, 20); page++) {
    ;(await search({ fulltext: '' }, 500, page)).rows.forEach((r) => names.add(r.ort))
  }
  return [...names].filter(Boolean).map((name) => ({ vendor: 'art' as const, name, provider: p.id }))
}

async function probeArt(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  const target = normStreet(addr.street || '')
  // `ort` and `strasse` are contains-matches upstream ("Trier" also finds
  // "Trierweiler"), so ask by the street's stem and compare exactly here.
  let hits = !target ? [] : (await search({ ort: town.name, strasse: streetStem(addr.street) }, 100)).rows
    .filter((r) => r.ort === town.name && r.strasse && normStreet(r.strasse) === target)
  // One street name in two PLZ areas of one Ort: the household's PLZ decides.
  if (hits.length > 1 && addr.postcode) {
    const byPlz = hits.filter((r) => r.plz === addr.postcode)
    if (byPlz.length) hits = byPlz
  }
  if (!hits.length) {
    // A village planned as a whole takes any street; a town with streets does
    // not. **Only when it is the household's own town by name**: the resolver
    // also tries "Konz-Kommlingen" for an address in "Konz", and taking any
    // street there would hand a Konz household a village's bin days.
    const own = (addr.town || '').trim().toLowerCase()
    const tn = town.name.toLowerCase()
    if (own !== tn && own !== tn.split('-').pop()) return null
    const rows = (await search({ ort: town.name }, 100)).rows.filter((r) => r.ort === town.name)
    const whole = rows.filter((r) => !r.strasse)
    if (whole.length !== 1 || rows.some((r) => r.strasse)) return null
    return { supported: true, town: town.name, street: addr.street, config: { vendor: 'art', street: addr.street, hnrId: whole[0].key } }
  }
  const street = hits[0].strasse!
  if (hits.length === 1) return { supported: true, town: town.name, street, config: { vendor: 'art', street, hnrId: hits[0].key } }
  // The same street in two Ortsteile: each chip names its Ortsteil.
  return {
    supported: true, town: town.name, street, needsHouseNumber: true,
    hausNrList: hits.map((r) => ({ id: r.key, nr: r.ortsteil || r.plz })),
    config: { vendor: 'art', street },
  }
}

async function readArt(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const key = cfg.hnrId != null ? String(cfg.hnrId) : ''
  if (!/^\d{5}:[^:/@]+:[^:/@]*:[^:/@]*$/.test(key)) throw new Error('reconnect_required')
  const res = await fetchWithTimeout(`${FEED}${encodeURIComponent(key)}@.ics`, {
    headers: { 'User-Agent': UA, Accept: 'text/calendar, */*' },
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const y = new Date().getUTCFullYear()
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const ev of parseIcs(await res.text(), new Date(Date.UTC(y - 1, 0, 1)), new Date(Date.UTC(y + 2, 0, 1)))) {
    if (/wichtiger hinweis/i.test(ev.title)) continue
    const title = ev.title.split(' - ')[0].trim()
    const day = ev.startsAt.slice(0, 10)
    const k = `${day}:${title}`
    if (!title || seen.has(k)) continue
    seen.add(k)
    const start = new Date(`${day}T00:00:00Z`)
    out.push({
      uid: `abfall:art:${key}:${k}`,
      title,
      notes: null,
      location: cfg.label ?? null,
      startsAt: start.toISOString(),
      endsAt: new Date(start.getTime() + 86_400_000).toISOString(),
      allDay: true,
    })
  }
  // Only the placeholder: the key no longer names a street.
  if (!out.length) throw new Error('reconnect_required')
  return out
}

export const adapter: VendorAdapter = {
  family: 'art',
  towns,
  probe: probeArt,
  read: readArt,
}
