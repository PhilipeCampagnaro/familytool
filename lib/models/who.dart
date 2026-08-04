import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../l10n/l10n.dart';
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

  /// The members behind a `custom` item, drawn as an overlapping stack instead
  /// of the single [bg]/[fg]/[icon] circle. Empty for every other badge, which
  /// is what `WhoAvatars` switches on.
  final List<FamilyMember> stack;

  const WhoMeta({
    required this.label,
    required this.bg,
    required this.fg,
    this.icon,
    this.initials,
    this.stack = const [],
  });
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
///
/// [sharedWith] is the item's `*_shares` rows. Like the picker's avatar row it
/// names the *others* an item is shared with and leaves the owner implicit —
/// the badge has room for a stack, not for the sentence that nuance needs.
WhoMeta whoBadge({
  String? assigneeId,
  required ItemVisibility visibility,
  required List<FamilyMember> members,
  List<String> sharedWith = const [],
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
    return WhoMeta(label: L.s.unknown, bg: AppColors.alleBg, fg: AppColors.muted, icon: LucideIcons.userRound);
  }

  if (visibility == ItemVisibility.custom) {
    // Walked in roster order rather than in share-row order, so two items shared
    // with the same people always draw the same stack. Members who have left the
    // household drop out here, exactly as their share rows already have.
    final shared = [
      for (final m in members)
        if (sharedWith.contains(m.id)) m,
    ];
    if (shared.isNotEmpty) {
      return WhoMeta(
        // Two names fit a task row; beyond that the count says more than a list
        // ellipsised mid-name would.
        label: shared.length <= 2
            ? L.s.joinNames([for (final m in shared) m.name])
            : L.s.peopleCount(shared.length),
        bg: AppColors.alleBg,
        fg: AppColors.alleFg,
        icon: LucideIcons.userRoundCheck,
        stack: shared,
      );
    }
    // Nobody resolved — a stale share list, or a guest who cannot see the
    // roster. Falls through to the generic chip below rather than claiming the
    // item is shared with no one, which would read as "Nur ich".
  }

  return switch (visibility) {
    ItemVisibility.private =>
      WhoMeta(label: L.s.onlyMe, bg: AppColors.nurIchBg, fg: AppColors.nurIchFg, icon: LucideIcons.lock),
    ItemVisibility.custom =>
      WhoMeta(label: L.s.selected, bg: AppColors.alleBg, fg: AppColors.alleFg, icon: LucideIcons.userRoundCheck),
    ItemVisibility.family =>
      WhoMeta(label: L.s.everyone, bg: AppColors.alleBg, fg: AppColors.alleFg, icon: LucideIcons.users),
  };
}
