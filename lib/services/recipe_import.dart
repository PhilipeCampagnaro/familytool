/// A recipe page the household was already reading, turned into a [ListPlan].
///
/// The Vorhaben card ([lib/screens/list/planner_card.dart]) can already take a
/// plan, let the reader tick off what they have, and stamp out a Liste with
/// icons and quantities on it. This file fills the same object from a page
/// instead of from a language model — **no request, no key, no cost, no limit**,
/// because the page already carries the answer in a machine-readable form that
/// Google's recipe rich card obliges it to publish.
///
/// ## The one decision everything follows from
///
/// **The ingredients come over; the method does not.**
///
/// [docs/list-planner.md](../../docs/list-planner.md) records that recipes were
/// once cut for licensing, and that generated text was acceptable precisely
/// because it is not somebody else's work. A *Zubereitungstext* is a Sprachwerk
/// and copying one into our database — where it is then replicated to the
/// household's other phones and to anyone the list is shared with — is
/// reproduction, not citation. A list of ingredients is a list of facts.
///
/// So [ListPlan.steps] and [ListPlan.recipe] are left empty here, and they are
/// left empty deliberately rather than because the pages lack the text: almost
/// every page tested carried `recipeInstructions` and this file reads straight
/// past it. Don't "improve" this by filling them in.
///
/// ## Where the work is split
///
/// The page is harvested by whatever can see it — on iOS the Share Extension's
/// JavaScript, which reads the DOM Safari has already rendered — and that side
/// is deliberately stupid: it hands over the HTML and the final URL and makes
/// no decisions. Everything that needs judgement (which block is the recipe,
/// what a quantity is, what to call the article) is here, in Dart, where it can
/// be tested against saved pages without a browser and where the Android path
/// will reuse it unchanged.
library;

import 'dart:convert';

import '../models/grocery_unit.dart';
import '../models/list_plan.dart';
import '../models/shopping_list.dart';

/// What a harvested page turned into, plus where it came from.
class RecipeImport {
  final ListPlan plan;

  /// The page the household was on, after redirects. Not stored anywhere yet —
  /// see the note in [parseRecipePage].
  final String sourceUrl;

  /// Which shape of markup answered. Only for diagnostics and the import
  /// harness; nothing user-facing branches on it.
  final RecipeSource source;

  const RecipeImport({required this.plan, required this.sourceUrl, required this.source});
}

enum RecipeSource { jsonLd, microdata, headingList, videoDescription }

/// Reads a rendered recipe page.
///
/// Returns null when the page carried nothing usable — which the caller shows
/// as "we could not read that page" rather than as an empty list, because an
/// empty Liste named after a URL is worse than no Liste.
RecipeImport? parseRecipePage({required String html, required String pageUrl}) {
  for (final attempt in [_fromJsonLd, _fromMicrodata, _fromHeadingList]) {
    final found = attempt(html);
    if (found == null || found.ingredients.isEmpty) continue;
    final import = _importFrom(found, pageUrl, () => _titleFromHtml(html));
    if (import != null) return import;
  }
  return null;
}

/// Lines of a recipe, in a language rather than in markup — a video's
/// description, and anything else that arrives as prose with a list in it.
///
/// Split out from [parseRecipePage] because everything after "here are the
/// ingredient lines" is identical: the same quantity parsing, the same
/// de-duplication, the same deliberate absence of a method. Only the job of
/// *finding* the lines differs, and for text that is [_ingredientBlock].
RecipeImport? parseRecipeText({
  required String text,
  required String title,
  required String pageUrl,
}) {
  final lines = _ingredientBlock(text);
  if (lines == null) return null;
  return _importFrom(
    _Found(title, lines, RecipeSource.videoDescription),
    pageUrl,
    () => title,
  );
}

/// The half that is the same whatever found the lines.
///
/// [fallbackTitle] is a callback rather than a string because the HTML paths
/// pay for it by scanning the document, and they should only pay when the
/// markup carried no name of its own.
RecipeImport? _importFrom(_Found found, String pageUrl, String Function() fallbackTitle) {
  final items = <ListPlanItem>[];
  final seen = <String>{};
  for (final line in found.ingredients) {
    if (_isGroupHeading(line)) continue;
    final item = _itemFromLine(line);
    if (item == null) continue;
    // The same article twice is legitimate in a recipe ("Zwiebeln" for the
    // sauce and for the topping) but not on a shopping list, where it is two
    // rows to tick for one thing to buy. Keyed on the name alone, so the
    // first quantity wins rather than the two being added up — adding them
    // would be arithmetic across units we did not parse.
    final key = item.name.toLowerCase();
    if (!seen.add(key)) continue;
    items.add(item);
  }
  if (items.isEmpty) return null;
  return RecipeImport(
    plan: ListPlan(
      title: found.title.isEmpty ? fallbackTitle() : found.title,
      kind: ListKind.grocery,
      // Empty on purpose — see the licensing note in this file's header.
      // The page is referenced instead, which is what `sourceUrl` is for.
      steps: const [],
      recipe: null,
      sourceUrl: pageUrl,
      items: items,
    ),
    sourceUrl: pageUrl,
    source: found.source,
  );
}


