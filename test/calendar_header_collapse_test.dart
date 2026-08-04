import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:aporah/screens/calendar_screen.dart';
import 'package:aporah/widgets/glass.dart';

/// The calendar filter is a chip row at rest and a compact dropdown once the
/// header has collapsed — in *both* the week and month views. These guard that
/// swap, and that the two views behave identically: the dropdown must never
/// show up alongside the chip row it stands in for.
void main() {
  Future<void> pumpCalendar(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: CalendarScreen())),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The collapsed dropdown is the only chevron on this screen, and it's built
  // conditionally, so its presence is the assertion.
  final dropdown = find.byIcon(LucideIcons.chevronDown);

  // The chip row stays mounted while collapsing (it's faded, not removed), so
  // "visible" means reading the opacity the collapsing header drives rather
  // than just finding it.
  final chipRow = find.byKey(calendarChipRowKey);

  double chipRowOpacity(WidgetTester tester) {
    final opacity = find.ancestor(of: chipRow, matching: find.byType(Opacity)).first;
    return tester.widget<Opacity>(opacity).opacity;
  }

  testWidgets('Week view: chips at rest, dropdown once collapsed', (tester) async {
    await pumpCalendar(tester);

    expect(chipRowOpacity(tester), 1.0);
    expect(dropdown, findsNothing);

    await tester.drag(find.text('Team Standup'), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(chipRowOpacity(tester), 0.0);
    expect(dropdown, findsOneWidget);
  });

  testWidgets('Month view: chips at rest, dropdown once collapsed', (tester) async {
    await pumpCalendar(tester);
    await tester.tap(find.byIcon(LucideIcons.layoutPanelLeft));
    await tester.pumpAndSettle();

    expect(chipRowOpacity(tester), 1.0);
    expect(dropdown, findsNothing);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(chipRowOpacity(tester), 0.0);
    expect(dropdown, findsOneWidget);
  });

  testWidgets('The dropdown opens an anchored filter menu that applies a filter', (tester) async {
    await pumpCalendar(tester);
    await tester.drag(find.text('Team Standup'), const Offset(0, -400));
    await tester.pumpAndSettle();

    await tester.tap(dropdown);
    await tester.pumpAndSettle();

    // The menu checkmarks the active filter — "Alle" by default — and is the
    // only thing on this screen drawing that icon, so it doubles as the
    // "menu is open" assertion.
    expect(find.byIcon(LucideIcons.check), findsOneWidget);

    // `.last` because the faded-out chip row behind the menu carries the same
    // labels.
    await tester.tap(find.text('Outlook · Arbeit').last);
    await tester.pumpAndSettle();

    expect(find.byIcon(LucideIcons.check), findsNothing);
    expect(dropdown, findsOneWidget);

    // Filter applied: that source's chip is now the active (semibold) one.
    final chip = tester.widgetList<Text>(find.text('Outlook · Arbeit')).firstWhere((t) => t.style?.fontSize == 13.5);
    expect(chip.style?.fontWeight, FontWeight.w600);
  });

  testWidgets('The collapsed title is centered on the screen, not on the space left by the buttons', (tester) async {
    await pumpCalendar(tester);
    await tester.drag(find.text('Team Standup'), const Offset(0, -400));
    await tester.pumpAndSettle();

    final screenCenter = tester.getCenter(find.byType(CalendarScreen)).dx;
    expect(tester.getCenter(find.text('Kalender')).dx, moreOrLessEquals(screenCenter, epsilon: 0.5));
  });

  testWidgets('The collapsed header is frosted across its full width and clears the buttons', (tester) async {
    await pumpCalendar(tester);
    await tester.drag(find.text('Team Standup'), const Offset(0, -400));
    await tester.pumpAndSettle();

    // NestedScrollView's body isn't clipped to below the pinned header — the
    // gray agenda slides all the way up to the top of the screen — so this
    // blurred layer is the only thing between it and the title.
    final frost = find.byType(FrostedHeaderBackground);
    expect(frost, findsOneWidget);
    final frostRect = tester.getRect(frost);
    expect(frostRect.top, 0);
    expect(frostRect.width, tester.getSize(find.byType(CalendarScreen)).width);
    // ...and it has to extend past the glass buttons, or the sharp gray would
    // butt straight against their bottom edge.
    expect(frostRect.bottom, greaterThan(tester.getRect(find.byIcon(LucideIcons.plus).first).bottom + 8));
  });

  testWidgets('The event sheet puts the title and close button on one row, chips below', (tester) async {
    await pumpCalendar(tester);
    await tester.tap(find.text('Team Standup'));
    await tester.pumpAndSettle();

    // `.last` — the agenda row behind the sheet carries the same title.
    final title = tester.getRect(find.text('Team Standup').last);
    final close = tester.getRect(find.byIcon(LucideIcons.x).first);
    final chip = tester.getRect(find.text('Outlook · Arbeit').last);

    // Same row: the chips used to sit above the title, which pushed the title
    // onto its own line and left the close button stranded beside the chips.
    expect(title.center.dy, moreOrLessEquals(close.center.dy, epsilon: 4));
    expect(chip.top, greaterThan(title.bottom));

    // Chips actually on screen, not laid out into a zero-height or clipped-away
    // band — they went missing once before while still being findable.
    expect(chip.height, greaterThan(8));
    final opacity = find.ancestor(of: find.text('Outlook · Arbeit').last, matching: find.byType(Opacity));
    expect(tester.widget<Opacity>(opacity.first).opacity, 1.0);

    // And the sheet's own frosted band has to cover both rows, so the gray body
    // passes under them blurred instead of reading through sharply.
    // `.last` — the calendar's own header behind the sheet has one too.
    expect(tester.getRect(find.byType(FrostedHeaderBackground).last).bottom, greaterThan(chip.bottom));
  });

  testWidgets('The day strip scrolls continuously instead of paging a week at a time', (tester) async {
    await pumpCalendar(tester);

    final strip = find.byKey(calendarDayStripKey);
    final controller = tester.widget<ListView>(strip).controller!;
    final before = controller.offset;

    // A short drag used to either jump seven days or snap back, depending on
    // velocity. It should now just move the strip by roughly what was dragged.
    await tester.drag(strip, const Offset(-60, 0));
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(before));
    expect(controller.offset - before, lessThan(120));
  });

  testWidgets('"Heute" scrolls the strip back even when today is still the selected day', (tester) async {
    await pumpCalendar(tester);

    final strip = find.byKey(calendarDayStripKey);
    final controller = tester.widget<ListView>(strip).controller!;
    final atToday = controller.offset;

    // Scroll today off the strip without tapping any day, so the selection is
    // untouched. "Heute" used to only call selectDay, which is a no-op here —
    // the button appeared and did nothing.
    await tester.fling(strip, const Offset(-600, 0), 1200);
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(atToday + 300));

    await tester.tap(find.text('Heute'));
    await tester.pumpAndSettle();

    expect(controller.offset, moreOrLessEquals(atToday, epsilon: 1));
  });
}
