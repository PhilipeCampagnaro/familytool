import 'grocery_catalog.dart';
import 'merchant_logos.dart';

/// Matching for the Listen screen: which icon a typed article gets, what the
/// suggestion chips offer, and whether a search query hits an item.
///
/// Two things it has to survive, both from the same household typing into the
/// same field:
///
/// * **All four languages at once.** The files are named in English and the
///   interface is one of four, and people reach for any of them regardless —
///   "Milch", "milk", "leite" and "leche" all land on `Dairy_Milk` whichever
///   language Settings is set to. Every name is indexed always; the interface
///   language decides only what is *shown*, never what can be found. That
///   matters more than it sounds in a bilingual household: a Portuguese parent
///   and a German grandparent share one list.
/// * **How German is actually typed.** Umlauts get spelled out or dropped, so
///   *Müsli*, *Muesli* and *Musli* have to be one query: [foldTerm] folds all
///   three to the same string, and folds the catalog the same way so the
///   comparison stays symmetric.

const _foldPairs = {
  'ä': 'a',
  'ö': 'o',
  'ü': 'u',
  'ß': 'ss',
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'í': 'i',
  'ì': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ç': 'c',
  'ñ': 'n',
  // Portuguese nasals. Not optional politeness: anything left unfolded is
  // stripped by [_punctuation] below, so without these `Romã` folds to "rom"
  // and stops answering to *roma* — the icon would be in the catalog and
  // findable by nothing.
  'ã': 'a',
  'õ': 'o',
  'ẽ': 'e',
  'ĩ': 'i',
  'ũ': 'u',
};

/// Everything that isn't a letter or a digit becomes a space: `Coca-Cola`,
/// `Kellogg's` and `Baby_Care_&_Hygiene` all have to survive being typed
/// without their punctuation.
final _punctuation = RegExp(r'[^a-z0-9 ]+');
final _spaces = RegExp(r'\s+');

/// Quantities and pack sizes: "Milch 2 Liter", "Mehl 500g" and "Eier (10
/// Stück)" are all still about the head noun. Longest units first — `l` would
/// otherwise swallow the `l` of "liter" and leave the rest stranded.
final _parenthetical = RegExp(r'\([^)]*\)');
final _quantity = RegExp(r'\b\d+[.,]?\d*\s*(liter|litre|packung|pack|stueck|stück|stk|dosen|dose|gramm|kg|mg|ml|cl|st|g|l|x)?\b');

/// The comparison form of a word. Lowercases, folds umlauts and accents to
/// their base letter, drops punctuation, then collapses the *spelled-out*
/// umlauts (`ae`/`oe`/`ue`) onto the same letter — that last step is what makes
/// "Kaese", "Käse" and "Kase" one query. It over-folds the odd English word
/// ("blueberry" → "bluberry"), which is harmless: both sides of every
/// comparison come through here, so they over-fold identically.
String foldTerm(String input) {
  var s = input.toLowerCase();
  _foldPairs.forEach((from, to) => s = s.replaceAll(from, to));
  s = s.replaceAll(_punctuation, ' ');
  s = s.replaceAll('ae', 'a').replaceAll('oe', 'o').replaceAll('ue', 'u');
  return s.replaceAll(_spaces, ' ').trim();
}

/// [foldTerm] plus the quantity noise an article line carries — the form used
/// when asking "what is this item, really?".
String foldItemText(String input) {
  final stripped = input.toLowerCase().replaceAll(_parenthetical, ' ').replaceAll(_quantity, ' ');
  final folded = foldTerm(stripped);
  // A line that was *only* a quantity ("2 Liter") folds away to nothing; fall
  // back to the raw text rather than letting an empty query match everything.
  return folded.isEmpty ? foldTerm(input) : folded;
}

