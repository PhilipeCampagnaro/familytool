// abfall/vendors/heidelberg.ts — Stadt Heidelberg, Amt für Abfallwirtschaft und
// Stadtreinigung — the Abfallkalender on abfallkalender.heidelberg.de, which
// reads the city's open-data platform.

import {
  type AbfallConfig,
  type AbfallProvider,
  dayEvents,
  type GeoAddress,
  getJson,
  type HausNr,
  normStreet,
  type ResolveResult,
  type RhythmTag,
  type SyncedEvent,
  type Town,
  type VendorAdapter,
} from "../core.ts";

// ── Heidelberg (garbage.datenplattform.heidelberg.de) ────────────────────────
//
//   GET  /streetnames              [["Bergheimer Straße Nr. 1-81A, 4-58", false], …]
//   GET  /collections?street=<n>   { collections: [rule], exceptions: [HolidayShift],
//                                    christmas: [ChristmasTreeCollection] }
//
// **There are no dates to read — there is a rule, and the city's page applies
// it.** Each bin has a weekday and a week code: "U" odd ISO weeks, "G" even,
// "A" the week that matches the house number (even numbers in even weeks), and
// a bin emptied weekly ignores the code. Which of weekly and 14-täglich a house
// has is not published: the page asks, per bin — Restabfall ("wöchentlich /
// nach Bedarf" or "14-täglich"), Altpapier and the Gelbe Tonne. So the read
// writes out both rhythms of those three and the household picks one per bin,
// which makes Heidelberg the one city that asks the rhythm question three times.
// Bio is not asked: the page offers weekly or "keine Abholung", and 14-täglich
// only on the outlying streets flagged `true` in /streetnames. Holiday shifts
// move a day's collection to another day; the page shows the current year, so
// the rule is written out to the end of the year or of the last published
// shift, whichever is later, and never past what the city has planned.
const BASE = 'https://garbage.datenplattform.heidelberg.de'

const BINS: Array<{ key: 'rest' | 'paper' | 'dsd' | 'bio'; name: string }> = [
  { key: 'rest', name: 'Restabfall' },
  { key: 'paper', name: 'Altpapier' },
  { key: 'dsd', name: 'Gelbe Tonne / Gelber Sack' },
  { key: 'bio', name: 'Bioabfall' },
]
const WEEKLY = 'Wöchentlich'
const FORTNIGHTLY = '14-täglich'
const DAYS = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa']

interface Rule {
  day_of_week_rest?: string; day_of_week_paper?: string; day_of_week_dsd?: string; day_of_week_bio?: string
  calendar_week_rest?: string; calendar_week_paper?: string; calendar_week_dsd?: string; calendar_week_bio?: string
}
interface Plan {
  collections?: Rule[]
  exceptions?: Array<{ shift_from_date?: string; shift_to_date?: string }>
  christmas?: Array<{ collection_date?: string }>
}

async function streetnames(): Promise<Array<[string, boolean]>> {
  const data = await getJson(`${BASE}/streetnames`)
  return Array.isArray(data)
    ? data.filter((x): x is [string, boolean] => Array.isArray(x) && typeof x[0] === 'string').map((x) => [x[0], !!x[1]])
    : []
}

async function plan(street: string): Promise<Plan> {
  return await getJson(`${BASE}/collections?street=${encodeURIComponent(street)}`) as Plan
}

// ── House numbers written into the street's name ────────────────────────────

/// "Bergheimer Straße Nr. 1-81A, 4-58" -> ["Bergheimer Straße", "1-81A, 4-58"].
function split(name: string): [string, string] {
  const m = name.match(/^(.*?)\s+Nr\.?\s*(.*)$/)
  return m ? [m[1].trim(), m[2].trim()] : [name.trim(), '']
}

/// Does "1-81A, 4-58" hold the number? A range whose ends are both odd is the
/// odd side of the street, both even the even side. Null where the entry is
/// written some other way ("53/1-61/1") — the household picks those.
function holds(part: string, nr: string): boolean | null {
  const n = Number(nr.match(/^\d+/)?.[0])
  if (!n) return null
  for (const bit of part.split(/\s*,\s*|\s+(?=\d)/).filter(Boolean)) {
    const r = bit.match(/^(\d+)[a-z]?(?:\s*-\s*(\d+)[a-z]?)?$/i)
    if (!r) return null
    const lo = Number(r[1]), hi = Number(r[2] ?? r[1])
    const side = lo % 2 === hi % 2 ? lo % 2 : null
    if (n >= lo && n <= hi && (side === null || n % 2 === side)) return true
  }
  return false
}

const cleanNr = (s: string) => s.replace(/\s+/g, '').toLowerCase()

