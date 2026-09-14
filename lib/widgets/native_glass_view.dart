import 'dart:typed_data';

import 'package:flutter/foundation.dart' show Factory, listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';
import '../theme/tokens.dart';

/// One tappable segment of a [NativeGlassView], as a fraction of the surface's
/// own box.
///
/// Fractions rather than points so nothing has to be re-sent when Flutter
/// resizes the control: the native side re-derives the frames in
/// `layoutSubviews` from whatever size it has been given.
typedef GlassTouchRegion = Rect;

/// The whole surface as one target — what a plain glass button wants.
const oneGlassTouchRegion = <GlassTouchRegion>[Rect.fromLTRB(0, 0, 1, 1)];

/// A native `UIVisualEffectView` configured with iOS 26's real `UIGlassEffect`
/// material, embedded via a Flutter platform view (see
/// ios/Runner/GlassPlatformView.swift, registered under "aporah/glass_view").
/// Falls back to a system blur natively on pre-iOS 26 devices. iOS only —
/// [GlassSurface] uses this on iOS and a Flutter-drawn approximation
/// everywhere else.
///
/// **The press belongs to UIKit.** `UIGlassEffect.isInteractive` is the
/// material's own response to a finger — the lensing that gathers under it —
/// and it only runs for touches UIKit itself delivers into the effect view. A
/// Flutter `GestureDetector` layered over the platform view took them all
/// instead, so `isInteractive` was set on every glass surface in the app and
/// never once fired. Pass [regions] to hand the press over; the tap comes back
/// through [onTap] and is still Dart's to act on.
class NativeGlassView extends StatefulWidget {
  /// Null means "no forced tint" — the real UIGlassEffect's own adaptive
  /// appearance (opacity/light-dark) applies instead of a flat color.
  final Color? tint;
  final bool interactive;
  final String style;

  /// The tappable segments. Empty (the default) means a purely decorative
  /// surface — the nav bar's backing capsule, the `Mehr` shelf — which takes
  /// no touches at all, exactly as it did before.
  final List<GlassTouchRegion> regions;

  /// A completed tap on segment `index`.
  final void Function(int index)? onTap;

  /// Touch-down and touch-up on segment `index`, for whatever Dart still draws
  /// *over* the glass. A [GlassIconGroup] uses it to scale the pressed glyph:
  /// the material's own lensing says the capsule was touched, not which of two
  /// icons it was.
  final void Function(int index, bool pressed)? onPressed;

  const NativeGlassView({
    super.key,
    this.tint,
    this.interactive = true,
    this.style = 'regular',
    this.regions = const <GlassTouchRegion>[],
    this.onTap,
    this.onPressed,
  });

  @override
  State<NativeGlassView> createState() => _NativeGlassViewState();
}

class _NativeGlassViewState extends State<NativeGlassView> {
  MethodChannel? _channel;

  /// Mirrors [AppColors.isDark] into the embedded `UIVisualEffectView`.
  ///
  /// The glass material derives its own appearance from the trait collection,
  /// which tracks the *device's* light/dark setting — but Aporah's dark mode is
  /// an in-app switch, so there is no device-appearance change for UIKit to
  /// pick up and the frosted headers would stay light in a dark app. Tracked
  /// here so the flip can be pushed over the channel; a `UiKitView` is not
  /// rebuilt from its `creationParams`.
  bool _nativeDark = AppColors.isDark;

  /// Set when the tint changed before there was a channel to push it over, so
  /// the change can be flushed once the view exists.
  bool _tintPending = false;

  void _syncBrightness() {
    if (_nativeDark == AppColors.isDark) return;
    _nativeDark = AppColors.isDark;
    _channel?.invokeMethod('setBrightness', {'dark': _nativeDark});
  }

  /// Mirrors [NativeGlassView.tint] into the embedded view — the same contract
  /// as [_syncBrightness], and the one that bites hardest.
  ///
  /// A create sheet's save button is grey while its name field is empty and
  /// accent once it isn't, and a `UiKitView` is built from `creationParams`
  /// exactly once: left alone the button keeps the grey it was born with, so
  /// typing a title changed nothing and the sheet looked like it refused to
  /// save. It appeared to work after opening a sub-sheet only because a
  /// covering route stands the platform view down (see `occludedByRoute`) and
  /// the one built on the way back is a *new* view, created with the tint of
  /// the moment.
  void _syncTint() {
    final channel = _channel;
    if (channel == null) {
      _tintPending = true;
      return;
    }
    _tintPending = false;
    channel.invokeMethod('setTint', {'tint': widget.tint?.toARGB32()});
  }

  /// Same contract again, for the touch targets: a group's segment count is a
  /// build-time value and the native view was created once.
  void _syncRegions() {
    _channel?.invokeMethod('setRegions', {'regions': _encodeRegions(widget.regions)});
  }

  /// Flat `[x, y, w, h, …]`, because `StandardMessageCodec` sends a
  /// `List<double>` as one `Float64List` and a list-of-lists as a boxed array
  /// per row.
  static Float64List _encodeRegions(List<GlassTouchRegion> regions) {
    final values = Float64List(regions.length * 4);
    for (var i = 0; i < regions.length; i++) {
      values[i * 4] = regions[i].left;
      values[i * 4 + 1] = regions[i].top;
      values[i * 4 + 2] = regions[i].width;
      values[i * 4 + 3] = regions[i].height;
    }
    return values;
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
    final index = args['index'] as int? ?? 0;
    switch (call.method) {
      case 'tapped':
        widget.onTap?.call(index);
      case 'pressed':
        widget.onPressed?.call(index, args['pressed'] as bool? ?? false);
    }
    return null;
  }

  @override
  void didUpdateWidget(NativeGlassView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncBrightness();
    if (widget.tint != oldWidget.tint) _syncTint();
    if (!listEquals(widget.regions, oldWidget.regions)) _syncRegions();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  void _onPlatformViewCreated(int id) {
    _channel = MethodChannel('aporah/glass_view_$id')..setMethodCallHandler(_onNativeCall);
    // The view was created with the brightness `_nativeDark` held at build
    // time; catch it up if the palette moved on while it was being set up.
    _syncBrightness();
    if (_tintPending) _syncTint();
  }

  @override
  Widget build(BuildContext context) {
    final takesTouches = widget.regions.isNotEmpty;
    return UiKitView(
      viewType: 'aporah/glass_view',
      // A decorative surface stays out of the way exactly as before. One with
      // segments is a control, and UIKit has to see touch-down the instant it
      // happens or the material's lensing lags the finger — the same bargain
      // the native tab bar and switch already make with `EagerGestureRecognizer`.
      hitTestBehavior: takesTouches
          ? PlatformViewHitTestBehavior.opaque
          : PlatformViewHitTestBehavior.transparent,
      gestureRecognizers: takesTouches
          ? <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
            }
          : const <Factory<OneSequenceGestureRecognizer>>{},
      onPlatformViewCreated: _onPlatformViewCreated,
      creationParams: {
        'tint': widget.tint?.toARGB32(),
        'interactive': widget.interactive,
        'style': widget.style,
        'dark': AppColors.isDark,
        'regions': _encodeRegions(widget.regions),
      },
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}
