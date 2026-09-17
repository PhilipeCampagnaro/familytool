part of '../calendar_screen.dart';

// ---------------------------------------------------------------------------
// Week view
// ---------------------------------------------------------------------------

class _WeekView extends ConsumerStatefulWidget {
  final CalendarScreenState state;
  final Color accent;

  /// The name of the screen this is mounted on — Home, since the Kalender tab
  /// is the month grid now. See [CalendarWeekScreen].
  final String title;

  /// Rides opposite the month/year label, where the view toggle used to be.
  final Widget? trailing;

  /// Home's status island, in the row that names the month on the other tab.
  /// Null falls back to the plain label. See [CalendarWeekScreen].
  final Widget? label;

  /// Directly under the label, above the filter chips: Home's first-steps
  /// checklist, folded out of the island. Always built; how much of it shows is
  /// [underLabelHeight].
  final Widget? underLabel;

  /// How tall that panel is when it is open, and zero when it is not — the
  /// caller's arithmetic, not a measurement, because the header's collapsing
  /// extent has to be known before the panel is laid out. The view animates
  /// between the two.
  final double underLabelHeight;

  /// Below the day card. Home's, and null on any other caller.
  final Widget? belowDay;

  const _WeekView({
    required this.state,
    required this.accent,
    required this.title,
    this.trailing,
    this.label,
    this.underLabel,
    this.underLabelHeight = 0,
    this.belowDay,
  });

  @override
  ConsumerState<_WeekView> createState() => _WeekViewState();
}

/// The day strip is a plain continuously-scrolling list of days: flick it and
/// it moves by however far you flicked, like any other horizontal list. It used
/// to page a whole week at a time off a drag-velocity threshold, which made
/// small drags either snap seven days away or do nothing at all.
///
/// The list is finite but deep ([_stripDayCount] days centred on today), which
/// is far past anything reachable by flicking and avoids the bookkeeping of a
/// two-directional `center:` sliver for a strip this simple. Days are addressed
/// by index off [_stripEpoch]; [_stripDate] and [_stripIndexOf] convert.
class _WeekViewState extends ConsumerState<_WeekView> with SingleTickerProviderStateMixin {
  static const _stripDaysBefore = 730;
  static const _stripDayCount = 1461;
  static const _stripGap = 6.0;

  static final DateTime _stripEpoch = calToday().subtract(const Duration(days: _stripDaysBefore));

  static DateTime _stripDate(int index) => _stripEpoch.add(Duration(days: index));

  static int _stripIndexOf(DateTime date) =>
      DateTime(date.year, date.month, date.day).difference(_stripEpoch).inDays;

  final ScrollController _stripController = ScrollController();

  /// Per-day extent including its trailing gap, set once the strip has been
  /// laid out — the conversions between scroll offset and day index need it,
  /// and it depends on the available width.
  double _stripItemExtent = 0;

  /// Whether today is currently on screen in the strip — drives the "Heute"
  /// button, which tracks the strip rather than the selected week.
  ///
  /// The only thing the strip's scroll position still feeds. It used to drive a
  /// month/year label above the chips as well, which followed the leftmost
  /// visible day rather than the selection; that label is "Dein Tag" now and
  /// names no month, so the anchor it needed went with it.
  bool _todayVisible = true;

  CalSelectedDay? _lastSelected;

  @override
  void initState() {
    super.initState();
    _stripController.addListener(_onStripScroll);
    _lastSelected = widget.state.selected;
    // Open on the first frame without an animation, so a household that left
    // the checklist unfolded does not watch it unfold again on every rebuild
    // of the screen.
    if (widget.underLabelHeight > 0) {
      _panelFull = widget.underLabelHeight;
      _panel.value = 1;
    }
  }

  @override
  void didUpdateWidget(_WeekView old) {
    super.didUpdateWidget(old);
    if (old.underLabelHeight != widget.underLabelHeight) _syncPanel();
  }

  @override
  void dispose() {
    _panel.dispose();
    _stripController.dispose();
    super.dispose();
  }

  void _onStripScroll() {
    if (_stripItemExtent <= 0 || !_stripController.hasClients) return;
    final firstIndex = (_stripController.offset / _stripItemExtent).round().clamp(0, _stripDayCount - 1);
    final todayIndex = _stripIndexOf(calToday());
    final todayVisible = todayIndex >= firstIndex && todayIndex < firstIndex + 7;
    if (todayVisible != _todayVisible) {
      setState(() => _todayVisible = todayVisible);
    }
  }

