import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/amazon.dart';
import '../data/brand_colors.dart';
import '../data/grocery_catalog.dart';
import '../data/grocery_search.dart';
import '../data/icon_suggestions.dart';
import '../data/list_data.dart';
import '../models/attachment.dart';
import '../models/event_link.dart';
import '../models/grocery_unit.dart';
import '../models/shopping_list.dart';
import '../services/external_links.dart';
import '../services/media_picker.dart';
import '../services/share_out.dart';
import '../state/auth_state.dart';
import '../state/family_state.dart';
import '../state/list_state.dart';
import '../state/nav_state.dart';
import '../state/sharing_state.dart';
import '../theme/tokens.dart';
import 'calendar_screen.dart';
import 'list/list_island.dart';
import 'list/planner_card.dart';
import '../widgets/paywall_sheet.dart';
import '../widgets/anchored_menu.dart';
import '../widgets/app_sheet.dart';
import '../widgets/avatar.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/check_off.dart';
import '../widgets/collapsing_header.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_note.dart';
import '../widgets/expandable_title.dart';
import '../widgets/event_link_chip.dart';
import '../widgets/floating_pill.dart';
import '../widgets/glass.dart';
import '../widgets/icon_picker.dart';
import '../widgets/markdown_text.dart';
import '../widgets/overview_screen.dart';
import '../widgets/search.dart';
import '../widgets/segmented_control.dart';
import '../widgets/share_sheet.dart';
import '../widgets/swipe_actions.dart';
import '../widgets/toast_chip.dart';
import '../widgets/visibility_picker.dart';
import '../models/entitlements.dart';
import '../l10n/l10n.dart';
import '../theme/app_icons.dart';

/// Label colour of a checked-off item — the strike-through fades the open row's
/// text to it, so landing in "Erledigt" isn't a colour jump.
Color get _itemDoneInk => AppColors.doneInk;

/// An article's name. Shared with the field that replaces it while the row is
/// being edited — same family, size and weight, so tapping a name doesn't make
/// the text move.
TextStyle get _itemTextStyle => AppText.itemTitle;

/// The number in the quantity circle, and the field it turns into. A step
/// firmer than [AppText.label] was as a subtitle: it is a single glyph or two
/// inside a shape of its own, and grey-on-grey at w300 would disappear in it.
TextStyle get _quantityStyle =>
    AppText.caption.copyWith(color: AppColors.inkSecondary, fontWeight: FontWeight.w600);

/// Whether an article's own list holds food — asked of the item rather than of
/// the open list, because "Alle Artikel" pools every list's articles into one
/// view and a Sonstige row in it is still a Sonstige row.
bool _isGroceryList(WidgetRef ref, String listId) =>
    ref.watch(listProvider).listById(listId)?.kind == ListKind.grocery;

/// Whether a Sonstige list's rows keep an icon slot: when at least one of its
/// articles — open or done — carries an icon the catalogs can draw. Per list,
/// so every row of it lines its words up in the same column.
/// The Amazon marketplace for this article's row, or null to draw no badge.
///
/// Null for a grocery list, null while no partner tag is configured at all, and
/// null when the device's region and the app's language between them name no
/// marketplace we have a tag for. **The region comes from the phone's own
/// setting** — no IP lookup, no permission, and the household's address stays
/// where it is; see [amazonMarketplace].
String? _amazonFor(WidgetRef ref, ShoppingListItem item) {
  if (!amazonConfigured) return null;
  final list = ref.watch(listProvider).lists.where((l) => l.id == item.listId).firstOrNull;
  if (list == null || list.kind == ListKind.grocery) return null;
  return amazonMarketplace(
    countryCode: PlatformDispatcher.instance.locale.countryCode,
    languageCode: L.s.localeCode,
  );
}

bool _listHasSymbols(WidgetRef ref, String listId) =>
    (ref.watch(listProvider).itemsByList[listId] ?? const []).any((i) => resolveIcon(i.iconKey) != null);

/// A Sonstige article's icon in the 42 slot a grocery picture gets — drawn the
/// way the Vorhaben card previewed it, or left empty when nothing matched.
class _SymbolSlot extends StatelessWidget {
  final String? iconKey;

  const _SymbolSlot({required this.iconKey});

  @override
  Widget build(BuildContext context) {
    // 38 at the shipped type scale, but it grows with the text size, and the
    // slot has to grow with it rather than clip the disc.
    final mark = AppText.rowMark;
    final side = mark > 42 ? mark : 42.0;
    return SizedBox(
      width: side,
      height: side,
      child: resolveIcon(iconKey) == null
          ? null
          : Center(
              child: IconTile(iconKey: iconKey, size: mark, imageSize: AppText.markImage(mark)),
            ),
    );
  }
}

/// A text field that has to pass for the label it replaced: no border, no
/// underline, and none of the vertical padding a [TextField] carries by
/// default.
InputDecoration _inlineFieldDecoration(String hint, TextStyle style) => InputDecoration(
  border: InputBorder.none,
  isDense: true,
  contentPadding: EdgeInsets.zero,
  hintText: hint,
  hintStyle: style.copyWith(color: AppColors.mutedLight),
);

class ListScreen extends ConsumerWidget {
  const ListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(listProvider);

    // A write that didn't land is reported once, transiently, and then
    // forgotten — so the same message can appear again if the next attempt
    // fails too. A failed *load* is deliberately not snacked: it leaves an
    // empty screen behind, which needs an explanation that stays put, and the
    // body renders an [ErrorNote] with a retry for exactly that case.
    ref.listen<String?>(listProvider.select((s) => s.error), (_, message) {
      if (message == null) return;
      final current = ref.read(listProvider);
      if (current.lists.isEmpty && !current.loading) return;
      showErrorSnack(context, message);
      ref.read(listProvider.notifier).clearError();
    });

    // Arriving from a list card in an event's detail sheet. The shell has
    // already switched tab; opening the list is Listen's own half of it.
    ref.listen<TabJump?>(tabJumpProvider, (_, jump) {
      if (jump?.listId case final id?) {
        ref.read(tabJumpProvider.notifier).done();
        ref.read(listProvider.notifier).open(id);
      }
    });

    return Scaffold(
      backgroundColor: AppColors.surface,
      // The detail screen goes edge to edge on purpose: its header carries a
      // brand-colored glow that has to start at the very top of the display, so
      // it absorbs the status-bar inset itself (see [CollapsingHeaderScreen])
      // rather than being pushed below a white band.
      body: state.isDetail
          ? _ListDetail(state: state)
          : SafeArea(bottom: false, child: _ListOverview(state: state)),
    );
  }
}

class _ListOverview extends ConsumerWidget {
  final ListScreenState state;

  const _ListOverview({required this.state});

  /// First-frame estimate only — the island's row plus the gap above it.
  /// [CollapsingHeaderScreen] re-measures the real thing once it's laid out.
  static double get _extraHeight => 16 + ListIsland.rowHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SearchableOverviewScreen(
      title: L.s.listsTitle,
      searchHint: L.s.searchListsAndItems,
      searchPrompt: L.s.searchListsAndItemsLong,
      onAdd: () => openListSheet(context, ref),
      addLabel: L.s.newList,
      // The one line under the title, and the way into Vorhaben. Always drawn:
      // the model is behind `list-plan` now, so no build is "unconfigured" —
      // a project missing the secret says so in the card rather than hiding
      // the feature. Not `const`: it reads the palette in its own build, see
      // `tool/check_const_palette.dart`.
      headerExtra: SizedBox(
        height: ListIsland.rowHeight,
        child: Row(children: [Expanded(child: ListIsland())]),
      ),
      extraHeight: _extraHeight,
      body: (context) => [
        // Vorhaben, unfolding from the island above it. Always in the tree so
        // it can size and fade in both directions (see the expand/collapse rule
        // in docs/design-system.md); it draws nothing at all while closed.
        PlannerCard(),
        if (_loadFailed)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: ErrorNote(message: state.error!, onRetry: () => ref.read(listProvider.notifier).load()),
          ),
        // Not while the first load is still out — an account with twelve lists
        // must not be told it has none.
        if (state.lists.isEmpty && !state.loading && state.error == null)
          EmptyState(
            icon: AppIcons.listPlus,
            iconColor: Theme.of(context).colorScheme.primary,
            message: L.s.noListsYet,
          ),
        if (state.lists.isNotEmpty) _listsCard(context, ref),
      ],
      results: (context, query, closeSearch) => _searchResults(context, ref, query, closeSearch),
    );
  }

  /// Every list on one card, Lebensmittel and Sonstige together and in the order
  /// they were loaded.
  ///
  /// They used to be split into "Übersicht" / "Lebensmittel" / "Sonstige", which
  /// on a household with three lists produced three headings over three cards
  /// holding one row each — the sections said more about the data model than
  /// about anything the user was looking for. What kind a list is is already
  /// visible in its symbol, and the pooled "Alle Artikel" row is just the first
  /// row of the same card, present only once there are two lists to pool (see
  /// [ListScreenState.showSummary]).
  Widget _listsCard(BuildContext context, WidgetRef ref) {
    final rows = <ShoppingList>[if (state.showSummary) allList, ...state.lists];
    return SectionCard(
      children: dividedRows([
        for (final list in rows)
          // "Alle Artikel" is computed rather than stored, so there is nothing
          // there to rename or delete — it gets the plain row.
          if (list.isSummary)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => ref.read(listProvider.notifier).open(list.id),
              child: _ListRow(list: list, state: state),
            )
          else
            SwipeToEditDelete(
              identity: list.id,
              onTap: () => ref.read(listProvider.notifier).open(list.id),
              onEdit: () => openListSheet(context, ref, list: list),
              onDelete: () async {
                final confirm = confirmChipOf(context);
                final notifier = ref.read(listProvider.notifier);
                if (await notifier.deleteList(list.id) case final deleted?) {
                  confirm(L.s.listDeleted, undo: () => notifier.restoreList(deleted));
                }
              },
              child: _ListRow(list: list, state: state),
            ),
      ]),
    );
  }

  /// Nothing on screen and a message saying why — as opposed to a write that
  /// failed while the screen still has content, which gets a snack instead.
  bool get _loadFailed => state.error != null && !state.loading && state.lists.isEmpty;

  /// Search covers the *contents* of every list, not just their names — the
  /// thing you're looking for ("Milch") is an article inside a list far more
  /// often than it is a list. Hits are grouped by the list they live in, and
  /// tapping one opens that list, so the results double as a way in.
  Widget? _searchResults(BuildContext context, WidgetRef ref, String query, VoidCallback closeSearch) {
    void open(String id) {
      closeSearch();
      ref.read(listProvider.notifier).open(id);
    }

    final matchedLists = state.lists
        .where((l) => listMatchesQuery(l.name, query, iconKey: l.iconKey))
        .toList();
    final itemHits = <(ShoppingList, List<ShoppingListItem>)>[];
    for (final l in state.lists) {
      final hits = state.itemsFor(l.id).where((i) => _itemMatches(i, query)).toList();
      if (hits.isNotEmpty) itemHits.add((l, hits));
    }

    if (matchedLists.isEmpty && itemHits.isEmpty) return null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (matchedLists.isNotEmpty)
          SearchHitGroup(
            first: true,
            label: L.s.listsTitle,
            count: L.s.matchCount(matchedLists.length),
            rows: [
              for (final list in matchedLists)
                GestureDetector(
                  // Without this the row is only tappable where a glyph is
                  // actually painted — the padding and the gap before the
                  // chevron fall through.
                  behavior: HitTestBehavior.opaque,
                  onTap: () => open(list.id),
                  child: _ListRow(list: list, state: state),
                ),
            ],
          ),
        for (final (index, (list, hits)) in itemHits.indexed)
          SearchHitGroup(
            first: index == 0 && matchedLists.isEmpty,
            label: list.name,
            count: L.s.itemCount(hits.length),
            icon: IconTile(iconKey: list.iconKey, size: 26, imageSize: 17),
            rows: [
              for (final hit in hits)
                SearchResultRow(
                  // The article's own picture only where the list shows one;
                  // a Sonstige hit wears its list's icon, which is what says
                  // where the row was found anyway.
                  leading: IconTile(
                    iconKey: (list.kind == ListKind.grocery ? hit.iconKey : null) ?? list.iconKey,
                    size: AppText.rowMark,
                    imageSize: AppText.markImage(AppText.rowMark),
                  ),
                  title: hit.text,
                  subtitle: hit.done ? L.s.doneInList(list.name) : (hit.sub ?? L.s.inList(list.name)),
                  onTap: () => open(list.id),
                ),
            ],
          ),
      ],
    );
  }
}

