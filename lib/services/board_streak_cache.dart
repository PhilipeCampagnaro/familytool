import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The device's record of how each day on the Board went.
///
/// It exists because `public.tasks` is not an archive and was never meant to be:
/// `BoardRepository.fetchBoard` only loads finished tasks from the last two
/// weeks, and "Erledigte löschen" deletes them outright. A tracker strip built
/// from the live rows alone would therefore be a fortnight deep at best and
/// would go blank the moment somebody tidied up — so the days are stamped here
/// as they happen and kept after the rows they were computed from are gone.
///
/// What is kept is **two integers per day and nothing else** — how many tasks
/// were due, how many were done. No text, no ids, no names: this file is worth
/// far less to whoever finds the phone than the calendar cache sitting next to
/// it, which is deliberate for a record that outlives everything else.
///
/// Same shape and the same failure rule as [CalendarCache]: one JSON document,
/// read once and rewritten whole, every error swallowed. A ledger that will not
/// read or write costs the strip its history, never the Board its screen.
class BoardStreakCache {
  BoardStreakCache({this.fileName = 'board_streak.json'});

  final String fileName;

  /// How far back days are kept. Well past the fourteen the strip draws, so the
  /// history is there if the strip ever grows, but bounded — a family that uses
  /// the Board for five years must not carry every one of those days around.
  static const retentionDays = 180;

  File? _file;

  Future<File?> _resolve() async {
    if (_file != null) return _file;
    try {
      final dir = await getApplicationSupportDirectory();
      return _file = File('${dir.path}/$fileName');
    } catch (_) {
      // No writable directory (a test host, a locked container). The Board
      // works, its strip just forgets everything older than the loaded rows.
      return null;
    }
  }

  /// `'2026-08-04' -> [done, planned]`, already pruned to [retentionDays].
  ///
  /// ISO day keys rather than epoch numbers so they sort and compare as plain
  /// strings — pruning is a `compareTo` against one cut-off key, with no date
  /// parsing and so no way for a malformed entry to throw the whole read away.
  Future<Map<String, List<int>>> read() async {
    try {
      final file = await _resolve();
      if (file == null || !await file.exists()) return {};

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return {};

      final cutoff = _cutoffKey();
      final days = <String, List<int>>{};
      for (final entry in decoded.entries) {
        if (entry.key.compareTo(cutoff) < 0) continue;
        final value = entry.value;
        if (value is! List || value.length != 2) continue;
        final done = value[0], planned = value[1];
        if (done is! int || planned is! int) continue;
        days[entry.key] = [done, planned];
      }
      return days;
    } catch (_) {
      // A truncated write (killed mid-save) parses as garbage. Drop it rather
      // than let one bad file cost the strip its history on every launch.
      await clear();
      return {};
    }
  }

  Future<void> write(Map<String, List<int>> days) async {
    try {
      final file = await _resolve();
      if (file == null) return;

      final cutoff = _cutoffKey();
      final kept = {
        for (final entry in days.entries)
          if (entry.key.compareTo(cutoff) >= 0) entry.key: entry.value,
      };

      // Written to a sibling and renamed, because rename is atomic: being killed
      // mid-write then leaves the previous good ledger in place instead of half
      // a JSON document.
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(kept), flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      // Ignored on purpose — see the class comment.
    }
  }

  /// Drops the ledger. Called on sign-out with the calendar cache: how busy the
  /// last household's days were is still their business, not the next person's.
  Future<void> clear() async {
    try {
      final file = await _resolve();
      if (file != null && await file.exists()) await file.delete();
    } catch (_) {
      // Ignored on purpose — see the class comment.
    }
  }

  /// The oldest day key still worth keeping.
  static String _cutoffKey() {
    final now = DateTime.now();
    return dayKey(DateTime(now.year, now.month, now.day - retentionDays));
  }

  /// The one place the on-disk key format is decided, so the notifier that
  /// encodes and the pruning that compares can never drift apart.
  static String dayKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  static DateTime? parseDayKey(String key) {
    final parsed = DateTime.tryParse(key);
    return parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day);
  }
}
