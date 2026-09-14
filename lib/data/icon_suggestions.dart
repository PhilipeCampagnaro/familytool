/// What picture a *name* is about — the one matcher behind "type a name, get an
/// icon" for a list, a box, an article and a box item.
///
/// It is a pure function over three local catalogs, in this order:
///
/// 1. **A shop logo** (`assets/merchants/`, named by `merchant_logos.dart`).
///    For a *list*, a logo beats everything else: typing *Rewe* means the shop,
///    not the generic cart, and a household names half its lists after a store.
///    An article never takes one — see [IconSubject].
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

import '../l10n/l10n.dart';
import 'grocery_catalog.dart';
import 'grocery_search.dart';
import 'merchant_logos.dart';
import '../theme/app_icons.dart';

/// Prefix that marks a stored icon as a Lucide glyph rather than an asset path.
/// Both live in the same `iconKey` field: a key either starts with this or is a
/// path under `assets/`, and nothing else is valid.
/// The prefix on a stored symbol key.
///
/// **The value stays `'lucide:'` even though the drawings are Phosphor now.**
/// It is on rows in `lists`, `boxes` and `tasks` that families wrote before the
/// swap, so it is a wire format, not a name — changing it would orphan every
/// icon anybody has ever chosen. Only the *drawing* behind a key changed; the
/// key itself, `lucide:pencil`, still resolves and always will.
const symbolIconPrefix = 'lucide:';

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
/// * An **[article]** is a single thing, so it may be a single picture — but
///   never a shop logo. A logo names a *place you go*, which is what a list is
///   for; a line on that list is the thing you bring home, so "Rewe" typed as
///   an article is a word the shop happens to share and not the shop. On a
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

  /// Shop logos say *where* — so they belong to a list, and to nothing else.
  /// Neither a box nor a single article is a place.
  bool get allowsMerchants => this == IconSubject.list;

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
  /// The symbol's stable name — the tail of the stored key, so a key survives
  /// being written to a database and read back. These are the *Lucide* names
  /// the app was first built on, and they stay that way for the reason
  /// [symbolIconPrefix] does: they are already in the database. The [glyph]
  /// beside each one is Phosphor.
  final String name;

  /// German label.
  final String de;

  /// English label. Hand-written: the Lucide [name] is close but not the same
  /// thing — `sprayCan` is "Drogerie" here, not "spray can".
  final String en;

  /// Portuguese and Spanish, hand-written for the same reason [en] is: the
  /// Phosphor [name] is close but not the same thing. Written out on the line
  /// rather than tabulated the way `grocery_catalog.dart` does it — this set is
  /// curated and a hundred-odd entries long, so a new symbol is meant to cost
  /// four labels, and the compiler cannot ask for them.
  final String pt;
  final String es;

  final IconData glyph;

  /// Everything else this symbol answers to: synonyms in any of the four
  /// languages, and the *bare stem* of a compound so "Wocheneinkauf" still
  /// finds "Einkauf" (see [_compoundRank]).
  final List<String> alias;

  const SymbolIcon(this.name, this.de, this.en, this.pt, this.es, this.glyph,
      [this.alias = const []]);

  String get key => '$symbolIconPrefix$name';

  /// What the picker shows and what the "Symbol" row reads.
  String get label => pickLabel(de: de, en: en, pt: pt, es: es);

  IconChoice get choice => IconChoice(kind: IconKind.symbol, key: key, label: label, glyph: glyph);
}

class SymbolGroup {
  final String de;
  final String en;
  final String pt;
  final String es;
  final List<SymbolIcon> icons;

  const SymbolGroup(this.de, this.en, this.pt, this.es, this.icons);

