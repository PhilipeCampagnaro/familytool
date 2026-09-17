import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/attachment.dart';
import '../../models/event_link.dart';
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

  /// Lists somebody outside the household can reach — see
  /// [ListRepository.fetchSharedOutIds].
  final Set<String> sharedOutIds;

  const ListSnapshot({
    required this.lists,
    required this.itemsByList,
    required this.guestListIds,
    this.sharedOutIds = const {},
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

  static const _listColumns =
      'id, family_id, name, icon_asset, kind, owner_id, visibility, position, '
      'event_calendar_id, event_uid, event_starts_at, steps, recipe, created_at, updated_at';
  static const _itemColumns =
      'id, list_id, text, sub, unit, icon_asset, link_url, assignee_id, done, done_by, done_at, position, created_by, created_at, updated_at';
  static const _attachmentColumns = 'id, item_id, storage_path, name, is_image, created_at';

  String get _uid {
    final id = AporahSupabase.userId;
    if (id == null) throw StateError(L.s.notSignedIn);
    return id;
  }

  // -------------------------------------------------------------------------
  // Read
  // -------------------------------------------------------------------------

  /// Everything the Listen screen needs, in two waits rather than five.
  /// Unfiltered is the point — see the class doc.
  ///
  /// The lists come first because their ids are what the other three reads are
  /// narrowed to; those three know nothing about each other, so they go
  /// together. Five round trips in a row was most of the time the screen spent
  /// blank, and they were serial only because each was written under the last.
  ///
  /// The attachments are **not** here any more. They are the one part of the
  /// screen nothing else depends on — an article whose photo hasn't arrived yet
  /// still says what to buy — so they load after the articles are on screen
  /// (see [ListNotifier.load]) rather than in front of them.
  Future<ListSnapshot> fetchAll() async {
    final listRows = await _db.from('lists').select(_listColumns).order('position').order('created_at');
    if (listRows.isEmpty) return ListSnapshot.empty;

    final ids = [for (final r in listRows) r['id'] as String];

    // Beside the three below rather than after them: it answers a badge, and
    // nothing else waits on it.
    final sharedOut = fetchSharedOutIds(ids);
    final results = await Future.wait([
      // `list_shares` is readable exactly for the lists that are readable, so
      // this needs no predicate of its own beyond narrowing to what we just
      // read.
      _db.from('list_shares').select('list_id, user_id').inFilter('list_id', ids),
      _db
          .from('list_items')
          .select(_itemColumns)
          .inFilter('list_id', ids)
          .order('position')
          .order('created_at'),
      // Own grants only — `guest_access_select` also returns the guests *on* my
      // household's lists, which are somebody else's grants and would wrongly
      // mark my own lists as foreign.
      _db.from('guest_access').select('resource_id').eq('resource_kind', 'list').eq('user_id', _uid),
    ]);
    final shareRows = results[0];
    final itemRows = results[1];
    final grantRows = results[2];

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
        for (final r in listRows)
          ShoppingList.fromMap(r, sharedWith: sharedWith[r['id'] as String] ?? const []),
      ],
      itemsByList: itemsByList,
      guestListIds: {for (final r in grantRows) r['resource_id'] as String},
      sharedOutIds: await sharedOut,
    );
  }

  /// Which of [listIds] somebody outside the household can reach, or has been
  /// invited to: a guest on it other than me, or a link still open.
  ///
  /// Never throws — it only decides whether a small icon is drawn, and a list
  /// without it is still a list. `share_links_select` shows a member only their
  /// own links (an admin sees all), so a member does not see the icon for an
  /// invitation another member sent until somebody has come in through it.
  Future<Set<String>> fetchSharedOutIds(List<String> listIds) async {
    if (listIds.isEmpty) return const {};
    try {
      final results = await Future.wait([
        _db
            .from('guest_access')
            .select('resource_id')
            .eq('resource_kind', 'list')
            .inFilter('resource_id', listIds)
            .neq('user_id', _uid),
        _db
            .from('share_links')
            .select('resource_id')
            .eq('resource_kind', 'list')
            .inFilter('resource_id', listIds)
            .isFilter('revoked_at', null)
            .or('expires_at.is.null,expires_at.gt.${DateTime.now().toUtc().toIso8601String()}'),
      ]);
      return {
        for (final rows in results)
          for (final r in rows) r['resource_id'] as String,
      };
    } catch (_) {
      return const {};
    }
  }

  /// The files hanging off a screenful of articles, one statement for all of
  /// them.
  ///
  /// `list_item_attachments_select` is `can_read_list` through the item, so this
  /// needs no predicate of its own beyond narrowing to the items just read —
  /// the same arrangement `list_shares` has. Signing the paths is the caller's
  /// job (see `PhotoRepository`); this returns rows, and a row with no signed
  /// URL still names its file.
  Future<Map<String, List<ItemAttachment>>> fetchAttachments(Iterable<String> itemIds) async {
    final ids = itemIds.toList();
    if (ids.isEmpty) return const {};
    final rows = await _db
        .from('list_item_attachments')
        .select(_attachmentColumns)
        .inFilter('item_id', ids)
        .order('created_at');

    final byItem = <String, List<ItemAttachment>>{};
    for (final r in rows) {
      (byItem[r['item_id'] as String] ??= []).add(ItemAttachment.fromMap(r));
    }
    return byItem;
  }

  /// Files an already-uploaded object against its article.
  ///
  /// Object first, row second, always: a row naming an object that isn't there
  /// draws a broken thumbnail for everyone, while an object no row names is a
  /// few kilobytes nobody can reach.
  Future<ItemAttachment> addAttachment({
    required String itemId,
    required String storagePath,
    required String name,
    required bool isImage,
  }) async {
    final row = await _db
        .from('list_item_attachments')
        .insert({
          'item_id': itemId,
          'storage_path': storagePath,
          'name': name,
          'is_image': isImage,
          'created_by': _uid,
        })
        .select(_attachmentColumns)
        .single();
    return ItemAttachment.fromMap(row);
  }

  /// `list_item_attachments_delete` is the uploader's own rows only, so somebody
  /// else's photo comes back as an empty result rather than as a raise.
  Future<void> deleteAttachment(String id) async {
    await _db.from('list_item_attachments').delete().eq('id', id);
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
  /// Hence: **the client brings the id and the row it just built.** There is no
  /// read-back. There used to be one — a second `select` on a fresh snapshot,
  /// which does succeed — and it cost a full round trip on the one action the
  /// user is watching, to fetch `created_at` and `updated_at` that no screen
  /// reads. On a slow mobile connection that trip was seconds, and the list
  /// appeared long enough after the sheet closed that people retapped. Every
  /// column the app draws was already in hand before the insert went out.
  ///
  /// What the read-back really bought was proof that the creator can see what
  /// they made. It never was proof: a `select` that came back empty threw
  /// `PostgrestException` from `.single()` and the caller reported "save
  /// failed" for a row that had landed perfectly well. The insert policy is
  /// what decides whether the write is allowed, and it is checked either way.
  ///
  /// The share rows are a third statement, because supabase-dart cannot open a
  /// transaction. A failed share write leaves a `custom` list with nobody on it,
  /// which is exactly as visible as `private` — the safe direction to fail in.
  Future<ShoppingList> createList({
    required String familyId,
    required String name,
    required ListKind kind,
    String? id,
    String? iconKey,
    ListVisibility visibility = ListVisibility.family,
    Set<String> sharedWith = const {},
    int position = 0,
    EventLink? eventLink,
    List<String> steps = const [],
    String? recipe,
  }) async {
    final listId = id ?? newUuidV4();
    final ownerId = _uid;
    final members = _effectiveShares(visibility, sharedWith, ownerId);
    final draft = ShoppingList(
      id: listId,
      name: name,
      iconKey: iconKey,
      kind: kind,
      familyId: familyId,
      ownerId: ownerId,
      visibility: visibility,
      sharedWith: members.toList(),
      position: position,
      // Only ever on the insert — see [BoardRepository.createTask].
      eventLink: eventLink,
      // Same: written once, with the row, and never by `updateList`.
      steps: steps,
      recipe: recipe,
    );

    await _db.from('lists').insert({...draft.toMap(forInsert: true), 'id': listId});

    if (members.isNotEmpty) await _writeShares(listId, familyId, members);

    return draft;
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
    String? unit,
    String? iconKey,
    String? linkUrl,
    String? assigneeId,
    required int position,
  }) async {
    final draft = ShoppingListItem(
      id: '',
      listId: listId,
      text: text,
      sub: sub,
      unit: unit,
      iconKey: iconKey,
      linkUrl: linkUrl,
      assigneeId: assigneeId,
      createdBy: _uid,
      position: position,
    );
    final row = await _db
        .from('list_items')
        .insert(draft.toMap(forInsert: true))
        .select(_itemColumns)
        .single();
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

  /// The link on its own, or `null` to take it off again.
  ///
  /// Its own statement for the same reason [setUnit] is: the URL is pasted into
  /// a sheet while the name and the count are typed into the row, and an edit
  /// of one must not restate the other. `list_items_link_url_shape` is what
  /// refuses a string that is not an http(s) URL — the client normalises first,
  /// but the column is where that is actually true.
  Future<ShoppingListItem> setLink(String itemId, String? url) async {
    final row = await _db
        .from('list_items')
        .update({'link_url': url})
        .eq('id', itemId)
        .select(_itemColumns)
        .single();
    return ShoppingListItem.fromMap(row);
  }

  /// The unit on its own — the picker's one write. Deliberately not folded into
  /// [editItem]: the unit is picked from a sheet while the name and the count
  /// are typed into the row, and an edit of one must not restate the other.
  Future<ShoppingListItem> setUnit(String itemId, String? unit) async {
    final row = await _db
        .from('list_items')
        .update({'unit': unit})
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
