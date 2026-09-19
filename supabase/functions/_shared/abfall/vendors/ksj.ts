// abfall/vendors/ksj.ts — KommunalService Jena — the city's own
// Entsorgungstermine servlet: street and house selects, ICS per house.

import {
  type AbfallConfig,
  type AbfallProvider,
  dayEvents,
  decodeEntities,
  fetchWithTimeout,
  type GeoAddress,
  icsDays,
  inSpans,
  normStreet,
  type ResolveResult,
  splitSpans,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── KSJ Jena (entsorgungstermine.jena.de, iframed by ksj.jena.de) ────────────
//
//   GET /getMainSelectMenus?x=true&lang=de                 <option value="Ahornweg">…
//   GET /getMainSelectMenus?x=true&lang=de&street=<name>   <select id="hnummer">
//   GET /makeICSAll?street=<name>[&hnummer=<nr>]&lang=de   text/calendar
//
// A street whose house select is empty is planned as a whole and the number is
// left out. House entries can be spans ("106-116"). Titles carry a suffix,
// "Restabfall2R", and one event titled "KSJ <address>" is the calendar's own
// header, not a pickup. **An unknown street answers 200 with a Java exception
// as text**, so anything that is not a VCALENDAR is "not found". The window runs
// from the start of this month to 31 December.
const ORIGIN = 'https://entsorgungstermine.jena.de'

async function get(path: string, params: Record<string, string>): Promise<string> {
  const res = await fetchWithTimeout(`${ORIGIN}${path}?${new URLSearchParams(params)}`, {
    headers: { 'User-Agent': UA, Accept: 'text/html,text/calendar,*/*' },
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return res.text()
}

async function probeKsj(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const target = normStreet(addr.street)
  const street = [...(await get('/getMainSelectMenus', { x: 'true', lang: 'de' })).matchAll(/<option[^>]*value="([^"]+)"/g)]
    .map((m) => decodeEntities(m[1]).trim()).find((s) => normStreet(s) === target)
  if (!street) return null
  const page = await get('/getMainSelectMenus', { x: 'true', lang: 'de', street })
  const sel = page.match(/<select[^>]*id="hnummer"[\s\S]*?<\/select>/i)?.[0] ?? ''
  const nrs = [...sel.matchAll(/<option[^>]*value="([^"]+)"/g)].map((m) => decodeEntities(m[1]).trim()).filter(Boolean)
  const cfg = { vendor: 'ksj' as const, street }
  if (!nrs.length) return { supported: true, town: town.name, street, config: { ...cfg, hnrId: '' } }
  const want = (addr.houseNumber || '').toLowerCase().replace(/\s+/g, '')
  let hit = nrs.filter((n) => n.toLowerCase() === want)
  if (!hit.length && want) hit = nrs.filter((n) => /-/.test(n) && inSpans(splitSpans(`x ${n}`).spans, want))
  if (hit.length === 1) return { supported: true, town: town.name, street, config: { ...cfg, hnrId: hit[0] } }
  return { supported: true, town: town.name, street, needsHouseNumber: true, hausNrList: nrs.map((n) => ({ id: n, nr: n })), config: cfg }
}

async function readKsj(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const street = (cfg.street || '').trim()
  const nr = cfg.hnrId != null ? String(cfg.hnrId).trim() : ''
  if (!street || street.length > 80 || !/^([0-9][0-9a-zA-Z /-]{0,12})?$/.test(nr)) throw new Error('reconnect_required')
  const body = await get('/makeICSAll', nr ? { street, hnummer: nr, lang: 'de' } : { street, lang: 'de' })
  if (!body.includes('BEGIN:VCALENDAR')) throw new Error('reconnect_required')
  const rows = icsDays(body)
    .filter((r) => !/^KSJ\s/.test(r.title))
    .map((r) => ({ ...r, title: r.title.replace(/\d*R$/, '').trim() }))
  return dayEvents(rows, `abfall:ksj:${normStreet(street)}-${nr.toLowerCase() || 'x'}`, cfg.label ?? null)
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'ksj', name: p.town || 'Jena', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'ksj',
  towns,
  probe: probeKsj,
  read: readKsj,
}
