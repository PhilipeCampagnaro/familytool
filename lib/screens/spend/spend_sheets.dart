import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../models/spend.dart';
import '../../state/family_state.dart';
import '../../state/spend_state.dart';
import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import '../../widgets/anchored_menu.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/glass.dart';
import '../../widgets/settings_chrome.dart';
import '../../widgets/segmented_control.dart';
import '../../widgets/toast_chip.dart';
import '../settings/wallet_capture_page.dart';
import 'spend_mark.dart';

// ---------------------------------------------------------------------------
// Looking at one payment
// ---------------------------------------------------------------------------

/// One spend, read-only — **this is what tapping a row opens.**
///
/// It used to open the edit form directly, which answered a question nobody
/// had asked: somebody tapping a line wants to know what that 43 € at REWE
/// was, and got a keyboard and five editable fields instead. Looking at a
/// thing and changing it are two different intentions, and the app already
/// draws that line everywhere else — an appointment opens as a detail sheet
/// whose header carries a pencil ([_buildEventDetailHeader] in the calendar),
/// and the form is one tap further in.
///
/// This is that pattern, down to the accent glass button in the right-hand
/// corner. That corner is where every sheet in the app saves from, which is
/// exactly why the glyph in it here is a pencil and not a check: a check would
/// promise this sheet has something to commit, and it has nothing to commit.
/// It is a receipt.
///
/// Deleting is not offered here either. It lives inside the edit sheet with
/// the rest of the destructive actions, so this one has no footer at all.
Future<void> showSpendDetailSheet(BuildContext context, WidgetRef ref, Spend spend) {
  return showAppSheet<void>(
    context: context,
    // Shorter than a form's 0.92: no keyboard is coming, and the body is a
    // head, one card of five lines and sometimes a note.
    heightFactor: 0.72,
    header: _SpendDetailHeader(spend: spend),
    child: _SpendDetailBody(spend: spend),
  );
}

/// The row as the notifier holds it *now*, falling back to the copy that was
/// tapped.
///
/// Read back by id rather than kept, because this sheet stays open underneath
/// the edit sheet: without the lookup somebody would correct an amount, come
/// back, and find the old one still sitting there. The fallback covers the one
/// frame between a delete and this sheet closing behind it.
Spend _liveSpend(WidgetRef ref, Spend fallback) =>
    ref.watch(spendProvider).spends.where((s) => s.id == fallback.id).firstOrNull ?? fallback;

/// [GlassIconButton]'s own diameter, so the title and the two buttons are one
/// row rather than three stacked ones.
const _spendDetailHeaderHeight = 40.0;

class _SpendDetailHeader extends ConsumerWidget {
  final Spend spend;

