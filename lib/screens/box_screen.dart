import 'dart:io';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/icon_suggestions.dart';
import '../data/merchant_logos.dart';
import '../models/box_item.dart';
import '../state/auth_state.dart';
import '../state/box_state.dart';
import '../state/family_state.dart';
import '../services/media_picker.dart';
import '../state/sharing_state.dart';
import '../theme/tokens.dart';
import '../widgets/paywall_sheet.dart';
import '../widgets/anchored_menu.dart';
import '../widgets/app_sheet.dart';
import '../widgets/avatar.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/collapsing_header.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_note.dart';
import '../widgets/expandable_title.dart';
import '../widgets/glass.dart';
import '../widgets/brand_mark.dart';
import '../widgets/icon_picker.dart';
import '../widgets/overview_screen.dart';
import '../widgets/search.dart';
import '../widgets/share_sheet.dart';
import '../widgets/swipe_actions.dart';
import '../widgets/toast_chip.dart';
import '../widgets/visibility_picker.dart';
import '../models/entitlements.dart';
import '../l10n/l10n.dart';
import '../theme/app_icons.dart';

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
      body: state.isDetail
          ? _BoxDetail(state: state)
          : SafeArea(bottom: false, child: _BoxOverview(state: state)),
    );
  }
}

class _BoxOverview extends ConsumerWidget {
  final BoxScreenState state;

  const _BoxOverview({required this.state});

