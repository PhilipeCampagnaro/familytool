import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'app_sheet.dart';
import 'confirmation.dart';
import 'error_note.dart';
import 'settings_chrome.dart';
import '../l10n/l10n.dart';

/// One thing has a name, you are changing it: the thing at the top, a field, a
/// blue check, and the beat that says it saved.
///
/// This is a whole sheet rather than an `AlertDialog` with a `TextField` in it
/// because renaming is a *save*, and every other save in the app is a check in
/// a sheet header. It used to be the last step of all six "add a calendar"
/// flows as well — hence the shape — but those now walk their own steps inside
/// one sheet (`showCalendarConnectSheet`), and a name they were already asking
/// for is a step there, not a second sheet over the first.
///
/// [onConfirm] is what actually happens when the check is tapped; it gets the
/// name from the field, already trimmed. The sheet stays open (and blocks the
/// close button) while it runs, shows the success beat when it returns, and
/// only then pops with `true`. If it throws, the sheet stays put with the
/// message under the field so the name isn't lost.
Future<bool> showRenameSheet({
  required BuildContext context,
  required IconData icon,
  required String title,
  required String headline,
  required String message,
  required String initialName,
  required Future<void> Function(String name) onConfirm,
  // Nullable rather than defaulted: a default parameter value has to be a
  // compile-time constant, and these follow the interface language.
  String? fieldLabel,
  String? fieldHint,
  String? busyLabel,
  String? successLabel,
  String Function(Object error)? errorText,
}) async {
  fieldLabel ??= L.s.name;
  fieldHint ??= L.s.calendarNameInAporah;
  busyLabel ??= L.s.connectingEllipsis;
  successLabel ??= L.s.calendarConnected;

  final flow = _RenameFlow(
    initialName: initialName,
    onConfirm: onConfirm,
    errorText: errorText,
    busyLabel: busyLabel,
  );

  final confirmed = await showAppSheet<bool>(
    context: context,
    // Tall enough that the name field stays above the keyboard: the sheet is
    // anchored to the bottom of the screen, so a shorter one puts the field
    // exactly where the keyboard comes up.
    heightFactor: 0.72,
    header: _RenameHeader(flow: flow, title: title),
    child: _RenameBody(
      flow: flow,
      icon: icon,
      headline: headline,
      message: message,
      fieldLabel: fieldLabel,
      fieldHint: fieldHint,
      successLabel: successLabel,
    ),
  );

  // Not disposed on the spot: the sheet's own widgets are still mounted — and
  // still reading the controller — while the route animates out.
  unawaited(Future<void>.delayed(const Duration(milliseconds: 400), flow.dispose));
  return confirmed ?? false;
}

enum _Phase { editing, busy, success }

/// The state the sheet's header and its body share.
///
/// They are siblings inside [showAppSheet]'s own Column — the header can't be
/// built by the body's `State` — so the two halves talk through this rather
/// than through a `setState` neither of them can reach.
class _RenameFlow {
  _RenameFlow({
    required String initialName,
    required this.onConfirm,
    required this.errorText,
    required this.busyLabel,
  }) : name = TextEditingController(text: initialName);

  final TextEditingController name;
  final Future<void> Function(String name) onConfirm;
  final String Function(Object error)? errorText;
  final String busyLabel;

  final ValueNotifier<_Phase> phase = ValueNotifier(_Phase.editing);
  final ValueNotifier<String?> error = ValueNotifier(null);

  /// The sheet can be swiped away while the connect is still in flight — the
  /// call carries on, but there is nothing left to tell about it.
  bool _disposed = false;

  Future<void> submit(BuildContext context) async {
    if (phase.value != _Phase.editing) return;
    FocusScope.of(context).unfocus();
    error.value = null;
    phase.value = _Phase.busy;
    try {
      await onConfirm(name.text.trim());
      if (_disposed) return;
      phase.value = _Phase.success;
    } catch (e) {
      if (_disposed) return;
      error.value = errorText?.call(e) ?? L.s.somethingWentWrong;
      phase.value = _Phase.editing;
    }
  }

