# Ausgaben — spend tracking

Two ways a payment gets in, one table behind them, and one page that adds it up.

## The Apple Pay route, and what it can and cannot be

An iOS **Personal Automation** with the **Wallet** (formerly Transaction) trigger runs an **App Intent** that Aporah
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

Setup is now: Shortcuts → Automation → **+** → **Wallet** → pick cards → Run Immediately →
**Ausgabe erfassen** → fill **Händler** and **Betrag** with the trigger's variables.

The trigger is called **Wallet** ("Wenn ich eine Wallet-Karte oder einen Pass verwende") in current
iOS; "Transaction" is its old name, and the setup steps once sent people looking for it. **The
last step is the one that fails silently**: both fields are required, so left unlinked Shortcuts
stops to ask for them after the payment, on a phone nobody is looking at, and `spend-ingest` never
hears a thing — no row, and no failed request in the logs either.

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

### The Brazilian, Spanish and Portuguese high street

`20260913090000_classify_merchant_iberia_brazil.sql` adds Pão de Açúcar, Assaí, Drogasil, Ipiranga,
iFood, Magalu, Mercadona, Continente, Galp, Correios and the rest of three countries' everyday
names. This is not cosmetic: **the ring chart *is* Ausgaben**, so a classifier that knows only REWE
and dm hands a São Paulo or Madrid household one grey circle — a feature that technically works and
tells them nothing.

- **Still one list, not a list per country.** Adding a market means adding names to
  `classify_merchant`, never a second function beside it. The whole reason these rules are in SQL is
  that two copies drift.
- **No country column, deliberately.** A German family on holiday buys petrol at a Galp and a
  Portuguese household orders from Amazon. Matching every chain regardless of where the household
  says it lives is simpler and more often right than asking.
- **`~*` folds case, not accents.** `cafe` does not match `café`; write `caf[eé]`, or `farm.cia` to
  cover `farmácia` and `farmacia` at once. This is the single easiest mistake to make here.
- **The short tokens are the dangerous ones.** `\ydia\y` (DIA, Spain) and `\yextra\y` (Extra,
  Brazil) are the two riskiest patterns — both are chains too big to omit and ordinary words in
  their own language. `cp` (Comboios de Portugal), `nos` (a Portuguese telecom), `gol` and `azul`
  (Brazilian airlines) were all considered and **left out**: "nos" is a Portuguese pronoun and "gol"
  is a goal, and filing every notification containing them under Entertainment or Transport is worse
  than missing a bill. When in doubt, leave it out — `other` is honest, and the category is a
  starting guess the user can change.
- **Pix never reaches this function.** Brazil's everyday payment rail is not a card tap and posts no
  wallet notification, so a large share of a Brazilian household's spending arrives through manual
  entry or not at all. That is a limit of the capture mechanism, not of these rules — and one more
  reason manual entry is half the feature rather than a fallback.

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

### Tap a bar, hold a line: reading a figure off a chart

`ChartScrub` wraps the line and the bar chart: the bucket that is picked is reported up to the card,
which puts **that** figure in the headline with the date under it. The line answers "how much by
here" (it is cumulative) and the bars answer "how much here", which is the same difference the two
drawings already are.

- **A bar is tapped and a line is held, because a bar is a thing and a line is a stretch.** Bars
  stand apart with air between them, so one of them is a target the finger can hit, and asking for a
  press and a wait to hit it is a toll on the obvious gesture. A line has no targets on it at all —
  every point of it is as good as the one beside it — so the only way to read a day off it is to put
  a finger down and slide until the callout says the day you wanted. The bars take the hold as well
  as the tap; the line takes only the hold.
- **Press and hold, not touch and drag, and that is not a compromise.** The charts live in a pager —
  a horizontal drag on one of them is the gesture that turns to the next chart — so a scrubber that
  took plain drags would have left the pager unusable. A long press is what iOS's own charts take
  for the same reason, and it is the only gesture here that cannot be started by accident while
  scrolling the page. A tap cannot be either, which is what lets the bars have both.