/// "Für den Teig:", "Para la salsa de tomate:", "For the filling:".
///
/// A recipe groups its ingredients under sub-headings, and **schema.org has no
/// field for a group** — `recipeIngredient` is a flat list of strings — so a
/// page that keeps its headings puts them in the list beside the ingredients.
/// Read literally they become articles, and the household goes shopping for a
/// thing called "Para las albóndigas".
///
/// Two tests, because either alone is wrong: a trailing colon is the reliable
/// mark but not every page writes one, and the opening words are recognisable
/// in all four languages but "Für" also begins a real line ("Fett und Mehl für
/// das Blech"). A heading carries **no digit**, which is what separates the two.
final _groupOpener = RegExp(
  r'^(?:für|fuer|zum|zur|for the|para (?:el|la|los|las)|pour (?:le|la|les)|per (?:il|la))\b',
  caseSensitive: false,
);

bool _isGroupHeading(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return true;
  if (trimmed.endsWith(':')) return true;
  return _groupOpener.hasMatch(trimmed) && !trimmed.contains(RegExp(r'\d'));
}

class _Found {
  final String title;
  final List<String> ingredients;
  final RecipeSource source;
  const _Found(this.title, this.ingredients, this.source);
}

// ---------------------------------------------------------------------------
// The three shapes a page can carry, in the order they are trusted.
// ---------------------------------------------------------------------------

final _jsonLdBlock = RegExp(
  r'''<script[^>]*type\s*=\s*['"]application/ld\+json['"][^>]*>(.*?)</script>''',
  caseSensitive: false,
  dotAll: true,
);

/// schema.org in a `<script>` tag — what Google's recipe rich card asks for,
/// and therefore what most of the web publishes.
///
/// **The Recipe object is rarely at the top level.** It is routinely wrapped in
/// an `@graph`, an array, or hung off a WebPage's `mainEntity`, and a reader
/// that only looks at the root finds nothing on perfectly good pages — so this
/// walks the whole tree. `@type` may itself be a list (`["Recipe","NewsArticle"]`).
_Found? _fromJsonLd(String html) {
  for (final match in _jsonLdBlock.allMatches(html)) {
    final raw = match.group(1);
    if (raw == null) continue;
    Object? decoded;
    for (final candidate in [raw.trim(), _unescapeEntities(raw.trim())]) {
      try {
        decoded = jsonDecode(candidate);
        break;
      } catch (_) {
        // A block that is not valid JSON is not a reason to stop: pages carry
        // several, and a broken analytics one must not hide the recipe.
        continue;
      }
    }
    if (decoded == null) continue;
    for (final node in _walk(decoded)) {
      if (!_isType(node, 'Recipe')) continue;
      final ingredients = _stringList(node['recipeIngredient'] ?? node['ingredients']);
      if (ingredients.isEmpty) continue;
      return _Found(_plainText(node['name']?.toString() ?? ''), ingredients, RecipeSource.jsonLd);
    }
  }
  return null;
}

/// schema.org spelled into the markup itself. Older, still current on a good
/// deal of the German web — rezeptwelt.de publishes this and no JSON-LD at all,
/// which is why this branch is not optional.
///
/// **Two shapes, and the second one is easy to miss.** Most sites put the text
/// inside the element, where the whole subtree matters: Thermomix's rezeptwelt
/// writes `<li itemprop=…><span>125</span><span> g</span><span> Zucker</span></li>`,
/// so a reader that stops at the first closing tag gets "125". The non-greedy
/// body up to the *matching* tag name plus [_plainText] flattening the spans is
/// what makes that come out as "125 g Zucker".
///
/// **The quotes are optional on purpose.** An abandoned WordPress plugin still
/// in the wild writes `<li\nclass=ingredient itemprop=recipeIngredient>` —
/// unquoted attribute values, with a newline between the tag name and the first
/// attribute. It is valid HTML5 and a pattern that insists on `itemprop="…"`
/// reads the page as having no ingredients at all.
///
/// The other shape is a **void element carrying the value in an attribute** —
/// `<meta itemprop="recipeIngredient" content="400 g Hühnerbrustfilet">`, which
/// ichkoche.at uses. It has no closing tag at all, so the first pattern cannot
/// see it and a page full of ingredients reads as empty.
final _microdataItem = RegExp(
  r'''<([a-zA-Z][\w-]*)\b[^>]*itemprop\s*=\s*['"]?(?:recipeIngredient|ingredients)\b['"]?[^>]*>(.*?)</\1\s*>''',
  caseSensitive: false,
  dotAll: true,
);
final _microdataMeta = RegExp(
  r'''<(?:meta|link)\b[^>]*itemprop\s*=\s*['"]?(?:recipeIngredient|ingredients)\b['"]?[^>]*?content\s*=\s*"([^"]*)"''',
  caseSensitive: false,
);
/// The same tag with the attributes the other way round. Cheaper than a real
/// attribute parser and covers what is actually published.
final _microdataMetaReversed = RegExp(
  r'''<(?:meta|link)\b[^>]*content\s*=\s*"([^"]*)"[^>]*itemprop\s*=\s*['"]?(?:recipeIngredient|ingredients)\b['"]?''',
  caseSensitive: false,
);

