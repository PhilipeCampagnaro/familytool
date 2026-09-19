// abfall/vendors/zah.ts — ZAH Zweckverband Abfallwirtschaft Hildesheim — the
// Abfuhrkalender on hildesheim.abfuhrkalender.de, for all twenty Gemeinden of
// the Landkreis.

import {
  type AbfallConfig,
  type AbfallProvider,
  dayEvents,
  decodeEntities,
  fetchWithTimeout,
  type GeoAddress,
  type HausNr,
  icsDays,
  normStreet,
  type ResolveResult,
  restRhythm,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── ZAH (hildesheim.abfuhrkalender.de, ASP.NET WebForms) ─────────────────────
//
//   GET  /                               Gemeinde dropdown + __VIEWSTATE
//   POST / __EVENTTARGET=ddGemeinde      -> Ortsteil dropdown
//   POST / __EVENTTARGET=ddOrtsteil (-1 = "Alle")  -> every street, value = streetID
//   GET  /ICalendar/Index.aspx?year=<y>&streetID=<id>   text/calendar, no session
//
// The street ids are unique across the Landkreis, so a read is one stateless
// GET per year; only finding the street walks the postbacks. Long streets are
// split into entries named for their numbers in free German — "Bahnhofsallee
// 1-12 / 38-40", "Goschenstr. ohne Nr. 31-41", "Berliner Str. nur ungerade + 98"
// — so the number picks one where the name is plain ranges and lists, and the
// household picks from the vendor's own wording where it is not.
//
// **Restabfall comes in two rhythms that share half their days.** The calendar
// writes a day both rhythms are emptied as "Restabfall (14tägige und
// vierwöchentliche Abfuhr" (sic, no closing bracket) and the others as
// "Restabfall (14tägige Abfuhr)". So a shared day is read as two lines, one per
// rhythm, and the household's pick keeps one: fortnightly keeps every day,
// four-weekly every other.
const BASE = 'https://hildesheim.abfuhrkalender.de/'

/// The Gemeinden, by the vendor's id. Fixed by the Landkreis, so kept here
/// rather than fetched on every town list.
const GEMEINDEN: Record<string, string> = {
  '11': 'Alfeld', '15': 'Algermissen', '10': 'Bad Salzdetfurth', '4': 'Bockenem', '16': 'Diekholzen',
  '3': 'Duingen', '18': 'Eime', '19': 'Elze', '17': 'Freden', '9': 'Giesen', '13': 'Gronau', '8': 'Harsum',
  '2': 'Hildesheim', '14': 'Holle', '12': 'Lamspringe', '5': 'Nordstemmen', '1': 'Sarstedt', '7': 'Schellerten',
  '20': 'Sibbesse', '6': 'Söhlde',
}

// ── The postbacks ───────────────────────────────────────────────────────────

interface Page { html: string; cookie: string }

function fields(html: string): URLSearchParams {
  const out = new URLSearchParams()
  for (const m of html.matchAll(/<input type="hidden" name="([^"]*)" id="[^"]*" value="([^"]*)"/g)) {
    out.set(m[1], decodeEntities(m[2]))
  }
  for (const m of html.matchAll(/<select name="([^"]*)"[^>]*>([\s\S]*?)<\/select>/g)) {
    const sel = m[2].match(/<option selected="selected" value="([^"]*)"/)
    if (sel) out.set(m[1], decodeEntities(sel[1]))
  }
  return out
}

function options(html: string, name: string): Array<{ value: string; text: string }> {
  const body = html.match(new RegExp(`<select name="${name}"[^>]*>([\\s\\S]*?)</select>`))?.[1] ?? ''
  return [...body.matchAll(/<option[^>]*value="([^"]*)"[^>]*>([^<]*)/g)]
    .map((m) => ({ value: decodeEntities(m[1]), text: decodeEntities(m[2]).trim() }))
    .filter((o) => o.value)
}

async function page(prev?: Page, set?: Record<string, string>): Promise<Page> {
  const headers: Record<string, string> = { 'User-Agent': UA, Accept: 'text/html' }
  let body: URLSearchParams | undefined
  if (prev && set) {
    body = fields(prev.html)
    for (const [k, v] of Object.entries(set)) body.set(k, v)
    headers['Content-Type'] = 'application/x-www-form-urlencoded'
    if (prev.cookie) headers.Cookie = prev.cookie
  }
  const res = await fetchWithTimeout(BASE, { method: body ? 'POST' : 'GET', headers, body })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const cookie = (res.headers.get('set-cookie') || '').split(/,(?=[^;]+=)/).map((c) => c.split(';')[0].trim())
    .filter(Boolean).join('; ') || prev?.cookie || ''
  return { html: await res.text(), cookie }
}

async function streets(gemeindeId: string): Promise<Array<{ value: string; text: string }>> {
  const start = await page()
  const gemeinde = await page(start, { ddGemeinde: gemeindeId, __EVENTTARGET: 'ddGemeinde' })
  const all = await page(gemeinde, { ddOrtsteil: '-1', __EVENTTARGET: 'ddOrtsteil' })
  return options(all.html, 'ddStrasse')
}

