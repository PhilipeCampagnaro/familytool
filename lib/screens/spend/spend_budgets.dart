import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../models/spend.dart';
import '../../models/spend_budget.dart';
import '../../state/spend_state.dart';
import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import '../../widgets/icon_picker.dart';
import '../../widgets/segmented_progress_bar.dart';
import 'spend_explore.dart';
import 'spend_sheets.dart';

/// The household's budgets, one ring each, above the chart card — and the "+"
/// that adds one.
///
/// **A ring rather than a bar, because it is a thing to glance at, not to
/// read.** The arc is how much of the month's budget is gone. There is no mark
/// for where today is in the month — at this size a tick across the band read as
/// a glitch in the ring — so the pace shows in the percentage underneath
/// instead. **The arcs are all one colour, and red means over**, never merely
/// fast: see [_arcColor].
///
/// **No text under a ring: the symbol names the budget** — the "+" at the end
/// keeps its one word, because an empty circle names nothing. Which is why the
/// symbol is the household's to pick ([SpendBudget.iconAsset]) rather than the
/// category's to dictate — a category glyph is a reasonable default and a poor
/// caption, and `Sonstiges` has no picture at all. The name is still read out
/// by VoiceOver on the bubble, and still written in full on the explore page a
/// tap away.
///
/// Always about **this calendar month**, whatever the slicer below says: a
/// budget is a monthly promise, and a ring that measured a picked week against
/// it would be measuring nothing.
class SpendBudgetStrip extends ConsumerWidget {
  const SpendBudgetStrip({super.key});

  static const double ring = 62;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(spendProvider).budgetProgress;

    return Semantics(
      container: true,
      label: L.s.spendBudgets,
      child: SizedBox(
        height: ring + 24,
        child: ListView(
          scrollDirection: Axis.horizontal,
          // The rings may run into the page gutter while they scroll; the
          // panel's own edge is what clips them.
          clipBehavior: Clip.none,
          padding: EdgeInsets.zero,
          children: [
            for (final p in progress) _BudgetBubble(progress: p),
            _AddBubble(),
          ],
        ),
      ),
    );
  }
}

/// What a budget's state is called, in the sheet and on the explore page's card.
String spendBudgetStatusLabel(SpendBudgetStatus status) => switch (status) {
  SpendBudgetStatus.onTrack => L.s.spendBudgetOnTrack,
  SpendBudgetStatus.ahead => L.s.spendBudgetAhead,
  SpendBudgetStatus.over => L.s.spendBudgetExceeded,
};

/// The ink for a budget's figures: plain until the budget is over, the danger
/// colour once it is.
///
/// **Red answers one question here — is this one blown — and
/// [SpendBudgetStatus.ahead] is not that question.** A budget at 94% in the middle
/// of the month is running fast and still kept; colouring it the same as one at
/// 108% asked the reader to check the number to find out which they were looking
/// at, which is the work a colour is there to save. Ahead still says so in words
/// on the budget's card.
Color spendBudgetInk(SpendBudgetProgress p) =>
    p.status == SpendBudgetStatus.over ? AppColors.danger : AppColors.inkSecondary;

/// The arc's colour: the accent for every budget, the danger colour for one that
/// is over.
///
/// **Colour here means one thing, and it is not which category this is.** The
/// label under the ring already says that, and the donut below is where the
/// seven category hues belong; a strip that wore them too spent its only loud
/// signal on something the reader was not asking. So the arcs read as one row
/// of budgets and red is reserved for the answer that matters — this one is
/// blown. Not [SpendBudgetStatus.ahead]: running ahead of the month is a pace,
/// which is what the percentage underneath is coloured for.
Color _arcColor(SpendBudgetProgress p) =>
    p.status == SpendBudgetStatus.over ? AppColors.danger : AppColors.accent;

class _BudgetBubble extends ConsumerWidget {
  final SpendBudgetProgress progress;

  const _BudgetBubble({required this.progress});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = progress;
    final category = p.budget.category;
    final currency = 'EUR';

