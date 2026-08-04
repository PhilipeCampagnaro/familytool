import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aporah/main.dart';
import 'package:aporah/screens/start_screen.dart';
import 'package:aporah/widgets/avatar.dart';
import 'package:aporah/widgets/bottom_nav.dart';

void main() {
  testWidgets('Tapping the Start tab avatar opens Settings', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: StartScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Avatar));
    await tester.pumpAndSettle();

    expect(find.text('Einstellungen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Root gate shows onboarding when unseen, app shell once done', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: AporahApp()));
    await tester.pumpAndSettle();

    expect(find.text('Richten wir deine Familie ein'), findsOneWidget);
    expect(find.byType(AppBottomNav), findsNothing);
  });

  testWidgets('Root gate shows app shell once onboarding is already done', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_done': true});
    await tester.pumpWidget(const ProviderScope(child: AporahApp()));
    await tester.pumpAndSettle();

    expect(find.byType(AppBottomNav), findsOneWidget);
    expect(find.text('Richten wir deine Familie ein'), findsNothing);
  });
}
