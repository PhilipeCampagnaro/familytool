// abfall/pdf/grid.ts — find the days in a printed year grid, and what is written in each.
//
// A town's bin calendar is nearly always a grid: one column (or block) per month, one row per
// day, the day's number beside its weekday ("1 Do", "Do 1", "1Do"), and the pickups written or
// coloured into the rest of the row. The date of a cell is where it sits, never a date printed in
// it, so everything here hangs on one check that cannot be fooled by layout: **the weekday printed
// beside a day number must be that date's real weekday.** A run of cells is only given a month if
// every one of them agrees, and the month is only trusted if the header above it or the run's own
// weekday pattern names it — both, when both are there.

import type { Box, PdfDoc, Word } from './types.ts'

export const WEEKDAYS: Record<string, number> = { mo: 0, di: 1, mi: 2, do: 3, fr: 4, sa: 5, so: 6 }

const MONTHS: Record<string, number> = {
  januar: 1, jänner: 1, jan: 1, februar: 2, feb: 2, märz: 3, maerz: 3, mär: 3, mrz: 3, marz: 3,
  april: 4, apr: 4, mai: 5, juni: 6, jun: 6, juli: 7, jul: 7, august: 8, aug: 8,
  september: 9, sep: 9, sept: 9, oktober: 10, okt: 10, november: 11, nov: 11, dezember: 12, dez: 12,
}

/// Monday = 0, as printed calendars count.
export function weekday(y: number, m: number, d: number): number {
  return (new Date(Date.UTC(y, m - 1, d)).getUTCDay() + 6) % 7
}
export function daysIn(y: number, m: number): number {
  return new Date(Date.UTC(y, m, 0)).getUTCDate()
}
export function iso(y: number, m: number, d: number): string {
  return `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`
}

export interface Mark {
  s: string // the word, '' for a coloured box with nothing written in it
  rgb?: [number, number, number] // the smallest box the word sits in, if it sits in one
  x: number
  y: number
}

export interface DayCell {
  date: string
  page: number
  marks: Mark[]
}

export interface Grid {
  year: number
  cells: DayCell[]
  /// Cells whose printed weekday did not match: a grid with many is not read.
  mismatched: number
  months: number[]
}

interface Anchor {
  page: number
  day: number
  wd: number
  x0: number // left of the day number
  x1: number // right of whichever of number/weekday is further right
  y0: number
  y1: number
  words: Word[]
}

const lower = (s: string) => s.toLowerCase().replace(/[.:,]$/, '')

/// "1", "01", "1." — a day number on its own.
const DAY = /^(\d{1,2})\.?$/
/// "1Do", "01.Do", "Do1", "Do.1" — the two glued together.
const GLUED = /^(?:(\d{1,2})\.?(mo|di|mi|do|fr|sa|so)\.?|(mo|di|mi|do|fr|sa|so)\.?(\d{1,2})\.?)$/i