  /// Scrolls [date] into view. Used when the selection changes from outside
  /// the strip, and by the "Heute" button — never in response to the user's own
  /// scrolling, since a strip that yanked itself back after every flick would
  /// be unusable.
  void _revealDate(DateTime date, {bool animate = true}) {
    if (_stripItemExtent <= 0 || !_stripController.hasClients) return;
    final index = _stripIndexOf(date);
    final firstIndex = (_stripController.offset / _stripItemExtent).round();
    if (index >= firstIndex && index < firstIndex + 7) return;
    // Land the day **first**, so "Heute" and the day the app opens on are the
    // leftmost cell and the six the strip shows beside it are the days still to
    // come. It used to land third-from-left for context on both sides, which
    // spent two of seven cells on days that had already happened.
    final target = (index * _stripItemExtent).clamp(0.0, _stripController.position.maxScrollExtent);
    if (animate) {
      _stripController.animateTo(
        target,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    } else {
      _stripController.jumpTo(target);
    }
  }

  void _jumpToToday() {
    ref.read(calendarProvider.notifier).selectDayToday();
    // Scrolled explicitly rather than leaning on the selection-change path in
    // build(): the button's visibility tracks the *strip*, so the common case
    // is that today is still the selected day and the strip has simply been
    // scrolled away from it. `selectDay` is then a no-op and nothing would move.
    _revealDate(calToday());
  }

  // The header's total height at rest (title row + toggle/chips row + day
  // strip) versus what's left once collapsed (title row + the gap below it) —
  // see _buildHeader. Approximates the natural height of that content; minor
  // mismatches just mean a few px of empty/clipped space, not a layout error,
  // since the collapsing math is self-consistent (collapsed + extra always
  // sums back to expanded).
  //
  // _collapsedGap is inside the *collapsed* height on purpose: it's the strip
  // of header that survives below the title row at t == 1, and — since the
  // header has a frosted background (see _buildHeader) — it's the band the gray
  // agenda body passes under blurred, so the sharp gray starts a little below
  // the glass buttons instead of butting straight against them.
  static const _collapsedGap = 14.0;
  static const _collapsedHeaderHeight = 48.0 + _collapsedGap;
  // 16 top + 48 island row + 14 + 44 chip row + 12 + the strip + 4 bottom,
  // rounded up so a font-metric wobble leaves slack rather than clipping. The
  // strip is the only term that moves with the type scale, so it is the only
  // one not folded into the constant — at the shipped scale this is still 294.
  static double get _baseExtraHeight => 142.0 + _stripHeight;

  /// The header's extent, panel included. **Not a constant any more**: Home's
  /// first-steps checklist opens *inside* the header rather than over the top
  /// of it, so the block it lives in grows by exactly its height and the whole
  /// day moves down. Everything else about the collapse is unchanged — this is
  /// still one number the sliver is laid out against, it is just no longer the
  /// same number all day.
  double get _extraHeaderHeight => _baseExtraHeight + _panelHeight;

  // Home's island is a sentence over the noun it counts, so this row is taller
  // than the 40 a month name takes on the other tab — eight points, paid for
  // once, above.
  static const _labelHeight = 48.0;
  double get _expandedHeaderHeight => _collapsedHeaderHeight + _extraHeaderHeight;

  /// The panel's open fraction. Driven here rather than by an `AnimatedSize`
  /// inside the header because the number the sliver is measured against and
  /// the space the panel occupies have to be the same number on the same frame;
  /// a child that animated its own height would be a frame ahead of the header
  /// containing it, and the chips would jump.
  late final AnimationController _panel = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  )..addListener(() => setState(() {}));

  /// The panel's height when fully open. Held past the close so the collapse
  /// animates back down through the same distance it came up.
  double _panelFull = 0;

  double get _panelHeight => _panelFull * _panel.value;

  void _syncPanel() {
    final target = widget.underLabelHeight;
    if (target > 0) {
      _panelFull = target;
      _panel.forward();
    } else {
      _panel.reverse();
    }
  }

