// abfall/pdf/interpret.ts — from what is written in each day cell to which bin, for whom.
//
// A cell holds *segments*: a bin, and the districts it is for ("Bio 3+4", "RM 1", a blue box
// with "2" in it, "B1"). The bin comes from a name printed in the segment, from a code the
// calendar's legend defines, or from the segment's colour matched to the legend's swatches —
// in that order, and nothing else. A segment none of those resolve is dropped, and if segments
// like it are common the whole PDF is refused rather than read with a hole in it. Districts are
// whatever codes are left; the household picks theirs.

import { type Bin, binOfName, isNoise } from './bins.ts'
import type { DayCell, Grid, Mark } from './grid.ts'
import type { PdfDoc, Word } from './types.ts'

type RGB = [number, number, number]

export interface Segment {
  bin: Bin | null
  /// Bins printed together as one entry ("Bio + BT 3 + 4") share one district list, and that
  /// is the calendar saying those bins run on one district system.
  linked?: Bin[]
  districts: string[] // raw district tokens, e.g. ['3', '4'] or ['AB'] or ['Lechenich']
  text: string // what was printed, for reports
  rgb?: RGB
}

const rgbKey = (c?: RGB) => (c ? c.join('.') : '')
const near = (a: RGB, b: RGB) => Math.abs(a[0] - b[0]) + Math.abs(a[1] - b[1]) + Math.abs(a[2] - b[2]) < 24

/// Word-sized tokens that name a district: "1", "12", "A", "AB", "1+2", "3,4", "II", "B4".
const DISTRICTISH = /^(?:[A-Za-z]{1,3}|\d{1,2}[a-z]?|[IVX]{1,4}|[A-Z]\d{1,2}|\d{1,2}[+,&]|\d{1,2}(?:[+,/&-]\d{1,2})+[+,]?|[A-Z](?:[+,/&][A-Z])+|\+|,|&|\/)$/

// ---------------------------------------------------------------------------------------------
// Legend

export interface Legend {
  codes: Map<string, Bin> // 'R' → rest, 'BT' → papier
  /// Codes the key defines as something that is not a bin ("S = Straßenreinigung").
  ignore: Set<string>
  colours: { rgb: RGB; bin: Bin }[]
}

/// Read the calendar's key. `cellColours` are the fills seen in day cells: only those are worth
/// resolving, and a swatch of any other colour is decoration.
export function readLegend(doc: PdfDoc, cellColours: RGB[]): Legend {
  const codeVotes = new Map<string, Map<Bin, number>>()
  const vote = (m: Map<string, Map<Bin, number>>, k: string, b: Bin) => {
    const v = m.get(k) ?? new Map<Bin, number>()
    v.set(b, (v.get(b) ?? 0) + 1)
    m.set(k, v)
  }
  const colourVotes = new Map<string, Map<Bin, number>>()
  const ignore = new Set<string>()

  for (const page of doc.pages) {
    const lines = linesOf(page.words)
    for (const line of lines) {
      for (let i = 0; i < line.length; i++) {
        const w = line[i].s
        // "R = Restmüll", "R: Restmüll", "R – Restmüll", "R Restmüll"
        const code = /^([A-ZÄÖÜ]{1,3}|[A-ZÄÖÜ][a-zäöü]{0,2})[:=]?$/.exec(w)
        // "Mo Bio" in a day cell is a weekday and a pickup, not a key saying MO means Bio.
        // Nor is a word that is a bin in its own right ("Bio gelber Sack" lists two bins).
        if (code && !WEEKDAY_WORD.test(code[1]) && !binOfName(code[1])) {
          let j = i + 1
          if (j < line.length && /^[=:–-]$/.test(line[j].s)) j++
          if (j < line.length && line[j].x0 - line[i].x1 < 30) {
            const hit = binOfName(line[j].s, line[j + 1]?.s)
            if (hit && (hit.words === 2 || !isCodeLike(line[j].s))) vote(codeVotes, code[1].toUpperCase(), hit.bin)
            // Only an explicit "=" or ":" defines a non-bin: "S = Straßenreinigung".
            else if (!hit && j > i + 1 && /^\p{L}{4,}/u.test(line[j].s)) ignore.add(code[1].toUpperCase())
          }
        }
        // "Restmüll (R)", "Restmüll = R"
        const paren = /^\(([A-ZÄÖÜ]{1,3})\)$/.exec(w) ?? (i > 0 && /^[=:]$/.test(line[i - 1].s) ? /^([A-ZÄÖÜ]{1,3})$/.exec(w) : null)
        if (paren && i > 0) {
          const back = line[i - 1].s === '=' || line[i - 1].s === ':' ? i - 2 : i - 1
          if (back >= 0) {
            const hit = binOfName(line[back].s) ?? (back > 0 ? binOfName(line[back - 1].s, line[back].s) : null)
            if (hit) vote(codeVotes, paren[1], hit.bin)
          }
        }
      }
    }
    // Colour swatches: a box of a cell colour with a bin name inside it or just right of it.
    for (const b of page.boxes) {
      if (!cellColours.some((c) => near(c, b.rgb))) continue
      const h = b.y1 - b.y0
      if (h > 60 || b.x1 - b.x0 > 260) continue
      const cy = (b.y0 + b.y1) / 2
      const beside = page.words
        .filter((w) => {
          const wc = (w.y0 + w.y1) / 2
          const inside = w.x0 >= b.x0 - 1 && w.x1 <= b.x1 + 1 && wc >= b.y0 && wc <= b.y1
          const right = w.x0 >= b.x1 - 1 && w.x0 - b.x1 < 18 && Math.abs(wc - cy) < Math.max(h, w.y1 - w.y0) * 0.6
          return inside || right
        })
        .sort((p, q) => p.x0 - q.x0)
      if (!beside.length) continue
      const hit = binOfName(beside[0].s, beside[1]?.s)
      // A single code in a coloured box is a day cell, not a legend entry.
      if (hit && !(hit.words === 1 && isCodeLike(beside[0].s))) vote(colourVotes, rgbKey(b.rgb), hit.bin)
    }
  }

  const decided = <K>(m: Map<K, Map<Bin, number>>) => {
    const out = new Map<K, Bin>()
    for (const [k, v] of m) {
      const sorted = [...v.entries()].sort((a, b) => b[1] - a[1])
      if (sorted.length === 1 || sorted[0][1] >= sorted[1][1] * 3) out.set(k, sorted[0][0])
    }
    return out
  }
  const colours: { rgb: RGB; bin: Bin }[] = []
  for (const [k, bin] of decided(colourVotes)) colours.push({ rgb: k.split('.').map(Number) as RGB, bin })
  // Two different colours may mean one bin (a light and a dark print), but one colour never
  // means two — `decided` already dropped those.
  const codes = decided(codeVotes)
  for (const k of codes.keys()) ignore.delete(k)
  return { codes, colours, ignore }
}

