import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../data/board_data.dart';
import '../models/task.dart';
import '../models/who.dart';
import '../state/auth_state.dart';
import '../state/board_state.dart';
import '../state/board_streak_state.dart';
import '../state/sharing_state.dart';
import '../state/family_state.dart';
import '../theme/tokens.dart';
import '../widgets/app_sheet.dart';
import '../widgets/avatar.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/check_off.dart';
import '../widgets/collapsing_header.dart';
import '../widgets/floating_pill.dart';
import '../widgets/glass.dart';
import '../widgets/share_sheet.dart';
import '../widgets/swipe_actions.dart';
import '../widgets/error_note.dart';
import '../widgets/visibility_picker.dart';
import '../widgets/toast_chip.dart';
import 'board/due_date_sheet.dart';
import 'board/tracker_strip.dart';
import '../l10n/l10n.dart';

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
    final members = ref.watch(householdMembersProvider);

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

    // The device clock, read on every build so the sections are still right
    // after the app has sat open past midnight.
    final today = boardDay(DateTime.now());
    final groups = state.groupsOn(today);
    final done = state.doneTasks;

    // The header reports on today, not on the whole list: a board with eleven
    // tasks spread over three weeks has no meaningful single percentage.
    final onDeck = state.onDeck(today);
    final onDeckDone = [for (final t in onDeck) if (t.done) t].length;
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
                trailingWidth: _avatarStackWidth(members.length) + 12 + 48,
                // The avatar stack folds away as the header collapses (see
                // _CollapsingAvatars), so the collapsed title only has to clear the
                // add button — reserving the full expanded slot would squeeze it to
                // a few characters.
                collapsedSideInset: 86,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CollapsingAvatars(t: t, members: members),
                    SizedBox(width: 12 * (1 - t).clamp(0.0, 1.0)),
                    GlassIconButton(icon: LucideIcons.plus, onTap: () => _openNewTaskSheet(context, ref)),
                  ],
                ),
              ),
              estimatedExtraHeight: _extraHeight,
              // Today, and how much of it is behind you. This is what the week strip
              // used to occupy, and it is deliberately *not* a picker any more:
              // the date is a property of a task now, so there is no day to select.
              extra: _TodayHeader(today: today, progress: progress, done: onDeckDone, total: onDeck.length, accent: accent),
              body: ScreenBodyPanel(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(16, 20, 16, navContentInset(context)),
                  children: [
                    if (state.error != null && !state.loading && state.isEmpty) ...[
                      ErrorNote(message: state.error!, onRetry: () => notifier.load()),
                      const SizedBox(height: 16),
                    ],
                    if (groups.isEmpty && !state.loading)
                      _EmptyBoard(onAdd: () => _openNewTaskSheet(context, ref))
                    else
                      for (final group in groups) ...[
                        _SectionHeading(section: group.section, count: group.tasks.length),
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
                            for (final task in group.tasks)
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
                                      showDate: _sectionSpansDays(group.section),
                                      overdue: group.section == BoardSection.overdue,
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
                              Text(
                                L.s.doneCountSeparator(done.length),
                                style: AppText.caption,
                              ),
                              GestureDetector(
                                onTap: notifier.clearDone,
                                child: Text(
                                  L.s.delete,
                                  style: AppText.caption.copyWith(color: accent),
                                ),
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
  static const _extraHeight = 12 + BoardTrackerStrip.height + 16 + 24 + 12 + 7.0;

  /// Whether a section's rows still need their own date printed on them. The
  /// three that name exactly one day answer the question in their heading;
  /// "Diese Woche" and "Später" cover a span, and "Ohne Datum" has no date to
  /// print in the first place.
  static bool _sectionSpansDays(BoardSection section) =>
      section == BoardSection.thisWeek || section == BoardSection.later || section == BoardSection.overdue;

  /// [AvatarStack]'s own width formula (avatar size + step per extra member),
  /// needed up front to keep the expanded title clear of the stack. Zero while
  /// the household is empty, so the title gets the whole row instead of
  /// reserving space for avatars that aren't drawn.
  ///
  /// A function of the live roster rather than a `static final` off a constant:
  /// members arrive after the first frame, and a width computed once at class
  /// load would reserve room for a household nobody had joined yet.
  static int _avatarStackWidth(int count) => count == 0 ? 0 : 28 + (28 - 9) * (count - 1);

  /// The create/edit sheet. Same sheet either way — [task] set means editing —
  /// so a task's notes and audience can be corrected, not only typed once.
  static void _openTaskSheet(BuildContext context, WidgetRef ref, {BoardTask? task, DateTime? initialDue}) {
    final text = TextEditingController(text: task?.text ?? '');
    final notes = TextEditingController(text: task?.meta ?? '');
    final notifier = ref.read(boardProvider.notifier);
    // Held under its own name because the sheet body's `Consumer` shadows
    // `context` with the sheet's own — which is unmounted by the time a write
    // comes back. The confirmation belongs to the screen, so it needs this one.
    final screen = context;
    // Before the sheet is built, so it opens on this task's own answers rather
    // than on whatever the last sheet left behind.
    notifier.primeDraft(task, initialDue: initialDue);
    showAppSheet(
      context: context,
      title: task == null ? L.s.newTask : L.s.editTask,
      onSave: () async {
        // The sheet is already gone by the time the write comes back (the
        // chrome pops it the moment save is tapped), so the chip lands on the
        // screen behind it — which is where it belongs.
        final confirm = confirmChipOf(screen);
        if (task != null) {
          if (await notifier.updateTask(task, text: text.text, meta: notes.text)) confirm(L.s.taskUpdated);
          return;
        }
        if (await notifier.addTask(text.text, meta: notes.text)) confirm(L.s.taskCreated);
      },
      child: Consumer(
        builder: (context, ref, _) {
          final state = ref.watch(boardProvider);
          final members = ref.watch(householdMembersProvider);
          final me = ref.watch(currentUserIdProvider);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionCard(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                    child: TextField(
                      controller: text,
                      textCapitalization: TextCapitalization.sentences,
                      style: AppText.inputTitle,
                      decoration: InputDecoration(border: InputBorder.none, hintText: L.s.taskPlaceholder, isDense: true),
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
                  _DueDateField(
                    value: state.newDueDate,
                    onChanged: notifier.setDueDate,
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
                noun: L.s.theTask,
                avatarSize: 52,
              ),
              // Only on an existing task: an external link needs a row to point
              // at, and a task that has not been saved yet has no id. Its own
              // action, never folded into "Für wen?" — see [showShareSheet].
              if (task != null && ref.watch(canShareExternallyProvider)) ...[
                const SizedBox(height: 14),
                OutlinedSheetAction(
                  icon: LucideIcons.userPlus,
                  label: L.s.share,
                  onTap: () => showShareSheet(
                    context,
                    kind: ShareableKind.task,
                    resourceId: task.id,
                    resourceName: task.text,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedSheetAction(
                  icon: LucideIcons.trash2,
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
            ],
          );
        },
      ),
    );
  }

  void _openNewTaskSheet(BuildContext context, WidgetRef ref) => _openTaskSheet(context, ref);

  /// Deletes a task from its row's swipe action, with the same undo chip the
  /// sheet's "Aufgabe löschen" puts up. There is no confirmation dialog in front
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

/// The Board header's member stack, folded away as the header collapses: the
/// width factor and the opacity both ride `t`, so the add button ends up flush
/// against the collapsed title bar instead of leaving a hole where the avatars
/// used to be.
class _CollapsingAvatars extends StatelessWidget {
  final double t;
  final List<FamilyMember> members;

  const _CollapsingAvatars({required this.t, required this.members});

  @override
  Widget build(BuildContext context) {
    final visible = (1 - t).clamp(0.0, 1.0);
    // Nobody in the household yet — no stack, and no gap where one would be.
    if (visible == 0 || members.isEmpty) return const SizedBox.shrink();
    return ClipRect(
      child: Align(
        alignment: Alignment.centerLeft,
        widthFactor: visible,
        child: Opacity(
          opacity: visible,
          child: AvatarStack(
            avatars: [for (final m in members) Avatar(size: 28, bg: m.toneColors.bg, fg: m.toneColors.fg, initials: m.initials, fontSize: 10)],
          ),
        ),
      ),
    );
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

  const _TodayHeader({required this.today, required this.progress, required this.done, required this.total, required this.accent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracker = ref.watch(boardStreakProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        // Named rather than left to explain itself — it has no axis, no numbers
        // and nothing to tap. The caption is drawn inside the grid's first row
        // (see [BoardTrackerStrip]) rather than above it: a line of its own here
        // would be a second title under "Board", and would cost the header a
        // whole row to say one word.
        BoardTrackerStrip(days: tracker.days, today: today, accent: accent),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                boardLongDayName(today),
                overflow: TextOverflow.ellipsis,
                style: AppText.sectionHeading,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              total == 0 ? L.s.nothingPlanned : L.s.doneOfTotal(done, total),
              style: AppText.label,
            ),
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
  final BoardSection section;
  final int count;

  const _SectionHeading({required this.section, required this.count});

  String get _title => switch (section) {
    BoardSection.overdue => L.s.sectionOverdue,
    BoardSection.today => L.s.sectionToday,
    BoardSection.tomorrow => L.s.sectionTomorrow,
    BoardSection.thisWeek => L.s.sectionThisWeek,
    BoardSection.later => L.s.sectionLater,
    BoardSection.undated => L.s.sectionUndated,
  };

  @override
  Widget build(BuildContext context) {
    // Overdue is the one heading that carries a colour: it is the only section
    // whose contents are a problem rather than a plan.
    final tone = section == BoardSection.overdue ? AppColors.danger : AppColors.muted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
      child: Row(
        children: [
          Text(
            _title,
            style: AppText.groupHeading.copyWith(letterSpacing: 0, color: tone),
          ),
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
              Text(
                L.s.noOpenTasks,
                style: AppText.body.copyWith(color: AppColors.inkTertiary),
              ),
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
                    child: Text(
                      note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.label,
                    ),
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
                      if (showDate && due != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          L.s.dayMonthShort(due.day, due.month),
                          style: AppText.label.copyWith(
                            color: overdue ? AppColors.danger : AppColors.muted,
                            fontWeight: overdue ? FontWeight.w500 : null,
                          ),
                        ),
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
                  child: Semantics(
                    label: w.label,
                    excludeSemantics: true,
                    child: WhoAvatars(who: w, size: 22, fontSize: 9.5),
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
                Expanded(
                  child: Text(
                    L.s.assigneeLabel,
                    style: AppText.rowTitle,
                  ),
                ),
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
                        child: Icon(LucideIcons.chevronRight, size: 16, color: AppColors.mutedLight),
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

  const _AssigneeOption({
    required this.member,
    required this.label,
    required this.selected,
    required this.onTap,
  });

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
            if (selected) Icon(LucideIcons.check, size: 17, color: accent),
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
class _DueDateField extends StatelessWidget {
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  const _DueDateField({required this.value, required this.onChanged});

  Future<void> _pick(BuildContext context) async {
    final choice = await showDueDateSheet(context, current: value);
    // Null means the sheet was dismissed — a *choice* of no date arrives as
    // `DueDateChoice(null)`, which is why the wrapper exists.
    if (choice == null) return;
    onChanged(choice.day);
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
            Expanded(child: Text(L.s.dueLabel, style: AppText.rowTitle)),
            Text(
              due == null ? L.s.dueNone : boardLongDayName(due),
              style: AppText.input.copyWith(
                // The dash is punctuation standing in for an answer, so it sits
                // a shade back from a date that really is one.
                color: due == null ? AppColors.mutedLight : AppColors.inkTertiary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronRight, size: 16, color: AppColors.mutedLight),
          ],
        ),
      ),
    );
  }
}
