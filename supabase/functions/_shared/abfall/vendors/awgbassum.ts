// abfall/vendors/awgbassum.ts — AWG Bassum (Landkreis Diepholz) — a per-street ICS export unique to that site.

import {
  type AbfallConfig,
  type AbfallProvider,
  fetchWithTimeout,
  getJson,
  parseIcs,
  type StreetOption,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

async function searchStreetsAwgBassum(town: Town, query: string): Promise<StreetOption[]> {
  if (!town.host || !town.city) return []
  const url = `https://${town.host}/ajax/?f=streets&c=${encodeURIComponent(town.city)}`
  const list = await getJson(url) as Array<{ display: string; data: string }>
  const q = (query || '').trim().toLowerCase()
  return (Array.isArray(list) ? list : [])
    .filter((s) => !q || (s.display || '').toLowerCase().includes(q))
    .slice(0, 40)
    .map((s) => ({
      name: s.display,
      config: {
        vendor: 'awgbassum', host: town.host, city: town.city,
        street: s.display, slug: s.data,
      },
    }))
}

// AWG Bassum publishes a per-street ICS per calendar year. Fetch this year + next
// so the overlay always looks ahead, parse with the shared ICS parser, and de-dup
// across the two feeds (they overlap at the year boundary).
async function readAwgBassum(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  if (!cfg.host || !cfg.city || !cfg.slug) throw new Error('reconnect_required')
  const thisYear = new Date().getUTCFullYear()
  const years = [thisYear, thisYear + 1]
  const start = new Date(Date.UTC(thisYear - 1, 0, 1))
  const end = new Date(Date.UTC(thisYear + 2, 0, 1))
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const year of years) {
    const url = `https://${cfg.host}/abfuhrkalender.html?year=${year}`
      + `&city=${encodeURIComponent(cfg.city)}`
      + `&street=${encodeURIComponent(cfg.street ?? '')}`
      + `&slug=${encodeURIComponent(cfg.slug)}&ical=1`
    let ics: string
    try {
      const res = await fetchWithTimeout(url, { headers: { Accept: 'text/calendar', 'User-Agent': UA } })
      if (!res.ok) continue
      ics = await res.text()
    } catch { continue }
    if (!ics.includes('BEGIN:VEVENT')) continue
    for (const ev of parseIcs(ics, start, end)) {
      const day = ev.startsAt.slice(0, 10)
      const key = `${day}:${ev.title}`
      if (seen.has(key)) continue
      seen.add(key)
      // city+slug scope the uid: every Landkreis-Diepholz address shares the same
      // host, so two family addresses would otherwise collide and merge.
      out.push({
        ...ev,
        uid: `abfall:awgbassum:${cfg.host}:${cfg.city}:${cfg.slug}:${key}`,
        notes: null,
        location: cfg.label ?? ev.location ?? null,
      })
    }
  }
  return out
}

function towns(p: AbfallProvider): Town[] {
  if (!p.host) return []
  return (p.cities || []).map((c) => ({
    vendor: 'awgbassum', name: c, provider: p.id, host: p.host, city: c,
  }))
}

export const adapter: VendorAdapter = {
  family: 'awgbassum',
  towns,
  searchStreets: searchStreetsAwgBassum,
  read: readAwgBassum,
}