  /// First-frame estimate only — the two stat tiles plus the gap above them.
  /// [CollapsingHeaderScreen] re-measures the real thing once it's laid out.
  static const _extraHeight = 105.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = Theme.of(context).colorScheme.primary;
    return SearchableOverviewScreen(
      title: L.s.boxes,
      searchHint: L.s.searchBoxesAndItems,
      searchPrompt: L.s.searchBoxesAndItemsLong,
      // Gated on the way in, because a new box is a form somebody fills in:
      // refusing it at save would take that work away. Editing an existing box
      // is never gated — a household that drops to free must still be able to
      // tidy up what it already has.
      onAdd: () async {
        if (await requireAnother(context, ref, Feature.boxes, ref.read(boxProvider).boxes.length)) {
          if (context.mounted) openBoxSheet(context, ref);
        }
      },
      addLabel: L.s.newBox,
      extraHeight: _extraHeight,
      headerExtra: Row(
        children: [
          Expanded(
            child: _StatTile(
              value: '${state.boxes.length}',
              icon: AppIcons.package,
              label: L.s.boxes,
              accent: accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatTile(
              value: '${state.totalItems}',
              icon: AppIcons.clipboardText,
              label: L.s.items,
              accent: accent,
            ),
          ),
        ],
      ),
      body: (context) => _loadFailed
          ? [
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ErrorNote(message: state.error!, onRetry: () => ref.read(boxProvider.notifier).load()),
              ),
            ]
          : [
              // Not while the first load is still out — an account with twelve
              // boxes must not be told it has none. Bare, outside the card:
              // see [EmptyState].
              if (state.boxes.isEmpty && !state.loading)
                EmptyState(icon: AppIcons.package, iconColor: accent, message: L.s.noBoxesYet)
              else if (state.boxes.isNotEmpty)
                SectionCard(
                  children: dividedRows([
                    for (final box in state.boxes)
                      SwipeToEditDelete(
                        identity: box.id,
                        onTap: () => ref.read(boxProvider.notifier).open(box.id),
                        onEdit: () => openBoxSheet(context, ref, box: box),
                        onDelete: () async {
                          final confirm = confirmChipOf(context);
                          final notifier = ref.read(boxProvider.notifier);
                          if (await notifier.deleteBox(box.id) case final deleted?) {
                            confirm(L.s.boxDeleted, undo: () => notifier.restoreBox(deleted));
                          }
                        },
                        child: _BoxRow(box: box, itemCount: state.itemsFor(box.id).length),
                      ),
                  ]),
                ),
            ],
      results: (context, query, closeSearch) => _searchResults(context, ref, query, closeSearch),
    );
  }

  /// Nothing on screen and a message saying why — as opposed to a write that
  /// failed while the screen still has content, which gets a snack instead.
  bool get _loadFailed => state.error != null && !state.loading && state.boxes.isEmpty;

  /// Search covers what's *in* the boxes, not just their names — a box is only
  /// worth finding because of what you stored in it. Article hits are grouped
  /// under their box and open it, so a result is also the way there.
  Widget? _searchResults(BuildContext context, WidgetRef ref, String query, VoidCallback closeSearch) {
    final q = query.toLowerCase();

    void open(String id) {
      closeSearch();
      ref.read(boxProvider.notifier).open(id);
    }

    final matchedBoxes = state.boxes
        .where((b) => b.name.toLowerCase().contains(q) || b.place.toLowerCase().contains(q))
        .toList();
    final itemHits = <(StorageBox, List<BoxItem>)>[];
    for (final b in state.boxes) {
      final hits = state
          .itemsFor(b.id)
          .where(
            (i) =>
                i.name.toLowerCase().contains(q) ||
                i.meta.toLowerCase().contains(q) ||
                (i.note?.toLowerCase().contains(q) ?? false),
          )
          .toList();
      if (hits.isNotEmpty) itemHits.add((b, hits));
    }

    if (matchedBoxes.isEmpty && itemHits.isEmpty) return null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (matchedBoxes.isNotEmpty)
          SearchHitGroup(
            first: true,
            label: L.s.boxes,
            count: L.s.matchCount(matchedBoxes.length),
            rows: [
              for (final box in matchedBoxes)
                GestureDetector(
                  // Without this the row is only tappable where a glyph is
                  // actually painted — the padding and the gap before the
                  // chevron fall through.
                  behavior: HitTestBehavior.opaque,
                  onTap: () => open(box.id),
                  child: _BoxRow(box: box, itemCount: state.itemsFor(box.id).length),
                ),
            ],
          ),
        for (final (index, (box, hits)) in itemHits.indexed)
          SearchHitGroup(
            first: index == 0 && matchedBoxes.isEmpty,
            label: box.name,
            count: L.s.itemCount(hits.length),
            icon: _BoxBadge(box: box, size: 26, iconSize: 14),
            rows: [
              for (final hit in hits)
                SearchResultRow(
                  leading: IconTile(
                    iconKey: hit.iconKey,
                    photoUrl: state.photoUrl(hit.photoPath),
                    size: AppText.rowMark,
                    imageSize: AppText.markImage(AppText.rowMark),
                    glyphSize: AppText.markGlyph(AppText.rowMark),
                    fallbackIcon: AppIcons.clipboardText,
                  ),
                  title: hit.name,
                  subtitle: hit.meta.isEmpty ? '${box.name} · ${box.place}' : '${hit.meta} · ${box.place}',
                  onTap: () => open(box.id),
                ),
            ],
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
    title: box == null ? L.s.newBox : L.s.editBox,
    requiredField: nameController,
    heightFactor: 0.64,
    onSave: () async {
      final notifier = ref.read(boxProvider.notifier);
      // The sheet is already gone by the time the write comes back, so the chip
      // lands on the screen behind it, next to the row it is talking about.
      final confirm = confirmChipOf(context);
      if (box != null) {
        // Opened and closed with the check, nothing touched: no write, and no
        // "Box aktualisiert" for a change that never happened. The picture is
        // not part of this — an existing box keeps a new one the moment it is
        // picked, see [_BoxSheetBodyState._photoMenu].
        final current = ref.read(boxProvider);
        final typed = nameController.text.trim();
        final unchanged =
            (typed.isEmpty || typed == box.name) &&
            placeController.text.trim() == box.place.trim() &&
            draft.picked == null &&
            current.newVisibility == box.visibility &&
            setEquals(current.newSharedWith, box.sharedWith.toSet());
        if (unchanged) return;
        if (await notifier.updateBox(
          box.id,
          name: nameController.text,
          place: placeController.text,
          iconKey: draft.picked,
        )) {
          confirm(L.s.boxUpdated);
        }
        return;
      }
      if (await notifier.createBox(
        name: nameController.text,
        place: placeController.text,
        iconKey: draft.picked,
        // Held on the draft rather than uploaded on the tap: the object is
        // filed under the box's id, and a box that doesn't exist has none.
        photo: draft.photoFile == null ? null : File(draft.photoFile!),
      )) {
        confirm(L.s.boxCreated);
      }
    },
    child: _BoxSheetBody(
      nameController: nameController,
      placeController: placeController,
      draft: draft,
      box: box,
    ),
  );
}

