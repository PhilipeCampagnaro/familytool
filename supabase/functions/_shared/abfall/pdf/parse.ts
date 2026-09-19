// abfall/pdf/parse.ts — a printed bin calendar, read or refused.
//
// `parsePdfDoc` answers with the districts a household can pick between and every pickup for
// each, or with the reason it would not answer. The bar it is held to (tool/abfall_pdf/) is
// zero wrong dates on the labelled corpus: a bin put out on the wrong day is worse than no
// calendar, so every doubt below ends in a refusal, never in a best guess.

import { BIN_LABEL, type Bin } from './bins.ts'
import { daysIn, findGrid, type Grid } from './grid.ts'
import { colourBin, expandDistricts, readLegend, type Segment, segmentsOf } from './interpret.ts'
import type { ParseResult, PdfChoice, PdfDoc, Pickup } from './types.ts'

type RGB = [number, number, number]

/// A month the grid shows must show (nearly) all of its days, or pickups hide in the gaps.
const MONTH_COVERAGE = 0.97
/// Printed weekdays that disagree with the calendar, as a share of the cells read.
const MAX_MISMATCH = 0.02
/// An unresolved mark seen this often is a bin we could not name, not a stray note.
const UNRESOLVED_LIMIT = 4
/// More combinations than a household can pick from a list without a street index.
const MAX_CHOICES = 16

