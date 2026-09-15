import 'package:flutter/material.dart';

/// Design tokens from the Aporah handoff (design_handoff_aporah_flutter/README.md).
///
/// ## Dark mode
///
/// The handoff only ever specified the light palette, so the dark one is
/// derived here rather than handed over: same hues and the same *relationships*
/// between tokens (screen behind card behind subtle fill), re-anchored onto a
/// dark base. Two rules kept it from turning muddy:
///
/// - **Lift the surfaces, don't just invert them.** iOS dark UIs separate
///   layers by lightness, not by shadow — shadows barely read on a dark
///   background. So `screenBg` < `surface` < `surfaceAlt` in lightness, the
///   reverse of the light palette's ordering.
/// - **Desaturate the accents you sit text on, brighten the ones you don't.**
///   The light palette's source/brand colours are tuned against white; at the
///   same luminance on a dark card they vibrate. The dark set lightens them
///   toward pastel so they stay identifiable as "the Outlook one" without
///   glowing.
///
/// [AppColors] resolves against whichever [AppPalette] is currently installed —
/// see the class doc there for why the tokens are getters and what that costs.
class AppPalette {
  final Brightness brightness;

  // Core
  final Color accent;
  final Color ink;
  final Color inkSecondary;
  final Color muted;
  final Color mutedLight;

  /// Subtitle / secondary body grey. Sits between [inkSecondary] and [muted];
  /// it exists because the screens had accumulated four near-identical
  /// hardcoded greys (#5C6570, #6B7280, #4A4A4A, #3A4250) for exactly this
  /// role, none of which could follow a palette.
  final Color inkTertiary;

  // Surfaces, ordered screen -> card -> subtle fill
  final Color surface;
  final Color surfaceAlt;
  final Color screenBg;

  // Separators
  final Color divider;
  final Color hairline;
  final Color hairline2;

  final Color danger;

  /// Confirmation green (a completed list, a satisfied onboarding check).
  final Color success;

  /// Label colour of a checked-off task/item — what the strike-through fades
  /// the open row's text to, so landing in "Erledigt" isn't a colour jump.
  final Color doneInk;

  /// Lift under the small sliding thumb of a segmented control.
  final List<BoxShadow> shadowThumb;

  // Bottom nav (the Flutter pill; the native iOS bar dresses itself)
  final Color navBar;
  final Color navIconBg;
  final Color navIconFg;

  // "Alle" / "Nur ich" chips
  final Color alleBg;
  final Color alleFg;
  final Color nurIchBg;
  final Color nurIchFg;

  // Calendar source colours
  final Color srcOutlook;
  final Color srcAbfall;
  final Color srcIserv;
  final Color srcGoogle;

  // List brand glows
  final Color brandRewe;
  final Color brandDm;
  final Color brandToom;
  final Color brandIkea;

  /// Tint the Flutter-drawn glass approximation fills itself with, and the
  /// strength of its specular highlight / rim. On dark the highlight has to
  /// come *way* down: the same 45% white that reads as a soft sheen over a
  /// light backdrop reads as a grey fog over a dark one.
  ///
  /// **A near-opaque tone of the surface, never a neutral veil.** It used to be
  /// ink at 15% on light, on the theory that a translucent grey over whatever
  /// is behind it is what glass does. It isn't: the real material lightens what
  /// it covers, so a darkening veil turned every glass control into a grey disc
  /// the moment the approximation was used — which on iOS is every time a sheet
  /// or a full screen opens over one (see `occludedByRoute`). Each caller had been
  /// working around it by passing the nav pill's light tint by hand, so this is
  /// now that tone, and there is nothing left to pass.
  final Color glassFallbackTint;
  final Color glassSpecular;
  final Color glassRim;

  /// The colour `FrostedHeaderBackground` washes a collapsing header with.
  final Color frost;

  /// The near-opaque vibrant material an anchored menu is drawn on, plus its
  /// hairline separator. Deliberately *not* glass — see `anchored_menu.dart`.
  final Color menuSurface;
  final Color menuSeparator;

  /// Backing tile for a third-party brand mark (calendar providers, shop
  /// logos). **White in both palettes, deliberately**: these are full-colour
  /// logos drawn for a light background, and several go unreadable on a dark
  /// circle. iOS does the same for app icons in dark mode.
  final Color brandTile;

  /// What is drawn *on* [brandTile] when there is no logo to draw — a shop's
  /// initials, a category's glyph. **Dark in both palettes, for the same reason
  /// the tile is white in both**: the tile does not follow the theme, so
  /// anything set on it cannot either, and `ink` on dark is a pale grey that
  /// disappears against it.
  final Color brandTileInk;

  /// Dimming behind a modal sheet.
  final Color scrim;

  /// The sheet's grab handle, and the unchecked ring in `check_off.dart`.
  final Color grabHandle;
  final Color idleRing;

  /// Day-number colours in `DaySelectorCircle` for a normal and a holiday day.
  final Color dayNumber;
  final Color holidayNumber;

  /// Avatar tone pairs, in the order `AppTones.list` exposes them.
  final List<Tone> tones;

  /// Chart colours for the Spend page's category ring and its legend, in the
  /// order `AppSpendColors` hands them out — one per `SpendCategory`, then the
  /// grey.
  ///
  /// **One each, because the assignment is by the category's own position and
  /// not by its rank this month.** That is what keeps a category the same
  /// colour when two stretches are compared, and it is also why a short palette
  /// could not be folded: with eight slots the six categories past the end all
  /// came out the same grey, so a ring showing Wohnen, Elektronik and Transport
  /// drew three identical arcs and the hole was the only way to tell them
  /// apart. A colour that is shared is not a colour.
  ///
  /// Only ever four of them are on screen at once — the ring folds everything
  /// past the fourth into the grey — so these do not have to survive being
  /// read as a thirteen-way legend. They have to survive being read four at a
  /// time beside a name.
  ///
  /// Hues are ordered to stay apart for the commonest colour-vision
  /// deficiencies: blue, amber and teal carry the three biggest slices in a
  /// typical household month, and no two neighbours here differ in red-green
  /// alone.
  final List<Color> spendSlices;

  /// Forecast-card skies, in the order `AppSkies` names them.
  final List<WeatherSkin> skies;

  /// Card / nav / sheet shadows. On dark these are near-invisible by design —
  /// separation comes from the surface lift above — but a little depth under
  /// floating controls still helps them read as floating.
  final List<BoxShadow> shadowCard;
  final List<BoxShadow> shadowNavBar;
  final List<BoxShadow> shadowFloatingPill;
  final List<BoxShadow> shadowSheet;

  /// Lift under a circular glass icon button, and under an anchored menu.
  final List<BoxShadow> shadowGlassButton;
  final List<BoxShadow> shadowMenu;

  const AppPalette({
    required this.brightness,
    required this.accent,
    required this.ink,
    required this.inkSecondary,
    required this.muted,
    required this.mutedLight,
    required this.inkTertiary,
    required this.surface,
    required this.surfaceAlt,
    required this.screenBg,
    required this.divider,
    required this.hairline,
    required this.hairline2,
    required this.danger,
    required this.success,
    required this.doneInk,
    required this.shadowThumb,
    required this.navBar,
    required this.navIconBg,
    required this.navIconFg,
    required this.alleBg,
    required this.alleFg,
    required this.nurIchBg,
    required this.nurIchFg,
    required this.srcOutlook,
    required this.srcAbfall,
    required this.srcIserv,
    required this.srcGoogle,
    required this.brandRewe,
    required this.brandDm,
    required this.brandToom,
    required this.brandIkea,
    required this.glassFallbackTint,
    required this.glassSpecular,
    required this.glassRim,
    required this.frost,
    required this.menuSurface,
    required this.menuSeparator,
    required this.brandTile,
    required this.brandTileInk,
    required this.scrim,
    required this.grabHandle,
    required this.idleRing,
    required this.dayNumber,
    required this.holidayNumber,
    required this.tones,
    required this.spendSlices,
    required this.skies,
    required this.shadowCard,
    required this.shadowNavBar,
    required this.shadowFloatingPill,
    required this.shadowSheet,
    required this.shadowGlassButton,
    required this.shadowMenu,
  });

