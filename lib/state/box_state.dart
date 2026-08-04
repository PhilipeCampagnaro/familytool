import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/icon_suggestions.dart';
import '../data/repositories/box_repository.dart';
import '../models/box_item.dart';
import '../models/visibility.dart';
import '../services/supabase.dart';
import 'auth_state.dart';
import 'family_state.dart';

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

  int get totalItems => boxes.fold(0, (n, b) => n + itemsFor(b.id).length);
}

class BoxNotifier extends StateNotifier<BoxScreenState> {
  BoxNotifier(this._repo, this._userId, this._familyId) : super(const BoxScreenState()) {
    if (_userId != null) load();
  }

  final BoxRepository _repo;
  final String? _userId;
  final String? _familyId;

  /// Client-side ids for rows that exist on screen but not yet on the server.
  static const _tempPrefix = 'tmp:';
  static bool _isTemp(String id) => id.startsWith(_tempPrefix);
  static String _tempId() => '$_tempPrefix${DateTime.now().microsecondsSinceEpoch}';

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

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
        loading: false,
        openId: open ? state.openId : '',
        isDetail: open && state.isDetail,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: 'Boxen konnten nicht geladen werden.');
    }
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
  /// Not optimistic, unlike [addItem]: a box is a container the very next tap
  /// navigates into, and navigating into a row with no server id yet would mean
  /// every item typed there had nowhere to go.
  Future<void> createBox({required String name, required String place, String? iconKey}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final familyId = _familyId;
    if (familyId == null) {
      _fail('Dein Haushalt ist noch nicht geladen.');
      return;
    }

    try {
      final saved = await _repo.createBox(
        familyId: familyId,
        name: trimmed,
        place: place.trim(),
        iconKey: iconKey ?? suggestIcon(trimmed, subject: IconSubject.box)?.key,
        visibility: state.newVisibility,
        sharedWith: state.newSharedWith,
        position: state.boxes.length,
      );
      if (!mounted) return;
      state = state.copyWith(
        boxes: [...state.boxes, saved],
        itemsByBox: {...state.itemsByBox, saved.id: const []},
      );
    } catch (_) {
      _fail('Die Box konnte nicht gespeichert werden.');
    }
  }

  /// Writes a renamed / re-symboled / moved box back. An emptied name means
  /// "left it alone"; the icon follows a changed name unless one was picked.
  Future<void> updateBox(String id, {required String name, required String place, String? iconKey}) async {
    final box = state.boxById(id);
    if (box == null) return;

    final newName = name.trim().isEmpty ? box.name : name.trim();
    final icon = iconKey ?? (newName == box.name ? box.iconKey : suggestIcon(newName, subject: IconSubject.box)?.key);

    try {
      final saved = await _repo.updateBox(
        box,
        name: newName,
        place: place.trim(),
        iconKey: icon,
        visibility: state.newVisibility,
        sharedWith: state.newSharedWith,
      );
      if (!mounted) return;
      state = state.copyWith(boxes: [for (final b in state.boxes) b.id == id ? saved : b]);
    } catch (_) {
      _fail('Die Änderung konnte nicht gespeichert werden.');
    }
  }

  /// Drops a box and its contents, and leaves the detail view if that's the box
  /// it was showing.
  Future<void> deleteBox(String id) async {
    final previous = state;
    final items = Map<String, List<BoxItem>>.from(state.itemsByBox)..remove(id);
    state = state.copyWith(
      boxes: state.boxes.where((b) => b.id != id).toList(),
      itemsByBox: items,
      isDetail: state.openId == id ? false : state.isDetail,
      openId: state.openId == id ? '' : state.openId,
    );

    try {
      await _repo.deleteBox(id);
    } catch (_) {
      if (!mounted) return;
      state = previous.copyWith(error: 'Die Box konnte nicht gelöscht werden.');
    }
  }

  // ---------------------------------------------------------------------------
  // Items
  // ---------------------------------------------------------------------------

  /// Files a typed item under the open box, on screen first and on the server
  /// after. No grocery-first bias here: a box holds a drill far more often than
  /// it holds milk.
  Future<void> addItem(String name, {String? iconKey}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final boxId = state.openId;
    if (boxId.isEmpty) return;

    final current = state.itemsFor(boxId);
    final position = current.isEmpty ? 0 : current.map((i) => i.position).reduce((a, b) => a > b ? a : b) + 1;
    final icon = iconKey ?? suggestIcon(trimmed)?.key;

    final optimistic = BoxItem(
      id: _tempId(),
      boxId: boxId,
      name: trimmed,
      iconKey: icon,
      createdBy: _userId,
      position: position,
    );
    _putItems(boxId, [...current, optimistic]);

    try {
      final saved = await _repo.addItem(boxId: boxId, name: trimmed, iconKey: icon, position: position);
      if (!mounted) return;
      // Reconcile in place: the row keeps its slot and swaps its id for the real
      // uuid, so an edit landing right after the insert has something to write to.
      _patchItem(boxId, optimistic.id, (_) => saved);
    } catch (_) {
      if (!mounted) return;
      _removeItemLocally(boxId, optimistic.id);
      _fail('Der Artikel konnte nicht gespeichert werden.');
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
      _fail('Die Änderung konnte nicht gespeichert werden.');
    }
  }

  /// Drops a single item, from its row's menu, its swipe action or the edit
  /// sheet's delete button.
  Future<void> removeItem(BoxItem item) async {
    final previous = state.itemsByBox;
    _removeItemLocally(item.boxId, item.id);
    if (_isTemp(item.id)) return;

    try {
      await _repo.deleteItem(item.id);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(itemsByBox: previous, error: 'Der Artikel konnte nicht gelöscht werden.');
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
    _putItems(boxId, [for (final i in items) if (i.id != itemId) i]);
  }
}

final boxRepositoryProvider = Provider<BoxRepository>((ref) => BoxRepository(AporahSupabase.client));

/// Rebuilt when the signed-in user or their household changes, and only then —
/// `select` rather than a bare `watch(familyProvider)`, or saving a profile
/// would tear the whole screen's data down and refetch it.
final boxProvider = StateNotifierProvider<BoxNotifier, BoxScreenState>((ref) {
  return BoxNotifier(
    ref.watch(boxRepositoryProvider),
    ref.watch(currentUserIdProvider),
    ref.watch(familyProvider.select((s) => s.household?.id)),
  );
});
