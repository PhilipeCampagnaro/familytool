import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/shopping_list.dart';
import '../../services/supabase.dart';
import '../../l10n/l10n.dart';

final _random = Random.secure();

/// An RFC 4122 v4 uuid, generated on the device.
///
/// Needed because a container row (`lists`, and the same will hold for `boxes`,
/// `tasks` and `calendars`) **cannot be inserted with `RETURNING`** — see
/// [ListRepository.createList]. Without a returned row there is no server id to
/// hang the follow-up statements on, so the client brings its own. Nothing
/// about that is privileged: `id` has no policy attached, `gen_random_uuid()`
/// is only a column default, and a collision would be a primary-key error.
///
/// Hand-rolled rather than pulling in `package:uuid` for eleven lines.
String newUuidV4() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
  final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// One round trip's worth of Listen: every list the signed-in user may see,
/// their articles, and which of those lists reached them through an external
/// share rather than through their own household.
class ListSnapshot {
  final List<ShoppingList> lists;
  final Map<String, List<ShoppingListItem>> itemsByList;

  /// Lists held via a `guest_access` grant. Not a permission the client
  /// enforces — RLS already did — but the app has to *render* differently for
  /// them: no pooled "Alle Artikel", no internal member picker (see
  /// docs/backend.md, "What the guest can never reach").
  final Set<String> guestListIds;

  const ListSnapshot({
    required this.lists,
    required this.itemsByList,
    required this.guestListIds,
  });

  static const empty = ListSnapshot(lists: [], itemsByList: {}, guestListIds: {});
}

/// The only file in the app that knows Listen is stored in PostgREST.
///
/// Two rules it exists to keep in one place:
///
/// 1. **No `family_id` filter, ever.** `lists_select` is `can_read_list(id)`,
///    which already answers "mine, my household's, shared with me, or granted
///    to me as a guest". Adding `.eq('family_id', …)` here would silently drop
///    the guest branch — the one case where a readable row lives in someone
///    else's household.
/// 2. Column names live here and nowhere else. The models' `fromMap`/`toMap`
///    are the translation layer (`icon_asset` ↔ `iconKey`); every screen and
///    notifier above this line speaks Dart.
class ListRepository {
  ListRepository([SupabaseClient? client]) : _db = client ?? AporahSupabase.client;

  final SupabaseClient _db;

  static const _listColumns = 'id, family_id, name, icon_asset, kind, owner_id, visibility, position, created_at, updated_at';
  static const _itemColumns =
      'id, list_id, text, sub, icon_asset, assignee_id, done, done_by, done_at, position, created_by, created_at, updated_at';

  String get _uid {
    final id = AporahSupabase.userId;
    if (id == null) throw StateError(L.s.notSignedIn);
    return id;
  }

  // -------------------------------------------------------------------------
  // Read
  // -------------------------------------------------------------------------

  /// Everything the Listen screen needs, in four unfiltered selects. Unfiltered
  /// is the point — see the class doc.
  Future<ListSnapshot> fetchAll() async {
    final listRows = await _db.from('lists').select(_listColumns).order('position').order('created_at');
    if (listRows.isEmpty) return ListSnapshot.empty;

    final ids = [for (final r in listRows) r['id'] as String];

    // `list_shares` is readable exactly for the lists that are readable, so
    // this needs no predicate of its own beyond narrowing to what we just read.
    final shareRows = await _db.from('list_shares').select('list_id, user_id').inFilter('list_id', ids);

    final itemRows = await _db
        .from('list_items')
        .select(_itemColumns)
        .inFilter('list_id', ids)
        .order('position')
        .order('created_at');

    // Own grants only — `guest_access_select` also returns the guests *on* my
    // household's lists, which are somebody else's grants and would wrongly
    // mark my own lists as foreign.
    final grantRows = await _db
        .from('guest_access')
        .select('resource_id')
        .eq('resource_kind', 'list')
        .eq('user_id', _uid);

    final sharedWith = <String, List<String>>{};
    for (final r in shareRows) {
      (sharedWith[r['list_id'] as String] ??= []).add(r['user_id'] as String);
    }

    final itemsByList = <String, List<ShoppingListItem>>{for (final id in ids) id: []};
    for (final r in itemRows) {
      final item = ShoppingListItem.fromMap(r);
      (itemsByList[item.listId] ??= []).add(item);
    }

    return ListSnapshot(
      lists: [
        for (final r in listRows) ShoppingList.fromMap(r, sharedWith: sharedWith[r['id'] as String] ?? const []),
      ],
      itemsByList: itemsByList,
      guestListIds: {for (final r in grantRows) r['resource_id'] as String},
    );
  }

