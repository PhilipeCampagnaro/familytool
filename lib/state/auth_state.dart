import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/calendar_cache.dart';
import '../services/spend_intent.dart';
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

  /// A code is on its way to [AuthScreenState.email] and nobody has typed it
  /// in yet. There is no session, and there must be none: this is not
  /// "signed out", because the screen has to keep asking for the code.
  awaitingCode,

  /// The code was right and there *is* a session — this is signed in in every
  /// sense but the one that matters here: the screen that took the code is
  /// still folding its six boxes into a check, and swapping the shell in under
  /// it would cut that off mid-frame. It lasts [codeAcceptedHold] and no
  /// longer, and it is a separate state rather than a flag so that the one
  /// place that decides what to render — `_RootGate` — keeps deciding it from
  /// the status alone.
  codeAccepted,
  signedIn,
}

/// How long [AuthStatus.codeAccepted] lasts: the code screen's 1.2s of boxes
/// merging into the app's own drawn check, and then a beat of finished mark
/// before the app arrives — a confirmation swapped out as it lands is a
/// confirmation nobody read.
const codeAcceptedHold = Duration(milliseconds: 1600);

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
      // Don't clobber `awaitingCode`: asking for a code yields no session,
      // which is not the same as being signed out, and the screen needs to
      // keep asking for it.
      if (state.status == AuthStatus.awaitingCode) return;
      state = state.copyWith(status: AuthStatus.signedOut, userId: null);
      return;
    }
    // `verifyOTP` tells its subscribers before it returns, so this runs first
    // and would hand the shell the frame the celebration was about to use.
    // Park in [AuthStatus.codeAccepted] instead and let [verifyCode]'s hold
    // release it — with the user id already set, so `familyProvider` can start
    // fetching the household underneath the animation rather than after it.
    final celebrating = _verifying || state.status == AuthStatus.codeAccepted;
    state = state.copyWith(
      status: celebrating ? AuthStatus.codeAccepted : AuthStatus.signedIn,
      userId: session.user.id,
      email: session.user.email,
      clearError: true,
    );
  }

  /// True from the moment a code is sent to be checked until the answer is in,
  /// so [_apply] knows the session arriving mid-call is this one.
  bool _verifying = false;

  /// Sign-in has no password. The address gets a one-time code by mail, and
  /// typing it in is what signs the person in — so registering, confirming the
  /// address and signing in are the same two steps, and there is nothing to
  /// forget, reset or leak.
  ///
  /// A [displayName] means "create the account if there is none". The database
  /// does the rest: `handle_new_user` creates the profile, a household named
  /// `Familie <Name>`, and an admin membership — all in the same transaction as
  /// the user row, so there is no moment where a signed-in user has no
  /// household. Without one, an unknown address is refused rather than quietly
  /// becoming a second household for somebody who mistyped theirs.
  ///
  /// A code, not a link: a link opens in whichever browser the mail app picks,
  /// often on the laptop rather than the phone the app is on.
  Future<void> requestCode({required String email, String? displayName}) async {
    final address = email.trim();
    final name = displayName?.trim();
    if (name != null && name.isEmpty) {
      state = state.copyWith(error: L.s.pleaseEnterName);
      return;
    }
    if (address.isEmpty) {
      state = state.copyWith(error: L.s.pleaseEnterEmailFirst);
      return;
    }
    _pendingName = name;

    state = state.copyWith(busy: true, clearError: true);
    if (await _sendCode(address) && mounted) {
      state = state.copyWith(status: AuthStatus.awaitingCode, email: address, busy: false);
    }
  }

  /// Sends another code to the address already on screen. Returns whether one
  /// went out, so the screen only restarts its countdown when it did.
  Future<bool> resendCode() async {
    final address = state.email;
    if (address == null) return false;
    state = state.copyWith(busy: true, clearError: true);
    final sent = await _sendCode(address);
    if (sent && mounted) state = state.copyWith(busy: false);
    return sent;
  }

  /// The one name [requestCode] was asked to register with, kept for
  /// [resendCode]. Supabase only reads it when it creates the user.
  String? _pendingName;

  Future<bool> _sendCode(String address) async {
    final name = _pendingName;
    try {
      await AporahSupabase.client.auth.signInWithOtp(
        email: address,
        shouldCreateUser: name != null,
        // `display_name` names the profile and the household in
        // handle_new_user; `lang` lets the mail templates pick the language,
        // since a template has no other way to know it.
        data: name == null ? null : {'display_name': name, 'lang': L.s.localeCode},
      );
      return true;
    } on AuthException catch (e) {
      if (mounted) state = state.copyWith(busy: false, error: _message(e));
    } catch (_) {
      if (mounted) state = state.copyWith(busy: false, error: L.s.noConnectionTryAgain);
    }
    return false;
  }

  /// Checks the typed code. A right one produces a session, which would put
  /// the app on screen immediately — so it lands in [AuthStatus.codeAccepted]
  /// and stays there for [codeAcceptedHold], which is the screen's one chance
  /// to say yes before it goes.
  Future<void> verifyCode(String code) async {
    final address = state.email;
    // Pasted from a mail, a code arrives with spaces or a line break around it.
    final token = code.replaceAll(RegExp(r'\s'), '');
    if (address == null || token.isEmpty) return;

    state = state.copyWith(busy: true, clearError: true);
    _verifying = true;
    try {
      await AporahSupabase.client.auth.verifyOTP(email: address, token: token, type: OtpType.email);
      _verifying = false;
      if (!mounted) return;
      final session = AporahSupabase.client.auth.currentSession;
      state = state.copyWith(
        status: AuthStatus.codeAccepted,
        userId: session?.user.id,
        busy: false,
        clearError: true,
      );
      await Future.delayed(codeAcceptedHold);
      // Anything else that moved in the meantime — a sign-out, a session that
      // died — wins: only a still-celebrating screen is released here.
      if (mounted && state.status == AuthStatus.codeAccepted) {
        state = state.copyWith(status: AuthStatus.signedIn);
      }
    } on AuthException catch (e) {
      _verifying = false;
      if (mounted) state = state.copyWith(busy: false, error: _message(e));
    } catch (_) {
      _verifying = false;
      if (mounted) state = state.copyWith(busy: false, error: L.s.noConnectionTryAgain);
    }
  }

  /// **The status flips on the tap, before anything is awaited.** Every await
  /// in here used to come first, so the app stayed on screen — with nobody
  /// signed in — for a file delete and a network round trip, and the login page
  /// arrived afterwards as if something else had happened. This is not pretending
  /// either: gotrue drops the local session and tells its subscribers *before* it
  /// ever reaches the network, so the session is already gone by the time the
  /// revoke below is sent.
  Future<void> signOut() async {
    state = const AuthScreenState(status: AuthStatus.signedOut);

    // The calendar cache is the one place this app keeps event bodies at rest.
    // Signing out has to take it with it, or the next person to open Aporah on
    // this phone finds the last household's appointments in a file.
    //
    // The Board's day ledger used to be wiped here too. There is no longer one:
    // the tracker record is `public.tracker_checks` and goes when the session
    // does, which also means both parents finally see the same grid instead of
    // whatever their own phone happened to witness.
    await CalendarCache().clear();

    // **And the capture credential goes with it**, for the same reason and one
    // more. A wallet token lives in the Keychain, not in the session, and the
    // thing that reads it — an App Intent on a locked phone, or Android's
    // notification listener — never asks whether anybody is signed in. Left
    // behind, this phone would go on filing its owner's payments into a
    // household nobody here belongs to any more, under a name the person
    // holding it cannot see.
    //
    // The server row is deliberately *not* revoked: signing out is not the same
    // as giving a phone up, and the row is what makes signing back in and
    // pressing "Aktivieren" rotate the same enrolment rather than add a second
    // one beside it. Until that tap, nothing is captured — which the capture
    // page says plainly rather than pretending.
    await const SpendIntents().clearToken();
    try {
      await AporahSupabase.client.auth.signOut();
    } catch (_) {
      // A revoke that never reached the server leaves the refresh token alive
      // until it expires, and there is nothing the user can do about that from
      // a screen they have already left. The session on this phone is gone
      // either way, which is what they asked for.
    }
  }

  /// Back to the address form from the code screen, to fix a typo in it.
  void changeEmail() => state = const AuthScreenState(status: AuthStatus.signedOut);

  void clearError() => state = state.copyWith(clearError: true);

  /// GoTrue's messages are English and occasionally mention internals. The
  /// cases a real person actually hits get their own copy; anything
  /// unrecognised falls back to something honest rather than a guess.
  String _message(AuthException e) {
    final code = e.code ?? '';
    final msg = e.message.toLowerCase();
    if (code == 'otp_expired' || (msg.contains('token') && (msg.contains('expired') || msg.contains('invalid')))) {
      return L.s.codeInvalid;
    }
    // `shouldCreateUser: false` for an address nobody registered.
    if (code == 'otp_disabled' || msg.contains('signups not allowed')) {
      return L.s.noAccountForEmail;
    }
    // Asking for a second code inside the minute GoTrue enforces answers "For
    // security purposes, you can only request this after N seconds".
    if (code.startsWith('over_') || msg.contains('rate limit') || msg.contains('too many') ||
        msg.contains('security purposes')) {
      return L.s.tooManyAttempts;
    }
    if (code == 'email_address_invalid' || (msg.contains('invalid') && msg.contains('email'))) {
      return L.s.emailLooksInvalid;
    }
    return L.s.signInFailed;
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthScreenState>((ref) => AuthNotifier());

/// The signed-in user's id, or null. Convenience for the many places that need
/// "is this mine?" without caring about the rest of the auth state.
final currentUserIdProvider = Provider<String?>((ref) => ref.watch(authProvider).userId);