  bool get isDark => brightness == Brightness.dark;

  /// The handoff palette, unchanged.
  static const light = AppPalette(
    brightness: Brightness.light,
    accent: Color(0xFF1668FF),
    ink: Color(0xFF0D0D0D),
    inkSecondary: Color(0xFF3D4C5E),
    muted: Color(0xFF8A94A6),
    mutedLight: Color(0xFFB4BAC5),
    inkTertiary: Color(0xFF5C6570),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF4F6FA),
    screenBg: Color(0xFFF7F8FA),
    divider: Color(0xFFF1F3F7),
    hairline: Color(0xFFE7EBF3),
    hairline2: Color(0xFFE4E7EC),
    danger: Color(0xFFE11D48),
    success: Color(0xFF16A34A),
    doneInk: Color(0xFFA6ADBA),
    shadowThumb: [BoxShadow(color: Color(0x29112A2B), blurRadius: 4, offset: Offset(0, 1))],
    navBar: Color(0xFF191A1E),
    navIconBg: Color(0xFF2A2C31),
    navIconFg: Color(0xFFC9CBD1),
    alleBg: Color(0xFFE8EEF9),
    alleFg: Color(0xFF2F4A78),
    nurIchBg: Color(0xFFEDEFF3),
    nurIchFg: Color(0xFF4B5563),
    srcOutlook: Color(0xFF0F6CBD),
    srcAbfall: Color(0xFF16A34A),
    srcIserv: Color(0xFF7C3AED),
    srcGoogle: Color(0xFFEA4335),
    brandRewe: Color(0xFFCC071E),
    brandDm: Color(0xFFE4051E),
    brandToom: Color(0xFF009036),
    brandIkea: Color(0xFFFFDB00),
    glassFallbackTint: Color(0xCCF3F4F7),
    glassSpecular: Color(0x73FFFFFF),
    glassRim: Color(0x8CFFFFFF),
    frost: Color(0xFFFFFFFF),
    menuSurface: Color(0xFAFBFBFD),
    menuSeparator: Color(0x1F3C3C43),
    brandTile: Color(0xFFFFFFFF),
    brandTileInk: Color(0xFF0D0D0D),
    scrim: Color(0x760B1220),
    grabHandle: Color(0xFFD7DBE3),
    idleRing: Color(0xFFC7CBD3),
    dayNumber: Color(0xFF2A2A2A),
    holidayNumber: Color(0xFF2A3550),
    tones: [
      Tone(Color(0xFFF5ECD9), Color(0xFF7B5B3A)),
      Tone(Color(0xFFF3E8FF), Color(0xFF6B21A8)),
      Tone(Color(0xFFDBEAFE), Color(0xFF1E40AF)),
      Tone(Color(0xFFFEF9C3), Color(0xFF854D0E)),
      Tone(Color(0xFFFFE4E6), Color(0xFF9F1239)),
    ],
    // Saturated enough to hold a 12-point ring segment against a white card
    // without going neon in a legend dot beside 15-point text.
    spendSlices: [
      Color(0xFF3B6FD4), Color(0xFFD98A1F), Color(0xFF1E9E8A), Color(0xFFD6456F),
      Color(0xFF7C55D4), Color(0xFF5A9E36), Color(0xFFE2653C), Color(0xFF1B8FB5),
      Color(0xFF4B54C6), Color(0xFFB2479E), Color(0xFF8A6A4B), Color(0xFF8C8A22),
      Color(0xFF2E8F5B), Color(0xFF6B7A90),
    ],
    // Pale on light, so the icon drawn on top keeps its own colours and the
    // temperature keeps a text-weight contrast — see [WeatherSkin].
    skies: [
      WeatherSkin(Color(0xFFFFF1D2), Color(0xFFFFE0A5), Color(0xFF8A5A11)),
      WeatherSkin(Color(0xFFE7EAFA), Color(0xFFCED3F0), Color(0xFF3B3F73)),
      WeatherSkin(Color(0xFFFEF3DC), Color(0xFFDFEAFA), Color(0xFF5D5730)),
      WeatherSkin(Color(0xFFE9EBF8), Color(0xFFD4D9EE), Color(0xFF3E4270)),
      // Deeper than they first look like they want to be: these four carry the
      // palest icons in the set (a white overcast cloud, a white snow cloud),
      // and on a near-white wash the drawing simply vanishes.
      WeatherSkin(Color(0xFFE7EDF5), Color(0xFFCFD9E6), Color(0xFF46536A)),
      WeatherSkin(Color(0xFFEAEDF1), Color(0xFFD3D8DF), Color(0xFF4C535E)),
      WeatherSkin(Color(0xFFE2EDF8), Color(0xFFC8DCF0), Color(0xFF2F5680)),
      WeatherSkin(Color(0xFFDFEBF9), Color(0xFFC0D8F0), Color(0xFF1E4D80)),
      WeatherSkin(Color(0xFFE6F2FC), Color(0xFFC9E1F5), Color(0xFF2C5A7A)),
      WeatherSkin(Color(0xFFE8E7F5), Color(0xFFD0CEE9), Color(0xFF433F7A)),
    ],
    // **Two layers, because on Home a card is white on white.** That screen's
    // page is `surface`, not `screenBg` — the day card inverts the usual
    // ordering and is the grey object — so the sections under its bottom edge
    // had nothing but a single 6% blur between them and the paper, and read as
    // rows floating under a heading rather than as cards. The tight layer is the
    // contact edge that gives the card a bottom; the wide one is the lift.
    // Together they carry a white card on white, which is the hardest case the
    // token has to survive, and no border is needed: a rim around a card whose
    // rows are already split by hairlines reads as a table rather than an
    // object.
    //
    // **The negative spread is what stops the corners looking square**, and it
    // is not a nicety. At spread 0 the lift's rounded rect is exactly the
    // card's, so a 20 blur against a 6 offset put a grey pool roughly twelve
    // points out on *every* side — above the card as much as below it. The
    // card's own corner then cuts a quarter circle out of a much larger, much
    // blurrier rounded rect, and what is left standing beside each corner is a
    // right angle: you see a square shadow behind a round card and cannot say
    // why. Pulling the shadow in by the offset tucks it under the card, so the
    // top edge keeps only the contact layer, and shrinking its rect also
    // *tightens* its own corners relative to its size, which is the other half
    // of the roundness. Every card in the app wears this, so it was visible on
    // Kalender's event cards and Listen's Vorhaben card at the same time.
    shadowCard: [
      BoxShadow(color: Color(0x0D112A2B), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x1A112A2B), blurRadius: 20, offset: Offset(0, 6), spreadRadius: -6),
    ],
    shadowNavBar: [BoxShadow(color: Color(0x4D0A0F1E), blurRadius: 30, offset: Offset(0, 14))],
    shadowFloatingPill: [BoxShadow(color: Color(0x1A0A0F1E), blurRadius: 14, offset: Offset(0, 4))],
    shadowSheet: [BoxShadow(color: Color(0x3D0A1428), blurRadius: 40, offset: Offset(0, -14))],
    shadowGlassButton: [BoxShadow(color: Color(0x1F0A1428), blurRadius: 8, offset: Offset(0, 2))],
    shadowMenu: [
      BoxShadow(color: Color(0x1F0A1428), blurRadius: 40, offset: Offset(0, 12)),
      BoxShadow(color: Color(0x140A1428), blurRadius: 8, offset: Offset(0, 2)),
    ],
  );

  /// Derived from [light] — see the class doc for the two rules it follows.
  static const dark = AppPalette(
    brightness: Brightness.dark,
    // #1668FF is heavy against a dark surface; this is the same hue lifted
    // until it reads as the same "Aporah blue" at dark-mode contrast.
    accent: Color(0xFF4C8DFF),
    ink: Color(0xFFF2F4F8),
    inkSecondary: Color(0xFFB9C2D0),
    muted: Color(0xFF8A94A6),
    mutedLight: Color(0xFF646E7E),
    inkTertiary: Color(0xFFAEB6C2),
    // Lifted, not inverted: screen < card < subtle fill.
    surface: Color(0xFF181A1F),
    surfaceAlt: Color(0xFF23262D),
    screenBg: Color(0xFF0E0F13),
    divider: Color(0xFF232630),
    hairline: Color(0xFF2A2E38),
    hairline2: Color(0xFF31353F),
    danger: Color(0xFFFB7185),
    success: Color(0xFF4ADE80),
    doneInk: Color(0xFF6E7686),
    shadowThumb: [BoxShadow(color: Color(0x66000000), blurRadius: 4, offset: Offset(0, 1))],
    // The light palette's near-black bar would vanish into `screenBg`, so the
    // dark bar goes *lighter* than its background instead of darker.
    navBar: Color(0xFF24262C),
    navIconBg: Color(0xFF34373E),
    navIconFg: Color(0xFFD6D8DE),
    alleBg: Color(0xFF1E2A42),
    alleFg: Color(0xFFA8C4F0),
    nurIchBg: Color(0xFF262A31),
    nurIchFg: Color(0xFFC0C6D0),
    srcOutlook: Color(0xFF4DA3E8),
    srcAbfall: Color(0xFF4ADE80),
    srcIserv: Color(0xFFA78BFA),
    srcGoogle: Color(0xFFF87171),
    // Brand marks keep their hue — a Rewe red that isn't Rewe red is worse
    // than a slightly dark one — but they're only ever used as a soft glow
    // behind a header, never as a text colour.
    brandRewe: Color(0xFFE8324A),
    brandDm: Color(0xFFF0334A),
    brandToom: Color(0xFF16B45A),
    brandIkea: Color(0xFFFFDB00),
    glassFallbackTint: Color(0xCC23262D),
    glassSpecular: Color(0x24FFFFFF),
    glassRim: Color(0x2EFFFFFF),
    frost: Color(0xFF14161B),
    menuSurface: Color(0xFA24272E),
    menuSeparator: Color(0x33FFFFFF),
    brandTile: Color(0xFFFFFFFF),
    brandTileInk: Color(0xFF0D0D0D),
    scrim: Color(0x99000000),
    grabHandle: Color(0xFF3A3E48),
    idleRing: Color(0xFF4A4F5A),
    dayNumber: Color(0xFFE6E9EF),
    holidayNumber: Color(0xFFAFC0E0),
    tones: [
      Tone(Color(0xFF3A3226), Color(0xFFE3C79B)),
      Tone(Color(0xFF332A44), Color(0xFFD8B4FE)),
      Tone(Color(0xFF1E2A44), Color(0xFF93C5FD)),
      Tone(Color(0xFF3A3520), Color(0xFFFDE68A)),
      Tone(Color(0xFF3D2830), Color(0xFFFDA4AF)),
    ],
    // The same eight hues lifted and slightly desaturated. The light set drawn
    // on a dark card reads as holes punched in it rather than as a chart.
    spendSlices: [
      Color(0xFF7BA3F0), Color(0xFFF0B45E), Color(0xFF55C7B2), Color(0xFFF07FA0),
      Color(0xFFB693F5), Color(0xFF92CC6E), Color(0xFFF79470), Color(0xFF5FBFDF),
      Color(0xFF8E94F0), Color(0xFFE289CE), Color(0xFFC4A183), Color(0xFFC6C45F),
      Color(0xFF62C48D), Color(0xFF9AA9BC),
    ],
    // Same hues at the surface lift the rest of the dark palette sits at, which
    // is what keeps a sunny card from glowing out of a night-time sheet. The
    // icons are pale by design and gain contrast here rather than losing it.
    skies: [
      WeatherSkin(Color(0xFF3A3019), Color(0xFF4A3B1F), Color(0xFFF2D49B)),
      WeatherSkin(Color(0xFF1E2140), Color(0xFF272C52), Color(0xFFC3C8F0)),
      // Warm at the sun end, cool at the cloud end — but barely, because a
      // brown top-left corner on a dark sheet reads as dirt rather than as sun.
      WeatherSkin(Color(0xFF2F2C24), Color(0xFF2E3440), Color(0xFFDFDBCD)),
      WeatherSkin(Color(0xFF1F2338), Color(0xFF282D45), Color(0xFFC6CCE4)),
      WeatherSkin(Color(0xFF262A32), Color(0xFF2F3540), Color(0xFFCBD3E0)),
      WeatherSkin(Color(0xFF272A2F), Color(0xFF31353B), Color(0xFFCED3DA)),
      WeatherSkin(Color(0xFF1F2A38), Color(0xFF273545), Color(0xFFB6CFE8)),
      WeatherSkin(Color(0xFF1B2B3E), Color(0xFF23374E), Color(0xFFA9CBEC)),
      WeatherSkin(Color(0xFF202D3A), Color(0xFF293A4A), Color(0xFFC2DCF2)),
      WeatherSkin(Color(0xFF262340), Color(0xFF2E2B4D), Color(0xFFC6C1EE)),
    ],
    // One layer here — on dark a card is lighter than its page, so the lift is
    // doing less work — with the same negative spread as light, for the same
    // reason: see the note over the light palette's.
    shadowCard: [
      BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 2), spreadRadius: -3),
    ],
    shadowNavBar: [BoxShadow(color: Color(0x8C000000), blurRadius: 30, offset: Offset(0, 14))],
    shadowFloatingPill: [BoxShadow(color: Color(0x59000000), blurRadius: 14, offset: Offset(0, 4))],
    shadowSheet: [BoxShadow(color: Color(0x99000000), blurRadius: 40, offset: Offset(0, -14))],
    shadowGlassButton: [BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 2))],
    shadowMenu: [
      BoxShadow(color: Color(0x8C000000), blurRadius: 40, offset: Offset(0, 12)),
      BoxShadow(color: Color(0x4D000000), blurRadius: 8, offset: Offset(0, 2)),
    ],
  );
}