- **The reading goes in the headline, not in a bubble at the finger.** A tooltip covers exactly the
  stretch of chart the reader is dragging along, and the headline is already the place this card
  says what a number is worth.
- **A held reading lets go on release; a tapped one stays until it is tapped away.** A reading left
  behind after the finger has gone is a headline that has quietly stopped being about the page — but
  a tap is a choice rather than a finger passing through, so the chosen bar keeps the headline until
  the reader taps it again or picks another. The card clears it when the pager turns and when the
  range or the metric changes: a reading belongs to the drawing it was taken off.
- **`ChartScrub` holds no copy of which bucket is picked.** The card's `_scrub` is the only one, and
  a second one inside the gesture would go stale the moment the card cleared it. The sticky variant
  also drops the long-press *release* handlers rather than making them conditional, because
  `onLongPressCancel` fires on the way to an ordinary tap and would clear the very reading that tap
  is about to toggle.
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
- **"Alle anzeigen" opens the explore page, not a longer card** (`SpendExplorePage`, below). A card
  grown to forty rows buries the payments under it; somebody who wants the whole list is reading
  rather than glancing, and reading deserves the screen. The link is drawn only where there is
  something behind it. The page watches the same range and metric as the card it was opened from,
  so a figure on it is the same figure that was on the card — and it is the one place the categories
  are **unfolded**, with "Sonstige" spelled out into the things it was hiding. **A row of the card
  opens that page filtered to it**; "Sonstige" is no one thing and has no tap.
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
- **The payments list under it does the same thing, at ten**, and its link opens the same explore page. It has no
  picture to agree with, so five would be short: what somebody scrolling to the bottom of Ausgaben
  is doing is scanning recent payments for one they half-remember, and ten is about a week of a
  normal household. A year selected in the slicer puts several hundred rows in that card otherwise,
  and everything under it — the wallet card included — becomes something you scroll past on the way
  to the tab bar. **The count moved into the link** rather than sitting beside it: a heading on a
  phone holds a title and one other thing, so it reads "Alle 214 anzeigen" and goes back to being a
  plain count once the list fits.

### The explore page: search filters the rows before they are folded

`SpendExplorePage` (`lib/screens/spend/spend_explore.dart`) answers "how much do we spend at REWE".
It is the chart card from Ausgaben (`SpendAnalysisCard`, which takes a `SpendSummary` rather than the
whole state for exactly this), a pill of **Alle · Personen · Geschäfte · Kategorien**, and the list —
with the phone's own search field pinned at the foot, the way Settings has it.

- **The filter runs on the rows, then `summariseRange` folds what is left.** So the headline, the
  line, the bars, the ring and the list all describe the same subset, and the comparison line is
  last month's REWE rather than last month's everything. Typing "rewe" with the slicer on 1 J. is
  the historical overview; there is no second chart for it.
- Search matches the shop, the category name, the note, the card and the payer's name, folded with
  `foldTerm` from Listen's search — case, umlauts and accents optional.
- **Tapping a breakdown row drills in**: the shop, the person or the category becomes a chip and the
  page goes back to the payments. A chip's X takes it off. Filters combine.
