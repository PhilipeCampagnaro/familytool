import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../data/calendar_data.dart';
import '../data/german_holidays.dart';
import '../models/calendar_event.dart';
import '../models/weather.dart';
import '../services/action_sheet.dart';
import '../services/external_links.dart';
import '../services/map_snapshot.dart';
import '../state/calendar_state.dart';
import '../state/family_state.dart';
import '../state/holidays_state.dart';
import '../state/weather_state.dart';
import '../theme/tokens.dart';
import '../widgets/anchored_menu.dart';
import '../widgets/app_sheet.dart';
import '../widgets/avatar.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/day_circle.dart';
import '../widgets/error_note.dart';
import '../widgets/event_dots.dart';
import '../widgets/floating_pill.dart';
import '../widgets/glass.dart';
import '../widgets/native_switch.dart';
import '../widgets/swipe_actions.dart';
import '../widgets/toast_chip.dart';
import '../l10n/l10n.dart';
import 'calendar_connect_screen.dart';

part 'calendar/event_form.dart';
part 'calendar/calendar_filter.dart';
part 'calendar/week_view.dart';
part 'calendar/month_view.dart';
part 'calendar/event_detail_sheet.dart';

/// The forecast for the event the sheet or the row is showing, on the day it is
/// being shown on.
///
/// The day matters and is always the selected one: an all-day event spanning a
/// week is sampled per day, so "which day am I looking at" is half of the
/// lookup key. Null is the ordinary answer for a past event, one beyond the
/// forecast horizon, or a household with no address yet.
WeatherReading? _weatherFor(WidgetRef ref, CalendarEvent event) {
  final sel = ref.watch(calendarProvider.select((s) => s.selected));
  return ref.watch(weatherProvider).forEvent(event, DateTime(sel.y, sel.m, sel.d));
}

bool _sameDay(CalSelectedDay s, int y, int m, int d) => s.y == y && s.m == m && s.d == d;

bool _isToday(int y, int m, int d) {
  final t = calToday();
  return y == t.year && m == t.month && d == t.day;
}

/// A day's dot colours, already narrowed to the active calendar chip.
///
/// The narrowing now happens inside [CalendarScreenState.dayColors], because
/// `eventsFor` applies the filter by calendar id. Matching on colour, as this
/// used to, silently merged two calendars a household had given the same
/// colour.

/// Year/month `monthOffset` months from the real "today", used to anchor the
/// month view's infinite scroll (offset 0 = today's month, negative = past,
/// positive = future) independent of whichever day is currently selected.
(int, int) _monthAt(int monthOffset) {
  final today = calToday();
  final total = today.month - 1 + monthOffset;
  final year = today.year + (total >= 0 ? total ~/ 12 : (total - 11) ~/ 12);
  final month = ((total % 12) + 12) % 12 + 1;
  return (year, month);
}

class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(calendarProvider);
    final accent = Theme.of(context).colorScheme.primary;

    // A write that didn't land is reported once and then forgotten, so the same
    // message can appear again if the next attempt fails too. This matters more
    // here than anywhere else in the app: the sheet's save button closes the
    // sheet before the write to Google has finished, so without this a family
    // would walk away believing an appointment is in their calendar when it
    // never arrived.
    ref.listen<String?>(calendarProvider.select((s) => s.error), (_, message) {
      if (message == null) return;
      showErrorSnack(context, message);
      ref.read(calendarProvider.notifier).clearError();
    });

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        // Both views build their own header (title + month/toggle row) inside
        // a scroll-collapsing sliver-or-listener, so it can shrink as their
        // content scrolls — see _WeekView / _MonthView.
        child: state.isWeek ? _WeekView(state: state, accent: accent) : _MonthView(state: state, accent: accent),
      ),
    );
  }
}

/// The screen's "Kalender" title + add button — always visible. [t] (0 =
/// expanded, 1 = fully collapsed) morphs the title from a large left-aligned
/// heading down to a small centered one, matching an iOS large-title nav bar
/// collapse. Both views drive it continuously from scroll offset (the week
/// view via [CollapsingSliverHeaderDelegate], the month view off its own
/// `ScrollController`).
class _TitleRow extends StatelessWidget {
  final double t;
  final VoidCallback onAdd;

  /// Optional control pinned to the far left, alongside the title — the
  /// calendar-filter dropdown lives here, and only while collapsed: it stands
  /// in for the [_ToggleAndChipsRow] chip row, which has scrolled away by
  /// then. See [_leadingOpacity].
  final Widget? leading;

  const _TitleRow({required this.t, required this.onAdd, this.leading});

  /// The filter dropdown duplicates the chip row, so it stays hidden until
  /// those chips are essentially gone — it fades in over the last 40% of the
  /// collapse rather than cross-fading against the control it replaces.
  double get _leadingOpacity => ((t - 0.6) / 0.4).clamp(0.0, 1.0);

  /// Horizontal breathing room reserved on both sides of the collapsed title —
  /// wide enough for the filter pill, which is the wider of the two flanking
  /// controls. Both sides get the *same* inset at t == 1 even though the add
  /// button needs less, because an asymmetric inset is exactly what knocks a
  /// centered title off-center.
  static const _collapsedSideInset = 86.0;

