import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../state/family_state.dart';
import '../../state/auth_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/avatar.dart';
import '../../widgets/confirmation.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_note.dart';
import '../../widgets/icon_tile.dart';
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
        // Members and the people who have been invited but haven't joined yet
        // are one list, not two: an invitation *is* a place at the table that
        // nobody has taken. Its own row already says so — the envelope instead
        // of an avatar, and "Mitglied · ausstehend" underneath — so a second
        // card under its own heading only said it a third time and pushed the
        // invite button into the middle of the page.
        SectionCard(
          radius: AppRadii.card,
          children: family.members.isEmpty && family.invites.isEmpty
              ? [
                  EmptyState(
                    icon: LucideIcons.users,
                    message: L.s.nobodyInHouseholdYet,
                  ),
                ]
              : dividedRows(inset: true, [
                  for (final m in family.members) _MemberRow(member: m, isMe: m.userId == me, canManage: isAdmin),
                  for (final invite in family.invites)
                    SettingsRow(
                      // Sized like the avatar beside it, so the merged list has
                      // one column of round leadings rather than two.
                      leading: GlassIconTile(icon: LucideIcons.mail, size: 40, iconSize: 18),
                      title: invite.name.isNotEmpty ? invite.name : invite.email,
                      subtitle: L.s.pendingWithRole(invite.role.label),
                      // Withdrawing an invitation is an admin's business, same
                      // as sending one; everybody else just sees who's coming.
                      trailing: !isAdmin
                          ? null
                          : GestureDetector(
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
        // The gate is courtesy, not security: `invite-member` checks the role
        // itself and RLS refuses the writes regardless. Showing a control that
        // is going to be refused is just a worse way of saying no.
        //
        // Last on the page on purpose: it acts on the list above it, so it
        // stays under the whole list however long it grows.
        if (isAdmin) ...[
          const SizedBox(height: AppSpacing.blockGap),
          AccentAction(
            icon: LucideIcons.userPlus,
            label: L.s.inviteMember,
            onTap: () => _openInviteSheet(context, ref),
          ),
        ],
      ],
    );
  }

  /// The invite sheet, which is three states of one sheet rather than a form
  /// that closes on the check: what you typed, the send in flight, and the
  /// confirmation of the invitation that now exists. It used to pop on the
  /// check and say nothing — an invitation is somebody else's mail arriving
  /// somewhere we can't see, so "it went out" is exactly the part the sender
  /// needs told. The confirmation also carries the link, which
  /// `invite-member` hands back exactly once.
  void _openInviteSheet(BuildContext context, WidgetRef ref) {
    final flow = _InviteFlow(ref.read(familyProvider.notifier));
    showAppSheet<void>(
      context: context,
      // Tall enough that the fields stay above the keyboard — the sheet is
      // anchored to the bottom, so a shorter one puts them where the keyboard
      // comes up — and that the confirmation doesn't have to be scrolled.
      heightFactor: 0.72,
      header: _InviteHeader(flow: flow),
      child: _InviteSheetBody(flow: flow),
    ).whenComplete(() {
      // Not disposed on the spot: the sheet's own widgets are still mounted —
      // and still reading the controllers — while the route animates out.
      Future<void>.delayed(const Duration(milliseconds: 400), flow.dispose);
    });
  }
}

enum _InvitePhase { editing, sending, sent }

/// The state the invite sheet's header and its body share.
///
/// They are siblings inside [showAppSheet]'s own Column — the header can't be
/// built by the body's `State` — so the two halves talk through this, the same
/// way the connect-confirm sheet does.
class _InviteFlow {
  _InviteFlow(this._notifier);

  final HouseholdNotifier _notifier;

  final TextEditingController email = TextEditingController();
  final TextEditingController name = TextEditingController();

  /// The role is chosen when the invitation is sent, not afterwards: it is
  /// written into the `family_invites` row and applied by `accept-invite`, so
  /// inviting a child as an admin and demoting them later would have given
  /// them full access in between.
  FamilyRole role = FamilyRole.member;

  final ValueNotifier<_InvitePhase> phase = ValueNotifier(_InvitePhase.editing);
  final ValueNotifier<String?> error = ValueNotifier(null);

  /// Set exactly once, when the invitation comes back. Read by both halves in
  /// the [_InvitePhase.sent] phase, so it is non-null wherever it is read.
  SentInvite? sent;

  /// The sheet can be swiped away while the send is still in flight — the
  /// invitation is still created, there is just nothing left to tell about it.
  bool _disposed = false;

  Future<void> submit(BuildContext context) async {
    if (phase.value != _InvitePhase.editing) return;
    FocusScope.of(context).unfocus();
    error.value = null;
    phase.value = _InvitePhase.sending;

    final outcome = await _notifier.inviteMember(
      email: email.text,
      name: name.text,
      role: role,
    );
    if (_disposed) return;

    if (outcome.invite case final invite?) {
      sent = invite;
      phase.value = _InvitePhase.sent;
    } else {
      // Reported here rather than as a toast: the sheet is still open, and the
      // message belongs next to the address it was typed into.
      error.value = outcome.error;
      phase.value = _InvitePhase.editing;
    }
  }

  void dispose() {
    _disposed = true;
    email.dispose();
    name.dispose();
    phase.dispose();
    error.dispose();
  }
}

class _InviteHeader extends StatelessWidget {
  final _InviteFlow flow;

  const _InviteHeader({required this.flow});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_InvitePhase>(
      valueListenable: flow.phase,
      builder: (context, phase, _) => SheetActionHeader(
        title: switch (phase) {
          _InvitePhase.editing || _InvitePhase.sending => L.s.inviteFamilyMember,
          // An invitation whose mail didn't go out is still an invitation; it
          // says so instead of claiming a delivery that didn't happen.
          _InvitePhase.sent => flow.sent!.mailSent ? L.s.inviteSentTitle : L.s.inviteCreatedTitle,
        },
        action: switch (phase) {
          _InvitePhase.editing => SheetHeaderAction.confirm,
          _InvitePhase.sending => SheetHeaderAction.busy,
          _InvitePhase.sent => SheetHeaderAction.none,
        },
        onConfirm: () => flow.submit(context),
      ),
    );
  }
}

