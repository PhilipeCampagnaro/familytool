import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import 'app_sheet.dart';
import 'glass.dart';
import 'native_search_field.dart';
import '../l10n/l10n.dart';
import '../theme/app_icons.dart';

/// The search surface Listen and Boxen share.
///
/// Searching happens *in place*: the screen's header turns into the system
/// search field and the screen's own body shows the hits, instead of a sheet
/// sliding over the content.
///
/// **There is one way in, and it is the magnifier beside the `+`.** It used to
/// be two — a flat pill in the collapsing header and a glass button that faded
/// in once that pill had scrolled away — which cost the block a whole row to
/// say a second time what the top bar could say once, and made the resting
/// header a search box above a heading above a card. A control that is always
/// in the same place is also what lets the field grow out of it (see
/// [HeaderSearchBar]); a pill that scrolls away cannot be grown out of.
///
/// The pieces here draw the handover; they don't time it. Opening search also
/// folds the header's collapsing block away and swaps the body to the hits, so
/// the screen ([SearchableOverviewScreen]) holds the one controller that runs
/// all of it and passes the eased value down — see [kSearchTransition].

/// How long Listen and Boxen take to hand their header over to search, and the
/// easing on the way in and back out.
///
/// One duration for the whole handover — the field growing, the title row and
/// its `+` going, the X arriving, the collapsing block folding up and the body
/// swapping to results are a single movement, and they're timed here so they
/// stay one. It's deliberately unhurried: the header loses most of its height
/// in that moment, and a fast fold of a tall thing reads as a glitch rather
/// than a transition.
const Duration kSearchTransition = Duration(milliseconds: 360);
const Curve kSearchTransitionCurve = Curves.easeOutCubic;
const Curve kSearchTransitionReverseCurve = Curves.easeInCubic;

/// Wraps a screen's pinned title row so search can take it over: as [progress]
/// runs 0 → 1 the row's contents fade out and the system search field grows
/// leftward out of the magnifier in the trailing capsule, until it fills the row
/// beside the glass X that closes it again.
///
/// **It opens and closes on the right**, on the magnifier that was pressed: the
/// capsule's two segments sit at the right end of the bar, the X lands over the
/// `+` at the very end of it, and the field unrolls from the segment beside it.
/// Closing runs the same movement backwards, so the field rolls back into the
/// button it came out of rather than draining off the opposite margin.
///
/// [progress] is the screen's, not this widget's: the same eased value folds the
/// collapsing block away underneath ([CollapsingHeaderScreen.extraCollapse]) and
/// crossfades the body to the results, so the whole header moves as one thing.
///
/// The field is the real `UISearchTextField` ([NativeSearchField] in
/// [NativeSearchFieldStyle.field]), autofocused, so the keyboard is already up
/// by the time the growth animation lands. The X is Flutter's, not the search
/// bar's own Cancel button: it's the same glass control the rest of the header
/// uses, and it's what lets the field be a plain field that fits a 40pt row.
///
/// Paint order matters here — the row's own glass buttons, then the X, then the
/// field, all platform views on iOS, with the only Flutter content (the title)
/// painted before all of them. Sandwiching Flutter content between two platform
/// views drops it on device (see docs/design-system.md).
class HeaderSearchBar extends StatelessWidget {
  /// The screen's normal title row, shown whenever search is closed.
  final Widget child;

  /// 0 closed → 1 open, already eased.
  final double progress;

  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  const HeaderSearchBar({
    super.key,
    required this.child,
    required this.progress,
    required this.hint,
    required this.onChanged,
    required this.onClose,
  });

  /// Matches [GlassIconButton]'s default — the width the X takes on the right,
  /// and the size of the collapsed field that grows out from beside it.
  static const _buttonSize = 40.0;
  static const _gap = 10.0;

