import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/l10n.dart';

// `PendingInvite` moved to `family_state.dart` and became a real
// `family_invites` row — with an id to revoke it by and a `FamilyRole` instead
// of the `isChild` bool, which could not express "Admin".

// Roles live in `family_state.dart` as `FamilyRole`, spelled exactly as the
// `public.member_role` enum spells them. This file used to declare its own
// three-value copy whose third value was `child` — which the database has no
// value for, so every attempt to save a child's role would have been rejected.

/// The interface languages. `name` is the locale code (`'de'` / `'en'` / `'pt'`
/// / `'es'`) that `AporahApp` hands to both `L.use` and `MaterialApp.locale`,
/// and the string this preference is persisted as — don't rename a value
/// without a migration. Adding one is additive: `_load` already resolves a
/// stored name against `AppLanguage.values` and falls back to German, so a
/// downgrade past a language finds an unknown name rather than a crash.
enum AppLanguage { de, en, pt, es }

extension AppLanguageLabel on AppLanguage {
  /// Each language named in itself, not translated: a picker that renamed
  /// "Deutsch" to "German" would be unreadable to the person looking for it.
  /// The names come through `L.s` like everything else, so the compiler still
  /// refuses a language that forgot one — they simply read the same in all four.
  String get label => switch (this) {
    AppLanguage.de => L.s.languageGerman,
    AppLanguage.en => L.s.languageEnglish,
    AppLanguage.pt => L.s.languagePortuguese,
    AppLanguage.es => L.s.languageSpanish,
  };

  /// The region under the name — this one *does* follow the interface
  /// language, since it is a description rather than the language's own name.
  String get nativeSubtitle => switch (this) {
    AppLanguage.de => L.s.languageGermanRegion,
    AppLanguage.en => L.s.languageEnglishRegion,
    AppLanguage.pt => L.s.languagePortugueseRegion,
    AppLanguage.es => L.s.languageSpanishRegion,
  };
}

class SettingsScreenState {
  final String name;
  final int avatarTone;
  final bool darkMode;
  final AppLanguage language;
  const SettingsScreenState({
    this.name = '',
    this.avatarTone = 4,
    this.darkMode = false,
    this.language = AppLanguage.de,
  });

  /// What Settings shows where a name would go. [name] stays genuinely empty
  /// until the user sets one or Supabase auth supplies it — this is a prompt,
  /// not a stand-in identity.
  String get displayName => name.trim().isEmpty ? L.s.setUpProfile : name;

  SettingsScreenState copyWith({String? name, int? avatarTone, bool? darkMode, AppLanguage? language}) {
    return SettingsScreenState(
      name: name ?? this.name,
      avatarTone: avatarTone ?? this.avatarTone,
      darkMode: darkMode ?? this.darkMode,
      language: language ?? this.language,
    );
  }
}

const _prefsDarkModeKey = 'settings_dark_mode';
const _prefsLanguageKey = 'settings_language';

/// Only [SettingsScreenState.darkMode] and [SettingsScreenState.language] live
/// here now. The roster, the roles and the invitations moved to
/// `family_state.dart`, where they are rows rather than session-local mock data
/// — a role that only this device believes in is worse than no role at all.
/// The language a fresh install opens in: **the phone's, not the place's.**
///
/// Walks the phone's own ordered list of preferred languages and takes the
/// first one the app speaks, so an iPhone set to French-then-Portuguese opens
/// in Portuguese. Location was considered and is the wrong signal: it says
/// where a family is, not what it reads — a Brazilian household in Munich
/// reads Portuguese — and asking for it would make a location prompt the first
/// thing the app says, before the sign-in page.
///
/// **English when nothing matches**, as the most widely read second language.
/// That is only the *first-launch* fallback; `stringsFor` still falls back to
/// German for a stored code it does not recognise, which is a downgrade guard,
/// not a choice of language.
AppLanguage deviceLanguage() {
  for (final locale in PlatformDispatcher.instance.locales) {
    for (final language in AppLanguage.values) {
      if (language.name == locale.languageCode) return language;
    }
  }
  return AppLanguage.en;
}

class SettingsNotifier extends StateNotifier<SettingsScreenState> {
  /// Seeded with the phone's language synchronously, not after `_load`: the
  /// sign-in page is the first thing a new user sees, and it would otherwise
  /// draw one frame in the default language before switching.
  SettingsNotifier() : super(SettingsScreenState(language: deviceLanguage())) {
    _load();
  }

  /// Whether the user picked a language in Settings. Until they do, the app
  /// follows the phone, and nothing is written — otherwise flipping dark mode
  /// would quietly freeze today's phone language as a choice nobody made.
  bool _languageChosen = false;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final darkMode = prefs.getBool(_prefsDarkModeKey) ?? false;
      final languageName = prefs.getString(_prefsLanguageKey);
      final stored = AppLanguage.values.where((l) => l.name == languageName).firstOrNull;
      _languageChosen = stored != null;
      final language = stored ?? deviceLanguage();
      if (!mounted) return;
      state = state.copyWith(darkMode: darkMode, language: language);
    } catch (_) {
      // No local storage available this session — keep running in-memory-only.
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsDarkModeKey, state.darkMode);
      if (_languageChosen) await prefs.setString(_prefsLanguageKey, state.language.name);
    } catch (_) {
      // Same as above — persistence is best-effort.
    }
  }

  void setName(String name) => state = state.copyWith(name: name);

  void setAvatarTone(int tone) => state = state.copyWith(avatarTone: tone);

  void setDarkMode(bool value) {
    state = state.copyWith(darkMode: value);
    _persist();
  }

  void setLanguage(AppLanguage language) {
    _languageChosen = true;
    state = state.copyWith(language: language);
    _persist();
  }

  // setMemberRole / addInvite / hideMember are gone. All three wrote to
  // session-local maps that no other device and no policy ever saw — a "role"
  // this app believed in and the database did not. They live on
  // `HouseholdNotifier` now, as `setRole`, `inviteMember` and `removeMember`,
  // against the real rows.
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsScreenState>(
  (ref) => SettingsNotifier(),
);