class _InviteSheetBody extends StatelessWidget {
  final _InviteFlow flow;

  const _InviteSheetBody({required this.flow});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_InvitePhase>(
      valueListenable: flow.phase,
      builder: (context, phase, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        child: phase == _InvitePhase.sent
            ? _InviteSentBody(key: const ValueKey('sent'), invite: flow.sent!)
            : _InviteFormBody(
                key: const ValueKey('editing'),
                flow: flow,
                busy: phase == _InvitePhase.sending,
              ),
      ),
    );
  }
}

class _InviteFormBody extends StatefulWidget {
  final _InviteFlow flow;
  final bool busy;

  const _InviteFormBody({super.key, required this.flow, required this.busy});

  @override
  State<_InviteFormBody> createState() => _InviteFormBodyState();
}

class _InviteFormBodyState extends State<_InviteFormBody> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCard(
          children: dividedRows([
            _InviteRow(
              child: TextField(
                controller: widget.flow.email,
                enabled: !widget.busy,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                style: AppText.searchInput,
                decoration: InputDecoration(border: InputBorder.none, hintText: L.s.emailAddress, isDense: true),
              ),
            ),
            _InviteRow(
              child: TextField(
                controller: widget.flow.name,
                enabled: !widget.busy,
                style: AppText.searchInput,
                decoration: InputDecoration(border: InputBorder.none, hintText: L.s.nameOptional, isDense: true),
              ),
            ),
            _InviteRow(
              child: Row(
                children: [
                  Expanded(child: Text(L.s.role, style: AppText.rowTitle)),
                  _RolePicker(
                    role: widget.flow.role,
                    onChanged: (r) => setState(() => widget.flow.role = r),
                  ),
                ],
              ),
            ),
          ]),
        ),
        ValueListenableBuilder<String?>(
          valueListenable: widget.flow.error,
          builder: (context, message, _) => message == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ErrorNote(message: message),
                ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            L.s.inviteValidity,
            style: AppText.label.copyWith(fontSize: 12),
          ),
        ),
        if (widget.busy) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Text(L.s.inviteSending, style: AppText.body.copyWith(color: AppColors.muted)),
            ],
          ),
        ],
      ],
    );
  }
}

/// One row of the invite card, at a fixed height.
///
/// A bare `TextField` and a bordered picker measure to different heights on
/// their own — which is why the card used to look assembled from three
/// different lists — and no amount of tuning each one's padding keeps them
/// agreeing when the text scale changes. The row owns the height; its content
/// sits centred in it.
class _InviteRow extends StatelessWidget {
  final Widget child;

  const _InviteRow({required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Center(child: child),
      ),
    );
  }
}

/// What the sheet becomes once the invitation exists — the app's one
/// confirmation ([ConfirmationView]) with the invitation's own content: who
/// was invited as what, and until when.
///
/// A beat, like the calendar connect: there is nothing here to act on. The
/// invitation link is deliberately **not** offered — the mail carries it, and
/// putting it on screen invites passing an invitation around by hand, which is
/// exactly the thing whose one-shot token and 14-day expiry exist to prevent.
/// It stays a celebration, though: somebody joining the household happens once.
class _InviteSentBody extends StatelessWidget {
  final SentInvite invite;

  const _InviteSentBody({super.key, required this.invite});

  @override
  Widget build(BuildContext context) {
    final expires = invite.expiresAt;

    return ConfirmationView(
      mark: ConfirmationMark.celebration,
      headline: invite.mailSent ? L.s.inviteSentTitle : L.s.inviteCreatedTitle,
      message: invite.mailSent ? L.s.inviteSentTo(invite.email) : L.s.inviteMailNotSent(invite.email),
      // Long enough to read the address it went to and the role, and no longer:
      // the pending-invites list on the page behind says all of it again.
      dismissAfter: const Duration(milliseconds: 3200),
      content: [
        SectionCard(
          children: dividedRows([
            SettingsRow(
              icon: LucideIcons.mail,
              title: invite.name.isNotEmpty ? invite.name : invite.email,
              subtitle: L.s.invitedAsRole(invite.role.label),
            ),
            if (expires != null)
              SettingsRow(
                icon: LucideIcons.clock,
                title: L.s.inviteValidUntil(L.s.dayMonthShort(expires.day, expires.month)),
              ),
          ]),
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
          Avatar(size: 40, bg: tone.bg, fg: tone.fg, initials: member.initials, fontSize: 13, imageUrl: member.avatarUrl),
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
