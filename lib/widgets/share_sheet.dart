import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../state/family_state.dart';
import '../state/sharing_state.dart';
import '../theme/tokens.dart';
import 'app_sheet.dart';
import 'avatar.dart';
import 'empty_state.dart';
import 'error_note.dart';
import 'native_switch.dart';

/// "Teilen" — the third visibility axis, and the only one that leaves the
/// household.
///
/// Reached from a list/box/task row menu, **never** from the "Für wen?" picker.
/// Mixing outsiders into the family avatar row would make a mis-tap leak
/// household data, so this is its own deliberate action with its own sheet.
///
/// Hidden for kids and for guests: `may_share_externally` excludes both, and
/// `enforce_share_link_author` raises on a kid's insert. The gate here is
/// courtesy — offering a button that is going to be refused is a worse way of
/// saying no.
Future<void> showShareSheet(
  BuildContext context, {
  required ShareableKind kind,
  required String resourceId,
  required String resourceName,
}) {
  return showAppSheet<void>(
    context: context,
    header: const SheetPickerHeader(title: 'Teilen'),
    heightFactor: 0.8,
    child: _ShareSheetBody(
      target: (kind: kind, id: resourceId),
      resourceName: resourceName,
    ),
  );
}

class _ShareSheetBody extends ConsumerStatefulWidget {
  final ShareTarget target;
  final String resourceName;

  const _ShareSheetBody({required this.target, required this.resourceName});

  @override
  ConsumerState<_ShareSheetBody> createState() => _ShareSheetBodyState();
}

class _ShareSheetBodyState extends ConsumerState<_ShareSheetBody> {
  final _email = TextEditingController();

  /// What a redeemer will be allowed to do. Defaults to true: the case this
  /// exists for is a shopping list somebody else is meant to tick off.
  bool _canEdit = true;

  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy) return;
    setState(() => _busy = true);
    await ref
        .read(sharingProvider(widget.target).notifier)
        .createLink(canEdit: _canEdit, email: _email.text);
    if (!mounted) return;
    _email.clear();
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final state = ref.watch(sharingProvider(widget.target));
    final notifier = ref.read(sharingProvider(widget.target).notifier);

    ref.listen<String?>(sharingProvider(widget.target).select((s) => s.error), (_, message) {
      if (message == null) return;
      showErrorSnack(context, message);
      notifier.clearError();
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12, right: 4),
          child: Text(
            '„${widget.resourceName}" mit Leuten außerhalb eurer Familie teilen. '
            'Sie sehen ausschließlich ${widget.target.kind.noun} — sonst nichts von euch.',
            style: AppText.label.copyWith(fontSize: 12.5),
          ),
        ),

        // --- The link just minted -------------------------------------------
        // Shown once and never again: only the token's hash is stored, so this
        // is the single moment the URL exists in the app. A link whose address
        // was never copied can be revoked, not recovered.
        if (state.freshUrl case final url?) ...[
          _FreshLinkCard(url: url, accent: accent, onDone: notifier.clearFreshUrl),
          const SizedBox(height: 14),
        ],

        // --- Create ----------------------------------------------------------
        SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                style: AppText.searchInput,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'E-Mail (optional)',
                  isDense: true,
                ),
              ),
            ),
            CardDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Bearbeiten erlaubt', style: AppText.rowTitle),
                        const SizedBox(height: 2),
                        Text(
                          _canEdit ? 'Kann abhaken und ergänzen' : 'Kann nur ansehen',
                          style: AppText.label.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  // SheetSwitch, not NativeSwitch: a platform view inside a
                  // sheet body makes iOS drop everything painted below it.
                  SheetSwitch(value: _canEdit, onChanged: (v) => setState(() => _canEdit = v)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _PrimaryAction(
          icon: LucideIcons.link,
          label: _email.text.trim().isEmpty ? 'Link erstellen' : 'Einladung senden',
          accent: accent,
          busy: _busy,
          onTap: _create,
        ),

        // --- Who is in -------------------------------------------------------
        if (state.guests.isNotEmpty) ...[
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 9),
            child: Text('Gäste', style: AppText.microLabel),
          ),
          SectionCard(
            children: [
              for (var i = 0; i < state.guests.length; i++) ...[
                if (i > 0) CardDivider(),
                _GuestRow(
                  guest: state.guests[i],
                  onRemove: () => notifier.removeGuest(state.guests[i].userId),
                ),
              ],
            ],
          ),
        ],

        // --- Links out -------------------------------------------------------
        if (state.links.isNotEmpty) ...[
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 9),
            child: Text('Aktive Links', style: AppText.microLabel),
          ),
          SectionCard(
            children: [
              for (var i = 0; i < state.links.length; i++) ...[
                if (i > 0) CardDivider(),
                _LinkRow(link: state.links[i], onRevoke: () => notifier.revokeLink(state.links[i].id)),
              ],
            ],
          ),
        ],

        if (!state.loading && state.guests.isEmpty && state.links.isEmpty && state.freshUrl == null) ...[
          const SizedBox(height: 18),
          EmptyState(
            icon: LucideIcons.userPlus,
            message: 'Noch nicht geteilt.\nErstell einen Link, um jemanden hineinzulassen.',
          ),
        ],
      ],
    );
  }
}

