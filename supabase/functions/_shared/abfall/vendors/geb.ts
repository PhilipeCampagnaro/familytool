// abfall/vendors/geb.ts — GEB Göttinger Entsorgungsbetriebe — the city's own
// Abfuhrkalender on geb-goettingen.de, one iCalendar per address.

import {
  type AbfallConfig,
  type AbfallProvider,
  dayEvents,
  fetchWithTimeout,
  type GeoAddress,
  icsDays,
  normStreet,
  type ResolveResult,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── GEB Göttingen (abfuhr.geb-goettingen.de/<year>/) ─────────────────────────
//
//   GET  geb-goettingen.de/…/abfuhrkalender/   every street, as JSON inside the
//                                              page: const strassen = JSON.parse("{…}")
//   GET  abfuhr.geb-goettingen.de/<y>/forward.php?str=<street>&nr=<nr>&year=<y>
//                                              text/calendar for that address
//
// **Not the Landkreis Göttingen's abfall.io calendar**, which lists every
// Restmüll rhythm side by side: the city runs its own, and it answers with the
// bins registered at the house, so there is nothing to ask. There is no list
// of house numbers — a number GEB does not know answers 200 with a calendar of
// no events, and so does a house whose bins are registered under a neighbour's
// number (GEB's own page says to try one). Either way the household is asked for
// the number rather than handed a guess. The year is in the path and next
// year's answers 404 until GEB publishes it. Titles read "[GEB] Abfuhr der
// Restmülltonne"; DTSTART is a floating 05:00.
const PAGE = 'https://www.geb-goettingen.de/abfall/abfallwirtschaft-in-der-stadt-goettingen/abfuhrkalender/'
const ICS = 'https://abfuhr.geb-goettingen.de'

async function streets(): Promise<string[]> {
  const res = await fetchWithTimeout(PAGE, { headers: { 'User-Agent': UA, Accept: 'text/html' } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const m = (await res.text()).match(/const strassen = JSON\.parse\("((?:[^"\\]|\\.)*)"\)/)
  if (!m) throw new Error('abfall upstream: no GEB street list')
  return Object.values(JSON.parse(JSON.parse(`"${m[1]}"`)) as Record<string, string>)
}

async function yearIcs(street: string, nr: string, year: number): Promise<string> {
  const q = new URLSearchParams({ str: street, nr, year: String(year) })
  const res = await fetchWithTimeout(`${ICS}/${year}/forward.php?${q}`, { headers: { 'User-Agent': UA, Accept: 'text/calendar' } })
  if (res.status === 404) return ''
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return res.text()
}

/// "[GEB] Abfuhr der Restmülltonne" -> "Restmülltonne", "… des gelben Sacks" -> "Gelber Sack".
function title(summary: string): string {
  const t = summary.replace(/^\[GEB\]\s*/, '').replace(/^Abfuhr (der|des)\s+/i, '').trim()
  return /^gelben Sacks?$/i.test(t) ? 'Gelber Sack' : t.charAt(0).toUpperCase() + t.slice(1)
}

const cleanNr = (s: string) => s.replace(/\s+/g, '').toLowerCase()

async function probeGeb(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const target = normStreet(addr.street)
  const street = (await streets()).find((s) => normStreet(s) === target)
  if (!street) return null
  const cfg = { vendor: 'geb' as const, street }
  const nr = cleanNr(addr.houseNumber || '')
  if (/^\d{1,4}[a-z]?$/.test(nr)) {
    const ics = await yearIcs(street, nr, new Date().getUTCFullYear())
    if (icsDays(ics).length) return { supported: true, town: town.name, street, config: { ...cfg, hnrId: nr } }
  }
  return { supported: true, town: town.name, street, needsHouseNumber: true, config: cfg }
}

async function readGeb(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const street = (cfg.street || '').trim()
  const nr = cleanNr(cfg.hnrId != null ? String(cfg.hnrId) : '')
  if (!street || street.length > 80 || !/^\d{1,4}[a-z]?$/.test(nr)) throw new Error('reconnect_required')
  const y = new Date().getUTCFullYear()
  const [now, next] = await Promise.all([yearIcs(street, nr, y), yearIcs(street, nr, y + 1).catch(() => '')])
  const rows = [...icsDays(now), ...icsDays(next)].map(({ day, title: s }) => ({ day, title: title(s) }))
  if (!rows.length) throw new Error('reconnect_required')
  return dayEvents(rows, `abfall:geb:${normStreet(street)}-${nr}`, cfg.label ?? null)
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'geb', name: p.town || 'Göttingen', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'geb',
  towns,
  probe: probeGeb,
  read: readGeb,
}
