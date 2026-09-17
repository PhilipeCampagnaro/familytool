import '../models/grocery_unit.dart';
import 'grocery_search.dart';

/// Splitting a typed article into what it is and how many: *Reis x3* is one
/// article called "Reis" with a 3 in the quantity circle, not an article called
/// "Reis x3".
///
/// Households type the count into the name because the name is the field under
/// the thumb — the same shopping list ends up holding "Reis (x3)", "Reis x3" and
/// "Reis 3" as three unrelated rows. The columns to hold it properly already
/// exist (`list_items.sub` and `.unit`), so this is filling in a field rather
/// than inventing a concept, and the row renders the result the moment it lands:
/// the name loses the noise, the number appears in the circle.
///
/// **Rewriting what somebody typed is the risk**, and on a shared list the other
/// parent reads the result. So the grammar is deliberately small, and each form
/// is here because it cannot mean anything else:
///
/// * `x3`, `3x`, `(x3)`, `×3` at either end. Nothing but a count is written that
///   way.
/// * A number with one of [_unitWords] after it — "500 g", "1,5 l", "2 Dosen",
///   "10 Stück". The unit is said out loud, so there is nothing to guess.
/// * A bare number, "Reis 3", **only** under [_bareCountAllowed]: a grocery
///   list, a whole number of at most two digits, and the rest of the line still
///   has to name a real article. That last guard is what keeps *Omega 3*,
///   *Vitamin B12* and *5 Minuten Terrine* intact — "Omega" answers to nothing
///   in the catalog, so the 3 stays where it was put.
///
/// Applied when an article is **added** and nowhere else. Renaming a row is an
/// explicit act and re-parsing it would fight the hand doing it, and the rows
/// families already wrote are left exactly as they are.
class ArticleQuantity {
  /// The article with the count taken out — or the whole line untouched, which
  /// is the answer for nearly everything typed.
  final String text;

  /// What goes in the quantity circle, as typed: `null`, "3", "1,5". A string
  /// because that column is free text and older lists hold sentences in it.
  final String? amount;

  /// A [GroceryUnit] key, or `null` for Stück and for no unit at all — the two
  /// are the same thing in that column by design.
  final String? unit;

  const ArticleQuantity(this.text, {this.amount, this.unit});

  /// The line said nothing about a count.
  const ArticleQuantity.none(this.text) : amount = null, unit = null;
}

/// The unit words, in both interface languages, mapped onto the stored keys.
///
/// Not shared with `grocery_search.dart`'s own quantity regex on purpose: that
/// one only rubs the numbers off a line so an icon can be matched against what
/// is left, it is German-only because that is all it needs to be, and widening
/// it would change what matches. This map is the opposite job — it has to say
/// *which* unit, and it has to answer an English household too.
const _unitWords = <String, GroceryUnit>{
  'g': GroceryUnit.gram,
  'gr': GroceryUnit.gram,
  'gramm': GroceryUnit.gram,
  'gram': GroceryUnit.gram,
  'grams': GroceryUnit.gram,
  'kg': GroceryUnit.kilogram,
  'kilo': GroceryUnit.kilogram,
  'kilos': GroceryUnit.kilogram,
  'kilogramm': GroceryUnit.kilogram,
  'kilogram': GroceryUnit.kilogram,
  'kilograms': GroceryUnit.kilogram,
  'ml': GroceryUnit.milliliter,
  'milliliter': GroceryUnit.milliliter,
  'millilitre': GroceryUnit.milliliter,
  'l': GroceryUnit.liter,
  'ltr': GroceryUnit.liter,
  'liter': GroceryUnit.liter,
  'litre': GroceryUnit.liter,
  'liters': GroceryUnit.liter,
  'litres': GroceryUnit.liter,
  'pack': GroceryUnit.pack,
  'packs': GroceryUnit.pack,
  'packung': GroceryUnit.pack,
  'packungen': GroceryUnit.pack,
  'päckchen': GroceryUnit.pack,
  'packet': GroceryUnit.pack,
  'packets': GroceryUnit.pack,
  'dose': GroceryUnit.can,
  'dosen': GroceryUnit.can,
  'can': GroceryUnit.can,
  'cans': GroceryUnit.can,
  'flasche': GroceryUnit.bottle,
  'flaschen': GroceryUnit.bottle,
  'bottle': GroceryUnit.bottle,
  'bottles': GroceryUnit.bottle,
  'bund': GroceryUnit.bunch,
  'bunch': GroceryUnit.bunch,
  'bunches': GroceryUnit.bunch,
  'glas': GroceryUnit.glass,
  'gläser': GroceryUnit.glass,
  'glass': GroceryUnit.glass,
  'glasses': GroceryUnit.glass,
  'jar': GroceryUnit.glass,
  'jars': GroceryUnit.glass,
  'stück': GroceryUnit.piece,
  'stueck': GroceryUnit.piece,
  'stk': GroceryUnit.piece,
  'st': GroceryUnit.piece,
  'piece': GroceryUnit.piece,
  'pieces': GroceryUnit.piece,
  'pcs': GroceryUnit.piece,
};