function anchorsOf(page: number, words: Word[]): Anchor[] {
  const out: Anchor[] = []
  const used = new Set<Word>()
  for (const w of words) {
    const g = GLUED.exec(w.s)
    if (g) {
      const day = Number(g[1] ?? g[4])
      const wd = WEEKDAYS[(g[2] ?? g[3]).toLowerCase()]
      if (day >= 1 && day <= 31) {
        out.push({ page, day, wd, x0: w.x0, x1: w.x1, y0: w.y0, y1: w.y1, words: [w] })
        used.add(w)
      }
    }
  }
  // A number and a weekday on the same line, touching: either order. Paired only when each is
  // the other's nearest partner, so the "1." of "1. Weihnachtstag" printed after "25 Fr" cannot
  // take the Friday from the 25.
  const gapOf = (w: Word, v: Word): number => {
    const h = w.y1 - w.y0
    if (Math.abs((v.y0 + v.y1) / 2 - (w.y0 + w.y1) / 2) > h * 0.45) return Infinity
    const g = v.x0 >= w.x1 - 0.5 ? v.x0 - w.x1 : w.x0 >= v.x1 - 0.5 ? w.x0 - v.x1 : Infinity
    return g < h * 1.8 ? g : Infinity
  }
  const nums = words.filter((w) => {
    if (used.has(w)) return false
    const m = DAY.exec(w.s)
    return !!m && Number(m[1]) >= 1 && Number(m[1]) <= 31
  })
  const wds = words.filter((v) => !used.has(v) && lower(v.s) in WEEKDAYS)
  const nearest = <A extends Word, B extends Word>(a: A, pool: B[]): B | null => {
    let best: B | null = null
    let gap = Infinity
    for (const b of pool) {
      const g = gapOf(a, b)
      if (g < gap) {
        gap = g
        best = b
      }
    }
    return best
  }
  for (const w of nums) {
    const best = nearest(w, wds)
    if (!best || nearest(best, nums) !== w) continue
    const h = w.y1 - w.y0
    const yc = (w.y0 + w.y1) / 2
    // Nothing else may sit between them.
    const lo = Math.min(w.x1, best.x1)
    const hi = Math.max(w.x0, best.x0)
    const between = words.some((u) => u !== w && u !== best && Math.abs((u.y0 + u.y1) / 2 - yc) < h * 0.45 && u.x0 >= lo - 0.5 && u.x1 <= hi + 0.5 && hi - lo > 0.5)
    if (between) continue
    used.add(w)
    used.add(best)
    out.push({
      page, day: Number(DAY.exec(w.s)![1]), wd: WEEKDAYS[lower(best.s)],
      x0: Math.min(w.x0, best.x0), x1: Math.max(w.x1, best.x1),
      y0: Math.min(w.y0, best.y0), y1: Math.max(w.y1, best.y1),
      words: [w, best],
    })
  }
  return out
}

/// Runs of consecutive days in one column: 1,2,3… with the weekday stepping along with them.
interface Run {
  page: number
  anchors: Anchor[]
  x0: number
  y0: number
  first: number // day number of the first anchor
  wd0: number // weekday of the first anchor
}

function runsOf(anchors: Anchor[]): Run[] {
  // Columns: anchors that sit over each other. Not "left edges line up": a right-aligned "10"
  // starts left of a "9", and a weekday printed first shifts the number by its own width.
  const cols: { x0: number; x1: number; list: Anchor[] }[] = []
  for (const a of [...anchors].sort((p, q) => p.x0 - q.x0)) {
    const c = cols.find((c) => {
      const overlap = Math.min(c.x1, a.x1) - Math.max(c.x0, a.x0)
      return overlap > Math.min(c.x1 - c.x0, a.x1 - a.x0) * 0.5 && c.list[0].page === a.page
    })
    if (c) {
      c.list.push(a)
    } else {
      cols.push({ x0: a.x0, x1: a.x1, list: [a] })
    }
  }
  const runs: Run[] = []
  for (const { list: col } of cols) {
    col.sort((p, q) => p.y0 - q.y0)
    let cur: Anchor[] = []
    const flush = () => {
      if (cur.length >= 5) {
        runs.push({ page: cur[0].page, anchors: cur, x0: cur[0].x0, y0: cur[0].y0, first: cur[0].day, wd0: cur[0].wd })
      }
      cur = []
    }
    for (const a of col) {
      const prev = cur[cur.length - 1]
      if (prev && a.day === prev.day + 1 && a.wd === (prev.wd + 1) % 7 && a.y0 - prev.y1 < (prev.y1 - prev.y0) * 4) {
        cur.push(a)
      } else {
        flush()
        cur = [a]
      }
    }
    flush()
  }
  return runs
}

interface Header {
  page: number
  month: number
  w: Word
}

function headersOf(page: number, words: Word[]): Header[] {
  const out: Header[] = []
  for (const w of words) {
    const k = lower(w.s).replace(/\d+$/, '')
    if (k.length >= 3 && k in MONTHS) out.push({ page, month: MONTHS[k], w })
  }
  return out
}

