// Reports content-catalog entries that have no Portuguese or Spanish label.
//
// The content catalogs — `grocery_catalog.dart` and `icon_suggestions.dart` —
// deliberately do **not** fail to compile when a translation is missing, unlike
// `AppStrings`. Content has to stay cheap to add:
// a grocery PNG needs one German line to be usable, and holding the catalog
// hostage to four translations would mean nobody ever adds an icon. `pickLabel`
// falls back to English instead.
//
// That fallback is invisible, which is what this script is for. It is the same
// bargain as `check_const_palette.dart`: no baseline to triage, fast, and its
// whole value is that an empty report stays empty.
//
//   dart tool/check_catalog_labels.dart
//
// Only the grocery catalog can actually go untranslated — its labels are keyed
// by file name in a side map. The symbol set takes all four names in its
// constructor, so the compiler already covers it.
import 'dart:io';

void main() {
  final source = File('lib/data/grocery_catalog.dart').readAsStringSync();

  final files = RegExp(r"GroceryIcon\('([^']+)'")
      .allMatches(_catalogSection(source))
      .map((m) => m.group(1)!)
      .toSet();

  final pt = _mapKeys(source, '_ptLabels');
  final es = _mapKeys(source, '_esLabels');

  final missingPt = files.difference(pt).toList()..sort();
  final missingEs = files.difference(es).toList()..sort();

  // A key with no icon behind it is the other half of the same mistake: a file
  // renamed in the catalog leaves its translation stranded and unreachable.
  final strandedPt = pt.difference(files).toList()..sort();
  final strandedEs = es.difference(files).toList()..sort();

  var bad = false;
  bad |= _report('Portuguese label missing', missingPt);
  bad |= _report('Spanish label missing', missingEs);
  bad |= _report('Portuguese label for no such icon', strandedPt);
  bad |= _report('Spanish label for no such icon', strandedEs);

  if (bad) {
    exitCode = 1;
    return;
  }
  stdout.writeln('OK — ${files.length} grocery icons, all four languages.');
}

/// The catalog literal only. The override maps below it use the same quoting and
/// would otherwise be scanned as if they declared icons.
String _catalogSection(String source) {
  final start = source.indexOf('const groceryCategories');
  final end = source.indexOf('\n// ---', start);
  return source.substring(start, end == -1 ? source.length : end);
}

Set<String> _mapKeys(String source, String name) {
  final start = source.indexOf('const $name = <String, String>{');
  if (start == -1) return {};
  final end = source.indexOf('\n};', start);
  final body = source.substring(start, end == -1 ? source.length : end);
  return RegExp(r"^\s*'([^']+)':", multiLine: true)
      .allMatches(body)
      .map((m) => m.group(1)!)
      .toSet();
}

bool _report(String what, List<String> entries) {
  if (entries.isEmpty) return false;
  stdout.writeln('$what (${entries.length}):');
  for (final entry in entries) {
    stdout.writeln('  $entry');
  }
  return true;
}
