# Production plan — Aporah on the App Store and Google Play

**This file is the checklist we work through, and it is the record of where we stopped.** Tick a
box the moment the work is done and analyze-clean, not when it is started. If a task turns out to
be wrong, strike it and write one line saying why — a plan that only ever grows is a plan nobody
trusts.

> **Status: Phase 2 done bar provider push. Phase 1 written out; nothing Android has ever been
> compiled.** Optimistic writes, resume and foreground re-reads, live updates across devices; on
> Android the photo/file pickers, external links, the deep-link filter, `minSdk` and the signing
> config are in place, Ausgaben and the map are decided and gated, and the fifth nav slot is Boxen
> rather than Mehr there.
>
> **Two hard blockers, both outside the code.** There is **no Android SDK on this machine** —
> `flutter doctor` cannot find one — so not a line of the Android work has been compiled, let alone
> run. And **Phase 1b**: every invite and share link the app mints points at `aporah.app`, which
> does not exist, so both features are dead on both platforms today. Realtime is still
> written-not-proven too.
>
> **Phase 0 is built bar two things.** The subscription columns are live and provably unwritable by
> any client, the limits table, the provider, the paywall sheet, the copy and a debug plan switch
> all exist. What is left is deploying the server-side checks (written, never compiled — there is no
> `deno` or Supabase CLI here) and **wiring the gates into the screens**, without which every limit
> is still theory.
>
> **Android Studio is installed** (M4, via Homebrew); the SDK itself still has to come from its
> first-run wizard, which is a GUI step.
>
> Next: finish the Android SDK, build, decide the link strategy, get an app icon drawn (both
> platforms still ship the Flutter logo).
> Last touched 2026-09-11.

Phases are ordered by dependency, not by size. Phase 1 blocks the Play launch, Phase 2 is the
product's selling point, Phase 4 cannot start late because two of its items have months of lead
time.

---

## The commercial model — decided

**€4.99 per month, €39.99 per year, per household, both stores.** Fourteen-day trial. Apple's
Small Business Program and Google Play's EEA subscription tier both resolve to 15%, so one price
works on both. The full cost analysis behind this — the hosting model at 50 to 1,000,000 users,
where each euro goes, and what actually limits growth — is the Unit Economics artifact; the
conclusions that bind code are here.

**Free — a complete product for a one-calendar household:**

- One connected calendar account, plus Ferien and Abfall (shared feeds, near-zero marginal cost)
- All of Kalender, Home and Board, including **creating, editing and deleting events**
- Three trackers, unlimited lists and articles, one Box, up to four people
- Weather, the German holidays, all four languages

**Plus:**

- Unlimited calendar accounts — and with them IServ, WebUntis, GMX, Web.de and any iCal link
- Ausgaben entirely (iOS only, by nature)
- Photographs on boxes, box items and list articles, plus file attachments
- Unlimited boxes, trackers and household members
- Sharing a list or a box outside the household — **under review, see Phase 1b.** This is the app's
  only acquisition loop, and gating it may cost more in growth than it earns in upgrades. The
  likely answer is a free cap of one or two live links with unlimited on Plus.

### Why write-back is *not* the gate

It was considered and rejected. Gating "create an event in your connected calendar" puts the
paywall on a new user's **first meaningful action**, before they have had any value from the app,
and leaves a free tier that is strictly worse than the Apple or Google calendar already on the
phone. It also saves nothing: `calendar-write` runs about 30 times per household per month.

The instinct behind it — that writing is worth more than reading — is already served by the gate
we have. One free account means there is exactly one place to write. Plus means writing into any
of several, and moving an appointment between them.

**This is a placement decision, not an architecture one.** Phase 0 builds the entitlement layer so
that moving the gate is a config change. If we want to trial write-back gating later, it is a flag,
not a refactor.

### Rules that follow for code

- **Never hardcode a gate.** Every check goes through `Entitlements`, so the free/paid line can be
  moved, remote-configured or A/B tested without touching a screen.
- **A gate never hides a feature, it explains it.** Reaching a limit shows what Plus does and what
  it costs. A disabled control with no explanation reads as a bug.
- **Entitlement is per household, not per user.** One subscription covers the family; the row lives
  on `families`, and any member's purchase entitles all of them.

---

## Phase 0 — Entitlements

Everything commercial depends on this, and it is small. Build it before anything it gates.

