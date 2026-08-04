import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/tokens.dart';
import 'glass.dart';
import 'native_search_field.dart';

/// The search surface Listen and Boxen share.
///
/// Searching happens *in place*: the screen's header turns into the system
/// search field and the screen's own body shows the hits, instead of a sheet
/// sliding over the content. There's one control either way — the flat
/// [SearchTriggerField] in the resting header and the glass [HeaderSearchButton]
/// once it has scrolled away both just switch the screen into search — and
/// [HeaderSearchBar] does the switching, so a screen only has to hold a query
/// string and render results for it.

/// The search pill in a screen's collapsing header at rest. Not a live field:
/// tapping it hands over to [HeaderSearchBar], so there's one place where typing
/// happens.
class SearchTriggerField extends StatelessWidget {
  final String hint;
  final VoidCallback onTap;

  const SearchTriggerField({super.key, required this.hint, required this.onTap});

  static const _radius = 20.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      // Flat gray, not glass: it sits on the frosted header bar, and glass on
      // glass reads as a smudge.
      child: DecoratedBox(
        decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(_radius)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          child: Row(
            children: [
              Icon(LucideIcons.search, size: 17, color: AppColors.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.searchInput.copyWith(color: AppColors.muted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The glass search button that takes the [SearchTriggerField]'s place in the
/// pinned bar once the header has collapsed — without it, scrolling down leaves
/// no way to search.
///
/// It fades in on the same late curve the collapsed title crossfades on, so the
/// pill below has actually gone before the button appears rather than the two
/// overlapping mid-scroll. While it's invisible it also stops taking taps, so it
/// can't swallow a tap meant for the expanded title area underneath.
class HeaderSearchButton extends StatelessWidget {
  /// Collapse progress from the header: 0 expanded, 1 collapsed.
  final double t;
  final VoidCallback onTap;

  const HeaderSearchButton({super.key, required this.t, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final visible = ((t - 0.55) / 0.45).clamp(0.0, 1.0);
    return IgnorePointer(
      ignoring: visible < 0.5,
      child: Opacity(
        opacity: visible,
        child: GlassIconButton(icon: LucideIcons.search, onTap: onTap),
      ),
    );
  }
}

/// Wraps a screen's pinned title row so search can take it over: while
/// [active], the row's contents fade out and the system search field grows out
/// of the leading slot — where [HeaderSearchButton] just was — up to a glass X
/// that closes search again.
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
class HeaderSearchBar extends StatefulWidget {
  /// The screen's normal title row, shown whenever search is closed.
  final Widget child;

  final bool active;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  const HeaderSearchBar({
    super.key,
    required this.child,
    required this.active,
    required this.hint,
    required this.onChanged,
    required this.onClose,
  });

  /// Matches [GlassIconButton]'s default — the size the field starts at and the
  /// width the X takes on the right.
  static const _buttonSize = 40.0;
  static const _gap = 10.0;

  @override
  State<HeaderSearchBar> createState() => _HeaderSearchBarState();
}

class _HeaderSearchBarState extends State<HeaderSearchBar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: widget.active ? 1 : 0,
  );
  late final Animation<double> _grow = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);

  @override
  void didUpdateWidget(HeaderSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      widget.active ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return AnimatedBuilder(
          animation: _grow,
          builder: (context, _) {
            final a = _grow.value;
            // From the search button's own footprint out to the full row, minus
            // the X it stops beside.
            final fieldRight = lerpDouble(width - HeaderSearchBar._buttonSize, HeaderSearchBar._buttonSize + HeaderSearchBar._gap, a)!;
            return Stack(
              children: [
                // Kept in the tree rather than swapped out so nothing below it
                // is rebuilt (and, on iOS, so its glass views aren't torn down
                // and recreated) for what is only a fade.
                IgnorePointer(
                  ignoring: a > 0.5,
                  child: Opacity(opacity: 1 - a, child: widget.child),
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
                      child: Opacity(
                        opacity: a,
                        child: GlassIconButton(icon: LucideIcons.x, onTap: widget.onClose),
                      ),
                    ),
                  ),
                if (a > 0)
                  Positioned(
                    key: const ValueKey('field'),
                    left: 0,
                    right: fieldRight,
                    top: 0,
                    bottom: 0,
                    child: NativeSearchField(
                      placeholder: widget.hint,
                      style: NativeSearchFieldStyle.field,
                      autofocus: true,
                      onChanged: widget.onChanged,
                    ),
                  ),
              ],
            );
          },
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
            child: Icon(LucideIcons.search, size: 26, color: AppColors.mutedLight),
          ),
          const SizedBox(height: 14),
          Text(
            query.isEmpty ? prompt : 'Keine Treffer für „$query"',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w300, color: AppColors.muted),
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
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted, letterSpacing: 0.3),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            count,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w300, color: AppColors.mutedLight),
          ),
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
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, fontWeight: FontWeight.w300, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 16, color: AppColors.mutedLight),
          ],
        ),
      ),
    );
  }
}