  void dispose() {
    _disposed = true;
    name.dispose();
    phase.dispose();
    error.dispose();
  }
}

/// Close on the left, the accent check on the right — the same two controls as
/// every other sheet header, so this reads as a sheet and not as a dialog.
/// While the connect runs the check becomes a spinner and the X goes away:
/// there is a request in flight that closing would not cancel. That is
/// [SheetActionHeader]'s job; this only maps the flow's phase onto it.
class _RenameHeader extends StatelessWidget {
  final _RenameFlow flow;
  final String title;

  const _RenameHeader({required this.flow, required this.title});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_Phase>(
      valueListenable: flow.phase,
      builder: (context, phase, _) => SheetActionHeader(
        title: title,
        action: switch (phase) {
          _Phase.editing => SheetHeaderAction.confirm,
          _Phase.busy => SheetHeaderAction.busy,
          _Phase.success => SheetHeaderAction.none,
        },
        onConfirm: () => flow.submit(context),
        // Closing by hand is a "no", so the caller gets `false` — the success
        // beat is the only thing that pops `true`.
        onClose: () => Navigator.of(context).pop(false),
      ),
    );
  }
}

class _RenameBody extends StatelessWidget {
  final _RenameFlow flow;
  final IconData icon;
  final String headline;
  final String message;
  final String fieldLabel;
  final String fieldHint;
  final String successLabel;

  const _RenameBody({
    required this.flow,
    required this.icon,
    required this.headline,
    required this.message,
    required this.fieldLabel,
    required this.fieldHint,
    required this.successLabel,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_Phase>(
      valueListenable: flow.phase,
      builder: (context, phase, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        child: phase == _Phase.success
            // The app's one confirmation (`confirmation.dart`), in its beat
            // shape: there is nothing to read here beyond the word, so it
            // plays and takes the sheet with it.
            ? ConfirmationView(
                key: const ValueKey('success'),
                headline: successLabel,
                message: flow.name.text.trim().isEmpty ? null : flow.name.text.trim(),
                dismissAfter: const Duration(milliseconds: 1100),
                onDone: () => Navigator.of(context).pop(true),
              )
            : _EditingBody(
                key: const ValueKey('editing'),
                flow: flow,
                icon: icon,
                headline: headline,
                message: message,
                fieldLabel: fieldLabel,
                fieldHint: fieldHint,
                busy: phase == _Phase.busy,
              ),
      ),
    );
  }
}

class _EditingBody extends StatelessWidget {
  final _RenameFlow flow;
  final IconData icon;
  final String headline;
  final String message;
  final String fieldLabel;
  final String fieldHint;
  final bool busy;

  const _EditingBody({
    super.key,
    required this.flow,
    required this.icon,
    required this.headline,
    required this.message,
    required this.fieldLabel,
    required this.fieldHint,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 21, color: accent),
            ),
            const SizedBox(width: 14),
            // Capped and clipped: a headline is an account, and an account is
            // "iCloud (vorname.nachname@example.com)" often enough that letting
            // it wrap pushed the field it introduces off the bottom of the
            // sheet. Two lines is a long address on two lines; anything past
            // that is an address nobody reads to the end anyway.
            Expanded(
              child: Text(
                headline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.cardTitle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(message, style: AppText.body.copyWith(color: AppColors.muted)),
        const SizedBox(height: 18),
        SectionCard(
          radius: AppRadii.card,
          children: dividedRows(inset: true, [
            FieldGroup(
              label: fieldLabel,
              hint: fieldHint,
              child: FieldBox(
                child: TextField(
                  controller: flow.name,
                  enabled: !busy,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  style: AppText.searchInput,
                  decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                  onSubmitted: (_) => flow.submit(context),
                ),
              ),
            ),
          ]),
        ),
        ValueListenableBuilder<String?>(
          valueListenable: flow.error,
          builder: (context, message, _) => message == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: ErrorNote(message: message),
                ),
        ),
        if (busy) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Text(flow.busyLabel, style: AppText.body.copyWith(color: AppColors.muted)),
            ],
          ),
        ],
      ],
    );
  }
}
