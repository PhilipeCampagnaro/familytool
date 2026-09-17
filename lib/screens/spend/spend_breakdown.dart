import 'package:flutter/material.dart';

import '../../data/spend_analysis.dart';
import '../../l10n/l10n.dart';
import '../../models/spend.dart';
import '../../state/family_state.dart';
import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import '../../widgets/avatar.dart';
import 'spend_charts.dart';
import 'spend_mark.dart';

/// How many rows the card on the Ausgaben page shows before it offers the rest.
///
/// **Five, because that is what the ring shows**, and a card listing fourteen
/// categories under a drawing of five is a card contradicting the picture above
/// it. The other two groupings take the same five for the same reason a list
/// and its heading take the same words: a page with two different ideas of "top"
/// is a page nobody trusts the numbers on.
const int spendBreakdownPreview = 5;

/// Which way the money is cut up.
enum SpendGrouping {
  category,
  merchant,
  member;

  String get title => switch (this) {
    SpendGrouping.category => L.s.spendByCategory,
    SpendGrouping.merchant => L.s.spendTopMerchants,
    SpendGrouping.member => L.s.spendByMember,
  };

  IconData get icon => switch (this) {
    SpendGrouping.category => AppIcons.shapes,
    SpendGrouping.merchant => AppIcons.storefront,
    SpendGrouping.member => AppIcons.users,
  };

  /// The glyph UIKit draws when the system puts the picker up — see
  /// `showAnchoredMenu`. Validated against the runtime's own list.
  String get symbol => switch (this) {
    SpendGrouping.category => 'square.grid.2x2',
    SpendGrouping.merchant => 'storefront',
    SpendGrouping.member => 'person.2',
  };
}

/// One line of a breakdown, whichever of the three it came from.
///
/// Built rather than drawn straight from a `SpendSlice` because the three
/// groupings disagree about the left-hand mark — a category owns a colour, a
/// shop owns none, and a person owns a face — and about nothing else at all.
class SpendBreakdownEntry {
  final String title;
  final int cents;
  final int count;
  final double share;

  final IconData icon;

  /// The member this row is about, where it is about one.
  final HouseholdMember? member;

  /// The business this row is about, where it is about one — which is what
  /// lets the mark beside it be the shop's own logo. See [SpendMark].
  final String? merchant;

  /// The category this row is, where it is exactly one — the folded "Sonstige"
  /// row is not. What a tap drills into on the explore page.
  final SpendCategory? category;

  /// True on a person's row, whose [payerId] may be null for somebody who has
  /// left — so the id alone cannot say it is a person's row.
  final bool byMember;
  final String? payerId;

  const SpendBreakdownEntry({
    required this.title,
    required this.cents,
    required this.count,
    required this.share,
    required this.icon,
    this.member,
    this.merchant,
    this.category,
    this.byMember = false,
    this.payerId,
  });
}

/// The rows for one grouping, capped at [limit] or every last one.
///
/// The category grouping reads [ringSlices], which is the same fold the donut
/// is drawn from — so the picture and the list can never disagree about what
/// went into "Sonstige". Asking for all of them unfolds it instead: the full
/// page is the place every category is named.
List<SpendBreakdownEntry> spendBreakdownRows(
  SpendSummary summary,
  SpendGrouping by,
  List<HouseholdMember> members, {
  int? limit,
}) {
  final rows = switch (by) {
    SpendGrouping.category =>
      limit == null
          ? [
              for (final slice in summary.byCategory)
                SpendBreakdownEntry(
                  title: slice.key.label,
                  cents: slice.cents,
                  count: slice.count,
                  share: slice.share,
                  icon: slice.key.icon,
                  category: slice.key,
                ),
            ]
          : [
              for (final (i, slice) in ringSlices(summary).indexed)
                SpendBreakdownEntry(
                  title: slice.label,
                  cents: slice.cents,
                  count: slice.count,
                  share: slice.share,
                  icon: slice.icon,
                  // The ring keeps the fold's order, so the arcs before
                  // "Sonstige" line up with the categories one to one.
                  category: i < summary.byCategory.length && summary.byCategory[i].key.label == slice.label
                      ? summary.byCategory[i].key
                      : null,
                ),
            ],
    SpendGrouping.merchant => [
      for (final slice in summary.byMerchant)
        () {
          final name = displayMerchant(summary.rows, slice.key);
          return SpendBreakdownEntry(
            title: name,
            cents: slice.cents,
            count: slice.count,
            share: slice.share,
            icon: AppIcons.storefront,
            merchant: name,
          );
        }(),
    ],
    SpendGrouping.member => [
      for (final slice in summary.byMember)
        () {
          final id = slice.key;
          final member = id == null ? null : members.where((m) => m.userId == id).firstOrNull;
          return SpendBreakdownEntry(
            // A payer whose membership has ended still has rows on the record;
            // they keep their money and lose only their name.
            title: member?.name ?? L.s.spendFormerMember,
            cents: slice.cents,
            count: slice.count,
            share: slice.share,
            icon: AppIcons.user,
            member: member,
            byMember: true,
            payerId: id,
          );
        }(),
    ],
  };

  return limit == null || rows.length <= limit ? rows : rows.sublist(0, limit);
}

/// One line: a disc, a name over its count, and the money over its share.
///
/// The percentage sits under the amount rather than between the name and it,
/// because the two numbers answer the same question at two zoom levels and the
/// eye compares a column of them without crossing the row.
class SpendBreakdownRow extends StatelessWidget {
  final SpendBreakdownEntry row;
  final String currency;

  /// Opens what the row stands for. Null leaves the row as a plain line.
  final VoidCallback? onTap;

  const SpendBreakdownRow({super.key, required this.row, this.currency = 'EUR', this.onTap});

  @override
  Widget build(BuildContext context) {
    final line = Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          _Disc(row: row),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.title, style: AppText.itemTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  L.s.spendCountShort(row.count),
                  style: AppText.body.copyWith(color: AppColors.inkSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatMoneyShort(row.cents, currency: currency), style: AppText.itemTitle),
              const SizedBox(height: 2),
              Text(
                L.s.percent((row.share * 100).round()),
                style: AppText.body.copyWith(color: AppColors.inkSecondary, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );

    final tap = onTap;
    if (tap == null) return line;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: tap, child: line);
  }
}

/// The row's mark: a person's face, a shop's logo, or the category's glyph on
/// the same grey disc everything else on this page wears — see [SpendMark].
///
/// **A person is the exception, and stays one.** A household member has a
/// picture and a tone that are theirs across all five tabs; grey-ing them here
/// would be Ausgaben inventing a second way to draw somebody who is already
/// drawn everywhere else.
class _Disc extends StatelessWidget {
  final SpendBreakdownEntry row;

  const _Disc({required this.row});

  @override
  Widget build(BuildContext context) {
    if (row.member case final member?) {
      final tone = AppTones.list[member.tone % AppTones.list.length];
      return Avatar(
        // The same disc as the [SpendMark] below it — a column that changed
        // diameter depending on whether a row named a person or a shop read as
        // two lists interleaved, which is the thing that widget exists to stop.
        size: AppText.rowMark,
        bg: tone.bg,
        fg: tone.fg,
        fontSize: AppText.markInitials(AppText.rowMark),
        initials: member.initials,
        imageUrl: member.avatarUrl,
      );
    }

    return SpendMark(size: AppText.rowMark, icon: row.icon, merchant: row.merchant);
  }
}