  Widget _buildHeader(BuildContext context, double t, CalendarScreenState state, Color accent, Widget label) {
    // Frosted, not transparent and not solid: NestedScrollView's body isn't
    // clipped to below the pinned header — the gray agenda keeps sliding up
    // until its top hits the screen's — so a see-through header had the agenda's
    // first rows rendering sharply behind the title and glass buttons. The blur
    // is what makes them stop reading as content while still showing that
    // they're there, passing underneath (an iOS nav bar).
    //
    // A Stack, not a ColoredBox wrapper, so the frost is a sibling layer that
    // fills the header's *current* extent — as the sliver shrinks, the blurred
    // band shrinks with it.
    return Stack(
      children: [
        Positioned.fill(child: FrostedHeaderBackground()),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 8, AppSpacing.screenPad, 0),
              child: _TitleRow(
                t: t,
                title: widget.title,
                leading: _CalendarFilterButton(state: state),
                // The profile avatar, where Kalender puts its actions capsule.
                // Home has no header actions at all — see [_TitleRow.trailing].
                trailing: widget.trailing,
                trailingWidth: _avatarSlot,
              ),
            ),
            SizedBox(
              height: _extraHeaderHeight * (1 - t),
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minHeight: _extraHeaderHeight,
                  maxHeight: _extraHeaderHeight,
                  child: Opacity(
                    opacity: (1 - t).clamp(0.0, 1.0),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.screenPad,
                            16,
                            AppSpacing.screenPad,
                            0,
                          ),
                          child: _MonthAndChipsRow(
                            state: state,
                            accent: accent,
                            label: label,
                            labelHeight: _labelHeight,
                            labelTrailing: _buildJumpToToday(accent),
                            // Sized by the same value the sliver was measured
                            // against, and clipped to it: the rows are built at
                            // their full height throughout and the panel shows
                            // as much of them as it has opened.
                            // Nothing at all while it is shut: a zero-height
                            // box would hand the rows a tight zero to lay
                            // themselves out in and overflow against it.
                            underLabel: widget.underLabel == null || _panelHeight <= 0
                                ? null
                                : SizedBox(
                                    height: _panelHeight,
                                    child: ClipRect(
                                      child: OverflowBox(
                                        alignment: Alignment.topCenter,
                                        minHeight: _panelFull,
                                        maxHeight: _panelFull,
                                        child: widget.underLabel,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        Padding(
                          // Only the left edge is inset: the strip runs to the
                          // right screen edge so days visibly continue off-screen
                          // rather than stopping at a margin, which is what makes
                          // it read as scrollable.
                          padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 12, 0, 4),
                          child: SizedBox(height: _stripHeight, child: _buildDayStrip(state, accent)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Kept outside the collapsing block so it survives at t == 1 — this
            // is the band of frost between the header buttons and the sharp
            // gray body.
            const SizedBox(height: _collapsedGap),
          ],
        ),
      ],
    );
  }

  /// "Heute", **at the right end of the status island's row** rather than
  /// parked above the nav bar.
  ///
  /// It answers "the strip has been scrolled away from today", so it belongs in
  /// the header with the strip. Above the bar it was a finger's width from the
  /// bottom of a page that scrolls, and Home no longer collapses the bar, so
  /// there was no nav row for it to drop onto either. Living in the header's
  /// collapsing block, it fades and goes with the strip it refers to.
  ///
  /// Null while today is on the strip, so the island has the whole row. The
  /// slide in from the right and back out is the row's — see
  /// [_MonthYearRow.trailing].
  ///
  /// Kalender's month view keeps [_JumpToTodaySlot] on the nav row.
  Widget? _buildJumpToToday(Color accent) {
    if (_todayVisible) return null;
    return _JumpToTodayButton(visible: true, accent: accent, onNavRow: false, onTap: _jumpToToday);
  }

  /// The 40pt profile circle plus the gap the title keeps from it — what
  /// [_TitleRow.trailingWidth] wants for Home's own trailing widget.
  static const _avatarSlot = 52.0;

  // The forecast + gap + the rounded day tile (weekday letter, day circle,
  // dots) — see the arithmetic on [_DayStripCell] — plus 4 points of slack, so
  // a font-metric wobble leaves room rather than clipping.
  static double get _stripHeight => _DayStripCell.cellHeight + 4;

  Widget _buildDayStrip(CalendarScreenState state, Color accent) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Size cells so exactly seven fill the screen's usable width — the
        // strip scrolls freely, but a week still lines up with what you see.
        final usable = constraints.maxWidth - AppSpacing.screenPad;
        final cellWidth = (usable - _stripGap * 6) / 7;
        final itemExtent = cellWidth + _stripGap;
        if (itemExtent != _stripItemExtent) {
          _stripItemExtent = itemExtent;
          // First layout: put the selected day's week on screen without an
          // animation, since there's nothing to animate away from yet.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _stripController.hasClients && _stripController.offset != 0) return;
            final sel = widget.state.selected;
            _revealDate(DateTime(sel.y, sel.m, sel.d), animate: false);
            _onStripScroll();
          });
        }
        return ListView.builder(
          key: calendarDayStripKey,
          controller: _stripController,
          scrollDirection: Axis.horizontal,
          itemExtent: itemExtent,
          padding: EdgeInsets.zero,
          itemCount: _stripDayCount,
          itemBuilder: (context, index) {
            final date = _stripDate(index);
            return Padding(
              padding: const EdgeInsets.only(right: _stripGap),
              child: _DayStripCell(
                date: date,
                letter: dayLetters[(date.weekday + 6) % 7],
                state: state,
                accent: accent,
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final accent = widget.accent;
    final sel = state.selected;
    final selDate = DateTime(sel.y, sel.m, sel.d);
    final events = _demoEvents(state.eventsFor(sel.y, sel.m, sel.d), selDate);
    // Only while the chip is lit — and unfiltered by the calendar row, which is
    // the whole point of it standing apart from those chips. See
    // [CalendarScreenState.showTasks].
    final todos = state.showTasks
        ? _demoTodos(_todosDueOn(ref, sel.y, sel.m, sel.d), selDate)
        : const <BoardTask>[];
    // The day split the way the grid draws it: the band above, the clock below.
    // See [_dayPlan].
    final plan = _dayPlan(events, todos, selDate);
    final headingText = _dayHeading(selDate);
    final holiday = ref.watch(germanHolidaysProvider).on(sel.y, sel.m, sel.d);

    // A selection made outside the strip (the "Heute" button) has to be
    // scrolled to; one made by tapping a cell is already on screen, and
    // _revealDate no-ops for it.
    final last = _lastSelected;
    if (last == null || last.y != sel.y || last.m != sel.m || last.d != sel.d) {
      _lastSelected = sel;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revealDate(selDate);
      });
    }

    return Stack(
      children: [
        NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverPersistentHeader(
              pinned: true,
              delegate: CollapsingSliverHeaderDelegate(
                expandedHeight: _expandedHeaderHeight,
                collapsedHeight: _collapsedHeaderHeight,
                builder: (context, t) => _buildHeader(
                  context,
                  t,
                  state,
                  accent,
                  widget.label ??
                      Text(L.s.yourDay, key: const ValueKey('yourDay'), style: AppText.sectionHeading),
                ),
              ),
            ),
          ],
          // **One scroll for the whole page.** The agenda used to be its own
          // scroller filling the viewport below a panel that never moved, which
          // is precisely why nothing could ever sit under it. It is a row of
          // widgets in this list now, the gray card sizes itself to the day, and
          // everything Home has to say that is *not* about a day goes below it.
          //
          // Still a `NestedScrollView`: its body is laid out at the viewport's
          // full height, so there is always enough travel to collapse the header
          // even on a day with one appointment and nothing else on screen. A
          // plain `CustomScrollView` would have left the header stuck open
          // whenever the content was shorter than the display.
          body: LayoutBuilder(
            builder: (context, viewport) => ListView(
              padding: EdgeInsets.zero,
              children: [
                _DayBody(
                  // At least the viewport, so the grey reaches the bottom of the
                  // screen on a short day rather than stopping mid-page.
                  minHeight: viewport.maxHeight,
                  bottomInset: navContentInset(context),
                  below: widget.belowDay,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.02),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      // The to-do toggle joins the key, so turning the chip on
                      // crossfades the day the way changing the filter does rather
                      // than having rows appear under the reader's thumb. It also
                      // resets [_DayAgenda]'s fold, so a day always opens showing
                      // what it shows rather than inheriting the last day's
                      // "weitere" still unfolded.
                      key: ValueKey(
                        '${sel.y}-${sel.m}-${sel.d}-${state.calendarFilterKey}-${state.showTasks}',
                      ),
                      child: _DayAgenda(
                        holiday: holiday,
                        plan: plan,
                        day: selDate,
                        headingText: headingText,
                        accent: accent,
                        // A day with only to-dos on it is not an empty day, so the
                        // empty state waits for both to be empty.
                        empty: events.isEmpty && todos.isEmpty,
                        eventCount: events.length,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// What a day with nothing on it offers — and it is not always the same thing.
///
/// A household with no connected calendar has an empty *calendar*, not an empty
/// day, and "Termin hinzufügen" answers a question it isn't asking: the event
/// would go into Aporah's own calendar and the family would still not see their
/// school, work or bin dates. Someone who skipped the onboarding lands here
/// first, so this is where connecting has to be reachable — one tap through to
/// the same Settings → Kalender page the onboarding would have shown.
///
/// Guarded on [CalendarScreenState.loaded] so the button doesn't flip from
/// "connect" to "add" a moment after the screen paints, while the first fetch is
/// still out.
class _EmptyDayActions extends ConsumerWidget {
  const _EmptyDayActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(calendarProvider);
    // Every calendar there is comes from a connection or a feed, so having any
    // at all is the same question as being connected.
    final connected = state.calendars.isNotEmpty;

    if (state.loaded && !connected) {
      return GlassAccentButton(
        label: L.s.connectCalendars,
        icon: AppIcons.calendarPlus,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CalendarConnectionsPage())),
      );
    }

    return GlassAccentButton(label: L.s.addEvent, onTap: () => _openNewEventSheet(context, ref));
  }
}

/// The grey surface under Home's page: the selected day at the top and, below a
/// divider, [below] — the household as it stands (`HomeSections`) — running
/// **all the way to the bottom of the screen**, rounded only at the top.
///
/// It used to be a card that ended under the day, with the sections on white
/// paper beneath it. One surface reads as one page; the divider is now the edge
/// between "whichever date the strip is on" and "the household right now", and
/// the section headings under it name what the new part is.
///
/// Still full-bleed rather than inset like a card: the agenda rows inside it
/// have a 54pt time rail, and pulling the whole thing in from both margins
/// would cost the appointment names the width they actually need.
///
/// Both calendar screens are `AppColors.surface`, so this is what gives the day
/// an edge and keeps it from running into the white above it.
///
/// **It is only safe because the chips are opaque.** A translucent chip takes
/// whatever is behind it into its own colour, so on grey every calendar drifted
/// toward the same dusty register — which is why the fill is now a lightened
/// version of the calendar's colour rather than an alpha of it. See
/// `_blockFill`. The section cards below are `AppColors.cardOnSurface`, a step
/// lighter than this grey on both palettes.
class _DayBody extends StatelessWidget {
  final Widget child;

  /// Under the divider. Null draws the day alone, still to the bottom.
  final Widget? below;

  /// The viewport's height, so the grey fills the screen on a short page.
  final double minHeight;

  /// Room left at the bottom so the last section clears the nav bar.
  final double bottomInset;

  const _DayBody({required this.child, required this.minHeight, required this.bottomInset, this.below});

  static const _radius = Radius.circular(26);

  /// The glass '+' in the card's top-right corner, and the room
  /// [_DayAgenda]'s title leaves for it.
  static const addButtonSize = 32.0;
  static const _addButtonTop = 14.0;
  static const _addButtonRight = 12.0;
  static const headingTrailingInset = addButtonSize + 8;

  @override
  Widget build(BuildContext context) {
    final below = this.below;
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        color: AppColors.screenBg,
        borderRadius: const BorderRadius.vertical(top: _radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              // **The day is clipped on its own, so the timeline's dot lattice
              // stops at the divider.** `_DotCanvas` is sized by the hour grid —
              // it has to be, because only the grid knows where an hour falls —
              // and it overdraws in every direction so the dots carry on under
              // the heading, under the all-day band and past the last hour. With
              // the sections sharing this grey, an unclipped lattice would run on
              // under them.
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: _radius),
                child: Padding(padding: const EdgeInsets.fromLTRB(14, 20, 16, 16), child: child),
              ),
              // Add an appointment without leaving Home — the same sheet as
              // Kalender's '+', dated to whichever day the strip is on.
              //
              // **Here rather than in `_DayAgenda`'s title row**, because the
              // day is an `AnimatedSwitcher` child that slides on every change
              // of day, and a platform view smears when Flutter transforms it.
              // Painted last so the native glass composites above the day.
              Positioned(
                top: _addButtonTop,
                right: _addButtonRight,
                child: Consumer(
                  builder: (context, ref, _) => GlassIconButton(
                    icon: AppIcons.plus,
                    label: L.s.addEvent,
                    size: addButtonSize,
                    // One tier down from the header buttons' glyph, to suit the
                    // smaller button.
                    iconSize: AppGlyph.row,
                    onTap: () => _openNewEventSheet(context, ref),
                  ),
                ),
              ),
            ],
          ),
          if (below != null) ...[
            Padding(
              // The day's own 14/16 inset, so the divider and the sections
              // under it share the calendar's margins.
              padding: const EdgeInsets.fromLTRB(14, 4, 16, 0),
              child: Divider(height: 1, thickness: 1, color: AppColors.hairline),
            ),
            below,
          ],
          SizedBox(height: bottomInset),
        ],
      ),
    );
  }
}