- [x] **`public.families` gained the four subscription columns, and no client can write one.**
      Applied to the live project (`20260911160000_entitlements.sql`). **RLS could not do this job**
      — `families_update_admin` already lets an admin update their own row, and a policy decides
      *which rows*, never which columns, so adding `plan` alone would have let any admin grant
      themselves Plus with one PostgREST call. The lock is a column-level grant, the same mechanism
      `share_links.revoked_at` and `family_invites.status` already use: `revoke all`, then `select`
      whole-table and `update` on exactly `name, address, onboarding_done, avatar_url`. **Verified
      against the live database as role `authenticated`**, not assumed: those four are allowed and
      all four plan columns raise `insufficient_privilege`. A future column on `families` is
      unwritable until someone deliberately adds it to that grant, which is the intended failure
      mode. Also a partial unique index on `plan_original_txn_id`, so one store subscription cannot
      entitle two households.
- [x] `lib/models/entitlements.dart` — the plan enum and **every number in the product in one
      table**. `limitFor` returns `int?`: null is unlimited, zero is "not yours", so `allows` and
      `allowsAnother` are the only two questions a screen ever asks. The expiry backstop is
      deliberately 35 days, because Apple's billing retry runs to 16 and Google's to 30 — cutting a
      household off the day `plan_expires_at` passes would take Plus from somebody mid-renewal,
      which is worse than a month of unpaid Plus for the rare lost webhook.
- [x] `lib/state/entitlement_state.dart` — `entitlementProvider`, derived from the household row
      rather than fetched, so there is no second query and no second moment where the answer is
      missing. `Household` carries `plan` and `planExpiresAt`; the two extra columns ride the load
      every screen already waits behind.
- [x] A debug override — `planOverrideProvider`, flipped from a `kDebugMode`-only row in Settings
      that cycles real → free → Plus. **It grants nothing**: it is a value in memory and cannot
      touch `families.plan`, so anything the server enforces stays enforced while it is on. The
      paywall shows a red marker whenever it is active, so a screenshot cannot pass a simulated
      plan off as real.
- [x] `lib/widgets/paywall_sheet.dart` — one sheet, told which `Feature` was reached; the copy comes
      from `paywallTitle`/`paywallBody`, so a paywall naming the wrong feature is not expressible and
      a new gate cannot ship without a sentence explaining itself. Both prices are shown rather than
      the yearly alone at a monthly-looking number. **The upgrade button is inert** until StoreKit 2
      and Play Billing land in Phase 4.
- [x] Strings for all of it in `AppStrings` / `StringsDe` / `StringsEn`, including the debug row —
      not excepted, because the rule that a forgotten translation fails to compile is worth more
      than three strings.
- [ ] **Deploy the server-side limits. Written, not deployed, and not type-checked.**
      `supabase/functions/_shared/entitlements.ts` plus a guard in all three connect routes
      (`calendar-connect`, `calendar-caldav`, `calendar-link`) and in `create-share-link` — the two
      limits with somebody else's bill behind them. This is cheap only because `authenticated` holds
      no INSERT grant on `calendar_connections` or `share_links`, so there is exactly one place per
      resource to check and no PostgREST call around it. Two traps handled: a **reconnect** is not an
      addition (all three routes `upsert`, so a naive count would lock a free household out of
      repairing the one calendar they are entitled to), and adding another feed URL to an existing
      connection is not a new account, because a school hands out three or four links for one IServ
      account. **Neither `deno` nor the Supabase CLI is on this machine**, so none of it has been
      compiled — do not deploy it to the live project until it type-checks.
- [x] **Gates wired into the screens**, through two one-line helpers in `paywall_sheet.dart`:
      `requireFeature` for a yes/no feature and `requireAnother` for a counted one, each returning
      false once the paywall is already up. The count stays the caller's, because only the caller
      knows what counts. **Every gate sits at the last moment that is still free of the user's own
      work**, never at save: photographs are refused before the system picker rather than after a
      picture is chosen, a new Box before the form rather than at the end of it, a tracker at the
      segment that picks its kind (the sheet is shared with to-dos, so neither the way in nor the
      save would do), and Ausgaben on the menu row, which is offered and then explains itself rather
      than quietly vanishing. **Nothing that only tidies up is gated** — removing a photograph,
      editing an existing Box — or a household dropping to free could not clean up after itself.
      Calendar accounts exclude Ferien and Abfall exactly as the server does, and let a reconnect
      through, or "Erneut verbinden" would paywall repairing the one calendar free entitles them to.
      Avatars are not `Feature.photos` and never were: a person's face is 512px and free.
