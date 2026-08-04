# Design system gotchas

Tokens live in `lib/theme/tokens.dart` (colors, spacing, radii, shadows, text styles) — always
use these instead of hardcoding a hex/size. Shared widgets are in `lib/widgets/`; check there
before writing a new one-off widget. The non-obvious rules are below.

## Dark mode

Driven by the app's **own** "Dunkelmodus" switch in Settings (`settingsProvider.darkMode`,
persisted to `shared_preferences`), *not* by the device appearance — the family shares one look
regardless of each phone's system setting. `AporahApp` watches that flag, installs the matching
`AppPalette` and picks the `ThemeMode`.

`AppColors.x` / `AppText.x` / `AppTones` / `AppShadows` are **getters over a mutable global**
(`AppColors.palette`), not constants. That keeps ~280 call sites untouched, at the cost of the
one rule below. The idiomatic alternative — a `ThemeExtension` read through `Theme.of(context)` —
needs a `BuildContext` everywhere, including in plain helper functions and static text styles
that have none.

- **Never `const`-construct a widget whose `build` reads a token**, directly or through a child.
  A `const` widget is canonicalised, so its element is *skipped* when an ancestor rebuilds, and it
  would keep painting the palette that was installed when it was first built. This is why several
  call sites look like they're missing a `const` (`CardDivider()`, `SectionCard(...)`, the screen
  list in `main.dart`). Constructors stay `const` — `prefer_const_constructors_in_immutables`
  wants them to be, and only the *caller* has to opt out.
  - **`const` is inherited by everything nested inside it**, so the keyword doesn't have to be on
    the offending widget — `const Positioned.fill(child: FrostedHeaderBackground())` const-builds
    the header background too, and that one shipped a frozen light frost wash over the dark app.
    Watch for a token-reading widget nested inside a `const` *framework* widget.
  - **The compiler cannot catch this** — it's a silent visual bug. Passing a token as an
    *argument* is self-enforcing (`const Foo(color: AppColors.ink)` won't compile, the getter
    isn't constant); it's tokens read *inside* `build` that slip through. `dart tool/check_const_palette.dart`
    walks the transitive "reads a token" closure and fails on any `const` *expression* that
    constructs one (the whole balanced expression, not just the head constructor) — run it after
    adding widgets.
- **Never store a resolved `Color` in a model or in const seed data.** It freezes at whatever the
  palette was. Store the *identity* and derive the colour: `CalendarEvent.src` is an
  `EventSource` with a `color` getter, `FamilyMember.tone` / `StorageBox.tone` /
  `CalendarEvent.ownerTone` are indices into `AppTones.list`. `MonthData.events` holds
  `EventSource`s for the same reason — `dayColors()` maps them to colours per call, so don't
  cache what it returns across a theme change.
- **`Colors.white` is still correct for foreground on a filled accent** — a button label, the
  selected day number, a check mark, a swipe action's icon. Those stay white in both palettes. A
  white *surface* is what has to become `AppColors.surface`. `AppColors.brandTile` is deliberately
  white in both: it backs third-party logos drawn for a light background.
- **Every iOS platform view** (`UITabBar`, `UISearchBar`/`UISearchTextField`, `UISwitch`, and the
  `UIGlassEffect` behind `NativeGlassView`) takes a `dark` creation arg *and* a `setBrightness`
  channel call. Both halves are needed: the theme is an in-app setting, so there's no device
  appearance change for UIKit to observe, and a `UiKitView` is never re-created from changed
  `creationParams` — only the channel push reaches a view that already exists. Dart pushes it from
  `didUpdateWidget`, which means the widget must actually rebuild on a flip (see the `const` rule
  above). **A new platform view needs the same treatment or it will follow the *phone* instead of
  the app.** The glass one is the easiest to miss and the most visible when missed: the whole
  frosted header stays light over a dark app.
- **`tint(c, amt)` aims at the lightest surface, not at the background.** It makes the pale wash
  behind a *selected* thing (filter chip, live timeline row, Feiertag swatch), so it has to land at
  or above whatever it sits on. On light that's white; on dark it's `surfaceAlt`. Aiming at
  `screenBg` — the obvious-looking "toward the background" reading — drags tinted elements *below*
  `surfaceAlt` and inverts the selected state. `shade(c, amt)` is unaffected: it's the same hue at
  an alpha, so it composites over whatever is behind it in either palette.
- Adding a colour means adding a field to `AppPalette` and a value to **both** `light` and `dark`,
  then a getter on `AppColors`. The dark values are derived, not from the handoff (which is
  light-only) — see the `AppPalette` doc for the two rules they follow.

## Typography (`AppText`, `tokens.dart`)

**Poppins is bundled in `pubspec.yaml`, not fetched.** It used to come from `google_fonts`, which
registers each weight under a *variant-suffixed* family (`Poppins_regular`, `Poppins_600`) and
never plain `Poppins` — so every `AppText` token and every hand-written style, all of which asked
for `'Poppins'`, silently fell back to the platform font while unstyled text rendered in real
Poppins. The app was showing two typefaces at once, which is what made Settings look like it had a
different weight from the content screens. Don't reintroduce `google_fonts`; the family name in
`AppText._family` and the `family:` key in `pubspec.yaml` have to stay the same string.

**Only w300/400/500/600/800 ship.** Asking for w700 gets a snapped or synthesised weight, not
Poppins Bold — a new weight means adding its `.ttf` to `assets/fonts/` and to `pubspec.yaml`.

**The scale is closed, and there is no hand-written `TextStyle` left in `lib/screens/` or
`lib/widgets/`.** It replaced 139 of them that had drifted to 22 sizes and 5 weights for ~17 real
roles. Half-point neighbours (13/13.5, 14/14.5, 15/15.5, 12/12.5) carried no meaning and are gone —
reach for the neighbouring token instead of adding one back.

- `.copyWith(color:)` **is** expected: a token names a role, and the same role is ink in one place
  and accent or danger in another.
- `.copyWith(fontSize:)` / `.copyWith(fontWeight:)` is how the drift started. The only sanctioned
  uses are genuinely *computed*: a collapsing header interpolating `screenTitle` down to 17 on
  every scroll frame, an avatar's initials scaling with its circle, a day number carrying
  selected/today/holiday in its weight.
- **`itemTitle` (15/w600) vs `rowTitle` (15/w500) is deliberate, not drift.** Content the family
  created — a list or box card, a task, a search hit, an event — is a step heavier than the
  settings rows that configure it. Two Board rows that changed weight the moment you checked them
  off (open w600, done w500 — the same bug in Listen) both use the row's own token now, so a task
  doesn't restyle itself on completion.
- **`body` carries `height: 1.55`, and that is the reason to use it.** Six places hand-wrote its
  14/w300 and dropped the leading, so the same paragraph was set tighter outside Settings.

## Glass (`GlassSurface` / `GlassIconButton`, `glass.dart`)

Apple "Liquid Glass": a real native `UIGlassEffect` on iOS via `native_glass_view.dart`, a
Flutter-drawn blur+tint approximation everywhere else.

- **Leave `tint` null.** It's forwarded straight to `UIGlassEffect.tintColor`, and a near-opaque
  one floods the material so it stops reading as glass at all. Use `fallbackTint` for the colour
  the non-iOS approximation should draw (keep it light so dark-on-glass labels stay legible).
  Reserve `tint` for a deliberate accent, e.g. the sheet's blue confirm button.
- **`forceFlutterApproximation: true`** for anything shown inside a scale/transform transition (a
  popup route) — platform views smear when Flutter transforms them.
- The approximation's `Stack` needs `fit: StackFit.expand`. A childless `DecoratedBox` is a
  `RenderProxyBox` and sizes to `constraints.smallest`, so under the default `StackFit.loose` the
  tint layer lays out at `Size.zero` and never paints — every non-iOS glass surface was just a
  blur with a specular highlight, see-through no matter what tint was passed. **If a glass
  surface ever looks washed out again, check this first.**
- On iOS `GlassIconButton` is a native platform view, so it composites above anything Flutter
  paints after it. Put it *last* in a `Stack` when siblings must appear over/beside it.
- **`GlassSurface` lays its child out in a top-left-aligned `Stack`.** Invisible for the icon
  buttons — their child is exactly the surface's size — but any child *smaller* than the surface
  (a row inside a fixed-height pill) pins to the top instead of centering. Wrap it in a `Center`.
- **Never lay Flutter content out *between* two glass buttons in a `Row`.** The sheet header
  shipped as `Row(x button, Expanded(title), check button)` and the title was **invisible on
  device**: content painted between two platform views lands in a composited overlay layer that
  never shows. It renders fine in a widget test — there are no platform views there — so a golden
  won't catch it. Both rows that flank a title with glass buttons (`showAppSheet`'s default header,
  `CollapsingScreenTitle`) are therefore a `Stack` with the title as a `Positioned.fill` layer
  painted *first* and the buttons `Align`ed on top.

