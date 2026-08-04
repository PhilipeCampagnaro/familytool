import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/board_streak_cache.dart';
import '../services/calendar_cache.dart';
import '../services/supabase.dart';
import '../l10n/l10n.dart';

/// Where the app is in the sign-in flow. Kept separate from "is there a
/// session" because two of these states have a session of *some* kind and
/// still must not show the app shell.
enum AuthStatus {
  /// Still restoring a stored session from disk — show nothing rather than
  /// flashing the login screen at a user who is already signed in.
  unknown,
  signedOut,

  /// Registered, but the confirmation link has not been clicked yet. Supabase
  /// returns a user with no session in this case.
  awaitingConfirmation,
  signedIn,
}

class AuthScreenState {
  final AuthStatus status;
  final String? userId;
  final String? email;

  /// German, and safe to render verbatim — every message set here is written
  /// for the user, not copied from a Postgres or GoTrue error.
  final String? error;

  final bool busy;

  const AuthScreenState({
    this.status = AuthStatus.unknown,
    this.userId,
    this.email,
    this.error,
    this.busy = false,
  });

  AuthScreenState copyWith({
    AuthStatus? status,
    String? userId,
    String? email,
    String? error,
    bool? busy,
    bool clearError = false,
  }) {
    return AuthScreenState(
      status: status ?? this.status,
      userId: userId ?? this.userId,
      email: email ?? this.email,
      error: clearError ? null : (error ?? this.error),
      busy: busy ?? this.busy,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthScreenState> {
  AuthNotifier() : super(const AuthScreenState()) {
    _listen();
  }

  void _listen() {
    final auth = AporahSupabase.client.auth;

    // The restored session is already available synchronously by the time
    // Supabase.initialize() has returned, so seed from it before subscribing —
    // otherwise the first frame renders `unknown` and only corrects itself once
    // the stream emits.
    _apply(auth.currentSession);

    auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      _apply(data.session);
    });
  }

  void _apply(Session? session) {
    if (session == null) {
      // Don't clobber `awaitingConfirmation`: signUp with confirmation on
      // yields a user and no session, which is not the same as being signed
      // out, and the screen needs to keep saying "check your mail".
      if (state.status == AuthStatus.awaitingConfirmation) return;
      state = state.copyWith(status: AuthStatus.signedOut, userId: null);
      return;
    }
    state = state.copyWith(
      status: AuthStatus.signedIn,
      userId: session.user.id,
      email: session.user.email,
      clearError: true,
    );
  }

  /// Registers a new account. The database does the rest: `handle_new_user`
  /// creates the profile, a household named `Familie <Name>`, and an admin
  /// membership — all in the same transaction as the user row, so there is no
  /// moment where a signed-in user has no household.
  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final name = displayName.trim();
    if (name.isEmpty) {
      state = state.copyWith(error: L.s.pleaseEnterName);
      return;
    }

    state = state.copyWith(busy: true, clearError: true);
    try {
      final res = await AporahSupabase.client.auth.signUp(
        email: email.trim(),
        password: password,
        // Read by handle_new_user to name the profile and the household.
        data: {'display_name': name},
      );

      if (!mounted) return;
      if (res.session == null) {
        state = state.copyWith(
          status: AuthStatus.awaitingConfirmation,
          email: email.trim(),
          busy: false,
        );
      } else {
        state = state.copyWith(busy: false);
      }
    } on AuthException catch (e) {
      if (mounted) state = state.copyWith(busy: false, error: _german(e));
    } catch (_) {
      if (mounted) {
        state = state.copyWith(busy: false, error: L.s.noConnectionTryAgain);
      }
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      await AporahSupabase.client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      if (mounted) state = state.copyWith(busy: false);
    } on AuthException catch (e) {
      if (mounted) state = state.copyWith(busy: false, error: _german(e));
    } catch (_) {
      if (mounted) {
        state = state.copyWith(busy: false, error: L.s.noConnectionTryAgain);
      }
    }
  }

  Future<void> resetPassword(String email) async {
    final address = email.trim();
    if (address.isEmpty) {
      state = state.copyWith(error: L.s.pleaseEnterEmailFirst);
      return;
    }
    state = state.copyWith(busy: true, clearError: true);
    try {
      await AporahSupabase.client.auth.resetPasswordForEmail(address);
      if (mounted) {
        state = state.copyWith(busy: false, error: L.s.resetMailSent);
      }
    } on AuthException catch (e) {
      if (mounted) state = state.copyWith(busy: false, error: _german(e));
    }
  }

  Future<void> signOut() async {
    // The calendar cache is the one place this app keeps event bodies at rest.
    // Signing out has to take it with it, or the next person to open Aporah on
    // this phone finds the last household's appointments in a file. The Board's
    // day ledger goes the same way — it holds only counts, but how busy the last
    // household's fortnight was is still theirs.
    await CalendarCache().clear();
    await BoardStreakCache().clear();
    await AporahSupabase.client.auth.signOut();
    if (mounted) state = const AuthScreenState(status: AuthStatus.signedOut);
  }

  /// Back to the login form from the "check your mail" screen.
  void backToSignIn() => state = const AuthScreenState(status: AuthStatus.signedOut);

  void clearError() => state = state.copyWith(clearError: true);

  /// GoTrue's messages are English and occasionally mention internals. The
  /// cases a real person actually hits get German copy; anything unrecognised
  /// falls back to something honest rather than a guess.
  String _german(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login credentials')) {
      return L.s.wrongCredentials;
    }
    if (msg.contains('email not confirmed')) {
      return L.s.confirmEmailFirst;
    }
    if (msg.contains('already registered') || msg.contains('already been registered')) {
      return L.s.accountExists;
    }
    if (msg.contains('password') && msg.contains('least')) {
      return L.s.passwordTooShort;
    }
    if (msg.contains('pwned') || msg.contains('compromised')) {
      return L.s.passwordLeaked;
    }
    if (msg.contains('rate limit') || msg.contains('too many')) {
      return L.s.tooManyAttempts;
    }
    if (msg.contains('invalid') && msg.contains('email')) {
      return L.s.emailLooksInvalid;
    }
    return L.s.signInFailed;
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthScreenState>((ref) => AuthNotifier());

/// The signed-in user's id, or null. Convenience for the many places that need
/// "is this mine?" without caring about the rest of the auth state.
final currentUserIdProvider = Provider<String?>((ref) => ref.watch(authProvider).userId);
