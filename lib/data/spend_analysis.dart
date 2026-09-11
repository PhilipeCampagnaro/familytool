import '../l10n/l10n.dart';
import '../models/spend.dart';

/// What a stretch of spending adds up to, computed rather than stored.
///
/// Same reasoning as `german_holidays.dart` and `tracker_data.dart`: the rows
/// are the truth and every number on the Spend page is a fold over them, so
/// there is nothing here worth a column, a cache or a materialised total. A
/// household's year is a few thousand rows; folding them is cheaper than the
/// round trip that would fetch a stored answer, and a stored answer could be
/// wrong after an edit.
///
/// **Everything is integer cents.** Percentages and the one elapsed-fraction
/// are the only places a double appears, and they are only ever drawn.

// ---------------------------------------------------------------------------
// The stretch of time
// ---------------------------------------------------------------------------

/// The four spans the slicer offers, plus the one a date picker produces.
///
/// **Every preset is aligned to the calendar rather than counted back from
/// today.** "Dieses Jahr" has to mean January to December or the comparison
/// against last year is a comparison of two arbitrary windows, and a household
/// asking "what did we spend this month" means the month on the wall.
enum SpendPeriod {
  week,
  month,
  halfYear,
  year,
  custom;

  /// What the slicer prints on the segment. Custom has none — it lives behind
  /// the calendar button instead.
  String get shortLabel => switch (this) {
    SpendPeriod.week => L.s.spendRangeWeek,
    SpendPeriod.month => L.s.spendRangeMonth,
    SpendPeriod.halfYear => L.s.spendRangeHalfYear,
    SpendPeriod.year => L.s.spendRangeYear,
    SpendPeriod.custom => '',
  };
}

/// Whether a bar is a day or a month.
///
/// There is no week bucket on purpose: a six-month span in weeks is 26 bars
/// nobody can label, and a month in weeks is five, of which two are stubs.
enum SpendBucketUnit { day, month }

/// The half-open stretch the page is adding up, and which preset produced it.
///
/// Half-open in local midnights, so the last payment of one bucket and the
/// first of the next cannot both land in the same one or fall between two.
class SpendRange {
  final SpendPeriod period;
  final DateTime from;
  final DateTime to;

  const SpendRange({required this.period, required this.from, required this.to});

  /// The calendar span [period] names around [now].
  factory SpendRange.of(SpendPeriod period, {DateTime? now}) {
    final today = _midnight(now ?? DateTime.now());
    return switch (period) {
      // Monday to Monday. `DateTime.weekday` is 1 on Monday, so subtracting
      // one lands on it without a modulo.
      SpendPeriod.week => SpendRange(
        period: period,
        from: today.subtract(Duration(days: today.weekday - 1)),
        to: today.subtract(Duration(days: today.weekday - 1)).add(const Duration(days: 7)),
      ),
      SpendPeriod.month => SpendRange(
        period: period,
        from: DateTime(today.year, today.month),
        to: DateTime(today.year, today.month + 1),
      ),
      // This month and the five before it, so the current month is the last
      // bar rather than the middle one.
      SpendPeriod.halfYear => SpendRange(
        period: period,
        from: DateTime(today.year, today.month - 5),
        to: DateTime(today.year, today.month + 1),
      ),
      SpendPeriod.year => SpendRange(
        period: period,
        from: DateTime(today.year),
        to: DateTime(today.year + 1),
      ),
      // Not reachable from the slicer; a custom range is built from two picked
      // days by [SpendRange.custom]. Answering with today keeps the switch
      // total rather than throwing on a value the compiler must still allow.
      SpendPeriod.custom => SpendRange(period: period, from: today, to: today.add(const Duration(days: 1))),
    };
  }

  /// Two days the user picked, **both inclusive** — which is what a date picker
  /// means and not what the rest of this file does, so the end is pushed to the
  /// following midnight here rather than at every call site.
  factory SpendRange.custom(DateTime firstDay, DateTime lastDay) {
    final from = _midnight(firstDay);
    final to = _midnight(lastDay).add(const Duration(days: 1));
    return SpendRange(period: SpendPeriod.custom, from: from, to: to.isAfter(from) ? to : from.add(const Duration(days: 1)));
  }

