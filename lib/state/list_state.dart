import '../services/app_review.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/article_quantity.dart';
import '../data/icon_suggestions.dart';
import '../data/repositories/list_repository.dart';
import '../data/repositories/photo_repository.dart';
import '../models/attachment.dart';
import '../models/picked_file.dart';
import '../models/event_link.dart';
import '../models/shopping_list.dart';
import '../services/supabase.dart';
import 'auth_state.dart';
import 'family_state.dart';
import '../l10n/l10n.dart';
import 'realtime_state.dart';

/// How a list draws its open articles.
///
/// [cards] is the Bring-style grid: the article's own picture at the size it
/// deserves, its name under it, and nothing else on the tile. It is offered on
/// **Lebensmittel lists only**, because a Sonstige article has no picture at
/// all — nothing picks a symbol for one (see `planItemIconKey`) — so a grid of
/// them would be a wall of empty circles with words underneath, strictly worse
/// than the rows it replaced.
///
/// The grid is a **reading** mode: it holds the picture, the name, the quantity
/// and tap-to-check, and sends everything else — rename, unit, link,
/// attachments — to the same row menu, reached by a long press. The list stays
/// the mode you edit in, which is why it is the default and why "Erledigt"
/// keeps its rows in both.
enum ListViewMode { list, cards }

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

  /// Lists somebody outside the household can reach or has been invited to —
  /// the small people icon on the row and in the header.
  final Set<String> sharedOutIds;

  /// Item id → what the row menu's Foto/Kamera/Dateien have attached to it.
  ///
  /// Stored now. This map used to be the whole feature — the objects lived in
  /// `Documents/attachments/` and the map died with the process, so a photo of
  /// the shelf survived until the next launch and never reached the other
  /// parent at all. It is a cache of `list_item_attachments` rows, refilled on
  /// every [ListNotifier.load].
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

  /// The lists this *device* draws as a grid — see [ListViewMode].
  ///
  /// Only the ids in cards are held, because [ListViewMode.list] is the default
  /// and an empty set is therefore the correct state for an account that has
  /// never touched the switch. It lives in `shared_preferences` rather than on
  /// `lists`: how I like to read the shopping list is mine, and a column would
  /// re-draw the other parent's screen from across town.
  final Set<String> cardListIds;

  /// Which real list the pooled "Alle Artikel" view files a typed article
  /// into, as the reader picked it from the add line's own chip — or null,
  /// which means "whichever comes first" and is what a fresh install has.
  ///
  /// Read through [summaryTargetId] rather than directly: a pick can outlive
  /// the list it names (deleted here, or unshared from the other side), and it
  /// arrives from `shared_preferences` a moment after the screen does.
  final String? summaryTargetChoice;

  const ListScreenState({
    this.isDetail = false,
    this.openId = summaryListId,
    this.lists = const [],
    this.itemsByList = const {},
    this.guestListIds = const {},
    this.sharedOutIds = const {},
    this.attachments = const {},
    this.newVisibility = ListVisibility.family,
    this.newSharedWith = const {},
    this.newType = 'grocery',
    this.justMoved = '',
    this.loading = true,
    this.error,
    this.cardListIds = const {},
    this.summaryTargetChoice,
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

  /// The list a typed article lands in while the pooled view is open —
  /// [summaryTargetChoice] where it still names a list this account may write
  /// to, and otherwise the first real one. Null only when there is no list at
  /// all, which is nothing to file under.
  ///
  /// A guest list is never it: pooling somebody else's list into the summary is
  /// already refused ([isGuest]), and filing into one would be the same
  /// mistake from the other direction.
  String? get summaryTargetId {
    final picked = summaryTargetChoice;
    if (picked != null && !guestListIds.contains(picked) && lists.any((l) => l.id == picked)) {
      return picked;
    }
    for (final l in lists) {
      if (!guestListIds.contains(l.id)) return l.id;
    }
    return null;
  }

  /// The list itself, for the add line's chip — it draws that list's own icon,
  /// so an id is not enough.
  ShoppingList? get summaryTarget {
    final id = summaryTargetId;
    return id == null ? null : listById(id);
  }

  ListScreenState copyWith({
    bool? isDetail,
    String? openId,
    List<ShoppingList>? lists,
    Map<String, List<ShoppingListItem>>? itemsByList,
    Set<String>? guestListIds,
    Set<String>? sharedOutIds,
    Map<String, List<ItemAttachment>>? attachments,
    ListVisibility? newVisibility,
    Set<String>? newSharedWith,
    String? newType,
    String? justMoved,
    bool? loading,
    String? error,
    bool clearError = false,
    Set<String>? cardListIds,
    String? summaryTargetChoice,
  }) {
    return ListScreenState(
      isDetail: isDetail ?? this.isDetail,
      openId: openId ?? this.openId,
      lists: lists ?? this.lists,
      itemsByList: itemsByList ?? this.itemsByList,
      guestListIds: guestListIds ?? this.guestListIds,
      sharedOutIds: sharedOutIds ?? this.sharedOutIds,
      attachments: attachments ?? this.attachments,
      newVisibility: newVisibility ?? this.newVisibility,
      newSharedWith: newSharedWith ?? this.newSharedWith,
      newType: newType ?? this.newType,
      justMoved: justMoved ?? this.justMoved,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      cardListIds: cardListIds ?? this.cardListIds,
      summaryTargetChoice: summaryTargetChoice ?? this.summaryTargetChoice,
    );
  }

  /// How [id] draws its open articles on this device. "Alle Artikel" is always
  /// [ListViewMode.list]: it is the one view with no menu to switch from — it
  /// is computed rather than stored, so its header carries nothing to act on —
  /// and it groups articles under the list each came from, which the grid has
  /// no place for.
  ListViewMode viewModeFor(String id) =>
      id != summaryListId && cardListIds.contains(id) ? ListViewMode.cards : ListViewMode.list;

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

/// Everything a deleted list would take with it, held just long enough for the
/// confirmation chip's "Rückgängig" to hand it back.
///
/// Deliberately not kept on [ListScreenState]: it is not something the screen
/// renders, and parking it there would make an un-undone delete linger in the
/// state for the rest of the session. It lives for the five seconds the chip is
/// up and is then collected with it.
class DeletedList {
  final ShoppingList list;
  final List<ShoppingListItem> items;

  /// Item id → the device-local photos filed against it, for the ones that had
  /// any. Re-keyed onto the new rows by `ListNotifier.restoreList`.
  final Map<String, List<ItemAttachment>> attachments;

  /// Where it sat in the overview, so undo puts it back rather than at the end.
  final int index;

  const DeletedList({
    required this.list,
    required this.items,
    required this.attachments,
    required this.index,
  });
}

/// One deleted article, held for as long as its chip is up.
///
/// The item side of [DeletedList], and much cheaper: the list it belonged to is
/// still there, so there is no container to re-create and no object to copy —
/// only the row, its attachment rows, and where in the list it sat.
class DeletedListItem {
  final ShoppingListItem item;
  final List<ItemAttachment> attachments;

  /// Its slot among its siblings, so undo puts it back where it was rather than
  /// at the end. Its stored `position` says the same thing to the server; this
  /// is what keeps the screen from re-ordering itself for a frame.
  final int index;

  const DeletedListItem({required this.item, required this.attachments, required this.index});
}

class ListNotifier extends StateNotifier<ListScreenState> {
  ListNotifier(this._repo, this._photos, this._userId, this._familyId) : super(const ListScreenState()) {
    _loadViewModes();
    _loadSummaryTarget();
    if (_userId != null) load();
  }

  final ListRepository _repo;
  final PhotoRepository _photos;
  final String? _userId;
  final String? _familyId;

  /// Client-side ids for rows that exist on screen but not yet on the server.
  /// Prefixed so nothing can mistake one for a uuid and send it back.
  ///
  /// **A uuid rather than the clock**, which is not a detail: [_fillList] mints
  /// one per article in a tight synchronous loop, and on a Sonstige list that
  /// loop does no work at all per row (no icon to look up), so two of them read
  /// the same microsecond. Two drafts then shared an id, the first insert to
  /// answer replaced *both* with its own saved row — `_patchItem` patches every
  /// match, which is right — and the list came back with one uuid on two rows,
  /// which is a duplicate `ValueKey` and a red screen rather than a wrong row.
  static const _tempPrefix = 'tmp:';
  static bool _isTemp(String id) => id.startsWith(_tempPrefix);
  static String _tempId() => '$_tempPrefix${newUuidV4()}';

  // ---------------------------------------------------------------------------
  // View mode
  // ---------------------------------------------------------------------------

  static const _prefsCardListsKey = 'list_view_cards';

  /// Best-effort, like every other `shared_preferences` read in the app: a
  /// device with no local storage this session simply draws every list as a
  /// list, which is the default anyway.
  Future<void> _loadViewModes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(_prefsCardListsKey);
      if (ids == null || ids.isEmpty || !mounted) return;
      state = state.copyWith(cardListIds: ids.toSet());
    } catch (_) {
      // No local storage — every list stays a list.
    }
  }

  /// Switches one list between rows and the grid, for this device only.
  ///
  /// The write prunes ids whose list is gone: the set is only ever touched from
  /// inside an open list, so `state.lists` is loaded by definition here and a
  /// year of deleted shopping lists can't pile up in the preference. An id that
  /// belongs to a list this account can no longer see would be pruned too,
  /// which is the same thing — it has nothing left to draw.
  void setViewMode(String listId, ListViewMode mode) {
    final ids = {...state.cardListIds};
    if (mode == ListViewMode.cards) {
      ids.add(listId);
    } else {
      ids.remove(listId);
    }
    final known = {for (final l in state.lists) l.id};
    ids.removeWhere((id) => !known.contains(id));
    state = state.copyWith(cardListIds: ids);
    _persistViewModes(ids);
  }

  Future<void> _persistViewModes(Set<String> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsCardListsKey, ids.toList());
    } catch (_) {
      // Same as above — the switch still holds for this session.
    }
  }

  // ---------------------------------------------------------------------------
  // Where the pooled view files into
  // ---------------------------------------------------------------------------

  static const _prefsSummaryTargetKey = 'list_summary_target';

  /// Best-effort like the view modes, and for the same reason it lives beside
  /// them rather than on a column: which list I file into from "Alle Artikel"
  /// is mine, on this device, and a column would move the other parent's chip
  /// while they were typing. A device that can't read it simply starts at the
  /// first list again — see [ListScreenState.summaryTargetId].
  Future<void> _loadSummaryTarget() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_prefsSummaryTargetKey);
      if (id == null || id.isEmpty || !mounted) return;
      state = state.copyWith(summaryTargetChoice: id);
    } catch (_) {
      // No local storage — the first list it is.
    }
  }

  /// Points the pooled view's add line at [listId], and remembers it.
  ///
  /// Nothing validates the id here: [ListScreenState.summaryTargetId] is the
  /// one place that decides whether a pick still names a list, so a list
  /// deleted later needs no cleanup pass.
  void setSummaryTarget(String listId) {
    state = state.copyWith(summaryTargetChoice: listId);
    _persistSummaryTarget(listId);
  }

  Future<void> _persistSummaryTarget(String listId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsSummaryTargetKey, listId);
    } catch (_) {
      // Same as above — the pick still holds for this session.
    }
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Re-reads which lists are shared outside the household, after a share
  /// sheet sent an invitation or the edit sheet removed a guest.
  Future<void> refreshSharedOut() async {
    final ids = [for (final l in state.lists) l.id];
    final shared = await _repo.fetchSharedOutIds(ids);
    if (mounted) state = state.copyWith(sharedOutIds: shared);
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
      state = state.copyWith(
        lists: snapshot.lists,
        itemsByList: snapshot.itemsByList,
        guestListIds: snapshot.guestListIds,
        sharedOutIds: snapshot.sharedOutIds,
        loading: false,
        // A list can vanish between two launches (deleted on another device,
        // or a share revoked) while its detail view is the one being restored.
        openId: _resolveOpenId(state.openId, snapshot),
      );
      // After the rows, and that is the whole point: the attachments are two
      // more round trips (the rows, then the signing) that the articles used to
      // wait behind. An article whose photo hasn't arrived yet still says what
      // to buy.
      await _loadAttachments();
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: L.s.listsLoadFailed);
    }
  }

  /// The files hanging off the articles now on screen, and their signed URLs.
  ///
  /// Never throws and never blanks anything: a failure here costs thumbnails,
  /// not the list. Replaced wholesale rather than merged — the server is the
  /// source of truth for what is attached, and a stale entry here would draw a
  /// thumbnail for a file somebody else has already removed.
  Future<void> _loadAttachments() async {
    final itemIds = [
      for (final items in state.itemsByList.values)
        for (final i in items) i.id,
    ];
    if (itemIds.isEmpty) {
      if (state.attachments.isNotEmpty) state = state.copyWith(attachments: const {});
      return;
    }
    try {
      final byItem = await _repo.fetchAttachments(itemIds);
      if (!mounted) return;
      state = state.copyWith(attachments: byItem);
    } catch (_) {
      return;
    }
    await _signAttachments();
  }

  /// Signs every attached object in one round trip. Never throws: a failure
  /// here costs thumbnails, not the screen.
  Future<void> _signAttachments() async {
    final urls = await _photos.signUrls(PhotoRepository.listBucket, [
      for (final list in state.attachments.values)
        for (final a in list) a.storagePath,
    ]);
    if (!mounted || urls.isEmpty) return;
    state = state.copyWith(
      attachments: {
        for (final entry in state.attachments.entries)
          entry.key: [
            for (final a in entry.value)
              urls[a.storagePath] == null ? a : a.copyWith(url: urls[a.storagePath]),
          ],
      },
    );
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
  /// On screen first and on the server after, like [addItem] — but under the
  /// **real** id rather than a `tmp:` one, which is what used to rule that out.
  /// A list is a container the very next tap navigates into, and a row with no
  /// server id yet would give every article typed there nowhere to go. The id
  /// was never the server's to give, though: `lists` is inserted with a
  /// client-side uuid because `insert … returning` cannot pass the SELECT
  /// policy (see [ListRepository.createList]), so the id the row will have is
  /// known here, before the write goes out. Navigating in works, and an article
  /// typed straight away carries a `list_id` that is about to exist.
  ///
  /// This is the difference between a list appearing when the sheet closes and
  /// a list appearing a network round trip later — which on a phone was long
  /// enough that people tapped "Sichern" a second time.
  ///
  /// True only when the row really landed on the server — the screen shows its
  /// confirmation chip off that, so a failed write gets the error snack and no
  /// chip rather than both, and takes the optimistic row back off.
  Future<bool> createList({
    required String name,
    required ListKind kind,
    String? iconKey,
    EventLink? eventLink,
    String? withId,
    bool openIt = false,
    List<String> steps = const [],
    String? recipe,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    final familyId = _familyId;
    if (familyId == null) {
      _fail(L.s.householdNotLoaded);
      return false;
    }

    // `allowGrocery: false`: a list is a container, and the article photos are
    // for the rows inside it — see [suggestIcon]. This is the icon that is
    // actually stored, so it has to agree with the preview the sheet showed.
    final icon = iconKey ?? suggestIcon(trimmed, subject: IconSubject.list)?.key;
    // The caller's own uuid where it has one — [createListWithItems] has to know
    // the list's id before the insert answers, so it can fill it. Minted here
    // otherwise, which is every other caller.
    final id = withId ?? newUuidV4();
    final visibility = state.newVisibility;
    final sharedWith = {...state.newSharedWith};
    final optimistic = ShoppingList(
      id: id,
      name: trimmed,
      iconKey: icon,
      kind: kind,
      familyId: familyId,
      ownerId: _userId ?? '',
      visibility: visibility,
      // `family` and `private` have no member list — the repository drops one
      // before it writes, so showing one here would be a badge that changes
      // when the answer comes back.
      sharedWith: visibility == ListVisibility.custom ? sharedWith.toList() : const [],
      position: state.lists.length,
      eventLink: eventLink,
      steps: steps,
      recipe: recipe,
    );
    state = state.copyWith(
      lists: [...state.lists, optimistic],
      itemsByList: {...state.itemsByList, id: const []},
      // In the same update as the row, so there is no frame of the shelf with
      // the new list on it before the detail view replaces it. A failed write
      // puts the reader back on the shelf below.
      isDetail: openIt ? true : null,
      openId: openIt ? id : null,
      justMoved: openIt ? '' : null,
    );

    try {
      final saved = await _repo.createList(
        id: id,
        familyId: familyId,
        name: trimmed,
        kind: kind,
        iconKey: icon,
        visibility: visibility,
        sharedWith: sharedWith,
        position: optimistic.position,
        eventLink: eventLink,
        // Must be passed, not merely put on `optimistic`: the row this returns
        // *replaces* the optimistic one below, so anything the repository was
        // not told about is dropped from the insert and from state alike.
        steps: steps,
        recipe: recipe,
      );
      if (!mounted) return false;
      // Appended rather than replaced when it is gone: a [load] that finished
      // mid-flight rebuilds `lists` from the server, which cannot yet see the
      // row being inserted, so the optimistic one is swept away. Swapping it in
      // place would then quietly drop the list the user just made.
      final present = state.lists.any((l) => l.id == id);
      state = state.copyWith(
        lists: present ? [for (final l in state.lists) l.id == id ? saved : l] : [...state.lists, saved],
        itemsByList: {...state.itemsByList, id: state.itemsByList[id] ?? const []},
      );
      return true;
    } catch (_) {
      if (!mounted) return false;
      final items = Map<String, List<ShoppingListItem>>.from(state.itemsByList)..remove(id);
      state = state.copyWith(
        lists: state.lists.where((l) => l.id != id).toList(),
        itemsByList: items,
        // The write failed under the user, who may already be inside the list
        // typing into it. Leaving them on a detail view of a row that no longer
        // exists is worse than putting them back on the shelf.
        isDetail: state.openId == id ? false : state.isDetail,
        openId: state.openId == id ? summaryListId : state.openId,
      );
      _fail(L.s.listSaveFailed);
      return false;
    }
  }

  /// A list and the articles that belong on it, in one action — the
  /// "Liste erstellen" a Vorhaben stamps out.
  ///
  /// One method rather than two calls from the screen, because the id is the
  /// hinge: `lists` is inserted with a **client-side uuid and no read-back** (see
  /// the "Writing containers from the client" section of docs/backend.md — the
  /// SELECT policy is a `stable` function that cannot see the row being
  /// inserted, so `insert … returning` is rejected), which is what makes filling
  /// it possible at all. Minting that uuid is this file's business and not a
  /// screen's.
  ///
  /// The articles go in only once the list itself has landed: `list_items` has a
  /// real foreign key onto `lists`, so a child row that overtook its parent
  /// would be rejected. False means the list failed and nothing was filled.
  /// [items] carry a `unit` — a [GroceryUnit] key, or null for the default —
  /// because a Vorhaben's articles arrive as *500* and *g* rather than as the
  /// one string "500g". A caller with no unit to give passes null, and the
  /// article is stored exactly as it was written.
  Future<bool> createListWithItems({
    required String name,
    required ListKind kind,
    required List<({String text, String? sub, String? unit})> items,
    bool openIt = false,
    List<String> steps = const [],
    String? recipe,
  }) async {
    final id = newUuidV4();
    if (!await createList(name: name, kind: kind, withId: id, openIt: openIt, steps: steps, recipe: recipe)) {
      return false;
    }
    await _fillList(id, items);
    return true;
  }

  /// Fills a list nobody has typed into yet — a Vorhaben's articles, stamped
  /// out behind the list itself.
  ///
  /// **Addressed by [listId] rather than by the open list**, which is the whole
  /// difference from [addItem]: this runs from the Board, where Listen has no
  /// list open, and `_targetListId()` would file a craft list's articles into
  /// whichever list happened to be showing. Positions count *up* from zero for
  /// the same kind of reason — these arrive in the order somebody wrote them,
  /// and [addItem]'s newest-first rule would stand them on their head.
  ///
  /// Each article's icon comes off its own name through [suggestIcon], exactly
  /// as a typed one's does, so a stamped-out list arrives looking like a list
  /// somebody made by hand.
  ///
  /// **Silent about failure, deliberately.** The list is what the confirmation
  /// chip is reporting on; an article that did not land leaves five rows where
  /// there should be six, which the next load corrects, and that is a smaller
  /// thing than an error over a list the user is already looking at.
  Future<void> _fillList(String listId, List<({String text, String? sub, String? unit})> rows) async {
    if (rows.isEmpty) return;
    final grocery = _isGrocery(listId);

    final drafts = <ShoppingListItem>[];
    for (var i = 0; i < rows.length; i++) {
      final text = rows[i].text.trim();
      if (text.isEmpty) continue;
      drafts.add(
        ShoppingListItem(
          id: _tempId(),
          listId: listId,
          text: text,
          sub: rows[i].sub,
          unit: rows[i].unit,
          iconKey: planItemIconKey(text, grocery: grocery),
          createdBy: _userId,
          position: drafts.length,
        ),
      );
    }
    if (drafts.isEmpty) return;
    _putItem(listId, [...state.itemsByList[listId] ?? const [], ...drafts]);

    for (final draft in drafts) {
      try {
        final saved = await _repo.addItem(
          listId: listId,
          text: draft.text,
          sub: draft.sub,
          unit: draft.unit,
          iconKey: draft.iconKey,
          position: draft.position,
        );
        if (!mounted) return;
        _replaceItem(listId, draft.id, saved);
      } catch (_) {
        if (!mounted) return;
        _removeItemLocally(listId, draft.id);
      }
    }
  }

  /// Writes a renamed / re-symboled list back.
  ///
  /// An emptied name means "left it alone", the same rule the item rows follow.
  /// The icon follows the name unless the user has picked one: renaming a list
  /// from *Rewe* to *Baumarkt* and keeping the REWE logo would be a lie.
  Future<bool> updateList(String id, {required String name, required ListKind kind, String? iconKey}) async {
    final list = state.listById(id);
    if (list == null) return false;

    final newName = name.trim().isEmpty ? list.name : name.trim();
    final icon =
        iconKey ??
        (newName == list.name ? list.iconKey : suggestIcon(newName, subject: IconSubject.list)?.key);

    try {
      final saved = await _repo.updateList(
        list,
        name: newName,
        kind: kind,
        iconKey: icon,
        visibility: state.newVisibility,
        sharedWith: state.newSharedWith,
      );
      if (!mounted) return false;
      state = state.copyWith(lists: [for (final l in state.lists) l.id == id ? saved : l]);
      return true;
    } catch (_) {
      _fail(L.s.changeSaveFailed);
      return false;
    }
  }

  /// Drops a list and everything filed under it, and leaves the detail view if
  /// that's the list it was showing.
  ///
  /// Returns what it took away, or null if the delete didn't land — the
  /// confirmation chip's "Rückgängig" hands it straight back to [restoreList].
  /// The snapshot is taken here rather than at the call site because the items
  /// and the photos hanging off them only exist in this state.
  Future<DeletedList?> deleteList(String id) async {
    final previous = state;
    final list = state.listById(id);
    if (list == null) return null;

    final removedItems = state.itemsFor(id);
    final removed = DeletedList(
      list: list,
      items: removedItems,
      attachments: {for (final item in removedItems) item.id: ?state.attachments[item.id]},
      index: state.lists.indexWhere((l) => l.id == id),
    );

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
      return removed;
    } catch (_) {
      if (!mounted) return null;
      state = previous.copyWith(error: L.s.listDeleteFailed);
      return null;
    }
  }

  /// Puts a deleted list back, articles and all.
  ///
  /// A re-*insert*, not a resurrection: the rows are gone, so everything comes
  /// back under new ids. That is invisible for the list, its articles and its
  /// audience — all of which are carried over — but a share link handed to
  /// somebody outside the household pointed at the old id and stays dead. Undo
  /// is for the mis-tap you notice immediately, and re-sharing is the honest
  /// price of it.
  Future<bool> restoreList(DeletedList deleted) async {
    final familyId = _familyId;
    if (familyId == null) {
      _fail(L.s.householdNotLoaded);
      return false;
    }

    try {
      final list = deleted.list;
      final saved = await _repo.createList(
        familyId: familyId,
        name: list.name,
        kind: list.kind,
        iconKey: list.iconKey,
        visibility: list.visibility,
        sharedWith: list.sharedWith.toSet(),
        position: list.position,
        // Undo has to give back the list that was deleted, and where it came
        // from is part of that — without this, "Rückgängig" would quietly return
        // an unlinked list and the event would offer to create it again.
        eventLink: list.eventLink,
      );

      // In parallel: each article carries its own `position`, so the order it
      // comes back in is the order it was in, whatever sequence the inserts
      // finish in.
      final restored = await Future.wait([for (final item in deleted.items) _restoreItem(saved.id, item)]);
      // The attached files have to be copied, not re-keyed. Undo re-inserts
      // under a fresh uuid — the old rows are gone and their ids with them —
      // and every object is filed under the id of the *list* it belongs to, so
      // the old `storage_path` would name something no list owns any more and
      // the read policy would rightly refuse it.
      final movedAttachments = await _restoreAttachments(saved.id, restored, deleted);
      if (!mounted) return false;

      final lists = [...state.lists];
      lists.insert(deleted.index.clamp(0, lists.length), saved);
      state = state.copyWith(
        lists: lists,
        itemsByList: {...state.itemsByList, saved.id: restored},
        attachments: {...state.attachments, ...movedAttachments},
      );
      return true;
    } catch (_) {
      _fail(L.s.listRestoreFailed);
      return false;
    }
  }

  /// Copies a restored list's attached files under its new id and files them
  /// against the new articles, index for index — `Future.wait` keeps the order,
  /// so [restored] and `deleted.items` line up.
  ///
  /// Best-effort per file: one object that has already been swept up must not
  /// turn undo into a failed restore. A list that comes back missing one photo
  /// is a far better outcome than a list that doesn't come back.
  Future<Map<String, List<ItemAttachment>>> _restoreAttachments(
    String listId,
    List<ShoppingListItem> restored,
    DeletedList deleted,
  ) async {
    final out = <String, List<ItemAttachment>>{};
    for (final (i, original) in deleted.items.indexed) {
      final files = deleted.attachments[original.id];
      if (files == null || files.isEmpty || i >= restored.length) continue;

      final moved = <ItemAttachment>[];
      for (final file in files) {
        try {
          final path = await _photos.copyTo(
            bucket: PhotoRepository.listBucket,
            fromPath: file.storagePath,
            containerId: listId,
          );
          moved.add(
            await _repo.addAttachment(
              itemId: restored[i].id,
              storagePath: path,
              name: file.name,
              isImage: file.isImage,
            ),
          );
        } catch (_) {
          continue;
        }
      }
      if (moved.isNotEmpty) out[restored[i].id] = moved;
    }

    if (out.isEmpty) return out;
    final urls = await _photos.signUrls(PhotoRepository.listBucket, [
      for (final list in out.values)
        for (final a in list) a.storagePath,
    ]);
    return {
      for (final entry in out.entries)
        entry.key: [
          for (final a in entry.value) urls[a.storagePath] == null ? a : a.copyWith(url: urls[a.storagePath]),
        ],
    };
  }

  /// One article of a restored list, back with everything the columns hold —
  /// including whether it had already been checked off, which is a second
  /// statement because `addItem` has no say over it.
  Future<ShoppingListItem> _restoreItem(String listId, ShoppingListItem item) async {
    final saved = await _repo.addItem(
      listId: listId,
      text: item.text,
      sub: item.sub,
      unit: item.unit,
      iconKey: item.iconKey,
      linkUrl: item.linkUrl,
      assigneeId: item.assigneeId,
      position: item.position,
    );
    if (!item.done) return saved;
    return _repo.setDone(saved.id, true);
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
  ///
  /// A count typed into the name is moved into the quantity circle where it
  /// belongs — "Reis x3" is one Reis, three times — under the narrow rules in
  /// [parseArticleQuantity], which leaves the line alone whenever it isn't sure.
  /// A unit read out of the text beats [unit] from the add row's chip: it is
  /// the more specific of the two and it is the one just typed.
  /// [matchIcon] is the add line saying whether the picture is still the
  /// matcher's business. It is false when the reader has already answered —
  /// they took the guessed picture off with its own little x — and then no
  /// icon is stored at all, which on a Lebensmittel list draws the general
  /// shopping cart (see `_ItemIcon`). Without it a cleared picture came
  /// straight back: `iconKey: null` means "you decide" everywhere else in this
  /// file, and the matcher decided the same thing it had just been overruled
  /// on.
  Future<void> addItem(String text, {String? iconKey, bool matchIcon = true, String? unit}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final targetId = _targetListId();
    if (targetId == null) return;

    final grocery = _isGrocery(targetId);
    final article = parseArticleQuantity(trimmed, grocery: grocery);
    final newUnit = article.unit ?? unit;

    final current = state.itemsFor(targetId);
    // Newest first, and one below the lowest sibling so the server agrees.
    final position = current.isEmpty ? 0 : current.map((i) => i.position).reduce((a, b) => a < b ? a : b) - 1;
    // **Only a Lebensmittel article picks its own picture.** A Sonstige one
    // takes the icon the reader chose and nothing otherwise — see
    // [planItemIconKey] for why the matcher stopped guessing here.
    final icon =
        iconKey ??
        (grocery && matchIcon ? suggestIcon(article.text, subject: IconSubject.groceryArticle)?.key : null);

    final optimistic = ShoppingListItem(
      id: _tempId(),
      listId: targetId,
      text: article.text,
      sub: article.amount,
      unit: newUnit,
      iconKey: icon,
      createdBy: _userId,
      position: position,
    );
    _putItem(targetId, [optimistic, ...state.itemsByList[targetId] ?? const []]);

    try {
      final saved = await _repo.addItem(
        listId: targetId,
        text: article.text,
        sub: article.amount,
        unit: newUnit,
        iconKey: icon,
        position: position,
      );
      if (!mounted) return;
      // Reconcile in place: the row keeps its slot and swaps its id for the
      // real uuid, so a tick landing right after the insert has something to
      // write to.
      _replaceItem(targetId, optimistic.id, saved);
    } catch (_) {
      if (!mounted) return;
      _removeItemLocally(targetId, optimistic.id);
      _fail(L.s.itemSaveFailed);
    }
  }

  /// Which list a typed article lands in: the one you are in, or — in the
  /// pooled view — the one its add line says it will file into. That used to be
  /// "the first real list", silently, which made "Alle Artikel" the one place
  /// where typing an article put it somewhere the screen never named.
  String? _targetListId() =>
      state.openId == summaryListId ? state.summaryTargetId : state.openId;

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

    // Renaming re-matches on a Lebensmittel list and leaves a Sonstige one
    // alone, which also means a picture the reader picked there survives a
    // typo being fixed.
    final icon = name == item.text || !_isGrocery(item.listId)
        ? item.iconKey
        : suggestIcon(name, subject: IconSubject.groceryArticle)?.key;

    _patchItem(
      item.listId,
      item.id,
      (i) => i.copyWith(
        text: name,
        sub: newSub,
        clearSub: newSub == null,
        iconKey: icon,
        clearIconKey: icon == null,
      ),
    );

    try {
      final saved = await _repo.editItem(item.id, text: name, sub: newSub, iconKey: icon);
      if (!mounted) return;
      _replaceItem(item.listId, item.id, saved);
    } catch (_) {
      if (!mounted) return;
      _patchItem(item.listId, item.id, (_) => item);
      _fail(L.s.changeSaveFailed);
    }
  }

  /// Changes what an article's count counts — kg, ml, Packung. Its own method
  /// rather than a parameter on [editItem]: the unit comes from a picker, the
  /// name and the count from the row's own fields, and writing all three
  /// together would let a half-finished edit overwrite a unit nobody touched.
  ///
  /// `null` is the default (Stück) and is what gets stored for it.
  Future<void> setUnit(ShoppingListItem item, String? unit) async {
    if (_isTemp(item.id)) return;
    if (unit == item.unit) return;

    _patchItem(item.listId, item.id, (i) => i.copyWith(unit: unit, clearUnit: unit == null));

    try {
      final saved = await _repo.setUnit(item.id, unit);
      if (!mounted) return;
      _replaceItem(item.listId, item.id, saved);
    } catch (_) {
      if (!mounted) return;
      _patchItem(item.listId, item.id, (_) => item);
      _fail(L.s.changeSaveFailed);
    }
  }

  /// Corrects the picture in front of an article, or takes it off with `null`.
  ///
  /// The matcher is a guess made from a name, and a guess is wrong often enough
  /// that it has to be answerable — `Paprika Gewürz` is a jar of spice and gets
  /// a pepper. Taking it off is not "no picture": a Lebensmittel row with no
  /// icon draws the general shopping cart, which is the honest answer where
  /// nothing recognised the line.
  ///
  /// Beside [setUnit] and written the same way, optimistically and one column
  /// at a time. Note that renaming the article puts the matcher back in charge
  /// — see [editItem], where a changed name re-matches — so this is a decision
  /// about *this* name rather than a lock on the row.
  Future<void> setItemIcon(ShoppingListItem item, String? iconKey) async {
    if (_isTemp(item.id)) return;
    if (iconKey == item.iconKey) return;

    _patchItem(
      item.listId,
      item.id,
      (i) => i.copyWith(iconKey: iconKey, clearIconKey: iconKey == null),
    );

    try {
      final saved = await _repo.setIcon(item.id, iconKey);
      if (!mounted) return;
      _replaceItem(item.listId, item.id, saved);
    } catch (_) {
      if (!mounted) return;
      _patchItem(item.listId, item.id, (_) => item);
      _fail(L.s.changeSaveFailed);
    }
  }

  /// Puts the shop page an article is about on it, or takes it off with
  /// `null`.
  ///
  /// Its own write beside [setUnit] and for the same reason: the URL is pasted
  /// into a sheet, the name and the count are typed into the row, and neither
  /// edit has any business restating the other.
  ///
  /// Reports by **returning false** rather than through [_fail], which is the
  /// one write here that does: setting a link happens inside a sheet that is
  /// still up when the answer comes back, and a message under the field is
  /// worth more there than a snack behind it. The caller that has no sheet —
  /// the menu's "Link entfernen" — snacks it itself.
  Future<bool> setLink(ShoppingListItem item, String? url) async {
    if (_isTemp(item.id)) return false;
    if (url == item.linkUrl) return true;

    _patchItem(item.listId, item.id, (i) => i.copyWith(linkUrl: url, clearLinkUrl: url == null));

    try {
      final saved = await _repo.setLink(item.id, url);
      if (!mounted) return true;
      _replaceItem(item.listId, item.id, saved);
      return true;
    } catch (_) {
      if (mounted) _patchItem(item.listId, item.id, (_) => item);
      return false;
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
      // The last article ticked on a list of any size is the errand done — one
      // of the few moments the rating prompt may consider. [ReviewPrompt]
      // decides whether it actually asks.
      if (next) {
        final items = state.itemsByList[listId] ?? const <ShoppingListItem>[];
        if (items.length >= 3 && items.every((i) => i.done)) unawaited(reviewPrompt.maybeAsk());
      }
    } catch (_) {
      if (!mounted) return;
      _patchItem(listId, itemId, (_) => before);
      _fail(L.s.saveFailed);
    }
  }

  /// "Erledigte löschen". Rows the database refused to delete (someone else's
  /// article, cleared by a non-admin) come straight back rather than
  /// disappearing until the next reload.
  Future<void> clearDone(List<ShoppingListItem> doneItems) async {
    final ids = [
      for (final i in doneItems)
        if (!_isTemp(i.id)) i.id,
    ];
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
      _fail(L.s.someDoneItemsNotDeleted);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(itemsByList: previous, error: L.s.doneItemsDeleteFailed);
    }
  }

  /// Drops a single item, from its row's menu or its swipe action. Keyed by the
  /// item's *own* list, not the open one: in "Alle Artikel" those differ.
  ///
  /// Returns what it takes to put the article back, for the confirmation chip's
  /// "Rückgängig" to hand to [restoreItem] — or null when there is nothing to
  /// offer, which is a row still in flight or a delete the server refused.
  Future<DeletedListItem?> removeItem(ShoppingListItem item) async {
    final previous = state.itemsByList;
    final index = (previous[item.listId] ?? const <ShoppingListItem>[]).indexWhere((i) => i.id == item.id);
    final attachments = state.attachmentsFor(item);
    _removeItemLocally(item.listId, item.id);
    state = state.copyWith(justMoved: '');
    // A row that never reached the server has nothing to restore *to*: undo
    // would insert an article the delete never removed.
    if (_isTemp(item.id)) return null;

    try {
      await _repo.deleteItem(item.id);
      // The rows went with it (`item_id … on delete cascade`), so the map has
      // to let go of them too — only now that the delete has actually landed,
      // since the branch below puts the article back on screen.
      if (attachments.isNotEmpty && mounted) _putAttachments(item.id, const []);
      return DeletedListItem(item: item, attachments: attachments, index: index < 0 ? 0 : index);
    } catch (_) {
      if (!mounted) return null;
      state = state.copyWith(itemsByList: previous, error: L.s.itemDeleteFailed);
      return null;
    }
  }

  /// Puts one deleted article back — a re-insert under a new id, the same deal
  /// as [restoreList] and for the same reason: the row is gone.
  ///
  /// The attached files are **not** copied the way a restored list's are. Those
  /// objects are filed under the *list*, which is still there and still owns
  /// them — deleting an article drops its `list_item_attachments` rows and
  /// leaves the objects where they were — so undo only has to point new rows at
  /// the same paths. Their signed URLs are carried over with them, since they
  /// name the very same object.
  Future<bool> restoreItem(DeletedListItem deleted) async {
    try {
      final saved = await _restoreItem(deleted.item.listId, deleted.item);
      final files = <ItemAttachment>[];
      for (final file in deleted.attachments) {
        // Best-effort per file, like every other restore here: one attachment
        // that won't come back must not cost the article.
        try {
          final row = await _repo.addAttachment(
            itemId: saved.id,
            storagePath: file.storagePath,
            name: file.name,
            isImage: file.isImage,
          );
          files.add(row.copyWith(url: file.url, localPath: file.localPath));
        } catch (_) {}
      }
      if (!mounted) return false;

      final items = [...state.itemsFor(deleted.item.listId)];
      items.insert(deleted.index.clamp(0, items.length), saved);
      _putItem(deleted.item.listId, items);
      if (files.isNotEmpty) _putAttachments(saved.id, files);
      return true;
    } catch (_) {
      _fail(L.s.itemRestoreFailed);
      return false;
    }
  }

  /// Files the picked photo/document under its article. Appends rather than
  /// replaces: picking a second photo adds to the first.
  ///
  /// **Object first, row second.** A row naming an object that isn't there
  /// draws a broken thumbnail for the whole household, while an object no row
  /// names is a few kilobytes nobody can reach — so the upload has to have
  /// landed before anything points at it.
  ///
  /// The picked file's own path is carried on the result as
  /// [ItemAttachment.localPath] and drawn in preference to the signed URL for
  /// the rest of the session: it is already on this disk, so there is nothing
  /// to fetch and no wait between the tap and the picture.
  Future<void> addAttachment(ShoppingListItem item, PickedFile picked) async {
    if (_isTemp(item.id)) return; // Still in flight; there is no row to hang it on.

    try {
      final path = await _photos.upload(
        bucket: PhotoRepository.listBucket,
        containerId: item.listId,
        file: File(picked.path),
      );
      final saved = await _repo.addAttachment(
        itemId: item.id,
        storagePath: path,
        name: picked.name,
        isImage: picked.isImage,
      );
      final urls = await _photos.signUrls(PhotoRepository.listBucket, [path]);
      if (!mounted) return;
      _putAttachments(item.id, [
        ...state.attachmentsFor(item),
        saved.copyWith(url: urls[path], localPath: picked.path),
      ]);
    } catch (_) {
      if (!mounted) return;
      _fail(L.s.photoUploadFailed);
    }
  }

  /// Takes one file off an article — the row, then the object.
  ///
  /// `list_item_attachments_delete` is the uploader's own rows only, so
  /// somebody else's photo comes back as an empty result rather than as a
  /// raise; the row is put back on screen in that case, because it is still
  /// there on the server.
  Future<void> removeAttachment(ShoppingListItem item, ItemAttachment attachment) async {
    final previous = state.attachmentsFor(item);
    _putAttachments(item.id, [
      for (final a in previous)
        if (a.id != attachment.id) a,
    ]);

    try {
      await _repo.deleteAttachment(attachment.id);
      await _photos.remove(PhotoRepository.listBucket, [attachment.storagePath]);
    } catch (_) {
      if (!mounted) return;
      _putAttachments(item.id, previous);
      _fail(L.s.photoRemoveFailed);
    }
  }

  void _putAttachments(String itemId, List<ItemAttachment> attachments) {
    final map = Map<String, List<ItemAttachment>>.from(state.attachments);
    if (attachments.isEmpty) {
      map.remove(itemId);
    } else {
      map[itemId] = attachments;
    }
    state = state.copyWith(attachments: map);
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
    _putItem(listId, [
      for (final i in items)
        if (i.id != itemId) i,
    ]);
  }

  void _removeItemsLocally(Set<String> itemIds) {
    state = state.copyWith(
      itemsByList: {
        for (final entry in state.itemsByList.entries)
          entry.key: [
            for (final i in entry.value)
              if (!itemIds.contains(i.id)) i,
          ],
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
  final notifier = ListNotifier(
    ref.watch(listRepositoryProvider),
    ref.watch(photoRepositoryProvider),
    ref.watch(currentUserIdProvider),
    ref.watch(familyProvider.select((s) => s.household?.id)),
  );
  reloadOnFamilyChange(ref, const {'lists', 'list_items'}, notifier.load);
  return notifier;
});
