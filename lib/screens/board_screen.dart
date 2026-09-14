import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/board_data.dart';
import '../models/event_link.dart';
import '../models/task.dart';
import '../models/tracker.dart';
import '../models/who.dart';
import '../state/auth_state.dart';
import '../state/board_state.dart';
import '../state/nav_state.dart';
import '../state/sharing_state.dart';
import '../state/family_state.dart';
import '../theme/tokens.dart';
import 'calendar_screen.dart';
import '../widgets/paywall_sheet.dart';
import '../widgets/app_sheet.dart';
import '../widgets/avatar.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/check_off.dart';
import '../widgets/collapsing_header.dart';
import '../widgets/floating_pill.dart';
import '../widgets/glass.dart';
import '../widgets/segmented_control.dart';
import '../widgets/share_sheet.dart';
import '../widgets/swipe_actions.dart';
import '../widgets/error_note.dart';
import '../widgets/event_link_chip.dart';
import '../widgets/visibility_picker.dart';
import '../widgets/toast_chip.dart';
import 'board/due_date_sheet.dart';
import 'board/schedule_sheet.dart';
import 'board/tracker_detail.dart';
import 'board/tracker_strip.dart';
import '../state/tracker_state.dart';
import '../models/entitlements.dart';
import '../l10n/l10n.dart';
import '../theme/app_icons.dart';

/// Opens Board's create-task sheet from outside Board.
///
/// The sheet itself is [BoardScreen._openTaskSheet] and stays private — this is
/// the one door into it, for the event detail sheet's "To-do zum Termin".
/// The text is not prefilled: a task hung off an appointment wants the
/// appointment's *date*, not its title. Prefilling the text with "Wochenende
/// Hamburg" would produce a task that says what the event beside it already
/// says; what the user is about to type is "Reisepass einpacken", and the
/// deadline is the part they'd otherwise have to set by hand.
///
/// [initialDue] is that deadline; [eventLink] is what makes the task point back
/// at the appointment afterwards, on both screens. They are separate on purpose
/// — the date is a day, the link is one specific event, and two tasks due the
/// same Thursday are exactly the case the link disambiguates.
///
/// Pass [task] to open an existing one instead of creating. That is what a to-do
/// tapped in the Kalender agenda does: the sheet stacks over the calendar rather
/// than switching tab, so closing it lands the reader back on the day they were
/// reading — the same rule [EventLinkChip] follows in the other direction.
void openTaskSheet(BuildContext context, WidgetRef ref, {BoardTask? task, DateTime? initialDue, EventLink? eventLink}) =>
    BoardScreen._openTaskSheet(context, ref, task: task, initialDue: initialDue, eventLink: eventLink);

/// Label colour of a checked-off task — the strike-through fades the open row's
/// text to it, so landing in "Erledigt" isn't a colour jump.
Color get _doneInk => AppColors.doneInk;

class BoardScreen extends ConsumerWidget {
  const BoardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(boardProvider);
    final notifier = ref.read(boardProvider.notifier);
    final accent = Theme.of(context).colorScheme.primary;

    // Arriving from a task card in an event's detail sheet. The task's own sheet
    // is what opens, rather than a highlight on a row somewhere down a scrolled
    // list — a task has no detail screen to land on, and "your task is in here
    // somewhere" is not an arrival.
    ref.listen<TabJump?>(tabJumpProvider, (_, jump) {
      if (jump?.taskId case final id?) {
        ref.read(tabJumpProvider.notifier).done();
        for (final task in ref.read(boardProvider).tasks) {
          if (task.id == id) {
            _openTaskSheet(context, ref, task: task);
            return;
          }
        }
      }
    });

    // A write that didn't land is reported once, transiently. A failed *load*
    // is not snacked: it leaves an empty screen behind, which needs an
    // explanation that stays put — the body renders an [ErrorNote] instead.
    ref.listen<String?>(boardProvider.select((s) => s.error), (_, message) {
      if (message == null) return;
      final current = ref.read(boardProvider);
      if (current.isEmpty && !current.loading) return;
      showErrorSnack(context, message);
      ref.read(boardProvider.notifier).clearError();
    });

    // Trackers get the same treatment, and unconditionally: there is no
    // [ErrorNote] for them to fall back on, because a household with no
    // trackers and a household whose trackers failed to load draw the same
    // empty grid. Without this a rejected save was simply nothing happening.
    ref.listen<String?>(trackerProvider.select((s) => s.error), (_, message) {
      if (message == null) return;
      showErrorSnack(context, message);
      ref.read(trackerProvider.notifier).clearError();
    });

