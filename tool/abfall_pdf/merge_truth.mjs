// Merge two labellers into ground truth: node merge_truth.mjs → truth/<id>.json + agreement report
//
// A date is truth only when both labellers wrote it and neither was unsure of it. A date only one
// of them wrote is *disputed*: it goes into `excluded`, so it counts neither for nor against the
// parser, and it is listed for a human to settle. Two labellers who picked different districts,
// or disagree on whether it is a calendar at all, give no truth for that PDF until someone looks.
import fs from "node:fs";

const raw = {};
for (const f of fs.readdirSync("truth/raw")) {
  const m = /^(\w+)\.(\w+)\.json$/.exec(f);
  if (!m) continue;
  (raw[m[1]] ??= {})[m[2]] = JSON.parse(fs.readFileSync(`truth/raw/${f}`));
}

const norm = (s) => String(s ?? "").toUpperCase().replace(/\s+/g, "");
const unsureOf = (l) => new Set((l.unsure || []).map((u) => { const m = /^(\d{4}-\d{2}-\d{2})\s+(\w+)/.exec(u); return m ? `${m[1]} ${m[2]}` : null; }).filter(Boolean));

let agreeDates = 0, disputedDates = 0;
const report = [];
for (const [id, byL] of Object.entries(raw)) {
  const ls = Object.values(byL);
  if (ls.length < 2) { report.push({ id, status: "one_labeller" }); continue; }
  const [a, b] = ls;
  if (a.calendar !== b.calendar) { report.push({ id, status: "disagree_calendar" }); continue; }
  if (a.calendar === false) {
    fs.writeFileSync(`truth/${id}.json`, JSON.stringify({ id, calendar: false }, null, 1));
    report.push({ id, status: "not_calendar" });
    continue;
  }
  if (a.unreadable || b.unreadable) { report.push({ id, status: "unreadable", reason: a.reason || b.reason }); continue; }
  // Labellers write the district in their own words ("1" vs "Müllbezirk 1 + Garten 1"), so the
  // district is compared by what it produces: the dates. Low agreement below flags a mismatch.
  const window = (a.window || []).filter((m) => (b.window || []).includes(m));
  const inWin = (d) => window.some((m) => d.startsWith(m));
  const unsure = new Set([...unsureOf(a), ...unsureOf(b)]);
  const bins = {}, excluded = [], disputes = [];
  let agree = 0, total = 0;
  for (const bin of new Set([...Object.keys(a.bins || {}), ...Object.keys(b.bins || {})])) {
    const A = new Set((a.bins?.[bin] || []).filter(inWin)), B = new Set((b.bins?.[bin] || []).filter(inWin));
    const inA = bin in (a.bins || {}), inB = bin in (b.bins || {});
    if (!inA || !inB) {
      // One labeller says the calendar has no such bin. Every date of it is disputed.
      for (const d of [...A, ...B]) { excluded.push(`${d} ${bin}`); disputes.push(`${d} ${bin} (${inA ? "a" : "b"} only; other has no ${bin})`); }
      continue;
    }
    bins[bin] = [];
    for (const d of new Set([...A, ...B])) {
      total++;
      const k = `${d} ${bin}`;
      if (A.has(d) && B.has(d) && !unsure.has(k)) { bins[bin].push(d); agree++; }
      else { excluded.push(k); if (!(A.has(d) && B.has(d))) disputes.push(`${k} (${A.has(d) ? "a" : "b"} only)`); }
    }
    bins[bin].sort();
  }
  agreeDates += agree;
  disputedDates += total - agree;
  if (total && agree / total < 0.8) { report.push({ id, status: "disagree_district", a: a.district, b: b.district, agree, total }); continue; }
  fs.writeFileSync(`truth/${id}.json`, JSON.stringify({
    id, calendar: true, year: a.year, district: a.district, district_b: b.district, window, bins, excluded,
    all_bins_labelled: true, labellers: Object.keys(byL),
  }, null, 1));
  report.push({ id, status: "merged", agree, total, rate: total ? +(agree / total).toFixed(3) : 1, disputes });
}

fs.writeFileSync("truth/agreement.json", JSON.stringify(report, null, 1));
for (const r of report) console.log(r.id, r.status, r.rate !== undefined ? `${r.agree}/${r.total} agree` : "", r.a ? `a=${r.a} b=${r.b}` : "", (r.disputes || []).slice(0, 6).join("; "));
console.log(`dates agreed ${agreeDates}, disputed or unsure ${disputedDates} → agreement ${(agreeDates / Math.max(1, agreeDates + disputedDates) * 100).toFixed(1)}%`);
