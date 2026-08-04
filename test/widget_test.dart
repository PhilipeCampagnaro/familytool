import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aporah/main.dart';

void main() {
  testWidgets('App shell shows Board tab with bottom nav', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_done': true});
    await tester.pumpWidget(const ProviderScope(child: AporahApp()));
    await tester.pumpAndSettle();

    expect(find.text('Board'), findsWidgets);
    // Kalender is a non-active tab, kept mounted-but-offstage by the shell's
    // IndexedStack (see CLAUDE.md's "Structure" section) — skipOffstage:
    // false is needed since find.text() ignores offstage matches by default.
    expect(find.text('Kalender', skipOffstage: false), findsWidgets);
  });
}
