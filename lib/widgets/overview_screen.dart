import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'bottom_nav.dart';
import 'collapsing_header.dart';
import 'glass.dart';
import 'search.dart';

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

class _SearchableOverviewScreenState extends State<SearchableOverviewScreen> {
  /// Search runs *in* the screen (see [HeaderSearchBar]): the header becomes
  /// the system search field and this body shows the hits — no sheet over the
  /// content.
  bool _searching = false;
  String _query = '';

  void _openSearch() => setState(() => _searching = true);

  void _closeSearch() {
    setState(() {
      _searching = false;
      _query = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim();
    return CollapsingHeaderScreen(
      titleRowBuilder: (context, t) => HeaderSearchBar(
        active: _searching,
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
          trailing: GlassIconButton(icon: LucideIcons.plus, onTap: widget.onAdd),
        ),
      ),
      // While searching the header is only the field: the trigger pill would be
      // a second search box for the same query.
      estimatedExtraHeight: _searching ? 0 : widget.extraHeight,
      extra: _searching
          ? const SizedBox.shrink()
          : Column(
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
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 18, 16, navContentInset(context, pill: 140)),
          children: _searching ? [_results(context, query)] : widget.body(context),
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