    return Semantics(
      button: true,
      label:
          '${category.label}, '
          '${L.s.spendBudgetOf(formatMoneyShort(p.spentCents, currency: currency), formatMoneyShort(p.budget.amountCents, currency: currency))}, '
          '${spendBudgetStatusLabel(p.status)}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // A tap asks "what went into this", which is the explore page filtered
        // to the category. Changing the budget is a hold, or the pencil on that
        // page — the less common wish gets the less obvious gesture.
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => SpendExplorePage(category: category))),
        onLongPress: () {
          HapticFeedback.selectionClick();
          showBudgetSheet(context, ref, budget: p.budget);
        },
        child: SizedBox(
          width: SpendBudgetStrip.ring + 16,
          child: Column(
            children: [
              _BudgetRing(progress: p),
              const SizedBox(height: 4),
              Text(
                L.s.percent((p.share * 100).round()),
                style: AppText.caption.copyWith(color: spendBudgetInk(p), fontWeight: FontWeight.w600),
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BudgetRing extends StatelessWidget {
  final SpendBudgetProgress progress;

  const _BudgetRing({required this.progress});

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final still = MediaQuery.disableAnimationsOf(context);
    final share = p.share.clamp(0.0, 1.0);

    return SizedBox(
      width: SpendBudgetStrip.ring,
      height: SpendBudgetStrip.ring,
      // Grows from nothing on first sight and glides between readings after,
      // the way the donut below it is drawn on.
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: share),
        duration: still ? Duration.zero : const Duration(milliseconds: 620),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => CustomPaint(
          painter: _BudgetRingPainter(share: value, arc: _arcColor(p), track: AppColors.hairline),
          child: child,
        ),
        child: Center(
          // The household's symbol where there is one, the category's glyph
          // where there is not — see [SpendBudget.iconAsset]. Drawn on nothing:
          // [IconTile]'s disc would put a second circle inside the ring.
          child: IconTile(
            iconKey: p.budget.iconAsset,
            size: 30,
            imageSize: 26,
            glyphSize: 26,
            fallbackIcon: p.budget.category.icon,
            glyphColor: AppColors.ink,
            background: Colors.transparent,
            border: false,
          ),
        ),
      ),
    );
  }
}

class _BudgetRingPainter extends CustomPainter {
  final double share;
  final Color arc;
  final Color track;

  const _BudgetRingPainter({required this.share, required this.arc, required this.track});

  static const _stroke = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_stroke / 2 + 1);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;

    canvas.drawArc(rect, 0, math.pi * 2, false, stroke..color = track);
    if (share > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * share,
        false,
        stroke
          ..color = arc
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_BudgetRingPainter old) => old.share != share || old.arc != arc || old.track != track;
}

class _AddBubble extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      label: L.s.spendBudgetAdd,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showBudgetSheet(context, ref),
        child: SizedBox(
          width: SpendBudgetStrip.ring + 16,
          child: Column(
            children: [
              Container(
                width: SpendBudgetStrip.ring,
                height: SpendBudgetStrip.ring,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.hairline, width: 1.5),
                ),
                child: Center(
                  child: AppIcon(AppIcons.plus, size: AppGlyph.row, flat: true, color: AppColors.accent),
                ),
              ),
              const SizedBox(height: 4),
              // The one word left under the strip, and it sits on the same line
              // the rings put their percentage on — so it labels the "+" rather
              // than floating under a row that has no other text. It says what
              // the tap makes, which is what the bubbles beside it are; "Neues
              // Budget" is the sheet's own title and too long to fit here
              // anyway.
              Text(
                L.s.spendBudget,
                style: AppText.caption.copyWith(color: AppColors.inkSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A category's budget written out, for the top of the explore page — or the
/// offer to set one when there is none.
class SpendBudgetCard extends ConsumerWidget {
  final SpendCategory category;
  final SpendBudgetProgress? progress;

  const SpendBudgetCard({super.key, required this.category, required this.progress});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = progress;

    final Widget body;
    if (p == null) {
      body = Row(
        children: [
          AppIcon(AppIcons.chartPieSlice, size: AppGlyph.row, color: AppColors.ink),
          const SizedBox(width: 12),
          Expanded(child: Text(L.s.spendBudgetAdd, style: AppText.rowTitle)),
          AppIcon(AppIcons.plus, size: AppGlyph.inline, flat: true, color: AppColors.accent),
        ],
      );
    } else {
      const currency = 'EUR';
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  L.s.spendBudgetOf(
                    formatMoneyShort(p.spentCents, currency: currency),
                    formatMoneyShort(p.budget.amountCents, currency: currency),
                  ),
                  style: AppText.itemTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              AppIcon(AppIcons.pencilSimple, size: AppGlyph.inline, flat: true, color: AppColors.muted),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedProgressBar(value: p.share, color: _arcColor(p), track: AppColors.hairline),
          const SizedBox(height: 8),
          Text(
            [
              spendBudgetStatusLabel(p.status),
              p.leftCents >= 0
                  ? L.s.spendBudgetLeft(formatMoneyShort(p.leftCents, currency: currency))
                  : L.s.spendBudgetOver(formatMoneyShort(-p.leftCents, currency: currency)),
              L.s.spendRangeThisMonth,
            ].join(' · '),
            style: AppText.body.copyWith(color: spendBudgetInk(p)),
            maxLines: 2,
          ),
        ],
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showBudgetSheet(context, ref, budget: p?.budget, category: category),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.cardPad),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.card),
          boxShadow: AppShadows.card,
        ),
        child: body,
      ),
    );
  }
}
