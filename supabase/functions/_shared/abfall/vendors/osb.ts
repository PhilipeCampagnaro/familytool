// abfall/vendors/osb.ts — Osnabrücker ServiceBetrieb — the city's own Online-
// Abfuhrkalender on nachhaltig.osnabrueck.de (TYPO3, tx_ytosn_wastecollection).

import {
  type AbfallConfig,
  type AbfallProvider,
  dayEvents,
  decodeEntities,
  fetchWithTimeout,
  type GeoAddress,
  normStreet,
  type ResolveResult,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── OSB Osnabrück ───────────────────────────────────────────────────────────
//
//   GET page                                    <datalist id="waste-collection-street-list">
//   GET page?tx_ytosn_wastecollection[street]=  the Abfuhrbezirk and its dates, or
//                                               <select id="waste-collection-house">
//   GET …&tx_ytosn_wastecollection[house]=<nr>  for a street split between Bezirke
//
// **Two bins per date**: the city collects Restmüll with Altpapier, and Gelbe
// Tonne with Biotonne, a week apart — each cell's title names the pair
// ("Restmüll- und Altpapiertonne"), so it is written out as two events. A cell
// reads "Di 22.09." with the year in the <h4> above it; an inline <svg> marks a
// moved date. An unknown street or number answers "Der Online-Abfuhrkalender
// ist aktuell leider nicht verfügbar." with no cells. No ICS; the window runs
// from today to 31 December.
const PAGE = 'https://nachhaltig.osnabrueck.de/de/abfall/muellabfuhr/muellabfuhr-digital/online-abfuhrkalender/'
const PAIRS: Record<string, string[]> = {
  waste: ['Restmüll', 'Altpapier'],
  bio: ['Gelbe Tonne', 'Biotonne'],
}

async function get(params?: Record<string, string>): Promise<string> {
  const q = params ? `?${new URLSearchParams(Object.entries(params).map(([k, v]) => [`tx_ytosn_wastecollection[${k}]`, v]))}` : ''
  const res = await fetchWithTimeout(`${PAGE}${q}`, { headers: { 'User-Agent': UA, Accept: 'text/html' } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return res.text()
}

const houseList = (html: string) =>
  [...(html.match(/<select[^>]*id="waste-collection-house"[\s\S]*?<\/select>/)?.[0] ?? '').matchAll(/<option value="([^"]+)"/g)]
    .map((m) => decodeEntities(m[1])).filter((v) => v !== '0')

async function probeOsb(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const list = (await get()).match(/<datalist id="waste-collection-street-list">([\s\S]*?)<\/datalist>/)?.[1] ?? ''
  const target = normStreet(addr.street)
  const street = [...list.matchAll(/<option>([^<]+)<\/option>/g)].map((m) => decodeEntities(m[1]).trim())
    .find((s) => normStreet(s) === target)
  if (!street) return null
  const cfg = { vendor: 'osb' as const, street }
  const page = await get({ street })
  const nrs = houseList(page)
  if (!nrs.length) {
    if (!/waste-collection-calendar-/.test(page)) return null
    return { supported: true, town: town.name, street, config: { ...cfg, hnrId: '' } }
  }
  const want = (addr.houseNumber || '').toUpperCase().replace(/\s+/g, '')
  const hit = nrs.find((n) => n.toUpperCase() === want)
  if (hit) return { supported: true, town: town.name, street, config: { ...cfg, hnrId: hit } }
  return { supported: true, town: town.name, street, needsHouseNumber: true, hausNrList: nrs.map((n) => ({ id: n, nr: n })), config: cfg }
}

async function readOsb(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const street = (cfg.street || '').trim()
  const nr = cfg.hnrId != null ? String(cfg.hnrId).trim() : ''
  if (!street || street.length > 80 || nr.length > 12) throw new Error('reconnect_required')
  const html = await get(nr ? { street, house: nr } : { street })
  const rows: Array<{ day: string; title: string; notes: string | null }> = []
  // Each <h4>year</h4> heads the cells after it.
  for (const part of html.split(/<h4>/).slice(1)) {
    const year = part.match(/^(\d{4})<\/h4>/)?.[1]
    if (!year) continue
    for (const m of part.matchAll(/class="waste-collection-calendar-(waste|bio)">\s*[A-Za-z]{2}\s+(\d{2})\.(\d{2})\.\s*(<svg)?/g)) {
      const day = `${year}-${m[3]}-${m[2]}`
      for (const title of PAIRS[m[1]]) rows.push({ day, title, notes: m[4] ? 'Abweichender Termin' : null })
    }
  }
  if (!rows.length) throw new Error('reconnect_required')
  return dayEvents(rows, `abfall:osb:${normStreet(street)}-${nr.toLowerCase() || 'x'}`, cfg.label ?? null)
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'osb', name: p.town || 'Osnabrück', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'osb',
  towns,
  probe: probeOsb,
  read: readOsb,
}