_Found? _fromMicrodata(String html) {
  final out = <String>[];
  for (final match in _microdataItem.allMatches(html)) {
    final text = _plainText(match.group(2) ?? '');
    if (text.isNotEmpty) out.add(text);
  }
  if (out.isEmpty) {
    for (final pattern in [_microdataMeta, _microdataMetaReversed]) {
      for (final match in pattern.allMatches(html)) {
        final text = _plainText(match.group(1) ?? '');
        if (text.isNotEmpty) out.add(text);
      }
      if (out.isNotEmpty) break;
    }
  }
  if (out.isEmpty) return null;
  return _Found(_titleFromHtml(html), out, RecipeSource.microdata);
}

/// Nothing structured at all: find a heading that says "ingredients" in one of
/// the four languages and read the list under it.
///
/// **The weakest branch by far**, and it is last for that reason. It exists
/// because the alternative on an unmarked page is nothing, and a list the
/// reader prunes beats retyping twelve lines.
final _ingredientHeading = RegExp(
  r'<h[1-6][^>]*>\s*((?:zutaten|ingredient|ingredients|ingredientes|ingredienti)[^<]{0,40})</h[1-6]\s*>',
  caseSensitive: false,
);
final _listItem = RegExp(r'<li\b[^>]*>(.*?)</li\s*>', caseSensitive: false, dotAll: true);

_Found? _fromHeadingList(String html) {
  final heading = _ingredientHeading.firstMatch(html);
  if (heading == null) return null;
  // Only the markup that follows the heading, and only a window of it: a whole
  // page's worth of <li> is a navigation menu with a recipe somewhere in it.
  final after = html.substring(heading.end, (heading.end + 8000).clamp(0, html.length));
  final out = <String>[];
  for (final match in _listItem.allMatches(after)) {
    final text = _plainText(match.group(1) ?? '');
    // A nav entry is one or two words and carries no digit; an ingredient line
    // nearly always has a quantity. Not a rule that can be right every time,
    // which is the whole reason this branch is the last one tried.
    if (text.isEmpty || text.length > 90) continue;
    out.add(text);
    if (out.length >= 40) break;
  }
  if (out.length < 2) return null;
  return _Found(_titleFromHtml(html), out, RecipeSource.headingList);
}

// ---------------------------------------------------------------------------
// Finding a list inside freeform text.
// ---------------------------------------------------------------------------