## `FrostedHeaderBackground` (`glass.dart`)

Progressive blur + translucent white; the material behind a collapsing header so scrolled content
passes under it blurred instead of reading through. Deliberately **not** a `GlassSurface` —
liquid glass's specular highlight and edge refraction read as a floating control, wrong for an
edge-to-edge bar. Two things are load-bearing, both learned by shipping the naive version first:

- **Progressive blur, not uniform.** Five stacked top-anchored `BackdropFilter` bands of
  increasing sigma plus a tint gradient, both ramping to zero at the bottom edge — the
  variable-blur treatment Apple uses under nav bars. A uniform bar ends in a hard step (sharp
  content and a flat tone change at the same y), and the user read that edge as the header being
  "a square, another layer over it" rather than content blurring as it slid under. Fade both out
  and there's no edge left to see. Each band needs its own `ClipRect` or its `BackdropFilter`
  reaches the whole enclosing layer.
- **Keep the tint's peak alpha low (~62%).** Content is white cards on `#F7F8FA`, so the blurred
  backdrop is already nearly white; at the 82% this first shipped with, the bar was
  indistinguishable from solid white — the effect ran, it just had nothing to show. Most visible
  contrast has to come from the content itself. A saturation-boost `ColorFilter` is composed onto
  the **first band only** (composing it onto all five would compound it), same reason Apple's
  materials do it: colored chips/dots keep their color instead of graying out.

