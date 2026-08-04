/// What picture a *name* is about — the one matcher behind "type a name, get an
/// icon" for a list, a box, an article and a box item.
///
/// It is a pure function over three local catalogs, in this order:
///
/// 1. **A shop logo** (`assets/merchants/`, named by `merchant_logos.dart`).
///    A logo beats everything else: typing *Rewe* means the shop, not the
///    generic cart, and a household names half its lists after a store.
/// 2. **A Lucide symbol** ([symbolGroups] below) — the topics a household
///    actually names things after: Geburtstag, Baumarkt, Umzug, Keller.
/// 3. **A grocery picture** (`assets/grocery/`, via [matchGroceryIcon]) —
///    ~2000 photographed articles. Last, because it is by far the widest net;
///    pass `groceryFirst: true` inside a *Lebensmittel* list, where "Milch"
///    should be the milk carton and not a symbol that happens to share a word.
///
/// Nothing here touches the network. The old web app resolved unknown store
/// names through logo.dev; that stays a future option and is written up in
/// docs/ported-features.md, not built.
///
/// Matching itself is [rankTerm] from `grocery_search.dart` — the same
/// German-or-English, umlauts-optional comparison the article field has always
/// used — plus one German-specific extra, see [_compoundRank].
library;

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../l10n/l10n.dart';
import 'grocery_catalog.dart';
import 'grocery_search.dart';
import 'merchant_logos.dart';

/// Prefix that marks a stored icon as a Lucide glyph rather than an asset path.
/// Both live in the same `iconKey` field: a key either starts with this or is a
/// path under `assets/`, and nothing else is valid.
const lucideIconPrefix = 'lucide:';

/// What is being named, and therefore which of the three catalogs its icon may
/// come from. One value per *thing the user is looking at*, rather than a set of
/// booleans, because the rule is about meaning and not about configuration:
///
/// * A **[box]** is a place in the house — Keller, Dachboden, Umzugskiste. It
///   takes symbols and nothing else. A shop logo says where something was
///   bought, which is not what a box is, and an article photo would make a whole
///   box look like the one thing in it.
/// * A **[list]** is a container too, but one a household routinely names after
///   a shop ("Rewe", "dm"), so the logos stay and only the article photos go.
/// * An **[article]** is a single thing, so it may be a single picture. On a
///   Lebensmittel list it is a food name outright — [groceryArticle] hands the
///   photo catalog the first look, ahead of the symbols.
///
/// Every entry point takes it: [suggestIcon] for the automatic match,
/// [searchIcons] and the picker for the manual override, so a box can't be given
/// by hand what it would never be given automatically.
enum IconSubject {
  /// An article on a Lebensmittel list.
  groceryArticle,

  /// An article anywhere else — a Sonstige list, a box's contents.
  article,

  /// A shopping list.
  list,

  /// A box.
  box;

  /// Shop logos are for what you buy and where — never for a box.
  bool get allowsMerchants => this != IconSubject.box;

  /// A photograph of one article only ever stands for one article.
  bool get allowsGroceries => this == IconSubject.article || this == IconSubject.groceryArticle;
}

enum IconKind {
  /// A shop logo from `assets/merchants/`.
  merchant,

  /// A photographed article from `assets/grocery/`.
  grocery,

  /// A Lucide glyph from [symbolGroups].
  symbol,
}

/// One choosable icon: what to store ([key]), what to draw ([glyph] or
/// [asset]) and what to call it in the UI ([label], always German).
class IconChoice {
  final IconKind kind;
  final String key;
  final String label;

  /// Set for [IconKind.symbol] only; the other two kinds draw [asset].
  final IconData? glyph;

  const IconChoice({required this.kind, required this.key, required this.label, this.glyph});

  /// The asset path to draw, or `null` when this is a glyph.
  String? get asset => glyph == null ? key : null;

  @override
  bool operator ==(Object other) => other is IconChoice && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// A Lucide glyph with the German name it answers to.
class SymbolIcon {
  /// The Lucide icon's own name — the tail of the stored key, so a key survives
  /// being written to a database and read back.
  final String name;

  /// German label.
  final String de;