/// A video description is not markup, and nothing in it is labelled. It is a
/// paragraph about the dish, then a shopping list, then the channel's links —
/// with no tag saying which is which. So the list is found by **shape**: a run
/// of short lines, most of which open with a number.
///
/// ## What the shapes actually are
///
/// Measured against 24 recipe videos off four German channels. The ones that
/// carry a list write it one of three ways, and all three had to be handled:
///
/// * plain, under a "Zutaten"/"Ingredients" heading;
/// * bulleted, or led by an emoji;
/// * **prefixed with a chapter timestamp** — `00:21 Salt.` — which is a list
///   and a set of video chapters at once, and which no amount of reading the
///   words would recognise.
///
/// ## Why it refuses more than it accepts
///
/// One channel in the sample writes its narration into the description, so
/// ingredients sit interleaved with "Mix it well" and "Subscribe to my
/// channel!". There is no reading of that text that yields a clean list, and a
/// list with *Subscribe to my channel* on it is worse than no list at all —
/// the reader has to notice the junk before they can delete it.
///
/// So a block is taken only when it is **introduced by an ingredient heading**
/// and at least three of its lines carry a quantity, or — with no heading at
/// all — when quantities are the clear majority ([_denseEnough]). Both
/// thresholds are measured rather than chosen: they are the loosest pair that
/// still rejects every narration description in the sample. 15 of the 24 came
/// through, which is the honest ceiling for this and well short of what a
/// marked-up page gives.
///
/// Returns null when nothing in the text qualifies, which the caller reports
/// as "no ingredients in that description".
List<String>? _ingredientBlock(String text) {
  List<String>? best;
  var bestQuantities = 0;

  // A block is kept as the groups it was written in — one blank line apart —
  // because where the blanks fell is the only evidence of where the list ends.
  var block = <List<String>>[];
  var headed = false;
  // Two blanks in a row end a block; one does not, because a list with groups
  // in it puts a blank line between them.
  var blanks = 0;

  void add(String line) {
    if (block.isEmpty || blanks > 0) block.add(<String>[]);
    block.last.add(line);
  }

  void close() {
    // **A trailing group with no quantity anywhere in it is a sign-off, not
    // ingredients.** "Bon appetit!", "Guten Appetit", an equipment note — they
    // are short, they look exactly like list entries, and they are separated
    // from the list by the single blank line that a group is also separated
    // by, so nothing but their content tells them apart. A real group has a
    // number in it somewhere.
    while (block.length > 1 && !block.last.any(_opensWithQuantity)) {
      block.removeLast();
    }
    final lines = [for (final group in block) ...group];
    if (lines.isNotEmpty) {
      final quantities = lines.where(_opensWithQuantity).length;
      final enough = headed ? quantities >= 3 : _denseEnough(quantities, lines.length);
      if (enough && quantities > bestQuantities) {
        best = lines;
        bestQuantities = quantities;
      }
    }
    block = [];
    headed = false;
  }

  for (final raw in const LineSplitter().convert(text)) {
    final line = _tidyTextLine(raw);

    if (_textIngredientHeading.hasMatch(line)) {
      // A second heading inside a block that already has one is a *group*
      // ("Zutaten Teig", "Zutaten Füllung"), not the start of a rival list —
      // closing there would throw away the half already collected.
      if (!(headed && block.isNotEmpty)) close();
      // A group heading inside a list starts a group, so the lines under it
      // are weighed on their own by the sign-off rule above.
      blanks = 1;
      headed = true;
      continue;
    }

    final listy = line.isNotEmpty &&
        line.length <= _maxTextLine &&
        !_looksLikeLink.hasMatch(line) &&
        !_textStopHeading.hasMatch(line);
    if (listy) {
      add(line);
      blanks = 0;
    } else {
      blanks = line.isEmpty ? blanks + 1 : 2;
      if (blanks >= 2) close();
    }
  }
  close();
  return best;
}

/// Three in five, with no floating point. Reached only where there is no
/// heading to go on, where the evidence has to come from the lines themselves.
bool _denseEnough(int quantities, int lines) => quantities >= 4 && quantities * 5 >= lines * 3;

/// A quantity **and something for it to be a quantity of**, so a bare year or
/// a stray "2024" in a sign-off does not read as an ingredient.
bool _opensWithQuantity(String line) {
  final match = _leadingQuantity.matchAsPrefix(line);
  return match != null && match.end < line.length;
}

/// Longest a line can be and still be a list entry rather than a sentence.
/// The longest real ingredient line in the sample was 44 characters.
const _maxTextLine = 60;

/// A chapter marker, which is a timestamp and nothing else.
final _chapterMark = RegExp(r'^\d{1,2}:\d{2}(?::\d{2})?\s+');

/// Whatever a channel decorates its lines with — hyphens, bullets, arrows,
/// emoji, stars. Anything before the first letter or digit is ornament.
/// Matched on unicode categories rather than a list of characters, because the
/// list would be a losing race against people's taste in emoji.
final _leadingOrnament = RegExp(r'^[^\p{L}\p{N}]+', unicode: true);

/// `6 potatoes.` is written with a full stop by channels that write every line
/// as a sentence, and `potatoes.` matches nothing in the grocery catalog.
final _trailingPunctuation = RegExp(r'[.,;:]+$');

final _looksLikeLink = RegExp(r'https?://|www\.', caseSensitive: false);

/// Kept deliberately shorter than the page-markup heading list: this one is
/// matched against every line of freeform prose, so a loose word here costs a
/// false heading in the middle of a paragraph.
final _textIngredientHeading = RegExp(
  r'^(zutaten|ingredient|ingrediente|ingr[ée]dient|du brauchst|you will need'
  r'|rezept und zutaten|recipe and ingredients)',
  caseSensitive: false,
);

