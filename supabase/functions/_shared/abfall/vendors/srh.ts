// abfall/vendors/srh.ts — Stadtreinigung Hamburg — one unsigned POST turns a street into every house on it.

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

// ── Stadtreinigung Hamburg ──────────────────────────────────────────────────
//
// The simplest of the city adapters, and the only one that hands over a house
// list. One unsigned POST and one plain GET:
//
//   1. POST /abfuhrkalender?…[action]=addresses -> every street whose name
//      starts with the query, each carrying **all** its houses with an `hnId`.
//   2. GET backend.stadtreinigung.hamburg/…/abholtermine.ics?hnIds=<id>.
//
// The `cHash` in the form's action is TYPO3's usual signature and the endpoint
// answers without it, so there is no form to walk — unlike München, where the
// same framework signs the year and forces one.
//
// **The street search does not fold anything.** It is a literal, case-
// insensitive prefix match: "Fränkelstraße" finds nothing, because the city
// spells it "Fraenkelstraße", and "Osterstrasse" finds nothing because the city
// writes "Osterstraße". The geocoder picks whichever spelling OSM holds, so the
// query is re-asked in each written form of the name (`hhSpellings`) until one
// answers. Folding both sides afterwards, the way every other vendor here is
// matched, cannot help: the fold has to happen *before* the request.
//
// It is also capped at five results, so only the full street name is ever sent —
// a prefix would return the five alphabetically first neighbours and not the
// street itself ("Oster" yields Osterbaum … Osterbekweg, never Osterstraße).
//
// The window is a rolling four months from today rather than a calendar year,
// which makes Hamburg the one city here with no year-end at all: today's feed
// already reaches into January 2027.
const SRH_ORIGIN = 'https://www.stadtreinigung.hamburg'

const SRH_ADDRESSES =
  `${SRH_ORIGIN}/abfuhrkalender?tx_srh_pickups%5Baction%5D=addresses&tx_srh_pickups%5Bcontroller%5D=PickUps&type=10002`

const SRH_ICS = 'https://backend.stadtreinigung.hamburg/kalender/abholtermine.ics'

interface SrhHouse { hnId: number; name: string }

interface SrhStreet { name: string; hnIds?: SrhHouse[] }

