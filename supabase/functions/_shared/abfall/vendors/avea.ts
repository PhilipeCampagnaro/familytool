// abfall/vendors/avea.ts — AVEA Leverkusen — the authority's own street pages,
// each with a plain ICS export per year.

import {
  type AbfallConfig,
  type AbfallProvider,
  decodeEntities,
  fetchWithTimeout,
  foldGerman,
  type GeoAddress,
  inSpans,
  normStreet,
  parseIcs,
  type ResolveResult,
  splitSpans,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── AVEA (Leverkusen) ───────────────────────────────────────────────────────
//
// AVEA runs Leverkusen's calendar on its own site, no widget in between:
//
//   GET …/abfuhrkalender/_<Letter>/        the streets under one letter, each a
//        link "…/abfuhrkalender/<slug>/<id>/<yyyy-mm>/" named "Ölbachstraße"
//   GET /abfuhrkalender-export/ical/<area>/<id>/<year>/export.ics
//
// `<area>` is Leverkusen's number in AVEA's system (85); it is read off the
// street's own page rather than assumed, because the link is printed there.
// An unknown street id answers an empty VCALENDAR — AVEA never says 404.
//
// **Long streets are split by number in the name** ("Bergische Landstraße 1 -
// 71 und 2 - 88" / "… 73 - Ende und 90 - Ende"); the household's number picks
// the entry, an ambiguous one is asked.
//
// **Two Restmüll rhythms print under two labels** — "Restmülltonne" (every two
// weeks) and "Restmülltonne 4-wöchentlich" — so both are kept: unlike Pforzheim,
// the household can tell its own row, and dropping one would leave the other
// rhythm without its bin. Calendar years: next year's export is empty until AVEA
// publishes it, so the read asks for this year and next. ICS UIDs are minted
// fresh per download; ours are built from the street and the day.
const ORIGIN = 'https://www.avea.de'
const LIST = `${ORIGIN}/privathaushalte/abfallentsorgung-leverkusen/abfuhrkalender`

interface Entry { id: string; slug: string; name: string }

async function getText(url: string): Promise<string> {
  const res = await fetchWithTimeout(url, { headers: { 'User-Agent': UA, Accept: 'text/html,text/calendar,*/*' } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return res.text()
}

async function streetsUnder(letter: string): Promise<Entry[]> {
  const html = await getText(`${LIST}/_${letter}/`)
  const out: Entry[] = []
  for (const m of html.matchAll(/abfuhrkalender\/([^"/]+)\/(\d+)\/[^"]*">([^<]+)</g)) {
    out.push({ slug: m[1], id: m[2], name: decodeEntities(m[3]).replace(/\s+/g, ' ').trim() })
  }
  return out
}

/// AVEA's number for Leverkusen, from the export link on a street's page.
async function areaOf(e: Entry): Promise<string | null> {
  const html = await getText(`${LIST}/${e.slug}/${e.id}/`)
  return html.match(/abfuhrkalender-export\/ical\/(\d+)\/\d+\//)?.[1] ?? null
}

async function probeAvea(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const target = normStreet(addr.street)
  const letter = foldGerman(addr.street.trim()).charAt(0).toUpperCase()
  if (!/^[A-Z]$/.test(letter)) return null
  const hits = (await streetsUnder(letter)).map((e) => ({ ...e, ...splitSpans(e.name) }))
    .filter((e) => normStreet(e.street) === target)
  if (!hits.length) return null
  const area = await areaOf(hits[0])
  if (!area) return null
  const street = hits[0].street
  const cfg = { vendor: 'avea' as const, street, kommuneId: area }
  let pick = hits.length === 1 ? hits[0] : undefined
  if (!pick && addr.houseNumber) {
    const fit = hits.filter((h) => inSpans(h.spans, addr.houseNumber!))
    if (fit.length === 1) pick = fit[0]
  }
  if (pick) return { supported: true, town: town.name, street, config: { ...cfg, hnrId: pick.id } }
  return {
    supported: true, town: town.name, street, needsHouseNumber: true,
    hausNrList: hits.map((h) => ({ id: h.id, nr: h.name.slice(h.street.length).trim() })),
    config: cfg,
  }
}

async function readAvea(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const id = cfg.hnrId != null ? String(cfg.hnrId) : ''
  const area = cfg.kommuneId || ''
  if (!/^\d{1,9}$/.test(id) || !/^\d{1,5}$/.test(area)) throw new Error('reconnect_required')
  const y = new Date().getUTCFullYear()
  const url = (year: number) => `${ORIGIN}/abfuhrkalender-export/ical/${area}/${id}/${year}/export.ics`
  const [now, next] = await Promise.all([getText(url(y)), getText(url(y + 1)).catch(() => '')])
  // This year is always published; an empty one means the street id is gone.
  if (!now.includes('BEGIN:VEVENT')) throw new Error('reconnect_required')
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const ics of [now, next]) {
    for (const ev of parseIcs(ics, new Date(Date.UTC(y - 1, 0, 1)), new Date(Date.UTC(y + 2, 0, 1)))) {
      const title = ev.title.trim()
      const day = ev.startsAt.slice(0, 10)
      const k = `${day}:${title}`
      if (!title || seen.has(k)) continue
      seen.add(k)
      const start = new Date(`${day}T00:00:00Z`)
      out.push({
        uid: `abfall:avea:${area}-${id}:${k}`,
        title,
        notes: null,
        location: cfg.label ?? ev.location ?? null,
        startsAt: start.toISOString(),
        endsAt: new Date(start.getTime() + 86_400_000).toISOString(),
        allDay: true,
      })
    }
  }
  return out
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'avea', name: p.town || 'Leverkusen', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'avea',
  towns,
  probe: probeAvea,
  read: readAvea,
}
