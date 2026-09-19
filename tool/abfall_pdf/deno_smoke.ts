// Proves the upload path runs under Deno, the Edge runtime, not just Node:
//   node_modules/.bin/deno run -A deno_smoke.ts corpus/<id>.pdf [choiceId]
import { encodeBase64 } from "jsr:@std/encoding@1/base64";
import { pdfToBinIcs } from "../../supabase/functions/_shared/abfall/pdf/upload.ts";
const [path, choiceId] = Deno.args;
const b64 = encodeBase64(await Deno.readFile(path));
const t = performance.now();
const r = await pdfToBinIcs(b64, { choiceId, name: "Abfall", fileName: path.split("/").pop(), today: "2026-09-19" });
console.log(Math.round(performance.now() - t) + "ms", JSON.stringify(r.ok ? { choices: r.choices.slice(0, 4), ics: r.ics?.slice(0, 300), fileName: r.fileName } : r));