async function yearIcs(streetId: string, year: number): Promise<string> {
  const res = await fetchWithTimeout(`${BASE}ICalendar/Index.aspx?year=${year}&streetID=${encodeURIComponent(streetId)}`,
    { headers: { 'User-Agent': UA, Accept: 'text/calendar' } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return res.text()
}

// ── Part-street entries ─────────────────────────────────────────────────────

/// "Bahnhofsallee 1-12 / 38-40" -> ["Bahnhofsallee", "1-12 / 38-40"];
/// "Goschenstr. ohne Nr. 31-41" -> ["Goschenstr.", "ohne Nr. 31-41"].
function split(name: string): [string, string] {
  const m = name.match(/^(.*?)\s+((?:nur|ohne|Nr\.?)\b.*|\d.*)$/i)
  return m ? [m[1].trim(), m[2].trim()] : [name.trim(), '']
}

/// Does a plain list of numbers and ranges ("1-12 / 38-40", "1-9, 18+20, 41",
/// "Nr. 13-23") hold the number? Null where the words say more than numbers
/// can ("ohne", "ungerade", "gerade") — the household decides those.
function holds(part: string, nr: string): boolean | null {
  if (/ohne|gerade|ungr/i.test(part)) return null
  const n = Number(nr.match(/^\d+/)?.[0])
  if (!n) return null
  const bits = part.replace(/^(nur\s+)?(Nr\.?\s*)?/i, '').split(/\s*(?:[,+/]|\bu\.|\bund\b)\s*/i).filter(Boolean)
  let any = false
  for (const b of bits) {
    const r = b.match(/^(\d+)[a-z]?(?:\s*-\s*(\d+)[a-z]?)?$/i)
    if (!r) return null
    any = true
    const lo = Number(r[1]), hi = Number(r[2] ?? r[1])
    if (n >= lo && n <= hi) return true
  }
  return any ? false : null
}

/// "LOCATION:Hildesheim\, Mitte\, Almsstr." -> "Mitte".
function ortsteil(ics: string): string {
  const loc = ics.match(/\nLOCATION:([^\r\n]*)/)?.[1] ?? ''
  return loc.split(/\\,\s*/).map((s) => s.trim())[1] ?? ''
}

async function probeZah(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street || !town.city) return null
  const target = normStreet(addr.street)
  const hits = (await streets(town.city)).filter((o) => normStreet(split(o.text)[0]) === target)
  if (!hits.length) return null
  const street = split(hits[0].text)[0]
  const cfg = { vendor: 'zah' as const, city: town.name, street }
  if (hits.length === 1) return { supported: true, town: town.name, street, config: { ...cfg, hnrId: hits[0].value } }

  const nr = (addr.houseNumber || '').replace(/\s+/g, '').toLowerCase()
  if (nr) {
    const fits = hits.filter((h) => holds(split(h.text)[1], nr) === true)
    const unsure = hits.filter((h) => holds(split(h.text)[1], nr) === null)
    if (fits.length === 1 && !unsure.length) {
      return { supported: true, town: town.name, street, config: { ...cfg, hnrId: fits[0].value } }
    }
  }
  // Entries the name cannot tell apart — the same street in two Ortsteile —
  // are told apart by the Ortsteil their calendar names.
  const y = new Date().getUTCFullYear()
  const labels = await Promise.all(hits.map(async (h) => {
    const part = split(h.text)[1]
    if (part && hits.filter((o) => split(o.text)[1] === part).length === 1) return part
    const where = ortsteil(await yearIcs(h.value, y).catch(() => ''))
    return [part, where].filter(Boolean).join(' · ') || h.text
  }))
  const hausNrList: HausNr[] = hits.map((h, i) => ({ id: h.value, nr: labels[i] }))
  return { supported: true, town: town.name, street, needsHouseNumber: true, hausNrList, config: cfg }
}

// ── Titles ──────────────────────────────────────────────────────────────────

/// "Abfuhr Restabfall (14tägige und vierwöchentliche Abfuhr (verschoben)" ->
/// two lines, "Restabfall (14-täglich)" and "Restabfall (Vierwöchentlich)", noted
/// "verschoben". Every other title loses its "Abfuhr " and keeps the rest.
function lines(summary: string): Array<{ title: string; notes: string | null }> {
  let t = summary.replace(/^Abfuhr\s+/i, '').trim()
  const moved = /\(verschoben\)\s*$/i.test(t)
  t = t.replace(/\s*\(verschoben\)\s*$/i, '').trim()
  const notes = moved ? 'verschoben' : null
  const rest = t.match(/^(Rest\w*)\s*\((.*?)\)?$/)
  if (!rest) return [{ title: t, notes }]
  const words = rest[2].replace(/\s*Abfuhr\s*$/i, '').split(/\s+und\s+/i)
  return words.map((w) => {
    const r = /14\s*-?\s*t[äa]gig/i.test(w) ? '14-täglich'
      : /vierw[öo]chentlich/i.test(w) ? 'Vierwöchentlich'
      : /^w[öo]chentlich/i.test(w) ? 'Wöchentlich'
      : w.trim()
    return { title: `${rest[1]} (${r})`, notes }
  })
}

async function readZah(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const id = cfg.hnrId != null ? String(cfg.hnrId) : ''
  if (!/^\d{1,6}$/.test(id)) throw new Error('reconnect_required')
  const y = new Date().getUTCFullYear()
  const [now, next] = await Promise.all([yearIcs(id, y), yearIcs(id, y + 1).catch(() => '')])
  const rows = [...icsDays(now), ...icsDays(next)]
    .flatMap(({ day, title }) => lines(title).map((l) => ({ day, ...l })))
  if (!rows.length) throw new Error('reconnect_required')
  return dayEvents(rows, `abfall:zah:${id}`, cfg.label ?? null)
}

function towns(p: AbfallProvider): Town[] {
  return Object.entries(GEMEINDEN).map(([id, name]) => ({ vendor: 'zah' as const, name, city: id, provider: p.id }))
}

export const adapter: VendorAdapter = {
  family: 'zah',
  towns,
  probe: probeZah,
  rhythm: restRhythm,
  read: readZah,
}
