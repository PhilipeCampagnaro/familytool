import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/foundation.dart' show Factory, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/tokens.dart';

/// Size used before UIKit reports its own — `UISwitch`'s long-standing
/// intrinsic size, and the box the non-iOS fallback is centered in so the two
/// lay out the same.
const Size kNativeSwitchSize = Size(51, 31);

/// The iPhone's own switch: a real `UISwitch` embedded as a platform view (see
/// ios/Runner/SwitchPlatformView.swift, registered under "aporah/switch"), the
/// same approach as [NativeSearchField] and [NativeTabBar].
///
/// Worth a platform view even though Flutter ships `CupertinoSwitch`: that
/// widget redraws the *pre-iOS 26* switch, so it misses the Liquid Glass knob
/// and the press/settle response the rest of this app's native chrome has. The
/// real control also brings drag-to-toggle, the commit haptic, the system
/// on-tint and the accessibility story, and keeps following the OS as it
/// changes.
///
/// Off iOS there's no such control to embed, so it falls back to
/// `Switch.adaptive` — Material's switch everywhere it matters, the same
/// fallback split `GlassSurface` makes.
class NativeSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const NativeSwitch({super.key, required this.value, required this.onChanged});

  static bool get _isNative => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  State<NativeSwitch> createState() => _NativeSwitchState();
}

/// The same on/off row, drawn by Flutter — for use **inside a `showAppSheet`
/// body**, where [NativeSwitch] must not go.
///
/// Not a style preference; a compositing limit. Every sheet's header already
/// embeds two platform views (the glass X and the check are each a
/// `NativeGlassView`), and adding a third inside the scrolling body makes iOS
/// drop the overlay layer holding everything painted after it. The first sheet
/// to try it — the Kalender event form — laid out correctly and rendered as
/// blank white below the switch: the Beginn/Ende rows, the calendar picker and
/// the notes field were all there, all invisible. It is the same failure
/// `showAppSheet`'s header documents, where the title vanished on device
/// between those two buttons.
///
/// So: [NativeSwitch] on a *screen*, [SheetSwitch] in a *sheet*. The visible
/// difference is the iOS 26 Liquid Glass knob, which `CupertinoSwitch` doesn't
/// redraw — a smaller price than a form nobody can see.
class SheetSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const SheetSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    // No `activeColor`: the system green is what the real control shows, and
    // matching it is the whole point of standing in for one.
    return CupertinoSwitch(value: value, onChanged: onChanged);
  }
}

class _NativeSwitchState extends State<NativeSwitch> {
  MethodChannel? _channel;

  /// The size UIKit lays the control out at, once it has told us. Reported
  /// rather than hardcoded for the same reason as the search field's: the
  /// control's metrics are the system's and can change with the OS version.
  Size? _intrinsicSize;

  /// What we last told UIKit / last heard from it. Guards the `didUpdateWidget`
  /// push so the state change we ourselves reported doesn't get echoed back as
  /// a redundant `setOn`, which would interrupt the animation UIKit is already
  /// running.
  late bool _nativeValue = widget.value;

  /// Mirrors [AppColors.isDark] into the embedded UIKit control. Tracked here
  /// because the theme is an in-app setting, so there's no device-appearance
  /// change for UIKit to pick up on its own.
  bool _nativeDark = AppColors.isDark;

  void _syncBrightness() {
    if (_nativeDark == AppColors.isDark) return;
    _nativeDark = AppColors.isDark;
    _channel?.invokeMethod('setBrightness', {'dark': _nativeDark});
  }

  @override
  void didUpdateWidget(NativeSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncBrightness();
    // Anything that flips the value from outside this widget (a provider, a
    // reset) has to reach the native control — it holds its own on/off state.
    if (widget.value != _nativeValue) {
      _nativeValue = widget.value;
      _channel?.invokeMethod('setValue', {'value': widget.value});
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _onPlatformViewCreated(int id) async {
    final channel = MethodChannel('aporah/switch_$id');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'valueChanged') {
        final value = (call.arguments as Map?)?['value'] as bool? ?? false;
        _nativeValue = value;
        widget.onChanged(value);
      }
      return null;
    });
    _channel = channel;

    // The view is created with the value we had at creation time; if the
    // provider moved on while it was being set up, catch it up.
    if (widget.value != _nativeValue) {
      _nativeValue = widget.value;
      await channel.invokeMethod('setValue', {'value': widget.value});
    }

    final size = await channel.invokeMapMethod<String, double>('getIntrinsicSize');
    if (!mounted) return;
    final width = size?['width'] ?? 0;
    final height = size?['height'] ?? 0;
    if (width <= 0 || height <= 0) return;
    setState(() => _intrinsicSize = Size(width, height));
  }

  @override
  Widget build(BuildContext context) {
    if (!NativeSwitch._isNative) {
      return Switch.adaptive(value: widget.value, onChanged: widget.onChanged);
    }
    final size = _intrinsicSize ?? kNativeSwitchSize;
    return SizedBox(
      width: size.width,
      height: size.height,
      child: UiKitView(
        viewType: 'aporah/switch',
        onPlatformViewCreated: _onPlatformViewCreated,
        // Touches are UIKit's: the control owns tap, drag-to-toggle and the
        // knob's press state, and a Flutter recognizer winning that sequence
        // would leave it unresponsive. A drag started *on the switch* therefore
        // doesn't scroll the settings list — the rest of the row still does.
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
        },
        creationParams: {'value': widget.value, 'dark': AppColors.isDark},
        creationParamsCodec: const StandardMessageCodec(),
      ),
    );
  }
}
