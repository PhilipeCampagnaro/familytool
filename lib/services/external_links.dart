import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

/// Opens a URL outside the app (Safari, or whichever app claims the scheme).
///
/// The iOS side is a dozen lines of `UIApplication.open` on a method channel
/// registered in `ios/Runner/AppDelegate.swift` under "aporah/links"; Android
/// goes through `url_launcher`. Two routes rather than one because the native
/// one is free on iOS, where the channel exists anyway for the pickers and the
/// menus, and because the plugin is the whole of the work on Android.
const _channel = MethodChannel('aporah/links');

/// Returns whether the URL was actually handed off.
///
/// **The bool is load-bearing, not a courtesy.** [openNavigation] tries an app's
/// own scheme and falls back to its website on false, which is what lets a
/// household without Waze installed land on waze.com with no `canOpenURL` on
/// iOS and no `<queries>` guesswork on Android. Both platforms report the same
/// thing here: iOS because `UIApplication.open` says whether anything claimed
/// the scheme, Android because `startActivity` throws when nothing does.
Future<bool> openExternalUrl(String url) async {
  if (kIsWeb) return false;

  if (defaultTargetPlatform == TargetPlatform.iOS) {
    try {
      return await _channel.invokeMethod<bool>('open', {'url': url}) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  if (defaultTargetPlatform != TargetPlatform.android) return false;

  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  try {
    // `externalApplication` rather than the default: a shop page belongs in the
    // browser the household actually uses, with their logins and their basket,
    // not in an in-app tab that forgets both.
    return await launcher.launchUrl(uri, mode: launcher.LaunchMode.externalApplication);
  } on PlatformException {
    // Nothing on the device claims the scheme. That is an answer, not an error —
    // see the note on the return value above.
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// What a pasted link turns into before it is stored, or `null` when there is
/// no URL in there at all.
///
/// People paste `amazon.de/dp/B0…` and `www.rewe.de/…` as often as they paste a
/// full URL, so a missing scheme is filled in with `https` rather than refused
/// — the alternative is an error message about something the app can plainly
/// work out. What is refused is anything without a dotted host and anything
/// whose scheme we would not hand to the device: `javascript:` and `file:` are
/// not links to a shop, and `list_items_link_url_shape` would reject them on
/// arrival anyway.
String? normalizeExternalUrl(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  final withScheme = text.contains('://') ? text : 'https://$text';
  final uri = Uri.tryParse(withScheme);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  // A host with no dot is a typo or a hostname on somebody's LAN; either way it
  // is not the shop page this field is for.
  if (!uri.host.contains('.')) return null;
  return uri.toString();
}

/// The short name a link is shown under — its host without `www.`, e.g.
/// `amazon.de`. Never the whole URL: a product URL is sixty characters of
/// tracking parameters and says less about where it leads than the domain does.
String urlLabel(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  if (host.isEmpty) return url;
  return host.startsWith('www.') ? host.substring(4) : host;
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
/// that order, because both platforms report whether anything claimed the
/// scheme. That is what makes this work with no `LSApplicationQueriesSchemes`
/// entry and no `canOpenURL`: a household without Waze installed simply lands
/// on waze.com.
///
/// **On Android the Google Maps scheme always misses, and that is the right
/// outcome.** `comgooglemaps://` is an iOS-only scheme, so the first attempt
/// fails and the https fallback goes out — which Google Maps claims with its own
/// intent filter, so an Android household with the app installed still lands in
/// it rather than in a browser. Waze's scheme is the same on both, and is
/// declared in the manifest's `<queries>` so package visibility does not turn
/// every answer into "no".
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