/// The create/edit sheet for a list. Same sheet either way — [list] set means
/// editing — so the symbol behaves identically in both.
///
/// [eventLink] files the new list against the appointment it was started from,
/// so reopening that event shows the list instead of offering to create it a
/// second time. Never passed when editing: a list belongs to the event it was
/// made for, and nothing re-points it.
///
/// [initialName] opens a *create* sheet with the name already typed — what the
/// event detail sheet hands over when a list is started from an appointment.
/// It only seeds the field: the name stays editable, and because it differs
/// from the empty `list?.name`, `suggestIcon` treats it as a typed name and
/// picks the icon off it like any other.
void openListSheet(
  BuildContext context,
  WidgetRef ref, {
  ShoppingList? list,
  String? initialName,
  EventLink? eventLink,
}) {
  final nameController = TextEditingController(text: list?.name ?? initialName ?? '');
  // What the greyed check points at when the name is still empty — see
  // [showAppSheet].
  final nameFocus = FocusNode();
  // **A suggested name arrives selected, so typing replaces it.** A list
  // started from an appointment opens carrying the event's name, which is a
  // good name and the reason the row is worth a tap — but it is a *suggestion*,
  // and a suggestion you have to clear by hand is a decision already made for
  // you. Selected, one keystroke is enough to overwrite it and the check alone
  // is enough to keep it. It also means the name can be changed without
  // tapping into the field, which is what people reported not working.
  //
  // Only for a name we suggested. Editing a list puts the cursor at the end of
  // the name the household chose: select-all there is one stray keystroke away
  // from wiping it.
  if (list == null && (initialName?.trim().isNotEmpty ?? false)) {
    nameController.selection = TextSelection(baseOffset: 0, extentOffset: nameController.text.length);
  }
  final notifier = ref.read(listProvider.notifier);
  // Set once, up front: the segmented control lives on the provider (it is what
  // `newType` is for), and an edit sheet has to open on the list's own kind.
  notifier.setNewType(list == null || list.kind == ListKind.grocery ? 'grocery' : 'other');
  // Same for "Für wen?", which is now two values (`visibility` + the members in
  // `list_shares`) rather than one `who` string.
  notifier.primeVisibility(list);
  // The manual override, if the user makes one. Held out here rather than in
  // the body's State so the sheet's save button — which is the shared chrome's,
  // not ours — can read it.
  //
  // Empty even when editing, and that is the point: seeding it with the list's
  // stored icon made every edit look like a manual pick, so retyping the name
  // left the old icon in the preview *and* sent it to [ListNotifier.updateList]
  // as an explicit `iconKey` — which is the one argument that switches the
  // "icon follows a changed name" rule off. Renaming *Rewe* to *Baumarkt* kept
  // the REWE logo. The body shows the stored icon from [list] while the name is
  // untouched; nothing but the picker writes to this.
  final draft = IconDraft(null);
  showAppSheet(
    context: context,
    title: list == null ? L.s.newList : L.s.editList,
    // A list with no name is not a list, so the check stays inert until there
    // is one — see [showAppSheet]'s `requiredField`.
    requiredField: nameController,
    requiredFocus: nameFocus,
    heightFactor: 0.72,
    onSave: () async {
      final kind = ref.read(listProvider).newType == 'grocery' ? ListKind.grocery : ListKind.other;
      // The sheet has already been popped by the chrome, so the chip lands on
      // the screen behind it, where the row it is talking about just changed.
      final confirm = confirmChipOf(context);
      if (list != null) {
        // Opened and closed with the check, nothing touched: no write, and no
        // "Liste aktualisiert" for a change that never happened.
        final current = ref.read(listProvider);
        final typed = nameController.text.trim();
        final unchanged =
            (typed.isEmpty || typed == list.name) &&
            kind == list.kind &&
            draft.picked == null &&
            current.newVisibility == list.visibility &&
            setEquals(current.newSharedWith, list.sharedWith.toSet());
        if (unchanged) return;
        if (await notifier.updateList(
          list.id,
          name: nameController.text,
          kind: kind,
          iconKey: draft.picked,
        )) {
          confirm(L.s.listUpdated);
        }
        return;
      }
      if (await notifier.createList(
        name: nameController.text,
        kind: kind,
        iconKey: draft.picked,
        // Only ever on the create path: the list remembers which appointment it
        // was started from, and the edit sheet has no say in it.
        eventLink: eventLink,
      )) {
        confirm(L.s.listCreated);
      }
    },
    child: _ListSheetBody(nameController: nameController, nameFocus: nameFocus, draft: draft, list: list),
  );
}

class _ListSheetBody extends ConsumerStatefulWidget {
  final TextEditingController nameController;
  final FocusNode nameFocus;
  final IconDraft draft;

  /// The list being edited, or null when creating one — the sheet needs its
  /// stored icon and its old name to tell "not touched yet" from "renamed".
  final ShoppingList? list;

  const _ListSheetBody({
    required this.nameController,
    required this.nameFocus,
    required this.draft,
    this.list,
  });

  @override
  ConsumerState<_ListSheetBody> createState() => _ListSheetBodyState();
}

class _ListSheetBodyState extends ConsumerState<_ListSheetBody> {
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(listProvider);
    final isGrocery = s.newType == 'grocery';
    final name = widget.nameController.text;
    // The live guess: recomputed on every keystroke, and only used while
    // nothing has been picked by hand.
    //
    // `allowGrocery: false` even on a Lebensmittel list — *especially* there.
    // A grocery picture is a photograph of one article, so a list called
    // "Milch" came out wearing a milk carton as though the list were the
    // carton. The list gets a symbol or the shop's logo; the article photos
    // belong to the rows inside it (see [_AddItemRow]).
    final suggestion = suggestIcon(name, subject: IconSubject.list);
    // Exactly what [ListNotifier.updateList] will store, so the preview can't
    // promise one icon and save another: a hand-picked one wins; an untouched
    // name keeps the icon the list already has; a changed name goes back to the
    // matcher, including when it matches nothing (the list then falls back to
    // the generic glyph rather than keeping a logo for a shop it is no longer
    // named after).
    final untouched = name.trim() == (widget.list?.name ?? '');
    final stored = untouched ? widget.list?.iconKey : null;
    final iconKey = widget.draft.picked ?? stored ?? suggestion?.key;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 2, bottom: 8),
          child: Text(L.s.whichKindOfList, style: AppText.microLabel),
        ),
        SegmentedControl<String>(
          value: isGrocery ? 'grocery' : 'other',
          onChanged: ref.read(listProvider.notifier).setNewType,
          options: [
            SegmentedOption(value: 'grocery', label: L.s.groceries, icon: AppIcons.clipboardText),
            SegmentedOption(value: 'other', label: L.s.otherKind, icon: AppIcons.listChecks),
          ],
        ),
        const SizedBox(height: 14),
        SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: TextField(
                controller: widget.nameController,
                focusNode: widget.nameFocus,
                // Every new list, whether or not it came with a suggested name
                // — the name is the first and often only thing to fill in, and
                // a suggested one is selected (above) so the keyboard is the
                // way to replace it rather than noise over a finished field.
                // An edit sheet keeps the keyboard down: it opens onto the
                // icon and the "Für wen?" rows, which are what people come to
                // change.
                autofocus: widget.list == null,
                textInputAction: TextInputAction.done,
                style: AppText.inputTitle,
                decoration: InputDecoration(border: InputBorder.none, hintText: L.s.listName, isDense: true),
                // A picked icon is *not* cleared by typing on: overriding the
                // guess and then fixing a typo shouldn't undo the override.
                onChanged: (_) => setState(() {}),
              ),
            ),
            CardDivider(),
            IconFieldRow(
              iconKey: iconKey,
              // The sparkle means "the name chose this" — not true of the icon
              // an edit sheet opens on.
              suggested: widget.draft.picked == null && stored == null,
              fallbackIcon: isGrocery ? AppIcons.shoppingCart : AppIcons.listChecks,
              onTap: () async {
                final picked = await showIconPicker(
                  context,
                  selected: iconKey,
                  name: name,
                  subject: IconSubject.list,
                );
                if (picked != null && mounted) setState(() => widget.draft.picked = picked);
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Writes `lists.visibility` plus the rows in `list_shares` — not the
        // old single `who` string, which conflated "who does this" with "who
        // may see it". The member chips are dropped for a guest: the composite
        // foreign key behind `list_shares` makes picking somebody outside the
        // owning household a constraint error, not a polite refusal.
        VisibilityPicker(
          visibility: s.newVisibility,
          sharedWith: s.newSharedWith,
          onChanged: ref.read(listProvider.notifier).setVisibility,
          members: ref.watch(householdMembersProvider),
          currentUserId: ref.watch(currentUserIdProvider),
          allowMembers: !s.isGuest,
          noun: L.s.theList,
        ),
        // Who outside the household is in, and the invitations still out. This
        // used to be the Teilen sheet's job; "Teilen" now goes straight to the
        // system share sheet, so the list's own edit sheet is where it lives.
        if (widget.list case final list?
            when ref.watch(canShareExternallyProvider) &&
                !s.guestListIds.contains(list.id) &&
                s.sharedOutIds.contains(list.id))
          _SharedOutsideSection(listId: list.id),
      ],
    );
  }
}

