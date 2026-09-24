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
    adding widgets, and keep it at `OK`. It reported nine standing offenders for a while, all of
    them false (it scanned class bodies without blanking comments and strings first, so one
    capitalised word in a UI string was enough to mark a class); a real
    `const FrostedHeaderBackground()` sat in that list unnoticed and shipped a dark header over
    the light app. A checker with a permanent baseline is a checker nobody reads.
  - **`FrostedHeaderBackground`'s constructor is deliberately not `const`**, which makes that one
    — the most-repeated and most-visible instance of this bug, since every screen has a bar — a
    compile error rather than something the eye has to catch. Worth copying for any other widget
    that reads a token in `build` *and* gets instantiated from many call sites.
- **Never store a resolved `Color` in a model or in const seed data.** It freezes at whatever the
  palette was. Store the *identity* and derive the colour: `CalendarEvent.src` is an
  `EventSource` with a `color` getter, `FamilyMember.tone` / `StorageBox.tone` /
  `CalendarEvent.ownerTone` are indices into `AppTones.list`. `MonthData.events` holds
  `EventSource`s for the same reason — `dayColors()` maps them to colours per call, so don't
  cache what it returns across a theme change.
- **`Colors.white` is still correct for foreground on a filled accent** — a button label, the
  selected day number, a check mark, a swipe action's icon. Those stay white in both palettes. A
  white *surface* is what has to become `AppColors.surface`. `AppColors.brandTile` is deliberately
  white in both: it backs third-party logos drawn for a light background, and
  `AppColors.brandTileInk` is its foreground for the same reason — a tile that does not follow the
  theme cannot have contents that do, and `ink` on dark is a pale grey that vanishes on it.
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
- **A placeholder is `mutedLight`, and `buildAppTheme` sets that once for the whole app.** Left to
  Material's `ColorScheme.onSurfaceVariant`, a `hintText` sat close enough to real ink that people
  read "Listenname" or "Was ist zu tun?" as something already typed — one user confirmed an unnamed
  list on exactly that reading. The `inputDecorationTheme.hintStyle` in `app_theme.dart` overrides
  only the colour, so each field keeps the size and weight of its own `style`; a field passing its
  own `hintStyle` still wins, which is why the two search boxes keep the slightly stronger `muted`.
- **`body` carries `height: 1.55`, and that is the reason to use it.** Six places hand-wrote its
  14/w300 and dropped the leading, so the same paragraph was set tighter outside Settings.

## Glass (`GlassSurface` / `GlassIconButton`, `glass.dart`)

Apple "Liquid Glass": a real native `UIGlassEffect` on iOS via `native_glass_view.dart`, a
Flutter-drawn blur+tint approximation everywhere else.

