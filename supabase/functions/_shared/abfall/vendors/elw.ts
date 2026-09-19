// abfall/vendors/elw.ts — ELW Entsorgungsbetriebe der Landeshauptstadt
// Wiesbaden — the city's own street/house search and a per-house ICS stream.

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

// ── ELW Wiesbaden ───────────────────────────────────────────────────────────
//
//   GET elw.de/abfallkalender?type=4712&sword=<prefix>
//        -> [{"street":"Hauptstraße","city":"Wiesbaden-Igstadt"}, …]
//   GET elw.de/abfallkalender?type=4713&street=<street>, <city>&housenumber=
//        -> [{"objid":"{2E65…}","housenumber":"3","housenumberadd":"-11"}, …]
//   GET elw.de/fileadmin/elw/php/googlecal_<objid without braces>_stream.ics
//
// The last is the "subscribe in Google" link the page builds itself. `city` is
// the district and tells same-named streets apart — and it includes **Mainz-
// Kastel, -Kostheim and -Amöneburg**, which are Wiesbaden's and served by ELW
// though the name says Mainz. A house entry can be a span: "3" + "-11" is 3–11,
// on the side of its first number. An unknown objid is an empty VCALENDAR.
// Rhythm is fixed per house; the stream runs January to early January.
const PAGE = 'https://www.elw.de/abfallkalender'

async function json<T>(params: Record<string, string>): Promise<T> {
  const res = await fetchWithTimeout(`${PAGE}?${new URLSearchParams(params)}`, {
    headers: { 'User-Agent': UA, Accept: 'application/json, */*' },
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return await res.json() as T
}

interface House { objid: string; housenumber: string; housenumberadd: string }

/// Does "3" + "-11" (or "10" + "a") hold the household's number?
function holds(h: House, want: string): boolean {
  const w = want.toLowerCase().replace(/\s+/g, '')
  const add = (h.housenumberadd || '').replace(/\s+/g, '')
  if (`${h.housenumber}${add}`.toLowerCase() === w) return true
  const span = add.match(/^-(\d+)$/)
  const n = parseInt(w, 10), from = parseInt(h.housenumber, 10)
  if (!span || isNaN(n) || isNaN(from)) return false
  return n >= from && n <= Number(span[1]) && n % 2 === from % 2
}

async function probeElw(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const target = normStreet(addr.street)
  const found = (await json<Array<{ street: string; city: string }>>({ type: '4712', sword: streetStem(addr.street).slice(0, 30) }))
    .filter((s) => normStreet(s.street) === target)
  if (!found.length) return null
  const street = found[0].street
  const all: Array<{ id: string; nr: string; house: House }> = []
  for (const s of found.slice(0, 6)) {
    const houses = await json<House[]>({ type: '4713', street: `${s.street}, ${s.city}`, housenumber: '' })
    const tag = found.length > 1 ? ` (${s.city.replace(/^(Wiesbaden|Mainz)-/, '')})` : ''
    for (const h of houses) {
      all.push({ id: h.objid.replace(/[{}]/g, ''), nr: `${h.housenumber}${(h.housenumberadd || '').replace(/\s+/g, '')}${tag}`, house: h })
    }
  }
  const cfg = { vendor: 'elw' as const, street }
  const want = (addr.houseNumber || '').trim()
  const fit = want ? all.filter((x) => holds(x.house, want)) : []
  if (fit.length === 1) return { supported: true, town: town.name, street, config: { ...cfg, hnrId: fit[0].id } }
  return {
    supported: true, town: town.name, street, needsHouseNumber: true,
    hausNrList: (fit.length ? fit : all).map(({ id, nr }) => ({ id, nr })),
    config: cfg,
  }
}

async function readElw(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const id = cfg.hnrId != null ? String(cfg.hnrId) : ''
  if (!/^[0-9A-Fa-f-]{36}$/.test(id)) throw new Error('reconnect_required')
  const res = await fetchWithTimeout(`https://www.elw.de/fileadmin/elw/php/googlecal_${id}_stream.ics`, {
    headers: { 'User-Agent': UA, Accept: 'text/calendar, */*' },
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const days = icsDays(await res.text())
  if (!days.length) throw new Error('reconnect_required')
  const rows = days.map((r) => ({ ...r, title: r.title.replace(/^ELW\s*-\s*/, '') }))
  return dayEvents(rows, `abfall:elw:${id.toLowerCase()}`, cfg.label ?? null)
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'elw', name: p.town || 'Wiesbaden', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'elw',
  towns,
  probe: probeElw,
  read: readElw,
}
