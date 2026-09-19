// abfall/vendors/beg.ts — BEG Bremerhavener Entsorgungsgesellschaft — the
// Abfuhrkalender on kalender.beg-logistics.de.

import {
  type AbfallConfig,
  type AbfallProvider,
  dayEvents,
  decodeEntities,
  fetchWithTimeout,
  type GeoAddress,
  JSON_HEADERS,
  normStreet,
  type ResolveResult,
  restRhythm,
  streetStem,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── BEG (kalender.beg-logistics.de, a Rails app) ─────────────────────────────
//
//   GET   /auto_complete/streets.json?term=<3+ chars>   ["Bgm.-Smidt-Straße, Bremerhaven", …]
//   GET   /sessions/new                   session cookie + authenticity_token
//   PATCH /auto_complete/update_street.js term=<street>
//   PATCH /sections/search.js             number=<nr>  -> "Diese Adresse wurde gefunden."
//   POST  /sessions                       street, number, two_weeks=0|1
//   GET   /schedules/public               "Termine in den nächsten 30 Tagen"
//
// **Thirty days is all BEG publishes in a form a machine can read** — the year
// is a PDF. Enough for a calendar refreshed daily; it just never shows more
// than the month ahead. The address lives in the session, so every read walks
// the form with its own cookie jar. The Restmüll rhythm is the form's
// "14-tägliche Abfuhr" box rather than a line of the answer, so the read walks
// it twice, box clear and ticked, and titles the grey bin by the rhythm; the
// household picks one as for every vendor that asks.
const BASE = 'https://kalender.beg-logistics.de'

/// BEG's icon classes, named as the bins are on beg-bhv.de.
const BINS: Record<string, string> = {
  restmuell: 'Restmüll',
  blauetonne: 'Altpapier',
  gelbersack: 'Gelber Sack',
  biotonne: 'Bioabfall',
}

class Jar {
  private c = new Map<string, string>()
  take(res: Response) {
    for (const line of res.headers.getSetCookie()) {
      const [kv] = line.split(';')
      const at = kv.indexOf('=')
      if (at > 0) this.c.set(kv.slice(0, at).trim(), kv.slice(at + 1).trim())
    }
  }
  get header(): string { return [...this.c].map(([k, v]) => `${k}=${v}`).join('; ') }
}

async function call(jar: Jar, path: string, init: { method?: string; body?: URLSearchParams; xhr?: boolean; token?: string } = {}): Promise<Response> {
  const headers: Record<string, string> = { 'User-Agent': UA, Cookie: jar.header }
  if (init.body) headers['Content-Type'] = 'application/x-www-form-urlencoded'
  if (init.xhr) Object.assign(headers, { 'X-Requested-With': 'XMLHttpRequest', Accept: 'text/javascript' })
  if (init.token) headers['X-CSRF-Token'] = init.token
  const res = await fetchWithTimeout(BASE + path, { method: init.method ?? 'GET', headers, body: init.body, redirect: 'manual' })
  jar.take(res)
  return res
}

/// Open a session on the address. Null when BEG does not know the number.
async function session(street: string, nr: string, twoWeeks: boolean): Promise<string | null> {
  const jar = new Jar()
  const start = await call(jar, '/sessions/new')
  const token = decodeEntities((await start.text()).match(/name="authenticity_token" type="hidden" value="([^"]*)"/)?.[1] ?? '')
  if (!token) throw new Error('abfall upstream: no BEG token')
  await (await call(jar, '/auto_complete/update_street.js', { method: 'PATCH', body: new URLSearchParams({ term: street }), xhr: true, token })).text()
  const found = await (await call(jar, '/sections/search.js', { method: 'PATCH', body: new URLSearchParams({ number: nr }), xhr: true, token })).text()
  if (!/wurde gefunden/.test(found)) return null
  const post = await call(jar, '/sessions', {
    method: 'POST',
    body: new URLSearchParams({
      utf8: '✓', authenticity_token: token, 'session[street]': street, 'session[number]': nr,
      'session[two_weeks]': twoWeeks ? '1' : '0', 'session[selection]': 'abfuhrtermine', commit: 'weiter',
    }),
  })
  await post.text()
  // POST -> "/" -> "/schedules/public", each hop setting cookies the next one
  // needs, so the chain is followed by hand rather than by fetch.
  let res = post
  for (let hop = 0; hop < 4 && res.status >= 300 && res.status < 400; hop++) {
    const to = new URL(res.headers.get('location') || '/schedules/public', BASE)
    if (to.origin !== BASE) break
    res = await call(jar, to.pathname)
    if (res.status >= 300 && res.status < 400) await res.body?.cancel()
  }
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return res.text()
}

/// The "next 30 days" list: one row per day, one icon per bin.
function days(html: string): Array<{ day: string; bins: string[] }> {
  const out: Array<{ day: string; bins: string[] }> = []
  for (const li of html.matchAll(/<li class="day">([\s\S]*?)<\/li>/g)) {
    const d = li[1].match(/(\d{2})\.(\d{2})\.(\d{4})/)
    if (!d) continue
    const bins = [...li[1].matchAll(/icon_(\w+)"><img alt="([^"]*)"/g)]
      .map((m) => BINS[m[1]] ?? decodeEntities(m[2]).replace(/^./, (c) => c.toUpperCase()))
    out.push({ day: `${d[3]}-${d[2]}-${d[1]}`, bins })
  }
  return out
}

async function streets(term: string): Promise<string[]> {
  const res = await fetchWithTimeout(`${BASE}/auto_complete/streets.json?term=${encodeURIComponent(term)}`, { headers: JSON_HEADERS })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const data = await res.json()
  return Array.isArray(data) ? data.filter((s): s is string => typeof s === 'string') : []
}

const cleanNr = (s: string) => s.replace(/\s+/g, '')

/// BEG abbreviates what the geocoder spells out: "Bgm.-Smidt-Straße" is
/// "Bürgermeister-Smidt-Straße".
const norm = (s: string) => normStreet(s.replace(/, Bremerhaven$/, '').replace(/\bBgm\.\s*-?\s*/g, 'Bürgermeister-'))

async function probeBeg(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const target = norm(addr.street)
  const stem = streetStem(addr.street)
  const hit = (await streets(stem.length >= 3 ? stem : addr.street))
    .find((s) => /, Bremerhaven$/.test(s) && norm(s) === target)
  if (!hit) return null
  const street = hit.replace(/, Bremerhaven$/, '')
  const cfg = { vendor: 'beg' as const, street: hit }
  const nr = cleanNr(addr.houseNumber || '')
  if (!/^\d{1,4}\s*[a-zA-Z]?$/.test(nr) || !(await session(hit, nr, false))) {
    return { supported: true, town: town.name, street, needsHouseNumber: true, config: cfg }
  }
  return { supported: true, town: town.name, street, config: { ...cfg, hnrId: nr } }
}

async function readBeg(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const street = (cfg.street || '').trim()
  const nr = cleanNr(cfg.hnrId != null ? String(cfg.hnrId) : '')
  if (!street || street.length > 100 || !/^\d{1,4}[a-zA-Z]?$/.test(nr)) throw new Error('reconnect_required')
  const [weekly, fortnightly] = await Promise.all([session(street, nr, false), session(street, nr, true)])
  if (weekly == null) throw new Error('reconnect_required')
  const rows: Array<{ day: string; title: string }> = []
  for (const { day, bins } of days(weekly)) {
    for (const b of bins) rows.push({ day, title: b === 'Restmüll' ? 'Restmüll: Wöchentlich' : b })
  }
  for (const { day, bins } of days(fortnightly ?? '')) {
    if (bins.includes('Restmüll')) rows.push({ day, title: 'Restmüll: 14-täglich' })
  }
  if (!rows.length) throw new Error('reconnect_required')
  return dayEvents(rows, `abfall:beg:${normStreet(street)}-${nr.toLowerCase()}`, cfg.label ?? null)
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'beg', name: p.town || 'Bremerhaven', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'beg',
  towns,
  probe: probeBeg,
  rhythm: restRhythm,
  read: readBeg,
}