/// The list whose invitation is being minted while "Teilen" waits on the
/// server — the header's menu button is a spinner for that moment.
final _sharingListId = ValueNotifier<String?>(null);

/// The header's menu button, so an iPad's share popover has something to point
/// at. One detail view is mounted at a time, so one key is enough.
final _shareAnchorKey = GlobalKey();

/// "Teilen" on a list: mint an invitation, then hand it straight to the system
/// share sheet — no sheet of ours in between.
///
/// **The link has to exist before the sheet can offer it**, which is the only
/// wait. Only its hash is stored, so a link from a sheet that was closed
/// without sending is one nobody holds, and it is revoked on the spot. Every
/// invitation runs out after [shareInvitationDays]; people who came in keep
/// their access. Who is in, and what is still out, is in the list's edit
/// sheet ([_SharedOutsideSection]).
Future<void> _shareListOut(BuildContext context, WidgetRef ref, ShoppingList list) async {
  if (_sharingListId.value != null) return;
  final lists = ref.read(listProvider.notifier);
  final confirm = confirmChipOf(context);
  final box = _shareAnchorKey.currentContext?.findRenderObject() as RenderBox?;
  final anchor = box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;

  _sharingListId.value = list.id;
  final MintedLink link;
  try {
    link = await mintShareLink((kind: ShareableKind.list, id: list.id), expiresInDays: shareInvitationDays);
  } on ShareLinkFailure catch (e) {
    if (context.mounted) showErrorSnack(context, e.message);
    return;
  } finally {
    _sharingListId.value = null;
  }

  switch (await shareOut(text: L.s.shareListMessage(list.name), url: link.url, anchor: anchor)) {
    case ShareOutcome.cancelled:
      await revokeUnsentShareLink(link.id);
      return;
    case ShareOutcome.copied:
      confirm(L.s.copied);
    case ShareOutcome.sent || ShareOutcome.unconfirmed:
      break;
  }
  await lists.refreshSharedOut();
}

/// Somebody outside the household can reach this list, or has been invited to.
class _SharedOutsideMark extends StatelessWidget {
  final double size;

  const _SharedOutsideMark({required this.size});

  @override
  Widget build(BuildContext context) => Semantics(
    label: L.s.sharedOutsideLabel,
    excludeSemantics: true,
    child: AppIcon(AppIcons.users, size: size, color: AppColors.muted),
  );
}

/// "Geteilt mit" in a list's edit sheet: the guests, each removable, and one
/// row for the invitations nobody has used yet.
///
/// Removing acts at once rather than on the sheet's check — it is somebody's
/// access, not a draft of the list.
class _SharedOutsideSection extends ConsumerWidget {
  final String listId;

  const _SharedOutsideSection({required this.listId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ShareTarget target = (kind: ShareableKind.list, id: listId);
    final sharing = ref.watch(sharingProvider(target));
    final notifier = ref.read(sharingProvider(target).notifier);
    final lists = ref.read(listProvider.notifier);

    ref.listen<String?>(sharingProvider(target).select((s) => s.error), (_, message) {
      if (message == null) return;
      showErrorSnack(context, message);
      notifier.clearError();
    });

    final pending = sharing.pendingLinks;
    if (sharing.guests.isEmpty && pending.isEmpty) return const SizedBox.shrink();

    // The last day any of them can still be used. A link minted before
    // invitations expired has no date, and one of those means no end at all.
    DateTime? latest;
    for (final link in pending) {
      final at = link.expiresAt;
      if (at != null && (latest == null || at.isAfter(latest))) latest = at;
    }
    final until = latest == null || pending.any((l) => l.expiresAt == null)
        ? null
        : L.s.dayMonthShort(latest.day, latest.month);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(L.s.sharedOutsideTitle, style: AppText.microLabel),
        ),
        SectionCard(
          children: dividedRows([
            for (final guest in sharing.guests)
              GuestRow(
                guest: guest,
                onRemove: () async {
                  await notifier.removeGuest(guest.userId);
                  await lists.refreshSharedOut();
                },
              ),
            if (pending.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    AppIcon(AppIcons.link, size: 16, color: AppColors.inkSecondary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        L.s.openInvitations(pending.length, until),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.rowTitle,
                      ),
                    ),
                    GestureDetector(
                      onTap: () async {
                        await notifier.revokePending();
                        await lists.refreshSharedOut();
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                        child: Text(L.s.revoke, style: AppText.caption.copyWith(color: AppColors.danger)),
                      ),
                    ),
                  ],
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 2, top: 8),
          child: Text(L.s.shareIntroSecond(L.s.theList), style: AppText.label.copyWith(fontSize: 12.5)),
        ),
      ],
    );
  }
}

/// One list on the overview card. Carries no tap target of its own — the row is
/// wrapped either by a [SwipeToEditDelete] or by a plain [GestureDetector], and
/// a second detector inside would swallow the tap that closes an open swipe.
class _ListRow extends ConsumerWidget {
  final ShoppingList list;
  final ListScreenState state;

  const _ListRow({required this.list, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final its = state.itemsFor(list.id);
    final remaining = its.where((i) => !i.done).length;
    final meta = its.isEmpty ? L.s.empty : (remaining == 0 ? L.s.allDone : L.s.remaining(remaining));
    final metaColor = its.isNotEmpty && remaining == 0 ? AppColors.success : AppColors.muted;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 15),
      child: Row(
        children: [
          IconTile(
            iconKey: list.iconKey,
            size: AppText.rowMark,
            imageSize: AppText.markImage(AppText.rowMark),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(list.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.itemTitle),
                // The subtitle line: where the list came from, then how much of
                // it is left. In that order because the appointment is what the
                // list *is* — "Wochenende Hamburg" — and "3 verbleibend" is how
                // it is going; reading the second one first tells you a number
                // before you know what it counts.
                //
                // The chip used to sit on the right of the row, past the
                // visibility badge, where it was a glyph with no room for a
                // name and read as a third status icon rather than as part of
                // the list's own description.
                Row(
                  children: [
                    if (list.eventLink case final link?) ...[
                      // Flexible, so a long appointment name gives way to the
                      // count beside it rather than pushing it off the row. The
                      // count is a handful of characters and never yields.
                      //
                      // A marker here, not a button — the row already opens the
                      // list, and two targets this close in one line meant a tap
                      // meant for the list left the tab. The link back is inside
                      // the list, under its name — see [EventLinkChip].
                      Flexible(child: EventLinkChip(link: link)),
                      const SizedBox(width: 7),
                    ],
                    Text(meta, style: AppText.label.copyWith(color: metaColor)),
                  ],
                ),
              ],
            ),
          ),
          // Somebody outside the household is in, or has been invited — before
          // the household's own badge, which answers a different question.
          if (state.sharedOutIds.contains(list.id))
            Padding(padding: const EdgeInsets.only(right: 10), child: _SharedOutsideMark(size: 17)),
          // Who may see this list, when that is not simply the household. "Alle
          // Artikel" is computed across the real lists and has no audience of
          // its own — it inherits [ListVisibility.family] and so draws nothing,
          // which is the honest answer for a view rather than a row.
          VisibilityBadge(
            visibility: list.visibility,
            sharedWith: list.sharedWith,
            members: ref.watch(householdMembersProvider),
            padding: const EdgeInsets.only(right: 10),
          ),
          AppIcon(AppIcons.caretRight, size: 16, color: AppColors.mutedLight),
        ],
      ),
    );
  }
}

/// The picture at the left of an article row on a **Lebensmittel** list — the
/// grocery image its name was matched to, or the shopping-cart picture when
/// nothing matched.
///
/// The picture assets are full-colour art on transparency, drawn for a light
/// background. On light that background is already there, so the picture sits
/// straight on the card with no tile at all — a circle around it would only add
/// a line the eye has to read past. On dark it needs the same white disc
/// third-party logos get ([AppPalette.brandTile]), or the dark linework
/// disappears into the card. A Lucide symbol has no such problem: it is drawn
/// in the theme's own ink, so it gets the ordinary tile from [IconTile].
///
/// A Sonstige list has no article pictures at all — see [_ItemRow] — so this
/// only ever draws on a list that holds food, and an article nothing matched
/// falls back to [generalGroceryAsset] rather than to a symbol: on a shopping
/// list even an unrecognised line still looks like shopping.
class _ItemIcon extends StatelessWidget {
  final String? iconKey;

