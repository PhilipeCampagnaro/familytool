// abfall/vendors/insertit.ts — Insert IT "BmsAbfallkalender" — one ASP.NET app
// per city on www.insert-it.de, three keyless GETs from street to ICS.

import {
  type AbfallConfig,
  type AbfallProvider,
  fetchWithTimeout,
  type GeoAddress,
  germanSpellings,
  normStreet,
  parseIcs,
  type ResolveResult,
  streetStem,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── Insert IT BmsAbfallkalender ─────────────────────────────────────────────
//
// Mannheim, Kassel, Lübeck, Herne and Offenbach each run their own copy under
// `www.insert-it.de/BmsAbfallkalender<Slug>/`:
//
//   GET Main/GetStreets?text=<prefix>              -> [{ID, Name}]
//   GET Main/GetLocations?streetId=<id>&houseNumber=
//        -> [{ID, HouseNumberStart, …StartExtra, HouseNumberEnd, …EndExtra, Text}]
//   GET Main/Calender?bmsLocationId=<ID>&year=<y>  -> text/calendar
//
// The page loads Friendly Captcha for its mail form; none of the three calls
// asks for it.
//
// **The street search is a literal prefix match that folds nothing**, and each
// city spells its own way — Mannheim abbreviates ("Hauptstr."), Lübeck does not
// ("Hauptstraße") and sometimes shouts ("BAHNHOFSBRÜCKE"). So the stem is asked
// in every spelling and the rows are compared normalised. An invented street
// returns `[]`, so this vendor does say no.
//
// **A location is a house or a span of houses** ("7", "7-7c", "19-21"), and one
// number can appear in several (Offenbach's Kaiserstraße 3 twice; Herne's
// Bahnhofstr. 7 as "7" and inside "7-7c"). Every row that names the house is
// taken, and `merge` decides whether they add up to one calendar.
//
// A calendar-year vendor: `year` is a parameter, the current year is always
// there and next year is `[]` until the city publishes it, so the read asks for
// both. The feed's UIDs are fresh random uuids on every download, so ours are
// built from the location and the day. Titles read "Leerung: Biomüll
// (Kaiserstraße 3)" — the prefix and the echoed address are dropped.
const BASE = 'https://www.insert-it.de/BmsAbfallkalender'

interface IitStreet { ID: number; Name: string }
interface IitLocation {
  ID: number
  HouseNumberStart: number | null
  HouseNumberStartExtra: string | null
  HouseNumberEnd: number | null
  HouseNumberEndExtra: string | null
  Text: string
}

async function getJson<T>(slug: string, path: string, params: Record<string, string>): Promise<T> {
  const res = await fetchWithTimeout(`${BASE}${slug}/Main/${path}?${new URLSearchParams(params)}`, {
    headers: { 'User-Agent': UA, Accept: 'application/json, */*' },
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return await res.json() as T
}

async function findStreet(slug: string, street: string): Promise<IitStreet | null> {
  const target = normStreet(street)
  if (!target) return null
  const seen = new Set<string>()
  for (const base of [street.trim(), streetStem(street)]) {
    for (const q of germanSpellings(base)) {
      if (!q || seen.has(q)) continue
      seen.add(q)
      const rows = await getJson<IitStreet[]>(slug, 'GetStreets', { text: q }).catch(() => [] as IitStreet[])
      const hit = rows.find((r) => normStreet(r.Name) === target)
      if (hit) return hit
    }
  }
  return null
}

const locations = (slug: string, streetId: number) =>
  getJson<IitLocation[]>(slug, 'GetLocations', { streetId: String(streetId), houseNumber: '' })

// "12a" -> [12, 'a']; anything without a leading number -> null.
function splitNr(nr: string): [number, string] | null {
  const m = (nr || '').trim().toLowerCase().replace(/\s+/g, '').match(/^(\d+)([a-z]*)/)
  return m ? [Number(m[1]), m[2]] : null
}

const cmp = (a: [number, string], b: [number, string]) => a[0] - b[0] || a[1].localeCompare(b[1])

const exact = (l: IitLocation, want: string) =>
  l.Text.toLowerCase().replace(/\s+/g, '') === want.toLowerCase().replace(/\s+/g, '')

function inSpan(l: IitLocation, want: [number, string]): boolean {
  if (l.HouseNumberStart == null || l.HouseNumberEnd == null) return false
  const lo: [number, string] = [l.HouseNumberStart, (l.HouseNumberStartExtra || '').toLowerCase()]
  // "7-7c" ends at 7c; "19-21" ends at 21 and takes 21a with it.
  const hi: [number, string] = [l.HouseNumberEnd, (l.HouseNumberEndExtra || 'zz').toLowerCase()]
  return cmp(lo, want) <= 0 && cmp(want, hi) <= 0
}

async function fetchYear(slug: string, locationId: string, year: number): Promise<string> {
  const res = await fetchWithTimeout(`${BASE}${slug}/Main/Calender?bmsLocationId=${encodeURIComponent(locationId)}&year=${year}`, {
    headers: { 'User-Agent': UA, Accept: 'text/calendar, */*' },
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return res.text()
}

function events(ics: string, who: string, label: string | null | undefined): SyncedEvent[] {
  const y = new Date().getUTCFullYear()
  const out: SyncedEvent[] = []
  for (const ev of parseIcs(ics, new Date(Date.UTC(y - 1, 0, 1)), new Date(Date.UTC(y + 2, 0, 1)))) {
    const title = ev.title.replace(/^Leerung:\s*/i, '').replace(/\s*\([^)]*\)\s*$/, '').trim() || ev.title.trim()
    const day = ev.startsAt.slice(0, 10)
    const start = new Date(`${day}T00:00:00Z`)
    out.push({
      uid: `abfall:insertit:${who}:${day}:${title}`,
      title,
      notes: null,
      location: label ?? ev.location ?? null,
      startsAt: start.toISOString(),
      endsAt: new Date(start.getTime() + 86_400_000).toISOString(),
      allDay: true,
    })
  }
  return out
}

// This year's pickups for one location, as title -> sorted dates.
async function binDates(slug: string, id: number): Promise<Map<string, string>> {
  const ics = await fetchYear(slug, String(id), new Date().getUTCFullYear()).catch(() => '')
  const by = new Map<string, string[]>()
  for (const e of events(ics, '', null)) by.set(e.title, [...(by.get(e.title) ?? []), e.startsAt])
  return new Map([...by].map(([t, d]) => [t, d.sort().join(',')]))
}

/// Several locations can answer for one house, and what to do depends on
/// whether they disagree. Herne's Bahnhofstr. has a "7" carrying only the
/// Wertstofftonne and a "7-7c" carrying all three bins — the house needs both,
/// and the Wertstoff dates are the same in each. Offenbach's twin "3"s are the
/// same calendar twice. Either way, every bin they share falls on the same days,
/// so the union is the house's calendar. When one bin has two rhythms, they are
/// different buildings and the household picks.
async function merge(slug: string, hits: IitLocation[]): Promise<IitLocation[] | null> {
  const maps = await Promise.all(hits.map((h) => binDates(slug, h.ID)))
  const seen = new Map<string, string>()
  for (const m of maps) {
    for (const [bin, dates] of m) {
      if (seen.has(bin) && seen.get(bin) !== dates) return null
      seen.set(bin, dates)
    }
  }
  if (!seen.size) return null
  // Drop a location that adds nothing (an identical twin), keep the rest.
  const keep: IitLocation[] = []
  const covered = new Set<string>()
  hits.forEach((h, i) => {
    const bins = [...maps[i].keys()]
    if (bins.some((b) => !covered.has(b))) {
      keep.push(h)
      bins.forEach((b) => covered.add(b))
    }
  })
  return keep
}

async function probeIit(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  const slug = town.client
  if (!slug || !addr.street) return null
  const st = await findStreet(slug, addr.street)
  if (!st) return null
  const locs = await locations(slug, st.ID)
  if (!locs.length) return null
  const cfg = { vendor: 'insertit' as const, client: slug, strasseId: st.ID, street: st.Name }
  const list = {
    supported: true as const,
    town: town.name,
    street: st.Name,
    needsHouseNumber: true,
    hausNrList: locs.map((l) => ({ id: l.ID, nr: l.Text })),
    config: cfg,
  }

  const want = (addr.houseNumber || '').trim()
  const parts = splitNr(want)
  if (!parts) return list
  const hits = locs.filter((l) => exact(l, want) || inSpan(l, parts))
  if (!hits.length) return list
  const merged = hits.length > 1 ? await merge(slug, hits) : hits
  if (!merged) return { ...list, hausNrList: hits.map((l) => ({ id: l.ID, nr: l.Text })) }
  // A location with no pickups this year is not a calendar to connect.
  if (!(await fetchYear(slug, String(merged[0].ID), new Date().getUTCFullYear()).catch(() => '')).includes('BEGIN:VEVENT')) return list
  return {
    supported: true, town: town.name, street: st.Name,
    config: { ...cfg, hnr: want, hnrId: merged.map((l) => l.ID).join('+') },
  }
}

async function readIit(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const slug = cfg.client
  // One location id, or several joined by "+" when a house is served by more
  // than one (see `merge`). A picked chip is always a single id.
  const key = cfg.hnrId != null ? String(cfg.hnrId) : ''
  if (!slug || !/^\d{1,9}(\+\d{1,9}){0,5}$/.test(key)) throw new Error('reconnect_required')
  const y = new Date().getUTCFullYear()
  const ids = key.split('+')
  const years = await Promise.all(ids.flatMap((id) => [fetchYear(slug, id, y), fetchYear(slug, id, y + 1).catch(() => '')]))
  // The current year is always published; a location without it is gone.
  if (ids.some((_, i) => !years[2 * i].includes('BEGIN:VEVENT'))) throw new Error('reconnect_required')
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const ev of years.flatMap((ics) => events(ics, `${slug}-${key}`, cfg.label))) {
    if (seen.has(ev.uid)) continue
    seen.add(ev.uid)
    out.push(ev)
  }
  return out
}

function towns(p: AbfallProvider): Town[] {
  return p.client && p.town ? [{ vendor: 'insertit', name: p.town, provider: p.id, client: p.client }] : []
}

export const adapter: VendorAdapter = {
  family: 'insertit',
  towns,
  probe: probeIit,
  read: readIit,
}
