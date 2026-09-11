import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import 'bottom_nav.dart';
import 'native_occlusion.dart';

/// The iPhone's own tab bar: a real `UITabBar` embedded as a platform view
/// (see ios/Runner/TabBarPlatformView.swift, registered under
/// "aporah/tab_bar"). On iOS 26 that is Apple's floating Liquid Glass bar —
/// the glass capsule, the selection pill sliding between tabs, the shimmer
/// under a finger and the SF Symbol animation are all UIKit's, not redrawn
/// here. Older iOS renders the same bar in its classic translucent style.
///
/// Flutter owns the selection: UIKit reports taps over a method channel and
/// [onTap] drives the app's index, which is pushed back down so the two can't
/// drift apart (e.g. if a tab change comes from somewhere other than the bar).
class NativeTabBar extends StatefulWidget {
  final int index;

  /// Awaited, and that matters: `UITabBar` selects the item under the finger
  /// itself, so after a tap UIKit's selection is whatever was tapped whether or
  /// not the app agreed. **Mehr** puts up a menu and only changes tab if a row
  /// is picked, so a dismissed menu would leave the bar highlighting a tab
  /// nobody is on. Once [onTap] has settled, the app's index is pushed back
  /// down and the two agree again.
  final Future<void> Function(int) onTap;

  /// Reports the height UIKit laid the bar out at, once it has one. Nothing
  /// in Dart can predict it — an iOS 26 capsule is a good deal taller than the
  /// classic bar — so anything that has to line up with the bar's centre (the
  /// compacted nav button in `AppShell`) has to be told rather than assume
  /// [kNativeTabBarHeight].
  final ValueChanged<double>? onHeight;

  const NativeTabBar({super.key, required this.index, required this.onTap, this.onHeight});

  @override
  State<NativeTabBar> createState() => _NativeTabBarState();
}

class _NativeTabBarState extends State<NativeTabBar> {
  MethodChannel? _channel;

  /// Mirrors [AppColors.isDark] into the embedded UIKit control. Tracked here
  /// because the theme is an in-app setting, so there's no device-appearance
  /// change for UIKit to pick up on its own.
  bool _nativeDark = AppColors.isDark;

  void _syncBrightness() {
    if (_nativeDark == AppColors.isDark) return;
    _nativeDark = AppColors.isDark;
    _channel?.invokeMethod('setBrightness', {'dark': _nativeDark});
  }

  /// Same problem as the brightness, same fix: the titles go to UIKit once, in
  /// `creationParams`, so without this the system tab bar would keep the
  /// language it was born in while every other word in the app changed.
  String _nativeLocale = L.s.localeCode;

  void _syncLabels() {
    if (_nativeLocale == L.s.localeCode) return;
    _nativeLocale = L.s.localeCode;
    _channel?.invokeMethod('setLabels', {
      'labels': [for (final tab in navTabs) tab.label],
    });
  }

  /// The size UIKit lays the bar out at, once it has told us. On iOS 26 the
  /// width is the floating capsule's, which is narrower than the screen — so
  /// the platform view is sized to it rather than stretched, otherwise the bar
  /// would be laid out as a full-width one.
  Size? _intrinsicSize;

  @override
  void didUpdateWidget(NativeTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncBrightness();
    _syncLabels();
    if (widget.index != oldWidget.index) {
      _channel?.invokeMethod('setSelectedIndex', {'index': widget.index});
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _onPlatformViewCreated(int id) async {
    final channel = MethodChannel('aporah/tab_bar_$id');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'tabSelected') {
        final index = (call.arguments as Map?)?['index'] as int?;
        if (index != null) await _tapped(index);
      }
      return null;
    });
    _channel = channel;

    final size = await channel.invokeMapMethod<String, double>('getIntrinsicSize');
    if (!mounted || size == null) return;
    final width = size['width'] ?? 0;
    final height = size['height'] ?? 0;
    if (width <= 0 || height <= 0) return;
    setState(() => _intrinsicSize = Size(width, height));
    widget.onHeight?.call(height);
  }

  /// Reports a tap and then makes UIKit's selection match the app's.
  ///
  /// The re-push is a no-op in the ordinary case — the tab changed, so
  /// [didUpdateWidget] has already sent the same index — and it is the whole
  /// point in the one case that isn't: a **Mehr** menu that was dismissed.
  Future<void> _tapped(int index) async {
    // Reported even when it is the tab already on screen: the shell drops a
    // repeat tap on an ordinary tab, and **Mehr** wants it, because tapping it
    // again is how you swap Boxen for Ausgaben.
    await widget.onTap(index);
    if (!mounted || widget.index == index) return;
    _channel?.invokeMethod('setSelectedIndex', {'index': widget.index});
  }

  @override
  Widget build(BuildContext context) {
    final size = _intrinsicSize;
    // A bar left behind an open sheet paints straight through it — see
    // [occludedByRoute]. It gives up the space rather than falling back to the
    // Flutter nav: every sheet is anchored to the bottom and covers the bar
    // anyway, so there is nothing there to draw, and swapping in a different
    // control would only be visible if the swap went wrong. The box it leaves
    // keeps the layout still.
    if (occludedByRoute(context)) {
      return SizedBox(width: size?.width, height: size?.height ?? kNativeTabBarHeight);
    }
    return SizedBox(
      width: size?.width,
      height: size?.height ?? kNativeTabBarHeight,
      // Hidden for the frame or two before UIKit reports its geometry, so the
      // bar doesn't appear full-width and then snap to a capsule.
      child: Opacity(
        opacity: size == null ? 0 : 1,
        child: UiKitView(
          viewType: 'aporah/tab_bar',
          onPlatformViewCreated: _onPlatformViewCreated,
          // Taps are UIKit's to handle — the bar has to see touch-down the
          // moment it happens or the press shimmer and the highlight lag
          // behind the finger. Nothing scrollable sits above the bar for this
          // to steal gestures from.
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
          },
          creationParams: {
            'labels': [for (final tab in navTabs) tab.label],
            'symbols': [for (final tab in navTabs) tab.sfSymbol],
            'selectedSymbols': [for (final tab in navTabs) tab.sfSymbolSelected],
            'selectedIndex': widget.index,
            'tint': AppColors.accent.toARGB32(),
            'unselectedTint': AppColors.muted.toARGB32(),
            'dark': AppColors.isDark,
          },
          creationParamsCodec: const StandardMessageCodec(),
        ),
      ),
    );
  }
}