/// Where the list stops: the method, or the channel's own business.
final _textStopHeading = RegExp(
  r'^(zubereitung|anleitung|instruction|method|pr[ée]paration|preparation'
  r'|preparaci|modo de|abonn|subscribe|folge |follow |musik|music|equipment|zubeh)',
  caseSensitive: false,
);

String _tidyTextLine(String raw) {
  var line = raw.trim();
  line = line.replaceFirst(_leadingOrnament, '');
  line = line.replaceFirst(_chapterMark, '');
  line = line.replaceFirst(_leadingOrnament, '').trim();
  // A heading keeps its colon: it is how "Zutaten:" is told from an article
  // called Zutaten, and the line is discarded rather than shown anyway.
  if (_textIngredientHeading.hasMatch(line)) return line;
  return line.replaceFirst(_trailingPunctuation, '').trim();
}

// ---------------------------------------------------------------------------
// One ingredient line → one article to buy.
// ---------------------------------------------------------------------------

/// The quantity at the front of a line: `500`, `1,5`, `0.5`, `1/2`, `½`, `2-3`.
final _leadingQuantity = RegExp(r'^\s*(\d+[.,]?\d*(?:\s*[-–/]\s*\d+[.,]?\d*)?|[½¼¾⅓⅔⅛])\s*');

/// The words that are *units of shopping* and nothing else.
///
/// [GroceryUnit] has ten values and deliberately no Esslöffel — "you buy a pack
/// of butter; the 2 EL belongs in the step that uses it" ([ListPlanItem]). So a
/// recipe unit with no shopping meaning (EL, TL, Prise, Becher, cup, tbsp) is
/// **not** dropped and **not** forced into the column: it stays in the free-text
/// [ListPlanItem.quantity] beside the number, exactly as the model's answers do.
const _shoppingUnits = <String, GroceryUnit>{
  'g': GroceryUnit.gram, 'gr': GroceryUnit.gram, 'gramm': GroceryUnit.gram, 'gram': GroceryUnit.gram,
  'grams': GroceryUnit.gram, 'gramos': GroceryUnit.gram, 'gramas': GroceryUnit.gram,
  'kg': GroceryUnit.kilogram, 'kilo': GroceryUnit.kilogram, 'kilogramm': GroceryUnit.kilogram,
  'ml': GroceryUnit.milliliter, 'milliliter': GroceryUnit.milliliter,
  'l': GroceryUnit.liter, 'liter': GroceryUnit.liter, 'litre': GroceryUnit.liter,
  'litro': GroceryUnit.liter, 'litros': GroceryUnit.liter,
  'pack': GroceryUnit.pack, 'packung': GroceryUnit.pack, 'packungen': GroceryUnit.pack,
  'pck': GroceryUnit.pack, 'pck.': GroceryUnit.pack, 'pkt': GroceryUnit.pack,
  'päckchen': GroceryUnit.pack, 'paeckchen': GroceryUnit.pack, 'pk': GroceryUnit.pack,
  'paquete': GroceryUnit.pack, 'pacote': GroceryUnit.pack,
  'dose': GroceryUnit.can, 'dosen': GroceryUnit.can, 'can': GroceryUnit.can,
  'cans': GroceryUnit.can, 'lata': GroceryUnit.can, 'latas': GroceryUnit.can,
  'flasche': GroceryUnit.bottle, 'flaschen': GroceryUnit.bottle, 'bottle': GroceryUnit.bottle,
  'botella': GroceryUnit.bottle, 'garrafa': GroceryUnit.bottle,
  'bund': GroceryUnit.bunch, 'bunch': GroceryUnit.bunch, 'manojo': GroceryUnit.bunch,
  'maço': GroceryUnit.bunch,
  'glas': GroceryUnit.glass, 'glass': GroceryUnit.glass, 'jar': GroceryUnit.glass,
  'tarro': GroceryUnit.glass,
  // 'piece' is the default and is stored as null — [ListPlanItem.fromJson] does
  // the same. Listed so the word is eaten off the name rather than left on it.
  'stück': GroceryUnit.piece, 'stueck': GroceryUnit.piece, 'stk': GroceryUnit.piece,
  'stk.': GroceryUnit.piece, 'st': GroceryUnit.piece, 'piece': GroceryUnit.piece,
  'pieces': GroceryUnit.piece, 'pcs': GroceryUnit.piece, 'unidade': GroceryUnit.piece,
  'unidades': GroceryUnit.piece, 'unidad': GroceryUnit.piece,
};