/// The design tokens, resolved against the currently installed [AppPalette].
///
/// These are **getters over a mutable global**, not constants, which is a
/// deliberate trade. The alternative — a `ThemeExtension` read through
/// `Theme.of(context)` — is the idiomatic Flutter answer, but it needs a
/// `BuildContext` at all ~280 call sites, including the ones in plain helper
/// functions and static text styles that have none. Since the app only ever
/// shows one theme at a time, a global costs nothing real.
///
/// **The one thing it costs: `const` widgets no longer rebuild on a theme
/// flip.** A `const CardDivider()` is canonicalised, so its element is skipped
/// when its parent rebuilds, and it would keep painting the old palette's
/// hairline forever. The rule that falls out of that, and the reason several
/// call sites in this app look like they're missing a `const`:
///
/// > **Never `const`-construct a widget whose `build` reads [AppColors],
/// > [AppText], [AppTones] or [AppShadows]** — directly or through a child.
/// > The constructors stay `const` (`prefer_const_constructors_in_immutables`
/// > wants them to be, and nothing stops a *caller* from opting out); it's the
/// > call sites that must not use it.
///
/// Passing a token *as an argument* is safe and self-enforcing — the compiler
/// already rejects `const Foo(color: AppColors.ink)` because the getter isn't a
/// constant. Only widgets that read tokens *inside* `build` need the care.
class AppColors {
  AppColors._();

  /// The installed palette. Set by `AporahApp` from the Settings toggle before
  /// the screen tree builds; nothing else should write it.
  static AppPalette palette = AppPalette.light;

  static AppPalette get _palette => palette;

  static bool get isDark => _palette.isDark;

  static Color get accent => _palette.accent;
  static Color get ink => _palette.ink;
  static Color get inkSecondary => _palette.inkSecondary;
  static Color get muted => _palette.muted;
  static Color get mutedLight => _palette.mutedLight;
  static Color get inkTertiary => _palette.inkTertiary;
  static Color get surface => _palette.surface;
  static Color get surfaceAlt => _palette.surfaceAlt;
  static Color get screenBg => _palette.screenBg;