class _BoxSheetBody extends ConsumerStatefulWidget {
  final TextEditingController nameController;
  final TextEditingController placeController;
  final IconDraft draft;

  /// The box being edited, or null when creating one — the sheet needs its
  /// stored icon and its old name to tell "not touched yet" from "renamed".
  final StorageBox? box;

  const _BoxSheetBody({
    required this.nameController,
    required this.placeController,
    required this.draft,
    this.box,
  });

  @override
  ConsumerState<_BoxSheetBody> createState() => _BoxSheetBodyState();
}

class _BoxSheetBodyState extends ConsumerState<_BoxSheetBody> {
  /// Where the fallback dropdown hangs when there is no system action sheet —
  /// see [showPictureMenu].
  final _pictureAnchor = GlobalKey();

  bool _uploading = false;

  /// The box being edited as the state currently holds it, or null while one is
  /// being created. [_BoxSheetBody.box] is a snapshot from the moment the sheet
  /// opened and goes stale the first time a picture is written.
  StorageBox? get _liveBox {
    final id = widget.box?.id;
    return id == null ? null : ref.read(boxProvider).boxById(id);
  }

  /// The symbol row's tap: straight into the picker, with nothing asked first.
  ///
  /// A photograph on the box is left exactly where it is. The two are separate
  /// rows now (see [IconFieldRow]) and separate columns underneath — the
  /// symbol is what the box goes back to when the picture is removed, so
  /// picking one is not a way of throwing the other away.
  Future<void> _pickSymbol(String? iconKey, String name) async {
    final picked = await showIconPicker(context, selected: iconKey, name: name, subject: IconSubject.box);
    if (picked == null || !mounted) return;
    setState(() => widget.draft.picked = picked);
  }