/// Words that are units in a cookbook but mean nothing at a supermarket shelf.
///
/// These are **listed rather than inferred**, and that is the whole of the
/// lesson here: the first version treated any short word after a number as a
/// unit, which is right for *1 Prise Salz* and catastrophic for *1 onion,
/// finely chopped* — the article was eaten as a unit and the row came out named
/// "finely chopped". German hides the problem because it compounds; English,
/// Portuguese and Spanish put the bare article there constantly.
///
/// So an unknown word after a number stays in the name. The failure mode of
/// this list being short is a quantity that reads "1" instead of "1 Prise",
/// which is a cosmetic loss on a row the reader can see. The failure mode of
/// guessing is a row called "finely chopped".
const _recipeUnits = <String>{
  // German
  'el', 'esslöffel', 'esslöffeln', 'tl', 'teelöffel', 'teelöffeln', 'prise', 'prisen',
  'becher', 'stange', 'stangen', 'zehe', 'zehen', 'scheibe', 'scheiben', 'blatt',
  'blätter', 'kopf', 'köpfe', 'handvoll', 'msp', 'messerspitze', 'tasse', 'tassen',
  'tropfen', 'würfel', 'kugel', 'kugeln', 'zweig', 'zweige', 'portion', 'portionen',
  'streifen', 'spritzer', 'schuss', 'knolle', 'rispe', 'tel',
  // English
  'tbsp', 'tbsp.', 'tablespoon', 'tablespoons', 'tsp', 'tsp.', 'teaspoon', 'teaspoons',
  'cup', 'cups', 'clove', 'cloves', 'slice', 'slices', 'sprig', 'sprigs', 'pinch',
  'pinches', 'handful', 'rasher', 'rashers', 'stick', 'sticks', 'head', 'dash',
  'knob', 'sheet', 'sheets', 'punnet', 'bulb', 'fillet', 'fillets', 'strip', 'strips',
  'oz', 'lb', 'lbs', 'tin', 'tins',
  // Portuguese
  'colher', 'colheres', 'xícara', 'xicara', 'xícaras', 'xicaras', 'caixa', 'caixas',
  'pitada', 'pitadas', 'dente', 'dentes', 'fatia', 'fatias', 'copo', 'copos', 'ramo',
  'ramos', 'punhado', 'folha', 'folhas',
  // Spanish
  'cucharada', 'cucharadas', 'cucharadita', 'cucharaditas', 'taza', 'tazas', 'pizca',
  'pizcas', 'diente', 'dientes', 'rebanada', 'rebanadas', 'rama', 'ramas', 'puñado',
  'hoja', 'hojas', 'sobre', 'sobres',
  // French and Italian are not interface languages, and these are here for the
  // same reason `grocery_search.dart` indexes all four languages at once: what
  // can be *read* is not what is displayed. A German household cooking from
  // giallozafferano is an ordinary Tuesday.
  'gousse', 'gousses', 'cuillère', 'cuillères', 'cuilleres', 'pincée', 'pincee',
  'tranche', 'tranches', 'brin', 'brins', 'verre', 'verres', 'sachet', 'sachets',
  'cucchiaio', 'cucchiai', 'cucchiaino', 'cucchiaini', 'spicchio', 'spicchi',
  'pizzico', 'fetta', 'fette', 'mazzetto', 'bustina',
  // "2 x 400 g" — a multiplier, not a unit, but it belongs beside the number.
  'x',
};

/// The amount at the *end* of the line, with its unit — *Latte intero 500 g*.
/// The unit is required, not optional; see the note at its use.
final _trailingQuantity = RegExp(
  r'\s(\d+[.,]?\d*(?:\s*[-–/]\s*\d+[.,]?\d*)?)\s*([\p{L}]+\.?)\s*$',
  unicode: true,
);

/// A fraction written after the whole number: *1 ½ TL*.
final _trailingFraction = RegExp(r'^([½¼¾⅓⅔⅛]|\d+\s*/\s*\d+)\s*');

/// "de", "of", "di" — the preposition a Romance-language line puts between the
/// unit and the article. *1 caixa de leite condensado* is a box of condensed
/// milk, and the article is the milk.
final _leadingPreposition = RegExp(r'^(?:de|do|da|of|di|von|d)\s+', caseSensitive: false);

final _wordAtStart = RegExp(r'^([\p{L}.]+)\s+', unicode: true);
final _parenthetical = RegExp(r'\([^)]*\)');
final _whitespace = RegExp(r'\s+');

