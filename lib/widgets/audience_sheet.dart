import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/visibility.dart';
import '../models/who.dart';
import '../state/sharing_state.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import 'app_sheet.dart';
import 'avatar.dart';

/// Everybody who can see a container, as overlapping circles.
///
/// It replaces the anonymous people glyph that used to mark a shared list. That
/// glyph said *that* somebody outside was in and never *who*, which is the only
/// question a row like this makes anybody ask — and the answer was two screens
/// away, in the edit sheet, under a heading nobody had a reason to open.
///
/// The faces are the household's and the guests' in one line, because they are
/// one answer: these people can read this. The two groups are told apart in the
/// sheet behind it ([showAudienceSheet]), where there is room to say which is
/// which and how each got there.
class AudienceStack extends StatelessWidget {
  final Audience audience;

  /// Opens [showAudienceSheet]. Null on the overview shelf, where the row's own
  /// tap opens the list and a second target beside it made that a coin toss —
  /// the same rule [EventLinkChip] follows on a row.
  final VoidCallback? onTap;

  /// An invitation is out that nobody has used yet — somebody outside is on
  /// their way in and has no face to draw.
  ///
  /// It earns a circle of its own because the mark this stack replaced said
  /// "shared or invited", and a household of familiar faces alone would have
  /// quietly dropped the second half: a list shared five minutes ago, before
  /// anybody accepted, would look exactly like one that was never shared.
  final bool invitationOut;

  final double size;

  /// Past this the circles stop being distinguishable and start eating the row;
  /// the rest are counted in a trailing "+n" that opens the same sheet.
  static const maxFaces = 3;

  const AudienceStack({
    super.key,
    required this.audience,
    this.onTap,
    this.invitationOut = false,
    this.size = 22,
  });

  @override
  Widget build(BuildContext context) {
    final people = audience.all;
    if (people.isEmpty && !invitationOut) return const SizedBox.shrink();
    // At least one outsider stays in view wherever there is one. Roster order
    // alone would push every guest behind the "+n" on a household of four,
    // which is the one face the stack exists to show.
    final guestSlots = audience.guests.isEmpty
        ? 0
        : audience.guests.length.clamp(0, audience.household.isEmpty ? maxFaces : maxFaces - 1);
    final shown = [
      ...audience.household.take(maxFaces - guestSlots),
      ...audience.guests.take(guestSlots),
    ];
    final rest = people.length - shown.length;
    final fontSize = size * 0.42;

    final stack = AvatarStack(
      avatarSize: size,
      overlap: size * 0.34,
      avatars: [
        for (final m in shown)
          Avatar(
            size: size,
            bg: m.toneColors.bg,
            fg: m.toneColors.fg,
            initials: m.initials,
            fontSize: fontSize,
            imageUrl: m.imageUrl,
          ),
        if (rest > 0)
          Avatar(
            size: size,
            bg: AppColors.alleBg,
            fg: AppColors.alleFg,
            initials: '+$rest',
            fontSize: fontSize,
          ),
        if (invitationOut)
          Avatar(size: size, bg: AppColors.alleBg, fg: AppColors.muted, icon: AppIcons.link),
      ],
    );

    final labelled = Semantics(
      label: invitationOut ? L.s.sharedOutsideLabel : L.s.peopleCount(people.length),
      button: onTap != null,
      excludeSemantics: true,
      child: stack,
    );
    if (onTap == null) return labelled;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      // Room for a finger around circles that are 22px of ink — the padding is
      // the hit target, not a gap the caller has to budget for.
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8), child: labelled),
    );
  }
}

/// Where "Für wen?" was, on a container somebody outside the household is
/// holding.
///
/// A control that is simply missing teaches nothing — the reader came to the
/// sheet to change exactly that — so the space it left says why it is gone and
/// [howTo] says what lifts it. The lock is the app's, not the database's:
/// `visibility` and `guest_access` really are independent, and it was that
/// independence, met through a picker that could not see the guest, that took a
/// shared container away from the whole family in one tap.
class LockedVisibilityNote extends StatelessWidget {
  /// What the sentence calls the thing — "die Liste", "die Box".
  final String noun;

  /// How to lift the lock, where the reader can. **It differs per screen and
  /// that is not cosmetic**: a list keeps its guests on its own edit sheet, a
  /// box keeps them inside "Teilen", so one instruction would send half the
  /// readers to a place that has no such rows. Null where the reader may not
  /// remove anybody — a kid, whose list an admin shared.
  final String? howTo;

  const LockedVisibilityNote({super.key, required this.noun, this.howTo});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 9),
        child: Text(L.s.forWhom, style: AppText.microLabel),
      ),
      SectionCard(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: AppIcon(AppIcons.users, size: 17, color: AppColors.muted),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    L.s.visibilityLockedWhileShared(noun),
                    style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w400),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      if (howTo case final text?)
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 8, right: 4),
          child: Text(text, style: AppText.label.copyWith(fontSize: 12)),
        ),
    ],
  );
}

