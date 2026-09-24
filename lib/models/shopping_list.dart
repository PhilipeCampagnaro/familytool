import 'event_link.dart';
import 'visibility.dart';
import '../l10n/l10n.dart';

/// What kind of list this is — **exactly** `public.list_kind` in Supabase.
///
/// Two values, not three: "Alle Artikel" used to be a third one
/// (`ListType.summary`), but it is a view computed across the real lists and has
/// no row to store, so a third enum value here was one careless `insert` away
/// from a `22P02 invalid input value for enum list_kind`. It lives on as
/// [ShoppingList.summary] instead — an object the repository refuses to write.
enum ListKind { grocery, other }

/// The one visibility enum, under the name the Listen code has always used.
///
/// Boxen and Board tasks need the same three values against the same
/// `public.visibility` type, so the definition moved to `visibility.dart` rather
/// than being copied twice. An alias rather than a rename because
/// `ListVisibility` reads better at the Listen call sites and the churn bought
/// nothing.
typedef ListVisibility = ItemVisibility;

ListKind _kindFrom(String? value) => value == 'grocery' ? ListKind.grocery : ListKind.other;

DateTime? _timeFrom(Object? value) => value == null ? null : DateTime.tryParse(value as String)?.toLocal();

/// An empty column and an absent one are the same thing everywhere in this
/// file — a list with `recipe = ''` draws no chip, exactly as `null` does.
String? _textOrNull(Object? value) {
  final text = (value as String?)?.trim();
  return text == null || text.isEmpty ? null : text;
}

/// The id of the computed "Alle Artikel" view. Never a `lists.id` — every real
/// one is a uuid.
const String summaryListId = 'all';

class ShoppingList {
  final String id;
  final String name;

  /// What to draw in front of the list — a shop logo, a grocery picture or a
  /// Lucide glyph, all as the one string `data/icon_suggestions.dart` defines
  /// (`assets/...` or `lucide:<name>`). Normally filled in from the name as it
  /// is typed; the picker overrides it.
  ///
  /// Stored in the `icon_asset` column. The names differ on purpose — the
  /// column predates Lucide keys being allowed in it — so [fromMap]/[toMap] are
  /// the only places the two spellings meet.
  final String? iconKey;

  final ListKind kind;

  /// The household this list belongs to. Written on insert (the insert policy
  /// re-checks it against `my_family_id()`), and **never** used to filter a
  /// read — RLS decides what "my lists" means, and a client-side family filter
  /// would hide exactly the rows a guest is meant to see.
  final String familyId;

  final String ownerId;
  final ListVisibility visibility;

  /// The user ids in `list_shares` — who else in the household may see this
  /// list when [visibility] is [ListVisibility.custom]. The owner is always
  /// implicitly included and is not repeated here.
  final List<String> sharedWith;

  final int position;

  /// The appointment this list was created for, or null — which is almost every
  /// list. Set once, when the list is made from an event's detail sheet; the
  /// edit sheet neither shows nor touches it, so a link is broken only by
  /// deleting the list.
  final EventLink? eventLink;

  /// How to actually do it, from the Vorhaben that made this list — the short
  /// overview, in order. Empty on every list somebody typed themselves, which
  /// is most of them.
  ///
  /// **Written once, when the list is created, and never edited.** Same shape
  /// as [eventLink] and for the same reason: it is a record of what the plan
  /// said, not a field of the list, so there is no edit path and no way to
  /// clear it but deleting the list.
  final List<String> steps;

  /// The full method, when the Vorhaben was about cooking — null otherwise, and
  /// null on every hand-made list. See [ListPlan.recipe].
  final String? recipe;

  /// The recipe page an imported list was built from — **the address, never
  /// the method**.
  ///
  /// This is [recipe]'s counterpart for a list that came off somebody else's
  /// page rather than out of the model. A *Zubereitungstext* is a Sprachwerk;
  /// copying one into our database and replicating it to every phone in the
  /// household is reproduction, and an ingredient list is facts. So the import
  /// keeps the link instead — which is also the better artefact, because it
  /// stays right when the page is corrected and it is what the cook actually
  /// wants at the hob.
  ///
  /// Same shape as [recipe] and [eventLink]: written once on create, never
  /// edited, and **nothing ever fetches it** afterwards — see
  /// `list_items.link_url` in CLAUDE.md. The import read the page once, when
  /// the reader asked.
  final String? sourceUrl;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// True for the one list that is computed rather than stored. Blocks
  /// [toMap], so "Alle Artikel" cannot be inserted by accident.
  final bool isSummary;

