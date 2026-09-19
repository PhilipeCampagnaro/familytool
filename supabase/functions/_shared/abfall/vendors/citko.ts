// abfall/vendors/citko.ts — Universitätsstadt Siegen — the Abfallkalender on
// siegen.de, a TYPO3 page run on the `citko_abfall` extension.

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
  restRhythm,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── Siegen (citko_abfall on siegen.de) ───────────────────────────────────────
//
//   GET  …/abfallkalender              the form: every street as an <option>,
//                                      and TYPO3's signed hidden fields
//   POST <form action>                 strasse + hausnummer; the answer page
//                                      links an iCalendar for the address
//   GET  <that link>                   text/calendar, today to the year's end
//
// **The ICS link is signed** (`cHash`) and cannot be written by hand, so every
// read walks the form: three requests, none of them keyed on a session. The
// calendar lists Restmüll in each rhythm the address has — "Restmüll -
// 2-wöchentlich", "Restmüll - 4-wöchentlich" — side by side, and the household
// picks theirs. A number the city does not know still answers the street's
// plan, so the number is asked for and not checked.
const PAGE = 'https://www.siegen.de/leben-in-siegen/buergerservice/abfallentsorgung/abfallkalender'
const ORIGIN = 'https://www.siegen.de'
const P = 'tx_citkoabfall_abfallkalender'

interface Form { action: string; hidden: Array<[string, string]>; streets: string[] }

async function form(): Promise<Form> {
  const res = await fetchWithTimeout(PAGE, { headers: { 'User-Agent': UA, Accept: 'text/html' } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const html = await res.text()
  const f = html.match(/<form[^>]*id="citko-abfall-form"[^>]*action="([^"]*)"[^>]*>([\s\S]*?)<\/form>/)
  if (!f) throw new Error('abfall upstream: no Siegen form')
  const hidden = [...f[2].matchAll(/<input type="hidden" name="([^"]*)"[^>]*value="([^"]*)"/g)]
    .map((m) => [m[1], decodeEntities(m[2])] as [string, string])
  const select = f[2].match(/<select[^>]*id="strasse"[^>]*>([\s\S]*?)<\/select>/)?.[1] ?? ''
  const streets = [...select.matchAll(/<option value="([^"]+)"/g)].map((m) => decodeEntities(m[1]))
  return { action: decodeEntities(f[1]), hidden, streets }
}

async function yearIcs(street: string, nr: string): Promise<string> {
  const f = await form()
  const body = new URLSearchParams(f.hidden)
  body.set(`${P}[strasse]`, street)
  body.set(`${P}[hausnummer]`, nr)
  const res = await fetchWithTimeout(ORIGIN + f.action, {
    method: 'POST',
    headers: { 'User-Agent': UA, Accept: 'text/html', 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const link = (await res.text()).match(/href="([^"]*%5Baction%5D=ics[^"]*)"/)?.[1]
  if (!link) return ''
  const ics = await fetchWithTimeout(ORIGIN + decodeEntities(link), { headers: { 'User-Agent': UA, Accept: 'text/calendar' } })
  if (!ics.ok) throw new Error(`abfall upstream ${ics.status}`)
  return ics.text()
}

const cleanNr = (s: string) => s.replace(/\s+/g, '').toLowerCase()

async function probeCitko(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const target = normStreet(addr.street)
  const street = (await form()).streets.find((s) => normStreet(s) === target)
  if (!street) return null
  const cfg = { vendor: 'citko' as const, street }
  const nr = cleanNr(addr.houseNumber || '')
  if (!/^\d{1,4}[a-z]?$/.test(nr)) return { supported: true, town: town.name, street, needsHouseNumber: true, config: cfg }
  return { supported: true, town: town.name, street, config: { ...cfg, hnrId: nr } }
}

async function readCitko(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const street = (cfg.street || '').trim()
  const nr = cleanNr(cfg.hnrId != null ? String(cfg.hnrId) : '')
  if (!street || street.length > 80 || !/^\d{1,4}[a-z]?$/.test(nr)) throw new Error('reconnect_required')
  const rows = icsDays(await yearIcs(street, nr))
  if (!rows.length) throw new Error('reconnect_required')
  return dayEvents(rows, `abfall:citko:${normStreet(street)}-${nr}`, cfg.label ?? null)
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'citko', name: p.town || 'Siegen', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'citko',
  towns,
  probe: probeCitko,
  rhythm: restRhythm,
  read: readCitko,
}