  /// The same stretch immediately before this one, for the comparison line.
  ///
  /// Shifted by the *calendar* unit rather than by a duration wherever there is
  /// one: February against January is the comparison a household means, and
  /// subtracting 31 days from 1 March lands on 29 January.
  SpendRange get previous => switch (period) {
    SpendPeriod.week => SpendRange(
      period: period,
      from: from.subtract(const Duration(days: 7)),
      to: from,
    ),
    SpendPeriod.month => SpendRange(period: period, from: DateTime(from.year, from.month - 1), to: from),
    SpendPeriod.halfYear => SpendRange(period: period, from: DateTime(from.year, from.month - 6), to: from),
    SpendPeriod.year => SpendRange(period: period, from: DateTime(from.year - 1), to: from),
    SpendPeriod.custom => SpendRange(period: period, from: from.subtract(to.difference(from)), to: from),
  };

  int get days => to.difference(from).inDays;

  /// Days below the threshold, months above it. Twelve weeks of daily bars is
  /// already a dense chart; past that the labels stop being readable at all.
  SpendBucketUnit get unit => switch (period) {
    SpendPeriod.week || SpendPeriod.month => SpendBucketUnit.day,
    SpendPeriod.halfYear || SpendPeriod.year => SpendBucketUnit.month,
    SpendPeriod.custom => days <= 84 ? SpendBucketUnit.day : SpendBucketUnit.month,
  };

  bool contains(DateTime at) => !at.isBefore(from) && at.isBefore(to);

  /// What the page prints under the total — "Dieses Jahr", or the two dates.
  String get caption => switch (period) {
    SpendPeriod.week => L.s.spendRangeThisWeek,
    SpendPeriod.month => L.s.spendRangeThisMonth,
    SpendPeriod.halfYear => L.s.spendRangeLastSixMonths,
    SpendPeriod.year => L.s.spendRangeThisYear,
    SpendPeriod.custom => L.s.dateRange(
      L.s.dayMonthShort(from.day, from.month),
      L.s.dayMonthShort(lastDay.day, lastDay.month),
    ),
  };

  /// The last day *inside* the range, for anything that shows a range to a
  /// person — who reads "1.–31. März" and not "1. März bis 1. April".
  DateTime get lastDay => to.subtract(const Duration(days: 1));

  @override
  bool operator ==(Object other) =>
      other is SpendRange && other.period == period && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(period, from, to);
}

DateTime _midnight(DateTime at) => DateTime(at.year, at.month, at.day);

// ---------------------------------------------------------------------------
// What is being counted
// ---------------------------------------------------------------------------

/// Which rows the page is adding up.
///
/// The picker that changes this sits where the total's own label would be,
/// because it *is* the total's label: swapping it changes what every number on
/// the page means, and a filter chip somewhere else would leave the headline
/// saying "Ausgaben" over a figure that is only the fixed ones.
enum SpendMetric {
  all,
  budget,
  extra;

  String get label => switch (this) {
    SpendMetric.all => L.s.spendMetricAll,
    SpendMetric.budget => L.s.spendKindBudget,
    SpendMetric.extra => L.s.spendKindExtra,
  };

  bool accepts(Spend spend) => switch (this) {
    SpendMetric.all => true,
    SpendMetric.budget => spend.kind == SpendKind.budget,
    SpendMetric.extra => spend.kind == SpendKind.extra,
  };
}

// ---------------------------------------------------------------------------
// The folds
// ---------------------------------------------------------------------------

/// One slice of a breakdown — a category, a merchant or a member.
///
/// `share` is of the total it was computed against, 0 to 1. It is carried rather
/// than recomputed at the call site because the ring, the legend and the bar
/// widths must all agree to the same rounding.
class SpendSlice<T> {
  final T key;
  final int cents;
  final int count;
  final double share;

  const SpendSlice({required this.key, required this.cents, required this.count, required this.share});
}

/// One bar, and one point on the line.
class SpendBucket {
  final DateTime from;
  final DateTime to;
  final int cents;

  /// The axis label — a weekday, a day number or a month's short name. The
  /// charts shorten it further when there are too many to print in full.
  final String label;

  /// Wholly ahead of now, so nothing was ever going to be in it. Drawn as a gap
  /// rather than as a zero: an empty December in September is not a December
  /// nobody spent anything in.
  final bool isFuture;

