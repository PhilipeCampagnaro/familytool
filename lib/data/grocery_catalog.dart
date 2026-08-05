/// The `assets/grocery/` icon set, named in both interface languages.
///
/// The files are named in English (`Dairy_Milk.png`) and people type either
/// language, so an entry pairs the file with the German label and the English
/// one is **still not listed by hand**: [englishGroceryLabel] reads it off the
/// file name, exactly as `grocery_search.dart` reads the English search terms
/// off it. A PNG dropped into the folder needs its German name here and nothing
/// else — unless its file name lies about its contents, which is what
/// [_englishLabelOverrides] is for.
///
/// [GroceryIcon.alias] is for what neither side says — plurals, synonyms, and
/// the odd file that spells its own contents wrong (`Disposable_Glovespng`).
///
/// Ordering does a little work: on an equally good match the shorter name wins
/// (see `grocery_search.dart`), so plain "Milch" beats "Schokomilch" for the
/// query *Milch* without either having to be marked special.
library;

import '../l10n/l10n.dart';

class GroceryIcon {
  /// File name inside `assets/grocery/`.
  final String file;

  /// German label.
  final String de;

  /// Extra names this icon answers to.
  final List<String> alias;

  const GroceryIcon(this.file, this.de, [this.alias = const []]);

  String get asset => '$groceryAssetDir$file';

  /// English label, derived from the file name — see [englishGroceryLabel].
  String get en => englishGroceryLabel(file);

  /// What a suggestion chip and a new item actually show.
  String get label => L.s.localeCode == 'en' ? en : de;
}

const groceryAssetDir = 'assets/grocery/';

/// The picture an article falls back to when the catalogs don't recognise what
/// was typed — **only on a Lebensmittel list**, where every other row carries a
/// photograph and a grey disc with a clipboard glyph in it is the one row that
/// doesn't look like shopping. A Sonstige list keeps the glyph: it has no
/// photos for the odd one out to be odd against.
///
/// Rendered rather than stored, so it holds however the article lost its icon —
/// renaming *Milch* to something no catalog knows clears the key, and the row
/// still has to look like a row.
const generalGroceryAsset = '${groceryAssetDir}General_Shopping_cart.png';

class GroceryCategory {
  /// German section name — also searchable, so "Gemüse" offers vegetables.
  final String de;

  /// English section name. Hand-written, unlike the icon labels: a section has
  /// no file name to read one off.
  final String en;

  final List<GroceryIcon> icons;

  const GroceryCategory(this.de, this.en, this.icons);

  String get label => L.s.localeCode == 'en' ? en : de;
}

