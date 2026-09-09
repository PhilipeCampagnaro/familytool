import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/event_link.dart';
import '../state/calendar_state.dart';
import '../state/nav_state.dart';
import '../theme/tokens.dart';
import '../theme/app_icons.dart';

/// "This came from an appointment" — on a task's row on Board, and on a list's
/// row in Listen. Tapping it leaves for Kalender and lands on that day.
///
/// **The return half of the link.** The event sheet knows what hangs off an
/// appointment because it can ask the two providers; a task has no way to say
/// where it came from except by carrying it, which is what
/// [BoardTask.eventLink] is. Without this the link would only work in one
/// direction, and the household would learn about it only from the calendar.
///
/// It belongs on the row's **subtitle line**, before the count or the date that
/// line already carries — it says what the list or the task *is* for, which is
/// read before how it is going. Parked at the right-hand end of the row instead,
/// past the visibility badge, it had no room for a name and read as a third
/// status glyph rather than as part of the description.
///
/// **The name on it is never stored — it is read off the live event.** The link
/// row holds a calendar, a uid and a day, and nothing that could be called a
/// copy of somebody's appointment; the label comes from
/// [CalendarScreenState.eventForLink] while Kalender is holding the event, which
/// also means a renamed appointment renames every badge pointing at it. Outside
/// the loaded window there is no name to show and the chip prints the date,
/// which is the honest form of "an appointment on the 14th".
///
/// It is its own tap target inside a row that already has one, which the app
/// otherwise avoids — the Kalender agenda card deliberately makes its homework
/// badge a marker rather than a button. The difference is where the two taps
/// go: a homework badge and the card under it both lead to the same sheet, so a
/// second target would only be a smaller way to do the same thing, whereas this
/// leads somewhere the row's own tap never does. The one cost is that a tap
/// here while the row is swiped open navigates instead of closing the swipe;
/// the chip is small and the state is brief, and the alternative is no link
/// back at all.
class EventLinkChip extends ConsumerWidget {
  final EventLink link;

  const EventLinkChip({super.key, required this.link});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = Theme.of(context).colorScheme.primary;

    // Selected down to the one string, so a chip rebuilds when its own
    // appointment is renamed and not on every tick of Kalender's clock. The
    // scan behind it runs over the loaded fortnight and misses for anything
    // further out, which is the common case and costs a map lookup.
    final title = ref.watch(
      calendarProvider.select(
        (s) => s.eventForLink(calendarId: link.calendarId, uid: link.uid, day: link.day)?.title.trim(),
      ),
    );
    final day = link.day;
    final label = (title == null || title.isEmpty)
        ? (day == null ? null : L.s.dayMonthShort(day.day, day.month))
        : title;

    return Semantics(
      button: true,
      // What it points at and what tapping does. On a chip that renders as a
      // glyph alone this is the only thing that says either.
      label: label == null ? L.s.openInCalendar : '$label · ${L.s.openInCalendar}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.read(tabJumpProvider.notifier).toEvent(
          calendarId: link.calendarId,
          uid: link.uid,
          // The day the link was made against. An appointment moved since lands
          // Kalender on the old day and finds nothing there, which is a wrong
          // day rather than a broken tap — see [EventLink].
          day: day,
        ),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: label == null ? 6 : 8, vertical: 4),
          decoration: BoxDecoration(
            color: tint(accent, .88),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(AppIcons.calendarDots, size: 12, color: accent),
              if (label != null) ...[
                const SizedBox(width: 5),
                // Flexible, not Expanded: the chip is as wide as the name it
                // holds until the row runs out of room, and only then does the
                // name give way. A fixed width would leave "Zahnarzt" floating
                // in a pill sized for "Elternabend Klasse 7b".
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.microLabel.copyWith(color: accent),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
