# Vorhaben — a goal in, a finished list out

**Status: proposed, nothing built. Written 2026-09-13.** This is the analysis and the plan, with the
open decisions marked as such. Nothing below has been agreed except where it says so.

A parent types *"Butter Chicken für vier"* or *"Hochbeet aus Holz bauen"*, and gets back the method
and — the part that matters — **the list of things to buy**, with the app's own pictures on it, one
tap from being a real Liste they walk into the supermarket with.

The thing being replaced is a real habit: ask ChatGPT, read the answer, copy the ingredients out by
hand into a note, lose half of them. The value is not the recipe. Every parent can already get a
recipe. The value is that **the answer arrives as an object this app can already carry** — a Liste
with icons, quantities, ticking, sharing and the family's other phone.

---

## What this contradicts, and why it is being reopened

Three earlier decisions say some version of "no". None of them was wrong; all three were about a
different shape of the same idea.

- **CLAUDE.md: "Explicitly out of scope: the KAI AI assistant."** That is about an *assistant* — a
  persona living in the app that you talk to. This is a **transform**: text in, one typed object
  out, no conversation, no memory, no persona, no second turn. If it ever grows a reply box it has
  become KAI and should be deleted.
- **Recipes were once cut for licensing** — recipe text is protected in Germany, and every parent
  already has Chefkoch. That cut was about *shipping a recipe catalog*: content we would have to
  license, host and maintain, competing with Chefkoch. Generated text is not licensed content and
  there is no catalog; the only version worth building writes the ingredients to a Liste, which is
  exactly this feature.
- **Amazon affiliate links are a good idea and a separate one.** See the Amazon section — they are
  unbundled from this deliberately.

---

## The one decision everything follows from

**It is not a chat, and the answer is not markdown.**

Both halves matter and they are the same decision. A chat invites a second turn; every second turn
is another paid request, and the app has no idea when the conversation is finished. A markdown blob
means the model decides the layout, which means the answer looks like a chatbot's answer sitting
inside an app whose whole design argument is that it uses the platform's real materials.

So: **one request, one typed answer, rendered with the app's own widgets.** The model fills in a
schema. `IconTile`, `SectionCard` and the real type scale draw it. What comes back looks like a list
somebody made by hand, which is the whole of why it reads as clean.

That also settles the cost question before it is asked: **there is exactly one paid call per
Vorhaben, and no user gesture can produce a second one except asking again, which says so.**

---

## Free or Plus — the analysis

### Why this is unlike everything else in the table

Every current `Feature` gates something whose cost is either **zero** (trackers, boxes, members —
rows in a database nobody notices) or **cumulative** (photos: Storage and egress, which is why it is
off on free rather than capped, since every free photograph is a bill that never ends).

This is the first feature with a **bounded, per-use, third-party marginal cost.** One generation
costs a few cents, once, and then costs nothing forever. That is a different shape from both, and it
points at a different answer from both.

### The numbers

One Vorhaben, measured as a request shape rather than guessed: ~1,000 input tokens (the rules and
the schema, which are the same every time, plus a goal of at most 300 characters) and ~1,100 output
tokens for eight steps and sixteen articles as JSON — ~1,800 on a model that thinks, which is most
of the difference between the rows below.

| Model | $/MTok in / out | Per Vorhaben | 3 free/month | 30 Plus/month |
|---|---|---|---|---|
| `claude-opus-5` (effort low) | 5 / 25 | ~€0.046 | €0.14 | €1.38 |
| `claude-sonnet-5` | 2 / 10 | ~€0.018 | €0.06 | €0.55 |
| **`claude-haiku-4-5`** | 1 / 5 | **~€0.006** | **€0.02** | **€0.18** |

Plus is €4.99/month, ~€4.24 net after the 15% store cut. **On Opus at a 30/month cap the absolute
worst case is a third of a Plus household's net revenue on one feature**, and the realistic average
is far lower — a household that cooks from it twice a week spends about €0.37/month. That is
affordable. It is *not* affordable uncapped, and it is not affordable on free without a cap: ten
thousand free households each burning three costs €1,380/month against zero revenue.

**Prompt caching does not save this.** The stable prefix is ~1,000 tokens, below the minimum
cacheable prefix on most models, and with a five-minute TTL and low early traffic the hit rate would
be near zero anyway. Revisit it if volume ever makes the system prompt worth growing.