  /// A card drawn on a page that is itself [surface] — which on Home is the
  /// whole page below the day card, because that screen inverts the usual
  /// ordering and gives the *day* the grey.
  ///
  /// On light this is still white, and [AppShadows.card] is what separates it
  /// from the paper. On dark a shadow separates nothing, so the card takes the
  /// lift instead, exactly as the palette's dark rule says: screen < card <
  /// fill, one step at a time.
  static Color get cardOnSurface => isDark ? surfaceAlt : surface;

  /// The row separator inside a [cardOnSurface]. [divider] is a tone of the
  /// card it normally sits in; on dark that card is a step lighter, and the
  /// normal one is then the same colour as the card it is meant to divide.
  static Color get cardOnSurfaceDivider => isDark ? hairline2 : divider;
  static Color get divider => _palette.divider;
  static Color get hairline => _palette.hairline;
  static Color get hairline2 => _palette.hairline2;
  static Color get danger => _palette.danger;
  static Color get success => _palette.success;
  static Color get doneInk => _palette.doneInk;
  static Color get navBar => _palette.navBar;
  static Color get navIconBg => _palette.navIconBg;
  static Color get navIconFg => _palette.navIconFg;
  static Color get alleBg => _palette.alleBg;
  static Color get alleFg => _palette.alleFg;
  static Color get nurIchBg => _palette.nurIchBg;
  static Color get nurIchFg => _palette.nurIchFg;
  static Color get srcOutlook => _palette.srcOutlook;
  static Color get srcAbfall => _palette.srcAbfall;
  static Color get srcIserv => _palette.srcIserv;
  static Color get srcGoogle => _palette.srcGoogle;
  static Color get brandRewe => _palette.brandRewe;
  static Color get brandDm => _palette.brandDm;
  static Color get brandToom => _palette.brandToom;
  static Color get brandIkea => _palette.brandIkea;
  static Color get glassFallbackTint => _palette.glassFallbackTint;
  static Color get glassSpecular => _palette.glassSpecular;
  static Color get glassRim => _palette.glassRim;
  static Color get frost => _palette.frost;
  static Color get menuSurface => _palette.menuSurface;
  static Color get menuSeparator => _palette.menuSeparator;
  static Color get brandTile => _palette.brandTile;
  static Color get brandTileInk => _palette.brandTileInk;
  static Color get scrim => _palette.scrim;
  static Color get grabHandle => _palette.grabHandle;
  static Color get idleRing => _palette.idleRing;
  static Color get dayNumber => _palette.dayNumber;
  static Color get holidayNumber => _palette.holidayNumber;
}

/// Avatar tone pair.
class Tone {
  final Color bg;
  final Color fg;
  const Tone(this.bg, this.fg);
}

class AppTones {
  AppTones._();

  static Tone get sand => AppColors.palette.tones[0];
  static Tone get purple => AppColors.palette.tones[1];
  static Tone get blue => AppColors.palette.tones[2];
  static Tone get yellow => AppColors.palette.tones[3];
  static Tone get rose => AppColors.palette.tones[4];

  static List<Tone> get list => AppColors.palette.tones;
}

/// The Spend page's chart colours, named the way [AppTones] names the avatar
/// tones and for the same reason: a widget asks for a colour by what it is for,
/// never by a literal.
///
/// [forCategory] is the one entry point. It maps a category onto a fixed slot,
/// so Lebensmittel is the same blue in September as it was in August — a chart
/// whose colours are assigned by this month's ranking makes two months
/// impossible to compare, which is most of what anybody does with this page.
/// The last slot is deliberately the grey one, and that is where "Sonstige"
/// lands.
/// The colours a household may give one of its calendars.
///
/// **The one colour list in the app that is not per-theme, and that is the
/// point.** Every other palette here swaps with light and dark because it is
/// ours to choose; a calendar's colour is the *account's*, and Google's does not
/// change when the phone goes dark. These sit in the same slot as one, so they
/// cannot either — a household that recognises a calendar by its colour would
/// otherwise stop recognising it at sunset. Mid-lightness and mid-saturation
/// precisely so one set holds against a white card and a near-black one.
///
/// Twelve, and deliberately including a grey: the day grid draws a chip at low
/// alpha over a grey card, so a grey calendar really is the hardest one to see —
/// but "you may not pick that" is a worse answer than letting a family file the
/// calendar they barely use in the colour that stays out of the way.
class AppCalendarColors {
  AppCalendarColors._();

  static const choices = <Color>[
    Color(0xFF4A7FDC), Color(0xFF2D9CDB), Color(0xFF1FA894), Color(0xFF63A83F),
    Color(0xFFC9B227), Color(0xFFE0912A), Color(0xFFE2653C), Color(0xFFDC4F78),
    Color(0xFFB0479E), Color(0xFF8A63DE), Color(0xFF8A6A4B), Color(0xFF7C8794),
  ];
}

class AppSpendColors {
  AppSpendColors._();

  static List<Color> get list => AppColors.palette.spendSlices;

  /// The neutral slot, for the folded "everything else" slice and for a
  /// category with nothing to show.
  static Color get rest => list.last;

  /// A stable colour per category, by the category's own position in
  /// `SpendCategory` rather than by its rank this month — so a slice keeps its
  /// colour when two stretches are compared.
  ///
  /// The list is one longer than the enum: the last slot is the grey, which
  /// `other` lands on by position and the folded "Sonstige" arc takes on
  /// purpose. An index past the end is a category the palette has not been
  /// told about, and grey is the honest answer to that too.
  static Color forCategory(int categoryIndex) {
    final coloured = list.length - 1;
    return categoryIndex >= 0 && categoryIndex < coloured ? list[categoryIndex] : rest;
  }
}

/// The sky a forecast card wears: a two-stop wash plus the ink that reads on it.
///
/// **Deliberately pale on light, not a dark weather widget.** The obvious design
/// is white text on a deep sky, and it fights the icons: Meteocons' clouds are
/// near-white, so a background dark enough for white text is a background the
/// cloud disappears into. Washing the card in the *lightest* end of the
/// condition's own hue keeps the icon full-colour and legible, keeps the
/// temperature at text contrast, and reads as one of this app's cards rather
/// than as something borrowed from a weather app.
///
/// [ink] belongs to the skin rather than coming from [AppColors] because it is
/// the same hue as the wash, deepened — amber on the sunny card, navy on the
/// rainy one. That tie is the whole effect; `AppColors.ink` on all ten would
/// wash out to the same grey card with a slightly different tint.
class WeatherSkin {
  final Color from;
  final Color to;
  final Color ink;

  const WeatherSkin(this.from, this.to, this.ink);

  /// Top-left to bottom-right, matching the light in the icons themselves.
  LinearGradient get gradient =>
      LinearGradient(colors: [from, to], begin: Alignment.topLeft, end: Alignment.bottomRight);
}

/// The ten skies, named — the same shape as [AppTones], and the same reason:
/// the list is positional so it stays readable in the palette, and nothing
/// outside this file should have to know which index is the rainy one.
class AppSkies {
  AppSkies._();

  static WeatherSkin get clearDay => AppColors.palette.skies[0];
  static WeatherSkin get clearNight => AppColors.palette.skies[1];
  static WeatherSkin get partlyCloudyDay => AppColors.palette.skies[2];
  static WeatherSkin get partlyCloudyNight => AppColors.palette.skies[3];
  static WeatherSkin get cloudy => AppColors.palette.skies[4];
  static WeatherSkin get fog => AppColors.palette.skies[5];
  static WeatherSkin get drizzle => AppColors.palette.skies[6];
  static WeatherSkin get rain => AppColors.palette.skies[7];
  static WeatherSkin get snow => AppColors.palette.skies[8];
  static WeatherSkin get storm => AppColors.palette.skies[9];
}