async function probeHeidelberg(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const target = normStreet(addr.street)
  const hits = (await streetnames()).filter(([n]) => normStreet(split(n)[0]) === target).map(([n]) => n)
  if (!hits.length) return null
  const street = split(hits[0])[0]
  const nr = cleanNr(addr.houseNumber || '')
  const known = /^\d{1,4}[a-z]?$/.test(nr)
  // The number is needed even on a street with one entry: a fortnightly bin
  // marked "A" is emptied in the weeks that match its parity.
  if (hits.length === 1) {
    const cfg = { vendor: 'heidelberg' as const, street: hits[0] }
    return known
      ? { supported: true, town: town.name, street, config: { ...cfg, hnrId: nr } }
      : { supported: true, town: town.name, street, needsHouseNumber: true, config: cfg }
  }
  if (!known) return { supported: true, town: town.name, street, needsHouseNumber: true, config: { vendor: 'heidelberg', street } }
  const fits = hits.filter((h) => holds(split(h)[1], nr) === true)
  if (fits.length === 1 && !hits.some((h) => holds(split(h)[1], nr) === null)) {
    return { supported: true, town: town.name, street, config: { vendor: 'heidelberg', street: fits[0], hnrId: nr } }
  }
  // Several entries and a number that does not settle it: the household picks
  // the one that names theirs, and the pick carries the entry and the number.
  const hausNrList: HausNr[] = hits.map((h) => ({ id: `${h}|${nr}`, nr: split(h)[1] || h }))
  return { supported: true, town: town.name, street, needsHouseNumber: true, hausNrList, config: { vendor: 'heidelberg', street } }
}

// ── The rule, written out ───────────────────────────────────────────────────

const iso = (d: Date) => d.toISOString().slice(0, 10)

/// ISO-8601 week number of a UTC date.
function isoWeek(d: Date): number {
  const t = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()))
  t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7))
  const jan1 = Date.UTC(t.getUTCFullYear(), 0, 1)
  return Math.ceil(((t.getTime() - jan1) / 86_400_000 + 1) / 7)
}

/// Is a fortnightly bin with this week code emptied in this week?
function inWeek(code: string | undefined, even: boolean, weekEven: boolean): boolean {
  if (code === 'A') return even === weekEven
  if (code === 'U') return !weekEven
  if (code === 'G') return weekEven
  return false
}

function rhythmHeidelberg(title: string): RhythmTag | null {
  const m = title.match(/^(.+): (Wöchentlich|14-täglich)$/)
  return m ? { bin: m[1], option: m[2] } : null
}

async function readHeidelberg(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  // A chip picked on a street with several entries carries "<entry>|<number>".
  const raw = cfg.hnrId != null ? String(cfg.hnrId) : ''
  const cut = raw.lastIndexOf('|')
  const entry = (cut >= 0 ? raw.slice(0, cut) : cfg.street || '').trim()
  const nr = cleanNr(cut >= 0 ? raw.slice(cut + 1) : raw)
  if (!entry || entry.length > 120 || !/^\d{1,4}[a-z]?$/.test(nr)) throw new Error('reconnect_required')
  const [p, names] = await Promise.all([plan(entry), streetnames()])
  const rule = p.collections?.[0]
  if (!rule) throw new Error('reconnect_required')
  const outlying = names.find(([n]) => n === entry)?.[1] ?? false
  const even = Number(nr.match(/^\d+/)?.[0]) % 2 === 0

  const moved = new Map<string, string>()
  for (const x of p.exceptions ?? []) {
    if (x.shift_from_date && x.shift_to_date) moved.set(x.shift_from_date.slice(0, 10), x.shift_to_date.slice(0, 10))
  }
  const y = new Date().getUTCFullYear()
  const lastShift = [...moved.values()].sort().pop() ?? ''
  const end = [`${y}-12-31`, lastShift].sort().pop()!

  const rows: Array<{ day: string; title: string }> = []
  for (let d = new Date(Date.UTC(y, 0, 1)); iso(d) <= end; d = new Date(d.getTime() + 86_400_000)) {
    const weekEven = isoWeek(d) % 2 === 0
    const day = moved.get(iso(d)) ?? iso(d)
    for (const { key, name } of BINS) {
      if (rule[`day_of_week_${key}`] !== DAYS[d.getUTCDay()]) continue
      const fortnight = inWeek(rule[`calendar_week_${key}`], even, weekEven)
      if (key === 'bio') {
        if (!outlying || fortnight) rows.push({ day, title: name })
        continue
      }
      rows.push({ day, title: `${name}: ${WEEKLY}` })
      if (fortnight) rows.push({ day, title: `${name}: ${FORTNIGHTLY}` })
    }
  }
  const tree = p.christmas?.[0]?.collection_date?.slice(0, 10)
  if (tree) rows.push({ day: tree, title: 'Weihnachtsbaumabholung' })
  if (!rows.length) throw new Error('reconnect_required')
  return dayEvents(rows, `abfall:heidelberg:${normStreet(entry)}-${nr}`, cfg.label ?? null)
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'heidelberg', name: p.town || 'Heidelberg', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'heidelberg',
  towns,
  probe: probeHeidelberg,
  rhythm: rhythmHeidelberg,
  read: readHeidelberg,
}