/// How well `term` answers `query`; lower is better, `null` is no match.
///
/// Exact → whole-term prefix → prefix of a word inside the term → anywhere.
/// That third step is what makes the English file names usable at all:
/// `Dairy_Milk.png` reads as "dairy milk", which nobody types the start of.
///
/// Public because it is *the* comparison in this app: `icon_suggestions.dart`
/// ranks shop names and Lucide symbols against a typed name with the same
/// function, so a list, an article and a box all agree on what "matches".
int? rankTerm(String term, String query) {
  if (term == query) return 0;
  if (term.startsWith(query)) return 1;
  for (var i = term.indexOf(' '); i != -1; i = term.indexOf(' ', i + 1)) {
    if (term.startsWith(query, i + 1)) return 2;
  }
  return term.contains(query) ? 3 : null;
}

/// Rank given to an icon that only its *category* matched.
const _categoryRank = 4;

/// The catalog with every term pre-folded — a query touches all ~2000 of them,
/// and folding them per keystroke was the one expensive thing here. Built on
/// first use.
final List<_FoldedIcon> _index = [
  for (final category in groceryCategories)
    for (final entry in _foldCategory(category)) entry,
];

List<_FoldedIcon> _foldCategory(GroceryCategory category) {
  // The section's own file-name prefix, dropped from every English term in it.
  // Left in, `Bread_Bagel.png` would read as "bread bagel" and win the query
  // *Brot/bread* outright — a whole category of file names all start with the
  // word people search the category by.
  final prefix = sharedFilePrefix(category.icons);
  final categoryTerms = [
    foldTerm(category.de),
    foldTerm(category.en),
    foldTerm(category.pt),
    foldTerm(category.es),
    if (prefix.isNotEmpty) foldTerm(prefix),
  ].where((t) => t.isNotEmpty).toList();
  return [
    for (final icon in category.icons)
      _FoldedIcon(
        icon,
        {
          foldTerm(icon.de),
          // The English label as *shown*, which for an overridden file is not
          // anything the file name says — "Chocolate figures" has to be
          // findable by the name it wears.
          foldTerm(icon.en),
          // Both nullable — a file the Portuguese or Spanish map hasn't reached
          // yet folds to the empty string and is dropped by the `where` below,
          // rather than indexing every icon under one shared blank term.
          foldTerm(icon.pt ?? ''),
          foldTerm(icon.es ?? ''),
          for (final term in icon.alias) foldTerm(term),
          for (final phrase in _phrases(icon.file.substring(prefix.length))) foldTerm(phrase),
        }.where((t) => t.isNotEmpty).toList(),
        categoryTerms,
        foldTerm(icon.de).length,
      ),
  ];
}

/// A file name as the phrases it's worth matching on: the name itself, and each
/// parenthesised aside on its own — "Cocoa_powder_(for_chocolate_cakes)"
/// shouldn't make "cocoa powder" a five-word phrase.
List<String> _phrases(String file) {
  final stem = file.replaceAll(RegExp(r'\.png$'), '');
  final asides = RegExp(r'\(([^)]*)\)').allMatches(stem).map((m) => m.group(1)!);
  final main = stem.replaceAll(RegExp(r'\([^)]*\)'), ' ');
  return [main, ...asides].map((s) => s.replaceAll('_', ' ')).toList();
}

final Map<String, _FoldedIcon> _byFile = {for (final entry in _index) entry.icon.file: entry};

class _FoldedIcon {
  final GroceryIcon icon;
  final List<String> terms;
  final List<String> categoryTerms;

  /// Length of the German label, the tie-break for a category-only hit.
  final int labelLength;

  const _FoldedIcon(this.icon, this.terms, this.categoryTerms, this.labelLength);
}

class _Hit {
  final GroceryIcon icon;
  final int rank;

  /// Length of the term that matched — on equal rank the more specific (that
  /// is, shorter) name wins, so "Milch" beats "Schokomilch" for *Milch*.
  final int length;

  const _Hit(this.icon, this.rank, this.length);
}

