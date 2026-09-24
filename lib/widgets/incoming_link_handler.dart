import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/l10n.dart';
import '../services/calendar_cache.dart';
import '../services/supabase.dart';
import '../state/auth_state.dart';
import '../state/board_state.dart';
import '../state/box_state.dart';
import '../state/calendar_connections_state.dart';
import '../state/calendar_state.dart';
import '../state/family_state.dart';
import '../state/incoming_link_state.dart';
import '../state/list_state.dart';
import '../state/more_state.dart';
import '../state/nav_state.dart';
import '../state/spend_state.dart';
import '../state/tracker_state.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import 'step_page.dart';
import 'action_bar.dart';
import 'app_sheet.dart';
import 'error_note.dart';
import 'glass.dart';
import 'toast_chip.dart';

/// Acts on an invitation or share link the app was opened with.
///
/// Sits above `_RootGate` rather than inside the shell, because the person
/// opening an invitation has usually only just signed up: they have a session
/// and a fresh household of their own, and the gate is about to put them into
/// onboarding for it. The invitation has to be offered **before** that, or
/// they set up a household only to have it deleted by the next tap.
///
/// Waits for a session and a loaded household; `incomingLinkProvider` holds
/// the link through sign-in until then.
class IncomingLinkHandler extends ConsumerStatefulWidget {
  final Widget child;

  const IncomingLinkHandler({super.key, required this.child});

  @override
  ConsumerState<IncomingLinkHandler> createState() => _IncomingLinkHandlerState();
}