/// What is inside the day card: its title, the Feiertag, then the day itself.
///
/// **The title names the date and counts the appointments, exactly as
/// Kalender's day box does.** Without it the band's chips sat at the top of a
/// grey card with nothing saying whose day they were — the strip's highlight
/// was the only link. The island above says something else on purpose; see
/// `DayIsland`.
///
/// **There is no cap and no fold any more.** The agenda was a column of cards,
/// so a badly connected calendar could push the sections below it a thousand
/// points down the page and `_maxEntries` existed to stop that. A grid cannot:
/// its height comes from the hours it covers, not from how many things stand on
/// them, so a day with forty appointments is exactly as tall as a day with four
/// and the founding brief — open the app, see everything happening today — is
/// finally met without an exception attached to it.
class _DayAgenda extends StatelessWidget {
  final GermanHoliday? holiday;
  final _DayPlan plan;
  final DateTime day;
  final String headingText;
  final Color accent;
  final bool empty;

  /// Appointments only, not to-dos — the same count Kalender prints.
  final int eventCount;

  const _DayAgenda({
    required this.holiday,
    required this.plan,
    required this.day,
    required this.headingText,
    required this.accent,
    required this.empty,
    required this.eventCount,
  });

  /// What an empty day is given so the card still reads as a card rather than
  /// as a gray stripe. The only place a height is asserted here — every other
  /// day is as tall as what is on it.
  static const _emptyHeight = 170.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          // Clear of `_DayBody`'s glass '+', which floats over this corner.
          padding: const EdgeInsets.only(left: 2, right: _DayBody.headingTrailingInset, bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(headingText, overflow: TextOverflow.ellipsis, style: AppText.itemTitle),
              ),
              // No "0 Termine" on an empty day: the empty state below says it
              // in a sentence.
              if (eventCount > 0) ...[
                const SizedBox(width: 8),
                Text(L.s.eventCount(eventCount), style: AppText.label),
              ],
            ],
          ),
        ),
        // On a day with something on it the Feiertag is the first chip in the
        // band — it is a property of the date, so it belongs with the other
        // things true of the whole day rather than in a row of its own above
        // them. An empty day has no band to put it in, and a day off with
        // nothing planned is still worth saying, so there it stands alone.
        if (holiday case final holiday? when empty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _HolidayChip(holiday: holiday, accent: accent),
          ),
        if (empty)
          SizedBox(
            height: _emptyHeight,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(L.s.noEventsThisDay, style: AppText.body.copyWith(color: AppColors.inkTertiary)),
                  const SizedBox(height: 18),
                  _EmptyDayActions(),
                ],
              ),
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: _DayTimeline(
              plan: plan,
              holiday: holiday,
              day: day,
              headingText: headingText,
              accent: accent,
            ),
          ),
      ],
    );
  }
}

