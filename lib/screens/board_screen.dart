import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../data/board_data.dart';
import '../models/task.dart';
import '../models/who.dart';
import '../state/auth_state.dart';
import '../state/board_state.dart';
import '../state/sharing_state.dart';
import '../state/family_state.dart';
import '../theme/tokens.dart';
import '../widgets/app_sheet.dart';
import '../widgets/avatar.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/check_off.dart';
import '../widgets/collapsing_header.dart';
import '../widgets/day_circle.dart';
import '../widgets/event_dots.dart';
import '../widgets/glass.dart';
import '../widgets/share_sheet.dart';
import '../widgets/error_note.dart';
import '../widgets/visibility_picker.dart';

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

    // The real week around the selected day, so the strip follows the device
    // clock and keeps working when a week straddles two months.
    final week = boardWeekOf(state.selectedDay);
    final allTasks = state.tasksFor(state.selectedDay);
    final open = [for (final t in allTasks) if (!t.done) t];
    final done = [for (final t in allTasks) if (t.done) t];
    final progress = allTasks.isEmpty ? 0.0 : done.length / allTasks.length;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: CollapsingHeaderScreen(
          titleRowBuilder: (context, t) => CollapsingScreenTitle(
            title: 'Board',
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
          // The week strip is inset like everything else here, so the whole
          // block takes the header's default padding.
          extra: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(boardMonthLabel(week), style: AppText.sectionHeading),
                  Spacer(),
                  Flexible(
                    child: Text(
                      boardWeekRange(week),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w300, color: AppColors.muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final d in week) ...[
                    Expanded(
                      child: _WeekDayCell(day: d, state: state, notifier: notifier, accent: accent),
                    ),
                    if (d != week.last) const SizedBox(width: 6),
                  ],
                ],
              ),
            ],
          ),
          body: ScreenBodyPanel(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 20, 16, navContentInset(context)),
              children: [
                if (state.error != null && !state.loading && state.isEmpty) ...[
                  ErrorNote(message: state.error!, onRetry: () => notifier.load()),
                  const SizedBox(height: 16),
                ],
                _DayCard(
                  state: state,
                  notifier: notifier,
                  accent: accent,
                  open: open,
                  progress: progress,
                  allCount: allTasks.length,
                  doneCount: done.length,
                  onAdd: () => _openNewTaskSheet(context, ref),
                ),
                if (done.isNotEmpty) ...[
                  const SizedBox(height: 20),
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
                            'Erledigt · ${done.length}',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.muted),
                          ),
                          GestureDetector(
                            onTap: notifier.clearDone,
                            child: Text(
                              'Löschen',
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500, color: accent),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SectionCard(
                    children: [
                      for (var i = 0; i < done.length; i++) ...[
                        if (i > 0) CardDivider(),
                        CheckOffArrival(
                          key: ValueKey(done[i].id),
                          animate: done[i].id == state.justMoved,
                          // Undo runs the same animation backwards before the
                          // task travels back up into the day card.
                          child: CheckOffRow(
                            undo: true,
                            onCompleted: () => notifier.toggle(done[i]),
                            builder: (context, strike, undo) => _DoneRow(task: done[i], accent: accent, strike: strike, onUndo: undo),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// First-frame estimate of the collapsing block (month row + week strip) —
  /// [CollapsingHeaderScreen] re-measures the real thing once it's laid out.
  static const _extraHeight = 159.0;

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
  static void _openTaskSheet(BuildContext context, WidgetRef ref, {BoardTask? task}) {
    final text = TextEditingController(text: task?.text ?? '');
    final notes = TextEditingController(text: task?.meta ?? '');
    final notifier = ref.read(boardProvider.notifier);
    // Before the sheet is built, so it opens on this task's own answers rather
    // than on whatever the last sheet left behind.
    notifier.primeDraft(task);
    showAppSheet(
      context: context,
      title: task == null ? 'Neue Aufgabe' : 'Aufgabe bearbeiten',
      onSave: () => task == null
          ? notifier.addTask(text.text, meta: notes.text)
          : notifier.updateTask(task, text: text.text, meta: notes.text),
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
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 17, fontWeight: FontWeight.w500, color: AppColors.ink),
                      decoration: const InputDecoration(border: InputBorder.none, hintText: 'Was ist zu tun?', isDense: true),
                    ),
                  ),
                  CardDivider(),
                  // The one static row left, and it shows real data: the day the
                  // strip is on, which is where the task will be filed. The
                  // "Wiederholen · Nie" row that used to sit under it is gone —
                  // `tasks` has no recurrence column, so it promised something
                  // nothing behind it could deliver.
                  _StaticFieldRow(label: 'Fällig', value: boardLongDayName(task?.dueDate ?? state.selectedDay)),
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
                        Text('Notizen', style: AppText.microLabel),
                        const SizedBox(height: 6),
                        TextField(
                          controller: notes,
                          maxLines: null,
                          textCapitalization: TextCapitalization.sentences,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w400, color: AppColors.ink),
                          decoration: const InputDecoration(border: InputBorder.none, hintText: 'Notizen hinzufügen', isDense: true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Two questions, two rows. The old single picker could answer only
              // one of them at a time — and its own hint admitted it
              // ("Zugewiesen an Lea — für alle sichtbar").
              _AssigneePicker(
                selected: state.newAssigneeId,
                members: members,
                currentUserId: me,
                onSelect: notifier.setAssignee,
              ),
              const SizedBox(height: 14),
              VisibilityPicker(
                visibility: state.newVisibility,
                sharedWith: state.newSharedWith,
                onChanged: notifier.setVisibility,
                members: members,
                currentUserId: me,
                noun: 'die Aufgabe',
                avatarSize: 52,
              ),
              // Only on an existing task: an external link needs a row to point
              // at, and a task that has not been saved yet has no id. Its own
              // action, never folded into "Für wen?" — see [showShareSheet].
              if (task != null && ref.watch(canShareExternallyProvider)) ...[
                const SizedBox(height: 14),
                OutlinedSheetAction(
                  icon: LucideIcons.userPlus,
                  label: 'Teilen',
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
                  label: 'Aufgabe löschen',
                  destructive: true,
                  onTap: () {
                    Navigator.of(context).pop();
                    notifier.deleteTask(task);
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
}

/// "Wer macht das?" — single-select, and independent of who may *see* the task.
///
/// Nobody selected is a real answer ("Niemand"), not a missing one: most family
/// chores are simply "whoever gets to it first", and forcing a name onto them
/// would make the badge on every row meaningless.
class _AssigneePicker extends StatelessWidget {
  final String? selected;
  final List<FamilyMember> members;
  final String? currentUserId;
  final ValueChanged<String?> onSelect;

  const _AssigneePicker({
    required this.selected,
    required this.members,
    required this.currentUserId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 9),
          child: Text('Wer macht das?', style: AppText.microLabel),
        ),
        SizedBox(
          height: 52 + 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            children: [
              PickerAvatarChip(
                label: 'Niemand',
                bg: AppColors.alleBg,
                fg: AppColors.alleFg,
                icon: LucideIcons.users,
                selected: selected == null,
                accent: accent,
                avatarSize: 52,
                onTap: () => onSelect(null),
              ),
              for (final m in members) ...[
                const SizedBox(width: 9),
                PickerAvatarChip(
                  // "Ich" rather than your own name: you know who you are, and
                  // the roster reads better with one first-person entry than
                  // with your name sitting among the others.
                  label: m.id == currentUserId ? 'Ich' : m.name,
                  bg: m.toneColors.bg,
                  fg: m.toneColors.fg,
                  initials: m.initials,
                  selected: selected == m.id,
                  accent: accent,
                  avatarSize: 52,
                  onTap: () => onSelect(selected == m.id ? null : m.id),
                ),
              ],
            ],
          ),
        ),
      ],
    );
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

class _WeekDayCell extends ConsumerWidget {
  final DateTime day;
  final BoardState state;
  final BoardNotifier notifier;
  final Color accent;

  const _WeekDayCell({required this.day, required this.state, required this.notifier, required this.accent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = boardIsSameDay(day, state.selectedDay);
    final today = boardIsSameDay(day, DateTime.now());
    final tasks = [for (final t in state.tasksFor(day)) if (!t.done) t];
    final members = ref.watch(householdMembersProvider);
    final dots = [
      for (final t in tasks.take(3))
        whoBadge(assigneeId: t.assigneeId, visibility: t.visibility, members: members).fg,
    ];
    final overflowCount = tasks.length - 3;

    return GestureDetector(
      onTap: () => notifier.selectDay(day),
      child: Column(
        children: [
          Text(
            boardDayLetter(day),
            style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w500, color: selected ? accent : AppColors.muted),
          ),
          const SizedBox(height: 9),
          Container(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
            decoration: BoxDecoration(color: selected ? tint(accent, .9) : AppColors.surfaceAlt, borderRadius: BorderRadius.circular(22)),
            child: Column(
              children: [
                SizedBox(
                  height: 8,
                  child: Center(
                    child: EventDots(colors: dots, overflowCount: overflowCount),
                  ),
                ),
                const SizedBox(height: 14),
                DaySelectorCircle(day: day.day, selected: selected, today: today, accent: accent),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  final BoardState state;
  final BoardNotifier notifier;
  final Color accent;
  final List<BoardTask> open;
  final double progress;
  final int allCount;
  final int doneCount;
  final VoidCallback onAdd;

  const _DayCard({required this.state, required this.notifier, required this.accent, required this.open, required this.progress, required this.allCount, required this.doneCount, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      boardLongDayName(state.selectedDay),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: AppColors.ink),
                    ),
                  ),
                  Text(
                    allCount == 0 ? 'Nichts geplant' : '$doneCount von $allCount erledigt',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, fontWeight: FontWeight.w400, color: AppColors.muted),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Row(
                children: [
                  Expanded(
                    flex: (progress * 1000).round().clamp(0, 1000),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      height: 7,
                      decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(999)),
                    ),
                  ),
                  const SizedBox(width: 3),
                  if (progress < 1)
                    Expanded(
                      flex: (1000 - (progress * 1000).round()).clamp(0, 1000),
                      child: Container(
                        height: 7,
                        decoration: BoxDecoration(color: tint(accent, .88), borderRadius: BorderRadius.circular(999)),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (open.isNotEmpty)
          // The row plays the check-off animation first and only then tells the
          // notifier, so it strikes through in place before moving to "Erledigt"
          // — and an undone task slides back in here from below.
          for (var i = 0; i < open.length; i++)
            CheckOffArrival(
              key: ValueKey(open[i].id),
              animate: open[i].id == state.justMoved,
              fromBelow: true,
              child: CheckOffRow(
                onCompleted: () => notifier.toggle(open[i]),
                builder: (context, strike, checkOff) => _TaskRow(task: open[i], accent: accent, strike: strike, onCheckOff: checkOff),
              ),
            )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
            child: Column(
              children: [
                Text(
                  'Keine Aufgaben an diesem Tag',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w400, color: AppColors.inkTertiary),
                ),
                const SizedBox(height: 16),
                GlassAccentButton(label: 'Aufgabe hinzufügen', onTap: onAdd),
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

  const _TaskRow({required this.task, required this.accent, required this.strike, required this.onCheckOff});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = whoBadge(
      assigneeId: task.assigneeId,
      visibility: task.visibility,
      members: ref.watch(householdMembersProvider),
    );
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      child: Row(
        children: [
          Expanded(
            // Tapping the task opens it; the check button beside it is still
            // the only thing that ticks it off. Without this the sheet could
            // only ever be typed into once.
            child: GestureDetector(
              onTap: () => BoardScreen._openTaskSheet(context, ref, task: task),
              behavior: HitTestBehavior.opaque,
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
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 15.5, fontWeight: FontWeight.w600, letterSpacing: -0.1, color: Color.lerp(AppColors.ink, _doneInk, strike)),
                  ),
                ),
                const SizedBox(height: 3),
                Opacity(
                  opacity: 1 - 0.45 * strike,
                  child: Row(
                    children: [
                      Avatar(size: 16, bg: w.bg, fg: w.fg, icon: w.icon, initials: w.initials, fontSize: 7.5),
                      const SizedBox(width: 6),
                      Text(
                        w.label,
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, fontWeight: FontWeight.w500, color: w.fg),
                      ),
                      if (task.meta case final note? when note.isNotEmpty)
                        Flexible(
                          child: Text(
                            ' · $note',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, fontWeight: FontWeight.w300, color: AppColors.muted),
                          ),
                        ),
                    ],
                  ),
                ),
                ],
              ),
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
      members: ref.watch(householdMembersProvider),
    );
    // A done row carries nothing else to tap, so the whole line undoes it.
    return GestureDetector(
      onTap: onUndo,
      behavior: HitTestBehavior.opaque,
      child: Padding(
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
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 15.5, fontWeight: FontWeight.w500, color: Color.lerp(AppColors.ink, _doneInk, strike)),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    w.label,
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, fontWeight: FontWeight.w300, color: Color.lerp(AppColors.muted, AppColors.mutedLight, strike)),
                  ),
                ],
              ),
            ),
            CheckOffButton(progress: strike, accent: accent, onTap: onUndo, size: 26, filled: true),
          ],
        ),
      ),
    );
  }
}

class _StaticFieldRow extends StatelessWidget {
  final String label;
  final String value;

  const _StaticFieldRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.ink),
            ),
          ),
          Text(
            value,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w400, color: AppColors.inkTertiary),
          ),
          const SizedBox(width: 4),
          Icon(LucideIcons.chevronRight, size: 16, color: AppColors.mutedLight),
        ],
      ),
    );
  }
}
