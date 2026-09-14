// Generates the missing `assets/grocery/` icons from manifest.json, in the
// style of the ones already there.
//
//     export GEMINI_API_KEY=...        # or put it in .env at the repo root
//     dart run tool/icon_gen/generate.dart --limit 3      # try three first
//     dart run tool/icon_gen/generate.dart                # the whole manifest
//     dart run tool/icon_gen/generate.dart --only Dairy_  # one category
//
// Nothing here writes into `assets/grocery/`. Output lands in
// `tool/icon_gen/out/` (git-ignored) so the batch can be looked through and
// the bad ones deleted before anything reaches the app; `--install` is the
// separate, deliberate step that copies the survivors across.
//
// Why the reference images: the set is a consistent studio packshot — pure
// white ground, soft top-left key, faint contact shadow — and describing that
// in words gets close but not identical. Three existing files of the same
// *kind* as the subject (produce, packaged, bakery, meat, household) are sent
// with every request as style anchors, which is what `gemini-3.1-flash-image`
// keeps its three dedicated style-reference slots for.
//
// Why standard mode and not the Batch API: the batch tier is half price but
// asynchronous with up to 24h turnaround, and the whole saving over this
// manifest is about three dollars. Being able to look at five icons, fix the
// prompt and go again is worth more than that.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

const _model = 'gemini-3.1-flash-image';
const _endpoint = 'https://generativelanguage.googleapis.com/v1beta/interactions';

/// The half of the prompt that never varies. The set's look, plus the things
/// the model otherwise volunteers: props, surfaces, text and packaging brands.
const _stylePrompt = '''
Match the style of the reference images exactly: professional studio product
photograph on a background of PURE WHITE, hex #FFFFFF, blown out to paper
white in every corner. Not grey, not off-white, not cream, not a gradient, not
a seamless studio sweep, not a surface the subject rests on. The only thing
separating subject from background is a faint soft contact shadow directly
beneath it. Soft diffused key light from the upper left, sharp focus
throughout, natural realistic colour, subject centred and filling roughly 85%
of the square frame.

Absolutely no text, no lettering, no numerals, no logos, no brand names, no
invented brand names, no packaging design, no printed labels, no barcodes and
no seals of any kind. If the product would normally come in printed packaging,
show the CONTENTS instead, or plain unprinted packaging with a blank surface. No hands, no people, no props, no plates,
no cutlery, no table, no cloth, no background objects, no reflections other
than the contact shadow. Nothing but the subject on plain white.
''';

