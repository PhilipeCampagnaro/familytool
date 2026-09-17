// abfall/vendors/awbkoeln.ts — AWB Köln — an address search that never says "not found", so every row is checked.

import {
  type AbfallConfig,
  type AbfallProvider,
  fetchWithTimeout,
  type GeoAddress,
  normStreet,
  parseIcs,
  type ResolveResult,
  type StreetOption,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── AWB Köln ────────────────────────────────────────────────────────────────
//
// Two keyless GETs and, unusually, no signature anywhere:
//
//   1. GET /api/streets?street_name=…&building_number=… -> the address rows,
//      each with a `street_code`, the canonical `street_name` and — the only
//      vendor here that volunteers it — the **zipcode**.
//   2. GET …/ics/icscal.php?street_code=…&building_number=…&start_year=…
//      &end_year=… with one flag per bin. Plain query, no cHash, no session.
//
// **The search never says "no".** Asked for a street Köln does not have it
// answers with the alphabetically nearest one that does: "Quatschstraße" comes
// back as "Quatermarkt", and a house number the street lacks comes back as a
// different house on a different street entirely ("Venloer Str. 2" -> "Kamekestr.
// 1z"). So every row is checked against what was asked for — street, house
// number and, where the geocoder gave one, the postcode — and anything else is
// discarded. Trusting the first row is exactly the mistake that put München on
// Münchenhof's bins.
//
// Because `start_year`/`end_year` are free parameters, the read asks for this
// year *and* next. Köln answers with whatever it has and an empty calendar for
// the rest, so the 2027 plan appears by itself on the day AWB publishes it —
// which is the thing München's signed, single-year link cannot do.
const AWB_BASE = 'https://www.awbkoeln.de'

const AWB_ICS = `${AWB_BASE}/typo3conf/ext/content/Resources/Public/ics/icscal.php`

// Two addresses in one row. `user_*` is the household's own address, as it would
// be written on a letter; `street_name`/`building_number`/`street_code` is the
// **Stellplatz** — where the bins are actually put out, which in Köln is often
// round the corner (Dürener Str. 200 is collected at Theresienstr. 70z). The
// first pair is what a match is judged on, the second is what the calendar is
// fetched with; confusing them means either rejecting a real address or
// connecting a stranger's.
interface AwbRow {
  street_name?: string
  building_number?: string
  street_code?: string
  zipcode?: string
  user_street_name?: string
  user_building_number?: string
}

async function awbSearch(street: string, hnr: string): Promise<AwbRow[]> {
  const url = new URL(`${AWB_BASE}/api/streets`)
  url.searchParams.set('street_name', street)
  url.searchParams.set('building_number', hnr)
  const res = await fetchWithTimeout(url.toString(), {
    headers: { 'User-Agent': UA, Accept: 'application/json' },
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const body = await res.json().catch(() => null) as { data?: AwbRow[] } | null
  return Array.isArray(body?.data) ? body!.data! : []
}

/// Köln reuses a street name across the villages it absorbed and tells them
/// apart with a two-letter district tag: "Hauptstr. Wi" is Widdersdorf's,
/// "Hauptstr. Zü" is Zündorf's, and the geocoder writes plain "Hauptstraße" for
/// both. The tag is stripped for comparison; **which of them it is, is then
/// settled by the postcode**, never by picking the first.
function awbStreetEq(rowName: string | undefined, target: string): boolean {
  const raw = (rowName || '').trim()
  if (normStreet(raw) === target) return true
  const untagged = raw.replace(/\s+[A-ZÄÖÜ][a-zäöüß]$/, '')
  return untagged !== raw && normStreet(untagged) === target
}

/// The rows that really are the address asked for. Anything the search threw in
/// because it had nothing better is dropped here.
function awbMatches(rows: AwbRow[], street: string, hnr: string, plz?: string): AwbRow[] {
  const target = normStreet(street)
  const wanted = hnr.trim().toLowerCase()
  const exact = rows.filter((r) =>
    awbStreetEq(r.user_street_name, target) &&
    (r.user_building_number || '').trim().toLowerCase() === wanted
  )
  const byPlz = plz ? exact.filter((r) => (r.zipcode || '') === plz) : []
  if (byPlz.length) return byPlz
  // Two districts and no postcode to choose between them: refuse. One of the
  // two would be somebody else's village, and there is no way to tell which.
  if (exact.length > 1) return []
  return exact
}

/// Whether AWB actually holds a plan for this Stellplatz. Some of them are in
/// the address list with no dates behind them at all — a village Hauptstraße and
/// a Stellplatz on Redwitzstr. both answer with an empty calendar — and
/// `supported` has to mean "there are pickup dates", not "the street exists".
/// The JSON is asked rather than the ICS because it is a tenth of the size.
async function awbHasDates(code: string, hnr: string): Promise<boolean> {
  const year = new Date().getUTCFullYear()
  const url = new URL(`${AWB_BASE}/api/calendar`)
  url.searchParams.set('street_code', code)
  url.searchParams.set('building_number', hnr)
  url.searchParams.set('start_year', String(year))
  url.searchParams.set('end_year', String(year + 1))
  url.searchParams.set('start_month', '1')
  url.searchParams.set('end_month', '12')
  url.searchParams.set('form', 'json')
  const res = await fetchWithTimeout(url.toString(), {
    headers: { 'User-Agent': UA, Accept: 'application/json' },
  })
  if (!res.ok) return false
  const body = await res.json().catch(() => null) as { data?: unknown[] } | null
  return Array.isArray(body?.data) && body!.data!.length > 0
}

async function searchStreetsAwb(query: string): Promise<StreetOption[]> {
  const q = (query || '').trim()
  if (q.length < 2) return []
  // House number 1 is only a probe here: it is what makes the search answer at
  // all, and the number the household actually lives at is asked for later.
  const rows = await awbSearch(q, '1')
  const seen = new Set<string>()
  const out: StreetOption[] = []
  for (const r of rows) {
    // The household's own street, not the Stellplatz's: picking "Theresienstr."
    // off a search for "Dürener Str." is not a street anybody lives on here.
    const name = (r.user_street_name || '').trim()
    if (!name || seen.has(name.toLowerCase())) continue
    seen.add(name.toLowerCase())
    // No street_code: it belongs to the Stellplatz, which is decided per house.
    out.push({ name, config: { vendor: 'awbkoeln', street: name } })
  }
  return out.slice(0, 50)
}

/// The house numbers worth asking about, in order. OSM regularly labels a
/// building with the range it occupies — "1-3", "18-24" — and the vendor knows
/// only the single numbers in it, so the first of the range is tried too.
function hnrCandidates(raw: string | undefined): string[] {
  const s = (raw || '').trim()
  if (!s) return []
  const out = [s]
  const head = (s.match(/^\s*([0-9]+\s*[a-zA-Z]?)\s*[-–/,]/) || [])[1]
  if (head) out.push(head.replace(/\s+/g, ''))
  return [...new Set(out)]
}

async function probeAwbKoeln(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const plz = /^[0-9]{5}$/.test(addr.postcode || '') ? addr.postcode! : undefined
  const target = normStreet(addr.street)

  for (const hnr of hnrCandidates(addr.houseNumber)) {
    const hit = awbMatches(await awbSearch(addr.street, hnr), addr.street, hnr, plz)[0]
    if (
      hit && hit.street_code && hit.building_number &&
      await awbHasDates(hit.street_code, hit.building_number.trim()).catch(() => false)
    ) {
      const street = (hit.user_street_name || addr.street).trim()
      const stellplatz = `${(hit.street_name || '').trim()} ${hit.building_number.trim()}`.trim()
      return {
        supported: true,
        town: town.name,
        street,
        config: {
          vendor: 'awbkoeln', street, strasseId: hit.street_code, hnr: hit.building_number.trim(),
          // Kept because it is not the household's address: the bins go out
          // somewhere else, and a family that has just moved in needs telling.
          stellplatz: stellplatz !== `${street} ${hnr}` ? stellplatz : undefined,
        },
      }
    }
  }

  // No number, or a number this street does not carry. Is the street ours at
  // all? Ask again with the numbers the household gave and then with 1, and
  // this time accept any row on the right *street*, whatever its number —
  // asking only about house 1 loses every street that starts at 18.
  // AWB's address list is Stellplätze rather than houses, so it is full of
  // holes: Sülzburgstr. has 5 and 100 but no 50, and Olpener Str. starts
  // answering at 200. A street is therefore only written off after a spread of
  // numbers has missed, not after house 1 has — that alone would have declared
  // a 900-number suburban road unserved.
  for (const hnr of [...hnrCandidates(addr.houseNumber), '1', '2', '5', '10', '20', '50', '100', '200']) {
    const rows = await awbSearch(addr.street, hnr)
    const onStreet = rows.filter((r) => awbStreetEq(r.user_street_name, target))
    const probe = (plz && onStreet.find((r) => (r.zipcode || '') === plz)) || onStreet[0]
    if (!probe) continue
    const street = (probe.user_street_name || addr.street).trim()
    // Street known, this house not: ask for the number rather than connecting
    // the one AWB happened to return.
    return {
      supported: true,
      town: town.name,
      street,
      needsHouseNumber: true,
      config: { vendor: 'awbkoeln', street },
    }
  }
  return null
}

async function readAwbKoeln(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const code = String(cfg.strasseId ?? '')
  // The Stellplatz number carries a letter often enough ("70z") that this is not
  // a digits-only field.
  const hnr = (cfg.hnr || '').trim()
  if (!/^[0-9]{1,8}$/.test(code) || !/^[0-9]{1,6}[a-zA-Z]?$/.test(hnr)) throw new Error('reconnect_required')
  const thisYear = new Date().getUTCFullYear()
  const url = new URL(AWB_ICS)
  url.searchParams.set('street_code', code)
  url.searchParams.set('building_number', hnr)
  // This year and next. The second is usually empty and that is not an error —
  // it is how next year's plan arrives without anybody reconnecting.
  url.searchParams.set('start_year', String(thisYear))
  url.searchParams.set('end_year', String(thisYear + 1))
  url.searchParams.set('start_month', '1')
  url.searchParams.set('end_month', '12')
  // Every fraction. Which bins this address actually has is AWB's answer, not a
  // preference of ours — asking for one it does not have simply returns none.
  // `trigger` is deliberately absent: it would write a VALARM into the file, and
  // reminders here are scheduled on the device.
  for (const bin of ['wertstoff', 'grey', 'brown', 'blue', 'red', 'xmastree']) url.searchParams.set(bin, '1')

  const res = await fetchWithTimeout(url.toString(), {
    headers: { 'User-Agent': UA, Accept: 'text/calendar, */*' },
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const ics = (await res.text()).replace(/^\uFEFF/, '')
  if (!ics.includes('BEGIN:VEVENT')) return []
  const start = new Date(Date.UTC(thisYear - 1, 0, 1))
  const end = new Date(Date.UTC(thisYear + 2, 0, 1))
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const ev of parseIcs(ics, start, end)) {
    // "Papier (blau), Bio (braun) AWB Köln" is one VEVENT for two bins, and it
    // has to become two: the colour dot is picked by matching the title, so a
    // combined one would be filed under whichever fraction happens to be tested
    // first and the other bin would never be drawn.
    const base = ev.title.replace(/\s*AWB\s+K(ö|oe)ln\s*$/i, '').trim()
    for (const part of (base ? base.split(/,\s*/) : []).filter(Boolean)) {
      const dayKey = `${ev.startsAt.slice(0, 10)}:${part}`
      if (seen.has(dayKey)) continue
      seen.add(dayKey)
      out.push({
        ...ev,
        uid: `abfall:awbkoeln:${code}:${hnr}:${dayKey}`,
        title: part,
        // The description is three lines of "your bin is broken? fill in this
        // form", which is not what a pickup date is for.
        notes: cfg.stellplatz ? `Stellplatz: ${cfg.stellplatz}` : null,
        location: cfg.stellplatz ?? cfg.label ?? null,
      })
    }
  }
  return out
}

function towns(p: AbfallProvider): Town[] {
  // One city; streets are searched live and the address validated by the probe.
  return [{ vendor: 'awbkoeln', name: p.town || 'Köln', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'awbkoeln',
  towns,
  searchStreets: (_town, query) => searchStreetsAwb(query),
  probe: probeAwbKoeln,
  read: readAwbKoeln,
}