const WEEKDAY_WORD = /^(mo|di|mi|do|fr|sa|so)$/i

function isCodeLike(s: string) {
  return /^[A-ZÄÖÜ]{1,3}$/.test(s) || /^[a-z]{1,2}$/.test(s)
}

function linesOf(words: Word[]): Word[][] {
  const sorted = [...words].sort((a, b) => a.y0 - b.y0 || a.x0 - b.x0)
  const lines: Word[][] = []
  for (const w of sorted) {
    const yc = (w.y0 + w.y1) / 2
    const l = lines.find((l) => Math.abs((l[0].y0 + l[0].y1) / 2 - yc) < (w.y1 - w.y0) * 0.4)
    if (l) l.push(w)
    else lines.push([w])
  }
  for (const l of lines) l.sort((a, b) => a.x0 - b.x0)
  return lines
}

// ---------------------------------------------------------------------------------------------
// Segments

export function colourBin(legend: Legend, rgb?: RGB): Bin | null {
  if (!rgb) return null
  const hits = new Set(legend.colours.filter((c) => near(c.rgb, rgb)).map((c) => c.bin))
  return hits.size === 1 ? [...hits][0] : null
}

/// Split a code glued to its district: "B1" → B + 1, "H4" → H + 4. Only when the letters are a
/// code the legend knows, so "A1" in a town whose districts are called A1 stays A1.
function splitCode(tok: string, legend: Legend): { bin: Bin; district: string } | null {
  const m = /^([A-ZÄÖÜ]{1,3})(\d{1,2})$/.exec(tok)
  if (!m) return null
  const bin = legend.codes.get(m[1]) ?? null
  return bin ? { bin, district: m[2] } : null
}

