// Pick the PDFs that get hand-labelled ground truth: node select_labels.mjs → label_set.json
//
// Up to PER_PUB (argv, default 1) calendars per publisher (the latest year first, then the most days the grid reader
// found), plus calendars the reader does not see yet — a label set drawn only from what already
// parses would measure nothing about what does not.
import fs from "node:fs";
const PER_PUB = Number(process.argv[2] ?? 1);
const rows = JSON.parse(fs.readFileSync("out/survey.json"));
const m = JSON.parse(fs.readFileSync("manifest.json"));
const towns = {};
for (const p of m.pages) for (const d of p.pdfs) (towns[d.id] ??= []).push(...p.towns.map((t) => t.name));
const CAL = /kalender|abfuhr|termin|plan|müll|bezirk|tour|ortenberg|selters|effolderbach|lißberg|bergheim|gelnhaar|bleichenbach|eckartsborn|januar|juli|hier|download/i;
const NOT = /elektro|sortier|info|satzung|organigramm|bekanntmachung|flyer|broschüre|wegweiser|präsentation|schadstoff|problemstoff|container|abfallbilanz|awiko|gemeindeblatt|bürger|übersicht|zusatz|merkblatt|richtlinie|standorte|trennung|erläuterung/i;
const cands = rows.filter((r) => r.words >= 40 && (r.year ?? 0) >= 2025 && r.pages <= 16 && (r.days > 0 || (CAL.test(r.text || "") && !NOT.test(r.text || ""))));
const byPub = {};
for (const r of cands) (byPub[r.pub] ??= []).push(r);
const pick = [];
for (const [pub, list] of Object.entries(byPub)) {
  list.sort((a, b) => (b.year ?? 0) - (a.year ?? 0) || b.days - a.days);
  // Two from a publisher only when they are different towns or districts, not the same file twice.
  const seen = new Set();
  for (const r of list) {
    const key = r.vocab.slice(0, 60);
    if (seen.has(key) && r.days) continue;
    seen.add(key);
    pick.push({ id: r.id, pub, text: r.text, year: r.year, pages: r.pages, towns: [...new Set(towns[r.id] || [])].slice(0, 5) });
    if (seen.size >= PER_PUB) break;
  }
}
fs.writeFileSync("label_set.json", JSON.stringify(pick, null, 1));
console.log(pick.length, "PDFs from", Object.keys(byPub).length, "publishers");
