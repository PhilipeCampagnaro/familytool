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
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// True for the one list that is computed rather than stored. Blocks
  /// [toMap], so "Alle Artikel" cannot be inserted by accident.
  final bool isSummary;

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
      if (forInsert) ...{'family_id': familyId, 'owner_id': ownerId},
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
  final String? sub;

  /// Same key as [ShoppingList.iconKey], same `icon_asset` column.
  final String? iconKey;

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
    this.iconKey,
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
      iconKey: map['icon_asset'] as String?,
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
      'icon_asset': iconKey,
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
    String? iconKey,
    bool clearIconKey = false,
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
      iconKey: clearIconKey ? null : (iconKey ?? this.iconKey),
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