class _DayStripCell extends ConsumerWidget {
  // A cell is three stacked pieces: the forecast, loose above; the rounded
  // tile; and inside that the weekday letter, the day number and the dots.
  //
  //   _weatherBand 48  ( _weatherIcon 30 over _weatherTemp 18 )
  //   _weatherGap   8
  //   tile             ( 8 + _letterBand + 6 + circle + 8 + _dotBand 8 + 8 )
  //   ---------------
  //   cellHeight, and _stripHeight leaves a little over it.
  //
  // The two variables in that sum — the letter band and the circle — come from
  // the installed AppTypeScale, so the shipped scale still adds up to the
  // 92-point tile and the 148-point cell it always did.

  /// The forecast, and it sits **outside the tile**, where the weekday letter
  /// used to.
  ///
  /// The two swapped places, and the swap is what makes the icon legible. A
  /// Meteocon is a full-colour drawing with soft edges, and several of them are
  /// pale — an overcast cloud, a snow cloud — so on a near-white tile they stop
  /// reading long before they stop being drawn: at 20, and worse at 16, they
  /// are smudges. A cell is a seventh of the screen, about 45 points, so an
  /// icon beside a two-digit temperature can never exceed 24; stacked, it is
  /// bounded by height instead, and height outside the tile costs the tile
  /// nothing. The letter is one glyph and fits the narrow band it left behind.
  ///
  /// Size was only ever half of it — the cloud art itself measured 1.09:1
  /// against this ground until it was deepened; see [WeatherReading.iconAsset].
  ///
  /// Reserved whether or not there is a forecast: a strip whose cells changed
  /// height as the 16-day horizon ran out would ripple every time it was
  /// scrolled. [_DayWeather] splits it into exactly these two parts rather than
  /// letting its column size itself — `AppText.microLabel` sets no `height`, so
  /// its line box is whatever Poppins' metrics make it, about 16 at 11.5pt, and
  /// a band guessed at the sum of two natural heights overflowed every visible
  /// cell at once.
  static const _weatherBand = _weatherIcon + _weatherTemp;
  static const _weatherIcon = 30.0;
  static const _weatherTemp = 18.0;
  static const _weatherGap = 8.0;

