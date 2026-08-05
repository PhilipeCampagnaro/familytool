import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/media_picker.dart';
import '../../state/auth_state.dart';
import '../../state/family_state.dart';
import '../../state/settings_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/anchored_menu.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/avatar.dart';
import '../../widgets/collapsing_header.dart';
import '../../widgets/glass.dart';
import '../../widgets/settings_chrome.dart';
import '../../l10n/l10n.dart';

/// The signed-in user's own profile — display name, picture, avatar colour, and
/// the role they hold, which is shown but never editable here: nobody promotes
/// themselves.
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => ProfilePageState();
}

class ProfilePageState extends ConsumerState<ProfilePage> {
  late final TextEditingController _nameController;

  final GlobalKey _avatarKey = GlobalKey();

  /// The picture that was just picked, drawn immediately while it uploads —
  /// see [Avatar.imageFile]. Cleared once the roster carries the real one.
  File? _uploading;

  static const _extraHeight = 84.0;

  @override
  void initState() {
    super.initState();
    // Seeded from the household's copy of the profile, which is what everyone
    // else sees, falling back to the local draft before the roster has loaded.
    final me = ref.read(familyProvider).me(ref.read(currentUserIdProvider));
    _nameController = TextEditingController(text: me?.name ?? ref.read(settingsProvider).name);
  }

  /// Puts the picked photo up straight away and saves it behind that.
  Future<void> _pickAvatar(AttachmentSource source) async {
    final picked = await pickAttachment(source, maxDimension: avatarMaxDimension);
    if (picked == null || !picked.isImage) return;

    final file = File(picked.path);
    setState(() => _uploading = file);
    final ok = await ref.read(familyProvider.notifier).setMyAvatar(file);
    if (!mounted) return;
    // Held for as long as this page is open, rather than handed back to the
    // signed URL the moment the upload lands: the file on disk *is* the
    // picture, and swapping to a URL that still has to be fetched would blink
    // the face back to initials for no gain. Dropped only when the upload
    // failed, so what's on screen is what's actually stored.
    if (!ok) setState(() => _uploading = null);
  }

  void _avatarMenu(HouseholdMember? me) {
    showAnchoredMenu(
      context: context,
      anchorKey: _avatarKey,
      items: [
        AnchoredMenuItem(
          label: L.s.photo,
          icon: LucideIcons.image,
          onSelected: () => _pickAvatar(AttachmentSource.photos),
        ),
        AnchoredMenuItem(
          label: L.s.camera,
          icon: LucideIcons.camera,
          onSelected: () => _pickAvatar(AttachmentSource.camera),
        ),
        if (me?.avatarPath != null || _uploading != null)
          AnchoredMenuItem(
            label: L.s.removePhoto,
            icon: LucideIcons.trash2,
            destructive: true,
            onSelected: () {
              setState(() => _uploading = null);
              ref.read(familyProvider.notifier).removeMyAvatar();
            },
          ),
      ],
    );
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

    // The field is the truth while this page is open — it is what will be
    // written on the way out. Reading the saved copy instead would leave the
    // hero, the bar title and the initials all describing the previous name
    // until the page was closed and reopened.
    final draft = _nameController.text.trim();
    final displayName = draft.isNotEmpty ? draft : (me?.name ?? state.displayName);

    // Derived with the same function the notifier saves and `handle_new_user`
    // mirrors, so the letters shown while typing are the letters stored.
    final initials = draft.isNotEmpty ? initialsOf(draft) : (me?.initials ?? '?');

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
                  // The avatar is the control, not a picture with a button next
                  // to it — it is already the biggest thing on the page and the
                  // one everybody reaches for. The badge is what says so.
                  GestureDetector(
                    key: _avatarKey,
                    onTap: () => _avatarMenu(me),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Avatar(
                          size: 64,
                          bg: tone.bg,
                          fg: tone.fg,
                          initials: initials,
                          fontSize: 21,
                          imageUrl: me?.avatarUrl,
                          imageFile: _uploading,
                        ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.hairline2),
                            ),
                            alignment: Alignment.center,
                            child: Icon(LucideIcons.camera, size: 12, color: AppColors.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
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
                            onChanged: (v) {
                              ref.read(settingsProvider.notifier).setName(v);
                              // The hero avatar, its initials and the collapsed
                              // bar title all read the field, so every
                              // keystroke has to redraw them.
                              setState(() {});
                            },
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
