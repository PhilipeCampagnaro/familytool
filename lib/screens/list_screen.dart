
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/brand_colors.dart';
import '../data/grocery_catalog.dart';
import '../data/grocery_search.dart';
import '../data/icon_suggestions.dart';
import '../data/list_data.dart';
import '../models/attachment.dart';
import '../models/event_link.dart';
import '../models/grocery_unit.dart';
import '../models/shopping_list.dart';
import '../services/action_sheet.dart';
import '../services/external_links.dart';
import '../services/media_picker.dart';
import '../state/auth_state.dart';
import '../state/family_state.dart';
import '../state/list_state.dart';
import '../state/nav_state.dart';
import '../state/sharing_state.dart';
import '../theme/tokens.dart';
import '../widgets/anchored_menu.dart';
import '../widgets/app_sheet.dart';
import '../widgets/avatar.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/check_off.dart';
import '../widgets/collapsing_header.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_note.dart';
import '../widgets/event_link_chip.dart';
import '../widgets/floating_pill.dart';
import '../widgets/glass.dart';
import '../widgets/icon_picker.dart';
import '../widgets/overview_screen.dart';
import '../widgets/search.dart';
import '../widgets/segmented_control.dart';
import '../widgets/share_sheet.dart';
import '../widgets/swipe_actions.dart';
import '../widgets/toast_chip.dart';
import '../widgets/visibility_picker.dart';
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
TextStyle get _quantityStyle => AppText.caption.copyWith(color: AppColors.inkSecondary, fontWeight: FontWeight.w600);

/// Whether an article's own list holds food — asked of the item rather than of
/// the open list, because "Alle Artikel" pools every list's articles into one
/// view and a Sonstige row in it is still a Sonstige row.
bool _isGroceryList(WidgetRef ref, String listId) =>
    ref.watch(listProvider).listById(listId)?.kind == ListKind.grocery;

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
      body: state.isDetail ? _ListDetail(state: state) : SafeArea(bottom: false, child: _ListOverview(state: state)),
    );
  }
}

class _ListOverview extends ConsumerWidget {
  final ListScreenState state;

  const _ListOverview({required this.state});

