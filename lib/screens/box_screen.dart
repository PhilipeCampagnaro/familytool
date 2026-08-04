import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../data/icon_suggestions.dart';
import '../models/box_item.dart';
import '../state/auth_state.dart';
import '../state/box_state.dart';
import '../state/family_state.dart';
import '../state/sharing_state.dart';
import '../theme/tokens.dart';
import '../widgets/anchored_menu.dart';
import '../widgets/app_sheet.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/collapsing_header.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_note.dart';
import '../widgets/glass.dart';
import '../widgets/icon_picker.dart';
import '../widgets/search.dart';
import '../widgets/share_sheet.dart';
import '../widgets/swipe_actions.dart';
import '../widgets/visibility_picker.dart';

class BoxScreen extends ConsumerWidget {
  const BoxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(boxProvider);

    // A write that didn't land is reported once, transiently, and then
    // forgotten. A failed *load* is deliberately not snacked: it leaves an
    // empty screen behind, which needs an explanation that stays put, and the
    // body renders an [ErrorNote] with a retry for exactly that case.
    ref.listen<String?>(boxProvider.select((s) => s.error), (_, message) {
      if (message == null) return;
      final current = ref.read(boxProvider);
      if (current.boxes.isEmpty && !current.loading) return;
      showErrorSnack(context, message);
      ref.read(boxProvider.notifier).clearError();
    });

    return Scaffold(
      backgroundColor: AppColors.surface,
      // The detail screen goes edge to edge on purpose: its header carries an
      // accent glow that has to start at the very top of the display, so it
      // absorbs the status-bar inset itself (see [CollapsingHeaderScreen])
      // rather than being pushed below a white band.
      body: state.isDetail ? _BoxDetail(state: state) : SafeArea(bottom: false, child: _BoxOverview(state: state)),
    );
  }
}

class _BoxOverview extends ConsumerStatefulWidget {
  final BoxScreenState state;

  const _BoxOverview({required this.state});

  @override
  ConsumerState<_BoxOverview> createState() => _BoxOverviewState();
}

class _BoxOverviewState extends ConsumerState<_BoxOverview> {
  /// First-frame estimate only — [CollapsingHeaderScreen] re-measures the real
  /// thing once it's laid out.
  static const _extraHeight = 163.0;