- [ ] **Share links are gated on the server only, and that is a gap worth closing.** The cap is per
      household and the share sheet is per resource, so the sheet cannot count what it would need
      to. `create-share-link` returns 402 with an explaining sentence and the sheet shows it as an
      error snack — correct, but a snack where every other limit gets the paywall. Closing it means
      either a household-wide live-link count in state or a 402 the sheet recognises.
- [ ] **Settle the sharing cap** (see Phase 1b). `Feature.shareLinks` is currently two live links on
      free and unlimited on Plus, in both the Dart table and the TypeScript one. One number in each.

---

## Phase 1 — Android parity (blocks the Play launch)

Four services are method channels with an iOS implementation and a **silent no-op** everywhere
else. Two of them carry features that are on the Plus list, so Android cannot be sold until they
exist.

- [x] **Media picker.** `image_picker` + `file_picker` behind the unchanged `pickAttachment`
      signature; iOS keeps its method channel. Both halves of the contract the callers rely on are
      reproduced: the longest edge capped, and the result copied into our own
      `Documents/attachments/` rather than left in a plugin cache Android may clear between the
      pick and the upload. The iOS-only gate on the calendar **file** upload is lifted with it.
- [x] **External links.** `url_launcher` on Android, the method channel on iOS. The return value is
      load-bearing — it drives the Waze-then-website fallback — so `<queries>` entries for `https`
      and `waze` went into the manifest, without which Android 11+ answers "nothing can open this"
      for every link. Google Maps' `comgooglemaps://` misses on Android and the https fallback
      lands in the app anyway, which is the right outcome.
- [x] **The map stays iOS-only, and the decision is written down.** In
      [lib/services/map_snapshot.dart](../lib/services/map_snapshot.dart), on `deviceMapsAvailable`.
      The Android twin is a static Google Maps tile or `google_maps_flutter`, and both mean an API
      key in the build and the household's addresses — the Kita, the Zahnarzt, the grandparents'
      street — going to Google on every event a parent opens. MapKit costs nothing and sends
      nothing. Buying a picture of a street with the list of streets this family visits is the trade
      the app refuses everywhere else. So on Android the location card is its **address row and the
      route button** and the "Ort" field is plain free text; the route still hands the words to Waze
      or Google Maps, which have the map and the household's consent to hold it. Two Android-only
      bugs went with the decision: the card asked `deviceMapsAvailable` *before* starting a request
      that could only fail, so the 132-point gray box no longer appears for one frame under every
      address, and the "Ort" field no longer prints **"Keine Orte gefunden"** under a search that
      never ran.
- [x] **Ausgaben stays iOS-only, and says so.** Google's Wallet API issues passes and reads no
      transactions. One getter now answers for the whole feature — `spendAvailable` in
      `lib/services/spend_intent.dart`, deliberately a separate question from
      `SpendIntents.isSupported`, which is about *capture* — and four places read it. The fifth nav
      slot is **Boxen** off iOS rather than Mehr, icon and label and all: a "Mehr" that names one
      place is a promise the menu cannot keep. `_navigateTo` therefore treats it as an ordinary tab
      with no menu to put up, `MoreScreen` returns `BoxScreen` directly so `SpendScreen` is never
      built (it is always-mounted in the stack, so building it would have `spendProvider` query a
      table nobody can see the result of), and the Apple Pay row leaves Settings — it would
      otherwise list the *other* parent's iPhones and offer to revoke them.
- [ ] Audit the Flutter fallbacks on a real Android device: `GlassSurface`, `NativeTabBar`,
      `NativeSwitch`, `NativeSearchField`, `showAnchoredMenu`. They all have one, but nobody has
      looked at them.
- [x] **Deep links, and the Google OAuth redirect that turned out not to need any.** The `aporah://`
      scheme now has its intent filter in the Android manifest, with `BROWSABLE` — without that
      category a link tapped in a mail client is never offered to us, and a mail client is where
      every one of these arrives from. **Google needs nothing per-platform**: the redirect URI
      registered at Google is the `calendar-connect` function's own URL, and the app is brought back
      by `APORAH_APP_REDIRECT` afterwards, so there is no Android client id and no second console
      entry to make. Two things this does *not* finish, and they are equally unfinished on iOS:
      every one of the four URLs must be on the **redirect allowlist in the Supabase dashboard**,
      and `aporah://invite/<token>` and `aporah://share/<token>` have **no handler in Dart at all**
      — nothing reads an incoming link. Only `login-callback` (consumed by `supabase_flutter`
      itself) and `kalender/verbunden` work today, and the second one works by merely bringing the
      app to the foreground: `_ProviderPageState` re-reads on resume and never looks at the URL.