  const SpendBucket({
    required this.from,
    required this.to,
    required this.cents,
    required this.label,
    required this.isFuture,
  });

  /// The bucket said in full, for the headline while a finger is on the chart.
  ///
  /// [label] is what fits under an axis — "14", "Mo", "Mär" — and none of those
  /// is an answer to "which day is this". A bucket one day long is a date; a
  /// longer one is a month and a year, because the six-month view crosses New
  /// Year and "Jan" alone would be ambiguous exactly where it matters.
  String get caption => to.difference(from).inDays <= 1
      ? L.s.dayMonth(from.day, from.month)
      : L.s.monthYear(from.month, from.year);
}

/// Everything the Spend page draws for one range.
class SpendSummary {
  final SpendRange range;
  final SpendMetric metric;

  /// The range's own rows, newest first, after [metric]. The page's transaction
  /// list and `displayMerchant` both want exactly these, and filtering twice is
  /// how the list and the ring end up disagreeing.
  final List<Spend> rows;

  final int totalCents;

  /// The same-length stretch before this one. Null when nothing was recorded
  /// then — which is not the same as zero, and the page says so rather than
  /// claiming a rise from nothing.
  final int? previousTotalCents;

  final int transactionCount;

  /// Descending by amount. Categories nobody spent anything in are absent, not
  /// present at zero: an empty slice is a lie about the shape of the range.
  final List<SpendSlice<SpendCategory>> byCategory;

  /// Descending by amount, uncapped. This is the "wo gebe ich am meisten aus"
  /// answer, and it is by *merchant* rather than by category because "€340 bei
  /// REWE" is actionable and "€340 Lebensmittel" is not. The card takes the
  /// first few; nothing here decides how many.
  final List<SpendSlice<String>> byMerchant;

  /// Descending by amount, keyed by `payer_id`. The key is null for a member
  /// who has since left the household.
  final List<SpendSlice<String?>> byMember;

  final int budgetCents;
  final int extraCents;

  /// One entry per day or month of the range, in order, including the ones
  /// nothing was spent in. The zeroes matter — they are what makes a bar chart
  /// show the rhythm of a month rather than a row of bars with the gaps
  /// squeezed out.
  final List<SpendBucket> buckets;

  /// The previous range in the same unit, for the grey comparison line. Never
  /// has future buckets, so it always runs the full width.
  final List<SpendBucket> previousBuckets;

  /// Rows the Wallet automation filed with a hole in them, newest first.
  ///
  /// Computed **before** [metric], because a row nobody has looked at yet is
  /// exactly the row whose kind cannot be trusted to decide whether to show it.
  final List<Spend> needsReview;

  const SpendSummary({
    required this.range,
    required this.metric,
    required this.rows,
    required this.totalCents,
    required this.previousTotalCents,
    required this.transactionCount,
    required this.byCategory,
    required this.byMerchant,
    required this.byMember,
    required this.budgetCents,
    required this.extraCents,
    required this.buckets,
    required this.previousBuckets,
    required this.needsReview,
  });

  bool get isEmpty => transactionCount == 0;

  /// The difference in cents against the previous stretch, which is what the
  /// trend view prints — a household reads "€12.868 mehr" faster than "+15 %",
  /// and the percentage is still there in the row below.
  int? get changeCents {
    final prev = previousTotalCents;
    return prev == null ? null : totalCents - prev;
  }

  /// Change against the previous stretch, as a fraction — `0.12` is twelve
  /// percent more. Null when there is nothing to compare against, or when it was
  /// genuinely zero: dividing by it would produce an infinity that renders as a
  /// shrug.
  double? get changeVsPrevious {
    final prev = previousTotalCents;
    if (prev == null || prev == 0) return null;
    return (totalCents - prev) / prev;
  }

  /// How much of the range has actually been lived, in buckets — 8.4 on the
  /// 12th of a ninth month.
  ///
  /// A fraction rather than a count because it divides the average: counting
  /// the current bucket whole makes September drag a yearly average down by a
  /// tenth on the 2nd, and dropping it throws away the money already spent in
  /// it. Never zero, so callers can divide without guarding.
  double get elapsedUnits {
    final now = DateTime.now();
    var units = 0.0;
    for (final bucket in buckets) {
      if (bucket.isFuture) continue;
      final span = bucket.to.difference(bucket.from).inSeconds;
      final lived = now.difference(bucket.from).inSeconds;
      units += span == 0 ? 1 : (lived / span).clamp(0.0, 1.0);
    }
    return units <= 0 ? 1 : units;
  }

