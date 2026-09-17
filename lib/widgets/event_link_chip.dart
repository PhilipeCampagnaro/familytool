import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/event_link.dart';
import '../state/calendar_state.dart';
import '../theme/tokens.dart';
import '../theme/app_icons.dart';

/// "This came from an appointment" — on a task and on a list, wherever there is
/// room to say so.
///
/// **The return half of the link.** The event sheet knows what hangs off an
/// appointment because it can ask the two providers; a task has no way to say
/// where it came from except by carrying it, which is what
/// [BoardTask.eventLink] is. Without this the link would only work in one
/// direction, and the household would learn about it only from the calendar.
///
/// **It is a marker by default and a button only where it is the only thing to
/// tap.** On a row — a task on the Board card, a list on the Listen overview —
/// the row's own tap already opens the thing, and a second target a few
/// millimetres away in the same line is a coin toss: people aiming at the list
/// landed somewhere else. So the badge there only *says* where the row came
/// from, exactly as the Kalender agenda card's homework badge does. The way
/// back lives one level in, on the opened list and in the task's own sheet,
/// where a chip has a line to itself and nothing to be confused with. Give
/// [onOpen] there.
///
/// **[onOpen] shows the appointment, it does not go to it.** `showLinkedEventSheet`
/// stacks the event's own detail sheet over Board or Listen, so closing it puts
/// the reader back on the row they came from. Switching to Kalender instead
/// worked and lost people: the sheet closed onto a calendar they had not asked
/// for, two tabs away from what they were reading.
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
class EventLinkChip extends ConsumerWidget {
  final EventLink link;

  /// What tapping opens — `showLinkedEventSheet` at every call site that has
  /// one. Null, the default, makes the chip a marker: the surface under it
  /// already has a tap of its own.
  ///
  /// It is ignored while the appointment is outside the fortnight Kalender
  /// holds, because there is then nothing to open — see the note on the name.
  /// Nothing about the pill changes; what changes is that it stops announcing
  /// itself as a button and stops swallowing the tap.
  final VoidCallback? onOpen;

  const EventLinkChip({super.key, required this.link, this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = Theme.of(context).colorScheme.primary;

    // A record rather than the event itself, so the chip rebuilds when its own
    // appointment is renamed or arrives in the window, and not on every tick of
    // Kalender's clock. `loaded` is its own field because an empty title is a
    // real answer — a proxied Google event may have none — and the two cases
    // want different behaviour.
    final (:title, :loaded) = ref.watch(
      calendarProvider.select((s) {
        final e = s.eventForLink(calendarId: link.calendarId, uid: link.uid, day: link.day);
        return (title: e?.title.trim(), loaded: e != null);
      }),
    );
    final day = link.day;
    final label = (title == null || title.isEmpty)
        ? (day == null ? null : L.s.dayMonthShort(day.day, day.month))
        : title;

    final chip = Container(
      padding: EdgeInsets.symmetric(horizontal: label == null ? 6 : 8, vertical: 4),
      decoration: BoxDecoration(color: tint(accent, .88), borderRadius: BorderRadius.circular(12)),
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
    );

    final open = onOpen;
    if (open == null || !loaded) {
      // Still worth a label: the pill is a glyph and a name with no other
      // reading, and VoiceOver would otherwise announce the name alone as if
      // it were the row's own.
      return Semantics(
        label: label == null ? L.s.linkedEventLabel : '${L.s.linkedEventLabel}: $label',
        excludeSemantics: true,
        child: chip,
      );
    }

    return Semantics(
      button: true,
      // What it points at and what tapping does. On a chip that renders as a
      // glyph alone this is the only thing that says either.
      label: label == null ? L.s.openInCalendar : '$label · ${L.s.openInCalendar}',
      excludeSemantics: true,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: open, child: chip),
    );
  }
}
