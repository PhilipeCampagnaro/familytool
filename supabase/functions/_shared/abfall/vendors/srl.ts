// abfall/vendors/srl.ts — Stadtreinigung Leipzig — one keyless GET turns a street
// into every house on it, and the ICS hangs off the houses' position numbers.

import {
  type AbfallConfig,
  type AbfallProvider,
  fetchWithTimeout,
  type GeoAddress,
  germanSpellings,
  normStreet,
  parseIcs,
  type ResolveResult,
  type StreetOption,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── Stadtreinigung Leipzig ──────────────────────────────────────────────────
//
// Hamburg's shape, found on the city's own Abfallkalender page (an Alpine.js
// widget whose two endpoints sit in plain sight in its `x-data`):
//
//   1. GET /rest/Navision/Streets?search=<prefix>
//      -> {"results":[{"name":"Karl-Liebknecht-Straße","postalcode":"04275",
//          "district":"Südvorstadt","numbers":[{"number":"1 A",
//          "position_nos":["24157","45911",…]}, …]}]}
//   2. GET /wir-kommen-zu-ihnen/abfallkalender/ical.ics
//          ?position_nos=<comma-joined>&name=<label>&time_allday=true&mode=download
//
// **A house is several position numbers, and the calendar is all of them.** Each
// is one container at that address — the page's own dropdown joins them with a
// comma and so do we — which is also why one Friday carries four identical
// "Restabfalltonne" rows. They are collapsed to one per bin per day.
//
// **`name` and `mode` are required, and leaving them out does not say so.** The
// server answers "Curently in Maintenance Mode." with a 200, which is the same
// text it would show for a genuine outage. So the text is never read as an
// error; the absence of a VEVENT is.
//
// **The UIDs are random on every request** (`sabre-vobject-<uuid4>`), so a uid
// taken from the feed would make every refresh look like a new set of pickups.
// Ours is built from the houses and the day instead.
//
// The search is a case-insensitive prefix match that folds "ss" into "ß" but
// not "oe" into "ö" ("Loessniger" finds nothing, "Löß" finds Lößniger Straße),
// so the name is re-asked in each written form. It also stops matching at some
// punctuation — "Straße des 18. Oktober" in full finds nothing, "Straße des"
// finds it — so a shorter prefix is tried last and the rows are always checked
// against the geocoded street, never taken on trust. It genuinely says no
// ("Quatschstraße" -> zero results).
//
// Street names are unique across the city, incorporated villages included
// (one Hauptstraße, in Holzhausen; one Dorfstraße, in Althen-Kleinpösna), so the
// postcode is a tie-breaker, not a requirement.
//
// The window runs from today to the last pickup Leipzig has published, which on
// 2026-09-18 is 24 December: a calendar-year vendor. `year`, `date` and friends
// are ignored by both endpoints, so next year arrives when the city publishes it
// and not before — nothing is stored, so the next refresh after that picks it up.
const SRL_ORIGIN = 'https://stadtreinigung-leipzig.de'
const SRL_STREETS = `${SRL_ORIGIN}/rest/Navision/Streets`
const SRL_ICS = `${SRL_ORIGIN}/wir-kommen-zu-ihnen/abfallkalender/ical.ics`

interface SrlHouse { number: string; position_nos?: string[] }

interface SrlStreet { name: string; postalcode?: string | null; district?: string | null; numbers?: SrlHouse[] }

async function srlStreets(query: string): Promise<SrlStreet[]> {
  const q = query.trim()
  if (q.length < 3) return []
  const res = await fetchWithTimeout(`${SRL_STREETS}?search=${encodeURIComponent(q)}`, {
    headers: { 'User-Agent': UA, Accept: 'application/json, */*' },
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const val = await res.json().catch(() => null) as { results?: unknown } | null
  return Array.isArray(val?.results) ? val!.results as SrlStreet[] : []
}

/// Every way to ask for this street, most specific first: each written form of
/// the whole name, then the part before the first digit or full stop, which is
/// where the search gives up ("Straße des 18. Oktober" -> "Straße des").
function srlQueries(street: string): string[] {
  const out = germanSpellings(street)
  const head = street.split(/[0-9.]/)[0].trim()
  if (head.length >= 3 && !out.includes(head.toLowerCase())) out.push(head.toLowerCase())
  return out
}

/// The vendor's own row for this street, or null when Leipzig has no such street.
async function srlFindStreet(street: string, postcode?: string): Promise<SrlStreet | null> {
  const target = normStreet(street)
  if (!target) return null
  for (const q of srlQueries(street)) {
    const rows = await srlStreets(q).catch(() => [] as SrlStreet[])
    const hits = rows.filter((r) => normStreet(r.name || '') === target)
    if (hits.length) return hits.find((r) => postcode && r.postalcode === postcode) ?? hits[0]
  }
  return null
}

// "1 A" and "1a" are the same house.
const srlKey = (s: string) => (s || '').trim().toLowerCase().replace(/\s+/g, '')

// The id the ICS is read with: the house's position numbers, comma-joined, and
// nothing else — it is sent back to Leipzig on every refresh.
const srlIds = (h: SrlHouse) =>
  (h.position_nos || []).filter((p) => /^[0-9]{1,9}$/.test(p)).join(',')

const srlHouseList = (s: SrlStreet) =>
  (s.numbers || [])
    .map((h) => ({ id: srlIds(h), nr: (h.number || '').trim() }))
    .filter((h) => h.id && h.nr)

async function srlFetchIcs(ids: string, name: string): Promise<string> {
  // `time_allday` is asked for explicitly: left out, every pickup arrives as an
  // "Restabfalltonne (Abholzeit)" block from 05:30 to 13:30, where every other
  // vendor here — and the bin row in Kalender — speaks in whole days.
  const q = new URLSearchParams({ position_nos: ids, name, time_allday: 'true', reminder: '0', mode: 'download' })
  const res = await fetchWithTimeout(`${SRL_ICS}?${q}`, {
    headers: { 'User-Agent': UA, Accept: 'text/calendar, */*' },
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return (await res.text()).replace(/^﻿/, '')
}

async function searchStreetsSrl(query: string): Promise<StreetOption[]> {
  const rows = await srlStreets(query)
  return rows
    .filter((r) => (r.name || '').trim())
    .map((r) => ({
      name: r.name.trim(),
      hausNrList: srlHouseList(r),
      config: { vendor: 'srl' as const, street: r.name.trim() },
    }))
}

async function probeSrl(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const hit = await srlFindStreet(addr.street, addr.postcode)
  if (!hit) return null
  const street = (hit.name || addr.street).trim()

  const want = srlKey(addr.houseNumber || '')
  const house = want ? (hit.numbers || []).find((h) => srlKey(h.number) === want) : undefined
  const ids = house ? srlIds(house) : ''
  if (house && ids) {
    const nr = house.number.trim()
    // An address that is listed but serviced some other way would connect a
    // calendar that stays empty forever, so a pickup has to be on it now.
    const ics = await srlFetchIcs(ids, `${street} ${nr}`).catch(() => '')
    if (ics.includes('BEGIN:VEVENT')) {
      return {
        supported: true,
        town: town.name,
        street,
        config: { vendor: 'srl', street, hnrId: ids, hnr: nr },
      }
    }
  }

  // The street is Leipzig's but the number is not one it lists, or none came
  // with the address. Leipzig knows every house on the street, so the household
  // picks theirs from the list rather than guessing how "1 A" is written.
  return {
    supported: true,
    town: town.name,
    street,
    needsHouseNumber: true,
    hausNrList: srlHouseList(hit),
    config: { vendor: 'srl', street },
  }
}

async function readSrl(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const ids = String(cfg.hnrId ?? '')
  if (!/^[0-9]{1,9}(,[0-9]{1,9})*$/.test(ids)) throw new Error('reconnect_required')
  const name = [cfg.street, cfg.hnr].filter(Boolean).join(' ') || 'Leipzig'
  const ics = await srlFetchIcs(ids, name)
  if (!ics.includes('BEGIN:VEVENT')) return []
  const thisYear = new Date().getUTCFullYear()
  const start = new Date(Date.UTC(thisYear - 1, 0, 1))
  const end = new Date(Date.UTC(thisYear + 2, 0, 1))
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const ev of parseIcs(ics, start, end)) {
    const title = ev.title.trim() || 'Abfuhr'
    const dayKey = `${ev.startsAt.slice(0, 10)}:${title}`
    if (seen.has(dayKey)) continue
    seen.add(dayKey)
    // Leipzig writes DTEND equal to DTSTART, a day that lasts no time at all;
    // RFC 5545's all-day event ends on the next date, as every other feed does.
    const endsAt = ev.allDay && ev.endsAt <= ev.startsAt
      ? new Date(Date.parse(ev.startsAt) + 86_400_000).toISOString()
      : ev.endsAt
    out.push({
      ...ev,
      endsAt,
      uid: `abfall:srl:${ids}:${dayKey}`,
      title,
      location: cfg.label ?? ev.location ?? null,
    })
  }
  return out
}

function towns(p: AbfallProvider): Town[] {
  // One city; streets are searched live and the address validated by the probe.
  return [{ vendor: 'srl', name: p.town || 'Leipzig', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'srl',
  towns,
  searchStreets: (_town, query) => searchStreetsSrl(query),
  probe: probeSrl,
  read: readSrl,
}
