// abfall/pdf/extract.ts — a PDF's words and filled boxes, via pdf.js.
//
// pdf.js is passed in rather than imported, because the Edge Function loads it as `npm:` and the
// regression harness under Node loads it from node_modules; the code between is the same file.
// Only the legacy build is used, which needs no worker and no canvas.

import type { Box, PdfDoc, PdfPage, Word } from './types.ts'

// deno-lint-ignore no-explicit-any
type PdfJs = any

type M = [number, number, number, number, number, number]
const mul = (a: M, b: M): M => [
  a[0] * b[0] + a[2] * b[1],
  a[1] * b[0] + a[3] * b[1],
  a[0] * b[2] + a[2] * b[3],
  a[1] * b[2] + a[3] * b[3],
  a[0] * b[4] + a[2] * b[5] + a[4],
  a[1] * b[4] + a[3] * b[5] + a[5],
]
const apply = (m: M, x: number, y: number): [number, number] => [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]]

/// More pages than a year of bins ever takes is not a bin calendar, and reading it is work.
export const MAX_PAGES = 24

export async function extractDoc(pdfjs: PdfJs, bytes: Uint8Array): Promise<PdfDoc> {
  const task = pdfjs.getDocument({
    data: bytes,
    isEvalSupported: false,
    disableFontFace: true,
    useSystemFonts: false,
    verbosity: 0,
  })
  const doc = await task.promise
  try {
    const pages: PdfPage[] = []
    const n = Math.min(doc.numPages, MAX_PAGES)
    for (let i = 1; i <= n; i++) {
      const page = await doc.getPage(i)
      const vp = page.getViewport({ scale: 1 })
      const view = vp.transform as M
      pages.push({
        w: Math.round(vp.width),
        h: Math.round(vp.height),
        words: words(await page.getTextContent(), view),
        boxes: boxes(pdfjs.OPS, await page.getOperatorList(), view, vp.width, vp.height),
      })
      page.cleanup()
    }
    return { pages }
  } finally {
    await doc.destroy()
  }
}

// deno-lint-ignore no-explicit-any
function words(content: any, view: M): Word[] {
  const out: Word[] = []
  for (const it of content.items) {
    const str: string = it.str ?? ''
    if (!str.trim()) continue
    const t = mul(view, it.transform as M)
    // Rotated text is a margin note or a vertical label, never a day cell.
    if (Math.abs(t[1]) > 0.01 || Math.abs(t[2]) > 0.01 || t[0] <= 0) continue
    const size = Math.abs(t[3]) || Math.abs(t[0])
    const x = t[4]
    const base = t[5]
    const width = (it.width as number) * (t[0] / (it.transform[0] || 1)) || size * str.length * 0.5
    // pdf.js hands over runs, not words: "1 Do", "Januar 2026". Split on spaces and share the
    // run's width out by character count, which is close enough to tell cells apart.
    const per = width / str.length
    let i = 0
    for (const part of str.split(/(\s+)/)) {
      if (part && !/^\s+$/.test(part)) {
        out.push({
          s: part.normalize('NFKC'),
          x0: r1(x + i * per),
          y0: r1(base - size * 0.8),
          x1: r1(x + (i + part.length) * per),
          y1: r1(base + size * 0.2),
        })
      }
      i += part.length
    }
  }
  return out
}

// deno-lint-ignore no-explicit-any
function boxes(OPS: any, list: any, view: M, pw: number, ph: number): Box[] {
  const out: Box[] = []
  let ctm: M = [1, 0, 0, 1, 0, 0]
  let fill: [number, number, number] = [0, 0, 0]
  const stack: { ctm: M; fill: [number, number, number] }[] = []
  let path: number[] | null = null
  const { fnArray, argsArray } = list
  for (let i = 0; i < fnArray.length; i++) {
    const fn = fnArray[i]
    const a = argsArray[i]
    switch (fn) {
      case OPS.save:
        stack.push({ ctm, fill })
        break
      case OPS.restore: {
        const s = stack.pop()
        if (s) ({ ctm, fill } = s)
        break
      }
      case OPS.transform:
        ctm = mul(ctm, a as M)
        break
      case OPS.paintFormXObjectBegin:
        stack.push({ ctm, fill })
        if (a?.[0]) ctm = mul(ctm, a[0] as M)
        break
      case OPS.paintFormXObjectEnd: {
        const s = stack.pop()
        if (s) ({ ctm, fill } = s)
        break
      }
      case OPS.setFillRGBColor:
        fill = typeof a[0] === 'string' ? hex(a[0]) : [a[0], a[1], a[2]]
        break
      case OPS.setFillGray:
        fill = [a[0] * 255, a[0] * 255, a[0] * 255]
        break
      case OPS.constructPath: {
        const mm = a[2] as number[]
        if (mm && isFinite(mm[0])) {
          const m = mul(view, ctm)
          const p = [apply(m, mm[0], mm[1]), apply(m, mm[2], mm[3]), apply(m, mm[0], mm[3]), apply(m, mm[2], mm[1])]
          const xs = p.map((q) => q[0])
          const ys = p.map((q) => q[1])
          const bb = [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)]
          path = path ? [Math.min(path[0], bb[0]), Math.min(path[1], bb[1]), Math.max(path[2], bb[2]), Math.max(path[3], bb[3])] : bb
        }
        break
      }
      case OPS.fill:
      case OPS.eoFill:
      case OPS.fillStroke:
      case OPS.eoFillStroke:
      case OPS.closeFillStroke:
      case OPS.closeEOFillStroke:
        if (path) {
          const [x0, y0, x1, y1] = path
          const w = x1 - x0
          const h = y1 - y0
          // White is paper, and a box the size of the page is a background.
          const white = fill[0] > 245 && fill[1] > 245 && fill[2] > 245
          if (!white && w > 1 && h > 1 && !(w > pw * 0.8 && h > ph * 0.5)) {
            out.push({ x0: r1(x0), y0: r1(y0), x1: r1(x1), y1: r1(y1), rgb: [Math.round(fill[0]), Math.round(fill[1]), Math.round(fill[2])] })
          }
        }
        path = null
        break
      case OPS.endPath:
      case OPS.stroke:
      case OPS.closeStroke:
        path = null
        break
    }
  }
  return out
}

const hex = (s: string): [number, number, number] => [parseInt(s.slice(1, 3), 16), parseInt(s.slice(3, 5), 16), parseInt(s.slice(5, 7), 16)]
const r1 = (n: number) => Math.round(n * 10) / 10