  /// The slot the picture is centred in. 42 on an article's own row; the add
  /// line draws it at the size of the check circle it stands in for.
  final double size;

  /// How much of [size] the picture itself gets. The pictures are re-framed to
  /// a consistent ~86% subject fill (tool/icon_gen/normalize.py), so the only
  /// padding still needed is what keeps a photo's own corners off the dark
  /// mode `ClipOval` — the subject lands at 0.92 × 0.86 ≈ 79% of the circle,
  /// and a round subject's widest point is horizontal, where the circle is
  /// widest too. Anything nearer 1.0 starts clipping the contact shadow.
  static const _imageRatio = 0.92;

  final double? imageSize;

  const _ItemIcon({super.key, required this.iconKey, this.size = 42, this.imageSize});

  @override
  Widget build(BuildContext context) {
    final image = IconImage(
      asset: resolveIcon(iconKey)?.asset ?? generalGroceryAsset,
      size: imageSize ?? size * _imageRatio,
    );
    if (!AppColors.isDark) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(child: image),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: AppColors.brandTile, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: ClipOval(child: image),
    );
  }
}

class _ListDetail extends ConsumerWidget {
  final ListScreenState state;

  const _ListDetail({required this.state});

  /// First-frame estimate only — see [_ListOverview._extraHeight].
  static const _detailExtraHeight = 62.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = Theme.of(context).colorScheme.primary;
    // Falls back to the "Alle Artikel" summary, which is computed rather than
    // stored and so always exists — a real list can be deleted while its detail
    // view is open, and nothing ships with the app to begin with.
    final open = [...state.lists, allList].firstWhere((l) => l.id == state.openId, orElse: () => allList);
    final summary = open.isSummary;
    final items = state.itemsFor(open.id);
    final openItems = items.where((i) => !i.done).toList();
    final doneItems = items.where((i) => i.done).toList();

    // The article the undo pill is offering to put back: the one that just
    // moved, and only while it is *done*. Undoing it moves it again, which
    // clears this and takes the pill away.
    final justChecked = _justCheckedOff(doneItems);

