import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'l10n/l10n.dart';
import 'screens/auth_screen.dart';
import 'screens/board_screen.dart';
import 'screens/box_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/list_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/start_screen.dart';
import 'services/supabase.dart';
import 'state/auth_state.dart';
import 'state/calendar_state.dart';
import 'state/family_state.dart';
import 'state/nav_state.dart';
import 'state/settings_state.dart';
import 'theme/app_icons.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';
import 'widgets/bottom_nav.dart';
import 'widgets/empty_state.dart';
import 'widgets/error_note.dart';
import 'widgets/native_tab_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Awaited before the first frame so a returning user's stored session is
  // already restored — otherwise `_RootGate` would render the login screen for
  // a moment on every launch.
  await AporahSupabase.initialize();
  runApp(ProviderScope(child: AporahApp()));
}

/// Dark mode is driven by the app's own "Dunkelmodus" switch in Settings
/// (persisted by `SettingsNotifier`), **not** by the device appearance — the
/// family shares one look regardless of each phone's system setting, and the
/// toggle would otherwise be a no-op whenever it disagreed with the OS.
class AporahApp extends ConsumerWidget {
  const AporahApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final darkMode = ref.watch(settingsProvider.select((s) => s.darkMode));
    final language = ref.watch(settingsProvider.select((s) => s.language));
    final palette = darkMode ? AppPalette.dark : AppPalette.light;

    // Installed here, before anything below builds, because the `AppColors`
    // tokens resolve against this global rather than through an
    // `InheritedWidget` (see the AppColors doc). Assigning during build is
    // safe precisely because it's not itself observable state: the rebuild is
    // already happening, driven by the `ref.watch` above.
    AppColors.palette = palette;

    // Same trick, same reason: every string below reads `L.s` directly rather
    // than through an `InheritedWidget`, so the language has to be in place
    // before the subtree builds. See the `L` doc.
    L.use(language.name);

    return MaterialApp(
      title: 'Aporah',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(AppPalette.light),
      darkTheme: buildAppTheme(AppPalette.dark),
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      // `locale` is forced from Settings rather than left to the device: the
      // family shares one interface language the same way it shares one theme,
      // and a phone set to French must not put the pickers into a third
      // language the app itself never speaks. The delegates are what translate
      // the one surface Flutter supplies rather than us — the date and time
      // pickers behind the event form.
      locale: Locale(language.name),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: appSupportedLocales,
      // No screen here has an `AppBar`, so nothing is setting the status-bar
      // style for us — without this the clock and battery icons stay dark and
      // disappear into a dark screen. Note the two brightness fields mean
      // opposite things: `statusBarIconBrightness` (Android) is the colour of
      // the icons, `statusBarBrightness` (iOS) is the colour of what's *behind*
      // them.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: darkMode ? Brightness.light : Brightness.dark,
          statusBarBrightness: darkMode ? Brightness.dark : Brightness.light,
        ),
        // `showTimePicker` reads its 12/24-hour dial off
        // `MediaQuery.alwaysUse24HourFormat`, which is the *device* setting.
        // Left alone, a German phone switched to English would show 12-hour
        // times everywhere in the app and then open a 24-hour picker to edit
        // them. The interface language decides both.
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            alwaysUse24HourFormat: alwaysUse24HourFormat,
          ),
          child: _DismissKeyboardOnTap(child: child ?? const SizedBox.shrink()),
        ),
      ),
      // Not `const`: a canonicalised instance would make the element below
      // identical across a theme flip, and the whole screen tree would be
      // skipped and keep painting the old palette.
      home: _RootGate(),
    );
  }
}

/// Puts the keyboard away on a tap that was meant for nothing else.
///
/// **Flutter drops focus on a tap outside the field only on desktop.** On a
/// phone `EditableText` deliberately holds on through a touch, so a field the
/// user has changed their mind about keeps the keyboard up with no way out of
/// it: "Artikel hinzufügen" with nothing typed in it offers Return, and the
/// number pad behind a quantity does not even offer that. The article row grew
/// its own `onTapOutside` for exactly this (`_unfocusFields` in
/// [ListScreen]'s row), and every other field in the app was still stuck. This
/// is that answer once, sitting above the `Navigator` so the sheets and the
/// screens behind them are both covered.
///
/// **A gesture-arena entry rather than a [Listener].** Anything with a tap of
/// its own — a row, a suggestion chip, a button, the check-off circle — sits
/// deeper in the tree and wins the arena, so only a tap nobody else wanted puts
/// the keyboard away. The native chrome is safe for the same reason from the
/// other direction: the tab bar, the switch and the search field each claim
/// their touches with an `EagerGestureRecognizer`, which resolves the arena
/// before this ever sees it.
class _DismissKeyboardOnTap extends StatelessWidget {
  final Widget child;

