import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';
import '../theme/tokens.dart';

/// A native `UIVisualEffectView` configured with iOS 26's real `UIGlassEffect`
/// material, embedded via a Flutter platform view (see
/// ios/Runner/GlassPlatformView.swift, registered under "aporah/glass_view").
/// Falls back to a system blur natively on pre-iOS 26 devices. iOS only —
/// [GlassSurface] uses this on iOS and a Flutter-drawn approximation
/// everywhere else.
class NativeGlassView extends StatefulWidget {
  /// Null means "no forced tint" — the real UIGlassEffect's own adaptive
  /// appearance (opacity/light-dark) applies instead of a flat color.
  final Color? tint;
  final bool interactive;
  final String style;

  const NativeGlassView({super.key, this.tint, this.interactive = true, this.style = 'regular'});

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

  @override
  void didUpdateWidget(NativeGlassView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncBrightness();
    if (widget.tint != oldWidget.tint) _syncTint();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  void _onPlatformViewCreated(int id) {
    _channel = MethodChannel('aporah/glass_view_$id');
    // The view was created with the brightness `_nativeDark` held at build
    // time; catch it up if the palette moved on while it was being set up.
    _syncBrightness();
    if (_tintPending) _syncTint();
  }

  @override
  Widget build(BuildContext context) {
    return UiKitView(
      viewType: 'aporah/glass_view',
      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
      onPlatformViewCreated: _onPlatformViewCreated,
      creationParams: {
        'tint': widget.tint?.toARGB32(),
        'interactive': widget.interactive,
        'style': widget.style,
        'dark': AppColors.isDark,
      },
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}