  static const _searchHint = 'Boxen und Artikel durchsuchen';

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
    ref.read(boxProvider.notifier).open(id);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final accent = Theme.of(context).colorScheme.primary;
    final query = _query.trim();
    return CollapsingHeaderScreen(
      titleRowBuilder: (context, t) => HeaderSearchBar(
        active: _searching,
        hint: _searchHint,
        onChanged: (v) => setState(() => _query = v),
        onClose: _closeSearch,
        // `leadingWidth: 0` on purpose even though there's a leading button: it
        // only fades in once the header is collapsed (see [HeaderSearchButton]),
        // and reserving room for it at rest would push the big "Boxen" heading
        // off the left margin.
        child: CollapsingScreenTitle(
          title: 'Boxen',
          t: t,
          trailingWidth: 48,
          leading: HeaderSearchButton(t: t, onTap: _openSearch),
          trailing: GlassIconButton(icon: LucideIcons.plus, onTap: () => openBoxSheet(context, ref)),
        ),
      ),
      // While searching the header is only the field: the trigger pill would be
      // a second search box for the same query, and dropping it (with the stat
      // tiles) gives the results the screen.
      estimatedExtraHeight: _searching ? 0 : _extraHeight,
      extra: _searching
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                SearchTriggerField(hint: _searchHint, onTap: _openSearch),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _StatTile(value: '${state.boxes.length}', icon: LucideIcons.box, label: 'Boxen', accent: accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatTile(value: '${state.totalItems}', icon: LucideIcons.clipboardList, label: 'Artikel', accent: accent),
                    ),
                  ],
                ),
              ],
            ),
      body: ScreenBodyPanel(
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 18, 16, navContentInset(context, pill: 140)),
          children: _searching
              ? [_searchResults(context, state, accent, query)]
              : _loadFailed(state)
                  ? [
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: ErrorNote(message: state.error!, onRetry: () => ref.read(boxProvider.notifier).load()),
                      ),
                    ]
                  : [
                      SectionCard(
                        children: [
                          for (var i = 0; i < state.boxes.length; i++) ...[
                            if (i > 0) CardDivider(),
                            _swipeBoxRow(context, ref, state.boxes[i], state.itemsFor(state.boxes[i].id).length, accent),
                          ],
                          // Not while the first load is still out — an account
                          // with twelve boxes must not be told it has none.
                          if (state.boxes.isEmpty && !state.loading)
                            EmptyState(
                              icon: LucideIcons.box,
                              iconColor: accent,
                              message: 'Noch keine Box angelegt.\nLeg eine an, um Verstautes wiederzufinden.',
                            ),
                        ],
                      ),
                    ],
        ),
      ),
    );
  }

  /// Nothing on screen and a message saying why — as opposed to a write that
  /// failed while the screen still has content, which gets a snack instead.
  bool _loadFailed(BoxScreenState state) => state.error != null && !state.loading && state.boxes.isEmpty;

  /// Search covers what's *in* the boxes, not just their names — a box is only
  /// worth finding because of what you stored in it. Article hits are grouped
  /// under their box and open it, so a result is also the way there.
  Widget _searchResults(BuildContext context, BoxScreenState state, Color accent, String query) {
    final q = query.toLowerCase();
    if (q.isEmpty) {
      return SearchResultsPlaceholder(query: '', prompt: 'Nach Boxen und Artikeln suchen');
    }

    final matchedBoxes = state.boxes.where((b) => b.name.toLowerCase().contains(q) || b.place.toLowerCase().contains(q)).toList();
    final itemHits = <(StorageBox, List<BoxItem>)>[];
    for (final b in state.boxes) {
      final hits = state
          .itemsFor(b.id)
          .where((i) => i.name.toLowerCase().contains(q) || i.meta.toLowerCase().contains(q) || (i.note?.toLowerCase().contains(q) ?? false))
          .toList();
      if (hits.isNotEmpty) itemHits.add((b, hits));
    }

    if (matchedBoxes.isEmpty && itemHits.isEmpty) {
      return SearchResultsPlaceholder(query: query, prompt: '');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (matchedBoxes.isNotEmpty) ...[
          SearchGroupHeading(label: 'Boxen', count: matchedBoxes.length == 1 ? '1 Treffer' : '${matchedBoxes.length} Treffer'),
          SectionCard(
            children: [
              for (var i = 0; i < matchedBoxes.length; i++) ...[
                if (i > 0) CardDivider(),
                GestureDetector(
                  // Without this the row is only tappable where a glyph is
                  // actually painted — the padding and the gap before the
                  // chevron fall through.
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _open(matchedBoxes[i].id),
                  child: _BoxRow(box: matchedBoxes[i], itemCount: state.itemsFor(matchedBoxes[i].id).length, accent: accent),
                ),
              ],
            ],
          ),
        ],
        for (final (index, (box, hits)) in itemHits.indexed)
          Padding(
            padding: EdgeInsets.only(top: index == 0 && matchedBoxes.isEmpty ? 0 : 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SearchGroupHeading(
                  label: box.name,
                  count: hits.length == 1 ? '1 Artikel' : '${hits.length} Artikel',
                  icon: _BoxBadge(box: box, size: 26, iconSize: 14, accent: accent),
                ),
                SectionCard(
                  children: [
                    for (var i = 0; i < hits.length; i++) ...[
                      if (i > 0) CardDivider(),
                      SearchResultRow(
                        leading: IconTile(
                          iconKey: hits[i].iconKey,
                          size: 38,
                          imageSize: 24,
                          glyphSize: 18,
                          fallbackIcon: LucideIcons.clipboardList,
                          glyphColor: accent,
                        ),
                        title: hits[i].name,
                        subtitle: hits[i].meta.isEmpty ? '${box.name} · ${box.place}' : '${hits[i].meta} · ${box.place}',
                        onTap: () => _open(box.id),
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

/// The create/edit sheet for a box. Same sheet either way — [box] set means
/// editing — so the symbol behaves identically in both.
void openBoxSheet(BuildContext context, WidgetRef ref, {StorageBox? box}) {
  final nameController = TextEditingController(text: box?.name ?? '');
  final placeController = TextEditingController(text: box?.place ?? '');
  // Empty even when editing — see [openListSheet] for the bug that seeding it
  // with the stored icon caused: the edit read as a manual pick, so renaming a
  // box left its old icon both in the preview and in the write.
  final draft = IconDraft(null);
  // Before the sheet is built, so it opens on this box's own audience rather
  // than on whatever the last sheet left behind.
  ref.read(boxProvider.notifier).primeVisibility(box);
  showAppSheet(
    context: context,
    title: box == null ? 'Neue Box' : 'Box bearbeiten',
    heightFactor: 0.64,
    onSave: () {
      if (box == null) {
        ref.read(boxProvider.notifier).createBox(name: nameController.text, place: placeController.text, iconKey: draft.picked);
      } else {
        ref.read(boxProvider.notifier).updateBox(box.id, name: nameController.text, place: placeController.text, iconKey: draft.picked);
      }
    },
    child: _BoxSheetBody(nameController: nameController, placeController: placeController, draft: draft, box: box),
  );
}

class _BoxSheetBody extends ConsumerStatefulWidget {
  final TextEditingController nameController;
  final TextEditingController placeController;
  final IconDraft draft;

  /// The box being edited, or null when creating one — the sheet needs its
  /// stored icon and its old name to tell "not touched yet" from "renamed".
  final StorageBox? box;

  const _BoxSheetBody({required this.nameController, required this.placeController, required this.draft, this.box});

  @override
  ConsumerState<_BoxSheetBody> createState() => _BoxSheetBodyState();
}

class _BoxSheetBodyState extends ConsumerState<_BoxSheetBody> {
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(boxProvider);
    final name = widget.nameController.text;
    // The live guess, recomputed per keystroke and only used while nothing has
    // been picked by hand: "Keller" a warehouse, "Werkzeug" a hammer.
    // Same three-way rule as the list sheet, and the same reason: this is what
    // [BoxNotifier.updateBox] will store.
    final untouched = name.trim() == (widget.box?.name ?? '');
    final stored = untouched ? widget.box?.iconKey : null;
    final iconKey = widget.draft.picked ?? stored ?? suggestIcon(name, subject: IconSubject.box)?.key;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: TextField(
                controller: widget.nameController,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 16, color: AppColors.ink),
                decoration: const InputDecoration(border: InputBorder.none, hintText: 'Box-Name', isDense: true),
                onChanged: (_) => setState(() {}),
              ),
            ),
            CardDivider(),
            IconFieldRow(
              iconKey: iconKey,
              // The sparkle means "the name chose this" — not true of the icon
              // an edit sheet opens on.
              suggested: widget.draft.picked == null && stored == null,
              fallbackIcon: LucideIcons.box,
              onTap: () async {
                final picked = await showIconPicker(context, selected: iconKey, name: name, subject: IconSubject.box);
                if (picked != null && mounted) setState(() => widget.draft.picked = picked);
              },
            ),
            CardDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  Text(
                    'Ort',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 14.5, fontWeight: FontWeight.w500, color: AppColors.ink),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: TextField(
                      controller: widget.placeController,
                      textAlign: TextAlign.right,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 15, color: AppColors.ink),
                      decoration: const InputDecoration(border: InputBorder.none, hintText: 'z.B. Keller, Dachboden', isDense: true),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Writes `boxes.visibility` plus the rows in `box_shares` — not the old
        // single `who` string, which conflated "who does this" with "who may
        // see it". Member chips are dropped for a guest: the composite foreign
        // key behind `box_shares` makes picking somebody outside the owning
        // household a constraint error, not a polite refusal.
        VisibilityPicker(
          visibility: s.newVisibility,
          sharedWith: s.newSharedWith,
          onChanged: ref.read(boxProvider.notifier).setVisibility,
          members: ref.watch(householdMembersProvider),
          currentUserId: ref.watch(currentUserIdProvider),
          allowMembers: !s.isGuest,
          noun: 'die Box',
        ),
      ],
    );
  }
}

class _BoxDetail extends ConsumerWidget {
  final BoxScreenState state;

  const _BoxDetail({required this.state});

  /// First-frame estimate only — see [_BoxOverview._extraHeight].
  static const _detailExtraHeight = 62.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = Theme.of(context).colorScheme.primary;
    // The open box can be gone — nothing ships with the app, and a box can be
    // removed while its detail view is on screen. Bail to the overview rather
    // than throwing out of firstWhere.
    final match = state.boxes.where((b) => b.id == state.openId);
    if (match.isEmpty) return const SizedBox.shrink();
    final box = match.first;
    final items = state.itemsFor(box.id);

    return CollapsingHeaderScreen(
      backdrop: HeaderBrandGlow(color: accent, strength: .14),
      // The pinned row keeps the generic "Box" label at rest — the box's own
      // name is the big row below it — and swaps to that name as the big one
      // scrolls away, so the bar never stops saying which box you're in.
      titleRowBuilder: (context, t) => CollapsingScreenTitle(
        title: 'Box',
        collapsedTitle: box.name,
        collapsedIcon: _BoxBadge(box: box, size: 24, iconSize: 13, accent: accent),
        t: t,
        expandedAlignment: Alignment.center,
        expandedFontSize: 19,
        fontWeight: FontWeight.w500,
        leadingWidth: 48,
        trailingWidth: 48,
        leading: GlassIconButton(icon: LucideIcons.chevronLeft, onTap: () => ref.read(boxProvider.notifier).back()),
        trailing: GlassMenuButton(
          items: [
            AnchoredMenuItem(label: 'Bearbeiten', icon: LucideIcons.pencil, onSelected: () => openBoxSheet(context, ref, box: box)),
            if (ref.watch(canShareExternallyProvider) && !state.guestBoxIds.contains(box.id))
              AnchoredMenuItem(
                label: 'Teilen',
                icon: LucideIcons.userPlus,
                onSelected: () => showShareSheet(
                  context,
                  kind: ShareableKind.box,
                  resourceId: box.id,
                  resourceName: box.name,
                ),
              ),
            AnchoredMenuItem(
              label: 'Löschen',
              icon: LucideIcons.trash2,
              destructive: true,
              onSelected: () => ref.read(boxProvider.notifier).deleteBox(box.id),
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
              _BoxBadge(box: box, size: 44, iconSize: 20, accent: accent),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  box.name,
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
                const _AddItemRow(),
                for (var i = 0; i < items.length; i++) ...[CardDivider(), _ItemRow(item: items[i], accent: accent)],
                if (items.isEmpty)
                  const EmptyState(
                    icon: LucideIcons.clipboardList,
                    message: 'Oben tippen, um das erste Element hinzuzufügen',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The box's round icon badge — full size next to the name, small alongside the
/// collapsed title in the header bar. Draws whatever the box's name produced
/// (or was overridden to), falling back to the plain carton.
class _BoxBadge extends StatelessWidget {
  final StorageBox box;
  final double size;
  final double iconSize;
  final Color accent;

  const _BoxBadge({required this.box, required this.size, required this.iconSize, required this.accent});

  @override
  Widget build(BuildContext context) {
    return IconTile(
      iconKey: box.iconKey,
      size: size,
      imageSize: iconSize * 1.5,
      glyphSize: iconSize,
      fallbackIcon: LucideIcons.box,
      glyphColor: accent,
    );
  }
}

class _ItemRow extends ConsumerWidget {
  final BoxItem item;
  final Color accent;

  const _ItemRow({required this.item, required this.accent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Swiping the row left reveals Delete, the same gesture the Kalender event
    // cards use. The row is inside a [SectionCard], which owns the rounded
    // corners and the white fill the row doesn't paint itself — hence the
    // square corners here and the explicit [ColoredBox], without which the
    // action would show straight through the sliding row.
    return SwipeActionsRow(
      onTap: () => _openItemSheet(context, ref, item),
      actions: [
        SwipeAction(
          icon: LucideIcons.trash2,
          color: AppColors.danger,
          closesRow: false,
          onTap: () => ref.read(boxProvider.notifier).removeItem(item),
        ),
      ],
      child: ColoredBox(
        color: AppColors.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 15),
          child: Row(
            children: [
              IconTile(
                iconKey: item.iconKey,
                size: 44,
                imageSize: 28,
                glyphSize: 20,
                fallbackIcon: LucideIcons.clipboardList,
                glyphColor: accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.ink),
                    ),
                    if (item.meta.isNotEmpty)
                      Text(
                        item.meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w300, color: AppColors.muted),
                      ),
                  ],
                ),
              ),
              RowMenuButton(
                items: [
                  AnchoredMenuItem(
                    label: 'Bearbeiten',
                    icon: LucideIcons.pencil,
                    onSelected: () => _openItemSheet(context, ref, item),
                  ),
                  AnchoredMenuItem(
                    label: 'Löschen',
                    icon: LucideIcons.trash2,
                    destructive: true,
                    onSelected: () => ref.read(boxProvider.notifier).removeItem(item),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openItemSheet(BuildContext context, WidgetRef ref, BoxItem item) {
    final form = _ItemForm(item);
    showAppSheet(
      context: context,
      title: 'Artikel bearbeiten',
      // An emptied *name* means "left it alone", not "call this item ''" —
      // whereas an emptied Größe or Notiz does mean "drop it", since both are
      // optional to begin with.
      onSave: () => ref.read(boxProvider.notifier).editItem(
            item,
            name: form.name.text,
            size: form.size.text,
            qty: form.qty,
            note: form.note.text,
            iconKey: form.draft.picked,
          ),
      child: _ItemSheetBody(item: item, form: form),
    );
  }
}

/// The item being edited, held by reference — the sheet's save button belongs to
/// the shared chrome and is handed its callback before the body exists, the same
/// arrangement `IconDraft` and the Kalender event form use.
class _ItemForm {
  _ItemForm(BoxItem item)
      : name = TextEditingController(text: item.name),
        size = TextEditingController(text: item.size ?? ''),
        note = TextEditingController(text: item.note ?? ''),
        draft = IconDraft(item.iconKey),
        qty = item.qty;

  final TextEditingController name;
  final TextEditingController size;
  final TextEditingController note;
  final IconDraft draft;

  /// Stepped rather than typed: a quantity is a small number, and a keyboard for
  /// it costs more taps than the two buttons do.
  int qty;

  void dispose() {
    name.dispose();
    size.dispose();
    note.dispose();
  }
}

class _ItemSheetBody extends ConsumerStatefulWidget {
  final BoxItem item;
  final _ItemForm form;

  const _ItemSheetBody({required this.item, required this.form});

  @override
  ConsumerState<_ItemSheetBody> createState() => _ItemSheetBodyState();
}

class _ItemSheetBodyState extends ConsumerState<_ItemSheetBody> {
  @override
  void dispose() {
    widget.form.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final nameController = widget.form.name;
    final name = nameController.text;
    final iconKey = widget.form.draft.picked ?? suggestIcon(name)?.key ?? item.iconKey;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: nameController,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 16, color: AppColors.ink),
                      decoration: const InputDecoration(border: InputBorder.none, hintText: 'Artikelname', isDense: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: AppColors.surfaceAlt, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Icon(LucideIcons.scanLine, size: 16, color: AppColors.inkSecondary),
                  ),
                ],
              ),
            ),
            CardDivider(),
            IconFieldRow(
              iconKey: iconKey,
              suggested: widget.form.draft.picked == null,
              fallbackIcon: LucideIcons.clipboardList,
              onTap: () async {
                final picked = await showIconPicker(context, selected: iconKey, name: name);
                if (picked != null && mounted) setState(() => widget.form.draft.picked = picked);
              },
            ),
            CardDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  Text(
                    'Größe',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 14.5, fontWeight: FontWeight.w500, color: AppColors.ink),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: TextField(
                      controller: widget.form.size,
                      textAlign: TextAlign.right,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 15, color: AppColors.ink),
                      decoration: const InputDecoration(border: InputBorder.none, hintText: 'z.B. EU 38, XL, 500ml', isDense: true),
                    ),
                  ),
                ],
              ),
            ),
            CardDivider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Menge',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 14.5, fontWeight: FontWeight.w500, color: AppColors.ink),
                    ),
                  ),
                  _QtyStepper(
                    value: widget.form.qty,
                    // Floored at one: a box holding nought of something is a box
                    // that doesn't hold it, and that is the delete button's job.
                    onChanged: (v) => setState(() => widget.form.qty = v.clamp(1, 999)),
                  ),
                ],
              ),
            ),
            CardDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: TextField(
                controller: widget.form.note,
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 15, color: AppColors.ink),
                decoration: const InputDecoration(border: InputBorder.none, hintText: 'Notizen, Zustand, Ort...', isDense: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () {
            Navigator.of(context).pop();
            ref.read(boxProvider.notifier).removeItem(item);
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.card),
            alignment: Alignment.center,
            child: Text(
              'Artikel löschen',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.danger),
            ),
          ),
        ),
      ],
    );
  }
}