  /// Whether this list carries anything worth opening a method sheet for.
  bool get hasMethod => steps.isNotEmpty || (recipe?.isNotEmpty ?? false);

  /// Whether this list can say where it came from.
  bool get hasSource => sourceUrl?.isNotEmpty ?? false;

  const ShoppingList({
    required this.id,
    required this.name,
    required this.kind,
    required this.familyId,
    required this.ownerId,
    this.iconKey,
    this.visibility = ListVisibility.family,
    this.sharedWith = const [],
    this.position = 0,
    this.eventLink,
    this.steps = const [],
    this.recipe,
    this.sourceUrl,
    this.createdAt,
    this.updatedAt,
  }) : isSummary = false;

  /// "Alle Artikel": every article across every list the user can see, pooled.
  ///
  /// Not seed data and not a row — it has no counterpart in `public.list_kind`
  /// (see the type migration) and exists regardless of how many real lists
  /// there are. [familyId] and [ownerId] are empty for exactly that reason.
  ShoppingList.summary({String? name, this.iconKey})
    : name = name ?? L.s.allItems,
      id = summaryListId,
      kind = ListKind.grocery,
      familyId = '',
      ownerId = '',
      visibility = ListVisibility.family,
      sharedWith = const [],
      position = -1,
      eventLink = null,
      steps = const [],
      recipe = null,
      sourceUrl = null,
      createdAt = null,
      updatedAt = null,
      isSummary = true;

  factory ShoppingList.fromMap(Map<String, dynamic> map, {List<String> sharedWith = const []}) {
    return ShoppingList(
      id: map['id'] as String,
      name: map['name'] as String,
      iconKey: map['icon_asset'] as String?,
      kind: _kindFrom(map['kind'] as String?),
      familyId: map['family_id'] as String,
      ownerId: map['owner_id'] as String,
      visibility: visibilityFrom(map['visibility'] as String?),
      sharedWith: sharedWith,
      position: (map['position'] as num?)?.toInt() ?? 0,
      eventLink: EventLink.fromMap(map),
      steps: [
        for (final s in (map['steps'] as List?) ?? const [])
          if (s is String && s.trim().isNotEmpty) s.trim(),
      ],
      recipe: _textOrNull(map['recipe']),
      sourceUrl: _textOrNull(map['source_url']),
      createdAt: _timeFrom(map['created_at']),
      updatedAt: _timeFrom(map['updated_at']),
    );
  }

  /// The columns of `public.lists` this client ever writes.
  ///
  /// `owner_id` and `family_id` are only sent on insert (they are what the
  /// insert policy checks); on update they would be rejected by
  /// `enforce_container_ownership` for anyone but the owner anyway — hence
  /// [forInsert].
  Map<String, dynamic> toMap({bool forInsert = false}) {
    if (isSummary) {
      throw StateError('"Alle Artikel" ist eine berechnete Ansicht und keine Zeile in public.lists.');
    }
    return {
      'name': name,
      'icon_asset': iconKey,
      'kind': kind.name,
      'visibility': visibility.name,
      'position': position,
      // All four columns or none: the `lists_event_link_complete` check refuses
      // half a link, so an unlinked list writes four explicit nulls.
      ...EventLink.columnsOf(eventLink),
      // **Insert only.** The method is what the plan said when the list was
      // made; there is no screen that edits it, and leaving it out of the
      // update patch is what stops a rename from rewriting it — or, worse, from
      // blanking it on a list loaded before these columns existed.
      if (forInsert) ...{
        'family_id': familyId,
        'owner_id': ownerId,
        'steps': steps.isEmpty ? null : steps,
        'recipe': recipe,
        'source_url': sourceUrl,
      },
    };
  }

