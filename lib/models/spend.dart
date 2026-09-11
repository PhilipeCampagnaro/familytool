import '../l10n/l10n.dart';
import '../theme/app_icons.dart';
import 'package:flutter/widgets.dart' show IconData;

/// One payment, and the three enums that describe it — `public.spends`.
///
/// **The amount is integer cents and never a double.** A household's month is a
/// few hundred of these added together, and a binary float cannot hold 0.10
/// exactly, so summing doubles drifts by a cent or two over a month and the
/// total disagrees with the rows above it. The old web app kept the amount as
/// *text* and parsed it on read, which was worse again: one mis-mapped Shortcut
/// field could make the whole family's spend view throw.
///
/// Nothing here is nullable that the database will not leave null. `payerId` is
/// the exception and it is a real one: a member can leave the household, and
/// their spending stays on the record without them.
class Spend {
  final String id;
  final String familyId;

  /// Who paid. Null once that member has left the household — the money was
  /// still spent, so the row outlives the membership.
  final String? payerId;

  final String merchant;

  /// Cents, always positive. A refund is not a negative spend; it is a
  /// different thing that this app does not model yet.
  final int amountCents;
  final String currency;

  final DateTime occurredAt;
  final SpendCategory category;
  final SpendKind kind;
  final SpendSource source;

  /// What the Wallet automation called the card. Display only, and never a
  /// number — the Transaction trigger hands over none.
  final String? cardLabel;
  final String? note;

  /// Apple's Transaction trigger sometimes hands a custom App Intent an empty
  /// merchant or an amount of zero. Such a row is kept and flagged rather than
  /// dropped, because the payment really happened; the Spend page floats these
  /// to the top so they can be fixed in two taps.
  final bool needsReview;

  const Spend({
    required this.id,
    required this.familyId,
    required this.payerId,
    required this.merchant,
    required this.amountCents,
    required this.currency,
    required this.occurredAt,
    required this.category,
    required this.kind,
    required this.source,
    this.cardLabel,
    this.note,
    this.needsReview = false,
  });

  factory Spend.fromMap(Map<String, dynamic> map) => Spend(
    id: map['id'] as String,
    familyId: map['family_id'] as String,
    payerId: map['payer_id'] as String?,
    merchant: map['merchant'] as String? ?? '',
    // Postgres `bigint` reaches Dart as an int over PostgREST's JSON, but a
    // jsonb round trip can make it a double; `num` covers both without
    // pretending the column might be a string.
    amountCents: (map['amount_cents'] as num?)?.round() ?? 0,
    currency: map['currency'] as String? ?? 'EUR',
    occurredAt: DateTime.parse(map['occurred_at'] as String).toLocal(),
    category: spendCategoryFrom(map['category'] as String?),
    kind: spendKindFrom(map['kind'] as String?),
    source: spendSourceFrom(map['source'] as String?),
    cardLabel: map['card_label'] as String?,
    note: map['note'] as String?,
    needsReview: map['needs_review'] as bool? ?? false,
  );

  /// What the client writes. `category` and `kind` are included because by the
  /// time a row is edited the user has seen them and may have changed them; on
  /// *create* the repository omits both so the `spends_classify` trigger names
  /// them from the merchant, which is the one place those rules live.
  Map<String, dynamic> toMap() => {
    'id': id,
    'family_id': familyId,
    'payer_id': payerId,
    'merchant': merchant,
    'amount_cents': amountCents,
    'currency': currency,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
    'category': category.wire,
    'kind': kind.wire,
    'source': source.wire,
    'card_label': cardLabel,
    'note': note,
    'needs_review': needsReview,
  };

  Spend copyWith({
    String? merchant,
    int? amountCents,
    DateTime? occurredAt,
    SpendCategory? category,
    SpendKind? kind,
    String? payerId,
    String? cardLabel,
    String? note,
    bool? needsReview,
  }) => Spend(
    id: id,
    familyId: familyId,
    payerId: payerId ?? this.payerId,
    merchant: merchant ?? this.merchant,
    amountCents: amountCents ?? this.amountCents,
    currency: currency,
    occurredAt: occurredAt ?? this.occurredAt,
    category: category ?? this.category,
    kind: kind ?? this.kind,
    source: source,
    cardLabel: cardLabel ?? this.cardLabel,
    note: note ?? this.note,
    needsReview: needsReview ?? this.needsReview,
  );
}

