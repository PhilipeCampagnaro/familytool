import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The device's copy of the calendar.
///
/// This file is what makes it possible for Aporah's server to hold no calendar
/// data at all. Google, Outlook, iCloud and IServ events are proxied live and
/// never stored in Supabase; without a cache the calendar would be blank on a
/// train, and every cold start would be a spinner. So the events land here
/// instead — on the user's own phone, inside the app container, covered by iOS
/// file protection and deleted with the app.
///
/// One file rather than a database: the whole snapshot is read at startup and
/// replaced whole after every successful fetch. There is no query to run against
/// it that `CalendarRepository` does not already do in memory, and a sqlite
/// dependency to store one JSON document would be a plugin for nothing.
///
/// Everything here fails soft. A cache that will not read or write is a slower
/// calendar, never a broken one — so every method swallows its errors and the
/// caller carries on to the network.
class CalendarCache {
  CalendarCache({this.fileName = 'calendar_cache.json'});

  final String fileName;

  File? _file;

  Future<File?> _resolve() async {
    if (_file != null) return _file;
    try {
      final dir = await getApplicationSupportDirectory();
      return _file = File('${dir.path}/$fileName');
    } catch (_) {
      // No writable directory (a test host, a locked container). The app works,
      // it just has no offline calendar.
      return null;
    }
  }

  /// The last snapshot written, or null if there is none.
  ///
  /// [maxAge] is a ceiling on staleness, not on usefulness: a month-old cache is
  /// still worth showing while the network answers, so callers pass a generous
  /// value and rely on the refresh that follows.
  Future<Map<String, dynamic>?> read({Duration? maxAge}) async {
    try {
      final file = await _resolve();
      if (file == null || !await file.exists()) return null;

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;

      final written = DateTime.tryParse(decoded['written_at'] as String? ?? '');
      if (written == null) return null;
      if (maxAge != null && DateTime.now().difference(written) > maxAge) return null;

      return decoded;
    } catch (_) {
      // A truncated write (killed mid-save) parses as garbage. Drop it rather
      // than let one bad file wedge the calendar on every launch.
      await clear();
      return null;
    }
  }

  Future<void> write(Map<String, dynamic> snapshot) async {
    try {
      final file = await _resolve();
      if (file == null) return;

      // Written to a sibling and renamed, because rename is atomic: being killed
      // mid-write then leaves the previous good cache in place instead of half a
      // JSON document.
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
        jsonEncode({...snapshot, 'written_at': DateTime.now().toIso8601String()}),
        flush: true,
      );
      await tmp.rename(file.path);
    } catch (_) {
      // Ignored on purpose — see the class comment.
    }
  }

  /// Drops the cache. Called on sign-out: the next person to use this phone must
  /// not find the last household's appointments sitting in a file.
  Future<void> clear() async {
    try {
      final file = await _resolve();
      if (file != null && await file.exists()) await file.delete();
    } catch (_) {
      // Ignored on purpose — see the class comment.
    }
  }
}
