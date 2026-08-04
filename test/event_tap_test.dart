import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aporah/screens/calendar_screen.dart';

void main() {
  testWidgets('Tapping an event opens the detail sheet', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: CalendarScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Team Standup'), findsOneWidget);
    await tester.tap(find.text('Team Standup'));
    await tester.pumpAndSettle();

    expect(find.text('Bearbeiten'), findsOneWidget);
  });
}