- [x] **`minSdk` pinned to 24, and a real signing config.** `minSdk` is a literal rather than
      `flutter.minSdkVersion`, so a `flutter upgrade` cannot quietly raise the floor and drop phones
      that already have the app. The release build reads `android/key.properties` (gitignored, along
      with the keystore) and falls back to the debug key with a loud warning when it is absent, so
      `flutter run --release` still works and a debug-signed bundle cannot reach Play unnoticed —
      Play refuses it at upload. **The keystore itself is yours to generate and to keep**; it cannot
      be regenerated, and losing it means never updating the listing again:
      `keytool -genkey -v -keystore ~/aporah-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`.
      Enrol in Play App Signing, which keeps Google's copy of the app signing key separate from this
      upload key.
- [ ] **An app icon, on both platforms — this is art, not configuration.** Android has the Flutter
      template icon and **so does iOS**: `Icon-App-1024x1024@1x.png` is still the blue Flutter logo.
      One 1024 master gives the iOS set, the Android adaptive foreground/background pair and the
      Play listing icon. Nothing else on this list is blocked by it.
- [ ] **A first Android build that runs. Blocked on this machine: there is no Android SDK.**
      `flutter doctor` says "Unable to locate Android SDK". Everything above is written and none of
      it has been compiled, let alone run — install Android Studio and its SDK, then
      `flutter build apk --debug` is the first honest check of the whole Android side.
- [ ] Splash screen (`android:windowBackground` / the launch theme) matched to the app's own
      background, so the cold start is not a white flash into a dark app.

---

## Phase 1b — The links nobody can open (found 2026-09-11, blocks both stores)

**Sharing stays. Decided 2026-09-11.** It was questioned as possible scope creep and it is the
opposite: it is the only way a new household ever hears about Aporah from inside the product. A
family organizer has a closed-loop acquisition problem — a household is four people who already
know each other, and nothing about using the app well brings a fifth. A grocery list sent to a
colleague crosses that wall, and `redeem-share-link`'s own doc comment already says so: *"the web
landing page sends them through registration first, which is the point of the whole funnel."* The
guest arrives with a household of their own and one borrowed list inside it.

It is also cheaper to finish than to remove. The app-side cost is about 550 lines (the share sheet
and two Edge Functions), but the guest branches are woven through the RLS predicates — 84
references across 12 migrations — and `can_read_list` / `can_read_box` are what the picture buckets
key on. Deleting the feature means unpicking the security model; finishing it means a landing page
and a link handler.

**The boundary to hold:** a guest gets **one resource, inside their own household, and nothing
else**. `guest_access` is one row per shared thing and `shareable_kind` names only list, box and
task. That is what keeps this a growth loop rather than a second collaboration product with shared
households and a permissions UI. Don't let it grow.

**Open question the decision creates: sharing outward is currently on the Plus list, and that gates
the funnel.** If a share link is how new people arrive, charging €4.99 before anyone can send one
throttles acquisition to buy a feature that costs us almost nothing to serve — a guest reading a
list is a handful of PostgREST reads. Recommendation: **move outward sharing to free, capped** (one
or two live links at a time), and keep *unlimited* links on Plus. The cap is a real upsell for the
household that shares constantly, and the first link — the one that matters for growth — is free.
To be settled in Phase 0, where the limits table is written.

---

Not Android parity: **this is broken identically on both platforms**, and it was found while wiring
the Android intent filter. Two of the app's own features mint a link that leads nowhere.

`create-share-link` returns `https://aporah.app/share/<token>` and `invite-member` returns
`https://aporah.app/invite/<token>` (`APORAH_WEB_URL`, defaulting to that host). **There is nothing
at that domain** — it was the old web app's, and the web app is being deleted. So a parent invited
to the household gets a dead link in their mail, and a grandparent sent a shared list gets the same.
`redeem-share-link` and `accept-invite` both work; nothing can reach them.

The `aporah://invite/<token>` and `aporah://share/<token>` schemes that `ios/Runner/Info.plist`
documents are **not minted by anything** — that comment describes a route that was never built — and
no Dart code reads an incoming link on either platform.