/// tint(hex, amt) -> lerp toward the lightest surface. shade(hex, amt) -> same
/// hue at alpha.
///
/// [tint] produces the pale wash behind a *selected* thing — a filter chip, a
/// live timeline row, the Feiertag swatch — so it has to land at or above the
/// surface it sits on, or the selected state reads as recessed rather than
/// picked out.
///
/// On light that target is plain white: `surface` is already white and
/// `screenBg` a hair below it, so `tint` can't undershoot. On dark the mirror
/// of "white" is **`surfaceAlt`, the lightest surface — not `screenBg`, the
/// darkest**. Aiming at `screenBg` (as this first did) dragged every tinted
/// element below `surfaceAlt`, which inverted the chip row: selected chips came
/// out darker than unselected ones, and the Feiertag dot sank into the page.
Color tint(Color c, double amt) =>
    Color.lerp(c, AppColors.isDark ? AppColors.surfaceAlt : Colors.white, amt)!;

Color shade(Color c, double amt) => c.withValues(alpha: amt);

class AppRadii {
  AppRadii._();

  static const card = 22.0;
  static const cardSmall = 20.0;
  static const sheetTop = 28.0;
  static const iconTile = 13.0;
  static const chip = 20.0;
  static const pill = 24.0;
  static const bar = 999.0;
}

class AppSpacing {
  AppSpacing._();

  static const screenPad = 24.0;
  static const cardPad = 16.0;
  static const rowPadV = 14.0;
  static const rowPadH = 16.0;

  /// The gap between two blocks stacked on a Settings page — card to card, or
  /// card to the action under it. One number, so no page invents its own and
  /// two pages of the same shape stop drifting apart.
  static const blockGap = 14.0;
}

/// **How big a control's glyph is drawn.**
///
/// Every number here is an *em* handed to [AppIcon], and an em is not what
/// lands on screen: a Phosphor glyph carries an invisible full-em box and the
/// drawing fills only 57–86% of it, so `size: 19` puts about 15pt of ink on a
/// button. Lucide, which Phosphor replaced, filled about 88% — which is how the
/// swap shrank every control in the app without a single number changing.
///
/// So these are calibrated against **rendered ink**, measured off the real SF
/// Symbols the system draws beside them, rather than against a design grid:
///
/// | | ink | stroke |
/// |---|---|---|
/// | iOS bar button — SF 17pt, `.large` | 21.0pt | 1.62pt |
/// | Phosphor Regular at [button] | 21.4pt | 1.63pt |
///
/// The `.large` scale step is the part that is easy to miss. `UIBarButtonItem`
/// does not draw its symbol at plain 17pt; it applies `.large` on top, which is
/// about +25%, and the old 19 was calibrated against the unscaled number.
///
/// **Sizing these correctly is also what let the flat weight go back to
/// Regular.** The glyph was too small and Bold was how it was kept from reading
/// as faint; at the right size Bold is 39% heavier than the symbol next to it.
/// The two errors were cancelling. See `_flatFamily` in `app_icons.dart`.
///
/// Only *controls* take these — the glyph you press, which is the same set
/// `AppIcon.flat` covers. An icon that names a thing is duotone, is sized
/// against the text beside it, and uses [AppText.markGlyph] or its own number.
///
/// A glyph beside *micro* type sits below the scale and keeps its own number —
/// `list_screen.dart`'s 11pt link mark is the one that does. Reaching for
/// [inline] there would put the glyph above the words it marks.
class AppGlyph {
  AppGlyph._();

  /// The glyph on a button of its own: a glass icon button, a sheet's X and
  /// check, the "..." at a row's trailing edge. iOS's bar button.
  ///
  /// The "..." is on this tier rather than [row] despite living in a row,
  /// because `dotsThreeVertical` is the narrowest glyph in the set — Phosphor
  /// draws its dots about 30% smaller than SF does at a matched length — and
  /// at a row's tier it comes out as three specks.
  static const button = 26.0;

  /// A control glyph that shares its space with a word of [AppText.rowTitle]'s
  /// size: a segment of a segmented control, the glyph on a pill beside its
  /// label, a sheet's full-width action. Apple's SF 17pt at `.medium`, which is
  /// ~16.5pt of ink.
  static const row = 21.0;

  /// The same, beside *smaller* type — a caption, a count, a delta on a stat.
  /// A glyph that out-measures the word it belongs to stops reading as part of
  /// it.
  static const inline = 17.0;

  /// A disclosure caret at a row's trailing edge. Sized to the system's own
  /// table-row indicator, which is ~12.5pt of chevron.
  static const caret = 18.0;
}


class AppShadows {
  AppShadows._();

  static List<BoxShadow> get card => AppColors.palette.shadowCard;

  static List<BoxShadow> accentGlass(Color accent) => [
    BoxShadow(color: shade(accent, AppColors.isDark ? .34 : .22), blurRadius: 18, offset: const Offset(0, 6)),
  ];

  static List<BoxShadow> get navBar => AppColors.palette.shadowNavBar;

  /// Lift for small floating pills (e.g. the calendar's "Heute" button).
  /// Deliberately much softer than [navBar]: that shadow is sized for a
  /// full-width bar, and under a ~90px pill it reads as a dark blob.
  static List<BoxShadow> get floatingPill => AppColors.palette.shadowFloatingPill;

  static List<BoxShadow> get sheet => AppColors.palette.shadowSheet;

  static List<BoxShadow> get glassButton => AppColors.palette.shadowGlassButton;

  static List<BoxShadow> get menu => AppColors.palette.shadowMenu;

  static List<BoxShadow> get thumb => AppColors.palette.shadowThumb;
}

/// One rung of a scale: the size and weight of a single role.
///
/// Deliberately *not* a `TextStyle`. A scale answers "how big, how heavy" and
/// nothing else — the family, the letter-spacing, the leading and the colour
/// belong to the token, are the same in every scale, and would be three more
/// things to keep in sync across three lists if they lived here.
class TypeStep {
  final double size;
  final FontWeight weight;

  const TypeStep(this.size, this.weight);
}

/// One complete set of sizes for the app's type roles.
///
/// Every size and weight below comes from the [AppTypeScale] in [AppText.scale],
/// exactly as every colour comes from the [AppPalette] in [AppColors.palette].
/// The token still names the role and still owns everything *else* about the
/// style — the family, the letter-spacing, the leading, the colour — so a scale
/// is a short list of sizes rather than a second copy of the type system.
///
/// That indirection exists for one reason: the app is set about one step below
/// the sizes iOS uses for the same roles (a list row is 15 here and 17 in
/// Settings, Mail and Telefon), and finding the right step is something you
/// have to *see*, on a phone, in both languages. Swapping one line here and
/// hot-reloading is how that comparison gets made; see [AppTypeScale.actual]
/// for what the three candidates are.
///
/// | Role | Actual | Plan B | Plan A |
/// |---|---|---|---|
/// | [screenTitle] | 26 w600 | 27 w600 | 28 w600 |
/// | [statValue] | 24 w600 | 25 w600 | 26 w600 |
/// | [detailTitle] | 23 w600 | 23 w600 | 24 w600 |
/// | [cardTitle] | 18 w600 | 18 w600 | 19 w600 |
/// | [sheetTitle] | 17 w600 | 17 w600 | 18 w600 |
/// | [inputTitle] | 17 w500 | 17 w500 | 18 w500 |
/// | [sectionHeading] | 16 w500 | 16 w600 | 17 w600 |
/// | [searchInput] | 16 w300 | 16 w400 | 17 w400 |
/// | [buttonLarge] | 16 w600 | 16 w600 | 17 w600 |
/// | [itemTitle] | 15 w600 | 16 w500 | 17 w500 |
/// | [rowTitle] | 15 w500 | 16 w500 | 17 w500 |
/// | [input] | 15 w400 | 16 w400 | 17 w400 |
/// | [buttonSmall] | 14 w500 | 14 w500 | 15 w500 |
/// | [body] | 14 w300 | 14 w400 | 15 w400 |
/// | [groupHeading] | 13 w600 | 13 w600 | 13 w600 |
/// | [caption] | 13 w500 | 13 w500 | 13 w500 |
/// | [label] | 12.5 w300 | 13 w400 | 13 w400 |
/// | [microLabel] | 11.5 w500 | 12 w500 | 12 w500 |
/// | [AppText.pageTitle] | 19 w600 | 19 w600 | 20 w600 |
/// | [weekdayLetter] | 15 w500 | 14 w500 | 13 w500 |
/// | [dayNumber] | 14 w400 | 16 w600 | 16 w600 |
///
/// ## The three
///
/// - [actual] — what has shipped. A list row is 15pt, every subtitle is 12.5pt
///   at Light, and the week strip's weekday letter (15) is *larger* than the
///   date under it (14).
/// - [planB] — the half step. Row titles to 16, subtitles to 13, and every
///   Light weight lifted to Regular. Chosen so that **nothing around it has to
///   move**: the day circle keeps its 34 points and the month cell its 38, so
///   no band, height budget or header constant is recalculated.
/// - [planA] — the full step, onto the sizes iOS uses for the same roles. Row
///   titles to 17, titles up a step with them so the hierarchy keeps its
///   spacing, and the day circle to 36 so the date outweighs its own label.
///
/// Both plans lift the Light weights identically, so the only variable between
/// them is size. Apple does not set a Light weight below roughly 20pt, because
/// the stroke thins faster than the size drops, and the app had w300 carrying
/// body prose, every row subtitle and the search field.
///
/// ## What a scale may not contain
///
/// Only sizes and weights that some plan actually changes. A number that is the
/// same in all three is not a scale value — it is a constant, and it stays
/// wherever it already lives. The two circle diameters are here because the day
/// number cannot grow inside a circle that cannot, and the week strip's bands
/// are derived from these rather than typed out beside them.
class AppTypeScale {
  final String name;

