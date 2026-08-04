import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../state/settings_state.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/settings_chrome.dart';
import '../../theme/tokens.dart';
import '../../l10n/l10n.dart';

/// The interface language. One row per [AppLanguage], the active one ticked.
class LanguagePage extends ConsumerWidget {
  const LanguagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(settingsProvider).language;

    return SettingsDetailPage(
      icon: LucideIcons.languages,
      title: L.s.language,
      description: L.s.languagePageDesc,
      estimatedHeroHeight: 190,
      children: [
        SectionCard(
          radius: AppRadii.card,
          children: dividedRows(
            inset: true,
            [
              for (final language in AppLanguage.values)
                SettingsRow(
                  title: language.label,
                  subtitle: language.nativeSubtitle,
                  trailing: language == selected
                      ? Icon(LucideIcons.check, size: 18, color: Theme.of(context).colorScheme.primary)
                      : const SizedBox.shrink(),
                  onTap: () => ref.read(settingsProvider.notifier).setLanguage(language),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
