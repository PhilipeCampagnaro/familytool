import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';
import 'app_sheet.dart';
import 'error_note.dart';
import 'glass.dart';
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
/// there is a request in flight that closing would not cancel.
class _ConfirmHeader extends StatelessWidget {
  final _ConnectFlow flow;
  final String title;

  const _ConfirmHeader({required this.flow, required this.title});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_Phase>(
      valueListenable: flow.phase,
      builder: (context, phase, _) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: SizedBox(
          height: 40,
          child: Stack(
            children: [
              // Painted before either button — see [showAppSheet] for why a
              // title between two glass platform views disappears on device.
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 54),
                  child: Center(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.sheetTitle,
                    ),
                  ),
                ),
              ),
              if (phase == _Phase.editing)
                Align(
                  alignment: Alignment.centerLeft,
                  child: GlassIconButton(
                    icon: LucideIcons.x,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: switch (phase) {
                  _Phase.editing => GlassConfirmButton(onTap: () => flow.submit(context)),
                  _Phase.busy => const SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  ),
                  _Phase.success => const SizedBox(width: 40, height: 40),
                },
              ),
            ],
          ),
        ),
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
            ? _SuccessBeat(
                key: const ValueKey('success'),
                label: successLabel,
                name: flow.name.text.trim(),
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

/// The beat between "connected" and the sheet closing.
///
/// Short on purpose — long enough to read the word, not long enough to be a
/// step of its own. The ring pops out from under the check rather than the
/// check bouncing, which keeps the motion in the same ease-out language as the
/// rest of the app.
class _SuccessBeat extends StatefulWidget {
  final String label;
  final String name;
  final VoidCallback onDone;

  const _SuccessBeat({super.key, required this.label, required this.name, required this.onDone});

  @override
  State<_SuccessBeat> createState() => _SuccessBeatState();
}

class _SuccessBeatState extends State<_SuccessBeat> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  late final CurvedAnimation _pop = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.3, curve: Curves.easeOutBack),
  );
  late final CurvedAnimation _ring = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.1, 0.55, curve: Curves.easeOutCubic),
  );
  late final CurvedAnimation _text = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.25, 0.6, curve: Curves.easeOutCubic),
  );

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onDone();
    });
  }

  @override
  void dispose() {
    _pop.dispose();
    _ring.dispose();
    _text.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          const SizedBox(height: 30),
          SizedBox(
            width: 130,
            height: 130,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: (1 - _ring.value).clamp(0.0, 1.0) * 0.35,
                    child: Container(
                      width: 78 + 52 * _ring.value,
                      height: 78 + 52 * _ring.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: accent, width: 2),
                      ),
                    ),
                  ),
                  Transform.scale(
                    scale: _pop.value,
                    child: Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                        boxShadow: AppShadows.accentGlass(accent),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(LucideIcons.check, size: 38, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          FadeTransition(
            opacity: _text,
            child: Column(
              children: [
                Text(widget.label, style: AppText.cardTitle),
                if (widget.name.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.name,
                    textAlign: TextAlign.center,
                    style: AppText.body.copyWith(color: AppColors.muted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
