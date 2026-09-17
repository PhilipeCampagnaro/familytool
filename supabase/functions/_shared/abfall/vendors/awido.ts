// abfall/vendors/awido.ts — AWIDO Online (Cubefour) — many municipalities keyed by a client id.

import {
  type AbfallConfig,
  type AbfallProvider,
  fetchWithTimeout,
  getJson,
  type HausNr,
  parseIcs,
  type StreetOption,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// AWIDO Online (Cubefour) — one shared host for every customer; the customer
// slug rides in the URL (note: `client=` is a PATH segment on getPlaces, a query
// param elsewhere — that asymmetry is the vendor's, not ours).
const AWIDO_BASE = 'https://awido.cubefour.de/WebServices/Awido.Service.svc/secure'

async function searchStreetsAwido(town: Town, query: string): Promise<StreetOption[]> {
  if (!town.client || !town.placeKey) return []
  const list = await getJson(
    `${AWIDO_BASE}/getGroupedStreets/${town.placeKey}?client=${town.client}`,
  ) as Array<{ key: string; value: string }>
  const q = (query || '').trim().toLowerCase()
  const tn = town.name.trim().toLowerCase()
  return (Array.isArray(list) ? list : [])
    // Keep a town-named entry even when the query misses it — that's the
    // vendor's "whole town, one schedule" form, which resolveAddress accepts.
    .filter((s) => {
      const n = (s.value || '').toLowerCase()
      return !q || n.includes(q) || n === tn
    })
    .slice(0, 40)
    .map((s) => ({
      name: s.value,
      config: { vendor: 'awido', client: town.client, oid: s.key },
    }))
}

// AWIDO: one getData call returns the full calendar year as JSON — pickup dates
// (dt=YYYYMMDD, fr=fraction codes) plus the fraction-code -> name map (fracts).
// Entries with fr=null are public holidays, not pickups. A picked house number
// (hnrId = addon GUID) replaces the street oid. A few clients don't serve the
// JSON payload at all; for those we fall back to the official ICS export.
async function readAwido(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  if (!cfg.client || !cfg.oid) throw new Error('reconnect_required')
  const oid = (typeof cfg.hnrId === 'string' && cfg.hnrId) || cfg.oid
  let data: {
    fracts?: Array<{ snm: string; nm: string }>
    calendar?: Array<{ dt?: string; fr?: string[] | null }>
  }
  try {
    data = await getJson(
      `${AWIDO_BASE}/getData/${oid}?fractions=&client=${cfg.client}`,
    ) as typeof data
  } catch {
    return readAwidoIcs(cfg, oid)
  }
  const fname = new Map<string, string>()
  for (const f of (data.fracts || [])) fname.set(f.snm, f.nm)

  const events: SyncedEvent[] = []
  for (const item of (data.calendar || [])) {
    if (!item?.dt || !Array.isArray(item.fr) || !item.fr.length) continue
    const iso = `${item.dt.slice(0, 4)}-${item.dt.slice(4, 6)}-${item.dt.slice(6, 8)}`
    const start = new Date(`${iso}T00:00:00Z`)
    if (isNaN(start.getTime())) continue
    const end = new Date(start)
    end.setUTCDate(end.getUTCDate() + 1)
    for (const fr of item.fr) {
      events.push({
        uid: `abfall:awido:${cfg.client}:${oid}:${item.dt}:${fr}`,
        title: fname.get(fr) || fr || 'Abfuhr',
        notes: null,
        location: cfg.label ?? null,
        startsAt: start.toISOString(),
        endsAt: end.toISOString(),
        allDay: true,
      })
    }
  }
  return events
}

// Fallback for AWIDO clients without the JSON payload: the per-oid ICS export,
// fetched for this year + next (mirrors the awgbassum year handling).
async function readAwidoIcs(cfg: AbfallConfig, oid: string): Promise<SyncedEvent[]> {
  const thisYear = new Date().getUTCFullYear()
  const start = new Date(Date.UTC(thisYear - 1, 0, 1))
  const end = new Date(Date.UTC(thisYear + 2, 0, 1))
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const year of [thisYear, thisYear + 1]) {
    // An empty reminder= makes the endpoint answer with an HTML page instead of
    // ICS; the widget always sends a concrete value, so we mirror it.
    const url = `https://awido.cubefour.de/Customer/${cfg.client}/KalenderICS.aspx`
      + `?oid=${encodeURIComponent(oid)}&jahr=${year}&fraktionen=&reminder=${encodeURIComponent('-1.17:00')}`
    let ics: string
    try {
      const res = await fetchWithTimeout(url, { headers: { Accept: 'text/calendar', 'User-Agent': UA } })
      if (!res.ok) continue
      ics = await res.text()
    } catch { continue }
    if (!ics.includes('BEGIN:VEVENT')) continue
    for (const ev of parseIcs(ics, start, end)) {
      const key = `${ev.startsAt.slice(0, 10)}:${ev.title}`
      if (seen.has(key)) continue
      seen.add(key)
      out.push({
        ...ev,
        uid: `abfall:awido:${cfg.client}:${oid}:${key}`,
        notes: null,
        location: cfg.label ?? ev.location ?? null,
      })
    }
  }
  return out
}

async function towns(p: AbfallProvider): Promise<Town[]> {
  if (!p.client) return []
  const places = await getJson(
    `${AWIDO_BASE}/getPlaces/client=${p.client}`,
  ) as Array<{ key: string; value: string }>
  return (Array.isArray(places) ? places : []).map((pl) => ({
    vendor: 'awido', name: pl.value, provider: p.id, client: p.client, placeKey: pl.key,
  }))
}

// AWIDO house numbers live behind an extra per-street call, so they are fetched
// only for the one matched street. No addons = a street-level schedule.
async function houseNumbers(opt: StreetOption): Promise<HausNr[] | undefined> {
  if (!opt.config.oid) return undefined
  const addons = await getJson(
    `${AWIDO_BASE}/getStreetAddons/${opt.config.oid}?client=${opt.config.client}`,
  ) as Array<{ key: string; value: string }>
  return (Array.isArray(addons) ? addons : [])
    .filter((a) => (a.value || '').trim())
    .map((a) => ({ id: a.key, nr: a.value }))
}

export const adapter: VendorAdapter = {
  family: 'awido',
  towns,
  searchStreets: searchStreetsAwido,
  houseNumbers,
  read: readAwido,
}
