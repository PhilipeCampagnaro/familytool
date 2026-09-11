# Ausgaben — spend tracking

Two ways a payment gets in, one table behind them, and one page that adds it up.

## The Apple Pay route, and what it can and cannot be

An iOS **Personal Automation** with the **Transaction** trigger runs an **App Intent** that Aporah
donates, and the intent posts the payment to `spend-ingest` from Swift. The phone is usually locked
and the app is not on screen, so no Flutter engine is involved at any point.

**No app can install a Personal Automation.** There is no API, there never has been, and the Apple
developer-forum thread asking for exactly this is unanswered. Apps that look pre-configured in
Shortcuts are donating *actions* through an `AppShortcutsProvider`, which is what
`ios/Runner/SpendAppIntent.swift` does — the action is in the list the moment Aporah is installed.
The trigger is always the user's to create. Don't go looking for a `shortcuts://` deep link that
makes one; there isn't a verb for it.

What that buys against the old web app is the whole reason this was rebuilt:

| Old Aporah (web) | Here |
|---|---|
| Copy a family-wide `families.ingest_token` to the clipboard | nothing — the user never sees a credential |
| Download a shortcut from an iCloud link, paste the token at an import prompt | nothing — the action is already there |
| Automation runs "Get Contents of URL" with a hand-built JSON body | Automation runs our action |

Setup is now: Shortcuts → Automation → **+** → Transaction → pick cards → **Ausgabe erfassen**.

### Apple's Transaction trigger hands over holes, and we keep them