  /// What the title must clear on the right at rest: the add button plus a gap.
  static const _addButtonSlot = 48.0;

  @override
  Widget build(BuildContext context) {
    final leadingOpacity = _leadingOpacity;
    return SizedBox(
      height: 40,
      child: Stack(
        children: [
          // The title is its own full-width layer rather than an `Expanded`
          // sibling of the add button: as a Row child its "center" would be
          // the center of the space the buttons left over, so the collapsed
          // title sat visibly off-center by half the button's width. Spanning
          // the whole row makes centered mean centered, whatever flanks it.
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(
                left: _collapsedSideInset * t,
                right: _addButtonSlot + (_collapsedSideInset - _addButtonSlot) * t,
              ),
              child: Align(
                alignment: Alignment.lerp(Alignment.centerLeft, Alignment.center, t)!,
                child: Text(
                  L.s.calendarTitle,
                  maxLines: 1,
                  style: AppText.screenTitle.copyWith(fontSize: 26 - 9 * t),
                ),
              ),
            ),
          ),
          Positioned(right: 0, top: 0, bottom: 0, child: Center(child: GlassIconButton(icon: LucideIcons.plus, onTap: onAdd))),
          // Overlaid rather than laid out inline for the same reason as the
          // title: reserving width for it would drag the expanded, left-aligned
          // title sideways even at t == 0, where this isn't visible at all.
          if (leading != null && leadingOpacity > 0)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: leadingOpacity < 1,
                child: Opacity(opacity: leadingOpacity, child: leading!),
              ),
            ),
        ],
      ),
    );
  }
}

/// Identifies the filter chip row for tests. The day strip is a horizontal
/// `ListView` too, so "the horizontal list in the header" isn't specific enough
/// to find it by.
const calendarChipRowKey = ValueKey('calendarChipRow');

/// Identifies the week view's scrolling day strip for tests.
const calendarDayStripKey = ValueKey('calendarDayStrip');

/// Month/year label + list-vs-grid toggle, and the calendar filter chip row —
/// the part of the header that fades/shrinks away entirely as either view
/// collapses, at which point [_CalendarFilterButton] fades into the title row
/// to take the chips' place. Shared by both views so the two behave
/// identically.
class _ToggleAndChipsRow extends ConsumerWidget {
  final CalendarScreenState state;
  final Color accent;
  final String monthLabel;

  const _ToggleAndChipsRow({required this.state, required this.accent, required this.monthLabel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MonthYearToggleRow(state: state, accent: accent, monthLabel: monthLabel),
        const SizedBox(height: 14),
        SizedBox(
          height: 40,
          child: ListView(
            key: calendarChipRowKey,
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _CalendarChip(
                  label: L.s.all,
                  color: AppColors.muted,
                  active: state.calendarFilter == null,
                  onTap: () => ref.read(calendarProvider.notifier).clearCalendarFilter(),
                ),
              ),
              for (final src in state.activeSources)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _CalendarChip(
                    label: src.name,
                    color: src.color,
                    active: state.calendarFilter == src.id,
                    onTap: () => ref.read(calendarProvider.notifier).setCalendarFilter(src.id),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Month/year label (crossfading as the visible month changes) + the
/// list-vs-grid view toggle — shared by the week view's full header
/// ([_ToggleAndChipsRow]) and the month view's own collapsing header.
class _MonthYearToggleRow extends StatelessWidget {
  final CalendarScreenState state;
  final Color accent;
  final String monthLabel;

  const _MonthYearToggleRow({required this.state, required this.accent, required this.monthLabel});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(animation),
                  child: child,
                ),
              ),
              child: Text(monthLabel, key: ValueKey(monthLabel), style: AppText.sectionHeading),
            ),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: [
                  _ViewToggleButton(icon: LucideIcons.list, active: state.isWeek, accent: accent, onTap: () => ref.read(calendarProvider.notifier).setWeekView()),
                  _ViewToggleButton(icon: LucideIcons.layoutPanelLeft, active: !state.isWeek, accent: accent, onTap: () => ref.read(calendarProvider.notifier).setMonthView()),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ViewToggleButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  const _ViewToggleButton({required this.icon, required this.active, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 34,
        decoration: BoxDecoration(
          color: active ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(17),
          boxShadow: active ? AppShadows.thumb : null,
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 17, color: active ? accent : AppColors.muted),
      ),
    );
  }
}

/// A single calendar's filter chip in the shared header — same outline-ring
/// (1.5px inset) as the day circles, but coloured per calendar source instead
/// of the app accent. Shown above both week and month views; tapping the
/// active chip again clears the filter (shows every calendar).
class _CalendarChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  const _CalendarChip({required this.label, required this.color, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(27),
          border: Border.all(color: active ? color : Colors.transparent, width: 1.5),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: active ? tint(color, .82) : AppColors.surfaceAlt, borderRadius: BorderRadius.circular(24)),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 7),
              Text(label, style: AppText.caption.copyWith(fontWeight: active ? FontWeight.w600 : FontWeight.w400, color: active ? AppColors.ink : AppColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}