  const _SpendDetailHeader({required this.spend});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: SizedBox(
        height: _spendDetailHeaderHeight,
        child: Stack(
          children: [
            // Painted before the buttons and spanning the whole row, never as
            // a `Row` sibling of them: [GlassIconButton] is a native platform
            // view on iOS and Flutter content painted after one lands in a
            // composited overlay that can be dropped. See the calendar's
            // detail header, which is written around the same trap.
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: _spendDetailHeaderHeight + 14),
                child: Center(
                  child: Text(
                    L.s.spendLabel,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.sheetTitle,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: GlassIconButton(icon: AppIcons.x, onTap: () => Navigator.of(context).pop()),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: GlassConfirmButton(
                icon: AppIcons.pencilSimple,
                onTap: () async {
                  final navigator = Navigator.of(context);
                  // Deleting from inside the edit sheet would leave this one
                  // showing a payment that no longer exists, so it goes too
                  // and the tap lands back on the month.
                  if (await showSpendSheet(context, ref, spend: _liveSpend(ref, spend))) {
                    navigator.pop();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpendDetailBody extends ConsumerWidget {
  final Spend spend;

  const _SpendDetailBody({required this.spend});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = _liveSpend(ref, spend);
    final members = ref.watch(familyProvider).members;
    final payer = members.where((m) => m.userId == live.payerId).firstOrNull;
    final at = live.occurredAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The amount above the name, the same way the month header puts the
        // total above the month: the figure is what the row was opened for and
        // the shop is what it was for.
        Center(child: SpendMark(size: 54, merchant: live.merchant)),
        const SizedBox(height: 14),
        Text(formatMoney(live.amountCents, currency: live.currency), textAlign: TextAlign.center, style: AppText.screenTitle),
        const SizedBox(height: 4),
        Text(
          live.merchant,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppText.cardTitle,
        ),
        const SizedBox(height: 4),
        Text(
          L.s.weekdayWithDate(at.weekday % 7, at.day, at.month),
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(color: AppColors.inkSecondary),
        ),
        const SizedBox(height: 18),

        if (live.needsReview) ...[
          _ReviewNote(),
          const SizedBox(height: 12),
        ],

        SectionCard(
          children: [
            _FactRow(label: L.s.spendCategory, value: live.category.label, icon: live.category.icon),
            CardDivider(),
            _FactRow(label: L.s.spendKindLabel, value: live.kind.label),
            CardDivider(),
            // Never blank: a payer who has left the household is named as one
            // rather than folded into nobody, because the money was still
            // spent by somebody.
            _FactRow(label: L.s.spendPaidBy, value: payer?.name ?? L.s.spendFormerMember),
            if (live.cardLabel case final card?) ...[
              CardDivider(),
              _FactRow(label: L.s.spendCard, value: card),
            ],
            CardDivider(),
            _FactRow(
              label: L.s.spendSourceLabel,
              value: live.source == SpendSource.wallet ? L.s.spendSourceWallet : L.s.spendSourceManual,
            ),
          ],
        ),

        if (live.note?.trim().isNotEmpty ?? false) ...[
          const SizedBox(height: 12),
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(L.s.spendNote, style: AppText.microLabel),
                    const SizedBox(height: 6),
                    Text(live.note!.trim(), style: AppText.body),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// One line of the card: a label and what it says.
///
/// Shaped like the edit form's own rows minus the chevron, so the two sheets
/// read as the same five facts with and without a way to change them.
class _FactRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;

  const _FactRow({required this.label, required this.value, this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Text(label, style: AppText.rowTitle),
          const SizedBox(width: 16),
          // **One flex child, not a `Spacer` and a `Flexible`.** Those are flex
          // 1 apiece, so the free space was split between them and a short
          // value came to rest halfway across the row instead of against the
          // right edge. The gap is a fixed minimum now and everything left over
          // belongs to this box, which aligns its contents to its own end.
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (icon case final glyph?) ...[
                  AppIcon(glyph, size: 16, color: AppColors.inkTertiary),
                  const SizedBox(width: 7),
                ],
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.rowTitle.copyWith(color: AppColors.inkSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Why a row arrived with a hole in it, said where the hole is rather than on
/// the page above — the banner on the month tells people to tap the row, and
/// this is what they find when they do.
class _ReviewNote extends StatelessWidget {
  const _ReviewNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.cardSmall),
        border: Border.all(color: AppColors.danger.withValues(alpha: .35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(AppIcons.warning, size: 17, color: AppColors.danger),
          const SizedBox(width: 9),
          Expanded(
            child: Text(L.s.spendReviewDetail, style: AppText.body.copyWith(color: AppColors.inkSecondary)),
          ),
        ],
      ),
    );
  }
}

/// The sheet that adds a spend by hand, and edits one that is already there.
///
/// One sheet for both, because they ask the same five questions — the old web
/// app had a create form and an edit form that had already drifted into
/// disagreeing about which fields were required.
/// Answers **true when the spend was deleted from inside it**, which is the one
/// outcome the caller cannot see for itself: [showSpendDetailSheet] is still
/// open underneath and would be left showing a payment that no longer exists.
///
/// The check in the header is the only way to commit it. There used to be a
/// second one — a full-width "Fertig" at the foot of the form — which made the
/// same promise twice and put one of them at the end of a scroll, below a
/// delete action.
Future<bool> showSpendSheet(BuildContext context, WidgetRef ref, {Spend? spend}) async {
  final draft = _SpendDraft(spend);
  final deleted = await showAppSheet<bool>(
    context: context,
    // Not the shared `title:` header: that one pops on the check, and this form
    // refuses a save it cannot make — an empty amount has to leave the sheet
    // standing with what was typed still in it.
    header: _SpendFormHeader(draft: draft),
    child: _SpendForm(draft: draft),
  );

  // Not disposed on the spot: the sheet's own widgets are still mounted — and
  // still reading the controllers — while the route animates out. Same delay,
  // for the same reason, as `showRenameSheet`.
  unawaited(Future<void>.delayed(const Duration(milliseconds: 400), draft.dispose));
  return deleted ?? false;
}

/// Everything the sheet is typing, held by reference.
///
/// The header's check is built beside the body rather than inside it, so the
/// two need one object between them — the same arrangement the calendar's
/// `_EventForm` and `IconDraft` use.
class _SpendDraft {
  _SpendDraft(this.original)
      : merchant = TextEditingController(text: original?.merchant ?? ''),
        amount = TextEditingController(
          text: original == null ? '' : formatMoney(original.amountCents, withSymbol: false),
        ),
        note = TextEditingController(text: original?.note ?? ''),
        date = original?.occurredAt ?? DateTime.now(),
        category = original?.category,
        kind = original?.kind ?? SpendKind.budget;

  /// The row being corrected, or null on a fresh payment.
  final Spend? original;

  final TextEditingController merchant;
  final TextEditingController amount;
  final TextEditingController note;

  DateTime date;

  /// Null means "let the database decide from the merchant name".
  ///
  /// A real third state, not a default dressed up as one: it is what the
  /// `spends_classify` trigger reads as permission to classify, and it is how
  /// the one copy of the merchant rules stays the one copy. On an *edit* it
  /// starts at the row's actual category, because by then a human has seen it.
  SpendCategory? category;
  SpendKind kind;

  /// The write is in flight — the header's check becomes a spinner, so a second
  /// tap cannot file the same payment twice.
  final ValueNotifier<bool> saving = ValueNotifier(false);

  bool get editing => original != null;

  void dispose() {
    merchant.dispose();
    amount.dispose();
    note.dispose();
    saving.dispose();
  }
}

/// Close on the left, the accent check on the right — and a spinner in its
/// place while the payment is being filed.
///
/// The check greys out until there is a merchant, which is [_SaveButton]'s own
/// behaviour everywhere else; the amount cannot be guarded that way and is
/// answered by [_saveSpend] instead.
class _SpendFormHeader extends ConsumerWidget {
  final _SpendDraft draft;

  const _SpendFormHeader({required this.draft});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ValueListenableBuilder<bool>(
      valueListenable: draft.saving,
      builder: (context, saving, _) => SheetActionHeader(
        title: draft.editing ? L.s.spendEdit : L.s.spendAdd,
        action: saving ? SheetHeaderAction.busy : SheetHeaderAction.confirm,
        requiredField: draft.merchant,
        onConfirm: () => _saveSpend(context, ref, draft),
      ),
    );
  }
}

/// Files the payment, says so, and only then closes the sheet.
///
/// The confirmation is the point: a manual spend used to be committed in
/// silence — the sheet closed, and whether the row had reached the server or
/// died on the way was something you found out by going looking for it. The
/// chip is captured before the write for the usual reason ([confirmChipOf]):
/// this sheet is gone by the time there is anything to report.
Future<void> _saveSpend(BuildContext context, WidgetRef ref, _SpendDraft draft) async {
  if (draft.saving.value) return;

  final merchant = draft.merchant.text.trim();
  final cents = parseAmountCents(draft.amount.text);
  if (merchant.isEmpty || cents == null) {
    // The two fields that cannot be guessed. Everything else on this form has
    // a defensible default, which is why only these two can block a save. The
    // sheet stays open on top of what was typed — closing it would throw the
    // rest of the form away over a missing comma.
    confirmChipOf(context, kind: ToastKind.error)(L.s.spendNeedsMerchantAndAmount);
    return;
  }

  final confirm = confirmChipOf(context);
  final failed = confirmChipOf(context, kind: ToastKind.error);
  final navigator = Navigator.of(context);
  final notifier = ref.read(spendProvider.notifier);
  final note = draft.note.text.trim();

  draft.saving.value = true;
  final spend = draft.original;
  final saved = spend == null
      ? await notifier.addSpend(
          merchant: merchant,
          amountCents: cents,
          occurredAt: draft.date,
          category: draft.category,
          kind: draft.kind,
          note: note,
        )
      : await notifier.editSpend(
          spend.copyWith(
            merchant: merchant,
            amountCents: cents,
            occurredAt: draft.date,
            category: draft.category ?? spend.category,
            kind: draft.kind,
            note: note.isEmpty ? null : note,
            // Editing a flagged row *is* the review. Anything the user just
            // looked at and saved is, by definition, no longer waiting to be
            // looked at.
            needsReview: false,
          ),
        );

  // The sheet goes either way: a failed write has already rolled the row back
  // off the month, and leaving the form up would invite the same tap again.
  navigator.pop();
  if (saved) {
    confirm(spend == null ? L.s.spendSaved : L.s.spendUpdated);
  } else {
    failed(L.s.spendSaveFailed);
  }
}

class _SpendForm extends ConsumerStatefulWidget {
  final _SpendDraft draft;

  const _SpendForm({required this.draft});

  @override
  ConsumerState<_SpendForm> createState() => _SpendFormState();
}

class _SpendFormState extends ConsumerState<_SpendForm> {
  final _categoryAnchor = GlobalKey();

  /// The controllers and the picked values live on the draft, which outlives
  /// this widget — the header is built from the same object.
  _SpendDraft get _draft => widget.draft;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(L.s.spendKindQuestion, style: AppText.microLabel),
        ),
        SegmentedControl<SpendKind>(
          value: _draft.kind,
          onChanged: (kind) => setState(() => _draft.kind = kind),
          options: [
            SegmentedOption(value: SpendKind.budget, label: L.s.spendKindBudget, icon: AppIcons.repeat),
            SegmentedOption(value: SpendKind.extra, label: L.s.spendKindExtra, icon: AppIcons.sparkle),
          ],
        ),
        const SizedBox(height: 14),

        SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: TextField(
                controller: _draft.merchant,
                autofocus: !_draft.editing,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                style: AppText.inputTitle,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: L.s.spendMerchantPlaceholder,
                  isDense: true,
                ),
                // The category caption under it says "automatisch" and then
                // names what it would pick — except it cannot, because the
                // rules live in SQL. So it just re-reads, which keeps the
                // placeholder honest about being a guess made elsewhere.
                onChanged: (_) => setState(() {}),
              ),
            ),
            CardDivider(),
            _AmountField(controller: _draft.amount),
            CardDivider(),
            _DateField(value: _draft.date, onChanged: (value) => setState(() => _draft.date = value)),
            CardDivider(),
            _CategoryField(
              anchorKey: _categoryAnchor,
              value: _draft.category,
              onChanged: (value) => setState(() => _draft.category = value),
            ),
            CardDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: TextField(
                controller: _draft.note,
                textCapitalization: TextCapitalization.sentences,
                style: AppText.input,
                maxLines: 3,
                minLines: 1,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: L.s.spendNotePlaceholder,
                  isDense: true,
                ),
              ),
            ),
          ],
        ),

        if (_draft.editing) ...[
          const SizedBox(height: 14),
          OutlinedSheetAction(
            icon: AppIcons.trash,
            label: L.s.delete,
            destructive: true,
            onTap: () async {
              // Both captured before the write: this sheet is popped by it.
              final confirm = confirmChipOf(context);
              final navigator = Navigator.of(context);
              final notifier = ref.read(spendProvider.notifier);
              navigator.pop(true);
              if (await notifier.deleteSpend(_draft.original!.id) case final deleted?) {
                confirm(L.s.spendDeleted, undo: () => notifier.undoDelete(deleted));
              }
            },
          ),
        ],
      ],
    );
  }
}

