// Quick census of how the grid reader does on every extracted PDF: node survey.mjs [> out/survey.json]
import fs from "node:fs";
import { findGrid, yearOf } from "../../supabase/functions/_shared/abfall/pdf/grid.ts";
const m = JSON.parse(fs.readFileSync("manifest.json"));
const meta = {};
for (const p of m.pages) for (const d of p.pdfs) meta[d.id] ??= { pub: p.publisher, text: d.text, towns: p.towns.length };
const rows = [];
for (const f of fs.readdirSync("out/tokens")) {
  const id = f.slice(0, -5);
  const doc = JSON.parse(fs.readFileSync("out/tokens/" + f));
  const words = doc.pages.reduce((a, p) => a + p.words.length, 0);
  const g = words < 40 ? null : findGrid(doc);
  const vocab = {};
  if (g) for (const c of g.cells) for (const k of c.marks) { const key = k.s + (k.rgb ? "#" + k.rgb.join(".") : ""); vocab[key] = (vocab[key] || 0) + 1; }
  rows.push({ id, ...meta[id], pages: doc.pages.length, words, year: yearOf(doc), days: g?.cells.length ?? 0, bad: g?.mismatched ?? 0, months: g?.months.length ?? 0,
    vocab: Object.entries(vocab).sort((a, b) => b[1] - a[1]).slice(0, 12).map(([k, n]) => `${k}×${n}`).join(" ") });
}
rows.sort((a, b) => b.days - a.days);
fs.writeFileSync("out/survey.json", JSON.stringify(rows, null, 1));
const bucket = (r) => r.words < 40 ? "no_text" : r.days >= 330 ? "full_year" : r.days >= 150 ? "half_year+" : r.days > 0 ? "partial" : "no_grid";
const c = {}; for (const r of rows) c[bucket(r)] = (c[bucket(r)] || 0) + 1;
console.log(c);
for (const r of rows) console.log(bucket(r).padEnd(10), r.id, String(r.days).padStart(3), "bad", String(r.bad).padStart(3), "m", r.months, r.year, "|", (r.pub || "").slice(0, 28), "|", (r.text || "").slice(0, 30), "|", r.vocab.slice(0, 110));
