import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../data/grocery_search.dart';
import '../data/icon_suggestions.dart';
import '../data/list_data.dart';
import '../data/merchant_logos.dart';
import '../models/attachment.dart';
import '../models/shopping_list.dart';
import '../services/external_links.dart';
import '../services/media_picker.dart';
import '../state/auth_state.dart';
import '../state/family_state.dart';
import '../state/list_state.dart';
import '../state/sharing_state.dart';
import '../theme/tokens.dart';
import '../widgets/anchored_menu.dart';
import '../widgets/app_sheet.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/check_off.dart';
import '../widgets/collapsing_header.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_note.dart';
import '../widgets/glass.dart';
import '../widgets/icon_picker.dart';
import '../widgets/search.dart';
import '../widgets/share_sheet.dart';
import '../widgets/swipe_actions.dart';
import '../widgets/visibility_picker.dart';

/// Label colour of a checked-off item — the strike-through fades the open row's
/// text to it, so landing in "Erledigt" isn't a colour jump.
Color get _itemDoneInk => AppColors.doneInk;

/// The two lines of an article row. Shared with the fields that replace them
/// while the row is being edited — same family, size and weight, so tapping a
/// name doesn't make the text move.
TextStyle get _itemTextStyle => TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.ink);
TextStyle get _itemSubStyle => TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w300, color: AppColors.muted);

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

class _ListOverview extends ConsumerStatefulWidget {
  final ListScreenState state;

  const _ListOverview({required this.state});

  @override
  ConsumerState<_ListOverview> createState() => _ListOverviewState();
}

class _ListOverviewState extends ConsumerState<_ListOverview> {
  /// First-frame estimate only — [CollapsingHeaderScreen] re-measures the real
  /// thing once it's laid out.
  static const _extraHeight = 74.0;

  static const _searchHint = 'Listen und Artikel durchsuchen';

  /// Search runs *in* the screen (see [HeaderSearchBar]): the header turns into
  /// the system search field and this body shows the hits — no sheet over the
  /// content.
  bool _searching = false;
  String _query = '';

  void _openSearch() => setState(() => _searching = true);

  void _closeSearch() {
    setState(() {
      _searching = false;
      _query = '';
    });
  }