A merchant that arrives as `""` and an amount that arrives as `0.0` are a
[known defect](https://developer.apple.com/forums/thread/797233) in the Transaction trigger's
handoff to *custom* App Intents. Apple DTS reproduced that built-in actions receive the same
variables intact and the thread ends there. `spend-ingest` therefore **writes the row anyway** and
sets `needs_review`; the page carries a folded line at the top for a two-second fix.

Dropping them was the obvious alternative and is the wrong one. The payment really happened, the
phone was locked when it did, and there is no way to tell the user about something silently binned.

### What it cannot see

Device Apple Pay only. A physical card, a browser checkout, a bank transfer, a direct debit and cash
are all invisible. **Manual entry is therefore half the feature, not a fallback** — a page that
counted only NFC taps would under-report a German household's month badly enough to be worse than no
page at all.

## The credential

`spend-enroll` mints a **per-device** token, hands it back exactly once, and stores only its
SHA-256 — the same contract as `invite-member` and `create-share-link`. The Flutter side puts the
raw token straight into the Keychain (`ios/Runner/SpendCapture.swift`) and never shows it.

- **`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`** is load-bearing. `WhenUnlocked` would make
  the token unreadable at exactly the moment it is wanted, because an automation fires on a phone in
  a pocket. `ThisDeviceOnly` because the token names *this* device on the server; syncing it through
  iCloud Keychain would put one phone's credential on another and make the revoke list lie.
- **The endpoint travels with the token**, rather than being compiled into Swift. A build pointed at
  a staging project with `--dart-define=SUPABASE_URL=…` files its spends there too, and there is no
  second copy of that address to get out of step.
- Keyed on `identifierForVendor`, so re-enrolling a phone **rotates** its row instead of leaving a
  second working token behind a name nobody recognises.

`spend-ingest` is the second function in the project pinned to `verify_jwt = false`, and for a
structural reason rather than a preference: a background automation has no session and can never
have one, so the gateway check would reject every legitimate post. The device token is the entire
security boundary and it is checked inside the function. It is declared in `supabase/config.toml`
so a routine `supabase functions deploy` cannot quietly re-secure it.

## The merchant rules live in SQL, and only in SQL

`private.classify_merchant(text)` turns a merchant name into a `public.spend_category`, and the
`spends_classify` BEFORE INSERT trigger calls it whenever the writer left `category` null.

Two paths write a spend — the ingest function as `service_role`, and the Flutter client inserting
what a user typed — and a copy of these rules in TypeScript *and* Dart would be two copies that
drift. The drift shows up as the same shop landing in different slices of the same ring depending on
how its row arrived. The database is the one place both paths already pass through.

Three things about it that are easy to get wrong:

- **Postgres word boundaries are `\y`, not `\b`.** `\b` is a backspace character here and matches
  nothing, silently.
- **First match wins, and the order is deliberate.** Several patterns are short enough to collide
  (`dm`, `bp`, `hit`, `db`), so the broad everyday categories are asked first.
- **`authenticated` keeps EXECUTE on it.** The trigger function is not `SECURITY DEFINER`, so the
  call inside it is evaluated as the role doing the insert. Revoking it would make every manual
  entry fail on a function the user never named. Living in `private` is what keeps it off
  `/rest/v1/rpc/`, exactly as for `private.is_admin()` — the grant was never what protected it.

The patterns are ported from the old web app's `SPEND_CATEGORIES`, which a German household tuned
against its own receipts over a couple of years. **That tuning is the value, not the regex.** The old
app also fell back to DeepSeek for merchants the regexes missed; that is deliberately not here —
unknown merchants land in `other`, which is an honest answer, and the user can override.

## Admin only

`spends_select` and its three siblings name `private.is_admin()`. There is no `visibility` column and
no `spend_shares` table: a spend row is not a container somebody owns a private copy of, it is the
household's money.

`docs/backend.md`'s permission matrix pencilled Finanzen in as admin **+ member**; this ships
admin-only because that is the smaller promise to walk back. Widening it is one
`or private.my_role() = 'member'` in four policies. A `member` who opens the tab gets a sentence
rather than an empty month they would read as "nobody spent anything".

`shareable_kind` still names no value for a spend, so none of it can be shared outward.

## Money is integer cents

`amount_cents bigint`, always positive. A month is a few hundred rows added together and a binary
float cannot hold `0.10` exactly, so summing doubles drifts and the total disagrees with the rows
above it. The old web app stored the amount as **text** and documented that one mis-mapped Shortcut
field could make the whole family's view throw; there is no parse here to throw.

A refund is not a negative spend. It is a different thing this app does not model.

## The page

`lib/screens/spend_screen.dart`, reached from the **Mehr** tab — which is a system menu on the nav
bar rather than a page, so Ausgaben opens in one tap and carries no back control. Everything the
screen draws is a fold over the rows in `lib/data/spend_analysis.dart` — nothing derived is stored,
for the same reason `german_holidays.dart` computes the Feiertage.

### It adds up a range, not a month

`SpendRange` is the unit the whole page turns on: a half-open pair of local midnights plus the
`SpendPeriod` that produced it. The slicer offers four — **1 W., 1 M., 6 M., 1 J.** — and the
calendar button beside it produces the fifth, `custom`, out of two picked days.

- **Every preset is aligned to the calendar rather than counted back from today.** "Dieses Jahr" has
  to mean January to December or the comparison against last year is a comparison of two arbitrary
  windows, and a household asking what it spent this month means the month on the wall.
- **`SpendRange.previous` shifts by the calendar unit, not by a duration.** February against January
  is the comparison somebody means; subtracting 31 days from 1 March lands on 29 January. Custom is
  the exception and shifts by its own length, because two picked days name no unit.
- **The loaded window always reaches over `previous` as well**, which is what makes the slicer feel
  instant: going from a year to a week never fetches, because the week is inside the year. The range
  goes on screen before any fetch either way, so the chart redraws from the rows already held.
- **Buckets are days or months and never weeks.** Six months in weeks is 26 bars nobody can label,
  and a month in weeks is five, of which two are stubs. A custom range crosses over at twelve weeks.
- **A bucket that has not started is not a bucket with nothing in it.** `isFuture` keeps them out of
  the bars, out of the cumulative line and out of the average — an empty December in September is
  not a December nobody spent anything in — while the *empty* buckets inside the range stay, because
  they are what makes a chart show the rhythm of a month rather than a row of bars with the gaps
  squeezed out.
- **The average divides by a fraction of a bucket.** `elapsedUnits` counts the current bucket as how
  much of it has been lived, so a yearly average is not dragged down by a tenth on the 2nd of the
  month and does not throw away the money already spent in it either.

The month pager that used to sit in the collapsing header — a swipe, a total and a row of six dots —
is gone with it, and so is the six-month bound it needed. A row of dots has to be countable; a date
picker does not, and the honest answer to "what did we spend in March two years ago" was always the
picker rather than forty swipes.

### Three charts, one range, and the slicer that swaps them

`SpendChart` names them and a pill switches between them. They are three answers about the same
money rather than three cards down a page: stacked, two of them were always scrolled past.

**The three are swiped, not tapped, and a row of dots says so.** A pill of three glyphs was a second
control stacked above the range slicer — forty points of a phone spent saying "there are three of
these", in symbols that had to be learned before they meant anything. `StepDots` says it in six and
names a gesture the phone already taught, which is the same mark and the same reasoning as the month
pager this page used to carry. The dots sit between the drawing and the range slicer.

The order inside the card never changes: headline, drawing, dots, range slicer, and the donut is
drawn at exactly the height the other two are, so turning a page moves nothing but the drawing. The
headline follows the page *as it turns* rather than after it lands, because the line under the total
is the chart's own caption — a trend's is the gap against last time, a bar chart's is the average
drawn through it — and a caption that arrives late belongs to the drawing that has already gone.

**The card matters as much as the order.** The analysis used to float on the grey panel while every
other block on the page was a card, which made the page's most important thing look like the one
thing nobody had laid out.

- **Verlauf** is *cumulative*, with the previous stretch behind it in grey. That is the whole reason
  it sits beside the bars: the question is "are we ahead of last month", which is a race between two
  lines and not a comparison of thirty pairs of bars. The grey line runs the full width because last
  month is over; the accent one stops where the month has got to, and a dotted callout names the
  figure it stopped at. Both share one scale or the race is a lie.
  - **The head of the line pulses**, and it is the only thing on the page that moves on its own. The
    point it stops at is *now* — the money as it stands this second, with the rest of the stretch
    still to come — and a ring breathing out of it says that where a static dot said "the data ends
    here". Slow, because it is a heartbeat and not a spinner, and off entirely under
    `MediaQuery.disableAnimationsOf`: a ring expanding for ever at the top of a page is exactly what
    "Bewegung reduzieren" is for, and the chart says everything it has to say without it.
- **Balken** is one bar per bucket, in the same accent the trend line is drawn in — one colour for
  "this is the money", whichever way it is being drawn — with the average dashed through them in the
  app's **ink**, because a dashed accent rule across accent bars is a rule nobody can see. It is the
  colour the bars themselves used to be, so the chart still carries the same two marks the other way
  round. The ceiling gridline is the **tallest bar itself** rather than a rounded-up axis maximum,
  so it labels a figure the household actually spent instead of a number picked to make the
  arithmetic tidy.
- **Ring** is the donut, and its hole holds how many payments made the total — not the total, which
  is in the headline above it like the other two views. **Five arcs at most**, the last of them
  "Sonstige": it was seven, and seven is past where a ring stops being read as a picture and starts
  being read as a table with extra steps. One
  category left over is named rather than folded — hiding a name to save nothing is not a saving.
  - **Nothing is drawn behind the arcs.** They always add up to the whole circle, so the grey track
    under them only ever showed through the partings — which reads as a fifth colourless slice laid
    across all of them rather than as the gaps it was filling. The track is still what an *empty*
    range draws, because a ring with no arcs has to be a ring and not a blank square.
  - **The gap between arcs is measured, not chosen.** A round cap sticks out past its arc's own end
    by half the stroke, which at this radius is about a seventh of a radian, so every constant small
    enough to read as a small gap had the two caps either side of a join growing *into* each other
    and the join came out as a bulge. `_gapFor` takes the cap's own angle off the geometry, which is
    what puts the caps exactly touching at whatever size the ring is drawn, and adds a quarter of a
    stroke of daylight on top of that — so the gap on screen is the gap that was asked for rather
    than whatever is left over once the caps have had their share.
  - **The hole is a label over a figure, in both of its states.** It reads "Zahlungen" over "27"
    normally and the category over its amount once an arc is tapped, rather than a sentence that
    rearranges itself into a stack — a tap should change the answer, not the furniture. Set the same
    way round, a count and a category read as two answers to one question, which is what they are.
  - **Tap an arc and the hole says what it is** — the category, what it came to, and its share in
    the arc's own colour, which is the one place on the page a slice colour appears as text. A slice
    of a donut is a shape with no words on it, and the hole is already the middle of what the finger
    is pointing at; a label out at the rim would have to dodge four other labels. The rest of the
    ring stands back to 22% while one is chosen, and a second tap on the same arc puts it back,
    which is the only way out that does not need a control of its own.
- **A category's colour comes from its own position in the enum, never from its rank this month.**
  Colours assigned by ranking make two stretches impossible to compare, which is most of what
  anybody does with this page. `AppSpendColors.forCategory` in `tokens.dart`. **There is one colour
  per category and then the grey**, because the short palette it started with folded the last six
  categories onto that grey: a ring holding Wohnen, Elektronik and Transport drew three identical
  arcs, and a colour that is shared is not a colour. Only four of them are ever on screen at once,
  so they have to survive being read four at a time beside a name rather than as a thirteen-way
  legend.
- **Still no chart package, and now for a stronger reason than "two shapes".** The design is
  specific down to the dashed average line, the rounded arc gaps, the comparison line that outruns
  the current one and the callout on the point it stopped at. Bending a package's axes, tooltips and
  type scale into that is more code than painting it, and every default that leaked through would be
  the one part of the app that came from somewhere else. None of the chart widgets may be
  `const`-constructed; `tool/check_const_palette.dart` enforces it.

### Press and hold a chart to read a day off it

`ChartScrub` wraps the line and the bar chart: hold a finger down and slide, and the bucket under it
is reported up to the card, which puts **that** figure in the headline with the date under it. The
line answers "how much by here" (it is cumulative) and the bars answer "how much here", which is the
same difference the two drawings already are.

- **Press and hold, not touch and drag, and that is not a compromise.** The charts live in a pager —
  a horizontal drag on one of them is the gesture that turns to the next chart — so a scrubber that
  took plain drags would have left the pager unusable. A long press is what iOS's own charts take
  for the same reason, and it is the only gesture here that cannot be started by accident while
  scrolling the page.
- **The reading goes in the headline, not in a bubble at the finger.** A tooltip covers exactly the
  stretch of chart the reader is dragging along, and the headline is already the place this card
  says what a number is worth.
- **It lets go on release.** A reading left behind after the finger has gone is a headline that has
  quietly stopped being about the page.
- **A `lightImpact` each time the finger crosses into the next bucket**, the same tick the swipe
  actions and the undo chip use. Sliding along a line the eye is not on is the whole of what the
  gesture is for; without the tick the reader has to watch the headline to know anything happened.
- **The plot's width is measured in the widget and handed to the painter**, because the two must not
  disagree: a finger halfway along a plot the painter thinks is forty points wider lands on the
  wrong day. `_plotWidth` is the one place that arithmetic lives.
- The line's marker is a rule down the plot and a dot ringed in the card's own colour, so it reads
  as sitting *on* the line rather than as a kink in it, and the head's pulse and end label stand
  down while it is up. The bar chart just turns the bar under the finger to ink — dimming the
  others made the whole chart flinch every time somebody touched it.

### The picker on the total is the total's label

`SpendMetric` is **Ausgaben / Fixkosten / Extras**, and it filters the whole page rather than one
card. It sits on the headline row, at the right-hand end of the total's own line, because it *is*
that total's label: swapping it changes what every figure on the page means, and a filter chip
parked somewhere else would leave the headline saying "Ausgaben" over a number that is only the
fixed ones. Beside the figure rather than stacked above it — reading "1.234 €" and "Extras" across
one line says the same thing in one row of the card instead of two.

The flagged rows are folded **before** the filter. A row nobody has looked at yet is exactly the row
whose `kind` cannot be trusted to decide whether to show it.

### One breakdown card with a picker, five rows, and a page for the rest

Category, shop and person are three answers to the same question and only ever one is being asked.
The card's heading *is* the control, which is why it carries a caret: a reader looking for "wo am
meisten" looks at the heading that currently says something else.

- **Five rows, because that is what the ring shows.** A card listing fourteen categories under a
  drawing of five is a card contradicting the picture above it, and the other two groupings take the
  same five so the page has one idea of "top" rather than three.
- **"Alle anzeigen" opens a page, not a longer card** (`SpendBreakdownPage`). A card grown to forty
  rows buries the payments under it; somebody who wants the whole list is reading rather than
  glancing, and reading deserves the screen. The link is drawn only where there is something behind
  it. The page watches the same range and metric as the card it was opened from, so a figure on it
  is the same figure that was on the card — and it is the one place the categories are **unfolded**,
  with "Sonstige" spelled out into the things it was hiding.
- **By shop rather than by category is the one with an answer somebody can act on.** "€340
  Lebensmittel" is a fact about a month; "€340 bei REWE" is a fact about a habit. Names are folded
  case-insensitively, and deliberately no further — "REWE Markt GmbH" and "REWE City 4471" really
  are different shops to somebody reading their own statement. Nothing caps the merchant fold any
  more: the card takes its five and the page takes the lot, off one list.
- The percentage sits under the amount rather than between the name and it, so the two numbers that
  answer the same question at two zoom levels make one column the eye can compare.
- `ringSlices` feeds the donut *and* the card, so the two can never disagree about what folded into
  "Sonstige"; `spendBreakdownRows` is where the three groupings are turned into the one row shape
  the card and the page both draw.
- **The payments list under it does the same thing, at ten** (`SpendPurchasesPage`). It has no
  picture to agree with, so five would be short: what somebody scrolling to the bottom of Ausgaben
  is doing is scanning recent payments for one they half-remember, and ten is about a week of a
  normal household. A year selected in the slicer puts several hundred rows in that card otherwise,
  and everything under it — the wallet card included — becomes something you scroll past on the way
  to the tab bar. **The count moved into the link** rather than sitting beside it: a heading on a
  phone holds a title and one other thing, so it reads "Alle 214 anzeigen" and goes back to being a
  plain count once the list fits.

### One mark, and a shop is drawn as itself

Every row on the page wears the same grey circle (`SpendMark`), and what is inside it is the only
thing that changes.

- **A business gets its logo** where `assets/merchants/` has one — the same two hundred marks Listen
  already searches, matched by `merchantLogoAsset`, which consults the shop folder and nothing else.
  A payment at "Apotheke am Markt" wants the Shop-Apotheke logo or no logo; it never wants the
  generic pill-bottle symbol, because a row that cannot be matched to a brand is not a row about a
  category.
- **Where there is no logo it gets the shop's first two letters**, black on the same grey. One
  shopfront glyph repeated down a column of eight different shops names none of them; two letters
  name every one. Letters *and digits*, because "Q1" and "o2" are shops.
- **Everything else is the category's own glyph in the app's ink** — duotone, so the black line sits
  on its grey fill, which is what the tone-coloured tiles were flattening.
- **A payment row is marked by its shop, not by its category.** The row's title *is* the shop, and
  the category is already the middle word of the line under it.
- **A person stays a person.** A household member has a picture and a tone that are theirs across
  all five tabs, and grey-ing them here would be Ausgaben inventing a second way to draw somebody
  who is already drawn everywhere else.

The card's rows no longer carry the arc colour they used to be filled with. Three kinds of tile down
one left edge — a tone-coloured square, a filled category colour, a neutral circle — read as three
unrelated lists that happened to be stacked, and a column of identical discs is what lets the eye go
down the *names*. Colour now means one thing on this page, and it means it in the donut.

### Nothing on the card cuts

Three things move when the slicer is tapped, and they are three halves of one gesture.

- **The chart is swept on from the left** (`ChartReveal`). A drawing that is swapped out is a
  drawing nobody watched change, and the slicer sits directly under it — every tap on it is a reader
  asking "and what does *that* look like". The sweep says which way time runs, which is the one
  thing all three drawings have in common; the ring's version of it grows the arcs clockwise out of
  twelve o'clock, biggest first, so the answer is readable before the picture has finished. The
  reveal fires on the **subtree being built**, keyed on the range and the metric — scrubbing,
  turning the pager and the head pulse rebuild the same element and leave it where it was, because a
  reveal that replayed on every frame of a drag is a chart that never settles. An `AnimatedSwitcher`
  around it carries the old picture out while the new one arrives, or the sweep would still start
  from a blink.
- **The total rolls** (`RollingNumber`). Only the digits that changed move, so a reader sees where
  the change was; a figure that ticks under a finger dragging along the chart reads as one quantity
  being measured rather than as numbers being flashed in the same place. It is scaled down rather
  than ellipsised, because this figure is the answer the whole card is for.
- **The slicer's thumb travels.** See the `SegmentedControl` notes in
  [design-system.md](design-system.md): the four segments are an ordered scale, and a capsule that
  vanishes from under one word and reappears under another says nothing about which way the choice
  went.

### The status island says the one thing worth saying

`SpendIsland` (`lib/screens/spend/spend_island.dart`) fills the collapsing block under the page
title — the slot Home gives its day and Kalender its month name — with **one sentence and a second
line saying what it counts**. It is the same widget underneath: `StatusIsland` and `IslandLine` in
`lib/widgets/status_island.dart`, lifted out of `DayIsland` the moment there were two of them.

A row of figures there would have been a dashboard on top of a dashboard. The card directly below
already prints the total, the trend and the breakdown; what the island adds is the thing a household
would otherwise have had to work out by looking.

**The cases are a ladder and the first match wins:**

1. still working it out — the only rung about the app rather than the money, and the one that
   shimmers on a loop, because there the wave *is* the spinner;
2. rows the automation could not read, which outrank everything under them: they are the one thing
   on the page asking for something rather than telling you something;
3. a range with nothing in it;
4. a rise or a fall of **five percent or more** against the stretch before — deliberately far above
   the one percent the old header chip used, because that chip captioned a figure the reader was
   already looking at and this is a sentence claiming something is worth knowing;
5. which category is carrying the range, under its own glyph.

**Every glyph is ink, and none of them is coloured.** A red warning and a green fall were the
obvious design and they are wrong here for the same reason the words are black: the line sits
directly above a card that is nothing but colour — seven category hues in the ring, a red trend
line, a blue average — and a tinted mark above all of that reads as a fourth thing competing rather
than as a tone. The glyph names what the sentence is about; the sentence says whether it is good
news. (Home keeps its red and its green, because what is under *it* is a page of black headings.)

**It sits in the same 48-point row Home gives its own island, under the same 16 points of gap**,
centred, with the row's whole width so a long category name ellipsises instead of running off the
edge. Two screens must not put the same widget at two different heights, and the collapsing block
starts flush under the title row here where Home's sits inside a padding of its own — which is the
whole of why the two did not line up.

### The flagged rows fold out of the island

There is no banner and no button. The banner was a bordered panel that opened the page and gave the
loudest block on the screen to the rarest thing on it; the button that replaced it said the same
sentence the island was already saying two rows higher.

So the island *is* the notice, and `_ReviewDrawer` is only what unfolds from it — the same split
Home has between its first-steps line and `FirstStepsCard`, down to the `StateProvider` that joins
them (`spendReviewOpenProvider`), which exists because the line is in the header and the rows are in
the body. `spendReviewBody` still says to tap the row, which is true from inside the drawer: the row
opens the detail sheet and the pencil edits it, exactly as anywhere else on the page.

### Tapping a row shows the payment; the pencil edits it

`showSpendDetailSheet` (`lib/screens/spend/spend_sheets.dart`) is what a row opens — the amount, the
shop, the day, and a card naming the category, the kind, who paid, the card the automation saw and
whether the row arrived from Apple Pay or a keyboard. It used to open the edit form directly, which
answered a question nobody asked: somebody tapping a line wants to know what that €43 at REWE was,
and met five editable fields and a keyboard.

The edit form is one tap further in, behind the accent glass button in the header's right-hand
corner — the same two steps an appointment takes (`_buildEventDetailHeader` in
`lib/screens/calendar/event_detail_sheet.dart`). **The glyph in that corner is a pencil, not a
check.** It is the corner every sheet in the app saves from, so a check would promise this one has
something to commit, and it has nothing: it is a receipt. Deleting stays inside the edit sheet with
the app's other destructive actions, which is why the detail sheet has no footer at all.

The body reads the row back out of `spendProvider` by id rather than keeping the copy it was opened
with, because the detail sheet stays mounted underneath the edit sheet; without that, a corrected
amount would come back to the old one still sitting there. `showSpendSheet` answers **true when the
spend was deleted inside it**, the one outcome the caller cannot see for itself, and the detail
sheet closes on it rather than showing a payment that no longer exists.

### Setup lives in Settings, and Ausgaben keeps one row that leads there

All of it is `ApplePayPage` (`lib/screens/settings/apple_pay_page.dart`): activating *this* phone,
the four Shortcuts steps that finish the job, the household's enrolled phones and the **Entfernen**
that takes one back. The primary action is pinned to the bottom edge as an `AccentAction`, the same
place the calendar provider pages put theirs, and it is the app's one primary pill rather than a
local coloured rectangle.

It was split in two before, and each half was the worse for it. The Ausgaben page carried a setup
card with an intro, an activate button and four numbered steps that sat under every full month of
spending and never went away, while the Settings page listed the phones and pointed *back* at
Ausgaben for the one button that mattered, which is a page telling you to go somewhere else to press
the thing it is about. Setup is setup. What stays on Ausgaben is `WalletSetupCard`, now a single
`SettingsRow` saying whether this iPhone is activated, because the wish for automatic capture
arrives while looking at money rather than while looking at Settings. It **pushes** the page with
`parentTitle` set to *Ausgaben*, so the nav bar names where the reader came from and the X in that
header leaves for the tab they were already on. The Settings row is admin-only, matching the
policies.

The enrol button said **Fertig**, which is what a form's save says, so the only control on a setup
card read as the end of the setup and the four Shortcuts steps it reveals read as something having
gone wrong afterwards. It says **Dieses iPhone aktivieren** now, which is what it does: mint a device
token into the Keychain. The automation is still the user's to create — there is no `shortcuts://`
verb that makes one — so once the phone is enrolled the page shows the four steps with **Kurzbefehle
öffnen** as its pinned action, and that button only opens the app.

### Demo data

`supabase/demo/spend_demo.sql` fills the page with six months of a plausible German household —
weekly groceries, two tanks of fuel, a couple of subscriptions, a large purchase now and then, and
two rows carrying Apple's empty-merchant defect so the review banner has something to show. Run it
with `supabase db query --linked --file supabase/demo/spend_demo.sql`.

It resolves the household and the payer itself, and it leaves `category` and `kind` null so the
`spends_classify` trigger does the classifying — which makes it a live check of what the merchant
rules actually make of those names rather than a picture of what we wish they made. Nothing runs it
automatically; it is not a migration and not `seed.sql`.

## Android

There is no equivalent and none is promised. Google's Wallet API issues passes — loyalty cards,
tickets, generic passes — and exposes no transaction read for third parties. The only automatic
route is a `NotificationListenerService` parsing the bank app's own push, which means per-bank text
parsing, German banks that each post differently and many that post nothing unless the user turns it
on, and a restricted Play Store policy area needing justification at review.

Android enters spending by hand. If notification capture is ever built it should be an opt-in
experiment per bank, not a feature the store listing claims.

## The App Intent's titles are hardcoded, and that is not a bug

Every other user-facing string in the app goes through `lib/l10n/`, and even the native tab bar has
its labels pushed over a method channel. An App Intent cannot: the system reads its title out of the
app bundle to list it in Shortcuts and Spotlight, long before a Flutter engine exists to ask.

Localising them properly means adding a `Localizable.xcstrings` to the Runner target in Xcode, at
which point the `LocalizedStringResource`s in `SpendAppIntent.swift` pick it up with no code change.
Until then they are German.