    return Stack(
      children: [
        CollapsingHeaderScreen(
          // "Alle Artikel" is every list at once and so belongs to no shop.
          backdrop: _ListGlow(iconKey: summary ? null : open.iconKey),
          // The pinned row keeps the generic "Liste" label at rest — the list's
          // own name is the big row below it — and swaps to that name as the
          // big one scrolls away, so the bar never stops saying which list
          // you're in.
          titleRowBuilder: (context, t) => CollapsingScreenTitle(
            title: L.s.listLabel,
            collapsedTitle: open.name,
            collapsedIcon: IconTile(iconKey: open.iconKey, size: 24, imageSize: 17, disc: true),
            t: t,
            expandedAlignment: Alignment.center,
            expandedFontSize: AppText.pageTitle,
            fontWeight: FontWeight.w500,
            leadingWidth: 48,
            trailingWidth: 48,
            leading: GlassIconButton(
              icon: AppIcons.caretLeft,
              onTap: () => ref.read(listProvider.notifier).back(),
            ),
            // "Alle Artikel" is computed rather than stored, so there is nothing
            // there to rename, re-symbol or delete.
            trailing: summary
                ? const SizedBox(width: 40)
                // A spinner in the button's place while "Teilen" mints its link
                // — in place of it rather than over it, because Flutter content
                // drawn over a glass platform view can be dropped on device.
                : ValueListenableBuilder<String?>(
                    valueListenable: _sharingListId,
                    builder: (context, sharing, _) => sharing == open.id
                        ? SizedBox(
                            width: 40,
                            height: 40,
                            child: Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.muted),
                              ),
                            ),
                          )
                        : KeyedSubtree(
                            key: _shareAnchorKey,
                            child: GlassMenuButton(
                              items: [
                                AnchoredMenuItem(
                                  label: L.s.edit,
                                  icon: AppIcons.pencilSimple,
                                  symbol: 'pencil',
                                  onSelected: () => openListSheet(context, ref, list: open),
                                ),
                                // Its own action, never part of "Für wen?". Straight to the
                                // system share sheet — see [_shareListOut]. Absent for kids
                                // and for a guest looking at somebody else's list, both of
                                // whom the database refuses.
                                if (ref.watch(canShareExternallyProvider) &&
                                    !state.guestListIds.contains(open.id))
                                  AnchoredMenuItem(
                                    label: L.s.share,
                                    icon: AppIcons.userPlus,
                                    symbol: 'person.badge.plus',
                                    onSelected: () => _shareListOut(context, ref, open),
                                  ),
                                AnchoredMenuItem(
                                  label: L.s.delete,
                                  icon: AppIcons.trash,
                                  symbol: 'trash',
                                  destructive: true,
                                  onSelected: () async {
                                    // Captured before the write: this row lives in the detail
                                    // view, which the delete itself unmounts.
                                    final confirm = confirmChipOf(context);
                                    final notifier = ref.read(listProvider.notifier);
                                    if (await notifier.deleteList(open.id) case final deleted?) {
                                      confirm(L.s.listDeleted, undo: () => notifier.restoreList(deleted));
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                  ),
          ),
          estimatedExtraHeight: _detailExtraHeight,
          extra: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Row(
                children: [
                  // The list's own name wears the disc; the articles under it do
                  // not — see [IconTile.disc].
                  IconTile(
                    iconKey: open.iconKey,
                    size: AppText.headerMark,
                    imageSize: AppText.markImage(AppText.headerMark),
                    disc: true,
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Unfolds when the name is longer than the line — see
                        // [ExpandableTitle]. The bar's collapsed copy of the
                        // name still ellipsizes, which is what a nav bar is
                        // for; this is the place the whole name can be read.
                        ExpandableTitle(text: open.name),
                        // The way back to the appointment this list was made
                        // for, as the name's **subtitle** — the same slot the
                        // tracker screen puts its streak in, and the reason it
                        // is inside this Column rather than under the whole
                        // header row. It says what the list is *for*, which is
                        // part of the name rather than a second thing in the
                        // header, and a line's gap below the row put it far
                        // enough away to read as one. Held to the name it
                        // belongs to, it also follows an unfolded name down
                        // instead of being left behind by it.
                        //
                        // The same badge on the overview row is inert, because
                        // the row's own tap opens the list and the two targets
                        // sat a few millimetres apart; here it has a line to
                        // itself and is the only thing on it.
                        // Both chips can be on one list — a Vorhaben started
                        // from an appointment — so they wrap rather than
                        // sitting in a Row that would squeeze the longer one.
                        if (open.eventLink != null || open.hasMethod) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (open.eventLink case final link?)
                                EventLinkChip(
                                  link: link,
                                  // The appointment's own sheet, over this list
                                  // rather than instead of it — see
                                  // [showLinkedEventSheet].
                                  onOpen: () => showLinkedEventSheet(context, ref, link),
                                ),
                              if (open.hasMethod) _MethodChip(list: open),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (state.sharedOutIds.contains(open.id)) ...[
                    const SizedBox(width: 10),
                    _SharedOutsideMark(size: 20),
                  ],
                ],
              ),
            ],
          ),
          body: ScreenBodyPanel(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 18, 16, navContentInset(context, pill: 140)),
              children: [
                SectionCard(
                  children: [
                    _AddItemRow(grocery: summary || open.kind == ListKind.grocery),
                    if (!summary)
                      for (var i = 0; i < openItems.length; i++)
                        // Divider inside the collapsing block so it folds away with
                        // the row instead of leaving a stray line behind.
                        CheckOffArrival(
                          key: ValueKey(openItems[i].id),
                          animate: openItems[i].id == state.justMoved,
                          fromBelow: true,
                          child: CheckOffRow(
                            onCompleted: () => ref.read(listProvider.notifier).toggle(openItems[i].id, false),
                            builder: (context, strike, checkOff) => Column(
                              children: [
                                CardDivider(),
                                _swipeToDelete(
                                  context,
                                  ref,
                                  openItems[i],
                                  _ItemRow(
                                    item: openItems[i],
                                    accent: accent,
                                    strike: strike,
                                    onCheckOff: checkOff,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
                if (summary)
                  for (final l in state.lists)
                    Builder(
                      builder: (context) {
                        final its = openItems.where((i) => i.listId == l.id).toList();
                        if (its.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(6, 0, 6, 9),
                                child: Row(
                                  children: [
                                    IconTile(iconKey: l.iconKey, size: 26, imageSize: 17),
                                    const SizedBox(width: 9),
                                    Text(l.name, style: AppText.groupHeading),
                                    const SizedBox(width: 6),
                                    Text(
                                      L.s.itemCount(its.length),
                                      style: AppText.label.copyWith(color: AppColors.mutedLight),
                                    ),
                                  ],
                                ),
                              ),
                              SectionCard(
                                children: [
                                  for (var i = 0; i < its.length; i++)
                                    CheckOffArrival(
                                      key: ValueKey(its[i].id),
                                      animate: its[i].id == state.justMoved,
                                      fromBelow: true,
                                      child: CheckOffRow(
                                        onCompleted: () =>
                                            ref.read(listProvider.notifier).toggle(its[i].id, false),
                                        builder: (context, strike, checkOff) => Column(
                                          children: [
                                            if (i > 0) CardDivider(),
                                            _swipeToDelete(
                                              context,
                                              ref,
                                              its[i],
                                              _ItemRow(
                                                item: its[i],
                                                accent: accent,
                                                strike: strike,
                                                onCheckOff: checkOff,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                if (doneItems.isNotEmpty) ...[
                  // The heading only pops into existence with the very first done
                  // item — let it arrive with that row instead.
                  CheckOffArrival(
                    animate: doneItems.length == 1 && doneItems.first.id == state.justMoved,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10).copyWith(top: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(L.s.doneWithCount(doneItems.length), style: AppText.caption),
                          GestureDetector(
                            onTap: () => ref.read(listProvider.notifier).clearDone(doneItems),
                            child: Text(L.s.deleteDone, style: AppText.caption.copyWith(color: accent)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SectionCard(
                    children: dividedRows([
                      for (final item in doneItems)
                        CheckOffArrival(
                          key: ValueKey(item.id),
                          animate: item.id == state.justMoved,
                          // Undo runs the same animation backwards before the item
                          // travels back up into the open list.
                          child: CheckOffRow(
                            undo: true,
                            onCompleted: () => ref.read(listProvider.notifier).toggle(item.id, true),
                            builder: (context, strike, undo) =>
                                _DoneItemRow(item: item, accent: accent, strike: strike, onUndo: undo),
                          ),
                        ),
                    ]),
                  ),
                ],
                if (items.isEmpty)
                  EmptyState(
                    icon: AppIcons.listChecks,
                    iconColor: accent,
                    message: L.s.tapAboveToAddFirst,
                    verticalPadding: 56,
                    gap: 16,
                  ),
              ],
            ),
          ),
        ),
        // "Rückgängig" for the article that just struck itself through, parked
        // where the calendar parks "Heute" — same pill, same clearance.
        Positioned(
          left: 0,
          right: 0,
          bottom: navContentInset(context, pill: 106, gap: 36),
          child: Center(
            child: UndoPill(
              token: justChecked?.id ?? '',
              accent: accent,
              onUndo: () {
                if (justChecked != null) ref.read(listProvider.notifier).toggle(justChecked.id, true);
              },
            ),
          ),
        ),
      ],
    );
  }

  /// The article behind the undo pill: whatever `justMoved` points at, but only
  /// while it sits in "Erledigt". `justMoved` is also set by adding an article
  /// and by undoing one, and neither of those is an offer to undo anything.
  ShoppingListItem? _justCheckedOff(List<ShoppingListItem> doneItems) {
    if (state.justMoved.isEmpty) return null;
    for (final item in doneItems) {
      if (item.id == state.justMoved) return item;
    }
    return null;
  }
}

/// The header wash behind a list, in the colour of the shop logo it carries
/// (see [brandGlowFor]).
///
/// Stateful for one reason: a logo the app hasn't looked at yet has to be
/// decoded before its colour is known. Until then — and for a list wearing a
/// plain symbol — the wash is the app accent, and it crossfades into the brand
/// colour when the decode lands. The same crossfade carries a *rename*: editing
/// "REWE" into "Amazon" changes the icon, so the colour follows it over 320ms
/// rather than snapping, matching the check-off colour transition.
class _ListGlow extends StatefulWidget {
  final String? iconKey;

  const _ListGlow({required this.iconKey});

  @override
  State<_ListGlow> createState() => _ListGlowState();
}

class _ListGlowState extends State<_ListGlow> {
  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(_ListGlow old) {
    super.didUpdateWidget(old);
    // The list itself never changes identity here — the detail view is one
    // widget for whichever list is open — so a new icon arrives as an update,
    // not as a fresh State.
    if (old.iconKey != widget.iconKey) _resolve();
  }

  void _resolve() {
    if (brandGlowKnown(widget.iconKey)) return;
    final pending = widget.iconKey;
    loadBrandGlow(pending).then((_) {
      // Dropped if the list was renamed again while the logo was decoding: the
      // colour on screen belongs to whatever icon it wears *now*.
      if (mounted && widget.iconKey == pending) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: brandGlowFor(widget.iconKey)),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, color, _) => HeaderBrandGlow(color: color ?? AppColors.accent),
    );
  }
}

/// Whether an article answers a Listen search: its own words first — folded, so
/// *Brotchen* still finds "Brötchen" — then what the article *is*, which is what
/// lets an English query reach a German list ("milk" → "Milch").
bool _itemMatches(ShoppingListItem item, String query) {
  final q = foldTerm(query);
  if (q.isEmpty) return false;
  if (foldTerm(item.text).contains(q)) return true;
  if (item.sub != null && foldTerm(item.sub!).contains(q)) return true;
  return groceryTermsMatch(item.text, query, iconKey: item.iconKey);
}

/// The "Artikel hinzufügen" line, with the catalogs behind it.
///
/// Two things happen as you type, both out of `data/icon_suggestions.dart`: the
/// circle on the left turns into the picture the article is about to get, and —
/// on a Lebensmittel list — a row of article suggestions grows under the field.
/// Both answer German and English, with or without umlauts: *Käse*, *kaese* and
/// *cheese* offer the same chips. Tapping one files the article under its
/// German name.
///
/// **One leading slot, not two.** The picture briefly had a 42px slot of its
/// own next to the circle, so that the add line was laid out as the row it was
/// about to become and committing moved nothing. It moved something worse: the
/// line's text started some 50px in from the left while every row above it
/// began at the checkbox, and an add line that reads as indented reads as
/// belonging to something. There is nothing to check off on this line and no
/// article yet either, so the circle carries both and the words stay where the
/// eye already is.
///
/// [grocery] decides what they are. On a Sonstige list the article chips are
/// dropped outright — "Bohrmaschine" is not a shopping article, and a row of
/// food photos under it would be noise — but the preview stays, as the symbol
/// the article will be stored with, because its row now shows one.
class _AddItemRow extends ConsumerStatefulWidget {
  final bool grocery;

  const _AddItemRow({required this.grocery});

  @override
  ConsumerState<_AddItemRow> createState() => _AddItemRowState();
}

class _AddItemRowState extends ConsumerState<_AddItemRow> {
  final _controller = TextEditingController();
  String _draft = '';

  /// The unit the next article gets, as a stored key — `null` is Stück. Back to
  /// the default after every add: the chip only exists while something is being
  /// typed, so a unit left standing from the last article would be a setting
  /// nobody can see they are still in.
  String? _unit;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add(String text, {String? iconKey}) {
    ref.read(listProvider.notifier).addItem(text, iconKey: iconKey, unit: _unit);
    _controller.clear();
    setState(() {
      _draft = '';
      _unit = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // The same call [ListNotifier.addItem] stores with, so the preview is the
    // icon the row will get.
    // Lebensmittel only, like the row it previews: nothing picks a symbol for a
    // Sonstige article any more (see [planItemIconKey]), so the circle stays a
    // circle until the reader chooses one themselves.
    final preview = widget.grocery ? suggestIcon(_draft, subject: IconSubject.groceryArticle) : null;
    final suggestions = widget.grocery
        ? [
            for (final icon in groceryIconSuggestions(_draft))
              IconChoice(kind: IconKind.grocery, key: icon.asset, label: icon.label),
          ]
        : const <IconChoice>[];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          child: Row(
            children: [
              // One slot, not two. The empty check circle is what an add line
              // starts as, and the picture the typed word chose takes its place
              // — crossfading in it rather than beside it, the way the circle
              // itself would fill.
              //
              // It used to hold a second 42px slot open for the picture, in the
              // place an article's own occupies. That kept the words still
              // while the picture changed with every keystroke, but it started
              // the line's text a good 50px in from the left while the rows
              // above it began at the checkbox — the add line read as indented
              // rather than as the next row. There is nothing to check off yet
              // and no article yet either, so the one circle carries both.
              SizedBox(
                width: 24,
                height: 24,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: preview == null
                      ? AppIcon(
                          AppIcons.circle,
                          key: const ValueKey('empty'),
                          size: 24,
                          color: AppColors.idleRing,
                        )
                      // Drawn over the slot rather than inside it: the circle is
                      // 24 because a checkbox is, and a photograph of a Paprika
                      // shrunk to a checkbox is a smudge. The slot keeps its
                      // width so the words don't move, and the picture spills
                      // symmetrically into the padding either side of it —
                      // close to the 42 it will be drawn at once the article is
                      // in the list.
                      : OverflowBox(
                          maxWidth: 36,
                          maxHeight: 36,
                          child: widget.grocery
                              ? _ItemIcon(
                                  key: ValueKey(preview.key),
                                  iconKey: preview.key,
                                  size: 36,
                                  imageSize: 36,
                                )
                              : KeyedSubtree(
                                  key: ValueKey(preview.key),
                                  child: IconTile(
                                    iconKey: preview.key,
                                    size: 36,
                                    imageSize: AppText.markImage(36),
                                  ),
                                ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: AppText.inputTitle,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: L.s.addItemPlaceholder,
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.done,
                  onChanged: (v) => setState(() => _draft = v),
                  onSubmitted: (v) => _add(v),
                ),
              ),
              // Lebensmittel only, and only once there is something to be a
              // unit *of*: an empty line offering "Stück" would be a control
              // for an article nobody has named yet, and a Bohrmaschine is not
              // sold by the Bund. Right where the article's own quantity circle
              // will be, so the two read as the same corner of the row.
              if (widget.grocery && _draft.trim().isNotEmpty) ...[
                const SizedBox(width: 8),
                _UnitButton(current: _unit, chip: true, onPicked: (u) => setState(() => _unit = u)),
              ],
            ],
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 180),
          sizeCurve: Curves.easeOutCubic,
          crossFadeState: suggestions.isEmpty ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: SizedBox(
            width: double.infinity,
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(15, 0, 15, 10),
              itemCount: suggestions.length,
              separatorBuilder: (context, i) => const SizedBox(width: 8),
              itemBuilder: (context, i) => _SuggestionChip(
                choice: suggestions[i],
                onTap: () => _add(suggestions[i].label, iconKey: suggestions[i].key),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final IconChoice choice;
  final VoidCallback onTap;

  const _SuggestionChip({required this.choice, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
        decoration: BoxDecoration(
          // Same white as the card behind it, not `surfaceAlt`: the grocery
          // pictures carry an opaque white background of their own, and a grey
          // chip turns that into a visible patch. The hairline does the
          // separating instead.
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.chip),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTile(iconKey: choice.key, size: 24, imageSize: 20),
            const SizedBox(width: 7),
            Text(choice.label, style: AppText.caption.copyWith(color: AppColors.inkSecondary)),
          ],
        ),
      ),
    );
  }
}

/// An open article, and the place it gets renamed.
///
/// Tapping the name turns the text into the field it already looks like, right
/// where it sits, so a wrong article is corrected in the list instead of in a
/// sheet on top of it. The quantity is the grey circle at the end of the row
/// and edits in place the same way. The row leaves edit mode the moment the
/// fields lose focus, whether that's Return, a tap somewhere else on the screen
/// or the keyboard being put away.
class _ItemRow extends ConsumerStatefulWidget {
  final ShoppingListItem item;
  final Color accent;

  /// 0 → 1 while the item is being checked off; drives the strike-through, the
  /// text greying out and the check filling in.
  final double strike;
  final VoidCallback onCheckOff;

  const _ItemRow({required this.item, required this.accent, required this.strike, required this.onCheckOff});

  @override
  ConsumerState<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends ConsumerState<_ItemRow> {
  final _textController = TextEditingController();
  final _subController = TextEditingController();
  final _textFocus = FocusNode();
  final _subFocus = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _textFocus.addListener(_onFocusChanged);
    _subFocus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _textController.dispose();
    _subController.dispose();
    _textFocus.dispose();
    _subFocus.dispose();
    super.dispose();
  }

  void _startEditing(FocusNode field) {
    _textController.text = widget.item.text;
    _subController.text = widget.item.sub ?? '';
    setState(() => _editing = true);
    // The fields only exist from the next build on, so the focus request has
    // to wait for them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) field.requestFocus();
    });
  }

  /// Leaving *both* fields ends the edit. Checked a frame late on purpose:
  /// moving from the name to the quantity takes the focus off one node before
  /// it lands on the other, and reading it mid-hop would commit halfway
  /// through a Tab.
  void _onFocusChanged() {
    if (!_editing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_editing) return;
      if (_textFocus.hasFocus || _subFocus.hasFocus) return;
      _commit();
    });
  }

  /// What a tap anywhere else has to do by hand. Flutter only drops focus on a
  /// tap outside by itself on desktop; on a phone the field keeps it — and the
  /// number pad the quantity puts up has no Return key to give it back with, so
  /// without this the keyboard would sit there until the row was tapped again.
  void _unfocusFields() {
    _textFocus.unfocus();
    _subFocus.unfocus();
  }

  void _commit() {
    setState(() => _editing = false);
    ref
        .read(listProvider.notifier)
        .editItem(widget.item, text: _textController.text, sub: _subController.text);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final accent = widget.accent;
    final strike = widget.strike;
    final onCheckOff = widget.onCheckOff;
    final attachments = ref.watch(listProvider).attachmentsFor(item);
    final photos = attachments.where((a) => a.isImage);
    final photo = photos.isEmpty ? null : photos.first;
    // A lone photo is already on the row as its thumbnail, so its file name
    // under the article would be a caption for a picture you can see —
    // "IMG_4821.HEIC" says nothing about the item. A document has no thumbnail
    // and its name is the only thing identifying it, and several attachments
    // still need the line to say how many there are.
    final showAttachments = attachments.length > 1 || (attachments.length == 1 && !attachments.first.isImage);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 15),
      child: Row(
        children: [
          CheckOffButton(progress: strike, accent: accent, onTap: onCheckOff, size: 24),
          const SizedBox(width: 12),
          // An attached photo takes the icon's place: it *is* the picture of
          // this item, and it says more than the grocery picture it replaces.
          // Round, like the grocery picture's own tile and the check circle
          // in front of it — the row reads as one line of circles, and a
          // rounded square in the middle of it was the only corner in sight.
          //
          // On a Sonstige list the slot is there only when the list has
          // something to put in it — an article whose name, or a Vorhaben's
          // icon hint, matched a symbol. Then every row of that list keeps the
          // slot so the words stay in one column, and a row that matched
          // nothing leaves it empty: a column of identical fallback symbols is
          // noise in front of the words that carry the meaning. A list where
          // nothing matched looks as it always did, a checkbox and the text. A
          // photo the user attached still shows either way, because that one
          // they chose.
          if (photo != null) ...[
            // Centred in the same 42 slot the grocery picture gets, but drawn
            // at the size that picture is drawn at rather than filling the
            // slot edge to edge. A photograph is opaque to its own border
            // while a PNG of rice is a small drawing inside a lot of empty
            // space, so the two at the same nominal size read as two
            // different sizes — the photo as the loudest thing on the screen,
            // the article beside it as an afterthought.
            SizedBox(
              width: 42,
              height: 42,
              child: Center(
                child: ClipOval(
                  // The copy on this device while the session that picked it
                  // is still running, the signed URL from then on — see
                  // [PhotoThumbnail].
                  child: PhotoThumbnail(url: photo.url, filePath: photo.localPath, size: 34),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ] else if (_isGroceryList(ref, item.listId)) ...[
            _ItemIcon(iconKey: item.iconKey),
            const SizedBox(width: 12),
          ] else if (_listHasSymbols(ref, item.listId)) ...[
            _SymbolSlot(iconKey: item.iconKey),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_editing)
                  TextField(
                    controller: _textController,
                    focusNode: _textFocus,
                    style: _itemTextStyle,
                    decoration: _inlineFieldDecoration(L.s.itemLabel, _itemTextStyle),
                    textInputAction: TextInputAction.next,
                    onTapOutside: (_) => _unfocusFields(),
                    onSubmitted: (_) => _subFocus.requestFocus(),
                  )
                else
                  // The whole strip next to the article is the target and it
                  // edits the name — the empty room after a short word is still
                  // that word, and aiming at four glyphs isn't a tap. Aligned
                  // rather than stretched inside it, so the strike-through
                  // still stops at the last letter.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _startEditing(_textFocus),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: StrikeThrough(
                        progress: strike,
                        color: _itemDoneInk,
                        child: Text(
                          item.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _itemTextStyle.copyWith(
                            color: Color.lerp(AppColors.ink, _itemDoneInk, strike),
                          ),
                        ),
                      ),
                    ),
                  ),
                // What the count counts, under the name — a line to read while
                // the row sits there, a chip to press while it is open. It is
                // not a second circle: the unit is chosen once when the article
                // goes on the list, while the number changes every week, so it
                // earns less of the row than the count does.
                if (_editing)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _UnitButton(
                      current: item.unit,
                      chip: true,
                      onPicked: (u) => ref.read(listProvider.notifier).setUnit(item, u),
                    ),
                  )
                else if (item.unit != null)
                  Opacity(
                    opacity: 1 - 0.45 * strike,
                    child: _UnitButton(
                      current: item.unit,
                      chip: false,
                      onPicked: (u) => ref.read(listProvider.notifier).setUnit(item, u),
                    ),
                  ),
                if (showAttachments)
                  Opacity(
                    opacity: 1 - 0.45 * strike,
                    child: _AttachmentsLine(attachments: attachments, accent: accent),
                  ),
                if (item.linkUrl case final url?)
                  Opacity(
                    opacity: 1 - 0.45 * strike,
                    child: _LinkLine(url: url, accent: accent),
                  ),
                // Non-grocery lists only: nobody orders a cucumber from Amazon,
                // and a badge under every article on the weekly shop would be
                // fourteen adverts nobody taps. The article's own shop page,
                // when the household set one, is the better answer and sits
                // directly above — so the badge steps aside for it.
                if (_amazonFor(ref, item) case final marketplace? when item.linkUrl == null && !_editing)
                  Opacity(
                    opacity: 1 - 0.45 * strike,
                    child: _AmazonLine(article: item.text, marketplace: marketplace, accent: accent),
                  ),
              ],
            ),
          ),
          // The quantity, on the row rather than under the name. It shows while
          // there is one and while the row is being edited — an article without
          // a quantity is one of it, and a circle saying so on every line would
          // be noise on a shopping list.
          if (_editing || (item.sub?.isNotEmpty ?? false))
            Opacity(
              opacity: 1 - 0.45 * strike,
              child: _QuantityCircle(
                onTap: _editing ? null : () => _startEditing(_subFocus),
                child: _editing
                    ? TextField(
                        controller: _subController,
                        focusNode: _subFocus,
                        style: _quantityStyle,
                        textAlign: TextAlign.center,
                        // A count, not a sentence — which is the other half of
                        // moving it out here: the number pad comes up instead
                        // of the letter keyboard, so changing a 2 into a 3 is
                        // one tap on one key.
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration.collapsed(
                          // A numeral, not copy: "1" is what an article without
                          // a quantity is in either language, so there is
                          // nothing here for `L.s` to answer.
                          hintText: '1',
                          hintStyle: _quantityStyle.copyWith(color: AppColors.mutedLight),
                        ),
                        onTapOutside: (_) => _unfocusFields(),
                        onSubmitted: (_) => _commit(),
                      )
                    // Scaled down rather than clipped: a count fits at full size,
                    // and the free-text quantities older lists still carry ("2
                    // Liter") shrink to fit instead of stretching the circle.
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(item.sub!, maxLines: 1, style: _quantityStyle),
                      ),
              ),
            ),
          // Where the owner's name used to sit. Whose item it is is already
          // said by the list it's in; the row menu is what you actually reach
          // for here. It greys out with the rest of the row as it's checked
          // off, on the way to the "Erledigt" section.
          Opacity(
            opacity: 1 - 0.45 * strike,
            child: RowMenuButton(items: _itemMenu(context, ref, item)),
          ),
        ],
      ),
    );
  }
}

/// What the count counts, and the control that changes it.
///
/// Two shapes for one thing, the way the row's name is a label until you tap
/// it: a filled chip while an article is being composed or edited, where it is
/// something to press, and a plain line under the name the rest of the time,
/// where it is something to read. [current] is the stored key — `null` is the
/// default, so the chip still has a word to show.
/// Stateful only to hold the [GlobalKey] the anchored fallback anchors to — a
/// key made in a `build` would be a different key on every frame.
class _UnitButton extends StatefulWidget {
  final String? current;
  final bool chip;
  final ValueChanged<String?> onPicked;

  const _UnitButton({required this.current, required this.chip, required this.onPicked});

  @override
  State<_UnitButton> createState() => _UnitButtonState();
}

class _UnitButtonState extends State<_UnitButton> {
  final _anchorKey = GlobalKey();

  /// Ten choices is more than the app's own panel wants to be, which is one
  /// more reason this menu is glad to be UIKit's where UIKit has one: the
  /// system list already knows how to scroll and to tick the unit in force.
  Future<void> _pick() async {
    final units = GroceryUnit.values;
    String? keyOf(GroceryUnit unit) => unit == GroceryUnit.piece ? null : unit.key;
    final active = widget.current ?? GroceryUnit.piece.key;

    await showAnchoredMenu(
      context: context,
      anchorKey: _anchorKey,
      title: L.s.unit,
      items: [
        for (final unit in units)
          AnchoredMenuItem(
            label: unit.label,
            // The tick is UIKit's own where UIKit draws the menu, and a glyph
            // in the icon column where the app draws it — the panel has no
            // separate place for state.
            selected: unit.key == active,
            icon: unit.key == active ? AppIcons.check : AppIcons.circle,
            onSelected: () => widget.onPicked(keyOf(unit)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.current == null ? GroceryUnit.piece.label : groceryUnitLabel(widget.current!);
    final control = GestureDetector(
      key: _anchorKey,
      behavior: HitTestBehavior.opaque,
      onTap: _pick,
      child: widget.chip
          ? Container(
              padding: const EdgeInsets.fromLTRB(9, 4, 6, 4),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadii.chip),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: AppText.microLabel.copyWith(color: AppColors.inkSecondary)),
                  const SizedBox(width: 2),
                  AppIcon(AppIcons.caretDown, size: 12, color: AppColors.mutedLight),
                ],
              ),
            )
          // The padding is the target: a unit is read far more often than it is
          // changed, so it stays a subtitle rather than growing into a control,
          // and the room around the word is what makes it tappable at all.
          : Padding(
              padding: const EdgeInsets.only(top: 1, bottom: 3),
              child: Text(label, style: AppText.label),
            ),
    );
    // The chip only exists while a row is being edited, which means a field on
    // that row holds the focus and its `onTapOutside` is waiting for a tap
    // anywhere else. Without this the chip's own tap was that tap: the
    // pointer-down dropped the focus, the row committed and left edit mode in
    // the same frame, and the chip was gone before the pointer came back up —
    // so the menu never opened and the only visible effect was the keyboard
    // going away. [TextFieldTapRegion] puts the chip inside the field's own
    // group, so pressing it counts as staying in the row.
    return widget.chip ? TextFieldTapRegion(child: control) : control;
  }
}

/// The grey circle at the end of an article row, holding its quantity — the
/// number itself, or the field it becomes while the row is being edited.
///
/// The quantity used to be a second line of grey text under the article, which
/// read fine and tapped badly: 12.5pt of type is about two millimetres of
/// target, on the thing in a shopping list that changes most often. Out here it
/// is a 30pt circle with the row's own padding counted into the target, and it
/// is next to the thumb rather than under the name.
///
/// Always [_size] across, whatever is in it. A circle that sized itself to its
/// contents would be a different shape on every row of the list — and it would
/// move as the number went from 9 to 10 — so what's inside scales to the circle
/// instead of the other way round.
class _QuantityCircle extends StatelessWidget {
  static const _size = 32.0;

  final Widget child;

  /// Null while the row is already being edited: the field inside takes its own
  /// taps then, and an opaque detector over it would only get in the way.
  final VoidCallback? onTap;

  const _QuantityCircle({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final circle = Padding(
      // The circle is what you see; this padding is the rest of the target, and
      // it fits inside the row's own height so nothing moves to make room.
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      child: Container(
        width: _size,
        height: _size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.surfaceAlt, shape: BoxShape.circle),
        // The one width anything inside gets: it keeps the number off the rim,
        // and it's what the contents are scaled to fit.
        child: SizedBox(width: _size - 8, child: child),
      ),
    );
    if (onTap == null) return circle;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: circle);
  }
}

/// What the item is carrying, under its name: the file's own name while
/// there's only one, a count once there are several — a column of file names
/// would drown out the item itself. Not shown at all for a single photo, which
/// the row is already showing rather than naming.
class _AttachmentsLine extends StatelessWidget {
  final List<ItemAttachment> attachments;
  final Color accent;

  const _AttachmentsLine({required this.attachments, required this.accent});

  @override
  Widget build(BuildContext context) {
    final label = attachments.length == 1 ? attachments.first.name : L.s.attachmentCount(attachments.length);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(AppIcons.paperclip, size: 11, color: accent),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.microLabel.copyWith(color: accent),
            ),
          ),
        ],
      ),
    );
  }
}

/// The shop page an article points at, under its name — a link glyph and the
/// bare host, and a tap opens it outside the app.
///
/// The host rather than the URL: a product link is sixty characters of tracking
/// parameters, and "amazon.de" says everything a shopping list needs to say
/// about where the tap leads. It is the one thing under the name that is a
/// target of its own — the attachments line beside it is a caption, while this
/// is the whole point of having stored a link.
/// "Bei Amazon suchen · Anzeige" under one article on a non-grocery list.
///
/// **The "Anzeige" is not decoration and must not be dropped.** An affiliate
/// link is advertising, and German law (§ 5a Abs. 4 UWG) requires the
/// commercial intent to be recognisable *at the link* rather than in a footnote
/// somebody scrolls past. That is why the word rides on the badge itself, on
/// every row, instead of one disclosure at the bottom of the list. The
/// Werbekennzeichnung is also why [amazonSearchUrl] fails closed: no partner
/// tag, no badge, so there is never an unlabelled one.
///
/// Nothing is stored. The URL is built from [article] as the row is drawn — see
/// [lib/data/amazon.dart]. A list shared outward carries no tag, because it
/// carries no link.
class _AmazonLine extends StatelessWidget {
  final String article;
  final String? marketplace;
  final Color accent;

  const _AmazonLine({required this.article, required this.marketplace, required this.accent});

  @override
  Widget build(BuildContext context) {
    final search = amazonSearch(article, marketplace: marketplace);
    // Gated on the tag by [_amazonFor], so this is belt-and-braces: an
    // unsponsored badge would be clutter that earns nothing, and a sponsored
    // one without the word beside it would be an unlabelled advert.
    if (!search.sponsored) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => openExternalUrl(search.url),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(top: 3, bottom: 3, right: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Same 11pt as [_LinkLine] and for the same reason — it sits beside
            // the same `microLabel`. Amazon's own mark cannot come: it is an
            // SVG, and this row draws from the Phosphor set.
            AppIcon(AppIcons.magnifyingGlass, size: 11, color: accent, flat: true),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                L.s.searchOnAmazon,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.microLabel.copyWith(color: accent),
              ),
            ),
            const SizedBox(width: 5),
            Text(L.s.adLabel, style: AppText.microLabel.copyWith(color: AppColors.mutedLight)),
          ],
        ),
      ),
    );
  }
}

