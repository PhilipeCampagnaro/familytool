// A harness for the recipe importer: run a URL, or a saved page or video
// description, through the real parser and print what a Liste would get.
//
//   flutter test tool/recipe_import/probe.dart --dart-define=probe=https://…
//   flutter test tool/recipe_import/probe.dart --dart-define=probe=--text,a.txt
//
// Run through `flutter test` rather than `dart run` because the models reach
// `L.s` for their labels and therefore pull in Flutter, which `dart run`
// cannot compile. It lives in tool/ and not test/ so that a bare
// `flutter test` never picks it up: it makes network requests and asserts
// nothing. Arguments arrive comma-separated in -Dprobe, because the test
// runner keeps argv for itself.
//
// It exists because the importer's rules are thresholds measured against real
// pages, and a threshold nobody can re-measure is a threshold that rots. There
// are no unit tests here on purpose (see CLAUDE.md): this is a tool for
// looking, run by hand when the heuristics change.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aporah/l10n/l10n.dart';
import 'package:aporah/l10n/strings_de.dart';
import 'package:aporah/services/recipe_fetch.dart';
import 'package:aporah/services/recipe_import.dart';
import 'package:aporah/services/youtube_import.dart';

const _probe = String.fromEnvironment('probe');

void main() => test('probe', () => _run(_probe.split(',')), timeout: const Timeout(Duration(minutes: 5)));

Future<void> _run(List<String> args) async {
  L.s = StringsDe();
  if (args.isEmpty || args.first.isEmpty) {
    stderr.writeln('usage: --dart-define=probe=<url>,… | --text,<file>,…');
    return;
  }
  if (args.first == '--text') {
    for (final path in args.skip(1)) {
      final file = File(path);
      _report(path, parseRecipeText(
        text: file.readAsStringSync(),
        title: path.split('/').last,
        pageUrl: 'file://$path',
      ));
    }
    return;
  }
  for (final arg in args) {
    final url = recipePageUrl(arg);
    if (url == null) {
      stdout.writeln('$arg  NOT A URL');
      continue;
    }
    try {
      final videoId = youtubeVideoId(url);
      final target = videoId == null ? url : youtubeWatchUrl(videoId);
      final html = await fetchRecipePage(target);
      if (videoId == null) {
        _report(arg, parseRecipePage(html: html, pageUrl: arg));
        continue;
      }
      // The same two steps `PlannerNotifier._fromVideo` takes, so what the
      // harness reports is what the card would show.
      final fromDescription = parseYoutubePage(html: html, pageUrl: arg);
      if (fromDescription != null) {
        _report(arg, fromDescription);
        continue;
      }
      final details = youtubeVideoDetails(html);
      final linked = details == null ? null : recipeLinkInDescription(details.description);
      if (linked == null) {
        _report(arg, null);
        continue;
      }
      stdout.writeln('$arg  ↳ following $linked');
      _report(arg, parseRecipePage(html: await fetchRecipePage(linked), pageUrl: arg));
    } catch (e) {
      stdout.writeln('$arg  FETCH FAILED ($e)');
    }
  }
}

void _report(String label, RecipeImport? import) {
  if (import == null) {
    stdout.writeln('$label  —  nothing readable');
    return;
  }
  final plan = import.plan;
  stdout.writeln('$label  —  ${import.source.name}  "${plan.title}"  ${plan.items.length} items');
  for (final item in plan.items) {
    stdout.writeln('    ${(item.quantity ?? '').padRight(8)}${(item.unit ?? '').padRight(10)}${item.name}');
  }
}
