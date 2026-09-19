// Dump each corpus PDF as the positioned words and filled boxes the parser reads.
//
//   node extract.mjs            # every corpus/*.pdf → out/tokens/<id>.json (skips existing)
//   node extract.mjs <id> ...   # just those, overwriting
//
// This mirrors what the Edge Function does with the same pdfjs build, so the parser the harness
// scores is fed exactly what it will be fed in production. The shape is `PdfDoc` in
// supabase/functions/_shared/abfall/pdf/types.ts.
import fs from "node:fs";
import path from "node:path";
import * as pdfjs from "pdfjs-dist/legacy/build/pdf.mjs";
import { extractDoc } from "../../supabase/functions/_shared/abfall/pdf/extract.ts";

const here = path.dirname(new URL(import.meta.url).pathname);
const corpus = path.join(here, "corpus");
const outDir = path.join(here, "out", "tokens");
fs.mkdirSync(outDir, { recursive: true });

const only = process.argv.slice(2);
const ids = only.length ? only : fs.readdirSync(corpus).filter((f) => f.endsWith(".pdf")).map((f) => f.slice(0, -4));
let done = 0;
for (const id of ids) {
  const out = path.join(outDir, id + ".json");
  if (!only.length && fs.existsSync(out)) continue;
  try {
    const doc = await extractDoc(pdfjs, new Uint8Array(fs.readFileSync(path.join(corpus, id + ".pdf"))));
    fs.writeFileSync(out, JSON.stringify(doc));
  } catch (e) {
    fs.writeFileSync(out, JSON.stringify({ error: String(e).slice(0, 200), pages: [] }));
  }
  done++;
  if (done % 20 === 0) console.error(`${done}/${ids.length}`);
}
console.error(`extracted ${done}`);
