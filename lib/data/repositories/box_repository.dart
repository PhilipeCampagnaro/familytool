import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/box_item.dart';
import '../../models/visibility.dart';
import '../../services/supabase.dart';
import '../../models/who.dart';
import 'list_repository.dart' show newUuidV4;
import 'shared_out.dart';
import '../../l10n/l10n.dart';

/// One round trip's worth of Boxen: every box the signed-in user may see, and
/// what is in them.
class BoxSnapshot {
  final List<StorageBox> boxes;
  final Map<String, List<BoxItem>> itemsByBox;

  /// Boxes held through an external share link rather than through the
  /// household — the same distinction `ListSnapshot.guestListIds` draws, and it
  /// matters for the same reason: a guest has no member picker to offer.
  final Set<String> guestBoxIds;

  /// Boxes somebody outside the household can reach or has been invited to, and
  /// the outsiders themselves — the twins of `ListSnapshot`'s two fields, read
  /// by the same [sharedOutFor].
  final Set<String> sharedOutIds;
  final Map<String, List<FamilyMember>> guestsByBox;

  const BoxSnapshot({
    required this.boxes,
    required this.itemsByBox,
    required this.guestBoxIds,
    this.sharedOutIds = const {},
    this.guestsByBox = const {},
  });

  static const empty = BoxSnapshot(boxes: [], itemsByBox: {}, guestBoxIds: {});
}

/// The only file in the app that knows Boxen are stored in PostgREST.
///
/// Deliberately the same shape as `ListRepository`, down to the two rules it
/// exists to keep in one place:
///
/// 1. **No `family_id` filter, ever.** `boxes_select` is `can_read_box(id)`,
///    which already answers "mine, my household's, shared with me, or granted to
///    me as a guest". Adding `.eq('family_id', …)` would silently drop the guest
///    branch.
/// 2. Column names live here and nowhere else — the models' `fromMap`/`toMap`
///    are the translation layer (`icon_asset` ↔ `iconKey`).
class BoxRepository {
  BoxRepository([SupabaseClient? client]) : _db = client ?? AporahSupabase.client;

  final SupabaseClient _db;

  static const _boxColumns =
      'id, family_id, name, place, tone, icon_asset, photo_path, owner_id, visibility, position, created_at, updated_at';
  static const _itemColumns =
      'id, box_id, name, size, qty, note, icon_asset, photo_path, position, created_by, created_at, updated_at';

  String get _uid {
    final id = AporahSupabase.userId;
    if (id == null) throw StateError(L.s.notSignedIn);
    return id;
  }

  // -------------------------------------------------------------------------
  // Read
  // -------------------------------------------------------------------------

  /// The shelf, in two waits rather than four.
  ///
  /// The boxes come first because their ids are what the rest is narrowed to;
  /// the three reads after them know nothing about each other, so they go
  /// together rather than one behind the next.
  Future<BoxSnapshot> fetchAll() async {
    final boxRows = await _db.from('boxes').select(_boxColumns).order('position', ascending: true).order('created_at', ascending: true);
    if (boxRows.isEmpty) return BoxSnapshot.empty;

    final ids = [for (final r in boxRows) r['id'] as String];

    // Beside the three below rather than after them: it answers a badge, and
    // nothing else waits on it.
    final sharedOut = fetchSharedOut(ids);
    final results = await Future.wait([
      _db.from('box_shares').select('box_id, user_id').inFilter('box_id', ids),
      _db
          .from('box_items')
          .select(_itemColumns)
          .inFilter('box_id', ids)
          .order('position', ascending: true)
          .order('created_at', ascending: true),
      // Own grants only — `guest_access_select` also returns the guests *on* my
      // household's boxes, which are somebody else's grants.
      _db.from('guest_access').select('resource_id').eq('resource_kind', 'box').eq('user_id', _uid),
    ]);
    final shareRows = results[0];
    final itemRows = results[1];
    final grantRows = results[2];

    final sharedWith = <String, List<String>>{};
    for (final r in shareRows) {
      (sharedWith[r['box_id'] as String] ??= []).add(r['user_id'] as String);
    }

    final itemsByBox = <String, List<BoxItem>>{for (final id in ids) id: []};
    for (final r in itemRows) {
      final item = BoxItem.fromMap(r);
      (itemsByBox[item.boxId] ??= []).add(item);
    }

    return BoxSnapshot(
      boxes: [
        for (final r in boxRows) StorageBox.fromMap(r, sharedWith: sharedWith[r['id'] as String] ?? const []),
      ],
      itemsByBox: itemsByBox,
      guestBoxIds: {for (final r in grantRows) r['resource_id'] as String},
      sharedOutIds: (await sharedOut).ids,
      guestsByBox: (await sharedOut).guests,
    );
  }

  /// Which of [boxIds] somebody outside the household holds, and who they are —
  /// [sharedOutFor] for `'box'`. Listen calls the same function with `'list'`.
  Future<SharedOut> fetchSharedOut(List<String> boxIds) =>
      sharedOutFor(_db, kind: 'box', resourceIds: boxIds, uid: _uid);

  // -------------------------------------------------------------------------
  // Boxes
  // -------------------------------------------------------------------------

