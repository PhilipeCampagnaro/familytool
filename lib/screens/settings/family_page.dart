import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../state/family_state.dart';
import '../../state/auth_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/avatar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_note.dart';
import '../../widgets/settings_chrome.dart';
import '../../l10n/l10n.dart';

/// Who is in the household, and — for an admin — the controls to change that.
/// Every control here is courtesy: `invite-member` checks the role itself and
/// RLS refuses the writes regardless.
class FamilyPage extends ConsumerWidget {
  const FamilyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final family = ref.watch(familyProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final me = ref.watch(currentUserIdProvider);

    // A refused write is reported once and forgotten. RLS is what actually
    // denies it — this only says so in German.
    ref.listen<String?>(familyProvider.select((s) => s.actionError), (_, message) {
      if (message == null) return;
      showErrorSnack(context, message);
      ref.read(familyProvider.notifier).clearActionError();
    });

    return SettingsDetailPage(
      icon: LucideIcons.users,
      title: L.s.familyMembers,
      description: isAdmin ? L.s.familyMembersDesc : L.s.familyMembersDescAdmin,
      children: [
        SectionCard(
          radius: AppRadii.card,
          children: family.members.isEmpty
              ? [
                  EmptyState(
                    icon: LucideIcons.users,
                    message: L.s.nobodyInHouseholdYet,
                  ),
                ]
              : dividedRows(inset: true, [
                  for (final m in family.members) _MemberRow(member: m, isMe: m.userId == me, canManage: isAdmin),
                ]),
        ),
        // The gate is courtesy, not security: `invite-member` checks the role
        // itself and RLS refuses the writes regardless. Showing a control that
        // is going to be refused is just a worse way of saying no.
        if (isAdmin) ...[
          const SizedBox(height: 14),
          AccentAction(
            icon: LucideIcons.userPlus,
            label: L.s.inviteMember,
            onTap: () => _openInviteSheet(context, ref),
          ),
        ],
        if (family.invites.isNotEmpty) ...[
          GroupLabel(L.s.pendingInvites),
          SectionCard(
            children: dividedRows([
              for (final invite in family.invites)
                SettingsRow(
                  icon: LucideIcons.mail,
                  title: invite.name.isNotEmpty ? invite.name : invite.email,
                  subtitle: L.s.pendingWithRole(invite.role.label),
                  trailing: GestureDetector(
                    onTap: () => ref.read(familyProvider.notifier).revokeInvite(invite.id),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      child: Icon(LucideIcons.x, size: 17, color: AppColors.mutedLight),
                    ),
                  ),
                ),
            ]),
          ),
        ],
      ],
    );
  }

  void _openInviteSheet(BuildContext context, WidgetRef ref) {
    final emailController = TextEditingController();
    final nameController = TextEditingController();
    final draft = _InviteDraft();
    showAppSheet(
      context: context,
      title: L.s.inviteFamilyMember,
      heightFactor: 0.6,
      onSave: () => ref.read(familyProvider.notifier).inviteMember(
            email: emailController.text,
            name: nameController.text,
            role: draft.role,
          ),
      child: _InviteSheetBody(
        emailController: emailController,
        nameController: nameController,
        draft: draft,
      ),
    );
  }
}

/// The invited role, held by reference — the sheet's save button is handed its
/// callback before the body exists.
class _InviteDraft {
  FamilyRole role = FamilyRole.member;
}

class _InviteSheetBody extends StatefulWidget {
  final TextEditingController emailController;
  final TextEditingController nameController;
  final _InviteDraft draft;

  const _InviteSheetBody({
    required this.emailController,
    required this.nameController,
    required this.draft,
  });

  @override
  State<_InviteSheetBody> createState() => _InviteSheetBodyState();
}