  /// The average bar — per day or per month, whichever the range is bucketed
  /// in. The bar chart draws this as its dashed line.
  int get averagePerUnitCents => (totalCents / elapsedUnits).round();

  int get averagePerTransactionCents =>
      transactionCount == 0 ? 0 : (totalCents / transactionCount).round();

  /// The biggest bucket, for scaling a bar chart. Never zero, so a caller can
  /// divide by it without guarding.
  int get peakBucketCents {
    var top = 0;
    for (final b in buckets) {
      if (b.cents > top) top = b.cents;
    }
    return top == 0 ? 1 : top;
  }

  /// Running totals over the buckets that have started, which is what the trend
  /// chart draws — a month is read as "how far through the money are we", and
  /// that is a line that only ever climbs.
  List<int> get cumulative => _runningTotal(buckets, stopAtFuture: true);

  /// The same for the previous stretch, all the way to its end.
  List<int> get previousCumulative => _runningTotal(previousBuckets, stopAtFuture: false);

  static List<int> _runningTotal(List<SpendBucket> buckets, {required bool stopAtFuture}) {
    final out = <int>[];
    var sum = 0;
    for (final b in buckets) {
      if (stopAtFuture && b.isFuture) break;
      sum += b.cents;
      out.add(sum);
    }
    return out;
  }
}

/// Folds a range's rows into everything the page draws.
///
/// [all] may hold rows from either stretch; only those inside [range] are
/// counted, and rows from [SpendRange.previous] are used for the comparison
/// alone. Passing the whole loaded window rather than a pre-filtered list keeps
/// the "which rows belong to this range" rule in one place instead of at every
/// call site.
SpendSummary summariseRange(
  List<Spend> all,
  SpendRange range, {
  SpendMetric metric = SpendMetric.all,
  /// Null keeps every shop. The page's card shows a handful and its "alle
  /// anzeigen" page shows the lot, and both read the same fold — a cap here
  /// would mean the full list was a different list rather than more of the
  /// same one.
  int? topMerchants,
}) {
  final previousRange = range.previous;

  final rows = <Spend>[];
  final review = <Spend>[];
  var previousTotal = 0;
  var sawPrevious = false;

  for (final s in all) {
    final at = s.occurredAt;
    if (range.contains(at)) {
      if (s.needsReview) review.add(s);
      if (metric.accepts(s)) rows.add(s);
    } else if (previousRange.contains(at) && metric.accepts(s)) {
      previousTotal += s.amountCents;
      sawPrevious = true;
    }
  }

  review.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

  var total = 0;
  var budget = 0;
  var extra = 0;
  final byCategory = <SpendCategory, (int, int)>{};
  final byMerchant = <String, (int, int)>{};
  final byMember = <String?, (int, int)>{};

  for (final s in rows) {
    total += s.amountCents;
    if (s.kind == SpendKind.budget) {
      budget += s.amountCents;
    } else {
      extra += s.amountCents;
    }

    _add(byCategory, s.category, s.amountCents);
    // Merchants are folded case-insensitively and on trimmed whitespace: a
    // terminal reports "REWE", "Rewe Markt GmbH" and "rewe " as three shops
    // otherwise, and the top-merchants list is exactly where that shows.
    _add(byMerchant, _merchantKey(s.merchant), s.amountCents);
    _add(byMember, s.payerId, s.amountCents);
  }

  return SpendSummary(
    range: range,
    metric: metric,
    rows: rows,
    totalCents: total,
    previousTotalCents: sawPrevious ? previousTotal : null,
    transactionCount: rows.length,
    byCategory: _slices(byCategory, total),
    byMerchant: _slices(byMerchant, total, limit: topMerchants),
    byMember: _slices(byMember, total),
    budgetCents: budget,
    extraCents: extra,
    buckets: bucketise(rows, range),
    previousBuckets: bucketise(
      [for (final s in all) if (previousRange.contains(s.occurredAt) && metric.accepts(s)) s],
      previousRange,
    ),
    needsReview: review,
  );
}

