import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'app_sheet.dart';
import 'confirmation.dart';
import 'error_note.dart';
import 'settings_chrome.dart';
import '../l10n/l10n.dart';

/// The last step of *every* "add a calendar" flow: what you picked, what it
/// will be called, and one blue check to say yes.
///
/// One sheet for all six providers on purpose. Picking a Bundesland, resolving
/// a street, coming back from Google's consent screen and typing an iCloud
/// password are four different ways of *choosing* a calendar, but they all end
/// the same way — "this is the calendar, here's its name, connect it" — and
/// before this each of them ended differently: some connected on the tap that
/// picked, some on a separate "Verbinden" button, none of them ever said it
/// had worked.
///
/// [onConfirm] is what actually happens when the check is tapped; it gets the
/// name from the field, already trimmed. The sheet stays open (and blocks the
/// close button) while it runs, shows the success beat when it returns, and
/// only then pops with `true`. If it throws, the sheet stays put with the
/// message under the field so the name isn't lost.
///
/// [extraFields] are card rows shown *above* the name field, for the one
/// question a particular provider still has to ask — which Abfuhrbezirk this
/// street belongs to, or the ICS link for a town no vendor serves. The caller
/// owns whatever state they hold (a `TextEditingController` it reads inside
/// [onConfirm]); anything that has to redraw on tap belongs in a
/// `StatefulBuilder`. They live in the sheet rather than on the page behind it
/// so that a rejected link is reported next to the field it was typed into,
/// which is the whole reason this sheet exists.
Future<bool> showConnectConfirmSheet({
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
  List<Widget> extraFields = const [],
}) async {
  fieldLabel ??= L.s.name;
  fieldHint ??= L.s.calendarNameInAporah;
  busyLabel ??= L.s.connectingEllipsis;
  successLabel ??= L.s.calendarConnected;

  final flow = _ConnectFlow(
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
    header: _ConfirmHeader(flow: flow, title: title),
    child: _ConnectConfirmBody(
      flow: flow,
      icon: icon,
      headline: headline,
      message: message,
      fieldLabel: fieldLabel,
      fieldHint: fieldHint,
      successLabel: successLabel,
      extraFields: extraFields,
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
class _ConnectFlow {
  _ConnectFlow({
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
class _ConfirmHeader extends StatelessWidget {
  final _ConnectFlow flow;
  final String title;

  const _ConfirmHeader({required this.flow, required this.title});

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

class _ConnectConfirmBody extends StatelessWidget {
  final _ConnectFlow flow;
  final IconData icon;
  final String headline;
  final String message;
  final String fieldLabel;
  final String fieldHint;
  final String successLabel;
  final List<Widget> extraFields;

  const _ConnectConfirmBody({
    required this.flow,
    required this.icon,
    required this.headline,
    required this.message,
    required this.fieldLabel,
    required this.fieldHint,
    required this.successLabel,
    required this.extraFields,
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
                extraFields: extraFields,
                busy: phase == _Phase.busy,
              ),
      ),
    );
  }
}

class _EditingBody extends StatelessWidget {
  final _ConnectFlow flow;
  final IconData icon;
  final String headline;
  final String message;
  final String fieldLabel;
  final String fieldHint;
  final List<Widget> extraFields;
  final bool busy;

  const _EditingBody({
    super.key,
    required this.flow,
    required this.icon,
    required this.headline,
    required this.message,
    required this.fieldLabel,
    required this.fieldHint,
    required this.extraFields,
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
            Expanded(child: Text(headline, style: AppText.cardTitle)),
          ],
        ),
        const SizedBox(height: 14),
        Text(message, style: AppText.body.copyWith(color: AppColors.muted)),
        const SizedBox(height: 18),
        SectionCard(
          radius: AppRadii.card,
          children: dividedRows(inset: true, [
            ...extraFields,
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
