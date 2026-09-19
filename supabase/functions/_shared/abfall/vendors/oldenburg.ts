// abfall/vendors/oldenburg.ts — Stadt Oldenburg (AWB) — the city's own TYPO3
// "CollectionCalendar" plugin: a street <select> and a hand-buildable ICS GET.

import {
  type AbfallConfig,
  type AbfallProvider,
  decodeEntities,
  fetchWithTimeout,
  type GeoAddress,
  normStreet,
  parseIcs,
  type ResolveResult,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── Stadt Oldenburg ─────────────────────────────────────────────────────────
//
// One page on oldenburg.de carries `<select id="street">` — 1,528 streets by
// numeric id — and the plugin's ICS export answers a plain GET, no session, no
// cHash (it carries one in the page's own link but does not check it):
//
//   GET <PAGE>?P[action]=exportIcs&P[controller]=Frontend\Export
//        &P[street]=<id>&P[houseNumber]=<nr>&P[year]=<y>&P[wasteTypes][n]=n
//
// **It never says no.** An unknown street, number or year is a 200 with an empty
// VCALENDAR, so empty *is* the "not found", and a number is required: Donnerschweer
// Straße 1–200 and 300–400 are on different days. Three names appear twice
// (Gneisenaustraße 506/507, Schäferstraße, Von-Halem-Straße) with one id always
// empty, so every id of the name is asked and the one with dates wins.
//
// Waste types 1–4 (Gelber Sack/Tonne, Bioabfall, Restabfall, Altpapier). **5,
// "Sommerbiotonne", is a booked extra** that the export returns for everybody, so
// it is not asked for. The ICS runs from today to 31 December with random UIDs
// (a reverse proxy caches per exact URL, so the parameter order is kept fixed);
// events are floating 06:00–07:00 and read as all-day. Next year is an empty
// calendar until the city publishes it, so the read asks for both.
const PAGE = 'https://www.oldenburg.de/startseite/stadtraum/umwelt/abfall-entsorgung/awb-von-a-bis-z/abfuhrkalender.html'
const P = 'tx_collectioncalendar_collectioncalendar'
const TYPES = ['1', '2', '3', '4']

async function streetIds(street: string): Promise<{ name: string; ids: string[] } | null> {
  const res = await fetchWithTimeout(PAGE, { headers: { 'User-Agent': UA, Accept: 'text/html,*/*' } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const sel = (await res.text()).match(/<select[^>]*id="street"[^>]*>([\s\S]*?)<\/select>/i)?.[1] ?? ''
  const target = normStreet(street)
  const hits = [...sel.matchAll(/<option[^>]*value="(\d+)"[^>]*>([^<]*)</gi)]
    .map((m) => ({ id: m[1], name: decodeEntities(m[2]).trim() }))
    .filter((o) => normStreet(o.name) === target)
  return hits.length ? { name: hits[0].name, ids: hits.map((h) => h.id) } : null
}

async function ics(street: string, nr: string, year: number): Promise<string> {
  // Fixed order: the proxy in front caches per exact URL.
  const q = [
    [`${P}[action]`, 'exportIcs'], [`${P}[controller]`, 'Frontend\\Export'],
    [`${P}[street]`, street], [`${P}[houseNumber]`, nr], [`${P}[year]`, String(year)],
    ...TYPES.map((t) => [`${P}[wasteTypes][${t}]`, t]),
  ].map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&')
  const res = await fetchWithTimeout(`${PAGE}?${q}`, { headers: { 'User-Agent': UA, Accept: 'text/calendar, */*' } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return res.text()
}

const hasDates = (s: string) => s.includes('BEGIN:VEVENT')

async function probeOl(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const st = await streetIds(addr.street)
  if (!st) return null
  const nr = (addr.houseNumber || '').trim()
  const y = new Date().getUTCFullYear()
  for (const id of nr ? st.ids : []) {
    if (hasDates(await ics(id, nr, y).catch(() => ''))) {
      return { supported: true, town: town.name, street: st.name, config: { vendor: 'oldenburg', street: st.name, strasseId: id, hnr: nr } }
    }
  }
  // No number, or one with no calendar: the city publishes no house list, so
  // the number is asked for again.
  return {
    supported: true, town: town.name, street: st.name, needsHouseNumber: true,
    config: { vendor: 'oldenburg', street: st.name, strasseId: st.ids[0] },
  }
}

async function readOl(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const id = cfg.strasseId != null ? String(cfg.strasseId) : ''
  const nr = (cfg.hnr || '').trim()
  if (!/^\d{1,6}$/.test(id) || !nr) throw new Error('reconnect_required')
  const y = new Date().getUTCFullYear()
  const [now, next] = await Promise.all([ics(id, nr, y), ics(id, nr, y + 1).catch(() => '')])
  // The window is today to 31 December, so it can run dry in the last days of
  // the year before next year is out; only outside December is empty a reconnect.
  if (!hasDates(now) && !hasDates(next) && new Date().getUTCMonth() !== 11) throw new Error('reconnect_required')
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const cal of [now, next]) {
    for (const ev of parseIcs(cal, new Date(Date.UTC(y - 1, 0, 1)), new Date(Date.UTC(y + 2, 0, 1)))) {
      const title = ev.title.trim()
      const day = ev.startsAt.slice(0, 10)
      const k = `${day}:${title}`
      if (!title || seen.has(k)) continue
      seen.add(k)
      const start = new Date(`${day}T00:00:00Z`)
      out.push({
        uid: `abfall:oldenburg:${id}-${nr.toLowerCase().replace(/\s+/g, '')}:${k}`,
        title,
        notes: null,
        location: cfg.label ?? null,
        startsAt: start.toISOString(),
        endsAt: new Date(start.getTime() + 86_400_000).toISOString(),
        allDay: true,
      })
    }
  }
  return out
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'oldenburg', name: p.town || 'Oldenburg', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'oldenburg',
  towns,
  probe: probeOl,
  read: readOl,
}