class _LinkLine extends StatelessWidget {
  final String url;
  final Color accent;

  const _LinkLine({required this.url, required this.accent});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => openExternalUrl(url),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        // A little taller than the attachments line it sits under, because this
        // one is aimed at: eleven points of glyph and a domain is a thin thing
        // to hit, and the padding is the target.
        padding: const EdgeInsets.only(top: 3, bottom: 3, right: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // **The one flat glyph that is not on the [AppGlyph] scale**, and
            // deliberately: the smallest tier there is sized against caption
            // type, and this mark belongs to a domain set smaller than that.
            // A glyph that out-measures its own word stops reading as part of
            // it — see the note on [AppGlyph].
            AppIcon(AppIcons.link, size: 11, color: accent, flat: true),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                urlLabel(url),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.microLabel.copyWith(color: accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Puts up the system picker and files whatever comes back under the item.
/// Cancelling (or a device with no camera) simply returns nothing.
Future<void> _attach(
  BuildContext context,
  WidgetRef ref,
  ShoppingListItem item,
  AttachmentSource source,
) async {
  // Before the system picker, not after it: asking somebody to choose a
  // photograph and then refusing to keep it is the worst possible moment for a
  // paywall. Taking one off again is not gated — a household that drops to the
  // free plan must still be able to clear what it already has.
  if (!await requireFeature(context, ref, Feature.photos)) return;

  // Photographs are capped on their way in; a document from Dateien is left
  // alone, because there is no such thing as a downscaled PDF.
  final picked = await pickAttachment(source, maxDimension: itemPhotoMaxDimension);
  if (picked == null) return;
  await ref.read(listProvider.notifier).addAttachment(item, picked);
}

/// Pastes the page this article is about onto it — the product at the shop the
/// family agreed on, which is the thing you cannot find again from the word
/// "Bohrmaschine" a week later.
///
/// A sheet rather than a fourth inline field: a URL is pasted, not typed
/// alongside the name and the count, and it is set once and then only tapped.
/// The app's ordinary create-sheet chrome, so the check is greyed while the
/// field is empty and a save that cannot be made a URL says so on the chip —
/// clearing the field is **not** how a link is removed, or a mis-tap in a sheet
/// somebody opened to *read* the URL would throw it away. The menu's own
/// "Link entfernen" is for that.
void _editLink(BuildContext context, WidgetRef ref, ShoppingListItem item) {
  final controller = TextEditingController(text: item.linkUrl ?? '');
  final focus = FocusNode();
  final notifier = ref.read(listProvider.notifier);
  showAppSheet(
    context: context,
    title: L.s.itemLink,
    // One field and two lines of explanation — the tall sheet the list editor
    // needs would be mostly empty here.
    heightFactor: 0.6,
    requiredField: controller,
    requiredFocus: focus,
    onSave: () async {
      // Taken before the write, as everywhere else here: the sheet is popped
      // the moment the check is tapped, so the chip belongs to the screen
      // behind it.
      final confirm = confirmChipOf(context);
      final fail = confirmChipOf(context, kind: ToastKind.error);
      final url = normalizeExternalUrl(controller.text);
      if (url == null) {
        fail(L.s.itemLinkInvalid);
        return;
      }
      if (await notifier.setLink(item, url)) {
        confirm(L.s.itemLinkSaved);
      } else {
        fail(L.s.changeSaveFailed);
      }
    },
    child: _LinkSheetBody(controller: controller, focus: focus, name: item.text),
  );
}

/// The method a Vorhaben wrote for this list, under its name.
///
/// **A chip rather than a card at the top of the list.** It sits exactly where
/// [EventLinkChip] sits and behaves the same way: the articles are why the
/// screen is opened — you add milk constantly and consult the method
/// occasionally — so the recipe gets one line that is always there and never in
/// the way, instead of a block that pushes the shopping down the screen every
/// time.
///
/// Drawn only when there is something behind it ([ShoppingList.hasMethod]),
/// which is a Vorhaben's list and nothing else.
class _MethodChip extends StatelessWidget {
  final ShoppingList list;

  const _MethodChip({required this.list});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    // "Rezept" only when there is one; a Bauhaus plan's steps are a method, not
    // a recipe, and calling them one would be a small lie on every such list.
    final label = list.recipe == null ? L.s.plannerHowTo : L.s.plannerRecipe;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showMethodSheet(context, list),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: tint(accent, .88), borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(AppIcons.listChecks, size: AppGlyph.inline, color: accent),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppText.caption.copyWith(color: accent, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// The method, read-only, over the list rather than instead of it.
///
/// [SheetPickerHeader] rather than the default header: there is nothing to
/// save. The list's own name is the title, because the sheet is opened from a
/// chip under that name and the method has no name of its own.
void _showMethodSheet(BuildContext context, ShoppingList list) {
  showAppSheet(
    context: context,
    header: SheetPickerHeader(title: list.name),
    heightFactor: 0.8,
    child: _MethodSheetBody(list: list),
  );
}

class _MethodSheetBody extends StatelessWidget {
  final ShoppingList list;

  const _MethodSheetBody({required this.list});

  @override
  Widget build(BuildContext context) {
    // Drawn by the same widget as the planner card's disclosure, deliberately:
    // this sheet is that card's content after the list was made, and a recipe
    // that reformatted itself on the way would read as a different recipe. See
    // `_MethodDisclosure` in list/planner_card.dart and [MarkdownText].
    final recipe = list.recipe?.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (list.steps.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Text(L.s.plannerHowTo, style: AppText.microLabel),
          ),
          MarkdownText(stepsAsMarkdown(list.steps)),
        ],
        if (recipe.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(4, list.steps.isEmpty ? 4 : 20, 4, 8),
            child: Text(L.s.plannerRecipe, style: AppText.microLabel),
          ),
          MarkdownText(recipe),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

/// One field, and the sentence that says what it is for.
class _LinkSheetBody extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;

  /// The article being pointed somewhere, over the field — the sheet is opened
  /// from a row menu, so without it there is nothing on screen saying which
  /// article this is about.
  final String name;

  const _LinkSheetBody({required this.controller, required this.focus, required this.name});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(name, style: AppText.microLabel),
        ),
        SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: TextField(
                controller: controller,
                focusNode: focus,
                // The sheet exists to receive a paste, so the keyboard is up on
                // arrival — and it is the URL one, with capitalisation off:
                // "Https://Amazon.de" is what the sentence-case default makes
                // of a pasted link the moment it is edited.
                autofocus: true,
                keyboardType: TextInputType.url,
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                style: AppText.inputTitle,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: L.s.itemLinkHint,
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(L.s.itemLinkMessage, style: AppText.body.copyWith(color: AppColors.muted)),
        ),
      ],
    );
  }
}

/// Takes the link off again. No confirmation in front of it — it is one line of
/// text that the sheet can put back — but a failure has nowhere else to show,
/// so this is the caller [ListNotifier.setLink] hands its `false` to.
Future<void> _removeLink(BuildContext context, WidgetRef ref, ShoppingListItem item) async {
  if (await ref.read(listProvider.notifier).setLink(item, null)) return;
  if (!context.mounted) return;
  showErrorSnack(context, L.s.changeSaveFailed);
}

/// Swiping an item row left reveals Delete, the same gesture the Kalender
/// event cards and the Boxen item rows use. No `onTap`: the article's own text
/// and its check circle carry the handlers here.
Widget _swipeToDelete(BuildContext context, WidgetRef ref, ShoppingListItem item, Widget row) {
  return SwipeToEditDelete(identity: item.id, onDelete: () => _deleteItem(context, ref, item), child: row);
}

/// Takes an article off its list and offers it straight back.
///
/// No confirmation dialog in front of it, exactly as with a whole list: the
/// chip *is* the confirmation, and it can put the article back — attachments
/// and all, see [ListNotifier.restoreItem]. Captured before the write, because
/// the row it was tapped in is gone by the time the write returns.
Future<void> _deleteItem(BuildContext context, WidgetRef ref, ShoppingListItem item) async {
  final confirm = confirmChipOf(context);
  final notifier = ref.read(listProvider.notifier);
  if (await notifier.removeItem(item) case final deleted?) {
    confirm(L.s.itemDeleted, undo: () => notifier.restoreItem(deleted));
  }
}

/// The row menu shared by an open item and a checked-off one.
///
/// Labels are the bare noun — "Foto", not "Foto hinzufügen". Every row of a
/// menu is something you're doing to the item, so spelling the verb out four
/// times says nothing and makes the list harder to scan.
List<AnchoredMenuItem> _itemMenu(BuildContext context, WidgetRef ref, ShoppingListItem item) {
  final attachments = ref.read(listProvider).attachmentsFor(item);
  // The household's own marketplace, not the German one this used to assume.
  // Unlike the row badge, this is **not** gated on having a partner tag: an
  // untagged search is still a search, useful to the reader and earning us
  // nothing — so it needs no Werbekennzeichnung either. The label picks up
  // "Anzeige" exactly when the link turns into advertising.
  final amazon = amazonSearch(
    item.text,
    marketplace: amazonMarketplace(
      countryCode: PlatformDispatcher.instance.locale.countryCode,
      languageCode: L.s.localeCode,
    ),
  );
  return [
    AnchoredMenuItem(
      label: amazon.sponsored ? '${L.s.searchOnAmazon} · ${L.s.adLabel}' : L.s.searchOnAmazon,
      svgAsset: 'assets/merchants/amazon-simple.svg',
      // The one row whose glyph can't survive the crossing: UIKit's menu takes
      // SF Symbols, and Amazon's mark is an SVG in `assets/merchants/`. The
      // label already says whose shop it is, so the system row shows what the
      // row *does* instead.
      symbol: 'magnifyingglass',
      onSelected: () => openExternalUrl(amazon.url),
    ),
    // Beside it because both rows are about the web: one goes looking for the
    // product, the other records the one that was already found.
    AnchoredMenuItem(
      label: L.s.itemLink,
      icon: AppIcons.link,
      symbol: 'link',
      onSelected: () => _editLink(context, ref, item),
    ),
    // The two system pickers, straight through to UIKit — see
    // lib/services/media_picker.dart. No Files row: what an article on a
    // shopping list wants beside it is a picture of the thing, and the
    // document picker offered a PDF that would then sit under the name as a
    // caption nobody can open from the row.
    AnchoredMenuItem(
      label: L.s.photo,
      icon: AppIcons.image,
      symbol: 'photo.on.rectangle',
      onSelected: () => _attach(context, ref, item, AttachmentSource.photos),
    ),
    AnchoredMenuItem(
      label: L.s.camera,
      icon: AppIcons.camera,
      symbol: 'camera',
      onSelected: () => _attach(context, ref, item, AttachmentSource.camera),
    ),
    // One row per attached file, because they are stored now and a file you
    // cannot take off again is a file you think twice about putting on. Named
    // by the file only when there are several — with one there is nothing to
    // tell apart, and "IMG_4821.HEIC" says less than "Foto entfernen" does.
    for (final attached in attachments)
      AnchoredMenuItem(
        label: attachments.length == 1 ? L.s.removePhoto : attached.name,
        icon: AppIcons.x,
        symbol: 'xmark',
        destructive: true,
        onSelected: () => ref.read(listProvider.notifier).removeAttachment(item, attached),
      ),
    if (item.linkUrl != null)
      AnchoredMenuItem(
        label: L.s.removeItemLink,
        icon: AppIcons.linkBreak,
        symbol: 'xmark',
        destructive: true,
        onSelected: () => _removeLink(context, ref, item),
      ),
    AnchoredMenuItem(
      label: L.s.delete,
      icon: AppIcons.trash,
      symbol: 'trash',
      destructive: true,
      onSelected: () => _deleteItem(context, ref, item),
    ),
  ];
}

class _DoneItemRow extends ConsumerWidget {
  final ShoppingListItem item;
  final Color accent;

