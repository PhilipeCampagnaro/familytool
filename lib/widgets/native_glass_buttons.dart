import 'package:flutter/foundation.dart' show Factory, listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';

/// The type size UIKit draws a tab bar's SF Symbols at — its own default, which
/// is what `TabBarPlatformView` gets by passing no symbol configuration at all.
/// Any symbol the app puts *beside* that bar takes the same number, so the two
/// are the same size by construction rather than by a tuned constant.
const kNavBarSymbolPointSize = 17.0;

/// How heavy an SF Symbol's stroke is drawn.
///
/// **The one thing about a symbol that does not follow the tab bar.** Size
/// does — see [kNavBarSymbolPointSize] — but the bar draws its glyphs *on the
/// bar*, where [regular] is right, and the `Mehr` shelf draws the same glyph on
/// a 62pt glass circle floating over a screen, where it reads thin beside the
/// Phosphor every other control in the app is set in. Measured: at 17pt SF's
/// own [regular] draws a 1.25–1.50pt line and [medium] a 1.44–1.75pt one, where
/// Phosphor Regular at [AppGlyph.button] draws 1.63pt — so [medium] is the step
/// that brackets it. One step up rather than two: [semibold] at this size
/// starts to look like a different icon set.
enum NativeSymbolWeight { light, regular, medium, semibold, bold }

/// A stack of colour dots drawn beside a button's glyph — Kalender's collapsed
/// filter, which says *which* calendars are showing by wearing their colours.
///
/// It rides with the glyph rather than beside it because a
/// `UIButton.Configuration` has exactly one image slot: UIKit is handed one
/// picture holding the dots and the glyph together. Two consequences, both
/// deliberate. The dots each carry their own colour, so that image cannot be a
/// **template** — which is how a glyph normally takes the button's tint and the
/// glass's vibrancy — so a button with dots also passes
/// [NativeGlassButton.glyphColor] and gives up the vibrancy on that one glyph.
/// And the gap between two dots is **cleared** rather than filled with a
/// background colour: the button is glass, so the material itself is what shows
/// through the overlap.
@immutable
class NativeGlassDots {
  final List<Color> colors;

  /// One dot's diameter.
  final double size;

  /// How far each dot sits *inside* the one before it. The stack is [size] +
  /// ([size] - [overlap]) per further dot, which is what the sizer draws.
  final double overlap;

  const NativeGlassDots({required this.colors, required this.size, required this.overlap});

  @override
  bool operator ==(Object other) =>
      other is NativeGlassDots &&
      listEquals(other.colors, colors) &&
      other.size == size &&
      other.overlap == overlap;

  @override
  int get hashCode => Object.hash(Object.hashAll(colors), size, overlap);
}

/// One button of a [NativeGlassButtons] row.
///
/// [icon] is drawn by UIKit, not by Flutter — the codepoint and the font asset
/// cross the channel and the native side rasterises the glyph out of the very
/// file the app already ships. So a glyph cannot drift between the two sides,
/// and there is no SF Symbol mapping table to keep in step.
///
/// **It is `flatIcon(icon)` that goes over, never [icon] itself.** The two
/// Phosphor weights do not share a codepoint space — a duotone glyph is a pair,
/// so Duotone maps 3025 codepoints where Regular maps 1543 — and sending an
/// [AppIcons] constant's own codepoint to the flat font draws a missing-glyph
/// box, which is exactly what the first version of this did.
///
/// [label] is never drawn; it is the button's accessible name, which an icon
/// hasn't got.
@immutable
class NativeGlassButton {
  /// Null for a button that is only a word — Settings' "Fertig", the calendar's
  /// "Heute".
  final IconData? icon;

  /// An SF Symbol name, which **wins over [icon]** where both are set.
  ///
  /// For the one row that is already Apple's set: the `Mehr` shelf stands over
  /// a real `UITabBar` drawing real symbols, and `navRowIcon` already swaps
  /// Phosphor out for `CupertinoIcons` there so the two don't read as two
  /// subtly different boxes. That font is a package asset with no path UIKit
  /// can be handed — and needs none, since a `UIButton` takes a symbol by name.
  /// **Validate a name against the runtime's own list before using one**; see
  /// the menu section of CLAUDE.md for the one that rendered as nothing.
  final String? symbol;

  final String label;

  /// The word the button *draws*, where it has one. Set in the app's own
  /// typeface: see [NativeGlassButtons] for why that is worth carrying across.
  final String? title;

  /// Resolved to a bundled font file and a point size for UIKit. Null with a
  /// [title] set falls back to [AppText.rowTitle], which is what the labelled
  /// glass pills are set in.
  final TextStyle? titleStyle;