/// Best hit per icon, ordered best-first. `matchCategory` lets a section name
/// ("Gemüse", "Vegetables") stand in for everything under it — useful while
/// browsing suggestions, wrong when picking the *one* icon for an article.
List<_Hit> _search(String query, {required bool matchCategory}) {
  if (query.length < 2) return const [];

  final hits = <_Hit>[];
  for (final entry in _index) {
    int? best;
    var bestLength = 0;
    for (final term in entry.terms) {
      final rank = rankTerm(term, query);
      if (rank == null) continue;
      if (best == null || rank < best || (rank == best && term.length < bestLength)) {
        best = rank;
        bestLength = term.length;
      }
    }
    // A category hit ranks behind every real name match, so "Gemüse" fills up
    // with vegetables only after anything actually called that.
    if (best == null && matchCategory && entry.categoryTerms.any((t) => rankTerm(t, query) != null)) {
      best = _categoryRank;
      bestLength = entry.labelLength;
    }
    if (best != null) hits.add(_Hit(entry.icon, best, bestLength));
  }

  hits.sort((a, b) {
    final byRank = a.rank.compareTo(b.rank);
    return byRank != 0 ? byRank : a.length.compareTo(b.length);
  });
  return hits;
}

/// The icon a typed article gets, or `null` if nothing fits.
///
/// Tries the whole line first ("Grüner Salat"), then its words longest-first,
/// so a line with a qualifier still finds its head noun. Filler words fall out
/// via the length floor rather than a stop-word list.
///
/// [strict] drops the weakest kind of hit — the query merely appearing
/// *somewhere* inside a name. Inside a Lebensmittel list that hit earns its
/// keep; asked about an arbitrary name it produces nonsense (a list called
/// "Mia" matching *Thymian*), so `icon_suggestions.dart` asks strictly when the
/// grocery catalog is only its last resort.
GroceryIcon? matchGroceryIcon(String text, {bool strict = false}) {
  final full = foldItemText(text);
  if (full.length < 2) return null;

  final direct = _search(full, matchCategory: false);
  if (direct.isNotEmpty && !(strict && direct.first.rank >= 3)) return direct.first.icon;

  final words = full.split(' ').where((w) => w.length >= 3).toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final word in words) {
    final hits = _search(word, matchCategory: false);
    if (hits.isEmpty || (strict && hits.first.rank >= 3)) continue;
    return hits.first.icon;
  }
  // A name found *inside* the word is weaker still than one the word is found
  // inside, and a misspelt one weaker than that, so a strict caller gets neither.
  return strict ? null : (_compoundMatch(full) ?? _typoMatch(full));
}

/// Shortest word, and shortest name, a one-letter slip is forgiven on. Below
/// this a single letter is too much of the word: *Reis* is one away from *Eis*.
const _minTypo = 7;

/// A name one keystroke away from a typed word — a letter swapped, dropped or
/// added. On a German keyboard **T and Z sit side by side**, so *Gewürtmischung*
/// is what *Gewürzmischung* looks like typed quickly, and a missed *h* turns
/// *Hähnchen* into *Hänchen*. Aliasing every such slip one by one never ends.
///
/// Whole words only, and only after the compound step has found nothing, so a
/// correctly spelt article can never be pulled onto a neighbour's icon.
GroceryIcon? _typoMatch(String folded) {
  for (final word in folded.split(' ')) {
    if (word.length < _minTypo) continue;
    for (final entry in _index) {
      for (final term in entry.terms) {
        if (term.length >= _minTypo && !term.contains(' ') && _oneEditApart(word, term)) {
          return entry.icon;
        }
      }
    }
  }
  return null;
}

/// Whether one substitution, insertion or deletion turns [a] into [b].
bool _oneEditApart(String a, String b) {
  if (a == b) return false;
  final (shorter, longer) = a.length <= b.length ? (a, b) : (b, a);
  if (longer.length - shorter.length > 1) return false;
  var i = 0;
  while (i < shorter.length && shorter[i] == longer[i]) {
    i++;
  }
  // Same length: skip the one differing letter on both. Otherwise skip it on
  // the longer only. Either way the rest must line up exactly.
  final skip = shorter.length == longer.length ? 1 : 0;
  return shorter.substring(i + skip) == longer.substring(i + 1);
}

/// Shortest word worth splitting, and shortest catalog name worth finding in it.
const _minCompound = 5;
const _minPart = 4;

/// Shorter than this, a name found inside a word that doesn't *end* it is more
/// likely the modifier than the thing: *Kaffee* in *Kaffeefilter* (6) is not
/// the article, *Hähnchenbrust* in *Hähnchenbrustfilet* (13) is.
const _minInfix = 8;

