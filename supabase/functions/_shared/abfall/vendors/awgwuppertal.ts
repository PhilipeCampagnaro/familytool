// abfall/vendors/awgwuppertal.ts — AWG Wuppertal — a TYPO3 street search whose
// result page links one cHash-signed ICS per calendar year.

import {
  type AbfallConfig,
  type AbfallProvider,
  fetchWithTimeout,
  type GeoAddress,
  germanSpellings,
  normStreet,
  parseIcs,
  type ResolveResult,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── AWG Wuppertal ───────────────────────────────────────────────────────────
//
// `awg-wuppertal.de/privatkunden/abfallkalender.html` runs the `bw_wastecalendar`
// TYPO3 extension:
//
//   GET  ?eID=wastecalendar_autocomplete&term=<prefix>  -> ["Hauptstraße", …]
//   GET  the page                                       -> the `demand` form with
//        its signed `__trustedProperties`
//   POST the form with demand[streetname]=<name>        -> 303 to either
//        action=list&streetname=<id>   the street's calendar, or
//        action=street                 a list of houses, each linking its own
//                                      action=month page, for the streets
//                                      planned per house (Uellendahler Str.)
//   The calendar page links `action=ics&streetname=<id>&year=<y>&cHash=…` for
//   this year and — from autumn — next.
//
// **Every link is cHash-signed and an unsigned one is a 404**, so nothing is
// built by hand: the read walks the form each time and fetches whichever years
// the page offers. That is also the whole year rollover — 2027 is a link on the
// page on 2026-09-18, and the read takes every link it finds.
//
// One event names every bin of that day, "/"-separated: "Restmüll/Bio/Papier",
// with "!!! Terminverschiebung !!!" tacked on when a holiday moved it. It is
// split into one row per bin. **"Restmüll-50%" is dropped**: it is the
// fortnightly tariff, and it only ever falls on a day the weekly "Restmüll"
// already has — so a half-tariff household sees a weekly row that is sometimes
// not theirs, where keeping both would give everyone two rows every other week.
// The feed's own UIDs are sha1s of unknown input; ours are built from the
// street and the day.
const ORIGIN = 'https://awg-wuppertal.de'
const PAGE = `${ORIGIN}/privatkunden/abfallkalender.html`

async function autocomplete(term: string): Promise<string[]> {
  const res = await fetchWithTimeout(`${PAGE}?eID=wastecalendar_autocomplete&term=${encodeURIComponent(term)}`, {
    headers: { 'User-Agent': UA, Accept: 'application/json, */*' },
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const val = await res.json().catch(() => null)
  return Array.isArray(val) ? val.filter((v): v is string => typeof v === 'string') : []
}

async function findStreet(street: string): Promise<string | null> {
  const target = normStreet(street)
  if (!target) return null
  for (const q of germanSpellings(street)) {
    const hit = (await autocomplete(q).catch(() => [] as string[])).find((n) => normStreet(n) === target)
    if (hit) return hit
  }
  return null
}

const decode = (s: string) =>
  s.replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#0?39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>')

/// The page the form lands on for one street: its calendar, or its house list.
async function submit(street: string): Promise<string> {
  const page = await fetchWithTimeout(PAGE, { headers: { 'User-Agent': UA, Accept: 'text/html,*/*' } })
  if (!page.ok) throw new Error(`abfall upstream ${page.status}`)
  const html = await page.text()
  const form = html.match(/<form[^>]*name="demand"[\s\S]*?<\/form>/i)?.[0]
  const action = form?.match(/action="([^"]*)"/)?.[1]
  if (!form || !action) throw new Error('abfall upstream: no AWG form')
  const body = new URLSearchParams()
  for (const [tag] of form.matchAll(/<input[^>]*>/gi)) {
    const name = tag.match(/name="([^"]*)"/)?.[1]
    const value = tag.match(/value="([^"]*)"/)?.[1]
    if (name && value !== undefined && !/type="submit"/i.test(tag)) body.append(name, decode(value))
  }
  body.set('tx_bwwastecalendar_pi1[demand][streetname]', street)
  const cookie = (page.headers.get('set-cookie') || '').split(';')[0]
  const res = await fetchWithTimeout(new URL(decode(action), ORIGIN).toString(), {
    method: 'POST',
    headers: {
      'User-Agent': UA,
      Accept: 'text/html,*/*',
      'Content-Type': 'application/x-www-form-urlencoded',
      ...(cookie ? { Cookie: cookie } : {}),
    },
    body: body.toString(),
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return res.text()
}

/// Signed same-site links on a page, by `action`.
function links(html: string, action: string): Array<{ url: string; text: string }> {
  const out: Array<{ url: string; text: string }> = []
  for (const m of html.matchAll(/<a[^>]*href="([^"]+)"[^>]*>([^<]*)</gi)) {
    const href = decode(m[1])
    if (!href.includes(`[action]=${action}`) && !href.includes(`%5Baction%5D=${action}`)) continue
    const url = new URL(href, ORIGIN)
    if (url.origin !== ORIGIN) continue
    out.push({ url: url.toString(), text: m[2].trim() })
  }
  return out
}

const icsLinks = (html: string) => links(html, 'ics')
// A house list's entries link to that house's month view, which carries the
// same ICS links as the list view.
const houseLinks = (html: string) =>
  [...links(html, 'month'), ...links(html, 'list')].filter((l) => /^\d/.test(l.text))

const key = (s: string) => (s || '').toLowerCase().replace(/\s+/g, '')

async function getPage(url: string): Promise<string> {
  const res = await fetchWithTimeout(url, { headers: { 'User-Agent': UA, Accept: 'text/html,*/*' } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return res.text()
}

async function probeAwg(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const street = await findStreet(addr.street)
  if (!street) return null
  const html = await submit(street)
  if (icsLinks(html).length) {
    return { supported: true, town: town.name, street, config: { vendor: 'awgwuppertal', street } }
  }
  const houses = houseLinks(html)
  // Neither a calendar nor a house list: the street is known and served some
  // other way (or not at all), and a calendar that stays empty is refused.
  if (!houses.length) return null
  const want = key(addr.houseNumber || '')
  const house = want ? houses.find((h) => key(h.text) === want) : undefined
  if (house && icsLinks(await getPage(house.url).catch(() => '')).length) {
    return { supported: true, town: town.name, street, config: { vendor: 'awgwuppertal', street, hnrId: house.text } }
  }
  return {
    supported: true,
    town: town.name,
    street,
    needsHouseNumber: true,
    hausNrList: houses.map((h) => ({ id: h.text, nr: h.text })),
    config: { vendor: 'awgwuppertal', street },
  }
}

async function readAwg(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const street = cfg.street
  if (!street) throw new Error('reconnect_required')
  let html = await submit(street)
  const nr = cfg.hnrId != null ? String(cfg.hnrId) : ''
  if (nr) {
    const house = houseLinks(html).find((h) => key(h.text) === key(nr))
    if (!house) throw new Error('reconnect_required')
    html = await getPage(house.url)
  }
  const years = icsLinks(html)
  // The street is still in the search but no longer has a calendar page.
  if (!years.length) throw new Error('reconnect_required')
  const y = new Date().getUTCFullYear()
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  const who = key(`${street} ${nr}`)
  for (const link of years) {
    const res = await fetchWithTimeout(link.url, { headers: { 'User-Agent': UA, Accept: 'text/calendar, */*' } })
    if (!res.ok) continue
    const ics = await res.text()
    for (const ev of parseIcs(ics, new Date(Date.UTC(y - 1, 0, 1)), new Date(Date.UTC(y + 2, 0, 1)))) {
      const day = ev.startsAt.slice(0, 10)
      const bins = ev.title.split('/')
        .map((t) => t.replace(/!!!.*?!!!/g, '').trim())
        .filter((t) => t && !/^Restmüll-50%$/i.test(t))
      for (const bin of bins) {
        const k = `${day}:${bin}`
        if (seen.has(k)) continue
        seen.add(k)
        const start = new Date(`${day}T00:00:00Z`)
        out.push({
          uid: `abfall:awgwuppertal:${who}:${k}`,
          title: bin,
          notes: null,
          location: cfg.label ?? ev.location ?? null,
          startsAt: start.toISOString(),
          endsAt: new Date(start.getTime() + 86_400_000).toISOString(),
          allDay: true,
        })
      }
    }
  }
  return out
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'awgwuppertal', name: p.town || 'Wuppertal', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'awgwuppertal',
  towns,
  probe: probeAwg,
  read: readAwg,
}