/// Grouped the way the files are named, so a category stays easy to eyeball
/// against the folder.
const groceryCategories = <GroceryCategory>[
  GroceryCategory('Obst', 'Fruit', [
    GroceryIcon('Fruits_Apple.png', 'Apfel', ['Äpfel']),
    GroceryIcon('Fruits_Avocado.png', 'Avocado', ['Avocados']),
    GroceryIcon('Fruits_Banana.png', 'Banane', ['Bananen']),
    GroceryIcon('Fruits_Blueberries.png', 'Heidelbeeren', ['Blaubeeren', 'Heidelbeere']),
    GroceryIcon('Fruits_Cantaloupe.png', 'Melone', ['Zuckermelone', 'Honigmelone']),
    GroceryIcon('Fruits_Cherry.png', 'Kirschen', ['Kirsche']),
    GroceryIcon('Fruits_Coconut.png', 'Kokosnuss', ['Kokos']),
    GroceryIcon('Fruits_Fig.png', 'Feigen', ['Feige']),
    GroceryIcon('Fruits_Kiwi.png', 'Kiwi', ['Kiwis']),
    GroceryIcon('Fruits_Lemon.png', 'Zitrone', ['Zitronen', 'Limette']),
    GroceryIcon('Fruits_Mixed_Fruits.png', 'Obstmischung', ['Obstsalat', 'Früchtemix', 'Obst', 'fruit']),
    GroceryIcon('Fruits_Orange.png', 'Orange', ['Orangen', 'Apfelsine']),
    GroceryIcon('Fruits_Peach.png', 'Pfirsich', ['Pfirsiche', 'Nektarine']),
    GroceryIcon('Fruits_Pineapple.png', 'Ananas'),
    GroceryIcon('Fruits_Plum.png', 'Pflaume', ['Pflaumen', 'Zwetschgen']),
    GroceryIcon('Fruits_Pomegranate.png', 'Granatapfel'),
    GroceryIcon('Fruits_Raspberries.png', 'Himbeeren', ['Himbeere']),
    GroceryIcon('Fruits_Strawberry.png', 'Erdbeeren', ['Erdbeere']),
    GroceryIcon('Fruits_Watermelon.png', 'Wassermelone'),
    GroceryIcon('Fruits_grapes.png', 'Weintrauben', ['Trauben', 'Weintraube']),
    GroceryIcon('Fruits_mango.png', 'Mango', ['Mangos']),
  ]),
  GroceryCategory('Gemüse', 'Vegetables', [
    GroceryIcon('Vegetables_Acorn_Squash.png', 'Eichelkürbis'),
    GroceryIcon('Vegetables_Artichoke.png', 'Artischocke', ['Artischocken']),
    GroceryIcon('Vegetables_Arugula.png', 'Rucola', ['Rauke']),
    GroceryIcon('Vegetables_Asparagus.png', 'Spargel'),
    GroceryIcon('Vegetables_Beet_Greens.png', 'Rote-Bete-Blätter'),
    GroceryIcon('Vegetables_Beetroot.png', 'Rote Bete', ['Rote Beete', 'Randen']),
    GroceryIcon('Vegetables_Bell_Pepper.png', 'Paprika', ['Paprikaschote']),
    GroceryIcon('Vegetables_Bok_Choy.png', 'Pak Choi'),
    GroceryIcon('Vegetables_Broccoli.png', 'Brokkoli'),
    GroceryIcon('Vegetables_Brussels_Sprout.png', 'Rosenkohl'),
    GroceryIcon('Vegetables_Butternut_Squash.png', 'Butternusskürbis'),
    GroceryIcon('Vegetables_Cabbage.png', 'Weißkohl', ['Kohl', 'Weißkraut']),
    GroceryIcon('Vegetables_Carrot.png', 'Karotten', ['Karotte', 'Möhren', 'Möhre', 'Mohrrüben']),
    GroceryIcon('Vegetables_Cassava.png', 'Maniok'),
    GroceryIcon('Vegetables_Cauliflower.png', 'Blumenkohl'),
    GroceryIcon('Vegetables_Celeriac.png', 'Knollensellerie'),
    GroceryIcon('Vegetables_Celery.png', 'Staudensellerie', ['Sellerie']),
    GroceryIcon('Vegetables_Chayote.png', 'Chayote'),
    GroceryIcon('Vegetables_Cherry_Tomato.png', 'Kirschtomaten', ['Cocktailtomaten']),
    GroceryIcon('Vegetables_Chicory.png', 'Chicorée'),
    GroceryIcon('Vegetables_Collard_Greens.png', 'Blattkohl'),
    GroceryIcon('Vegetables_Corn.png', 'Mais', ['Maiskolben']),
    GroceryIcon('Vegetables_Cucumber.png', 'Gurke', ['Gurken', 'Salatgurke']),
    GroceryIcon('Vegetables_Daikon.png', 'Rettich', ['Daikon']),
    GroceryIcon('Vegetables_Dandelion_Greens.png', 'Löwenzahn'),
    GroceryIcon('Vegetables_Delicata_Squash.png', 'Delicata-Kürbis'),
    GroceryIcon('Vegetables_Edamame.png', 'Edamame'),
    GroceryIcon('Vegetables_Eggplant.png', 'Aubergine', ['Auberginen']),
    GroceryIcon('Vegetables_Endive.png', 'Endivie', ['Endiviensalat']),
    GroceryIcon('Vegetables_Fennel.png', 'Fenchel'),
    GroceryIcon('Vegetables_Fiddlehead_Ferns.png', 'Farnspitzen'),
    GroceryIcon('Vegetables_Frisée.png', 'Friséesalat', ['Frisee']),
    GroceryIcon('Vegetables_Garlic.png', 'Knoblauch'),
    GroceryIcon('Vegetables_Ginger.png', 'Ingwer'),
    GroceryIcon('Vegetables_Green_Bean.png', 'Grüne Bohnen', ['Bohnen', 'Buschbohnen']),
    GroceryIcon('Vegetables_Horseradish.png', 'Meerrettich'),
    GroceryIcon('Vegetables_Jicama.png', 'Jicama'),
    GroceryIcon('Vegetables_Kabocha_Squash.png', 'Kabocha-Kürbis'),
    GroceryIcon('Vegetables_Kale.png', 'Grünkohl'),
    GroceryIcon('Vegetables_Kohlrabi.png', 'Kohlrabi'),
    GroceryIcon('Vegetables_Leek.png', 'Lauch', ['Porree']),
    GroceryIcon('Vegetables_Lettuce.png', 'Kopfsalat', ['Salat']),
    GroceryIcon('Vegetables_Mushroom.png', 'Champignons', ['Pilze', 'Pilz', 'Champignon']),
    GroceryIcon('Vegetables_Mustard_Greens.png', 'Senfblätter'),
    GroceryIcon('Vegetables_Napa_Cabbage.png', 'Chinakohl'),
    GroceryIcon('Vegetables_Nori.png', 'Nori-Blätter', ['Algen']),
    GroceryIcon('Vegetables_Okra.png', 'Okra'),
    GroceryIcon('Vegetables_Olive.png', 'Oliven', ['Olive']),
    GroceryIcon('Vegetables_Onion.png', 'Zwiebeln', ['Zwiebel']),
    GroceryIcon('Vegetables_Parsnip.png', 'Pastinake', ['Pastinaken']),
    GroceryIcon('Vegetables_Peas.png', 'Erbsen'),
    GroceryIcon('Vegetables_Potato.png', 'Kartoffeln', ['Kartoffel']),
    GroceryIcon('Vegetables_Pumpkin.png', 'Kürbis'),
    GroceryIcon('Vegetables_Radicchio.png', 'Radicchio'),
    GroceryIcon('Vegetables_Radish.png', 'Radieschen'),
    GroceryIcon('Vegetables_Romaine_Lettuce.png', 'Römersalat', ['Romana-Salat']),
    GroceryIcon('Vegetables_Romanesco.png', 'Romanesco'),
    GroceryIcon('Vegetables_Rutabaga.png', 'Steckrübe'),
    GroceryIcon('Vegetables_Salsify.png', 'Schwarzwurzel', ['Schwarzwurzeln']),
    GroceryIcon('Vegetables_Shallot.png', 'Schalotten', ['Schalotte']),
    GroceryIcon('Vegetables_Spaghetti_Squash.png', 'Spaghettikürbis'),
    GroceryIcon('Vegetables_Spinach.png', 'Spinat'),
    GroceryIcon('Vegetables_Sunchoke.png', 'Topinambur'),
    GroceryIcon('Vegetables_Sweet_Potato.png', 'Süßkartoffel', ['Süßkartoffeln']),
    GroceryIcon('Vegetables_Swiss_Chard.png', 'Mangold'),
    GroceryIcon('Vegetables_Taro.png', 'Taro'),
    GroceryIcon('Vegetables_Tomato.png', 'Tomaten', ['Tomate']),
    GroceryIcon('Vegetables_Turnip.png', 'Mairübe', ['Weiße Rübe', 'Rübe']),
    GroceryIcon('Vegetables_Turnip_Greens.png', 'Rübstiel', ['Rübenblätter']),
    GroceryIcon('Vegetables_Water_Spinach.png', 'Wasserspinat'),
    GroceryIcon('Vegetables_Watercress.png', 'Brunnenkresse', ['Kresse']),
    GroceryIcon('Vegetables_Yam.png', 'Yamswurzel', ['Yams']),
    GroceryIcon('Vegetables_Yardlong_Bean.png', 'Spargelbohne'),
    GroceryIcon('Vegetables_Zucchini.png', 'Zucchini'),
  ]),
  GroceryCategory('Frische Kräuter', 'Fresh herbs', [
    GroceryIcon('Fresh_Herbs_Fresh_Basil.png', 'Basilikum'),
    GroceryIcon('Fresh_Herbs_Fresh_Chives.png', 'Schnittlauch'),
    GroceryIcon('Fresh_Herbs_Fresh_Cilantro.png', 'Koriander', ['Koriandergrün']),
    GroceryIcon('Fresh_Herbs_Fresh_Dill.png', 'Dill'),
    GroceryIcon('Fresh_Herbs_Fresh_Mint.png', 'Minze', ['Pfefferminze']),
    GroceryIcon('Fresh_Herbs_Fresh_Oregano.png', 'Oregano'),
    GroceryIcon('Fresh_Herbs_Fresh_Parsley.png', 'Petersilie'),
    GroceryIcon('Fresh_Herbs_Fresh_Rosemary.png', 'Rosmarin'),
    GroceryIcon('Fresh_Herbs_Fresh_Sage.png', 'Salbei'),
    GroceryIcon('Fresh_Herbs_Fresh_Thyme.png', 'Thymian'),
  ]),
  GroceryCategory('Fleisch & Fisch', 'Meat & fish', [
    GroceryIcon('Meat_Bacon.png', 'Speck', ['Bacon', 'Frühstücksspeck']),
    GroceryIcon('Meat_Bison.png', 'Bisonfleisch'),
    GroceryIcon('Meat_Bratwurst.png', 'Bratwurst', ['Rostbratwurst']),
    GroceryIcon('Meat_Calf_Liver.png', 'Kalbsleber', ['Leber']),
    GroceryIcon('Meat_Chicken_Breast.png', 'Hähnchenbrust', ['Hähnchen', 'Hühnerbrust', 'Hühnchen', 'chicken']),
    GroceryIcon('Meat_Chicken_Thigh.png', 'Hähnchenschenkel', ['Hähnchenkeule']),
    GroceryIcon('Meat_Chicken_Wing.png', 'Hähnchenflügel'),
    GroceryIcon('Meat_Chorizo.png', 'Chorizo'),
    GroceryIcon('Meat_Cod_Fillet.png', 'Kabeljaufilet', ['Kabeljau', 'Dorsch']),
    GroceryIcon('Meat_Crab.png', 'Taschenkrebs', ['Krebs']),
    GroceryIcon('Meat_Deli_Ham.png', 'Kochschinken', ['Aufschnitt']),
    GroceryIcon('Meat_Duck_Breast.png', 'Entenbrust', ['Ente']),
    GroceryIcon('Meat_Flank_Steak.png', 'Flanksteak'),
    GroceryIcon('Meat_Goat.png', 'Ziegenfleisch'),
    GroceryIcon('Meat_Ground_Beef.png', 'Rinderhack', ['Hackfleisch', 'Gehacktes', 'Mett']),
    GroceryIcon('Meat_Ground_Pork.png', 'Schweinehack'),
    GroceryIcon('Meat_Ground_Turkey.png', 'Putenhack'),
    GroceryIcon('Meat_Haddock.png', 'Schellfisch'),
    GroceryIcon('Meat_Halibut.png', 'Heilbutt'),
    GroceryIcon('Meat_Ham.png', 'Schinken'),
    GroceryIcon('Meat_Lamb_Chop.png', 'Lammkotelett'),
    GroceryIcon('Meat_Lamb_Chops.png', 'Lammkoteletts', ['Lamm']),
    GroceryIcon('Meat_Lobster.png', 'Hummer'),
    GroceryIcon('Meat_Mahi-mahi_Fillet.png', 'Mahi-Mahi-Filet'),
    GroceryIcon('Meat_Mixed.png', 'Gemischtes Fleisch', ['Fleisch', 'Grillfleisch', 'meat']),
    GroceryIcon('Meat_Mussels.png', 'Miesmuscheln', ['Muscheln']),
    GroceryIcon('Meat_New_York_Strip_Steak.png', 'New-York-Strip-Steak', ['Striploin']),
    GroceryIcon('Meat_Octopus.png', 'Oktopus', ['Krake', 'Pulpo']),
    GroceryIcon('Meat_Oysters.png', 'Austern'),
    GroceryIcon('Meat_Pancetta.png', 'Pancetta'),
    GroceryIcon('Meat_Pork_Chop.png', 'Schweinekotelett'),
    GroceryIcon('Meat_Pork_Ribs.png', 'Schweinerippchen', ['Rippchen']),
    GroceryIcon('Meat_Pork_Shoulder.png', 'Schweineschulter'),
    GroceryIcon('Meat_Pork_Spare_Ribs.png', 'Spareribs', ['Schälrippchen']),
    GroceryIcon('Meat_Pork_Tenderloin.png', 'Schweinefilet'),
    GroceryIcon('Meat_Rabbit.png', 'Kaninchen', ['Hase']),
    GroceryIcon('Meat_Ribeye_Steak.png', 'Ribeye-Steak', ['Entrecôte']),
    GroceryIcon('Meat_Salami.png', 'Salami'),
    GroceryIcon('Meat_Salmon_Fillet.png', 'Lachsfilet', ['Lachs', 'Fisch', 'fish']),
    GroceryIcon('Meat_Sausage.png', 'Würstchen', ['Wurst', 'Würste']),
    GroceryIcon('Meat_Scallops.png', 'Jakobsmuscheln'),
    GroceryIcon('Meat_Shrimp.png', 'Garnelen', ['Shrimps', 'Krabben']),
    GroceryIcon('Meat_Sirloin_Steak.png', 'Rumpsteak', ['Sirloin']),
    GroceryIcon('Meat_Squid.png', 'Tintenfisch', ['Calamari']),
    GroceryIcon('Meat_Swordfish_Steak.png', 'Schwertfischsteak', ['Schwertfisch']),
    GroceryIcon('Meat_T-bone_Steak.png', 'T-Bone-Steak', ['Steak']),
    GroceryIcon('Meat_Tilapia.png', 'Tilapia', ['Buntbarsch']),
    GroceryIcon('Meat_Tuna_Steak.png', 'Thunfischsteak', ['Thunfisch']),
    GroceryIcon('Meat_Turkey_Drumstick.png', 'Putenkeule', ['Pute', 'Truthahn']),
    GroceryIcon('Meat_Veal.png', 'Kalbfleisch', ['Kalb']),
    GroceryIcon('Meat_Venison.png', 'Wildfleisch', ['Wild', 'Hirsch', 'Reh']),
  ]),
  GroceryCategory('Milchprodukte', 'Dairy', [
    GroceryIcon('Dairy_Blue_Cheese.png', 'Blauschimmelkäse', ['Gorgonzola']),
    GroceryIcon('Dairy_Brie.png', 'Brie'),
    GroceryIcon('Dairy_Butter.png', 'Butter'),
    GroceryIcon('Dairy_Buttermilk.png', 'Buttermilch'),
    GroceryIcon('Dairy_Cheddar_Cheese.png', 'Cheddar'),
    GroceryIcon('Dairy_Cheese.png', 'Käse'),
    GroceryIcon('Dairy_Chocolate_Milk.png', 'Schokomilch', ['Kakao']),
    GroceryIcon('Dairy_Condensed_Milk.png', 'Kondensmilch'),
    GroceryIcon('Dairy_Cottage_Cheese.png', 'Hüttenkäse', ['Körniger Frischkäse']),
    GroceryIcon('Dairy_Cream.png', 'Sahne'),
    GroceryIcon('Dairy_Cream_Cheese.png', 'Frischkäse'),
    GroceryIcon('Dairy_Evaporated_Milk.png', 'Dosenmilch', ['Kaffeemilch']),
    GroceryIcon('Dairy_Feta.png', 'Feta'),
    GroceryIcon('Dairy_Feta_Cheese.png', 'Feta-Käse', ['Schafskäse']),
    GroceryIcon('Dairy_Fresh_Mozzarella.png', 'Frischer Mozzarella', ['Büffelmozzarella']),
    GroceryIcon('Dairy_Goat_Cheese.png', 'Ziegenkäse'),
    GroceryIcon('Dairy_Gouda.png', 'Gouda'),
    GroceryIcon('Dairy_Greek_Yogurt.png', 'Griechischer Joghurt'),
    GroceryIcon('Dairy_Gruyere.png', 'Gruyère', ['Greyerzer']),
    GroceryIcon('Dairy_Half_and_Half.png', 'Kaffeesahne'),
    GroceryIcon('Dairy_Heavy_Cream.png', 'Schlagsahne'),
    GroceryIcon('Dairy_Kefir.png', 'Kefir'),
    GroceryIcon('Dairy_Lactose-Free_Milk.png', 'Laktosefreie Milch'),
    GroceryIcon('Dairy_Mascarpone.png', 'Mascarpone'),
    GroceryIcon('Dairy_Milk.png', 'Milch', ['Vollmilch', 'H-Milch', 'Frischmilch']),
    GroceryIcon('Dairy_Mozzarella.png', 'Mozzarella'),
    GroceryIcon('Dairy_Parmesan_Cheese.png', 'Parmesan'),
    GroceryIcon('Dairy_Plain_Yogurt.png', 'Naturjoghurt'),
    GroceryIcon('Dairy_Provolone.png', 'Provolone'),
    GroceryIcon('Dairy_Ricotta.png', 'Ricotta'),
    GroceryIcon('Dairy_Ricotta_Cheese.png', 'Ricotta-Käse'),
    GroceryIcon('Dairy_Sharp_Cheddar.png', 'Würziger Cheddar'),
    GroceryIcon('Dairy_Shepherds_Cheese.png', 'Hirtenkäse'),
    GroceryIcon('Dairy_Sour_Cream.png', 'Saure Sahne', ['Schmand']),
    GroceryIcon('Dairy_String_Cheese.png', 'Käsesticks'),
    GroceryIcon('Dairy_Swiss_Cheese.png', 'Emmentaler', ['Schweizer Käse']),
    GroceryIcon('Dairy_Unsalted_Butter.png', 'Süßrahmbutter', ['Ungesalzene Butter']),
    GroceryIcon('Dairy_Whipping_Cream.png', 'Sahne zum Schlagen'),
    GroceryIcon('Dairy_Yogurt.png', 'Joghurt'),
  ]),
  GroceryCategory('Brot & Backwaren', 'Bread & bakery', [
    GroceryIcon('Bread_Bagel.png', 'Bagel', ['Bagels']),
    GroceryIcon('Bread_Baguette.png', 'Baguette'),
    GroceryIcon('Bread_Brioche.png', 'Brioche'),
    GroceryIcon('Bread_Ciabatta.png', 'Ciabatta'),
    GroceryIcon('Bread_Cornbread.png', 'Maisbrot'),
    GroceryIcon('Bread_Croissant.png', 'Croissant', ['Croissants']),
    GroceryIcon('Bread_Dinner_Roll.png', 'Brötchen', ['Semmeln', 'Schrippen']),
    GroceryIcon('Bread_English_Muffin.png', 'Englisches Muffin'),
    GroceryIcon('Bread_Focaccia.png', 'Focaccia'),
    GroceryIcon('Bread_Garlic_Bread.png', 'Knoblauchbrot'),
    GroceryIcon('Bread_Hamburger_Bun.png', 'Hamburgerbrötchen', ['Burgerbrötchen']),
    GroceryIcon('Bread_Hot_Dog_Bun.png', 'Hotdog-Brötchen'),
    GroceryIcon('Bread_Naan_Bread.png', 'Naan-Brot'),
    GroceryIcon('Bread_Pita_Bread.png', 'Pitabrot', ['Fladenbrot']),
    GroceryIcon('Bread_Pretzel.png', 'Brezel', ['Brezeln', 'Laugenbrezel']),
    GroceryIcon('Bread_Rye_Bread.png', 'Roggenbrot'),
    GroceryIcon('Bread_Sourdough_Bread.png', 'Sauerteigbrot'),
    GroceryIcon('Bread_Tortilla.png', 'Tortilla', ['Wraps', 'Tortillas']),
    GroceryIcon('Bread_White_Bread.png', 'Weißbrot', ['Brot', 'Toastbrot', 'bread']),
    GroceryIcon('Bread_Whole_Wheat_Bread.png', 'Vollkornbrot'),
  ]),
  GroceryCategory('Frühstück & Müsli', 'Breakfast & cereal', [
    GroceryIcon('Cereals_Cornflakes.png', 'Cornflakes', ['Maisflocken', 'Müsli', 'Frühstücksflocken']),
    GroceryIcon('Cereals_Fruit_Loops.png', 'Froot Loops', ['Fruchtringe']),
    GroceryIcon("Cereals_Kellogg's_Corn_Flakes.png", "Kellogg's Cornflakes"),
    GroceryIcon("Cereals_Kellogg's_Frosted_Flakes.png", "Kellogg's Frosties", ['Frosted Flakes']),
    GroceryIcon('Cereals_Malt-O-Meal_Frosted_Flakes.png', 'Malt-O-Meal Frosted Flakes'),
    GroceryIcon('Cereals_General_Mills_Corn_Chex.png', 'General Mills Corn Chex'),
    GroceryIcon('Cereals_Post_Toasties.png', 'Post Toasties'),
    GroceryIcon('Cereals_Arrowhead_Mills_Organic_Corn_Flakes.png', 'Arrowhead Mills Bio-Cornflakes'),
    GroceryIcon("Cereals_Barbara's_Bakery_Corn_Flakes.png", "Barbara's Bakery Cornflakes"),
    GroceryIcon('Cereals_Kashi_Organic_Corn_Flakes.png', 'Kashi Bio-Cornflakes'),
    GroceryIcon("Cereals_Nature's_Path_Organic_Corn_Flakes.png", "Nature's Path Bio-Cornflakes"),
    GroceryIcon('Cereals_Three_Wishes_Cereal_Corn_Flakes.png', 'Three Wishes Cornflakes'),
  ]),
  GroceryCategory('Nudeln & Pasta', 'Pasta & noodles', [
    GroceryIcon('Noodles_&_Pasta_Spaghetti.png', 'Spaghetti', ['Nudeln', 'Pasta']),
    GroceryIcon('Noodles_&_Pasta_Angel_hair.png', 'Engelshaar', ['Capellini']),
    GroceryIcon('Noodles_&_Pasta_Couscous.png', 'Couscous'),
    GroceryIcon('Noodles_&_Pasta_Farfalle.png', 'Farfalle'),
    GroceryIcon('Noodles_&_Pasta_Fettuccine.png', 'Fettuccine'),
    GroceryIcon('Noodles_&_Pasta_Fusilli.png', 'Fusilli'),
    GroceryIcon('Noodles_&_Pasta_Gnocchi.png', 'Gnocchi'),
    GroceryIcon('Noodles_&_Pasta_Lasagna.png', 'Lasagneplatten', ['Lasagne']),
    GroceryIcon('Noodles_&_Pasta_Linguine.png', 'Linguine'),
    GroceryIcon('Noodles_&_Pasta_Macaroni.png', 'Makkaroni'),
    GroceryIcon('Noodles_&_Pasta_Orzo.png', 'Kritharaki', ['Orzo']),
    GroceryIcon('Noodles_&_Pasta_Penne.png', 'Penne'),
    GroceryIcon('Noodles_&_Pasta_Ramen.png', 'Ramen'),
    GroceryIcon('Noodles_&_Pasta_Rice_noodles.png', 'Reisnudeln'),
    GroceryIcon('Noodles_&_Pasta_Rigatoni.png', 'Rigatoni'),
    GroceryIcon('Noodles_&_Pasta_Soba.png', 'Soba-Nudeln'),
    GroceryIcon('Noodles_&_Pasta_Somen.png', 'Somen-Nudeln'),
    GroceryIcon('Noodles_&_Pasta_Tagliatelle.png', 'Tagliatelle'),
    GroceryIcon('Noodles_&_Pasta_Udon.png', 'Udon-Nudeln'),
    GroceryIcon('Noodles_&_Pasta_Ziti.png', 'Ziti'),
  ]),
  GroceryCategory('Reis', 'Rice', [
    GroceryIcon('Rice_White_Rice.png', 'Weißer Reis', ['Reis', 'rice']),
    GroceryIcon('Rice_Arborio_Rice.png', 'Arborio-Reis'),
    GroceryIcon('Rice_Brown_Rice.png', 'Naturreis', ['Brauner Reis', 'Vollkornreis']),
    GroceryIcon('Rice_Jasmine_Rice.png', 'Jasminreis'),
    GroceryIcon('Rice_Long-grain_Rice.png', 'Langkornreis'),
    GroceryIcon('Rice_Parboiled_Rice.png', 'Parboiled-Reis'),
    GroceryIcon('Rice_Risotto_Rice.png', 'Risottoreis'),
    GroceryIcon('Rice_Short-grain_Rice.png', 'Rundkornreis'),
    GroceryIcon('Rice_Sushi_Rice.png', 'Sushireis'),
    GroceryIcon('Rice_Wild_Rice.png', 'Wildreis'),
  ]),
  GroceryCategory('Getreide, Hülsenfrüchte & Samen', 'Grains, pulses & seeds', [
    GroceryIcon('Grains_Beans_and_Seeds_Barley.png', 'Gerste', ['Graupen']),
    GroceryIcon('Grains_Beans_and_Seeds_Black_Bean.png', 'Schwarze Bohnen'),
    GroceryIcon('Grains_Beans_and_Seeds_Brown_Rice.png', 'Vollkornreis'),
    GroceryIcon('Grains_Beans_and_Seeds_Bulgur.png', 'Bulgur'),
    GroceryIcon('Grains_Beans_and_Seeds_Chia_Seed.png', 'Chiasamen'),
    GroceryIcon('Grains_Beans_and_Seeds_Chickpea.png', 'Kichererbsen'),
    GroceryIcon('Grains_Beans_and_Seeds_Flax_Seed.png', 'Leinsamen'),
    GroceryIcon('Grains_Beans_and_Seeds_Lentil.png', 'Linsen'),
    GroceryIcon('Grains_Beans_and_Seeds_Oat.png', 'Haferflocken', ['Hafer']),
    GroceryIcon('Grains_Beans_and_Seeds_Quinoa.png', 'Quinoa'),
    GroceryIcon('Grains_Beans_and_Seeds_Sesame_Seed.png', 'Sesam'),
  ]),
  GroceryCategory('Backzutaten', 'Baking', [
    GroceryIcon('Baking_Supplies_Baking_Powder.png', 'Backpulver'),
    GroceryIcon('Baking_Supplies_Baking_Soda.png', 'Natron'),
    GroceryIcon('Baking_Supplies_Cocoa_powder_(for_chocolate_cakes).png', 'Kakaopulver'),
    GroceryIcon('Baking_Supplies_Dry_Yeast.png', 'Trockenhefe'),
    GroceryIcon('Baking_Supplies_Eggs.png', 'Eier', ['Ei']),
    GroceryIcon('Baking_Supplies_Flour.png', 'Mehl', ['Weizenmehl']),
    GroceryIcon('Baking_Supplies_Fresh_Yeast.png', 'Frische Hefe', ['Hefe']),
    GroceryIcon('Baking_Supplies_Oil.png', 'Öl', ['Speiseöl', 'Sonnenblumenöl', 'Rapsöl']),
    GroceryIcon('Baking_Supplies_Oliven_Oil.png', 'Olivenöl', ['olive oil']),
    GroceryIcon('Baking_Supplies_Salt.png', 'Salz'),
    GroceryIcon('Baking_Supplies_Sugar.png', 'Zucker'),
    GroceryIcon('Baking_Supplies_Vanilla_extract_(or_other_flavorings).png', 'Vanilleextrakt', ['Backaroma']),
    GroceryIcon('Baking_Supplies_Vanilla_sugar.png', 'Vanillezucker'),
  ]),
  GroceryCategory('Gewürze', 'Spices', [
    GroceryIcon('Spices_Cinnamon.png', 'Zimt'),
    GroceryIcon('_Spices_and_Seasonings_Allspice.png', 'Piment'),
    GroceryIcon('_Spices_and_Seasonings_Basil_(ground).png', 'Basilikum getrocknet'),
    GroceryIcon('_Spices_and_Seasonings_Bay_leaf_(ground).png', 'Lorbeer', ['Lorbeerblätter']),
    GroceryIcon('_Spices_and_Seasonings_Black_pepper.png', 'Schwarzer Pfeffer', ['Pfeffer']),
    GroceryIcon('_Spices_and_Seasonings_Cardamom.png', 'Kardamom'),
    GroceryIcon('_Spices_and_Seasonings_Cayenne_pepper.png', 'Cayennepfeffer'),
    GroceryIcon('_Spices_and_Seasonings_Celery_seed_(ground).png', 'Selleriesamen'),
    GroceryIcon('_Spices_and_Seasonings_Chili_powder.png', 'Chilipulver', ['Chili']),
    GroceryIcon('_Spices_and_Seasonings_Cinnamon.png', 'Zimtpulver'),
    GroceryIcon('_Spices_and_Seasonings_Cloves.png', 'Nelken', ['Gewürznelken']),
    GroceryIcon('_Spices_and_Seasonings_Coriander.png', 'Koriander gemahlen'),
    GroceryIcon('_Spices_and_Seasonings_Cumin.png', 'Kreuzkümmel', ['Kumin']),
    GroceryIcon('_Spices_and_Seasonings_Fennel_seeds_(ground).png', 'Fenchelsamen'),
    GroceryIcon('_Spices_and_Seasonings_Fenugreek_(ground).png', 'Bockshornklee'),
    GroceryIcon('_Spices_and_Seasonings_Garlic_powder.png', 'Knoblauchpulver'),
    GroceryIcon('_Spices_and_Seasonings_Ginger_powder.png', 'Ingwerpulver'),
    GroceryIcon('_Spices_and_Seasonings_Marjoram_(ground).png', 'Majoran'),
    GroceryIcon('_Spices_and_Seasonings_Mustard_powder.png', 'Senfpulver'),
    GroceryIcon('_Spices_and_Seasonings_Nutmeg.png', 'Muskatnuss', ['Muskat']),
    GroceryIcon('_Spices_and_Seasonings_Onion_powder.png', 'Zwiebelpulver'),
    GroceryIcon('_Spices_and_Seasonings_Oregano.png', 'Oregano getrocknet'),
    GroceryIcon('_Spices_and_Seasonings_Paprika.png', 'Paprikapulver'),
    GroceryIcon('_Spices_and_Seasonings_Rosemary_(ground).png', 'Rosmarin gemahlen'),
    GroceryIcon('_Spices_and_Seasonings_Sage_(ground).png', 'Salbei gemahlen'),
    GroceryIcon('_Spices_and_Seasonings_Smoked_paprika.png', 'Geräuchertes Paprikapulver'),
    GroceryIcon('_Spices_and_Seasonings_Star_anise_(ground).png', 'Sternanis'),
    GroceryIcon('_Spices_and_Seasonings_Sumac.png', 'Sumach'),
    GroceryIcon('_Spices_and_Seasonings_Thyme_(ground).png', 'Thymian gemahlen'),
    GroceryIcon('_Spices_and_Seasonings_Turmeric.png', 'Kurkuma'),
    GroceryIcon('_Spices_and_Seasonings_White_mustard.png', 'Weißer Senf', ['Senfkörner']),
    GroceryIcon('_Spices_and_Seasonings_White_pepper.png', 'Weißer Pfeffer'),
  ]),
  GroceryCategory('Saucen & Aufstriche', 'Sauces & spreads', [
    GroceryIcon('Sauces_Barbecue_Sauce.png', 'Barbecuesauce', ['BBQ-Sauce', 'Grillsoße']),
    GroceryIcon('Sauces_Chili_Sauce.png', 'Chilisauce', ['Scharfe Sauce', 'Sriracha']),
    GroceryIcon('Sauces_Dips.png', 'Dips', ['Dip']),
    GroceryIcon('Sauces_Hummus.png', 'Hummus'),
    GroceryIcon('Sauces_Ketchup.png', 'Ketchup'),
    GroceryIcon('Sauces_Mayonnaise.png', 'Mayonnaise', ['Mayo']),
    GroceryIcon('Sauces_Mustard.png', 'Senf'),
    GroceryIcon('Sauces_Pesto.png', 'Pesto'),
    GroceryIcon('Sauces_Soy_Sauce.png', 'Sojasauce', ['Sojasoße']),
    GroceryIcon('Sauces_Tomato_Sauce_(Glass_Bottle).png', 'Tomatensauce', ['Passata', 'Pastasauce']),
  ]),
  GroceryCategory('Konserven', 'Tinned food', [
    GroceryIcon('Canned_Goods_Canned_beans.png', 'Bohnen aus der Dose', ['Dosenbohnen']),
    GroceryIcon('Canned_Goods_Canned_corn.png', 'Mais aus der Dose', ['Dosenmais']),
    GroceryIcon('Canned_Goods_Canned_fish_(salmon,_sardines).png', 'Fisch aus der Dose', ['Dosenfisch']),
    GroceryIcon('Canned_Goods_Canned_peas.png', 'Erbsen aus der Dose'),
    GroceryIcon('Canned_Goods_Canned_sardines.png', 'Sardinen'),
    GroceryIcon('Canned_Goods_Canned_soup.png', 'Dosensuppe', ['Suppe']),
    GroceryIcon('Canned_Goods_Canned_tuna.png', 'Thunfisch aus der Dose', ['Dosenthunfisch']),
    GroceryIcon('Canned_Goods_Condensed_milk.png', 'Gezuckerte Kondensmilch'),
    GroceryIcon('Canned_Goods_Tomato_paste.png', 'Tomatenmark'),
  ]),
  GroceryCategory('Tiefkühlkost', 'Frozen food', [
    GroceryIcon('Frozen_Foods_Chicken_nuggets.png', 'Chicken Nuggets', ['Hähnchen-Nuggets']),
    GroceryIcon('Frozen_Foods_Fish_sticks.png', 'Fischstäbchen'),
    GroceryIcon('Frozen_Foods_French_fries_(frozen).png', 'Pommes frites', ['Pommes']),
    GroceryIcon('Frozen_Foods_Frozen_berries_(strawberries,_blueberries).png', 'Tiefkühlbeeren', ['Gefrorene Beeren']),
    GroceryIcon('Frozen_Foods_Frozen_breakfast_sandwiches.png', 'Frühstückssandwiches'),
    GroceryIcon('Frozen_Foods_Frozen_chicken_wings.png', 'Hähnchenflügel TK'),
    GroceryIcon('Frozen_Foods_Frozen_corn_on_the_cob.png', 'Maiskolben TK'),
    GroceryIcon('Frozen_Foods_Frozen_fries_with_seasoning.png', 'Gewürzpommes'),
    GroceryIcon('Frozen_Foods_Frozen_lasagna.png', 'Lasagne TK'),
    GroceryIcon('Frozen_Foods_Frozen_meatballs.png', 'Hackbällchen', ['Frikadellen']),
    GroceryIcon('Frozen_Foods_Frozen_mixed_fruit.png', 'Früchtemischung TK'),
    GroceryIcon('Frozen_Foods_Frozen_pizza.png', 'Tiefkühlpizza', ['Pizza']),
    GroceryIcon('Frozen_Foods_Frozen_shrimp.png', 'Garnelen TK'),
    GroceryIcon('Frozen_Foods_Frozen_spinach.png', 'Tiefkühlspinat', ['Rahmspinat']),
    GroceryIcon('Frozen_Foods_Frozen_spring_rolls.png', 'Frühlingsrollen'),
    GroceryIcon('Frozen_Foods_Frozen_vegetables_(peas,_corn,_mixed_veggies).png', 'Tiefkühlgemüse', ['Gemüse', 'vegetables']),
    GroceryIcon('Frozen_Foods_Frozen_waffles.png', 'Waffeln TK'),
    GroceryIcon('Frozen_Foods_Ice_cream_(pints_or_cones).png', 'Eis', ['Eiscreme', 'Speiseeis']),
    GroceryIcon('Frozen_Foods_gyoza.png', 'Gyoza', ['Teigtaschen', 'Dumplings']),
    GroceryIcon('Frozen_Foods_pastries.png', 'Backwaren TK', ['Blätterteig']),
  ]),
  GroceryCategory('Schokolade & Süßes', 'Chocolate & sweets', [
    GroceryIcon('Chocolate_Milk_chocolate_bar.png', 'Vollmilchschokolade', ['Schokolade', 'Tafel Schokolade']),
    GroceryIcon('Chocolate_Dark_chocolate_bar.png', 'Zartbitterschokolade', ['Bitterschokolade', 'Dunkle Schokolade']),
    GroceryIcon('Chocolate_White_chocolate_bar.png', 'Weiße Schokolade'),
    GroceryIcon('Chocolate_Chocolate_chips_(for_cookies,_muffins).png', 'Schokotropfen', ['Schokoladenstückchen']),
    GroceryIcon('Chocolate_Chocolate_coins.png', 'Schokotaler', ['Schokomünzen']),
    GroceryIcon('Chocolate_Chocolate_spreads_(like_Nutella).png', 'Schokoaufstrich', ['Nutella', 'Nuss-Nougat-Creme']),
    GroceryIcon('Chocolate_Cocoa_powder.png', 'Kakaopulver', ['Kakao', 'Backkakao']),
    GroceryIcon('Chocolate_Novelty_&_Seasonal.png', 'Schokofiguren', ['Saisonartikel', 'Adventskalender']),
    GroceryIcon('Chocolate_hot_chocolate_mix.png', 'Trinkschokolade', ['Heiße Schokolade']),
  ]),
  GroceryCategory('Getränke', 'Drinks', [
    GroceryIcon('Drinks_Bottle_of_water.png', 'Wasser', ['Mineralwasser', 'Sprudel', 'water']),
    GroceryIcon('Coffee_&_Tea_Coffee_Beans.png', 'Kaffeebohnen', ['Bohnenkaffee']),
    GroceryIcon('Coffee_Tea_Coffee_Beans.png', 'Kaffee', ['Filterkaffee', 'Gemahlener Kaffee']),
    GroceryIcon('Beverages_Beer.png', 'Bier'),
    GroceryIcon('Beverages_Champagne.png', 'Champagner', ['Sekt', 'Prosecco']),
    GroceryIcon('Beverages_Gin_&_Tonic.png', 'Gin Tonic', ['Gin']),
    GroceryIcon('Beverages_Margarita.png', 'Margarita'),
    GroceryIcon('Beverages_Martini.png', 'Martini'),
    GroceryIcon('Beverages_Rum.png', 'Rum'),
    GroceryIcon('Beverages_Tequila.png', 'Tequila'),
    GroceryIcon('Beverages_Vodka.png', 'Wodka', ['Vodka']),
    GroceryIcon('Beverages_Whiskey.png', 'Whiskey', ['Whisky']),
    GroceryIcon('Beverages_White_Wine.png', 'Weißwein'),
    GroceryIcon('Beverages_Wine.png', 'Wein', ['Rotwein']),
  ]),
  GroceryCategory('Säfte', 'Juices', [
    GroceryIcon('Juice_Apple_Juice.png', 'Apfelsaft'),
    GroceryIcon('Juice_Blueberry_Juice.png', 'Heidelbeersaft'),
    GroceryIcon('Juice_Carrot_Juice.png', 'Karottensaft'),
    GroceryIcon('Juice_Cherry_Juice.png', 'Kirschsaft'),
    GroceryIcon('Juice_Cranberry_Juice.png', 'Cranberrysaft'),
    GroceryIcon('Juice_Grape_Juice.png', 'Traubensaft'),
    GroceryIcon('Juice_Grapefruit_Juice.png', 'Grapefruitsaft'),
    GroceryIcon('Juice_Guava_Juice.png', 'Guavensaft'),
    GroceryIcon('Juice_Kiwi_Juice.png', 'Kiwisaft'),
    GroceryIcon('Juice_Lemonade.png', 'Limonade'),
    GroceryIcon('Juice_Mango_Juice.png', 'Mangosaft'),
    GroceryIcon('Juice_Orange_Juice.png', 'Orangensaft'),
    GroceryIcon('Juice_Papaya_Juice.png', 'Papayasaft'),
    GroceryIcon('Juice_Passion_Fruit_Juice.png', 'Maracujasaft', ['Passionsfruchtsaft']),
    GroceryIcon('Juice_Pineapple_Juice.png', 'Ananassaft'),
    GroceryIcon('Juice_Pomegranate_Juice.png', 'Granatapfelsaft'),
    GroceryIcon('Juice_Raspberry_Juice.png', 'Himbeersaft'),
    GroceryIcon('Juice_Strawberry_Juice.png', 'Erdbeersaft'),
    GroceryIcon('Juice_Tomato_Juice.png', 'Tomatensaft'),
    GroceryIcon('Juice_Watermelon_Juice.png', 'Wassermelonensaft'),
  ]),
  GroceryCategory('Erfrischungsgetränke', 'Soft drinks', [
    GroceryIcon('Soft_Drinks_Coca-Cola.png', 'Coca-Cola', ['Cola', 'Coke']),
    GroceryIcon('Soft_Drinks_Coca-Cola_Zero_Sugar_(Coke_Zero).png', 'Cola Zero', ['Coke Zero']),
    GroceryIcon('Soft_Drinks_Diet_Coke.png', 'Cola light'),
    GroceryIcon('Soft_Drinks_Pepsi.png', 'Pepsi'),
    GroceryIcon('Soft_Drinks_Sprite.png', 'Sprite'),
    GroceryIcon('Soft_Drinks_Fanta.png', 'Fanta'),
    GroceryIcon('Soft_Drinks_7Up.png', '7Up'),
    GroceryIcon('Soft_Drinks_Dr_Pepper.png', 'Dr Pepper'),
    GroceryIcon('Soft_Drinks_Ginger_Ale.png', 'Ginger Ale'),
    GroceryIcon('Soft_Drinks_Mountain_Dew.png', 'Mountain Dew'),
  ]),
  GroceryCategory('Hygiene', 'Hygiene', [
    GroceryIcon('Hygiene_Bar_soap.png', 'Seifenstück', ['Seife']),
    GroceryIcon('Hygiene_Body_lotion.png', 'Bodylotion', ['Körperlotion']),
    GroceryIcon('Hygiene_Conditioner.png', 'Spülung', ['Conditioner', 'Haarspülung']),
    GroceryIcon('Hygiene_Cotton_pads.png', 'Wattepads'),
    GroceryIcon('Hygiene_Cotton_swabs_(Q-tips).png', 'Wattestäbchen'),
    GroceryIcon('Hygiene_Dental_floss.png', 'Zahnseide'),
    GroceryIcon('Hygiene_Deodorant.png', 'Deo', ['Deodorant']),
    GroceryIcon('Hygiene_Disposable_Glovespng.png', 'Einweghandschuhe', ['Handschuhe', 'gloves']),
    GroceryIcon('Hygiene_Face_cleanser.png', 'Gesichtsreiniger'),
    GroceryIcon('Hygiene_Face_cream_(moisturizer).png', 'Gesichtscreme'),
    GroceryIcon('Hygiene_Feminine_pads_(sanitary_pads).png', 'Binden', ['Damenbinden']),
    GroceryIcon('Hygiene_Hair_gel_(or_hair_wax).png', 'Haargel', ['Haarwachs']),
    GroceryIcon('Hygiene_Hand_sanitizer.png', 'Handdesinfektion', ['Desinfektionsmittel']),
    GroceryIcon('Hygiene_Lip_balm.png', 'Lippenbalsam', ['Lippenpflege']),
    GroceryIcon('Hygiene_Liquid_soap.png', 'Flüssigseife', ['Handseife', 'Duschgel', 'shower gel']),
    GroceryIcon('Hygiene_Makeup_brush.png', 'Make-up-Pinsel'),
    GroceryIcon('Hygiene_Makeup_remover_(wipes_or_liquid).png', 'Make-up-Entferner', ['Abschminktücher']),
    GroceryIcon('Hygiene_Menstrual_cup.png', 'Menstruationstasse'),
    GroceryIcon('Hygiene_Mouthwash.png', 'Mundwasser', ['Mundspülung']),
    GroceryIcon('Hygiene_Nail_clippers.png', 'Nagelknipser', ['Nagelschere']),
    GroceryIcon('Hygiene_Nail_polish.png', 'Nagellack'),
    GroceryIcon('Hygiene_Panty_liners.png', 'Slipeinlagen'),
    GroceryIcon('Hygiene_Razor.png', 'Rasierer', ['Rasierklingen']),
    GroceryIcon('Hygiene_Shampoo.png', 'Shampoo'),
    GroceryIcon('Hygiene_Sunscreen.png', 'Sonnencreme', ['Sonnenschutz']),
    GroceryIcon('Hygiene_Tampons.png', 'Tampons'),
    GroceryIcon('Hygiene_Tissues_(facial_tissues).png', 'Taschentücher'),
    GroceryIcon('Hygiene_Toilet_paper.png', 'Toilettenpapier', ['Klopapier']),
    GroceryIcon('Hygiene_Toothbrush.png', 'Zahnbürste'),
    GroceryIcon('Hygiene_Toothpaste.png', 'Zahnpasta', ['Zahncreme']),
    GroceryIcon('Hygiene_comb.png', 'Kamm'),
  ]),
  GroceryCategory('Putzmittel', 'Cleaning', [
    GroceryIcon('Cleaning_Supplies_All-purpose_cleaner.png', 'Allzweckreiniger'),
    GroceryIcon('Cleaning_Supplies_Bathroom_cleaner_(tile_&_grout).png', 'Badreiniger'),
    GroceryIcon('Cleaning_Supplies_Bleach.png', 'Bleichmittel', ['Chlorreiniger']),
    GroceryIcon('Cleaning_Supplies_Carpet_cleaner.png', 'Teppichreiniger'),
    GroceryIcon('Cleaning_Supplies_Cleaning_gloves.png', 'Putzhandschuhe'),
    GroceryIcon('Cleaning_Supplies_Dishwashing_liquid.png', 'Spülmittel'),
    GroceryIcon('Cleaning_Supplies_Drain_cleaner.png', 'Rohrreiniger'),
    GroceryIcon('Cleaning_Supplies_Fabric_softener.png', 'Weichspüler'),
    GroceryIcon('Cleaning_Supplies_Glass_cleaner.png', 'Glasreiniger'),
    GroceryIcon('Cleaning_Supplies_Laundry_detergent.png', 'Waschmittel'),
    GroceryIcon('Cleaning_Supplies_Microfiber_cloths.png', 'Mikrofasertücher', ['Putzlappen']),
    GroceryIcon('Cleaning_Supplies_Oven_cleaner.png', 'Backofenreiniger'),
    GroceryIcon('Cleaning_Supplies_Toilet_bowl_cleaner.png', 'WC-Reiniger'),
    GroceryIcon('Cleaning_Supplies_Toilet_brush.png', 'WC-Bürste', ['Klobürste']),
    GroceryIcon('Cleaning_Supplies_baking_soda.png', 'Backsoda'),
    GroceryIcon('Cleaning_Supplies_bin_liners.png', 'Müllbeutel', ['Mülltüten']),
    GroceryIcon('Cleaning_Supplies_brushes.png', 'Bürsten'),
    GroceryIcon('Cleaning_Supplies_mop_solution.png', 'Bodenreiniger', ['Wischmittel']),
    GroceryIcon('Cleaning_Supplies_room_spray.png', 'Raumspray', ['Duftspray']),
  ]),
  GroceryCategory('Baby', 'Baby', [
    GroceryIcon('Baby_Care_Diapers.png', 'Windeln'),
    GroceryIcon('Baby_Care_&_Hygiene_Diapers.png', 'Windelpackung'),
    GroceryIcon('Baby_Care_&_Hygiene_Baby_lotion.png', 'Babylotion'),
    GroceryIcon('Baby_Care_&_Hygiene_Baby_shampoo_&_body_wash.png', 'Babyshampoo', ['Baby-Waschgel']),
    GroceryIcon('Baby_Care_&_Hygiene_Baby_wipes.png', 'Feuchttücher', ['Babytücher']),
    GroceryIcon('Baby_Care_&_Hygiene_Diaper_rash_cream.png', 'Wundschutzcreme', ['Windelcreme']),
    GroceryIcon('Baby_Feeding_Baby_spoons.png', 'Babylöffel'),
    GroceryIcon('Baby_Feeding_Bibs.png', 'Lätzchen'),
    GroceryIcon('Baby_Feeding_Bottles_&_nipples.png', 'Babyflasche', ['Fläschchen', 'Sauger']),
    GroceryIcon('Baby_Feeding_Pacifiers.png', 'Schnuller'),
    GroceryIcon('Baby_Feeding_Sippy_cups.png', 'Trinklernbecher'),
    GroceryIcon('Baby_Food_&_Drinks_Baby_cereal.png', 'Babybrei', ['Getreidebrei']),
    GroceryIcon('Baby_Food_&_Drinks_Baby_purees.png', 'Babygläschen', ['Obstbrei', 'Gemüsebrei']),
    GroceryIcon('Baby_Food_&_Drinks_Baby_snacks.png', 'Babysnacks'),
    GroceryIcon('Baby_Food_&_Drinks_Infant_formula.png', 'Säuglingsnahrung', ['Babymilch', 'Pre-Nahrung']),
  ]),
  GroceryCategory('Tierbedarf', 'Pet supplies', [
    GroceryIcon('Pet_Food_Cat_food_(dry).png', 'Katzentrockenfutter', ['Katzenfutter']),
    GroceryIcon('Pet_Food_Cat_food_(wet).png', 'Katzennassfutter'),
    GroceryIcon('Pet_Food_Dog_food_(dry).png', 'Hundetrockenfutter', ['Hundefutter']),
    GroceryIcon('Pet_Food_Dog_food_(wet).png', 'Hundenassfutter'),
  ]),
  GroceryCategory('Sonstiges', 'Other', [
    GroceryIcon('BBQ_Charcoal.png', 'Grillkohle', ['Holzkohle', 'Kohle']),
    GroceryIcon('General_Shopping_cart.png', 'Einkaufswagen', ['Einkauf']),
    GroceryIcon('Other_Other.png', 'Sonstiges', ['Anderes']),
  ]),
];