  const _DismissKeyboardOnTap({required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // The child fills the screen, but much of it is transparent and a tap on
      // empty glass is the commonest way of saying "I'm done here".
      behavior: HitTestBehavior.translucent,
      // VoiceOver already has its own way out of a field; announcing the whole
      // app as a button would bury every control under it.
      excludeFromSemantics: true,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: child,
    );
  }
}

/// Three gates in sequence: signed in, household loaded, onboarding finished.
///
/// Each "still deciding" case renders a bare surface rather than a spinner or a
/// guess. The alternative — showing the login screen while the stored session
/// is still being restored, or an empty household while the roster loads — is a
/// visible flash of the wrong thing on every launch.
///
/// `families.onboarding_done` decides the last gate, not the old local
/// `shared_preferences` flag: whether the wizard has been run is a property of
/// the household, so it must not reappear on a second device or for a member
/// who joins later.
class _RootGate extends ConsumerWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(authProvider.select((s) => s.status));

    switch (status) {
      case AuthStatus.unknown:
        return Scaffold(backgroundColor: AppColors.surface);
      case AuthStatus.signedOut:
      case AuthStatus.awaitingConfirmation:
        return AuthScreen();
      case AuthStatus.signedIn:
        break;
    }

    final family = ref.watch(familyProvider);
    if (!family.loaded) return Scaffold(backgroundColor: AppColors.surface);
    if (family.household == null) return _NoHousehold();

    if (family.household?.onboardingDone == false) return OnboardingScreen();
    return AppShell();
  }
}

