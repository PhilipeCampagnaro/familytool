import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/icon_suggestions.dart';
import '../data/repositories/list_repository.dart';
import '../models/attachment.dart';
import '../models/shopping_list.dart';
import '../services/supabase.dart';
import 'auth_state.dart';
import 'family_state.dart';

/// Everything the Listen screen renders, and nothing it doesn't.
///
/// The old overlay maps (`done`, `removed`, `extra`, `edits`) are gone. They
/// existed only because the articles used to be `const` seed data that could
/// not be changed in place; over a server they would be a second source of
/// truth laid on top of the first, and the first one wins after every reload.
/// [lists] and [itemsByList] are now simply owned by this state.
class ListScreenState {
  final bool isDetail;
  final String openId;

  /// Every real list, as RLS handed it over: my household's, plus anything
  /// shared with me — internally or as a guest. Never filtered by `family_id`
  /// here; see `ListRepository`.
  final List<ShoppingList> lists;

  final Map<String, List<ShoppingListItem>> itemsByList;

  /// Lists that reached this account through an external share link rather than
  /// through the household — see [isGuest].
  final Set<String> guestListIds;

  /// Item id → what the row menu's Foto/Kamera/Dateien have attached to it.
  /// Still device-local: `list_item_attachments` needs a Storage bucket, and
  /// those are not created yet (docs/backend.md, "Status").
  final Map<String, List<ItemAttachment>> attachments;

  /// The create/edit sheet's draft "Für wen?" answer, in the two fields the
  /// database actually has. Replaces the old single `who` string, which
  /// conflated assignment with visibility.
  final ListVisibility newVisibility;
  final Set<String> newSharedWith;

  final String newType;

  /// Item the user just checked off or undid, or `''` — lets the section it
  /// landed in animate that one row in (see `CheckOffArrival`) and leave the
  /// rest at rest. Pass `''` to clear it.
  final String justMoved;

  /// True until the first load has answered, so the screen can show the panel
  /// empty rather than "Noch keine Liste angelegt" at somebody with twelve.
  final bool loading;

  /// German, and safe to render verbatim — every message set here is written
  /// for the user, never a raw PostgREST message.
  final String? error;

  const ListScreenState({
    this.isDetail = false,
    this.openId = summaryListId,
    this.lists = const [],
    this.itemsByList = const {},
    this.guestListIds = const {},
    this.attachments = const {},
    this.newVisibility = ListVisibility.family,
    this.newSharedWith = const {},
    this.newType = 'grocery',
    this.justMoved = '',
    this.loading = true,
    this.error,
  });

  /// Whether this account is looking at somebody else's list through an
  /// external share.
  ///
  /// Two things follow, both from docs/backend.md ("What the guest can never
  /// reach"): there is no pooled "Alle Artikel" — pooling a foreign household's
  /// list into your own summary would also make "Artikel hinzufügen" file into
  /// a stranger's list — and the internal member picker is hidden, because the
  /// composite foreign key on `list_shares` makes picking a non-member a
  /// constraint error rather than a polite refusal.
  bool get isGuest => guestListIds.isNotEmpty;

  /// "Alle Artikel" only earns its row once there is something to pool. With a
  /// single list it is that list under a second name, and with none it is an
  /// empty row where the "create your first list" hint belongs.
  bool get showSummary => !isGuest && lists.length >= 2;