/// Every other step asks whether the query is a piece of a name; German asks
/// the reverse just as often. It glues words together, so *Rinderhackfleisch*,
/// *Kinderjoghurt* and *Hähnchenbrustfilet* are longer than every name we hold
/// and contain one — `Hackfleisch`, `Joghurt`, `Hähnchenbrust` — and no prefix
/// or substring test in that direction can see it.
///
/// A German compound's head noun comes **last**, so a name the word ends with
/// wins: *Kinderjoghurt* is a yoghurt. Only when no name ends the word does a
/// long one inside it count (`_minInfix`), which
/// is what still finds *Hähnchenbrustfilet* — the filet is the head and we have
/// no picture called that. The longest name wins either way, so *Rinderhack*
/// beats *Hack*.
///
/// Last resort only: reached when nothing matched the ordinary way, so it can
/// never take a query away from an icon that answers it directly.
GroceryIcon? _compoundMatch(String folded) {
  _Hit? best;
  var bestSuffix = false;
  for (final word in folded.split(' ')) {
    if (word.length < _minCompound) continue;
    for (final entry in _index) {
      for (final term in entry.terms) {
        if (term.length < _minPart || term.length >= word.length || term.contains(' ')) continue;
        final suffix = word.endsWith(term);
        if (!suffix && (term.length < _minInfix || !word.contains(term))) continue;
        final better = best == null ||
            (suffix && !bestSuffix) ||
            (suffix == bestSuffix && term.length > best.length);
        if (better) {
          best = _Hit(entry.icon, 0, term.length);
          bestSuffix = suffix;
        }
      }
    }
  }
  return best?.icon;
}

/// Autocomplete for the "Artikel hinzufügen" field: up to [limit] icons,
/// offered under their name in the interface language. Deduped by that name, so
/// the near-identical files in the set ("Feta" / "Feta-Käse") don't spend two
/// chips on one thing — and so the dedupe follows whichever language is on,
/// since two files can collide in one language and not the other.
List<GroceryIcon> groceryIconSuggestions(String query, {int limit = 8}) {
  final folded = foldItemText(query);
  final seen = <String>{};
  final out = <GroceryIcon>[];
  for (final hit in _search(folded, matchCategory: true)) {
    if (!seen.add(foldTerm(hit.icon.label))) continue;
    out.add(hit.icon);
    if (out.length == limit) break;
  }
  // Typed a compound the catalog only holds a piece of — offer that piece
  // rather than an empty row of chips.
  if (out.isEmpty && folded.length >= _minCompound) {
    final fallback = _compoundMatch(folded) ?? _typoMatch(folded);
    if (fallback != null) out.add(fallback);
  }
  return out;
}

/// Whether an article answers to [query] — the cross-language half of the
/// Listen search. The literal text is the caller's job; this adds what the item
/// *is*, so "Milch" is found by *milk* and "Waschmittel" by *detergent*.
///
/// [iconKey] wins over the text when the item already carries a grocery
/// picture: it's a firmer statement of what the thing is than re-deriving it
/// from a label. A key that isn't one of those (a logo, a Lucide symbol) simply
/// falls through to the text.
bool groceryTermsMatch(String text, String query, {String? iconKey}) {
  final q = foldTerm(query);
  if (q.length < 2) return false;
  final icon = (iconKey == null ? null : groceryIconByAsset[iconKey]) ?? matchGroceryIcon(text);
  if (icon == null) return false;
  final entry = _byFile[icon.file];
  return entry != null && entry.terms.any((term) => rankTerm(term, q) != null);
}

/// Whether a list answers to [query]: its own name, umlaut-insensitively, plus
/// the shop its logo stands for — a "Wocheneinkauf" carrying the REWE logo is
/// findable as *Rewe*.
bool listMatchesQuery(String name, String query, {String? iconKey}) {
  final q = foldTerm(query);
  if (q.isEmpty) return false;
  if (foldTerm(name).contains(q)) return true;
  final merchant = iconKey == null ? null : merchantNameFor(iconKey);
  return merchant != null && foldTerm(merchant).contains(q);
}