/// The URL, once. Copy is the only action that matters here, so it is the whole
/// card rather than a small button beside it.
class _FreshLinkCard extends StatefulWidget {
  final String url;
  final Color accent;
  final VoidCallback onDone;

  const _FreshLinkCard({required this.url, required this.accent, required this.onDone});

  @override
  State<_FreshLinkCard> createState() => _FreshLinkCardState();
}

class _FreshLinkCardState extends State<_FreshLinkCard> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.link, size: 15, color: widget.accent),
                  const SizedBox(width: 8),
                  Text('Neuer Link', style: AppText.rowTitle),
                  const Spacer(),
                  GestureDetector(
                    onTap: widget.onDone,
                    behavior: HitTestBehavior.opaque,
                    child: Icon(LucideIcons.x, size: 16, color: AppColors.mutedLight),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.url,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.inkSecondary),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: widget.url));
                  if (mounted) setState(() => _copied = true);
                },
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Icon(_copied ? LucideIcons.check : LucideIcons.copy, size: 15, color: widget.accent),
                    const SizedBox(width: 7),
                    Text(
                      _copied ? 'Kopiert' : 'Link kopieren',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w500, color: widget.accent),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Dieser Link wird nur jetzt angezeigt — wir speichern ihn nicht.',
                style: AppText.label.copyWith(fontSize: 11.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GuestRow extends StatelessWidget {
  final Guest guest;
  final VoidCallback onRemove;

  const _GuestRow({required this.guest, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final tone = AppTones.list[guest.tone % AppTones.list.length];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Avatar(size: 34, bg: tone.bg, fg: tone.fg, initials: guest.initials, fontSize: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(guest.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.rowTitle),
                Text(
                  guest.canEdit ? 'Darf bearbeiten' : 'Nur ansehen',
                  style: AppText.label.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Icon(LucideIcons.userMinus, size: 17, color: AppColors.mutedLight),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final ShareLink link;
  final VoidCallback onRevoke;

  const _LinkRow({required this.link, required this.onRevoke});

  String get _subtitle {
    final parts = <String>[
      link.canEdit ? 'Bearbeiten' : 'Nur ansehen',
      if (link.useCount == 1) '1× benutzt' else if (link.useCount > 1) '${link.useCount}× benutzt',
      if (link.expired) 'abgelaufen' else if (link.usedUp) 'aufgebraucht',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(LucideIcons.link, size: 16, color: link.live ? AppColors.inkSecondary : AppColors.mutedLight),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // No URL: only the hash is stored, so there is nothing to print
                // here. That is the point of storing it that way.
                Text('Freigabe-Link', style: AppText.rowTitle),
                Text(_subtitle, style: AppText.label.copyWith(fontSize: 12)),
              ],
            ),
          ),
          GestureDetector(
            onTap: onRevoke,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Text(
                'Zurückziehen',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.danger),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final bool busy;
  final VoidCallback onTap;

  const _PrimaryAction({
    required this.icon,
    required this.label,
    required this.accent,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: busy ? tint(accent, .85) : accent,
          borderRadius: BorderRadius.circular(AppRadii.cardSmall),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            else
              Icon(icon, size: 17, color: Colors.white),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

/// Whether the signed-in user may share anything outward at all.
///
/// Mirrors `may_share_externally`: admins and members, never kids. A guest has
/// no `family_members` row for this household and so is never an admin or
/// member of it either.
final canShareExternallyProvider = Provider<bool>((ref) {
  final role = ref.watch(myRoleProvider);
  return role == FamilyRole.admin || role == FamilyRole.member;
});