  ShoppingList copyWith({
    String? id,
    String? name,
    String? iconKey,
    bool clearIconKey = false,
    ListKind? kind,
    ListVisibility? visibility,
    List<String>? sharedWith,
    int? position,
    EventLink? eventLink,
    List<String>? steps,
    String? recipe,
    String? sourceUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ShoppingList(
      id: id ?? this.id,
      name: name ?? this.name,
      iconKey: clearIconKey ? null : (iconKey ?? this.iconKey),
      kind: kind ?? this.kind,
      familyId: familyId,
      ownerId: ownerId,
      visibility: visibility ?? this.visibility,
      sharedWith: sharedWith ?? this.sharedWith,
      position: position ?? this.position,
      eventLink: eventLink ?? this.eventLink,
      steps: steps ?? this.steps,
      recipe: recipe ?? this.recipe,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class ShoppingListItem {
  final String id;

  /// Non-nullable: every article belongs to exactly one list, including in the
  /// pooled "Alle Artikel" view, where it is what says which list a row came
  /// from and where a tick has to be written back.
  final String listId;

  final String text;

  /// The count — "2" in *2 kg Kartoffeln*. Free text rather than a number: it
  /// was free text before the unit was split out of it, and an older row may
  /// still hold a word.
  final String? sub;

  /// What [sub] counts, as a [GroceryUnit] key — see there. `null` is the
  /// default (Stück), so most articles carry nothing at all.
  final String? unit;

  /// Same key as [ShoppingList.iconKey], same `icon_asset` column.
  final String? iconKey;

  /// Where to buy this — one `http(s)` URL, or null, which is nearly every
  /// article. Held as a column rather than as an attachment row because
  /// `list_item_attachments` is objects in a bucket all the way down and a link
  /// has no object; one rather than a list for the same reason a box has one
  /// photograph. Nothing ever fetches it: it goes to the device to open, so no
  /// preview is drawn and no shop page is copied into our database.
  final String? linkUrl;

  /// Who is meant to do this — `assignee_id`. Split out of the old single
  /// `owner` string, which held a member id and doubled as a visibility hint.
  final String? assigneeId;

  final String? createdBy;

  /// Authoritative. There is no overlay map beside the items any more: the seed
  /// articles that forced one are gone, and a second source of truth for "is
  /// this ticked" would shadow the server's answer after every reload.
  final bool done;

  final String? doneBy;
  final DateTime? doneAt;
  final int position;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ShoppingListItem({
    required this.id,
    required this.listId,
    required this.text,
    this.sub,
    this.unit,
    this.iconKey,
    this.linkUrl,
    this.assigneeId,
    this.createdBy,
    this.done = false,
    this.doneBy,
    this.doneAt,
    this.position = 0,
    this.createdAt,
    this.updatedAt,
  });

  factory ShoppingListItem.fromMap(Map<String, dynamic> map) {
    return ShoppingListItem(
      id: map['id'] as String,
      listId: map['list_id'] as String,
      text: map['text'] as String,
      sub: map['sub'] as String?,
      unit: map['unit'] as String?,
      iconKey: map['icon_asset'] as String?,
      linkUrl: map['link_url'] as String?,
      assigneeId: map['assignee_id'] as String?,
      createdBy: map['created_by'] as String?,
      done: map['done'] as bool? ?? false,
      doneBy: map['done_by'] as String?,
      doneAt: _timeFrom(map['done_at']),
      position: (map['position'] as num?)?.toInt() ?? 0,
      createdAt: _timeFrom(map['created_at']),
      updatedAt: _timeFrom(map['updated_at']),
    );
  }

  /// `created_by` is only sent on insert — the insert policy requires it to be
  /// the caller, and the update policy has no business rewriting it.
  Map<String, dynamic> toMap({bool forInsert = false}) {
    return {
      'list_id': listId,
      'text': text,
      'sub': sub,
      'unit': unit,
      'icon_asset': iconKey,
      'link_url': linkUrl,
      'assignee_id': assigneeId,
      'done': done,
      'done_by': doneBy,
      'done_at': doneAt?.toUtc().toIso8601String(),
      'position': position,
      if (forInsert) 'created_by': createdBy,
    };
  }

  ShoppingListItem copyWith({
    String? id,
    String? listId,
    String? text,
    String? sub,
    bool clearSub = false,
    String? unit,
    bool clearUnit = false,
    String? iconKey,
    bool clearIconKey = false,
    String? linkUrl,
    bool clearLinkUrl = false,
    String? assigneeId,
    String? createdBy,
    bool? done,
    String? doneBy,
    bool clearDoneBy = false,
    DateTime? doneAt,
    bool clearDoneAt = false,
    int? position,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ShoppingListItem(
      id: id ?? this.id,
      listId: listId ?? this.listId,
      text: text ?? this.text,
      sub: clearSub ? null : (sub ?? this.sub),
      unit: clearUnit ? null : (unit ?? this.unit),
      iconKey: clearIconKey ? null : (iconKey ?? this.iconKey),
      linkUrl: clearLinkUrl ? null : (linkUrl ?? this.linkUrl),
      assigneeId: assigneeId ?? this.assigneeId,
      createdBy: createdBy ?? this.createdBy,
      done: done ?? this.done,
      doneBy: clearDoneBy ? null : (doneBy ?? this.doneBy),
      doneAt: clearDoneAt ? null : (doneAt ?? this.doneAt),
      position: position ?? this.position,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