- [ ] **Decide the link strategy.** The recommendation is a real `aporah.app` with **Universal Links
      and App Links**: `apple-app-site-association` and `assetlinks.json` on the domain, so an
      installed app opens the link directly and everyone else lands on a page that says what Aporah
      is and offers both stores. A bare `aporah://` custom scheme is the cheap alternative and is
      wrong for exactly the case that matters — the recipient of a share link is by definition
      someone who may not have the app, and a custom scheme shows them a browser error. This needs
      the domain, a static page and a store listing id, so it is weeks of lead time in wall-clock
      even though it is a day of work.
- [ ] Read an incoming link in Dart and act on it: the token goes to `accept-invite` or
      `redeem-share-link`, and the app lands on the thing that was shared. Needed for both flows and
      built for neither.
- [ ] Fix the stale `CFBundleURLTypes` comment once the answer is known.

---

## Phase 2 — The live calendar (the selling point)

**Supabase Realtime does not solve this on its own.** It broadcasts changes to *our* Postgres
tables, and we deliberately store no events, so there is nothing for it to carry. The calendar
needs three separate mechanisms, and only the second is Realtime.

### 2a — Your own write appears instantly

Today `createEvent` writes and then calls `refresh()`, which fans out to every connected provider
on a 90-second budget. The user watches a spinner after saving an appointment. This is the single
worst interaction in the app and it is the one the product is sold on.

- [x] Apply the event **optimistically**. Provisional events are held in an overlay *beside* the
      snapshot (`_pendingAdds` / `_pendingHides`) and merged on the way into state, rather than
      patched into the fetched day map — where the next refresh, from a resume or from anybody,
      would have silently wiped the write back off.
- [x] Reconcile or roll back when the function answers. Overlay entries retire **with** the next
      snapshot, not before it (which blinks the event out for the length of the read) and not after
      it (which shows the provisional and the real one side by side for a frame).
- [x] Same for edit and delete, including the create-then-delete move between calendars, and
      hiding a whole series when that is what is being deleted.
- [x] The post-write read is now background housekeeping. `createEvent` returns as soon as
      `calendar-write` accepts, which is the only part that can fail in a way the user must know
      about. `onProgress` and the `calendarsUpdating` string are gone with the two-stage wait.
- [x] `_readAfterWrite` refuses to join a read already in the air — it left before the write did,
      so its answer cannot contain it.
- [ ] **A series edit is deliberately still synchronous.** The app is handed expanded occurrences
      and never the rule behind them, so the client cannot know which other days a changed series
      lands on. Revisit only if `calendar-write` starts returning the new occurrence set.

### 2b — Another member's change appears without a reload

- [x] **Broadcast, not Postgres Changes.** `postgres_changes` re-evaluates every subscriber's RLS
      against every changed row, so one tick on a shopping list costs a policy evaluation per
      connected device. One topic per household, `family:<uuid>`, private, authorized once on join.
- [x] **The message carries no row** — the table's name and who changed it, nothing else. Receivers
      re-read through the repository they always use, which goes through RLS. A payload with the
      row in it would be a second read path with its own access rules to get wrong.
- [x] `private.broadcast_family_change()` on all eight content tables, resolving the household from
      `family_id` or, for the two item tables, from the container. The send is wrapped so a
      Realtime outage can never roll back a user's write.
- [x] RLS on `realtime.messages`: members read and send on their own household topic only.
- [x] `FamilyChannel` + `reloadOnFamilyChange`, wired into Listen, Box, Board and Ausgaben. A
      400 ms coalesce, and a device ignores the echo of its own write.
- [x] Calendar invalidation over the same channel. **The calendar is the one thing a trigger cannot
      announce** — storing no events means there is no row to fire on — so the writing device says
      so itself and everyone re-reads through `calendar-events`.
- [ ] **Verify against a running client, on two devices.** Nothing below has been exercised.
- [ ] **`realtime.messages` has no partitions on this project and pg_cron is absent**, so
      `realtime.send` currently warns and drops every message it is handed — it catches its own
      insert failure by design. This is expected to fix itself: Supabase's Realtime service
      provisions partitions when it first runs for a tenant, and nothing has ever connected. It is
      also self-correcting in the only way that matters — with no client connected there is nobody
      to miss a dropped message. **Confirm it after the first connection**:
      `select count(*) from pg_inherits i join pg_class p on p.oid = i.inhparent where p.relname = 'messages';`
      If it is still zero once a device has been online, the trigger path is dead and every
      announcement has to come from the client.