/// "Wer sieht die Liste?" — the household on one side, the people outside it on
/// the other, and a sentence saying why each group is in.
///
/// Read-only on purpose. Who in the household may see it is changed in the edit
/// sheet's "Für wen?", and who outside is let in or dropped is changed by
/// "Teilen" and the "Geteilt mit" rows below it; a third place that did either
/// would be a second set of controls over one pair of database rows. This is
/// where the two axes are shown *together*, which is the one thing neither
/// control does.
Future<void> showAudienceSheet({
  required BuildContext context,
  required ShareTarget target,
  required Audience audience,
  required String noun,
  required String? currentUserId,

  /// Drives the sentence at the top and the note at the bottom — a private
  /// container says why it cannot be shared, which is the only place that
  /// connects the missing "Teilen" row to the picker that would bring it back.
  required ItemVisibility visibility,
}) {
  return showAppSheet<void>(
    context: context,
    title: L.s.whoSeesTitle(noun),
    heightFactor: 0.6,
    child: _AudienceBody(
      target: target,
      audience: audience,
      noun: noun,
      currentUserId: currentUserId,
      visibility: visibility,
    ),
  );
}

class _AudienceBody extends ConsumerWidget {
  final ShareTarget target;
  final Audience audience;
  final String noun;
  final String? currentUserId;
  final ItemVisibility visibility;

  const _AudienceBody({
    required this.target,
    required this.audience,
    required this.noun,
    required this.currentUserId,
    required this.visibility,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The live view of the outward share, for the invitations that are out —
    // those are nobody's face yet, so the cached roster behind [audience] has
    // no way to know about them. Its guests take over from the cached ones once
    // it has loaded, so removing somebody in the edit sheet is visible here on
    // the next open rather than on the next launch.
    final sharing = ref.watch(sharingProvider(target));
    final guests = sharing.loading
        ? audience.guests
        : [for (final g in sharing.guests) g.asFamilyMember];
    final pending = sharing.pendingLinks;

    final others = [
      for (final m in audience.household)
        if (m.id != currentUserId) m.name,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 12),
          child: Text(
            switch (visibility) {
              ItemVisibility.family => L.s.wholeFamilySees(noun),
              ItemVisibility.private => L.s.onlyYouSee(noun),
              ItemVisibility.custom => others.isEmpty
                  ? L.s.onlyYouSee(noun)
                  : L.s.youAndOthersSee(L.s.joinNames(others), noun),
            },
            style: AppText.label.copyWith(fontSize: 12.5),
          ),
        ),
        if (audience.household.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(L.s.family, style: AppText.microLabel),
          ),
          SectionCard(
            children: dividedRows([
              for (final m in audience.household)
                _PersonRow(person: m, subtitle: m.id == currentUserId ? L.s.me : null),
            ]),
          ),
        ],
        if (guests.isNotEmpty || pending.isNotEmpty) ...[
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(L.s.sharedOutsideTitle, style: AppText.microLabel),
          ),
          SectionCard(
            children: dividedRows([
              for (final g in guests) _PersonRow(person: g, subtitle: L.s.guest),
              if (pending.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      AppIcon(AppIcons.link, size: 16, color: AppColors.inkSecondary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          L.s.openInvitations(pending.length, null),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.rowTitle,
                        ),
                      ),
                    ],
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 8),
            child: Text(L.s.shareIntroSecond(noun), style: AppText.label.copyWith(fontSize: 12.5)),
          ),
        ],
        // Only where it is actually the reason nothing can be shared: a private
        // container that somebody outside already holds is a combination the
        // database allows and the app no longer creates, and telling its owner
        // they cannot share it while a guest is listed above would be a flat
        // contradiction.
        if (visibility == ItemVisibility.private && guests.isEmpty && pending.isEmpty) ...[
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: AppIcon(AppIcons.lock, size: 15, color: AppColors.muted),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  L.s.privateCannotShare(noun),
                  style: AppText.label.copyWith(fontSize: 12.5),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PersonRow extends StatelessWidget {
  final FamilyMember person;
  final String? subtitle;

  const _PersonRow({required this.person, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          Avatar(
            size: 34,
            bg: person.toneColors.bg,
            fg: person.toneColors.fg,
            initials: person.initials,
            fontSize: 12,
            imageUrl: person.imageUrl,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(person.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.rowTitle),
          ),
          if (subtitle case final text?)
            Text(text, style: AppText.caption.copyWith(color: AppColors.muted)),
        ],
      ),
    );
  }
}
