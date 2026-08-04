import 'package:supabase_flutter/supabase_flutter.dart';

/// The Supabase client, and the one place its credentials are configured.
///
/// Both values are overridable with `--dart-define`, so a fork or a staging
/// project needs no code change:
///
/// ```
/// flutter run --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…
/// ```
///
/// The defaults are the live project, because the publishable key is *not* a
/// secret — it ships inside every installed copy of the app by design, and RLS
/// is what actually protects the data (see docs/backend.md). Requiring a
/// `--dart-define` just to press Run would buy no security and cost every
/// `flutter run`.
///
/// **The `service_role` key must never appear here, or anywhere in `lib/`.**
/// It bypasses RLS entirely and lives only in Edge Function secrets.
class AporahSupabase {
  AporahSupabase._();

  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://uzhzrwakrtwbpuuupccu.supabase.co',
  );

  static const publishableKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_V2KTNFqatQrUep6YamB7vA_lsDYtFEb',
  );

  /// Called once from `main()` before `runApp`. Restores a stored session from
  /// disk, so a returning user is signed in before the first frame.
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: url,
      publishableKey: publishableKey,
      authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
    );
  }

  static SupabaseClient get client => Supabase.instance.client;

  /// The signed-in user's id, or null. Every content row the app writes is
  /// owned by this id — and the database re-checks that in each insert policy,
  /// so passing someone else's id here would be rejected, not honoured.
  static String? get userId => client.auth.currentUser?.id;
}
