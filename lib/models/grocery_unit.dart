import '../l10n/l10n.dart';

/// What an article's quantity counts — the "kg" in *2 kg Kartoffeln*.
///
/// Stored on `list_items.unit` as [key], never as the word: the app switches
/// language while it is running, so a stored "Liter" would stay German in an
/// English household. [L.s.unitName] answers the word, exactly as it does for
/// the Feiertage.
///
/// **[piece] is the default and is stored as `null`.** An article with no unit
/// is one of it, and writing 'piece' on every row would put a "Stück" line under
/// every article in the list for no information.
enum GroceryUnit {
  piece('piece'),
  gram('g'),
  kilogram('kg'),
  milliliter('ml'),
  liter('l'),
  pack('pack'),
  can('can'),
  bottle('bottle'),
  bunch('bunch'),
  glass('glass');

  /// What goes in the column. Deliberately not the enum's Dart name: 'kg' reads
  /// the same in a database client as it does in the app.
  final String key;

  const GroceryUnit(this.key);

  String get label => L.s.unitName(this);
}

/// The unit a stored value names, or `null` for the default and for anything the
/// keys don't cover — an older row can still hold a word a hand typed, and it is
/// shown as itself rather than dropped. See [groceryUnitLabel].
GroceryUnit? groceryUnitFromKey(String? key) {
  if (key == null || key.isEmpty) return null;
  for (final unit in GroceryUnit.values) {
    if (unit.key == key) return unit;
  }
  return null;
}

/// What a row prints for a stored unit: the word in the interface language when
/// the value is one of ours, the value itself when it is a leftover.
String groceryUnitLabel(String key) => groceryUnitFromKey(key)?.label ?? key;
