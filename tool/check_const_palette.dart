// Fails on `const` expressions that (transitively) construct a widget reading
// a design token, because those would freeze in whichever palette was
// installed when they were first built.
//
// The global-palette design in lib/theme/tokens.dart has exactly one failure
// mode, and the compiler can't see it: a `const` widget is canonicalised, so
// its element is skipped when an ancestor rebuilds, and it keeps painting the
// old colours after a dark-mode flip. Passing a token as an *argument* is
// already self-enforcing (the getter isn't a constant, so it won't compile) —
// this covers the other case, tokens read inside `build`.
//
//     dart tool/check_const_palette.dart
//
// Note what "const expression" means here: `const` is inherited by everything
// nested inside it, so
//
//     const Positioned.fill(child: FrostedHeaderBackground())
//
// const-constructs the *header background* too, even though the keyword sits
// on a framework widget. That one shipped a frozen light frost wash over the
// dark app, so the whole balanced expression after each `const` is checked,
// not just the constructor it's written in front of.
//
// Deliberately a lint-style script rather than a test: `flutter test` is
// opt-in in this project (see CLAUDE.md).

import 'dart:io';

final _tokenUse = RegExp(
  r'\b(AppColors|AppText|AppTones|AppShadows)\b|\btint\(|\bwhoMeta\(|\.toneColors\b|\.srcColor\b',
);
final _classDecl = RegExp(r'^class\s+(\w+)\s+extends\s+([\w<>, ]+?)\s*\{', multiLine: true);
final _classHead = RegExp(r'^class\s+(\w+)', multiLine: true);
final _identifier = RegExp(r'\b([A-Z_]\w+)\b');

/// A capitalised name that is *invoked* — `Foo(`, `Foo.named(`. Anything else
/// is a static read like `CollapsingHeaderScreen.collapsedGap`, which is a
/// plain compile-time constant and perfectly fine inside a `const`.
final _construction = RegExp(r'\b([A-Z]\w*)\s*(?:\.\s*\w+\s*)?\(');

const _open = '([{';
const _close = ')]}';

/// Overwrites comments and string literals with spaces, so the scanners below
/// can't trip over a `const` in prose or `'AppColors'` in a message. Length is
/// preserved so byte offsets still map back to line numbers.
String _blankNonCode(String src) {
  final out = src.split('');
  var i = 0;
  while (i < src.length) {
    final c = src[i];
    if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        out[i++] = ' ';
      }
    } else if (c == '/' && i + 1 < src.length && src[i + 1] == '*') {
      while (i < src.length && !(src[i] == '*' && i + 1 < src.length && src[i + 1] == '/')) {
        if (src[i] != '\n') out[i] = ' ';
        i++;
      }
      for (var k = 0; k < 2 && i < src.length; k++) {
        out[i++] = ' ';
      }
    } else if (c == "'" || c == '"') {
      out[i++] = ' ';
      while (i < src.length && src[i] != c) {
        if (src[i] == r'\') out[i++] = ' ';
        if (i < src.length && src[i] != '\n') out[i] = ' ';
        i++;
      }
      if (i < src.length) out[i++] = ' ';
    } else {
      i++;
    }
  }
  return out.join();
}

/// The source of the whole expression a `const` at [start] applies to: the
/// balanced `(...)`/`[...]`/`{...}` after the constructor name, or — for a
/// `const` *declaration* like `const _bands = [...]` — everything up to the
/// terminating `;`.
String _constExpression(String src, int start) {
  var i = start;
  while (i < src.length && src[i].trim().isEmpty) {
    i++;
  }
  while (i < src.length && (RegExp(r'[\w.]').hasMatch(src[i]))) {
    i++;
  }
  while (i < src.length && src[i].trim().isEmpty) {
    i++;
  }
  if (i < src.length && _open.contains(src[i])) {
    var depth = 0;
    for (var j = i; j < src.length; j++) {
      if (_open.contains(src[j])) depth++;
      if (_close.contains(src[j])) {
        depth--;
        if (depth == 0) return src.substring(start, j + 1);
      }
    }
    return src.substring(start);
  }
  final semi = src.indexOf(';', i);
  return src.substring(start, semi < 0 ? src.length : semi + 1);
}

void main() {
  final lib = Directory('lib');
  if (!lib.existsSync()) {
    stderr.writeln('run me from the project root');
    exit(2);
  }

  final files = lib
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  final bases = <String, String>{};
  final mentions = <String, Set<String>>{};
  final readsToken = <String>{};

  for (final f in files) {
    final src = f.readAsStringSync();
    final decls = _classDecl.allMatches(src).toList();
    for (var i = 0; i < decls.length; i++) {
      final name = decls[i].group(1)!;
      final end = i + 1 < decls.length ? decls[i + 1].start : src.length;
      final body = src.substring(decls[i].start, end);
      bases[name] = decls[i].group(2)!;
      mentions[name] = _identifier.allMatches(body).map((m) => m.group(1)!).toSet();
      if (_tokenUse.hasMatch(body)) readsToken.add(name);
    }
  }

  // A `State<Foo>` reading tokens makes Foo palette-dependent too.
  for (final entry in bases.entries) {
    final m = RegExp(r'State<(\w+)>').firstMatch(entry.value);
    if (m != null && readsToken.contains(entry.key)) readsToken.add(m.group(1)!);
  }

  // Transitive closure: a widget that builds a palette-dependent widget must
  // itself rebuild, so it must not be const either.
  for (var changed = true; changed;) {
    changed = false;
    for (final name in bases.keys) {
      if (readsToken.contains(name)) continue;
      if (mentions[name]!.any(readsToken.contains)) {
        readsToken.add(name);
        changed = true;
      }
    }
  }

  final offenders = <String>[];
  for (final f in files) {
    final raw = f.readAsStringSync();
    final src = _blankNonCode(raw);
    final classAt = _classHead.allMatches(src).map((m) => (m.start, m.group(1)!)).toList();

    for (final m in RegExp(r'\bconst\b').allMatches(src)) {
      final span = _constExpression(src, m.end);

      // `const Foo(...)` inside class Foo is the constructor declaration,
      // which must stay const (prefer_const_constructors_in_immutables).
      String? enclosing;
      for (final c in classAt) {
        if (c.$1 < m.start) enclosing = c.$2;
      }

      final hits = _construction
          .allMatches(span)
          .map((c) => c.group(1)!)
          .where(readsToken.contains)
          .where((name) => name != enclosing)
          .toSet();
      if (hits.isEmpty) continue;

      final line = '\n'.allMatches(raw.substring(0, m.start)).length + 1;
      final snippet = span.replaceAll(RegExp(r'\s+'), ' ').trim();
      offenders.add(
        '${f.path}:$line  ${hits.join(', ')}  --  '
        '${snippet.length > 90 ? '${snippet.substring(0, 90)}…' : snippet}',
      );
    }
  }

  if (offenders.isEmpty) {
    stdout.writeln('OK: no const expression constructs a palette-dependent widget '
        '(${readsToken.length}/${bases.length} classes are palette-dependent).');
    return;
  }

  stderr.writeln('${offenders.length} const expression(s) would freeze in the old palette:\n');
  for (final o in offenders) {
    stderr.writeln('  $o');
  }
  stderr.writeln('\nDrop the `const` (keep it on the constructors themselves). Remember it is\n'
      'inherited: the offender may be nested inside a const framework widget.');
  exit(1);
}