- **A glass *button* is a real `UIButton`, not a piece of glass with a glyph on it**
  (`native_glass_buttons.dart` + `ios/Runner/GlassButtonPlatformView.swift`). `GlassIconButton`
  and `GlassIconGroup` were built out of `GlassSurface` — the raw material, a Flutter glyph laid
  over it, a Flutter shadow under it and a Flutter gesture detector on top — which is the app
  re-implementing a control the system ships, and it showed: no press response the system would
  recognise, a drop shadow the material then refracted, and a rim that read as painted rather than
  lensed. Apple's guidance for the new design is *prefer system views and controls*, and for a
  button that is `UIButton.Configuration.glass()` (or `.prominentGlass()` for an accent). Same
  bargain the bottom bar already makes by being a real `UITabBar` and every menu makes by being a
  real `UIMenu`. The button brings its own material, press behaviour, shadow, metrics and
  accessibility.
  - **A group is one glass capsule with plain buttons on it**, which is what UIKit's own grouped
    `UIBarButtonItem`s are: image buttons *share* a background with the image buttons beside them.
    Any number of segments works; two and three are what the app uses.
    - **Not `UIGlassContainerEffect`**, which is what this was built as first. That effect is for
      glass that comes apart and back together — a toolbar that splits as it moves — and at rest
      two 50×40 capsules two points apart do not union into a 100×40 one: each keeps its own round
      ends and the pair renders as a **peanut with a pinched waist**. (Closing the waist needs an
      overlap of a full height, which then puts the tap targets somewhere other than where the
      glyphs are drawn.) The merge was working exactly as designed; it was the wrong effect for a
      control that never moves.
    - A segment is therefore `.plain()`, not `.glass()` — glass on glass is the one thing the
      material's own guidance rules out. What a segment gives up is the per-press lensing, because
      the glass belongs to the group; that is true of Apple's grouped bar buttons too.
  - **The glyphs stay Phosphor.** SF Symbols is what a `UIMenu` row has to take, but a menu row is
    a list item where a header button is the *same* glyph the rest of the screen draws — two icon
    families on one screen. So `PhosphorGlyphs` reads the font straight out of the Flutter bundle
    with CoreText and rasterises a **template** image, which UIKit then tints and gives the glass's
    own vibrancy. The font is resolved by the file's own PostScript name, never by the
    `PhosphorRegular` family name in `pubspec.yaml` (that is Flutter's name for it).
  - **Send `flatIcon(icon)`, never the `AppIcons` constant** — codepoint *and* font asset, because
    a codepoint only means something alongside the file it is a codepoint in. **The two Phosphor
    weights do not share a codepoint space**: a duotone glyph is a pair of layers, so
    `Phosphor-Duotone.ttf` maps 3025 codepoints where `Phosphor-Regular.ttf` maps 1543, at different
    positions. `_flat`'s *values* are the same number in Regular, Bold or Thin — that is what the
    note on it means, and it is about the values, not the keys. Handing an `AppIcons` constant's
    own codepoint to the flat font drew a missing-glyph box in every single button. `flatIcon()`
    and `iconFontAsset()` in `app_icons.dart` are the resolution `AppIcon` already did internally,
    exposed for the one caller that cannot let Flutter do the drawing.
  - **A labelled button keeps the app's typeface.** `GlassPillButton` ("Fertig", "Überspringen"),
    `FloatingGlassPill` ("Heute", "Rückgängig") and the `MoreShelf` buttons are native too, and
    their titles are set in **Poppins**, loaded from the Flutter bundle exactly like the icon font
    (`AppText.fontAsset` resolves a `TextStyle`'s weight to a file). A native button saying
    "Fertig" in SF Pro beside a screen set in Poppins would be the one place the app changed
    voice — a worse trade than the one the material is being adopted for.
    - The title carries its **own colour**, not the button's tint. On "Heute" the tint is the
      accent and belongs to the glyph alone; one `tintColor` for both repaints the word accent and
      the pill reads as a filled accent control rather than a neutral one carrying an accent mark.
  - **`dots:` puts a stack of colour dots beside the glyph, in the same image.** A
    `UIButton.Configuration` has exactly one image slot, so `NativeGlassDots` travels *with* the
    glyph rather than beside it (Kalender's collapsed filter, which wears the colours of the
    calendars it is showing). Two consequences. Each dot has its own colour, so that image cannot
    be a **template** — which is how a glyph normally takes the button's tint and the glass's
    vibrancy — so a button with dots also passes `glyphColor:` and gives that vibrancy up on that
    one glyph. And the overlap between two dots is **cleared** out of the image rather than filled
    with a background colour, so the glass itself shows through it; the Flutter sizer draws the
    `AvatarStack` ring in `AppColors.surface` instead, which is the one place the two drawings
    differ.
  - **A platform view has no intrinsic size, so `NativeGlassButtons.sizer` gives it one.** The
    Flutter widget the native button replaces is built at zero opacity to size the `Stack`, and the
    button fills it. One source of truth: a `TextPainter` measurement would have to be kept in step
    with the fallback path's padding and type by hand and would drift the first time either moved.
    The sizer is built *first*, so it lands in the base surface rather than an overlay above the
    platform view.
  - **`symbol:` beats `icon:` where the row is already Apple's set.** The `Mehr` shelf stands over
    a real `UITabBar` drawing real SF Symbols, and `navRowIcon` already swaps Phosphor out for
    `CupertinoIcons` there — which is a *package* asset with no path UIKit can be handed, and needs
    none, since a `UIButton` takes a symbol by name. Validate a name against the runtime's own list
    first (`CoreGlyphs.bundle/name_availability.plist`).
    - **A symbol's `pointSize` is a type size, not a box**, and it is `symbolSize`, never
      `iconSize`. `kNavRowIconSize` is 28 because that is the *em* a Phosphor glyph is drawn at,
      and an icon font puts well under an em of ink inside it; a symbol fills its own metrics, so
      the same 28 came back as a 35×35 image for `shippingbox` and 40×28 for `creditcard` and the
      shelf towered over the identical glyphs on the bar below it. The default is
      `kNavBarSymbolPointSize`, which is UIKit's own — what `TabBarPlatformView` gets by passing no
      configuration at all — so a symbol beside the bar is the bar's size by construction.
    - **Weight is the one thing that does not follow the bar**, and is `symbolWeight` for that
      reason. The bar draws its glyphs *on the bar*, where `.regular` is right; the shelf draws the
      same glyph on a 62pt glass circle floating over a screen, where `.regular` reads thin beside
      the Phosphor every other control is set in. Measured: at 17pt SF's own `.regular` draws a
      1.25–1.50pt line and `.medium` a 1.44–1.75pt one, where Phosphor Regular at `AppGlyph.button`
      draws 1.63pt — so `.medium` is the step that brackets it. One step, not two; `.semibold` at
      this size starts to look like a different icon set.
  - **Push everything an item carries, not just its word.** A `UiKitView` reads `creationParams`
    once, and *two* things on a button change under a live view: the label follows the language
    picked in Settings, and the title's **colour** follows the palette, since `AppText`'s styles
    resolve to `AppColors.ink`. Baked into the `AttributedString` at creation, "Fertig" stayed
    black in a dark app until something else tore the view down. One `setItems` push covers both
    so they cannot fall out of step — the same contract `setTint` and `setBrightness` already have,
    and the same trap `NativeGlassView._syncTint` documents at the other end.
  - Still `GlassSurface` on the fallback paths: off iOS, and on iOS for as long as a sheet covers
    the screen (`occludedByRoute`). Every glass *control* is now a real button on iOS, including
    `GlassAccentButton` — `prominent: true` with the accent as its `tint`, and the grey it wears
    while `enabled` is false passed the same way, so a disabled pill is still a filled pill.
  - **The accent pill was the last one converted, and it converted because it was dropping taps.**
    On the surface path a tappable glass control is an invisible `UIControl` hung inside an
    *interactive* `UIGlassEffect`'s `contentView`, and the material's own touch handling competes
    with that control for the gesture — the lensing is a recognizer on the effect view, and a
    recognizer that wins cancels the touches underneath it. Fast taps got through and ordinary ones
    did not, so "Verbinden" at the bottom of a calendar provider page took several tries. A glass
    `UIButton` has no such contest: the press response and the action belong to one control, which
    is the argument for system controls making itself for the third time. That leaves
    `GlassSurface.regions` with no caller on the native path at all: it stays for a *surface* that
    genuinely needs segments, but **a new tappable control belongs on `NativeGlassButtons`**, not
    on a region.
- **`GlassSurface` remains the right thing for a *surface*** — the nav bar's backing capsule, the
  floating pill, the `Mehr` shelf, a sheet's material. The rules below are about those.
- **The press belongs to UIKit where the material is real.** `UIGlassEffect.isInteractive` is the
  material's *own* response to a finger — the lensing that gathers under it — and it only runs for
  touches UIKit itself delivers into the effect view. It shipped set to `true` on every glass
  surface in the app and could never once fire: `GlassPlatformView` held
  `isUserInteractionEnabled = false` and a Flutter `GestureDetector` layered over the platform view
  took every touch, so what a press actually did was shrink the whole control 10% — which is not
  the gesture language of iOS 26 glass, and is why the buttons read as "not active". So a tappable
  surface now passes `GlassSurface.regions` (fractions of its own box, one per segment) and the
  native side hangs invisible `UIControl`s inside `effectView.contentView`; only the *tap* comes
  back over the channel. `nativeGlassActive(context)` is the one question both sides ask, so the
  surface and its caller can never disagree about who is detecting the gesture. The
  `AnimatedScale` survives on the approximation path only, which has no response of its own.
  - This needs `PlatformViewHitTestBehavior.opaque` + an `EagerGestureRecognizer`, the same
    bargain the tab bar and switch already make. The cost: a drag that *starts* on a glass button
    no longer scrolls what's behind it. That is what a nav-bar button does natively too.
  - A surface with **no** regions (the nav bar's backing capsule, the `Mehr` shelf, the floating
    pill) keeps `isUserInteractionEnabled = false` and takes no touches at all, so nothing that
    was never a button starts swallowing gestures.
  - The platform view publishes no Flutter semantics, so a native-path control wraps itself in a
    `Semantics(button: true, …)` node — `GlassIconGroup`'s segments carry `onTap` there as well.
- **Nothing may be painted *underneath* real glass, and a `boxShadow` is the easy thing to forget.**
  Flutter paints a `DecoratedBox`'s shadow into the surface *below* the platform view, which is
  exactly what `UIGlassEffect` samples — so a 35%-black blur sized to sit behind the control got
  pulled up through the material and smeared across its rim, with the rest hanging outside the
  capsule as a grey halo. That halo is what made the header capsule look painted rather than
  refracted. `GlassSurface` therefore drops `boxShadow` on the native path entirely; the material
  carries its own shadow, and the token is for the Flutter drawing, which has none. The same
  applies to `AppShadows.accentGlass` under the accent buttons.
- **Leave `tint` null.** It's forwarded straight to `UIGlassEffect.tintColor`, and a near-opaque
  one floods the material so it stops reading as glass at all. Reserve `tint` for a deliberate
  accent, e.g. the sheet's blue confirm button.
- **The approximation is not just the Android look — it is what an iOS control wears while a menu
  or a sheet covers it** (`occludedByRoute`), which happens several times a session. So the two
  have to agree, and `AppColors.glassFallbackTint` is tuned for that: a near-opaque tone of the
  *surface*, the same light material the nav pill draws. It used to be ink at 15%, on the theory
  that glass is a translucent grey — it isn't, the real material lightens what it covers, and
  every glass button in the app turned into a grey disc the moment a dropdown opened over it.
  Leave `fallbackTint` off; it exists for a control that wants a *different* material off iOS, and
  nothing currently does.
- **A `tint` also turns the approximation's sheen down.** The white lift, the specular and the rim
  are sized for a near-opaque *surface* tone, where they read as curvature. Over an opaque accent
  they read as a wash, and a washed-out fill is how a disabled control is drawn — which is the
  whole point of the accent-filled glass rule below. So an accent surface gets a 6% lift instead
  of 30% and roughly a third of the highlight, matching what `UIGlassEffect` does with an opaque
  `tintColor`. Without it every blue button in the app went pale for as long as a menu was open.
- **The approximation's rim has to carry the surface's `borderRadius`.** `Border.all` on a
  `BoxDecoration` with no radius is a rectangle, and the enclosing `ClipRRect` keeps only the four
  points where it touches the curve — bright flecks at the sides of a circle, the flat top and
  bottom of a capsule with nothing joining them. That is what made covered buttons look squared
  off at the left and right.
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

## Icons: duotone for labels, flat for controls (`app_icons.dart`)

The set is Phosphor Duotone and you draw one with `AppIcon`, never `Icon` — a duotone glyph is two
codepoints stacked with the lower one faded, so a bare `Icon` renders half of it. Two rules decide
whether the second layer is drawn at all.

**By role.** An icon that *names* a thing keeps its duotone: a settings row, a menu row, a list, a
box, an empty state, a masthead. An icon that *is* the control you press is flat: the glyph on a
glass button, a segment of a segmented control, the check-off, a swipe action, the nav pill, a
disclosure caret. A control is small and often sits on a filled or frosted ground where a
26%-opacity under-layer has nothing to read against — but the deciding reason is that a duotone
glyph is a little picture and a button is not one. The button's own material already supplies the
mass; the glyph only has to say which button it is.

That is `AppIcon.flat`, and it is set **inside the control widgets**, not by their callers, so a
button is flat wherever it is used and nobody has to remember.

**Flat means Phosphor's Regular weight**, from a second vendored font, not the duotone with its
under-layer switched off. Those are not the same drawing. The duotone `caret-right` is a hollow
*triangle*; the single-weight one is the *chevron* a disclosure row wants. `arrow-right` differs
the same way, and the duotone `check` is shrunk to fit inside its placeholder box, so used alone it
comes out visibly small. Most glyphs *are* identical across the two, but "most" is not something a
button should depend on, so `_flat` maps every glyph to its single-weight twin.

**Every Phosphor weight shares one codepoint per glyph**, so the weight is chosen in exactly one
place: the `_flatFamily` constant and the matching `pubspec.yaml` font entry. Changing those two
lines moves all 171 flat glyphs, and the `_flat` table never has to be touched.

### How big a control's glyph is, and why it was wrong

**Sizes come from `AppGlyph` (`tokens.dart`), never from a number written at the call site.** Four
tiers, each calibrated against the ink of the SF Symbol the system would draw in the same place:
`button` 26 (a glyph that *is* the control — a glass button, a swipe action, a row's "..."),
`row` 21 (a glyph beside a `rowTitle`-sized word), `inline` 17 (beside smaller type), `caret` 18
(a disclosure chevron).

Two things make this a measurement rather than a preference:

- **An em is not what lands on screen.** A Phosphor glyph carries an invisible full-em box and the
  drawing fills only 57–86% of it, so `size: 19` puts about **15pt of ink** on a button. Lucide
  filled about 88%, so the swap to Phosphor shrank every control in the app without a single number
  changing.
- **`UIBarButtonItem` applies `.large` on top of 17pt**, which is about +25%. Its symbol draws
  **21.0pt of ink with a 1.62pt stroke** — not the ~14pt the unscaled number suggests, which is what
  the old 19 was calibrated against.

This is also why the flat weight is Regular again. Bold was chosen to stop a glyph that was too
small from reading as faint — a heavier stroke compensating for a smaller drawing, two errors that
cancelled, which is exactly why it read as "small *and* the weight is off". At `AppGlyph.button`,
Phosphor Regular draws 21.4pt of ink with a 1.63pt stroke; Bold at the same size is 2.25pt, 39%
heavier than the symbol next to it.

The one glyph that needs saying out loud is `dotsThreeVertical`. Phosphor draws its dots about 30%
smaller than SF does at a matched overall length, so a row's "..." takes `button` rather than `row`
— at the row tier it is three specks. It was drawn at 15 in `mutedLight`, the smallest glyph in the
faintest grey, and that combination is what made it invisible.

Glyphs beside *micro* type sit below the scale and keep their own number; `list_screen.dart`'s 11pt
link mark is the only one.

**By glyph.** Fourteen bare marks are flat everywhere regardless — `check`, `x`, `plus`, `minus`,
`dotsThreeVertical`, four arrows and five carets — because Phosphor has no honest duotone for
them. A mark has only itself, so the set gives it either a placeholder rounded rectangle around
its bounding box (which read as a check *inside a box* on the sheet's confirm button) or a solid
copy of itself with only the outline on top (which turned every disclosure chevron into a hollow
triangle). They have no entry in `_underLayers`, and the absence *is* the mechanism — it routes
them down the same path as a control, so they come out of the flat font. Do not add one. Note this is a judgement and not a rule a script can apply: `laptop`, `monitor`, `signOut`,
`batteryCharging`, `gasPump`, `headphones`, `iceCream` and `recycle` all have rounded-rect
under-layers too, and in each of those the rectangle is a screen, a door, a battery body.

## `BinFileActions` (`bin_file_actions.dart`) — the one layout for a waste calendar that is a file

Every town whose bins come in as a file shows exactly this, wherever it is asked: the Kalender
sheet's Abfall step, the upload sheet, and the onboarding's address step. Numbered steps, the blue
"Abfallkalender der Stadt öffnen", and one upload button under it. **One upload button for every
kind of file** — a PDF plan joins it as a new label, never as a third button — and a town the app
reads live never shows it at all. Don't draw a second version of it with settings rows.

## `GlyphTile` (`glyph_tile.dart`) — the square a settings glyph sits in

Reserves the footprint and centres an `AppIcon` in it. Nothing else: no fill, no rim, no shadow.
The glyph defaults to `size * 0.66` and to `AppColors.ink`; `tone` tints it to the thing it
belongs to. Reads a token in `build`, so **never `const`-construct it**.

**Not `IconTile` (`icon_picker.dart`)**, which is the other half of a confusing pair of names:
that one is handed an `iconKey` string and works out whether it names a merchant logo, a grocery
photograph or a symbol, and draws whatever ground that kind of art needs. `GlyphTile` is handed the
glyph already.

### This was a glass lens, and the duotone icons took its job

It used to be `GlassIconTile`: a painted glass disc — a near-clear tinted body, the glyph's own
colour bleeding into it, thickness shading at the far edge, a specular, and a bright bevel just
inside the rim, with the glyph painted *between* the passes so it read as sitting inside the
material. It was carefully built and it is gone, because everything it was doing was giving a flat
stroke icon some depth and some weight on a white card, and a Phosphor duotone glyph brings its
own. The under-layer is already a mass behind the strokes. Inside a lit disc the two cues argued
over 34 points — the lens saying "lit object", the glyph saying "flat shape with a shadow in it" —
and neither won.

Two things from building it are worth keeping, because they generalise past the widget:

- **An edge drawn *on* a boundary says "shape"; an edge drawn just *inside* it says "thickness".**
  That is the whole difference between a bordered circle and a lens, and it is the most
  recognisable thing about Apple's material. Both earlier attempts drew an outline — first accent,
  then grey — and both read as a bordered circle.
- **A treatment that overlaps a glyph costs the glyph its edges.** The specular was painted over
  the icon on "the icon is under the glass" reasoning; even aimed at the upper-left rim it laid 42%
  white over the glyph's upper-left and 21% over its centre, and at 34/17 a stroke is about 1.5pt,
  so it went visibly soft. Anything drawn over an icon has to be checked against the icon, not
  against the tile.

### When a row uses `IconTile` instead

`SettingsRow`'s `icon:` parameter draws a `GlyphTile`, and that is the default for a settings list.
The event sheet's two link cards pass `leading:` with an `IconTile` instead (`_LinkTile` in
`event_detail_sheet.dart`), for two reasons that generalise:

- **The rows carry containers the user already knows by their own symbol.** A list draws a shop
  logo or a grocery picture in Listen; giving it a bare settings glyph here would make the same
  list look like two different things in two places.
- **The sheet is a column of white cards over a photograph of the day**, and a row of loose glyphs
  has nothing separating it from the picture behind.

Inside those cards the fill carries one distinction — grey `surfaceAlt` for something that exists,
white `surface` for a row that creates one — via `IconTile.background`. That override exists for
this case only: the automatic choice (no disc at all for a glyph or for artwork in light, a white one
on dark) is about legibility, and overriding it elsewhere is how a shop logo ends up unreadable
on dark. Naming a `background` is now the *only* thing that puts a disc under a glyph, which is what
keeps these two cards telling things apart from actions after the disc went everywhere else. Note it is
`surface` and not `brandTile`: `brandTile` is white in *both* palettes so that logos stay readable,
and an ink glyph on it would disappear on dark.

**A second circle on the same row is not a second disc.** Listen's overview marks each list's
*kind* — Lebensmittel or Sonstige — with a glyph in a small filled circle on the subtitle line
(`_KindMark`, `list_screen.dart`, sized by `AppText.inlineMark`). It is not `IconTile(disc: true)`
and must not become one: that disc marks a **place**, a container's own name wherever it is named,
so wearing it twice would say the row has two names. The difference is drawn as well as reasoned —
the container disc is white with a ring, the kind mark is a fill with no ring, sitting among the
words rather than in the column in front of them. Its glyphs are the **same pair the create
sheet's segmented control wears** (`shoppingCart` / `listChecks`) and must stay so: the distinction
is taught once, when the list is made, and the overview is where that lesson is read back — a
second pair meaning the same two things would be a private language one screen speaks and the
other does not. Those are also the two lists' own default icons, so a list that matched no icon of
its own shows the glyph twice on one row, at `rowMark` meaning "this list" and at `inlineMark`
meaning "this kind". That is knowingly accepted: it is the minority case, and an echo beats two
vocabularies for one question.

## `FrostedHeaderBackground` (`glass.dart`)

A **variable blur** under a translucent wash, both ramping to nothing at the bottom edge — the
material behind a collapsing header, so scrolled content passes under it blurred instead of reading
through. It is what Apple's `.soft` scroll-edge effect does; deliberately **not** a `GlassSurface` —
liquid glass's specular highlight and edge refraction read as a floating control, wrong for an
edge-to-edge bar.

- **The blur is one `FragmentShader`, run twice, and the ramp is continuous.**
  `shaders/progressive_blur.frag` computes a Gaussian whose sigma is `smoothstep` of how far down
  the bar the fragment sits — peak at the top, zero (with zero slope) at the bottom. It runs
  vertically, then horizontally over that result, because a separable pair of 17-tap passes is the
  same Gaussian as one 289-tap kernel. `main()` awaits `loadFrostedHeaderShader()` before
  `runApp`, so the first header ever drawn already has it.
- **Don't go back to stacked bands.** This shipped first as five `BackdropFilter`s in hard
  `ClipRect`s with rising sigmas, and every clip was an edge — the user saw them as lines drawn
  across the screen, and the smearing as the header being "frozen":
  - blur **stepped** at each of the four interior boundaries, and a step in blur reads as a line;
  - the full-height band was still at sigma 3 when it stopped dead, so the bar's own bottom edge
    was the sharpest line of the lot — the tint ramped out, the blur never did;
  - a band's kernel was wider than the band was tall (sigma 11 in a ~29pt box), so it ran out of
    pixels and **edge-clamped**: rows stretched rather than blurred;
  - each band filtered the output of the ones below it, so the sigmas **compounded** to
    √(3²+4.5²+6²+8²+11²) ≈ 15.8 where 11 was written down;
  - and the saturation `ColorFilter` was flat over a band that ended, putting a colour step at the
    same edge.
  None of that is tunable — a hard-clipped band *is* an edge. `_BandedFrost` survives only as the
  non-Impeller fallback (`ImageFilter.isShaderFilterSupported`), at gentler sigmas; leave it alone.
- **`peakSigma` (12 logical px) is the "too strong / not enough" knob**, and the ramp's shape stays
  in the shader. It reads lower than the old stack's nominal 11 because that stack compounded: 12
  is what actually reaches the glass.
- **Its tint is also what the header's glass buttons refract, which is why `tintOpacity` is
  0.46 and not the 0.62 it shipped at.** A `GlassIconGroup` or `GlassIconButton` on the title row
  is real `UIGlassEffect` sitting on this bar, and glass shows you whatever is behind it: behind a
  near-opaque tint there is nothing left to lens, so the control rendered as a flat grey pill with
  a hard rim — the look of a painted approximation. Apple's own scroll-edge effect is mostly
  *blur* with a very light tint for the same reason. Content here is white cards on `#F7F8FA`, so
  the blurred backdrop is already nearly white; at the 82% this first shipped with, the bar was
  indistinguishable from solid white — the effect ran, it just had nothing to show.
- **The wash eases out in six stops, not three.** A linear fade to zero ends in a corner — alpha
  stops changing all at once — and the eye picks that corner up as a faint band even where nothing
  is drawn. The stops follow the same ease the shader ramps the blur on, so tint and blur die
  together.
- **Saturation is boosted at the top and ramped down with the blur**, inside the shader's second
  pass (`uSaturation`), the way Apple's materials do it: a coloured chip or source dot passing
  under the bar keeps its colour instead of washing out to the same grey as everything else. Ramped
  rather than flat, or it is one more step at the bar's edge.
- **The private route was considered and declined.** A true variable blur in UIKit means the
  undocumented `CAFilter` named `variableBlur` with an `inputMaskImage` on a `UIVisualEffectView`'s
  backdrop layer — private API, and a review risk for no gain now that `ImageFilter.shader` gives
  the same effect in public Dart. `UIScrollEdgeEffect` (iOS 26) is the public one and attaches to a
  native `UIScrollView`, which we don't have: our scroll views are Flutter's.
## Collapsing headers (`collapsing_header.dart`)

Board, Box and Listen all scroll the same way: `CollapsingHeaderScreen` (a `NestedScrollView` +
pinned `SliverPersistentHeader` over `CollapsingSliverHeaderDelegate`) pins a title row while the
block under it — search field, stat tiles, Board's today/progress line, a detail screen's big name
row — clips and
fades away. That collapse tracks the finger; `extraCollapse` is the one way to drive the same fold
from an animation instead (Listen and Boxen, handing the header over to search — see the search
entry in the widget index), and it scales the extent the block is *given*, never the height it is
measured at. `CollapsingScreenTitle` morphs the heading from large-left to small-centered;
`ScreenBodyPanel` is the rounded gray panel the body scrolls on; `HeaderBrandGlow` is the colored
wash the detail screens put behind theirs.

**The big name in a detail header is an `ExpandableTitle` (`expandable_title.dart`), not a `Text`.**
Families write names that do not fit on one line, and both copies of the name — the big row and the
pinned bar's collapsed one — ellipsize at the same word, so the end of it was unreadable anywhere on
the screen. The widget measures the name at the width the row actually got, with the platform text
scale, and only *then* draws a caret: a name that fits gets no control, because an affordance that
expands nothing promises hidden content that isn't hidden. Tapping anywhere on the row unfolds it to
at most four lines. Nothing else is needed to make the header grow — the `extra` block measures
itself every frame (below), so the extra lines push the body down exactly as another row would.
Listen, Boxen and the tracker screen all use it, and a new detail header should too.

A Listen detail header takes that wash from the shop logo the list carries, and
[lib/data/brand_colors.dart](../lib/data/brand_colors.dart) **reads it off the logo** — one decode
per asset, cached, dominant hue by saturation-weighted hue bucket — rather than from a table. The
four shops the palette names (`brandRewe`, `brandDm`, `brandToom`, `brandIkea`) stay as overrides;
everything else in `assets/merchants/` colors itself, so a logo dropped into the folder brings its
color with it. Renaming a list re-derives its icon, so the wash follows the new shop (crossfaded,
320ms) — that is the point, and a hardcoded four-shop switch is what made it silently not happen.
The bucketing itself lives in [lib/data/dominant_hue.dart](../lib/data/dominant_hue.dart), shared
with the celebration screen's `CelebrationGlow`, which reads three colours off 🎉 the same way.

**Kalender keeps its own copy of this plumbing on purpose** — its header carries a freely-scrolling
day strip whose geometry the week view owns, plus a collapsed-only filter dropdown. Don't merge
them, but a change to how the collapse *feels* belongs in both.

Non-obvious bits, each one a bug that shipped first:

- **A screen with no `extra` block at all still gets a collapse range.** `t` is the fraction of the
  header's *own* range that has been scrolled away, so a header whose block is empty has no range
  and every title is drawn at `t == 1` from the first frame — pinned size, centred, on a tab nobody
  has scrolled yet. `bareTitleHeadroom` (44) is the height the sliver keeps beyond its pinned bar in
  that case, and the title morphs over it exactly as it does over a real block. It is keyed on the
  block's **natural** height, not its folded one: a block folded away by `extraCollapse` is on its
  way to zero deliberately and must not stop 44px short. Ausgaben is the screen that found this —
  its month pager used to be the block, and taking it out left the page with a small centred title.
- **The `extra` block measures itself at runtime; never hardcode its height.** It's laid out
  unbounded in an `OverflowBox` and read back through a `GlobalKey` after the frame, with
  `estimatedExtraHeight` only covering frame one (the sliver must publish its extents before
  anything under it is laid out). Poppins comes from `google_fonts` at *runtime*, so a widget test
  measures a fallback font at ~1.0em line height against the device's ~1.4em — a constant tuned in
  a test clips the bottom row on a real phone. **It re-measures on its own `build` and on a
  `SizeChangedLayoutNotification` from the block, and it needs both**: a widget inside the block
  with state of its own (`ExpandableTitle` unfolding a name) rebuilds the block without touching
  the header's element, so the post-frame measurement is never scheduled and the header keeps a
  height the block has outgrown. That is what clipped the second line of a name and the event chip
  under it.
- **`extraPadding` is not part of the measured height — keep it horizontal.** The block is measured
  through a key *inside* that padding, so any top or bottom padding there is laid out but never
  counted, and the bottom of the block is clipped by exactly that much. Put vertical gaps inside
  `extra` itself. The spend explore page's filter chips shipped with their bottom edge cut off for
  this reason.
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

- **`DissolveBottom` (`dissolve_edge.dart`)** — a picture that **ends by dissolving** instead of
  being cut. A hard edge across a screenshot or an illustration reads as something that failed to
  draw; the same content faded out over its last stretch reads as a picture continuing past the
  frame. A `ShaderMask` in `BlendMode.dstIn`, so it takes the *alpha* away and whatever is behind
  comes through — a coloured gradient laid over the top would be a grey smear on the dark palette.
  One caller today: the Plus paywall's device shots, drawn taller than their band
  (`_heroOverflow`, 1.62) and top-anchored, so the phone reads large and gives up its empty lower
  half. Replacing one of those means another phone-shaped export with the interesting half at the
  top — bezel, notch and status bar belong in the pixels. The sign-in front door used to be the
  second caller and is now `FrontDoorHero` instead; the widget stays shared because the next
  screenshot in a band will want it.

- **`FrontDoorHero` (`screens/auth/front_door_hero.dart`)** — the sign-in page's picture: a
  household using the app, **drawn live** over a dot grid that lights where something is happening.
  One story, **played once and stopped**, in three movements: four pointers put a list article, an
  appointment, a to-do and a tracker into four cards; Mama comes back and swipes the whole board
  off the left edge; and `hero_welcome.png` — the tour's own first illustration, at the size the
  tour draws it — is carried in from the right on the same drag, over a blue wash in the dot grid.
  That is the last frame. A loop is wallpaper, and the fifth time the same four cards land is the
  time a reader stops seeing them.
  - The tagline types itself out under the illustration, which is why the gray panel below is
    bare: the promise belongs beside the picture making it, not a full panel away from it. It types
    by laying out the *whole* line and leaving the unwritten half at zero alpha — revealing a
    growing substring re-wraps the text on nearly every frame. **It is inside the canvas**, so it
    is a fixed size and does not follow the phone's type setting; that is the price of it being the
    picture's caption rather than a paragraph below it.
  - `_Spark` has a **`core`** (full strength before the falloff starts) and an **`aspect`**, and
    `DotField` takes a list of **`shades`** — the same struct read as a subtraction. Between them
    the wash is an even ellipse the shape of the picture rather than a pool in its middle, and the
    light steps back out from under the sentence. That last part is the fix for "the words are hard
    to read over the dots", and it is the right shape of fix: a heavier face over the same texture
    is a heavier thing that is still hard to read.
  - The four cards wear a **hairline of accent at a fifth strength**, which no card in the app
    itself does. On a page a card's shadow is edge enough because the card is what you are looking
    at; here it is a small white rectangle on a white band, and the shadow alone left it floating.
  - **The arrow is Figma's, not the system's** — broad, tilted, blunt-cornered, filled in the
    member's tone, with a thick white rim and a shadow lifting it off the page, and a name pill
    under it. A hairline system cursor is drawn for a desktop at 1:1 and vanishes inside a picture
    of something else. A round touch blob was tried in between and dropped: it is the better
    argument about input and the worse one about meaning, because what the picture has to say is
    "somebody else is in here with you", not "a finger pressed here".
  - **It borrows, it does not imitate** — the app's own card and shadow, `GlyphTile`,
    `CheckOffButton`, `formatTimeOfDay`, the grocery catalog's real article pictures, and
    `AppIcons.circleDashed` for the tracker because that is the mark a tracker wears on the Board,
    on Home and in the paywall. An act that drew the Ausgaben charts lived here briefly and was
    cut: the front door is about what the app is *for*, and three screens of product in one hero is
    none of them.
  - **Every fixed height in it is a sum, not a guess.** Poppins' line box is **1.5x** its point
    size, so two rows of `rowTitle` over `microLabel` need 42 points where most faces need 34 —
    which is exactly how three `RenderFlex` overflows got in. The constants at the top of the file
    carry the arithmetic; change a type token and redo it.
  - The layout is a fixed 356x330 canvas scaled by hand — `BoxFit.contain` worked out in
    `LayoutBuilder` rather than handed to a `FittedBox`, because the dot field is painted in the
    band's coordinates and the sparks that light it come from the canvas's. **It never scales past
    1**, or the whole thing reads as a blown-up screenshot. Inside it, text scaling is off
    (`MediaQuery.withNoTextScaling`): the picture is scaled bodily, and enlarging its type would
    burst the cards rather than help anybody. Every layer is **keyed**, because the `Stack` is
    rebuilt from scratch each frame and an unkeyed layer inherits the element of whatever used to
    sit at its index.

- **`DotField` / `DotSpark` (`dot_field.dart`)** — the **paper both sign-in pictures are drawn
  on**: a grid of dots that lights up where something is happening. It came out of
  `front_door_hero.dart` when the form pages grew a picture of their own, and it is shared rather
  than copied for the obvious reason — two painters would have drifted into two different dot grids
  on two pages of one flow.
  - A `DotSpark` is a point, a strength, a falloff `radius`, an optional `core` of undimmed light
    and an `aspect` that turns the round falloff into the ellipse of a non-round thing. A `ring`
    makes it a band of light at a radius rather than a disc — the press. `shades` are the same
    struct read as a **subtraction**, which is how the light is taken back out from under text.
  - **Spacing and dot size are in the band's own points and never scale.** It is paper, not part of
    the drawing, and paper whose texture grew on a bigger phone reads as a zoom.
  - The form pages' `GreetingHero` is the still one: a band a quarter of the display tall (clamped
    180–250, the way `StepHero` sizes an illustration) with the greeting alone in the middle of it,
    set in `AppText.greeting` — the app's largest type — on a steady glow, under the same 'aporah'
    the landing carries. Sized to its own text instead, it was a caption with dots behind it.
    It was a cursive writing itself out for a while — a wipe travelling along the letters rather
    than a real stroke, in a second vendored typeface — and both went: the effect read as the trick
    it was, and one word did not earn a second face on the one page a stranger sees.

- **`StepPage` / `StepTopBar` / `StepHero` / `StepButton` / `stepTopInset` (`step_page.dart`)** —
  the **full-page step**: a scrolling body running edge to edge under a frosted band, with the
  app's glass controls standing on it. Two flows use it — the welcome tour's three questions and
  the sign-in flow's front door → form → code — and it is one widget because the screens either
  side of "Konto erstellen" must not read as two apps.
  - It expects a `Scaffold` with `SafeArea(top: false)` around it. **The body runs to the top of
    the safe area, not to the bottom of the bar**, and each step leaves the room itself with
    `stepTopInset(context)` in its scroll padding — a `Column` of bar-over-body puts a hard white
    edge across the illustration the moment anything scrolls.
  - `StepTopBar` is a **`Stack`, not a `Row`**: the glass buttons are platform views on iOS, and
    Flutter content laid out *between* two of them never shows on device. `center` is the tour's
    `StepDots` and is null on a flow that is one of one; `trailing` is the tour's "Überspringen".
  - `StepButton` is the accent glass pill, and `enabled: false` draws a **different widget** — a
    flat muted pill — rather than the same one faded, because a platform view cannot be faded.
    A step that offers a second way on stacks a `GlassPillButton` under it at `stepButtonPadding`,
    which is what makes the two the same height. The sign-in front door is the one that does.
  - The tour keeps a private `_StepChrome` over it, holding its own dots and skip, because "step
    two of three" is the tour's vocabulary and no other stepped flow has it.

- **`SegmentedProgressBar` (`segmented_progress_bar.dart`)** — every horizontal "this much of it"
  bar: the Board's day and a spending goal. Drawn like the Ausgaben donut's arcs — a rounded filled
  piece, a rounded remainder, and daylight between them, with nothing painted under the fill. Empty
  is all track and full is all fill, and a non-zero value never shrinks below a round mark. Don't
  lay a fill over a track for a new bar; use this.

- **`AppFilterChip` (`filter_chip.dart`)** — the rounded, tappable word: Kalender's people row and
  Listen's Vorhaben suggestions are the same chip. It was Kalender's private `_CalendarChip` first,
  and the extraction is the point — a second chip that resembles the first is how two rows on
  adjacent tabs end up with different radii, a different lit colour or a different height.
  - **The lit ring sits outside the fill**, so the chip keeps its size when it is selected. A border
    drawn inside would make the row twitch as chips light and go out, and the outer ring is what
    lets the fill stay a pale accent rather than a solid one the label then has to fight.
  - `leading` and `trailing` are drawn exactly as given, **gap included**. The calendar's face,
    colour dot and glyph each sit a different distance from the word, and three knobs on the chip
    is worse than one `Padding` at the call site.
  - `rowHeight` (44) and `gap` (8) live on the class, so a second chip row cannot be a point
    shorter than the first.
  - **Three tones, and which one to use follows from what the row is *for*.** `ChipTone.lit` and
    `ChipTone.muted` are a pair and only mean anything against each other: a filter row is a set of
    answers to one question and needs a difference between the answer in force and the rest. A
    *suggestion* row is not answering anything — every chip is an offer — so neither half works
    alone: muted is four grey blobs that read as disabled buttons, lit is four accent chips
    claiming a selection nobody made. `ChipTone.outlined` is the third thing: white, ink label,
    hairline rim, which reads as *press me* without reading as *on*.

- **`StatusIsland` / `IslandLine` (`status_island.dart`)** — a screen's one-line status: a glyph, a
  sentence, and a second line saying what the sentence counts. Home's `DayIsland` and Ausgaben's
  `SpendIsland` are both a ladder of cases handing the first match to an `IslandLine`; Listen's
  `ListIsland` is the same shape with a single case in it, the invitation to Vorhaben — and its
  disclosure caret unfolds `PlannerCard` at the top of the body below. This file is
  the sentence, the crossfade between two of them and the wave that says one has just changed.
  - **A caret only on a line that answers a tap**, and the direction says which kind: `expanded`
    is the disclosure one, folding a checklist out below it; `navigates` points right, for a line
    whose tap leaves the screen. A caret on a line that merely says something promises a screen
    that does not exist, so neither is the default and the two are mutually exclusive.
  - **The crossfade belongs here, not in the row that hosts the island.** A switcher one level up
    compares the widget it is handed — always a keyless `DayIsland` — so it never sees one state
    become another and every change lands as an instant swap. The keys are on what the ladder
    builds.
  - **The two halves do not overlap.** Interval curves take the old sentence away over the first
    half and bring the new one in over the second; a plain crossfade of two sentences at the same
    left edge is two sentences printed over each other.
  - **The sweep plays once and then drops its shader.** It is the page's own colour rather than
    white so the letters dissolve towards the paper and the dark palette gets the same effect
    instead of a flashbulb, `BlendMode.srcATop` keeps it inside the glyphs, and a `ShaderMask` left
    in place would hold a save-layer under the header all day. `IslandSweep.loop` is the loading
    line, where the wave *is* the spinner; `IslandSweep.none` is a sentence the reader changed
    themselves, which is not news.
  - **The tone goes on the glyph and never on the words.** A red sentence among black headings
    shouts across the page for what is one overdue to-do or one mis-filed payment.
- **`RollingNumber` (`rolling_number.dart`)** — a figure whose digits roll from the old value to the
  new, one column at a time, as on the total at the top of the Ausgaben card.
  - **Only the columns that changed move**, so the eye sees *where* the change was rather than only
    that there was one. A total that ticks while a finger drags along a chart then reads as one
    quantity being measured, not as a series of unrelated numbers flashed in the same place.
  - **It animates the string, not the amount.** The caller has already decided the grouping
    separator, the currency symbol and the U+2212 minus; re-deriving any of it here would put a
    second opinion about money formatting in the widget layer. Anything that is not `0`–`9` is set.
  - Columns are keyed **from the right**, so a number growing a digit rolls the place that changed
    instead of shunting every column along. A figure appearing for the first time is set rather than
    rolled — there is nothing for it to have come from. Nothing in it reads a palette: the style is
    the caller's, exactly as on a `Text`.
- **`SegmentedControl` (`segmented_control.dart`)** — the app's two-or-three-way switch, at the top
  of the Listen sheet ("Welche Art von Liste?") and the Board sheet ("Was möchtest du anlegen?" —
  To-do or Tracker). It lived as a private `_SegButton` inside `list_screen.dart` until the Board
  needed the same question asked the same way.
  - **The track needs its hairline.** `surfaceAlt` is within a percent of the sheet's own
    `screenBg` body on light, so without the border the control has no visible edge at all and
    reads as two loose labels, one of which happens to sit on a white pill. The border draws the
    control; the fill only separates the inactive half from the white thumb.
  - **`pill: true` is the Spend page's two slicers, and it is a different control rather than a
    skin.** The thumb is a capsule, the track drops its border — a pill inside a pill reads as a
    button with a button in it — and hairlines part the segments instead, which is the mark iOS uses
    once the border is gone. The hairline is drawn only between two *inactive* segments, because a
    rule against the thumb's edge reads as a seam in the thumb, and it keeps its width when hidden
    so the segments do not shuffle sideways as the thumb moves. The chosen segment goes `ink`
    rather than `accent` there: the thumb already says which one it is, and a blue label on top of
    it competed with the figure the control qualifies.
  - A segment carries a label, an icon, or **an icon alone** (`showLabel: false`, for the three
    chart glyphs). `label` is still required either way — it is what VoiceOver reads in place of
    the glyph, and each segment publishes itself as a selected/unselected button.
  - **A pill whose `value` matches no segment lights none**, which is deliberate: it is how the
    Spend page's range slicer shows that the stretch on screen came from the date picker beside it
    rather than from one of its four.
  - **The thumb is one object that slides, not one that is repainted somewhere else.** It is a
    single `AnimatedAlign` in a `Stack` *under* the labels, and the labels cross from muted to
    chosen on the same clock, so the two segments trade weight while the capsule is in flight. Painted per segment, the control answered a tap by having the capsule vanish from
    under one word and appear under another, which says nothing about *which way* the choice went;
    on a range slicer, whose four segments are an ordered scale, that direction is most of what the
    movement is for. The hairlines fade on the same duration rather than blinking off a frame after
    the tap. Because the capsule is no longer the segment's own background, `_SegButton` hit-tests
    opaque — a transparent child is not a target.
  - **The thumb is placed by fraction and never measured, and that is not a shortcut.** A
    `LayoutBuilder` is the obvious way to get a segment's width, and it **cannot answer an intrinsic
    query** — which is exactly what the Spend page's range slicer asks of it, from inside an
    `IntrinsicHeight`. What that costs is not a wrong number: the throw leaves the subtree
    `NEEDS-LAYOUT`, and the next semantics pass fails `!semantics.parentDataDirty` over and over. The
    segments are all flex 1, so a capsule one-nth wide aligned on a fraction lands where the
    arithmetic would have put it anyway; the hairlines are a point each and that is the whole of the
    error. It is a `Positioned.fill`, so only the row gives the stack its size — as a plain child it
    would be asked to fill a height with no end inside a column.
  - The selected half is `AppColors.surface` plus `AppShadows.thumb`, so it reads as a thumb
    sitting on the track rather than as a second fill.

- **`PinnedActionLayout` / `PinnedActionBar` (`action_bar.dart`)** — a screen's primary action
  pinned to the bottom edge, with the body scrolling underneath it. Used by every Settings
  sub-page (`SettingsDetailPage.bottomAction`), all four onboarding steps, and both auth screens.
  - **Pass the action to the layout, never as the last child of the list.** That is where all of
    these used to be, and it put the same button in a different place on every screen: a third of
    the way down a short page with nothing under it, below the fold on a long one. The bottom edge
    is the one position that is the same on both.
  - The bar **measures itself** and hands its height to `bodyBuilder`, which must add it to the
    scroll view's bottom padding. Don't replace that with a constant — the bar carries the
    home-indicator inset and a label that wraps at large text sizes, so a constant buries the last
    row on exactly the phones that can least afford it.
  - `fit: StackFit.expand` is load-bearing. Loose constraints let a short scroll view shrink-wrap,
    and the bar then sits under the last paragraph instead of at the bottom of the screen.
  - `fadeInto` is the colour behind the bar — `AppColors.screenBg` by default (the gray body
    panel), `AppColors.surface` for onboarding. The gradient rather than a flat fill: a hard edge
    reads as the end of the page, and content would appear to stop at a line it is still scrolling
    past.
  - **Nothing may be added after the action inside the bar** — the accent pill is a platform view,
    and Flutter content painted after one lands in an overlay that lags during a route push. The
    gradient is painted first for that reason, not just for the stacking order.
  - **The bar must sit under a `Material`.** It carries its own transparent one for that reason:
    put it beside a `Scaffold` rather than inside it and its label renders in the debug text
    style — yellow and double-underlined — because nothing else on the route supplies a text
    style. `SettingsDetailPage` learned this the hard way; the layout goes *inside* the Scaffold,
    with the `SafeArea` inside the body builder so the bar keeps the home-indicator inset it
    needs to carry itself.
  - On a form the Scaffold's keyboard resize carries the bar up with the keyboard, so the action
    stays in view rather than being the thing the keyboard covers (`auth_screen.dart`).
  - A screen whose action lives inside another widget suppresses that one rather than showing
    two: the tour's last step passes `ConfirmationAction.none` to `ConfirmationView` and pins the
    pill itself.
  - Not for sheets. A sheet confirms from the chevron/check in its header (`SheetActionHeader`),
    which is its own convention and stays that way.
  - `null` action draws no bar at all, so a page whose action is gated (a non-admin's
    Familienmitglieder) ends where its content ends rather than on an empty band.

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
    - **Once, and nothing forces a layout.** A `UITabBarItem`'s title keeps the width it was
      *first* laid out at, and Flutter creates a platform view before it gives it a frame — so a
      `layoutIfNeeded` anywhere in the creation path lays five items out in zero width and clips
      every one of their titles for the life of the bar. The bar then looks perfectly spread and
      reads `Home Ka… Li… Bo… Me…`, coming right only when a tab is selected, which invalidates
      the labels. Left alone, UIKit lays it out for the first time with the frame Flutter gave it
      and the labels are right. Asking repeatedly is the same trap from the other end: Dart
      resizes the view to each answer, so a second measurement taken inside the new bounds
      measures the first answer, and the bar walks itself narrower until it truncates its own
      labels. Ask once, don't force layout, and don't add machinery to undo either.
    - It needs an `EagerGestureRecognizer`, or touch-down reaches UIKit too late for the press
      shimmer. `GlassPlatformView` now makes the same bargain for the same reason — see the glass
      section — but only for a surface that was given touch regions.
    - Not available without a `UITabBarController`: the iOS 26 *minimize-on-scroll* behaviour.
  - **Everywhere else: `AppBottomNav` (`bottom_nav.dart`)** — the same bar drawn in Flutter, and
    deliberately **not** Material's `NavigationBar`. Aporah is one app with one shape language: an
    edge-to-edge surface with its own selection indicator is a second one, and every screen above
    it is laid out to float clear of a capsule rather than to end at a bar. So this is a
    `GlassSurface` capsule **hugging its five items** clear of the bottom of the display, with a
    rounded `AppColors.surface` highlight that slides to the tapped item (`AnimatedPositioned`,
    `_selectionDuration`).
    - **The material and the glyphs are `MoreShelf`'s**, because the shelf comes out of this bar:
      the same `GlassSurface`, the same flat Phosphor at `kNavRowIconSize` through the same
      `navRowIcon` helper, `AppColors.ink` at rest and `AppColors.accent` on the item in force.
      A different treatment in either place makes the shelf read as a control from somewhere else
      that happened to appear there.
    - **Every item carries its name.** The handoff's pill labelled the selected item only and
      filled its glyph's circle with the accent — four unlabelled dots and one wide chip is a
      different control in each state, and the accent circle was the loudest thing on any screen
      it floated over. Labels cost width, so `LayoutBuilder` gives items `_maxNavItemWidth` where
      there is room and shares out what there is where there isn't; the bar then hugs the result
      and is **centred, never pinned to both margins** (`_NavLayer` in `main.dart`) — a capsule
      stretched edge to edge is the bar shape this exists instead of. The label alone is clamped
      to 1.2× text scaling, because the item is a fixed box inside a bar whose height the
      compacted nav button lines up against.
    - `kFlutterNavBarHeight` is that height and `navRowBottom` reads it, so the bar and
      `CompactNavButton` keep one centre line. Never hardcode 70 again.
  - **Compacting on scroll (Kalender only)** — scrolling the agenda down collapses the bar to
    `CompactNavButton`, a glass circle at the bottom-left carrying the **active tab's** icon;
    tapping it brings the bar back, as does scrolling to the top. On iOS the circle is a real
    `UIButton` glass configuration (`NativeGlassButtons`, the tab's `sfSymbolSelected`), like the
    header buttons and the `Mehr` shelf; `GlassSurface` + `AppIcon` is only the off-iOS fallback.
    Home does **not** compact — it is too short for it. This is our answer to the iOS 26
    minimize-on-scroll behaviour listed above as unavailable: `_CompactNavOnScroll`
    (`calendar_screen.dart`) writes `navBarProvider` (`lib/state/nav_state.dart`), and
    `_NavLayer` / `_NavShape` in `main.dart` animate the swap. Four things there are load-bearing:
    - The two shapes are **separate children that slide and fade past each other**, never one
      morphing control — a `UITabBar` platform view cannot be reshaped into a circle. What sells
      it as a collapse is that all the motion is on **one axis**: the bar drifts left as it goes,
      the circle arrives from the left, and both hang off the same centre line.
    - That centre line needs the bar's **measured** height (`NativeTabBar.onHeight`), not
      `kNativeTabBarHeight` — an iOS 26 capsule is taller, and guessing drops the circle visibly
      below where the bar was.
    - `_NavShape` takes a shape **offstage** at zero opacity. A platform view left at zero opacity
      is still a UIKit view in the scene, over both the pixels and the touches behind it. It is
      `Offstage`, not removed, so the native bar keeps its geometry and its channel.
    - The scroll test is on the **delta**, not the position: the week view is a `NestedScrollView`
      and its inner list reports `pixels == 0` for the whole time the header is collapsing.
    - **A tap on the circle holds the bar open until the next drag starts**
      (`expand(holdOpen: true)` / `dragStarted`). A flick keeps the list gliding after the finger
      lifts, and every frame of that glide is a downward scroll: without the hold, the tap expanded
      the bar and the next frame collapsed it, so it took two or three taps.
  - The bar is the **shell's**, so a screen never builds one; drive it through
    `navBarProvider` rather than passing callbacks down. That provider also publishes the
    measured bar height, because Kalender's "Heute" button hangs off the same centre line from a
    different subtree.
  - **The `Mehr` shelf (`more_shelf.dart`)** — the fifth item is the one tap that is not a tab
    change: it stands a column of two labelled glass buttons on top of the bar item, Boxen and
    Ausgaben, and the shell switches tab only once one is pressed. `AppShell` holds it as a `Completer<MoreSection?>`
    rather than a route, because it is two widgets in `_NavLayer` and not a layer of its own; the
    future is what `NativeTabBar.onTap` awaits, so UIKit keeps **Mehr** highlighted for exactly as
    long as the shelf is up and snaps back when it is dismissed.
    - It replaced a `UIMenu` anchored on the same item, and the swap is **not** a walk-back of
      "every menu is the system's own". That rule is about menus, and this is not one: **Mehr**
      names two *places* where a "..." lists verbs for the row beside it, and two labelled lines
      put a text list where the other four tabs answer with a glyph. Nor is glass beside the bar a
      compromise — `GlassSurface` embeds the real `UIGlassEffect`, so these are the bar's own
      material, not an approximation of it.
    - The buttons are `CompactNavButton`'s twins deliberately: `kCompactNavSize`, `AppShadows.navBar`,
      the accent glyph. The nav row already puts a glass circle of that size on screen when
      Kalender collapses the bar, so the shelf reads as the same family of control. Two circles
      rather than a `GlassIconGroup` capsule — `kMoreShelfSpacing` is what keeps them from being
      the one cracked capsule that widget exists to avoid — because each is a target and the
      selected one wears the opaque accent.
    - **Everything on the nav row is one size, and its glyphs are UIKit's own.**
      `kCompactNavSize` is the diameter of the collapsed nav button, Kalender's "Heute" and these
      two buttons alike, and `kNavRowIconSize` is the size UIKit draws a tab-bar symbol at (28pt).
      The glyph size is not ours to pick: the collapsed button *is* the selected tab with the
      other four folded away, and the shelf stands a finger's width above five SF Symbols that are
      still on screen. A circle carrying a glyph under the bar's glyph size reads as a smaller,
      quieter control that appeared in the bar's place rather than as the bar itself — which is
      what a 54pt circle and a 22pt glyph were doing. The circles grew to make room for the glyph
      rather than the glyph shrinking to fit them.
    - **UIKit is asked where the item actually is, once, on the tap.**
      `TabBarPlatformView.lastItemFrame` walks the bar for its item views and reports the
      rightmost one — Mehr is the last tab on both bars — and `NativeTabBar.onTap` carries that
      rect up with the tap for `AppShell._moreItemAnchor` to stand the shelf on. A
      `UITabBarItem` is a *description*, not a view, so there is no public frame to ask it for.
      - **The obvious substitute is wrong by tens of points.** An iOS 26 bar reports the **whole
        display width** from `sizeThatFits` and then draws its floating glass platter inset inside
        those bounds, so the last fifth of the bar's rect lands to the right of the item the
        reader is looking at. That is where the shelf standing right of **Mehr** came from. The
        fifth is still the fallback, and off iOS it is not an approximation at all: the Flutter
        pill really does spread five items evenly across its own width.
      - **On the tap, and not cached.** UIKit lays the items out again whenever the selection
        moves, because the iOS 26 pill changes the selected item's width, so an answer kept from
        earlier describes a bar in a different state. There is exactly one moment the rect is
        wanted. A `frame` read during UIKit's own pill animation is the value being animated *to*,
        which is the bar as it will look while the shelf stands on it.
      - **It reads and changes nothing, and that is the whole design.** No `layoutIfNeeded`, no
        items rebuilt, no sizing. **A `UITabBarItem`'s title keeps the width it was first laid out
        at**, and Flutter creates a platform view before it gives it a frame — so forcing this bar
        to lay itself out during creation lays five items out in zero width and clips every title,
        and the bar then looks perfectly spread while reading `Home Ka… Li… Bo… Me…` until a tab
        is selected. Left alone, UIKit lays the bar out for the first time when it has its real
        frame and the labels are simply right. **Don't add a layout or a measurement pass to this
        control**; the whole `Home Ka… Li… Bo… Me…` episode was one `layoutIfNeeded` called too
        early, and every mechanism added to compensate for it was treating a self-inflicted wound.
      - **Only the horizontal half of the anchor comes from the item.** The shelf is parked a gap
        above the *bar*, not above the glyph: an iOS 26 item view sits inset inside the glass
        platter, which is itself inset inside the bar's bounds, so taking the item's top tucks the
        bottom button behind the capsule it is standing on.
      - **Three rungs, in Swift, and it says which one answered.** The item view by class name
        (`UITabBarButton` / `UITabBarItem`, stable across every version of the bar until iOS 26
        reworked its insides for Liquid Glass); failing that, by shape, any real-sized `UIControl`,
        since a bar of five items and no accessories has only the five; failing that, the
        **platter** split into as many slots as there are items. The two item passes are kept
        apart, name winning outright, so a stray control on the platter cannot out-rank a real
        item. The last rung is openly a guess and is there for scale: a fifth of the platter is
        wrong by the padding inside it, where Dart's fifth of the whole *bar* is wrong by the
        entire inset — tens of points on an iOS 26 capsule, which is the misplacement this whole
        mechanism exists to fix.
      - **Then the title overrides the centre, whichever rung answered.** A `UILabel` whose text is
        the last item's title is the item on any version of the bar, because the text is ours
        rather than UIKit's, and the glyph is centred over it. It was added when iOS 26 found no
        item view at all and the platter split answered: the selected item's pill is wider than
        the rest, so the capsule's items are **not evenly spread**, and the shelf stood ~30pt right
        of the glyph. Only the centre comes from the label; the width and band stay the rung's.
      - The answer carries a **`found`** string (`named:5`, `shape:5`, `platter/5`, each prefixed
        `title/` when the label was found) and the bar and
        view widths, printed in debug as `[tab-bar-item]`. A shelf standing in the wrong place
        then says *why* in one console line; without it, "UIKit moved the item" and "we measured
        something that is not an item" look identical from Dart.
      - With nothing at all to go on it answers **nil** rather than guessing, and Dart splits the
        bar. It is a **Swift** method, so a hot reload over an older binary doesn't have it; the
        call catches that rather than throwing, because the one failure allowed here is a shelf a
        few points off its item, never no shelf at all.
    - **A column, and that is what lets it stand centred on the bar item** (`_moreItemAnchor`).
      Mehr is the outermost slot on both bars, so a *row* of two bar-sized circles would be twice the
      width of the slot and have to be pushed inward off the item it grew out of. Stacked, the
      circles sit on the slot's centre line and the labels run left from them, which is why the
      shelf is pinned by its right edge rather than laid out around a centre. Nearest button
      first, bottom-up (`VerticalDirection.up`) — the way UIKit reverses a menu it has to present
      above its anchor.
    - **Offstage when closed, never removed**, for `_NavShape`'s reason: each button is a platform
      view on iOS, and one at zero opacity still sits over the pixels and the touches behind it.
      It rises and fades, staggered from the bar item outwards; it never **scales**, because
      scaling a platform view smears it.
    - The scrim behind it paints *before* both bars, so the bar stays visible and live underneath:
      unlike a `UIMenu` the shelf does not take the screen over, and going straight to another tab
      from it is one tap. `_switchTo` closes it ahead of its own repeat-tap check for that reason.
    - **The name rides in front of the button, on a glass capsule of its own**, and the pair is
      one tap target. Beside the glyph the column is still two buttons read left to right; *under*
      it, it is the list of menu rows again. The capsule rather than bare text because the shelf
      floats over a box's photographs or a screen of Ausgaben, which is exactly where loose
      letters stop being readable. `AppShadows.floatingPill` on it, not `navBar` — that lift is
      sized for a circle and smudges under something this wide.
    - **`AppColors.ink` at rest** — black on the light palette, white on the dark one, the same
      weight as the label capsule beside it — and `AppColors.accent` only for the section in
      force. The bar's own `unselectedTint` was tried and is wrong here: `AppColors.muted` is one
      grey for *both* palettes, which reads on the bar's material and goes soft and half-disabled
      on a glass circle floating over a screen. Not the accent-*filled* circle this started as
      either, which was louder than anything it stands over and put blue on a control that is at
      rest nine taps in ten.
  - Flutter-drawn controls on that row take their icons through `navRowIcon` — Cupertino glyphs
    on iOS, the handoff's own ones elsewhere. The iOS bar draws real SF Symbols, so an app-set
    calendar in the button that replaces it reads as a second, subtly different calendar.
  - Scrolling screens must pad their last row clear of whichever bar is up: use
    `navContentInset(context)`, with the `pill:` argument for the non-iOS clearance. Same helper
    for anything `Positioned` off the bottom edge (e.g. the calendar's "Heute" button) — but pass
    a larger `gap:` for those: scrolling content may sit close and slide under the glass, while a
    control *parked* above the bar needs air or the two glass surfaces touch and it reads as
    hiding behind the bar.
  - **It uses the height UIKit reported, and `kNativeTabBarHeight` is only the floor before the
    bar has measured itself.** The helper used to pass the constant and argue that content sliding
    a few points under the glass is fine. It is, for a row in the middle of a list — and it is not
    for the *last* one, which has nothing left to scroll and simply stays under the bar with its
    check circle and its "..." out of reach. An iOS 26 capsule measures well above 56, so that was
    the bottom row of every list, box and Board. Same mistake the confirmation chip made before it
    started reading `navBarProvider.barHeight`; anything computing clearance reads it too.
- `GlassIconGroup` (`glass.dart`) — two or more icon buttons in **one** glass capsule: iOS 26's
  grouped bar buttons. On iOS these are real `UIButton`s merged by a `UIGlassContainerEffect` —
  see the glass section; everything below describes the Flutter fallback. **No separator between the segments** — one was tried and the capsule read
  as a button that had cracked down the middle. The glass carries no line of its own, so a
  hairline is the only hard edge inside it and the eye lands on it; Apple's own grouped items have
  none either. Spacing does the work instead, including padding at the ends so the outer icons
  aren't pressed against the round caps.
  - Segments are **44pt wide** in a 40pt-tall capsule — Apple's minimum target, and wider than the
    control is tall because two icons this close are otherwise easy to mis-hit.
  - Same material arguments as the "Heute" pill: no forced `tint`, no `fallbackTint`, and
    `AppShadows.floatingPill` rather than `glassButton`, whose lift is sized for a 40pt circle and
    smudges under something ~100pt wide. On the native path the shadow is dropped altogether —
    see the "nothing painted underneath real glass" rule above.
  - **One capsule, several touch targets.** `_regions` derives each segment's fraction from the
    same three numbers the `Row` is laid out from, so the target and the glyph under a finger
    cannot drift apart. The material lenses the whole capsule (that is what it is); the *icon*
    still scales, because the lensing says the capsule was touched and nothing about which of two
    icons it was under.
  - On the iOS Simulator this renders flat: a grey fill and a hard rim, with none of the
    refraction. That is the Simulator, not the code — judge any glass surface on a device. Kalender's header uses it for "verbinden" + "neuer
  Termin". Reach for it rather than two `GlassIconButton`s side by side, which read as one button
  that failed to draw: each is its own piece of glass with its own rim. Only the pressed segment
  reacts, and it is the **icon** that scales — the capsule is a `UIGlassEffect` platform view on
  iOS and scaling one smears. A header that reserves room for it should track `width`.
- `FloatingGlassPill` / `UndoPill` (`floating_pill.dart`) — the glass control that comes and goes
  with the state behind it: the calendar's "Heute", Board's and Listen's "Rückgängig". The widget
  only draws itself and taps beside it fall through to the screen underneath.
  - Two shapes. The default is the small icon + label pill, parked above the bottom nav at
    `Positioned(left: 0, right: 0, bottom: navContentInset(context, pill: 106, gap: 36))` around a
    `Center` — that is "Rückgängig". `onNavRow: true` is the taller capsule that stands on the nav
    bar's row, the height of `CompactNavButton` at the other end of it — that is "Heute".
  - `icon` is **nullable**, and "Heute" passes none: it stands a finger's width from the bar's
    calendar icon, so any calendar glyph on it reads as a duplicate of that icon rather than as a
    different offer. Don't put one back.
  - `UndoPill` is the check-off half: it takes a **token** (the id of the row that just moved into
    "Erledigt", `''` for nothing) and shows itself for five seconds each time that token *changes*.
    The screens derive the token from `state.justMoved` plus the row's `done` flag rather than
    calling anything imperatively — which is also why undoing, from the pill or from the "Erledigt"
    row, takes the pill away by itself. A token already up when it mounts shows nothing, so opening
    a list doesn't offer to undo something ticked off ten minutes ago.
- `EmptyState` (`empty_state.dart`) — the one "there's nothing here yet" block: a tinted circle
  around a glyph, a line of guidance, and an optional `action` under it. Every screen with nothing
  on it draws **this, bare** — never wrapped in a `SectionCard`. A card is a container for rows,
  and an empty one draws a box around the news that there is no box; Listen is the shape the others
  follow, and Box and Board were brought onto it. A detail screen whose card holds the add row
  keeps the card and puts the block **under** it, because there the card is the field you type in.
  - `iconColor` defaults to the muted tone. Pass the accent where the state is an **invitation**
    (no boxes yet, no lists yet, nothing open on the Board) rather than a statement of fact (a
    search with no hits, a range with no spending).
  - `action` is for the screen with no other way in — Board's "Aufgabe hinzufügen". Most leave it
    null and say "Oben tippen…", pointing at the `+` that is already in the header; a button
    beside a `+` two centimetres above it is the same offer made twice.
  - **Settings pages are the deliberate exception and say so at each site**: on a page of other
    cards, the empty card holds the place its rows will take, so the page keeps its shape once
    something connects and the state doesn't read as a page that failed to load.
- `showAppSheet` / `SectionCard` / `CardDivider` (`app_sheet.dart`) — shared bottom-sheet chrome
  (grab handle, X/title/check header or a custom `header`, scrolling body). **Every** modal sheet
  should go through this rather than a bespoke `showModalBottomSheet`.
  - **`SectionCard(onSurface: true)` for a card whose page is itself `AppColors.surface`** — the
    onboarding steps, anything built the way Home is below its day card. On light it changes
    nothing and `AppShadows.card` does the lifting; **on dark a shadow separates nothing**, so
    without it a `surface` card on a `surface` page is invisible — which is what the whole welcome
    tour looked like. It swaps in `AppColors.cardOnSurface`, and the rows need it too
    (`dividedRows(..., onSurface: true)`, `CardDivider(onSurface: true)`): `AppColors.divider` is a
    tone of the card it normally sits in, so on a lifted card it comes out the same colour as the
    card it is meant to divide.
  - **The grab handle doubles as the countdown on a sheet that dismisses itself.** Anything
    inside the sheet can set `SheetCountdown.of(context)?.value = duration` (from a post-frame
    callback — setting it during build rebuilds a sibling mid-pass) and the pill's fill drains
    left to right over exactly that span, on a faint track it leaves behind. Same 44×4 handle,
    same place, still draggable; a sheet that never counts down looks exactly as it always did.
    `ConfirmationView` sets it from its own `dismissAfter`, so no caller has to keep the two in
    sync.
  - **A create sheet names its `requiredField`, and the check goes grey without it.** Pass the
    sheet's own name/title `TextEditingController` and the header's blue button dims and swallows
    its tap while that field is blank — the sheet stays open with the empty field in view. It
    exists because the opposite shipped: the chrome popped the sheet on every tap and the write
    was then refused for having no text, so confirming an unnamed list closed the sheet and
    created nothing, with no error anywhere. Two of the app's placeholders ("Listenname", "Was ist
    zu tun?") were dark enough to read as text somebody had already typed, so that tap was made in
    good faith — the hint colour is fixed in `buildAppTheme` (see below), and this is the guard
    behind it. `SheetActionHeader` takes the same argument. Skip it where an empty title is a
    legitimate state to save from: the Kalender **edit** sheet, because a proxied Google or
    Outlook event may genuinely have no summary, and the Box item sheet, where an emptied name
    means "leave it alone".
  - **The keyboard is handled here, once, for every sheet in the app.** Flutter's
    `showModalBottomSheet` does not apply `viewInsets` to what it builds, so a sheet left to
    itself keeps its full height and the keyboard is simply drawn over the lower half of it — the
    field being typed into ends up underneath, and the body cannot be scrolled to reach it,
    because its scroll view still believes it has the whole sheet to lay out in. `showAppSheet`
    does two things about it: the gray body's bottom padding carries the keyboard inset, so the
    part that scrolls **ends** where the keyboard starts, and the sheet's height grows by that
    same inset, so `heightFactor` is a fraction of what is *visible* rather than of the screen.
    An 0.92 sheet is otherwise showing about half of itself. Nothing a caller passes is involved,
    so a new sheet gets this for free — which is another reason not to hand-roll a
    `showModalBottomSheet`.
  - **The top inset has to be read off the view, not off the `MediaQuery`.** A grown sheet stops
    short of the status bar, or the clock and the wifi bars end up sitting on the grab handle and
    the X. But the ceiling that does it cannot be measured the obvious way: `showModalBottomSheet`
    builds its content inside `MediaQuery.removePadding(removeTop: true)` — `useSafeArea` defaults
    to false — so **inside any sheet, `padding.top` and `viewPadding.top` both read 0**, and a
    ceiling computed from either is just the top of the screen. The real inset comes from
    `MediaQueryData.fromView(View.of(context))`, read inside the `LayoutBuilder` so a rotation
    brings the new one with it. The same trap is waiting for anything else in a sheet that
    wants to know where the notch is — a `SafeArea` in there does nothing at the top edge.
  - **A sheet covered by a second sheet drops in behind it, and only a sheet does that to it.**
    The Board's create sheet is 0.92 tall and the due-date sheet it opens is 0.58, so the first
    one used to stay in full view above the second: same width, same 30pt radius, same white, a
    legible title and a second grab handle above the front sheet's header. Two peers, not a
    stack. The back sheet now drops until only 14pt of it clears the front sheet's top edge, and
    scales toward its own top by Apple's measured 8.35% on the way down, leaving a rounded
    shoulder slightly narrower than the card in front. The scrim can't do this job — it dims both
    sheets equally.
    - **Scaling alone is not enough, even though that is literally what iOS does** when a sheet
      covers a sheet (`_kSheetScaleFactor` in `cupertino/sheet.dart`). It shipped for one build
      and was worse: iOS applies it to two sheets of similar height, ours are 0.92 and 0.58, so
      an 8% inset left the same tall sheet showing its whole header. The drop is the part that
      makes it a stack, and it is what iOS itself does to a full-screen page covered by a sheet.
    - **The two sheets are sibling routes**, so neither can inherit the other's height through a
      context. `_openSheets` is a module-level list each sheet writes its own height into during
      layout, read by the sheet below on each frame of the covering animation. Read rather than
      pushed on purpose: a notifier would mark a route dirty that had already built that frame.
    - This is why `showAppSheet` pushes its own `_AppSheetRoute` instead of calling
      `showModalBottomSheet`. `canTransitionTo` is the only place a route can say *what* may push
      it into the background, and it is what wires `secondaryAnimation` at all. Left at its
      default `true`, a sheet would drop away under an anchored menu, a `showDatePicker` dialog
      or anything else pushed over it — the due-date sheet opens both.
    - Safe to transform because the same moment stands the native chrome down (`occludedByRoute`,
      above): by the time the sheet moves, every `UIGlassEffect` inside it has already swapped
      itself for the Flutter approximation, so nothing being moved is a platform view.
    - It rides `secondaryAnimation` rather than playing its own animation, so dragging the front
      sheet down brings the one behind back up under the finger.
- `SheetActionHeader` (`app_sheet.dart`) — the same X/title/check row for a sheet that **submits
  while it stays open**: `SheetHeaderAction.confirm` → `.busy` (spinner, and the X withdrawn — the
  request wouldn't be cancelled by closing) → `.none` (bare title: the sheet has become a
  confirmation that dismisses itself, and an X would race it for what the sheet pops with).
  `.close` is the fourth and belongs to a different kind of sheet entirely — one whose controls
  each act as they are used, so there is nothing to submit and the X is the only thing in the bar
  (the connected calendar's sheet: the name saves on its own tick, the owner on the tap that picks
  it). Don't put a check on one of those; it would be a second way to commit what is already
  committed, and the first thing somebody looks for when they want to know whether it took.
  `showAppSheet`'s built-in header pops on the check, which such a sheet
  must not do, so pass this as `header` wrapped in a `ValueListenableBuilder` on the phase. Used
  by `showRenameSheet`, `showCalendarConnectSheet` and Settings' invite sheet
  (`settings/family_page.dart`) — a fourth sheet with a request in flight belongs here rather than
  in its own copy. `closeIcon`/`confirmIcon` are for a **stepped** sheet: a back chevron instead
  of the X once there is a step behind you, a right chevron instead of the check while there is
  one ahead.
- **`ConfirmationView` (`confirmation.dart`) — the app's *one* "that worked" surface.** A mark, a
  headline, a muted `message`, and `content` cards for whatever the action left behind. All three
  confirmations in the app are this widget with different content (calendar connected, member
  invited, onboarding finished); **do not hand-build a fourth**. Three axes:
  - `dismissAfter` — a duration makes it a **beat** that plays and leaves via `onDone` (the
    connect, the invite); null makes it a **screen** that waits with an action at its foot
    (onboarding). Every check beat passes the shared `confirmationBeat` (2.5s) rather than a
    number of its own: the mark spends ~620ms drawing itself, so at the 1.1s this used to be, the
    sheet began leaving as the check landed and the line under it was read off a moving card. The
    celebration keeps its own 3.2s — its confetti has to reach the floor.
  - `mark` — `check` is the accent ring with the check **drawn** inside it (`_DrawnCheckPainter`,
    ~620ms: the circle closes from twelve o'clock, the tick is put down along its own path with
    `PathMetric.extractPath`, the two overlapping so it reads as one gesture) — the everyday
    result. Outlined on an 8% wash of the accent rather than a filled disc: the disc was *already
    finished* when the sheet opened, so the only motion left was a halo expanding around something
    that never happened. One size (`_markSize`, 76pt, in a box of exactly that) on every surface;
    the 78pt disc used to sit in a 130pt box to leave room for that halo, which was 52pt of empty
    height in a sheet that is mostly white space. There is no `icon` override any more — the check
    is a path, not a glyph.
    `celebration` is 🎉 (which keeps the ease-out-back pop the drawn check gave up), falling
    confetti and the full `screenTitle`, for the moments that happen
    once per family: the household set up, somebody invited into it. **Confetti on every write is
    confetti nobody sees** — a new caller needs a reason to be a celebration.
  - `action` — `sheetAction` (the bordered `OutlinedSheetAction` a sheet ends with) or
    `accentPill` (`GlassAccentButton`, the accent glass pill a full screen ends with).

  It is a sheet/screen *body*, not a sheet: a flow that already has one swaps its body for this
  (`AnimatedSwitcher`, 220ms) so the sheet that acted becomes the sheet that confirms, with no
  second modal stacked on the first. `showConfirmationSheet` is only for a result that came from
  somewhere other than a sheet, and asks for `heightFactor: 0.44` — a sheet is a fixed fraction of
  the screen whatever is in it, so that number *is* the confirmation's height. The confetti is 26 rounded rects on one controller in a
  `CustomPainter`, coloured from `AppTones` — one pass, no package, no loop.
- **`CelebrationGlow` (`confirmation.dart`) — the party light behind a `celebration`.** Three
  radial washes off the top edge in 🎉's *own* colours, read off the rendered glyph by
  [lib/data/emoji_colors.dart](../lib/data/emoji_colors.dart) — same saturation-weighted hue
  bucketing as a shop logo's brand wash, shared in
  [lib/data/dominant_hue.dart](../lib/data/dominant_hue.dart), taking the top three instead of the
  top one. Don't tabulate the hexes instead: Apple, Google and every desktop emoji font draw that
  popper differently and redraw it between OS releases, so a hardcoded gold stops matching the
  picture directly above it. Like `HeaderBrandGlow` it belongs at the **foot of the screen's
  stack, outside the `SafeArea`** (onboarding's `_DoneStep` is the only caller) — inside the
  confirmation it would start below the status bar and leave a white band over it. It paints
  nothing until the glyph has been read and then fades in over 520ms; there is no accent-coloured
  stand-in, because a wash snapping from blue to gold under a headline reads as a bug.
- **There is no `PrimaryButton`.** A **full screen**'s primary action (onboarding's four steps) is
  `GlassAccentButton(expand: true)` like every other accent action in the app — it was a flat
  accent `Container`, the one filled rectangle left in an app whose every other button refracts
  what's behind it. A sheet ends with `OutlinedSheetAction` instead, where a filled pill would
  compete with the accent check in the header.
- `GlassPillButton` (`glass.dart`) — the **neutral** labelled glass pill: a way *out* rather than
  the action (Settings' "Fertig", the onboarding header's "Überspringen"). Same material as
  `GlassIconButton` beside it, no tint; `GlassAccentButton` is the filled sibling.
- `CopyLinkCard` (`copy_link_card.dart`) — a URL the app was handed **once** (currently only the
  share sheet's fresh link), with copy-as-the-whole-card and the "wir speichern ihn nicht"
  footnote. `onDismiss` adds the X, for the share sheet where the card outlives the moment.
  **Not used for invitations**: an invite travels by mail only (see `SentInvite`).
- `StepDots` (`step_dots.dart`) — one dot per step with the current one drawn as an accent pill,
  at the top of a sheet's gray body, and centred in the onboarding wizard's own top bar. A
  multi-step flow has to declare its length; a sheet is a single question by default here, so a stepped
  one has to declare itself: without the dots the first step reads as the whole thing and the
  accent button in the header looks like it will finish rather than continue. Steps already taken
  keep a faded accent, which is the "2 von 3" nobody has to read.
- **`showCalendarConnectSheet` (`calendar_connect_screen.dart`) — one sheet per connect, never a
  sheet over a sheet.** All six providers walk the same spine inside it, marked by `StepDots`:
  their own first question (a CalDAV login, a Bundesland, an address — Google and Outlook have
  answered theirs in Safari before the sheet opens), then whatever that answer opened up (the
  account's calendar list; Abfall's Abfuhrbezirk chips, or the ICS link for a town no vendor
  serves), then the name, then the `ConfirmationView` beat. `_ConnectFlow` is the whole
  conversation — steps are views of it, and its `steps` getter is **recomputed**, so the dot row
  grows at the moment an answer says there is another question. The header's accent button is a
  **chevron** while there is a step after this one and the check on the last; the X becomes a back
  chevron as soon as there is a step behind you. It is never hidden or greyed: an unanswered step
  says what is missing in its own error line when the chevron is tapped, which a disabled button
  cannot. Every network check happens on the step that asked — the password, the ICS link — so a
  rejection lands under the field it belongs to. What this replaced: each provider used to finish
  by opening a *second* sheet over its own, stacking two grab handles, two headers and two X's.
- `showRenameSheet` (`rename_sheet.dart`) — one thing, one name, one check, and the beat that says
  it saved. A whole sheet rather than an `AlertDialog` with a `TextField` because renaming is a
  *save*, and every save in this app is a check in a sheet header. `onConfirm(name)` runs while the
  sheet stays open (the X goes away — the request wouldn't be cancelled by closing), then a short
  `ConfirmationView` beat (`confirmationBeat`, 2.5s) before it pops `true`; throwing keeps it open with the message
  under the field so the typing isn't lost. It used to be the shared last step of all six connect
  flows, which is why it looks like one — those now have that step inside their own sheet. It
  takes an `icon` **or** a `leading` widget: a subject that has a face of its own puts that face at
  the head of the sheet instead of a glyph in a tinted circle.
- `FamilyAvatarButton` (`family_avatar_button.dart`) — the household's picture, or its initials on
  the tone derived from its id, plus the camera badge an admin taps to change it. Drawn in two
  places that both edit it: the leading slot of the family-name row, and the rename sheet that row
  opens (which used to show a house glyph — a family is people, and the face it already had was one
  tap away without being drawn). Its menu goes through `showPictureMenu`, so
  it is the system's own anchored menu first and the dropdown only as a fallback — which is what
  makes it safe to open from inside a sheet whose header carries native glass buttons. `ringColor`
  is what the badge is ringed against: the card's surface on the page, `AppColors.screenBg` in the
  sheet.
- `SettingsRow`'s built-in icon tile is a **circle**, not a squircle (`settings_chrome.dart`) —
  the rows that carry a logo (calendar providers) or a face (family members) can only be round,
  and a settings list mixing both shapes reads as two lists.
- **A Settings page is cards, and everything on it writes at x=18** — the inset a card's own text
  sits at, so a page reads as one column instead of two (`settings_chrome.dart`). Three widgets,
  and which one you want depends on what the text is naming:
  - `FieldGroup` — a caption, one optional line of explanation, and the control under it, all
    **inside** the card. This is the label of a *field*: "Adresse" and the box you type it in are
    one thing, so they can't be separated by the card's edge.
  - `GroupLabel` — the small 13pt muted caption **above** a card, naming the rows in it
    ("Verbunden" over the connected calendars). A list of rows that already say what they are needs
    a quiet name over the group, not a 16pt ink heading inside it. It is *not* the old
    floating caption: that one sat at x=6 and never lined up with anything.
  - `SettingsNote` — a muted line **under** an action, an iOS footer (the privacy line beneath
    "Mit Google anmelden"). Pass `inset: 0` inside a sheet, whose gray body already carries the 18.
  - Explanation goes in the `hint` of the block it is about, never in a paragraph at the top: the
    page's hero already says what the page is for, and the pages that repeated it read as two
    intros and a form.
  - Blocks are spaced by `AppSpacing.blockGap` (card→card, card→button). Don't hand-pick a gap.
- **A Settings detail page shows what you have and offers one button, and that button *starts* the
  thing — it never opens something that offers to start it.** Settings → Kalender is the pattern
  (`calendar_connect_screen.dart`): the root lists the six providers with a status badge each, and
  every provider page under it is the same three parts — hero, a "Verbunden" card of that
  provider's connections (an `EmptyState` card holding its place when there are none), and a glass
  `AccentAction`. What the button does is the provider's own first step: for Google and Outlook it
  says "Mit Google anmelden" and goes straight to the consent screen (with the privacy line as a
  `SettingsNote` footer under it), and the sheet opens only on the way back, on the first thing
  left to ask; for the other four it opens `showCalendarConnectSheet` on their first question. A
  sheet whose only content is one button is a popup asking permission to ask. Keeping the forms on
  the pages made each provider look like a different screen with nowhere obvious to press; keeping
  the *list* of providers in a sheet made the household guess what Aporah could read before
  opening anything.
- `HeaderSearchBar` (`search.dart`) — Listen's and Boxen's search, which happens **in place, never
  in a sheet**. **One way in: the magnifier sharing the `+`'s glass capsule**, always in the same
  spot on the title row. It was two — a flat pill filling the collapsing header plus a glass button
  that faded in once the pill had scrolled away — which spent a whole row of the block saying a
  second time what the capsule says once, and left the resting screen a search box above a heading
  above a card. `HeaderSearchBar` wraps the screen's whole title row: it fades that row out and
  grows the system search field **leftward out of the magnifier's own footprint** (right edge
  pinned, left edge travelling) over to a glass X that lands where the `+` was and closes search
  again. A control that never moves is what makes that possible — a pill that scrolls away cannot
  be grown out of, and a field unrolling from the opposite margin read as a separate thing arriving
  rather than as that button opening. Closing runs the same movement backwards. Search reaches
  *into* the detail screens — articles inside a list, contents of a box — so a hit is grouped under
  whatever holds it and tapping it opens that list/box.
- **Opening search is one movement, and `SearchableOverviewScreen` owns it, not `HeaderSearchBar`.**
  Four things happen at once — the field grows, the title row and its `+` give way to the X, the
  collapsing block folds up, and the body crossfades to the hits — and the screen holds the single
  `AnimationController` (`kSearchTransition`, 360ms, `easeOutCubic` in / `easeInCubic` out) that
  drives all four. `HeaderSearchBar` is a `StatelessWidget` taking an already-eased `progress`;
  don't give it a controller of its own again, or the header's height and the field's width will
  be two animations that only look like one.
  - The block **folds**, it isn't dropped. Swapping `extra` for an empty box was what made this
    read as a jump cut: the sliver lost its whole extent between one frame and the next, so the
    header teleported up while the field animated. `CollapsingHeaderScreen.extraCollapse` scales
    the extent instead, and the block stays in the tree at its natural measured height.
  - The `+` and the X are the same glass circle in the same place, so they are **not** crossfaded
    50/50 — the row is gone by `progress` 0.45 and the X only starts at 0.4. Held at half opacity
    together they draw one smeared button rather than a swap.
  - The body is a `Stack`: the screen's own `ListView` stays mounted underneath and the results
    fade in over it on an **opaque** `AppColors.screenBg` (a transparent crossfade shows two lists
    through each other). That keeps the body's scroll offset, so closing search puts the reader
    back where they were. The results list must carry `primary: false` and a controller of its own
    — the body list already holds `PrimaryScrollController`, and two scrollables can't share it.
  - The query is cleared when the reverse animation *completes*, not on the tap: clearing it at
    the tap empties the hits to the "search for something" placeholder for the third of a second
    they spend fading out.
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
- **A sheet body may hold a platform view again — it was forbidden, and the ban outlived its
  cause.** The Kalender event form shipped with a real `UISwitch` in its Ganztägig row and rendered
  as blank white below it: the Beginn/Ende rows, the calendar picker and the notes field laid out
  at full height and painted nothing. That was read as a headcount — two `NativeGlassView`s in
  every sheet header, a third view in the body, overlay layer dropped — and `SheetSwitch` existed
  to keep the count down. The headcount was the symptom. `native_occlusion.dart` found the cause:
  a sheet is a **non-opaque** route, so the screen behind it kept compositing its own native
  chrome into the same scene, and the tab bar and search field punching up through the sheet were
  what took the body with them. Native views now stand down while covered, which is why the same
  symptom stopped happening everywhere else. So sheets use `NativeSwitch` like every other on/off
  row, and `GlassSwitch` is the Flutter-drawn fallback it stands down *to* — also the one-word way
  back if the blank body ever returns. It fails silently, on device only, with correct layout: the
  tell is a card whose height is right and whose contents aren't there.
- `showAnchoredMenu` / `RowMenuButton` (`anchored_menu.dart`) — the menu a row's trailing "..."
  opens (Listen and Boxen item rows), and the one door every menu in the app goes through. **On
  iOS it is UIKit's own `UIMenu`**, so give each `AnchoredMenuItem` a `symbol:` (an SF Symbol name)
  beside its Phosphor `icon:`; the panel below is what the rest of the world gets, and what iOS
  falls back to before 17.4. Deliberately **not** a `GlassSurface`: UIKit
  menus are a near-opaque vibrant material, and glass lets the content underneath read through the
  rows. The panel is **opaque and carries no `BackdropFilter`** — it had one, and inside a sheet it
  read back the wrong backdrop on device: the card and the native glass buttons behind the menu
  painted over its own rows, so a two-item menu showed one item and a blue pill. Sampling the
  backdrop for the last 3% of translucency is not worth a panel that breaks wherever the app's own
  platform views are. Rows are a **fixed** `AnchoredMenuSurface.rowHeight`, which is what lets the route compute
  the panel's height up front and decide before layout whether it still fits below its anchor (it
  flips above it otherwise) and which corner to grow out of. The bottom bound is
  `navContentInset`, not the screen edge — on iOS the native tab bar composites over anything
  Flutter paints, so a menu reaching under it is simply cut off. `AnchoredMenuItem.onSelected`
  runs *after* the menu has closed, so an action that opens a sheet isn't animating in behind it.
  A row carries either an `icon` or an `svgAsset` (a brand mark from `assets/`, via
  `flutter_svg`) — **the SVG is tinted to the row's own colour** with a `srcIn` `ColorFilter`, not
  left full-colour: a menu row is a label, and a lone colour logo is then the one thing shouting
  on a monochrome list. Labels are bare nouns ("Foto", not "Foto hinzufügen") — every row is
  something you're doing to the item, so repeating the verb says nothing.
- `RowMoreButton` (`anchored_menu.dart`) — the three dots on their own, for a row whose "more" is
  not a menu. `RowMenuButton` is this plus an anchored menu, so both wear the same mark at the same
  size. The connected-calendar rows in Kalender's settings use the bare one: tapping the row opens
  a sheet holding everything you can do to that calendar (rename, assign, disconnect), and a menu
  listing those three words in front of it was a stop on the way rather than a choice. The dots
  stay because they are what says a row has more behind it than the tap; they simply open what the
  row opens.
- `GlassMenuButton` (`anchored_menu.dart`) — [RowMenuButton]'s counterpart for a *screen header*:
  the glass "..." in a detail screen's title row (Listen and Boxen both use it for Bearbeiten /
  Löschen), opening the same anchored menu. A separate widget rather than a flag, since
  `RowMenuButton` is a bare 15px glyph sized for a list row.
- `BrandMark` (`brand_mark.dart`) — **the one frame a shop logo is drawn in**, for Listen, Box,
  Ausgaben and the icon picker alike. Brand marks share no shape (REWE is a full-bleed red square,
  IKEA a wide wordmark, ALDI a tall one), so fitted straight into a slot they normalise to nothing
  and a column of them reads as unrelated coloured rectangles; the white `brandTile` disc — white in
  both palettes, because these logos are printed for paper — is what gives all of them one
  footprint, and the hairline is the only reason a white logo is visible on a white card.
  - **The logo fills the disc and is clipped round.** It sat at `AppText.markImage` (0.68, the
    square that fits inside a circle) until 2026-09-17, which left a red square floating on a white
    circle: that reads as a sticker put on the row rather than as the shop's own mark. Drawn edge to
    edge, REWE *is* the disc. A badge that fills it hides the hairline, which is what the hairline is
    for.
  - **The artwork is what makes that safe, not the clip.** A circle keeps 79% of its square, so a
    badge whose lettering runs to its own edge loses the ends of it — ALDI NORD did, AliExpress lost
    two fifths of its logotype. `tool/icon_gen/frame_merchants.py` fixes that in the *asset*,
    alongside the `normalize.py` that re-frames the grocery pictures: a badge's flat edge colour is
    extended to fill the frame and its logotype scaled to fit the inscribed circle, a mark on
    transparency is scaled until its bounding box touches the circle (which makes a wide wordmark
    *bigger* than the old inset allowed), and a logo with a gradient at its edges is left fitting
    inside, because there is no flat colour to extend and inventing one puts a seam across the mark.
    **Run it after dropping a logo into `assets/merchants/`.** The widget draws what it is given at
    full width and has no per-logo inset to fall back on, deliberately: a table of those in Dart is
    exactly what a new PNG would silently miss — the same reasoning that makes `brand_colors.dart`
    read a logo's hue off the file rather than tabulate it.
  - `fallback:` is what goes on the identical disc when there is no logo — Ausgaben's initials for a
    shop `assets/merchants/` has never heard of, its category glyph on a fold. One disc, several
    fillings, so the eye can go down the *names*.

- `IconTile` / `IconFieldRow` / `PhotoFieldRow` / `showIconPicker` / `IconDraft` (`icon_picker.dart`) — the one place
  a list/box/item icon is **drawn** and the one place it is **chosen**. Both sides speak the same
  `iconKey` string from `data/icon_suggestions.dart`: an `assets/` path, `lucide:<name>`, or
  `emoji:<character>` — a
  key format frozen by the rows already in the database, not a statement about which icon set the
  app draws (that is Phosphor Duotone; see `lib/theme/app_icons.dart`).
  - `IconTile` splits four ways on *what kind of art it is*, not on taste. **A symbol glyph is
    drawn bare** in the theme's own ink at `AppText.markBareGlyph` (0.6 of the slot). It sat on the
    `surfaceAlt` disc until 2026-09-16, on the reasoning that a hairline mark needs somewhere to be —
    but a duotone glyph is not a hairline mark: its under-layer is already a mass behind the strokes,
    so the disc was a second ground under a shape that brings its own. In a column mixing glyphs with
    grocery pictures it was also the only thing wearing one, so every food row read as artwork and
    every other row as a button. (Same discovery `GlyphTile` made when the duotone set took its glass
    lens's job.) The glyph *grows* when the disc goes — half the slot inside a fill and 0.6 of it on
    nothing are the same apparent size, and this lands where `_ItemIcon` in `box_screen.dart` already
    had it by hand. **A grocery picture is drawn bare** at `size * 0.88`, since it
    arrives already sized and centred on nothing — except on dark, where it keeps the white
    `brandTile` under it because the art is drawn for paper (the same rule `_ItemIcon` in
    `list_screen.dart` follows). **A shop logo is handed to `BrandMark`** (see below), in
    every one of the tile's shapes. `IconImage` (`icon_image.dart`) bounds the decode with
    `cacheWidth` — the picker puts 160 full-size logo PNGs on screen at once. **An emoji is the fourth kind**, drawn as text at 0.56 of
    the slot (0.52 on a disc, since an emoji fills its em box where a Phosphor mark leaves air) —
    `emoji:⛺`, which only a Vorhaben writes; see [list-planner.md](list-planner.md).
  - **The disc came back where a container is named.** `IconTile.disc` asks for the ground without
    naming a colour for it, and a list or a box passes it wherever it says its own name: its row on
    the Listen/Boxen overview, its header once open, the collapsed title above that (Box does it
    through `_BoxBadge`, which is all three at once). The rule it encodes is about *place, not
    kind*: a container is a heading and its contents are a column of rows, so the name wears the
    disc and none of the articles under it do — which is the same observation that took the disc off
    every row above, read from the other end. An overview row is a heading too, so the disc there
    marks every row and therefore marks none of them out; hand it to a row of *contents* and it
    starts meaning something it can't deliver. **The fill is `surface`, not `surfaceAlt`** — the
    card's own white on light. A grey one drew a second tone into a row that already carries three
    greys of type, and on the header, where the disc sits on `screenBg` rather than on a card, white
    lifts off the page where grey blended into it. What marks the container is the hairline ring.
  - **A symbol that names a thing is drawn in ink, never in the accent, and `glyphColor` is
    therefore left alone.** The app has one accent and it already carries a meaning — a check-off
    circle, a done count, an attachment line, an empty state's call to action — so colouring a box
    or list icon with it says "this is a control" about the one part of the row that isn't, and
    reads as a per-tab brand colour the rest of the app doesn't have. Box's badge and its search
    hits used to pass `glyphColor: accent` while Listen passed nothing; Listen was right. The one
    surviving exception is the event sheet's two link cards, where the colour is telling the card
    of *things* apart from the card of *actions*.
  - **An item inside a box is drawn bare** (`_ItemIcon` in `box_screen.dart`): the glyph in
    `inkSecondary` inside an empty hairline ring, no fill. The filled disc is what the box's own
    badge above it wears, and repeating that down every row made a shelf of things read as a shelf
    of boxes. A photograph still gets the filled disc — it has to be cropped to something — and so
    does full-colour art on dark, for the legibility reason above.
  - `showIconPicker` is a `showAppSheet` with a **custom header**: X + title, no save check, since
    tapping an icon *is* the save. It browses the curated symbol groups + the shops, and searches
    across those plus the ~2000 grocery pictures (which are search-only — a browsable grid of them
    would be its own screen).
  - `IconDraft` is the mutable box a create/edit sheet's body and its save button both hold. The
    body owns the picker, but the save callback is handed to `showAppSheet` before the body exists,
    so the picked key can't live in the body's `State`. `picked == null` means "the name is still
    choosing" — which is what `IconFieldRow`'s `suggested:` flag renders.
  - **A photograph beats all three.** `IconTile.photoUrl` / `.photoFile` and the `PhotoThumbnail`
    behind them draw a picture the user took of the thing itself, and it *replaces* the icon rather
    than sitting beside it. It fills the disc edge to edge (`BoxFit.cover`), unlike a logo or a
    grocery picture, which are art on a background and stay small and centred — cropping a real
    photo to the circle is what makes the row read as "this is the thing". `photoFile` (a path on
    this device) wins over `photoUrl` (signed, expiring): it needs no round trip, and it is what a
    brand-new box's picture has before there is a box to hang it on. Every failure — expired link,
    no signal, object swept up elsewhere — lands on the muted placeholder, never on Flutter's grey
    exception box.
  - `PhotoFieldRow` is the photograph's **own row**, directly under `IconFieldRow` on the box and
    box-item sheets, and the split is the point. "Ändern" on the symbol row goes straight into
    `showIconPicker`; the row underneath reads "Bild hochladen" until there is a picture and
    "Foto · Ändern" after. They used to be one row behind one menu whose four entries asked
    *which kind of picture* before anything useful, which taxed the commonest tap on the sheet —
    correcting the guessed symbol — with a choice every time. Because they are now two rows over
    two independent columns, picking a symbol no longer deletes the photograph: the symbol is
    what the thing falls back to when the picture is removed. The symbol row therefore keeps
    showing the *symbol* while a photo is set, rather than previewing the photo twice in adjacent
    rows.
  - `showPictureMenu` is the menu behind `PhotoFieldRow` and `FamilyAvatarButton`: Foto / Kamera,
    plus a destructive Foto entfernen once there is one. No "Symbol wählen" — that row is why the
    box sheet needed splitting, and each of the two rows' taps now knows its own answer. It is one `showAnchoredMenu` call, which on
    iOS is the system's own menu — this is the sheet-internal case that forced that, since its
    header carries native glass buttons (see the platform-view note further up). It hangs off the
    row's own `GlobalKey`, so the choice grows out of the row either way; it was a
    bottom-of-the-screen `UIAlertController` until the anchored `UIMenu` replaced it. `IconDraft.photoFile` is the pending
    half: every picture is written the moment it is chosen, exactly as a profile picture is, except
    a *new* box's, which has no id for the object to be filed under until the insert comes back.
- `SwipeActionsRow` / `SwipeAction` (`swipe_actions.dart`) — iOS swipe-left row actions, shared by
  the Kalender event cards (Edit + Delete) and the Listen/Boxen item rows (Delete). The reveal is
  a 0→1 fraction on an `AnimationController`, not a pixel offset, so the live drag and the release
  snap share one value and curve; a tap while open only closes the row. Two things to get right at
  a call site: the child **must be opaque** (it slides over the actions — wrap it in a
  `ColoredBox` where a `SectionCard` was providing the fill), and `closesRow: false` belongs on
  anything that removes the row outright. `borderRadius` is the card's for a free-standing card,
  zero inside a `SectionCard` (which clips its own corners).
- `DaySelectorCircle` (`day_circle.dart`) — day-number circle (selected / today / `DayHighlight`,
  the last one the Feiertag hatch or the flatter Ferien wash — see the day-off washes section of
  [kalender.md](kalender.md)), shared by
  Kalender's week strip and month grid. Board used to have a week strip of its own and no longer
  does: a task's date is a property of the task, so the Board is a grouped list with nothing to
  select.
- `EventDots` (`event_dots.dart`) — the mark under a day cell: **one 4.5-point stroke that grows 3
  points per event (9 → 24) and is cut into a slice per event by white dividers**, up to six; plus
  an optional leading ring (`todo`) for a day that still owes a to-do, which never takes a slice. It
  owns its own budget (the caller hands over uncapped colours) and publishes `bandHeight`, which both
  day cells measure their own heights off. See the day's-stroke section of
  [kalender.md](kalender.md).
- `Avatar`, `WhoPicker` — person avatar chip and the "Alle / Nur ich / <person>" picker on
  new-item sheets. `WhoPicker` is the **assignment** axis (a single `who` string) and is what
  Board/Box/Kalender still use.
  - `Avatar` draws a **picture** when given one (`imageUrl`, a signed URL from the `avatars`
    bucket, or `imageFile` for one still uploading) and the initials-on-a-tone-colour circle
    otherwise. Every failure — a URL that expired, a decode error, no picture at all — resolves to
    the initials rather than to a hole or an error: pass both and let it choose.
  - **A face is on `FamilyMember.imageUrl`, and every circle in the app has to pass it on.** The
    picture used to stop at Settings because only `HouseholdMember` carried it, so each badge,
    stack and picker chip drawn from the `whoBadge` roster fell back to initials for a user who had
    just uploaded a photo. `HouseholdMember.asFamilyMember` and `Guest.asFamilyMember` now hand it
    across, `whoBadge` puts the assignee's on `WhoMeta.imageUrl`, and `WhoAvatars` draws it for both
    the single circle and the stack — so a new `Avatar(...)` built from a member without
    `imageUrl: m.imageUrl` is the bug, not the default. Signing is `signAvatarUrls` in
    `family_state.dart`: one batched call per roster, an empty map meaning everybody falls back to
    initials. The one avatar with no picture left is the Kalender event-owner chip, which resolves
    a *name* denormalised onto the event rather than a member id.
- `VisibilityPicker` (`visibility_picker.dart`) — the **visibility** axis, and what a sheet backed
  by Supabase wants instead: it writes `visibility` (`family` | `private` | `custom`) plus the
  member ids that become `*_shares` rows, rather than one conflated string. Alle and Nur ich are
  mutually exclusive with each other and with the member chips; selecting members makes it
  `custom`; deselecting the last one falls back to Nur ich, because `custom` shared with nobody
  *is* private. The creator is always implicitly included and has no chip. Pass
  `allowMembers: false` for a guest — the composite FK on `*_shares` makes picking a non-member a
  constraint error, not a polite refusal. Its chips are `PickerAvatarChip` (same file), which fades
  a member's *photo* to 0.55 while unselected — a picture ignores the drained bg/fg that says "not
  this one", so without it every member with a photo reads as picked.
- `VisibilityBadge` (`avatar.dart`) — what the picker wrote, read back on the row: the padlock on a
  private list/box/task, the faces of the people a `custom` one is shared with, **and nothing at
  all on a family one**. That last part is the rule (`visibilityBadge()` in `models/who.dart`
  returns null for `family`, which is what separates it from `whoBadge`): family is the default
  every second container carries, so drawing "Alle" on it would put the same anonymous circle on
  nearly every row of Listen and Boxen and bury the two rows that *are* restricted. Give it the
  gap to its neighbours as `padding` rather than a `SizedBox` beside it, or every family row's
  chevron is indented by space belonging to a circle that isn't drawn.
  - On Listen and Boxen it is the whole badge — nobody "does" a box. On a Board row it sits
    *beside* the assignee's face, because those are two independent axes and a private task
    assigned to Lea has to say both; there it is skipped when nothing is assigned, since `whoBadge`
    has already put the padlock in the one circle the row has.
- `ErrorNote` (`error_note.dart`) — a failed **read**: nothing on screen and no reason to expect
  the next frame to fix it, so an inline note with "Erneut laden" that stays put. Takes German copy
  written for the user — the notifier translates, never the widget.
- **The toast chip (`toast_chip.dart`) — one component for every transient outcome.** A
  liquid-glass capsule floating clear of the nav bar: a coloured **ring** with the check or the X
  inside it, one line, and on a delete an "Rückgängig". Outlined on a 12% wash of its own colour
  rather than a filled disc with a white glyph — the confirmation sheet draws an outlined mark, and
  a solid dot beside it read as a second system. `confirmChipOf` for a write that landed, `showToast(…, kind: ToastKind.error)` for
  one that didn't — `showErrorSnack` is now a one-line delegate to the latter and keeps its ~8 call
  sites. **Success and failure differ by the ring's colour and glyph and by nothing else**; they
  used to be two unrelated objects (a hugging white pill vs. a full-width grey bar) for what is one
  event with two outcomes. Do not give a new outcome its own shape.
  - Shown for every create / update / delete of a list, a box, a task, a tracker, an appointment
    **and of one article inside a list or a box**. Not for adding an article to an open list: the
    row appears under the finger, and a chip on every mutation is one the user stops reading.
  - `confirmChipOf` is a *capture*, not a `show…(context, …)` call, and that is the point: half the
    callers are deletions that unmount the widget they were tapped in (the row, the row menu, the
    whole detail view), so the overlay and the nav-bar inset have to be taken **before** the write
    and the returned callback invoked after. A `context.mounted` guard would drop exactly the
    confirmations that matter most.
  - **A third state, `ToastKind.pending`, for a write the user would otherwise watch nothing
    happen during.** It carries a spinner where the ring goes, has **no dwell timer**, and stays up
    until the caller settles it — `showPendingChip(context, …)` hands back a `PendingChip` with
    `step` (rewrite the line, keep spinning), `done` / `failed` (swap the mark, start the fade) and
    `dismiss`. The capsule is never rebuilt across those: only its contents change, cross-faded,
    with an `AnimatedSize` around them so the glass grows into the new width. Swapping the *widget*
    would tear down `GlassSurface` and build a second one, and on iOS that is a platform view —
    two of them dissolving in the same place is a flicker, not a transition.
    - **Only for a write that is genuinely slow, and only where its stages are honest.** Creating
      an appointment is the case it was built for: `calendar-write` goes out to Google, Outlook or
      a school's CalDAV server, and then `calendar-events` re-reads every connected calendar,
      because the app stores no events and the new one cannot appear until a proxied read brings it
      back. So the chip names the calendar being written, then says the calendars are being
      refreshed. A container create is now instant on screen (see the backend doc) and must not get
      one — a spinner over a row that is already there is theatre.
    - The stages are the client's own round trips and nothing finer. An event goes into **one**
      calendar, the one the sheet picked; the refresh's fan-out to every provider happens inside
      the Edge Function, in parallel, and comes back as a single answer. Do not write copy that
      counts calendars off — there is no per-calendar progress to report, and inventing one would
      describe a thing the app does not do.
    - On failure the calendar screen's `ref.listen` on `state.error` already puts an error chip up,
      so the pending chip is `dismiss`ed rather than turned red. Two chips saying the same thing is
      one too many.
  - A chip only appears on a `true` from the notifier, which is why the create/update calls return
    `Future<bool>` and every delete returns its snapshot-or-null — `Future<DeletedList?>`,
    `Future<DeletedBox?>`, `Future<DeletedListItem?>`, `Future<DeletedBoxItem?>` (see the undo note
    below). A failed write gets the error chip and no confirmation — never both.
  - **It lives in the root `Overlay`, not in the `ScaffoldMessenger`.** A `SnackBar` is a slot in
    the `Scaffold`, and the `Scaffold` belongs to the shell route — so any sheet on top of it
    covers the chip and dims what is left behind its scrim. "Liste zum Termin erstellen" was
    exactly that: the create sheet pops, the event sheet is still up, and the confirmation was
    drawn where nobody could see it. An entry in the root overlay outranks every route, which is
    also what lets a delete *inside* a sheet offer its undo. `_ToastLayer` owns the entrance, the
    dwell timer and the fade back out; `_ToastHandle` is what an outsider can do to a chip (take it
    down), and a second chip dismisses the first rather than stacking on it.
  - **It is also the one text in the app with no `Material` over it**, and Flutter's fallback for
    that case is its debug style — yellow, double-underlined. The chip's `AppText.buttonSmall` sets
    size, weight and colour but not `decoration`, so the underline came through under the message
    and under "Rückgängig". `_ToastLayer` declares a `DefaultTextStyle` with
    `decoration: TextDecoration.none` around the whole entry; don't patch a new one at the `Text`.
  - The chip's own position is computed rather than delegated, and it has three answers: just above
    the keyboard while one is up; `navBarTop(…) + 14` while the nav bar is on screen; and **down at
    the home indicator while it isn't** — a sheet or a pushed page covers the shell. The last is read
    live off `NavBarState.onScreen`, which the shell publishes from `occludedByRoute`, because the
    chip is ordered with a sheet up and often shown after it has closed. Parked above a bar that
    wasn't there, it hung mid-page over the buttons the next delete needed.
- **Undo lives on the delete chip, and it is a re-insert.** `restoreList` / `restoreBox` /
  `restoreTask` / `restoreEvent` / `restoreItem` (one on each of the list and box notifiers)
  recreate what was deleted from the snapshot the delete handed back — items, done state, audience
  and position included. The **ids do not come back**: a `share_links` row handed to somebody
  outside the household pointed at the old one and stays dead, which is the honest price of an undo
  that isn't a soft-delete column. `restoreEvent` is the cheap one — `_write(EventDraft.of(event))`
  already routes an own event to `public.events` and a provider's back out through
  `calendar-write`.
  - **The item restores copy nothing.** A deleted *container* has to copy its pictures, because
    every object is filed under the container's id and the restore gets a new one. A deleted
    article or box item leaves its list or box standing, so the objects are still where they were
    and still owned by something that can read them: undo only re-points fresh
    `list_item_attachments` rows / a fresh `photo_path` at the same paths, and the signed URLs
    already in hand still name the same object.
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
- **A day's blocks arriving** (`_HourGridState`, `day_timeline.dart`): one `AnimationController`
  per day (460ms) with each block taking its own slice of it — fade plus a 10pt rise, staggered by
  index and capped so a crowded day is still assembled inside half a second. A single controller
  rather than a `TweenAnimationBuilder` per block, because the stagger has to be computed against
  one clock; `AnimatedBuilder` takes the block as its `child` so the stagger animates a transform
  and never rebuilds the block underneath it.
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
  **`inPlace: true` swaps the last gesture for a tile**: the same feedback and the same beat, but
  the thing shrinks ~14% and fades where it stands instead of folding away. Listen's card view
  needs it because a grid cell is a fixed box — there is nothing above and below to close up
  behind the tile, so folding only clipped the picture from the bottom while its hole stayed
  put.
- **Anchored menus** (`showAnchoredMenu`, and the Kalender filter's own `_AllCalendarsPickerRoute`): a
  custom `PopupRoute` that lays the finished panel out beside its anchor and fade +
  `ScaleTransition`s it out of the nearest corner (200ms in / 140ms out). Don't use `showMenu` —
  it grows the panel's height while staggering each item's fade, which over dense content reads as
  a smeared, half-drawn slab. Scale the **panel**, inside `buildPage`, not the page in
  `buildTransitions`: that layer is screen-sized, so scaling it slides the panel across the
  display instead of growing it out of its own corner.
- **The `Mehr` shelf** (`more_shelf.dart`): 420ms in / 260ms out on one controller, with each
  button given a later slice of it (`_stagger`) so the column unfolds upward out of the tap and
  winds back down the same way — one window read in both directions, not two sequences to keep in
  step. Going in, the rise overshoots and settles (`Curves.easeOutBack`); coming out it falls back
  the way it came (`easeInCubic`), because an overshoot on the way to nowhere is a wobble. The
  label capsule unfurls **leftward from behind its circle** a third of the way through that button's
  own arrival — an animated `Align.widthFactor` inside a `ClipRect`, so the circle never moves.
  - **Both of those stay in the tree once the label is out; the clip only switches to `Clip.none`.**
    Returning the bare capsule at full reveal is the obvious saving and it flashes, every time, at
    the end of the open: the capsule is a real `UIGlassEffect` platform view, so changing the
    widgets above it moves its element and the view is torn down and recreated, showing the screen
    behind it for a frame before it is covered again. **The rule generalises** — never swap the
    widgets wrapping a platform view as an animation lands. Turn the effect off in place instead.
  - It never **scales**: the buttons are `UIGlassEffect` platform views and scaling one smears it.
    Rise, fade and clip are all the entrance there is, which is why the rise is a generous 30pt.
  - It goes `Offstage` at zero rather than leaving the tree, so the platform views survive between
    openings — but the controller still **starts at zero and is driven forward**, including the
    first time, when the shell mounts the widget and opens it in the same breath. Seeding the
    controller at 1 for that case is what made the first tap of a session snap the buttons on with
    no animation while every tap after it animated, which reads as a dropped frame.
- **One door giving way to the next** (`auth_screen.dart`, and the tour's own switcher): the
  sign-in flow is three steps on one `Scaffold` — front door, form, code — swapped by an
  `AnimatedSwitcher` keyed on which door, with the tour's exact transition (260ms, fade plus a 3%
  rise).

- **The code being accepted** (`_CodeBoxes`, `auth_screen.dart`): one 1200ms controller cut into
  overlapping intervals — the rest of the page fades out, the six boxes slide into one another,
  what is left rounds off into the confirmation mark's own circle, and **`DrawnCheck` draws itself
  over the last stretch**. The ending is not a mark of its own: it is the same `DrawnCheck` at the
  same `drawnCheckSize`, over `drawnCheckDuration`, that every sheet and page confirms with, played
  on this screen's longer clock because the boxes merging into it is a longer gesture than the mark
  is. That is what `drawnCheckDuration` and the intervals inside `DrawnCheck` are public for; a
  second set of numbers here would be a second mark.
  - **The boxes are never swapped for a single shape**: every one travels to the same rectangle and
    then rounds together, so there is nothing to cross-fade. Their fill is opaque while they
    travel, or six translucent boxes sliding through each other would darken as they met — and it
    is gone by the time the ring closes, because the mark paints its own 8% wash and two of them
    make one too strong. Both the fill and the border drop their *own* alpha rather than lerping
    toward `Colors.transparent`, which is transparent **black** and drags a grey through the fade.
  - The border is handed over to the ring rather than fading first: the arc sweeps round the same
    circle the border was drawn on, so it reads as the outline being re-drawn by a pen.
  - It only works because `AuthStatus.codeAccepted` holds the screen: the session exists by then,
    and without the hold `_RootGate` would swap the shell in on the frame the animation started.
    `codeAcceptedHold` is the longer of the two numbers on purpose, so the finished mark stands
    still for a beat — and `_RootGate` watches `familyProvider` during it, so the household fetch
    and the animation spend the same second.

- **Deliberate exception**: the week view's day strip has no transition of its own — the user
  asked for standard scrolling over week-at-a-time paging. Its only motion is `_revealDate`'s
  `animateTo` (420ms, `Curves.easeOutCubic`) when something *else* moves the strip.