  void _open(String id) {
    _closeSearch();
    ref.read(listProvider.notifier).open(id);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final query = _query.trim();
    return CollapsingHeaderScreen(
      titleRowBuilder: (context, t) => HeaderSearchBar(
        active: _searching,
        hint: _searchHint,
        onChanged: (v) => setState(() => _query = v),
        onClose: _closeSearch,
        // `leadingWidth: 0` on purpose even though there's a leading button: it
        // only fades in once the header is collapsed (see [HeaderSearchButton]),
        // and reserving room for it at rest would push the big "Listen" heading
        // off the left margin.
        child: CollapsingScreenTitle(
          title: 'Listen',
          t: t,
          trailingWidth: 48,
          leading: HeaderSearchButton(t: t, onTap: _openSearch),
          trailing: GlassIconButton(icon: LucideIcons.plus, onTap: () => openListSheet(context, ref)),
        ),
      ),
      // While searching the header is only the field: the trigger pill would be
      // a second search box for the same query, and dropping it gives the
      // results the screen.
      estimatedExtraHeight: _searching ? 0 : _extraHeight,
      extra: _searching
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                SearchTriggerField(hint: _searchHint, onTap: _openSearch),
              ],
            ),
      body: ScreenBodyPanel(
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 18, 16, navContentInset(context, pill: 140)),
          children: _searching
              ? [_searchResults(context, state, query)]
              : [
                  if (_loadFailed(state))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: ErrorNote(message: state.error!, onRetry: () => ref.read(listProvider.notifier).load()),
                    ),
                  // Not while the first load is still out — an account with
                  // twelve lists must not be told it has none.
                  if (state.lists.isEmpty && !state.loading && state.error == null)
                    EmptyState(
                      icon: LucideIcons.listPlus,
                      iconColor: Theme.of(context).colorScheme.primary,
                      message: 'Noch keine Liste angelegt.\nOben tippen, um die erste zu erstellen.',
                    ),
                  if (state.lists.isNotEmpty) _listsCard(context, state),
                ],
        ),
      ),
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
  Widget _listsCard(BuildContext context, ListScreenState state) {
    final rows = <ShoppingList>[if (state.showSummary) allList, ...state.lists];
    return SectionCard(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) CardDivider(),
          // "Alle Artikel" is computed rather than stored, so there is nothing
          // there to rename or delete — it gets the plain row.
          if (rows[i].isSummary)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => ref.read(listProvider.notifier).open(rows[i].id),
              child: _ListRow(list: rows[i], state: state),
            )
          else
            _swipeListRow(context, ref, rows[i], state),
        ],
      ],
    );
  }

  /// Nothing on screen and a message saying why — as opposed to a write that
  /// failed while the screen still has content, which gets a snack instead.
  bool _loadFailed(ListScreenState state) => state.error != null && !state.loading && state.lists.isEmpty;

  /// Search covers the *contents* of every list, not just their names — the
  /// thing you're looking for ("Milch") is an article inside a list far more
  /// often than it is a list. Hits are grouped by the list they live in, and
  /// tapping one opens that list, so the results double as a way in.
  Widget _searchResults(BuildContext context, ListScreenState state, String query) {
    if (query.isEmpty) {
      return SearchResultsPlaceholder(query: '', prompt: 'Nach Listen und Artikeln suchen');
    }

    final matchedLists = state.lists.where((l) => listMatchesQuery(l.name, query, iconKey: l.iconKey)).toList();
    final itemHits = <(ShoppingList, List<ShoppingListItem>)>[];
    for (final l in state.lists) {
      final hits = state.itemsFor(l.id).where((i) => _itemMatches(i, query)).toList();
      if (hits.isNotEmpty) itemHits.add((l, hits));
    }

    if (matchedLists.isEmpty && itemHits.isEmpty) {
      return SearchResultsPlaceholder(query: query, prompt: '');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (matchedLists.isNotEmpty) ...[
          SearchGroupHeading(label: 'Listen', count: matchedLists.length == 1 ? '1 Treffer' : '${matchedLists.length} Treffer'),
          SectionCard(
            children: [
              for (var i = 0; i < matchedLists.length; i++) ...[
                if (i > 0) CardDivider(),
                GestureDetector(
                  // Without this the row is only tappable where a glyph is
                  // actually painted — the padding and the gap before the
                  // chevron fall through.
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _open(matchedLists[i].id),
                  child: _ListRow(list: matchedLists[i], state: state),
                ),
              ],
            ],
          ),
        ],
        for (final (index, (list, hits)) in itemHits.indexed)
          Padding(
            padding: EdgeInsets.only(top: index == 0 && matchedLists.isEmpty ? 0 : 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SearchGroupHeading(
                  label: list.name,
                  count: hits.length == 1 ? '1 Artikel' : '${hits.length} Artikel',
                  icon: IconTile(iconKey: list.iconKey, size: 26, imageSize: 17),
                ),
                SectionCard(
                  children: [
                    for (var i = 0; i < hits.length; i++) ...[
                      if (i > 0) CardDivider(),
                      SearchResultRow(
                        leading: IconTile(iconKey: hits[i].iconKey ?? list.iconKey, size: 38, imageSize: 26),
                        title: hits[i].text,
                        subtitle: hits[i].done ? 'Erledigt · ${list.name}' : (hits[i].sub ?? 'in ${list.name}'),
                        onTap: () => _open(list.id),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

}

/// The create/edit sheet for a list. Same sheet either way — [list] set means
/// editing — so the symbol behaves identically in both.
void openListSheet(BuildContext context, WidgetRef ref, {ShoppingList? list}) {
  final nameController = TextEditingController(text: list?.name ?? '');
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
    title: list == null ? 'Neue Liste' : 'Liste bearbeiten',
    heightFactor: 0.72,
    onSave: () {
      final kind = ref.read(listProvider).newType == 'grocery' ? ListKind.grocery : ListKind.other;
      if (list == null) {
        notifier.createList(name: nameController.text, kind: kind, iconKey: draft.picked);
      } else {
        notifier.updateList(list.id, name: nameController.text, kind: kind, iconKey: draft.picked);
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
    final accent = Theme.of(context).colorScheme.primary;
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
          child: Text('Welche Art von Liste?', style: AppText.microLabel),
        ),
        // The track needs the hairline: `surfaceAlt` is within a percent of the
        // sheet's own `screenBg` body on light, so the segmented control had no
        // visible edge at all there and read as two loose labels, one of which
        // happened to sit on a white pill. The border draws the control; the
        // fill only separates the inactive half from the white thumb.
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              Expanded(
                child: _SegButton(label: 'Lebensmittel', icon: LucideIcons.clipboardList, active: isGrocery, accent: accent, onTap: () => ref.read(listProvider.notifier).setNewType('grocery')),
              ),
              Expanded(
                child: _SegButton(label: 'Sonstige', icon: LucideIcons.clipboardCheck, active: !isGrocery, accent: accent, onTap: () => ref.read(listProvider.notifier).setNewType('other')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: TextField(
                controller: widget.nameController,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 16, color: AppColors.ink),
                decoration: const InputDecoration(border: InputBorder.none, hintText: 'Listenname', isDense: true),
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
              fallbackIcon: isGrocery ? LucideIcons.shoppingCart : LucideIcons.clipboardCheck,
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
          noun: 'die Liste',
        ),
      ],
    );
  }
}

class _SegButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  const _SegButton({required this.label, required this.icon, required this.active, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: active ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: active ? AppShadows.thumb : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: active ? accent : AppColors.muted),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w500, color: active ? accent : AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Swiping a list row left reveals Bearbeiten and Löschen — the same gesture,
/// the same two actions and the same order as an article row inside a list (see
/// [_swipeToDelete]), so the overview doesn't make renaming a list a trip
/// through its detail screen's menu.
///
/// The opaque [ColoredBox] is what keeps the actions from showing through the
/// sliding row: the row itself paints nothing, the [SectionCard] around it does.
Widget _swipeListRow(BuildContext context, WidgetRef ref, ShoppingList list, ListScreenState state) {
  return SwipeActionsRow(
    onTap: () => ref.read(listProvider.notifier).open(list.id),
    actions: [
      SwipeAction(
        icon: LucideIcons.pencil,
        color: Theme.of(context).colorScheme.primary,
        onTap: () => openListSheet(context, ref, list: list),
      ),
      SwipeAction(
        icon: LucideIcons.trash2,
        color: AppColors.danger,
        // Nothing left to close once the row is gone.
        closesRow: false,
        onTap: () => ref.read(listProvider.notifier).deleteList(list.id),
      ),
    ],
    child: ColoredBox(color: AppColors.surface, child: _ListRow(list: list, state: state)),
  );
}

/// One list on the overview card. Carries no tap target of its own — the row is
/// wrapped either by [_swipeListRow] or by a plain [GestureDetector], and a
/// second detector inside would swallow the tap that closes an open swipe.
class _ListRow extends StatelessWidget {
  final ShoppingList list;
  final ListScreenState state;

  const _ListRow({required this.list, required this.state});

  @override
  Widget build(BuildContext context) {
    final its = state.itemsFor(list.id);
    final remaining = its.where((i) => !i.done).length;
    final meta = its.isEmpty ? 'Leer' : (remaining == 0 ? 'Alles erledigt' : '$remaining verbleibend');
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
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
                Text(
                  meta,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, fontWeight: FontWeight.w300, color: metaColor),
                ),
              ],
            ),
          ),
          Icon(LucideIcons.chevronRight, size: 16, color: AppColors.mutedLight),
        ],
      ),
    );
  }
}