## Collapsing headers (`collapsing_header.dart`)

Board, Box and Listen all scroll the same way: `CollapsingHeaderScreen` (a `NestedScrollView` +
pinned `SliverPersistentHeader` over `CollapsingSliverHeaderDelegate`) pins a title row while the
block under it — search field, stat tiles, Board's today/progress line, a detail screen's big name
row — clips and
fades away. `CollapsingScreenTitle` morphs the heading from large-left to small-centered;
`ScreenBodyPanel` is the rounded gray panel the body scrolls on; `HeaderBrandGlow` is the colored
wash the detail screens put behind theirs.

**Kalender keeps its own copy of this plumbing on purpose** — its header carries a freely-scrolling
day strip whose geometry the week view owns, plus a collapsed-only filter dropdown. Don't merge
them, but a change to how the collapse *feels* belongs in both.

Non-obvious bits, each one a bug that shipped first:

- **The `extra` block measures itself at runtime; never hardcode its height.** It's laid out
  unbounded in an `OverflowBox` and read back through a `GlobalKey` after the frame, with
  `estimatedExtraHeight` only covering frame one (the sliver must publish its extents before
  anything under it is laid out). Poppins comes from `google_fonts` at *runtime*, so a widget test
  measures a fallback font at ~1.0em line height against the device's ~1.4em — a constant tuned in
  a test clips the bottom row on a real phone.
- **`OverflowBox` + `ClipRect`, not a shrinking box.** The block keeps its natural height while its
  visible box shrinks, so rows slide up under the title and get clipped. Constrain it instead and
  the content re-flows on every scroll frame, then overflows.
- **The title is a full-width `Positioned.fill` layer, not an `Expanded` Row sibling.** As a Row
  child, "centered" means centered in whatever the flanking buttons left over — visibly off by half
  a button. The side insets must also be **symmetric wherever the title is centered** — collapsed
  always, and at rest too when `expandedAlignment` is `Alignment.center` (Settings, the detail
  screens), which is why `leadingWidth`/`trailingWidth` are collapsed to their max there instead of
  being applied per side: reserving 48 on one side and 84 on the other centers the title in what's
  left over, off by half the difference. Where a control folds away as it collapses (Board's avatar
  stack), pass `collapsedSideInset` so the title isn't reserving room for something that's gone.
