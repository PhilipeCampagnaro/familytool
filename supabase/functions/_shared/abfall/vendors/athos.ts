// abfall/vendors/athos.ts — the Athos "WasteManagement" portal (EDG Dortmund and
// others) — a stateful form walk whose result page lists every pickup of the year.

import { ABFALL_PROVIDERS } from "../../abfall_providers.ts";
import {
  type AbfallConfig,
  type AbfallProvider,
  fetchWithTimeout,
  type GeoAddress,
  normStreet,
  parseIcs,
  type ResolveResult,
  restRhythm,
  type RhythmTag,
  type SyncedEvent,
  type Town,
  townMatches,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── Athos WasteManagement (PLATFORM family) ─────────────────────────────────
//
// A Java servlet sold to waste authorities as their "Kundenportal". Every tenant
// sits at `https://<host>/<tenant>/WasteManagementServlet` and walks the same
// four steps, each a multipart POST carrying the session's hidden fields:
//
//   GET  ?SubmitAction=wasteDisposalServices&InFrameMode=TRUE -> SessionId
//   POST SubmitAction=CITYCHANGED   Ort=<…>            -> the street <select>
//   POST SubmitAction=STREETCHANGED Strasse=<…>        -> the house numbers
//   POST SubmitAction=forward       Hausnummer=<…>     -> "Terminliste"
//
// **The state lives on the server and no step may be skipped** — a fresh session
// posting all three fields at once is answered "Bitte wählen Sie eine
// vollständige Adresse." So a read is four requests, like München's form walk.
//
// **Why the result page and not the portal's own iCal link.** The Terminliste
// offers `WasteManagementServiceServlet?ApplicationName=Calendar&SubmitAction=sync
// &StandortID=<n>&AboID=<any>&Fra=<fractions>` — keyless, and `AboID` is not
// checked. But how far it looks ahead is a tenant setting: Schaumburg's runs to
// the end of the year, **Dortmund's stops after the next two pickups per bin**,
// and no parameter (`Zeitraum`, `Von`/`Bis`, `Year`, `Anzahl`) moves it. A bin
// calendar that goes blank a fortnight out is not one, so the page is read
// instead. It is generated markup with stable ids, which is what makes that safe:
//
//   <P ID="LabelR[1100](02-w)">Restabfall</P>
//   <P ID="TermineDatumR[1100](02-w)_1">Mo. 21.09.2026 </P>
//
// The part after `Label`/`TermineDatum` is the container's key, so each date is
// filed under its own bin without depending on the page's layout.
//
// **Two things vary by tenant**, and both are read off the form rather than
// configured:
//   - `Ort` is the municipality in a Landkreis (Schaumburg, Karlsruhe) but the
//     street's **first letter** in Dortmund ("A", "Ä", "I.", "II."), because one
//     city has too many streets for one dropdown.
//   - the house number is a `<select>` of the numbers the tenant knows (Dortmund)
//     or a text field plus `Hausnummerzusatz` (the Landkreise).
//
// **Option values are HTML-escaped and use `&nbsp;` as their space**
// ("Kahle&nbsp;Hege", "5&nbsp;a"). The browser posts the decoded value, a U+00A0
// and not a space, and the server compares literally — so what is posted is
// exactly the option's own decoded value, never a normalised copy of it.
//
// **Bielefeld's build hides the form in a script and asks two more things.**
// The page is `var text = '<!DOCTYPE HTML>…'` written into an iframe, so every
// answer is unwrapped before it is read. It also carries a checkbox per bin
// (all ticked) and a `Zeitraum` radio of **October-to-September years**
// ("01.10.2026 - 30.09.2027"). Ticked boxes and the ticked radio are posted
// back on every step, as a browser would. The read walks once per `Zeitraum`
// and keeps the union, because on 18 September the ticked year is the one that
// starts in a fortnight and the pickups until then are only in the other.
//
// A container that serves several households ("Abweichende Behälterstandorte:
// Ostwall 6") is still this address's calendar; the page says whose it is, and
// the bins are the ones this household puts out. Two bins of one fraction in
// different sizes ("Wertstoffe 1100 l" and "240 l") fall on the same day and
// collapse to one row.

const SERVLET = 'WasteManagementServlet'

// The base URL travels in the stored config, and the read would otherwise POST
// wherever a row said to. Only a tenant one of our own provider rows names is
// ever contacted.
const TENANTS = new Set(ABFALL_PROVIDERS.filter((p) => p.family === 'athos' && p.host).map((p) => p.host!))

const ENTITIES: Record<string, string> = {
  nbsp: ' ', amp: '&', quot: '"', apos: "'", lt: '<', gt: '>',
  auml: 'ä', ouml: 'ö', uuml: 'ü', Auml: 'Ä', Ouml: 'Ö', Uuml: 'Ü', szlig: 'ß',
  eacute: 'é', egrave: 'è', aacute: 'á', agrave: 'à', oacute: 'ó', ccedil: 'ç',
}

/// The value exactly as a browser would post it — `&nbsp;` stays U+00A0.
function unescapeHtml(s: string): string {
  return (s || '')
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCharCode(parseInt(n, 16)))
    .replace(/&([a-z]+);/gi, (m, name) => ENTITIES[name] ?? m)
}

