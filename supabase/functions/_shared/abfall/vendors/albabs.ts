// abfall/vendors/albabs.ts — ALBA Braunschweig — the company's own TYPO3
// calendar (mf_abfallkalender): street search, house list, ICS per house.

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

// ── ALBA Braunschweig ───────────────────────────────────────────────────────
//
// Everything is one URL with a different `action` (P = the plugin prefix):
//
//   POST …/ajax-kalender.html?P[action]=ajaxlist&P[mf-trash-search]=<≥3 chars>
//        -> HTML, <a class="mf-trash-street" …P[mf-trash-strasse]=<name>…>
//   POST …?P[action]=hnrlist&P[mf-trash-strasse]=<name>
//        -> <a class="mf-trash-street-nr" …P[mf-trash-hausnr]=2&…hausnrzusatz]=A>
//   GET  …?P[action]=makeical&…strasse&…hausnr&…hausnrzusatz&…thisyear=<y>
//
// The page's links carry a cHash, and the server does not check it. The plan is
// per house and names the household's own bins (size and rhythm in DESCRIPTION),
// so there is no rhythm to ask. **A house with two bins of one kind has two
// events on the day**, deduplicated here. Events are `VALUE=DATE` with DTEND
// equal to DTSTART — a zero-length day — so they are read directly rather than
// through the general parser. An unknown address is an empty VCALENDAR; next
// year is empty until ALBA publishes it. Paper is sometimes collected by a
// private firm with its own calendar, which is not ALBA's and not read.
const URL_ = 'https://alba-bs.de/service/abfuhrtermine/ajax-kalender.html'
const P = 'tx_mfabfallkalender_mfabfallkalender'

function url(params: Record<string, string>): string {
  const q = Object.entries({ ...params }).map(([k, v]) => `${encodeURIComponent(`${P}[${k}]`)}=${encodeURIComponent(v)}`)
  return `${URL_}?${q.join('&')}&id=161`
}

async function text(u: string, method = 'GET'): Promise<string> {
  const res = await fetchWithTimeout(u, { method, headers: { 'User-Agent': UA, Accept: 'text/html,text/calendar,*/*' } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return res.text()
}

const param = (href: string, name: string) => {
  const m = href.match(new RegExp(`${P}%5B${name}%5D=([^&"]*)`))
  return m ? decodeURIComponent(m[1].replace(/\+/g, ' ')) : ''
}

async function probeAlba(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const target = normStreet(addr.street)
  const q = streetStem(addr.street).slice(0, 30)
  if (q.length < 3) return null
  const list = await text(url({ action: 'ajaxlist', 'mf-trash-search': q }), 'POST')
  const name = [...list.matchAll(/<a[^>]*class="mf-trash-street"[^>]*href="([^"]+)"/g)]
    .map((m) => param(decodeEntities(m[1]), 'mf-trash-strasse'))
    .find((n) => normStreet(n) === target)
  if (!name) return null
  const hn = await text(url({ action: 'hnrlist', 'mf-trash-strasse': name }), 'POST')
  const houses = [...hn.matchAll(/<a[^>]*class="mf-trash-street-nr"[^>]*href="([^"]+)"/g)].map((m) => {
    const h = decodeEntities(m[1])
    const nr = param(h, 'mf-trash-hausnr'), zu = param(h, 'mf-trash-hausnrzusatz')
    return { id: `${nr}|${zu}`, nr: `${nr}${zu}` }
  })
  const cfg = { vendor: 'albabs' as const, street: name }
  const want = (addr.houseNumber || '').toLowerCase().replace(/\s+/g, '')
  const hit = houses.find((h) => h.nr.toLowerCase() === want)
  if (hit) return { supported: true, town: town.name, street: name, config: { ...cfg, hnrId: hit.id } }
  return { supported: true, town: town.name, street: name, needsHouseNumber: true, hausNrList: houses, config: cfg }
}

async function readAlba(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const street = (cfg.street || '').trim()
  const [nr, zu = ''] = (cfg.hnrId != null ? String(cfg.hnrId) : '').split('|')
  if (!street || !/^\d{1,5}$/.test(nr) || !/^[A-Za-z0-9]{0,4}$/.test(zu)) throw new Error('reconnect_required')
  const y = new Date().getUTCFullYear()
  const ics = (year: number) => url({
    action: 'makeical', 'mf-trash-strasse': street, 'mf-trash-hausnr': nr, 'mf-trash-hausnrzusatz': zu,
    'mf-trash-thisyear': String(year),
  })
  const [now, next] = await Promise.all([text(ics(y)), text(ics(y + 1)).catch(() => '')])
  const days = icsDays(now)
  if (!days.length) throw new Error('reconnect_required')
  const rows = [...days, ...icsDays(next)].map((r) => ({ ...r, title: r.title.replace(/\s+Abholung\s*$/i, '') }))
  return dayEvents(rows, `abfall:albabs:${normStreet(street)}-${nr}${zu.toLowerCase()}`, cfg.label ?? null)
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'albabs', name: p.town || 'Braunschweig', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'albabs',
  towns,
  probe: probeAlba,
  read: readAlba,
}
