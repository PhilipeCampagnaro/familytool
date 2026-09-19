// abfall/vendors/tsk.ts — Team Sauberes Karlsruhe — the city's own
// Abfuhrkalender form (web6.karlsruhe.de), which answers an ICS per address.

import {
  type AbfallConfig,
  type AbfallProvider,
  dayEvents,
  decodeEntities,
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

// ── TSK Karlsruhe ───────────────────────────────────────────────────────────
//
//   GET  …/akal_2024.php         the streets, as a JS array `strassen_liste`
//   POST …/akal_2024.php?hausnr= strasse_n=<street>&hausnr=<nr>&ical= iCalendar
//        -> text/calendar, X-WR-CALNAME "Abfuhrtermine Rheinstraße 20"
//
// There is no house list, and **the form never refuses**: an unknown street is
// quietly answered with the first street in the list (Abraham-Lincoln-Allee),
// and some unknown numbers with a catch-all span ("Durlacher Allee
// 110-9998Z") of mixed rhythms. So the street is matched against the list
// first, and the calendar is only believed when its name is the address that
// was asked for. Titles read "Restmüll, 14-täglich": the rhythm goes to the
// notes. The feed runs from today to 31 December.
const FORM = 'https://web6.karlsruhe.de/service/abfall/akal/akal_2024.php'

async function streets(): Promise<string[]> {
  const res = await fetchWithTimeout(FORM, { headers: { 'User-Agent': UA, Accept: 'text/html' } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const arr = (await res.text()).match(/var\s+strassen_liste\s*=\s*\[([\s\S]*?)\]/)?.[1] ?? ''
  return [...arr.matchAll(/'((?:[^'\\]|\\.)*)'/g)].map((m) => decodeEntities(m[1].replace(/\\'/g, "'")).trim())
}

async function calendar(street: string, nr: string): Promise<string> {
  const res = await fetchWithTimeout(`${FORM}?hausnr=`, {
    method: 'POST',
    headers: { 'User-Agent': UA, 'Content-Type': 'application/x-www-form-urlencoded', Accept: 'text/calendar, */*' },
    body: new URLSearchParams({ strasse_n: street, hausnr: nr, ical: ' iCalendar' }).toString(),
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return res.text()
}

/// The calendar is this address's, not the form's nearest guess.
function isFor(ics: string, street: string, nr: string): boolean {
  const name = ics.match(/X-WR-CALNAME:Abfuhrtermine\s+([^\r\n]*)/)?.[1]?.trim() ?? ''
  const norm = (s: string) => s.toLowerCase().replace(/\s+/g, '')
  return norm(name) === norm(`${street} ${nr}`)
}

async function probeTsk(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const target = normStreet(addr.street)
  const street = (await streets()).find((s) => normStreet(s) === target)
  if (!street) return null
  const nr = (addr.houseNumber || '').trim()
  const cfg = { vendor: 'tsk' as const, street }
  if (!nr) return { supported: true, town: town.name, street, needsHouseNumber: true, config: cfg }
  const ics = await calendar(street, nr)
  // A number the city does not know: ask again rather than take its catch-all.
  if (!isFor(ics, street, nr) || !icsDays(ics).length) {
    return { supported: true, town: town.name, street, needsHouseNumber: true, config: cfg }
  }
  return { supported: true, town: town.name, street, config: { ...cfg, hnr: nr } }
}

async function readTsk(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const street = (cfg.street || '').trim()
  const nr = String(cfg.hnr ?? cfg.hnrId ?? '').trim()
  if (!street || street.length > 80 || !/^[0-9][0-9a-zA-Z /-]{0,10}$/.test(nr)) throw new Error('reconnect_required')
  const ics = await calendar(street, nr)
  if (!isFor(ics, street, nr)) throw new Error('reconnect_required')
  const rows = icsDays(ics).map(({ day, title }) => {
    const [bin, ...rhythm] = title.split(/,\s*/)
    return { day, title: bin.trim(), notes: rhythm.join(', ') || null }
  })
  return dayEvents(rows, `abfall:tsk:${normStreet(street)}-${nr.toLowerCase().replace(/\s+/g, '')}`, cfg.label ?? null)
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'tsk', name: p.town || 'Karlsruhe', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'tsk',
  towns,
  probe: probeTsk,
  read: readTsk,
}