  /// The photo row's menu: one from the library, one taken now, or away with
  /// the one that is there.
  ///
  /// **Two different write moments, and the box is what decides which.** An
  /// existing box takes the picture straight away, exactly as the profile page
  /// does — the user has just watched it appear in the row and does not expect
  /// a Sichern to be what keeps it. A box being *created* has no id yet, and
  /// the storage layout keys on that id, so its picture waits on the draft
  /// until the insert comes back.
  Future<void> _photoMenu() async {
    // From the state, not from `widget.box` — that is the box as it was when
    // the sheet opened, and a picture taken a moment ago has already moved on
    // without it.
    final box = _liveBox;
    final hasPhoto = widget.draft.photoFile != null || box?.photoPath != null;
    final choice = await showPictureMenu(context, anchorKey: _pictureAnchor, hasPhoto: hasPhoto);
    if (choice == null || !mounted) return;

    switch (choice) {
      case PictureChoice.remove:
        setState(() => widget.draft.photoFile = null);
        if (box?.photoPath != null) await ref.read(boxProvider.notifier).removeBoxPhoto(box!.id);
      case PictureChoice.photo || PictureChoice.camera:
        // Before the system picker, not after it: asking somebody to choose a
        // photograph and then refusing to keep it is the worst possible moment
        // for a paywall. Removing one stays free — a household that drops to the
        // free plan must still be able to take its pictures back off.
        if (!await requireFeature(context, ref, Feature.photos)) return;
        final source = choice == PictureChoice.photo ? AttachmentSource.photos : AttachmentSource.camera;
        final picked = await pickAttachment(source, maxDimension: itemPhotoMaxDimension);
        if (picked == null || !picked.isImage || !mounted) return;
        if (box == null) {
          setState(() => widget.draft.photoFile = picked.path);
          return;
        }
        setState(() => _uploading = true);
        await ref.read(boxProvider.notifier).setBoxPhoto(box.id, File(picked.path));
        if (mounted) setState(() => _uploading = false);
    }
  }

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
                textInputAction: TextInputAction.next,
                style: AppText.inputTitle,
                decoration: InputDecoration(border: InputBorder.none, hintText: L.s.boxName, isDense: true),
                onChanged: (_) => setState(() {}),
              ),
            ),
            CardDivider(),
            IconFieldRow(
              iconKey: iconKey,
              // The sparkle means "the name chose this" — not true of the icon
              // an edit sheet opens on.
              suggested: widget.draft.picked == null && stored == null,
              fallbackIcon: AppIcons.package,
              onTap: () => _pickSymbol(iconKey, name),
            ),
            CardDivider(),
            PhotoFieldRow(
              photoUrl: s.photoUrl(s.boxById(widget.box?.id ?? '')?.photoPath),
              photoFile: widget.draft.photoFile,
              anchorKey: _pictureAnchor,
              uploading: _uploading,
              onTap: _photoMenu,
            ),
            CardDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  Text(L.s.place, style: AppText.rowTitle),
                  const SizedBox(width: 11),
                  Expanded(
                    child: TextField(
                      controller: widget.placeController,
                      textInputAction: TextInputAction.done,
                      textAlign: TextAlign.right,
                      style: AppText.input,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: L.s.placeExample,
                        isDense: true,
                      ),
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
          noun: L.s.theBox,
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
        title: L.s.boxLabel,
        collapsedTitle: box.name,
        collapsedIcon: _BoxBadge(box: box, size: 24, iconSize: 13),
        t: t,
        expandedAlignment: Alignment.center,
        expandedFontSize: AppText.pageTitle,
        fontWeight: FontWeight.w500,
        leadingWidth: 48,
        trailingWidth: 48,
        leading: GlassIconButton(
          icon: AppIcons.caretLeft,
          onTap: () => ref.read(boxProvider.notifier).back(),
        ),
        trailing: GlassMenuButton(
          items: [
            AnchoredMenuItem(
              label: L.s.edit,
              icon: AppIcons.pencilSimple,
              symbol: 'pencil',
              onSelected: () => openBoxSheet(context, ref, box: box),
            ),
            if (ref.watch(canShareExternallyProvider) && !state.guestBoxIds.contains(box.id))
              AnchoredMenuItem(
                label: L.s.share,
                icon: AppIcons.userPlus,
                symbol: 'person.badge.plus',
                onSelected: () => showShareSheet(
                  context,
                  kind: ShareableKind.box,
                  resourceId: box.id,
                  resourceName: box.name,
                ),
              ),
            AnchoredMenuItem(
              label: L.s.delete,
              icon: AppIcons.trash,
              symbol: 'trash',
              destructive: true,
              onSelected: () async {
                // Captured before the write: this menu lives in the detail
                // view, which the delete itself unmounts.
                final confirm = confirmChipOf(context);
                final notifier = ref.read(boxProvider.notifier);
                if (await notifier.deleteBox(box.id) case final deleted?) {
                  confirm(L.s.boxDeleted, undo: () => notifier.restoreBox(deleted));
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
              _BoxBadge(box: box, size: AppText.rowMark, iconSize: AppText.markGlyph(AppText.rowMark)),
              const SizedBox(width: 13),
              // Unfolds when the name is longer than the line, exactly as a
              // list's does — see [ExpandableTitle].
              Expanded(child: ExpandableTitle(text: box.name)),
            ],
          ),
        ],
      ),
      body: ScreenBodyPanel(
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 18, 16, navContentInset(context, pill: 140)),
          children: [
            SectionCard(
              children: dividedRows([_AddItemRow(), for (final item in items) _ItemRow(item: item)]),
            ),
            // Under the card that holds the add row rather than inside it, the
            // way a list's own empty state sits — the card is the field you
            // type in, not a container for the sentence saying it is empty.
            if (items.isEmpty)
              EmptyState(icon: AppIcons.clipboardText, message: L.s.tapAboveToAddFirst, verticalPadding: 48),
          ],
        ),
      ),
    );
  }
}

/// The box's round icon badge — full size next to the name, small alongside the
/// collapsed title in the header bar, and the mark at the head of its row on the
/// overview. Draws whatever the box's name produced (or was overridden to),
/// falling back to the plain carton.
///
/// All three are the same thing — *this box, named* — so all three wear the
/// disc, which is what [IconTile.disc] is for.
class _BoxBadge extends ConsumerWidget {
  final StorageBox box;
  final double size;
  final double iconSize;

