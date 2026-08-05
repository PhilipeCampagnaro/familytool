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

/// The navigation apps the event-detail sheet's "Route" button offers.
///
/// [label] is a brand, so it is *not* in `lib/l10n/` — same call as the shop
/// names in `data/merchant_logos.dart`: a company is called what it is called
/// in both languages.
enum NavigationApp {
  waze('Waze'),
  googleMaps('Google Maps');

  final String label;

  const NavigationApp(this.label);
}

/// Starts navigation to a place in [app].
///
/// [latitude]/[longitude] come from the map we already rendered for this event
/// ([MapView] in `map_snapshot.dart`); when there are none — the geocoder could
/// not place it — the raw [query] goes over instead, and the app opens on its
/// own search for it rather than not opening at all.
///
/// The app's own URL scheme is tried first and the website is the fallback, in
/// that order, because `UIApplication.open` reports back whether anything
/// claimed the scheme. That is what makes this work with no
/// `LSApplicationQueriesSchemes` entry and no `canOpenURL`: a household without
/// Waze installed simply lands on waze.com.
Future<void> openNavigation(
  NavigationApp app, {
  required String query,
  double? latitude,
  double? longitude,
}) async {
  final point = latitude != null && longitude != null ? '$latitude,$longitude' : null;
  final destination = point ?? Uri.encodeQueryComponent(query);

  final (String scheme, String web) = switch (app) {
    NavigationApp.waze => (
      point != null ? 'waze://?ll=$point&navigate=yes' : 'waze://?q=$destination&navigate=yes',
      point != null
          ? 'https://waze.com/ul?ll=$point&navigate=yes'
          : 'https://waze.com/ul?q=$destination&navigate=yes',
    ),
    NavigationApp.googleMaps => (
      'comgooglemaps://?daddr=$destination&directionsmode=driving',
      'https://www.google.com/maps/dir/?api=1&destination=$destination',
    ),
  };

  if (await openExternalUrl(scheme)) return;
  await openExternalUrl(web);
}