  /// Puts the glyph *after* the [title] rather than before it — a dropdown's
  /// caret, which reads as "opens" only when it trails the word it opens.
  final bool iconTrailing;

  /// Colour dots drawn beside the glyph — see [NativeGlassDots].
  final NativeGlassDots? dots;

  /// Bakes the glyph in this colour instead of letting the button's tint paint
  /// it. Only for a glyph that has to share its image with something coloured
  /// — i.e. [dots], which is what stops that image being a template.
  final Color? glyphColor;

  final VoidCallback onTap;

  const NativeGlassButton({
    this.icon,
    this.symbol,
    required this.label,
    this.title,
    this.titleStyle,
    this.iconTrailing = false,
    this.dots,
    this.glyphColor,
    required this.onTap,
  });

  @override
  bool operator ==(Object other) =>
      other is NativeGlassButton &&
      other.icon == icon &&
      other.symbol == symbol &&
      other.label == label &&
      other.title == title &&
      other.iconTrailing == iconTrailing &&
      other.dots == dots &&
      other.glyphColor == glyphColor;

  @override
  int get hashCode => Object.hash(icon, symbol, label, title, iconTrailing, dots, glyphColor);
}

/// **The real UIKit Liquid Glass button** — `UIButton.Configuration.glass()`,
/// or `.prominentGlass()` for the accent — embedded as a platform view
/// (ios/Runner/GlassButtonPlatformView.swift, registered under
/// "aporah/glass_buttons").
///
/// This is the same bargain the app already makes for the bottom bar (a real
/// `UITabBar`) and every menu (a real `UIMenu`): where the system ships the
/// control, use the control rather than rebuilding it. The header buttons used
/// to be [GlassSurface] — the raw material with a Flutter glyph over it, a
/// Flutter shadow under it and a Flutter gesture detector on top — which is an
/// app re-implementing `UIButton`, and it showed. A real button brings its own
/// material, its own press response, its own shadow and its own metrics.
///
/// More than one button is hung inside a `UIGlassContainerEffect`, which is the
/// documented way to make adjacent glass **merge into one shape** rather than
/// sit beside each other as separate pieces — that is what a grouped capsule
/// is, and what UIKit's own grouped `UIBarButtonItem`s use.
///
/// iOS only. [GlassIconButton] and [GlassIconGroup] fall back to their
/// Flutter-drawn selves everywhere else, and for as long as a sheet covers the
/// screen (see `occludedByRoute`).
class NativeGlassButtons extends StatefulWidget {
  final List<NativeGlassButton> buttons;

  /// The accent fill — `.prominentGlass()` rather than `.glass()`. False is a
  /// plain glass button, which is what a header's verbs are.
  final bool prominent;

  /// Forced colour. On a prominent button it is the fill; on a plain one it is
  /// the glyph. Null leaves UIKit's own tint, which is what an ordinary icon
  /// button wants.
  final Color? tint;

  /// The em a Phosphor glyph is drawn at — see [AppGlyph], which is where the
  /// number comes from and why it is not the box the glyph fills.
  final double iconSize;

  /// The **type** size an SF Symbol is drawn at, which is not a box and not
  /// interchangeable with [iconSize] — see [NativeGlassButton.symbol]. The
  /// default is UIKit's own, which is what `TabBarPlatformView` gets by passing
  /// no configuration at all, so a symbol here comes out the size of the bar's.
  final double symbolSize;

  /// The stroke weight of an SF Symbol — see [NativeSymbolWeight].
  final NativeSymbolWeight symbolWeight;

  /// **What gives the button its box.** A platform view has no intrinsic size,
  /// and every one of these controls is sized by its own content — a word, or a
  /// glyph and a word, plus padding. So the Flutter widget this replaces is
  /// built here at zero opacity purely to measure: the `Stack` takes its size
  /// and the native button fills it.
  ///
  /// One source of truth rather than two. A `TextPainter` measurement would
  /// have to be kept in step with the padding and type of the fallback path by
  /// hand, and would silently drift the first time either changed. It is built
  /// *first* in the stack, so it lands in the base surface rather than in an
  /// overlay layer above the platform view.
  ///
  /// Null for a control whose caller already fixes the box — the header icon
  /// buttons, which are a known 40pt circle.
  final Widget? sizer;

  const NativeGlassButtons({
    super.key,
    required this.buttons,
    this.prominent = false,
    this.tint,
    this.iconSize = AppGlyph.button,
    this.symbolSize = kNavBarSymbolPointSize,
    this.symbolWeight = NativeSymbolWeight.medium,
    this.sizer,
  });

  @override
  State<NativeGlassButtons> createState() => _NativeGlassButtonsState();
}

