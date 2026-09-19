// abfall/vendors/hws.ts — HWS Hallesche Wasser und Stadtwirtschaft (Halle
// (Saale)) — the company's own street list, house list and ICS per house.

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

// ── HWS Halle ───────────────────────────────────────────────────────────────
//
//   GET  …/entsorgungskalender                  <datalist id="street-name-datalist">
//        of 1,573 streets, abbreviated ("Adam-Kuckhoff-Str")
//   POST /hws_entsorgungskalender_autocomplete_housenumber  street=<name>
//        -> ["1","11","17A","17b",…]
//   GET  /entsorgungskalender_ics?streetName=&houseNumber=&customer=&year=<y>
//
// `customer` names a business at the address; a household sends it empty. **One
// event carries every bin collected that day**, comma-separated in SUMMARY
// ("Restmüll (Graue Tonne), Papier/Pappe (Blaue Tonne)"), so it is split here;
// a leading "★" marks a date moved by a holiday. One request is one calendar
// year, and next year was already published in September. An unknown address is
// an empty VCALENDAR.
const ORIGIN = 'https://hws-halle.de'
const PAGE = `${ORIGIN}/produkte-dienstleistungen/entsorgung/entsorgungskalender`

async function probeHws(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const res = await fetchWithTimeout(PAGE, { headers: { 'User-Agent': UA, Accept: 'text/html' } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const list = (await res.text()).match(/<datalist[^>]*id="street-name-datalist"[\s\S]*?<\/datalist>/i)?.[0] ?? ''
  const target = normStreet(addr.street)
  const street = [...list.matchAll(/<option[^>]*value="([^"]*)"/g)].map((m) => decodeEntities(m[1]).trim())
    .find((s) => normStreet(s) === target)
  if (!street) return null
  const hn = await fetchWithTimeout(`${ORIGIN}/hws_entsorgungskalender_autocomplete_housenumber`, {
    method: 'POST',
    headers: { 'User-Agent': UA, 'Content-Type': 'application/x-www-form-urlencoded', Accept: 'application/json' },
    body: new URLSearchParams({ street }).toString(),
  })
  if (!hn.ok) throw new Error(`abfall upstream ${hn.status}`)
  const nrs = ((await hn.json()) as string[]).filter((n) => typeof n === 'string')
    .sort((a, b) => parseInt(a, 10) - parseInt(b, 10) || a.localeCompare(b))
  const cfg = { vendor: 'hws' as const, street }
  const want = (addr.houseNumber || '').toLowerCase().replace(/\s+/g, '')
  const hit = nrs.find((n) => n.toLowerCase() === want)
  if (hit) return { supported: true, town: town.name, street, config: { ...cfg, hnrId: hit } }
  return { supported: true, town: town.name, street, needsHouseNumber: true, hausNrList: nrs.map((n) => ({ id: n, nr: n })), config: cfg }
}

async function readHws(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const street = (cfg.street || '').trim()
  const nr = cfg.hnrId != null ? String(cfg.hnrId).trim() : ''
  if (!street || street.length > 80 || !/^[0-9][0-9a-zA-Z /-]{0,10}$/.test(nr)) throw new Error('reconnect_required')
  const y = new Date().getUTCFullYear()
  const url = (year: number) =>
    `${ORIGIN}/entsorgungskalender_ics?${new URLSearchParams({ streetName: street, houseNumber: nr, customer: '', year: String(year) })}`
  const get = async (u: string) => {
    const res = await fetchWithTimeout(u, { headers: { 'User-Agent': UA, Accept: 'text/calendar, */*' } })
    if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
    return res.text()
  }
  const [now, next] = await Promise.all([get(url(y)), get(url(y + 1)).catch(() => '')])
  const days = icsDays(now)
  if (!days.length) throw new Error('reconnect_required')
  const rows = [...days, ...icsDays(next)].flatMap(({ day, title }) => {
    const moved = /^★/.test(title)
    return title.replace(/^★\s*/, '').split(/,\s*(?=[A-ZÄÖÜ])/).map((t) => ({
      day, title: t.trim(), notes: moved ? 'Verschoben (Feiertag)' : null,
    }))
  })
  return dayEvents(rows, `abfall:hws:${normStreet(street)}-${nr.toLowerCase()}`, cfg.label ?? null)
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'hws', name: p.town || 'Halle (Saale)', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'hws',
  towns,
  probe: probeHws,
  read: readHws,
}