export function parsePdfDoc(doc: PdfDoc): ParseResult {
  const words = doc.pages.reduce((n, p) => n + p.words.length, 0)
  if (words < 40) return { ok: false, refusal: 'no_text' }

  const grid = findGrid(doc)
  if (!grid || grid.cells.length < 20) return { ok: false, refusal: 'not_calendar' }

  const sheet = oneSheet(grid)
  if (!sheet) return { ok: false, refusal: 'unsupported_layout', detail: 'several calendars repeat the same days' }
  const cells = sheet

  if (grid.mismatched > cells.length * MAX_MISMATCH) {
    return { ok: false, refusal: 'weekday_mismatch', detail: `${grid.mismatched} of ${cells.length + grid.mismatched}` }
  }
  const perMonth = new Map<number, number>()
  for (const c of cells) {
    const m = Number(c.date.slice(5, 7))
    perMonth.set(m, (perMonth.get(m) ?? 0) + 1)
  }
  const months = [...perMonth.keys()].sort((a, b) => a - b)
  for (const m of months) {
    if (perMonth.get(m)! < daysIn(grid.year, m) * MONTH_COVERAGE) {
      return { ok: false, refusal: 'low_coverage', detail: `month ${m}: ${perMonth.get(m)} of ${daysIn(grid.year, m)} days` }
    }
  }
  // Months must run without a hole: a calendar that reads Jan–Mar and Jul–Dec lost a block.
  for (let i = 1; i < months.length; i++) {
    if (months[i] !== months[i - 1] + 1) return { ok: false, refusal: 'low_coverage', detail: `month ${months[i - 1] + 1} missing` }
  }

  const cellColours: RGB[] = []
  for (const c of cells) for (const m of c.marks) if (m.rgb && !cellColours.some((x) => x.join() === m.rgb!.join())) cellColours.push(m.rgb)
  const legend = readLegend(doc, cellColours)

  stripWeekNumbers(cells)
  const segsByDate = cells.map((c) => ({ date: c.date, segs: segmentsOf(c, legend) }))

  // Unresolved segments that look like pickups: coloured, or carrying a district code.
  const unresolved = new Map<string, number>()
  for (const { segs } of segsByDate) {
    for (const s of segs) {
      if (s.bin) continue
      if (!s.rgb && !s.districts.length) continue
      const k = `${s.text || '□'}${s.rgb ? ' #' + s.rgb.join('.') : ''}`
      unresolved.set(k, (unresolved.get(k) ?? 0) + 1)
    }
  }
  const frequent = [...unresolved.entries()].filter(([, n]) => n >= UNRESOLVED_LIMIT)
  if (frequent.length) {
    const colourOnly = frequent.some(([k]) => k.includes('#'))
    return {
      ok: false,
      refusal: colourOnly ? 'colour_only' : 'unsupported_layout',
      detail: frequent.slice(0, 6).map(([k, n]) => `${k}×${n}`).join(', '),
    }
  }

  const resolved = segsByDate.flatMap(({ date, segs }) => segs.filter((s) => s.bin).map((s) => ({ date, seg: s })))
  if (resolved.length < 6) return { ok: false, refusal: 'no_bins' }

  // Districts. Singles first, so "AB" can be read as A and B only where A and B exist alone.
  const singles = new Set<string>()
  for (const { seg } of resolved) for (const d of seg.districts) if (!/[+,/&-]/.test(d)) singles.add(d)
  let expanded = resolved.map(({ date, seg }) => ({ date, bin: seg.bin!, ds: expandDistricts(seg.districts, singles), linked: seg.linked }))

  // A bin that nearly always names its districts but once does not: that mark lost its
  // district to the layout (a wrapped line), it is not "for everybody". Dropped, and too many of
  // them means the cells are not being read the way they are printed.
  let orphans = 0
  expanded = expanded.filter((e) => {
    if (e.ds.length) return true
    const all = expanded.filter((x) => x.bin === e.bin)
    const withD = all.filter((x) => x.ds.length).length
    if (withD >= all.length * 0.8) {
      orphans++
      return false
    }
    return true
  })
  if (orphans > 4) return { ok: false, refusal: 'unsupported_layout', detail: `${orphans} pickups without their district` }

  // Which bins share a district system. **Each bin is its own until the calendar shows
  // otherwise**: Datteln numbers every bin column from 1 on its own, and Willingen's Gelber Sack
  // runs different tours from its bins, so reading "3" as one district across bins invents
  // households that do not exist. Two things count as the calendar saying so:
  //  - it prints bins as one entry with one district list ("Bio + BT 3 + 4");
  //  - one bin's combined codes are another's singles (Bio "AB" where Restmüll has A and B), or
  //    two bins group their districts the same non-trivial way (both print "3+4" and "5+6").
  const bins = [...new Set(expanded.filter((e) => e.ds.length).map((e) => e.bin))]
  const parent = new Map<Bin, Bin>(bins.map((b) => [b, b]))
  const find = (b: Bin): Bin => (parent.get(b) === b ? b : find(parent.get(b)!))
  const union = (a: Bin, b: Bin) => parent.set(find(a), find(b))
  for (const e of expanded) if (e.linked) for (const b of e.linked) if (parent.has(b) && parent.has(e.linked[0])) union(e.linked[0], b)
  const valsOf = (b: Bin) => new Set(expanded.filter((e) => e.bin === b).flatMap((e) => e.ds))
  const combosOf = (b: Bin) => new Set(expanded.filter((e) => e.bin === b && e.ds.length > 1).map((e) => [...e.ds].sort(natural).join('+')))
  const rawCombos = (b: Bin) => resolved.filter(({ seg }) => seg.bin === b).flatMap(({ seg }) => seg.districts.filter((d) => /^[A-Z]{2,3}$/.test(d)))
  for (const a of bins) {
    for (const b of bins) {
      if (a >= b) continue
      const ca = combosOf(a), cb = combosOf(b)
      const sameGrouping = ca.size > 0 && ca.size === cb.size && [...ca].every((c) => cb.has(c)) && setEq(valsOf(a), valsOf(b))
      const lettersOfOther = (x: Bin, y: Bin) => {
        const r = rawCombos(x)
        return r.length > 0 && r.every((t) => [...t].every((ch) => valsOf(y).has(ch)))
      }
      if (sameGrouping || lettersOfOther(a, b) || lettersOfOther(b, a)) union(a, b)
    }
  }
  const groups = new Map<Bin, Bin[]>()
  for (const b of bins) groups.set(find(b), [...(groups.get(find(b)) ?? []), b])
  let groupList = [...groups.values()].map((bs) => ({ bins: bs, vals: [...new Set(bs.flatMap((b) => [...valsOf(b)]))].sort(natural) }))

  // A group whose every district comes up once is a once-a-year collection per district
  // (Sperrmüll 1, 2, 3 …) with nothing tying its numbers to the household's: left out, never
  // guessed. Within a regular group, a value seen once is a stray code — a misread, or a mark
  // for somebody else — and the marks carrying it cannot be placed, so the read is unsafe.
  const usesOf = (g: { bins: Bin[] }, v: string) => expanded.filter((e) => g.bins.includes(e.bin) && e.ds.includes(v)).length
  const dropped = groupList.filter((g) => g.vals.every((v) => usesOf(g, v) < 2))
  if (dropped.length) {
    const out = new Set(dropped.flatMap((g) => g.bins))
    expanded = expanded.filter((e) => !(out.has(e.bin) && e.ds.length))
    groupList = groupList.filter((g) => !dropped.includes(g))
  }
  for (const g of groupList) {
    for (const v of g.vals) {
      if (usesOf(g, v) < 2) return { ok: false, refusal: 'unsupported_layout', detail: `stray district code ${v}` }
    }
  }
  let combos: string[][] = [[]]
  for (const g of groupList) combos = combos.flatMap((c) => g.vals.map((v) => [...c, v]))
  if (combos.length > MAX_CHOICES) {
    return { ok: false, refusal: 'independent_districts', detail: groupList.map((g) => `${g.bins.join('+')}: ${g.vals.length}`).join(', ') }
  }
  const word = districtWord(doc)
  const choices: PdfChoice[] = []
  for (const combo of combos) {
    const seen = new Set<string>()
    const pickups: Pickup[] = []
    for (const e of expanded) {
      // A mark for nobody in particular is for everybody; one naming districts is for those.
      const gi = groupList.findIndex((g) => g.bins.includes(e.bin))
      const forMe = !e.ds.length || (gi >= 0 && e.ds.includes(combo[gi]))
      if (!forMe) continue
      const k = e.date + e.bin
      if (seen.has(k)) continue
      seen.add(k)
      pickups.push({ date: e.date, bin: e.bin })
    }
    pickups.sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : a.bin < b.bin ? -1 : 1))
    // The group with the most bins is "the" district ("Bezirk 3"); any other system is named by
    // its bin ("Grünschnitt 1"), because that is how the calendar prints it.
    const main = groupList.reduce((m, g, i) => (g.bins.length > groupList[m].bins.length ? i : m), 0)
    const generic = groupList.length <= 1 || groupList[main].bins.length > 1
    const parts = groupList.map((g, i) => (i === main && generic ? `${word} ${combo[i]}` : `${g.bins.map((b) => BIN_LABEL[b]).join('/')} ${combo[i]}`))
    choices.push({ id: combo.join('|') || 'all', label: combo.length ? [parts[main], ...parts.filter((_, i) => i !== main)].join(' · ') : 'Alle', pickups })
  }
  // A bin calendar that yields none of the household bins (only a Giftmobil, say) has had its
  // real bins lost somewhere above; what is left would pass for the whole calendar.
  const CORE = new Set(['rest', 'bio', 'papier', 'gelb'])
  if (!choices.some((c) => [...CORE].some((b) => c.pickups.filter((p) => p.bin === b).length >= 6))) {
    return { ok: false, refusal: 'no_bins', detail: 'no household bin found' }
  }

  // Two districts with identical pickups are one choice for the household.
  const merged: PdfChoice[] = []
  for (const c of choices) {
    const twin = merged.find((m) => sameDates(m.pickups, c.pickups))
    if (!twin) {
      merged.push(c)
      continue
    }
    // "Bezirk 3" and "Bezirk 4" always together read as "Bezirk 3 + 4".
    const a = twin.label.split(' · '), b = c.label.split(' · ')
    const diff = a.map((p, i) => p !== b[i])
    if (diff.filter(Boolean).length === 1) {
      const i = diff.indexOf(true)
      a[i] += ` + ${b[i].split(' ').pop()}`
      twin.label = a.join(' · ')
    } else {
      twin.label += ` / ${c.label}`
    }
    twin.id += `,${c.id}`
  }
  const layout = legend.colours.length && resolved.some(({ seg }) => seg.rgb && colourBin(legend, seg.rgb)) ? 'grid+colour' : 'grid'
  return { ok: true, year: grid.year, layout, choices: merged }
}

