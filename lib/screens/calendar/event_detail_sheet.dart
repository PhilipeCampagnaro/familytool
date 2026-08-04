part of '../calendar_screen.dart';

// ---------------------------------------------------------------------------
// Event detail sheet
// ---------------------------------------------------------------------------

/// Builds the event-detail sheet's collapsing header: the title and the close
/// button share the first row, and the source/owner chips sit on a second row
/// underneath that fades and shrinks away as the sheet's body is scrolled
/// (same mechanism as the Kalender week view's own header — see
/// [CollapsingSliverHeaderDelegate]). The title always stays visible, morphing
/// from a large left-aligned heading down to a small centered one.
Widget _buildEventDetailHeader(BuildContext context, WidgetRef ref, double t) {
  final state = ref.watch(calendarProvider);
  final e = state.openEvent;
  if (e == null) return const SizedBox.shrink();
  final tone = AppTones.list[e.ownerTone];

  // Everything is laid out absolutely against the header's *expanded* geometry
  // and the Stack (hardEdge by default) clips whatever no longer fits as the
  // sliver shrinks. That's deliberately simpler than shrinking a Column child
  // with ClipRect + OverflowBox: the rows never move or re-lay-out, so the
  // title can't shift a pixel as the chips go away.
  return Stack(
    children: [
      // Frosted for the same reason as the week view's header (see
      // _WeekViewState._buildHeader): a sheet's NestedScrollView body isn't
      // clipped to below the pinned header, so the sheet's gray content slides
      // up underneath — blurred, rather than reading sharply through the title.
      Positioned.fill(child: FrostedHeaderBackground()),
      // Below the title row, and painted before it: the chips are the part that
      // collapses away, so putting them first in the Column used to push the
      // title down a line and strand the close button beside them.
      Positioned(
        top: _eventDetailTopPad + _eventDetailTitleRowHeight,
        left: 22,
        right: 22,
        height: _eventDetailChipsRowHeight,
        child: Opacity(
          opacity: (1 - t).clamp(0.0, 1.0),
          child: Padding(
            padding: const EdgeInsets.only(top: _eventDetailChipsGap),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(color: e.srcColor, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(e.source, style: AppText.microLabel.copyWith(color: AppColors.inkSecondary)),
                  ]),
                ),
                // An event has no owner until there is an account behind the
                // app; the chip is dropped rather than shown blank.
                if (e.owner.isNotEmpty) ...[
                  const SizedBox(width: 7),
                  Container(
                    padding: const EdgeInsets.fromLTRB(3, 3, 11, 3),
                    decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Avatar(size: 21, bg: tone.bg, fg: tone.fg, initials: e.ownerInitial, fontSize: 9),
                      const SizedBox(width: 6),
                      Text(e.owner, style: AppText.microLabel.copyWith(color: AppColors.inkSecondary)),
                    ]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      // Title layer: full width, not a Row sibling of the close button — as a
      // sibling its centered state landed half a button's width left of the
      // sheet's actual center.
      Positioned(
        top: _eventDetailTopPad,
        // Right stays reserved for the close button at every t; the left grows
        // in to match it, so collapsed reads symmetric (truly centered) while at
        // rest the title still starts flush left.
        left: 22 + 48 * t,
        right: 14 + 48,
        height: _eventDetailTitleRowHeight,
        child: Align(
          alignment: Alignment.lerp(Alignment.centerLeft, Alignment.center, t)!,
          child: Text(
            e.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.detailTitle.copyWith(fontSize: 23 - 6 * t),
          ),
        ),
      ),
      // Painted last so the glass — a native platform view on iOS, which
      // composites above whatever Flutter draws after it — sits over the frost
      // and the title rather than forcing them into an overlay layer.
      Positioned(
        top: _eventDetailTopPad,
        right: 14,
        height: _eventDetailTitleRowHeight,
        child: Center(
          child: GlassIconButton(
            icon: LucideIcons.x,
            onTap: () {
              ref.read(calendarProvider.notifier).closeEvent();
              Navigator.of(context).pop();
            },
          ),
        ),
      ),
    ],
  );
}

/// Height of the event-detail sheet's action row. The trash [GlassIconButton]
/// is square, so this is also its width — it's sized from the "Bearbeiten"
/// pill beside it, whose height is its 14pt padding top and bottom around a
/// ~22pt line of Poppins 15.
const _detailActionHeight = 50.0;

// The event-detail header's geometry, shared by its builder (which positions
// every row against these) and the sliver that sizes it.
const _eventDetailTopPad = 2.0;
const _eventDetailTitleRowHeight = 44.0;
const _eventDetailChipsGap = 8.0;
// Only just clears the chips themselves (8 above + a 27pt chip): the leftover
// is dead space between the chips and the gray body, and showAppSheet already
// adds its own 14pt margin above that body.
const _eventDetailChipsRowHeight = _eventDetailChipsGap + 28.0;
// What survives at t == 1: the band of frost the sheet's gray body passes under,
// so the sharp gray starts clear of the title and close button.
const _eventDetailCollapsedGap = 8.0;
const _eventDetailCollapsedHeight = _eventDetailTopPad + _eventDetailTitleRowHeight + _eventDetailCollapsedGap;
const _eventDetailExpandedHeight = _eventDetailCollapsedHeight + _eventDetailChipsRowHeight;

void _showEventDetailSheet(BuildContext context, WidgetRef ref) {
  showAppSheet(
    context: context,
    heightFactor: 0.88,
    collapsingHeader: SheetCollapsingHeader(
      expandedHeight: _eventDetailExpandedHeight,
      collapsedHeight: _eventDetailCollapsedHeight,
      builder: (context, t) => Consumer(
        builder: (context, ref, _) => _buildEventDetailHeader(context, ref, t),
      ),
    ),
    child: Consumer(
      builder: (context, ref, _) {
        final state = ref.watch(calendarProvider);
        final e = state.openEvent;
        final accent = Theme.of(context).colorScheme.primary;
        if (e == null) return const SizedBox.shrink();
        final weather = _weatherFor(ref, e);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IntrinsicHeight(
              child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.card),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Icon(LucideIcons.calendar, size: 15, color: AppColors.muted),
                                        SizedBox(width: 9),
                                        Text(L.s.eventLabel, style: AppText.microLabel.copyWith(letterSpacing: 0.3)),
                                      ]),
                                      const SizedBox(height: 9),
                                      Text(state.openEventDateLine, style: AppText.itemTitle),
                                      const SizedBox(height: 2),
                                      Text(e.timeRangeLabel, style: AppText.caption.copyWith(fontWeight: FontWeight.w300, color: AppColors.inkTertiary)),
                                    ],
                                  ),
                                ),
                              ),
                              // Same as the agenda row: no forecast, no card —
                              // and the date beside it then takes the full
                              // width rather than sitting next to an empty box.
                              if (weather != null) ...[
                                const SizedBox(width: 10),
                                Container(
                                  width: 126,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.card),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Icon(weather.icon, size: 28, color: accent),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 8),
                                          Text(weather.temperatureLabel, style: AppText.statValue),
                                          Text(weather.label, style: AppText.label.copyWith(color: AppColors.inkTertiary)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.card),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                                  child: Row(
                                    children: [
                                      Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(13)), alignment: Alignment.center, child: Icon(LucideIcons.mapPin, size: 18, color: accent)),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(e.loc, style: AppText.itemTitle),
                                            if (e.locSub.isNotEmpty) Text(e.locSub, style: AppText.label),
                                          ],
                                        ),
                                      ),
                                      Icon(LucideIcons.chevronRight, size: 17, color: AppColors.muted),
                                    ],
                                  ),
                                ),
                                if (!e.online)
                                  Container(
                                    height: 132,
                                    margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                                    decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(15)),
                                    child: Stack(
                                      children: [
                                        Align(
                                          alignment: Alignment.center,
                                          child: Container(
                                            width: 22,
                                            height: 22,
                                            decoration: BoxDecoration(color: accent, borderRadius: const BorderRadius.only(topLeft: Radius.circular(11), topRight: Radius.circular(11), bottomRight: Radius.circular(11))),
                                          ),
                                        ),
                                        Positioned(
                                          right: 10,
                                          bottom: 10,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.all(Radius.circular(13))),
                                            child: Text(L.s.route, style: AppText.microLabel.copyWith(color: accent)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.card),
                            child: Row(
                              children: [
                                Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(13)), alignment: Alignment.center, child: Icon(LucideIcons.bell, size: 18, color: accent)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(L.s.reminder, style: AppText.microLabel),
                                      Text(e.reminder, style: AppText.itemTitle),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.card),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(L.s.notes, style: AppText.microLabel),
                                const SizedBox(height: 6),
                                Text(e.body, style: AppText.body),
                              ],
                            ),
                          ),
                          // Wider than the 12pt rhythm between the detail
                          // cards above: these are the sheet's actions, not
                          // another card, so they need to read as a separate
                          // group rather than crowding the notes card.
                          const SizedBox(height: 22),
                          // Hidden for anything proxied from a connected account
                          // or a public feed: Aporah keeps no copy of those, so
                          // there is nothing here to edit or delete. The source
                          // app — or the Stadtreinigung — owns them.
                          if (state.sourceById(e.calendarId)?.editable ?? false)
                            Row(
                              children: [
                                Expanded(
                                  child: GlassAccentButton(
                                    label: L.s.edit,
                                    expand: true,
                                    onTap: () => _openEditEventSheet(context, ref, e),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // Same size as the pill beside it is tall, so the
                                // pair reads as one row of controls in the same
                                // material rather than a button and a card.
                                GlassIconButton(
                                  icon: LucideIcons.trash,
                                  size: _detailActionHeight,
                                  iconSize: 18,
                                  iconColor: AppColors.danger,
                                  onTap: () => _confirmDeleteEvent(context, ref, e, closeParentSheet: true),
                                ),
                              ],
                            ),
          ],
        );
      },
    ),
  );
}

/// [closeParentSheet] should only be `true` when called from within the
/// event detail sheet itself (closing it after delete) — the swipe-action
/// entry point on the agenda card calls this directly from the screen, with
/// no parent sheet route to pop.
void _confirmDeleteEvent(BuildContext context, WidgetRef ref, CalendarEvent event, {bool closeParentSheet = false}) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(L.s.deleteEventQuestion),
      content: Text(L.s.deleteEventBody(event.title)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(L.s.cancel),
        ),
        TextButton(
          onPressed: () async {
            // Before the pops: [context] is the sheet's own when the delete came
            // from inside it, and that route is about to go.
            final confirm = confirmChipOf(context);
            final notifier = ref.read(calendarProvider.notifier);
            final deleting = notifier.deleteEvent(event);
            Navigator.of(dialogContext).pop();
            if (closeParentSheet) Navigator.of(context).pop();
            if (await deleting) {
              confirm(L.s.eventDeleted, undo: () => notifier.restoreEvent(event));
            }
          },
          child: Text(L.s.delete, style: AppText.rowTitle.copyWith(color: AppColors.danger)),
        ),
      ],
    ),
  );
}
