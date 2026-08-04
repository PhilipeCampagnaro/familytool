import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:aporah/screens/board_screen.dart';

void main() {
  testWidgets('Opening the new-task sheet renders WhoPicker without overflow', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: BoardScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pumpAndSettle();

    expect(find.text('Für wen?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