/// −/+ around a number, for the item sheet's Menge row.
///
/// A stepper rather than a text field: the quantity in a box is almost always a
/// single digit, and putting up a numeric keyboard for it costs more taps than
/// the two buttons — and lets somebody type "zwölf".
class _QtyStepper extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _QtyStepper({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _QtyButton(icon: LucideIcons.minus, accent: accent, enabled: value > 1, onTap: () => onChanged(value - 1)),
        SizedBox(
          width: 38,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
          ),
        ),
        _QtyButton(icon: LucideIcons.plus, accent: accent, enabled: true, onTap: () => onChanged(value + 1)),
      ],
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final bool enabled;
  final VoidCallback onTap;

  const _QtyButton({required this.icon, required this.accent, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(color: AppColors.surfaceAlt, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Icon(icon, size: 15, color: enabled ? accent : AppColors.mutedLight),
      ),
    );
  }
}

/// The "Artikel hinzufügen" line of a box, with the same live match the Listen
/// field has: the circle on the left turns into the picture the item is about
/// to get as soon as the name says what it is (`data/icon_suggestions.dart`).
/// No grocery bias — a box holds a drill far more often than it holds milk.
class _AddItemRow extends ConsumerStatefulWidget {
  const _AddItemRow();

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

  void _add(String text) {
    ref.read(boxProvider.notifier).addItem(text);
    _controller.clear();
    setState(() => _draft = '');
  }