- **`backdrop` paints *over* the frost, not under it.** The frost is ~62% white; a glow behind it
  washes out to nothing. It's anchored to the top at its natural height and clipped to the header,
  so the gradient keeps its screen geometry instead of sliding around as the bar shrinks.
- **The header absorbs the status-bar inset itself** (`MediaQuery.paddingOf(context).top`). Screens
  that still want a `SafeArea` above it read 0 and are unaffected; the Box/Listen *detail* screens
  drop theirs so the glow owns the top edge instead of starting below a white band.

## Other shared widgets

- Bottom navigation — **two bars, one per platform**, both fed from the same `navTabs` list and
  both floating over the content (see `useNativeTabBar` in `bottom_nav.dart`).
  - **iOS: `NativeTabBar` (`native_tab_bar.dart`)** — a real `UITabBar` embedded as a platform
    view (`ios/Runner/TabBarPlatformView.swift`, view type `aporah/tab_bar`). On iOS 26 that *is*
    Apple's floating Liquid Glass tab bar: capsule, sliding selection pill, press shimmer, SF
    Symbol animation, all UIKit's. Flutter's own `CupertinoTabBar` is **not** an option here — it
    still draws the pre-iOS-26 bar and the Flutter team has said Liquid Glass won't land in
    Cupertino ([flutter#170310](https://github.com/flutter/flutter/issues/170310)).
    - Tabs are SF Symbol *names* on `NavTab`, not `IconData`. Taps come back over a per-view
      method channel; Flutter still owns the index and pushes it down via `setSelectedIndex`.
    - The bar sizes *itself* — Dart asks for `getIntrinsicSize` once and lays the platform view out
      to match, centered; never hardcode its width. UIKit may report the full width (it then draws
      the iOS 26 glass platter inset inside those bounds) or a narrower capsule; both are handled.
      The measurement is deliberately taken against the width the view already has, since
      `sizeThatFits` will hand back an unbounded width if you ask it to fit one.
    - It needs an `EagerGestureRecognizer`, or touch-down reaches UIKit too late for the press
      shimmer. Note this is the opposite of `GlassPlatformView`, which takes no touches at all.
    - Not available without a `UITabBarController`: the iOS 26 *minimize-on-scroll* behaviour.
  - **Everywhere else: `AppBottomNav` (`bottom_nav.dart`)** — the floating glass pill from the
    handoff.
  - Scrolling screens must pad their last row clear of whichever bar is up: use
    `navContentInset(context)`, with the `pill:` argument for the non-iOS clearance. Same helper
    for anything `Positioned` off the bottom edge (e.g. the calendar's "Heute" button) — but pass
    a larger `gap:` for those: scrolling content may sit close and slide under the glass, while a
    control *parked* above the bar needs air or the two glass surfaces touch and it reads as
    hiding behind the bar.
- `showAppSheet` / `SectionCard` / `CardDivider` (`app_sheet.dart`) — shared bottom-sheet chrome
  (grab handle, X/title/check header or a custom `header`, scrolling body). **Every** modal sheet
  should go through this rather than a bespoke `showModalBottomSheet`.
- `showConnectConfirmSheet` (`connect_confirm_sheet.dart`) — the last step of **every** "add a
  calendar" flow, and the only place a connect is actually performed: what you picked, the name
  it will carry, X on the left and the accent check on the right. `onConfirm(name)` runs while
  the sheet stays open (the X goes away — the request wouldn't be cancelled by closing), then a
  short success beat (accent check + an expanding ring, ~1.1s) before it pops `true`. It also
  serves the rename action on a connected row. `extraFields` adds card rows **above** the name
  field for the one question a provider still has to ask — Abfall's Abfuhrbezirk chips, or the
  ICS link for a town no vendor serves; the caller owns their controllers and reads them inside
  `onConfirm` (anything that redraws on tap goes in a `StatefulBuilder`, since this screen's
  `setState` only rebuilds the page behind the sheet). Throwing a
  `CalendarConnectionException` from `onConfirm` keeps the sheet open with the message under the
  fields, which is how the ICS link is rejected. The one check that stays *outside*: a CalDAV
  password, which is typed on the page and verified before the sheet opens at all
  (`calendar_connect_screen.dart`).
- `SettingsRow`'s built-in icon tile is a **circle**, not a squircle (`settings_chrome.dart`) —
  the rows that carry a logo (calendar providers) or a face (family members) can only be round,
  and a settings list mixing both shapes reads as two lists.
- `HeaderSearchBar` / `SearchTriggerField` / `HeaderSearchButton` (`search.dart`) — Listen's and
  Boxen's search, which happens **in place, never in a sheet**. Both entry points only flip a bool
  on the screen: the flat pill in the resting header (`SearchTriggerField`) and the glass magnifier
  that replaces it once the header has collapsed (`HeaderSearchButton`, fading in on the same late
  curve as the collapsed title — pass `leadingWidth: 0` so it doesn't shift the expanded heading).
  `HeaderSearchBar` wraps the screen's whole title row: while active it fades that row out and
  grows the system search field out of the magnifier's own footprint, over to a glass X that closes
  search again. The screen drops its `extra` while searching (the pill would be a second box for
  the same query) and renders hits in its own body. Search reaches *into* the detail screens —
  articles inside a list, contents of a box — so a hit is grouped under whatever holds it and
  tapping it opens that list/box.
- `NativeSearchField` (`native_search_field.dart`) — the real system search control as a platform
  view (`ios/Runner/SearchFieldPlatformView.swift`, view type `aporah/search_field`), in two
  styles. `NativeSearchFieldStyle.bar` is a whole `UISearchBar`: it reports its own height
  (`getIntrinsicSize`) and brings its own Cancel button, whose reveal on focus — field narrows, X
  animates in beside it — is `setShowsCancelButton(_:animated:)`, not anything drawn here. It
  floats at the *bottom* of the Settings screen as a live filter (iOS 26 puts search within thumb
  reach, not under the nav bar), parked above the keyboard by hand: that screen sets
  `resizeToAvoidBottomInset: false`, since resizing a `NestedScrollView` mid-scroll re-runs the
  collapsing header's measurement and makes the bar jump. `NativeSearchFieldStyle.field` is just
  the `UISearchTextField` from inside that bar, sized to the height it's given and optionally
  autofocused — what `HeaderSearchBar` puts in a 40pt title row, where a 52pt bar wouldn't fit and
  the glass X is already the way out. **UIKit's in-field clear button is switched off in both
  styles** (`clearButtonMode = .never`): each already sits next to an X — the bar's Cancel, the
  header's glass X — so the two stack up into a row of X's the moment you type. Same platform-view
  pattern as `NativeTabBar`: UIKit owns the control, Flutter only receives text over a per-view
  method channel. Needs an
  `EagerGestureRecognizer` so UIKit owns tap-to-focus, the caret and text selection — the cost is
  that a drag starting *on the field* doesn't scroll the page. Off iOS it falls back to a Flutter
  `TextField` in the flat gray search-pill shape.
- `NativeSwitch` (`native_switch.dart`) — a real `UISwitch` as a platform view
  (`ios/Runner/SwitchPlatformView.swift`, view type `aporah/switch`). **Use this instead of
  `Switch`/`Switch.adaptive` for any on/off row**: `CupertinoSwitch` redraws the *pre-iOS 26*
  switch, so it misses the Liquid Glass knob and press response the rest of the native chrome
  has. UIKit holds the on/off state, so the value goes both ways over the per-view method channel
  — `valueChanged` up, `setValue` down from `didUpdateWidget` when a provider flips it — and
  `getIntrinsicSize` gives the box (≈51×31). No `onTintColor` override: the system green is the
  native look, and on iOS 26 the on-track is a material a flat color would flatten. Needs an
  `EagerGestureRecognizer` so UIKit owns tap and drag-to-toggle; a drag starting *on the switch*
  therefore doesn't scroll the list. Off iOS it falls back to `Switch.adaptive`.
- **Never put a platform view inside a `showAppSheet` body** — use `SheetSwitch`
  (`native_switch.dart`) rather than `NativeSwitch` there. Every sheet header already embeds two
  (`GlassIconButton`'s X and `GlassConfirmButton`'s check are each a `NativeGlassView`), and a
  third one inside the scrolling body makes iOS drop the overlay layer carrying everything painted
  after it. The Kalender event form shipped that way and rendered as blank white below the
  Ganztägig toggle — the Beginn/Ende rows, the calendar picker and the notes field laid out at
  full height and painted nothing. Same failure as the sheet title vanishing between the two
  header buttons (`app_sheet.dart`), and it fails the same way: silently, on device only, with
  correct layout. The tell is a card whose height is right and whose contents aren't there.
- `showAnchoredMenu` / `RowMenuButton` (`anchored_menu.dart`) — the UIKit-style dropdown a row's
  trailing "..." opens (Listen and Boxen item rows). Deliberately **not** a `GlassSurface`: UIKit
  menus are a near-opaque vibrant material, and glass lets the content underneath read through the
  rows. Rows are a **fixed** `AnchoredMenuSurface.rowHeight`, which is what lets the route compute
  the panel's height up front and decide before layout whether it still fits below its anchor (it
  flips above it otherwise) and which corner to grow out of. The bottom bound is
  `navContentInset`, not the screen edge — on iOS the native tab bar composites over anything
  Flutter paints, so a menu reaching under it is simply cut off. `AnchoredMenuItem.onSelected`
  runs *after* the menu has closed, so an action that opens a sheet isn't animating in behind it.
  A row carries either a Lucide `icon` or an `svgAsset` (a brand mark from `assets/`, via
  `flutter_svg`) — **the SVG is tinted to the row's own colour** with a `srcIn` `ColorFilter`, not
  left full-colour: a menu row is a label, and a lone colour logo is then the one thing shouting
  on a monochrome list. Labels are bare nouns ("Foto", not "Foto hinzufügen") — every row is
  something you're doing to the item, so repeating the verb says nothing.
- `GlassMenuButton` (`anchored_menu.dart`) — [RowMenuButton]'s counterpart for a *screen header*:
  the glass "..." in a detail screen's title row (Listen and Boxen both use it for Bearbeiten /
  Löschen), opening the same anchored menu. A separate widget rather than a flag, since
  `RowMenuButton` is a bare 15px glyph sized for a list row.
- `IconTile` / `IconFieldRow` / `showIconPicker` / `IconDraft` (`icon_picker.dart`) — the one place
  a list/box/item icon is **drawn** and the one place it is **chosen**. Both sides speak the same
  `iconKey` string from `data/icon_suggestions.dart`: an `assets/` path or `lucide:<name>`.
  - `IconTile` splits on *what kind of art it is*, not on taste: a shop logo or grocery picture is
    full-colour art drawn for a light background, so it gets the white `brandTile` disc in both
    palettes; a Lucide glyph is line art in the theme's own ink, so it sits on `surfaceAlt`. Its
    `IconImage` bounds the decode with `cacheWidth` — the picker puts 160 full-size logo PNGs on
    screen at once.
  - `showIconPicker` is a `showAppSheet` with a **custom header**: X + title, no save check, since
    tapping an icon *is* the save. It browses the curated symbol groups + the shops, and searches
    across those plus the ~2000 grocery pictures (which are search-only — a browsable grid of them
    would be its own screen).
  - `IconDraft` is the mutable box a create/edit sheet's body and its save button both hold. The
    body owns the picker, but the save callback is handed to `showAppSheet` before the body exists,
    so the picked key can't live in the body's `State`. `picked == null` means "the name is still
    choosing" — which is what `IconFieldRow`'s `suggested:` flag renders.
- `SwipeActionsRow` / `SwipeAction` (`swipe_actions.dart`) — iOS swipe-left row actions, shared by
  the Kalender event cards (Edit + Delete) and the Listen/Boxen item rows (Delete). The reveal is
  a 0→1 fraction on an `AnimationController`, not a pixel offset, so the live drag and the release
  snap share one value and curve; a tap while open only closes the row. Two things to get right at
  a call site: the child **must be opaque** (it slides over the actions — wrap it in a
  `ColoredBox` where a `SectionCard` was providing the fill), and `closesRow: false` belongs on
  anything that removes the row outright. `borderRadius` is the card's for a free-standing card,
  zero inside a `SectionCard` (which clips its own corners).
- `DaySelectorCircle` (`day_circle.dart`) — day-number circle (selected/today/holiday), shared by
  Kalender's week strip and month grid. Board used to have a week strip of its own and no longer
  does: a task's date is a property of the task, so the Board is a grouped list with nothing to
  select.
- `EventDots` (`event_dots.dart`) — small overlapping source-color dots under a day cell.
- `Avatar`, `WhoPicker` — person avatar chip and the "Alle / Nur ich / <person>" picker on
  new-item sheets. `WhoPicker` is the **assignment** axis (a single `who` string) and is what
  Board/Box/Kalender still use.
- `VisibilityPicker` (`visibility_picker.dart`) — the **visibility** axis, and what a sheet backed
  by Supabase wants instead: it writes `visibility` (`family` | `private` | `custom`) plus the
  member ids that become `*_shares` rows, rather than one conflated string. Alle and Nur ich are
  mutually exclusive with each other and with the member chips; selecting members makes it
  `custom`; deselecting the last one falls back to Nur ich, because `custom` shared with nobody
  *is* private. The creator is always implicitly included and has no chip. Pass
  `allowMembers: false` for a guest — the composite FK on `*_shares` makes picking a non-member a
  constraint error, not a polite refusal. Both pickers render the same chip
  (`PickerAvatarChip`, in `who_picker.dart`).
- `ErrorNote` (`error_note.dart`) — a failed **read**: nothing on screen and no reason to expect
  the next frame to fix it, so an inline note with "Erneut laden" that stays put. Takes German copy
  written for the user — the notifier translates, never the widget.
- **The toast chip (`toast_chip.dart`) — one component for every transient outcome.** A
  liquid-glass capsule floating clear of the nav bar: coloured disc, one line, and on a delete an
  "Rückgängig". `confirmChipOf` for a write that landed, `showToast(…, kind: ToastKind.error)` for
  one that didn't — `showErrorSnack` is now a one-line delegate to the latter and keeps its ~8 call
  sites. **Success and failure differ by the disc's colour and glyph and by nothing else**; they
  used to be two unrelated objects (a hugging white pill vs. a full-width grey bar) for what is one
  event with two outcomes. Do not give a new outcome its own shape.
  - Shown for the twelve actions whose result isn't self-evident on screen — create / update /
    delete of a list, a box, a task, an appointment. Not for adding an article to an open list: the
    row appears under the finger, and a chip on every mutation is one the user stops reading.
  - `confirmChipOf` is a *capture*, not a `show…(context, …)` call, and that is the point: half the
    callers are deletions that unmount the widget they were tapped in (the row, the row menu, the
    whole detail view), so the messenger and the nav-bar inset have to be taken **before** the
    write and the returned callback invoked after. A `context.mounted` guard would drop exactly the
    confirmations that matter most.
  - A chip only appears on a `true` from the notifier, which is why the create/update calls return
    `Future<bool>` and the two container deletes return `Future<DeletedList?>` / `Future<DeletedBox?>`
    (see the undo note below). A failed write gets the error chip and no confirmation — never both.
  - **`clipBehavior: Clip.none` on the `SnackBar` is load-bearing.** It clips its child to its own
    barely-rounded shape by default, which cut the capsule's drop shadow off along four straight
    edges — the rectangular smudge the chip shipped with — and would crop the native glass view
    too. The bar itself is transparent with `elevation: 0`; it is only the carrier, so the capsule
    can hug its text instead of spanning the display.
- **Undo lives on the delete chip, and it is a re-insert.** `restoreList` / `restoreBox` /
  `restoreTask` / `restoreEvent` recreate what was deleted from the snapshot the delete handed
  back — items, done state, audience and position included. The **ids do not come back**: a
  `share_links` row handed to somebody outside the household pointed at the old one and stays dead,
  which is the honest price of an undo that isn't a soft-delete column. `restoreEvent` is the cheap
  one — `_write(EventDraft.of(event))` already routes an own event to `public.events` and a
  provider's back out through `calendar-write`.
- `CheckOffRow` / `CheckOffArrival` / `CheckOffButton` / `StrikeThrough` (`check_off.dart`) — the
  abhaken animation shared by Board and Listen; see the animation conventions below before wiring
  a fourth screen into it.

## Animation conventions

Smooth, subtle transitions — avoid instant cuts for anything state-driven the user directly
triggers. Match the existing timing language (~120–220ms, ease-out) rather than introducing a new
one.

- **Tab navigation** (`lib/main.dart`, `_AppShellState`): screens stay mounted in an
  `IndexedStack` (per-tab scroll/expansion state survives switching), wrapped in `FadeTransition`
  + `SlideTransition` on one `AnimationController` (220ms, `Curves.easeOutCubic`). Tapping a nav
  item reverses the animation, swaps `_index`, then plays forward — reads as one crossfade even
  though `IndexedStack` paints only one child.
- **Expand/collapse**: `AnimatedCrossFade`, not a conditional `if (...) Widget` in a children
  list — it keeps both states around so it can size *and* fade smoothly in both directions.
- **Content swap** (week-view agenda on day/filter change): `AnimatedSwitcher` with
  `FadeTransition` + slight upward `SlideTransition`, keyed `"$y-$m-$d-$calendarFilter"` via
  `KeyedSubtree`.
- **Timeline rail fills** (`_EventAgendaRow`): `AnimatedContainer` / `AnimatedDefaultTextStyle`
  (320ms, `Curves.easeOutCubic`) so the done/live color transitions instead of snapping.
- **Appearing floating controls** (`_JumpToTodayButton`): `AnimatedSlide` + `AnimatedOpacity`
  (220ms, `Curves.easeOutCubic`) inside `IgnorePointer` so the invisible widget can't eat taps,
  plus the `AnimatedScale` press feedback `GlassIconButton` uses.
- **Checking an item off / undoing it** (`check_off.dart`, used by Board and Listen's detail): the
  row is *not* moved the moment it's tapped — `CheckOffRow` plays the feedback first (check fills
  and pops, `StrikeThrough` draws a line across the label, text greys toward the done colour, all
  over ~240ms), holds a beat, then folds the row down and away (~200ms) and only *then* calls
  `onCompleted` to flip the notifier. `CheckOffArrival` fades and slides the row into the section
  it landed in — from above for "Erledigt", `fromBelow` for the open list — gated on the state's
  `justMoved` id so only the row that just moved animates; everything else builds at rest.
  `undo: true` runs the identical sequence backwards for a done row (line retracts, check empties,
  row folds *up*), and since a done row has no other affordance the **whole line** is its tap
  target, not just the check. Three rules: whatever sits directly in the list **must** carry a
  `ValueKey(item.id)`, or a row inherits the previous item's animation state when the list shifts;
  the divider above a row belongs *inside* the builder, so it folds away with the row instead of
  leaving a stray line; and a `StrikeThrough` under an `Expanded` needs an `Align` around it, or
  the line spans the whole row instead of stopping at the last glyph.
- **Anchored menus** (`showAnchoredMenu`, and the Kalender filter's own `_FilterMenuRoute`): a
  custom `PopupRoute` that lays the finished panel out beside its anchor and fade +
  `ScaleTransition`s it out of the nearest corner (200ms in / 140ms out). Don't use `showMenu` —
  it grows the panel's height while staggering each item's fade, which over dense content reads as
  a smeared, half-drawn slab. Scale the **panel**, inside `buildPage`, not the page in
  `buildTransitions`: that layer is screen-sized, so scaling it slides the panel across the
  display instead of growing it out of its own corner.
- **Deliberate exception**: the week view's day strip has no transition of its own — the user
  asked for standard scrolling over week-at-a-time paging. Its only motion is `_revealDate`'s
  `animateTo` (420ms, `Curves.easeOutCubic`) when something *else* moves the strip.