// ---------------------------------------------------------------------------
// Category
// ---------------------------------------------------------------------------

/// `public.spend_category`. The set is small on purpose: a donut with twenty
/// slices answers nothing, and every value here is one a household would
/// recognise on a bank statement.
///
/// **Which category a merchant falls into is decided in SQL, not here.**
/// `private.classify_merchant` runs in a trigger, so the Wallet automation and
/// the app's own form reach the same answer; a second copy of those rules in
/// Dart would drift and put one shop in two different slices depending on how
/// its row arrived. This enum only knows how to *name* and *draw* a category.
enum SpendCategory {
  groceries,
  drugstore,
  fuel,
  restaurant,
  cafe,
  shipping,
  clothing,
  shopping,
  electronics,
  transport,
  entertainment,
  health,
  home,
  other;

  /// The Postgres enum label. Every name here already matches, so this is the
  /// identity — spelled out anyway so a future rename in Dart cannot silently
  /// change what goes on the wire.
  String get wire => switch (this) {
    SpendCategory.groceries => 'groceries',
    SpendCategory.drugstore => 'drugstore',
    SpendCategory.fuel => 'fuel',
    SpendCategory.restaurant => 'restaurant',
    SpendCategory.cafe => 'cafe',
    SpendCategory.shipping => 'shipping',
    SpendCategory.clothing => 'clothing',
    SpendCategory.shopping => 'shopping',
    SpendCategory.electronics => 'electronics',
    SpendCategory.transport => 'transport',
    SpendCategory.entertainment => 'entertainment',
    SpendCategory.health => 'health',
    SpendCategory.home => 'home',
    SpendCategory.other => 'other',
  };

  /// Read live, so it follows the interface language like every other label.
  String get label => switch (this) {
    SpendCategory.groceries => L.s.spendCatGroceries,
    SpendCategory.drugstore => L.s.spendCatDrugstore,
    SpendCategory.fuel => L.s.spendCatFuel,
    SpendCategory.restaurant => L.s.spendCatRestaurant,
    SpendCategory.cafe => L.s.spendCatCafe,
    SpendCategory.shipping => L.s.spendCatShipping,
    SpendCategory.clothing => L.s.spendCatClothing,
    SpendCategory.shopping => L.s.spendCatShopping,
    SpendCategory.electronics => L.s.spendCatElectronics,
    SpendCategory.transport => L.s.spendCatTransport,
    SpendCategory.entertainment => L.s.spendCatEntertainment,
    SpendCategory.health => L.s.spendCatHealth,
    SpendCategory.home => L.s.spendCatHome,
    SpendCategory.other => L.s.spendCatOther,
  };

  /// A glyph that names a thing, so duotone — drawn with `AppIcon`, never
  /// `Icon`. See CLAUDE.md on why a bare `Icon` renders half of one.
  IconData get icon => switch (this) {
    SpendCategory.groceries => AppIcons.shoppingCart,
    SpendCategory.drugstore => AppIcons.pill,
    SpendCategory.fuel => AppIcons.gasPump,
    SpendCategory.restaurant => AppIcons.forkKnife,
    SpendCategory.cafe => AppIcons.coffee,
    SpendCategory.shipping => AppIcons.package,
    SpendCategory.clothing => AppIcons.tShirt,
    SpendCategory.shopping => AppIcons.shoppingBag,
    SpendCategory.electronics => AppIcons.deviceMobile,
    SpendCategory.transport => AppIcons.train,
    SpendCategory.entertainment => AppIcons.television,
    SpendCategory.health => AppIcons.heartbeat,
    SpendCategory.home => AppIcons.couch,
    SpendCategory.other => AppIcons.shapes,
  };
}

SpendCategory spendCategoryFrom(String? value) => switch (value) {
  'groceries' => SpendCategory.groceries,
  'drugstore' => SpendCategory.drugstore,
  'fuel' => SpendCategory.fuel,
  'restaurant' => SpendCategory.restaurant,
  'cafe' => SpendCategory.cafe,
  'shipping' => SpendCategory.shipping,
  'clothing' => SpendCategory.clothing,
  'shopping' => SpendCategory.shopping,
  'electronics' => SpendCategory.electronics,
  'transport' => SpendCategory.transport,
  'entertainment' => SpendCategory.entertainment,
  'health' => SpendCategory.health,
  'home' => SpendCategory.home,
  _ => SpendCategory.other,
};