  /// The weekday letter, now the tile's top band. Sized for
  /// [AppText.weekdayLetter]'s own line box rather than left to it, so the day
  /// numbers below line up across cells whatever the font does — and **derived
  /// from the installed scale rather than written down**, because a band typed
  /// out beside a size is exactly the coupling that clips the letter the day
  /// somebody changes the scale. At the shipped 15pt it is still the 20 it
  /// always was.
  static double get _letterBand => AppText.lineBox(AppText.scale.weekdayLetter.size);

  /// The tile, and above it the whole cell. Both follow the circle and the
  /// band, so the strip re-measures itself when the scale moves instead of
  /// being re-counted by hand.
  static double get _tileHeight => 38.0 + _letterBand + AppText.dayCircle;
  static double get cellHeight => _weatherBand + _weatherGap + _tileHeight;

  /// The bottom band, where the calendars' dots and the to-do ring sit. They
  /// stay with the number: the dots are what is *in* the day, where the
  /// forecast is about the day as a whole and now sits above the tile entirely.
  static const _dotBand = 8.0;

  final DateTime date;
  final String letter;
  final CalendarScreenState state;
  final Color accent;

  const _DayStripCell({required this.date, required this.letter, required this.state, required this.accent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sel = state.selected;
    final isSel = _sameDay(sel, date.year, date.month, date.day);
    final today = _isToday(date.year, date.month, date.day);
    // Same two washes as the month grid: a Feiertag and a Ferien day have to
    // read the same way in both views, or the texture stops meaning anything.
    final highlight = _dayHighlight(
      publicHoliday: ref.watch(germanHolidaysProvider).on(date.year, date.month, date.day) != null,
      schoolHoliday: state.isSchoolHoliday(date.year, date.month, date.day),
    );
    final colors = state.dayColors(date.year, date.month, date.day);
    final dots = colors.take(3).toList();
    final overflowCount = colors.length - 3;
    // Only while the overlay is on. A ring on a day whose to-do the agenda is
    // not showing points at nothing, and the reader has no way to find out what
    // it meant.
    final hasTodo =
        state.showTasks &&
        ref.watch(openTodoDaysProvider).contains(CalendarScreenState.key(date.year, date.month, date.day));

    return GestureDetector(
      onTap: () => ref.read(calendarProvider.notifier).selectDay(date.year, date.month, date.day),
      child: Column(
        children: [
          SizedBox(
            height: _weatherBand,
            child: _DayWeather(date: date),
          ),
          const SizedBox(height: _weatherGap),
          Container(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
            decoration: BoxDecoration(
              color: isSel ? tint(accent, .9) : AppColors.screenBg,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                SizedBox(
                  height: _letterBand,
                  child: Center(
                    child: Text(
                      letter,
                      style: AppText.weekdayLetter.copyWith(color: isSel ? AppColors.ink : AppColors.muted),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                DaySelectorCircle(
                  day: date.day,
                  selected: isSel,
                  today: today,
                  highlight: highlight,
                  accent: accent,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: _dotBand,
                  child: Center(
                    child: EventDots(
                      colors: dots,
                      overflowCount: overflowCount,
                      todo: hasTodo,
                      todoColor: accent,
                    ),
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

/// The forecast above a day's tile in the strip: the condition, drawn, and the
/// temperature under it.
///
/// **The day's weather at home, not an appointment's.** A cell is asking what
/// that day is like where the family lives, which it has to be able to answer
/// on a day with nothing planned — see [WeatherState.daily]. The agenda rows
/// below still carry each appointment's own reading at its own hour and in its
/// own town, and the two disagreeing is correct rather than a bug: a swimming
/// lesson two towns over genuinely has different weather.
///
/// There is no reading on any day outside the 16-day horizon, which on a strip
/// four years deep is nearly all of them, nor on a past day, nor in a household
/// that has given no address. That is the same bargain the rest of the feature
/// makes — no reading is no drawing, never an error — and it is why the band
/// keeps its height either way.
///
/// **What stands in for one is a dash, not a skeleton.** A skeleton is a
/// promise that something is on its way, and on a day in 2029 nothing is: the
/// forecast is not late, it does not exist and will not until the day is a
/// fortnight out. Seven shimmering blocks across the top of the screen would be
/// the app telling the reader it is loading, for ever, on the one piece of
/// chrome that is always in front of them. The dash is the convention a table
/// uses for a cell with no value — quiet, uniform, and honest about the fact
/// that it is nothing rather than pretending to be something not yet arrived.
///
/// Stacked, not side by side: a cell is a seventh of the screen and an icon
/// beside a two-digit temperature caps the icon at 24, which is below the size
/// these drawings need to read. See [_DayStripCell._weatherBand].
///
/// The temperature is [AppText.microLabel], the smallest type in the app, in a
/// box of exactly [_DayStripCell._weatherTemp] — so the column is the band's
/// height by construction rather than by adding up two natural heights and
/// hoping.
class _DayWeather extends ConsumerWidget {
  final DateTime date;

  const _DayWeather({required this.date});

  /// The stand-in when there is no forecast. Sized in points rather than set as
  /// a text glyph so it is the same mark whatever the font does with an en
  /// dash, and drawn in [AppColors.mutedLight] so it reads as an absence on
  /// both palettes without competing with the day numbers under it.
  static const _dashWidth = 10.0;
  static const _dashHeight = 2.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reading = ref.watch(weatherProvider).forDay(date);
    if (reading == null) {
      return Center(
        child: Container(
          width: _dashWidth,
          height: _dashHeight,
          decoration: BoxDecoration(
            color: AppColors.mutedLight,
            borderRadius: BorderRadius.circular(_dashHeight / 2),
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          reading.iconAsset,
          width: _DayStripCell._weatherIcon,
          height: _DayStripCell._weatherIcon,
        ),
        SizedBox(
          height: _DayStripCell._weatherTemp,
          child: Center(child: Text(reading.temperatureLabel, maxLines: 1, style: AppText.microLabel)),
        ),
      ],
    );
  }
}

/// Shared agenda-row rail: the time / dot / connecting-line timeline on the
/// left, paired with the event card. Used by both the week view's day agenda
/// and the month view's per-day details box so the timeline isn't drawn
/// twice with two different implementations.
/// Bearbeiten and Löschen for a card inside a carousel, where the swipe that
/// normally reveals them is turning pages instead.
///
/// Anchored on the card itself rather than on the press point, so UIKit's menu
/// grows out of the thing it acts on the way every other menu in the app does.
Future<void> _openEventCardMenu(BuildContext context, WidgetRef ref, CalendarEvent event) async {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return;
  await showAnchoredMenuAt(
    context: context,
    anchor: box.localToGlobal(Offset.zero) & box.size,
    title: event.title,
    items: [
      AnchoredMenuItem(
        label: L.s.edit,
        icon: AppIcons.pencilSimple,
        symbol: 'pencil',
        onSelected: () => _openEditEventSheet(context, ref, event),
      ),
      AnchoredMenuItem(
        label: L.s.delete,
        icon: AppIcons.trash,
        symbol: 'trash',
        destructive: true,
        onSelected: () => _confirmDeleteEvent(context, ref, event),
      ),
    ],
  );
}

/// Liquid-glass "Heute" button shown whenever today's date has scrolled out of
/// view (week view: today isn't in the displayed week; month view: today's day
/// cell isn't in the viewport). Tapping it re-selects today and (in month
/// view) scrolls back to it. Kalender's [_JumpToTodaySlot] puts it on the nav
/// row; Home's week view puts it at the right end of the status island's row
/// ([_WeekViewState._buildJumpToToday]).
///
/// A [FloatingGlassPill] — the nav-row shape on Kalender, the small one under
/// Home's strip — and **the word on its own**: on Kalender it stands a finger's
/// width from the bar's calendar icon, and any calendar glyph on it reads as a
/// duplicate of that icon rather than as a different offer. The word is also
/// the shorter of the two, in every language.
class _JumpToTodayButton extends StatelessWidget {
  final bool visible;
  final Color accent;
  final VoidCallback onTap;

  /// The taller capsule that matches the nav bar's row. False for the small
  /// pill that sits under Home's day strip.
  final bool onNavRow;

  const _JumpToTodayButton({
    required this.visible,
    required this.accent,
    required this.onTap,
    this.onNavRow = true,
  });

  @override
  Widget build(BuildContext context) {
    return FloatingGlassPill(
      visible: visible,
      label: L.s.today,
      accent: accent,
      onNavRow: onNavRow,
      onTap: onTap,
    );
  }
}
