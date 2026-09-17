// abfall.ts — German waste-collection (Abfall) resolver.
//
// This file is the PUBLIC FACE of the resolver and nothing else: the four callers
// (abfall-lookup, calendar-feed, calendar-events via feeds.ts) import from here,
// so the implementation can be reorganised without touching a function that
// serves every household's calendar.
//
// Two jobs:
//  1) Setup-time address autocomplete — aggregateTowns() + searchStreets() let the
//     client offer a "type your town / street" picker driven by the vendor's own
//     authoritative data (no hand-labelled region slugs).
//  2) Sync-time event fetch — readAbfallEvents(config) turns a stored address
//     selection into pickup events in the same SyncedEvent shape every other
//     calendar provider returns.
//
// Coverage is a MAP of providers (see abfall_providers.ts), each tagged with a
// vendor "family" = one adapter in abfall/vendors/. Two kinds of family:
//   - Platform families: ONE API/URL pattern serves many municipalities keyed by a
//     slug, so one adapter yields broad coverage. Live: `regioit` (AbfallNavi JSON
//     API), `awido` (AWIDO Online/Cubefour), `jumomind` (Jumomind/MyMuell app API),
//     `abfallio` (abfall.io/AbfallPlus legacy widget API). The path to
//     near-nationwide coverage is more of these — app.abfallplus.de v3, C-Trace —
//     added the same way.
//   - Single-authority families: a bespoke feed covering one city or district that
//     does not generalise. The five largest cities are each one of these.
//
// WHERE THE CODE LIVES — and where to add a city:
//   abfall/core.ts       types, HTTP helpers, the German street/town normalisers,
//                        and the VendorAdapter contract every vendor implements.
//   abfall/geo.ts        nationwide address autocomplete (Photon) + the Bundesland
//                        guard that stops a town name served in two Länder matching
//                        the wrong one.
//   abfall/vendors/*.ts  ONE FILE PER FAMILY. Self-contained: its endpoints, its
//                        quirks, its adapter.
//   abfall/registry.ts   the list of adapters. The only shared file a new city
//                        touches.
//   abfall/resolve.ts    the vendor-agnostic half — town aggregation, street
//                        search, address resolution, the event read. It names no
//                        vendor at all.
//
// Adding a city is therefore: one new vendors/ file, one provider row in
// abfall_providers.ts, two lines in registry.ts. There is deliberately no dispatch
// chain to update, because there used to be four and adding a vendor to three of
// them looked exactly like success.

export type {
  AbfallConfig,
  GeoAddress,
  ResolveResult,
  StreetOption,
  Town,
  VendorAdapter,
} from "./abfall/core.ts";

export { geocode } from "./abfall/geo.ts";
export { ADAPTERS, adapterFor } from "./abfall/registry.ts";
export {
  aggregateTowns,
  readAbfallEvents,
  resolveAddress,
  searchStreets,
} from "./abfall/resolve.ts";
export { normalizeIcsUrl, readIcsUrl } from "./abfall/vendors/ics.ts";
