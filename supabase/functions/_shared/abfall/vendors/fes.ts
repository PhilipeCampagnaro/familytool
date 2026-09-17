// abfall/vendors/fes.ts — FES Frankfurt am Main — address search by id, then the official ICS export.

import {
  type AbfallConfig,
  type AbfallProvider,
  fetchWithTimeout,
  type GeoAddress,
  getJson,
  normStreet,
  parseIcs,
  type ResolveResult,
  type StreetOption,
  streetSpellings,
  streetStem,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── FES (Frankfurt am Main) ──────────────────────────────────────────────────
//
// frankfurtplus.de is a Laravel/Inertia site with two keyless JSON GETs behind
// its address box, and one ICS per address:
//
//   /api/addresses/search?query=<text>        streets, or addresses once the
//                                             text carries a house number
//   /api/addresses/search?street_code=<code>  every house number of one street
//   /abfallkalender/<address id>/ical         that address's calendar
//
// Frankfurt plans per HOUSE like Berlin — Frankenallee 2 reads 156 pickups and
// no. 20 reads 130 — so an address without a number is answered
// `needsHouseNumber` rather than guessed at.
//
// The site normalises "-straße" to "-str." inside its own search, so the
// geocoder's spelling goes in unchanged and no `streetSpellings` dance is
// needed here.
//
// **The postcode is checked, and that is not pedantry.** Frankfurt (Oder) is a
// different city 500 km away in Brandenburg and "Bahnhofstraße" exists in both;
// without the check a Brandenburg address could be handed Hessen's bin days —
// the "Hain" inside "Friedrichshain" bug wearing a different hat. The town name
// in the registry is spelled out for the same reason.
const FES_BASE = 'https://frankfurtplus.de'

interface FesAddress {
  id: number
  street?: string
  house_number?: string
  postal_code?: string
  label?: string
  street_code?: string
}

async function fesSearch(params: Record<string, string>): Promise<FesAddress[]> {
  const rows = await getJson(
    `${FES_BASE}/api/addresses/search?${new URLSearchParams(params)}`,
  ) as FesAddress[]
  return Array.isArray(rows) ? rows : []
}

// A row is a street rather than an address when it carries no house number.
async function searchStreetsFes(query: string): Promise<StreetOption[]> {
  const q = query.trim()
  if (!q) return []
  const seen = new Set<string>()
  const out: StreetOption[] = []
  for (const r of await fesSearch({ query: q })) {
    const name = (r.street || '').trim()
    if (!name || r.house_number || seen.has(name.toLowerCase())) continue
    seen.add(name.toLowerCase())
    out.push({
      name,
      config: { vendor: 'fes', street: name, strasseId: r.street_code },
    })
  }
  return out
}

async function probeFes(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const plz = (addr.postcode || '').trim()
  const hnr = (addr.houseNumber || '').trim()

  if (hnr) {
    const rows = await fesSearch({ query: `${addr.street} ${hnr}` })
    // The search is a prefix match, so "2" also answers 20, 22, 24 — only the
    // row whose number is exactly the one asked for is this house.
    const exact = rows.filter((r) => (r.house_number || '').toLowerCase() === hnr.toLowerCase())
    const matching = plz ? exact.filter((r) => (r.postal_code || '') === plz) : exact
    if (matching.length === 1) {
      const pick = matching[0]
      return {
        supported: true,
        town: town.name,
        street: (pick.street || addr.street).trim(),
        config: {
          vendor: 'fes', street: (pick.street || addr.street).trim(),
          strasseId: pick.street_code, hnrId: pick.id, hnr: pick.house_number,
        },
      }
    }
    // One number, several entries (a street crossing postcodes, an "a"/"b"
    // split): the rows themselves become the chips.
    if (matching.length > 1) {
      return {
        supported: true,
        town: town.name,
        street: (matching[0].street || addr.street).trim(),
        needsHouseNumber: true,
        hausNrList: matching.slice(0, 40).map((r) => ({ id: r.id, nr: r.label || r.house_number || '' })),
        config: { vendor: 'fes', street: (matching[0].street || addr.street).trim(), hnr },
      }
    }
    // A postcode that answered nothing is the Frankfurt (Oder) case: the street
    // name exists here, the address does not. Not ours.
    if (plz && exact.length && !matching.length) return null
  }

  // No number, or a number this street does not carry: is the street ours?
  const streets = await searchStreetsFes(streetStem(addr.street))
  const target = normStreet(addr.street)
  const best =
    streets.find((s) => normStreet(s.name) === target) ||
    streets.find((s) => {
      const n = normStreet(s.name)
      return n.includes(target) || target.includes(n)
    })
  if (!best) return null
  // 225 house numbers on one street is a list, not a row of chips, so this asks
  // for the number to be typed instead of offering them.
  return { supported: true, town: town.name, street: best.name, needsHouseNumber: true, config: best.config }
}

async function readFes(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const id = String(cfg.hnrId ?? '')
  if (!/^[0-9]{1,12}$/.test(id)) throw new Error('reconnect_required')
  const res = await fetchWithTimeout(`${FES_BASE}/abfallkalender/${id}/ical`, {
    headers: { 'User-Agent': UA, Accept: 'text/calendar, */*' },
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const ics = (await res.text()).replace(/^\uFEFF/, '')
  if (!ics.includes('BEGIN:VEVENT')) return []
  const thisYear = new Date().getUTCFullYear()
  const start = new Date(Date.UTC(thisYear - 1, 0, 1))
  const end = new Date(Date.UTC(thisYear + 2, 0, 1))
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const ev of parseIcs(ics, start, end)) {
    // "Frankenallee 2 : Restabfall-Abholung" -> "Restabfall". The address is in
    // every summary because the file is named after it; classifyWaste on the
    // client needs the bin, not the street.
    const title = ev.title.replace(/^.*?\s:\s/, '').replace(/-Abholung\s*$/i, '').trim() || 'Abfuhr'
    const dayKey = `${ev.startsAt.slice(0, 10)}:${title}`
    if (seen.has(dayKey)) continue
    seen.add(dayKey)
    out.push({
      ...ev,
      uid: `abfall:fes:${id}:${dayKey}`,
      title,
      notes: null,
      location: cfg.label ?? null,
    })
  }
  return out
}

function towns(p: AbfallProvider): Town[] {
  // One city; streets are searched live and the address validated by the probe.
  return [{ vendor: 'fes', name: p.town || 'Frankfurt am Main', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'fes',
  towns,
  searchStreets: (_town, query) => searchStreetsFes(query),
  probe: probeFes,
  read: readFes,
}
