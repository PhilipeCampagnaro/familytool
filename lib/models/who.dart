import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/tokens.dart';
import 'visibility.dart';

/// The "Für wen?" assignment: the whole family, private, or one member.
class FamilyMember {
  final String id;
  final String name;
  final String initials;

  /// Index into [AppTones.list], **not** a resolved [Tone] — the same
  /// convention `StorageBox.tone` and `CalendarEvent.ownerTone` already use.
  /// Storing the pair itself would freeze a member's avatar in whichever
  /// palette happened to be installed when this const was canonicalised.
  final int tone;

  const FamilyMember({
    required this.id,
    required this.name,
    required this.initials,
    required this.tone,
  });

  /// The tone's colours in the palette that's installed *now*.
  Tone get toneColors => AppTones.list[tone];
}

/// The avatar-and-label badge an item wears: an assignee, or — with nobody
/// assigned — who the item is visible to.
class WhoMeta {
  final String label;
  final Color bg;
  final Color fg;
  final IconData? icon;
  final String? initials;

  const WhoMeta({required this.label, required this.bg, required this.fg, this.icon, this.initials});
}

/// One badge for the two independent questions an item now answers.
///
/// [assigneeId] wins when it is set: "Lea" says more than "Alle" does, and a
/// task assigned to somebody is the one a family scans the Board for. With
/// nobody assigned, the badge falls back to [visibility] — who may see it.
///
/// Replaces the old `whoMeta(String who)`, which read a single string that was
/// *either* an audience or an assignee and could never be both. [members] comes
/// from `householdMembersProvider`, so the roster is the live one rather than a
/// constant that no longer exists.
WhoMeta whoBadge({
  String? assigneeId,
  required ItemVisibility visibility,
  required List<FamilyMember> members,
}) {
  if (assigneeId != null) {
    for (final m in members) {
      if (m.id == assigneeId) {
        return WhoMeta(label: m.name, bg: m.toneColors.bg, fg: m.toneColors.fg, initials: m.initials);
      }
    }
    // Assigned to somebody who has left the household. Shown neutrally rather
    // than dropped, so the item doesn't silently lose its badge — and rather
    // than falling through to the visibility, which would read as a promise
    // ("Alle") that the row is not making.
    return WhoMeta(label: 'Unbekannt', bg: AppColors.alleBg, fg: AppColors.muted, icon: LucideIcons.userRound);
  }

  return switch (visibility) {
    ItemVisibility.private =>
      WhoMeta(label: 'Nur ich', bg: AppColors.nurIchBg, fg: AppColors.nurIchFg, icon: LucideIcons.lock),
    ItemVisibility.custom =>
      WhoMeta(label: 'Ausgewählte', bg: AppColors.alleBg, fg: AppColors.alleFg, icon: LucideIcons.userRoundCheck),
    ItemVisibility.family =>
      WhoMeta(label: 'Alle', bg: AppColors.alleBg, fg: AppColors.alleFg, icon: LucideIcons.users),
  };
}
