import 'spend.dart';

/// A monthly budget for one category — `public.spend_budgets`.
///
/// **Only the limit is stored.** How much of it is used is a fold over this
/// month's spends ([SpendBudgetProgress]), for the reason every other figure on
/// the Ausgaben page is computed: a stored total is contradicted by the next
/// edit.
class SpendBudget {
  final String id;
  final String familyId;
  final SpendCategory category;

  /// Per calendar month, in cents, always positive.
  final int amountCents;

  /// The symbol the household picked for this budget, in the same
  /// `lucide:<name>` wire format as `lists.icon_asset` and `boxes.icon_asset`,
  /// or null to wear the category's own glyph.
  ///
  /// **Null is a real answer, not a missing one.** Every category already has a
  /// glyph, so a budget that was never given one has nothing to fall back
  /// *from*; storing the category's default here would freeze today's choice of
  /// glyph into every row and make a change to the icon set invisible to
  /// everyone who had already made a budget.
  final String? iconAsset;

  const SpendBudget({
    required this.id,
    required this.familyId,
    required this.category,
    required this.amountCents,
    this.iconAsset,
  });

  factory SpendBudget.fromMap(Map<String, dynamic> map) => SpendBudget(
    id: map['id'] as String,
    familyId: map['family_id'] as String,
    category: spendCategoryFrom(map['category'] as String?),
    amountCents: (map['amount_cents'] as num?)?.round() ?? 0,
    iconAsset: map['icon_asset'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'family_id': familyId,
    'category': category.wire,
    'amount_cents': amountCents,
    'icon_asset': iconAsset,
  };

  /// [clearIcon] drops back to the category's glyph — a null [iconAsset] means
  /// "leave it as it is", the way it does everywhere else.
  SpendBudget copyWith({int? amountCents, String? iconAsset, bool clearIcon = false}) => SpendBudget(
    id: id,
    familyId: familyId,
    category: category,
    amountCents: amountCents ?? this.amountCents,
    iconAsset: clearIcon ? null : (iconAsset ?? this.iconAsset),
  );
}

/// Where a budget stands today.
enum SpendBudgetStatus {
  /// At or under where the month's pace says it should be.
  onTrack,

  /// Under the limit, but spending faster than the days are passing — 60% gone
  /// on the 10th. The one state worth a nudge while there is still time to act.
  ahead,

  /// Past the limit.
  over,
}

/// A budget measured against this month's rows.
///
/// **Pace, not just the total.** 500 € of 800 € is fine on the 25th and a
/// warning on the 10th, and a ring that only showed 62 % would say the same
/// thing on both days.
class SpendBudgetProgress {
  final SpendBudget budget;
  final int spentCents;

  /// How far through the calendar month today is, 0 to 1.
  final double monthElapsed;

  const SpendBudgetProgress({required this.budget, required this.spentCents, required this.monthElapsed});

  /// Spent over limit. Past 1 when the budget is blown; callers clamp for drawing.
  double get share => spentCents / budget.amountCents;

  int get leftCents => budget.amountCents - spentCents;

  /// A tenth of slack on the pace before calling it: a single weekly shop on
  /// the 3rd is not a household running ahead of its month.
  SpendBudgetStatus get status {
    if (spentCents > budget.amountCents) return SpendBudgetStatus.over;
    if (share > monthElapsed + .1) return SpendBudgetStatus.ahead;
    return SpendBudgetStatus.onTrack;
  }
}

/// Folds [rows] into one progress per budget, in the order the budgets came in.
///
/// [rows] may hold anything; only the current calendar month is counted, and
/// every kind of spend — a budget is about the category, not about whether a
/// payment was planned.
List<SpendBudgetProgress> spendBudgetProgress(List<SpendBudget> budgets, List<Spend> rows, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final from = DateTime(at.year, at.month);
  final to = DateTime(at.year, at.month + 1);
  final elapsed = (at.difference(from).inSeconds / to.difference(from).inSeconds).clamp(0.0, 1.0);

  final byCategory = <SpendCategory, int>{};
  for (final s in rows) {
    if (s.occurredAt.isBefore(from) || !s.occurredAt.isBefore(to)) continue;
    byCategory[s.category] = (byCategory[s.category] ?? 0) + s.amountCents;
  }

  return [
    for (final b in budgets)
      SpendBudgetProgress(budget: b, spentCents: byCategory[b.category] ?? 0, monthElapsed: elapsed),
  ];
}
