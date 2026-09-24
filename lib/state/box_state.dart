import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/icon_suggestions.dart';
import '../data/repositories/box_repository.dart';
import '../data/repositories/list_repository.dart' show newUuidV4;
import '../data/repositories/photo_repository.dart';
import '../models/box_item.dart';
import '../models/visibility.dart';
import '../models/who.dart';
import '../services/supabase.dart';
import 'auth_state.dart';
import 'family_state.dart';
import '../l10n/l10n.dart';
import 'realtime_state.dart';

/// Everything the Boxen screen renders, and nothing it doesn't.
///
/// The old overlay maps (`created`, `extra`, `removed`, `edited`) are gone.
/// They existed only because the contents used to be `const` seed data that
/// could not be changed in place — deleting was filtering, editing was
/// shadowing. Over a server they would be a second source of truth on top of
/// the first, and the first one wins after every reload.
class BoxScreenState {
  final bool isDetail;
  final String openId;

  /// Every box, as RLS handed it over: my household's, plus anything shared
  /// with me. Never filtered by `family_id` here; see `BoxRepository`.
  final List<StorageBox> boxes;

  final Map<String, List<BoxItem>> itemsByBox;

  /// Boxes that reached this account through an external share link.
  final Set<String> guestBoxIds;

  /// Boxes somebody outside the household can reach or has been invited to —
  /// what puts the audience stack on the row and in the header, and what takes
  /// the "Für wen?" picker away while it is true.
  final Set<String> sharedOutIds;

  /// The outsiders themselves, per box. Read with the boxes rather than per row
  /// — see [BoxRepository.fetchSharedOut].
  final Map<String, List<FamilyMember>> guestsByBox;

  /// `photo_path` → a signed URL for it, for every picture on screen.
  ///
  /// Keyed by path rather than held on the model because that is what the
  /// signing is keyed by, and because a box and one of its items can perfectly
  /// well be photographed twice into the same map without either of them
  /// caring. Missing means "no picture, or signing failed" — both fall back to
  /// the symbol, which is what a box without a photo already shows.
  final Map<String, String> photoUrls;

  /// The create/edit sheet's draft "Für wen?" answer, in the two fields the
  /// database actually has. Replaces the old single `who` string, which
  /// conflated assignment with visibility.
  final ItemVisibility newVisibility;
  final Set<String> newSharedWith;

  /// True until the first load has answered, so the screen can show the panel
  /// empty rather than "Noch keine Box angelegt" at somebody with twelve.
  final bool loading;

  /// German, and safe to render verbatim.
  final String? error;

  const BoxScreenState({
    this.isDetail = false,
    // No box is open until one is tapped; there are none to point at.
    this.openId = '',
    this.boxes = const [],
    this.itemsByBox = const {},
    this.guestBoxIds = const {},
    this.sharedOutIds = const {},
    this.guestsByBox = const {},
    this.photoUrls = const {},
    this.newVisibility = ItemVisibility.family,
    this.newSharedWith = const {},
    this.loading = true,
    this.error,
  });

  bool get isGuest => guestBoxIds.isNotEmpty;

