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

**Free — a complete product for a two-calendar household:**

- **Two** connected calendar accounts, plus Ferien and Abfall (shared feeds, near-zero marginal
  cost). Raised from one on 2026-09-16: a household is at least two adults, and a free tier
  holding one account is a calendar app for one parent — most families would never have seen the
  app do the thing it is for. The third account is where Plus starts. **Abfall stays free where
  it has to come as a file too** (2026-09-19): in a town whose provider we may not fetch from, the
  household uploads the town's ICS, and that file lands on one fixed connection
  (`external_account = 'abfall:datei'`, `BIN_FILE_ACCOUNT` in `_shared/entitlements.ts`) that
  `canAddCalendarAccount` does not count. `calendar-link` only puts a file there when the town is
  upload-only, four in five events are named like a pickup, and it is under 512 KB — so the free slot
  holds bins and nothing else. Cost: ~50 KB of database per household, no extra function call, no
  outside request.
- All of Kalender, Home and Board, including **creating, editing and deleting events**
- Three trackers, unlimited lists and articles, one Box, up to four people
- Weather, the German holidays, all four languages

**Plus:**

- Unlimited calendar accounts — and with them IServ, WebUntis, GMX, Web.de and any iCal link
- Ausgaben entirely (iOS only, by nature)
- Photographs on boxes, box items and list articles, plus file attachments
- Unlimited boxes, trackers and household members

**Sharing is not on this list, on either plan — decided 2026-09-15.** It is the app's only
acquisition loop, and a list's "Teilen" now mints a link every time the system share sheet opens,
so a cap counted in links would be a cap on taps. `create-share-link`'s daily rate limit is the
abuse guard and the only limit.

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
      through, or "Erneut verbinden" would paywall repairing a calendar free entitles them to.
      Avatars are not `Feature.photos` and never were: a person's face is 512px and free.