  const _BoxBadge({required this.box, required this.size, required this.iconSize});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconTile(
      iconKey: box.iconKey,
      // A photograph of the crate itself wins over the symbol its name chose —
      // a shelf of cartons is told apart by what they look like, not by which
      // of them the word "Keller" picked a warehouse glyph for.
      photoUrl: ref.watch(boxProvider.select((s) => s.photoUrl(box.photoPath))),
      size: size,
      imageSize: iconSize * 1.5,
      glyphSize: iconSize,
      fallbackIcon: AppIcons.package,
      // The badge is the box's own name wherever it is drawn — the row on the
      // overview, the header of the open box, the collapsed title above it —
      // and that is the place [IconTile.disc] marks. The items inside the box
      // are the column that stays bare; see [_ItemIcon].
      disc: true,
    );
  }
}

/// Takes an item off its box and offers it straight back.
///
/// No confirmation dialog in front of it, exactly as with a whole box: the chip
/// *is* the confirmation, and it can put the item back — photograph and all,
/// see [BoxNotifier.restoreItem]. Captured before the write, because the row it
/// was tapped in is gone by the time the write returns.
Future<void> _deleteItem(BuildContext context, WidgetRef ref, BoxItem item) async {
  final confirm = confirmChipOf(context);
  final notifier = ref.read(boxProvider.notifier);
  if (await notifier.removeItem(item) case final deleted?) {
    confirm(L.s.itemDeleted, undo: () => notifier.restoreItem(deleted));
  }
}

/// The picture in front of one item inside a box.
///
/// Deliberately *not* an [IconTile]: the box's own badge at the top of the
/// screen is a glyph on a filled disc, and repeating that treatment down every
/// row made a shelf of things read as a shelf of boxes. A row's symbol is the
/// plain mark in the theme's ink inside an empty hairline ring — the ring holds
/// the column and keeps the row looking built, the missing fill is what stops it
/// competing with the badge above.
///
/// Two things still keep a disc, for the reason [IconTile] has one at all. A
/// photograph has to be cropped to some shape, and full-colour art (a grocery
/// picture, a shop logo) is drawn for a light background, so on dark it needs
/// the white one under it or it goes unreadable.
class _ItemIcon extends StatelessWidget {
  final String? iconKey;
  final String? photoUrl;

  static double get _slot => AppText.rowMark;

  const _ItemIcon({required this.iconKey, this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final asset = resolveIcon(iconKey)?.asset;
    // A shop is framed by [BrandMark] here as it is everywhere else: the ring
    // this row draws is for a symbol, and a logo left inside it was a square in
    // a circle.
    if (photoUrl == null && isMerchantAsset(asset)) {
      return BrandMark(size: _slot, asset: asset);
    }
    if (photoUrl != null || (asset != null && AppColors.isDark)) {
      return IconTile(
        iconKey: iconKey,
        photoUrl: photoUrl,
        size: _slot,
        imageSize: AppText.markImage(_slot),
        glyphSize: AppText.markGlyph(_slot),
        fallbackIcon: AppIcons.clipboardText,
      );
    }
    return Container(
      width: _slot,
      height: _slot,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.hairline),
      ),
      alignment: Alignment.center,
      child: asset != null
          ? IconImage(asset: asset, size: 28)
          : AppIcon(
              resolveIcon(iconKey)?.glyph ?? AppIcons.clipboardText,
              size: 22,
              color: AppColors.inkSecondary,
            ),
    );
  }
}

class _ItemRow extends ConsumerWidget {
  final BoxItem item;