  /// First-frame estimate only — just the search pill, Listen having no stat
  /// tiles. [CollapsingHeaderScreen] re-measures the real thing once it's laid
  /// out.
  static const _extraHeight = 74.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SearchableOverviewScreen(
      title: L.s.listsTitle,
      searchHint: L.s.searchListsAndItems,
      searchPrompt: L.s.searchListsAndItemsLong,
      onAdd: () => openListSheet(context, ref),
      extraHeight: _extraHeight,
      body: (context) => [
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

    final matchedLists = state.lists.where((l) => listMatchesQuery(l.name, query, iconKey: l.iconKey)).toList();
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
                  leading: IconTile(iconKey: (list.kind == ListKind.grocery ? hit.iconKey : null) ?? list.iconKey, size: 38, imageSize: 26),
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
    heightFactor: 0.72,
    onSave: () async {
      final kind = ref.read(listProvider).newType == 'grocery' ? ListKind.grocery : ListKind.other;
      // The sheet has already been popped by the chrome, so the chip lands on
      // the screen behind it, where the row it is talking about just changed.
      final confirm = confirmChipOf(context);
      if (list != null) {
        if (await notifier.updateList(list.id, name: nameController.text, kind: kind, iconKey: draft.picked)) {
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
    child: _ListSheetBody(nameController: nameController, draft: draft, list: list),
  );
}

class _ListSheetBody extends ConsumerStatefulWidget {
  final TextEditingController nameController;
  final IconDraft draft;

  /// The list being edited, or null when creating one — the sheet needs its
  /// stored icon and its old name to tell "not touched yet" from "renamed".
  final ShoppingList? list;

  const _ListSheetBody({required this.nameController, required this.draft, this.list});

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
                final picked = await showIconPicker(context, selected: iconKey, name: name, subject: IconSubject.list);
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
          IconTile(iconKey: list.iconKey, size: 38, imageSize: 26),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  list.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.itemTitle,
                ),
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
                      Flexible(child: EventLinkChip(link: link)),
                      const SizedBox(width: 7),
                    ],
                    Text(
                      meta,
                      style: AppText.label.copyWith(color: metaColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
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

  const _ItemIcon({required this.iconKey});

  @override
  Widget build(BuildContext context) {
    final image = IconImage(asset: resolveIcon(iconKey)?.asset ?? generalGroceryAsset, size: 34);
    if (!AppColors.isDark) {
      return SizedBox(width: 42, height: 42, child: Center(child: image));
    }
    return Container(
      width: 42,
      height: 42,
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
            collapsedIcon: IconTile(iconKey: open.iconKey, size: 24, imageSize: 17),
            t: t,
            expandedAlignment: Alignment.center,
            expandedFontSize: 19,
            fontWeight: FontWeight.w500,
            leadingWidth: 48,
            trailingWidth: 48,
            leading: GlassIconButton(icon: AppIcons.caretLeft, onTap: () => ref.read(listProvider.notifier).back()),
            // "Alle Artikel" is computed rather than stored, so there is nothing
            // there to rename, re-symbol or delete.
            trailing: summary
                ? const SizedBox(width: 40)
                : GlassMenuButton(
                    items: [
                      AnchoredMenuItem(label: L.s.edit, icon: AppIcons.pencilSimple, onSelected: () => openListSheet(context, ref, list: open)),
                      // Its own action, never part of "Für wen?" — see
                      // [showShareSheet]. Absent for kids and for a guest looking
                      // at somebody else's list, both of whom the database refuses.
                      if (ref.watch(canShareExternallyProvider) && !state.guestListIds.contains(open.id))
                        AnchoredMenuItem(
                          label: L.s.share,
                          icon: AppIcons.userPlus,
                          onSelected: () => showShareSheet(
                            context,
                            kind: ShareableKind.list,
                            resourceId: open.id,
                            resourceName: open.name,
                          ),
                        ),
                      AnchoredMenuItem(
                        label: L.s.delete,
                        icon: AppIcons.trash,
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
          estimatedExtraHeight: _detailExtraHeight,
          extra: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Row(
                children: [
                  IconTile(iconKey: open.iconKey, size: 44, imageSize: 30),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      open.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.detailTitle,
                    ),
                  ),
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
                                _swipeToDelete(ref, openItems[i], _ItemRow(item: openItems[i], accent: accent, strike: strike, onCheckOff: checkOff)),
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
                                    Text(
                                      l.name,
                                      style: AppText.groupHeading,
                                    ),
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
                                        onCompleted: () => ref.read(listProvider.notifier).toggle(its[i].id, false),
                                        builder: (context, strike, checkOff) => Column(
                                          children: [
                                            if (i > 0) CardDivider(),
                                            _swipeToDelete(ref, its[i], _ItemRow(item: its[i], accent: accent, strike: strike, onCheckOff: checkOff)),
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
                          Text(
                            L.s.doneWithCount(doneItems.length),
                            style: AppText.caption,
                          ),
                          GestureDetector(
                            onTap: () => ref.read(listProvider.notifier).clearDone(doneItems),
                            child: Text(
                              L.s.deleteDone,
                              style: AppText.caption.copyWith(color: accent),
                            ),
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
                            builder: (context, strike, undo) => _DoneItemRow(item: item, accent: accent, strike: strike, onUndo: undo),
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
/// circle on the left turns into the icon the article is about to get, and — on
/// a Lebensmittel list — a row of article suggestions grows under the field.
/// Both answer German and English, with or without umlauts: *Käse*, *kaese* and
/// *cheese* offer the same chips. Tapping one files the article under its
/// German name.
///
/// [grocery] says whether either of them happens at all. On a Sonstige list
/// the article chips are dropped outright — "Bohrmaschine" is not a shopping
/// article, and a row of food photos under it would be noise — and so is the
/// icon preview, because the row it is previewing carries no icon either. The
/// empty circle stays where it is: it sits exactly where the article's own
/// checkbox will, so the text lines up before and after the add.
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
    final preview = widget.grocery ? suggestIcon(_draft, subject: IconSubject.groceryArticle) : null;
    final suggestions = widget.grocery
        ? [for (final icon in groceryIconSuggestions(_draft)) IconChoice(kind: IconKind.grocery, key: icon.asset, label: icon.label)]
        : const <IconChoice>[];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          child: Row(
            children: [
              // The matched icon takes the empty circle's place the moment the
              // text says what the article is — the same picture the row will
              // carry once it's in the list, so the match is visible before you
              // commit to it.
              SizedBox(
                width: 24,
                height: 24,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: preview == null
                      ? AppIcon(AppIcons.circle, key: ValueKey('empty'), size: 24, color: AppColors.idleRing)
                      : IconTile(key: ValueKey(preview.key), iconKey: preview.key, size: 24, imageSize: 24),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: AppText.inputTitle,
                  decoration: InputDecoration(border: InputBorder.none, hintText: L.s.addItemPlaceholder, isDense: true),
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
            Text(
              choice.label,
              style: AppText.caption.copyWith(color: AppColors.inkSecondary),
            ),
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
    ref.read(listProvider.notifier).editItem(widget.item, text: _textController.text, sub: _subController.text);
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
          // On a Sonstige list there is nothing in that slot to begin with: a
          // Bohrmaschine and a Termin beim Zahnarzt have no picture worth
          // guessing at, and a row of near-identical fallback symbols reads as
          // noise in front of the words that carry the meaning. A checkbox and
          // the text are the whole row — but a photo the user attached
          // themselves still shows, because that one they chose.
          if (photo != null) ...[
            ClipOval(
              // The copy on this device while the session that picked it is
              // still running, the signed URL from then on — see
              // [PhotoThumbnail].
              child: PhotoThumbnail(url: photo.url, filePath: photo.localPath, size: 42),
            ),
            const SizedBox(width: 12),
          ] else if (_isGroceryList(ref, item.listId)) ...[
            _ItemIcon(iconKey: item.iconKey),
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
                          style: _itemTextStyle.copyWith(color: Color.lerp(AppColors.ink, _itemDoneInk, strike)),
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
            child: RowMenuButton(items: _itemMenu(ref, item)),
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

  /// The system's own sheet first — ten choices is more than the app's dropdown
  /// wants to be, and UIKit's already knows how to scroll them. It answers null
  /// off iOS, which is the cue to fall back to the anchored menu, and that is
  /// what [_anchorKey] is for.
  Future<void> _pick() async {
    final units = GroceryUnit.values;
    String? keyOf(GroceryUnit unit) => unit == GroceryUnit.piece ? null : unit.key;

    final picked = await showNativeActionSheet(
      options: [for (final unit in units) unit.label],
      cancelLabel: L.s.cancel,
      dark: AppColors.isDark,
      title: L.s.unit,
    );
    if (picked != null) {
      if (picked != actionSheetCancelled) widget.onPicked(keyOf(units[picked]));
      return;
    }
    if (!mounted) return;
    final active = widget.current ?? GroceryUnit.piece.key;
    await showAnchoredMenu(
      context: context,
      anchorKey: _anchorKey,
      items: [
        for (final unit in units)
          AnchoredMenuItem(
            label: unit.label,
            icon: unit.key == active ? AppIcons.check : AppIcons.circle,
            onSelected: () => widget.onPicked(keyOf(unit)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.current == null ? GroceryUnit.piece.label : groceryUnitLabel(widget.current!);
    return GestureDetector(
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

/// Puts up the system picker and files whatever comes back under the item.
/// Cancelling (or a device with no camera) simply returns nothing.
Future<void> _attach(WidgetRef ref, ShoppingListItem item, AttachmentSource source) async {
  // Photographs are capped on their way in; a document from Dateien is left
  // alone, because there is no such thing as a downscaled PDF.
  final picked = await pickAttachment(source, maxDimension: itemPhotoMaxDimension);
  if (picked == null) return;
  await ref.read(listProvider.notifier).addAttachment(item, picked);
}

/// Swiping an item row left reveals Delete, the same gesture the Kalender
/// event cards and the Boxen item rows use. No `onTap`: the article's own text
/// and its check circle carry the handlers here.
Widget _swipeToDelete(WidgetRef ref, ShoppingListItem item, Widget row) {
  return SwipeToEditDelete(
    onDelete: () => ref.read(listProvider.notifier).removeItem(item),
    child: row,
  );
}

/// The row menu shared by an open item and a checked-off one.
///
/// Labels are the bare noun — "Foto", not "Foto hinzufügen". Every row of a
/// menu is something you're doing to the item, so spelling the verb out four
/// times says nothing and makes the list harder to scan.
List<AnchoredMenuItem> _itemMenu(WidgetRef ref, ShoppingListItem item) {
  final attachments = ref.read(listProvider).attachmentsFor(item);
  return [
    AnchoredMenuItem(
      label: L.s.searchOnAmazon,
      svgAsset: 'assets/merchants/amazon-simple.svg',
      onSelected: () => openExternalUrl(amazonSearchUrl(item.text)),
    ),
    // The three system pickers, straight through to UIKit — see
    // lib/services/media_picker.dart.
    AnchoredMenuItem(label: L.s.photo, icon: AppIcons.image, onSelected: () => _attach(ref, item, AttachmentSource.photos)),
    AnchoredMenuItem(label: L.s.camera, icon: AppIcons.camera, onSelected: () => _attach(ref, item, AttachmentSource.camera)),
    AnchoredMenuItem(label: L.s.files, icon: AppIcons.folder, onSelected: () => _attach(ref, item, AttachmentSource.files)),
    // One row per attached file, because they are stored now and a file you
    // cannot take off again is a file you think twice about putting on. Named
    // by the file only when there are several — with one there is nothing to
    // tell apart, and "IMG_4821.HEIC" says less than "Foto entfernen" does.
    for (final attached in attachments)
      AnchoredMenuItem(
        label: attachments.length == 1 ? L.s.removePhoto : attached.name,
        icon: AppIcons.x,
        destructive: true,
        onSelected: () => ref.read(listProvider.notifier).removeAttachment(item, attached),
      ),
    AnchoredMenuItem(
      label: L.s.delete,
      icon: AppIcons.trash,
      destructive: true,
      onSelected: () => ref.read(listProvider.notifier).removeItem(item),
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
              // Same rule as the open row: pictures on a Lebensmittel list,
              // nothing on a Sonstige one.
              if (_isGroceryList(ref, item.listId)) ...[
                _ItemIcon(iconKey: item.iconKey),
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
                child: RowMenuButton(items: _itemMenu(ref, item)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

