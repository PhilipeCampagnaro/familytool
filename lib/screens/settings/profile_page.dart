import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../state/auth_state.dart';
import '../../state/family_state.dart';
import '../../state/settings_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/avatar.dart';
import '../../widgets/collapsing_header.dart';
import '../../widgets/glass.dart';
import '../../widgets/settings_chrome.dart';
import '../../l10n/l10n.dart';

/// The signed-in user's own profile — display name, avatar colour, and the
/// role they hold, which is shown but never editable here: nobody promotes
/// themselves.
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => ProfilePageState();
}

class ProfilePageState extends ConsumerState<ProfilePage> {
  late final TextEditingController _nameController;

  static const _extraHeight = 84.0;

  @override
  void initState() {
    super.initState();
    // Seeded from the household's copy of the profile, which is what everyone
    // else sees, falling back to the local draft before the roster has loaded.
    final me = ref.read(familyProvider).me(ref.read(currentUserIdProvider));
    _nameController = TextEditingController(text: me?.name ?? ref.read(settingsProvider).name);
  }

  @override
  void dispose() {
    // Written once, on the way out, rather than on every keystroke — a request
    // per character would be both wasteful and racy.
    _householdNotifier.saveMyProfile(displayName: _nameController.text);
    _nameController.dispose();
    super.dispose();
  }

  /// Captured while the widget is still mounted: `dispose` must not touch
  /// `ref`, and the save above deliberately outlives this page.
  late final HouseholdNotifier _householdNotifier = ref.read(familyProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(settingsProvider);
    final me = ref.watch(familyProvider).me(ref.watch(currentUserIdProvider));
    final displayName = me?.name ?? state.displayName;
    final tone = AppTones.list[me?.tone ?? state.avatarTone];
    final role = ref.watch(myRoleProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        // Hand-rolled rather than a [SettingsDetailPage]: the profile's own
        // avatar and name introduce the page better than a glyph and a
        // sentence, so the identity row *is* this page's hero.
        child: CollapsingHeaderScreen(
          titleRowBuilder: (context, t) => CollapsingScreenTitle(
            // Same rule as [SettingsDetailPage]: the bar names where you came
            // from until the identity row below it scrolls away.
            title: L.s.settingsTitle,
            collapsedTitle: displayName,
            t: t,
            expandedAlignment: Alignment.center,
            expandedFontSize: 17,
            leading: GlassIconButton(icon: LucideIcons.chevronLeft, onTap: () => Navigator.of(context).pop()),
            leadingWidth: 48,
            trailing: CloseSettingsButton(),
            trailingWidth: 48,
          ),
          estimatedExtraHeight: _extraHeight,
          extraPadding: const EdgeInsets.symmetric(horizontal: 20),
          extra: Column(
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  Avatar(size: 64, bg: tone.bg, fg: tone.fg, initials: me?.initials ?? initialsFromName(state.name), fontSize: 21),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.cardTitle),
                        const SizedBox(height: 2),
                        Text(role.label, style: AppText.body.copyWith(color: AppColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
          body: ScreenBodyPanel(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
              children: [
                SectionCard(
                  radius: AppRadii.card,
                  children: dividedRows(
                    inset: true,
                    [
                      FieldGroup(
                        label: L.s.displayName,
                        child: FieldBox(
                          child: TextField(
                            controller: _nameController,
                            style: AppText.searchInput,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              hintText: L.s.name,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (v) => ref.read(settingsProvider.notifier).setName(v),
                          ),
                        ),
                      ),
                      FieldGroup(
                        label: L.s.avatarColour,
                        child: Row(
                          children: [
                            for (var i = 0; i < AppTones.list.length; i++) ...[
                              _ToneSwatch(
                                tone: AppTones.list[i],
                                selected: i == (me?.tone ?? state.avatarTone),
                                onTap: () {
                                  ref.read(settingsProvider.notifier).setAvatarTone(i);
                                  ref.read(familyProvider.notifier).saveMyProfile(tone: i);
                                },
                              ),
                              if (i != AppTones.list.length - 1) const SizedBox(width: 12),
                            ],
                          ],
                        ),
                      ),
                      FieldGroup(
                        label: L.s.role,
                        hint: L.s.adminsManageFamily,
                        child: FieldBox(
                          child: Row(
                            children: [
                              Icon(LucideIcons.shieldCheck, size: 17, color: AppColors.muted),
                              const SizedBox(width: 10),
                              Text(role.label, style: AppText.searchInput),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToneSwatch extends StatelessWidget {
  final Tone tone;
  final bool selected;
  final VoidCallback onTap;

  const _ToneSwatch({required this.tone, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Selection is an outer ring rather than a border on the swatch itself:
    // several tones are pale enough that an inset border reads as a shadow.
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: selected ? AppColors.ink : Colors.transparent, width: 1.5),
        ),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: tone.bg, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
