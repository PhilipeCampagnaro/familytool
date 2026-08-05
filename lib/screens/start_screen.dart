import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../state/auth_state.dart';
import '../state/family_state.dart';
import '../theme/tokens.dart';
import '../widgets/avatar.dart';
import 'settings_screen.dart';
import '../l10n/l10n.dart';

/// The "Home" tab has no design yet in the handoff — placeholder except for
/// the header's profile avatar, which is this app's entry point into
/// Settings (mirrors the old web app's "tap your avatar on the dashboard"
/// pattern; see CLAUDE.md's "Ported feature knowledge" -> Settings).
class StartScreen extends ConsumerWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(familyProvider).me(ref.watch(currentUserIdProvider));
    final tone = me == null ? null : AppTones.list[me.tone % AppTones.list.length];
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 8, AppSpacing.screenPad, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(L.s.navHome, style: AppText.screenTitle)),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen())),
                    // The signed-in user's own face — their picture where they
                    // have one, their initials on their tone otherwise. Neutral
                    // only until the roster has loaded: no name, no initials, no
                    // tone to borrow yet.
                    child: Avatar(
                      size: 40,
                      bg: tone?.bg ?? AppColors.surfaceAlt,
                      fg: tone?.fg ?? AppColors.muted,
                      initials: me?.initials,
                      icon: me == null ? LucideIcons.userRound : null,
                      fontSize: 14,
                      imageUrl: me?.avatarUrl,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(color: AppColors.surfaceAlt, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Icon(LucideIcons.home, size: 28, color: AppColors.muted),
                      ),
                      const SizedBox(height: 16),
                      Text(L.s.startNotDesigned, style: AppText.body.copyWith(color: AppColors.inkTertiary)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
