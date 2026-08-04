import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:aporah/data/box_data.dart';
import 'package:aporah/screens/board_screen.dart';
import 'package:aporah/screens/box_screen.dart';
import 'package:aporah/screens/list_screen.dart';
import 'package:aporah/widgets/avatar.dart';
import 'package:aporah/widgets/collapsing_header.dart';
import 'package:aporah/widgets/glass.dart';

/// Board, Box and Listen share Kalender's collapsing header via
/// [CollapsingHeaderScreen]: a pinned title row that morphs from a large
/// left-aligned heading to a small centered one while the search field / stat
/// tiles / week strip below it fade away and the body slides under a frosted
/// bar.
void main() {
  Future<void> pump(WidgetTester tester, Widget screen) async {
    // A phone-sized surface, not the 800x600 default: these headers reserve
    // horizontal room for their flanking controls, and the centered-title
    // assertions below only mean anything at a realistic width.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: screen)));
    await tester.pumpAndSettle();
  }

  Future<void> collapse(WidgetTester tester) async {
    await tester.drag(find.byType(ScreenBodyPanel), const Offset(0, -400));
    await tester.pumpAndSettle();
  }

  /// The opacity the collapsing block is being drawn at — it stays mounted
  /// while it fades, so finding it isn't enough to call it visible.
  double extraOpacity(WidgetTester tester, Finder inExtra) {
    final opacity = find.ancestor(of: inExtra, matching: find.byType(Opacity)).first;
    return tester.widget<Opacity>(opacity).opacity;
  }

  Future<void> openFirstBox(WidgetTester tester) async {
    await tester.tap(find.byIcon(LucideIcons.chevronRight).first);
    await tester.pumpAndSettle();
  }

  double screenCenterX(WidgetTester tester) => tester.getCenter(find.byType(CollapsingHeaderScreen)).dx;

  testWidgets('Listen: the header collapses and the title lands centered', (tester) async {
    await pump(tester, const ListScreen());

    final title = find.text('Listen');
    final search = find.text('Listen durchsuchen');
    expect(extraOpacity(tester, search), 1.0);
    // At rest the heading is flush left, well clear of center.
    expect(tester.getRect(title).left, lessThan(40));

    await collapse(tester);

    expect(extraOpacity(tester, search), 0.0);
    // Centered on the *screen*, not on the space the add button left over —
    // that off-by-half-a-button is what a Row-based title row gets you.
    expect(tester.getCenter(title).dx, moreOrLessEquals(screenCenterX(tester), epsilon: 0.5));
  });

  testWidgets('Board: the avatar stack folds away so the collapsed title still centers', (tester) async {
    await pump(tester, const BoardScreen());

    expect(find.byType(AvatarStack), findsOneWidget);

    await collapse(tester);

    // Reserving the expanded trailing slot (avatars + button) on both sides
    // would squeeze the collapsed title down to a few characters, so the stack
    // folds away entirely instead.
    expect(find.byType(AvatarStack), findsNothing);
    expect(tester.getCenter(find.text('Board')).dx, moreOrLessEquals(screenCenterX(tester), epsilon: 0.5));
  });

  testWidgets('Box detail: the pinned label swaps to the box name once collapsed', (tester) async {
    await pump(tester, const BoxScreen());
    await openFirstBox(tester);

    // The name is in the title row *and* in the big row below it; only the
    // title row's copy is what this is about.
    Finder inTitleRow(Finder f) => find.descendant(of: find.byType(CollapsingScreenTitle), matching: f);
    final generic = inTitleRow(find.text('Box'));
    final name = inTitleRow(find.text(seedBoxes.first.name));
    expect(generic, findsOneWidget);
    expect(name, findsOneWidget);

    double opacityOf(Finder f) => tester.widget<Opacity>(find.ancestor(of: f, matching: find.byType(Opacity)).first).opacity;

    expect(opacityOf(generic), moreOrLessEquals(1.0));
    expect(opacityOf(name), moreOrLessEquals(0.0));

    await collapse(tester);

    expect(opacityOf(generic), moreOrLessEquals(0.0));
    expect(opacityOf(name), moreOrLessEquals(1.0));
  });

  testWidgets('The collapsing block is measured, not clipped to a hardcoded height', (tester) async {
    await pump(tester, const BoxScreen());

    // The header sizes itself from the content it actually laid out. A constant
    // would have to be tuned against a font — and the app's Poppins is fetched
    // at runtime by google_fonts, so it is *not* the font a widget test
    // measures. Getting that wrong clips the bottom row on a real phone, which
    // is exactly what this catches: the last thing in the block has to still
    // clear the gray panel by the header's own trailing gap.
    final lastRowBottom = tester.getRect(find.text('Artikel')).bottom;
    final panelTop = tester.getRect(find.byType(ScreenBodyPanel)).top;
    expect(panelTop - lastRowBottom, greaterThanOrEqualTo(CollapsingHeaderScreen.collapsedGap));
  });

  testWidgets('The collapsed header is frosted across its full width and clears the buttons', (tester) async {
    await pump(tester, const ListScreen());
    await collapse(tester);

    // NestedScrollView doesn't clip its body to below the pinned header — the
    // gray panel slides all the way up to the top of the screen — so this
    // blurred layer is the only thing between it and the title.
    final frost = find.byType(FrostedHeaderBackground);
    expect(frost, findsOneWidget);
    final rect = tester.getRect(frost);
    expect(rect.top, 0);
    expect(rect.width, tester.getSize(find.byType(CollapsingHeaderScreen)).width);
    expect(rect.bottom, greaterThan(tester.getRect(find.byIcon(LucideIcons.plus).first).bottom));
  });

  testWidgets('Box detail: the pinned row carries the box icon once collapsed', (tester) async {
    await pump(tester, const BoxScreen());
    await openFirstBox(tester);

    Finder inTitleRow(Finder f) => find.descendant(of: find.byType(CollapsingScreenTitle), matching: f);
    final badge = inTitleRow(find.byIcon(LucideIcons.box));
    // Mounted from the start — it's the other half of a crossfade — but drawn
    // at nothing until the big name row it stands in for has scrolled away.
    expect(tester.widget<Opacity>(find.ancestor(of: badge, matching: find.byType(Opacity)).first).opacity, moreOrLessEquals(0.0));

    await collapse(tester);

    expect(badge, findsOneWidget);
    // Badge then name, as a unit: the icon sits to the left of the label and
    // the pair straddles the center of the screen.
    final name = inTitleRow(find.text(seedBoxes.first.name));
    expect(tester.getRect(badge).right, lessThanOrEqualTo(tester.getRect(name).left));
    // The min-width Row wrapping the two is what has to sit centered — the
    // badge's own box, not just its glyph, counts toward that.
    final pair = find.ancestor(of: badge, matching: find.byType(Row)).first;
    expect(tester.getRect(pair).center.dx, moreOrLessEquals(screenCenterX(tester), epsilon: 0.5));
  });

  testWidgets('Box detail: back and overflow are the same glass as every other control', (tester) async {
    await pump(tester, const BoxScreen());
    await openFirstBox(tester);

    // They used to be flat gray circles, the only non-glass round buttons in
    // the app.
    expect(find.descendant(of: find.byType(CollapsingScreenTitle), matching: find.byType(GlassIconButton)), findsNWidgets(2));
    expect(find.byIcon(LucideIcons.chevronLeft), findsOneWidget);
  });

  testWidgets('Box detail: the brand glow runs under the status bar', (tester) async {
    // A notch-sized top inset, which is the whole point: the detail screens
    // drop their SafeArea so the glow owns the top edge, and the header takes
    // the inset on itself instead.
    tester.view.padding = const FakeViewPadding(top: 47);
    await pump(tester, const BoxScreen());
    await openFirstBox(tester);

    expect(tester.getRect(find.byType(HeaderBrandGlow)).top, 0);
    // The title still clears the notch — absorbing the inset means padding the
    // content down by it, not painting over it.
    expect(tester.getRect(find.descendant(of: find.byType(CollapsingScreenTitle), matching: find.text('Box'))).top, greaterThanOrEqualTo(47));
  });
}
