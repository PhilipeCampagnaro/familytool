import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Hands text and a link to the system share sheet — `UIActivityViewController`
/// on iOS (ios/Runner/ShareSheet.swift), the chooser on Android
/// (ShareChannel.kt), both under "aporah/share". A bit of native code rather
/// than `share_plus`, for the same reason as the other channels: the iOS build
/// has no Podfile, and the iOS half is forty lines.
const _channel = MethodChannel('aporah/share');

/// What became of the sheet — the question the caller revokes a link on.
enum ShareOutcome {
  /// Something was picked and it went through, "Kopieren" included.
  sent,

  /// The sheet was closed without sending. Only iOS can say so.
  cancelled,

  /// A sheet appeared and the platform does not report what happened (Android).
  unconfirmed,

  /// No sheet could be shown, so the link went to the clipboard instead.
  copied,
}

/// Shows the share sheet for [text] and [url].
///
/// [anchor] is the control that asked, in global logical pixels — iPad presents
/// the sheet as a popover pointing at it; a phone ignores it.
Future<ShareOutcome> shareOut({required String text, required String url, Rect? anchor}) async {
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android)) {
    try {
      final sent = await _channel.invokeMethod<bool>('share', {
        'text': text,
        'url': url,
        if (anchor != null)
          'anchor': {'x': anchor.left, 'y': anchor.top, 'w': anchor.width, 'h': anchor.height},
      });
      if (defaultTargetPlatform == TargetPlatform.android) return ShareOutcome.unconfirmed;
      // iOS answers nil only when there was nothing to present from.
      if (sent != null) return sent ? ShareOutcome.sent : ShareOutcome.cancelled;
    } on PlatformException {
      // Fall through to the clipboard.
    } on MissingPluginException {
      // Fall through to the clipboard.
    }
  }
  await Clipboard.setData(ClipboardData(text: '$text\n$url'));
  return ShareOutcome.copied;
}
