import 'shopping_list.dart';

/// What comes back from one Vorhaben: a goal turned into a list of things to
/// buy, plus how to actually do it.
///
/// **A plan is a template, not an object.** It is never written to Supabase, has no id, no row and no pointer back; it
/// lives in [PlannerState] until the reader taps "Liste erstellen", and then the
/// *Liste* is the artifact. Killing the app loses it, which is correct: the
/// household's dinner plans are not ours to keep, and a table of everything
/// every family has ever asked for is a thing that can leak.
///
/// See [docs/list-planner.md](../../docs/list-planner.md).
class ListPlan {
  /// What the list will be called — "Butter Chicken für 4".
  final String title;

  /// Lebensmittel or Sonstige. **This is what decides the icons**: it becomes
  /// the new list's [ListKind], which decides whether `suggestIcon` looks in the
  /// grocery photographs or in the symbol set. A Bauhaus run wants symbols; a
  /// curry wants pictures of chicken.
  final ListKind kind;

  /// How to do it, in order. May be empty — a hardware run has no method, and
  /// pretending otherwise would print an empty card.
  ///
  /// **The overview, not the method, whenever [recipe] is there.** The server
  /// cuts these to six in that case, because a model asked for both will
  /// happily write the whole thing twice.
  final List<String> steps;

  /// The full method, **cooking goals only** — null for a hardware run, a
  /// party, a trip or a week's shopping, which is most of what Vorhaben is for.
  ///
  /// **The one field with markup in it**, and the subset is ours rather than the
  /// model's: `##` headings, `-` ingredients, `1.` working steps, `**bold**` on
  /// a temperature or a time, and nothing else — see `MarkdownText`, which is
  /// the only parser in the app. A method has structure that prose cannot carry,
  /// and this is the shape of a cookbook page rather than of a chat answer.
  ///
  /// It is folded away behind a disclosure on the card, because the shopping is
  /// why the card was opened and the recipe is what you want later, at the hob.
  final String? recipe;

  final List<ListPlanItem> items;

  const ListPlan({
    required this.title,
    required this.kind,
    required this.steps,
    this.recipe,
    required this.items,
  });

  /// Reads the model's answer, defensively.
  ///
  /// **Every field is optional on the wire even though the schema asks for all
  /// of them.** The answer is a JSON object a language model produced; a missing
  /// `steps` is a plan with no method rather than an exception in front of
  /// somebody who typed a sentence and waited ten seconds. The one thing that
  /// cannot be recovered from is having no items, and the caller checks that.
  factory ListPlan.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final recipe = (json['recipe'] as String?)?.trim();
    return ListPlan(
      title: (json['title'] as String?)?.trim() ?? '',
      kind: json['kind'] == 'other' ? ListKind.other : ListKind.grocery,
      // Empty is the same as absent: an older function answers without the
      // field at all, and both must draw no disclosure rather than an empty one.
      recipe: recipe == null || recipe.isEmpty ? null : recipe,
      steps: [
        for (final step in (json['steps'] as List?) ?? const [])
          if (step is String && step.trim().isNotEmpty) step.trim(),
      ],
      items: [
        for (final item in (rawItems as List?) ?? const [])
          if (item is Map<String, dynamic>) ?ListPlanItem.fromJson(item),
      ],
    );
  }

  bool get isUsable => items.isNotEmpty;
}

/// One article on the plan — **what to buy, not what the recipe measures.**
///
/// You buy a pack of butter; the "2 EL" belongs in the step that uses it. That
/// is the correct answer for a shopping list and it is also why `GroceryUnit`
/// needs no Esslöffel: those are not units of shopping.
class ListPlanItem {
  final String name;

  /// The count — "500" in *500 g Hähnchenbrust*. Free text, exactly as
  /// `list_items.sub` is, because it was free text before the unit was split
  /// out of it and an older row may still hold a word.
  final String? quantity;

  /// A [GroceryUnit] key, or null for the default (Stück). The prompt gives the
  /// model the ten keys and nothing else, so it cannot invent a value into a
  /// column that holds ten; anything it could not express lands in [quantity].
  final String? unit;

  const ListPlanItem({required this.name, this.quantity, this.unit});

  static ListPlanItem? fromJson(Map<String, dynamic> json) {
    final name = (json['name'] as String?)?.trim();
    if (name == null || name.isEmpty) return null;
    final quantity = (json['quantity'] as String?)?.trim();
    final unit = (json['unit'] as String?)?.trim();
    // **No `emoji` here, and an older answer's is ignored.** A picture beside an
    // article was a guess the app made confidently and often wrongly; the model
    // still draws, but in the method and the recipe where a miss is decoration
    // rather than a mislabelled row. See [planItemIconKey].
    return ListPlanItem(
      name: name,
      quantity: quantity == null || quantity.isEmpty ? null : quantity,
      // 'piece' is the default and is stored as null — writing it on every row
      // would put a "Stück" line under every article for no information.
      unit: unit == null || unit.isEmpty || unit == 'piece' ? null : unit,
    );
  }
}