  @override
  Widget build(BuildContext context) {
    final a = progress.clamp(0.0, 1.0);
    // The two don't cross at 50/50. The `+` and the X are the same glass circle
    // in the same spot, so holding both at half opacity mid-way draws one
    // smeared button rather than a swap; the row is gone before the X starts
    // arriving.
    final rowFade = (1 - a / 0.45).clamp(0.0, 1.0);
    final closeFade = ((a - 0.4) / 0.6).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Out of the magnifier's own footprint and leftward to the full row.
        // The field's right edge never moves, so it grows and rolls back up on
        // the side the header keeps its glass — a 40pt box one button in from
        // the right edge is where the capsule's search segment sits, which is
        // the control that was just pressed. Growing from the far margin
        // instead read as a separate thing arriving.
        final fieldLeft = lerpDouble(width - _buttonSize * 2 - _gap, 0, a)!;
        return Stack(
          children: [
            // Kept in the tree rather than swapped out so nothing below it
            // is rebuilt (and, on iOS, so its glass views aren't torn down
            // and recreated) for what is only a fade.
            IgnorePointer(
              ignoring: a > 0,
              child: Opacity(opacity: rowFade, child: child),
            ),
            // Keys: the two only exist while search is open, so without
            // them the field would be matched against the X the frame the
            // row above it goes away — recreating the platform view mid-
            // animation and dropping focus and the query with it.
            if (a > 0)
              Positioned(
                key: const ValueKey('close'),
                right: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IgnorePointer(
                    ignoring: closeFade < 0.5,
                    child: Opacity(
                      opacity: closeFade,
                      child: GlassIconButton(icon: AppIcons.x, onTap: onClose),
                    ),
                  ),
                ),
              ),
            if (a > 0)
              Positioned(
                key: const ValueKey('field'),
                left: fieldLeft,
                right: _buttonSize + _gap,
                top: 0,
                bottom: 0,
                child: NativeSearchField(
                  placeholder: hint,
                  style: NativeSearchFieldStyle.field,
                  autofocus: true,
                  onChanged: onChanged,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Shared chrome for a screen's search results: a `Keine Treffer` / prompt state
/// when there's nothing to show, so both screens phrase it the same way.
class SearchResultsPlaceholder extends StatelessWidget {
  final String query;
  final String prompt;

  const SearchResultsPlaceholder({super.key, required this.query, required this.prompt});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 20),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: AppColors.surfaceAlt, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: AppIcon(AppIcons.magnifyingGlass, size: 26, color: AppColors.mutedLight),
          ),
          const SizedBox(height: 14),
          Text(
            query.isEmpty ? prompt : L.s.noMatchesFor(query),
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

/// Heading above a group of search hits (`Listen`, `Artikel`, a box's name),
/// matching the small caption the overview screens put above their cards.
class SearchGroupHeading extends StatelessWidget {
  final String label;
  final String count;
  final Widget? icon;

  const SearchGroupHeading({super.key, required this.label, required this.count, this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 9),
      child: Row(
        children: [
          if (icon != null) ...[icon!, const SizedBox(width: 9)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.groupHeading,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            count,
            style: AppText.label.copyWith(color: AppColors.mutedLight),
          ),
        ],
      ),
    );
  }
}

/// A [SearchGroupHeading] over a card of [rows] — the unit a results list is
/// built from, whether the group is "every list whose name matched" or "the
/// articles found inside Wocheneinkauf".
///
/// Groups after the first carry the gap above them, so a screen composes its
/// results with `SearchHitGroup(first: i == 0, …)` instead of each one working
/// out its own padding from where it happens to sit.
class SearchHitGroup extends StatelessWidget {
  final String label;
  final String count;
  final Widget? icon;
  final List<Widget> rows;

  /// Whether this is the topmost group on screen; the rest get a gap above.
  final bool first;

  const SearchHitGroup({
    super.key,
    required this.label,
    required this.count,
    required this.rows,
    this.icon,
    this.first = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SearchGroupHeading(label: label, count: count, icon: icon),
          SectionCard(children: dividedRows(rows)),
        ],
      ),
    );
  }
}

/// One hit inside a results group: an icon/badge, the matched text, and what it
/// sits in ("in Wocheneinkauf", "Keller · 3 Artikel").
class SearchResultRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const SearchResultRow({super.key, required this.leading, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 15),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.itemTitle,
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.label,
                  ),
                ],
              ),
            ),
            AppIcon(AppIcons.caretRight, size: 16, color: AppColors.mutedLight),
          ],
        ),
      ),
    );
  }
}