  String get label => pickLabel(de: de, en: en, pt: pt, es: es);
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
  SymbolGroup('Einkauf', 'Shopping', 'Compras', 'Compras', [
    SymbolIcon('shoppingCart', 'Einkauf', 'Shopping', 'Compras', 'Compras', AppIcons.shoppingCart, ['einkaufen', 'einkaufswagen', 'supermarkt', 'lebensmittel', 'shopping', 'groceries']),
    SymbolIcon('shoppingBasket', 'Einkaufskorb', 'Shopping basket', 'Cesta de compras', 'Cesta de la compra', AppIcons.basket, ['korb', 'basket']),
    SymbolIcon('shoppingBag', 'Einkaufstasche', 'Shopping bag', 'Sacola de compras', 'Bolsa de la compra', AppIcons.shoppingBag, ['tasche', 'tuete', 'bag']),
    SymbolIcon('store', 'Laden', 'Shop', 'Loja', 'Tienda', AppIcons.storefront, ['geschaeft', 'shop', 'markt', 'store', 'kiosk']),
    SymbolIcon('package', 'Paket', 'Parcel', 'Encomenda', 'Paquete', AppIcons.package, ['pakete', 'lieferung', 'bestellung', 'versand', 'delivery']),
    SymbolIcon('tag', 'Angebot', 'Offer', 'Promoção', 'Oferta', AppIcons.tag, ['preis', 'preisschild', 'rabatt', 'sale']),
    SymbolIcon('creditCard', 'Karte', 'Card', 'Cartão', 'Tarjeta', AppIcons.creditCard, ['bezahlen', 'kreditkarte', 'zahlung', 'card']),
    SymbolIcon('wallet', 'Geldbeutel', 'Wallet', 'Carteira', 'Cartera', AppIcons.wallet, ['portemonnaie', 'geldboerse', 'wallet']),
    SymbolIcon('receipt', 'Kassenbon', 'Receipt', 'Recibo', 'Ticket', AppIcons.receipt, ['quittung', 'beleg', 'rechnung', 'receipt']),
    SymbolIcon('banknote', 'Geld', 'Money', 'Dinheiro', 'Dinero', AppIcons.money, ['budget', 'bargeld', 'kasse', 'money', 'cash']),
    SymbolIcon('barcode', 'Barcode', 'Barcode', 'Código de barras', 'Código de barras', AppIcons.barcode, ['strichcode', 'scannen']),
  ]),
  SymbolGroup('Haushalt', 'Household', 'Casa', 'Hogar', [
    SymbolIcon('house', 'Haus', 'House', 'Casa', 'Casa', AppIcons.house, ['zuhause', 'wohnung', 'haushalt', 'home', 'heim']),
    SymbolIcon('sofa', 'Wohnzimmer', 'Living room', 'Sala', 'Salón', AppIcons.couch, ['sofa', 'couch', 'moebel', 'einrichtung', 'furniture']),
    SymbolIcon('bedDouble', 'Schlafzimmer', 'Bedroom', 'Quarto', 'Dormitorio', AppIcons.bed, ['bett', 'betten', 'bed']),
    SymbolIcon('bath', 'Bad', 'Bathroom', 'Banheiro', 'Baño', AppIcons.bathtub, ['badezimmer', 'baden', 'dusche', 'bathroom']),
    SymbolIcon('lamp', 'Lampe', 'Lamp', 'Luminária', 'Lámpara', AppIcons.lamp, ['licht', 'leuchte', 'beleuchtung', 'light']),
    SymbolIcon('doorOpen', 'Tür', 'Door', 'Porta', 'Puerta', AppIcons.doorOpen, ['tueren', 'eingang', 'door']),
    SymbolIcon('keyRound', 'Schlüssel', 'Key', 'Chave', 'Llave', AppIcons.key, ['schluessel', 'key']),
    SymbolIcon('washingMachine', 'Wäsche', 'Laundry', 'Lavanderia', 'Colada', AppIcons.washingMachine, ['waschen', 'waschmaschine', 'waschkueche', 'laundry']),
    SymbolIcon('sprayCan', 'Drogerie', 'Toiletries', 'Higiene', 'Droguería', AppIcons.sprayBottle, ['putzen', 'putzmittel', 'reinigung', 'haushaltswaren', 'cleaning']),
    SymbolIcon('trash2', 'Müll', 'Rubbish', 'Lixo', 'Basura', AppIcons.trash, ['abfall', 'entsorgen', 'trash']),
    SymbolIcon('plug', 'Strom', 'Electricity', 'Eletricidade', 'Electricidad', AppIcons.plug, ['steckdose', 'stecker', 'energie']),
    SymbolIcon('droplets', 'Wasser', 'Water', 'Água', 'Agua', AppIcons.drop, ['water']),
  ]),
  SymbolGroup('Werkzeug & Bau', 'Tools & DIY', 'Ferramentas e obras', 'Herramientas y obras', [
    SymbolIcon('hammer', 'Werkzeug', 'Tools', 'Ferramentas', 'Herramientas', AppIcons.hammer, ['hammer', 'reparatur', 'reparieren', 'basteln', 'tools']),
    SymbolIcon('wrench', 'Schrauben', 'Spanner', 'Chave inglesa', 'Llave inglesa', AppIcons.wrench, ['schraubenschluessel', 'montage', 'wrench']),
    SymbolIcon('drill', 'Bohrmaschine', 'Drill', 'Furadeira', 'Taladro', AppIcons.screwdriver, ['bohren', 'bohrer', 'akkuschrauber', 'drill']),
    SymbolIcon('hardHat', 'Baumarkt', 'DIY store', 'Bricolagem', 'Bricolaje', AppIcons.hardHat, ['baustelle', 'bau', 'handwerk', 'renovierung', 'renovieren', 'umbau']),
    SymbolIcon('paintRoller', 'Streichen', 'Decorating', 'Pintar', 'Pintar', AppIcons.paintRoller, ['farbe', 'malern', 'anstrich', 'tapete', 'paint']),
    SymbolIcon('ruler', 'Messen', 'Measuring', 'Medir', 'Medir', AppIcons.ruler, ['massband', 'zollstock', 'lineal', 'ruler']),
  ]),
  SymbolGroup('Garten', 'Garden', 'Jardim', 'Jardín', [
    SymbolIcon('sprout', 'Garten', 'Garden', 'Jardim', 'Jardín', AppIcons.plant, ['gaertnern', 'gartenarbeit', 'pflanzen', 'saat', 'beet', 'garden']),
    SymbolIcon('flower2', 'Blumen', 'Flowers', 'Flores', 'Flores', AppIcons.flower, ['blume', 'strauss', 'flower']),
    SymbolIcon('treeDeciduous', 'Baum', 'Tree', 'Árvore', 'Árbol', AppIcons.tree, ['baeume', 'hecke', 'tree']),
    SymbolIcon('leaf', 'Pflanze', 'Plant', 'Planta', 'Planta', AppIcons.leaf, ['blatt', 'gruen', 'plant']),
    SymbolIcon('shovel', 'Schaufel', 'Spade', 'Pá', 'Pala', AppIcons.shovel, ['graben', 'spaten', 'shovel']),
  ]),
  SymbolGroup('Feiern & Feste', 'Celebrations', 'Festas', 'Celebraciones', [
    SymbolIcon('cake', 'Geburtstag', 'Birthday', 'Aniversário', 'Cumpleaños', AppIcons.cake, ['kuchen', 'torte', 'birthday', 'feier']),
    SymbolIcon('partyPopper', 'Party', 'Party', 'Festa', 'Fiesta', AppIcons.confetti, ['fest', 'feiern', 'silvester', 'jubilaeum', 'party']),
    SymbolIcon('gift', 'Geschenk', 'Gift', 'Presente', 'Regalo', AppIcons.gift, ['geschenke', 'praesent', 'gift', 'wunschliste']),
    SymbolIcon('treePine', 'Weihnachten', 'Christmas', 'Natal', 'Navidad', AppIcons.treeEvergreen, ['weihnacht', 'advent', 'tannenbaum', 'christmas', 'xmas', 'nikolaus']),
    SymbolIcon('egg', 'Ostern', 'Easter', 'Páscoa', 'Pascua', AppIcons.egg, ['osterfest', 'easter']),
    SymbolIcon('sparkles', 'Deko', 'Decorations', 'Decoração', 'Decoración', AppIcons.sparkle, ['dekoration', 'schmuck', 'glitzer']),
    SymbolIcon('music', 'Musik', 'Music', 'Música', 'Música', AppIcons.musicNotes, ['lieder', 'konzert', 'music']),
  ]),
  SymbolGroup('Essen & Trinken', 'Food & drink', 'Comida e bebida', 'Comida y bebida', [
    SymbolIcon('utensils', 'Essen', 'Meals', 'Refeições', 'Comidas', AppIcons.forkKnife, ['restaurant', 'mittag', 'abendessen', 'speiseplan', 'menue', 'food']),
    SymbolIcon('cookingPot', 'Kochen', 'Cooking', 'Cozinhar', 'Cocinar', AppIcons.cookingPot, ['topf', 'rezept', 'rezepte', 'kueche', 'cooking']),
    SymbolIcon('coffee', 'Kaffee', 'Coffee', 'Café', 'Café', AppIcons.coffee, ['cafe', 'tee', 'coffee']),
    SymbolIcon('wine', 'Wein', 'Wine', 'Vinho', 'Vino', AppIcons.wine, ['wine']),
    SymbolIcon('beer', 'Bier', 'Beer', 'Cerveja', 'Cerveza', AppIcons.beerStein, ['beer']),
    SymbolIcon('pizza', 'Pizza', 'Pizza', 'Pizza', 'Pizza', AppIcons.pizza, ['italienisch']),
    SymbolIcon('iceCreamCone', 'Eis', 'Ice cream', 'Sorvete', 'Helado', AppIcons.iceCream, ['eiscreme', 'icecream']),
    SymbolIcon('flame', 'Grillen', 'Barbecue', 'Churrasco', 'Barbacoa', AppIcons.flame, ['grill', 'feuer', 'kamin', 'bbq']),
  ]),
  SymbolGroup('Familie', 'Family', 'Família', 'Familia', [
    SymbolIcon('users', 'Familie', 'Family', 'Família', 'Familia', AppIcons.users, ['alle', 'gruppe', 'family', 'eltern']),
    SymbolIcon('user', 'Person', 'Person', 'Pessoa', 'Persona', AppIcons.user, ['ich', 'profil', 'person']),
    SymbolIcon('baby', 'Baby', 'Baby', 'Bebê', 'Bebé', AppIcons.baby, ['kind', 'kinder', 'saeugling', 'wickeln']),
    SymbolIcon('graduationCap', 'Schule', 'School', 'Escola', 'Colegio', AppIcons.graduationCap, ['schulsachen', 'lernen', 'uni', 'kita', 'hausaufgaben', 'school']),
    SymbolIcon('pawPrint', 'Haustier', 'Pet', 'Animal', 'Mascota', AppIcons.pawPrint, ['tier', 'hund', 'katze', 'tierbedarf', 'pet']),
    SymbolIcon('heart', 'Liebe', 'Love', 'Amor', 'Amor', AppIcons.heart, ['lieblings', 'favoriten', 'heart']),
    SymbolIcon('briefcase', 'Arbeit', 'Work', 'Trabalho', 'Trabajo', AppIcons.briefcase, ['buero', 'job', 'beruf', 'work']),
  ]),
  SymbolGroup('Gesundheit & Sport', 'Health & sport', 'Saúde e esporte', 'Salud y deporte', [
    SymbolIcon('pill', 'Apotheke', 'Pharmacy', 'Farmácia', 'Farmacia', AppIcons.pill, ['medikamente', 'medikament', 'tabletten', 'medizin', 'pille']),
    SymbolIcon('stethoscope', 'Arzt', 'Doctor', 'Médico', 'Médico', AppIcons.stethoscope, ['doktor', 'praxis', 'termin', 'doctor']),
    SymbolIcon('heartPulse', 'Gesundheit', 'Health', 'Saúde', 'Salud', AppIcons.heartbeat, ['vorsorge', 'health']),
    SymbolIcon('syringe', 'Impfung', 'Vaccination', 'Vacina', 'Vacuna', AppIcons.syringe, ['spritze', 'impfen']),
    SymbolIcon('bandage', 'Erste Hilfe', 'First aid', 'Primeiros socorros', 'Primeros auxilios', AppIcons.bandaids, ['pflaster', 'verband', 'verbandskasten']),
    SymbolIcon('dumbbell', 'Sport', 'Sport', 'Esporte', 'Deporte', AppIcons.barbell, ['fitness', 'training', 'sportsachen', 'gym']),
  ]),
  SymbolGroup('Reise & Auto', 'Travel & car', 'Viagens e carro', 'Viajes y coche', [
    SymbolIcon('car', 'Auto', 'Car', 'Carro', 'Coche', AppIcons.car, ['wagen', 'werkstatt', 'pkw', 'car']),
    SymbolIcon('plane', 'Reise', 'Travel', 'Viagem', 'Viaje', AppIcons.airplane, ['urlaub', 'flug', 'flugzeug', 'ferien', 'travel']),
    SymbolIcon('luggage', 'Koffer', 'Suitcase', 'Mala', 'Maleta', AppIcons.suitcaseRolling, ['gepaeck', 'packliste', 'packen', 'reisetasche']),
    SymbolIcon('trainFront', 'Zug', 'Train', 'Trem', 'Tren', AppIcons.train, ['bahn', 'train']),
    SymbolIcon('bus', 'Bus', 'Bus', 'Ônibus', 'Autobús', AppIcons.bus, ['bus']),
    SymbolIcon('bike', 'Fahrrad', 'Bicycle', 'Bicicleta', 'Bicicleta', AppIcons.bicycle, ['rad', 'bike']),
    SymbolIcon('fuel', 'Tanken', 'Fuel', 'Combustível', 'Combustible', AppIcons.gasPump, ['tankstelle', 'benzin', 'diesel', 'sprit']),
    SymbolIcon('tent', 'Camping', 'Camping', 'Camping', 'Camping', AppIcons.tent, ['zelt', 'campen', 'camping']),
    SymbolIcon('ship', 'Schiff', 'Ship', 'Barco', 'Barco', AppIcons.boat, ['faehre', 'boot', 'ship']),
    SymbolIcon('mapPin', 'Ort', 'Place', 'Local', 'Lugar', AppIcons.mapPin, ['adresse', 'karte', 'route', 'map']),
  ]),
  SymbolGroup('Kleidung', 'Clothing', 'Lavanderia', 'Ropa', [
    SymbolIcon('shirt', 'Kleidung', 'Clothing', 'Lavanderia', 'Ropa', AppIcons.tShirt, ['klamotten', 'hemd', 'shirt', 'anziehsachen', 'clothes']),
    SymbolIcon('footprints', 'Schuhe', 'Shoes', 'Sapatos', 'Zapatos', AppIcons.footprints, ['schuh', 'stiefel', 'shoes']),
    SymbolIcon('glasses', 'Brille', 'Glasses', 'Óculos', 'Gafas', AppIcons.eyeglasses, ['sehhilfe', 'glasses']),
    SymbolIcon('watch', 'Uhr', 'Watch', 'Relógio', 'Reloj', AppIcons.watch, ['armbanduhr', 'watch']),
    SymbolIcon('umbrella', 'Regenschirm', 'Umbrella', 'Guarda-chuva', 'Paraguas', AppIcons.umbrella, ['schirm', 'regen', 'umbrella']),
  ]),
  SymbolGroup('Technik', 'Tech', 'Tecnologia', 'Tecnología', [
    SymbolIcon('smartphone', 'Handy', 'Phone', 'Celular', 'Móvil', AppIcons.deviceMobile, ['telefon', 'mobil', 'phone']),
    SymbolIcon('laptop', 'Laptop', 'Laptop', 'Notebook', 'Portátil', AppIcons.laptop, ['notebook', 'computer', 'rechner']),
    SymbolIcon('monitor', 'Bildschirm', 'Monitor', 'Tela', 'Pantalla', AppIcons.monitor, ['pc', 'monitor']),
    SymbolIcon('tv', 'Fernseher', 'TV', 'Televisão', 'Televisión', AppIcons.television, ['tv', 'fernsehen']),
    SymbolIcon('headphones', 'Kopfhörer', 'Headphones', 'Fones de ouvido', 'Auriculares', AppIcons.headphones, ['kopfhoerer', 'headset']),
    SymbolIcon('camera', 'Kamera', 'Camera', 'Câmera', 'Cámara', AppIcons.camera, ['foto', 'fotos', 'bilder', 'camera']),
    SymbolIcon('cable', 'Kabel', 'Cable', 'Cabo', 'Cable', AppIcons.plugsConnected, ['ladekabel', 'stecker', 'cable']),
    SymbolIcon('batteryCharging', 'Batterien', 'Batteries', 'Pilhas', 'Pilas', AppIcons.batteryCharging, ['akku', 'batterie', 'laden', 'battery']),
    SymbolIcon('gamepad2', 'Spiele', 'Games', 'Jogos', 'Juegos', AppIcons.gameController, ['gaming', 'konsole', 'spielzeug', 'games']),
    SymbolIcon('printer', 'Drucker', 'Printer', 'Impressora', 'Impresora', AppIcons.printer, ['drucken', 'printer']),
  ]),
  SymbolGroup('Büro & Dokumente', 'Office & documents', 'Escritório e documentos', 'Oficina y documentos', [
    SymbolIcon('fileText', 'Dokumente', 'Documents', 'Documentos', 'Documentos', AppIcons.fileText, ['dokument', 'unterlagen', 'papiere', 'vertrag', 'zeugnis', 'documents']),
    SymbolIcon('folder', 'Ordner', 'Folder', 'Pasta', 'Carpeta', AppIcons.folder, ['akten', 'mappe', 'folder']),
    SymbolIcon('book', 'Bücher', 'Books', 'Livros', 'Libros', AppIcons.book, ['buch', 'lesen', 'book']),
    SymbolIcon('calendar', 'Termine', 'Events', 'Compromissos', 'Citas', AppIcons.calendar, ['kalender', 'termin', 'calendar']),
    SymbolIcon('mail', 'Post', 'Post', 'Correio', 'Correo', AppIcons.envelope, ['briefe', 'brief', 'mail']),
    SymbolIcon('scissors', 'Schere', 'Scissors', 'Tesoura', 'Tijeras', AppIcons.scissors, ['schneiden', 'scissors']),
    SymbolIcon('palette', 'Malen', 'Art', 'Pintura', 'Arte', AppIcons.palette, ['kunst', 'hobby', 'farben', 'art']),
    SymbolIcon('bell', 'Erinnerung', 'Reminder', 'Lembrete', 'Recordatorio', AppIcons.bell, ['erinnern', 'notiz', 'reminder']),
  ]),
  SymbolGroup('Aufbewahrung', 'Storage', 'Armazenamento', 'Almacenaje', [
    SymbolIcon('box', 'Box', 'Box', 'Caixa', 'Caja', AppIcons.package, ['kiste', 'karton', 'behaelter']),
    SymbolIcon('boxes', 'Umzug', 'Moving', 'Mudança', 'Mudanza', AppIcons.stack, ['umziehen', 'kartons', 'kisten', 'moving']),
    SymbolIcon('warehouse', 'Lager', 'Storage', 'Armazenamento', 'Almacén', AppIcons.warehouse, ['keller', 'dachboden', 'garage', 'abstellraum', 'speicher', 'schuppen', 'lagerraum']),
    SymbolIcon('archive', 'Archiv', 'Archive', 'Arquivo', 'Archivo', AppIcons.archive, ['aufbewahrung', 'aufbewahren', 'archiv']),
    SymbolIcon('layers', 'Stapel', 'Stack', 'Pilha', 'Pila', AppIcons.stackSimple, ['sortiert', 'schichten']),
  ]),
  SymbolGroup('Jahreszeiten', 'Seasons', 'Estações do ano', 'Estaciones', [
    SymbolIcon('sun', 'Sommer', 'Summer', 'Verão', 'Verano', AppIcons.sun, ['sonne', 'sonnig', 'summer']),
    SymbolIcon('snowflake', 'Winter', 'Winter', 'Inverno', 'Invierno', AppIcons.snowflake, ['schnee', 'kalt', 'winter']),
    SymbolIcon('leafyGreen', 'Frühling', 'Spring', 'Primavera', 'Primavera', AppIcons.flowerTulip, ['fruehling', 'spring']),
    SymbolIcon('wind', 'Herbst', 'Autumn', 'Outono', 'Otoño', AppIcons.wind, ['wind', 'sturm', 'autumn']),
    SymbolIcon('star', 'Favorit', 'Favourite', 'Favorito', 'Favorito', AppIcons.star, ['stern', 'wichtig', 'star']),
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
    for (final icon in group.icons) _Entry(icon.choice, _folded([icon.de, icon.en, icon.pt, icon.es, icon.name, ...icon.alias]), compound: true),
];

final Map<String, IconChoice> _symbolsByKey = {for (final entry in _symbolIndex) entry.choice.key: entry.choice};

/// Shops in one flat, alphabetical list — what the picker browses.
List<IconChoice> get merchantChoices => [for (final entry in _merchantIndex) entry.choice];

/// The logo for a shop **named by a payment**, or null where the folder has
/// none — what an Ausgaben row draws before falling back to the shop's initials.
///
/// The shop folder and nothing else, which is the difference between this and
/// [suggestIcon]: a payment at "Apotheke am Markt" wants the Shop-Apotheke logo
/// or no logo, never the generic pill-bottle symbol. A row that cannot be
/// matched to a brand is not a row about a category.
String? merchantLogoAsset(String merchant) =>
    merchant.trim().isEmpty ? null : _match(_merchantIndex, merchant)?.key;

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
    return _groceryChoice(text, strict: false) ?? _match(_symbolIndex, text);
  }

  // The *whole* line only, not its words: "Rewe Einkauf" is the shop, and
  // splitting here would hand it to the cart before the logos get a look.
  final exact = _best(_symbolIndex, foldItemText(text), 0);
  if (exact != null) return exact;
  if (subject.allowsMerchants) {
    final merchant = _match(_merchantIndex, text);
    if (merchant != null) return merchant;
  }
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
  if (key.startsWith(symbolIconPrefix)) return _symbolsByKey[key];
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
const defaultListIcon = IconChoice(kind: IconKind.symbol, key: '${symbolIconPrefix}clipboardCheck', label: 'Liste', glyph: AppIcons.listChecks);
const defaultGroceryListIcon = IconChoice(kind: IconKind.symbol, key: '${symbolIconPrefix}shoppingCart', label: 'Einkauf', glyph: AppIcons.shoppingCart);
const defaultBoxIcon = IconChoice(kind: IconKind.symbol, key: '${symbolIconPrefix}box', label: 'Box', glyph: AppIcons.package);
const defaultItemIcon = IconChoice(kind: IconKind.symbol, key: '${symbolIconPrefix}clipboardList', label: 'Artikel', glyph: AppIcons.clipboardText);
