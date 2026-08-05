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
import 'state/family_state.dart';
import 'state/settings_state.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';
import 'widgets/bottom_nav.dart';
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
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      // Not `const`: a canonicalised instance would make the element below
      // identical across a theme flip, and the whole screen tree would be
      // skipped and keep painting the old palette.
      home: _RootGate(),
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

    if (family.household?.onboardingDone == false) return OnboardingScreen();
    return AppShell();
  }
}

/// Board is the primary designed tab; matches the handoff's default screen.
const _initialTab = 3;

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

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

/// Cross-fades + slides between tabs on every nav-bar tap instead of an
/// instant cut, while keeping each screen mounted in an [IndexedStack] so
/// per-tab scroll/expansion state survives switching away and back. The
/// controller runs a quick fade-out of the outgoing screen, swaps `_index`
/// at the midpoint, then fades/slides the new one in — since `IndexedStack`
/// only ever paints one child, this "out then in" sequence reads as a single
/// smooth transition without the cost of a true crossfade (both screens
/// visible at once), which `IndexedStack` can't do.
class _AppShellState extends State<AppShell> with SingleTickerProviderStateMixin {
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
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _navigateTo(int i) async {
    if (i == _index) return;
    await _controller.reverse();
    if (!mounted) return;
    setState(() => _index = i);
    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    // The `Scaffold` resizes its body around the keyboard so text fields stay
    // visible, which would otherwise carry the floating nav bar up with it and
    // park it on top of the keyboard. iOS keeps the tab bar at the bottom and
    // lets the keyboard cover it, so the bar is simply hidden while one is up —
    // `Offstage` rather than dropping it from the tree, so the native bar isn't
    // torn down and re-measured on every keystroke session.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
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
          if (useNativeTabBar)
            Positioned(
              left: 0,
              right: 0,
              bottom: nativeTabBarBottomInset(context),
              // UIKit decides how wide the bar is (a capsule on iOS 26,
              // narrower than the screen), so it's centered rather than
              // stretched.
              child: Offstage(
                offstage: keyboardOpen,
                child: Center(child: NativeTabBar(index: _index, onTap: _navigateTo)),
              ),
            )
          else
            Positioned(
              left: 14,
              right: 14,
              bottom: 22,
              child: Offstage(
                offstage: keyboardOpen,
                child: AppBottomNav(index: _index, onTap: _navigateTo),
              ),
            ),
        ],
      ),
    );
  }
}