  const _ItemRow({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Swiping the row left reveals Delete, the same gesture the Kalender event
    // cards and the Listen article rows use.
    return SwipeToEditDelete(
      identity: item.id,
      onTap: () => _openItemSheet(context, ref, item: item),
      onDelete: () => _deleteItem(context, ref, item),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 15),
        child: Row(
          children: [
            _ItemIcon(
              iconKey: item.iconKey,
              // The whole point of the feature: a symbol says "Werkzeug", a
              // photograph says *which* drill.
              photoUrl: ref.watch(boxProvider.select((s) => s.photoUrl(item.photoPath))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.itemTitle),
                  if (item.meta.isNotEmpty)
                    Text(item.meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label),
                ],
              ),
            ),
            RowMenuButton(
              items: [
                AnchoredMenuItem(
                  label: L.s.edit,
                  icon: AppIcons.pencilSimple,
                  symbol: 'pencil',
                  onSelected: () => _openItemSheet(context, ref, item: item),
                ),
                AnchoredMenuItem(
                  label: L.s.delete,
                  icon: AppIcons.trash,
                  symbol: 'trash',
                  destructive: true,
                  onSelected: () => _deleteItem(context, ref, item),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The item sheet — the same sheet for a new item and for one being edited,
/// [item] being what tells them apart.
///
/// **Creating goes through here too, rather than through the row at the bottom
/// of the box.** That row used to take the name inline and file the item on
/// submit, opening this sheet a keystroke later on the row that came back. It
/// worked, but it asked the user to finish one field before being shown the
/// four that make an item an item — a Größe, an Anzahl, a Notiz and above all a
/// picture of the thing — and it wrote a row to the database for a Bohrmaschine
/// somebody was still thinking about. Now the row is a button, the sheet opens
/// empty, and nothing is written until Sichern.
void _openItemSheet(BuildContext context, WidgetRef ref, {BoxItem? item}) {
  final form = _ItemForm(item);
  showAppSheet(
    context: context,
    title: item == null ? L.s.newItem : L.s.editItem,
    // Creating: there is no item to leave alone, so the name is what the save
    // button waits for.
    requiredField: item == null ? form.name : null,
    requiredFocus: form.nameFocus,
    onSave: () async {
      final notifier = ref.read(boxProvider.notifier);
      if (item != null) {
        // An emptied *name* means "left it alone", not "call this item ''" —
        // whereas an emptied Größe or Notiz does mean "drop it", since both are
        // optional to begin with.
        return notifier.editItem(
          item,
          name: form.name.text,
          size: form.size.text,
          qty: form.qty,
          note: form.note.text,
          iconKey: form.draft.picked,
        );
      }
      // The sheet is already gone by the time the insert comes back, so the
      // chip lands on the box behind it — same as the box sheet's own.
      final confirm = confirmChipOf(context);
      final saved = await notifier.addItem(
        form.name.text,
        iconKey: form.draft.picked,
        size: form.size.text,
        qty: form.qty,
        note: form.note.text,
        // Held on the draft rather than uploaded on the tap: `photo_path`
        // belongs to a row that does not exist yet.
        photo: form.draft.photoFile == null ? null : File(form.draft.photoFile!),
      );
      if (saved != null) confirm(L.s.itemCreated);
    },
    child: _ItemSheetBody(item: item, form: form),
  );
}

/// The item being edited, held by reference — the sheet's save button belongs to
/// the shared chrome and is handed its callback before the body exists, the same
/// arrangement `IconDraft` and the Kalender event form use.
class _ItemForm {
  _ItemForm(BoxItem? item)
    : name = TextEditingController(text: item?.name ?? ''),
      size = TextEditingController(text: item?.size ?? ''),
      note = TextEditingController(text: item?.note ?? ''),
      draft = IconDraft(item?.iconKey),
      qty = item?.qty ?? 1;

  final TextEditingController name;
  final TextEditingController size;
  final TextEditingController note;
  final IconDraft draft;

  /// So the greyed save button can put the cursor where the missing name goes —
  /// see [showAppSheet]'s `requiredFocus`.
  final nameFocus = FocusNode();

  /// Stepped rather than typed: a quantity is a small number, and a keyboard for
  /// it costs more taps than the two buttons do.
  int qty;

  void dispose() {
    name.dispose();
    size.dispose();
    note.dispose();
    nameFocus.dispose();
  }
}

class _ItemSheetBody extends ConsumerStatefulWidget {
  /// Null while an item is being created — there is no row to write a picture
  /// to and nothing to delete.
  final BoxItem? item;

  final _ItemForm form;

  const _ItemSheetBody({required this.item, required this.form});

  @override
  ConsumerState<_ItemSheetBody> createState() => _ItemSheetBodyState();
}

class _ItemSheetBodyState extends ConsumerState<_ItemSheetBody> {
  final _pictureAnchor = GlobalKey();

  bool _uploading = false;

  @override
  void dispose() {
    widget.form.dispose();
    super.dispose();
  }

  /// The item as [state] holds it — [_ItemSheetBody.item] is the row as it was
  /// when the sheet opened, and a photograph taken a moment ago has already
  /// moved on without it.
  ///
  /// Takes the state rather than reading the provider so it can be used inside
  /// a `select`, which is where the sheet needs it: the picture row has to
  /// rebuild when the upload lands.
  BoxItem? _itemIn(BoxScreenState state) {
    final item = widget.item;
    if (item == null) return null;
    for (final i in state.itemsFor(item.boxId)) {
      if (i.id == item.id) return i;
    }
    return item;
  }

  /// The symbol row's tap — the picker, and nothing asked first. The item's
  /// photograph is untouched: see [_BoxSheetBodyState._pickSymbol].
  Future<void> _pickSymbol(String? iconKey, String name) async {
    final picked = await showIconPicker(context, selected: iconKey, name: name);
    if (picked == null || !mounted) return;
    setState(() => widget.form.draft.picked = picked);
  }

  /// The photo row's menu, with the same two write moments the box sheet has
  /// and for the same reason: an item that already exists takes the photograph
  /// straight away — the user has watched it appear and does not expect a
  /// Sichern to be what keeps it — while one being created has no row for
  /// `photo_path` to sit in, so its picture waits on the draft until the insert
  /// comes back.
  Future<void> _photoMenu() async {
    final item = _itemIn(ref.read(boxProvider));
    final notifier = ref.read(boxProvider.notifier);
    final hasPhoto = widget.form.draft.photoFile != null || item?.photoPath != null;
    final choice = await showPictureMenu(context, anchorKey: _pictureAnchor, hasPhoto: hasPhoto);
    if (choice == null || !mounted) return;

    switch (choice) {
      case PictureChoice.remove:
        setState(() => widget.form.draft.photoFile = null);
        if (item?.photoPath != null) await notifier.removeItemPhoto(item!);
      case PictureChoice.photo || PictureChoice.camera:
        // Before the system picker, not after it: asking somebody to choose a
        // photograph and then refusing to keep it is the worst possible moment
        // for a paywall. Removing one stays free — a household that drops to the
        // free plan must still be able to take its pictures back off.
        if (!await requireFeature(context, ref, Feature.photos)) return;
        final source = choice == PictureChoice.photo ? AttachmentSource.photos : AttachmentSource.camera;
        final picked = await pickAttachment(source, maxDimension: itemPhotoMaxDimension);
        if (picked == null || !picked.isImage || !mounted) return;
        if (item == null) {
          setState(() => widget.form.draft.photoFile = picked.path);
          return;
        }
        setState(() => _uploading = true);
        await notifier.setItemPhoto(item, File(picked.path));
        if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final nameController = widget.form.name;
    final name = nameController.text;
    final iconKey = widget.form.draft.picked ?? suggestIcon(name)?.key ?? item?.iconKey;
    final photoUrl = ref.watch(boxProvider.select((s) => s.photoUrl(_itemIn(s)?.photoPath)));
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
                      focusNode: widget.form.nameFocus,
                      // A new item opens on the keyboard: the name is the first
                      // thing to fill in and everything else on the sheet is
                      // optional. An edit sheet keeps it down — it is opened to
                      // change the picture or the Anzahl far more often than
                      // the name. Same rule as the list sheet.
                      autofocus: item == null,
                      textInputAction: TextInputAction.next,
                      style: AppText.inputTitle,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: L.s.itemName,
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: AppColors.surfaceAlt, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: AppIcon(AppIcons.scan, size: 16, color: AppColors.inkSecondary),
                  ),
                ],
              ),
            ),
            CardDivider(),
            IconFieldRow(
              iconKey: iconKey,
              suggested: widget.form.draft.picked == null,
              fallbackIcon: AppIcons.clipboardText,
              onTap: () => _pickSymbol(iconKey, name),
            ),
            CardDivider(),
            PhotoFieldRow(
              photoUrl: photoUrl,
              photoFile: widget.form.draft.photoFile,
              anchorKey: _pictureAnchor,
              uploading: _uploading,
              onTap: _photoMenu,
            ),
            CardDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  Text(L.s.size, style: AppText.rowTitle),
                  const SizedBox(width: 11),
                  Expanded(
                    child: TextField(
                      controller: widget.form.size,
                      // Not `next`: the row after this one is the multi-line
                      // note, and a return key that jumps into a field whose
                      // own return key inserts a newline reads as a dead end.
                      textInputAction: TextInputAction.done,
                      textAlign: TextAlign.right,
                      style: AppText.input,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: L.s.sizeExample,
                        isDense: true,
                      ),
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
                  Expanded(child: Text(L.s.quantity, style: AppText.rowTitle)),
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
                style: AppText.input,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: L.s.itemNotePlaceholder,
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        if (item != null) ...[
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () async {
              // Taken before the pop, like the Board sheet's own delete row: the
              // sheet is on its way out, and the chip has to outlive it.
              final confirm = confirmChipOf(context);
              final notifier = ref.read(boxProvider.notifier);
              Navigator.of(context).pop();
              if (await notifier.removeItem(item) case final deleted?) {
                confirm(L.s.itemDeleted, undo: () => notifier.restoreItem(deleted));
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: AppShadows.card,
              ),
              alignment: Alignment.center,
              child: Text(L.s.deleteItem, style: AppText.rowTitle.copyWith(color: AppColors.danger)),
            ),
          ),
        ],
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
        _QtyButton(
          icon: AppIcons.minus,
          accent: accent,
          enabled: value > 1,
          onTap: () => onChanged(value - 1),
        ),
        SizedBox(
          width: 38,
          child: Text('$value', textAlign: TextAlign.center, style: AppText.itemTitle),
        ),
        _QtyButton(icon: AppIcons.plus, accent: accent, enabled: true, onTap: () => onChanged(value + 1)),
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
        child: AppIcon(icon, size: 15, color: enabled ? accent : AppColors.mutedLight),
      ),
    );
  }
}

/// The "Artikel hinzufügen" line of a box — a button, not a field.
///
/// **Nothing is typed here.** It used to take the name inline and file the item
/// on submit, opening its sheet a keystroke later; the difference from the
/// Listen row is that "Milch" on its own is a whole article, whereas an item in
/// a box is a Größe, an Anzahl, a Notiz and above all a picture of the thing.
/// Asking for one field and then showing the other four read as two steps for
/// one action, and it wrote a row for a Bohrmaschine somebody was still
/// thinking about. The tap now opens the sheet with everything on it at once,
/// and the insert happens on Sichern — see [_openItemSheet].
///
/// The circle stays empty, and stays a circle. It previewed the matched picture
/// once, which put a photograph of a drill inside what reads as a checkbox.
class _AddItemRow extends ConsumerWidget {
  const _AddItemRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      // Without this the row is only tappable where a glyph is actually
      // painted — the words and the gaps around them fall through.
      behavior: HitTestBehavior.opaque,
      onTap: () => _openItemSheet(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        child: Row(
          children: [
            AppIcon(AppIcons.circle, size: 24, color: AppColors.idleRing),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                L.s.addItemPlaceholder,
                style: AppText.inputTitle.copyWith(color: AppColors.mutedLight),
              ),
            ),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: AppColors.surfaceAlt, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: AppIcon(AppIcons.scan, size: 16, color: AppColors.inkSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// One box on the overview card. Carries no tap target of its own — the row is
/// wrapped either by a [SwipeToEditDelete] or by a plain [GestureDetector], and
/// a second detector inside would swallow the tap that closes an open swipe.
class _BoxRow extends ConsumerWidget {
  final StorageBox box;
  final int itemCount;

  const _BoxRow({required this.box, required this.itemCount});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 15),
      child: Row(
        children: [
          _BoxBadge(box: box, size: AppText.rowMark, iconSize: AppText.markGlyph(AppText.rowMark)),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(box.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.itemTitle),
                Text(
                  itemCount == 0 ? L.s.emptyWithPlace(box.place) : L.s.itemsWithPlace(itemCount, box.place),
                  style: AppText.label,
                ),
              ],
            ),
          ),
          // Who may see this box, when that is not simply the household — the
          // padlock the "Für wen?" picker put there, or the faces it was shared
          // with. Draws nothing on a family box, which is most of them.
          VisibilityBadge(
            visibility: box.visibility,
            sharedWith: box.sharedWith,
            members: ref.watch(householdMembersProvider),
            padding: const EdgeInsets.only(right: 10),
          ),
          AppIcon(AppIcons.caretRight, size: 16, color: AppColors.mutedLight),
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
          Text(value, style: AppText.statValue),
          const SizedBox(height: 3),
          Row(
            children: [
              AppIcon(icon, size: 13, color: accent),
              const SizedBox(width: 5),
              Text(label, style: AppText.label),
            ],
          ),
        ],
      ),
    );
  }
}
