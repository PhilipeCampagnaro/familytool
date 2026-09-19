import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../models/picked_file.dart';
import 'external_links.dart';

/// A town's waste-calendar page, opened inside the app so the `.ics` its
/// export button produces comes back here — `ios/Runner/CalendarPageBrowser.swift`
/// behind the "aporah/calendarPage" channel.
///
/// **iOS only, because only iOS needs it.** Safari hands a `text/calendar`
/// download straight to Apple Calendar's "Add" sheet, so an iPhone never has a
/// file to upload. Android's browser saves it to Downloads, where the ordinary
/// picker finds it, so there the page opens in the browser as before.
const _channel = MethodChannel('aporah/calendarPage');

bool get calendarPageBrowserAvailable => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Opens [url] (https only) and returns the calendar file the household
/// downloaded there — in the media picker's shape, so [readPickedText] reads
/// and deletes it — or null when they closed the page without one.
Future<PickedFile?> fetchCalendarFromPage(String url) async {
  if (!calendarPageBrowserAvailable) return null;
  try {
    final picked = await _channel.invokeMapMethod<String, dynamic>('open', {
      'url': url,
      'labels': {
        'prompt': L.s.calendarPagePrompt,
        'notCalendar': L.s.calendarPageNotCalendar,
        'failed': L.s.calendarPageFailed,
        'ok': L.s.ok,
      },
    });
    if (picked == null) return null;
    return PickedFile(path: picked['path'] as String, name: picked['name'] as String, isImage: false);
  } on PlatformException catch (e) {
    // The page could not be put up. Safari at least shows it, and is exactly
    // where the household was before this existed.
    debugPrint('calendarPage: $e');
    await openExternalUrl(url);
    return null;
  } on MissingPluginException {
    // A build without the native side (a hot restart after adding it, say).
    debugPrint('calendarPage: no native handler — rebuild the app');
    await openExternalUrl(url);
    return null;
  }
}
