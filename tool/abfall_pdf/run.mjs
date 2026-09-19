// The regression run: parse every extracted PDF and score it against the ground truth.
//
//   node run.mjs              # report to stdout, out/report.json; exit 1 if any date is wrong
//   node run.mjs <id> ...     # just those, with every pickup printed
//
// Scoring, per labelled PDF (truth/<id>.json, built by merge_truth.mjs from two labellers):
//   wrong   — a date the parser gives for a bin, in the labelled window, that the truth does not
//             have (or a pickup read out of something the labellers said is not a calendar).
//             The bar is zero.
//   missed  — a truth date the parser does not give. Counted, not fatal.
//   refused — the parser declined, with its reason. Never wrong; it is the price of never guessing.
// Dates either labeller was unsure of, or the two disagreed on, are left out of both counts.
import fs from "node:fs";
import { parsePdfDoc } from "../../supabase/functions/_shared/abfall/pdf/parse.ts";

const only = process.argv.slice(2);
const meta = {};
for (const p of JSON.parse(fs.readFileSync("manifest.json")).pages) for (const d of p.pdfs) meta[d.id] ??= { pub: p.publisher, text: d.text };
const ids = only.length ? only : fs.readdirSync("out/tokens").map((f) => f.slice(0, -5));

const inWindow = (date, win) => win.some((m) => date.startsWith(m));
// The zero-wrong bar is on the four household bins. The extras (Grünschnitt, Sperrmüll,
// Schadstoff, Glas) are scored and reported, but labellers read "is this a pickup at all"
// differently for them, so a disagreement there is not evidence against the parser.
const CORE = new Set(["rest", "bio", "papier", "gelb"]);
const norm = (s) => String(s).toUpperCase().replace(/\s+/g, "");

function score(res, truth) {
  if (!truth.calendar) {
    const n = res.ok ? res.choices.reduce((a, c) => a + c.pickups.length, 0) : 0;
    return { verdict: n ? "wrong" : "ok", wrong: n ? [`read ${n} pickups from a non-calendar`] : [], missed: [] };
  }
  if (!res.ok) return { verdict: "refused", wrong: [], missed: [] };
  // The household's choice: the one whose dates best match the labelled district. Whether its
  // *name* is the one the labellers read is reported beside it, since a right calendar under a
  // wrong name still puts a household's bins out on somebody else's days.
  const all = Object.entries(truth.bins).flatMap(([bin, ds]) => ds.map((d) => `${d} ${bin}`));
  const overlap = (c) => { const got = new Set(c.pickups.map((p) => `${p.date} ${p.bin}`)); return all.filter((k) => got.has(k)).length; };
  const choice = [...res.choices].sort((x, y) => overlap(y) - overlap(x))[0];
  const nums = (s) => (String(s).match(/\b[0-9]{1,2}\b|\b[A-Z]\b/g) || []);
  const labelOk = res.choices.length === 1 || nums(truth.district).some((n) => nums(choice.label).includes(n));
  const excluded = new Set(truth.excluded || []);
  const wrong = [], missed = [];
  for (const [bin, dates] of Object.entries(truth.bins)) {
    const got = new Set(choice.pickups.filter((p) => p.bin === bin && inWindow(p.date, truth.window)).map((p) => p.date));
    const want = new Set(dates);
    for (const d of got) if (!want.has(d) && !excluded.has(`${d} ${bin}`)) wrong.push(`${d} ${bin}`);
    for (const d of want) if (!got.has(d)) missed.push(`${d} ${bin}`);
  }
  // A bin the parser reads that the labellers said this calendar does not have at all.
  for (const p of choice.pickups) {
    if (!(p.bin in truth.bins) && inWindow(p.date, truth.window) && truth.all_bins_labelled && !excluded.has(`${p.date} ${p.bin}`)) wrong.push(`${p.date} ${p.bin} (bin not in calendar)`);
  }
  const extraWrong = wrong.filter((k) => !CORE.has(k.split(" ")[1]));
  const coreWrong = wrong.filter((k) => CORE.has(k.split(" ")[1]));
  return { verdict: coreWrong.length ? "wrong" : missed.length || extraWrong.length ? "ok_with_gaps" : "exact", wrong: coreWrong, extraWrong, missed, choice: choice.label, labelOk, district: truth.district };
}

const rows = [];
for (const id of ids) {
  const doc = JSON.parse(fs.readFileSync(`out/tokens/${id}.json`));
  let res;
  try {
    res = parsePdfDoc(doc);
  } catch (e) {
    res = { ok: false, refusal: "crash", detail: String(e.stack || e).slice(0, 300) };
  }
  const tpath = `truth/${id}.json`;
  const truth = fs.existsSync(tpath) ? JSON.parse(fs.readFileSync(tpath)) : null;
  const s = truth ? score(res, truth) : null;
  rows.push({ id, ...meta[id], res, score: s });
  if (only.length) {
    console.log(id, meta[id]?.pub, JSON.stringify(res.ok ? { year: res.year, layout: res.layout, choices: res.choices.map((c) => `${c.label}:${c.pickups.length}`) } : res));
    if (res.ok) for (const c of res.choices.slice(0, 3)) console.log(" ", c.label, c.pickups.filter((p) => p.date < `${res.year}-02-01`).map((p) => `${p.date.slice(5)} ${p.bin}`).join(", "));
    if (s) console.log("  score", JSON.stringify(s));
  }
}
fs.mkdirSync("out", { recursive: true });
fs.writeFileSync("out/report.json", JSON.stringify(rows, null, 1));

if (!only.length) {
  const tally = (f) => rows.reduce((m, r) => ((m[f(r)] = (m[f(r)] || 0) + 1), m), {});
  console.log("parser, all PDFs:", tally((r) => (r.res.ok ? "read" : r.res.refusal)));
  const labelled = rows.filter((r) => r.score);
  console.log(`labelled: ${labelled.length}`, tally.call(null, (r) => (r.score ? r.score.verdict : "unlabelled")));
  const wrong = labelled.filter((r) => r.score.wrong.length);
  const missed = labelled.reduce((n, r) => n + r.score.missed.length, 0);
  const wrongN = labelled.reduce((n, r) => n + r.score.wrong.length, 0);
  const extraN = labelled.reduce((n, r) => n + (r.score.extraWrong?.length || 0), 0);
  console.log(`wrong dates (rest/bio/papier/gelb): ${wrongN} in ${wrong.length} PDFs · wrong extras: ${extraN} · missed dates: ${missed}`);
  for (const r of labelled.filter((r) => r.score.labelOk === false)) console.log("  LABEL", r.id, (r.pub || "").slice(0, 30), `truth ${r.score.district} vs choice ${r.score.choice}`);
  for (const r of wrong) console.log("  WRONG", r.id, (r.pub || "").slice(0, 30), r.score.choice, r.score.wrong.slice(0, 8).join(", "));
  for (const r of labelled.filter((r) => r.score.verdict === "no_matching_choice")) console.log("  NOCHOICE", r.id, (r.pub || "").slice(0, 30), r.score.detail);
  process.exit(wrongN ? 1 : 0);
}
