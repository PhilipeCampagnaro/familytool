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

  /// Tint the non-iOS glass approximation draws, and the strength of its
  /// specular highlight / rim. On dark the highlight has to come *way* down:
  /// the same 45% white that reads as a soft sheen over a light backdrop reads
  /// as a grey fog over a dark one.
  final Color glassFallbackTint;
  final Color glassSpecular;
  final Color glassRim;

  /// The colour `FrostedHeaderBackground` washes a collapsing header with.
  final Color frost;

  /// Fill behind the bottom nav pill's Flutter approximation (non-iOS).
  final Color navPillTint;

  /// The near-opaque vibrant material an anchored menu is drawn on, plus its
  /// hairline separator. Deliberately *not* glass — see `anchored_menu.dart`.
  final Color menuSurface;
  final Color menuSeparator;

  /// Backing tile for a third-party brand mark (calendar providers, shop
  /// logos). **White in both palettes, deliberately**: these are full-colour
  /// logos drawn for a light background, and several go unreadable on a dark
  /// circle. iOS does the same for app icons in dark mode.
  final Color brandTile;

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
    required this.navPillTint,
    required this.menuSurface,
    required this.menuSeparator,
    required this.brandTile,
    required this.scrim,
    required this.grabHandle,
    required this.idleRing,
    required this.dayNumber,
    required this.holidayNumber,
    required this.tones,
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
    glassFallbackTint: Color(0x26111418),
    glassSpecular: Color(0x73FFFFFF),
    glassRim: Color(0x8CFFFFFF),
    frost: Color(0xFFFFFFFF),
    navPillTint: Color(0xCCF3F4F7),
    menuSurface: Color(0xFAFBFBFD),
    menuSeparator: Color(0x1F3C3C43),
    brandTile: Color(0xFFFFFFFF),
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
    shadowCard: [BoxShadow(color: Color(0x0F112A2B), blurRadius: 10, offset: Offset(0, 2))],
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
    glassFallbackTint: Color(0x40FFFFFF),
    glassSpecular: Color(0x24FFFFFF),
    glassRim: Color(0x2EFFFFFF),
    frost: Color(0xFF14161B),
    navPillTint: Color(0xCC23262D),
    menuSurface: Color(0xFA24272E),
    menuSeparator: Color(0x33FFFFFF),
    brandTile: Color(0xFFFFFFFF),
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
    shadowCard: [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 2))],
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
  static Color get navPillTint => _palette.navPillTint;
  static Color get menuSurface => _palette.menuSurface;
  static Color get menuSeparator => _palette.menuSeparator;
  static Color get brandTile => _palette.brandTile;
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

/// The app's type scale. **Every piece of text goes through one of these** —
/// there is no hand-written `TextStyle` left in `lib/screens/` or
/// `lib/widgets/`, and a new one is almost always a sign that an existing role
/// fits.
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
///   [screenTitle]'s use in the collapsing headers).
/// - **A new weight needs a new .ttf.** `pubspec.yaml` ships only w300/400/500/
///   600/800; asking for w700 gets a synthesised or snapped weight, not Poppins
///   Bold.
///
/// ### The scale
///
/// | Role | Size / weight |
/// |---|---|
/// | [screenTitle] | 26 w600 |
/// | [statValue] | 24 w600 |
/// | [detailTitle] | 23 w600 |
/// | [cardTitle] | 18 w600 |
/// | [sheetTitle] / [inputTitle] | 17 w600 / w500 |
/// | [sectionHeading] / [buttonLarge] / [searchInput] | 16 w500 / w600 / w300 |
/// | [itemTitle] / [rowTitle] / [input] | 15 w600 / w500 / w400 |
/// | [body] / [buttonSmall] | 14 w300 / w500 |
/// | [groupHeading] / [caption] | 13 w600 / w500 |
/// | [label] | 12.5 w300 |
/// | [microLabel] | 11.5 w500 |
class AppText {
  AppText._();

  /// Bundled in `pubspec.yaml`, **not** fetched by `google_fonts` — see the
  /// comment there for why the distinction matters.
  static const _family = 'Poppins';

  // ---------------------------------------------------------------- Titles

  /// A tab's own title, the largest type in the app. The collapsing headers
  /// animate its `fontSize` down to [sheetTitle]'s 17 as the header pins, which
  /// is the one sanctioned `copyWith(fontSize:)`.
  static TextStyle get screenTitle => TextStyle(
    fontFamily: _family,
    fontSize: 26,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: AppColors.ink,
  );

