// abfall/vendors/abki.ts — ABK Abfallwirtschaftsbetrieb Kiel — three keyless
// JSON GETs behind the Leerungstermine page's Kendo form.

import {
  type AbfallConfig,
  type AbfallProvider,
  fetchWithTimeout,
  type GeoAddress,
  germanSpellings,
  normStreet,
  type ResolveResult,
  streetStem,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── ABK Kiel ────────────────────────────────────────────────────────────────
//
//   GET /abki-services/strassennamen?filter[…]=<prefix>  -> [{IDSTREET, Strasse}]
//   GET /abki-services/streetnumber?IDSTREET=<id>        -> [{IDSTANDORT, NUMBER}]
//   GET /abki-services/leerungen-data?Zeitraum=<y>&Strasse=<IDSTREET>&IDSTANDORT=<id>
//        -> {termine: [{titel, einheit, turnus, list: [{VALUE: "12.01.2026 (Montag)"}]}]}
//
// **The street list is Kendo server filtering**: without a `filter` it answers
// the 115 streets under "A" and looks like a complete list. The filter is the
// grid's own query-string shape, a case-insensitive prefix.
//
// **The Termine are the containers actually standing at the address** — each
// with its size and its rhythm ("Restabfall 120 l 2-wöchentlich") — not a menu
// of rhythms to choose from as in Pforzheim or Saarbrücken. Two containers of
// one kind on the same days collapse into one row per day.
//
// A house is a Standort, and one can span several numbers: "   1 -11" is the
// odd side from 1 to 11 (2 is its own row), "  21 - 27" likewise. A span covers
// the numbers of its own parity.
//
// A calendar-year vendor: `Zeitraum` is the year, next year answers an error
// with no Termine until ABK publishes it (the site itself asks from October).
const BASE = 'https://www.abki.de/abki-services'

async function getJson<T>(path: string, query: string): Promise<T> {
  const res = await fetchWithTimeout(`${BASE}/${path}?${query}`, {
    headers: { 'User-Agent': UA, Accept: 'application/json, */*' },
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return await res.json() as T
}

interface AbkStreet { IDSTREET: string; Strasse: string }
interface AbkHouse { IDSTANDORT: string; NUMBER: string }
interface AbkTermin { titel?: string; list?: Array<{ VALUE?: string }> }

const streetsLike = (prefix: string) =>
  getJson<AbkStreet[]>('strassennamen', new URLSearchParams({
    'filter[logic]': 'and',
    'filter[filters][0][field]': 'Strasse',
    'filter[filters][0][operator]': 'startswith',
    'filter[filters][0][value]': prefix,
    'filter[filters][0][ignoreCase]': 'true',
  }).toString())

async function findStreet(street: string): Promise<AbkStreet | null> {
  const target = normStreet(street)
  if (!target) return null
  const seen = new Set<string>()
  for (const base of [street.trim(), streetStem(street)]) {
    for (const q of germanSpellings(base)) {
      if (!q || seen.has(q)) continue
      seen.add(q)
      const hit = (await streetsLike(q).catch(() => [] as AbkStreet[])).find((r) => normStreet(r.Strasse) === target)
      if (hit) return hit
    }
  }
  return null
}

const houses = (idStreet: string) =>
  getJson<AbkHouse[]>('streetnumber', new URLSearchParams({ IDSTREET: idStreet }).toString())

const nrText = (s: string) => s.replace(/\s+/g, ' ').trim()

type Nr = [number, string]
const parseNr = (s: string): Nr | null => {
  const m = s.trim().toLowerCase().replace(/\s+/g, '').match(/^(\d+)([a-z]?)$/)
  return m ? [Number(m[1]), m[2]] : null
}
const cmp = (a: Nr, b: Nr) => a[0] - b[0] || a[1].localeCompare(b[1])

/// Does this Standort's NUMBER name the house? Exact ("14", "3a") or a span
/// ("1 -11", "21 - 27") of the same parity as its ends.
function covers(number: string, want: Nr): 'exact' | 'span' | null {
  const parts = number.split('-').map((p) => parseNr(p))
  if (parts.length === 1) return parts[0] && cmp(parts[0], want) === 0 ? 'exact' : null
  const [lo, hi] = parts
  if (parts.length !== 2 || !lo || !hi) return null
  if (cmp(lo, want) > 0 || cmp(want, [hi[0], hi[1] || 'zz']) > 0) return null
  if (lo[0] % 2 === hi[0] % 2 && want[0] % 2 !== lo[0] % 2) return null
  return 'span'
}

async function termine(idStreet: string, standort: string, year: number): Promise<AbkTermin[]> {
  const q = new URLSearchParams({ Zeitraum: String(year), Strasse: idStreet, IDSTANDORT: standort })
  const val = await getJson<{ termine?: AbkTermin[] }>('leerungen-data', q.toString())
  return Array.isArray(val?.termine) ? val.termine : []
}

function toEvents(ts: AbkTermin[], standort: string, label: string | null | undefined): SyncedEvent[] {
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const t of ts) {
    const title = (t.titel || '').trim()
    if (!title) continue
    for (const d of t.list || []) {
      const m = (d.VALUE || '').match(/^(\d{2})\.(\d{2})\.(\d{4})/)
      if (!m) continue
      const day = `${m[3]}-${m[2]}-${m[1]}`
      const k = `${day}:${title}`
      if (seen.has(k)) continue
      seen.add(k)
      const start = new Date(`${day}T00:00:00Z`)
      out.push({
        uid: `abfall:abki:${standort}:${k}`,
        title,
        notes: null,
        location: label ?? null,
        startsAt: start.toISOString(),
        endsAt: new Date(start.getTime() + 86_400_000).toISOString(),
        allDay: true,
      })
    }
  }
  return out
}

async function probeAbki(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const st = await findStreet(addr.street)
  if (!st) return null
  const hs = await houses(st.IDSTREET)
  if (!hs.length) return null
  const cfg = { vendor: 'abki' as const, strasseId: st.IDSTREET, street: st.Strasse }
  const list = (rows: AbkHouse[]): ResolveResult => ({
    supported: true, town: town.name, street: st.Strasse, needsHouseNumber: true,
    hausNrList: rows.map((h) => ({ id: h.IDSTANDORT, nr: nrText(h.NUMBER) })), config: cfg,
  })
  const want = parseNr(addr.houseNumber || '')
  if (!want) return list(hs)
  const exact = hs.filter((h) => covers(h.NUMBER, want) === 'exact')
  const hits = exact.length ? exact : hs.filter((h) => covers(h.NUMBER, want) === 'span')
  if (hits.length !== 1) return list(hits.length ? hits : hs)
  const pick = hits[0]
  const ts = await termine(st.IDSTREET, pick.IDSTANDORT, new Date().getUTCFullYear()).catch(() => [])
  if (!toEvents(ts, pick.IDSTANDORT, null).length) return list(hs)
  return {
    supported: true, town: town.name, street: st.Strasse,
    config: { ...cfg, hnr: nrText(pick.NUMBER), hnrId: pick.IDSTANDORT },
  }
}

async function readAbki(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const street = cfg.strasseId != null ? String(cfg.strasseId) : ''
  const standort = cfg.hnrId != null ? String(cfg.hnrId) : ''
  if (!/^\d{1,12}$/.test(street) || !/^\d{1,12}$/.test(standort)) throw new Error('reconnect_required')
  const y = new Date().getUTCFullYear()
  const [now, next] = await Promise.all([termine(street, standort, y), termine(street, standort, y + 1).catch(() => [])])
  const out = toEvents([...now, ...next], standort, cfg.label)
  // This year is always published; a Standort without it is gone.
  if (!toEvents(now, standort, null).length) throw new Error('reconnect_required')
  return out
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'abki', name: p.town || 'Kiel', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'abki',
  towns,
  probe: probeAbki,
  read: readAbki,
}