/// For comparing and showing: every kind of space is a space.
const plain = (s: string) => unescapeHtml(s).replace(/\s+/g, ' ').trim()

// "5 a", "5a", "5 A" are one house; "15 - 15 a" and "15-15a" one range.
const nrKey = (s: string) => plain(s).toLowerCase().replace(/\s+/g, '')

// `ApplicationName` and the first page's name are read off the form, not
// assumed: Hameln-Pyrmont's build posts `com.athos.kd.hameln.abfuhrtermine.
// CheckAbfuhrTermineParameterModel` where Dortmund's posts `…abfterm.
// CheckAbfuhrTermineParameterBusinessCase`, and the wrong one is answered with
// the portal's "Willkommen" page and no error.
interface Session {
  base: string; sessionId: string; cookie: string; app: string; page: string
  /// The ticked checkboxes and radios, posted back on every step.
  sticky: Record<string, string>
  /// Every `Zeitraum` a tenant offers (Bielefeld), empty elsewhere.
  periods: string[]
}

const hidden = (html: string, name: string) =>
  html.match(new RegExp(`NAME="${name}"[^>]*VALUE="([^"]*)"`, 'i'))?.[1]

/// Bielefeld's answer is the real page as a JS string literal; unwrap it.
function unwrap(html: string): string {
  const m = html.match(/var\s*text\s*=\s*'((?:\\.|[^'\\])*)'\s*;/)
  // Only a page that is a whole document — any other script's `text` stays put.
  if (!m || !/^\s*<!DOCTYPE/i.test(m[1])) return html
  return m[1].replace(/\\(.)/g, (_, c) => (c === 'n' ? '\n' : c))
}

const attr = (tag: string, name: string) =>
  tag.match(new RegExp(`\\b${name}="([^"]*)"`, 'i'))?.[1]

function sticky(html: string): { sticky: Record<string, string>; periods: string[] } {
  const out: Record<string, string> = {}
  const periods: string[] = []
  for (const [tag] of html.matchAll(/<INPUT\b[^>]*>/gi)) {
    const type = (attr(tag, 'TYPE') || '').toLowerCase()
    const name = attr(tag, 'NAME')
    if (!name || (type !== 'checkbox' && type !== 'radio')) continue
    const value = type === 'checkbox' ? (attr(tag, 'VALUE') ?? 'on') : unescapeHtml(attr(tag, 'VALUE') || '')
    if (type === 'radio' && name === 'Zeitraum') periods.push(value)
    if (/\bCHECKED\b/i.test(tag)) out[name] = value
  }
  return { sticky: out, periods }
}

