// abfall/registry.ts — the list of vendor families, and the only file that grows
// when a city is added.
//
// Adding a vendor is: write `vendors/<family>.ts` exporting an `adapter`, add its
// provider row to abfall_providers.ts, and add the two lines below. Nothing else
// in the resolver knows the family exists — there is no dispatch chain to update
// and therefore no way to add a vendor to three of four and not notice.

import type { VendorAdapter } from "./core.ts";

import { adapter as abfallio } from "./vendors/abfallio.ts";
import { adapter as abki } from "./vendors/abki.ts";
import { adapter as abfallplus } from "./vendors/abfallplus.ts";
import { adapter as athos } from "./vendors/athos.ts";
import { adapter as awbkoeln } from "./vendors/awbkoeln.ts";
import { adapter as awgbassum } from "./vendors/awgbassum.ts";
import { adapter as awido } from "./vendors/awido.ts";
import { adapter as awista } from "./vendors/awista.ts";
import { adapter as awm } from "./vendors/awm.ts";
import { adapter as awsstuttgart } from "./vendors/awsstuttgart.ts";
import { adapter as bsr } from "./vendors/bsr.ts";
import { adapter as ctrace } from "./vendors/ctrace.ts";
import { adapter as fes } from "./vendors/fes.ts";
import { adapter as ics } from "./vendors/ics.ts";
import { adapter as jumomind } from "./vendors/jumomind.ts";
import { adapter as oldenburg } from "./vendors/oldenburg.ts";
import { adapter as regioit } from "./vendors/regioit.ts";
import { adapter as srh } from "./vendors/srh.ts";
import { adapter as aha } from "./vendors/aha.ts";
import { adapter as awgwuppertal } from "./vendors/awgwuppertal.ts";
import { adapter as avea } from "./vendors/avea.ts";
import { adapter as art } from "./vendors/art.ts";
import { adapter as waswob } from "./vendors/waswob.ts";
import { adapter as albabs } from "./vendors/albabs.ts";
import { adapter as elw } from "./vendors/elw.ts";
import { adapter as fuerth } from "./vendors/fuerth.ts";
import { adapter as heilbronn } from "./vendors/heilbronn.ts";
import { adapter as abis } from "./vendors/abis.ts";
import { adapter as enni } from "./vendors/enni.ts";
import { adapter as muellmax } from "./vendors/muellmax.ts";
import { adapter as hws } from "./vendors/hws.ts";
import { adapter as ksj } from "./vendors/ksj.ts";
import { adapter as tsk } from "./vendors/tsk.ts";
import { adapter as hausmuell } from "./vendors/hausmuell.ts";
import { adapter as sab } from "./vendors/sab.ts";
import { adapter as swp } from "./vendors/swp.ts";
import { adapter as osb } from "./vendors/osb.ts";
import { adapter as meinabfall } from "./vendors/meinabfall.ts";
import { adapter as geb } from "./vendors/geb.ts";
import { adapter as mags } from "./vendors/mags.ts";
import { adapter as citko } from "./vendors/citko.ts";
import { adapter as zah } from "./vendors/zah.ts";
import { adapter as heidelberg } from "./vendors/heidelberg.ts";
import { adapter as beg } from "./vendors/beg.ts";
import { adapter as sro } from "./vendors/sro.ts";
import { adapter as ead } from "./vendors/ead.ts";
import { adapter as insertit } from "./vendors/insertit.ts";
import { adapter as srdd } from "./vendors/srdd.ts";
import { adapter as srl } from "./vendors/srl.ts";
import { adapter as wuerzburg } from "./vendors/wuerzburg.ts";

// Platform families first (one adapter, many municipalities), then the
// single-authority ones, then the vendor-less pasted link.
export const ADAPTERS: VendorAdapter[] = [
  regioit,
  awido,
  jumomind,
  abfallio,
  abfallplus,
  athos,
  insertit,
  ctrace,
  awgbassum,
  bsr,
  fes,
  awm,
  awbkoeln,
  srh,
  awsstuttgart,
  awista,
  srl,
  srdd,
  aha,
  awgwuppertal,
  abki,
  wuerzburg,
  avea,
  oldenburg,
  art,
  waswob,
  albabs,
  elw,
  fuerth,
  heilbronn,
  abis,
  enni,
  muellmax,
  hws,
  ksj,
  tsk,
  hausmuell,
  sab,
  swp,
  osb,
  meinabfall,
  geb,
  mags,
  citko,
  zah,
  heidelberg,
  beg,
  sro,
  ead,
  ics,
];

const BY_FAMILY = new Map(ADAPTERS.map((a) => [a.family, a]));

export function adapterFor(family: string | undefined): VendorAdapter | undefined {
  return family ? BY_FAMILY.get(family) : undefined;
}
