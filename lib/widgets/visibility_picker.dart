import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/visibility.dart';
import '../models/who.dart';
import '../theme/tokens.dart';
import 'avatar.dart';

/// The "Für wen?" section of a create/edit sheet, writing the two things the
/// database actually has: `visibility` and the rows in `*_shares`.
///
/// It replaces the old single `who` string (`'all' | 'private' | <memberId>`),
/// which conflated *who does this* with *who may see it* — the hint text said so
/// out loud ("Zugewiesen an Lea — für alle sichtbar"). Here:
///
/// - **Alle** → `visibility = 'family'`, no share rows.
/// - **Nur ich** → `visibility = 'private'`, no share rows.
/// - **one or more members** → `visibility = 'custom'`, one `*_shares` row each.
///
/// The first two are mutually exclusive with each other and with the member
/// selection; deselecting the last member falls back to *Nur ich*, because
/// `custom` shared with nobody **is** private. The creator is always implicitly
/// included and therefore has no chip of their own — a row saying "shared with
/// myself" would be noise, and the owner branch of `can_read_list` covers it.
///
/// External sharing (guests, share links) is deliberately not in this picker:
/// mixing outsiders into the family avatar row would make a mis-tap leak
/// household data. See docs/backend.md.
class VisibilityPicker extends StatelessWidget {
  final ItemVisibility visibility;
  final Set<String> sharedWith;
  final void Function(ItemVisibility visibility, Set<String> sharedWith) onChanged;

  /// The live household roster (`householdMembersProvider`). The signed-in user
  /// is filtered out here rather than by the caller.
  final List<FamilyMember> members;

  final String? currentUserId;

  /// What the hint calls the thing — "die Liste", "die Box".
  final String noun;

  /// False for a guest looking at a list shared into their account. The
  /// composite foreign key on `list_shares` → `family_members` makes selecting
  /// somebody outside the owning household impossible *at the database level*,
  /// so offering the picker would produce a constraint error rather than a
  /// polite refusal.
  final bool allowMembers;

  final double avatarSize;

  const VisibilityPicker({
    super.key,
    required this.visibility,
    required this.sharedWith,
    required this.onChanged,
    required this.members,
    required this.noun,
    this.currentUserId,
    this.allowMembers = true,
    this.avatarSize = 48,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final others = [
      for (final m in members)
        if (m.id != currentUserId) m,
    ];
    final showMembers = allowMembers && others.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 9),
          child: Text('Für wen?', style: AppText.microLabel),
        ),
        SizedBox(
          height: avatarSize + 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            children: [
              PickerAvatarChip(
                label: 'Alle',
                bg: AppColors.alleBg,
                fg: AppColors.alleFg,
                icon: LucideIcons.users,
                selected: visibility == ItemVisibility.family,
                accent: accent,
                avatarSize: avatarSize,
                onTap: () => onChanged(ItemVisibility.family, const {}),
              ),
              const SizedBox(width: 9),
              PickerAvatarChip(
                label: 'Nur ich',
                bg: AppColors.nurIchBg,
                fg: AppColors.nurIchFg,
                icon: LucideIcons.lock,
                selected: visibility == ItemVisibility.private,
                accent: accent,
                avatarSize: avatarSize,
                onTap: () => onChanged(ItemVisibility.private, const {}),
              ),
              if (showMembers)
                for (final m in others) ...[
                  const SizedBox(width: 9),
                  PickerAvatarChip(
                    label: m.name,
                    bg: m.toneColors.bg,
                    fg: m.toneColors.fg,
                    initials: m.initials,
                    selected: visibility == ItemVisibility.custom && sharedWith.contains(m.id),
                    accent: accent,
                    avatarSize: avatarSize,
                    onTap: () => _toggleMember(m.id),
                  ),
                ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
          child: Text(_hint(others), style: AppText.label.copyWith(fontSize: 12)),
        ),
      ],
    );
  }

  void _toggleMember(String id) {
    // Coming from Alle or Nur ich, the selection starts empty — those two carry
    // no member list, so there is nothing to add to.
    final next = visibility == ItemVisibility.custom ? {...sharedWith} : <String>{};
    if (!next.remove(id)) next.add(id);
    if (next.isEmpty) {
      onChanged(ItemVisibility.private, const {});
      return;
    }
    onChanged(ItemVisibility.custom, next);
  }

  String _hint(List<FamilyMember> others) {
    switch (visibility) {
      case ItemVisibility.family:
        return 'Für die ganze Familie — alle können $noun sehen und bearbeiten.';
      case ItemVisibility.private:
        return 'Nur für dich sichtbar — niemand sonst sieht $noun.';
      case ItemVisibility.custom:
        final names = [
          for (final m in others)
            if (sharedWith.contains(m.id)) m.name,
        ];
        if (names.isEmpty) return 'Nur für dich sichtbar — niemand sonst sieht $noun.';
        return 'Nur du und ${_joinGerman(names)} sehen $noun.';
    }
  }

  /// "Lea", "Lea und Tom", "Lea, Tom und Max" — the Oxford comma is not a thing
  /// in German, so the last item is joined with "und" and nothing else.
  static String _joinGerman(List<String> names) {
    if (names.length == 1) return names.first;
    return '${names.sublist(0, names.length - 1).join(', ')} und ${names.last}';
  }
}

/// One avatar-over-label chip in the picker row: the ring thickens and takes the
/// accent colour when it's the selected one.
///
/// Lived in `who_picker.dart` while there were two pickers sharing it — the old
/// single-select `WhoPicker` over the `who` string, and this one. That string is
/// gone (see [whoBadge]), and with it the second picker, so the chip moved in
/// with its only remaining user.
class PickerAvatarChip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final IconData? icon;
  final String? initials;
  final bool selected;
  final Color accent;
  final double avatarSize;
  final VoidCallback onTap;

  const PickerAvatarChip({
    super.key,
    required this.label,
    required this.bg,
    required this.fg,
    required this.selected,
    required this.accent,
    required this.avatarSize,
    required this.onTap,
    this.icon,
    this.initials,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: avatarSize + 12,
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: selected ? accent.withValues(alpha: 1) : AppColors.hairline,
                    blurRadius: 0,
                    spreadRadius: selected ? 2.5 : 1,
                  ),
                ],
              ),
              child: Avatar(
                size: avatarSize,
                bg: selected ? bg : AppColors.surface,
                fg: selected ? fg : AppColors.muted,
                icon: icon,
                initials: initials,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? AppColors.ink : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
