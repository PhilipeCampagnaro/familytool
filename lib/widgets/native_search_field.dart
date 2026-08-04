import 'package:flutter/foundation.dart' show Factory, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/tokens.dart';

/// Height used before UIKit reports its own — and the fixed height of the
/// non-iOS fallback, so the two lay out the same.
const double kNativeSearchFieldHeight = 52;

/// Which system control [NativeSearchField] embeds.
enum NativeSearchFieldStyle {
  /// A whole `UISearchBar`: it brings its own Cancel button, which animates in
  /// beside the contracting field on focus, and it decides its own height.
  /// This is the standalone search of a page (Settings).
  bar,

  /// Just the rounded `UISearchTextField` inside that bar, sized to whatever
  /// height it's given. Used where the surrounding UI already provides the way
  /// out — the screen headers put a glass X beside it — and where a 52pt bar
  /// wouldn't fit the row.
  field,
}

/// The iPhone's own search field: a real `UISearchBar` embedded as a platform
/// view (see ios/Runner/SearchFieldPlatformView.swift, registered under
/// "aporah/search_field"), the same approach as [NativeTabBar].
///
/// Everything that makes it feel like iOS is UIKit's, not redrawn here: the
/// field shrinking aside as a Cancel/X control animates in on focus, the
/// magnifier glyph, the clear button, the scribble/dictation affordances and
/// the automatic accessibility behaviour. Flutter only learns the query, over
/// a per-view method channel.
///
/// Off iOS there's no such control to embed, so it falls back to a Flutter
/// [TextField] in the app's flat search-pill shape — the same fallback split
/// `GlassSurface` makes.
class NativeSearchField extends StatefulWidget {
  final String placeholder;
  final ValueChanged<String> onChanged;

  /// [NativeSearchFieldStyle.bar] sizes itself; [NativeSearchFieldStyle.field]
  /// fills the height its parent gives it.
  final NativeSearchFieldStyle style;

  /// Raise the keyboard as soon as the field exists. For the header search,
  /// which only appears because the user just asked for it.
  final bool autofocus;

  const NativeSearchField({
    super.key,
    required this.placeholder,
    required this.onChanged,
    this.style = NativeSearchFieldStyle.bar,
    this.autofocus = false,
  });

  static bool get _isNative => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  State<NativeSearchField> createState() => _NativeSearchFieldState();
}

class _NativeSearchFieldState extends State<NativeSearchField> {
  MethodChannel? _channel;

  /// The height UIKit lays the bar out at, once it has told us. Reported
  /// rather than hardcoded for the same reason as the tab bar's: the control's
  /// metrics are the system's and change with the OS version and text size.
  double? _intrinsicHeight;

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
  void didUpdateWidget(NativeSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncBrightness();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _onPlatformViewCreated(int id) async {
    final channel = MethodChannel('aporah/search_field_$id');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'textChanged') {
        widget.onChanged((call.arguments as Map?)?['text'] as String? ?? '');
      }
      return null;
    });
    _channel = channel;

    // Only the self-sizing bar needs measuring; the field style is laid out by
    // whatever row it sits in.
    if (widget.style != NativeSearchFieldStyle.bar) return;
    final size = await channel.invokeMapMethod<String, double>('getIntrinsicSize');
    if (!mounted) return;
    final height = size?['height'] ?? 0;
    if (height <= 0) return;
    setState(() => _intrinsicHeight = height);
  }

  @override
  Widget build(BuildContext context) {
    if (!NativeSearchField._isNative) {
      return _FallbackSearchField(
        placeholder: widget.placeholder,
        onChanged: widget.onChanged,
        autofocus: widget.autofocus,
        fill: widget.style == NativeSearchFieldStyle.field,
      );
    }
    final view = UiKitView(
      viewType: 'aporah/search_field',
      onPlatformViewCreated: _onPlatformViewCreated,
      // Touches are UIKit's: the field has to own tap-to-focus, the caret,
      // text selection and the clear button, and a Flutter recognizer
      // winning any of those sequences breaks editing outright. The cost is
      // that a drag started *on the field* doesn't scroll the page — the
      // rest of the header and all of the content still do.
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
      },
      creationParams: {
        'placeholder': widget.placeholder,
        'tint': AppColors.accent.toARGB32(),
        'style': widget.style.name,
        'autofocus': widget.autofocus,
        'dark': AppColors.isDark,
      },
      creationParamsCodec: const StandardMessageCodec(),
    );
    if (widget.style == NativeSearchFieldStyle.field) return view;
    return SizedBox(height: _intrinsicHeight ?? kNativeSearchFieldHeight, child: view);
  }
}

/// Non-iOS stand-in: the app's flat gray search pill with a live field and a
/// clear button that appears once there's something to clear — the same
/// behaviour the native bar gives for free.
class _FallbackSearchField extends StatefulWidget {
  final String placeholder;
  final ValueChanged<String> onChanged;
  final bool autofocus;

  /// Take the height given rather than the bar's own — mirrors
  /// [NativeSearchFieldStyle.field].
  final bool fill;

  const _FallbackSearchField({required this.placeholder, required this.onChanged, this.autofocus = false, this.fill = false});

  @override
  State<_FallbackSearchField> createState() => _FallbackSearchFieldState();
}

class _FallbackSearchFieldState extends State<_FallbackSearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pill = DecoratedBox(
      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(AppRadii.chip)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Row(
          children: [
            Icon(LucideIcons.search, size: 17, color: AppColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _controller,
                autofocus: widget.autofocus,
                textAlignVertical: TextAlignVertical.center,
                textInputAction: TextInputAction.search,
                style: AppText.searchInput,
                onChanged: widget.onChanged,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: widget.placeholder,
                  hintStyle: AppText.searchInput.copyWith(color: AppColors.muted),
                ),
              ),
            ),
            // No clear button in the filling variant: whatever laid it out has
            // its own X beside it (the header's glass one), and UIKit's
            // equivalent is switched off for the same reason.
            if (!widget.fill)
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) => value.text.isEmpty
                    ? const SizedBox.shrink()
                    : GestureDetector(
                        onTap: () {
                          _controller.clear();
                          widget.onChanged('');
                        },
                        child: Icon(LucideIcons.circleX, size: 17, color: AppColors.muted),
                      ),
              ),
          ],
        ),
      ),
    );
    // Filling means taking the row's height; otherwise the pill keeps the
    // native bar's own metrics so both variants lay out alike.
    if (widget.fill) return pill;
    return SizedBox(height: kNativeSearchFieldHeight, child: Center(child: pill));
  }
}