/// The last gate's failure, which until now had nowhere to appear.
///
/// `FamilyState` has carried an `error` for this all along and nothing drew
/// it, so a household that did not come back fell through to the shell and
/// rendered a plausible-looking empty family — the one thing
/// `HouseholdNotifier` says in its own comments that it refuses to do. Now it
/// says so instead, and offers the only move that helps.
///
/// Reloading invalidates the provider rather than calling `load()` again: a
/// fresh notifier starts from `loaded: false`, so the gate goes back to its
/// bare surface for the length of one attempt and this screen returns if that
/// attempt fails too. Calling `load()` would leave the failure on screen with
/// nothing visibly happening behind it.
class _NoHousehold extends ConsumerWidget {
  const _NoHousehold();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = ref.watch(familyProvider.select((s) => s.error));
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              EmptyState(
                icon: AppIcons.warning,
                message: error ?? L.s.householdLoadFailed,
                verticalPadding: 0,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(familyProvider),
                child: Text(L.s.reload),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Home is the landing tab — the app opens on the overview, not on Board.
const _initialTab = homeTabIndex;

/// One entry per [navTabs] entry, in the same order.
///
/// Built fresh on every `AppShell` build rather than held as a `const` list:
/// const screen instances are canonicalised, so their elements would be
/// skipped when the theme flips and all five tabs would stay in the old
/// palette. Rebuilding the *widgets* is cheap and preserves each screen's
/// `State` (scroll offset, header expansion), which is the thing that
/// actually has to survive here.
List<Widget> _buildScreens() => [
  StartScreen(),
  CalendarScreen(),
  ListScreen(),
  BoardScreen(),
  BoxScreen(),
];

/// The tabs whose scrolling compacts the nav bar (see [navBarProvider]).
///
/// Both halves of the calendar: Home is its week view and Kalender its month
/// grid. They are the screens where the rows are wide, dense and read for a
/// while, so the bar has the most to gain by getting out of the way — and the
/// least to lose, since nothing on either is a step in a flow that needs
/// another tab. See [calendarTabIndex] for why the indices have names at all.
const _compactingTabs = {homeTabIndex, calendarTabIndex};

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

/// Cross-fades + slides between tabs on every nav-bar tap instead of an
/// instant cut, while keeping each screen mounted in an [IndexedStack] so
/// per-tab scroll/expansion state survives switching away and back. The
/// controller runs a quick fade-out of the outgoing screen, swaps `_index`
/// at the midpoint, then fades/slides the new one in — since `IndexedStack`
/// only ever paints one child, this "out then in" sequence reads as a single
/// smooth transition without the cost of a true crossfade (both screens
/// visible at once), which `IndexedStack` can't do.
class _AppShellState extends ConsumerState<AppShell>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int _index = _initialTab;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  late final Animation<Offset> _slide = Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(_fade);

  @override
  void initState() {
    super.initState();
    _controller.value = 1;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  /// Coming back to the app re-reads the calendar.
  ///
  /// Without this the only calendar read in the app's life is the one at launch,
  /// because all five screens stay mounted in the `IndexedStack` and nothing
  /// remounts. A phone left in a pocket overnight and picked up in the morning
  /// showed yesterday — on the screen the whole product is sold on.
  ///
  /// **The shell, not a screen**, for the same reason the write-failure listener
  /// below sits here: two tabs draw the calendar and both are always mounted, so
  /// an observer on each would fan out twice on every resume.
  ///
  /// [CalendarNotifier.refreshIfStale] owns the throttle. This deliberately does
  /// not wait on it and does not report failure — a resume is not an action on
  /// the calendar, and whatever is already on screen stays there.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!mounted) return;
    unawaited(ref.read(calendarProvider.notifier).refreshIfStale());
  }

  void _expandNav() => ref.read(navBarProvider.notifier).expand();

  Future<void> _navigateTo(int i) async {
    if (i == _index) return;
    // A compacted bar belongs to the tab that compacted it and must not follow
    // the user out: reset here as well as gating on the index below, so the tab
    // the bar reappears on is never a surprise.
    ref.read(navBarProvider.notifier).expand();
    await _controller.reverse();
    if (!mounted) return;
    setState(() => _index = i);
    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    // A link tapped on another tab — the calendar icon on a task, the list card
    // in an event's sheet. The shell owns the tab and does that half; the
    // payload is left in place for the destination screen's own listener, which
    // is what clears it. See [TabJump].
    //
    // A jump with no payload — Home's "Alle anzeigen" over the open to-dos —
    // has no destination listener to clear it, so the shell clears its own.
    ref.listen<TabJump?>(tabJumpProvider, (_, jump) {
      if (jump == null) return;
      // [_switchTo] rather than [_navigateTo]: a jump names its destination, so
      // it must never be answered with a menu.
      _switchTo(jump.tab);
      if (jump.listId == null && jump.taskId == null) {
        ref.read(tabJumpProvider.notifier).done();
      }
    });
    // A calendar write that didn't land is reported once and then forgotten, so
    // the same message can appear again if the next attempt fails too. This
    // matters more than anywhere else in the app: the event sheet's save button
    // closes the sheet before the write to Google has finished, so without this
    // a family would walk away believing an appointment is in their calendar
    // when it never arrived.
    //
    // **The shell, not a screen.** It used to sit on `CalendarScreen`, which was
    // the only place an event could be written from. Two tabs draw the calendar
    // now and both are always mounted in the `IndexedStack`, so the same listener
    // on each would have shown every failure twice.
    ref.listen<String?>(calendarProvider.select((s) => s.error), (_, message) {
      if (message == null) return;
      showErrorSnack(context, message);
      ref.read(calendarProvider.notifier).clearError();
    });
    // The `Scaffold` resizes its body around the keyboard so text fields stay
    // visible, which would otherwise carry the floating nav bar up with it and
    // park it on top of the keyboard. iOS keeps the tab bar at the bottom and
    // lets the keyboard cover it, so the bar is simply hidden while one is up —
    // `Offstage` rather than dropping it from the tree, so the native bar isn't
    // torn down and re-measured on every keystroke session.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    // Only the two calendar tabs compact the bar, and only while one of them
    // is the tab on screen.
    final nav = ref.watch(navBarProvider);
    final compact = nav.compact && _compactingTabs.contains(_index);
    return Scaffold(
      body: Stack(
        children: [
          FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: IndexedStack(index: _index, children: _buildScreens()),
            ),
          ),
          // Both bars float over the content rather than taking layout space —
          // the native bar's glass has to have the screen behind it to refract,
          // exactly like the pill's. Screens leave room for whichever one is up
          // with `navContentInset`.
          Positioned.fill(
            child: _NavLayer(
              index: _index,
              compact: compact,
              barHeight: nav.barHeight,
              keyboardOpen: keyboardOpen,
              onTap: _navigateTo,
              onExpand: _expandNav,
              onBarHeight: ref.read(navBarProvider.notifier).setBarHeight,
            ),
          ),
        ],
      ),
    );
  }
}

/// The bottom nav and its compacted stand-in, and the animation between them.
///
/// They are two separate children sliding and fading past each other, not one
/// morphing control: the iOS bar is a `UITabBar` platform view, so there is no
/// way to reshape it into a circle. What sells the collapse instead is that
/// everything moves along one axis — the bar drifts left as it goes, the
/// circle arrives from the left, and both sit on the same centre line — so it
/// reads as the bar drawing itself in rather than one control blinking out and
/// another blinking on.
class _NavLayer extends StatefulWidget {
  final int index;
  final bool compact;

  /// What UIKit measured the bar at, from [navBarProvider] — see
  /// [navRowBottom]. Reported back up through [onBarHeight] rather than kept
  /// here, because Kalender's "Heute" button needs the same number.
  final double? barHeight;
  final bool keyboardOpen;
  final ValueChanged<int> onTap;
  final VoidCallback onExpand;
  final ValueChanged<double> onBarHeight;