  BoxScreenState copyWith({
    bool? isDetail,
    String? openId,
    List<StorageBox>? boxes,
    Map<String, List<BoxItem>>? itemsByBox,
    Set<String>? guestBoxIds,
    Set<String>? sharedOutIds,
    Map<String, List<FamilyMember>>? guestsByBox,
    Map<String, String>? photoUrls,
    ItemVisibility? newVisibility,
    Set<String>? newSharedWith,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return BoxScreenState(
      isDetail: isDetail ?? this.isDetail,
      openId: openId ?? this.openId,
      boxes: boxes ?? this.boxes,
      itemsByBox: itemsByBox ?? this.itemsByBox,
      guestBoxIds: guestBoxIds ?? this.guestBoxIds,
      sharedOutIds: sharedOutIds ?? this.sharedOutIds,
      guestsByBox: guestsByBox ?? this.guestsByBox,
      photoUrls: photoUrls ?? this.photoUrls,
      newVisibility: newVisibility ?? this.newVisibility,
      newSharedWith: newSharedWith ?? this.newSharedWith,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  StorageBox? boxById(String id) {
    for (final b in boxes) {
      if (b.id == id) return b;
    }
    return null;
  }

  List<BoxItem> itemsFor(String id) => itemsByBox[id] ?? const [];

  /// The signed URL for a stored picture, or null while there isn't one to
  /// draw. Callers pass [StorageBox.photoPath] / [BoxItem.photoPath] straight
  /// in, so neither of them has to know a map is involved.
  String? photoUrl(String? path) => path == null ? null : photoUrls[path];

  int get totalItems => boxes.fold(0, (n, b) => n + itemsFor(b.id).length);
}

/// A deleted box and its contents, held just long enough for the confirmation
/// chip's "Rückgängig" — the Box side of `DeletedList`, and kept off the state
/// class for the same reason.
class DeletedBox {
  final StorageBox box;
  final List<BoxItem> items;

  /// Where it sat in the overview, so undo puts it back rather than at the end.
  final int index;

  const DeletedBox({required this.box, required this.items, required this.index});
}

/// One deleted item, held for as long as its chip is up.
///
/// The item side of [DeletedBox], and much cheaper: the box it sat in is still
/// there, so there is no container to re-create and no picture to copy — only
/// the row and where on the shelf it was.
class DeletedBoxItem {
  final BoxItem item;

  /// Its slot among its siblings, so undo puts it back where it was rather than
  /// at the end. Its stored `position` says the same thing to the server; this
  /// is what keeps the screen from re-ordering itself for a frame.
  final int index;

  const DeletedBoxItem({required this.item, required this.index});
}

class BoxNotifier extends StateNotifier<BoxScreenState> {
  BoxNotifier(this._repo, this._photos, this._userId, this._familyId) : super(const BoxScreenState()) {
    if (_userId != null) load();
  }

  final BoxRepository _repo;
  final PhotoRepository _photos;
  final String? _userId;
  final String? _familyId;

  /// Client-side ids for rows that exist on screen but not yet on the server.
  static const _tempPrefix = 'tmp:';
  static bool _isTemp(String id) => id.startsWith(_tempPrefix);
  static String _tempId() => '$_tempPrefix${DateTime.now().microsecondsSinceEpoch}';

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Re-reads which boxes are shared outside the household, after the share
  /// sheet sent an invitation, dropped a guest or revoked a link. The twin of
  /// `ListNotifier.refreshSharedOut`, and the reason the lock on "Für wen?"
  /// lifts on the same tap that removes the last guest.
  Future<void> refreshSharedOut() async {
    final ids = [for (final b in state.boxes) b.id];
    final shared = await _repo.fetchSharedOut(ids);
    if (mounted) state = state.copyWith(sharedOutIds: shared.ids, guestsByBox: shared.guests);
  }

  Future<void> load() async {
    if (_userId == null) {
      state = state.copyWith(loading: false);
      return;
    }
    state = state.copyWith(loading: true, clearError: true);
    try {
      final snapshot = await _repo.fetchAll();
      if (!mounted) return;
      // A box can vanish between two launches (deleted on another device, or a
      // share revoked) while its detail view is the one being restored.
      final open = snapshot.boxes.any((b) => b.id == state.openId);
      state = state.copyWith(
        boxes: snapshot.boxes,
        itemsByBox: snapshot.itemsByBox,
        guestBoxIds: snapshot.guestBoxIds,
        sharedOutIds: snapshot.sharedOutIds,
        guestsByBox: snapshot.guestsByBox,
        loading: false,
        openId: open ? state.openId : '',
        isDetail: open && state.isDetail,
      );
      // After the rows, not with them: a signing round trip must not hold the
      // shelf back, and a box whose URL hasn't arrived yet simply shows its
      // symbol for a moment — the same thing it shows for good if it has no
      // picture at all.
      await _signVisiblePhotos(snapshot);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: L.s.boxesLoadFailed);
    }
  }

  /// Signs every `photo_path` in one round trip and folds the result into the
  /// state. Never throws: a failure here costs thumbnails, not the screen.
  Future<void> _signVisiblePhotos(BoxSnapshot snapshot) async {
    final paths = <String>[
      for (final box in snapshot.boxes) ?box.photoPath,
      for (final items in snapshot.itemsByBox.values)
        for (final item in items) ?item.photoPath,
    ];
    if (paths.isEmpty) return;
    final urls = await _photos.signUrls(PhotoRepository.boxBucket, paths);
    if (!mounted || urls.isEmpty) return;
    state = state.copyWith(photoUrls: {...state.photoUrls, ...urls});
  }

  void clearError() => state = state.copyWith(clearError: true);

  void _fail(String message) {
    if (mounted) state = state.copyWith(error: message);
  }

  // ---------------------------------------------------------------------------
  // Navigation and sheet drafts
  // ---------------------------------------------------------------------------

  void open(String id) => state = state.copyWith(isDetail: true, openId: id);

  void back() => state = state.copyWith(isDetail: false);

  /// The sheet's "Für wen?" answer. `family` and `private` carry no member
  /// list; `custom` is exactly the case that does.
  void setVisibility(ItemVisibility visibility, Set<String> sharedWith) {
    state = state.copyWith(
      newVisibility: visibility,
      newSharedWith: visibility == ItemVisibility.custom ? sharedWith : const {},
    );
  }

  /// Opens the sheet on a box's own visibility, or on the default for a new one.
  void primeVisibility(StorageBox? box) {
    state = state.copyWith(
      newVisibility: box?.visibility ?? ItemVisibility.family,
      newSharedWith: {...?box?.sharedWith},
    );
  }

  // ---------------------------------------------------------------------------
  // Boxes
  // ---------------------------------------------------------------------------

  /// Files a new box. Without an explicit [iconKey] the name picks its own
  /// symbol — "Keller" a warehouse, "Weihnachtsdeko" a fir, "Werkzeug" a
  /// hammer — so a shelf of boxes is scannable by picture.
  ///
  /// On screen first and on the server after, under the **real** id — the same
  /// trade `list_state.dart` explains at length. A box is a container the very
  /// next tap navigates into, but the id is minted here rather than by the
  /// server (`insert … returning` cannot pass the SELECT policy), so an item
  /// typed straight away already has a `box_id` that is about to exist.
  ///
  /// True only when the row really landed on the server — the screen's
  /// confirmation chip hangs off that, exactly as it does in `list_state.dart`,
  /// and a failed write takes the optimistic row back off.
  Future<bool> createBox({required String name, required String place, String? iconKey, File? photo}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    final familyId = _familyId;
    if (familyId == null) {
      _fail(L.s.householdNotLoaded);
      return false;
    }

    final id = newUuidV4();
    final icon = iconKey ?? suggestIcon(trimmed, subject: IconSubject.box)?.key;
    final visibility = state.newVisibility;
    final sharedWith = {...state.newSharedWith};
    final optimistic = StorageBox(
      id: id,
      name: trimmed,
      place: place.trim(),
      iconKey: icon,
      familyId: familyId,
      ownerId: _userId ?? '',
      visibility: visibility,
      // `family` and `private` have no member list — see `list_state.dart`.
      sharedWith: visibility == ItemVisibility.custom ? sharedWith.toList() : const [],
      position: state.boxes.length,
    );
    state = state.copyWith(
      boxes: [...state.boxes, optimistic],
      itemsByBox: {...state.itemsByBox, id: const []},
    );

    try {
      final saved = await _repo.createBox(
        id: id,
        familyId: familyId,
        name: trimmed,
        place: place.trim(),
        iconKey: icon,
        visibility: visibility,
        sharedWith: sharedWith,
        position: optimistic.position,
      );
      if (!mounted) return false;
      // Appended rather than replaced when it is gone — see `list_state.dart`:
      // a [load] that finished mid-flight cannot see the row being inserted, so
      // it sweeps the optimistic one away.
      final present = state.boxes.any((b) => b.id == id);
      state = state.copyWith(
        boxes: present ? [for (final b in state.boxes) b.id == id ? saved : b] : [...state.boxes, saved],
        itemsByBox: {...state.itemsByBox, id: state.itemsByBox[id] ?? const []},
      );
      // Only now: the object is filed under the box's id and the storage policy
      // asks whether that box may be written, so there has to *be* one first.
      // A picture that fails to upload leaves a created box behind rather than
      // failing the save — the box is the thing the user asked for.
      if (photo != null) await setBoxPhoto(saved.id, photo);
      return true;
    } catch (_) {
      if (!mounted) return false;
      final items = Map<String, List<BoxItem>>.from(state.itemsByBox)..remove(id);
      state = state.copyWith(
        boxes: state.boxes.where((b) => b.id != id).toList(),
        itemsByBox: items,
        // The user may already be inside the box that failed to land; putting
        // them back on the shelf beats a detail view of nothing.
        isDetail: state.openId == id ? false : state.isDetail,
        openId: state.openId == id ? '' : state.openId,
      );
      _fail(L.s.boxSaveFailed);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Pictures
  //
  // Always written straight away rather than on the sheet's save, and for the
  // same reason the profile picture is: the upload has to have landed before a
  // column may name the object, and a user who has just watched their photo
  // appear in the row does not expect a Sichern to be what keeps it.
  // ---------------------------------------------------------------------------

  /// Puts [file] up as the box's picture and points the row at it.
  ///
  /// The object it replaces is deleted afterwards, never before: a failed
  /// upload that had already removed the old picture costs the user the only
  /// copy they had.
  Future<bool> setBoxPhoto(String boxId, File file) async {
    final box = state.boxById(boxId);
    if (box == null) return false;
    final previous = box.photoPath;

    try {
      final path = await _photos.upload(bucket: PhotoRepository.boxBucket, containerId: boxId, file: file);
      final saved = await _repo.setPhoto(boxId, path);
      final urls = await _photos.signUrls(PhotoRepository.boxBucket, [path]);
      if (!mounted) return false;
      // `setPhoto` reads the row back without its share rows — the same reason
      // `updateBox` carries them over by hand.
      state = state.copyWith(
        boxes: [for (final b in state.boxes) b.id == boxId ? saved.copyWith(sharedWith: box.sharedWith) : b],
        photoUrls: {...state.photoUrls, ...urls},
      );
      if (previous != null && previous != path) {
        await _photos.remove(PhotoRepository.boxBucket, [previous]);
      }
      return true;
    } catch (_) {
      _fail(L.s.photoUploadFailed);
      return false;
    }
  }

  /// Takes the box's picture away, back to the symbol its name chose.
  Future<void> removeBoxPhoto(String boxId) async {
    final box = state.boxById(boxId);
    final previous = box?.photoPath;
    if (box == null || previous == null) return;

    try {
      final saved = await _repo.setPhoto(boxId, null);
      if (!mounted) return;
      state = state.copyWith(
        boxes: [for (final b in state.boxes) b.id == boxId ? saved.copyWith(sharedWith: box.sharedWith) : b],
      );
      // The row no longer points at it; the object is just litter.
      await _photos.remove(PhotoRepository.boxBucket, [previous]);
    } catch (_) {
      _fail(L.s.photoRemoveFailed);
    }
  }

  /// The item side of [setBoxPhoto] — and the one this feature was asked for.
  ///
  /// Filed under the **box's** id, not the item's: an item inherits its box's
  /// visibility, so the box is what the storage policy can ask about.
  Future<bool> setItemPhoto(BoxItem item, File file) async {
    if (_isTemp(item.id)) return false; // Still in flight; there is no row to point yet.
    final previous = item.photoPath;

    try {
      final path = await _photos.upload(
        bucket: PhotoRepository.boxBucket,
        containerId: item.boxId,
        file: file,
      );
      final saved = await _repo.setItemPhoto(item.id, path);
      final urls = await _photos.signUrls(PhotoRepository.boxBucket, [path]);
      if (!mounted) return false;
      _patchItem(item.boxId, item.id, (_) => saved);
      state = state.copyWith(photoUrls: {...state.photoUrls, ...urls});
      if (previous != null && previous != path) {
        await _photos.remove(PhotoRepository.boxBucket, [previous]);
      }
      return true;
    } catch (_) {
      _fail(L.s.photoUploadFailed);
      return false;
    }
  }

  Future<void> removeItemPhoto(BoxItem item) async {
    final previous = item.photoPath;
    if (previous == null || _isTemp(item.id)) return;

    try {
      final saved = await _repo.setItemPhoto(item.id, null);
      if (!mounted) return;
      _patchItem(item.boxId, item.id, (_) => saved);
      await _photos.remove(PhotoRepository.boxBucket, [previous]);
    } catch (_) {
      _fail(L.s.photoRemoveFailed);
    }
  }

  /// Writes a renamed / re-symboled / moved box back. An emptied name means
  /// "left it alone"; the icon follows a changed name unless one was picked.
  Future<bool> updateBox(String id, {required String name, required String place, String? iconKey}) async {
    final box = state.boxById(id);
    if (box == null) return false;

    final newName = name.trim().isEmpty ? box.name : name.trim();
    final icon =
        iconKey ?? (newName == box.name ? box.iconKey : suggestIcon(newName, subject: IconSubject.box)?.key);

    try {
      final saved = await _repo.updateBox(
        box,
        name: newName,
        place: place.trim(),
        iconKey: icon,
        visibility: state.newVisibility,
        sharedWith: state.newSharedWith,
      );
      if (!mounted) return false;
      state = state.copyWith(boxes: [for (final b in state.boxes) b.id == id ? saved : b]);
      return true;
    } catch (_) {
      _fail(L.s.changeSaveFailed);
      return false;
    }
  }

  /// Drops a box and its contents, and leaves the detail view if that's the box
  /// it was showing.
  ///
  /// Returns what it took away, or null if the delete didn't land — the chip's
  /// "Rückgängig" hands it straight back to [restoreBox].
  Future<DeletedBox?> deleteBox(String id) async {
    final previous = state;
    final box = state.boxById(id);
    if (box == null) return null;

    final removed = DeletedBox(
      box: box,
      items: state.itemsFor(id),
      index: state.boxes.indexWhere((b) => b.id == id),
    );

    final items = Map<String, List<BoxItem>>.from(state.itemsByBox)..remove(id);
    state = state.copyWith(
      boxes: state.boxes.where((b) => b.id != id).toList(),
      itemsByBox: items,
      isDetail: state.openId == id ? false : state.isDetail,
      openId: state.openId == id ? '' : state.openId,
    );

    try {
      await _repo.deleteBox(id);
      return removed;
    } catch (_) {
      if (!mounted) return null;
      state = previous.copyWith(error: L.s.boxDeleteFailed);
      return null;
    }
  }

  /// Puts a deleted box back, contents and all. Same re-insert-under-new-ids
  /// deal as `ListNotifier.restoreList`, including what that costs a share link.
  Future<bool> restoreBox(DeletedBox deleted) async {
    final familyId = _familyId;
    if (familyId == null) {
      _fail(L.s.householdNotLoaded);
      return false;
    }

    try {
      final box = deleted.box;
      final saved = await _repo.createBox(
        familyId: familyId,
        name: box.name,
        place: box.place,
        iconKey: box.iconKey,
        visibility: box.visibility,
        sharedWith: box.sharedWith.toSet(),
        position: box.position,
      );

      final restored = await Future.wait([for (final item in deleted.items) _restoreItem(saved.id, item)]);
      // The pictures have to be copied, not carried over. Undo re-inserts under
      // a fresh uuid — the old row is gone and its id with it — and every object
      // is filed under the id of the box it belongs to, so the old `photo_path`
      // would name something no box owns any more and the read policy would
      // rightly refuse it. See [PhotoRepository.copyTo].
      final withPhotos = await _restorePhotos(saved, restored, deleted.items, box.photoPath);
      if (!mounted) return false;

      final boxes = [...state.boxes];
      boxes.insert(deleted.index.clamp(0, boxes.length), withPhotos.box);
      state = state.copyWith(
        boxes: boxes,
        itemsByBox: {...state.itemsByBox, saved.id: withPhotos.items},
        photoUrls: {...state.photoUrls, ...withPhotos.urls},
      );
      return true;
    } catch (_) {
      _fail(L.s.boxRestoreFailed);
      return false;
    }
  }

  /// Copies a restored box's pictures under its new id and points the rows at
  /// them, then signs them so the shelf comes back looking as it went.
  ///
  /// Every step is best-effort per picture: one object that has already been
  /// swept up must not turn undo into a failed restore, and a box that comes
  /// back without one photo is a far better outcome than a box that doesn't
  /// come back.
  /// [items] are the rows that were just re-inserted and [originals] the ones
  /// they were copied from, index for index — `Future.wait` keeps the order, and
  /// the new rows are the only place with an id to write to while the old ones
  /// are the only place with a picture to copy.
  Future<({StorageBox box, List<BoxItem> items, Map<String, String> urls})> _restorePhotos(
    StorageBox box,
    List<BoxItem> items,
    List<BoxItem> originals,
    String? boxPhoto,
  ) async {
    Future<String?> copy(String? from) async {
      if (from == null) return null;
      try {
        return await _photos.copyTo(bucket: PhotoRepository.boxBucket, fromPath: from, containerId: box.id);
      } catch (_) {
        return null;
      }
    }

    var restoredBox = box;
    if (await copy(boxPhoto) case final path?) {
      try {
        restoredBox = (await _repo.setPhoto(box.id, path)).copyWith(sharedWith: box.sharedWith);
      } catch (_) {}
    }

    final restoredItems = <BoxItem>[];
    for (final (i, item) in items.indexed) {
      final source = i < originals.length ? originals[i].photoPath : null;
      if (source == null) {
        restoredItems.add(item);
        continue;
      }
      final path = await copy(source);
      if (path == null) {
        restoredItems.add(item);
        continue;
      }
      try {
        restoredItems.add(await _repo.setItemPhoto(item.id, path));
      } catch (_) {
        restoredItems.add(item);
      }
    }

    final paths = <String>[?restoredBox.photoPath, for (final item in restoredItems) ?item.photoPath];
    return (
      box: restoredBox,
      items: restoredItems,
      urls: await _photos.signUrls(PhotoRepository.boxBucket, paths),
    );
  }

  /// One item of a restored box. Two statements, because `addItem` only takes
  /// what the quick-add row can type — Größe, Anzahl and Notiz are the item
  /// sheet's, and dropping them would make undo a lossy copy.
  Future<BoxItem> _restoreItem(String boxId, BoxItem item) async {
    final saved = await _repo.addItem(
      boxId: boxId,
      name: item.name,
      iconKey: item.iconKey,
      position: item.position,
    );
    if (item.size == null && item.note == null && item.qty <= 1) return saved;
    return _repo.editItem(
      saved.id,
      name: item.name,
      size: item.size,
      qty: item.qty,
      note: item.note,
      iconKey: item.iconKey,
    );
  }

  // ---------------------------------------------------------------------------
  // Items
  // ---------------------------------------------------------------------------

  /// Files a typed item under the open box, on screen first and on the server
  /// after. No grocery-first bias here: a box holds a drill far more often than
  /// it holds milk.
  ///
  /// Answers the row as the server stored it, which is what the add row waits
  /// for before it opens the item sheet: the optimistic copy carries a
  /// [_tempId] and [editItem] refuses to write to one, so a sheet opened on it
  /// would save nothing. Null means the item never landed.
  /// Files a new item, with everything its sheet collected.
  ///
  /// [photo] is the picture the user picked while the item did not exist yet,
  /// and it is uploaded *after* the insert for the same reason [createBox]'s is:
  /// the object is filed under the box's id and the storage policy asks whether
  /// that box may be written, but the `photo_path` column belongs to a row that
  /// has to exist first. A picture that fails to upload leaves the item behind
  /// rather than failing the save — the item is what the user asked for.
  Future<BoxItem?> addItem(
    String name, {
    String? iconKey,
    String? size,
    int qty = 1,
    String? note,
    File? photo,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;

    final boxId = state.openId;
    if (boxId.isEmpty) return null;

    final current = state.itemsFor(boxId);
    final position = current.isEmpty ? 0 : current.map((i) => i.position).reduce((a, b) => a > b ? a : b) + 1;
    final icon = iconKey ?? suggestIcon(trimmed)?.key;

    final optimistic = BoxItem(
      id: _tempId(),
      boxId: boxId,
      name: trimmed,
      size: _orNull(size),
      qty: qty,
      note: _orNull(note),
      iconKey: icon,
      createdBy: _userId,
      position: position,
    );
    _putItems(boxId, [...current, optimistic]);

    try {
      final saved = await _repo.addItem(
        boxId: boxId,
        name: trimmed,
        size: _orNull(size),
        qty: qty,
        note: _orNull(note),
        iconKey: icon,
        position: position,
      );
      if (!mounted) return null;
      // Reconcile in place: the row keeps its slot and swaps its id for the real
      // uuid, so an edit landing right after the insert has something to write to.
      _patchItem(boxId, optimistic.id, (_) => saved);
      if (photo != null) await setItemPhoto(saved, photo);
      return saved;
    } catch (_) {
      if (!mounted) return null;
      _removeItemLocally(boxId, optimistic.id);
      _fail(L.s.itemSaveFailed);
      return null;
    }
  }

  /// Writes back what the item sheet changed.
  ///
  /// An emptied *name* means "left it alone" — the same rule the list rows
  /// follow — but an emptied Größe or Notiz does mean "drop it", since both are
  /// optional to begin with. The picture follows a changed name unless one was
  /// picked by hand.
  Future<void> editItem(
    BoxItem item, {
    required String name,
    String? size,
    int? qty,
    String? note,
    String? iconKey,
  }) async {
    if (_isTemp(item.id)) return; // Still in flight; the reconcile would clobber it.

    final newName = name.trim().isEmpty ? item.name : name.trim();
    final newSize = _orNull(size);
    final newNote = _orNull(note);
    final newQty = qty ?? item.qty;
    final icon = iconKey ?? (newName == item.name ? item.iconKey : suggestIcon(newName)?.key);

    if (newName == item.name &&
        newSize == item.size &&
        newNote == item.note &&
        newQty == item.qty &&
        icon == item.iconKey) {
      return;
    }

    _patchItem(
      item.boxId,
      item.id,
      (i) => i.copyWith(
        name: newName,
        size: newSize,
        clearSize: newSize == null,
        qty: newQty,
        note: newNote,
        clearNote: newNote == null,
        iconKey: icon,
        clearIconKey: icon == null,
      ),
    );

    try {
      final saved = await _repo.editItem(
        item.id,
        name: newName,
        size: newSize,
        qty: newQty,
        note: newNote,
        iconKey: icon,
      );
      if (!mounted) return;
      _patchItem(item.boxId, item.id, (_) => saved);
    } catch (_) {
      if (!mounted) return;
      _patchItem(item.boxId, item.id, (_) => item);
      _fail(L.s.changeSaveFailed);
    }
  }

  /// Drops a single item, from its row's menu, its swipe action or the edit
  /// sheet's delete button.
  ///
  /// Returns what it takes to put the item back, for the confirmation chip's
  /// "Rückgängig" to hand to [restoreItem] — or null when there is nothing to
  /// offer, which is a row still in flight or a delete the server refused.
  Future<DeletedBoxItem?> removeItem(BoxItem item) async {
    final previous = state.itemsByBox;
    final index = (previous[item.boxId] ?? const <BoxItem>[]).indexWhere((i) => i.id == item.id);
    _removeItemLocally(item.boxId, item.id);
    // A row that never reached the server has nothing to restore *to*: undo
    // would insert an item the delete never removed.
    if (_isTemp(item.id)) return null;

    try {
      await _repo.deleteItem(item.id);
      return DeletedBoxItem(item: item, index: index < 0 ? 0 : index);
    } catch (_) {
      if (!mounted) return null;
      state = state.copyWith(itemsByBox: previous, error: L.s.itemDeleteFailed);
      return null;
    }
  }

  /// Puts one deleted item back — a re-insert under a new id, the same deal as
  /// [restoreBox] and for the same reason: the row is gone.
  ///
  /// Its photograph is **not** copied the way a restored box's are. That object
  /// is filed under the *box*, which is still there and still owns it —
  /// deleting an item leaves the object where it was — so undo only has to
  /// point the new row at the same path, and the signed URL already in
  /// `photoUrls` is keyed on that path and still stands.
  Future<bool> restoreItem(DeletedBoxItem deleted) async {
    final original = deleted.item;
    try {
      var saved = await _restoreItem(original.boxId, original);
      if (original.photoPath case final path?) {
        // Best-effort, like every other restore here: a picture that won't come
        // back must not cost the item.
        try {
          saved = await _repo.setItemPhoto(saved.id, path);
        } catch (_) {}
      }
      if (!mounted) return false;

      final items = [...state.itemsFor(original.boxId)];
      items.insert(deleted.index.clamp(0, items.length), saved);
      _putItems(original.boxId, items);
      return true;
    } catch (_) {
      _fail(L.s.itemRestoreFailed);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Item bookkeeping
  // ---------------------------------------------------------------------------

  static String? _orNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  void _putItems(String boxId, List<BoxItem> items) {
    state = state.copyWith(itemsByBox: {...state.itemsByBox, boxId: items});
  }

  void _patchItem(String boxId, String itemId, BoxItem Function(BoxItem) patch) {
    final items = state.itemsByBox[boxId];
    if (items == null) return;
    _putItems(boxId, [for (final i in items) i.id == itemId ? patch(i) : i]);
  }

  void _removeItemLocally(String boxId, String itemId) {
    final items = state.itemsByBox[boxId];
    if (items == null) return;
    _putItems(boxId, [
      for (final i in items)
        if (i.id != itemId) i,
    ]);
  }
}

final boxRepositoryProvider = Provider<BoxRepository>((ref) => BoxRepository(AporahSupabase.client));

/// Rebuilt when the signed-in user or their household changes, and only then —
/// `select` rather than a bare `watch(familyProvider)`, or saving a profile
/// would tear the whole screen's data down and refetch it.
final boxProvider = StateNotifierProvider<BoxNotifier, BoxScreenState>((ref) {
  final notifier = BoxNotifier(
    ref.watch(boxRepositoryProvider),
    ref.watch(photoRepositoryProvider),
    ref.watch(currentUserIdProvider),
    ref.watch(familyProvider.select((s) => s.household?.id)),
  );
  reloadOnFamilyChange(ref, const {'boxes', 'box_items'}, notifier.load);
  return notifier;
});