async function srhAddresses(query: string): Promise<SrhStreet[]> {
  // Fewer than three characters is answered with an empty list by the server,
  // so there is nothing to gain by asking.
  if (query.trim().length < 3) return []
  const res = await fetchWithTimeout(SRH_ADDRESSES, {
    method: 'POST',
    headers: {
      'User-Agent': UA,
      'Content-Type': 'application/x-www-form-urlencoded',
      Accept: 'application/json, */*',
      Origin: SRH_ORIGIN,
    },
    body: new URLSearchParams({ 'tx_srh_pickups[street]': query.trim() }).toString(),
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const val = await res.json().catch(() => null)
  return Array.isArray(val) ? val as SrhStreet[] : []
}

/// The vendor's own row for this street, or null when Hamburg has no such
/// street. Unlike Köln's, this search genuinely says no.
async function srhFindStreet(street: string): Promise<SrhStreet | null> {
  const target = normStreet(street)
  if (!target) return null
  for (const spelling of germanSpellings(street)) {
    const rows = await srhAddresses(spelling).catch(() => [] as SrhStreet[])
    const hit = rows.find((r) => normStreet(r.name || '') === target)
    if (hit) return hit
  }
  return null
}

const srhKey = (s: string) => (s || '').trim().toLowerCase().replace(/\s+/g, '')

/// Does this house entry cover the number the household gave, and how tightly?
///
/// Hamburg lists the *collection points*, so a row is regularly a span of houses
/// — "9-11", "30-35", "4-4A" — and the household's own number is inside one
/// rather than equal to it. Returns the width of the span (0 for a single
/// house), or null when it does not cover the number at all.
function srhRangeCovers(name: string, want: string): { span: number; lettered: boolean } | null {
  const m = srhKey(name).match(/^(\d+)([a-z]?)-(\d+)([a-z]?)$/)
  const t = srhKey(want).match(/^(\d+)([a-z]?)$/)
  if (!m || !t) return null
  const lo = Number(m[1]), hi = Number(m[3]), num = Number(t[1])
  if (num < lo || num > hi) return null
  // "4-4A" and "7a-7c" are one house split by letter rather than a run of
  // houses, so there the letter is the range and has to be inside it.
  const lettered = !!(m[2] || m[4])
  if (lettered && t[2] && !(t[2] >= (m[2] || 'a') && t[2] <= (m[4] || 'z'))) return null
  return { span: hi - lo, lettered }
}

/// The one collection point this address belongs to, or undefined when Hamburg
/// does not say which.
///
/// Exact names are tried across the whole street first, because both forms
/// coexist on one street: Fraenkelstraße has "1-3" **and** a separate "2", and a
/// family at number 2 belongs to the latter.
///
/// Spans overlap, and that is the trap. Winterhuder Weg lists "4-10" and
/// "7a-7c", two different collection points that both contain number 7, so
/// taking the first match would have filed half that street under whichever row
/// the vendor happened to return first. A letter settles it — 7b is in 7a-7c and
/// nothing else — and where nothing settles it the household is asked, which
/// here costs only a dropdown because this vendor hands over every house on the
/// street.
function srhPickHouse(houses: SrhHouse[], want: string): SrhHouse | undefined {
  const w = srhKey(want)
  if (!w) return undefined
  const exact = houses.find((h) => srhKey(h.name || '') === w)
  if (exact) return exact
  const hits = houses
    .map((h) => ({ h, r: srhRangeCovers(h.name || '', w) }))
    .filter((x): x is { h: SrhHouse; r: { span: number; lettered: boolean } } => x.r !== null)
  if (hits.length === 1) return hits[0].h
  // Several spans claim the number: only a letter can break the tie.
  const lettered = /[a-z]$/.test(w) ? hits.filter((x) => x.r.lettered) : []
  return lettered.length === 1 ? lettered[0].h : undefined
}

/// An id that is merely unknown answers with a **valid, empty** calendar rather
/// than an error, exactly as Köln's does, so "it parsed" is not "it works".
async function srhHasDates(hnId: number | string): Promise<boolean> {
  const ics = await srhFetchIcs(hnId).catch(() => '')
  return ics.includes('BEGIN:VEVENT')
}

async function srhFetchIcs(hnId: number | string): Promise<string> {
  const res = await fetchWithTimeout(`${SRH_ICS}?hnIds=${encodeURIComponent(String(hnId))}`, {
    headers: { 'User-Agent': UA, Accept: 'text/calendar, */*' },
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return (await res.text()).replace(/^﻿/, '')
}

const srhHouseList = (s: SrhStreet) =>
  (s.hnIds || []).filter((h) => h && h.hnId).map((h) => ({ id: h.hnId, nr: (h.name || '').trim() }))

async function searchStreetsSrh(query: string): Promise<StreetOption[]> {
  const rows = await srhAddresses(query)
  return rows
    .filter((r) => (r.name || '').trim())
    .map((r) => ({
      name: r.name.trim(),
      hausNrList: srhHouseList(r),
      config: { vendor: 'srh' as const, street: r.name.trim() },
    }))
}

async function probeSrh(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const hit = await srhFindStreet(addr.street)
  if (!hit) return null
  const street = (hit.name || addr.street).trim()
  const houses = hit.hnIds || []

  const want = (addr.houseNumber || '').trim()
  const house = want ? srhPickHouse(houses, want) : undefined
  if (house && await srhHasDates(house.hnId).catch(() => false)) {
    return {
      supported: true,
      town: town.name,
      street,
      config: { vendor: 'srh', street, hnrId: house.hnId, hnr: (house.name || '').trim() },
    }
  }

  // The street is Hamburg's but this house is not one of its collection points
  // — or the address came without a number. Hand over the list rather than a
  // text field: this is the one vendor that knows every house on the street, so
  // the household recognises theirs instead of guessing at the spelling of
  // "U-Bahn / 1" or which span covers number 33.
  return {
    supported: true,
    town: town.name,
    street,
    needsHouseNumber: true,
    hausNrList: srhHouseList(hit),
    config: { vendor: 'srh', street },
  }
}

async function readSrh(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const id = String(cfg.hnrId ?? '')
  if (!/^[0-9]{1,9}$/.test(id)) throw new Error('reconnect_required')
  const ics = await srhFetchIcs(id)
  if (!ics.includes('BEGIN:VEVENT')) return []
  const thisYear = new Date().getUTCFullYear()
  const start = new Date(Date.UTC(thisYear - 1, 0, 1))
  const end = new Date(Date.UTC(thisYear + 2, 0, 1))
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const ev of parseIcs(ics, start, end)) {
    // "Abfuhr schwarze Restmülltonne" -> "Schwarze Restmülltonne". The bin's own
    // name is the whole content of the row and the colour is matched out of it,
    // so only the word that is true of every entry is dropped.
    const base = ev.title.replace(/^\s*Abfuhr\s+/i, '').trim() || ev.title.trim() || 'Abfuhr'
    const title = base.charAt(0).toUpperCase() + base.slice(1)
    const dayKey = `${ev.startsAt.slice(0, 10)}:${title}`
    if (seen.has(dayKey)) continue
    seen.add(dayKey)
    out.push({
      ...ev,
      uid: `abfall:srh:${id}:${dayKey}`,
      title,
      // "Die Abholung erfolgt ab 6:00 Uhr" — the one description in any of these
      // feeds that tells the household something they need the night before.
      notes: ev.notes,
      location: cfg.label ?? ev.location ?? null,
    })
  }
  return out
}

function towns(p: AbfallProvider): Town[] {
  // One city; streets are searched live and the address validated by the probe.
  return [{ vendor: 'srh', name: p.town || 'Hamburg', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'srh',
  towns,
  searchStreets: (_town, query) => searchStreetsSrh(query),
  probe: probeSrh,
  read: readSrh,
}