export function segmentsOf(cell: DayCell, legend: Legend): Segment[] {
  // Group marks into runs: same fill and touching are one printed chip.
  const chips: Mark[][] = []
  for (const m of cell.marks) {
    const last = chips[chips.length - 1]
    const prev = last?.[last.length - 1]
    // Uncoloured words run together too, so "grüner Punkt" reaches the name matcher as a pair.
    if (prev && rgbKey(prev.rgb) === rgbKey(m.rgb)) last.push(m)
    else chips.push([m])
  }
  const segs: Segment[] = []
  let cur: Segment | null = null
  let afterKw = false
  for (const chip of chips) {
    const coloured = !!chip[0].rgb
    if (coloured) cur = null // a coloured chip is its own segment
    const colourSeg: Segment | null = coloured
      ? { bin: null, districts: [], text: chip.map((m) => m.s).join(' ').trim(), rgb: chip[0].rgb }
      : null
    // "Papier/Problemmüll" is two bins; "3/4" stays one district token.
    const words = chip.flatMap((m) => m.s.split(/([+,&])|(?<=\p{L}{2})\/(?=\p{L}{2})/u)).map((s) => (s ?? "").trim()).filter((s) => s !== '' && !/^(u\.?|und)$/i.test(s))
    for (let i = 0; i < words.length; i++) {
      const w = words[i]
      if (/^kw\.?$/i.test(w)) {
        afterKw = true
        continue
      }
      if (afterKw && /^\d{1,2}$/.test(w)) {
        afterKw = false
        continue
      }
      afterKw = false
      if (isNoise(w)) continue
      if (legend.ignore.has(w.toUpperCase())) {
        cur = null
        continue
      }
      const name = binOfName(w, words[i + 1])
      const code = legend.codes.get(w.toUpperCase().replace(/[:.]$/, ''))
      const split = splitCode(w, legend)
      const target = colourSeg ?? null
      if (name || (code && /^[A-ZÄÖÜ]{1,3}$/.test(w)) || split) {
        const bin = name?.bin ?? code ?? split!.bin
        if (target) {
          if (target.bin && target.bin !== bin) target.bin = null // two bins in one chip: unreadable
          else target.bin = bin
          if (split) target.districts.push(split.district)
        } else if (cur && cur.bin && cur.districts.length && cur.districts.every((d) => /^[+&]$/.test(d))) {
          // "Bio + BT 3 + 4": the running segment has only a "+" so far, so this bin joins it and
          // both take the districts that follow — one list, shared by reference.
          cur.districts.length = 0
          const joined: Segment = { bin, districts: cur.districts, text: w, linked: [cur.bin, bin] }
          cur.linked = joined.linked
          segs.push(joined)
          cur = joined
        } else {
          cur = { bin, districts: split ? [split.district] : [], text: w }
          segs.push(cur)
        }
        if (name && name.words === 2) i++
        continue
      }
      if (DISTRICTISH.test(w)) {
        let into = target ?? cur
        // "RM 3 + 4, AH 1": AH is not a district of RM's kind — it is another bin this calendar
        // did not define. It ends RM's list and starts a segment of its own, unresolved.
        const first = into?.districts.find((d) => !/^[+,&/]$/.test(d))
        if (into && !target && first && !/^[+,&/]$/.test(w) && shapeOf(first) !== shapeOf(w)) {
          cur = { bin: null, districts: [], text: w }
          segs.push(cur)
          into = null
          if (/^[A-ZÄÖÜ]{2,3}$/.test(w)) continue
        }
        if (into) {
          into.districts.push(w)
          if (!target) into.text += ' ' + w
        } else {
          // A district before any bin: a segment of its own whose bin may come from colour.
          cur = { bin: null, districts: [w], text: w }
          segs.push(cur)
        }
        continue
      }
      // Any other word ends the running segment: it is a note, not a district.
      if (!target) {
        cur = { bin: null, districts: [], text: w }
        segs.push(cur)
        cur = null
      }
    }
    if (colourSeg) {
      if (!colourSeg.bin) colourSeg.bin = colourBin(legend, colourSeg.rgb)
      segs.push(colourSeg)
    }
  }
  return segs
}

/// Digits, letters or names: a district list keeps to one.
function shapeOf(t: string): string {
  if (/^\d/.test(t)) return 'num'
  if (/^[IVX]+$/.test(t)) return 'roman'
  if (/^[A-Z]{1,3}$/.test(t)) return 'letter'
  return 'name'
}

// ---------------------------------------------------------------------------------------------
// Districts

/// "3+4" → ["3","4"], "1,2,3" → [...], "2+" → ["2"]; "AB" → ["A","B"] only when A and B are
/// districts on their own somewhere in the calendar.
export function expandDistricts(raw: string[], singles: Set<string>): string[] {
  const out: string[] = []
  for (const t of raw) {
    if (/^[+,&/]$/.test(t)) continue
    if (/[+,/&]/.test(t)) {
      out.push(...t.split(/[+,/&]/).filter(Boolean))
      continue
    }
    const r = /^(\d{1,2})-(\d{1,2})$/.exec(t)
    if (r) {
      for (let i = Number(r[1]); i <= Number(r[2]); i++) out.push(String(i))
      continue
    }
    if (/^[A-Z]{2,3}$/.test(t) && [...t].every((c) => singles.has(c))) {
      out.push(...t)
      continue
    }
    out.push(t)
  }
  return out
}

export type { Grid }