  /// English label. Hand-written: the Lucide [name] is close but not the same
  /// thing — `sprayCan` is "Drogerie" here, not "spray can".
  final String en;

  final IconData glyph;

  /// Everything else this symbol answers to: German synonyms, the English name
  /// people reach for, and the *bare stem* of a compound so "Wocheneinkauf"
  /// still finds "Einkauf" (see [_compoundRank]).
  final List<String> alias;

  const SymbolIcon(this.name, this.de, this.en, this.glyph, [this.alias = const []]);

  String get key => '$lucideIconPrefix$name';

  /// What the picker shows and what the "Symbol" row reads.
  String get label => L.s.localeCode == 'en' ? en : de;

  IconChoice get choice => IconChoice(kind: IconKind.symbol, key: key, label: label, glyph: glyph);
}

class SymbolGroup {
  final String de;
  final String en;
  final List<SymbolIcon> icons;

  const SymbolGroup(this.de, this.en, this.icons);

  String get label => L.s.localeCode == 'en' ? en : de;
}

/// The curated Lucide set — the icons a family organizer actually needs, not
/// the whole ~1500-glyph library.
///
/// The old web app put every Lucide export in a searchable grid; nobody scrolls
/// 1500 outline glyphs looking for "Geburtstag". This list is the same idea
/// pointed the other way: a few dozen icons, each named in German, so browsing
/// it is a short scroll *and* the smart match has something to match against.
/// An icon appears **once** — the groups are the picker's sections, and a glyph
/// in two of them would be two hits for one thing.
const symbolGroups = <SymbolGroup>[
  SymbolGroup('Einkauf', 'Shopping', [
    SymbolIcon('shoppingCart', 'Einkauf', 'Shopping', LucideIcons.shoppingCart, ['einkaufen', 'einkaufswagen', 'supermarkt', 'lebensmittel', 'shopping', 'groceries']),
    SymbolIcon('shoppingBasket', 'Einkaufskorb', 'Shopping basket', LucideIcons.shoppingBasket, ['korb', 'basket']),
    SymbolIcon('shoppingBag', 'Einkaufstasche', 'Shopping bag', LucideIcons.shoppingBag, ['tasche', 'tuete', 'bag']),
    SymbolIcon('store', 'Laden', 'Shop', LucideIcons.store, ['geschaeft', 'shop', 'markt', 'store', 'kiosk']),
    SymbolIcon('package', 'Paket', 'Parcel', LucideIcons.package, ['pakete', 'lieferung', 'bestellung', 'versand', 'delivery']),
    SymbolIcon('tag', 'Angebot', 'Offer', LucideIcons.tag, ['preis', 'preisschild', 'rabatt', 'sale']),
    SymbolIcon('creditCard', 'Karte', 'Card', LucideIcons.creditCard, ['bezahlen', 'kreditkarte', 'zahlung', 'card']),
    SymbolIcon('wallet', 'Geldbeutel', 'Wallet', LucideIcons.wallet, ['portemonnaie', 'geldboerse', 'wallet']),
    SymbolIcon('receipt', 'Kassenbon', 'Receipt', LucideIcons.receipt, ['quittung', 'beleg', 'rechnung', 'receipt']),
    SymbolIcon('banknote', 'Geld', 'Money', LucideIcons.banknote, ['budget', 'bargeld', 'kasse', 'money', 'cash']),
    SymbolIcon('barcode', 'Barcode', 'Barcode', LucideIcons.barcode, ['strichcode', 'scannen']),
  ]),
  SymbolGroup('Haushalt', 'Household', [
    SymbolIcon('house', 'Haus', 'House', LucideIcons.house, ['zuhause', 'wohnung', 'haushalt', 'home', 'heim']),
    SymbolIcon('sofa', 'Wohnzimmer', 'Living room', LucideIcons.sofa, ['sofa', 'couch', 'moebel', 'einrichtung', 'furniture']),
    SymbolIcon('bedDouble', 'Schlafzimmer', 'Bedroom', LucideIcons.bedDouble, ['bett', 'betten', 'bed']),
    SymbolIcon('bath', 'Bad', 'Bathroom', LucideIcons.bath, ['badezimmer', 'baden', 'dusche', 'bathroom']),
    SymbolIcon('lamp', 'Lampe', 'Lamp', LucideIcons.lamp, ['licht', 'leuchte', 'beleuchtung', 'light']),
    SymbolIcon('doorOpen', 'Tür', 'Door', LucideIcons.doorOpen, ['tueren', 'eingang', 'door']),
    SymbolIcon('keyRound', 'Schlüssel', 'Key', LucideIcons.keyRound, ['schluessel', 'key']),
    SymbolIcon('washingMachine', 'Wäsche', 'Laundry', LucideIcons.washingMachine, ['waschen', 'waschmaschine', 'waschkueche', 'laundry']),
    SymbolIcon('sprayCan', 'Drogerie', 'Toiletries', LucideIcons.sprayCan, ['putzen', 'putzmittel', 'reinigung', 'haushaltswaren', 'cleaning']),
    SymbolIcon('trash2', 'Müll', 'Rubbish', LucideIcons.trash2, ['abfall', 'entsorgen', 'trash']),
    SymbolIcon('plug', 'Strom', 'Electricity', LucideIcons.plug, ['steckdose', 'stecker', 'energie']),
    SymbolIcon('droplets', 'Wasser', 'Water', LucideIcons.droplets, ['water']),
  ]),
  SymbolGroup('Werkzeug & Bau', 'Tools & DIY', [
    SymbolIcon('hammer', 'Werkzeug', 'Tools', LucideIcons.hammer, ['hammer', 'reparatur', 'reparieren', 'basteln', 'tools']),
    SymbolIcon('wrench', 'Schrauben', 'Spanner', LucideIcons.wrench, ['schraubenschluessel', 'montage', 'wrench']),
    SymbolIcon('drill', 'Bohrmaschine', 'Drill', LucideIcons.drill, ['bohren', 'bohrer', 'akkuschrauber', 'drill']),
    SymbolIcon('hardHat', 'Baumarkt', 'DIY store', LucideIcons.hardHat, ['baustelle', 'bau', 'handwerk', 'renovierung', 'renovieren', 'umbau']),
    SymbolIcon('paintRoller', 'Streichen', 'Decorating', LucideIcons.paintRoller, ['farbe', 'malern', 'anstrich', 'tapete', 'paint']),
    SymbolIcon('ruler', 'Messen', 'Measuring', LucideIcons.ruler, ['massband', 'zollstock', 'lineal', 'ruler']),
  ]),
  SymbolGroup('Garten', 'Garden', [
    SymbolIcon('sprout', 'Garten', 'Garden', LucideIcons.sprout, ['gaertnern', 'gartenarbeit', 'pflanzen', 'saat', 'beet', 'garden']),
    SymbolIcon('flower2', 'Blumen', 'Flowers', LucideIcons.flower2, ['blume', 'strauss', 'flower']),
    SymbolIcon('treeDeciduous', 'Baum', 'Tree', LucideIcons.treeDeciduous, ['baeume', 'hecke', 'tree']),
    SymbolIcon('leaf', 'Pflanze', 'Plant', LucideIcons.leaf, ['blatt', 'gruen', 'plant']),
    SymbolIcon('shovel', 'Schaufel', 'Spade', LucideIcons.shovel, ['graben', 'spaten', 'shovel']),
  ]),
  SymbolGroup('Feiern & Feste', 'Celebrations', [
    SymbolIcon('cake', 'Geburtstag', 'Birthday', LucideIcons.cake, ['kuchen', 'torte', 'birthday', 'feier']),
    SymbolIcon('partyPopper', 'Party', 'Party', LucideIcons.partyPopper, ['fest', 'feiern', 'silvester', 'jubilaeum', 'party']),
    SymbolIcon('gift', 'Geschenk', 'Gift', LucideIcons.gift, ['geschenke', 'praesent', 'gift', 'wunschliste']),
    SymbolIcon('treePine', 'Weihnachten', 'Christmas', LucideIcons.treePine, ['weihnacht', 'advent', 'tannenbaum', 'christmas', 'xmas', 'nikolaus']),
    SymbolIcon('egg', 'Ostern', 'Easter', LucideIcons.egg, ['osterfest', 'easter']),
    SymbolIcon('sparkles', 'Deko', 'Decorations', LucideIcons.sparkles, ['dekoration', 'schmuck', 'glitzer']),
    SymbolIcon('music', 'Musik', 'Music', LucideIcons.music, ['lieder', 'konzert', 'music']),
  ]),
  SymbolGroup('Essen & Trinken', 'Food & drink', [
    SymbolIcon('utensils', 'Essen', 'Meals', LucideIcons.utensils, ['restaurant', 'mittag', 'abendessen', 'speiseplan', 'menue', 'food']),
    SymbolIcon('cookingPot', 'Kochen', 'Cooking', LucideIcons.cookingPot, ['topf', 'rezept', 'rezepte', 'kueche', 'cooking']),
    SymbolIcon('coffee', 'Kaffee', 'Coffee', LucideIcons.coffee, ['cafe', 'tee', 'coffee']),
    SymbolIcon('wine', 'Wein', 'Wine', LucideIcons.wine, ['wine']),
    SymbolIcon('beer', 'Bier', 'Beer', LucideIcons.beer, ['beer']),
    SymbolIcon('pizza', 'Pizza', 'Pizza', LucideIcons.pizza, ['italienisch']),
    SymbolIcon('iceCreamCone', 'Eis', 'Ice cream', LucideIcons.iceCreamCone, ['eiscreme', 'icecream']),
    SymbolIcon('flame', 'Grillen', 'Barbecue', LucideIcons.flame, ['grill', 'feuer', 'kamin', 'bbq']),
  ]),
  SymbolGroup('Familie', 'Family', [
    SymbolIcon('users', 'Familie', 'Family', LucideIcons.users, ['alle', 'gruppe', 'family', 'eltern']),
    SymbolIcon('user', 'Person', 'Person', LucideIcons.user, ['ich', 'profil', 'person']),
    SymbolIcon('baby', 'Baby', 'Baby', LucideIcons.baby, ['kind', 'kinder', 'saeugling', 'wickeln']),
    SymbolIcon('graduationCap', 'Schule', 'School', LucideIcons.graduationCap, ['schulsachen', 'lernen', 'uni', 'kita', 'hausaufgaben', 'school']),
    SymbolIcon('pawPrint', 'Haustier', 'Pet', LucideIcons.pawPrint, ['tier', 'hund', 'katze', 'tierbedarf', 'pet']),
    SymbolIcon('heart', 'Liebe', 'Love', LucideIcons.heart, ['lieblings', 'favoriten', 'heart']),
    SymbolIcon('briefcase', 'Arbeit', 'Work', LucideIcons.briefcase, ['buero', 'job', 'beruf', 'work']),
  ]),
  SymbolGroup('Gesundheit & Sport', 'Health & sport', [
    SymbolIcon('pill', 'Apotheke', 'Pharmacy', LucideIcons.pill, ['medikamente', 'medikament', 'tabletten', 'medizin', 'pille']),
    SymbolIcon('stethoscope', 'Arzt', 'Doctor', LucideIcons.stethoscope, ['doktor', 'praxis', 'termin', 'doctor']),
    SymbolIcon('heartPulse', 'Gesundheit', 'Health', LucideIcons.heartPulse, ['vorsorge', 'health']),
    SymbolIcon('syringe', 'Impfung', 'Vaccination', LucideIcons.syringe, ['spritze', 'impfen']),
    SymbolIcon('bandage', 'Erste Hilfe', 'First aid', LucideIcons.bandage, ['pflaster', 'verband', 'verbandskasten']),
    SymbolIcon('dumbbell', 'Sport', 'Sport', LucideIcons.dumbbell, ['fitness', 'training', 'sportsachen', 'gym']),
  ]),
  SymbolGroup('Reise & Auto', 'Travel & car', [
    SymbolIcon('car', 'Auto', 'Car', LucideIcons.car, ['wagen', 'werkstatt', 'pkw', 'car']),
    SymbolIcon('plane', 'Reise', 'Travel', LucideIcons.plane, ['urlaub', 'flug', 'flugzeug', 'ferien', 'travel']),
    SymbolIcon('luggage', 'Koffer', 'Suitcase', LucideIcons.luggage, ['gepaeck', 'packliste', 'packen', 'reisetasche']),
    SymbolIcon('trainFront', 'Zug', 'Train', LucideIcons.trainFront, ['bahn', 'train']),
    SymbolIcon('bus', 'Bus', 'Bus', LucideIcons.bus, ['bus']),
    SymbolIcon('bike', 'Fahrrad', 'Bicycle', LucideIcons.bike, ['rad', 'bike']),
    SymbolIcon('fuel', 'Tanken', 'Fuel', LucideIcons.fuel, ['tankstelle', 'benzin', 'diesel', 'sprit']),
    SymbolIcon('tent', 'Camping', 'Camping', LucideIcons.tent, ['zelt', 'campen', 'camping']),
    SymbolIcon('ship', 'Schiff', 'Ship', LucideIcons.ship, ['faehre', 'boot', 'ship']),
    SymbolIcon('mapPin', 'Ort', 'Place', LucideIcons.mapPin, ['adresse', 'karte', 'route', 'map']),
  ]),
  SymbolGroup('Kleidung', 'Clothing', [
    SymbolIcon('shirt', 'Kleidung', 'Clothing', LucideIcons.shirt, ['klamotten', 'hemd', 'shirt', 'anziehsachen', 'clothes']),
    SymbolIcon('footprints', 'Schuhe', 'Shoes', LucideIcons.footprints, ['schuh', 'stiefel', 'shoes']),
    SymbolIcon('glasses', 'Brille', 'Glasses', LucideIcons.glasses, ['sehhilfe', 'glasses']),
    SymbolIcon('watch', 'Uhr', 'Watch', LucideIcons.watch, ['armbanduhr', 'watch']),
    SymbolIcon('umbrella', 'Regenschirm', 'Umbrella', LucideIcons.umbrella, ['schirm', 'regen', 'umbrella']),
  ]),
  SymbolGroup('Technik', 'Tech', [
    SymbolIcon('smartphone', 'Handy', 'Phone', LucideIcons.smartphone, ['telefon', 'mobil', 'phone']),
    SymbolIcon('laptop', 'Laptop', 'Laptop', LucideIcons.laptop, ['notebook', 'computer', 'rechner']),
    SymbolIcon('monitor', 'Bildschirm', 'Monitor', LucideIcons.monitor, ['pc', 'monitor']),
    SymbolIcon('tv', 'Fernseher', 'TV', LucideIcons.tv, ['tv', 'fernsehen']),
    SymbolIcon('headphones', 'Kopfhörer', 'Headphones', LucideIcons.headphones, ['kopfhoerer', 'headset']),
    SymbolIcon('camera', 'Kamera', 'Camera', LucideIcons.camera, ['foto', 'fotos', 'bilder', 'camera']),
    SymbolIcon('cable', 'Kabel', 'Cable', LucideIcons.cable, ['ladekabel', 'stecker', 'cable']),
    SymbolIcon('batteryCharging', 'Batterien', 'Batteries', LucideIcons.batteryCharging, ['akku', 'batterie', 'laden', 'battery']),
    SymbolIcon('gamepad2', 'Spiele', 'Games', LucideIcons.gamepad2, ['gaming', 'konsole', 'spielzeug', 'games']),
    SymbolIcon('printer', 'Drucker', 'Printer', LucideIcons.printer, ['drucken', 'printer']),
  ]),
  SymbolGroup('Büro & Dokumente', 'Office & documents', [
    SymbolIcon('fileText', 'Dokumente', 'Documents', LucideIcons.fileText, ['dokument', 'unterlagen', 'papiere', 'vertrag', 'zeugnis', 'documents']),
    SymbolIcon('folder', 'Ordner', 'Folder', LucideIcons.folder, ['akten', 'mappe', 'folder']),
    SymbolIcon('book', 'Bücher', 'Books', LucideIcons.book, ['buch', 'lesen', 'book']),
    SymbolIcon('calendar', 'Termine', 'Events', LucideIcons.calendar, ['kalender', 'termin', 'calendar']),
    SymbolIcon('mail', 'Post', 'Post', LucideIcons.mail, ['briefe', 'brief', 'mail']),
    SymbolIcon('scissors', 'Schere', 'Scissors', LucideIcons.scissors, ['schneiden', 'scissors']),
    SymbolIcon('palette', 'Malen', 'Art', LucideIcons.palette, ['kunst', 'hobby', 'farben', 'art']),
    SymbolIcon('bell', 'Erinnerung', 'Reminder', LucideIcons.bell, ['erinnern', 'notiz', 'reminder']),
  ]),
  SymbolGroup('Aufbewahrung', 'Storage', [
    SymbolIcon('box', 'Box', 'Box', LucideIcons.box, ['kiste', 'karton', 'behaelter']),
    SymbolIcon('boxes', 'Umzug', 'Moving', LucideIcons.boxes, ['umziehen', 'kartons', 'kisten', 'moving']),
    SymbolIcon('warehouse', 'Lager', 'Storage', LucideIcons.warehouse, ['keller', 'dachboden', 'garage', 'abstellraum', 'speicher', 'schuppen', 'lagerraum']),
    SymbolIcon('archive', 'Archiv', 'Archive', LucideIcons.archive, ['aufbewahrung', 'aufbewahren', 'archiv']),
    SymbolIcon('layers', 'Stapel', 'Stack', LucideIcons.layers, ['sortiert', 'schichten']),
  ]),
  SymbolGroup('Jahreszeiten', 'Seasons', [
    SymbolIcon('sun', 'Sommer', 'Summer', LucideIcons.sun, ['sonne', 'sonnig', 'summer']),
    SymbolIcon('snowflake', 'Winter', 'Winter', LucideIcons.snowflake, ['schnee', 'kalt', 'winter']),
    SymbolIcon('leafyGreen', 'Frühling', 'Spring', LucideIcons.leafyGreen, ['fruehling', 'spring']),
    SymbolIcon('wind', 'Herbst', 'Autumn', LucideIcons.wind, ['wind', 'sturm', 'autumn']),
    SymbolIcon('star', 'Favorit', 'Favourite', LucideIcons.star, ['stern', 'wichtig', 'star']),
  ]),
];

// ---------------------------------------------------------------------------
// The index
// ---------------------------------------------------------------------------

/// Rank for a term that the *query* contains rather than the other way round —
/// see [_compoundRank]. Behind every rank [rankTerm] can produce.
const _compoundRankValue = 5;

/// German glues its nouns together, so half the names a household types are
/// longer than the word that identifies them: *Wocheneinkauf*, *Winterkleidung*,
/// *Geburtstagsparty*. [rankTerm] only answers "is the query inside the term",
/// which those never are — so a term of 4+ letters sitting inside the query
/// counts too, as the weakest kind of hit.
int? _compoundRank(String term, String query) {
  final rank = rankTerm(term, query);
  if (rank != null) return rank;
  if (term.length >= 4 && query.contains(term)) return _compoundRankValue;
  return null;
}

class _Scored {
  final IconChoice choice;
  final int rank;