### DeepSeek was priced and turned down — decided 2026-09-13

Not on cost. Same request shape, and off-peak is the realistic row: DeepSeek's peak window is
01:00–04:00 and 06:00–10:00 UTC on weekdays, which in German time is 03:00–06:00 and 08:00–12:00, so
a parent planning dinner is always off-peak.

| Model | Per Vorhaben (peak / off-peak) | 30,000 runs/month, off-peak |
|---|---|---|
| `deepseek-v4-pro` | ~€0.005 / ~€0.003 | €78 |
| `deepseek-flash` | ~€0.0015 / ~€0.0007 | €21 |

So `deepseek-v4-pro` is **Haiku's price**, and only `deepseek-flash` is meaningfully cheaper —
about €160/month against Haiku's €180 at thirty thousand runs, which is ten thousand free households
each using their whole allowance. At any realistic early volume the gap is thirty to fifty euros.

**And the transfer is unlawful as things stand.** The Berlin data protection commissioner found
Hangzhou DeepSeek in breach of **Art. 46(1) GDPR** — China has no adequacy decision and the company
produced no adequate safeguards — and when it did not comply, reported the apps to Apple and Google
for removal from the German stores under Art. 16 DSA (6 May and 27 June 2025). The finding is
specifically about text entries and uploaded files landing on servers in China.

That is exactly this feature's data flow, and the free-text field will contain a child's name in the
second example anybody types. **Thirty euros a month does not buy that**, and for a German family
app it is not a risk to weigh but a thing that ends the app.

**The objection is to DeepSeek's API, not to the models.** They are open-weight, so an EU-hosted
deployment sidesteps the transfer question entirely — at the cost of picking a host, an AVV with
them, and owning uptime for something that is otherwise one API key. Not worth it at this scale.
Revisit only if this line ever reaches five figures.

Worth knowing this is the second time: the old web app used DeepSeek as its merchant-classifier
fallback and [docs/spend.md](spend.md) records the rebuild dropping it. Different reason — SQL beat
it — same answer.

### "Recipes only, off a free API, at zero cost" — asked and answered 2026-09-13

The cheapest version of this feature is no AI at all: narrow it to cooking and read a free recipe
API. It was researched properly and it fails three times over, and the first failure is the one that
matters.

**Narrowing to recipes deletes the reason to build it.** The second example anybody gives is *"was
brauche ich im Bauhaus, um eine Mauer zu bauen"*, and no recipe API knows. Neither does it know
*Kindergeburtstag für acht Kinder*, *Campingwochenende* or *Wocheneinkauf für fünf Tage* — which are
the goals a **family organiser** is uniquely placed to answer and a recipe site is not. The
generality is the feature. A recipe-only version is a worse Chefkoch living inside a to-do app,
which is exactly why recipes were cut the first time round. If it only does recipes, do not build
it.

**The free recipe APIs do not fit this app even for cooking.**

- **TheMealDB** — English only, the free tier is browse-limited to 100 items, and their own docs say
  a **public app-store release requires the paid supporter upgrade**. Not free for us specifically,
  and no GDPR or SLA posture at all.
- **Spoonacular / Edamam** — freemium with daily caps, and commercial use requires **showing their
  logo and a link back**. That is not zero cost; it is somebody else's cost curve plus an
  advertisement on the Listen screen.
- **The language failure is the subtle one.** Ingredients come back in English. `suggestIcon` would
  still find the right pictures, because the matcher indexes English on purpose — so the list would
  *look* right while the stored article text in a German household's Liste reads "double cream".
  That breaks the app's most load-bearing rule quietly rather than loudly, and the only fix that
  scales is an LLM, which is the thing we were avoiding.
- **Chefkoch is the only German source at scale and it is out.** No API, scrapers exist, and German
  copyright protects the method text.

**And the free LLM tiers are the DeepSeek problem wearing a different hat.** Free tiers are funded by
the prompts: Google AI Studio's free tier uses content to improve Google's products, and Mistral's
free *Experiment* tier requires opting **into** training to use it. There is no AVV on a free tier,
so personal data cannot lawfully go through one regardless of training. Worse operationally, **the
rate limit is per API key and we would ship one key for every household** — ten families cooking at
18:00 on a Sunday exhaust it, and the feature dies exactly when it is used. No SLA, withdrawable at
a third party's convenience.