/// A PDF may print the year twice (a bin calendar and a street-cleaning one, a summary and
/// a detail page). Keep the only page group that carries bins; refuse if two do.
function oneSheet(grid: Grid): Grid['cells'] | null {
  const byDate = new Map<string, number>()
  for (const c of grid.cells) byDate.set(c.date, (byDate.get(c.date) ?? 0) + 1)
  if ([...byDate.values()].every((n) => n === 1)) return grid.cells
  const pages = [...new Set(grid.cells.map((c) => c.page))]
  // Group pages into sheets: consecutive pages whose dates do not overlap belong together.
  const sheets: number[][] = []
  for (const p of pages.sort((a, b) => a - b)) {
    const last = sheets[sheets.length - 1]
    const dates = new Set(grid.cells.filter((c) => c.page === p).map((c) => c.date))
    const clash = last && grid.cells.some((c) => last.includes(c.page) && dates.has(c.date))
    if (last && !clash) last.push(p)
    else sheets.push([p])
  }
  const binny = (ps: number[]) =>
    grid.cells.filter((c) => ps.includes(c.page)).reduce((n, c) => n + c.marks.filter((m) => /m[üu]ll|tonne|sack|bio|papier|rest|gelb|\b[A-Z]{1,3}\d?\b/i.test(m.s) || m.rgb).length, 0)
  const scored = sheets.map((s) => ({ s, n: binny(s) })).sort((a, b) => b.n - a.n)
  if (scored.length > 1 && scored[1].n > scored[0].n * 0.1) return null
  return grid.cells.filter((c) => scored[0].s.includes(c.page))
}

