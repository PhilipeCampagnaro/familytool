// abfall/vendors/enni.ts — ENNI Stadt & Service Niederrhein (Moers) — the
// company's own street select and an ICS per street.

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

// ── ENNI (Moers) ────────────────────────────────────────────────────────────
//
//   GET  abfallkalender.enni.de/            <select name="street_id">, 985 streets
//   POST abfallkalender.enni.de/ street_id=<id>
//        -> 302 Location: /abholtermine/<slug>   (e.g. homberger-strasse/61-10962-120)
//   GET  abfallkalender.enni.de/ics-kalender/<slug>
//
// Long streets are split by number in the name ("Homberger Straße 61-109,62-120")
// and the household's number picks the entry. The slug is taken from the
// redirect, never built — the split ones are not guessable. An unknown slug is a
// 404. The feed runs from today to 31 December; titles read "Abholung Restabfall".
const ORIGIN = 'https://abfallkalender.enni.de'

async function probeEnni(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const res = await fetchWithTimeout(`${ORIGIN}/`, { headers: { 'User-Agent': UA, Accept: 'text/html' } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const sel = (await res.text()).match(/<select[^>]*name="street_id"[^>]*>([\s\S]*?)<\/select>/i)?.[1] ?? ''
  const target = normStreet(addr.street)
  const hits = [...sel.matchAll(/<option[^>]*value="(\d+)"[^>]*>([^<]*)/gi)]
    .map((m) => ({ id: m[1], name: decodeEntities(m[2]).replace(/\s+/g, ' ').trim() }))
    .map((o) => ({ ...o, ...splitSpans(o.name.replace(/,\s*(?=\d)/g, ' / ')) }))
    .filter((o) => normStreet(o.street) === target)
  if (!hits.length) return null
  let pick = hits.length === 1 ? hits[0] : undefined
  if (!pick && addr.houseNumber) {
    const fit = hits.filter((h) => inSpans(h.spans, addr.houseNumber!))
    if (fit.length === 1) pick = fit[0]
  }
  const street = hits[0].street
  const slugs = await Promise.all((pick ? [pick] : hits).map(async (h) => ({ h, slug: await slugOf(h.id) })))
  const cfg = { vendor: 'enni' as const, street }
  if (pick) {
    const slug = slugs[0].slug
    return slug ? { supported: true, town: town.name, street, config: { ...cfg, slug } } : null
  }
  return {
    supported: true, town: town.name, street, needsHouseNumber: true,
    hausNrList: slugs.filter((s) => s.slug).map(({ h, slug }) => ({ id: slug!, nr: h.name.slice(h.street.length).trim() })),
    config: cfg,
  }
}

async function slugOf(id: string): Promise<string | null> {
  const res = await fetchWithTimeout(`${ORIGIN}/`, {
    method: 'POST', redirect: 'manual',
    headers: { 'User-Agent': UA, 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `street_id=${encodeURIComponent(id)}`,
  })
  const loc = res.headers.get('location') || ''
  await res.body?.cancel()
  return loc.match(/\/abholtermine\/([a-z0-9/-]+)$/)?.[1] ?? null
}

async function readEnni(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  // A split street picked from the list arrives as hnrId.
  const slug = String(cfg.hnrId ?? cfg.slug ?? '')
  if (!/^[a-z0-9-]+(\/[a-z0-9-]+)?$/.test(slug)) throw new Error('reconnect_required')
  const res = await fetchWithTimeout(`${ORIGIN}/ics-kalender/${slug}`, { headers: { 'User-Agent': UA, Accept: 'text/calendar, */*' } })
  if (res.status === 404) throw new Error('reconnect_required')
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const rows = icsDays(await res.text()).map((r) => ({ ...r, title: r.title.replace(/^Abholung\s+/i, '') }))
  return dayEvents(rows, `abfall:enni:${slug}`, cfg.label ?? null)
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'enni', name: p.town || 'Moers', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'enni',
  towns,
  probe: probeEnni,
  read: readEnni,
}
