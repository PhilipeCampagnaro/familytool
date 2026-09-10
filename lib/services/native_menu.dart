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

  /// A filled dot in this colour instead of a [symbol] — a calendar's colour is
  /// data rather than an icon, and there is no SF Symbol for "green".
  final Color? color;

  /// The caption over this row's section, taken from the first row of it — an
  /// inline submenu's title, which is the only header a `UIMenu` has.
  final String? sectionTitle;

  /// Rows sharing a number are drawn as one group, with a hairline above it.
  /// UIKit has no indent, so a calendar sits in its account's group rather than
  /// under its name.
  final int section;

  /// Leaves the menu up when this row is picked, for a row that toggles
  /// something rather than answering the question. It reports itself through
  /// `onKeptOpen` and flips its own checkmark; the menu goes on waiting for a
  /// real answer.
  final bool keepsOpen;

  const NativeMenuOption(
    this.label, {
    this.symbol,
    this.destructive = false,
    this.selected = false,
    this.color,
    this.section = 0,
    this.sectionTitle,
    this.keepsOpen = false,
  });
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
  void Function(int index)? onKeptOpen,
}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS || options.isEmpty) return null;
  // A tap that lands while the last one's menu is still coming up is the same
  // tap twice. Answered as a cancel, never as `null`: `null` would send this
  // caller off to draw the app's own dropdown under the system menu the first
  // tap is already opening — two menus for one gesture.
  //
  // A window rather than a flag held for as long as the menu is up: two taps a
  // second apart are two gestures, and the native side handles that properly by
  // cancelling the first menu. A flag would also have to be cleared by
  // something, and the one thing worse than two menus is none, forever.
  final now = DateTime.now();
  if (_lastRequest != null && now.difference(_lastRequest!) < _doubleTapWindow) {
    return nativeMenuCancelled;
  }
  _lastRequest = now;
  _installKeptOpenHandler();
  _onKeptOpen = onKeptOpen;
  try {
    return await _channel.invokeMethod<int>('show', {
      'options': [
        for (final o in options)
          {
            'label': o.label,
            'symbol': o.symbol,
            'destructive': o.destructive,
            'selected': o.selected,
            'section': o.section,
            'sectionTitle': o.sectionTitle,
            'keepsOpen': o.keepsOpen,
            if (o.color != null) 'color': o.color!.toARGB32(),
          },
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
  } finally {
    _onKeptOpen = null;
  }
}

/// When the last menu was asked for, and how close behind it a second request
/// is treated as the same tap arriving twice.
DateTime? _lastRequest;
const _doubleTapWindow = Duration(milliseconds: 500);

/// Re-draws the menu that is up with a fresh checkmark per row, for a menu
/// whose rows [NativeMenuOption.keepsOpen] — one tick can move the others, and
/// the presented menu is a snapshot UIKit never re-asks for. Same order and
/// length as the options it was opened with; a mismatch is ignored rather than
/// half-applied. A no-op where there is no such menu.
Future<void> updateNativeMenuSelection(List<bool> selected) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
  try {
    await _channel.invokeMethod<void>('update', {'selected': selected});
  } on PlatformException {
    // Nothing to update is not a failure worth reporting to a menu row.
  } on MissingPluginException {
    // Same.
  }
}

/// The open menu's [showNativeMenu.onKeptOpen], if it has such a row. One menu
/// is up at a time, so one callback is all there is to keep.
void Function(int index)? _onKeptOpen;
bool _keptOpenHandlerInstalled = false;

void _installKeptOpenHandler() {
  if (_keptOpenHandlerInstalled) return;
  _keptOpenHandlerInstalled = true;
  _channel.setMethodCallHandler((call) async {
    if (call.method != 'keptOpen') return null;
    final index = (call.arguments as Map?)?['index'] as int?;
    if (index != null) _onKeptOpen?.call(index);
    return null;
  });
}