/// The month a run is printed under: the nearest month word above it, overlapping it sideways.
function headerFor(run: Run, headers: Header[]): number | null {
  const colRight = Math.max(...run.anchors.map((a) => a.x1))
  let best: Header | null = null
  let score = Infinity
  for (const h of headers) {
    if (h.page !== run.page) continue
    if (h.w.y1 > run.y0 + 1) continue
    const dy = run.y0 - h.w.y1
    if (dy > 120) continue
    // The header spans the month's column, which starts at the day number and runs right.
    const dx = h.w.x0 < run.x0 - 40 ? run.x0 - 40 - h.w.x0 : h.w.x0 > colRight + 140 ? h.w.x0 - colRight - 140 : 0
    if (dx > 0) continue
    const s = dy + Math.abs(h.w.x0 - run.x0) * 0.2
    if (s < score) {
      score = s
      best = h
    }
  }
  return best ? best.month : null
}

/// Months of `year` a run could be: its first day falls on its first weekday, and it fits.
function monthsMatching(year: number, run: Run): number[] {
  const last = run.first + run.anchors.length - 1
  const out: number[] = []
  for (let m = 1; m <= 12; m++) {
    if (last > daysIn(year, m)) continue
    if (weekday(year, m, run.first) === run.wd0) out.push(m)
  }
  return out
}

/// The calendar year: the year printed most often, preferring a title-sized one near the top.
export function yearOf(doc: PdfDoc): number | null {
  const count = new Map<number, number>()
  for (const p of doc.pages) {
    for (const w of p.words) {
      const m = /^(?:\D*)(20(?:2[4-9]|3\d))(?:\D*)$/.exec(w.s)
      if (!m) continue
      const y = Number(m[1])
      const size = w.y1 - w.y0
      const weight = 1 + (size > 12 ? 3 : 0) + (w.y0 < p.h * 0.2 ? 1 : 0)
      count.set(y, (count.get(y) ?? 0) + weight)
    }
  }
  let best: number | null = null
  for (const [y, n] of count) if (best === null || n > count.get(best)! || (n === count.get(best)! && y > best)) best = y
  return best
}