  // Titles
  final TypeStep screenTitle;
  final TypeStep statValue;
  final TypeStep detailTitle;
  final TypeStep cardTitle;
  final TypeStep sheetTitle;
  final TypeStep sectionHeading;

  // Rows
  final TypeStep itemTitle;
  final TypeStep rowTitle;

  // Inputs
  final TypeStep inputTitle;
  final TypeStep input;
  final TypeStep searchInput;

  // Actions
  final TypeStep buttonLarge;
  final TypeStep buttonSmall;

  // Body & captions
  final TypeStep body;
  final TypeStep groupHeading;
  final TypeStep caption;
  final TypeStep label;
  final TypeStep microLabel;

  /// The name under a glyph in the bottom nav bar.
  ///
  /// **Its own rung, and smaller than [microLabel], because it is a name rather
  /// than a line of text.** Five of them sit in a fixed-height capsule under
  /// five 28pt glyphs, so this is the one label in the app whose size is
  /// decided by the control around it: the glyph says which tab it is and the
  /// word confirms it, which is the opposite of the weighting everywhere else.
  /// It follows UIKit's own tab-bar label, the way [AppBottomNav]'s glyph
  /// follows UIKit's symbol size. Borrowing `microLabel` is what made the
  /// names read as loud as the glyphs they were labelling.
  final TypeStep navLabel;

  /// The title of a *pushed* page's collapsing header at rest — one box, one
  /// list, one tracker. Its own rung because it was a bare `19` in four files,
  /// which on a larger scale would have left a detail header a single point
  /// clear of the rows beneath it.
  final TypeStep pageTitle;

  /// The weekday letter above a day in the week strip.
  ///
  /// **It has its own rung rather than borrowing [rowTitle], which is what it
  /// used to do.** That coupling is why a bigger Settings row would have
  /// dragged the calendar's letter up with it, and it is also how the letter
  /// came to outweigh the date underneath: a row title grew for reasons that
  /// had nothing to do with the calendar, and the day number stayed where it
  /// was. A label must not be heavier than the thing it labels.
  final TypeStep weekdayLetter;

  /// The day number, and the circle it is drawn in — **one rung for both
  /// views**.
  ///
  /// It used to be two, on the grounds that the month grid has more room, and
  /// what that bought was a date that changed size when you moved between Home
  /// and Kalender: 14 in a 34pt circle on one tab, 15 in a 38pt circle on the
  /// other, for the same day of the same week. A day is the same object in both
  /// views and the cells are the same seventh of the same width, so there was
  /// never a second measurement to make — only a second place to forget.
  final TypeStep dayNumber;
  final double dayCircle;

  const AppTypeScale({
    required this.name,
    required this.screenTitle,
    required this.statValue,
    required this.detailTitle,
    required this.cardTitle,
    required this.sheetTitle,
    required this.sectionHeading,
    required this.itemTitle,
    required this.rowTitle,
    required this.inputTitle,
    required this.input,
    required this.searchInput,
    required this.buttonLarge,
    required this.buttonSmall,
    required this.body,
    required this.groupHeading,
    required this.caption,
    required this.label,
    required this.microLabel,
    required this.navLabel,
    required this.pageTitle,
    required this.weekdayLetter,
    required this.dayNumber,
    required this.dayCircle,
  });

  /// What ships today.
  static const actual = AppTypeScale(
    name: 'actual',
    screenTitle: TypeStep(26, FontWeight.w600),
    statValue: TypeStep(24, FontWeight.w600),
    detailTitle: TypeStep(23, FontWeight.w600),
    cardTitle: TypeStep(18, FontWeight.w600),
    sheetTitle: TypeStep(17, FontWeight.w600),
    sectionHeading: TypeStep(16, FontWeight.w500),
    itemTitle: TypeStep(15, FontWeight.w600),
    rowTitle: TypeStep(15, FontWeight.w500),
    inputTitle: TypeStep(17, FontWeight.w500),
    input: TypeStep(15, FontWeight.w400),
    searchInput: TypeStep(16, FontWeight.w300),
    buttonLarge: TypeStep(16, FontWeight.w600),
    buttonSmall: TypeStep(14, FontWeight.w500),
    body: TypeStep(14, FontWeight.w300),
    groupHeading: TypeStep(13, FontWeight.w600),
    caption: TypeStep(13, FontWeight.w500),
    label: TypeStep(12.5, FontWeight.w300),
    microLabel: TypeStep(11.5, FontWeight.w500),
    navLabel: TypeStep(9.5, FontWeight.w500),
    pageTitle: TypeStep(19, FontWeight.w600),
    weekdayLetter: TypeStep(15, FontWeight.w500),
    dayNumber: TypeStep(14, FontWeight.w400),
    dayCircle: 34,
  );

  /// The half step. Costs no layout constant anywhere — see the class doc.
  static const planB = AppTypeScale(
    name: 'planB',
    screenTitle: TypeStep(27, FontWeight.w600),
    statValue: TypeStep(25, FontWeight.w600),
    detailTitle: TypeStep(23, FontWeight.w600),
    cardTitle: TypeStep(18, FontWeight.w600),
    sheetTitle: TypeStep(17, FontWeight.w600),
    sectionHeading: TypeStep(16, FontWeight.w600),
    itemTitle: TypeStep(16, FontWeight.w500),
    rowTitle: TypeStep(16, FontWeight.w500),
    inputTitle: TypeStep(17, FontWeight.w500),
    input: TypeStep(16, FontWeight.w400),
    searchInput: TypeStep(16, FontWeight.w400),
    buttonLarge: TypeStep(16, FontWeight.w600),
    buttonSmall: TypeStep(14, FontWeight.w500),
    body: TypeStep(14, FontWeight.w400),
    groupHeading: TypeStep(13, FontWeight.w600),
    caption: TypeStep(13, FontWeight.w500),
    label: TypeStep(13, FontWeight.w400),
    microLabel: TypeStep(12, FontWeight.w500),
    navLabel: TypeStep(10, FontWeight.w500),
    pageTitle: TypeStep(19, FontWeight.w600),
    weekdayLetter: TypeStep(14, FontWeight.w500),
    dayNumber: TypeStep(16, FontWeight.w600),
    dayCircle: 34,
  );