  /// 1 at rest; runs back down to 0 as the item is undone, which unwinds the
  /// strike-through and empties the check again.
  final double strike;
  final VoidCallback onUndo;

  const _DoneItemRow({required this.item, required this.accent, required this.strike, required this.onUndo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Apart from its menu button the row carries nothing else to tap, so the
    // whole line undoes it — and it comes back up to full strength as it does.
    return GestureDetector(
      onTap: onUndo,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: 1 - 0.4 * strike,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 15),
          child: Row(
            children: [
              CheckOffButton(progress: strike, accent: accent, onTap: onUndo, size: 24),
              const SizedBox(width: 12),
              // Same rule as the open row: pictures on a Lebensmittel list, and
              // on a Sonstige one only when the list has any to show.
              if (_isGroceryList(ref, item.listId)) ...[
                _ItemIcon(iconKey: item.iconKey),
                const SizedBox(width: 12),
              ] else if (_listHasSymbols(ref, item.listId)) ...[
                _SymbolSlot(iconKey: item.iconKey),
                const SizedBox(width: 12),
              ],
              Expanded(
                // Aligned, not stretched: the strike has to stop at the last
                // glyph, and [Expanded] would hand the stack the whole row.
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: StrikeThrough(
                    progress: strike,
                    color: _itemDoneInk,
                    child: Text(
                      item.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _itemTextStyle.copyWith(color: Color.lerp(AppColors.ink, _itemDoneInk, strike)),
                    ),
                  ),
                ),
              ),
              Opacity(
                opacity: strike,
                child: RowMenuButton(items: _itemMenu(context, ref, item)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