Future<void> main(List<String> args) async {
  final opts = _Options.parse(args);
  final repoRoot = _repoRoot();

  final apiKey = _apiKey(repoRoot);
  if (apiKey == null) {
    stderr.writeln('''
No API key found.

Set it either way:
  export GEMINI_API_KEY=...                    (shell, not committed)
  echo 'GEMINI_API_KEY=...' >> ${repoRoot.path}/.env   (.env is git-ignored)

Get one at https://aistudio.google.com/apikey — image generation needs
billing enabled on the project, it is not on the free tier.''');
    exit(64);
  }

  final manifest = jsonDecode(
    File('${repoRoot.path}/tool/icon_gen/manifest.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  final refs = (manifest['refs'] as Map<String, dynamic>)
      .map((k, v) => MapEntry(k, (v as List).cast<String>()));

  var items = (manifest['items'] as List).cast<Map<String, dynamic>>();
  if (opts.only != null) {
    // Comma-separated, so one run can span several categories — which is how
    // a first batch gets one of each *kind* rather than fourteen fruits.
    final wanted = opts.only!.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
    items = items
        .where((i) => wanted.any((w) => (i['file'] as String).contains(w)))
        .toList();
  }

  final outDir = Directory('${repoRoot.path}/tool/icon_gen/out')..createSync(recursive: true);
  final assetDir = Directory('${repoRoot.path}/assets/grocery');

  // Already generated, or already shipped: skip both unless --force.
  if (!opts.force) {
    items = items.where((i) {
      final name = i['file'] as String;
      return !File('${outDir.path}/$name').existsSync() &&
          !File('${assetDir.path}/$name').existsSync();
    }).toList();
  }

  if (opts.limit != null && items.length > opts.limit!) {
    items = items.sublist(0, opts.limit!);
  }

  if (items.isEmpty) {
    stdout.writeln('Nothing to do — everything in scope already exists in out/ or assets/.');
    return;
  }

  final unitCost = opts.size == '2K' ? 0.101 : (opts.size == '0.5K' ? 0.045 : 0.067);
  stdout.writeln('${items.length} icon(s) at $_model / ${opts.size}'
      ' — about \$${(items.length * unitCost).toStringAsFixed(2)}');
  if (opts.dryRun) {
    for (final i in items) {
      stdout.writeln('  ${i['file']}  <- ${refs[i['ref']]!.join(', ')}');
    }
    stdout.writeln('\n--dry-run: nothing sent, nothing spent.');
    return;
  }

  final client = http.Client();
  final failures = <String, String>{};
  var done = 0;

  try {
    for (final item in items) {
      final name = item['file'] as String;
      final refFiles = refs[item['ref'] as String]!;
      stdout.write('[${++done}/${items.length}] $name ... ');

      try {
        final bytes = await _generate(
          client: client,
          apiKey: apiKey,
          subject: item['subject'] as String,
          refPaths: refFiles.map((f) => '${assetDir.path}/$f').toList(),
          size: opts.size,
        );
        File('${outDir.path}/$name').writeAsBytesSync(bytes);
        stdout.writeln('${(bytes.length / 1024).round()} KB');
      } catch (e) {
        stdout.writeln('FAILED');
        failures[name] = '$e';
      }
    }
  } finally {
    client.close();
  }

  stdout.writeln('\nWrote ${done - failures.length} file(s) to tool/icon_gen/out/');
  if (failures.isNotEmpty) {
    stdout.writeln('\n${failures.length} failed:');
    failures.forEach((k, v) => stdout.writeln('  $k: ${v.split('\n').first}'));
    stdout.writeln('\nRe-run the same command to retry only the ones that are missing.');
  }
  stdout.writeln('''

Next:
  open tool/icon_gen/out            # delete anything that missed
  dart run tool/icon_gen/generate.dart        # regenerates whatever you deleted
  dart run tool/icon_gen/install.dart         # resize to 512 and copy into assets/''');
}

/// One image. Returns the decoded PNG bytes.
Future<Uint8List> _generate({
  required http.Client client,
  required String apiKey,
  required String subject,
  required List<String> refPaths,
  required String size,
}) async {
  final input = <Map<String, dynamic>>[
    {
      'type': 'text',
      'text': 'Generate a product photograph of $subject.\n$_stylePrompt',
    },
    for (final path in refPaths)
      {
        'type': 'image',
        'mime_type': 'image/png',
        'data': base64Encode(File(path).readAsBytesSync()),
      },
  ];

  final response = await client.post(
    Uri.parse(_endpoint),
    headers: {
      'x-goog-api-key': apiKey,
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'model': _model,
      'input': input,
      'response_format': {
        'type': 'image',
        'aspect_ratio': '1:1',
        'image_size': size,
      },
    }),
  );

  if (response.statusCode != 200) {
    // Deliberately prints the body but never the key or the headers.
    throw Exception('HTTP ${response.statusCode}: ${_trim(response.body)}');
  }

  final data = _findImage(jsonDecode(response.body));
  if (data == null) throw Exception('no image in response: ${_trim(response.body)}');
  return base64Decode(data);
}

/// Walks the response for the first base64 image payload, rather than hard-coding
/// one path through it — the shape differs between a plain image reply and an
/// interleaved text-and-image one.
String? _findImage(Object? node) {
  if (node is Map) {
    for (final key in const ['data', 'image_bytes', 'b64_json']) {
      final v = node[key];
      if (v is String && v.length > 256) return v;
    }
    for (final v in node.values) {
      final found = _findImage(v);
      if (found != null) return found;
    }
  } else if (node is List) {
    for (final v in node) {
      final found = _findImage(v);
      if (found != null) return found;
    }
  }
  return null;
}

String _trim(String s) => s.length > 400 ? '${s.substring(0, 400)}…' : s;

/// `GEMINI_API_KEY` from the environment, else the same key out of a `.env` at
/// the repo root. Never printed, never logged, never written anywhere.
String? _apiKey(Directory repoRoot) {
  final fromEnv = Platform.environment['GEMINI_API_KEY'];
  if (fromEnv != null && fromEnv.trim().isNotEmpty) return fromEnv.trim();

  final dotEnv = File('${repoRoot.path}/.env');
  if (!dotEnv.existsSync()) return null;
  for (final raw in dotEnv.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    if (eq < 0) continue;
    if (line.substring(0, eq).trim() != 'GEMINI_API_KEY') continue;
    var value = line.substring(eq + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    if (value.isNotEmpty) return value;
  }
  return null;
}

Directory _repoRoot() {
  var dir = Directory(Platform.script.toFilePath()).parent;
  while (!File('${dir.path}/pubspec.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      stderr.writeln('Could not find the repo root (no pubspec.yaml above this script).');
      exit(70);
    }
    dir = parent;
  }
  return dir;
}

class _Options {
  _Options({this.limit, this.only, this.size = '1K', this.dryRun = false, this.force = false});

  final int? limit;
  final String? only;
  final String size;
  final bool dryRun;
  final bool force;

  static _Options parse(List<String> args) {
    int? limit;
    String? only;
    var size = '1K';
    var dryRun = false;
    var force = false;

    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      String next() {
        if (i + 1 >= args.length) {
          stderr.writeln('$a needs a value');
          exit(64);
        }
        return args[++i];
      }

      switch (a) {
        case '--limit':
          limit = int.tryParse(next());
        case '--only':
          only = next();
        case '--size':
          size = next();
        case '--dry-run':
          dryRun = true;
        case '--force':
          force = true;
        case '-h':
        case '--help':
          stdout.writeln('''
dart run tool/icon_gen/generate.dart [options]

  --limit N     stop after N icons (try --limit 3 first)
  --only TEXT   files whose name contains TEXT; comma-separated for several,
                e.g. --only Dairy_  or  --only Fruits_Pear,Snacks_Crisps
  --size SIZE   0.5K | 1K | 2K   (default 1K, downsized to 512 on install)
  --dry-run     list what would be generated and the cost, send nothing
  --force       regenerate even if the file already exists
''');
          exit(0);
        default:
          stderr.writeln('unknown option: $a');
          exit(64);
      }
    }
    return _Options(limit: limit, only: only, size: size, dryRun: dryRun, force: force);
  }
}