  const _NavLayer({
    required this.index,
    required this.compact,
    required this.barHeight,
    required this.keyboardOpen,
    required this.onTap,
    required this.onExpand,
    required this.onBarHeight,
  });

  @override
  State<_NavLayer> createState() => _NavLayerState();
}

class _NavLayerState extends State<_NavLayer> with SingleTickerProviderStateMixin {
  /// Slower than the tab cross-fade and eased at both ends. This one runs
  /// under the user's finger while they are reading, so it has to feel like
  /// the bar getting out of the way; anything quicker reads as a glitch.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: kNavSwapDuration,
    value: widget.compact ? 1 : 0,
  );
  late final Animation<double> _t = CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic);

  @override
  void didUpdateWidget(_NavLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.compact != oldWidget.compact) {
      widget.compact ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final native = useNativeTabBar;
    final barBottom = native ? nativeTabBarBottomInset(context) : 22.0;

    return Offstage(
      offstage: widget.keyboardOpen,
      // A bare `Stack` over the whole screen takes no hits of its own, so the
      // content underneath stays tappable everywhere the two shapes aren't.
      child: Stack(
        children: [
          if (native)
            Positioned(
              left: 0,
              right: 0,
              bottom: barBottom,
              // UIKit decides how wide the bar is (a capsule on iOS 26,
              // narrower than the screen), so it's centered rather than
              // stretched.
              child: _NavShape(
                t: _t,
                compactShape: false,
                child: Center(
                  child: NativeTabBar(index: widget.index, onTap: widget.onTap, onHeight: widget.onBarHeight),
                ),
              ),
            )
          else
            Positioned(
              left: 14,
              right: 14,
              bottom: barBottom,
              child: _NavShape(
                t: _t,
                compactShape: false,
                child: AppBottomNav(index: widget.index, onTap: widget.onTap),
              ),
            ),
          Positioned(
            left: native ? AppSpacing.screenPad : 14,
            // The circle hangs off the bar's own centre line, so the collapse
            // stays strictly horizontal.
            bottom: navRowBottom(context, barHeight: widget.barHeight),
            child: _NavShape(
              t: _t,
              compactShape: true,
              child: CompactNavButton(icon: navTabs[widget.index].compactIcon, onTap: widget.onExpand),
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the two nav shapes, faded and drifted by the swap animation (0 = the
/// full bar, 1 = the compacted circle).
///
/// The two fades cross with only a sliver of overlap: enough that there is
/// never a frame with neither shape on screen, little enough that two glass
/// surfaces are never both at a readable opacity — glass over glass at half
/// opacity is muddy, and near the left edge is exactly where that would show.
///
/// Going offstage at zero opacity is load-bearing rather than an optimisation.
/// Both shapes are iOS platform views — the `UITabBar` itself, and the real
/// `UIGlassEffect` behind [CompactNavButton] — and a platform view left at zero
/// opacity is still a UIKit view composited into the scene, sitting over both
/// the pixels and the touches behind it. `Offstage` and not removal, so the
/// native bar keeps its measured geometry and its method channel across a swap
/// instead of being torn down and re-measured.
class _NavShape extends AnimatedWidget {
  final bool compactShape;
  final Widget child;

  const _NavShape({required Animation<double> t, required this.compactShape, required this.child}) : super(listenable: t);

  double get _progress => (listenable as Animation<double>).value;

  /// How far each shape travels along the one axis the collapse moves on.
  /// Small on purpose: the bar only has to *start* leaving for the eye to read
  /// direction, and a big throw would put it under the circle.
  static const _barDrift = 24.0;
  static const _buttonDrift = 16.0;

  /// Fraction of the swap each shape's fade takes. Anything over 0.5 is the
  /// overlap between them.
  static const _crossover = 0.575;

  @override
  Widget build(BuildContext context) {
    final p = _progress;
    final opacity = compactShape
        ? ((p - (1 - _crossover)) / _crossover).clamp(0.0, 1.0)
        : ((_crossover - p) / _crossover).clamp(0.0, 1.0);
    // Both drift left-to-right along the same line: the bar leaves to the
    // left, the circle comes in from the left behind it.
    final dx = compactShape ? -_buttonDrift * (1 - p) : -_barDrift * p;
    return Offstage(
      offstage: opacity == 0,
      // Nothing is tappable mid-swap, so a tap that lands as the shapes cross
      // can't hit the one that is on its way out.
      child: IgnorePointer(
        ignoring: opacity < 1,
        child: Transform.translate(
          offset: Offset(dx, 0),
          child: Opacity(opacity: opacity, child: child),
        ),
      ),
    );
  }
}