  /// Tie-break within a rank; lower wins. For a normal hit that's the matched
  /// term's length — the shorter, more specific name ("Einkauf" over
  /// "Einkaufskorb"). For a compound hit it's *negated*, because there the
  /// longer stem is the more specific one: "Winterkleidung" should land on
  /// *Kleidung*, not on *Winter*.
  final int tie;

  const _Scored(this.choice, this.rank, this.tie);
}

class _Entry {
  final IconChoice choice;
  final List<String> terms;

  /// Whether [_compoundRank]'s German-compound step applies. Symbols want it —
  /// *Wocheneinkauf* is an Einkauf. Shop names must not have it: their names are
  /// short and brandable, and half of them turn up inside an ordinary German
  /// word (*Akku-schrauber* → Uber, *Geburtstags-party* → Spar).
  final bool compound;

  const _Entry(this.choice, this.terms, {this.compound = false});

  _Scored? score(String query) {
    int? best;
    var tie = 0;
    for (final term in terms) {
      final rank = compound ? _compoundRank(term, query) : rankTerm(term, query);
      if (rank == null) continue;
      final t = rank == _compoundRankValue ? -term.length : term.length;
      if (best == null || rank < best || (rank == best && t < tie)) {
        best = rank;
        tie = t;
      }
    }
    return best == null ? null : _Scored(choice, best, tie);
  }
}

List<String> _folded(Iterable<String> raw) => {for (final s in raw) foldTerm(s)}.where((s) => s.isNotEmpty).toList();

/// Every shop, folded once. Deduped by the *name* the file derives to, so the
/// twins in the folder (`ebay_de.png` and `ebay-logo.jpg`) are one shop.
final List<_Entry> _merchantIndex = () {
  final seen = <String>{};
  final out = <_Entry>[];
  for (final file in merchantFiles) {
    final asset = '$merchantAssetDir$file';
    final name = merchantNameFor(asset);
    if (name == null || name.isEmpty || !seen.add(foldTerm(name))) continue;
    out.add(_Entry(IconChoice(kind: IconKind.merchant, key: asset, label: name), _folded([name])));
  }
  out.sort((a, b) => a.choice.label.toLowerCase().compareTo(b.choice.label.toLowerCase()));
  return out;
}();

final List<_Entry> _symbolIndex = [
  for (final group in symbolGroups)
    for (final icon in group.icons) _Entry(icon.choice, _folded([icon.de, icon.en, icon.name, ...icon.alias]), compound: true),
];

final Map<String, IconChoice> _symbolsByKey = {for (final entry in _symbolIndex) entry.choice.key: entry.choice};

/// Shops in one flat, alphabetical list — what the picker browses.
List<IconChoice> get merchantChoices => [for (final entry in _merchantIndex) entry.choice];

// ---------------------------------------------------------------------------
// Matching
// ---------------------------------------------------------------------------

/// Best hit in [index] for [text]: the whole line first, then its words
/// longest-first, so "Einkauf bei Rewe" still finds the shop. Same shape as
/// [matchGroceryIcon], deliberately — one rule for how a typed line is read.
IconChoice? _match(List<_Entry> index, String text, {int maxRank = _compoundRankValue}) {
  final full = foldItemText(text);
  if (full.length < 2) return null;

  final direct = _best(index, full, maxRank);
  if (direct != null) return direct;

  final words = full.split(' ').where((w) => w.length >= 3).toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final word in words) {
    final hit = _best(index, word, maxRank);
    if (hit != null) return hit;
  }
  return null;
}

