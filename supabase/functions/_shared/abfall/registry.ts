// abfall/registry.ts — the list of vendor families, and the only file that grows
// when a city is added.
//
// Adding a vendor is: write `vendors/<family>.ts` exporting an `adapter`, add its
// provider row to abfall_providers.ts, and add the two lines below. Nothing else
// in the resolver knows the family exists — there is no dispatch chain to update
// and therefore no way to add a vendor to three of four and not notice.

import type { VendorAdapter } from "./core.ts";

import { adapter as abfallio } from "./vendors/abfallio.ts";
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
import { adapter as regioit } from "./vendors/regioit.ts";
import { adapter as srh } from "./vendors/srh.ts";

// Platform families first (one adapter, many municipalities), then the
// single-authority ones, then the vendor-less pasted link.
export const ADAPTERS: VendorAdapter[] = [
  regioit,
  awido,
  jumomind,
  abfallio,
  ctrace,
  awgbassum,
  bsr,
  fes,
  awm,
  awbkoeln,
  srh,
  awsstuttgart,
  awista,
  ics,
];

const BY_FAMILY = new Map(ADAPTERS.map((a) => [a.family, a]));

export function adapterFor(family: string | undefined): VendorAdapter | undefined {
  return family ? BY_FAMILY.get(family) : undefined;
}
