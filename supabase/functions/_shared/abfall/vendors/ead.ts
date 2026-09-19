// abfall/vendors/ead.ts — EAD Eigenbetrieb für kommunale Aufgaben und
// Dienstleistungen Darmstadt — the Abfallkalender on ead.darmstadt.de.

import {
  type AbfallConfig,
  type AbfallProvider,
  dayEvents,
  fetchWithTimeout,
  type GeoAddress,
  type HausNr,
  normStreet,
  type ResolveResult,
  type RhythmTag,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── EAD Darmstadt (TYPO3 plugin, no session, no key) ─────────────────────────
//
//   GET  getStreets/?type=742394                 ["Rheinstraße 1-41, 2-38", "Rheinstraße 105", …]
//   GET  singleStreet/?type=742394&street=<e>    {"02.01.2026": ["PPK"], "09.01.2026": ["RM1","RM2","RM4"], …}
//                                                  — `[]` for a name it does not know
//
// This replaced MyMüll for Darmstadt (2026-09-19). EAD's page shows the MyMüll
// app badges beside its own calendar, which is why MyMüll was allowlisted, but
// the calendar and its ICS download are EAD's own (UIDs @ead.darmstadt.de).
//
// A long street is split into entries named for the numbers they cover — both
// sides written out ("1-41, 2-38"), an open end ("160-Ende, 201-Ende"), or one
// house ("105") — so the house number picks the entry. **The Restabfall rhythm
// is the household's**: every day carries RM1, RM2 and RM4 side by side, and the
// page has the reader tick the one matching the lid — schwarz weekly, orange
// every two weeks, rot every four. So the read writes all three and the
// household picks (RhythmChoice in abfall/core.ts).
//
// It serves the current year only; `year=` is ignored. The next one appears
// when EAD publishes it, as with every single-year vendor here.
const BASE = 'https://ead.darmstadt.de/unser-angebot/privathaushalte/abfallkalender'

const REST = 'Restabfall-Tonne'
const TITLES: Record<string, string> = {
  PPK: 'Grüne Altpapier-Tonne',
  WET: 'Gelbe Wertstoff-Tonne',
  BIO: 'Braune Bioabfall-Tonne',
  RM1: `${REST}: Wöchentlich (Deckel schwarz)`,
  RM2: `${REST}: 14-täglich (Deckel orange)`,
  RM4: `${REST}: 4-wöchentlich (Deckel rot)`,
}

async function get(path: string): Promise<unknown> {
  const res = await fetchWithTimeout(`${BASE}/${path}`, { headers: { 'User-Agent': UA, Accept: 'application/json' } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return JSON.parse(await res.text())
}

async function streets(): Promise<string[]> {
  const data = await get('getStreets/?type=742394')
  return Array.isArray(data) ? data.filter((s): s is string => typeof s === 'string') : []
}

// ── House numbers written into the entry's name ─────────────────────────────

/// "Rheinstraße 1-41, 2-38" -> ["Rheinstraße", "1-41, 2-38"]; "Achatweg" -> ["Achatweg", ""].
function split(entry: string): [string, string] {
  const m = entry.match(/^(.*?)\s+(\d.*)$/)
  return m ? [m[1].trim(), m[2].trim()] : [entry.trim(), '']
}

/// Does "1-41, 2-38" / "160-Ende, 201-Ende" / "62-96A" / "105" hold the number?
/// A span whose two ends share a parity is that side of the street. Null where
/// a part is written some other way — the household picks those.
function holds(part: string, nr: string): boolean | null {
  const want = nr.match(/^(\d+)([a-z]?)$/)
  if (!want) return null
  const n = Number(want[1]), letter = want[2]
  for (const bit of part.split(/\s*,\s*/).filter(Boolean)) {
    const r = bit.match(/^(\d+)([a-z]?)(?:\s*-\s*(?:(\d+)([a-z]?)|(Ende)))?$/i)
    if (!r) return null
    const lo = Number(r[1])
    if (!r[3] && !r[5]) {
      // A single house: "105" holds 105 and 105a, "7a" only 7a.
      if (n === lo && (!r[2] || r[2].toLowerCase() === letter)) return true
      continue
    }
    const hi = r[5] ? Infinity : Number(r[3])
    const side = r[5] ? null : lo % 2 === hi % 2 ? lo % 2 : null
    if (n >= lo && n <= hi && (side === null || n % 2 === side)) return true
  }
  return false
}

const cleanNr = (s: string) => s.replace(/\s+/g, '').toLowerCase()

async function probeEad(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const target = normStreet(addr.street)
  const hits = (await streets()).filter((e) => normStreet(split(e)[0]) === target)
  if (!hits.length) return null
  const street = split(hits[0])[0]
  // One entry for the whole street: the number changes nothing.
  if (hits.length === 1 && !split(hits[0])[1]) {
    return { supported: true, town: town.name, street, config: { vendor: 'ead', street, hnrId: hits[0] } }
  }
  const nr = cleanNr(addr.houseNumber || '')
  const fits = /^\d{1,4}[a-z]?$/.test(nr) ? hits.filter((e) => holds(split(e)[1], nr) === true) : []
  if (fits.length === 1) {
    return { supported: true, town: town.name, street, config: { vendor: 'ead', street, hnrId: fits[0] } }
  }
  // No number, or one no entry names: the household picks the entry.
  const hausNrList: HausNr[] = hits.map((e) => ({ id: e, nr: split(e)[1] || e }))
  return { supported: true, town: town.name, street, needsHouseNumber: true, hausNrList, config: { vendor: 'ead', street } }
}

function rhythmEad(title: string): RhythmTag | null {
  return title.startsWith(`${REST}: `) ? { bin: REST, option: title.slice(REST.length + 2) } : null
}

async function readEad(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const entry = cfg.hnrId != null ? String(cfg.hnrId) : ''
  if (!entry || entry.length > 120) throw new Error('reconnect_required')
  const data = await get(`singleStreet/?type=742394&street=${encodeURIComponent(entry)}`)
  const rows: Array<{ day: string; title: string }> = []
  if (data && typeof data === 'object' && !Array.isArray(data)) {
    for (const [date, codes] of Object.entries(data as Record<string, unknown>)) {
      const d = date.match(/^(\d{2})\.(\d{2})\.(\d{4})$/)
      if (!d || !Array.isArray(codes)) continue
      for (const c of codes) {
        const title = TITLES[String(c)]
        if (title) rows.push({ day: `${d[3]}-${d[2]}-${d[1]}`, title })
      }
    }
  }
  // `[]` is how EAD says it no longer knows the entry — a renamed street.
  if (!rows.length) throw new Error('reconnect_required')
  return dayEvents(rows, `abfall:ead:${normStreet(entry)}`, cfg.label ?? null)
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'ead', name: p.town || 'Darmstadt', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'ead',
  towns,
  probe: probeEad,
  rhythm: rhythmEad,
  read: readEad,
}