/// A two-letter query may only match a name *exactly* ("dm", "Q1"); anything
/// looser needs three, or every third keystroke would flash a different logo.
IconChoice? _best(List<_Entry> index, String query, int maxRank) {
  _Scored? best;
  for (final entry in index) {
    final scored = entry.score(query);
    if (scored == null || scored.rank > maxRank) continue;
    if (query.length < 3 && scored.rank != 0) continue;
    // "contains it somewhere" is too loose to pick an icon off — it is what
    // makes *Real* out of "Realschule". Browsing (see [searchIcons]) keeps it.
    if (scored.rank == 3) continue;
    if (best == null || scored.rank < best.rank || (scored.rank == best.rank && scored.tie < best.tie)) {
      best = scored;
    }
  }
  return best?.choice;
}

/// The icon a typed name is about, or `null` when nothing fits and the caller
/// should fall back to its own default ([defaultListIcon] and friends).
///
/// The order is the one in this library's doc, with one refinement either side
/// of the shop logos:
///
/// * A symbol whose German name the text hits **exactly** goes first. "Shop
///   logo beats generic icon" is about an ambiguous match, not about *Baby*
///   having to become BabyOne or *Apotheke* the Shop-Apotheke logo.
/// * Everything looser about a symbol goes after the shops, so *Ede…* is still
///   Edeka on the third keystroke.
///
/// [subject] is what is being named, and decides which catalogs are in play at
/// all — see [IconSubject]. A box sees only the symbols, a list only the symbols
/// and the shops, an article everything.
IconChoice? suggestIcon(String text, {IconSubject subject = IconSubject.article}) {
  if (text.trim().isEmpty) return null;

  // Nothing to weigh against anything: the symbols are the whole catalog.
  if (subject == IconSubject.box) return _match(_symbolIndex, text);

  // A food name outright, so the photos come before the symbols and are allowed
  // their loosest matches.
  if (subject == IconSubject.groceryArticle) {
    return _match(_merchantIndex, text) ?? _groceryChoice(text, strict: false) ?? _match(_symbolIndex, text);
  }

  // The *whole* line only, not its words: "Rewe Einkauf" is the shop, and
  // splitting here would hand it to the cart before the logos get a look.
  final exact = _best(_symbolIndex, foldItemText(text), 0);
  if (exact != null) return exact;
  final merchant = _match(_merchantIndex, text);
  if (merchant != null) return merchant;
  return _match(_symbolIndex, text) ?? (subject.allowsGroceries ? _groceryChoice(text, strict: true) : null);
}