async function open(base: string): Promise<{ s: Session; html: string }> {
  const res = await fetchWithTimeout(`${base}/${SERVLET}?SubmitAction=wasteDisposalServices&InFrameMode=TRUE`, {
    headers: { 'User-Agent': UA, Accept: 'text/html,*/*' },
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const html = unwrap(await res.text())
  const sessionId = hidden(html, 'SessionId')
  const app = hidden(html, 'ApplicationName')
  if (!sessionId || !app) throw new Error('abfall upstream: no Athos session')
  const page = hidden(html, 'PageName') || 'Lageadresse'
  const cookie = (res.headers.get('set-cookie') || '')
    .split(/,(?=\s*[A-Za-z0-9_-]+=)/)
    .map((c) => c.split(';')[0].trim())
    .filter(Boolean)
    .join('; ')
  return { s: { base, sessionId, cookie, app, page, ...sticky(html) }, html }
}

async function post(s: Session, action: string, fields: Record<string, string>): Promise<string> {
  const form = new FormData()
  const all: Record<string, string> = {
    ApplicationName: s.app, SessionId: s.sessionId, PageName: s.page, SubmitAction: action,
    Ajax: 'false', InFrameMode: 'TRUE', Method: 'POST', IsLastPage: 'false', IsSubmitPage: 'false',
    ...s.sticky,
    ...fields,
  }
  for (const [k, v] of Object.entries(all)) form.append(k, v)
  const res = await fetchWithTimeout(`${s.base}/${SERVLET}`, {
    method: 'POST',
    headers: { 'User-Agent': UA, Accept: 'text/html,*/*', ...(s.cookie ? { Cookie: s.cookie } : {}) },
    body: form,
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return unwrap(await res.text())
}

/// The raw (still escaped) option values of one `<select>`, blank one dropped.
function options(html: string, name: string): string[] {
  const sel = html.match(new RegExp(`<SELECT NAME="${name}"[\\s\\S]*?</SELECT>`, 'i'))?.[0]
  if (!sel) return []
  return [...sel.matchAll(/<OPTION VALUE="([^"]*)"/gi)].map((m) => m[1]).filter((v) => v !== '')
}

const hasTextNumber = (html: string) => /<INPUT NAME="Hausnummer"/i.test(html)

// Dortmund's `Ort` is a letter: the street's own first one, or the Roman
// numeral a handful of streets start with ("I. Kampstr." files under "I.").
const isLetterOrt = (vals: string[]) => vals.length > 0 && vals.every((v) => plain(v).length <= 3)

function ortFor(vals: string[], street: string, town: string): string | undefined {
  if (isLetterOrt(vals)) {
    const roman = street.match(/^(I{1,3}\.)\s/)?.[1]
    if (roman && vals.includes(roman)) return roman
    const first = street.trim().charAt(0).toUpperCase()
    return vals.find((v) => plain(v) === first)
  }
  const t = plain(town).toLowerCase()
  return vals.find((v) => plain(v).toLowerCase() === t)
    ?? vals.find((v) => townMatches(plain(v).toLowerCase(), t))
}

interface Walk {
  s: Session; ort: string; strasse: string; streetHtml: string
  /// Every option the name matched, this one included. More than one where the
  /// tenant lists a name once per Ortsteil — Saarbrücken has four
  /// Bahnhofstraßen, "(Bübingen)", "(Scheidt)", … — and then the house decides.
  alternatives: string[]
}

/// Steps one to three: the session, the Ort and the street. Null when the tenant
/// has no such street.
async function walkToStreet(
  base: string, street: string, town: string, ortHint?: string, period?: string,
): Promise<Walk | null> {
  const { s, html } = await open(base)
  if (period) s.sticky.Zeitraum = period
  const ort = ortHint ?? ortFor(options(html, 'Ort'), street, town)
  if (!ort) return null
  const cityHtml = await post(s, 'CITYCHANGED', { Ort: unescapeHtml(ort), Strasse: '', Hausnummer: '' })
  // The stored option exactly, when there is one: normStreet drops the Ortsteil
  // in brackets, and a read that matched loosely would walk the first
  // Bahnhofstraße in the list rather than the household's.
  const all = options(cityHtml, 'Strasse')
  const exact = all.filter((v) => plain(v) === plain(street))
  const want = normStreet(plain(street))
  const hits = exact.length ? exact : all.filter((v) => normStreet(plain(v)) === want)
  if (!hits.length) return null
  const strasse = unescapeHtml(hits[0])
  const streetHtml = await post(s, 'STREETCHANGED', { Ort: unescapeHtml(ort), Strasse: strasse, Hausnummer: '' })
  // Saarbrücken asks which containers the household has — "Restmüll:
  // Wöchentlich / 2-wöchentlich / 4-wöchentlich", Bio, Papier, Gelb — ticks
  // none, and answers an unticked form with no list at all. Every box is ticked
  // and the household's rhythm is picked from the result instead (RhythmChoice).
  const boxes = [...streetHtml.matchAll(/<INPUT\b[^>]*NAME="(ContainerGewaehlt_\d+)"[^>]*>/gi)]
  if (boxes.length && !boxes.some((b) => /\bCHECKED\b/i.test(b[0]))) for (const b of boxes) s.sticky[b[1]] = 'on'
  return { s, ort: unescapeHtml(ort), strasse, streetHtml, alternatives: hits.map(unescapeHtml) }
}

/// Step four: the Terminliste for one house, or '' when the tenant refused it.
async function walkToList(w: Walk, hnr: string, zusatz: string): Promise<string> {
  const fields: Record<string, string> = { Ort: w.ort, Strasse: w.strasse, Hausnummer: hnr }
  if (hasTextNumber(w.streetHtml)) fields.Hausnummerzusatz = zusatz
  const html = await post(w.s, 'forward', fields)
  return /ID="PageName"[^>]*VALUE="Terminliste"/i.test(html) ? html : ''
}

interface Pickup { day: string; title: string }

const RHYTHM_WORD: Record<number, string> = { 7: 'wöchentlich', 14: '14-täglich', 28: '4-wöchentlich' }

/// Restmüll's rhythms, and Pforzheim's "Großmüllbehälter 1100 L" beside them —
/// the block container is the other answer to "which Restmüll bin is yours".
function rhythmAthos(title: string): RhythmTag | null {
  if (/^Großmüllbehälter\b/i.test(title)) return { bin: 'Restmüll', option: title }
  return restRhythm(title)
}

function parseList(html: string): Pickup[] {
  const labels = new Map<string, string>()
  for (const m of html.matchAll(/ID="Label([^"]+)">([^<]*)</gi)) labels.set(m[1], plain(m[2]))
  // Bielefeld numbers the label ("Label1M") but not its dates ("TermineDatumM_1").
  for (const [k, v] of [...labels]) {
    const bare = k.match(/^\d+(\D.*)$/)?.[1]
    if (bare && !labels.has(bare)) labels.set(bare, v)
  }
  // Pforzheim prints weekly and fortnightly Restmüll under one word, "Restmüll",
  // and only the key tells them apart: RM7, RM14. A label two keys share gets
  // the rhythm its key names, or the key itself, so they stay two lines.
  const count = new Map<string, number>()
  for (const v of labels.values()) count.set(v, (count.get(v) ?? 0) + 1)
  for (const [k, v] of labels) {
    if ((count.get(v) ?? 0) < 2) continue
    const days = Number(k.match(/\D(\d+)$/)?.[1])
    const word = RHYTHM_WORD[days] ?? k
    labels.set(k, `${v} (${word})`)
  }
  const out: Pickup[] = []
  for (const m of html.matchAll(/ID="TermineDatum([^"]+)_\d+">[^<]*?(\d{2})\.(\d{2})\.(\d{4})/gi)) {
    const title = labels.get(m[1])
    if (title) out.push({ day: `${m[4]}-${m[3]}-${m[2]}`, title })
  }
  // Augsburg's build: a heading per bin (`ID="HeadinfoRM"` + <P>Restmüll</P>)
  // followed by its table of date cells (`…DialogComponent.DateRM`). The ids do
  // not always agree ("HeadinfoPap" over "DatePapier"), so a date belongs to the
  // heading above it.
  let head = ''
  for (const m of html.matchAll(/ID="Headinfo\w+"[^>]*>\s*<P[^>]*>([^<]*)<|NAME="WasteDisposalServicesDialogComponent\.Date\w+"[^>]*>\s*(\d{2})\.(\d{2})\.(\d{4})/gi)) {
    if (m[1] !== undefined) head = plain(m[1])
    else if (head) out.push({ day: `${m[4]}-${m[3]}-${m[2]}`, title: head })
  }
  return out
}

/// The portal's own subscription link, as printed on the Terminliste.
function icsLink(html: string, base: string): string | undefined {
  const raw = html.match(/(?:https|webcal):\/\/[^"'<\s]*WasteManagementServiceServlet\?[^"'<\s]*/i)?.[0]
  if (!raw) return undefined
  const url = unescapeHtml(raw).replace(/^webcal:/i, 'https:')
  // Only ever the tenant it came from.
  return url.startsWith(`${base}/`) ? url : undefined
}

// "Restabfall 1100 l 02-wöchentl." -> "Restabfall"; "Wertstoff (gewerblich)
// 2-Rad 02-woechentl." -> "Wertstoff (gewerblich)" — the page's own label.
const icsTitle = (s: string) =>
  s.replace(/\s+(\d+\s*l\b|\d+-Rad\b|\d+-w\S*chentl\.?).*$/i, '').trim()

async function readIcs(url: string): Promise<Pickup[]> {
  const res = await fetchWithTimeout(url, { headers: { 'User-Agent': UA, Accept: 'text/calendar, */*' } })
  if (!res.ok) return []
  const ics = await res.text()
  if (!ics.includes('BEGIN:VEVENT')) return []
  const y = new Date().getUTCFullYear()
  return parseIcs(ics, new Date(Date.UTC(y - 1, 0, 1)), new Date(Date.UTC(y + 2, 0, 1)))
    .map((e) => ({ day: e.startsAt.slice(0, 10), title: icsTitle(e.title) }))
    .filter((p) => p.title)
}

const lastDay = (ps: Pickup[]) => ps.reduce((m, p) => (p.day > m ? p.day : m), '')

function splitNumber(nr: string): { hnr: string; zusatz: string } {
  const m = plain(nr).match(/^(\d+)\s*(.*)$/)
  return m ? { hnr: m[1], zusatz: m[2].trim() } : { hnr: plain(nr), zusatz: '' }
}

async function probeAthos(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  const base = town.host
  if (!base || !addr.street) return null
  let w = await walkToStreet(base, addr.street, town.name, town.city).catch(() => null)
  if (!w) return null
  // One name in several Ortsteile: the ones whose list has this house are
  // candidates. One is the household's street; several (Saarbrücken has a
  // Bahnhofstraße 31 at the Hauptbahnhof and another in Dudweiler) are offered
  // as chips naming the Ortsteil, each carrying its own street in the id
  // ("<street>|<number>", see readAthos). None, or no number: refused — the
  // wrong Ortsteil's calendar is somebody else's bins.
  if (w.alternatives.length > 1) {
    if (!addr.houseNumber) return null
    const { hnr, zusatz } = splitNumber(addr.houseNumber)
    const fits: Array<{ strasse: string; nr: string }> = []
    for (const alt of w.alternatives) {
      const a = await walkToStreet(base, alt, town.name, w.ort).catch(() => null)
      if (!a) continue
      const text = hasTextNumber(a.streetHtml)
      const nr = text ? hnr : options(a.streetHtml, 'Hausnummer').find((x) => nrKey(x) === nrKey(addr.houseNumber!))
      if (!nr) continue
      const value = text ? hnr : unescapeHtml(nr)
      if (parseList(await walkToList(a, value, zusatz).catch(() => '')).length) fits.push({ strasse: a.strasse, nr: value })
    }
    if (!fits.length) return null
    if (fits.length > 1) {
      return {
        supported: true,
        town: town.name,
        street: plain(addr.street),
        needsHouseNumber: true,
        hausNrList: fits.map((f) => ({
          id: `${f.strasse}|${f.nr}`,
          nr: `${plain(f.nr)} · ${plain(f.strasse).match(/\(([^)]*)\)\s*$/)?.[1] ?? plain(f.strasse)}`,
        })),
        config: { vendor: 'athos' as const, host: base, ort: w.ort, street: w.strasse, hnr: zusatz || undefined },
      }
    }
    w = await walkToStreet(base, fits[0].strasse, town.name, w.ort) ?? w
  }
  const street = plain(w.strasse)
  const cfg = { vendor: 'athos' as const, host: base, ort: w.ort, street: w.strasse }

  // Dortmund lists its houses; the Landkreise take whatever is typed and say
  // whether it exists only on the last step.
  const listed = hasTextNumber(w.streetHtml) ? [] : options(w.streetHtml, 'Hausnummer')
  // A street in the list with no house under it (Dortmund's Übelgönne) has
  // nobody the tenant collects from. Asking for a number there would offer an
  // empty dropdown, so it is simply not served.
  if (!hasTextNumber(w.streetHtml) && !listed.length) return null
  const hausNrList = listed.map((v) => ({ id: unescapeHtml(v), nr: plain(v) }))
  const want = nrKey(addr.houseNumber || '')

  let hnr = '', zusatz = ''
  if (listed.length) {
    const v = listed.find((x) => nrKey(x) === want)
    if (v) hnr = unescapeHtml(v)
  } else if (want) {
    ;({ hnr, zusatz } = splitNumber(addr.houseNumber || ''))
  }
  if (hnr) {
    const html = await walkToList(w, hnr, zusatz).catch(() => '')
    if (parseList(html).length) {
      return {
        supported: true,
        town: town.name,
        street,
        config: { ...cfg, hnrId: hnr, hnr: zusatz || undefined },
      }
    }
  }
  return {
    supported: true,
    town: town.name,
    street,
    needsHouseNumber: true,
    hausNrList: hausNrList.length ? hausNrList : undefined,
    config: cfg,
  }
}

async function readAthos(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const base = cfg.host
  let strasse = cfg.street, hnr = String(cfg.hnrId ?? '')
  // A chip for one of several same-named streets carries its own street.
  const cut = hnr.lastIndexOf('|')
  if (cut > 0) [strasse, hnr] = [hnr.slice(0, cut), hnr.slice(cut + 1)]
  if (!base || !TENANTS.has(base) || !strasse || !hnr || !cfg.ort) throw new Error('reconnect_required')
  const w = await walkToStreet(base, strasse, '', cfg.ort)
  // The street is gone from the tenant's list — renamed or merged — and no
  // amount of retrying will bring the calendar back.
  if (!w) throw new Error('reconnect_required')
  const html = await walkToList(w, hnr, cfg.hnr ?? '')
  // The page and the subscription link carry the same dates over different
  // horizons, and which one is the long one is a tenant setting (Dortmund: the
  // page; Schaumburg, Karlsruhe: the link). Both are read and the one that
  // reaches further is kept — never merged, because their titles are worded
  // differently and a merge would put two rows on one day for one bin.
  let page = parseList(html)
  // Bielefeld's years: the page walked above is the ticked one; the others are
  // walked too and joined, all of them worded by the same page.
  // Only the yearly periods: Augsburg also offers "Die nächsten 4 Leerungen"
  // and "…3 Monate", which are slices of the year already walked.
  for (const period of w.s.periods.filter((p) => p !== w.s.sticky.Zeitraum && /jahres/i.test(p))) {
    const other = await walkToStreet(base, strasse, '', cfg.ort, period)
    if (other) page = page.concat(parseList(await walkToList(other, hnr, cfg.hnr ?? '')))
  }
  const link = icsLink(html, base)
  const feed = link ? await readIcs(link).catch(() => [] as Pickup[]) : []
  const pickups = lastDay(feed) > lastDay(page) ? feed : page
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  const who = `${plain(strasse)} ${plain(hnr)}${cfg.hnr ? ' ' + cfg.hnr : ''}`
  for (const p of pickups) {
    const key = `${p.day}:${p.title}`
    if (seen.has(key)) continue
    seen.add(key)
    const start = new Date(`${p.day}T00:00:00Z`)
    out.push({
      uid: `abfall:athos:${nrKey(cfg.ort + ' ' + who)}:${key}`,
      title: p.title,
      notes: null,
      location: cfg.label ?? who,
      startsAt: start.toISOString(),
      endsAt: new Date(start.getTime() + 86_400_000).toISOString(),
      allDay: true,
    })
  }
  return out
}

/// A city tenant is one town; a Landkreis tenant contributes every `Ort` on its
/// form. `city` carries the option's value exactly as it is posted back.
async function towns(p: AbfallProvider): Promise<Town[]> {
  if (!p.host) return []
  if (p.town) return [{ vendor: 'athos', name: p.town, provider: p.id, host: p.host }]
  const { html } = await open(p.host)
  const vals = options(html, 'Ort')
  if (isLetterOrt(vals)) return []
  return vals.map((v) => ({ vendor: 'athos' as const, name: plain(v), provider: p.id, host: p.host, city: unescapeHtml(v) }))
}

export const adapter: VendorAdapter = {
  family: 'athos',
  towns,
  probe: probeAthos,
  rhythm: rhythmAthos,
  read: readAthos,
}