  /// Files a new box, then its `box_shares` rows if it is `custom`.
  ///
  /// **The insert carries no `.select()`**, for the reason spelled out on
  /// [ListRepository.createList]: `boxes_select` is a `stable security definer`
  /// function that reads `public.boxes`, so it runs against the statement's
  /// starting snapshot — in which the row being inserted does not exist — and
  /// `insert … returning` comes back as `42501 new row violates row-level
  /// security policy`, a visibility problem wearing a permission problem's
  /// error. Hence the client-side id — and, as there, no read-back: the draft
  /// already holds every column the shelf draws.
  Future<StorageBox> createBox({
    required String familyId,
    required String name,
    String? id,
    String place = '',
    String? iconKey,
    ItemVisibility visibility = ItemVisibility.family,
    Set<String> sharedWith = const {},
    int position = 0,
  }) async {
    final boxId = id ?? newUuidV4();
    final ownerId = _uid;
    final members = _effectiveShares(visibility, sharedWith, ownerId);
    final draft = StorageBox(
      id: boxId,
      name: name,
      place: place,
      iconKey: iconKey,
      familyId: familyId,
      ownerId: ownerId,
      visibility: visibility,
      sharedWith: members.toList(),
      position: position,
    );

    await _db.from('boxes').insert({...draft.toMap(forInsert: true), 'id': boxId});

    if (members.isNotEmpty) await _writeShares(boxId, familyId, members);

    return draft;
  }

  /// Renames / re-symbols / moves a box, and rewrites its share rows.
  ///
  /// `UPDATE … RETURNING` is fine here where the insert's wasn't: the row
  /// already existed when the statement's snapshot was taken.
  Future<StorageBox> updateBox(
    StorageBox box, {
    required String name,
    required String place,
    String? iconKey,
    ItemVisibility? visibility,
    Set<String>? sharedWith,
  }) async {
    final patch = <String, dynamic>{
      'name': name,
      'place': place.isEmpty ? null : place,
      'icon_asset': iconKey,
      if (visibility != null && visibility != box.visibility) 'visibility': visibility.name,
    };

    final row = await _db.from('boxes').update(patch).eq('id', box.id).select(_boxColumns).single();
    final saved = StorageBox.fromMap(row);

    // Shares are the owner's to change, so a member editing someone else's box
    // leaves them alone.
    if (sharedWith == null || saved.ownerId != AporahSupabase.userId) {
      return saved.copyWith(sharedWith: box.sharedWith);
    }

    final members = _effectiveShares(saved.visibility, sharedWith, saved.ownerId);
    await _db.from('box_shares').delete().eq('box_id', saved.id);
    if (members.isNotEmpty) await _writeShares(saved.id, saved.familyId, members);

    return saved.copyWith(sharedWith: members.toList());
  }

  /// Points a box at a picture, or takes it away with a null.
  ///
  /// Its own statement rather than a field on [updateBox]: a photo is picked
  /// and uploaded when the user taps it, not when the sheet is saved, and the
  /// upload has to have landed before the column may name it. Bundling the two
  /// would mean a `photo_path` pointing at an object that isn't there yet.
  Future<StorageBox> setPhoto(String boxId, String? path) async {
    final row = await _db
        .from('boxes')
        .update({'photo_path': path})
        .eq('id', boxId)
        .select(_boxColumns)
        .single();
    return StorageBox.fromMap(row);
  }

  Future<void> deleteBox(String id) async {
    await _db.from('boxes').delete().eq('id', id);
  }

  /// `custom` is the only visibility with a member list; the others must not
  /// leave stale rows behind, or flipping back to `custom` would silently
  /// restore an old audience.
  Set<String> _effectiveShares(ItemVisibility visibility, Set<String> sharedWith, String ownerId) {
    if (visibility != ItemVisibility.custom) return const {};
    return {...sharedWith}..remove(ownerId);
  }

  Future<void> _writeShares(String boxId, String familyId, Set<String> userIds) async {
    await _db.from('box_shares').insert([
      for (final userId in userIds) {'box_id': boxId, 'family_id': familyId, 'user_id': userId},
    ]);
  }

  // -------------------------------------------------------------------------
  // Items
  // -------------------------------------------------------------------------

  Future<BoxItem> addItem({
    required String boxId,
    required String name,
    String? size,
    int qty = 1,
    String? note,
    String? iconKey,
    required int position,
  }) async {
    final draft = BoxItem(
      id: '',
      boxId: boxId,
      name: name,
      size: size,
      qty: qty,
      note: note,
      iconKey: iconKey,
      createdBy: _uid,
      position: position,
    );
    final row = await _db
        .from('box_items')
        .insert(draft.toMap(forInsert: true))
        .select(_itemColumns)
        .single();
    return BoxItem.fromMap(row);
  }

  /// Everything the item sheet can change. `size` and `note` are sent as
  /// explicit nulls when emptied — unlike the name, which reads as "left it
  /// alone", those two are optional to begin with, so clearing one has to reach
  /// the column.
  Future<BoxItem> editItem(
    String itemId, {
    required String name,
    String? size,
    int? qty,
    String? note,
    String? iconKey,
  }) async {
    final row = await _db
        .from('box_items')
        .update({'name': name, 'size': size, 'qty': ?qty, 'note': note, 'icon_asset': iconKey})
        .eq('id', itemId)
        .select(_itemColumns)
        .single();
    return BoxItem.fromMap(row);
  }

  /// The item side of [setPhoto], and the same reasoning.
  Future<BoxItem> setItemPhoto(String itemId, String? path) async {
    final row = await _db
        .from('box_items')
        .update({'photo_path': path})
        .eq('id', itemId)
        .select(_itemColumns)
        .single();
    return BoxItem.fromMap(row);
  }

  Future<void> deleteItem(String itemId) async {
    await _db.from('box_items').delete().eq('id', itemId);
  }
}