/// ISO week of a YYYY-MM-DD date.
function isoWeek(date: string): number {
  const d = new Date(date + 'T00:00:00Z')
  const day = (d.getUTCDay() + 6) % 7
  d.setUTCDate(d.getUTCDate() - day + 3)
  const firstThu = new Date(Date.UTC(d.getUTCFullYear(), 0, 4))
  return 1 + Math.round(((d.getTime() - firstThu.getTime()) / 86400000 - 3 + ((firstThu.getUTCDay() + 6) % 7)) / 7)
}

/// Some grids print the calendar week as a bare number in each Monday's cell ("Bio 5" is Bio in
/// KW 5, not Bio for district 5). When nearly every Monday carries its own week number, those
/// numbers are taken out before the cells are read — and only then, so a real district 3 on a
/// Monday of KW 3 in a calendar without the habit is left alone.
function stripWeekNumbers(cells: Grid['cells']) {
  const mondays = cells.filter((c) => new Date(c.date + 'T00:00:00Z').getUTCDay() === 1)
  // Printed week numbers can sit a row off (Gaienhofen prints KW 29 on KW 28's Monday from July
  // on), so a number within one of the ISO week counts — but only in a calendar where most
  // Mondays carry one: a district that tracks the week number all year is not a district.
  const isKw = (c: Grid['cells'][number], s: string) => {
    const n = Number(s.replace(/\.$/, ''))
    return /^\d{1,2}\.?$/.test(s) && Math.abs(n - isoWeek(c.date)) <= 1
  }
  if (mondays.length < 8 || mondays.filter((c) => c.marks.some((m) => isKw(c, m.s))).length < mondays.length * 0.6) return
  for (const c of mondays) {
    const i = c.marks.findIndex((m) => isKw(c, m.s))
    if (i >= 0) c.marks.splice(i, 1)
  }
}

/// What the calendar calls its districts, for the choice labels: the word printed most often
/// right before a district code ("Bezirk 3", "Tour 1"). "Bezirk" when it never says.
function districtWord(doc: PdfDoc): string {
  const count = new Map<string, number>()
  for (const p of doc.pages) {
    for (let i = 0; i + 1 < p.words.length; i++) {
      const m = /^(Abfuhrbezirk|Müllbezirk|Bezirk|Tour|Zone|Revier|Gebiet|Abfuhrgebiet|Sammelbezirk)$/i.exec(p.words[i].s)
      if (m && /^[A-Z0-9]{1,3}:?$/i.test(p.words[i + 1].s)) {
        const k = m[1][0].toUpperCase() + m[1].slice(1).toLowerCase()
        count.set(k, (count.get(k) ?? 0) + 1)
      }
    }
  }
  return [...count.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? 'Bezirk'
}

const setEq = <T>(a: Set<T>, b: Set<T>) => a.size === b.size && [...a].every((x) => b.has(x))

function sameDates(a: Pickup[], b: Pickup[]) {
  return a.length === b.length && a.every((p, i) => p.date === b[i].date && p.bin === b[i].bin)
}

const natural = (a: string, b: string) => a.localeCompare(b, 'de', { numeric: true })

export function pickupsToIcs(choice: PdfChoice, name: string): string {
  const lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Aporah//Abfall PDF//DE', 'CALSCALE:GREGORIAN', `X-WR-CALNAME:${esc(name)}`]
  for (const p of choice.pickups) {
    const d = p.date.replace(/-/g, '')
    const next = new Date(Date.UTC(Number(p.date.slice(0, 4)), Number(p.date.slice(5, 7)) - 1, Number(p.date.slice(8, 10)) + 1))
    const e = next.toISOString().slice(0, 10).replace(/-/g, '')
    lines.push(
      'BEGIN:VEVENT',
      `UID:${d}-${p.bin}-${choice.id.replace(/[^A-Za-z0-9]/g, '_')}@pdf.aporah`,
      `DTSTAMP:${d}T000000Z`,
      `DTSTART;VALUE=DATE:${d}`,
      `DTEND;VALUE=DATE:${e}`,
      `SUMMARY:${esc(BIN_LABEL[p.bin as Bin])}`,
      'TRANSP:TRANSPARENT',
      'END:VEVENT',
    )
  }
  lines.push('END:VCALENDAR')
  return lines.join('\r\n') + '\r\n'
}

const esc = (s: string) => s.replace(/\\/g, '\\\\').replace(/[,;]/g, (m) => '\\' + m).replace(/\n/g, '\\n')

export type { Segment }
