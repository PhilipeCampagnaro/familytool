import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Puts up the system's own action sheet — a title and a column of choices —
/// over the "aporah/action_sheet" channel registered in
/// `ios/Runner/AppDelegate.swift` (see `ios/Runner/ActionSheet.swift`).
///
/// **Not the default way to offer a choice**: [showAnchoredMenu] is, and it
/// stays that way everywhere it works. This is for a menu opened from inside a
/// sheet that carries native glass buttons, where Flutter content composited
/// after a platform view can be dropped whole on device — the failure that
/// already ate a sheet title and, later, the event sheet's route menu.
/// `UIAlertController` is presented by UIKit, so there is no Flutter layer left
/// to lose.
const _channel = MethodChannel('aporah/action_sheet');

/// Returned instead of an index when the user backed out of the sheet.
const actionSheetCancelled = -1;

/// The index of the picked option, [actionSheetCancelled] if it was dismissed,
/// or **null when this platform has no action sheet to put up** — off iOS, and
/// on iOS if there was nothing to present from. A null is the caller's cue to
/// fall back to the app's own menu rather than to do nothing.
Future<int?> showNativeActionSheet({
  required List<String> options,
  required String cancelLabel,
  required bool dark,
  String? title,
  String? message,
}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS || options.isEmpty) return null;
  try {
    return await _channel.invokeMethod<int>('show', {
      'options': options,
      'cancel': cancelLabel,
      'dark': dark,
      'title': title,
      'message': message,
    });
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}
