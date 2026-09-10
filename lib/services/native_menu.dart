import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Puts up the system's own menu **beside the control that was tapped**, over
/// the "aporah/menu" channel registered in `ios/Runner/AppDelegate.swift` (see
/// `ios/Runner/NativeMenu.swift`).
///
/// **Not the default way to offer a choice**: [showAnchoredMenu] is, and it
/// stays that way everywhere it works. This is for a menu opened from inside a
/// sheet that carries native glass buttons, where Flutter content composited
/// after a platform view can be dropped whole on device — the failure that
/// already ate a sheet title and, later, the event sheet's route menu. UIKit
/// presents this one, so there is no Flutter layer left to lose.
///
/// It used to be a `UIAlertController` action sheet, and that was the wrong
/// shape for the trap it was solving: you pressed a row halfway up a sheet and
/// the answer appeared at the bottom of the display, detached from the thing
/// you pressed. A `UIMenu` is the bubble iOS itself grows out of a control, so
/// this and the app's own dropdown are now the same gesture drawn by two
/// different hands. The old sheet survives as the pre-iOS 17.4 fallback, on the
/// native side — the version that first lets a button be told to show its own
/// menu with no finger on it.
const _channel = MethodChannel('aporah/menu');

/// Returned instead of an index when the user backed out of the menu.
const nativeMenuCancelled = -1;

/// One row of a [showNativeMenu].
class NativeMenuOption {
  final String label;

  /// An **SF Symbol** name for the row's glyph, e.g. `photo`. The app draws
  /// Phosphor everywhere it paints its own menus, but this menu is UIKit's and
  /// takes UIKit's icons; a row with no symbol simply has no glyph.
  final String? symbol;

  /// Draws the row in the system's destructive red.
  final bool destructive;

  /// Puts a checkmark on the row — the system's way of showing which of a set
  /// of choices is the one in force.
  final bool selected;

  const NativeMenuOption(this.label, {this.symbol, this.destructive = false, this.selected = false});
}

/// The rect [anchorKey]'s widget occupies on screen, or null if it has not been
/// laid out — which is [showNativeMenu]'s cue to fall back to a sheet.
Rect? anchorRectOf(GlobalKey anchorKey) {
  final box = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// The index of the picked option, [nativeMenuCancelled] if it was dismissed,
/// or **null when this platform has no system menu to put up** — off iOS, and
/// on iOS if there was nothing to present from. A null is the caller's cue to
/// fall back to the app's own dropdown rather than to do nothing.
///
/// [anchor] is the tapped control's rect in global coordinates
/// ([anchorRectOf]); without one the native side puts up the pre-iOS 16 action
/// sheet instead, which is why [cancelLabel] is still required.
Future<int?> showNativeMenu({
  required List<NativeMenuOption> options,
  required String cancelLabel,
  required bool dark,
  Rect? anchor,
  String? title,
  String? message,
}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS || options.isEmpty) return null;
  try {
    return await _channel.invokeMethod<int>('show', {
      'options': [
        for (final o in options)
          {'label': o.label, 'symbol': o.symbol, 'destructive': o.destructive, 'selected': o.selected},
      ],
      'cancel': cancelLabel,
      'dark': dark,
      'title': title,
      'message': message,
      if (anchor != null)
        'anchor': {'x': anchor.left, 'y': anchor.top, 'width': anchor.width, 'height': anchor.height},
    });
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}
