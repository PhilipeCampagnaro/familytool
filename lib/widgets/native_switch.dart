import 'package:flutter/cupertino.dart' show CupertinoColors;
import 'package:flutter/foundation.dart' show Factory, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/tokens.dart';
import 'native_occlusion.dart';

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
///
/// ## It goes in a sheet body too, and that is a reversal
///
/// It used to be forbidden there, and [GlassSwitch] existed to take its place:
/// the Kalender event form shipped with a real `UISwitch` in its "Ganztägig"
/// row and rendered blank white below it — the Beginn/Ende rows, the calendar
/// card and the notes field all laid out at full height and painting nothing.
/// The reading at the time was a headcount: two platform views in every sheet
/// header, a third in the body, and iOS drops the overlay layer carrying
/// everything above them.
///
/// The headcount was the symptom. [occludedByRoute] found the cause — a sheet
/// is a **non-opaque** route, so the whole screen behind it kept its native
/// chrome composited into the same scene, and it was the tab bar and the search
/// field punching up through the sheet that took the body with them. Every
/// native view now stands down for as long as something covers it, which is
/// why the *same* symptom stopped happening everywhere else in the app. The
/// switch was simply never tried again afterwards.
///
/// So a sheet body may hold one. If the blank body ever comes back, the tell is
/// unchanged — a card whose height is right and whose contents aren't there —
/// and the way back is one word: [GlassSwitch] at the call site.
class NativeSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const NativeSwitch({super.key, required this.value, required this.onChanged});

  static bool get _isNative => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  State<NativeSwitch> createState() => _NativeSwitchState();
}

/// The switch drawn by Flutter, for the moments the real one cannot be on
/// screen — **[NativeSwitch] is what a row asks for**, and this is what it
/// falls back to while a sheet or a menu covers it.
///
/// Drawn rather than borrowed from `CupertinoSwitch`, which redraws the
/// *pre-iOS 26* control: a switch that changed shape for as long as a menu was
/// open is the same visible swap the glass buttons used to make, and the whole
/// point of the fallback is that nobody notices it. Same metrics, same system
/// green, and a knob lit with the lift, specular and rim the rest of the app's
/// material uses when it cannot have the real thing ([GlassSurface]'s
/// approximation).
///
/// It is an approximation and stays one. What only the real `UISwitch` has is
/// the knob's stretch as it is dragged and the system's own commit haptic
/// timing; the haptic is fired here, the stretch is not drawn.
///
/// It is also the way back if a platform view in a sheet body ever empties one
/// again — see [NativeSwitch]'s note. That is why it is still a widget of its
/// own rather than a private fallback.
class GlassSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const GlassSwitch({super.key, required this.value, required this.onChanged});

  /// The system green the real control shows, picked off the app's own
  /// brightness rather than the phone's — dark mode here is an in-app setting,
  /// so `CupertinoDynamicColor` resolved against the platform would light the
  /// wrong one whenever the two disagree.
  static Color get _onTrack =>
      AppColors.isDark ? CupertinoColors.systemGreen.darkColor : CupertinoColors.systemGreen.color;

  static Color get _offTrack => AppColors.isDark
      ? CupertinoColors.secondarySystemFill.darkColor
      : CupertinoColors.secondarySystemFill.color;

  void _toggle() {
    // The real control's commit feedback. Without it the two switches in the
    // app feel different even when they look the same.
    HapticFeedback.lightImpact();
    onChanged(!value);
  }

  @override
  Widget build(BuildContext context) {
    const inset = 2.0;
    final knob = kNativeSwitchSize.height - inset * 2;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      // Drag-to-toggle, which the real control has and a bare tap target
      // doesn't: a flick across the switch commits the direction it was going,
      // and a flick back the way it already is does nothing.
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity > 0 && !value) _toggle();
        if (velocity < 0 && value) _toggle();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        width: kNativeSwitchSize.width,
        height: kNativeSwitchSize.height,
        padding: const EdgeInsets.all(inset),
        decoration: BoxDecoration(
          color: value ? _onTrack : _offTrack,
          borderRadius: BorderRadius.circular(kNativeSwitchSize.height / 2),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: _SwitchKnob(size: knob),
        ),
      ),
    );
  }
}

/// The knob: white, and lit the way glass is lit everywhere else in this app —
/// a lift toward white at the top for curvature, a specular off the top-left,
/// a rim, and the thumb shadow that lifts it off the track.
///
/// White in both palettes, unlike every surface token: the real control's knob
/// does not darken in dark mode, and one that did would read as an *off* switch
/// with a hole in it.
class _SwitchKnob extends StatelessWidget {
  final double size;

  const _SwitchKnob({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // A white ball on a white gradient is a flat disc. The foot of it is
        // pulled a tenth of the way toward the muted grey so the sphere has a
        // shaded underside for the specular above to play against.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Color.lerp(Colors.white, AppColors.mutedLight, 0.10)!],
        ),
        border: Border.all(color: AppColors.glassRim, width: 0.5),
        boxShadow: AppShadows.thumb,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.6, -0.8),
            radius: 1.2,
            colors: [AppColors.glassSpecular, AppColors.glassSpecular.withValues(alpha: 0)],
          ),
        ),
      ),
    );
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
    // A switch left behind an open sheet would otherwise paint straight through
    // it — see [occludedByRoute]. It stands down to the drawn one rather than
    // to `Switch.adaptive`, which on iOS is `CupertinoSwitch`: the control
    // would visibly change shape for as long as a menu was open over it.
    if (occludedByRoute(context)) {
      return GlassSwitch(value: widget.value, onChanged: widget.onChanged);
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