/// What somebody typed into the amount field, in cents, or null.
///
/// Accepts both decimal conventions because a German keyboard's number pad
/// offers a comma and the app is also in English: "12,34" and "12.34" are the
/// same twelve euros thirty-four and refusing one of them would be pedantry
/// about a separator the user did not choose.
int? parseAmountCents(String input) {
  final cleaned = input.trim().replaceAll(RegExp(r'[^\d.,]'), '');
  if (cleaned.isEmpty) return null;

  final lastComma = cleaned.lastIndexOf(',');
  final lastDot = cleaned.lastIndexOf('.');
  final normalised = lastComma > lastDot
      ? cleaned.replaceAll('.', '').replaceAll(',', '.')
      : cleaned.replaceAll(',', '');

  final value = double.tryParse(normalised);
  if (value == null || value.isNaN || value.isInfinite) return null;
  return (value.abs() * 100).round();
}

class _AmountField extends StatelessWidget {
  final TextEditingController controller;

  const _AmountField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(L.s.spendAmount, style: AppText.rowTitle),
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
              controller: controller,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              // Digits and both separators. Not a formatter that reformats as
              // you type: those fight the cursor, and this field is three
              // keystrokes long.
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
              style: AppText.inputTitle,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: '0${L.s.decimalSeparator}00',
                isDense: true,
                suffixText: '€',
                suffixStyle: AppText.inputTitle.copyWith(color: AppColors.inkSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  const _DateField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          // Two years back is well past anything anybody is still entering by
          // hand, and tomorrow is not a thing you have spent yet.
          firstDate: DateTime(value.year - 2),
          lastDate: DateTime.now(),
        );
        if (picked != null) {
          onChanged(DateTime(picked.year, picked.month, picked.day, value.hour, value.minute));
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Text(L.s.spendDate, style: AppText.rowTitle),
            const Spacer(),
            Text(
              L.s.dayMonth(value.day, value.month),
              style: AppText.rowTitle.copyWith(color: AppColors.inkSecondary),
            ),
            const SizedBox(width: 6),
            AppIcon(AppIcons.caretRight, size: 14, flat: true, color: AppColors.inkTertiary),
          ],
        ),
      ),
    );
  }
}

