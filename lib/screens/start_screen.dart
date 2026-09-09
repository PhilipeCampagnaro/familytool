import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/auth_state.dart';
import '../state/family_state.dart';
import '../theme/tokens.dart';
import '../widgets/avatar.dart';
import 'confirmation_lab.dart';
import 'settings_screen.dart';
import '../l10n/l10n.dart';
import '../theme/app_icons.dart';
import '../widgets/bottom_nav.dart';

/// The "Home" tab has no design yet in the handoff. Two things are on it: the
/// header's profile avatar, which is this app's entry point into Settings
/// (mirrors the old web app's "tap your avatar on the dashboard" pattern; see
/// CLAUDE.md's "Ported feature knowledge" -> Settings), and — because the space
/// is otherwise empty — the [ConfirmationLab], the bench every "that worked"
/// surface is put up on side by side while they are being made to agree. The
/// lab goes when Home gets its real content.
class StartScreen extends ConsumerWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(familyProvider).me(ref.watch(currentUserIdProvider));
    final tone = me == null ? null : AppTones.list[me.tone % AppTones.list.length];
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        // The nav bar floats over the content, so the bottom inset is the
        // scroll view's padding rather than the safe area's.
        bottom: false,
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
                      icon: me == null ? AppIcons.user : null,
                      fontSize: 14,
                      imageUrl: me?.avatarUrl,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(L.s.startNotDesigned, style: AppText.body.copyWith(color: AppColors.inkTertiary)),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(bottom: navContentInset(context)),
                  child: ConfirmationLab(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