  /// The full step, onto the sizes iOS uses for the same roles.
  static const planA = AppTypeScale(
    name: 'planA',
    screenTitle: TypeStep(28, FontWeight.w600),
    statValue: TypeStep(26, FontWeight.w600),
    detailTitle: TypeStep(24, FontWeight.w600),
    cardTitle: TypeStep(19, FontWeight.w600),
    sheetTitle: TypeStep(18, FontWeight.w600),
    sectionHeading: TypeStep(17, FontWeight.w600),
    itemTitle: TypeStep(17, FontWeight.w500),
    rowTitle: TypeStep(17, FontWeight.w500),
    inputTitle: TypeStep(18, FontWeight.w500),
    input: TypeStep(17, FontWeight.w400),
    searchInput: TypeStep(17, FontWeight.w400),
    buttonLarge: TypeStep(17, FontWeight.w600),
    buttonSmall: TypeStep(15, FontWeight.w500),
    body: TypeStep(15, FontWeight.w400),
    groupHeading: TypeStep(13, FontWeight.w600),
    caption: TypeStep(13, FontWeight.w500),
    label: TypeStep(13, FontWeight.w400),
    microLabel: TypeStep(12, FontWeight.w500),
    navLabel: TypeStep(10, FontWeight.w500),
    pageTitle: TypeStep(20, FontWeight.w600),
    weekdayLetter: TypeStep(13, FontWeight.w500),
    dayNumber: TypeStep(16, FontWeight.w600),
    dayCircle: 36,
  );
}

/// The app's type scale. **Every piece of text goes through one of these** —
/// there is no hand-written `TextStyle` left in `lib/screens/` or
/// `lib/widgets/`, and a new one is almost always a sign that an existing role
/// fits. The sizes themselves are not here: they come from the installed
/// [AppTypeScale], the way colours come from the installed [AppPalette].
///
/// It is a *closed* scale on purpose. It replaced 139 hand-written styles that
/// had drifted to 22 sizes and 5 weights for about 17 real roles: the same list
/// row was 15/w500 in Settings, 15/w600 in Listen and 15.5/w600 in Board, and a
/// single Board task changed weight when you checked it off. Sizes half a point
/// apart (13/13.5, 14/14.5, 15/15.5, 12/12.5) carried no meaning, so they are
/// collapsed — reach for the neighbouring token rather than reintroducing one.
///
/// Two rules for extending it:
///
/// - **Adjust colour and nothing else at the call site.** `.copyWith(color: …)`
///   is expected — a token names a *role*, and the same role is ink here and
///   accent or danger there. `.copyWith(fontSize:)` / `.copyWith(fontWeight:)`
///   is how the drift started; the only legitimate use is an animated size (see
///   [screenTitle]'s use in the collapsing headers), and that one now reads its
///   two ends off [scale] rather than naming 26 and 17.
/// - **A new weight needs a new .ttf.** `pubspec.yaml` ships only w300/400/500/
///   600/800; asking for w700 gets a synthesised or snapped weight, not Poppins
///   Bold.
class AppText {
  AppText._();

  /// Bundled in `pubspec.yaml`, **not** fetched by `google_fonts` — see the
  /// comment there for why the distinction matters.
  static const _family = 'Poppins';

  /// The file each bundled weight lives in, for the one caller that cannot let
  /// Flutter do the drawing: a **native** Liquid Glass button's title
  /// (`native_glass_buttons.dart`). Flutter resolves a family plus a weight to
  /// a file itself; UIKit has to be handed the file.
  ///
  /// Kept beside [_family] rather than re-derived from `pubspec.yaml`, so a
  /// typeface swap moves both at once — the same arrangement `app_icons.dart`
  /// makes for the icon fonts.
  static const Map<int, String> _weightAssets = {
    300: 'assets/fonts/Poppins-Light.ttf',
    400: 'assets/fonts/Poppins-Regular.ttf',
    500: 'assets/fonts/Poppins-Medium.ttf',
    600: 'assets/fonts/Poppins-SemiBold.ttf',
    800: 'assets/fonts/Poppins-ExtraBold.ttf',
  };

  /// The font file [style] is drawn from — the nearest bundled weight, which is
  /// what Flutter would land on too. A style is never drawn in two different
  /// files depending on who is doing the drawing.
  static String fontAsset(TextStyle style) {
    final target = (style.fontWeight ?? FontWeight.w400).value;
    var best = _weightAssets.keys.first;
    for (final weight in _weightAssets.keys) {
      if ((weight - target).abs() < (best - target).abs()) best = weight;
    }
    return _weightAssets[best]!;
  }

  /// The installed scale. **Change this one line and hot-reload to try a
  /// different size across the whole app**, which is the entire reason the
  /// indirection exists — see [AppTypeScale].
  ///
  /// Mutable and global for the same reason [AppColors.palette] is: the tokens
  /// are read in notifiers, models and repositories where there is no
  /// `BuildContext`, so there is nowhere to hang an `InheritedWidget`. Unlike
  /// the palette, nothing writes this at runtime — it is a build-time choice
  /// until a scale earns a place in Settings.
  static AppTypeScale scale = AppTypeScale.planB;

  static AppTypeScale get _s => scale;

  // ---------------------------------------------------------------- Titles

  /// A tab's own title, the largest type in the app. The collapsing headers
  /// animate its `fontSize` down to [sheetTitle]'s as the header pins, which is
  /// the one sanctioned `copyWith(fontSize:)`.
  static TextStyle get screenTitle => TextStyle(
    fontFamily: _family,
    fontSize: _s.screenTitle.size,
    fontWeight: _s.screenTitle.weight,
    letterSpacing: -0.3,
    color: AppColors.ink,
  );

  /// A big numeric readout that is the *point* of its tile — a Box stat, a
  /// temperature. Tighter leading than the other titles because it is usually a
  /// number sitting directly on its own caption.
  static TextStyle get statValue => TextStyle(
    fontFamily: _family,
    fontSize: _s.statValue.size,
    fontWeight: _s.statValue.weight,
    letterSpacing: -0.5,
    height: 1.1,
    color: AppColors.ink,
  );

  /// The title of a *detail* screen — one box, one list, one event. A step
  /// below [screenTitle]: it names a thing you opened, not a tab.
  static TextStyle get detailTitle => TextStyle(
    fontFamily: _family,
    fontSize: _s.detailTitle.size,
    fontWeight: _s.detailTitle.weight,
    letterSpacing: -0.4,
    color: AppColors.ink,
  );

  static TextStyle get cardTitle => TextStyle(
    fontFamily: _family,
    fontSize: _s.cardTitle.size,
    fontWeight: _s.cardTitle.weight,
    letterSpacing: -0.2,
    color: AppColors.ink,
  );

  static TextStyle get sheetTitle => TextStyle(
    fontFamily: _family,
    fontSize: _s.sheetTitle.size,
    fontWeight: _s.sheetTitle.weight,
    letterSpacing: -0.2,
    color: AppColors.ink,
  );

  static TextStyle get sectionHeading => TextStyle(
    fontFamily: _family,
    fontSize: _s.sectionHeading.size,
    fontWeight: _s.sectionHeading.weight,
    color: AppColors.ink,
  );

  // ------------------------------------------------------------------ Rows

  /// The title of a row you *act on* — a list or box card, a task, a search
  /// hit, an event.
  ///
  /// **It used to be one weight above [rowTitle]**, on the theory that content
  /// the household created should carry more weight than the settings that
  /// configure it. The Ausgaben page is where that theory was tested and lost:
  /// the category card is set in this token and the payments card below it in
  /// [rowTitle], the two sit one above the other on the same screen, and the
  /// heavier one reads as shouting rather than as content. The lighter of the
  /// two is the standard for a list row now, everywhere.
  ///
  /// The two tokens still name different roles and still stand apart in the
  /// shipped [AppTypeScale.actual]; on the newer scales they happen to agree.
  static TextStyle get itemTitle => TextStyle(
    fontFamily: _family,
    fontSize: _s.itemTitle.size,
    fontWeight: _s.itemTitle.weight,
    color: AppColors.ink,
  );