// ---------------------------------------------------------------------------
// Kind and source
// ---------------------------------------------------------------------------

/// Planned versus unplanned — `public.spend_kind`. The trigger guesses from the
/// category and the user is free to disagree; there is no budget feature to
/// check it against yet, and this column is what will let one arrive without a
/// backfill.
enum SpendKind {
  budget,
  extra;

  String get wire => this == SpendKind.budget ? 'budget' : 'extra';
  String get label => this == SpendKind.budget ? L.s.spendKindBudget : L.s.spendKindExtra;
}

SpendKind spendKindFrom(String? value) =>
    value == 'extra' ? SpendKind.extra : SpendKind.budget;

/// How the row arrived — `public.spend_source`. A `wallet` row was written by a
/// device token with nobody signed in, which is why it is the only kind that can
/// need review.
enum SpendSource {
  wallet,
  manual;

  String get wire => this == SpendSource.wallet ? 'wallet' : 'manual';
}

SpendSource spendSourceFrom(String? value) =>
    value == 'wallet' ? SpendSource.wallet : SpendSource.manual;

// ---------------------------------------------------------------------------
// Money
// ---------------------------------------------------------------------------

/// Cents to something a person reads, in the interface language.
///
/// German writes `12,34 €` and English `€12.34`, which is a bigger difference
/// than a decimal separator: the symbol changes sides. Both come off `L.s` for
/// the same reason month names do.
String formatMoney(int cents, {String currency = 'EUR', bool withSymbol = true}) {
  final negative = cents < 0;
  final abs = cents.abs();
  final whole = abs ~/ 100;
  final rest = abs % 100;

  final grouped = _group(whole, L.s.thousandsSeparator);
  final number = '$grouped${L.s.decimalSeparator}${rest.toString().padLeft(2, '0')}';
  final body = withSymbol ? L.s.money(number, _symbol(currency)) : number;
  return negative ? '−$body' : body;
}

/// Rounded to whole units, for an axis label or a headline where two decimal
/// places are noise.
String formatMoneyShort(int cents, {String currency = 'EUR'}) {
  final grouped = _group((cents.abs() / 100).round(), L.s.thousandsSeparator);
  return L.s.money(grouped, _symbol(currency));
}

/// `870`, `99,9k`, `1,4 Mio.` — an axis label or an end-of-line marker, where
/// a thousands separator and two decimal places are noise the eye has to step
/// over on its way to the shape of the chart.
///
/// No symbol by default: these sit *inside* a drawing whose headline already
/// says what the currency is, and a € on every gridline is five € nobody reads.
/// The threshold is ten thousand rather than one, so `9.999` stays exact and
/// only numbers that were never going to be read to the euro get rounded.
String formatMoneyCompact(int cents, {String currency = 'EUR', bool withSymbol = false}) {
  final negative = cents < 0;
  final euros = (cents.abs() / 100).round();

  final String number;
  if (euros < 10000) {
    number = _group(euros, L.s.thousandsSeparator);
  } else if (euros < 1000000) {
    number = '${_oneDecimal(euros / 1000)}${L.s.thousandsSuffix}';
  } else {
    number = '${_oneDecimal(euros / 1000000)} ${L.s.millionsSuffix}';
  }

  final body = withSymbol ? L.s.money(number, _symbol(currency)) : number;
  return negative ? '−$body' : body;
}

/// One decimal place in the interface language's own separator. Always one,
/// even on a round number: a column of `139,2k` and `140k` reads as two
/// different kinds of number.
String _oneDecimal(double value) {
  final rounded = (value * 10).round();
  return '${_group(rounded ~/ 10, L.s.thousandsSeparator)}${L.s.decimalSeparator}${rounded % 10}';
}

String _symbol(String currency) => switch (currency) {
  'EUR' => '€',
  'USD' => r'$',
  'GBP' => '£',
  'CHF' => 'CHF',
  _ => currency,
};

String _group(int value, String separator) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(separator);
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