class _NativeGlassButtonsState extends State<NativeGlassButtons> {
  MethodChannel? _channel;

  /// A `UiKitView` is built from its `creationParams` exactly once, so every
  /// one of these is a value that can change under a view that will never
  /// re-read it. Same contract as the native tab bar, search field and switch.
  bool _nativeDark = AppColors.isDark;

  void _syncBrightness() {
    if (_nativeDark == AppColors.isDark) return;
    _nativeDark = AppColors.isDark;
    _channel?.invokeMethod('setBrightness', {'dark': _nativeDark});
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method != 'tapped') return null;
    final index = ((call.arguments as Map?)?['index'] as int?) ?? 0;
    if (index < widget.buttons.length) widget.buttons[index].onTap();
    return null;
  }

  @override
  void didUpdateWidget(NativeGlassButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncBrightness();
    if (widget.prominent != oldWidget.prominent) {
      _channel?.invokeMethod('setProminent', {'prominent': widget.prominent});
    }
    if (widget.tint != oldWidget.tint) {
      _channel?.invokeMethod('setTint', {'tint': widget.tint?.toARGB32()});
    }
    // **Everything the items carry has to be pushed, not just the words.**
    // A `UiKitView` reads its `creationParams` exactly once, and a button's
    // title colour is `AppColors.ink` — which flips with the palette. Baked
    // into the `AttributedString` at creation and never sent again, "Fertig"
    // stayed black in a dark app until something else tore the view down. The
    // same is true of the label after a language switch, so one push covers
    // both rather than two that can fall out of step.
    final items = _items;
    if (!listEquals(items, _sentItems)) {
      _sentItems = items;
      _channel?.invokeMethod('setItems', {'items': items});
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  void _onPlatformViewCreated(int id) {
    _channel = MethodChannel('aporah/glass_buttons_$id')..setMethodCallHandler(_onNativeCall);
    _syncBrightness();
  }

  /// What was last sent, so a rebuild that changed nothing sends nothing. Not
  /// `widget.buttons`: two `NativeGlassButton`s can be equal and still resolve
  /// to different colours, which is the whole point of the push above.
  List<Map<String, dynamic>>? _sentItems;

  List<Map<String, dynamic>> get _items => [for (final b in widget.buttons) _item(b)];

  @override
  void initState() {
    super.initState();
    _sentItems = _items;
  }

  /// One button's creation params. Split out because it is also what
  /// `setLabels` would have to rebuild, and because the glyph half of it has a
  /// trap in it — see [NativeGlassButton.icon].
  Map<String, dynamic> _item(NativeGlassButton button) {
    final glyph = button.icon == null || button.symbol != null ? null : flatIcon(button.icon!);
    final style = button.title == null ? null : (button.titleStyle ?? AppText.rowTitle);
    return {
      'symbol': ?button.symbol,
      'glyph': ?glyph?.codePoint,
      'font': ?(glyph == null ? null : iconFontAsset(glyph)),
      'label': button.label,
      'title': ?button.title,
      'titleFont': ?(style == null ? null : AppText.fontAsset(style)),
      'titleSize': ?style?.fontSize,
      'titleColor': ?style?.color?.toARGB32(),
      if (button.iconTrailing) 'iconTrailing': true,
      'glyphColor': ?button.glyphColor?.toARGB32(),
      if (button.dots != null)
        'dots': {
          'colors': [for (final c in button.dots!.colors) c.toARGB32()],
          'size': button.dots!.size,
          'overlap': button.dots!.overlap,
        },
    };
  }

  @override
  Widget build(BuildContext context) {
    final view = _buildView();
    final sizer = widget.sizer;
    if (sizer == null) return view;
    return Stack(
      children: [
        // Painted first and invisible: it exists to give the stack a size, and
        // anything laid out *after* a platform view lands in an overlay layer.
        IgnorePointer(child: Opacity(opacity: 0, child: sizer)),
        Positioned.fill(child: view),
      ],
    );
  }

  Widget _buildView() {
    return UiKitView(
      viewType: 'aporah/glass_buttons',
      // The touches are the button's. It needs to see touch-down the instant it
      // happens or the material's own press response lags the finger — the same
      // reason the native tab bar and switch take an eager recognizer. The cost
      // is that a drag starting on a button no longer scrolls what is behind
      // it, which is what a real bar button does anyway.
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
      },
      onPlatformViewCreated: _onPlatformViewCreated,
      creationParams: {
        'items': _sentItems,
        'prominent': widget.prominent,
        'tint': widget.tint?.toARGB32(),
        'iconSize': widget.iconSize,
        'symbolSize': widget.symbolSize,
        'symbolWeight': widget.symbolWeight.name,
        'dark': AppColors.isDark,
      },
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}