  ListScreenState copyWith({
    bool? isDetail,
    String? openId,
    List<ShoppingList>? lists,
    Map<String, List<ShoppingListItem>>? itemsByList,
    Set<String>? guestListIds,
    Map<String, List<ItemAttachment>>? attachments,
    ListVisibility? newVisibility,
    Set<String>? newSharedWith,
    String? newType,
    String? justMoved,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return ListScreenState(
      isDetail: isDetail ?? this.isDetail,
      openId: openId ?? this.openId,
      lists: lists ?? this.lists,
      itemsByList: itemsByList ?? this.itemsByList,
      guestListIds: guestListIds ?? this.guestListIds,
      attachments: attachments ?? this.attachments,
      newVisibility: newVisibility ?? this.newVisibility,
      newSharedWith: newSharedWith ?? this.newSharedWith,
      newType: newType ?? this.newType,
      justMoved: justMoved ?? this.justMoved,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  ShoppingList? listById(String id) {
    for (final l in lists) {
      if (l.id == id) return l;
    }
    return null;
  }

  /// The articles of one list, or — for [summaryListId] — every article pooled.
  ///
  /// Guest lists stay out of the pool even when [showSummary] somehow says yes:
  /// belt and braces on the same rule, since the pooled view is also what
  /// `addItem` writes into.
  List<ShoppingListItem> itemsFor(String id) {
    if (id == summaryListId) {
      return [
        for (final l in lists)
          if (!guestListIds.contains(l.id)) ...?itemsByList[l.id],
      ];
    }
    return itemsByList[id] ?? const [];
  }

  List<ItemAttachment> attachmentsFor(ShoppingListItem item) => attachments[item.id] ?? const [];
}

class ListNotifier extends StateNotifier<ListScreenState> {
  ListNotifier(this._repo, this._userId, this._familyId) : super(const ListScreenState()) {
    if (_userId != null) load();
  }

  final ListRepository _repo;
  final String? _userId;
  final String? _familyId;

  /// Client-side ids for rows that exist on screen but not yet on the server.
  /// Prefixed so nothing can mistake one for a uuid and send it back.
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
      state = state.copyWith(
        lists: snapshot.lists,
        itemsByList: snapshot.itemsByList,
        guestListIds: snapshot.guestListIds,
        loading: false,
        // A list can vanish between two launches (deleted on another device,
        // or a share revoked) while its detail view is the one being restored.
        openId: _resolveOpenId(state.openId, snapshot),
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: 'Listen konnten nicht geladen werden.');
    }
  }

  String _resolveOpenId(String openId, ListSnapshot snapshot) {
    if (snapshot.lists.any((l) => l.id == openId)) return openId;
    if (snapshot.guestListIds.isEmpty) return summaryListId;
    // A pure guest has no summary to fall back to.
    return snapshot.lists.isEmpty ? summaryListId : snapshot.lists.first.id;
  }

  void clearError() => state = state.copyWith(clearError: true);

  void _fail(String message) {
    if (mounted) state = state.copyWith(error: message);
  }

  // ---------------------------------------------------------------------------
  // Navigation and sheet drafts
  // ---------------------------------------------------------------------------

  void open(String id) => state = state.copyWith(isDetail: true, openId: id, justMoved: '');

  void back() => state = state.copyWith(isDetail: false, justMoved: '');

  void setNewType(String type) => state = state.copyWith(newType: type);

  /// The sheet's "Für wen?" answer. `family` and `private` carry no member
  /// list; `custom` is exactly the case that does.
  void setVisibility(ListVisibility visibility, Set<String> sharedWith) {
    state = state.copyWith(
      newVisibility: visibility,
      newSharedWith: visibility == ListVisibility.custom ? sharedWith : const {},
    );
  }

  /// Opens the sheet on a list's own visibility, or on the default for a new
  /// one. Called before the sheet is shown, the same way `setNewType` is.
  void primeVisibility(ShoppingList? list) {
    state = state.copyWith(
      newVisibility: list?.visibility ?? ListVisibility.family,
      newSharedWith: {...?list?.sharedWith},
    );
  }

  // ---------------------------------------------------------------------------
  // Lists
  // ---------------------------------------------------------------------------

  /// Files a new list. Without an explicit [iconKey] — the sheet's picker hands
  /// one over when the user overrode the guess — the name is matched against
  /// the shop logos, the symbol set and the grocery catalog, so "Rewe" arrives
  /// with the REWE logo and "Geburtstag" with a cake.
  ///
  /// Not optimistic, unlike [addItem]: a list is a container that the very next
  /// tap navigates into, and navigating into a row with no server id yet would
  /// mean every article typed there had nowhere to go.
  Future<void> createList({required String name, required ListKind kind, String? iconKey}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final familyId = _familyId;
    if (familyId == null) {
      _fail('Dein Haushalt ist noch nicht geladen.');
      return;
    }

    // `allowGrocery: false`: a list is a container, and the article photos are
    // for the rows inside it — see [suggestIcon]. This is the icon that is
    // actually stored, so it has to agree with the preview the sheet showed.
    final icon = iconKey ?? suggestIcon(trimmed, subject: IconSubject.list)?.key;
    try {
      final saved = await _repo.createList(
        familyId: familyId,
        name: trimmed,
        kind: kind,
        iconKey: icon,
        visibility: state.newVisibility,
        sharedWith: state.newSharedWith,
        position: state.lists.length,
      );
      if (!mounted) return;
      state = state.copyWith(
        lists: [...state.lists, saved],
        itemsByList: {...state.itemsByList, saved.id: const []},
      );
    } catch (_) {
      _fail('Die Liste konnte nicht gespeichert werden.');
    }
  }

  /// Writes a renamed / re-symboled list back.
  ///
  /// An emptied name means "left it alone", the same rule the item rows follow.
  /// The icon follows the name unless the user has picked one: renaming a list
  /// from *Rewe* to *Baumarkt* and keeping the REWE logo would be a lie.
  Future<void> updateList(String id, {required String name, required ListKind kind, String? iconKey}) async {
    final list = state.listById(id);
    if (list == null) return;

    final newName = name.trim().isEmpty ? list.name : name.trim();
    final icon = iconKey ?? (newName == list.name ? list.iconKey : suggestIcon(newName, subject: IconSubject.list)?.key);

    try {
      final saved = await _repo.updateList(
        list,
        name: newName,
        kind: kind,
        iconKey: icon,
        visibility: state.newVisibility,
        sharedWith: state.newSharedWith,
      );
      if (!mounted) return;
      state = state.copyWith(lists: [for (final l in state.lists) l.id == id ? saved : l]);
    } catch (_) {
      _fail('Die Änderung konnte nicht gespeichert werden.');
    }
  }

  /// Drops a list and everything filed under it, and leaves the detail view if
  /// that's the list it was showing.
  Future<void> deleteList(String id) async {
    final previous = state;
    final items = Map<String, List<ShoppingListItem>>.from(state.itemsByList)..remove(id);
    state = state.copyWith(
      lists: state.lists.where((l) => l.id != id).toList(),
      itemsByList: items,
      isDetail: state.openId == id ? false : state.isDetail,
      openId: state.openId == id ? summaryListId : state.openId,
      justMoved: '',
    );

    try {
      await _repo.deleteList(id);
    } catch (_) {
      if (!mounted) return;
      state = previous.copyWith(error: 'Die Liste konnte nicht gelöscht werden.');
    }
  }

  // ---------------------------------------------------------------------------
  // Items
  // ---------------------------------------------------------------------------

  /// Files a typed article under the open list, on screen first and on the
  /// server after.
  ///
  /// Without an explicit [iconKey] — a tapped suggestion brings its own — the
  /// text is matched against the catalogs, so "Milch 2 Liter" arrives with the
  /// milk picture, "Bohrmaschine" on a Sonstige list with a drill, and anything
  /// unrecognised simply arrives without one.
  Future<void> addItem(String text, {String? iconKey}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final targetId = _targetListId();
    if (targetId == null) return;

    final current = state.itemsFor(targetId);
    // Newest first, and one below the lowest sibling so the server agrees.
    final position = current.isEmpty ? 0 : current.map((i) => i.position).reduce((a, b) => a < b ? a : b) - 1;
    final icon = iconKey ?? suggestIcon(trimmed, subject: _isGrocery(targetId) ? IconSubject.groceryArticle : IconSubject.article)?.key;

    final optimistic = ShoppingListItem(
      id: _tempId(),
      listId: targetId,
      text: trimmed,
      iconKey: icon,
      createdBy: _userId,
      position: position,
    );
    _putItem(targetId, [optimistic, ...state.itemsByList[targetId] ?? const []]);

    try {
      final saved = await _repo.addItem(listId: targetId, text: trimmed, iconKey: icon, position: position);
      if (!mounted) return;
      // Reconcile in place: the row keeps its slot and swaps its id for the
      // real uuid, so a tick landing right after the insert has something to
      // write to.
      _replaceItem(targetId, optimistic.id, saved);
    } catch (_) {
      if (!mounted) return;
      _removeItemLocally(targetId, optimistic.id);
      _fail('Der Artikel konnte nicht gespeichert werden.');
    }
  }

  /// Which list a typed article lands in. In the pooled view that is the first
  /// real list; with no list at all there is nothing to file it under.
  String? _targetListId() {
    if (state.openId != summaryListId) return state.openId;
    for (final l in state.lists) {
      if (!state.guestListIds.contains(l.id)) return l.id;
    }
    return null;
  }

  /// Writes back what was typed into an article's row — its name and the
  /// quantity line under it.
  ///
  /// An emptied name means "left it alone" rather than "call this article ''",
  /// the same rule the Box item sheet follows; an emptied quantity does mean
  /// "drop it", since that line is optional to begin with. The picture follows
  /// the name: rename *Milch* to *Käse* and the milk carton would be a lie, so
  /// a changed name is matched against the catalogs again and simply loses its
  /// icon if nothing answers.
  Future<void> editItem(ShoppingListItem item, {required String text, String? sub}) async {
    if (_isTemp(item.id)) return; // Still in flight; the reconcile would clobber it.

    final name = text.trim().isEmpty ? item.text : text.trim();
    final quantity = sub?.trim();
    final newSub = (quantity == null || quantity.isEmpty) ? null : quantity;
    if (name == item.text && newSub == item.sub) return;

    final icon = name == item.text ? item.iconKey : suggestIcon(name, subject: _isGrocery(item.listId) ? IconSubject.groceryArticle : IconSubject.article)?.key;

    _patchItem(item.listId, item.id, (i) => i.copyWith(text: name, sub: newSub, clearSub: newSub == null, iconKey: icon, clearIconKey: icon == null));

    try {
      final saved = await _repo.editItem(item.id, text: name, sub: newSub, iconKey: icon);
      if (!mounted) return;
      _replaceItem(item.listId, item.id, saved);
    } catch (_) {
      if (!mounted) return;
      _patchItem(item.listId, item.id, (_) => item);
      _fail('Die Änderung konnte nicht gespeichert werden.');
    }
  }

  /// Ticks an article off, or undoes it. `done`, `done_by` and `done_at` move
  /// together — who ticked it and when is what a shared list renders.
  Future<void> toggle(String itemId, bool current) async {
    if (_isTemp(itemId)) return;

    final listId = _listIdOf(itemId);
    if (listId == null) return;
    final before = _itemById(listId, itemId);
    if (before == null) return;

    final next = !current;
    _patchItem(
      listId,
      itemId,
      (i) => i.copyWith(
        done: next,
        doneBy: next ? _userId : null,
        clearDoneBy: !next,
        doneAt: next ? DateTime.now() : null,
        clearDoneAt: !next,
      ),
    );
    state = state.copyWith(justMoved: itemId);

    try {
      final saved = await _repo.setDone(itemId, next);
      if (!mounted) return;
      _replaceItem(listId, itemId, saved);
    } catch (_) {
      if (!mounted) return;
      _patchItem(listId, itemId, (_) => before);
      _fail('Konnte nicht gespeichert werden.');
    }
  }

  /// "Erledigte löschen". Rows the database refused to delete (someone else's
  /// article, cleared by a non-admin) come straight back rather than
  /// disappearing until the next reload.
  Future<void> clearDone(List<ShoppingListItem> doneItems) async {
    final ids = [for (final i in doneItems) if (!_isTemp(i.id)) i.id];
    if (ids.isEmpty) return;

    final previous = state.itemsByList;
    _removeItemsLocally(ids.toSet());

    try {
      final deleted = await _repo.clearDone(ids);
      if (!mounted) return;
      final refused = ids.toSet().difference(deleted);
      if (refused.isEmpty) return;
      state = state.copyWith(itemsByList: previous);
      _removeItemsLocally(deleted);
      _fail('Nicht alle erledigten Artikel konnten gelöscht werden.');
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(itemsByList: previous, error: 'Die erledigten Artikel konnten nicht gelöscht werden.');
    }
  }

  /// Drops a single item, from its row's menu or its swipe action. Keyed by the
  /// item's *own* list, not the open one: in "Alle Artikel" those differ.
  Future<void> removeItem(ShoppingListItem item) async {
    final previous = state.itemsByList;
    _removeItemLocally(item.listId, item.id);
    state = state.copyWith(justMoved: '');
    if (_isTemp(item.id)) return;

    try {
      await _repo.deleteItem(item.id);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(itemsByList: previous, error: 'Der Artikel konnte nicht gelöscht werden.');
    }
  }

  /// Files the picked photo/document under its item. Appends rather than
  /// replaces: picking a second photo adds to the first. Device-local until
  /// there is a Storage bucket behind `list_item_attachments`.
  void addAttachment(String itemId, ItemAttachment attachment) {
    final attachments = Map<String, List<ItemAttachment>>.from(state.attachments);
    attachments[itemId] = [...?attachments[itemId], attachment];
    state = state.copyWith(attachments: attachments);
  }

  // ---------------------------------------------------------------------------
  // Item bookkeeping
  // ---------------------------------------------------------------------------

  void _putItem(String listId, List<ShoppingListItem> items) {
    state = state.copyWith(itemsByList: {...state.itemsByList, listId: items});
  }

  ShoppingListItem? _itemById(String listId, String itemId) {
    for (final i in state.itemsByList[listId] ?? const <ShoppingListItem>[]) {
      if (i.id == itemId) return i;
    }
    return null;
  }

  String? _listIdOf(String itemId) {
    for (final entry in state.itemsByList.entries) {
      if (entry.value.any((i) => i.id == itemId)) return entry.key;
    }
    return null;
  }

  void _patchItem(String listId, String itemId, ShoppingListItem Function(ShoppingListItem) patch) {
    final items = state.itemsByList[listId];
    if (items == null) return;
    _putItem(listId, [for (final i in items) i.id == itemId ? patch(i) : i]);
  }

  void _replaceItem(String listId, String itemId, ShoppingListItem saved) {
    _patchItem(listId, itemId, (_) => saved);
  }

  void _removeItemLocally(String listId, String itemId) {
    final items = state.itemsByList[listId];
    if (items == null) return;
    _putItem(listId, [for (final i in items) if (i.id != itemId) i]);
  }

  void _removeItemsLocally(Set<String> itemIds) {
    state = state.copyWith(
      itemsByList: {
        for (final entry in state.itemsByList.entries)
          entry.key: [for (final i in entry.value) if (!itemIds.contains(i.id)) i],
      },
    );
  }

  /// Whether articles typed into this list are food. It decides which catalog
  /// gets the first look at an article's name — see `suggestIcon`. "Alle
  /// Artikel" counts: it is the pooled view over the grocery lists.
  bool _isGrocery(String listId) {
    if (listId == summaryListId) return true;
    return state.listById(listId)?.kind != ListKind.other;
  }
}

final listRepositoryProvider = Provider<ListRepository>((ref) => ListRepository(AporahSupabase.client));

/// Rebuilt when the signed-in user or their household changes, and only then —
/// `select` rather than a bare `watch(familyProvider)`, or saving a profile
/// would tear the whole screen's data down and refetch it.
final listProvider = StateNotifierProvider<ListNotifier, ListScreenState>((ref) {
  return ListNotifier(
    ref.watch(listRepositoryProvider),
    ref.watch(currentUserIdProvider),
    ref.watch(familyProvider.select((s) => s.household?.id)),
  );
});
