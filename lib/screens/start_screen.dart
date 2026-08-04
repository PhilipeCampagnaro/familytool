import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/tokens.dart';
import '../widgets/avatar.dart';
import 'settings_screen.dart';
import '../l10n/l10n.dart';

/// The "Home" tab has no design yet in the handoff — placeholder except for
/// the header's profile avatar, which is this app's entry point into
/// Settings (mirrors the old web app's "tap your avatar on the dashboard"
/// pattern; see CLAUDE.md's "Ported feature knowledge" -> Settings).
class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                    // Neutral until there is an account: no name, no initials,
                    // no tone to borrow. Supabase auth fills this in.
                    child: Avatar(
                      size: 40,
                      bg: AppColors.surfaceAlt,
                      fg: AppColors.muted,
                      icon: LucideIcons.userRound,
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