- [ ] **Guests get no live updates.** Somebody outside the household reading through a share link
      has a different `my_family_id()`, so they never join the topic. Fixing it means a
      per-shareable topic.

### 2c — A change made in Google or Outlook directly

Neither optimistic writes nor Realtime help here; the change happened outside our system entirely.

- [x] **Refresh on resume.** `AppShell` now observes the lifecycle and calls
      `CalendarNotifier.refreshIfStale()` on resume, throttled to two minutes and silent on
      failure. Before this the only calendar read in the app's life was the one at launch, because
      all five screens stay mounted in the `IndexedStack` and nothing ever remounts — a phone left
      in a pocket overnight showed yesterday. "Jetzt aktualisieren" deliberately still calls
      `refresh()` and ignores the throttle.
- [x] A throttled foreground interval — fifteen minutes, riding the clock ticker the agenda
      already runs. That makes it foreground-only for free: iOS suspends timers with the app, so a
      phone in a pocket polls nothing. Much longer than the two-minute resume window on purpose —
      a resume is a moment the user is about to look, this fires whether anyone is looking or not,
      and the provider quota it spends is shared across every user of the app.
- [ ] Provider push, later: Google Calendar watch channels and Microsoft Graph subscriptions into
      an Edge Function that broadcasts on the same family channel. Note the renewal burden — Graph
      calendar subscriptions cap at about three days, Google's at about a week — so this needs a
      scheduled renewal job and should not be started until 2a and 2b are in.

---

## Phase 3 — Scale and cost

None of this is urgent at launch. All of it is much cheaper to do before there are households on
the other end.

- [ ] Narrow the sync window. `MONTHS_BACK`/`MONTHS_FORWARD` in
      [supabase/functions/_shared/calendar.ts](../supabase/functions/_shared/calendar.ts) are 6 and
      18. Six and six roughly halves the largest response the app ever receives, with almost
      nothing lost on screen.
- [ ] Confirm `calendar-events` responses are actually gzipped. If they are not, egress is roughly
      double the model and this is the cheapest fix in the project.
- [ ] Stagger the morning refresh. Every household refreshes between seven and nine and each
      refresh holds a function open while it fans out on fifteen-second timeouts. The invoice
      counts invocations and does not care; concurrency does.
- [ ] Move the Supabase organisation from Free to Pro before launch, not after the first limit.

---

## Phase 4 — Store, billing and legal

**Start the first two items now.** They are the only things in this document with a lead time
longer than the engineering.

- [ ] **Google Calendar API quota review.** Quota is issued per project, not per user, so it is the
      ceiling at tens of thousands of households. Sensitive-scope review takes months.
- [ ] **Microsoft Graph** equivalent.
- [ ] An AVV with Supabase.
- [ ] Datenschutzerklärung covering the user's IP reaching Open-Meteo with a residential
      coordinate, the sealed school-calendar credentials in `calendar_connection_secrets`, and both
      stores as processors. This was already the open item on the WebUntis work.
- [ ] Enrol in the App Store Small Business Program **before the first sale** — €0.63 per
      subscriber per month, one form.
- [ ] Register for Google Play (€25 one-off).
- [ ] StoreKit 2 and Play Billing behind one Dart interface, so `entitlementProvider` does not know
      which store it is on.
- [ ] A `store-webhook` Edge Function — App Store Server Notifications V2 and Play Real-time
      Developer Notifications — as the **only** writer of the subscription columns. `verify_jwt`
      stays true for neither; both verify their own signature, which makes this the third and
      fourth pinned exception and each needs the same comment in `config.toml` explaining why.
- [ ] Restore purchases, and a household that already has Plus not being charged twice.
- [ ] Store listings, screenshots and privacy labels in German, English, Portuguese and Spanish.
      **Four sets of screenshots is now the standing cost of every UI change** — that is the tax the
      extra two languages bought, and it is worth stating before the next redesign.

---

## Decided against

- **Write-back as a paid feature.** See above.
- **Gating household members below four.** A family organizer that stops at two people is not one.
- **Charging for weather, the Feiertage or the language switch.** They cost nothing — Open-Meteo is
  called from the device, the holidays are computed in Dart — and free features that cost nothing
  are what make the free tier worth recommending.
- **An Android equivalent of Ausgaben.** Google's Wallet API issues passes and reads no
  transactions. There is nothing to build.