  // -------------------------------------------------------------------------
  // Lists
  // -------------------------------------------------------------------------

  /// Files a new list, then its `list_shares` rows if it is `custom`.
  ///
  /// **The insert deliberately carries no `.select()`.** `lists_select` is
  /// `can_read_list(id)`, a `stable security definer` function that queries
  /// `public.lists` itself — and a stable function runs against the snapshot the
  /// statement started with, in which the row being inserted does not exist yet.
  /// So `insert … returning` fails the SELECT policy and Postgres reports
  /// `42501 new row violates row-level security policy for table "lists"`, which
  /// reads like a permission problem and is really a visibility one. Verified
  /// against the live database; the same holds for `boxes`, `tasks` and
  /// `calendars`, so the repositories that follow this one need the same shape.
  ///
  /// Hence: client-side id, insert, then read the row back in a *separate*
  /// statement — which has a fresh snapshot and succeeds. The read-back is not
  /// bookkeeping either; it is what proves the creator can actually see what
  /// they just made, including after a `private` or `custom` choice.
  ///
  /// The share rows are a third statement, because supabase-dart cannot open a
  /// transaction. A failed share write leaves a `custom` list with nobody on it,
  /// which is exactly as visible as `private` — the safe direction to fail in.
  Future<ShoppingList> createList({
    required String familyId,
    required String name,
    required ListKind kind,
    String? iconKey,
    ListVisibility visibility = ListVisibility.family,
    Set<String> sharedWith = const {},
    int position = 0,
  }) async {
    final id = newUuidV4();
    final ownerId = _uid;
    final draft = ShoppingList(
      id: id,
      name: name,
      iconKey: iconKey,
      kind: kind,
      familyId: familyId,
      ownerId: ownerId,
      visibility: visibility,
      position: position,
    );

    await _db.from('lists').insert({...draft.toMap(forInsert: true), 'id': id});

    final members = _effectiveShares(visibility, sharedWith, ownerId);
    if (members.isNotEmpty) await _writeShares(id, familyId, members);

    final row = await _db.from('lists').select(_listColumns).eq('id', id).single();
    return ShoppingList.fromMap(row, sharedWith: members.toList());
  }

  /// Renames / re-symbols / re-kinds a list, and rewrites its share rows.
  ///
  /// `UPDATE … RETURNING` is fine here where the insert's wasn't: the row
  /// already existed when the statement's snapshot was taken, so
  /// `can_read_list(id)` can see it.
  ///
  /// `visibility` is only sent when it actually changed: the update policy lets
  /// any household member write a family-visible list, but
  /// `enforce_container_ownership` rejects a `visibility` change from anyone but
  /// the owner — including a no-op one, which Postgres still sees as an
  /// assignment only when the value differs (`is distinct from`), so sending an
  /// unchanged value is harmless but sending it needlessly isn't worth the risk.
  Future<ShoppingList> updateList(
    ShoppingList list, {
    required String name,
    required ListKind kind,
    String? iconKey,
    ListVisibility? visibility,
    Set<String>? sharedWith,
  }) async {
    final patch = <String, dynamic>{
      'name': name,
      'icon_asset': iconKey,
      'kind': kind.name,
      if (visibility != null && visibility != list.visibility) 'visibility': visibility.name,
    };

    final row = await _db.from('lists').update(patch).eq('id', list.id).select(_listColumns).single();
    final saved = ShoppingList.fromMap(row);

    // Shares are the owner's to change (`list_shares_insert`/`_delete` check
    // `owner_id`), so a member editing someone else's list leaves them alone.
    if (sharedWith == null || saved.ownerId != AporahSupabase.userId) {
      return saved.copyWith(sharedWith: list.sharedWith);
    }

    final members = _effectiveShares(saved.visibility, sharedWith, saved.ownerId);
    await _db.from('list_shares').delete().eq('list_id', saved.id);
    if (members.isNotEmpty) await _writeShares(saved.id, saved.familyId, members);

    return saved.copyWith(sharedWith: members.toList());
  }