class _InviteSheetBodyState extends State<_InviteSheetBody> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: widget.emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                style: AppText.searchInput,
                decoration: InputDecoration(border: InputBorder.none, hintText: L.s.emailAddress, isDense: true),
              ),
            ),
            CardDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: widget.nameController,
                style: AppText.searchInput,
                decoration: InputDecoration(border: InputBorder.none, hintText: L.s.nameOptional, isDense: true),
              ),
            ),
            CardDivider(),
            // The role is chosen when the invitation is sent, not afterwards:
            // it is written into the `family_invites` row and applied by
            // `accept-invite`, so inviting a child as an admin and demoting
            // them later would have given them full access in between.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(child: Text(L.s.role, style: AppText.rowTitle)),
                  _RolePicker(
                    role: widget.draft.role,
                    onChanged: (r) => setState(() => widget.draft.role = r),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            L.s.inviteValidity,
            style: AppText.label.copyWith(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _MemberRow extends ConsumerWidget {
  final HouseholdMember member;
  final bool isMe;

  /// Whether the *viewer* is an admin. The row is rendered for everybody; only
  /// an admin gets the controls.
  final bool canManage;

  const _MemberRow({required this.member, required this.isMe, required this.canManage});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tone = AppTones.list[member.tone % AppTones.list.length];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Avatar(size: 40, bg: tone.bg, fg: tone.fg, initials: member.initials, fontSize: 13),
          const SizedBox(width: 13),
          Expanded(
            child: Row(
              children: [
                Flexible(child: Text(member.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.rowTitle)),
                if (isMe) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadii.iconTile),
                      border: Border.all(color: AppColors.hairline2),
                    ),
                    child: Text(L.s.youCaps, style: AppText.microLabel.copyWith(letterSpacing: 0.5)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Nobody demotes or removes themselves here. `enforce_last_admin`
          // would refuse it whenever they are the only admin, and when they
          // aren't, leaving a household is a different action with different
          // consequences than being removed from one.
          if (isMe || !canManage)
            Text(member.role.label, style: AppText.label)
          else ...[
            _RolePicker(
              role: member.role,
              onChanged: (r) => ref.read(familyProvider.notifier).setRole(member.userId, r),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => _confirmRemove(context, ref),
              behavior: HitTestBehavior.opaque,
              child: Icon(LucideIcons.trash2, size: 18, color: AppColors.mutedLight),
            ),
          ],
        ],
      ),
    );
  }

  void _confirmRemove(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L.s.removeMemberQuestion),
        // Says what actually happens, because it is not reversible:
        // `reassign_content_on_member_removal` hands their family-visible
        // content to an admin and deletes their private content outright —
        // there is no backdoor into it, by design.
        content: Text(L.s.removeMemberBody(member.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(L.s.cancel),
          ),
          TextButton(
            onPressed: () {
              ref.read(familyProvider.notifier).removeMember(member.userId);
              Navigator.of(dialogContext).pop();
            },
            child: Text(L.s.remove, style: AppText.rowTitle.copyWith(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}

/// The bordered role dropdown on a member row. Deliberately a plain
/// [PopupMenuButton] rather than anything glass — see `glass.dart`: a native
/// glass platform view inside a popup's scale transition smears.
class _RolePicker extends StatelessWidget {
  final FamilyRole role;
  final ValueChanged<FamilyRole> onChanged;

  const _RolePicker({required this.role, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<FamilyRole>(
      onSelected: onChanged,
      position: PopupMenuPosition.under,
      color: AppColors.surface,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.iconTile)),
      itemBuilder: (_) => [
        for (final r in FamilyRole.values)
          PopupMenuItem(
            value: r,
            height: 42,
            child: Row(
              children: [
                Text(r.label, style: AppText.rowTitle),
                if (r == role) ...[
                  const SizedBox(width: 10),
                  Icon(LucideIcons.check, size: 15, color: Theme.of(context).colorScheme.primary),
                ],
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.iconTile),
          border: Border.all(color: AppColors.hairline2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(role.label, style: AppText.rowTitle),
            const SizedBox(width: 8),
            Icon(LucideIcons.chevronsUpDown, size: 14, color: AppColors.mutedLight),
          ],
        ),
      ),
    );
  }
}