/// Flat view of [groceryCategories], in the same order.
final List<GroceryIcon> groceryIcons = [for (final c in groceryCategories) ...c.icons];

/// The category an icon came from, in the interface language.
final Map<String, GroceryCategory> groceryCategoryByFile = {
  for (final c in groceryCategories)
    for (final i in c.icons) i.file: c,
};

/// Icon by asset path, for looking up what an item already carries.
final Map<String, GroceryIcon> groceryIconByAsset = {for (final i in groceryIcons) i.asset: i};

// ---------------------------------------------------------------------------
// English labels, read off the file names
// ---------------------------------------------------------------------------

/// Longest run of leading `_`-separated words shared by every file in a
/// section, e.g. `Fresh_Herbs_Fresh_` or `Baby_`. Empty when they don't agree —
/// the drinks sit in `Drinks_`, `Beverages_` and `Coffee_&_Tea_` files — in
/// which case nothing is stripped.
///
/// Public because `grocery_search.dart` strips exactly the same prefix before
/// folding the English search terms. If the two disagreed, an icon could show a
/// name it could not be found by.
String sharedFilePrefix(List<GroceryIcon> icons) {
  if (icons.length < 2) return '';
  final first = icons.first.file.split('_');
  var shared = first.length - 1;
  for (final icon in icons.skip(1)) {
    final words = icon.file.split('_');
    shared = shared.clamp(0, words.length - 1);
    for (var i = 0; i < shared; i++) {
      if (words[i] != first[i]) {
        shared = i;
        break;
      }
    }
  }
  return shared == 0 ? '' : '${first.take(shared).join('_')}_';
}

