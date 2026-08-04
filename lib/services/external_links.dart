import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Opens a URL outside the app (Safari, or whichever app claims the scheme).
///
/// Flutter has no built-in for this and the app takes no plugins for it: the
/// iOS side is a dozen lines of `UIApplication.open` on a method channel
/// registered in `ios/Runner/AppDelegate.swift` under "aporah/links". Off iOS
/// there's no handler, so this is a no-op — the same trade the native tab bar,
/// switch and search field already make.
const _channel = MethodChannel('aporah/links');

/// Returns whether the URL was actually handed off.
Future<bool> openExternalUrl(String url) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return false;
  try {
    return await _channel.invokeMethod<bool>('open', {'url': url}) ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// Amazon's search URL for [query] — the German store, matching the app's
/// German copy and the merchants the Listen screen already ships icons for.
String amazonSearchUrl(String query) => 'https://www.amazon.de/s?k=${Uri.encodeQueryComponent(query)}';