  /// The title of a *settings-shaped* row, and the label of a button. Lighter
  /// than [itemTitle] on purpose — see there.
  static TextStyle get rowTitle => TextStyle(
    fontFamily: _family,
    fontSize: _s.rowTitle.size,
    fontWeight: _s.rowTitle.weight,
    color: AppColors.ink,
  );

  // ---------------------------------------------------------------- Inputs

  /// The headline field of a create/edit sheet — the task text, the event
  /// title, a list's or box's name. All four used to disagree (17/w500 in Board
  /// and Kalender, 16/w400 in Listen and Box) for what is the same field.
  static TextStyle get inputTitle => TextStyle(
    fontFamily: _family,
    fontSize: _s.inputTitle.size,
    fontWeight: _s.inputTitle.weight,
    color: AppColors.ink,
  );

  /// Every other editable field, and the label of a menu item — text the user
  /// supplies rather than text the app asserts, so a step lighter than
  /// [rowTitle] at the same size.
  static TextStyle get input => TextStyle(
    fontFamily: _family,
    fontSize: _s.input.size,
    fontWeight: _s.input.weight,
    color: AppColors.ink,
  );

  /// The search pill's text — shared by the header trigger's placeholder and the
  /// live field in the search sheet, so the two read as the same control.
  static TextStyle get searchInput => TextStyle(
    fontFamily: _family,
    fontSize: _s.searchInput.size,
    fontWeight: _s.searchInput.weight,
    color: AppColors.ink,
  );

  // --------------------------------------------------------------- Actions

  /// A full-width primary call to action (Anmelden, Weiter). Buttons at
  /// [rowTitle]'s weight are the common case; this is for the one button a
  /// screen is *about*.
  static TextStyle get buttonLarge => TextStyle(
    fontFamily: _family,
    fontSize: _s.buttonLarge.size,
    fontWeight: _s.buttonLarge.weight,
    color: AppColors.ink,
  );

  /// A compact action — a chip, an icon-picker entry, a sheet's secondary
  /// button.
  static TextStyle get buttonSmall => TextStyle(
    fontFamily: _family,
    fontSize: _s.buttonSmall.size,
    fontWeight: _s.buttonSmall.weight,
    color: AppColors.ink,
  );

  // ------------------------------------------------------- Body & captions

  /// Running prose: a page's explanatory sentence, an error message, an empty
  /// state. **The `height` is the reason to use the token** — six places used to
  /// hand-write 14/w300 and drop it, so the same paragraph was set tighter
  /// outside Settings than in it.
  static TextStyle get body => TextStyle(
    fontFamily: _family,
    fontSize: _s.body.size,
    fontWeight: _s.body.weight,
    height: 1.55,
    color: AppColors.inkSecondary,
  );

  /// The caption naming a *group* of rows — a search result section, a list's
  /// name above its items, a Settings group.
  static TextStyle get groupHeading => TextStyle(
    fontFamily: _family,
    fontSize: _s.groupHeading.size,
    fontWeight: _s.groupHeading.weight,
    letterSpacing: 0.3,
    color: AppColors.muted,
  );

  /// A small piece of status text that is not a row's subtitle — the
  /// "Erledigt (3)" bar and the inline action beside it, a week range.
  static TextStyle get caption => TextStyle(
    fontFamily: _family,
    fontSize: _s.caption.size,
    fontWeight: _s.caption.weight,
    color: AppColors.muted,
  );

  /// The secondary line *under* a row's title.
  static TextStyle get label => TextStyle(
    fontFamily: _family,
    fontSize: _s.label.size,
    fontWeight: _s.label.weight,
    color: AppColors.muted,
  );

  /// The smallest type in the app — a timeline hour, an all-day pill.
  static TextStyle get microLabel => TextStyle(
    fontFamily: _family,
    fontSize: _s.microLabel.size,
    fontWeight: _s.microLabel.weight,
    color: AppColors.muted,
  );

  /// The name under a glyph in the bottom nav bar — see [AppTypeScale.navLabel]
  /// for why it is smaller than [microLabel] rather than borrowing it. Takes
  /// its colour from the item (`AppColors.ink`, or the accent on the tab in
  /// force), so unlike the captions above it does not carry one.
  static TextStyle get navLabel => TextStyle(
    fontFamily: _family,
    fontSize: _s.navLabel.size,
    fontWeight: _s.navLabel.weight,
  );

  /// The two ends of a collapsing header's title, and the title of a pushed
  /// page at rest. Sizes rather than styles, because the header interpolates
  /// between them every scroll frame — that interpolation is the one sanctioned
  /// `copyWith(fontSize:)` in the app, and this is where its two ends live so
  /// that no screen has to name a number.
  static double get headerExpanded => _s.screenTitle.size;
  static double get headerCollapsed => _s.sheetTitle.size;
  static double get pageTitle => _s.pageTitle.size;

  // ------------------------------------------------------------- Row marks

  /// The round mark at the head of a **two-line row** — a list, a box, a box
  /// item, a spend. Derived from the text block beside it rather than written
  /// down, because that is the only thing it has ever been measured against:
  /// a disc shorter than the words it leads stops reading as the row's subject
  /// and starts reading as a bullet.
  ///
  /// Writing it down is how the three screens came to disagree about the same
  /// row — 34 in Ausgaben, 38 in Listen, 44 in Box — and how raising the type
  /// left all three behind at once. At the shipped scale this still comes out
  /// at the 38 Listen used.
  ///
  /// Rounded down to an even number so the disc has a whole-pixel centre at
  /// 1× and 2×; a 39pt circle puts its own hairline on a half pixel.
  static double get rowMark =>
      ((lineBox(_s.itemTitle.size) + lineBox(_s.label.size) + 2) / 2).floorToDouble() * 2;

  /// The same mark where it names a whole page rather than a row — a list's or
  /// a tracker's own header. One step up, which at the shipped scale is the 44
  /// those headers used.
  static double get headerMark => rowMark + 6;

  /// What goes *inside* a mark, as a fraction of it.
  ///
  /// **These are not the thing to grow when a mark feels small.** The inset a
  /// logo gets is what keeps full-colour artwork off the hairline, and several
  /// merchant marks bleed to their own edge and are clipped by the disc — push
  /// the art out and those lose their edges rather than gaining presence. The
  /// disc is what tracks the type; the ratios inside it are fixed.
  static double markImage(double mark) => mark * 0.68;
  static double markGlyph(double mark) => mark * 0.5;
  static double markInitials(double mark) => mark * 0.36;

  // -------------------------------------------------------------- Calendar

  /// The weekday letter above a day in the week strip. Its own role rather than
  /// [rowTitle]'s — see [AppTypeScale.weekdayLetter] for why that mattered.
  static TextStyle get weekdayLetter => TextStyle(
    fontFamily: _family,
    fontSize: _s.weekdayLetter.size,
    fontWeight: _s.weekdayLetter.weight,
    color: AppColors.muted,
  );

  /// The day number, per view. The colour and the weight are the *day's* — a
  /// selected or today's number is set heavier by `DaySelectorCircle` — so what
  /// these two carry is the resting size and the resting weight.
  static TypeStep get dayNumber => _s.dayNumber;

  /// The diameter each of those is drawn in. Here rather than at the call site
  /// because a number cannot grow inside a circle that cannot, and the week
  /// strip's bands are measured off this.
  static double get dayCircle => _s.dayCircle;

  /// The line box a run of Poppins occupies at [size], to the nearest point.
  ///
  /// Used where a band is reserved for one line of text and the cells either
  /// side of it have to agree on the baseline — the week strip's weekday letter
  /// is the case that made it necessary. The factor is measured from Poppins'
  /// own metrics: at 15pt it gives the 20 that band was hand-written as.
  static double lineBox(double size) => (size * 1.34).roundToDouble();
}