  Future<void> deleteList(String id) async {
    await _db.from('lists').delete().eq('id', id);
  }

  /// `custom` is the only visibility that has a member list; `family` and
  /// `private` must not leave stale rows behind, or flipping back to `custom`
  /// would silently restore an old audience. The owner is implicit and never
  /// written — the composite FK would accept it, but a row saying "shared with
  /// myself" is noise.
  Set<String> _effectiveShares(ListVisibility visibility, Set<String> sharedWith, String ownerId) {
    if (visibility != ListVisibility.custom) return const {};
    return {...sharedWith}..remove(ownerId);
  }

  Future<void> _writeShares(String listId, String familyId, Set<String> userIds) async {
    await _db.from('list_shares').insert([
      for (final userId in userIds) {'list_id': listId, 'family_id': familyId, 'user_id': userId},
    ]);
  }

  // -------------------------------------------------------------------------
  // Items
  // -------------------------------------------------------------------------

  /// Newest article at the top, matching where the row appears in the UI. The
  /// `position` is one below the lowest in the list rather than a renumbering of
  /// every sibling — a single insert should stay a single insert.
  Future<ShoppingListItem> addItem({
    required String listId,
    required String text,
    String? sub,
    String? iconKey,
    String? assigneeId,
    required int position,
  }) async {
    final draft = ShoppingListItem(
      id: '',
      listId: listId,
      text: text,
      sub: sub,
      iconKey: iconKey,
      assigneeId: assigneeId,
      createdBy: _uid,
      position: position,
    );
    final row = await _db.from('list_items').insert(draft.toMap(forInsert: true)).select(_itemColumns).single();
    return ShoppingListItem.fromMap(row);
  }

  /// The editable half of an article: its name, the quantity line and the
  /// picture that follows from the name. Nothing that identifies it.
  Future<ShoppingListItem> editItem(
    String itemId, {
    required String text,
    String? sub,
    String? iconKey,
  }) async {
    final row = await _db
        .from('list_items')
        .update({'text': text, 'sub': sub, 'icon_asset': iconKey})
        .eq('id', itemId)
        .select(_itemColumns)
        .single();
    return ShoppingListItem.fromMap(row);
  }

  Future<void> deleteItem(String itemId) async {
    await _db.from('list_items').delete().eq('id', itemId);
  }

  /// Ticking off writes all three columns together: who ticked it and when are
  /// what `can_see_profile` renders on a shared list, and a `done` without them
  /// is a row that cannot say who did the shopping.
  Future<ShoppingListItem> setDone(String itemId, bool done) async {
    final row = await _db
        .from('list_items')
        .update({
          'done': done,
          'done_by': done ? _uid : null,
          'done_at': done ? DateTime.now().toUtc().toIso8601String() : null,
        })
        .eq('id', itemId)
        .select(_itemColumns)
        .single();
    return ShoppingListItem.fromMap(row);
  }

  /// "Erledigte löschen". One statement for the whole batch — but
  /// `list_items_delete` still applies per row, so somebody else's article
  /// survives a clear-out run by a non-admin. Returns the ids that actually went
  /// away, so the caller removes those and puts the rest back rather than
  /// showing a deletion that never happened.
  Future<Set<String>> clearDone(Iterable<String> itemIds) async {
    final ids = itemIds.toList();
    if (ids.isEmpty) return const {};
    final rows = await _db.from('list_items').delete().inFilter('id', ids).select('id');
    return {for (final r in rows) r['id'] as String};
  }
}