class _CategoryField extends StatelessWidget {
  final GlobalKey anchorKey;
  final SpendCategory? value;
  final ValueChanged<SpendCategory?> onChanged;

  const _CategoryField({required this.anchorKey, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: anchorKey,
      onTap: () => showAnchoredMenu(
        context: context,
        anchorKey: anchorKey,
        title: L.s.spendCategory,
        items: [
          AnchoredMenuItem(
            label: L.s.spendCategoryAuto,
            icon: AppIcons.sparkle,
            symbol: 'wand.and.stars',
            onSelected: () => onChanged(null),
          ),
          for (final category in SpendCategory.values)
            AnchoredMenuItem(
              label: category.label,
              icon: category.icon,
              onSelected: () => onChanged(category),
            ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Text(L.s.spendCategory, style: AppText.rowTitle),
            const Spacer(),
            Text(
              value?.label ?? L.s.spendCategoryAuto,
              style: AppText.rowTitle.copyWith(color: AppColors.inkSecondary),
            ),
            const SizedBox(width: 6),
            AppIcon(AppIcons.caretRight, size: 14, flat: true, color: AppColors.inkTertiary),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The way through to Apple Pay capture
// ---------------------------------------------------------------------------

/// One row on the Ausgaben page, saying whether this iPhone files payments by
/// itself and leading to the page where that is decided.
///
/// **Setup does not live here any more.** The card this replaces carried the
/// intro, the activate button, four numbered steps and a link into Shortcuts,
/// under every full month of spending — a page about last month's groceries
/// ending in a setup guide that never goes away, while the Apple Pay page in
/// Settings listed the household's phones and pointed *back* here for the one
/// button that mattered. Both halves now sit on
/// [WalletCapturePage](../settings/wallet_capture_page.dart); this row is the second way
/// in, because the wish for automatic capture arrives while looking at money,
/// not while looking at Settings.
///
/// The page is pushed rather than jumped to: Ausgaben is a tab, Settings is a
/// route over the shell, and the X in that page's header leaves for the tab the
/// reader was already on.
class WalletSetupCard extends ConsumerWidget {
  const WalletSetupCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(spendProvider);

    // Off both phone platforms there is nothing to switch on and the row would
    // lead to a page that says so. `SpendScreen` ships where `spendAvailable` is
    // true anyway, so this is the belt to that braces.
    final intents = ref.watch(spendIntentsProvider);
    if (!intents.isSupported) return const SizedBox.shrink();

    // **Android is set up when both switches are on, not when the token is
    // stored.** A row reading "aktiv" over a phone that has been enrolled but
    // never granted notification access would describe a capture that files
    // nothing, which is the one thing this subtitle exists to prevent.
    final ready = intents.usesNotificationAccess
        ? state.thisDeviceEnrolled && state.notificationAccess
        : state.thisDeviceEnrolled;

    return SectionCard(
      radius: AppRadii.card,
      children: [
        SettingsRow(
          icon: AppIcons.wallet,
          title: intents.usesNotificationAccess
              ? L.s.spendWalletAndroidTitle
              : L.s.spendWalletTitle,
          subtitle: intents.usesNotificationAccess
              ? (ready ? L.s.spendWalletAndroidActive : L.s.spendWalletAndroidInactive)
              : (ready ? L.s.spendWalletActive : L.s.spendWalletInactive),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => WalletCapturePage(parentTitle: L.s.spendTitle),
            ),
          ),
        ),
      ],
    );
  }
}