export function findGrid(doc: PdfDoc, yearHint?: number): Grid | null {
  const allRuns: Run[] = []
  const headers: Header[] = []
  doc.pages.forEach((p, i) => {
    allRuns.push(...runsOf(anchorsOf(i, p.words)))
    headers.push(...headersOf(i, p.words))
  })
  if (!allRuns.length) return null

  // The year is whichever one the runs' weekday patterns agree with best. A printed year only
  // breaks a tie: phone numbers and "gültig ab 2025" are printed too, weekdays are not negotiable.
  const printed = yearHint ?? yearOf(doc)
  const candidates = [...new Set([printed, 2024, 2025, 2026, 2027, 2028].filter((y): y is number => !!y))]
  let year = candidates[0]
  let bestFit = -1
  for (const y of candidates) {
    const fit = allRuns.reduce((n, r) => n + (monthsMatching(y, r).length ? r.anchors.length : 0), 0)
    if (fit > bestFit || (fit === bestFit && y === printed)) {
      bestFit = fit
      year = y
    }
  }

  // Reading order: page, then top to bottom in bands, then left to right.
  allRuns.sort((a, b) => a.page - b.page || (Math.abs(a.y0 - b.y0) > 40 ? a.y0 - b.y0 : a.x0 - b.x0))

  const cells: DayCell[] = []
  const months: number[] = []
  let mismatched = 0
  let lastMonth = 0
  for (const run of allRuns) {
    const fits = monthsMatching(year, run)
    const head = headerFor(run, headers)
    let month: number | null = null
    if (head !== null) {
      month = fits.includes(head) ? head : null
    } else {
      // No header: the weekday pattern must name exactly one month after the last one read.
      const after = fits.filter((m) => m > lastMonth)
      month = after.length ? after[0] : null
      if (after.length > 1 && run.first === 1 && run.anchors.length >= 28) {
        // A whole month: its length tells the look-alikes apart (Jan and Oct 2026 both start on
        // a Thursday and both have 31 days — then order decides, and order is what `after` is).
        month = after[0]
      }
    }
    if (month === null) {
      mismatched += run.anchors.length
      continue
    }
    lastMonth = Math.max(lastMonth, month)
    months.push(month)
    for (const a of run.anchors) {
      if (weekday(year, month, a.day) !== a.wd) {
        mismatched++
        continue
      }
      cells.push({ date: iso(year, month, a.day), page: a.page, marks: [] })
      ;(cells[cells.length - 1] as DayCell & { _a?: Anchor })._a = a
    }
  }
  if (!cells.length) return null

  // Each cell's marks: what sits right of its anchor on its row, up to the next anchor to the right.
  const byPage = new Map<number, (DayCell & { _a?: Anchor })[]>()
  for (const c of cells as (DayCell & { _a?: Anchor })[]) {
    const l = byPage.get(c.page) ?? []
    l.push(c)
    byPage.set(c.page, l)
  }
  for (const [pi, list] of byPage) {
    const page = doc.pages[pi]
    const anchorWords = new Set(list.flatMap((c) => c._a!.words))
    const lefts = [...new Set(list.map((c) => c._a!.x0))].sort((a, b) => a - b)
    const pageAnchors = list.map((c) => c._a!)
    for (const c of list) {
      const a = c._a!
      const h = a.y1 - a.y0
      const yc = (a.y0 + a.y1) / 2
      const nextLeft = lefts.find((x) => x > a.x1 + 2) ?? page.w
      // The row runs down to the next day in the same column, so a cell whose text wraps onto
      // a second line ("gelber Sack /" over "Blaue Tonne") is read whole. Never further than
      // two rows, and a last row gets one line's worth.
      const below = pageAnchors
        // Only the next day of the same month bounds a row: below a month's last day is a
        // legend or the next half-year, and neither belongs to the 31st.
        .filter((o) => o.day === a.day + 1 && o.wd === (a.wd + 1) % 7 && o.y0 > a.y0 + h * 0.5 && Math.min(o.x1, a.x1) - Math.max(o.x0, a.x0) > 0)
        .reduce((m, o) => Math.min(m, o.y0), Infinity)
      const top = a.y0 - h * 0.35
      const bottom = Math.min(below === Infinity ? a.y1 + h * 0.35 : below - h * 0.1, a.y1 + h * 2)
      for (const w of page.words) {
        if (anchorWords.has(w)) continue
        const wc = (w.y0 + w.y1) / 2
        if (wc < top || wc > bottom) continue
        if (w.x0 < a.x1 - 0.5 || w.x0 >= nextLeft - 1) continue
        c.marks.push({ s: w.s, rgb: fillUnder(page.boxes, w, nextLeft - a.x0), x: w.x0, y: wc })
      }
      // A coloured box with nothing in it is a mark too, in towns that print a dot per bin.
      for (const b of page.boxes) {
        const bw = b.x1 - b.x0
        const bh = b.y1 - b.y0
        if (bw > h * 3 || bh > h * 2.2) continue
        const bc = (b.y0 + b.y1) / 2
        if (bc < top || bc > bottom || b.x0 < a.x1 - 0.5 || b.x0 >= nextLeft - 1) continue
        if (page.words.some((w) => within(w, b))) continue
        c.marks.push({ s: '', rgb: b.rgb, x: b.x0, y: bc })
      }
      // Reading order: line by line, left to right.
      c.marks.sort((p, q) => (Math.abs(p.y - q.y) > h * 0.6 ? p.y - q.y : p.x - q.x))
      delete c._a
    }
  }
  cells.sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0))
  return { year, cells, mismatched, months: [...new Set(months)].sort((a, b) => a - b) }
}

function within(w: Word, b: Box): boolean {
  const cx = (w.x0 + w.x1) / 2
  const cy = (w.y0 + w.y1) / 2
  return cx >= b.x0 && cx <= b.x1 && cy >= b.y0 && cy <= b.y1
}

/// The fill a word is printed on: the smallest box around it that is narrower than the cell —
/// a row shaded for Sundays is not a bin colour.
function fillUnder(boxes: Box[], w: Word, cellWidth: number): [number, number, number] | undefined {
  let best: Box | undefined
  for (const b of boxes) {
    if (!within(w, b)) continue
    if (b.x1 - b.x0 > cellWidth * 0.6) continue
    if (!best || (b.x1 - b.x0) * (b.y1 - b.y0) < (best.x1 - best.x0) * (best.y1 - best.y0)) best = b
  }
  return best?.rgb
}