IconChoice? _groceryChoice(String text, {required bool strict}) {
  // Two letters are enough to name an article you're typing into a grocery
  // list; they are not enough to decide what an arbitrary name is about — "Ed"
  // would put an edamame pod on a list on its way to being called Edeka.
  if (strict && foldItemText(text).length < 3) return null;
  final icon = matchGroceryIcon(text, strict: strict);
  return icon == null ? null : IconChoice(kind: IconKind.grocery, key: icon.asset, label: icon.label);
}

/// What a stored key draws and is called, or `null` for an empty/unknown one —
/// an icon can be removed from the catalogs while a list still points at it.
IconChoice? resolveIcon(String? key) {
  if (key == null || key.isEmpty) return null;
  if (key.startsWith(lucideIconPrefix)) return _symbolsByKey[key];
  final merchant = merchantNameFor(key);
  if (merchant != null) return IconChoice(kind: IconKind.merchant, key: key, label: merchant);
  final grocery = groceryIconByAsset[key];
  if (grocery != null) return IconChoice(kind: IconKind.grocery, key: key, label: grocery.label);
  return null;
}

/// Free-text search across all three catalogs — the picker's search field.
///
/// Wider than [suggestIcon] on purpose: browsing wants everything that could
/// plausibly be it (so "contains" counts), picking one icon for a name does not.
/// Order is shops, then symbols, then groceries within each rank, which keeps a
/// searched-for store at the top where it belongs.
///
/// [subject] narrows it the same way it narrows [suggestIcon] — the picker must
/// not offer by hand what the automatic match is not allowed to pick.
List<IconChoice> searchIcons(String query, {int limit = 60, IconSubject subject = IconSubject.article}) {
  final q = foldTerm(query);
  if (q.isEmpty) return const [];

  final hits = <_Scored>[];
  for (final entry in [if (subject.allowsMerchants) ..._merchantIndex, ..._symbolIndex]) {
    final scored = entry.score(q);
    if (scored != null) hits.add(scored);
  }
  hits.sort((a, b) => a.rank != b.rank ? a.rank.compareTo(b.rank) : a.tie.compareTo(b.tie));

  final out = [for (final hit in hits.take(limit)) hit.choice];
  if (subject.allowsGroceries && out.length < limit) {
    for (final icon in groceryIconSuggestions(query, limit: limit - out.length)) {
      out.add(IconChoice(kind: IconKind.grocery, key: icon.asset, label: icon.label));
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Fallbacks
// ---------------------------------------------------------------------------

/// What a list, a box and an item wear when nothing matched. Named rather than
/// spelled out at each call site so "no icon" looks the same everywhere.
const defaultListIcon = IconChoice(kind: IconKind.symbol, key: '${lucideIconPrefix}clipboardCheck', label: 'Liste', glyph: LucideIcons.clipboardCheck);
const defaultGroceryListIcon = IconChoice(kind: IconKind.symbol, key: '${lucideIconPrefix}shoppingCart', label: 'Einkauf', glyph: LucideIcons.shoppingCart);
const defaultBoxIcon = IconChoice(kind: IconKind.symbol, key: '${lucideIconPrefix}box', label: 'Box', glyph: LucideIcons.box);
const defaultItemIcon = IconChoice(kind: IconKind.symbol, key: '${lucideIconPrefix}clipboardList', label: 'Artikel', glyph: LucideIcons.clipboardList);
