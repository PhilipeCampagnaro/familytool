// abfall/vendors/sro.ts — Stadtentsorgung Rostock — the Abfuhrkalender on
// stadtentsorgung-rostock.de.

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
  streetStem,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── Stadtentsorgung Rostock (an eZ Publish form, no session needed) ──────────
//
//   GET  /service/ekalend_form_data_get_address?q=<2+ chars>&callback=cb
//          cb([{ "label": "Lange Str. ( 18055 ) ", "value": "Lange Str.", "zip": "18055" }, …])
//   POST /service/ekalend_form_data/1216/SearchByAddress
//          Input[address][street|no|zip|legit]  -> the result page, whose
//          hidden `address-key` is "AWI~99510-GEG~31097-GEG~99510"
//   GET  /service/ekalend_ical/(key)/<address key>[/(period)/year]
//
// **The search is behind a tick-box**: "Ich bin als Eigentümer, Mieter oder
// Beauftragter zur Abfrage der von mir angegebenen Adresse berechtigt." Without
// it the answer carries no key. What the box guards is the result page, which
// lists the address's container numbers and sizes; the read keeps none of that,
// only the ICS of the pickup days. The household connecting its own address in
// Aporah is the owner or tenant the box names, and we tick it on their behalf
// once, at connect; the key is stored and every later read is the ICS alone.
// Don't add a path that ticks it for anything but the address being connected.
//
// "year" is the calendar year and nothing past it, so the read also asks
// without a period — the next few dates, which cross New Year's Eve in
// December — and the two are merged. ("(period)/next" is a 500.)
const BASE = 'https://www.stadtentsorgung-rostock.de'
const KEY = /^[A-Z]{3}~\d+(?:-[A-Z]{3}~\d+)*$/

async function streets(q: string): Promise<Array<{ value: string; zip: string }>> {
  const u = `${BASE}/service/ekalend_form_data_get_address?q=${encodeURIComponent(q)}&name_startsWith=${encodeURIComponent(q)}&maxRows=40&callback=cb`
  const res = await fetchWithTimeout(u, { headers: { 'User-Agent': UA, Accept: 'text/javascript' } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const body = (await res.text()).trim().replace(/^cb\(/, '').replace(/\)\s*;?$/, '').replace(/,\s*\]$/, ']')
  try {
    const data = JSON.parse(body)
    return Array.isArray(data)
      ? data.filter((x) => typeof x?.value === 'string').map((x) => ({ value: decodeURIComponent(x.value), zip: String(x.zip ?? '') }))
      : []
  } catch {
    return []
  }
}

/// The address key, or '' when the Stadtentsorgung does not know the number.
async function addressKey(street: string, nr: string, zip: string): Promise<string> {
  const body = new URLSearchParams({
    'Input[address][street]': street, 'Input[address][no]': nr, 'Input[address][zip]': zip,
    'Input[address][legit]': 'on', SearchByAddress: 'Abfuhrtermine anzeigen',
  })
  const res = await fetchWithTimeout(`${BASE}/service/ekalend_form_data/1216/SearchByAddress`, {
    method: 'POST',
    headers: { 'User-Agent': UA, Accept: 'text/html', 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const key = decodeEntities((await res.text()).match(/id="address-key"[^>]*value="([^"]*)"/)?.[1] ?? '')
  return KEY.test(key) ? key : ''
}

const cleanNr = (s: string) => s.replace(/\s+/g, '')

async function probeSro(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const target = normStreet(addr.street)
  const stem = streetStem(addr.street)
  const hits = (await streets(stem.length >= 2 ? stem : addr.street)).filter((s) => normStreet(s.value) === target)
  if (!hits.length) return null
  // A name in two postcodes is two streets; the geocoder's postcode decides.
  const hit = hits.find((s) => s.zip === addr.postcode) ?? (hits.length === 1 ? hits[0] : null)
  if (!hit) return null
  const cfg = { vendor: 'sro' as const, street: hit.value }
  const nr = cleanNr(addr.houseNumber || '')
  const key = /^\d{1,4}[a-zA-Z]?$/.test(nr) ? await addressKey(hit.value, nr, hit.zip) : ''
  if (!key) return { supported: true, town: town.name, street: hit.value, needsHouseNumber: true, config: cfg }
  return { supported: true, town: town.name, street: hit.value, config: { ...cfg, hnrId: key } }
}

async function ics(key: string, year: boolean): Promise<string> {
  const res = await fetchWithTimeout(`${BASE}/service/ekalend_ical/(key)/${key}${year ? '/(period)/year' : ''}`, {
    headers: { 'User-Agent': UA, Accept: 'text/calendar' },
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return res.text()
}

async function readSro(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const key = cfg.hnrId != null ? String(cfg.hnrId) : ''
  if (!KEY.test(key) || key.length > 120) throw new Error('reconnect_required')
  const [year, next] = await Promise.all([ics(key, true), ics(key, false)])
  const rows = [...icsDays(year), ...icsDays(next)]
  if (!rows.length) throw new Error('reconnect_required')
  return dayEvents(rows, `abfall:sro:${key}`, cfg.label ?? null)
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'sro', name: p.town || 'Rostock', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'sro',
  towns,
  probe: probeSro,
  read: readSro,
}