/// Where the file name is not a usable English label on its own.
///
/// Three kinds of problem, and nothing else belongs here:
///
/// * **The section prefix survives.** `Gewürze`, `Getränke` and `Baby` have
///   files whose leading words don't agree (`Spices_Cinnamon` beside
///   `_Spices_and_Seasonings_Allspice`), so [sharedFilePrefix] finds nothing to
///   strip and the label would read "Spices and Seasonings Allspice".
/// * **Two files reduce to the same label.** `Cat_food_(dry)` and
///   `Cat_food_(wet)` both lose their parenthetical and become "Cat food".
/// * **The file name is simply wrong** — `Disposable_Glovespng`,
///   `Oliven_Oil`, `Novelty_&_Seasonal` for the chocolate figures.
const _englishLabelOverrides = <String, String>{
  // Spices: the section prefix is not shared, so it would survive in full.
  'Spices_Cinnamon.png': 'Cinnamon',
  '_Spices_and_Seasonings_Allspice.png': 'Allspice',
  '_Spices_and_Seasonings_Basil_(ground).png': 'Dried basil',
  '_Spices_and_Seasonings_Bay_leaf_(ground).png': 'Bay leaf',
  '_Spices_and_Seasonings_Black_pepper.png': 'Black pepper',
  '_Spices_and_Seasonings_Cardamom.png': 'Cardamom',
  '_Spices_and_Seasonings_Cayenne_pepper.png': 'Cayenne pepper',
  '_Spices_and_Seasonings_Celery_seed_(ground).png': 'Celery seed',
  '_Spices_and_Seasonings_Chili_powder.png': 'Chilli powder',
  '_Spices_and_Seasonings_Cinnamon.png': 'Ground cinnamon',
  '_Spices_and_Seasonings_Cloves.png': 'Cloves',
  '_Spices_and_Seasonings_Coriander.png': 'Ground coriander',
  '_Spices_and_Seasonings_Cumin.png': 'Cumin',
  '_Spices_and_Seasonings_Fennel_seeds_(ground).png': 'Fennel seeds',
  '_Spices_and_Seasonings_Fenugreek_(ground).png': 'Fenugreek',
  '_Spices_and_Seasonings_Garlic_powder.png': 'Garlic powder',
  '_Spices_and_Seasonings_Ginger_powder.png': 'Ground ginger',
  '_Spices_and_Seasonings_Marjoram_(ground).png': 'Marjoram',
  '_Spices_and_Seasonings_Mustard_powder.png': 'Mustard powder',
  '_Spices_and_Seasonings_Nutmeg.png': 'Nutmeg',
  '_Spices_and_Seasonings_Onion_powder.png': 'Onion powder',
  '_Spices_and_Seasonings_Oregano.png': 'Dried oregano',
  '_Spices_and_Seasonings_Paprika.png': 'Paprika',
  '_Spices_and_Seasonings_Rosemary_(ground).png': 'Ground rosemary',
  '_Spices_and_Seasonings_Sage_(ground).png': 'Ground sage',
  '_Spices_and_Seasonings_Smoked_paprika.png': 'Smoked paprika',
  '_Spices_and_Seasonings_Star_anise_(ground).png': 'Star anise',
  '_Spices_and_Seasonings_Sumac.png': 'Sumac',
  '_Spices_and_Seasonings_Thyme_(ground).png': 'Ground thyme',
  '_Spices_and_Seasonings_Turmeric.png': 'Turmeric',
  '_Spices_and_Seasonings_White_mustard.png': 'White mustard',
  '_Spices_and_Seasonings_White_pepper.png': 'White pepper',

  // Drinks: three different file prefixes in one section.
  'Drinks_Bottle_of_water.png': 'Water',
  'Coffee_&_Tea_Coffee_Beans.png': 'Coffee beans',
  'Coffee_Tea_Coffee_Beans.png': 'Coffee',
  'Beverages_Beer.png': 'Beer',
  'Beverages_Champagne.png': 'Champagne',
  'Beverages_Gin_&_Tonic.png': 'Gin & tonic',
  'Beverages_Margarita.png': 'Margarita',
  'Beverages_Martini.png': 'Martini',
  'Beverages_Rum.png': 'Rum',
  'Beverages_Tequila.png': 'Tequila',
  'Beverages_Vodka.png': 'Vodka',
  'Beverages_Whiskey.png': 'Whiskey',
  'Beverages_White_Wine.png': 'White wine',
  'Beverages_Wine.png': 'Wine',

  // Baby: `Baby_` is shared, the sub-section after it is not.
  'Baby_Care_Diapers.png': 'Nappies',
  'Baby_Care_&_Hygiene_Diapers.png': 'Pack of nappies',
  'Baby_Care_&_Hygiene_Baby_lotion.png': 'Baby lotion',
  'Baby_Care_&_Hygiene_Baby_shampoo_&_body_wash.png': 'Baby shampoo',
  'Baby_Care_&_Hygiene_Baby_wipes.png': 'Baby wipes',
  'Baby_Care_&_Hygiene_Diaper_rash_cream.png': 'Nappy rash cream',
  'Baby_Feeding_Baby_spoons.png': 'Baby spoons',
  'Baby_Feeding_Bibs.png': 'Bibs',
  'Baby_Feeding_Bottles_&_nipples.png': 'Baby bottle',
  'Baby_Feeding_Pacifiers.png': 'Dummies',
  'Baby_Feeding_Sippy_cups.png': 'Sippy cups',
  'Baby_Food_&_Drinks_Baby_cereal.png': 'Baby cereal',
  'Baby_Food_&_Drinks_Baby_purees.png': 'Baby purees',
  'Baby_Food_&_Drinks_Baby_snacks.png': 'Baby snacks',
  'Baby_Food_&_Drinks_Infant_formula.png': 'Infant formula',

  // Pet food: the parenthetical is the whole distinction.
  'Pet_Food_Cat_food_(dry).png': 'Dry cat food',
  'Pet_Food_Cat_food_(wet).png': 'Wet cat food',
  'Pet_Food_Dog_food_(dry).png': 'Dry dog food',
  'Pet_Food_Dog_food_(wet).png': 'Wet dog food',

  // Miscellany: a section of three unrelated files shares no prefix.
  'BBQ_Charcoal.png': 'Charcoal',
  'General_Shopping_cart.png': 'Shopping cart',
  'Other_Other.png': 'Other',

  // File names that are wrong or unhelpful.
  'Hygiene_Disposable_Glovespng.png': 'Disposable gloves',
  'Baking_Supplies_Oliven_Oil.png': 'Olive oil',
  'Chocolate_Novelty_&_Seasonal.png': 'Chocolate figures',
  'Frozen_Foods_pastries.png': 'Frozen pastries',
  'Frozen_Foods_French_fries_(frozen).png': 'Chips',
  'Frozen_Foods_Frozen_fries_with_seasoning.png': 'Seasoned chips',
  'Cereals_Fruit_Loops.png': 'Froot Loops',
};

/// File name → English label, built once. Everything not overridden is the file
/// name with its section prefix, its parenthetical asides and its `.png` taken
/// off, and the first letter capitalised.
final Map<String, String> _englishLabels = {
  for (final category in groceryCategories)
    ...() {
      final prefix = sharedFilePrefix(category.icons);
      return {
        for (final icon in category.icons)
          icon.file: _englishLabelOverrides[icon.file] ??
              _labelFromFile(icon.file.substring(prefix.length)),
      };
    }(),
};

String _labelFromFile(String stem) {
  final withoutExtension = stem.replaceAll(RegExp(r'\.png$'), '');
  final withoutAsides = withoutExtension.replaceAll(RegExp(r'\([^)]*\)'), ' ');
  final words = withoutAsides.replaceAll('_', ' ').split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final joined = words.join(' ');
  if (joined.isEmpty) return withoutExtension.replaceAll('_', ' ');
  return joined[0].toUpperCase() + joined.substring(1);
}

/// The English name of a grocery file. Falls back to the bare file name for a
/// file that isn't in the catalog at all, which only a stale `icon_asset` in the
/// database can produce.
String englishGroceryLabel(String file) => _englishLabels[file] ?? _labelFromFile(file);
