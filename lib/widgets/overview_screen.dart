import 'package:flutter/material.dart';

import 'bottom_nav.dart';
import 'collapsing_header.dart';
import 'glass.dart';
import 'search.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';

/// The overview half of Listen and Boxen: a collapsing header that turns into a
/// search field, and a body that shows either the screen's own content or the
/// hits for what was typed.
///
/// Both screens had a verbatim copy of this — the `_searching`/`_query` pair,
/// the two ways into search, the rule that the resting header content is
/// dropped while searching, the body panel and its padding. The copies had
/// already drifted (one dropped the stat tiles while searching, the other had
/// nothing to drop), which is exactly how two screens that are meant to feel
/// like one app stop doing so.
///
/// What stays with the screen is what actually differs: what a row looks like,
/// what "matches" means, and what the plus button opens.
class SearchableOverviewScreen extends StatefulWidget {
  /// The large heading at rest — `Listen`, `Boxen`.
  final String title;

  /// Placeholder for both the resting pill and the live field, so the screen
  /// doesn't get to phrase the same prompt two ways.
  final String searchHint;

  /// Shown in place of results while search is open but nothing has been typed
  /// yet — the long form of [searchHint].
  final String searchPrompt;

  /// The `+` in the pinned bar.
  final VoidCallback onAdd;

  /// Header content below the search pill at rest — the stat tiles on Boxen,
  /// nothing on Listen. Dropped entirely while searching: it says nothing about
  /// the query, and dropping it gives the results the screen.
  final Widget? headerExtra;

  /// First-frame estimate of [headerExtra] plus the search pill above it;
  /// [CollapsingHeaderScreen] re-measures the real thing once it's laid out.
  /// Never hardcode this as the header's collapsing-block height — see
  /// docs/design-system.md.
  final double extraHeight;

  /// The screen's normal body, as the children of the shared [ListView].
  final List<Widget> Function(BuildContext context) body;

  /// The hits for [query], which is always non-empty and trimmed. Returning
  /// null means nothing matched, and gets the shared "Keine Treffer" state
  /// rather than each screen writing its own.
  ///
  /// [closeSearch] puts the header back and clears the query — a result is also
  /// the way to the thing it found, and leaving the field open behind the
  /// screen it opened would strand the query there.
  final Widget? Function(BuildContext context, String query, VoidCallback closeSearch) results;

  const SearchableOverviewScreen({
    super.key,
    required this.title,
    required this.searchHint,
    required this.searchPrompt,
    required this.onAdd,
    required this.extraHeight,
    required this.body,
    required this.results,
    this.headerExtra,
  });

  @override
  State<SearchableOverviewScreen> createState() => _SearchableOverviewScreenState();
}

class _SearchableOverviewScreenState extends State<SearchableOverviewScreen> with SingleTickerProviderStateMixin {
  /// Search runs *in* the screen (see [HeaderSearchBar]): the header becomes
  /// the system search field and this body shows the hits — no sheet over the
  /// content.
  ///
  /// Which means the screen, not the search bar, owns the animation: opening
  /// search shortens the header by the whole collapsing block and replaces
  /// everything below it, and those have to happen *as* the field grows rather
  /// than on the frame the tap lands. One controller drives all three.
  late final AnimationController _controller = AnimationController(vsync: this, duration: kSearchTransition);
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: kSearchTransitionCurve,
    reverseCurve: kSearchTransitionReverseCurve,
  );

  /// The results list scrolls on its own controller rather than the primary
  /// one: [CollapsingHeaderScreen]'s body already holds the screen's own list
  /// on [PrimaryScrollController], and two scrollables can't share it. Nothing
  /// is lost — while search is open the header has no block left to collapse,
  /// so there's no scroll for it to track.
  final ScrollController _resultsScroll = ScrollController();

  bool _searching = false;
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    _resultsScroll.dispose();
    super.dispose();
  }

  void _openSearch() {
    if (_searching) return;
    setState(() => _searching = true);
    _controller.forward();
  }

  /// The query outlives the tap by the length of the animation on purpose:
  /// clearing it here would empty the results to "search for something" for the
  /// third of a second they spend fading out.
  void _closeSearch() {
    if (!_searching) return;
    setState(() => _searching = false);
    _controller.reverse().whenComplete(() {
      if (mounted && !_searching && _query.isNotEmpty) setState(() => _query = '');
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, _) => _build(context, _progress.value.clamp(0.0, 1.0)),
    );
  }

  Widget _build(BuildContext context, double a) {
    final query = _query.trim();
    final padding = EdgeInsets.fromLTRB(16, 18, 16, navContentInset(context, pill: 140));
    return CollapsingHeaderScreen(
      titleRowBuilder: (context, t) => HeaderSearchBar(
        progress: a,
        hint: widget.searchHint,
        onChanged: (v) => setState(() => _query = v),
        onClose: _closeSearch,
        // No `leadingWidth` even though there's a leading button: it only fades
        // in once the header is collapsed (see [HeaderSearchButton]), and
        // reserving room for it at rest would push the big heading off the left
        // margin.
        child: CollapsingScreenTitle(
          title: widget.title,
          t: t,
          trailingWidth: 48,
          leading: HeaderSearchButton(t: t, onTap: _openSearch),
          trailing: GlassIconButton(icon: AppIcons.plus, onTap: widget.onAdd),
        ),
      ),
      // While searching the header is only the field: the trigger pill would be
      // a second search box for the same query, and the stat tiles say nothing
      // about the query. The block stays in the tree and is folded away instead
      // of being swapped for an empty one, so the header travels the distance
      // rather than jumping it.
      extraCollapse: a,
      estimatedExtraHeight: widget.extraHeight,
      extra: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          SearchTriggerField(hint: widget.searchHint, onTap: _openSearch),
          if (widget.headerExtra != null) ...[
            const SizedBox(height: 14),
            widget.headerExtra!,
          ],
        ],
      ),
      body: ScreenBodyPanel(
        child: Stack(
          children: [
            // The screen's own list is never torn down, only covered: it keeps
            // its scroll offset, so closing search puts the reader back exactly
            // where they were instead of at the top.
            IgnorePointer(
              ignoring: a > 0,
              child: ListView(padding: padding, children: widget.body(context)),
            ),
            if (a > 0)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: a < 1,
                  child: Opacity(
                    opacity: a,
                    // Opaque, so the fade is a crossfade rather than the two
                    // lists showing through each other half-drawn.
                    child: ColoredBox(
                      color: AppColors.screenBg,
                      child: ListView(
                        primary: false,
                        controller: _resultsScroll,
                        padding: padding,
                        children: [_results(context, query)],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _results(BuildContext context, String query) {
    if (query.isEmpty) {
      return SearchResultsPlaceholder(query: '', prompt: widget.searchPrompt);
    }
    return widget.results(context, query, _closeSearch) ??
        SearchResultsPlaceholder(query: query, prompt: '');
  }
}