- **The chips sit in the header, under the title**, and **categories are a set**: the glass button
  in the header's right-hand corner is always there and opens every category, ticked on and off
  with the menu staying open (Kalender's filter mechanism, `keepsOpen` + `onKeptOpen`). The goal
  card and the chart's goal line appear only while exactly one category is picked — two goals added
  together would be a promise nobody made.
- With no chip the header's block is **one point tall, not empty**: an empty block gets
  `bareTitleHeadroom` (44) under the title, which on this nav-bar-sized title is just a gap above
  the panel.
- Reached from the header's search button (keyboard up), from "Alle anzeigen", from a breakdown row
  and from a goal's ring. It replaced `SpendPurchasesPage` and `SpendBreakdownPage`.
- The range and the metric are the page's shared ones, so changing the slicer here changes Ausgaben
  behind it. That is deliberate: two pages with two ideas of "this month" disagree on every figure.

### Goals: one ring per category, measured against the month's pace

`public.spend_budgets` holds a monthly limit per category — one per household per category, admin
only like `spends`, integer cents. **How much of it is used is not stored**: `spendBudgetProgress`
(`lib/models/spend_budget.dart`) folds this month's rows on the device.

- **The rings sit above the chart card** (`SpendBudgetStrip`, `spend_budgets.dart`), scrolling
  sideways, with a "+" at the end. The arc is the share used in the category's own donut colour.
  **There is no tick for where today is in the month** — it was tried, and at 62 points a mark across
  the band read as a glitch in the ring. The pace lives in the percentage under the ring instead,
  which turns the danger colour once the goal is running more than a tenth ahead of the month, and
  the arc turns danger once it is blown. The goal card's bar has no marker either, and is drawn as the donut is — a
  rounded filled piece and a rounded remainder with daylight between them (`SegmentedProgressBar`,
  shared with the Board's day bar). 500 € of 800 € is fine on the 25th and a warning on the 10th, and a bare
  62 % says the same thing on both days.
- **Always this calendar month, whatever the slicer is on.** When the loaded window does not reach
  over the month (a week, a picked stretch in the past) the notifier fetches the month on its own
  into `SpendState.monthSpends` rather than widening the window, and every local insert, edit and
  delete touches both lists.
- A tap opens the explore page filtered to the category, with a goal card on top and the goal drawn
  as a dashed danger line — across the cumulative line on a month, across the bars when every bar is
  a month, and nowhere else, because a month's promise against a week's total means nothing. A long
  press, or the card, opens `showBudgetSheet`.
- **Monthly only.** A period column would be a second axis every ring has to ask about.
- **A goal does notify, and it notifies on pace rather than on a percentage.** The obvious version
  of this was "80 % erreicht", and it is the wrong trigger for exactly the reason the ring does not
  draw a bare percentage: **every household that spends evenly crosses 80 % near the end of every
  month, in every category.** That is a guaranteed monthly buzz per goal carrying no information,
  which is how the switch gets turned off before the month it would have mattered. So the early
  notice is `SpendBudgetStatus.ahead` — the state whose own comment already read *"the one state
  worth a nudge while there is still time to act"* — and the late one is the limit being passed.
  `SpendBudgetProgress.noticeLevel` is the whole rule and it sits beside `status` rather than in the
  scheduler, because the two are the same judgement at two costs: a ring's false positive is a
  colour nobody sees again, a notification's is a phone. It is harder to satisfy than `status` by
  two floors — a quarter of the month gone and half the goal spent — because on the 2nd
  `monthElapsed` is .03 and a single weekly shop already clears the tenth of slack.
  **It names no hour**, unlike every other notice in the app: a goal has no deadline to count back
  from, so there is nothing for an hour to be *before* — it goes out when the derivation finds the
  crossing. See the Ausgaben section of [notifications.md](notifications.md) for that, the
  coalescing and the once-per-month memory.
- A failed goals read is silent, like the device list: the page's numbers are correct without them.

### One mark, and a shop is drawn as itself

Every row on the page wears the same white circle (`SpendMark`), and what is inside it is the only
thing that changes. **White rather than grey because most of them carry a logo**: shop marks are
full-colour artwork drawn for paper, and a grey circle behind one reads as a sticker on the wrong
background. It is the same brand tile Listen and the calendar providers already use, with the
hairline that is the only reason a white circle is visible on a white card, and what is set on it is
`brandTileInk` rather than `ink` — the tile is white in both palettes, so its contents have to be
dark in both.

- **A business gets its logo** where `assets/merchants/` has one — the same two hundred marks Listen
  already searches, matched by `merchantLogoAsset`, which consults the shop folder and nothing else.
  A payment at "Apotheke am Markt" wants the Shop-Apotheke logo or no logo; it never wants the
  generic pill-bottle symbol, because a row that cannot be matched to a brand is not a row about a
  category.
- **Where there is no logo it gets the shop's first two letters**, black on the same white. One
  shopfront glyph repeated down a column of eight different shops names none of them; two letters
  name every one. Letters *and digits*, because "Q1" and "o2" are shops.
- **Everything else is the category's own glyph**, duotone, so the black line sits on its grey fill
  — which is what the tone-coloured tiles were flattening.
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
  the change was. It is scaled down rather than ellipsised, because this figure is the answer the
  whole card is for. **It rolls for the slicer and is simply set for the chart** (`_Figure`):
  changing the range or the metric asks the same question of a longer stretch, so the figure is one
  quantity moving, which is what a rolling column says. Picking a bar asks about one day instead —
  1.234 € and 87 € are two readings rather than one number that changed, and every way of animating
  between them says otherwise. Rolling invents a relationship they do not have, a cross-fade leaves
  both legible at once and neither for long, a slide puts motion under a finger that is already
  moving; all three were tried on the page and all three read as fuss. A reading now changes the
  instant the bar is tapped, which is what a readout does. There is no switcher, and that is the
  mechanism: on the total the headline is one `RollingNumber` that stays put across slicer taps, so
  its columns roll, while a reading replaces it with plain text — and the one built afresh on the
  way back sets itself rather than rolling, there being nothing for it to have come from.
- **The slicer's thumb travels.** See the `SegmentedControl` notes in
  [design-system.md](design-system.md): the four segments are an ordered scale, and a capsule that
  vanishes from under one word and reappears under another says nothing about which way the choice
  went.

**And all three of those need the analysis card to survive the tap, which is why it is keyed.** The
page's body is a plain list of children, and the review drawer above the card comes and goes with
the range — a wider stretch can turn up a payment to review where the narrower one had none. An
unkeyed child that changes position in such a list is matched against whatever used to sit at its
index, so the card was thrown away and rebuilt: the thumb snapped across instead of sliding, and the
pager went back to the first chart. `const ValueKey('analysis')` on `_AnalysisBlock` (and one on the
drawer) is the whole fix, and it is load-bearing rather than tidiness.

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

**Rung 4 is drawn with `trendUp`/`trendDown`, and a caret there was a bug report.** The rise and
the fall started out under `caretUp`/`caretDown`, which is a direction everywhere else in the app
and a *disclosure* mark here: rung 2 directly above it really does fold rows out of the island, so
readers tapped "80 % weniger ausgegeben" waiting for a list that was never coming. A chart line
with an arrowhead can only mean which way the money went, and it is a duotone glyph like the other
four rungs rather than a bare mark borrowed from a control. The euro delta inside the card keeps
its caret: it sits beside the figure it qualifies, with nothing there that expands.

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

**The form has one save, and it is the check in its header.** It carried two: the header's check and
a full-width *Fertig* at the foot of the body, which made the same promise twice and put one of them
below a delete action at the end of a scroll. The header is `SheetActionHeader` rather than
`showAppSheet`'s built-in one because that one pops on the check, and this form has to refuse a save
it cannot make — an empty amount leaves the sheet standing with everything else still typed into it,
rather than throwing the form away over a missing comma. The check greys out until there is a
merchant, the way every create sheet's does, and becomes a spinner while the write is in flight so
the same payment cannot be filed twice.

Because the header and the body are built side by side, the controllers and the picked values live
on a `_SpendDraft` the two share — the arrangement the calendar's `_EventForm` uses — and it is
disposed a beat after the sheet pops, because the body is still reading it while the route animates
out.

**And the save says so.** A hand-entered payment used to commit in silence: the sheet closed, and
whether the row had reached the server or died on the way was something you found out by going
looking for it. Now the write answers — `addSpend` already did, and `editSpend` was changed to —
and the sheet puts up the usual chip, *Ausgabe gespeichert* or *aktualisiert* on the way through and
`spendSaveFailed` when it didn't land. Apple Pay's own rows need none of this: nobody is watching
when they arrive.

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

## Android reads the wallet's own notification

**There is no payment trigger on Android and there is no transaction API.** Google's Wallet API
issues passes — loyalty cards, tickets, generic passes — and exposes no transaction read for third
parties; Samsung's is the same shape. What Android does have is the notification the wallet posts to
the user the instant a tap goes through, carrying the shop, the amount and the card. A
`NotificationListenerService` reads that one notification and files it. It is the same payment
arriving by a worse road, and everything below is about how much worse.

The pieces mirror iOS one for one, which is the point — there is no second backend, no second
classifier and no second table:

| | iOS | Android |
|---|---|---|
| What wakes up | Personal Automation → App Intent | `SpendNotificationListener` |
| Where the token lives | Keychain, `AfterFirstUnlockThisDeviceOnly` | AES-GCM in the AndroidKeystore over an app-private file |
| What posts | `SpendIngest` in Swift | `HttpURLConnection` in Kotlin |
| What it posts to | `spend-ingest` | `spend-ingest` |
| Who names the category | `private.classify_merchant` | `private.classify_merchant` |

### The allowlist is the privacy promise, and it is four packages

Notification access is **all-or-nothing**. Android offers no way to subscribe to one app, so the
grant hands this process every notification on the phone — messages, one-time codes, everything.
That cost is real and it is not hidden behind a policy link: `_DisclosureCard` on the capture page
states it before the ask, which is also what Google Play's prominent-disclosure rule requires.

What makes it defensible is that the cost is paid and not used. `onNotificationPosted` returns on
its first line for any package outside `WalletNotifications.sourcePackages`, before it reads a single
extra. Nothing else is parsed, logged, buffered or counted.

**Google Play services is deliberately not on that list.** It is where the tap-to-pay "Purchases"
notification used to come from, so allowing it would catch a few old phones. It is also not a
payments app — it notifies about device scanning, account warnings and nearby sharing — so it would
mean running a parser over most of what Google sends a phone to find the one thing that is a
payment. Google Wallet has posted its own purchase notifications since 2024. Missing a payment on an
old phone is the cheaper mistake, and manual entry is right there. **Adding a package to that set is
not a small change**; it widens what this process reads, which is the one thing the setup page
promises it does not do.

### The parse is a guess, and the code is written as one

Apple hands the App Intent typed fields. Android hands us a sentence a product team wrote for a
human, in the phone's language, which changes without notice when the wallet app updates. So
`WalletNotifications.kt` matches no known layout. It looks for **an amount with a currency on it**
anywhere in the notification and treats everything else as material for naming the shop. Two rules
fall out of that and both matter more than any regex in the file:

- **No amount, no row.** A wallet posts plenty that is not a payment — a pass added, a card verified
  — and a notification we cannot price is one of those far more often than it is a payment we
  mis-read. A refund, a decline or a reversal is refused by name for the same reason: filing one as
  a spend puts a number in the month that nobody spent.
- **A merchant we had to guess is flagged, never dropped.** The listener sends `needs_review: true`,
  the row lands in the fold-out drawer at the top of the page, and the household fixes it in two
  seconds. This is the same trade the ingest function already makes for Apple's empty-merchant
  defect, and it is why that drawer was worth building before Android existed.

**"Had to guess" is defined by which of the three naming attempts answered, not by whether one
answered at all**, and getting that wrong is the difference between a feature people pay for and a
category ring quietly filling with junk. The shop is read from an "at"/"bei" phrase, else from a
title that is not the wallet naming itself, else from **whatever survives stripping the price, the
card and the wallet's own vocabulary off the priced line** — and that last one is a sentence
fragment far more often than it is a shop, so it is flagged by construction. Flagging only the total
miss let a payment be filed to a merchant called "Zahlung erfolgreich" with full confidence, land in
`other` from the classifier, and never surface for anyone to correct. The wallet's own words are
therefore matched as **whole words inside the candidate** rather than against the whole string,
which is what let a phrase through where a single word was caught; a candidate that is *entirely*
those words plus grammar names nothing and is dropped, and one that merely contains some of them is
kept and flagged.

**The refusal words are matched in more languages than the app speaks, on purpose.** The
notification is written in the phone's language, not Aporah's, and the amount parser already reads
two dozen currencies — so a Turkish or Polish refund notice prices itself perfectly and would be
filed as a purchase for want of one word. They are bounded on letters rather than tested as
substrings, because at four characters "iade" otherwise turns up inside somebody's shop name.

`spend-ingest` honours `needs_review: true` from the body and ignores `false`. A caller may **add**
doubt and never remove it, so nothing on the wire can talk the function out of its own checks.

### What it cannot see, and what is not being built

Device wallet payments only, exactly as on iOS: a physical card, a browser checkout, a transfer, a
direct debit and cash are all invisible. Manual entry is half the feature on both platforms.

**Open banking is the route that would fix that, and it is not being built.** A PSD2 account feed
catches everything the wallet cannot, and it would improve iOS too, but it needs a contract and KYB
under a licensed AISP, banks rate-limit to a handful of calls per account per day, and consent needs
re-authorising every 90 days. That is Plus-tier economics for a household feature. It was considered
and declined on cost.

### Two switches, and the page says which one is missing

Setup is our token *and* the OS grant, and they fail differently. A phone that holds a token but has
no access is set up and deaf; one with access and no token hears a payment it may not file. So
`SpendState` carries `notificationAccess` beside `thisDeviceEnrolled` rather than folding them into
one boolean, the capture page's step list shows a check against each, and the "activated but deaf"
state is the only warning on the page.

The grant is the one piece of state the app cannot watch change — it is given and taken on a system
screen — so the page observes the app lifecycle and re-reads it on resume. Without that it would go
on offering a grant already given, or promising a capture already switched off.

### The release manifest needed `INTERNET`

Unrelated to capture and found while building it: Flutter's template declares
`android.permission.INTERNET` in `src/debug` only, because the tool needs it for hot reload. A
release build assembled from the main manifest had **no network permission at all**, which would
have failed every Supabase call on a user's phone with nothing on screen to explain it. It is now
declared in the manifest that ships.

### Not `EncryptedSharedPreferences`

All of `androidx.security:security-crypto` was deprecated in April 2025 with no replacement release.
Its two known failure modes are a strict-mode violation on the main thread and an unrecoverable
keyset corruption, and the second is worse here than anywhere else: a corrupted keyset would
silently stop a household's payments arriving with nothing on screen to say so. `SpendCredential.kt`
is the same construction without the library — one AES-GCM key that never leaves the AndroidKeystore,
wrapping values in an ordinary app-private file. App-private storage is credential-encrypted, so it
becomes readable once the phone has been unlocked since boot, which is the same promise
`kSecAttrAccessibleAfterFirstUnlock` makes on iOS.

## The App Intent's titles are hardcoded, and that is not a bug

Every other user-facing string in the app goes through `lib/l10n/`, and even the native tab bar has
its labels pushed over a method channel. An App Intent cannot: the system reads its title out of the
app bundle to list it in Shortcuts and Spotlight, long before a Flutter engine exists to ask.

Localising them properly means adding a `Localizable.xcstrings` to the Runner target in Xcode, at
which point the `LocalizedStringResource`s in `SpendAppIntent.swift` pick it up with no code change.
Until then they are German.
