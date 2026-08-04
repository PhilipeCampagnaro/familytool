import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aporah/screens/board_screen.dart';
import 'package:aporah/screens/box_screen.dart';
import 'package:aporah/screens/calendar_screen.dart';
import 'package:aporah/screens/list_screen.dart';
import 'package:aporah/screens/start_screen.dart';
import 'package:aporah/main.dart';

Future<void> _shoot(WidgetTester tester, Widget child, String name) async {
  tester.view.physicalSize = const Size(780, 1688);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(debugShowCheckedModeBanner: false, home: child),
    ),
  );
  await tester.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/$name.png'));
}

void main() {
  testWidgets('Board screenshot', (tester) async => _shoot(tester, const BoardScreen(), 'board'));
  testWidgets('Box screenshot', (tester) async => _shoot(tester, const BoxScreen(), 'box'));
  testWidgets('List screenshot', (tester) async => _shoot(tester, const ListScreen(), 'list'));
  testWidgets('Calendar screenshot', (tester) async => _shoot(tester, const CalendarScreen(), 'calendar'));
  testWidgets('Start screenshot', (tester) async => _shoot(tester, const StartScreen(), 'start'));
  testWidgets('Shell screenshot', (tester) async => _shoot(tester, const AppShell(), 'shell'));
}