- [x] **Share links are gated on the server only.** Moot — there is no gate any more (below).
- [x] **Settle the sharing cap** (2026-09-15). No cap on free or Plus: `Feature.shareLinks`,
      `canAddShareLink` and the paywall copy are gone from both tables.

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
- [x] **An overlay retires only against a read that actually contains the change** (`_retire`,
      `_landed`). Retiring on the first read back was right for Google and Graph, which are
      read-your-writes for the same credential, and wrong for CalDAV: iCloud accepts the PUT and
      then serves a REPORT without the new event for several seconds. The appointment blinked off
      the day it had just been added to and did not return until the next read — fifteen minutes
      later, or the next launch, which is what "I have to restart the app to see it" was. The write
      now keeps the uid `calendar-write` answers with (it was being discarded) and the add settles
      on that uid plus the title; a hide settles when the row it suppresses is really gone, each
      half on its own so a move between calendars can't show the appointment twice or not at all
      while the slower provider catches up. `_settleReads` adds at most two spaced re-reads so the
      real event arrives in seconds rather than at the next refresh, and an overlay that still has
      not landed stays up rather than being forced down — the write was accepted, so the
      appointment exists.
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
- [ ] **Verify against a running client, on two devices** — now with the fixes below.
- [x] **`realtime.messages` is partitioned and the trigger path is live** (confirmed 2026-09-19: seven
      daily partitions, both members' writes landing on `family:<uuid>`). The "dropped for want of a
      partition" worry is closed.
- [x] **First two-device test, 2026-09-19: nothing appeared until the app was killed and relaunched.**
      Four separate gaps, all on the receiving side, since the database was sending correctly:
      1. *Broadcasts are not replayed*, and supabase_flutter disconnects the socket on pause. A list made
         while the other phone was locked was announced to nobody, and only Ausgaben and the calendar
         re-read on resume. Now `FamilyChannel.catchUp()` runs on every resume and on every rejoin
         after the first (the join hooks survive a rejoin), and every screen but the calendar re-reads
         once, coalesced.
      2. *The household roster was never announced.* `family_members`, `families`, `profiles` and
         `family_invites` now carry the trigger (`20260919193715_family_realtime_roster`), including
         the old household of a member who moves, and `AppShell` re-reads `familyProvider` on them
         while keeping the signed faces, so avatars don't blink.
      3. *The calendar's device-sent announcements were refused.* On a private channel a client send
         needs an INSERT policy on `realtime.messages`, and there was none, so every
         `announce()` was silently dropped. Members may now send on their own topic.
      4. *Trackers never re-read.* `trackers`/`tracker_checks` reloaded the Board's tasks, not
         `trackerProvider`.
      The join also reports its status now (it was fire-and-forget, so a refused join looked like a
      quiet household), and a channel the server closes is reopened.
- [x] **Cost.** One broadcast per write, delivered to that household's open devices, plus one
      PostgREST re-read per screen per change or resume. The free tier's 2M messages and 200
      concurrent connections a month cover many hundreds of active families. Watch *concurrent
      connections* first as it grows.
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

### 2d — The household's own calendar colours

**A calendar's colour is the account's, and the app does not second-guess it.** iCloud gives
"Familie" Apple's system grey `#8E8E93`, which is a fine colour on Apple's white calendar and a grey
rectangle on a grey rectangle here. The first fix tried was substituting a legible colour when the
account's had no hue left; that was wrong, because the colour is what a household recognises a
calendar by in *their own calendar app* as much as in ours, and an app that quietly renames the
thing you are looking for is not helping. The real fix is a rendering one — every block gets a rim
clamped into a visible band (`_blockRim`, see the day-view section of [kalender.md](kalender.md)) —
and it holds for any colour an account can produce, grey included.

- [x] **A block is the same flat chip the rest of the app uses**, in the calendar's colour, with
      nothing drawn around it. A coloured outline (at a full point and at a tenth of one), a
      translucent fill, and a drop shadow were each tried and each lost — see the day-view section
      of [kalender.md](kalender.md). What separates a chip from the card is the dot lattice running
      under it.
- [x] **The household picks the colour, in the calendar's own sheet.** A grey calendar on a grey
      card cannot be rescued by a rim, a lift or a saturation floor, and the app will not choose a
      different colour on a family's behalf — so they choose. `calendar_connections.calendar_colors`
      is the third map of the same shape as `calendar_names` and `calendar_owners`, merged by the
      client and copied onto `calendars.color` by `calendar-events` on the next read (the app holds
      no grant on `calendars`). Ferien and Abfall needed no schema at all: `family_feeds.color`
      already existed with an UPDATE grant, and it is this household's subscription row, never the
      shared `public_feeds` one the street reads. Twelve swatches, grey included — "you may not pick
      that" is a worse answer than a calendar a family files in the colour that stays out of the
      way.
- [ ] **A colour per calendar, set in Settings.** One row per calendar on the Settings calendar
      page with a swatch that opens a picker.
      - Store it in a **new `family_calendar_colors` table keyed on (`family_id`, `calendar_id`)**,
        not in `calendar_connections.calendar_names`' shape. The id is a `calendars.id` for a
        connected calendar and a `public_feeds.id` for Ferien/Abfall, so a column on the connection
        cannot cover the feeds — and recolouring the bin calendar is exactly the case a household
        will want. One table covers both; there is no FK for the same reason `event_link` has none.
      - RLS: readable by the household, written by any member (a colour is not admin-shaped — it is
        a preference about how the family's own calendar looks). Unlike the connection tables this
        one **can** take a client INSERT: there is nothing to prove reachable first.
      - Applied in `CalendarSource.fromMap`, the one place the colour is resolved, so every surface
        picks it up at once and nothing else has to learn about it.
      - **A full picker, including grey.** The rim makes any colour legible, so there is no colour
        the household has to be protected from — and "you may not pick that one" is a worse answer
        than a block they can see. Offer the account's own colour as a reset.

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
- [ ] **Abfall sources: a lawyer's read, or the vendors' written OK** (raised 2026-09-18). The dates
      are facts, but the databases behind them can carry the § 87b UrhG database right, and each
      backend has its own terms. Aporah asks per household on demand and stores nothing, which is
      close to ordinary use. Risk by source, lowest first: the authority's own subscribe/ICS links
      (made for calendar apps); the vendor widgets authorities embed (Insert IT, Athos, regio iT,
      AbfallPlus — public but undocumented); **MyMüll, highest** — Jumomind's own backend, where a
      city recommending the app makes the *data* official but grants no third-party API right.
      Cheapest fix: ask Jumomind (and ideally Insert IT and Athos) for permission, with a credit
      line in the app.
- [ ] Datenschutzerklärung covering the user's IP reaching Bright Sky (the DWD's weather) and
      Photon (place lookup) together with a residential place — check where each is hosted first;
      Open-Meteo, which this item used to name, is gone because its free tier is non-commercial —
      the sealed school-calendar credentials in `calendar_connection_secrets`, and both stores as
      processors. This was already the open item on the WebUntis work.
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
- [ ] **Launch in the German storefront only** (decided 2026-09-18). App Store Connect → Pricing
      and Availability, and Play Console → Countries/regions, set to Germany alone; adding a
      country later is a checkbox, not a build or a review. A pilot with one market answers "does
      this work, will families pay" cleanly, where five markets at once muddy it. **The four
      languages stay** — availability follows the store account's country, not the phone's
      language, so an English- or Portuguese-speaking family living in Germany gets every German
      feature in its own language. Austria and Switzerland are *not* the free extension they look
      like: their Ferien, Feiertage and waste collection are not the German ones.
      **Growing afterwards is one country at a time**, and the order and prerequisites are already
      researched in [research/](research/Family%20calendar%20sources%20PT%20ES%20BR%20US.md):
      first a country on the household that hides Abfall/Ferien/IServ/WebUntis outside Germany
      (without it a Lisbon family's welcome tour asks for their Bundesland), then check that
      Apple's Wallet "Transaction" trigger exists in that storefront. Portugal, Spain and Brazil are
      nearest — translated, and the merchant classifier already knows their chains; the US has
      neither the classifier nor a free school or bin source.
- [ ] Store listings, screenshots and privacy labels in German, English, Portuguese and Spanish.
      **Four sets of screenshots is now the standing cost of every UI change** — that is the tax the
      extra two languages bought, and it is worth stating before the next redesign.

---

## Decided against

- **Write-back as a paid feature.** See above.
- **Gating household members below four.** A family organizer that stops at two people is not one.
- **Charging for weather, the Feiertage or the language switch.** They cost nothing — the DWD's
  forecast (via Bright Sky) is called from the device, the holidays are computed in Dart — and free
  features that cost nothing are what make the free tier worth recommending.
- **An Android equivalent of Ausgaben.** Google's Wallet API issues passes and reads no
  transactions. There is nothing to build.

---

## Notifications and the rating prompt

The plan, the principle and the record live in [notifications.md](notifications.md); this is the
pointer, so the checklist here stays the one place that says what is finished.

- [x] Local notifications (appointment reminders, Abfall the evening before, to-dos with a time,
      the morning brief), Settings → Mitteilungen, and the rating prompt. Analyze-clean, not yet
      run on a device, Android never compiled.
- [ ] Deploy `calendar-events` with the provider's own alarm (`reminder_minutes`). Written, not
      type-checked.
- [ ] Fill in the App Store id in `lib/services/app_review.dart` once the listing exists.
- [ ] Push (APNs + FCM) and the family triggers that need it.

## Abfall coverage — the map, the queue and the next vendor

The live census of what the Müllabfuhr-Kalender can connect from an address — per Bundesland,
per provider, per big city, with the vendor survey and the order of work — is the **Abfall
Coverage artifact**: <https://claude.ai/artifact/H4BjoKubN585C8rUFSmQTa>. It is built from three
JSON files by the scripts in [tool/abfall_census/](../tool/abfall_census/); rebuild it after
touching `abfall_providers.ts`. 2026-09-17: 132 providers, 3,707 towns, 14 of 16 Länder with at
least one town, 130 providers delivering dates live, and 25 of the 81 largest cities — **including
the seven largest: Berlin, Hamburg, München, Köln, Frankfurt, Stuttgart and Düsseldorf, all added
that day**. Leipzig, Dortmund and Essen are the biggest still out, and Mecklenburg-Vorpommern and
the Saarland have no town at all. The page's **Jahreswechsel** section is the answer to "does next
year arrive by itself": nothing is stored, so it does — 27 of the 130 already reach into 2027, and
the rest publish one calendar year at a time. Three shapes: Köln takes a free year range, München's
link is signed per year and the vendor decides, and Hamburg and Stuttgart have no year at all — a
rolling window of four and three months that never has a year-end. Düsseldorf is the fourth kind
and the tidiest: a calendar year, but keyed on a uuid that demonstrably survives the rollover.

- [x] **Ferien for Berlin and Hamburg** (2026-09-17). Photon has no `state` for the Stadtstaaten;
      `geocode` fills it from the city and `ferienStateOf` does the same on the client.
- [x] **"Anfragen" on the Müllabfuhr row** (2026-09-17), onboarding and connect flow, filing the
      town in `public.abfall_requests` through `abfall-lookup`; the row says "angefragt" on every
      later visit. Migration applied and the three functions deployed the same day.
- [x] **Stuttgart (AWS), and `abfall.ts` split into a vendor registry** (2026-09-17). The feed is
      addressed by the street name and house number themselves — no ids — so the whole adapter is
      the question "is this calendar about the address we asked for?". Often it is not: the server
      prefix-matches on both axes and answers `Königstr. 1` with **Kleine Königstr. 1** and
      `Badstr. 1` with **Badstr. 11**, full calendars either way. `X-WR-CALDESC` echoes what it
      actually resolved, so every fetch is checked against the request, and a shared collection
      point (which echoes no address at all) is confirmed against the street's house list instead.
      Verified live at 25 real addresses across every Bezirk — streets and numbers both taken from
      the vendor's own lists — 23 resolved, **0 matched wrongly, 0 unsupported**; the two refusals
      are genuine vendor mis-resolutions where asking is the only honest answer. Both links the
      household started from reproduce exactly, 33 and 32 events. The 2,294-line `abfall.ts` became
      a 63-line facade over `abfall/` — core, geo, registry, resolve and one file per family — so a
      city is now one new file plus four lines instead of an edit to four dispatch chains. Proved
      behaviour-preserving by diffing the full 130-provider probe against a pre-refactor baseline:
      identical, line for line.
- [x] **Göttingen** (2026-09-18) — `geb`, the city's own per-address ICS; it had been filed under
      the rhythm question by mistake. 186 providers, 69 of 81. The other ten rhythm cities were
      each checked live: five have adapters and wait only on the question, five need an adapter
      too, and Heidelberg asks per bin. See ported-features.md.
- [x] **The rhythm question in the connect flow** (2026-09-18) — per bin, only the options the
      address has, in the vendor's own words plus the measured interval; in the connect sheet and
      the onboarding. Freiburg, Hagen, Pforzheim, Saarbrücken and Neuss connect with it.
      `calendar-feed` refuses an unanswered question. See ported-features.md.
- [x] **Rostock and Reutlingen; Koblenz declined** (2026-09-19) — `sro` (new) and the TBR's own
      AbfallPlus key. 198 providers, 80 of 81 cities. Rostock's form asks for "zur Abfrage
      berechtigt", which `sro.ts` ticks for the address being connected — **confirm or reverse that
      before deploying.** Koblenz publishes no Rest/Bio dates at all (phone only). See ported-features.md.
- [x] **Mönchengladbach, Siegen, Hildesheim, Heidelberg, Bremerhaven** (2026-09-19) — `mags`,
      `citko`, `zah` (the whole Landkreis Hildesheim), `heidelberg`, `beg`. Heidelberg asks three
      bins at once; Bremerhaven publishes only 30 days ahead. See ported-features.md.
- [x] **Chemnitz, Erfurt, Magdeburg, Potsdam, Osnabrück, Erlangen** (2026-09-18, sixth batch) —
      `hausmuell` (two generations), `sab`, `swp`, `osb`, `meinabfall`. 185 providers, 68 of 81
      cities. Everything that needed only a source is built; the rest waits on the rhythm
      question, Rostock's self-declaration, Koblenz and Reutlingen. The artifact's city table now
      filters by status. See the sixth-batch section of ported-features.md.
- [x] **Nineteen more cities** (2026-09-18, fifth batch) — Bochum, Hamm, Remscheid, Münster and
      Mainz (`muellmax`, only where the city embeds it), Gelsenkirchen and Bottrop (`abis`), Trier
      with four Landkreise (`art`), Wolfsburg, Braunschweig, Wiesbaden, Fürth, Heilbronn, Moers,
      Halle, Jena, Karlsruhe (one city-own file each), Ulm (AWIDO `ebu`). 179 providers, 62 of 81
      cities; probe green but for the two dead abfall.io keys and Stuttgart. The rhythm question
      now blocks eleven cities. See the fifth-batch section of ported-features.md.
- [x] **Bonn, Augsburg, Würzburg, Leverkusen, Oldenburg** (2026-09-18, fourth batch) — two more
      Athos tenants and three city-own sources (`wuerzburg` open data, `avea`, `oldenburg`); the
      Abfall+ app backend was skipped on purpose. 161 providers, 43 of 81 cities. Hagen and
      Freiburg wait on the Restmüll-rhythm question with Pforzheim and Saarbrücken. See the
      fourth-batch section of ported-features.md.
- [x] **Mannheim, Kassel, Lübeck, Herne, Offenbach, Kiel** (2026-09-18, third batch) — two new
      families, `insertit` (five cities on one platform) and `abki` (Kiel). 153 providers, probe
      green but for the two dead abfall.io keys and Stuttgart's GIS outage. Pforzheim and
      Saarbrücken are blocked on a Restmüll-rhythm picker. See the third-batch section of
      ported-features.md.
- [x] **Dresden, Hannover, Bielefeld, Wuppertal** (2026-09-18, second batch) — three new families,
      `srdd` (Dresden), `aha` (the Region Hannover's 21 municipalities) and `awgwuppertal`, and
      Bielefeld as a fifth Athos tenant once `athos.ts` learned its script-wrapped, two-year form.
      147 providers, probe green but for the two dead abfall.io keys and Stuttgart's own GIS
      outage (which no longer reads as a reconnect). See the second-batch section of
      ported-features.md.
- [x] **Leipzig, Dortmund, Essen** (2026-09-18) — the three largest cities still missing, as three
      new families: `srl` (Leipzig), `athos` (Dortmund, plus Schaumburg, Hameln-Pyrmont and
      Landkreis Karlsruhe on the same portal) and `abfallplus` (Essen, plus Duisburg, Reutlingen,
      Märkisch-Oderland, Nordsachsen and Osterholz on the v3 widget). 143 providers, probe green
      but for the two long-dead abfall.io keys. See the Leipzig/Dortmund/Essen section of
      ported-features.md, including the postcode-fallback hole it found.
- [x] **Düsseldorf — AWISTA Kommunal** (2026-09-17), the thirteenth family and the last of the
      seven largest cities, again from an ICS a household had downloaded. The uuid in that file is
      the whole address, and nothing in the file says how to get one: the city's site is a Next.js
      app whose address search is a **Server Action**, so the lookup is a POST to an ordinary page
      URL with the function's id in a `Next-Action` header and `["Straße Nr"]` as the body. The id
      is build-specific, so a stale one (`404 Server action not found.`) sends the adapter back to
      the page's own JavaScript to re-read it. **The search never says no** — "Quatschstraße 1"
      comes back as *Kuhstraße 10*, "Königsallee 56" as *Berliner Allee 56* — so every row is held
      against its own title, and then every VEVENT's `LOCATION` is held against the request too. An
      address can also resolve to a real uuid and an **empty** calendar (Venloer Str. 1, Grafenberger
      Allee 302), which is refused rather than connected. Verified live at 49 real addresses drawn
      from OpenStreetMap, not invented: **30 resolved with the right address echoed back, 19 asked
      for a house number, 0 matched wrongly**. Of the 24 that were residential buildings, 20
      resolved; the misses are houses AWISTA's own address list does not hold (Zeisigweg has 1, 10,
      11, 13, 14 — no 12), which is why no house-number dropdown is offered. The site is behind
      Vercel's rate limiter and answers 429 to a burst, so the adapter waits and retries twice: a
      429 leaking out of the probe would read as "Düsseldorf wird noch nicht unterstützt" for a city
      that is covered.
- [ ] **Redeploy after the AWB Köln, Hamburg, Stuttgart and Düsseldorf adapters, the `abfall.ts`
      split and the `normStreet` fix**: `abfall-lookup`,
      `calendar-feed` and `calendar-events` all carry `abfall.ts` at runtime, so all three ship
      together or the new cities resolve and then never refresh. `npx supabase functions deploy
      abfall-lookup calendar-feed calendar-events --project-ref uzhzrwakrtwbpuuupccu`.
      (The FES/AWM deploy went out at 10:25 on 2026-09-17; this is the next one.)
- [x] **Berlin — BSR** (2026-09-17), the seventh family, per house and refusing to guess without
      the number. Verified live at four addresses.
- [x] **Frankfurt am Main — FES** (2026-09-17), the eighth, found from an ICS link a household
      already had: `frankfurtplus.de` exposes `/api/addresses/search` and one ICS per address id.
      Per house as well, and it checks the postcode so Frankfurt (Oder) cannot collect Hessen's bin
      days. Verified live at four addresses plus the Brandenburg negative.
- [x] **München — AWM** (2026-09-17), the ninth, from an ICS a household had downloaded. A TYPO3
      form walk: the page carries all 5,834 streets and the signed form fields, the POST answers
      with the ICS link. Reproduces that household's own file exactly. Per house as well.
- [x] **Köln — AWB** (2026-09-17), the tenth, again from an ICS a household had downloaded. Two
      keyless JSON GETs and no signature anywhere. Three things are peculiar to it and all three
      are guarded: the address search **never says "no"** (it answers "Quatschstraße" with
      "Quatermarkt"), a row's `user_*` fields are the household's address while `street_name` is
      the **Stellplatz** the bins actually go to, and the list is Stellplätze rather than houses,
      so it is full of holes — Sülzburgstr. has 5 and 100 but no 50. `supported` therefore also
      checks that dates exist, because two of six test addresses are in the list with an empty
      calendar behind them. Verified live at eleven addresses.
- [x] **Hamburg — Stadtreinigung** (2026-09-17), the eleventh, and the fifth of Germany's five
      largest cities. Built from nothing but the `webcal://…abholtermine.ics?hnIds=139014` link a
      household was already subscribed to: one unsigned POST turns a street into every house on it
      with its `hnId`, and the ICS hangs off that id alone — the same TYPO3 that forces a form walk
      in München answers here without its `cHash`. Two guards. The street search **folds nothing**
      — it is a literal prefix match, so "Fränkelstraße" finds nothing where the city writes
      "Fraenkelstraße" — so the name is re-asked in each written form until one answers; folding
      both sides afterwards, the way every other vendor is matched, is too late. And the house
      spans overlap: Winterhuder Weg lists "4-10" **and** "7a-7c", two different collection points
      that both contain number 7, so a letter decides where it can and the household is asked where
      it cannot — which costs only a dropdown, because this is the one vendor that hands over every
      house on the street. Verified live at twenty-five addresses across every Bezirk: every street
      was found, nothing matched wrongly, and the three that asked for a number genuinely lack one
      (Große Bergstraße starts at 139). hnId 139014 comes back as the feed that started it, all 48
      events identical.
- [x] **The street normaliser deleted letters it did not know** (2026-09-17). `normStreet` ended in
      a `[^a-z0-9äöü]` class, so `é` and `ß` were dropped rather than folded and "Francéstraße"
      could never meet AWM's "Francestr." — München reported "kein Entsorger" two minutes after the
      deploy that added it. `foldGerman` now folds ä/ö/ü/ß and NFD-strips accents first.
- [x] Gütersloh removed (AbfallNavi shell, no dates), Landau's abbreviated streets retried.
- [x] **Two wrong-town bugs, both found the same day** (2026-09-17). A München address in the
      running app came back with a Saxony-Anhalt hamlet's bins, because `townMatches` still had a
      bare prefix test: "München" matched "Münchenhof". Removed — seven of the eighty largest
      cities were mis-routing that way. And because 37 town names are served in more than one
      Bundesland, every provider now carries the state it serves and a candidate contradicting the
      address's own is dropped. See the Abfall section of
      [ported-features.md](ported-features.md).
- [ ] Set `APORAH_REQUESTS_TO` on `abfall-lookup` to get a mail per request; until then the queue
      is `select * from abfall_requests where status = 'open'`.
- [ ] Next vendors, in the order the census suggests: abfall.io v3 GraphQL (Essen, Duisburg,
      Göttingen, Osterholz back), Insert IT (Mannheim, Kassel, Krefeld, Lübeck), Leipzig,
      Kiel — all keyless JSON in ≤3 requests. München was a form walk;
      Müllmax bans the egress IP for 24 h and needs a daily cache first. Let `abfall_requests`
      reorder this. **The FES and AWM routes are the pattern to copy**: the vendor's own site was
      read for its address endpoints rather than a third-party list, which is how two cities nobody
      had catalogued turned out to be two JSON calls and one form POST — and Köln and Hamburg
      then fell the same way, the second of them from nothing but a household's own webcal link.
- [ ] Two abfall.io keys are dead (Osterholz, Kitzingen) and stay listed as dead until the v3
      family replaces them.
- [ ] **Every town gets its official calendar page, and "Anfragen" goes** (started 2026-09-19).
      The register is Destatis' Gemeindeverzeichnis (401 Kreise, 10,940 Gemeinden, 30.06.2026) in
      [tool/abfall_authorities/](../tool/abfall_authorities/). Agents research, per county, who
      publishes the calendar and where; a script then fetches every URL. NRW pilot first (153
      unserved towns), then the other fifteen Länder. After that the app shows the in-app
      page browser and the upload for every unserved town, and `calendar-link` takes a bin file
      from any town.
      **Research done 2026-09-19:** all 7,872 unserved towns (39.3M people) have an official page
      except three, and 423 of the 426 distinct URLs pass the fetch check. 82% of towns offer iCal,
      7.6% are PDF only (mostly TH, RP and SN). Tracked in the
      [Abfuhrkalender Atlas](https://claude.ai/artifact/DbMc4mfPLtfuVkw3HoCnUz).
      A recount with the census's district names stripped ("Altenbeken-Buke") found 104 of those
      towns already recognised, Kreis Paderborn among them (MyMüll, upload). A PDF-only town gets
      its page and the upload like any other; the PDF parser is built but parked (see step 2).
      The bigger lever turned out to be live coverage, not the upload: most counties run a vendor
      the registry already reads. Jumomind does not count, because robots.txt disallows every
      `*.jumomind.com` host.
  - [x] **Step 1: provider rows for counties on vendors we already read** (2026-09-19). 43 rows
        (22 Athos, 18 abfall.io/AbfallPlus, 1 AWIDO, 2 Müllmax), each config pulled from the
        authority's own page by `find_configs.py`, read by `probe_candidates.ts`, gated by
        `gate_candidates.py` (robots.txt for the adapter's exact path, terms) and then resolved end
        to end by `probe.ts`, which now carries a test address for each. About 1,400 atlas towns
        and 7.7M people went live; the census stands at 241 providers and 6,416 towns.
        Rhein-Hunsrück moved from upload (`jumomind-rhe`, removed) to its own Athos portal.
        **Deploy the Edge Functions for this to reach the app.**
  - [ ] Held back from step 1, each for a reason written beside the rows in
        `abfall_providers.ts`: container sizes or rhythms printed side by side with no choice
        (Zollernalb, Traunstein, Nordfriesland, Tuttlingen, Oberallgäu, Vorpommern-Rügen, like
        Göttingen), Neuwied's county-wide Schadstoffmobil stops, two Athos hosts with a broken
        certificate chain (Donau-Wald, Main-Spessart), Böblingen's publisher answering with no
        towns, six Athos tenants without a working test address yet, and EVS (the whole Saarland)
        and the c-trace county services, which need one row per town. AbfallPlus streets split
        into number ranges ("Hauptstraße 1+3, 2-26") do not resolve yet.
  - [ ] Advantic's Abfallmodul (5 counties plus the Herford towns): the one new vendor file.
  - [x] **Step 2: the page and the upload replace "Anfragen"** for every other town (2026-09-19).
        `abfall/town_pages.ts` (485 pages, 6,355 keys) answers last in `resolveAddress`;
        "Anfragen", its `request` action and the client code are gone. Upload rows and atlas towns
        are matched by `townKey` — "Buch am Erlbach" no longer reaches Altötting's MyMüll page, and
        now resolves live to Landshut's abfall.io. The details step's instructions follow the
        page's format. **Deploy `abfall-lookup` and `calendar-link` (for `isUploadOnlyTown`).**
  - [ ] 134 towns share a name with a town elsewhere in their Land that has a different page, so
        they get the upload without a page; the register's postcode could tell them apart.
  - [ ] AbfallPlus towns split into districts (Mülheim-Kärlich: Kärlich, Mülheim, …) find no
        street, because the adapter searches the city and not its districts.
  - [ ] **PDF plans — parked 2026-09-19. Built, not deployed, and not to be invested in for now.**
        The client is done behind `pdfUploadAvailable = false`: the page browser keeps the PDF,
        a base64 upload, an 8 MB cap and a Bezirk step. The parser is `_shared/abfall/pdf/` plus
        `calendar-link`'s `body.pdf` branch. The harness in `tool/abfall_pdf/` fails on any wrong
        date. The bar is 0 wrong Rest/Bio/Papier/Gelb dates wherever the parser answers;
        everything else is refused with a reason.
        - **Pilot:** 12 PDFs, each labelled twice from images. The labellers agreed on 369 of
          373 dates. The parser read 4 of the 12 with **0 wrong dates** and refused 8. Across one
          calendar per publisher it reads 12 of 65. Refusals: colour-only legend 17, not a
          calendar or an unknown layout 11, unsupported layout 8, separate tours per bin 6, month
          not fully readable 6, weekday mismatch 4, no household bins 1.
        - **Left before `pdfUploadAvailable` is flipped:** colour legends (the largest refusal
          group) and a labelled set of about 40 or more PDFs with 0 wrong dates.
        - **Open UX point:** calendars that run separate tours per bin come out as up to 16
          combined choices ("Restmüll 1 · Papier 2 · Gelber Sack 1"). One question per bin
          would read better, but the contract has a single `choice`.
        - **Why parked:** PDF-only is about 7% of unserved atlas towns, mostly small ones, and
          they still get their official page. Every other file town already has iCal. Coverage,
          plus layouts that change every year, doesn't justify the spend yet.
        - **Revisit if** households in PDF-only towns ask for it, or a major publisher turns out
          to be PDF-only.

