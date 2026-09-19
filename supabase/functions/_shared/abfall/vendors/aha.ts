// abfall/vendors/aha.ts — aha Zweckverband Abfallwirtschaft Region Hannover — a
// stateless TYPO3 form over 21 municipalities; the same POST returns the ICS.

import {
  type AbfallConfig,
  type AbfallProvider,
  fetchWithTimeout,
  foldGerman,
  type GeoAddress,
  normStreet,
  parseIcs,
  type ResolveResult,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── aha Region Hannover ─────────────────────────────────────────────────────
//
// One page, `aha-region.de/abholtermine/abfuhrkalender`, with no session, no
// token and no cHash. Every step is a POST of the whole form to it:
//
//   gemeinde=Hannover&von=V                -> <select name="strasse"> of
//        value='02896@Voltastr. / Vahrenwald@Vahrenwald'  (id@label@district)
//   … &strasse=<value>&hausnr=25&hausnraddon=&anzeigen=Suchen
//                                          -> <select name="ladeort"> (or one
//        hidden <input>) of "02896-0025" = "Voltastr. 25, Hannover / Vahrenwald"
//   … &ladeort=<value>&ical=ICAL Jahresübersicht
//                                          -> text/calendar, from today to 31 Dec
//
// **A street label carries its district** ("Voltastr. / Vahrenwald"), and one
// municipality can have the same name in several districts (Hannover has a
// Hauptstr. in Wettbergen and more elsewhere). The geocoder gives no district,
// so each candidate is asked for the house number and the ones that know it
// survive. A number that doesn't exist on that street gets the form back with
// no `ladeort` at all.
//
// **The Ladeort is where the bins are emptied**, and a corner house can have two
// ("Dragonerstr. 28" and "Vahrenwalder Str. 100" for Vahrenwalder Str. 100).
// The one written as the household's own address is taken; otherwise the
// household picks, because the other corner's bins are a different calendar.
// The pick's id carries the street too (`<strasse>|<ladeort>`), since the ICS
// wants street, number and Ladeort together — the Ladeort alone returns the page.
//
// A calendar-year vendor: the ICS starts today and stops on 31 December, and
// nothing moves it (`jahr` is ignored). Next year arrives when aha publishes it.
// Its UIDs are stable, but ours are built from the Ladeort and the day all the
// same. " *" on a title marks a date moved by a holiday and is dropped.
const URL_ = 'https://www.aha-region.de/abholtermine/abfuhrkalender'

// The form's own municipality names, and how an address writes them.
const DISPLAY: Record<string, string> = { 'Neustadt a. Rbge.': 'Neustadt am Rübenberge' }

async function postForm(fields: Record<string, string>): Promise<Response> {
  const res = await fetchWithTimeout(URL_, {
    method: 'POST',
    headers: { 'User-Agent': UA, Accept: 'text/html,text/calendar,*/*', 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(fields).toString(),
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return res
}

const decode = (s: string) =>
  s.replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#0?39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>')

// The first letter the form files a street under: Ä, Ö and Ü sit under A, O, U.
const letterOf = (street: string) => foldGerman(street.trim()).charAt(0).toUpperCase()

interface Street { value: string; label: string; base: string; district: string }

async function streets(gemeinde: string, letter: string): Promise<Street[]> {
  const html = await (await postForm({ gemeinde, von: letter })).text()
  const sel = html.match(/<select[^>]*name="strasse"[\s\S]*?<\/select>/i)?.[0] ?? ''
  return [...sel.matchAll(/<option value='([^']*)'[^>]*>([^<]*)</g)].map((m) => {
    const value = decode(m[1])
    const label = decode(m[2]).trim()
    const [base, district = ''] = label.split(' / ')
    return { value, label, base: base.trim(), district: district.trim() }
  })
}

interface Ladeort { value: string; label: string }

/// The collection points for one house, or none when the street doesn't have it.
async function ladeorte(gemeinde: string, st: Street, hnr: string, zusatz: string): Promise<Ladeort[]> {
  const html = await (await postForm({
    gemeinde, jsaus: '', von: letterOf(st.base), strasse: st.value, hausnr: hnr, hausnraddon: zusatz, anzeigen: 'Suchen',
  })).text()
  const single = html.match(/<input[^>]*name="ladeort"[^>]*>/i)?.[0]
  if (single) {
    const value = single.match(/value="([^"]*)"/)?.[1]
    return value ? [{ value: decode(value), label: `${st.base} ${hnr}${zusatz}` }] : []
  }
  const sel = html.match(/<select[^>]*name="ladeort"[\s\S]*?<\/select>/i)?.[0] ?? ''
  return [...sel.matchAll(/<option value="([^"]*)"[^>]*>([^<]*)</g)]
    .map((m) => ({ value: decode(m[1]), label: decode(m[2]).trim() }))
    .filter((l) => l.value)
}

function splitNumber(nr: string): { hnr: string; zusatz: string } {
  const m = (nr || '').trim().match(/^(\d+)\s*(.*)$/)
  return m ? { hnr: m[1], zusatz: m[2].replace(/\s+/g, '').toLowerCase() } : { hnr: '', zusatz: '' }
}

// "Voltastr. 25, Hannover / Vahrenwald" is the household's own door when it
// begins with their street and number.
const ownDoor = (l: Ladeort, st: Street, hnr: string, zusatz: string) => {
  const head = l.label.split(',')[0]
  return normStreet(head) === normStreet(`${st.base} ${hnr}${zusatz}`)
}

async function fetchIcs(gemeinde: string, strasse: string, hnr: string, zusatz: string, ladeort: string): Promise<string> {
  const base = strasse.split('@')[1]?.split(' / ')[0] ?? strasse
  const res = await postForm({
    gemeinde, jsaus: '', von: letterOf(base), strasse, hausnr: hnr, hausnraddon: zusatz, ladeort,
    ical: 'ICAL Jahresübersicht',
  })
  return res.text()
}

async function probeAha(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  const gemeinde = town.city
  if (!gemeinde || !addr.street) return null
  const target = normStreet(addr.street)
  const cands = (await streets(gemeinde, letterOf(addr.street))).filter((s) => normStreet(s.base) === target)
  if (!cands.length) return null
  const street = cands[0].base
  const { hnr, zusatz } = splitNumber(addr.houseNumber || '')
  const cfg = { vendor: 'aha' as const, city: gemeinde, hnr: hnr || undefined, zusatz: zusatz || undefined }
  // No number, or one no district of this street has: the form has no house
  // list to offer, so the number is asked for again.
  const needsNumber: ResolveResult = {
    supported: true, town: town.name, street, needsHouseNumber: true, config: { ...cfg, street: cands[0].value },
  }
  if (!hnr) return needsNumber

  const found: Array<{ st: Street; l: Ladeort }> = []
  for (const st of cands.slice(0, 8)) {
    for (const l of await ladeorte(gemeinde, st, hnr, zusatz).catch(() => [] as Ladeort[])) found.push({ st, l })
  }
  if (!found.length) return needsNumber

  const own = found.filter(({ st, l }) => ownDoor(l, st, hnr, zusatz))
  const pick = own.length === 1 ? own[0] : found.length === 1 ? found[0] : undefined
  if (pick) {
    const ics = await fetchIcs(gemeinde, pick.st.value, hnr, zusatz, pick.l.value).catch(() => '')
    if (ics.includes('BEGIN:VEVENT')) {
      return {
        supported: true, town: town.name, street,
        config: { ...cfg, street: pick.st.value, hnrId: `${pick.st.value}|${pick.l.value}` },
      }
    }
  }
  // Two districts know the number, or the house has two collection points: the
  // household picks, and each chip names the place in aha's own words.
  return {
    supported: true, town: town.name, street, needsHouseNumber: true,
    hausNrList: found.map(({ st, l }) => ({
      id: `${st.value}|${l.value}`,
      nr: l.label.includes('/') || !st.district ? l.label : `${l.label} / ${st.district}`,
    })),
    config: { ...cfg, street: cands[0].value },
  }
}

async function readAha(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const [strasse, ladeort] = String(cfg.hnrId ?? '').split('|')
  if (!cfg.city || !strasse || !/^[0-9]{1,6}-[0-9]{1,6}$/.test(ladeort || '') || !cfg.hnr) {
    throw new Error('reconnect_required')
  }
  const ics = await fetchIcs(cfg.city, strasse, cfg.hnr, cfg.zusatz ?? '', ladeort)
  if (!ics.includes('BEGIN:VCALENDAR')) throw new Error('reconnect_required')
  const y = new Date().getUTCFullYear()
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const ev of parseIcs(ics, new Date(Date.UTC(y - 1, 0, 1)), new Date(Date.UTC(y + 2, 0, 1)))) {
    // "Restabfall 660/1.100 Liter *" -> "Restabfall": the size is the container's,
    // and the star marks a date a holiday moved.
    const title = ev.title
      .replace(/\s*\*\s*$/, '')
      .replace(/\s+[\d./]+\s*Liter\b.*$/i, '')
      .replace(/^Abfuhr\s+/i, '')
      .trim() || 'Abfuhr'
    const day = ev.startsAt.slice(0, 10)
    const k = `${day}:${title}`
    if (seen.has(k)) continue
    seen.add(k)
    const start = new Date(`${day}T00:00:00Z`)
    out.push({
      uid: `abfall:aha:${ladeort}:${k}`,
      title,
      notes: null,
      location: cfg.label ?? ev.location ?? null,
      startsAt: start.toISOString(),
      endsAt: new Date(start.getTime() + 86_400_000).toISOString(),
      allDay: true,
    })
  }
  return out
}

/// Every municipality on the form; `city` is the value posted back.
async function towns(p: AbfallProvider): Promise<Town[]> {
  const res = await fetchWithTimeout(URL_, { headers: { 'User-Agent': UA, Accept: 'text/html,*/*' } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const html = await res.text()
  const sel = html.match(/<select[^>]*name="gemeinde"[\s\S]*?<\/select>/i)?.[0] ?? ''
  return [...sel.matchAll(/<option value="([^"]*)"/g)]
    .map((m) => decode(m[1]).trim())
    .filter(Boolean)
    .map((g) => ({ vendor: 'aha' as const, name: DISPLAY[g] ?? g, provider: p.id, city: g }))
}

export const adapter: VendorAdapter = {
  family: 'aha',
  towns,
  probe: probeAha,
  read: readAha,
}