class _IncomingLinkHandlerState extends ConsumerState<IncomingLinkHandler> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeHandle());
  }

  void _maybeHandle() {
    if (_busy || !mounted) return;
    final link = ref.read(incomingLinkProvider);
    if (link == null) return;
    if (ref.read(authProvider).status != AuthStatus.signedIn) return;
    if (!ref.read(familyProvider).loaded) return;

    _busy = true;
    ref.read(incomingLinkProvider.notifier).done();
    final work = switch (link.kind) {
      IncomingLinkKind.invite => _acceptInvite(link.token),
      IncomingLinkKind.share => _redeemShare(link.token),
    };
    work.whenComplete(() => _busy = false);
  }

  // ------------------------------------------------------------------ invite --

  Future<void> _acceptInvite(String token) async {
    // Asked first, so the question can name the household and a dead link is
    // reported before anybody has agreed to anything.
    final _InvitePreview? preview;
    try {
      preview = await _previewInvite(token);
    } on FunctionException catch (e) {
      if (mounted) showErrorSnack(context, _inviteError(e));
      return;
    }
    if (!mounted) return;

    // Somebody who signed up a minute ago to take this very invitation has a
    // household only because `handle_new_user` makes one for every signup:
    // onboarding never finished and nobody else is in it, so joining costs them
    // nothing and the warning below would be about nothing. They get a welcome
    // instead, and "no" leaves them in the tour they were already in.
    final family = ref.read(familyProvider);
    final fresh = family.household?.onboardingDone == false && family.members.length <= 1;

    // Asked, never assumed: `accept_family_invite` deletes the household the
    // person is in now, and with it whatever they made there alone.
    final join = fresh && preview != null
        ? await showAppSheet<bool>(
            context: context,
            header: SheetPickerHeader(title: ''),
            heightFactor: 0.6,
            footer: _WelcomeActions(household: preview.household),
            child: _WelcomeBody(preview: preview),
          )
        : await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(
                preview == null ? L.s.joinHouseholdTitle : L.s.joinNamedHouseholdTitle(preview.household),
              ),
              content: Text(L.s.joinHouseholdBody),
              actions: [
                TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(L.s.cancel)),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(L.s.joinHousehold, style: AppText.rowTitle.copyWith(color: AppColors.danger)),
                ),
              ],
            ),
          );
    if (join != true || !mounted) return;

    try {
      await AporahSupabase.client.functions.invoke('accept-invite', body: {'token': token});
    } on FunctionException catch (e) {
      if (mounted) showErrorSnack(context, _inviteError(e));
      return;
    } catch (_) {
      if (mounted) showErrorSnack(context, L.s.inviteAcceptFailed);
      return;
    }
    if (!mounted) return;

    // Same user, different household — and every provider below keys on the
    // user, so none of them would notice on their own. The calendar cache goes
    // for the reason sign-out takes it: it holds the old household's events.
    await CalendarCache().clear();
    if (!mounted) return;
    late final ProviderSubscription<FamilyState> welcome;
    welcome = ref.listenManual<FamilyState>(familyProvider, (_, next) {
      if (!next.loaded) return;
      welcome.close();
      final name = next.household?.name;
      if (name != null && mounted) showToast(context, L.s.joinedHousehold(name));
    });
    ref
      ..invalidate(familyProvider)
      ..invalidate(listProvider)
      ..invalidate(boxProvider)
      ..invalidate(boardProvider)
      ..invalidate(trackerProvider)
      ..invalidate(calendarProvider)
      ..invalidate(calendarConnectionsProvider)
      ..invalidate(spendProvider);
  }

  /// Whose invitation this is. `null` when the question could not be asked —
  /// `invite-preview` not deployed yet, no network — and the caller falls back
  /// to the unnamed question rather than refusing a link that may be fine.
  /// Throws the [FunctionException] of a real refusal (expired, used, sent to
  /// another address), which is worth saying before the question, not after.
  Future<_InvitePreview?> _previewInvite(String token) async {
    try {
      final res = await AporahSupabase.client.functions.invoke('invite-preview', body: {'token': token});
      final data = res.data;
      if (data is! Map || data['family_name'] is! String) return null;
      return _InvitePreview(household: data['family_name'] as String, inviter: data['inviter_name'] as String?);
    } on FunctionException catch (e) {
      if (e.status == 400) rethrow;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// `accept_family_invite` raises German sentences for the four refusals a
  /// person can actually hit. They are matched here rather than passed
  /// through, so the answer comes in the reader's language.
  String _inviteError(FunctionException e) {
    final details = e.details;
    final message = (details is Map ? details['error'] as String? : null) ?? '';
    if (message.contains('abgelaufen')) return L.s.inviteExpired;
    if (message.contains('andere E-Mail')) return L.s.inviteOtherEmail;
    if (message.contains('anderen Mitgliedern')) return L.s.inviteLeaveFirst;
    if (message.contains('ungültig')) return L.s.inviteInvalid;
    return L.s.inviteAcceptFailed;
  }

  // ------------------------------------------------------------------- share --

  Future<void> _redeemShare(String token) async {
    final String kind;
    final String id;
    try {
      final res = await AporahSupabase.client.functions.invoke('redeem-share-link', body: {'token': token});
      final data = res.data;
      if (data is! Map || data['kind'] is! String || data['resource_id'] is! String) throw const FormatException();
      kind = data['kind'] as String;
      id = data['resource_id'] as String;
    } catch (_) {
      if (mounted) showErrorSnack(context, L.s.shareLinkInvalid);
      return;
    }
    if (!mounted) return;

    // The grant is a new row in `guest_access`; the screens only see what it
    // opens once they read again.
    final jump = ref.read(tabJumpProvider.notifier);
    switch (kind) {
      case 'list':
        await ref.read(listProvider.notifier).load();
        jump.toList(id);
      case 'box':
        await ref.read(boxProvider.notifier).load();
        if (!mounted) return;
        ref.read(moreProvider.notifier).open(MoreSection.box);
        ref.read(boxProvider.notifier).open(id);
        jump.toTab(moreTabIndex);
      case 'task':
        await ref.read(boardProvider.notifier).load();
        jump.toTask(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(incomingLinkProvider, (_, _) => _maybeHandle());
    ref.listen(authProvider.select((s) => s.status), (_, _) => _maybeHandle());
    ref.listen(familyProvider.select((s) => s.loaded), (_, _) => _maybeHandle());
    return widget.child;
  }
}

class _InvitePreview {
  final String household;
  final String? inviter;

  const _InvitePreview({required this.household, this.inviter});
}

/// The invitation as a newcomer sees it: whose household, and who asked.
class _WelcomeBody extends StatelessWidget {
  final _InvitePreview preview;

  // ignore: prefer_const_constructors_in_immutables
  _WelcomeBody({required this.preview});

  @override
  Widget build(BuildContext context) {
    final inviter = preview.inviter;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 62,
              height: 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadii.iconTile + 5),
              ),
              child: AppIcon(AppIcons.usersThree, size: 30, color: AppColors.accent),
            ),
          ),
          const SizedBox(height: 14),
          Text(L.s.joinedHousehold(preview.household), style: AppText.cardTitle, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            inviter == null
                ? L.s.inviteWelcomeBodyNoInviter(preview.household)
                : L.s.inviteWelcomeBody(inviter, preview.household),
            style: AppText.caption.copyWith(color: AppColors.inkSecondary, fontWeight: FontWeight.w400, height: 1.45),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Join, or go on with the tour. Both pop the sheet with the answer; closing
/// it with the X is the same "no".
class _WelcomeActions extends StatelessWidget {
  final String household;

  // ignore: prefer_const_constructors_in_immutables
  _WelcomeActions({required this.household});

  /// The same pair a sign-in step offers, so it is the same pair of pills —
  /// see [stepButtonPadding], which is what makes the accent one and the
  /// neutral one under it one height.
  static const _padding = stepButtonPadding;

  @override
  Widget build(BuildContext context) {
    return PinnedActionBar(
      fadeHeight: 10,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassAccentButton(
            label: L.s.inviteJoinNamed(household),
            expand: true,
            fontSize: 16,
            padding: _padding,
            onTap: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: 10),
          GlassPillButton(
            label: L.s.inviteSetUpOwn,
            expand: true,
            padding: _padding,
            onTap: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}