/// Cuts [range] into bars and drops [rows] into them.
///
/// Public because the trend chart's comparison line is the same fold over a
/// different stretch, and two copies of the "which bar does this land in" rule
/// would be two chances to put a payment in the wrong week.
List<SpendBucket> bucketise(List<Spend> rows, SpendRange range) {
  final now = DateTime.now();
  final edges = <DateTime>[];

  if (range.unit == SpendBucketUnit.day) {
    for (var at = range.from; at.isBefore(range.to); at = at.add(const Duration(days: 1))) {
      edges.add(at);
    }
  } else {
    for (var at = DateTime(range.from.year, range.from.month);
        at.isBefore(range.to);
        at = DateTime(at.year, at.month + 1)) {
      edges.add(at);
    }
  }
  if (edges.isEmpty) return const [];

  final cents = List<int>.filled(edges.length, 0);
  for (final s in rows) {
    final at = s.occurredAt;
    if (!range.contains(at)) continue;
    final index = range.unit == SpendBucketUnit.day
        // Whole days apart rather than a Duration, so the hour of the payment
        // and the two days a year that are not 24 hours long cannot shift a row
        // into the bar next door.
        ? _daysBetween(range.from, at)
        : (at.year - edges.first.year) * 12 + (at.month - edges.first.month);
    if (index >= 0 && index < cents.length) cents[index] += s.amountCents;
  }

  return [
    for (var i = 0; i < edges.length; i++)
      SpendBucket(
        from: edges[i],
        to: i + 1 < edges.length
            ? edges[i + 1]
            : (range.unit == SpendBucketUnit.day
                  ? edges[i].add(const Duration(days: 1))
                  : DateTime(edges[i].year, edges[i].month + 1)),
        cents: cents[i],
        label: _bucketLabel(edges[i], range),
        isFuture: !edges[i].isBefore(now),
      ),
  ];
}

int _daysBetween(DateTime from, DateTime to) =>
    DateTime(to.year, to.month, to.day).difference(DateTime(from.year, from.month, from.day)).inDays;

/// A weekday inside one week, a day number inside a month, a month's short name
/// above that. The charts shorten these further when there are more of them
/// than the axis can print.
String _bucketLabel(DateTime at, SpendRange range) {
  if (range.unit == SpendBucketUnit.month) return L.s.monthShort[at.month];
  if (range.days <= 7) return L.s.weekdayShort[at.weekday % 7];
  return '${at.day}';
}

/// Folds the merchant names a card terminal produces onto one key.
///
/// Case and surrounding whitespace only. It deliberately does **not** try to
/// strip legal suffixes or branch numbers: "REWE Markt GmbH" and "REWE City
/// 4471" really are different shops to somebody reading their own statement, and
/// a cleverer normaliser would merge things the user can no longer tell apart.
String _merchantKey(String merchant) => merchant.trim().toLowerCase();

void _add<K>(Map<K, (int, int)> into, K key, int cents) {
  final existing = into[key];
  into[key] = existing == null ? (cents, 1) : (existing.$1 + cents, existing.$2 + 1);
}

List<SpendSlice<K>> _slices<K>(Map<K, (int, int)> tallies, int total, {int? limit}) {
  final slices = [
    for (final e in tallies.entries)
      SpendSlice<K>(
        key: e.key,
        cents: e.value.$1,
        count: e.value.$2,
        share: total == 0 ? 0 : e.value.$1 / total,
      ),
  ]..sort((a, b) => b.cents.compareTo(a.cents));

  return limit == null || slices.length <= limit ? slices : slices.sublist(0, limit);
}

/// The merchant name to *show* for a folded key — the most common spelling among
/// the rows that folded onto it, so the list reads the way the statement does
/// rather than in the lower case the key is stored in.
String displayMerchant(List<Spend> rows, String key) {
  final counts = <String, int>{};
  for (final s in rows) {
    if (_merchantKey(s.merchant) != key) continue;
    final name = s.merchant.trim();
    counts[name] = (counts[name] ?? 0) + 1;
  }
  if (counts.isEmpty) return key;
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}