  @override
  Widget build(BuildContext context) {
    final preview = suggestIcon(_draft);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: preview == null
                  ? Icon(LucideIcons.circle, key: ValueKey('empty'), size: 24, color: AppColors.idleRing)
                  : IconTile(key: ValueKey(preview.key), iconKey: preview.key, size: 24, imageSize: 24, glyphSize: 15),
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
              onSubmitted: _add,
            ),
          ),
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: AppColors.surfaceAlt, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(LucideIcons.scanLine, size: 16, color: AppColors.inkSecondary),
          ),
        ],
      ),
    );
  }
}

/// Swiping a box row left reveals Bearbeiten and Löschen — the same gesture and
/// the same two actions as a list row and as the item rows inside a box, so
/// renaming a box doesn't mean opening it first and going through its menu.
///
/// The opaque [ColoredBox] is what keeps the actions from showing through the
/// sliding row: the row paints nothing, the [SectionCard] around it does.
Widget _swipeBoxRow(BuildContext context, WidgetRef ref, StorageBox box, int itemCount, Color accent) {
  return SwipeActionsRow(
    onTap: () => ref.read(boxProvider.notifier).open(box.id),
    actions: [
      SwipeAction(
        icon: LucideIcons.pencil,
        color: accent,
        onTap: () => openBoxSheet(context, ref, box: box),
      ),
      SwipeAction(
        icon: LucideIcons.trash2,
        color: AppColors.danger,
        // Nothing left to close once the row is gone.
        closesRow: false,
        onTap: () => ref.read(boxProvider.notifier).deleteBox(box.id),
      ),
    ],
    child: ColoredBox(color: AppColors.surface, child: _BoxRow(box: box, itemCount: itemCount, accent: accent)),
  );
}

/// One box on the overview card. Carries no tap target of its own — the row is
/// wrapped either by [_swipeBoxRow] or by a plain [GestureDetector], and a
/// second detector inside would swallow the tap that closes an open swipe.
class _BoxRow extends StatelessWidget {
  final StorageBox box;
  final int itemCount;
  final Color accent;

  const _BoxRow({required this.box, required this.itemCount, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 15),
      child: Row(
        children: [
          _BoxBadge(box: box, size: 44, iconSize: 20, accent: accent),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  box.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
                Text(
                  itemCount == 0 ? 'Leer · ${box.place}' : '$itemCount Artikel · ${box.place}',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, fontWeight: FontWeight.w300, color: AppColors.muted),
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

class _StatTile extends StatelessWidget {
  final String value;
  final IconData icon;
  final String label;
  final Color accent;

  const _StatTile({required this.value, required this.icon, required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.5, height: 1.1, color: AppColors.ink),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Icon(icon, size: 13, color: accent),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, fontWeight: FontWeight.w300, color: AppColors.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