    // One tracker's own screen, opened from its row on the card below. A mode
    // of this screen rather than a pushed route, the way Listen opens a list —
    // see [TrackerDetailView].
    if (ref.watch(trackerProvider.select((s) => s.openTracker)) case final open?) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: TrackerDetailView(
          tracker: open,
          accent: accent,
          onEdit: () => _openTaskSheet(context, ref, tracker: open),
        ),
      );
    }

    // The device clock, read on every build so the sections are still right
    // after the app has sat open past midnight.
    final today = boardDay(DateTime.now());
    final groups = state.groupsOn(today);
    final done = state.doneTasks;

    final sections = [
      for (final section in BoardSection.values)
        if (groups.any((g) => g.section == section)) section,
    ];
    List<BoardTask> tasksIn(BoardSection section) {
      for (final g in groups) {
        if (g.section == section) return g.tasks;
      }
      return const [];
    }

    // The header reports on today, not on the whole list: a board with eleven
    // tasks spread over three weeks has no meaningful single percentage.
    final onDeck = state.onDeck(today);
    final onDeckDone = [
      for (final t in onDeck)
        if (t.done) t,
    ].length;
    final progress = onDeck.isEmpty ? 0.0 : onDeckDone / onDeck.length;

    // The task the undo pill is offering to put back: the one that just moved,
    // and only while it is *done*. Undoing one moves it too, which flips this to
    // null and takes the pill away.
    final justChecked = _justCheckedOff(state, done);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: CollapsingHeaderScreen(
              titleRowBuilder: (context, t) => CollapsingScreenTitle(
                title: L.s.boardTitle,
                t: t,
                trailingWidth: 48,
                trailing: GlassIconButton(icon: AppIcons.plus, onTap: () => _openNewTaskSheet(context, ref)),
              ),
              estimatedExtraHeight: _extraHeight,
              // Today, and how much of it is behind you. This is what the week strip
              // used to occupy, and it is deliberately *not* a picker any more:
              // the date is a property of a task now, so there is no day to select.
              extra: _TodayHeader(
                today: today,
                progress: progress,
                done: onDeckDone,
                total: onDeck.length,
                accent: accent,
              ),
              body: ScreenBodyPanel(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(16, 20, 16, navContentInset(context)),
                  children: [
                    if (state.error != null && !state.loading && state.isEmpty) ...[
                      ErrorNote(message: state.error!, onRetry: () => notifier.load()),
                      const SizedBox(height: 16),
                    ],
                    // Above the dated sections, and never inside one. A
                    // tracker is not owed on a deadline, so it belongs to
                    // neither "Heute" nor "Überfällig" — putting it in the
                    // former would be close enough to look right and wrong
                    // every time one was missed.
                    _TrackerCard(today: today, accent: accent, personFilter: state.personFilter),
                    if (sections.isEmpty && !state.loading)
                      _EmptyBoard(onAdd: () => _openNewTaskSheet(context, ref))
                    else
                      for (final section in sections) ...[
                        _SectionHeading(
                          title: _sectionTitle(section),
                          overdue: section == BoardSection.overdue,
                          count: tasksIn(section).length,
                        ),
                        if (tasksIn(section).isNotEmpty)
                          SectionCard(
                            // [dividedRows] rather than a border on the row itself:
                            // the row used to sit under the day card's own header and
                            // drew its own top rule, which at the top of a card of its
                            // own would be a line against the card's edge.
                            children: dividedRows([
                              // The row plays the check-off animation first and only
                              // then tells the notifier, so it strikes through in place
                              // before moving to "Erledigt" — and an undone task slides
                              // back in here from below.
                              for (final task in tasksIn(section))
                                CheckOffArrival(
                                  key: ValueKey(task.id),
                                  animate: task.id == state.justMoved,
                                  fromBelow: true,
                                  child: CheckOffRow(
                                    onCompleted: () => notifier.toggle(task),
                                    // Same gesture as a Listen or Boxen row: swipe
                                    // left for Bearbeiten and Löschen. The row's own
                                    // tap opens the sheet from here rather than from
                                    // a detector inside [_TaskRow] — an inner one
                                    // would swallow the tap that closes an open
                                    // swipe.
                                    builder: (context, strike, checkOff) => SwipeToEditDelete(
                                      identity: task.id,
                                      onTap: () => _openTaskSheet(context, ref, task: task),
                                      onEdit: () => _openTaskSheet(context, ref, task: task),
                                      onDelete: () => _deleteTask(context, ref, task),
                                      child: _TaskRow(
                                        task: task,
                                        accent: accent,
                                        strike: strike,
                                        onCheckOff: checkOff,
                                        // Only where the heading doesn't already say
                                        // it. "Heute" above a row stamped "13. Aug"
                                        // is the same fact printed twice.
                                        showDate: _sectionSpansDays(section),
                                        overdue: section == BoardSection.overdue,
                                      ),
                                    ),
                                  ),
                                ),
                            ]),
                          ),
                        const SizedBox(height: 18),
                      ],
                    if (done.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      // The heading only pops into existence with the very first
                      // done task — let it arrive with that row instead.
                      CheckOffArrival(
                        animate: done.length == 1 && done.first.id == state.justMoved,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(L.s.doneCountSeparator(done.length), style: AppText.caption),
                              GestureDetector(
                                onTap: notifier.clearDone,
                                child: Text(L.s.delete, style: AppText.caption.copyWith(color: accent)),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SectionCard(
                        children: dividedRows([
                          for (final task in done)
                            CheckOffArrival(
                              key: ValueKey(task.id),
                              animate: task.id == state.justMoved,
                              // Undo runs the same animation backwards before the
                              // task travels back up into the day card.
                              child: CheckOffRow(
                                undo: true,
                                onCompleted: () => notifier.toggle(task),
                                // Delete only, like a Listen article row: the whole
                                // row already means "undo", and there is nothing
                                // worth editing about a task that is finished. It
                                // throws one away without clearing the lot.
                                builder: (context, strike, undo) => SwipeToEditDelete(
                                  identity: task.id,
                                  onTap: undo,
                                  onDelete: () => _deleteTask(context, ref, task),
                                  child: _DoneRow(task: task, accent: accent, strike: strike, onUndo: undo),
                                ),
                              ),
                            ),
                        ]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // "Rückgängig" for the row that just struck itself through, parked
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
                  if (justChecked != null) notifier.toggle(justChecked);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The task behind the undo pill: whatever `justMoved` points at, but only
  /// when it is sitting in "Erledigt". `justMoved` is also set by adding a task
  /// and by undoing one, and neither of those is an offer to undo anything.
  static BoardTask? _justCheckedOff(BoardState state, List<BoardTask> done) {
    if (state.justMoved.isEmpty) return null;
    for (final task in done) {
      if (task.id == state.justMoved) return task;
    }
    return null;
  }

  /// First-frame estimate of the collapsing block (the tracker's caption and
  /// grid + today's line + progress bar) — [CollapsingHeaderScreen] re-measures the real thing once
  /// it's laid out, which is the number that counts. See the collapsing-headers
  /// section of `docs/design-system.md`: this is frame one only, and a value
  /// tuned against a widget test's fallback font clips the real one.
  ///
  /// The person row is **not** in this sum. It only exists once a school
  /// account is connected, so a constant that included it would over-reserve on
  /// every other household's first frame; the re-measure catches it either way,
  /// and over-reserving is the more visible of the two mistakes.
  static const _extraHeight = 12 + BoardTrackerStrip.height + 16 + 24 + 12 + 7.0;

  static String _sectionTitle(BoardSection section) => switch (section) {
    BoardSection.overdue => L.s.sectionOverdue,
    BoardSection.today => L.s.sectionToday,
    BoardSection.tomorrow => L.s.sectionTomorrow,
    BoardSection.thisWeek => L.s.sectionThisWeek,
    BoardSection.later => L.s.sectionLater,
    BoardSection.undated => L.s.sectionUndated,
  };

  /// Whether a section's rows still need their own date printed on them. The
  /// three that name exactly one day answer the question in their heading;
  /// "Diese Woche" and "Später" cover a span, and "Ohne Datum" has no date to
  /// print in the first place.
  static bool _sectionSpansDays(BoardSection section) =>
      section == BoardSection.thisWeek || section == BoardSection.later || section == BoardSection.overdue;

  /// The create/edit sheet, for both kinds of row.
  ///
  /// [task] or [tracker] set means editing that one, and the type switch is then
  /// not offered: a task that turns out to be a rhythm is a new tracker and an
  /// old task, not one row changing species — the record a tracker keeps has
  /// nowhere to come from, and the "erledigt" a task carries has nowhere to go.
  /// With neither set the sheet is creating, and the segmented control at the
  /// top decides which.
  static void _openTaskSheet(
    BuildContext context,
    WidgetRef ref, {
    BoardTask? task,
    Tracker? tracker,
    DateTime? initialDue,
    EventLink? eventLink,
  }) {
    final text = TextEditingController(text: task?.text ?? tracker?.text ?? '');
    final notes = TextEditingController(text: task?.meta ?? tracker?.meta ?? '');
    // The name is what the save button waits for, so the sheet hands it the
    // cursor: a new task opens with nothing in the one field it cannot do
    // without, and the check is grey until there is. Held out here so the
    // chrome's greyed check can point back at it — see [showAppSheet].
    final textFocus = FocusNode();
    final editing = task != null || tracker != null;
    final notifier = ref.read(boardProvider.notifier);
    final trackerNotifier = ref.read(trackerProvider.notifier);
    // Held under its own name because the sheet body's `Consumer` shadows
    // `context` with the sheet's own — which is unmounted by the time a write
    // comes back. The confirmation belongs to the screen, so it needs this one.
    final screen = context;
    // Before the sheet is built, so it opens on this row's own answers rather
    // than on whatever the last sheet left behind.
    if (tracker != null) {
      notifier.primeTrackerDraft(tracker);
    } else {
      notifier.primeDraft(task, initialDue: initialDue);
    }
    trackerNotifier.primeDraft(tracker);
    showAppSheet(
      context: context,
      // Neutral while the sheet can still become either kind — see
      // [AppStrings.newEntry]. Opened from an appointment it cannot, so it says
      // what it is making.
      title: tracker != null
          ? L.s.editTracker
          : task != null
          ? L.s.editTask
          : eventLink != null
          ? L.s.newTask
          : L.s.newEntry,
      requiredField: text,
      requiredFocus: textFocus,
      onSave: () async {
        // The sheet is already gone by the time the write comes back (the
        // chrome pops it the moment save is tapped), so the chip lands on the
        // screen behind it — which is where it belongs.
        final confirm = confirmChipOf(screen);
        final draft = ref.read(boardProvider);

        if (tracker != null) {
          final saved = await trackerNotifier.updateTracker(
            tracker,
            text: text.text,
            meta: notes.text,
            assigneeId: draft.newAssigneeId,
            visibility: draft.newVisibility,
            sharedWith: draft.newSharedWith,
          );
          if (saved) confirm(L.s.trackerUpdated);
          return;
        }
        if (task != null) {
          if (await notifier.updateTask(task, text: text.text, meta: notes.text)) confirm(L.s.taskUpdated);
          return;
        }
        if (draft.newKind == BoardItemKind.tracker) {
          final saved = await trackerNotifier.addTracker(
            text.text,
            meta: notes.text.trim().isEmpty ? null : notes.text.trim(),
            assigneeId: draft.newAssigneeId,
            visibility: draft.newVisibility,
            sharedWith: draft.newSharedWith,
          );
          if (saved) confirm(L.s.trackerCreated);
          return;
        }
        if (await notifier.addTask(text.text, meta: notes.text, eventLink: eventLink)) {
          confirm(L.s.taskCreated);
        }
      },
      child: Consumer(
        builder: (context, ref, _) {
          final state = ref.watch(boardProvider);
          final members = ref.watch(householdMembersProvider);
          final me = ref.watch(currentUserIdProvider);
          final isTracker = tracker != null || (!editing && state.newKind == BoardItemKind.tracker);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Only while creating, and never from an appointment. The same
              // switch on an edit sheet would read as an offer to convert the
              // row, which is not on the table — and a **tracker started from an
              // appointment is a contradiction**: an appointment is one moment,
              // a tracker is a rhythm that owes no particular day and is never
              // overdue. `public.trackers` carries none of the three event-link
              // columns for that reason, so the choice could only ever have
              // saved a tracker with the link quietly dropped.
              if (!editing && eventLink == null) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 8),
                  child: Text(L.s.whatToCreate, style: AppText.microLabel),
                ),
                SegmentedControl<BoardItemKind>(
                  value: state.newKind,
                  // At the moment the choice is made, not at save. The sheet is
                  // shared with to-dos, so gating it on the way in would put a
                  // paywall in front of a free feature; gating it at save would
                  // take a filled-in form away. Picking the segment is the one
                  // moment that is only ever about a tracker.
                  onChanged: (kind) async {
                    if (kind == BoardItemKind.tracker &&
                        !await requireAnother(
                          screen,
                          ref,
                          Feature.trackers,
                          ref.read(trackerProvider).trackers.length,
                        )) {
                      return;
                    }
                    notifier.setKind(kind);
                  },
                  options: [
                    SegmentedOption(value: BoardItemKind.task, label: L.s.kindTask, icon: AppIcons.checkCircle),
                    SegmentedOption(value: BoardItemKind.tracker, label: L.s.kindTracker, icon: AppIcons.repeat),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              SectionCard(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                    child: TextField(
                      controller: text,
                      focusNode: textFocus,
                      // Only on a new one. An edit sheet opening with the
                      // keyboard up covers the rows the user came to change.
                      autofocus: !editing,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.next,
                      style: AppText.inputTitle,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: isTracker ? L.s.trackerPlaceholder : L.s.taskPlaceholder,
                        isDense: true,
                      ),
                    ),
                  ),
                  CardDivider(),
                  // Was a static row showing whatever day the week strip stood
                  // on — a chevron that did nothing, next to a date nobody could
                  // change. It asks the question properly now, and "—" is a real
                  // answer: a task does not have to be due on a day.
                  //
                  // The "Wiederholen · Nie" row that used to sit under it is
                  // still gone — `tasks` has no recurrence column, so it promised
                  // something nothing behind it could deliver.
                  // The one row that differs between the two kinds. A tracker has
                  // no deadline to miss — it has a rhythm — and offering both
                  // would be offering a contradiction.
                  if (isTracker)
                    _RhythmField(value: ref.watch(trackerProvider).newSchedule, onChanged: trackerNotifier.setSchedule)
                  else
                    _DueDateField(
                      value: state.newDueDate,
                      time: state.newDueTime,
                      onChanged: (day, time) => notifier.setDueDate(day, time: time),
                    ),
                  CardDivider(),
                  // "Wer macht das?" as a field row rather than a second avatar
                  // strip: stacked under "Für wen?" the two avatar pickers read
                  // as one question asked twice, which is exactly the confusion
                  // the split into `assignee_id` + `visibility` exists to undo.
                  _AssigneeField(
                    selected: state.newAssigneeId,
                    members: members,
                    currentUserId: me,
                    onSelect: notifier.setAssignee,
                  ),
                  // The appointment this task was made for, and the only place
                  // the way back to it is a button. On the Board card the same
                  // badge is a marker, because the row under it already opens
                  // this sheet — see [EventLinkChip]. Read-only otherwise: the
                  // link is set once, on create, and there is no unlink.
                  if (task?.eventLink case final link?) ...[
                    CardDivider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                      child: Row(
                        children: [
                          Text(L.s.linkedEventLabel, style: AppText.rowTitle),
                          const SizedBox(width: 12),
                          // Right-aligned against the card edge like every other
                          // value in this card, and flexible so a long
                          // appointment name ellipsises instead of pushing the
                          // label off the row.
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: EventLinkChip(
                                link: link,
                                // Stacked on this sheet rather than replacing
                                // it: closing the appointment lands back on the
                                // task, and closing that lands back on Board —
                                // see [showLinkedEventSheet].
                                onOpen: () => showLinkedEventSheet(context, ref, link),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              SectionCard(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(L.s.notes, style: AppText.microLabel),
                        const SizedBox(height: 6),
                        TextField(
                          controller: notes,
                          maxLines: null,
                          textCapitalization: TextCapitalization.sentences,
                          style: AppText.input,
                          decoration: InputDecoration(border: InputBorder.none, hintText: L.s.addNotes, isDense: true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // The audience question, in the same avatar picker Listen and Box
              // use. Who *does* the task is asked further up as a field row —
              // see [_AssigneeFieldRow] for why the shapes differ.
              VisibilityPicker(
                visibility: state.newVisibility,
                sharedWith: state.newSharedWith,
                onChanged: notifier.setVisibility,
                members: members,
                currentUserId: me,
                noun: isTracker ? L.s.theTracker : L.s.theTask,
                avatarSize: 52,
              ),
              // Only on an existing task: an external link needs a row to point
              // at, and a task that has not been saved yet has no id. Its own
              // action, never folded into "Für wen?" — see [showShareSheet].
              //
              // **A tracker is never offered it.** `public.shareable_kind` names
              // no value for one, and a link handing an outsider a page of the
              // household's habits has no reader worth the leak.
              if (task != null && ref.watch(canShareExternallyProvider)) ...[
                const SizedBox(height: 14),
                OutlinedSheetAction(
                  icon: AppIcons.userPlus,
                  label: L.s.share,
                  onTap: () =>
                      showShareSheet(context, kind: ShareableKind.task, resourceId: task.id, resourceName: task.text),
                ),
              ],
              if (task != null) ...[
                const SizedBox(height: 10),
                OutlinedSheetAction(
                  icon: AppIcons.trash,
                  label: L.s.deleteTask,
                  destructive: true,
                  onTap: () async {
                    final confirm = confirmChipOf(screen);
                    Navigator.of(context).pop();
                    if (await notifier.deleteTask(task)) {
                      confirm(L.s.taskDeleted, undo: () => notifier.restoreTask(task));
                    }
                  },
                ),
              ],
              if (tracker != null) ...[
                const SizedBox(height: 14),
                OutlinedSheetAction(
                  icon: AppIcons.trash,
                  label: L.s.deleteTracker,
                  destructive: true,
                  onTap: () async {
                    final confirm = confirmChipOf(screen);
                    Navigator.of(context).pop();
                    if (await trackerNotifier.deleteTracker(tracker)) {
                      confirm(L.s.trackerDeleted, undo: () => trackerNotifier.restoreTracker(tracker));
                    }
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  void _openNewTaskSheet(BuildContext context, WidgetRef ref) => _openTaskSheet(context, ref);

  /// Deletes a task from its row's swipe action, with the same undo chip the
  /// sheet's "To-do löschen" puts up. There is no confirmation dialog in front
  /// of it on purpose: the chip is the confirmation, and it can put the task
  /// back — see [BoardNotifier.restoreTask] for what survives the round trip.
  static Future<void> _deleteTask(BuildContext context, WidgetRef ref, BoardTask task) async {
    final confirm = confirmChipOf(context);
    final notifier = ref.read(boardProvider.notifier);
    if (await notifier.deleteTask(task)) {
      confirm(L.s.taskDeleted, undo: () => notifier.restoreTask(task));
    }
  }
}

/// Today, at the top of the Board, in the space the week strip used to take.
///
/// Not a picker: with the date living on the task there is no day to select, so
/// this reports rather than navigates. What it reports is deliberately narrow —
/// today plus anything still overdue — because a percentage over a list running
/// three weeks out is a number nobody can act on.
///
/// Three lines, and they run oldest to newest down the header: the months
/// behind today ([BoardTrackerStrip]), then the day itself with its count, then
/// today's own bar. The grid is at the top because it is the widest, least
/// urgent thing here — a backdrop for the two lines that report on today — and
/// the bar is at the bottom because it is the last thing before the task list it
/// measures.
class _TodayHeader extends ConsumerWidget {
  final DateTime today;
  final double progress;
  final int done;
  final int total;
  final Color accent;

  const _TodayHeader({
    required this.today,
    required this.progress,
    required this.done,
    required this.total,
    required this.accent,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The grid's source, and the change that dissolves the confusion this
    // feature came out of: it counts the household's *trackers*, not whichever
    // one-off tasks happened to fall on a day. A to-do is no longer a data
    // point in a habit chart.
    final trackers = ref.watch(trackerProvider);
    final days = trackers.dayTallies(today);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        // Faces first, above the tracker: it is the control, and the grid
        // behind it is a report. It appears only where there is more than one
        // person to choose between — see [_PersonFilterRow].
        _PersonFilterRow(),
        // Named rather than left to explain itself — it has no axis, no numbers
        // and nothing to tap. The caption is drawn inside the grid's first row
        // (see [BoardTrackerStrip]) rather than above it: a line of its own here
        // would be a second title under "Board", and would cost the header a
        // whole row to say one word.
        BoardTrackerStrip(
          days: days,
          today: today,
          // An empty grid on a Board with no trackers reads as lost data rather
          // than as a chart waiting for its first one, so it says so instead.
          hasTrackers: trackers.trackers.isNotEmpty,
          accent: accent,
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(boardLongDayName(today), overflow: TextOverflow.ellipsis, style: AppText.sectionHeading),
            ),
            const SizedBox(width: 10),
            Text(total == 0 ? L.s.nothingPlanned : L.s.doneOfTotal(done, total), style: AppText.label),
          ],
        ),
        const SizedBox(height: 12),
        _ProgressBar(progress: progress, accent: accent),
      ],
    );
  }
}

/// The day card's old two-`Expanded` bar, kept whole: an `AnimatedContainer` on
/// the filled half so ticking a task off slides the bar along instead of
/// snapping it.
class _ProgressBar extends StatelessWidget {
  final double progress;
  final Color accent;

  const _ProgressBar({required this.progress, required this.accent});

  @override
  Widget build(BuildContext context) {
    final filled = (progress * 1000).round().clamp(0, 1000);
    return Row(
      children: [
        Expanded(
          flex: filled,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            height: 7,
            decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(999)),
          ),
        ),
        const SizedBox(width: 3),
        if (progress < 1)
          Expanded(
            flex: (1000 - filled).clamp(0, 1000),
            child: Container(
              height: 7,
              decoration: BoxDecoration(color: tint(accent, .88), borderRadius: BorderRadius.circular(999)),
            ),
          ),
      ],
    );
  }
}

/// A section's heading: its name and how many are in it.
///
/// Each heading used to carry its own `+` that pre-filled that section's date.
/// Six of them down one screen read as six buttons rather than as six labels,
/// and the header's own `+` plus the "Fällig" row in the sheet already reach
/// every date — including the ones no section names.
class _SectionHeading extends StatelessWidget {
  final String title;
  final int count;

  /// The one heading that carries a colour — "Überfällig" is the only section
  /// whose contents are a problem rather than a plan. Never a tracker: a rhythm
  /// that slipped is not overdue, it is a gap.
  final bool overdue;

  const _SectionHeading({required this.title, required this.count, this.overdue = false});

  @override
  Widget build(BuildContext context) {
    final tone = overdue ? AppColors.danger : AppColors.muted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
      child: Row(
        children: [
          Text(title, style: AppText.groupHeading.copyWith(letterSpacing: 0, color: tone)),
          const SizedBox(width: 7),
          Text(
            '$count',
            style: AppText.caption.copyWith(fontWeight: FontWeight.w400, color: AppColors.mutedLight),
          ),
        ],
      ),
    );
  }
}

/// Today's rhythms, above the dated sections.
///
/// Renders nothing at all when the household keeps none, rather than an empty
/// card: the Board is a task list first, and a permanent empty shell for a
/// feature nobody has used would cost every screen a heading and a box.
///
/// **What a row does when it is ticked is the whole difference from a task.** It
/// stays exactly where it is, with its circle filled — a tracker's day is
/// recorded, not cleared away — where a task collapses out of its section and
/// travels to "Erledigt". So there is no [CheckOffRow] here: that widget's job
/// is the collapse, and a tracker never does it.
class _TrackerCard extends ConsumerWidget {
  final DateTime today;
  final Color accent;
  final String? personFilter;

  const _TrackerCard({required this.today, required this.accent, required this.personFilter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(trackerProvider);
    final due = state.dueOn(today, personFilter: personFilter);
    final rest = state.offToday(today, personFilter: personFilter);
    if (due.isEmpty && rest.isEmpty) return const SizedBox.shrink();

    // Nothing hides behind a chevron when there is nothing in front of it: on a
    // day none of the rhythms ask about, the rest of them *are* the card.
    final expanded = state.showAll || due.isEmpty;

    Widget row(Tracker tracker, {required bool dueToday}) => SwipeToEditDelete(
      identity: tracker.id,
      // The row opens the tracker's own screen; editing stays on the swipe,
      // where the Board's other rows keep it. Tapping used to open the edit
      // sheet, which answered a question nobody had — the thing you want after
      // ticking something off for a fortnight is to see the fortnight.
      onTap: () => ref.read(trackerProvider.notifier).open(tracker.id),
      onEdit: () => BoardScreen._openTaskSheet(context, ref, tracker: tracker),
      onDelete: () => _delete(context, ref, tracker),
      child: _TrackerRow(
        tracker: tracker,
        state: state,
        today: today,
        accent: accent,
        dueToday: dueToday,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Every tracker the household keeps, not just today's. The rows add up
        // to it either way — collapsed, the fold row says how many are missing.
        _SectionHeading(title: L.s.trackersTitle, count: due.length + rest.length),
        SectionCard(
          children: dividedRows([
            for (final tracker in due) row(tracker, dueToday: true),
            if (expanded)
              for (final tracker in rest) row(tracker, dueToday: false),
            if (rest.isNotEmpty && due.isNotEmpty)
              _MoreTrackersRow(
                count: rest.length,
                expanded: expanded,
                accent: accent,
                onTap: () => ref.read(trackerProvider.notifier).toggleShowAll(),
              ),
          ]),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  static Future<void> _delete(BuildContext context, WidgetRef ref, Tracker tracker) async {
    final confirm = confirmChipOf(context);
    final notifier = ref.read(trackerProvider.notifier);
    if (await notifier.deleteTracker(tracker)) {
      confirm(L.s.trackerDeleted, undo: () => notifier.restoreTracker(tracker));
    }
  }
}

/// One tracker on the Board's card.
///
/// The subtitle is the row's whole state, and it says a different thing for each
/// kind of rhythm — which is the point of having two. A day-based tracker prints
/// the days it runs on and, once there is one, the streak. A weekly one prints
/// how far into its week it is, because it is never due today and "Mo, Do" would
/// be a lie about days it does not care about.
class _TrackerRow extends ConsumerWidget {
  final Tracker tracker;
  final TrackerState state;
  final DateTime today;
  final Color accent;

  /// Whether today's rhythm asks for this one. False rows are the ones folded
  /// in under the card and carry **no check circle** — a Montag tracker cannot
  /// be kept on a Mittwoch, and a circle offering it would write a check that
  /// counts towards no streak and appears on no plan. They are here to be read
  /// and opened, not ticked.
  final bool dueToday;

  const _TrackerRow({
    required this.tracker,
    required this.state,
    required this.today,
    required this.accent,
    this.dueToday = true,
  });

  String _subtitle() {
    final streak = state.streakOf(tracker, today);
    if (!tracker.schedule.isDayBased) {
      final week = L.s.weekProgressLabel(state.weekDoneFor(tracker, today), tracker.schedule.target);
      return streak > 0 ? '$week · ${L.s.streakWeeks(streak)}' : week;
    }
    final rhythm = scheduleSummary(tracker.schedule);
    return streak > 0 ? '$rhythm · ${L.s.streakDays(streak)}' : rhythm;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checked = dueToday && state.isCheckedOn(tracker.id, today);
    final w = whoBadge(
      assigneeId: tracker.assigneeId,
      visibility: tracker.visibility,
      sharedWith: tracker.sharedWith,
      members: ref.watch(householdMembersProvider),
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tracker.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // A kept tracker greys the way a done task does, but keeps its
                  // text un-struck: the day is recorded, not crossed out.
                  style: AppText.itemTitle.copyWith(color: checked ? _doneInk : AppColors.ink),
                ),
                const SizedBox(height: 3),
                Text(_subtitle(), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Semantics(
                      label: w.label,
                      excludeSemantics: true,
                      child: WhoAvatars(who: w, size: 22, fontSize: 9.5),
                    ),
                    if (tracker.assigneeId != null)
                      VisibilityBadge(
                        visibility: tracker.visibility,
                        sharedWith: tracker.sharedWith,
                        members: ref.watch(householdMembersProvider),
                        padding: const EdgeInsets.only(left: 6),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (dueToday)
            CheckOffButton(
              progress: checked ? 1 : 0,
              accent: accent,
              // Ticking and un-ticking are the same tap, unlike a task's,
              // because the row does not go anywhere — a mis-tap at breakfast is
              // undone by tapping it again rather than by hunting for it in
              // "Erledigt".
              onTap: () => ref.read(trackerProvider.notifier).toggleCheck(tracker, today),
              size: 26,
              filled: true,
            ),
        ],
      ),
    );
  }
}

/// The fold at the bottom of the tracker card: everything today asks nothing
/// about, one tap away.
///
/// It counts them in its own label rather than saying "Alle anzeigen", so the
/// card admits there is something there before anybody taps it. A tracker has a
/// screen of its own now, and one that disappeared on its off days would be
/// unreachable five days a week — but putting all of them on the card by default
/// would push the day's actual tasks down the screen to make room for rhythms
/// nobody owes today.
class _MoreTrackersRow extends StatelessWidget {
  final int count;
  final bool expanded;
  final Color accent;
  final VoidCallback onTap;

  const _MoreTrackersRow({
    required this.count,
    required this.expanded,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
        child: Row(
          children: [
            Text(L.s.moreTrackers(count), style: AppText.label.copyWith(color: accent)),
            const Spacer(),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: AppIcon(AppIcons.caretDown, size: 16, color: accent),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nothing open at all — not "nothing on this day", which is what the day card
/// used to say and which a list spanning every day can no longer mean.
class _EmptyBoard extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyBoard({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
          child: Column(
            children: [
              Text(L.s.noOpenTasks, style: AppText.body.copyWith(color: AppColors.inkTertiary)),
              const SizedBox(height: 16),
              GlassAccentButton(label: L.s.addTask, onTap: onAdd),
            ],
          ),
        ),
      ],
    );
  }
}

class _TaskRow extends ConsumerWidget {
  final BoardTask task;
  final Color accent;

  /// 0 → 1 while the task is being checked off; drives the strike-through, the
  /// text greying out and the check filling in.
  final double strike;
  final VoidCallback onCheckOff;

  /// Whether to print the task's own date under it — true only in the sections
  /// that span more than one day (see [BoardScreen._sectionSpansDays]).
  final bool showDate;

  /// Colours that date as a problem rather than a plan.
  final bool overdue;

  const _TaskRow({
    required this.task,
    required this.accent,
    required this.strike,
    required this.onCheckOff,
    this.showDate = false,
    this.overdue = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = whoBadge(
      assigneeId: task.assigneeId,
      visibility: task.visibility,
      sharedWith: task.sharedWith,
      members: ref.watch(householdMembersProvider),
    );
    final due = task.dueDate;
    final time = task.dueTime;
    // Built once rather than three conditional widgets in the row: the day
    // alone, the hour alone, or both — and nothing at all on an undated to-do
    // under a heading that already names its day.
    final dayPart = showDate && due != null ? L.s.dayMonthShort(due.day, due.month) : null;
    final timePart = time == null ? null : formatTimeOfDay(time.hour, time.minute);
    final dueLabel = switch ((dayPart, timePart)) {
      (final day?, final at?) => '$day · $at',
      (final day?, null) => day,
      (null, final at?) => at,
      _ => null,
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StrikeThrough(
                  progress: strike,
                  color: _doneInk,
                  child: Text(
                    task.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.itemTitle.copyWith(color: Color.lerp(AppColors.ink, _doneInk, strike)),
                  ),
                ),
                // The note is the task's subtitle, on a line of its own under
                // the title it belongs to. It used to run on behind the avatar
                // and the date, where it competed for width with the two things
                // that must never be cut — and where a sentence about the task
                // read as part of a row about who owns it.
                if (task.meta case final note? when note.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Opacity(
                    opacity: 1 - 0.45 * strike,
                    child: Text(note, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.label),
                  ),
                ],
                const SizedBox(height: 6),
                Opacity(
                  opacity: 1 - 0.45 * strike,
                  child: Row(
                    children: [
                      // The face without its name: on a household of four or
                      // five the colour and initials *are* the name, and
                      // spelling it out again cost the row a line's worth of
                      // width for something already on screen. Bigger than it
                      // was, because a 16pt circle needed the label to be
                      // readable at all — it is now the whole answer to "whose
                      // is this?" and is sized like it.
                      //
                      // The label lives on in [Semantics]: an avatar is exactly
                      // the kind of meaning-in-colour that VoiceOver cannot see.
                      Semantics(
                        label: w.label,
                        excludeSemantics: true,
                        child: WhoAvatars(who: w, size: 22, fontSize: 9.5),
                      ),
                      // …and, next to it, who may *see* it. The face above is
                      // the assignee, so on an assigned task — which is every
                      // task, the sheet has no "Niemand" — the audience never
                      // reached the row at all: a private task looked exactly
                      // like a family one. The two are independent axes and the
                      // row now has room for both. Only drawn where it says
                      // something ([VisibilityBadge]), and skipped entirely with
                      // nobody assigned, where [whoBadge] has already put the
                      // padlock in the circle above.
                      if (task.assigneeId != null)
                        VisibilityBadge(
                          visibility: task.visibility,
                          sharedWith: task.sharedWith,
                          members: ref.watch(householdMembersProvider),
                          padding: const EdgeInsets.only(left: 6),
                        ),
                      // The day where the heading doesn't already say it, and
                      // the hour whenever there is one. The hour is *not*
                      // conditioned on [showDate]: under "Heute" the day is
                      // already known and "08:00" is the whole of what the row
                      // still has to say.
                      if (dueLabel != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          dueLabel,
                          style: AppText.label.copyWith(
                            color: overdue ? AppColors.danger : AppColors.muted,
                            fontWeight: overdue ? FontWeight.w500 : null,
                          ),
                        ),
                      ],
                      // The appointment this task was made for. Last in the row
                      // and flexible, so the faces and the date — which are on
                      // every task — keep their width and the name of the event
                      // is what gives way.
                      //
                      // A marker here, not a button: the row itself opens the
                      // task, and a second target this close inside it made
                      // "open the task" a coin toss between the task and
                      // Kalender. The way back to the appointment is in the
                      // task's own sheet — see [EventLinkChip].
                      if (task.eventLink case final link?) ...[
                        const SizedBox(width: 8),
                        Flexible(child: EventLinkChip(link: link)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          CheckOffButton(progress: strike, accent: accent, onTap: onCheckOff, size: 26, filled: true),
        ],
      ),
    );
  }
}

class _DoneRow extends ConsumerWidget {
  final BoardTask task;
  final Color accent;

  /// 1 at rest; runs back down to 0 as the task is undone, which unwinds the
  /// strike-through and empties the check again.
  final double strike;
  final VoidCallback onUndo;

  const _DoneRow({required this.task, required this.accent, required this.strike, required this.onUndo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = whoBadge(
      assigneeId: task.assigneeId,
      visibility: task.visibility,
      sharedWith: task.sharedWith,
      members: ref.watch(householdMembersProvider),
    );
    // A done row carries nothing else to tap, so the whole line undoes it —
    // handled by the [SwipeToEditDelete] around this row rather than by a
    // detector here, which would swallow the tap that closes an open swipe.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StrikeThrough(
                  progress: strike,
                  color: _doneInk,
                  child: Text(
                    task.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // Same token as the open row above: a task that changed
                    // weight the moment you checked it off read as a
                    // different task.
                    style: AppText.itemTitle.copyWith(color: Color.lerp(AppColors.ink, _doneInk, strike)),
                  ),
                ),
                const SizedBox(height: 6),
                // The same face the open row shows, not the name it used to
                // print here: a task must not change how it says who it belongs
                // to at the moment it is ticked off. Faded rather than greyed,
                // because an avatar's colour is what identifies it.
                Opacity(
                  opacity: 1 - 0.45 * strike,
                  child: Row(
                    children: [
                      Semantics(
                        label: w.label,
                        excludeSemantics: true,
                        child: WhoAvatars(who: w, size: 22, fontSize: 9.5),
                      ),
                      // A done task keeps saying who could see it, for the same
                      // reason it keeps the face: ticking something off is not
                      // the moment to change what a row tells you about it.
                      if (task.assigneeId != null)
                        VisibilityBadge(
                          visibility: task.visibility,
                          sharedWith: task.sharedWith,
                          members: ref.watch(householdMembersProvider),
                          padding: const EdgeInsets.only(left: 6),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          CheckOffButton(progress: strike, accent: accent, onTap: onUndo, size: 26, filled: true),
        ],
      ),
    );
  }
}

/// "Zuständig" — who is meant to *do* the task (`assignee_id`), as a collapsible
/// field in the sheet's first card: the answer on the row, the household roster
/// underneath once it's open.
///
/// Deliberately not the avatar strip [VisibilityPicker] uses. Sitting directly
/// above "Für wen?", a second permanently-open row of member avatars reads as
/// the same question asked twice — in a two-person household "Niemand / Ich"
/// and "Alle / Nur ich" are almost the same four chips. Collapsed, this is one
/// line carrying its own answer; open, it is unmistakably a different control.
///
/// There is no "Niemand": a task nobody is responsible for is a task nobody
/// does, so the sheet always names someone and starts on you. See
/// [BoardNotifier.primeDraft] for what an older row without an `assignee_id`
/// falls back to.
class _AssigneeField extends StatefulWidget {
  final String? selected;
  final List<FamilyMember> members;
  final String? currentUserId;
  final ValueChanged<String> onSelect;

  const _AssigneeField({
    required this.selected,
    required this.members,
    required this.currentUserId,
    required this.onSelect,
  });

  @override
  State<_AssigneeField> createState() => _AssigneeFieldState();
}

class _AssigneeFieldState extends State<_AssigneeField> {
  bool _open = false;

  /// "Ich" rather than your own name: you know who you are, and the roster reads
  /// better with one first-person entry than with your name among the others.
  String _labelFor(FamilyMember m) => m.id == widget.currentUserId ? L.s.me : m.name;

  FamilyMember? get _assignee {
    for (final m in widget.members) {
      if (m.id == widget.selected) return m;
    }
    return null;
  }

  void _pick(FamilyMember m) {
    widget.onSelect(m.id);
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final assignee = _assignee;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Expanded(child: Text(L.s.assigneeLabel, style: AppText.rowTitle)),
                // One tight flex child holding the whole answer, aligned to the
                // end — not three loose siblings. A bare `Flexible` around the
                // name competes with the label's `Expanded` for the free space,
                // takes half of it, then uses only the width the name needs; the
                // remainder lands after the chevron and floats the group into
                // the middle of the row. [_StaticFieldRow] avoids it by having
                // no flex child on this side at all, which is not an option
                // here — a long member name has to be able to ellipsise.
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // A member who has since left the household leaves an id
                      // behind that no longer resolves. Naming it "Unbekannt"
                      // beats both a blank row and quietly reassigning the task
                      // to the reader.
                      if (assignee != null) ...[
                        Avatar(
                          size: 24,
                          bg: assignee.toneColors.bg,
                          fg: assignee.toneColors.fg,
                          initials: assignee.initials,
                          fontSize: 10,
                          imageUrl: assignee.imageUrl,
                        ),
                        const SizedBox(width: 7),
                      ],
                      Flexible(
                        child: Text(
                          assignee == null ? L.s.unknown : _labelFor(assignee),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.input.copyWith(color: AppColors.inkTertiary),
                        ),
                      ),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: _open ? -0.25 : 0.25,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        child: AppIcon(AppIcons.caretRight, size: 16, color: AppColors.mutedLight),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // AnimatedCrossFade rather than `if (_open)`: it keeps both states
        // around so the card sizes *and* fades in both directions — see the
        // expand/collapse rule in docs/design-system.md.
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InsetDivider(),
              for (final m in widget.members)
                _AssigneeOption(
                  member: m,
                  label: _labelFor(m),
                  selected: m.id == widget.selected,
                  onTap: () => _pick(m),
                ),
              const SizedBox(height: 4),
            ],
          ),
          crossFadeState: _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
          sizeCurve: Curves.easeOutCubic,
          firstCurve: Curves.easeOut,
          secondCurve: Curves.easeIn,
          alignment: Alignment.topCenter,
        ),
      ],
    );
  }
}

/// One member in the open [_AssigneeField]: their real avatar and name, with a
/// check on the one currently carrying the task.
class _AssigneeOption extends StatelessWidget {
  final FamilyMember member;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AssigneeOption({required this.member, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
        child: Row(
          children: [
            Avatar(
              size: 30,
              bg: member.toneColors.bg,
              fg: member.toneColors.fg,
              initials: member.initials,
              fontSize: 12,
              imageUrl: member.imageUrl,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (selected ? AppText.itemTitle : AppText.input).copyWith(
                  color: selected ? AppColors.ink : AppColors.inkSecondary,
                ),
              ),
            ),
            if (selected) AppIcon(AppIcons.check, size: 17, color: accent),
          ],
        ),
      ),
    );
  }
}

/// "Fällig" in the task sheet.
///
/// This row was a `_StaticFieldRow` — a label, the day the week strip happened
/// to be on, and a chevron that did nothing. It was the only row in the app
/// wearing the affordance of a control without being one, and the date it showed
/// could not be changed from anywhere. Both are fixed here: it opens
/// [showDueDateSheet], and "—" is a legitimate answer rather than a missing one.
/// A tracker's rhythm row — where a task has "Fällig am".
///
/// Reads its answer back as a summary ("Jeden Tag", "Mo, Do", "4-mal pro
/// Woche") rather than as the kind alone, because the kind on its own does not
/// say what the tracker will do. No "—" state: every rhythm is a complete
/// answer, and a tracker without one is not a thing this sheet can produce.
class _RhythmField extends StatelessWidget {
  final TrackerSchedule value;
  final ValueChanged<TrackerSchedule> onChanged;

  const _RhythmField({required this.value, required this.onChanged});

  Future<void> _pick(BuildContext context) async {
    final picked = await showScheduleSheet(context, current: value);
    // Null means dismissed — the sheet's only other exit hands back a rhythm.
    if (picked == null) return;
    onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _pick(context),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Text(L.s.trackerRhythm, style: AppText.rowTitle),
            const SizedBox(width: 12),
            // The label takes its own width and the answer takes the rest,
            // right-aligned against the chevron — the same geometry as the
            // "Fällig" row it replaces. `Expanded` on *both* halves splits the
            // row down the middle instead, which left a short summary
            // ("Jeden Tag") stranded mid-row while every other field row in the
            // app ends its value at the edge.
            Expanded(
              child: Text(
                scheduleSummary(value),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.input.copyWith(color: AppColors.inkTertiary),
              ),
            ),
            const SizedBox(width: 4),
            AppIcon(AppIcons.caretRight, size: 16, color: AppColors.mutedLight),
          ],
        ),
      ),
    );
  }
}

class _DueDateField extends StatelessWidget {
  final DateTime? value;
  final DueTime? time;

  /// Both halves at once, because the sheet answers them together and the pair
  /// is what means something — see [BoardTask.dueTime].
  final void Function(DateTime? day, DueTime? time) onChanged;

  const _DueDateField({required this.value, required this.time, required this.onChanged});

  Future<void> _pick(BuildContext context) async {
    final choice = await showDueDateSheet(context, current: value, currentTime: time);
    // Null means the sheet was dismissed — a *choice* of no date arrives as
    // `DueDateChoice(null)`, which is why the wrapper exists.
    if (choice == null) return;
    onChanged(choice.day, choice.time);
  }

  @override
  Widget build(BuildContext context) {
    final due = value;
    return GestureDetector(
      onTap: () => _pick(context),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Text(L.s.dueLabel, style: AppText.rowTitle),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                // The hour rides on the same line rather than taking a row of
                // its own: "Donnerstag · 08:00" is one answer to one question,
                // and a second field row saying "Uhrzeit" would suggest a to-do
                // can have an hour without a day.
                due == null
                    ? L.s.dueNone
                    : (time == null
                        ? boardLongDayName(due)
                        : '${boardLongDayName(due)} · ${formatTimeOfDay(time!.hour, time!.minute)}'),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.input.copyWith(
                  // The dash is punctuation standing in for an answer, so it sits
                  // a shade back from a date that really is one.
                  color: due == null ? AppColors.mutedLight : AppColors.inkTertiary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            AppIcon(AppIcons.caretRight, size: 16, color: AppColors.mutedLight),
          ],
        ),
      ),
    );
  }
}

/// Board's filter row: one face per person who is actually holding something.
///
/// **The row is read off `assignee_id`, not off the household**, because
/// `assignee_id` is the only axis this filter narrows on — a member with no
/// to-do and no tracker to their name is a chip that can only ever empty the
/// screen, and a household full of them is a row of faces that means nothing.
/// It is deliberately *not* Kalender's chip row: over there a person owns
/// calendars whether or not anybody assigned them anything, so the two rows
/// answer different questions and only happen to look alike.
///
/// Both kinds of Board content count, and that is the point of doing it here
/// rather than over tasks alone: a parent who keeps a rhythm but was never
/// given a chore still gets a chip, and tapping it narrows the to-dos *and* the
/// trackers ([BoardState.visibleTasks], [TrackerState.visibleTrackers]).
/// Finished to-dos count too — filtering to somebody is also how you find what
/// they already did.
///
/// The person a filter is currently on keeps their chip even after their last
/// item is gone, or ticking off the final chore would take away the only way
/// back to "Alle".
///
/// Rendered only where there is more than one person to choose between, which
/// is the honest threshold: a single chip beside "Alle" narrows nothing, and a
/// row that cannot change the screen is one more thing to explain.
///
/// Scrolls horizontally. Four children plus two parents is six chips, and this
/// app is built for exactly that household.
class _PersonFilterRow extends ConsumerWidget {
  const _PersonFilterRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(boardProvider.select((s) => s.personFilter));
    final notifier = ref.read(boardProvider.notifier);
    final members = ref.watch(householdMembersProvider);

    // Who is carrying something on this Board — the to-dos and the rhythms
    // together, since the filter narrows both. Somebody who was assigned
    // nothing has nothing for their chip to show.
    final assigned = <String>{
      for (final t in ref.watch(boardProvider.select((s) => s.tasks)))
        if (t.assigneeId != null) t.assigneeId!,
      for (final t in ref.watch(trackerProvider.select((s) => s.trackers)))
        if (t.assigneeId != null) t.assigneeId!,
    };

    // In the household's own order, so the row does not reshuffle itself as
    // work is handed around.
    final people = <({String id, String name})>[
      for (final m in members)
        if (assigned.contains(m.id) || selected == 'member:${m.id}') (id: 'member:${m.id}', name: m.name),
    ];

    if (people.length < 2) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SizedBox(
        // Sized to the face, like Kalender's row: 26 plus the chip's padding
        // and its selected ring.
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _PersonChip(label: L.s.all, active: selected == null, onTap: () => notifier.filterToPerson(null)),
            for (final person in people)
              _PersonChip(
                label: person.name,
                active: selected == person.id,
                onTap: () => notifier.filterToPerson(person.id),
                face: _personFace(ref, person.id, person.name),
              ),
          ],
        ),
      ),
    );
  }
}

/// The circle on a Board person chip — a member's own picture where there is
/// one, their initials on their tone where there is not, and the initial of a
/// name for somebody with no account at all.
Widget _personFace(WidgetRef ref, String groupId, String name) {
  // The same 26pt Kalender's row uses, and for the same reason: below about
  // that, a photograph stops being a face and becomes a coloured dot, which is
  // the one thing a row of people must not look like.
  const size = 26.0;

  if (groupId.startsWith('member:')) {
    final id = groupId.substring('member:'.length);
    for (final m in ref.watch(householdMembersProvider)) {
      if (m.id != id) continue;
      final tone = AppTones.list[m.tone % AppTones.list.length];
      return Avatar(size: size, bg: tone.bg, fg: tone.fg, initials: m.initials, fontSize: 11, imageUrl: m.imageUrl);
    }
  }
  final tone = AppTones.list[name.hashCode.abs() % AppTones.list.length];
  return Avatar(
    size: size,
    bg: tone.bg,
    fg: tone.fg,
    initials: name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
    fontSize: 11,
  );
}

/// One chip in [_PersonFilterRow]. Shaped like Kalender's so the two rows read
/// as the same control; it has no chevron, because a person on the Board has
/// nothing to open into — their tasks and their rhythms are already the whole
/// answer.
class _PersonChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Widget? face;

  const _PersonChip({required this.label, required this.active, required this.onTap, this.face});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.only(left: face == null ? 14 : 4, right: 14, top: 4, bottom: 4),
          decoration: BoxDecoration(
            color: active ? tint(accent, .82) : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: active ? accent : Colors.transparent, width: 1.5),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (face != null) ...[face!, const SizedBox(width: 7)],
              Text(
                label,
                style: AppText.caption.copyWith(
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? AppColors.ink : AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