ListPlanItem? _itemFromLine(String raw) {
  var rest = raw.replaceAll(_parenthetical, ' ').replaceAll(_whitespace, ' ').trim();
  if (rest.isEmpty) return null;

  final quantity = StringBuffer();
  GroceryUnit? unit;
  // A unit word that is real but is not one of [GroceryUnit]'s ten — *Stangen*,
  // *Becher*, *TL*, *cucchiaio*. It goes in the unit column as itself, which
  // `groceryUnitFromKey` explicitly provides for ("an older row can still hold
  // a word a hand typed, and it is shown as itself rather than dropped").
  //
  // **It emphatically does not go in the quantity.** That field is drawn as a
  // small round badge beside the row, sized for a number; "3 Stangen" in there
  // is a sentence in a counter, and it sat next to rows reading a clean "500"
  // with their *g* on the subtitle line where it belongs.
  String? wordUnit;

  // Two passes at most, for "2 x 400 g Dosen": the multiplier is consumed by
  // the first and the real measure by the second. A third would be reading
  // article words as numbers.
  for (var pass = 0; pass < 2; pass++) {
    final number = _leadingQuantity.firstMatch(rest);
    if (number == null) break;
    if (quantity.isNotEmpty) quantity.write(' ');
    quantity.write(number.group(1)!.replaceAll(_whitespace, ''));
    rest = rest.substring(number.end);

    final fraction = _trailingFraction.firstMatch(rest);
    if (fraction != null) {
      quantity.write(' ${fraction.group(1)!.replaceAll(_whitespace, '')}');
      rest = rest.substring(fraction.end);
    }

    final word = _wordAtStart.firstMatch(rest);
    if (word == null) break;
    final candidate = word.group(1)!.toLowerCase();
    final bare = candidate.replaceAll('.', '');
    final shopping = _shoppingUnits[candidate] ?? _shoppingUnits[bare];
    if (shopping != null) {
      // The first real unit wins; a second one ("2 x 400 g") only confirms it.
      unit ??= shopping;
      rest = rest.substring(word.end);
      if (pass == 0 && candidate == 'x') continue;
      break;
    }
    if (_recipeUnits.contains(candidate) || _recipeUnits.contains(bare)) {
      // "x" is the one that really is part of the count — *2 x 400 g* is two
      // four-hundred-gram tins, and the multiplier means nothing on its own.
      if (bare == 'x') {
        quantity.write(' ${word.group(1)!}');
        rest = rest.substring(word.end);
        continue;
      }
      wordUnit ??= word.group(1);
      rest = rest.substring(word.end);
      break;
    }
    // Not a unit in any language we know — it is the article. Leave it.
    break;
  }

  // **Not every language puts the amount first.** Italian writes
  // *Latte intero 500 g*, and a Brazilian site writes *Molho de tomate 200
  // gramas* and *Alho 2 dentes*. A leading-quantity reader takes the whole
  // line as the article name and loses the amount on roughly a fifth of the
  // non-English web.
  //
  // **Only ever accepted when a unit word follows the number**, which is the
  // guard that makes this safe: *Weizenmehl Type 1050* and *Mehl Type 405* end
  // in a number that is part of the name, and without the unit test they would
  // come out as 1050 of a thing called "Weizenmehl Type".
  if (quantity.isEmpty) {
    final trailing = _trailingQuantity.firstMatch(rest);
    if (trailing != null) {
      final word = trailing.group(2)!.toLowerCase();
      final bare = word.replaceAll('.', '');
      final shopping = _shoppingUnits[word] ?? _shoppingUnits[bare];
      final isRecipeUnit = _recipeUnits.contains(word) || _recipeUnits.contains(bare);
      if (shopping != null || isRecipeUnit) {
        quantity.write(trailing.group(1)!.replaceAll(_whitespace, ''));
        if (shopping != null) {
          unit = shopping;
        } else {
          wordUnit ??= trailing.group(2);
        }
        rest = rest.substring(0, trailing.start);
      }
    }
  }

  rest = rest.replaceFirst(_leadingPreposition, '');
  final name = _articleName(rest);
  if (name.isEmpty) return null;
  return ListPlanItem(
    name: name,
    quantity: quantity.isEmpty ? null : quantity.toString(),
    // Matches [ListPlanItem.fromJson]: the default is stored as absent, so a
    // "Stück" line is not printed under every article for no information.
    // A [GroceryUnit] wins over a bare word when a line somehow produced both.
    unit: unit == GroceryUnit.piece
        ? null
        : (unit?.key ?? (wordUnit?.isEmpty ?? true ? null : wordUnit)),
  );
}

/// What the row will be called.
///
/// A recipe line qualifies its article after a comma — *Hackfleisch, Rind oder
/// gemischt*; *Salz und Pfeffer, aus der Mühle* — and that tail is instruction
/// for the cook, not part of what is bought. Cutting at the comma is a judgement
/// and it is occasionally wrong, which is exactly what the Vorhaben card's
/// per-row editing is for.
String _articleName(String input) {
  var s = input.trim();
  final comma = s.indexOf(',');
  if (comma > 2) s = s.substring(0, comma);
  s = s.replaceAll(RegExp(r'^[\s\-–•:]+'), '').replaceAll(_whitespace, ' ').trim();
  return s;
}