  /// A big numeric readout that is the *point* of its tile — a Box stat, a
  /// temperature. Tighter leading than the other titles because it is usually a
  /// number sitting directly on its own caption.
  static TextStyle get statValue => TextStyle(
    fontFamily: _family,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
    height: 1.1,
    color: AppColors.ink,
  );

  /// The title of a *detail* screen — one box, one list, one event. A step
  /// below [screenTitle]: it names a thing you opened, not a tab.
  static TextStyle get detailTitle => TextStyle(
    fontFamily: _family,
    fontSize: 23,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    color: AppColors.ink,
  );

  static TextStyle get cardTitle => TextStyle(
    fontFamily: _family,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: AppColors.ink,
  );

  static TextStyle get sheetTitle => TextStyle(
    fontFamily: _family,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: AppColors.ink,
  );

  static TextStyle get sectionHeading => TextStyle(
    fontFamily: _family,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: AppColors.ink,
  );

  // ------------------------------------------------------------------ Rows

  /// The title of a row you *act on* — a list or box card, a task, a search
  /// hit, an event. Deliberately one weight above [rowTitle]: content the user
  /// created should carry more weight than the settings that configure it.
  static TextStyle get itemTitle => TextStyle(
    fontFamily: _family,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
  );

  /// The title of a *settings-shaped* row, and the label of a button. Lighter
  /// than [itemTitle] on purpose — see there.
  static TextStyle get rowTitle => TextStyle(
    fontFamily: _family,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: AppColors.ink,
  );

  // ---------------------------------------------------------------- Inputs

  /// The headline field of a create/edit sheet — the task text, the event
  /// title, a list's or box's name. All four used to disagree (17/w500 in Board
  /// and Kalender, 16/w400 in Listen and Box) for what is the same field.
  static TextStyle get inputTitle => TextStyle(
    fontFamily: _family,
    fontSize: 17,
    fontWeight: FontWeight.w500,
    color: AppColors.ink,
  );

  /// Every other editable field, and the label of a menu item — text the user
  /// supplies rather than text the app asserts, so a step lighter than
  /// [rowTitle] at the same size.
  static TextStyle get input => TextStyle(
    fontFamily: _family,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.ink,
  );

  /// The search pill's text — shared by the header trigger's placeholder and the
  /// live field in the search sheet, so the two read as the same control.
  static TextStyle get searchInput => TextStyle(
    fontFamily: _family,
    fontSize: 16,
    fontWeight: FontWeight.w300,
    color: AppColors.ink,
  );

  // --------------------------------------------------------------- Actions

  /// A full-width primary call to action (Anmelden, Weiter). Buttons at
  /// [rowTitle]'s 15/w500 are the common case; this is for the one button a
  /// screen is *about*.
  static TextStyle get buttonLarge => TextStyle(
    fontFamily: _family,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
  );

  /// A compact action — a chip, an icon-picker entry, a sheet's secondary
  /// button.
  static TextStyle get buttonSmall => TextStyle(
    fontFamily: _family,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.ink,
  );

  // ------------------------------------------------------- Body & captions

  /// Running prose: a page's explanatory sentence, an error message, an empty
  /// state. **The `height` is the reason to use the token** — six places used to
  /// hand-write 14/w300 and drop it, so the same paragraph was set tighter
  /// outside Settings than in it.
  static TextStyle get body => TextStyle(
    fontFamily: _family,
    fontSize: 14,
    fontWeight: FontWeight.w300,
    height: 1.55,
    color: AppColors.inkSecondary,
  );

  /// The caption naming a *group* of rows — a search result section, a list's
  /// name above its items, a Settings group.
  static TextStyle get groupHeading => TextStyle(
    fontFamily: _family,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
    color: AppColors.muted,
  );

  /// A small piece of status text that is not a row's subtitle — the
  /// "Erledigt (3)" bar and the inline action beside it, a week range.
  static TextStyle get caption => TextStyle(
    fontFamily: _family,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.muted,
  );

  /// The secondary line *under* a row's title.
  static TextStyle get label => TextStyle(
    fontFamily: _family,
    fontSize: 12.5,
    fontWeight: FontWeight.w300,
    color: AppColors.muted,
  );

  /// The smallest type in the app — a timeline hour, an all-day pill.
  static TextStyle get microLabel => TextStyle(
    fontFamily: _family,
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
    color: AppColors.muted,
  );
}
