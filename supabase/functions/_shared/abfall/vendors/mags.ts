// abfall/vendors/mags.ts — mags Mönchengladbacher Abfall-, Grün- und
// Straßenbetriebe — the city's own Online-Abfuhrkalender on mags.de.

import {
  type AbfallConfig,
  type AbfallProvider,
  dayEvents,
  fetchWithTimeout,
  type GeoAddress,
  JSON_HEADERS,
  normStreet,
  type ResolveResult,
  restRhythm,
  type SyncedEvent,
  type Town,
  type VendorAdapter,
} from "../core.ts";

// ── mags (mags.de/proxy/) ────────────────────────────────────────────────────
//
//   GET  /proxy/proxy_streets.php   {"data": ["Aachener Straße", …]}
//   GET  /proxy/proxy_dates.php?street_name=&building_number=&building_number_addition=
//        &start_year=&end_year=&start_month=1&end_month=12&turnus=<1|2|4>
//        {"data": [{"type": "grau", "day": 13, "month": 1, "year": 2026}, …]}
//
// **The Restmüll rhythm is a request parameter, not a line of the answer.**
// mags' page asks "Nach Abholrhythmus filtern" — 1-, 2- or 4-wöchentlich — and
// `turnus` changes the grey bin's dates and nothing else. So the read asks all
// three and titles each "Restmüll: <rhythm>", and the household's pick keeps
// one, as for every vendor that prints its rhythms side by side. An address
// mags does not know answers the street's plan, so the number is asked for but
// cannot be checked. Next year's dates appear a month at a time from December.
const BASE = 'https://mags.de/proxy'

const TURNUS: Record<number, string> = { 1: 'Wöchentlich', 2: '2-wöchentlich', 4: '4-wöchentlich' }

/// mags' colour keys, in the words of its own ICS export.
const BINS: Record<string, string> = {
  grau: 'Restmüll',
  blau: 'Altpapier',
  braun: 'Bioabfall',
  gelb: 'Verpackungen',
  elektro: 'Elektrokleingeräte-Sammlung',
  'grün': 'Grünschnitt',
  tan: 'Weihnachtsbäume',
}

async function streets(): Promise<string[]> {
  const res = await fetchWithTimeout(`${BASE}/proxy_streets.php`, { headers: JSON_HEADERS })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const data = (await res.json() as { data?: unknown }).data
  return Array.isArray(data) ? data.filter((s): s is string => typeof s === 'string') : []
}

interface Row { type: string; day: number; month: number; year: number }

async function dates(street: string, nr: string, add: string, year: number, turnus: number): Promise<Row[]> {
  const q = new URLSearchParams({
    building_number: nr, building_number_addition: add, street_name: street,
    start_year: String(year), end_year: String(year), start_month: '1', end_month: '12', turnus: String(turnus),
  })
  const res = await fetchWithTimeout(`${BASE}/proxy_dates.php?${q}`, { headers: JSON_HEADERS })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const data = (await res.json() as { data?: unknown }).data
  return Array.isArray(data) ? data as Row[] : []
}

/// "12a" -> ["12", "a"], "12 A" -> ["12", "a"]. Null for anything that is not a house number.
function splitNr(s: string): [string, string] | null {
  const m = s.replace(/\s+/g, '').toLowerCase().match(/^(\d{1,4})([a-z]?)$/)
  return m ? [m[1], m[2]] : null
}

async function probeMags(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const target = normStreet(addr.street)
  const street = (await streets()).find((s) => normStreet(s) === target)
  if (!street) return null
  const cfg = { vendor: 'mags' as const, street }
  const nr = splitNr(addr.houseNumber || '')
  if (!nr) return { supported: true, town: town.name, street, needsHouseNumber: true, config: cfg }
  return { supported: true, town: town.name, street, config: { ...cfg, hnrId: nr.join('') } }
}

async function readMags(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const street = (cfg.street || '').trim()
  const nr = splitNr(cfg.hnrId != null ? String(cfg.hnrId) : '')
  if (!street || street.length > 80 || !nr) throw new Error('reconnect_required')
  const y = new Date().getUTCFullYear()
  const asks = [1, 2, 4].flatMap((t) => [y, y + 1].map((year) => ({ t, year })))
  const answers = await Promise.all(asks.map(({ t, year }) =>
    dates(street, nr[0], nr[1], year, t).catch((e) => {
      if (year === y) throw e
      return [] as Row[]
    }).then((rows) => ({ t, rows }))))
  const out: Array<{ day: string; title: string }> = []
  for (const { t, rows } of answers) {
    for (const r of rows) {
      if (!r || typeof r.type !== 'string') continue
      // Every bin but the grey one is the same whatever the turnus: take it once.
      if (r.type === 'grau' ? false : t !== 2) continue
      const bin = BINS[r.type] ?? r.type.charAt(0).toUpperCase() + r.type.slice(1)
      const day = `${r.year}-${String(r.month).padStart(2, '0')}-${String(r.day).padStart(2, '0')}`
      out.push({ day, title: r.type === 'grau' ? `${bin}: ${TURNUS[t]}` : bin })
    }
  }
  if (!out.length) throw new Error('reconnect_required')
  return dayEvents(out, `abfall:mags:${normStreet(street)}-${nr.join('')}`, cfg.label ?? null)
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'mags', name: p.town || 'Mönchengladbach', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'mags',
  towns,
  probe: probeMags,
  rhythm: restRhythm,
  read: readMags,
}