**The number being optimised is already about zero.** Three Vorhaben on Haiku is **€0.02 per free
household per month**. Reaching €180/month needs ten thousand free households each burning their
whole allowance, which is a business rather than a cost problem. Literal zero costs the feature's
generality and saves twenty to forty euros in the first year.

### Mistral is the open lead, and the reason is not the money

French company, EU infrastructure. Mistral Large 3 is **$0.50/M in, $1.50/M out** (corroborated by
mistral.ai's own page and a second source); Mistral Small 4 is listed at **$0.15/$0.60**, which is
single-sourced and should be treated as indicative until checked.

### Modelled at the household counts that matter

Assumptions, all debatable and all one cell to change: **5% Plus conversion**; 40% of free
households ever use the feature, at ~2 runs/month; 70% of Plus, at ~6; allowances 3 free and 30
Plus; ~1,000 in / 1,100 out tokens; USD→EUR 0.92; Plus nets €4.24.

| Model | $/MTok in / out | Per Vorhaben |
|---|---|---|
| Ministral 3 8B | 0.15 / 0.15 | €0.0003 |
| **Mistral Small 4** | 0.15 / 0.60 | **€0.0007** |
| Mistral Large 3 | 0.50 / 1.50 | €0.0020 |
| `claude-haiku-4-5` | 1.00 / 5.00 | €0.0060 |

**Realistic monthly bill:**

| Households | Plus | Runs/mo | Small 4 | Large 3 | Haiku 4.5 | Plus revenue (net) |
|---|---|---|---|---|---|---|
| 30 | 1–2 | 29 | €0.02 | €0.06 | €0.17 | €6 |
| 50 | 2–3 | 49 | €0.04 | €0.10 | €0.29 | €11 |
| 150 | 7–8 | 146 | €0.11 | €0.29 | €0.87 | €32 |
| 500 | 25 | 485 | €0.36 | €0.96 | €2.90 | €106 |
| 1,000 | 50 | 970 | €0.73 | €1.92 | €5.80 | €212 |
| 10,000 | 500 | 9,700 | €7.28 | €19.21 | €58.01 | €2,120 |

**Every household maxing its allowance:**

| Households | Runs/mo | Small 4 | Large 3 | Haiku 4.5 |
|---|---|---|---|---|
| 30 | 131 | €0.10 | €0.26 | €0.78 |
| 50 | 218 | €0.16 | €0.43 | €1.30 |
| 150 | 653 | €0.49 | €1.29 | €3.90 |
| 500 | 2,175 | €1.63 | €4.31 | €13.01 |
| 1,000 | 4,350 | €3.26 | €8.61 | €26.01 |
| 10,000 | 43,500 | €32.63 | €86.13 | €260.13 |

**There is no scale cliff, and cost was over-weighted in the section above.** Both cost and revenue
are linear in households, so the ratio is fixed at every row: **0.35% of net revenue on Small 4,
0.9% on Large 3, 2.7% on Haiku**, and 12% in the worst case that never happens. At a thousand
households the gap between cheapest and dearest is **five euros a month** — less than one Plus
subscription, and almost certainly less than Supabase at the same scale. **Do not pick the model on
price.**

Two things the table does not cover. **The caps still matter** even though the totals are small:
they are what stops one scripted client turning a linear cost into an unbounded one, and that risk
does not scale with household count. And **5% conversion is a guess** — at 0% the ten-thousand row
is €58/month against no revenue on Haiku and €7 on Small 4, which is the only place model choice
bites at all.

**So Mistral's argument is EU hosting, not the money.** A French processor deletes the
third-country transfer entirely — no SCCs, no transfer impact assessment, no US-processor paragraph
in the Datenschutzerklärung, for a field a parent types a child's name into. That is worth more than
every number above. **Still unverified**: Small 4's price, the DPA, the training policy on paid, and
quality on a German shopping list. Test it on the same twenty real goals as Haiku before the
function is written; `claude-haiku-4-5` stands until something displaces it.

### The recommendation

**Capped on free, capped on Plus, enforced on the server.**

- **Free: 3 per household per month.** Not off. This is the single most demonstrable thing in the
  app — *type "Butter Chicken", get a shopping list with pictures on it* is the screenshot that
  sells Aporah — and a feature nobody ever sees converts nobody. Three is enough to watch it work
  twice and still have one left for the week you actually want it. Five doubles the worst-case free
  bill and proves nothing extra.
- **Plus: 30 per household per month.** This would be **the first non-null number in the Plus
  column**, and that is a deliberate break in the table's shape rather than an oversight: every
  other Plus value is `null` because unlimited costs us nothing. Thirty is a Vorhaben every day for
  a month, which no household will reach, and it is the ceiling that stops one scripted client from
  spending a hundred euros of somebody else's money.
- **Plus a daily abuse limit in the function**, separate from the plan cap and for a different
  reason. `create-share-link` already carries exactly this pair — a per-user daily rate limit
  because people abuse things, and a plan cap because plans are plans. Copy it.
- **A failed generation does not count.** The row is written after the model answers, the same rule
  the connect routes follow: *"verbunden" always means "we reached it just now"*.

Both numbers live in `Entitlements._limits`, one line each, which is the entire reason that file
exists. `allowsAnother(Feature.listPlanner, usedThisMonth)` is the question, and it is the question
that shape already answers.

### What free households see when they run out

Not a disabled button. `paywallTitle`/`paywallBody` get a `Feature.listPlanner` case — which means
the gate cannot ship without somebody writing the sentence that explains it — and the ask
step carries the remaining count as an ordinary line (*"Noch 2 diesen Monat"*), so running out is
never a surprise. The gate goes on the **send button**, not on opening the screen: a parent should be
able to read what the feature is before being told they have used it up.

---

## The experience

**A card that unfolds under the island that offered it** —
[lib/screens/list/planner_card.dart](../lib/screens/list/planner_card.dart), the first thing in
Listen's body, with the household's own lists still on screen underneath it the whole time.

**Three answers were tried, and the first two were both a departure** — that is what was wrong with
them: you ask Listen a question and Listen goes away.

- **Not a sheet.** A half-height card with a scroll of its own, and what lands in it is a title, a
  dozen articles and up to twelve steps — a page of reading, through a letterbox. A sheet is also
  where this app puts a *form*: something you fill in and confirm with the check in its header.
  There is no check here, ever, because the action is not "save this" but "make the list".
- **Not a pushed page.** It fixed the letterbox and kept the departure. It also had to answer
  "where does the nav bar go" (a route covers it) and "where does the button go" (pinned to the
  bottom edge, `PinnedActionLayout`) — two real problems that existed only because the answer had
  been moved somewhere else. Nothing to come back from beats a good way back: the list you make is
  already underneath the card that made it.

**It is a `SectionCard`, not a container that resembles one.** It sits fourteen points above the
household's own lists, which are one, and the hand-rolled copy this started as differed from it in
every way a copy does — a 22 radius against their 20, its own idea of the lift. Two cards of the
same width that close together wearing two different shadows is exactly the kind of thing you see
and cannot name. Being the same widget is the only way that stays true as the token moves.

It has four faces and they are one card, so the goal you typed stays above the answer it produced.
The card grows **twice** — open it is a field, a suggestion row and a send button; when the answer
lands it grows again into the whole plan. One `AnimatedSize` around a `switch` on the phase, so the
surface is never rebuilt, only taller. `AnimatedCrossFade` opens and closes it, per the
expand/collapse rule in [docs/design-system.md](design-system.md).

**The suggestions are `AppFilterChip`, Kalender's own chip, and they sit *outside* the card, under
it, on the panel's own grey.** They were inside first and it read wrong: on the same white as the
field and under the same rim, they looked like tags on the draft rather than four ways to start one.
Out there they are offers *about* the card, and the card goes back to being one field and one
button. They leave the moment the question is sent — a suggestion is only a suggestion while the
field is still empty enough to take one. **`ChipTone.outlined`** — white, ink label, hairline rim. Neither filter tone
fits a row where nothing is being filtered: grey on the card's own white is four disabled-looking
buttons, accent is four chips claiming a selection nobody made. **Each carries its own glyph**, and
it comes off the example rather than a list of four icons zipped by index — the examples are
deliberately not translations of one another, so a language that picks a different fourth example
would otherwise get an icon about something else. `PlannerExample` in `app_strings.dart` is the pair,
and it is `const`, so `--tree-shake-icons` still sees the glyphs named. Extracting the chip out of
`calendar_screen.dart` was the point — a second chip that resembles
the first is how two rows on adjacent tabs end up with different radii.

**Four chips out of twenty-four, and they turn over daily — but the row is stratified, not
shuffled.** `plannerExampleGroups` holds the examples in four buckets — Anlässe und Reisen, Einkauf
und Haushalt, Bauen und Garten, Kochen — and `plannerSuggestions` in
[lib/data/planner_examples.dart](../lib/data/planner_examples.dart) takes exactly one from each, in
that order, indexed by the date. **Uniform random out of one flat pool is the version to avoid**, and
the reason is the row's own job: it is the only place the feature says what it can do, so a day that
happened to deal four dinners would teach a first-time household that Vorhaben is a recipe generator
and lose the Hochbeet for good. One draw per bucket makes that hand impossible while still turning
over. The group order is the chip order for the same reason it was fixed when the examples were:
the row scrolls, so the two read without a swipe are the broad household errands, and the narrow
ones — a build, then one dish — follow.

It is a **rotation on the date, not a random number**, so every example in a group comes up before
any of them comes up twice, the row cannot repeat yesterday's chip, and it cannot hide one for a
month. Being a pure function of the day is also what lets `PlannerCard` call it straight in `build`:
the chips cannot reshuffle under somebody who is mid-sentence, which is what shuffling inline would
do on every keystroke. Nothing about the row belongs in `PlannerState`. With four groups of six the
same four arrive together every sixth day; unequal group lengths are the lever if that ever matters.
Weighting the draw by season — Weihnachtsessen in December, Grillabend in June — is the obvious next
move and is deliberately not built yet.

**Both buttons are real glass, and which one is showing says what the card is for.** Asking, it is a
`GlassConfirmButton` with an up arrow — the compose-field idiom, and deliberately not
`paperPlaneTilt`, which in this app means sending something *to somebody* (it is onboarding's invite
button). With an answer on screen it is `GlassAccentButton`, the blue pill every primary action in
the app wears, and it appears only then, because until the answer lands there is no list to make.

**1. Ask.** One multi-line field, four tappable examples that seed it (*"Kindergeburtstag für 8
Kinder"*, *"Wocheneinkauf für 5 Tage"*, *"Hochbeet aus Holz bauen"*, *"Butter Chicken für 4"* — one
per bucket, and a different four tomorrow), the remaining count, and one send button. The examples are doing real work: this is a blank field with no
affordance, and the difference between a parent typing something useful and turning back is
knowing what shape of thing to type.

**2. Working.** The field is replaced by one line showing what was asked. A skeleton where the answer
will be, and a progress line that names the stage.

**Not streamed, in v1.** Streaming a *structured* answer means parsing partial JSON on the client to
render anything at all, which is a lot of machinery to buy a progress bar; a fifteen-second wait for
something you asked for once and get once is acceptable. `output_config: {effort: "low"}` cuts most
of that wait anyway. If it tests badly, the function can hand back SSE and the card can fill the
list rows in as they arrive — that is a later change to two files, not a different architecture.

**3. Answer.** Two blocks, the list first because the list is the point:

- **Die Liste** — the articles, drawn with the real `IconTile` and the icon `suggestIcon` picks, with
  quantity and unit, each one **tickable off before the list is made**, so the parent drops the salt
  and the olive oil they already have rather than carrying them into a Liste and deleting them there.
- **So geht's** — the steps, numbered, in the app's own type. Below the list, expanded.

One primary button, **Liste erstellen**, which calls `createListWithItems`, folds the card away and
confirms with a chip — the landing any newly created list gets. **Jumping straight into the new
list is still open**, and it is not free: `createListWithItems` mints the id inside itself and
returns a bool, so the caller has nothing to open, and awaiting the insert before jumping would put
a visible pause on the one action the parent is watching. Worth doing — they are about to leave for
the shop — but it is a change to `ListNotifier`'s signature, not to this card. One secondary,
**Nochmal**, under it, puts the text back in the field for editing and says plainly that it costs
another Vorhaben.

**No save, no history, no favourites.** The answer lives in the notifier and nowhere else; killing
the app loses it. The artifact is the Liste, and the Liste is stored. Anything more turns a stamp
into a second product with its own table.

### Where the way in goes

**One place: the status island under Listen's title** —
[lib/screens/list/list_island.dart](../lib/screens/list/list_island.dart), the slot Home fills with
its day and Ausgaben with its money. A glyph, *"Sag, was du vorhast."* as the line,
*"Wir machen die Liste daraus"* under it (`plannerIslandLine` / `plannerIslandHint` — the island
ellipsises rather than wrapping, so the card's longer promise was cut to fit), and the **disclosure
caret** (`IslandLine.expanded`), because the tap goes nowhere: `PlannerCard` unfolds directly under
it. `plannerAvailable` decides whether it is there at all; in a build with no key Listen has no
collapsing block, which is honest — an invitation to something that can only fail is worse than no
invitation.

**It was two places, and both were wrong in the same way.** A lightbulb shared the `+`'s glass
capsule on the title row, and a card at the top of the body carried the copy until the household had
run one:

- The capsule was the right layer and the wrong tenant. It now holds the **magnifier and the `+`**:
  search moved up out of the collapsing header (see the search entry in
  [docs/design-system.md](design-system.md)), and a third glass segment on a five-tab app's title row
  is a toolbar. The icon also said nothing — a bulb on its own is a hint that something is available,
  which is exactly what the card underneath then had to explain.
- The card said it properly and charged the lists for it: a heading, a paragraph and a glyph tile
  standing above the household's own lists. It was meant to leave once a Vorhaben had been run, off
  the usage counter — but `public.list_plan_runs` does not exist yet, so *until then* it always
  showed, which is the permanent advertisement this was supposed to avoid.

The island is both at once and costs nothing: the app's own sentence, in the place where the app
already speaks on two other tabs, in a block that was going spare the moment search left it. And
because the line is a sentence rather than a glyph, there is nothing left for a card to explain.
There is **no dismissal to derive** any more — one line under a title is not an advertisement, so
`list_plan_runs` is back to being only the quota counter it was always going to be.

**The glyph is a bulb rather than a sparkle.** The sparkle already means two other things in this
app — the mark the icon picker puts beside a name that chose its own icon, and Ausgaben's "Extra" —
and a third meaning for it here would be the generic "AI happens" badge rather than a glyph about
this feature. A bulb is what the thing actually asks for: you arrive with an idea and it comes back
as a list.

---

## How the icons come out right

**They already do, and this is the part that needs no work.** `_fillList` in
[lib/state/list_state.dart](../lib/state/list_state.dart) runs every article's own name through
`suggestIcon(text, subject: …)`, which is the same function a hand-typed article goes through — so a
generated Lebensmittel list gets photographs from `assets/grocery/` (544 of them) and a Bauhaus list
gets symbols, with no new code and no icon field in the response.

Three things make this work better than it sounds:

- **`kind` comes back in the response**, so the model decides Lebensmittel or Sonstige, which
  decides `IconSubject.groceryArticle` vs `IconSubject.article`, which decides whether the photo
  catalog gets first look.
- **The matcher already speaks all four languages with the umlauts optional**
  ([lib/data/grocery_search.dart](../lib/data/grocery_search.dart)) and already strips quantities
  off a line. A Spanish household's *pechuga de pollo* lands on the same chicken picture as
  *Hähnchenbrust*. Nothing has to be sent to the model to make that true.
- **Do not ship the catalog in the prompt.** Sending 544 article names would multiply the input cost
  and buy a worse result than the matcher we already have. What the prompt gets instead is one style
  rule: *name each article the way a supermarket labels it, one head noun, no brands*. That is what
  makes `Hähnchenbrustfilet` come back rather than *"boneless skinless chicken breast, about 600g"*.

### Shop quantities, not recipe measures

The items are **what to buy** (*1 Packung Butter*, *500 g Hähnchenbrust*); the recipe measures
(*2 EL Butter*) stay inline in the steps where they belong. That is the correct product answer — you
buy a pack of butter — and it happens to sidestep the fact that `GroceryUnit` has ten keys and none
of them is Esslöffel. **Do not add EL/TL/Prise to `GroceryUnit` for this.** They are not units of
shopping.

**One small change is needed:** `_fillList` takes `({String text, String? sub})` and never passes a
unit, and `ListRepository.addItem` has no `unit` parameter. Both need one, or every generated row
lands as a bare count with the unit welded into the text.

---

## What the server does

One new Edge Function, `list-plan`, and one new table. Nothing else in `supabase/` moves.

**The function.** Ordinary `verify_jwt = true` — there is a real session behind every call, so no
entry in `config.toml`. It resolves the caller with `callerId`, reads their household from their
membership row (**never from the request body**), checks the daily rate limit and then the plan cap
through a new `canRunListPlan` in [_shared/entitlements.ts](../supabase/functions/_shared/entitlements.ts),
calls the model, validates the answer against the schema, writes the usage row and returns the typed
object.

**This one has to be enforced server-side, and unlike the others there is no argument about it.** A
household that hacks its way to a fourth Box costs us nothing. A household that hacks its way past
this spends our money on every request. The Dart check is for the UI; the function's check is the
gate.

**The table**, `public.list_plan_runs`: `id`, `family_id`, `created_by`, `created_at`, and the token
counts for cost telemetry. **`authenticated` holds no INSERT grant** — only the function writes it,
which is the same lock every other counted resource uses and the reason the count cannot be forged.
SELECT is open to the household so the screen can print "noch 2 diesen Monat" without a second route.

**The prompt and the answer are not stored. Neither one, ever.** A household's dinner plans and
their building projects are not ours to keep, the Liste is the artifact and it is already stored,
and a table of everything every family has ever asked for is a thing that can leak. This is the same
call the app makes about `list_items.link_url` (*nothing ever fetches it*) and about events (*we do
not store anybody's calendar*).

**The key** is `ANTHROPIC_API_KEY`, a function secret, exactly as `RESEND_API_KEY` and
`GOOGLE_CLIENT_SECRET` are. It is never in the app.

**Model and request shape — `claude-haiku-4-5`, decided 2026-09-13.** A strict schema via
`output_config.format`, so what comes back is a typed object rather than text somebody has to parse
and a malformed answer is a 400 from the API rather than a broken screen.

Haiku is the right size for this and not a compromise: the input is one sentence, the output is a
fixed shape, there is no long context to hold and no tool loop to run. **The hard part of this
feature is `suggestIcon`, not the model** — the matcher decides whether the list looks like Aporah,
and it is ours.

Two things follow from the model, both easy to get wrong:

- **No thinking.** Haiku 4.5 takes the older `budget_tokens` shape rather than adaptive thinking and
  rejects `output_config.effort` outright, so thinking is simply not enabled. That is most of why it
  is cheaper than the per-token price suggests — ~1,100 output tokens instead of ~1,800.
- **Confirm structured outputs against the Models API before building on them.** They are documented
  as a general API feature rather than a model tier, but the whole design rests on the typed answer,
  so check rather than assume.

If it disappoints on the messier goals — *"Kindergeburtstag für 8 Kinder"* rather than a named dish
— the step up is `claude-sonnet-5` at ~3×, and it is one string.

```
{
  title:  string,                    // "Butter Chicken für 4"
  kind:   "grocery" | "other",       // picks ListKind, which picks the icon subject
  steps:  string[],                  // 0..12; empty is legitimate for a hardware run
  items:  [{ name, quantity?, unit?, note? }]   // unit ∈ the ten GroceryUnit keys
}
```

`unit` is an enum of the exact `GroceryUnit.key` strings, so the model cannot invent a value into a
column that holds ten. Anything it cannot express goes into `quantity`, which is free text and
always was.

**The answer comes back in the interface language.** Four languages now, not two — the request
carries the language code, and the schema's contents are free text, so it follows the instruction.
The chrome around it goes through `AppStrings` like everything else and will not compile in one
language and not the others.

---

## Legal, and it is not a footnote

**This sends user-typed text to a US company, and that is a different thing from every other
request the app makes.** Weather sends a coordinate and an hour to a German host. This sends
whatever a parent typed.

- **Never call the provider from the client.** The Open-Meteo exception does not extend here: a
  direct call would put the household's IP in front of the provider *and* the API key in the build.
  The Edge Function is the boundary and there is no version of this without it.
- **An AVV/DPA with the provider, and a named third-country transfer in the
  Datenschutzerklärung** — the SCCs, the retention period, and the fact that API inputs are not
  used for training. Check whether inference can be pinned to the EU (`inference_geo`); if it can,
  do it, and say so in the same paragraph.
- **Children's names will end up in that field.** *"Kindergeburtstag für Lena, 6"* is the second
  example anybody types. Two mitigations, both cheap: the prompt copy asks for a goal and not for
  people, and **we store neither the question nor the answer**, so the exposure is one request in
  flight rather than a table.
- This is a third item for the legal list in [production-plan.md](production-plan.md), and unlike
  the two already there it does not have months of lead time — an AVV and a paragraph.

---

## Amazon, and why it ships separately

The mechanism already exists and it is one column: `list_items.link_url`, one `http(s)` URL, opened
by the device, **never fetched by us**. But it should not be used the way it first looks.

**Do not ask the model for URLs.** It will produce plausible ASINs that 404, and a dead link on
every row is worse than no link.

**Do not write a link into `link_url` on generated rows either.** That column means *the shop page
this particular article points at*, set deliberately from the item menu. Filling it on fourteen rows
puts a link chip on every one of them and writes our affiliate tag into the household's own data.

**Do add one row to the item menu, for every article, generated or typed:** *"Bei Amazon suchen"*,
which builds `https://www.amazon.de/s?k=<article>&tag=<partner-tag>` and hands it to
`external_links.dart`. Deterministic, never dead, no API, no scraping, nothing stored, nothing
fetched, and it works on articles that have nothing to do with this feature. The menu is a `UIMenu`
on iOS and takes SF Symbols, so the row gets `magnifyingglass` — Amazon's own mark is an SVG and
cannot come.

**Be honest about the revenue.** Grocery and household categories pay 1–3% on a 24-hour cookie from
a *search* link, which converts far worse than a product link. At family-app scale this is a
rounding error, not a line in the model. It is worth doing because it is one menu row, not because
it pays for anything.

**And it needs paperwork this feature does not:** a PartnerNet account, **Werbekennzeichnung** on
the row (German law, not optional), the *"Als Amazon-Partner verdiene ich an qualifizierten
Verkäufen"* disclosure, and another line in the Datenschutzerklärung.
**So ship the Vorhaben without it and add Amazon as its own small change once PartnerNet exists** — they are independent, and coupling
them puts the good feature behind the paperwork.

---

## The build, in order

1. `Feature.listPlanner` in [lib/models/entitlements.dart](../lib/models/entitlements.dart), both
   numbers, and the two paywall sentences — which will not compile until they are written.
2. The migration: `public.list_plan_runs`, no client INSERT grant, household SELECT.
3. `supabase/functions/list-plan/` + `canRunListPlan` in `_shared/entitlements.ts`. **Neither `deno`
   nor the Supabase CLI is on this machine** — the same blocker Phase 0's server limits are sitting
   behind — so this type-checks somewhere else before it is deployed.
4. `unit` through `ListRepository.addItem` and `_fillList`. Smallest change here, and everything
   downstream is wrong without it.
5. `plannerProvider` + `PlannerState` in [lib/state/](../lib/state/), one notifier and one immutable
   state class like every other one, holding the goal, the phase, the answer and the per-item ticks.
6. `PlannerCard`, and the island that unfolds it.
7. The introduction card on Listen.
8. Strings in all four of `StringsDe`/`StringsEn`/`StringsEs`/`StringsPt`.
9. Rewrite the KAI line in CLAUDE.md and add the legal item to
   [production-plan.md](production-plan.md). A cut that has been reversed and left standing is a doc
   nobody trusts.

**Separately, once PartnerNet exists:** the Amazon menu row and its Werbekennzeichnung.

---

## Open decisions

1. **3 free / 30 Plus**, or different numbers. Both are one line in `_limits`.
2. **Monthly or weekly on free.** Three a month can be gone in week one and read as broken; one a
   week is smoother but *"noch 0 diese Woche"* is a worse sentence than *"noch 1 diesen Monat"*.
3. **The name.** "Vorhaben" is the working title and it is a bit formal for a card headline.
4. **Mistral, properly priced.** Cheaper than Haiku on the one figure available and EU-hosted, which
   would delete the whole third-country paragraph. Verify against real pricing and the DPA, then
   test on the same twenty goals. Until then Haiku stands.

~~**The model.**~~ Settled 2026-09-13: `claude-haiku-4-5`, with DeepSeek priced and refused. Both
sections above carry the reasoning; Sonnet 5 is the step up if quality disappoints.

---

## Verifying

House rules, unchanged: `flutter analyze` clean; `lib/screens/` and `lib/widgets/` are both touched,
so `dart tool/check_const_palette.dart` must also say `OK`; every icon drawn with `AppIcon`, `flat:
true` for anything that is a control; no `flutter test` and no new tests unless asked. The user tests
it in the running UI, which is the source of truth.