/// The picture at the left of an article row — the grocery image, shop logo or
/// symbol its name was matched to, or the generic glyph when nothing matched.
///
/// The picture assets are full-colour art on transparency, drawn for a light
/// background. On light that background is already there, so the picture sits
/// straight on the card with no tile at all — a circle around it would only add
/// a line the eye has to read past. On dark it needs the same white disc
/// third-party logos get ([AppPalette.brandTile]), or the dark linework
/// disappears into the card. A Lucide symbol has no such problem: it is drawn
/// in the theme's own ink, so it gets the ordinary tile from [IconTile].
class _ItemIcon extends StatelessWidget {
  final String? iconKey;
  final Color accent;

  const _ItemIcon({required this.iconKey, required this.accent});

  @override
  Widget build(BuildContext context) {
    final asset = resolveIcon(iconKey)?.asset;
    if (asset == null) {
      return IconTile(iconKey: iconKey, size: 42, imageSize: 20, glyphSize: 20, fallbackIcon: LucideIcons.clipboardCheck, glyphColor: accent);
    }
    final image = IconImage(asset: asset, size: 34);
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

    final glowColor = summary ? accent : _brandGlow(open.iconKey);

    return CollapsingHeaderScreen(
      backdrop: HeaderBrandGlow(color: glowColor),
      // The pinned row keeps the generic "Liste" label at rest — the list's
      // own name is the big row below it — and swaps to that name as the
      // big one scrolls away, so the bar never stops saying which list
      // you're in.
      titleRowBuilder: (context, t) => CollapsingScreenTitle(
        title: 'Liste',
        collapsedTitle: open.name,
        collapsedIcon: IconTile(iconKey: open.iconKey, size: 24, imageSize: 17),
        t: t,
        expandedAlignment: Alignment.center,
        expandedFontSize: 19,
        fontWeight: FontWeight.w500,
        leadingWidth: 48,
        trailingWidth: 48,
        leading: GlassIconButton(icon: LucideIcons.chevronLeft, onTap: () => ref.read(listProvider.notifier).back()),
        // "Alle Artikel" is computed rather than stored, so there is nothing
        // there to rename, re-symbol or delete.
        trailing: summary
            ? const SizedBox(width: 40)
            : GlassMenuButton(
                items: [
                  AnchoredMenuItem(label: 'Bearbeiten', icon: LucideIcons.pencil, onSelected: () => openListSheet(context, ref, list: open)),
                  // Its own action, never part of "Für wen?" — see
                  // [showShareSheet]. Absent for kids and for a guest looking
                  // at somebody else's list, both of whom the database refuses.
                  if (ref.watch(canShareExternallyProvider) && !state.guestListIds.contains(open.id))
                    AnchoredMenuItem(
                      label: 'Teilen',
                      icon: LucideIcons.userPlus,
                      onSelected: () => showShareSheet(
                        context,
                        kind: ShareableKind.list,
                        resourceId: open.id,
                        resourceName: open.name,
                      ),
                    ),
                  AnchoredMenuItem(
                    label: 'Löschen',
                    icon: LucideIcons.trash2,
                    destructive: true,
                    onSelected: () => ref.read(listProvider.notifier).deleteList(open.id),
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
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 23, fontWeight: FontWeight.w600, letterSpacing: -0.4, color: AppColors.ink),
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
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted, letterSpacing: 0.3),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  its.length == 1 ? '1 Artikel' : '${its.length} Artikel',
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w300, color: AppColors.mutedLight),
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
                        'Erledigt (${doneItems.length})',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.muted),
                      ),
                      GestureDetector(
                        onTap: () => ref.read(listProvider.notifier).clearDone(doneItems),
                        child: Text(
                          'Erledigte löschen',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500, color: accent),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SectionCard(
                children: [
                  for (var i = 0; i < doneItems.length; i++) ...[
                    if (i > 0) CardDivider(),
                    CheckOffArrival(
                      key: ValueKey(doneItems[i].id),
                      animate: doneItems[i].id == state.justMoved,
                      // Undo runs the same animation backwards before the item
                      // travels back up into the open list.
                      child: CheckOffRow(
                        undo: true,
                        onCompleted: () => ref.read(listProvider.notifier).toggle(doneItems[i].id, true),
                        builder: (context, strike, undo) => _DoneItemRow(item: doneItems[i], accent: accent, strike: strike, onUndo: undo),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            if (items.isEmpty)
              EmptyState(
                icon: LucideIcons.clipboardCheck,
                iconColor: accent,
                message: 'Oben tippen, um das erste Element hinzuzufügen',
                verticalPadding: 56,
                gap: 16,
              ),
          ],
        ),
      ),
    );
  }

  /// The header glow behind a list, taken from the shop logo it carries.
  ///
  /// Keyed on the icon, not the list id: ids are `lists.id` uuids now, so the
  /// old switch over four seed ids ('week', 'drug', …) could never match again.
  /// Only the four shops the palette actually has a colour for are named; every
  /// other list glows in the app accent.
  Color _brandGlow(String? iconKey) {
    if (iconKey == null || !iconKey.startsWith(merchantAssetDir)) return AppColors.accent;
    final file = iconKey.substring(merchantAssetDir.length);
    switch (file) {
      case 'rewe_de.png':
        return AppColors.brandRewe;
      case 'dm_de.png':
        return AppColors.brandDm;
      case 'toom_de.png':
        return AppColors.brandToom;
      case 'ikea_com.png':
        return AppColors.brandIkea;
      default:
        return AppColors.accent;
    }
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
/// [grocery] says which catalog gets the first look at what was typed. On a
/// Sonstige list the article chips are dropped outright — "Bohrmaschine" is not
/// a shopping article, and a row of food photos under it would be noise — but
/// the icon preview stays, and there it can just as well come out as a symbol
/// or a shop logo.
class _AddItemRow extends ConsumerStatefulWidget {
  final bool grocery;

  const _AddItemRow({required this.grocery});

  @override
  ConsumerState<_AddItemRow> createState() => _AddItemRowState();
}

class _AddItemRowState extends ConsumerState<_AddItemRow> {
  final _controller = TextEditingController();
  String _draft = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add(String text, {String? iconKey}) {
    ref.read(listProvider.notifier).addItem(text, iconKey: iconKey);
    _controller.clear();
    setState(() => _draft = '');
  }

  @override
  Widget build(BuildContext context) {
    final preview = suggestIcon(_draft, subject: widget.grocery ? IconSubject.groceryArticle : IconSubject.article);
    final suggestions = widget.grocery
        ? [for (final icon in groceryIconSuggestions(_draft)) IconChoice(kind: IconKind.grocery, key: icon.asset, label: icon.de)]
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
                      ? Icon(LucideIcons.circle, key: ValueKey('empty'), size: 24, color: AppColors.idleRing)
                      : IconTile(key: ValueKey(preview.key), iconKey: preview.key, size: 24, imageSize: 24),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 16, color: AppColors.ink),
                  decoration: const InputDecoration(border: InputBorder.none, hintText: 'Artikel hinzufügen...', isDense: true),
                  textInputAction: TextInputAction.done,
                  onChanged: (v) => setState(() => _draft = v),
                  onSubmitted: (v) => _add(v),
                ),
              ),
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
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.inkSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// An open article, and the place it gets renamed.
///
/// Tapping the name turns the two lines of text into the two fields they
/// already look like — the article and the quantity under it — right where
/// they sit, so a wrong article is corrected in the list instead of in a sheet
/// on top of it. The row leaves edit mode the moment the fields lose focus,
/// whether that's Return, a tap somewhere else on the screen or the keyboard
/// being put away.
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 15),
      child: Row(
        children: [
          CheckOffButton(progress: strike, accent: accent, onTap: onCheckOff, size: 24),
          const SizedBox(width: 12),
          // An attached photo takes the icon's place: it *is* the picture of
          // this item, and it says more than the generic grocery glyph it
          // replaces. Rounded rather than round — a photo cropped to a circle
          // loses its corners for nothing.
          if (photo != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.file(File(photo.path), width: 42, height: 42, fit: BoxFit.cover),
            )
          else
            _ItemIcon(iconKey: item.iconKey, accent: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_editing) ...[
                  TextField(
                    controller: _textController,
                    focusNode: _textFocus,
                    style: _itemTextStyle,
                    decoration: _inlineFieldDecoration('Artikel', _itemTextStyle),
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _subFocus.requestFocus(),
                  ),
                  TextField(
                    controller: _subController,
                    focusNode: _subFocus,
                    style: _itemSubStyle,
                    decoration: _inlineFieldDecoration('Menge', _itemSubStyle),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _commit(),
                  ),
                ] else ...[
                  // The whole text block is the target and it edits the name —
                  // the strip of empty row next to a short article is still
                  // that article, and aiming at four glyphs isn't a tap. The
                  // quantity carries a target of its own on top of it, so the
                  // line you actually hit is the line that opens.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _startEditing(_textFocus),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StrikeThrough(
                          progress: strike,
                          color: _itemDoneInk,
                          child: Text(
                            item.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _itemTextStyle.copyWith(color: Color.lerp(AppColors.ink, _itemDoneInk, strike)),
                          ),
                        ),
                        if (item.sub != null)
                          Opacity(
                            opacity: 1 - 0.45 * strike,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _startEditing(_subFocus),
                              child: Text(item.sub!, style: _itemSubStyle),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (attachments.isNotEmpty)
                  Opacity(
                    opacity: 1 - 0.45 * strike,
                    child: _AttachmentsLine(attachments: attachments, accent: accent),
                  ),
              ],
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

/// What the item is carrying, under its name: the file's own name while
/// there's only one, a count once there are several — a column of file names
/// would drown out the item itself.
class _AttachmentsLine extends StatelessWidget {
  final List<ItemAttachment> attachments;
  final Color accent;

  const _AttachmentsLine({required this.attachments, required this.accent});

  @override
  Widget build(BuildContext context) {
    final label = attachments.length == 1 ? attachments.first.name : '${attachments.length} Anhänge';
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.paperclip, size: 11, color: accent),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w500, color: accent),
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
  final picked = await pickAttachment(source);
  if (picked == null) return;
  ref.read(listProvider.notifier).addAttachment(item.id, picked);
}

/// Swiping an item row left reveals Delete, the same gesture the Kalender
/// event cards use. Square corners and an explicit white fill: the row is
/// inside a [SectionCard], which owns the rounded corners and the background
/// the row itself doesn't paint — and the sliding row has to be opaque or the
/// action shows straight through it.
Widget _swipeToDelete(WidgetRef ref, ShoppingListItem item, Widget row) {
  return SwipeActionsRow(
    actions: [
      SwipeAction(
        icon: LucideIcons.trash2,
        color: AppColors.danger,
        closesRow: false,
        onTap: () => ref.read(listProvider.notifier).removeItem(item),
      ),
    ],
    child: ColoredBox(color: AppColors.surface, child: row),
  );
}

/// The row menu shared by an open item and a checked-off one.
///
/// Labels are the bare noun — "Foto", not "Foto hinzufügen". Every row of a
/// menu is something you're doing to the item, so spelling the verb out four
/// times says nothing and makes the list harder to scan.
List<AnchoredMenuItem> _itemMenu(WidgetRef ref, ShoppingListItem item) {
  return [
    AnchoredMenuItem(
      label: 'Bei Amazon suchen',
      svgAsset: 'assets/merchants/amazon-simple.svg',
      onSelected: () => openExternalUrl(amazonSearchUrl(item.text)),
    ),
    // The three system pickers, straight through to UIKit — see
    // lib/services/media_picker.dart.
    AnchoredMenuItem(label: 'Foto', icon: LucideIcons.image, onSelected: () => _attach(ref, item, AttachmentSource.photos)),
    AnchoredMenuItem(label: 'Kamera', icon: LucideIcons.camera, onSelected: () => _attach(ref, item, AttachmentSource.camera)),
    AnchoredMenuItem(label: 'Dateien', icon: LucideIcons.folder, onSelected: () => _attach(ref, item, AttachmentSource.files)),
    AnchoredMenuItem(
      label: 'Löschen',
      icon: LucideIcons.trash2,
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
              _ItemIcon(iconKey: item.iconKey, accent: accent),
              const SizedBox(width: 12),
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
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w400, color: Color.lerp(AppColors.ink, _itemDoneInk, strike)),
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