/// Longest first, so `liter` is tried before the `l` that would swallow its
/// first letter and strand the rest.
final String _units = (_unitWords.keys.toList()..sort((a, b) => b.length.compareTo(a.length))).join('|');

/// A number, German or English decimal.
const String _number = r'\d+(?:[.,]\d+)?';

/// A count written as one — `x3`, `20x`. Three digits: it says what it is, so
/// there is no need to be shy about the size of it.
const String _count = r'\d{1,3}';

/// A count that is only a number sitting next to a word, which has to be small
/// enough that it cannot be anything else. "Wasser 500" is a millilitre whose
/// unit went unsaid, not five hundred waters.
const String _bareCount = r'\d{1,2}';

/// The four shapes, each anchored to one end of the line so that the *other*
/// end is the article — sliced off the original by the match's own offset, which
/// is why these are run against a lowercased copy and never used to rebuild the
/// text. Case folding a `ü` is exactly where a `caseSensitive: false` regex
/// stops agreeing with `toLowerCase`.
final _tailTimes = RegExp(r'[\s]+\(?\s*(?:[x×]\s*(' + _count + r')|(' + _count + r')\s*[x×])\s*\)?$');
final _headTimes = RegExp(r'^\(?\s*(?:[x×]\s*(' + _count + r')|(' + _count + r')\s*[x×])\s*\)?[\s]+');
final _tailUnit = RegExp(r'[\s]+\(?\s*(' + _number + r')\s*(' + _units + r')\b\.?\s*\)?$');
final _headUnit = RegExp(r'^\(?\s*(' + _number + r')\s*(' + _units + r')\b\.?\s*\)?[\s]+');
final _tailCount = RegExp(r'[\s]+\(?\s*(' + _bareCount + r')\s*\)?$');
final _headCount = RegExp(r'^\(?\s*(' + _bareCount + r')\s*\)?[\s]+');

/// Reads the count out of a typed article. Returns the line untouched whenever
/// it isn't sure, which is the whole design of it.
///
/// [grocery] is the list's own kind: the bare-number form needs the catalog to
/// vouch for what is left, and a Sonstige list has no catalog to ask. The two
/// spelled-out forms don't need one and apply everywhere — "Schrauben x20" and
/// "Farbe 2 Dosen" say what they mean on a Baumarkt list too.
ArticleQuantity parseArticleQuantity(String input, {required bool grocery}) {
  final text = input.trim();
  final probe = text.toLowerCase();

  final times = _tailTimes.firstMatch(probe) ?? _headTimes.firstMatch(probe);
  if (times != null) {
    final rest = _rest(text, times);
    if (rest != null) return ArticleQuantity(rest, amount: times.group(1) ?? times.group(2));
  }

  final unit = _tailUnit.firstMatch(probe) ?? _headUnit.firstMatch(probe);
  if (unit != null) {
    final rest = _rest(text, unit);
    if (rest != null) {
      final parsed = _unitWords[unit.group(2)!]!;
      // Stück is the default and is stored as nothing — see [GroceryUnit].
      return ArticleQuantity(
        rest,
        amount: unit.group(1),
        unit: parsed == GroceryUnit.piece ? null : parsed.key,
      );
    }
  }

  final count = _tailCount.firstMatch(probe) ?? _headCount.firstMatch(probe);
  if (count != null) {
    final rest = _rest(text, count);
    if (rest != null && _bareCountAllowed(rest, grocery: grocery)) {
      return ArticleQuantity(rest, amount: count.group(1));
    }
  }

  return ArticleQuantity.none(text);
}

/// The article, once the matched quantity is cut off whichever end it sat at.
/// `null` when nothing is left — a line that is only a quantity ("500 g", "x3")
/// is not an article with a count, it is somebody halfway through typing, and it
/// goes on the list exactly as written.
String? _rest(String text, RegExpMatch match) {
  final rest = (match.start == 0 ? text.substring(match.end) : text.substring(0, match.start)).trim();
  return rest.isEmpty ? null : rest;
}

/// Whether a bare number is safe to read as a count of [rest].
///
/// The catalog is the whole guard. *Reis* is an article and takes its 3; *Omega*
/// is not and keeps it. Asked strictly, so that a name merely containing a
/// grocery's letters somewhere doesn't vouch for itself.
bool _bareCountAllowed(String rest, {required bool grocery}) =>
    grocery && rest.length >= 2 && matchGroceryIcon(rest, strict: true) != null;