// ---------------------------------------------------------------------------
// Small HTML helpers. Deliberately not a DOM: the project has no HTML parser
// dependency and this needs three things out of the markup, not a tree.
// ---------------------------------------------------------------------------

final _tag = RegExp(r'<[^>]*>');
final _titleTag = RegExp(r'<title[^>]*>(.*?)</title\s*>', caseSensitive: false, dotAll: true);
final _ogTitle = RegExp(
  r'''<meta[^>]*property\s*=\s*['"]og:title['"][^>]*content\s*=\s*['"]([^'"]*)['"]''',
  caseSensitive: false,
);

String _titleFromHtml(String html) {
  final og = _ogTitle.firstMatch(html);
  if (og != null) {
    final text = _plainText(og.group(1) ?? '');
    if (text.isNotEmpty) return text;
  }
  final title = _titleTag.firstMatch(html);
  if (title == null) return '';
  // Sites hang their own name off the title with a dash or a pipe. The dish is
  // the part before it, and it is what the Liste should be called.
  final full = _plainText(title.group(1) ?? '');
  final cut = full.split(RegExp(r'\s+[|–—]\s+|\s+-\s+')).first.trim();
  return cut.isEmpty ? full : cut;
}

String _plainText(String input) =>
    _unescapeEntities(input.replaceAll(_tag, ' ')).replaceAll(_whitespace, ' ').trim();

const _entities = <String, String>{
  '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'", '&apos;': "'",
  '&nbsp;': ' ', '&auml;': 'ä', '&ouml;': 'ö', '&uuml;': 'ü', '&Auml;': 'Ä',
  '&Ouml;': 'Ö', '&Uuml;': 'Ü', '&szlig;': 'ß', '&eacute;': 'é', '&egrave;': 'è',
  '&ccedil;': 'ç', '&atilde;': 'ã', '&otilde;': 'õ', '&ntilde;': 'ñ', '&frac12;': '½',
  '&frac14;': '¼', '&frac34;': '¾', '&deg;': '°',
};
final _numericEntity = RegExp(r'&#(x?)([0-9a-fA-F]+);');

String _unescapeEntities(String input) {
  var s = input;
  _entities.forEach((from, to) => s = s.replaceAll(from, to));
  return s.replaceAllMapped(_numericEntity, (m) {
    final code = int.tryParse(m.group(2)!, radix: m.group(1)!.isEmpty ? 10 : 16);
    return code == null ? m.group(0)! : String.fromCharCode(code);
  });
}

/// Every map in a decoded JSON-LD document, in document order.
Iterable<Map<String, dynamic>> _walk(Object? node) sync* {
  if (node is Map<String, dynamic>) {
    yield node;
    for (final value in node.values) {
      yield* _walk(value);
    }
  } else if (node is List) {
    for (final value in node) {
      yield* _walk(value);
    }
  }
}

bool _isType(Map<String, dynamic> node, String type) {
  final raw = node['@type'];
  if (raw is String) return raw == type;
  if (raw is List) return raw.contains(type);
  return false;
}

List<String> _stringList(Object? raw) {
  if (raw is String) {
    final text = _plainText(raw);
    return text.isEmpty ? const [] : [text];
  }
  // **A JSON array serialised as an object.** sallys-blog.de publishes
  // `"recipeIngredient":{"0":"Eier","1":"Zucker",…}` — numeric string keys,
  // and sparse besides, which is what PHP produces when an array with holes in
  // it is handed to `json_encode`. It is not what schema.org says and it is
  // real, so the keys are sorted as numbers and the values taken in that
  // order; anything else keyed by words is a different object and refused.
  if (raw is Map) {
    final keys = raw.keys.map((k) => int.tryParse(k.toString())).toList();
    if (keys.any((k) => k == null)) return const [];
    final ordered = [...raw.entries]
      ..sort((a, b) => int.parse(a.key.toString()).compareTo(int.parse(b.key.toString())));
    return _stringList([for (final entry in ordered) entry.value]);
  }
  if (raw is! List) return const [];
  final out = <String>[];
  for (final entry in raw) {
    if (entry is String) {
      final text = _plainText(entry);
      if (text.isNotEmpty) out.add(text);
    } else if (entry is Map<String, dynamic>) {
      // Some pages wrap each ingredient in an object with a `name` or `text`.
      final text = _plainText((entry['name'] ?? entry['text'] ?? '').toString());
      if (text.isNotEmpty) out.add(text);
    }
  }
  return out;
}
