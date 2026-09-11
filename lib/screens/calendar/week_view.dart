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

  static int _stripIndexOf(DateTime date) => DateTime(date.year, date.month, date.day).difference(_stripEpoch).inDays;

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
      _stripController.animateTo(target, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
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
  // rounded up so a font-metric wobble leaves slack rather than clipping.
  static const _baseExtraHeight = 294.0;

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
                          padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 16, AppSpacing.screenPad, 0),
                          child: _MonthAndChipsRow(
                            state: state,
                            accent: accent,
                            label: label,
                            labelHeight: _labelHeight,
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

  /// The 40pt profile circle plus the gap the title keeps from it — what
  /// [_TitleRow.trailingWidth] wants for Home's own trailing widget.
  static const _avatarSlot = 52.0;

  // The forecast + gap + the rounded day tile (weekday letter, 34pt day
  // circle, dots) — see the arithmetic on [_DayStripCell].
  static const _stripHeight = 152.0;

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
    final events = state.eventsFor(sel.y, sel.m, sel.d);
    // Only while the chip is lit — and unfiltered by the calendar row, which is
    // the whole point of it standing apart from those chips. See
    // [CalendarScreenState.showTasks].
    final todos = state.showTasks ? _todosDueOn(ref, sel.y, sel.m, sel.d) : const <BoardTask>[];
    // One list, in reading order — a to-do that names an hour sits at that hour
    // among the appointments. See [_agendaEntries].
    final entries = _agendaEntries(events, todos);
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
                  widget.label ?? Text(L.s.yourDay, key: const ValueKey('yourDay'), style: AppText.sectionHeading),
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
          body: ListView(
            padding: EdgeInsets.only(bottom: navContentInset(context)),
            children: [
              _AgendaGrayBody(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero).animate(animation),
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
                    key: ValueKey('${sel.y}-${sel.m}-${sel.d}-${state.calendarFilterKey}-${state.showTasks}'),
                    child: _DayAgenda(
                      holiday: holiday,
                      entries: entries,
                      headingText: headingText,
                      accent: accent,
                      // A day with only to-dos on it is not an empty day, so the
                      // empty state waits for both to be empty.
                      empty: events.isEmpty && todos.isEmpty,
                    ),
                  ),
                ),
              ),
              ?widget.belowDay,
            ],
          ),
        ),
        _JumpToTodaySlot(visible: !_todayVisible, accent: accent, onTap: _jumpToToday),
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
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CalendarConnectionsPage()),
        ),
      );
    }

    return GlassAccentButton(
      label: L.s.addEvent,
      onTap: () => _openNewEventSheet(context, ref),
    );
  }
}

/// The selected day's card: full-width gray, and **rounded at the bottom as
/// well as the top**.
///
/// That bottom edge is the whole reason Home can say anything else. While this
/// was the viewport's floor it was a background, and anything put near it read
/// as one more appointment; ending it makes it an object, and the white below
/// it is visibly a different subject. What is above the edge is whichever date
/// the strip is on. What is below it is the household as it stands — see
/// `HomeSections`.
///
/// Still full-bleed rather than inset like a card: the agenda rows inside it
/// have a 54pt time rail, and pulling the whole thing in from both margins
/// would cost the appointment names the width they actually need.
class _AgendaGrayBody extends StatelessWidget {
  final Widget child;

  const _AgendaGrayBody({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.screenBg, borderRadius: BorderRadius.circular(26)),
      padding: const EdgeInsets.fromLTRB(14, 20, 16, 16),
      child: child,
    );
  }
}

/// What is inside the day card: the Feiertag, then the day in reading order.
///
/// **It grows with the day and stops at [_maxEntries].** A floor would have been
/// the wrong instinct — the founding brief for this screen was that you open the
/// app and see everything happening today, so truncating today's agenda on the
/// one screen built to show it undoes the point. The cap is high enough that no
/// real family day reaches it and exists only so that a calendar somebody has
/// connected badly cannot push the sections below a thousand points down the
/// page. Past it the rest unfolds in place; there is nowhere else to send
/// anybody, because this *is* the day view.
class _DayAgenda extends StatefulWidget {
  final GermanHoliday? holiday;
  final List<Object> entries;
  final String headingText;
  final Color accent;
  final bool empty;

  const _DayAgenda({
    required this.holiday,
    required this.entries,
    required this.headingText,
    required this.accent,
    required this.empty,
  });

  @override
  State<_DayAgenda> createState() => _DayAgendaState();
}

class _DayAgendaState extends State<_DayAgenda> {
  static const _maxEntries = 8;

  /// What an empty day is given so the card still reads as a card rather than
  /// as a gray stripe. The only place a height is asserted here — every other
  /// day is as tall as what is on it.
  static const _emptyHeight = 170.0;

  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final folded = !_showAll && entries.length > _maxEntries;
    final shown = folded ? entries.take(_maxEntries).toList() : entries;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The Feiertag sits above the agenda rather than in it — it is something
        // about the day, not an appointment on it. A day off with nothing
        // planned is still worth saying, so it shows over the empty state too.
        if (widget.holiday case final holiday?)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _HolidayChip(holiday: holiday, accent: widget.accent),
          ),
        if (widget.empty)
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
        else ...[
          for (var i = 0; i < shown.length; i++)
            if (shown[i] case final BoardTask task)
              _TodoAgendaRow(
                key: ValueKey(task.id),
                task: task,
                isFirst: i == 0,
                accent: widget.accent,
              )
            else if (shown[i] case final CalendarEvent event)
              _EventAgendaRow(
                event: event,
                isFirst: i == 0,
                headingText: widget.headingText,
                accent: widget.accent,
              ),
          if (folded)
            GestureDetector(
              onTap: () => setState(() => _showAll = true),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                // Inset to where the cards start (the rail plus its gap), so the
                // fold reads as the end of the column of cards rather than as a
                // row of its own.
                padding: const EdgeInsets.only(left: _EventAgendaRow._railWidth + 9, top: 2, bottom: 4),
                child: Row(
                  children: [
                    Text(
                      L.s.homeMoreEntries(entries.length - _maxEntries),
                      style: AppText.caption.copyWith(color: widget.accent),
                    ),
                    const SizedBox(width: 4),
                    AppIcon(AppIcons.caretDown, size: 13, color: widget.accent, flat: true),
                  ],
                ),
              ),
            ),
        ],
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
  //   tile          92  ( 8 + _letterBand 20 + 6 + circle 34 + 8 + _dotBand 8 + 8 )
  //   ---------------
  //                148, and _stripHeight leaves a little over it.

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
  /// `AppText.rowTitle`'s own line box at 15pt rather than left to it, so the
  /// day numbers below line up across cells whatever the font does.
  static const _letterBand = 20.0;

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
    final hasTodo = state.showTasks &&
        ref.watch(openTodoDaysProvider).contains(CalendarScreenState.key(date.year, date.month, date.day));

    return GestureDetector(
      onTap: () => ref.read(calendarProvider.notifier).selectDay(date.year, date.month, date.day),
      child: Column(
        children: [
          SizedBox(height: _weatherBand, child: _DayWeather(date: date)),
          const SizedBox(height: _weatherGap),
          Container(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
            decoration: BoxDecoration(color: isSel ? tint(accent, .9) : AppColors.screenBg, borderRadius: BorderRadius.circular(22)),
            child: Column(
              children: [
                SizedBox(
                  height: _letterBand,
                  child: Center(
                    child: Text(letter, style: AppText.rowTitle.copyWith(color: isSel ? AppColors.ink : AppColors.muted)),
                  ),
                ),
                const SizedBox(height: 6),
                DaySelectorCircle(day: date.day, selected: isSel, today: today, highlight: highlight, accent: accent),
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
class _EventAgendaRow extends ConsumerWidget {
  final CalendarEvent event;
  final bool isFirst;
  final String headingText;
  final Color accent;
  final bool compact;

  const _EventAgendaRow({required this.event, required this.isFirst, required this.headingText, required this.accent, this.compact = false});

  /// Wide enough for "Ganztägig" at a legible scale — see the [FittedBox] on
  /// the label. A rail sized to a clock time alone left the all-day rows
  /// hyphenating across two lines.
  static const _railWidth = 54.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(calendarProvider);
    final phase = event.phaseAt(state.now);
    final past = phase == EventPhase.done;
    final live = phase == EventPhase.now;
    final rail = AppColors.hairline2;
    final timeColor = past ? AppColors.muted : (live ? accent : AppColors.inkTertiary);
    // Ferien, Abfall and any calendar the connected account can only read stay
    // untouchable — offering the swipe action there would be a lie. Everything
    // else is editable, including a Google event, which travels back out to
    // Google rather than being changed in a row of ours.
    final editable = state.sourceById(event.calendarId)?.editable ?? false;
    const railAnim = Duration(milliseconds: 320);
    const railCurve = Curves.easeOutCubic;

    return Padding(
      padding: const EdgeInsets.only(bottom: 0),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: _railWidth,
              child: Column(
                children: [
                  AnimatedContainer(duration: railAnim, curve: railCurve, width: 2, height: 10, color: isFirst ? Colors.transparent : (past || live ? accent : rail)),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: AnimatedDefaultTextStyle(
                      duration: railAnim,
                      curve: railCurve,
                      style: AppText.groupHeading.copyWith(letterSpacing: -0.3, color: timeColor),
                      // A clock time fits the rail at full size; "Ganztägig"
                      // does not, and wrapped to "Ganzt-/ägig" over two lines it
                      // also pushed this row's dot out of line with its
                      // neighbours'. Scaling down is the one treatment that
                      // holds for every label in both languages — the rail is
                      // sized for a time, and anything longer simply shrinks to
                      // the single line it has.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(event.timeLabel, maxLines: 1, softWrap: false),
                      ),
                    ),
                  ),
                  AnimatedContainer(
                    duration: railAnim,
                    curve: railCurve,
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: past ? accent : AppColors.surface, shape: BoxShape.circle, border: Border.all(color: past || live ? accent : rail, width: 2.5)),
                  ),
                  Expanded(child: AnimatedContainer(duration: railAnim, curve: railCurve, width: 2, color: past ? accent : rail)),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: compact ? 10 : 14),
                // Swipe-left on a card reveals Edit/Delete, so fixing a title
                // or removing an event doesn't always require opening the full
                // detail sheet first.
                child: SwipeActionsRow(
                  // Keyed on the event, so a deleted row takes its open swipe
                  // with it instead of handing it to whichever appointment
                  // moves up into its place in the agenda.
                  key: ValueKey(event.id),
                  borderRadius: BorderRadius.circular(compact ? 16 : 20),
                  onTap: () {
                    ref.read(calendarProvider.notifier).openEvent(event, headingText);
                    _showEventDetailSheet(context, ref);
                  },
                  actions: [
                    if (editable) ...[
                      SwipeAction(
                        icon: AppIcons.pencilSimple,
                        color: accent,
                        // No need to open the event first: the edit sheet is
                        // seeded from the row it was swiped on.
                        onTap: () => _openEditEventSheet(context, ref, event),
                      ),
                      SwipeAction(
                        icon: AppIcons.trash,
                        color: AppColors.danger,
                        // The confirm dialog and the removal own what happens
                        // next; snapping the row shut under it just fights that.
                        closesRow: false,
                        onTap: () => _confirmDeleteEvent(context, ref, event),
                      ),
                    ],
                  ],
                  child: _EventCard(
                    event: event,
                    compact: compact,
                    weather: _weatherFor(ref, event),
                    linkedLists: _linkedListsFor(ref, event).length,
                    linkedTasks: _linkedTasksFor(ref, event).length,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One to-do's row in the agenda — the rail on the left, its card on the right.
///
/// Deliberately the same rail as [_EventAgendaRow] so the day stays one column
/// with one line running down it, and deliberately a different card, so no row
/// of it can be mistaken for an appointment. The rail says [AppStrings.dueRailLabel]
/// where an event says a clock time: a due date carries no time, and "Ganztägig"
/// would claim the to-do occupies the day rather than merely being owed by the
/// end of it.
///
/// The dot follows *done*, not the clock. An event's dot fills as the day passes
/// it; a to-do's fills when somebody ticks it, which is the only thing about a
/// to-do that a calendar can honestly show as having happened.
class _TodoAgendaRow extends ConsumerWidget {
  final BoardTask task;
  final bool isFirst;
  final Color accent;
  final bool compact;

  const _TodoAgendaRow({super.key, required this.task, required this.isFirst, required this.accent, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rail = AppColors.hairline2;
    final done = task.done;
    final at = task.dueTime;
    const railAnim = Duration(milliseconds: 320);
    const railCurve = Curves.easeOutCubic;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _EventAgendaRow._railWidth,
            child: Column(
              children: [
                AnimatedContainer(duration: railAnim, curve: railCurve, width: 2, height: 10, color: isFirst ? Colors.transparent : (done ? accent : rail)),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: AnimatedDefaultTextStyle(
                    duration: railAnim,
                    curve: railCurve,
                    style: AppText.groupHeading.copyWith(
                      letterSpacing: -0.3,
                      color: done ? AppColors.muted : AppColors.inkTertiary,
                    ),
                    // The hour where the to-do names one — it is then sorted
                    // in among the appointments and the rail has to say why it
                    // is there — and "Fällig" where it does not.
                    //
                    // Same treatment as the event rail's: the rail is sized for
                    // a clock time, and any word longer than one shrinks to the
                    // single line it has rather than hyphenating.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        at == null ? L.s.dueRailLabel : formatTimeOfDay(at.hour, at.minute),
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: railAnim,
                  curve: railCurve,
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: done ? accent : AppColors.surface, shape: BoxShape.circle, border: Border.all(color: done ? accent : rail, width: 2.5)),
                ),
                Expanded(child: AnimatedContainer(duration: railAnim, curve: railCurve, width: 2, color: done ? accent : rail)),
              ],
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: compact ? 10 : 14),
              // **No swipe actions, unlike the event card beside it.** There
              // the swipe reveals Bearbeiten and Löschen because the card's own
              // tap opens a *detail* sheet and editing is a second thing. A
              // to-do has no detail sheet — its tap already opens the editor —
              // so a swipe could only offer the same sheet a second way.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => openTaskSheet(context, ref, task: task),
                // **Not [CheckOffRow].** That plays the strike and then
                // collapses the row to nothing, because on the Board a ticked
                // to-do leaves the open list and travels to "Erledigt". Here it
                // stays exactly where it is — a day whose to-dos all vanished as
                // they were done would end up reading like a day that never had
                // any. So the strike is driven off the row's own state instead,
                // and animates because the value it is given changes.
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: done ? 1 : 0),
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  builder: (context, strike, _) => _TodoCard(
                    task: task,
                    accent: accent,
                    compact: compact,
                    strike: strike,
                    onCheckOff: () => ref.read(boardProvider.notifier).toggle(task),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One to-do's card in the agenda.
///
/// **It carries the check, and that is what keeps it from reading as an
/// appointment.** No event card in the agenda has one, so the circle at the
/// right-hand end is the whole signal — no coloured fill, no second label
/// saying "To-do", nothing that would make the day a two-tone list.
///
/// The check is also the one place this breaks the rule the event card's link
/// chips follow. Those are markers because a 12pt glyph is too small to aim at;
/// this is the Board's own 26pt button, the same size and in the same corner as
/// on the Board itself. A to-do you can see and cannot tick is the calendar
/// showing you your day and making you leave it to change anything.
class _TodoCard extends ConsumerWidget {
  final BoardTask task;
  final Color accent;
  final bool compact;

  /// 0 → 1 as the row is checked off, 1 → 0 as it is undone. Drives the strike
  /// and the ink at once, so the text fades to the done colour as the line
  /// crosses it.
  final double strike;
  final VoidCallback onCheckOff;

  const _TodoCard({required this.task, required this.accent, required this.compact, required this.strike, required this.onCheckOff});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final who = whoBadge(
      assigneeId: task.assigneeId,
      visibility: task.visibility,
      sharedWith: task.sharedWith,
      members: ref.watch(householdMembersProvider),
    );
    final note = task.meta?.trim() ?? '';

    return Container(
      padding: EdgeInsets.fromLTRB(16, compact ? 12 : 14, 14, compact ? 12 : 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(compact ? 16 : 20),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          // The face first, where an event card starts with its title. Whose
          // to-do it is, is the question a household asks of one of these
          // before it asks what it says.
          Semantics(
            label: who.label,
            excludeSemantics: true,
            child: WhoAvatars(who: who, size: 26, fontSize: 10.5),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StrikeThrough(
                  progress: strike,
                  color: AppColors.doneInk,
                  child: Text(
                    task.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.itemTitle.copyWith(color: Color.lerp(AppColors.ink, AppColors.doneInk, strike)),
                  ),
                ),
                // Skipped whole rather than rendered empty — an empty `Text`
                // still takes a line, which is what put a gap under the title of
                // a note-less card.
                if (!compact && note.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Opacity(
                    opacity: 1 - 0.45 * strike,
                    child: Text(note, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.label),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          CheckOffButton(progress: strike, accent: accent, onTap: onCheckOff, size: 26, filled: true),
        ],
      ),
    );
  }
}

/// One event's card in the agenda.
///
/// **Every card is white.** The live event used to be filled with the accent
/// tint, which put a blue card between two white ones for as long as it ran —
/// and since an all-day event is "live" for its whole span, a day with Ferien
/// and a bin pickup on it was blue/white/blue before anything had even started.
/// The rail beside the card already says where the day is (filled dot, accent
/// line, accent time), so the fill was saying it a second time and louder.
class _EventCard extends StatelessWidget {
  final CalendarEvent event;
  final bool compact;

  /// Resolved by the row, which has the `ref` — the card stays a pure render of
  /// what it is handed. Null when there is no forecast for this event, which is
  /// the common case for anything in the past.
  ///
  /// The card takes no accent any more: the forecast icon used to be tinted
  /// with it, and it is the one thing here that draws itself.
  final WeatherReading? weather;

  /// How many lists and how many tasks were made from this appointment. Counts
  /// rather than the rows themselves: the card shows a marker, and the sheet
  /// behind it is where they can be read and opened.
  final int linkedLists;
  final int linkedTasks;

  const _EventCard({
    required this.event,
    this.compact = false,
    this.weather,
    this.linkedLists = 0,
    this.linkedTasks = 0,
  });

  @override
  Widget build(BuildContext context) {
    // An event with nothing typed under its title gets no subtitle line at all
    // — an empty `Text` still occupies a full line, which is where the gap
    // between title and chips on a bare card was coming from.
    final subtitle = event.body.trim();
    final showSubtitle = !compact && subtitle.isNotEmpty;

    return Container(
      padding: EdgeInsets.fromLTRB(16, compact ? 13 : 16, 16, compact ? 14 : 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(compact ? 16 : 20),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(event.title, style: AppText.itemTitle),
          if (showSubtitle) ...[
            const SizedBox(height: 5),
            Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.body.copyWith(color: AppColors.inkTertiary)),
          ],
          const SizedBox(height: 11),
          Row(
            children: [
              // Takes the avatar's old spot, so the title above no longer
              // reserves corner space for it. An event with no forecast — one
              // in the past, or further out than Open-Meteo reaches — shows no
              // placeholder at all rather than an empty slot.
              if (weather != null) ...[
                // Bigger than the 18 the Lucide glyph sat at: a Meteocons file
                // carries its own padding inside a 128 viewBox, so the drawing
                // fills about two thirds of whatever it is given.
                SvgPicture.asset(weather!.iconAsset, width: 26, height: 26),
                const SizedBox(width: 5),
                Text(weather!.temperatureLabel, style: AppText.groupHeading.copyWith(letterSpacing: 0, color: AppColors.ink)),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _Chip(bg: AppColors.surfaceAlt, child:Row(children: [
                        Container(width: 7, height: 7, decoration: BoxDecoration(color: event.srcColor, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text(event.source, style: AppText.microLabel.copyWith(color: AppColors.inkSecondary)),
                      ])),
                      const SizedBox(width: 7),
                      _Chip(bg: AppColors.surfaceAlt, child:Text(event.durationLabel, style: AppText.microLabel)),
                      // The lists and tasks hung off this appointment: a
                      // marker, not a button — the card is already one tap
                      // target and the detail sheet behind it is where they can
                      // actually be read. An icon small enough to fit here is
                      // far too small to aim at inside a card this size. It carries the tab's
                      // own icon so the row says *where* the thing is without a
                      // word — which is the whole job of a 12pt glyph on a card
                      // you read at arm's length while getting three people out
                      // of the door.
                      //
                      // Two chips rather than one summed count: "2" over a
                      // clipboard means two lists, and pooling them would make
                      // the packing list and the dentist reminder into a number
                      // that names neither.
                      if (linkedLists > 0) ...[
                        const SizedBox(width: 7),
                        _Chip(
                          bg: AppColors.surfaceAlt,
                          child: Row(children: [
                            AppIcon(AppIcons.listChecks, size: 12, color: AppColors.inkSecondary),
                            const SizedBox(width: 5),
                            Text(
                              L.s.linkedListCount(linkedLists),
                              style: AppText.microLabel.copyWith(color: AppColors.inkSecondary),
                            ),
                          ]),
                        ),
                      ],
                      if (linkedTasks > 0) ...[
                        const SizedBox(width: 7),
                        _Chip(
                          bg: AppColors.surfaceAlt,
                          child: Row(children: [
                            // The check the Board create sheet puts on
                            // "To-do", not the Board tab's grid: the chip
                            // counts tasks, and a grid beside a clipboard read
                            // as a table rather than as a to-do.
                            AppIcon(AppIcons.checkCircle, size: 12, color: AppColors.inkSecondary),
                            const SizedBox(width: 5),
                            Text(
                              L.s.linkedTaskCount(linkedTasks),
                              style: AppText.microLabel.copyWith(color: AppColors.inkSecondary),
                            ),
                          ]),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final Color bg;
  final Widget child;

  const _Chip({required this.bg, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: child,
    );
  }
}

/// Liquid-glass "Heute" button shown whenever today's date has scrolled out of
/// view (week view: today isn't in the displayed week; month view: today's day
/// cell isn't in the viewport). Tapping it re-selects today and (in month
/// view) scrolls back to it. [_JumpToTodaySlot] places it.
///
/// A [FloatingGlassPill] in its nav-row shape, and **the word on its own** —
/// the come-and-go is shared with Board's and Listen's "Rückgängig", but this
/// one stands a finger's width from the bar's calendar icon, and any calendar
/// glyph on it reads as a duplicate of that icon rather than as a different
/// offer. The word is also the shorter of the two, in both languages.
class _JumpToTodayButton extends StatelessWidget {
  final bool visible;
  final Color accent;
  final VoidCallback onTap;

  const _JumpToTodayButton({required this.visible, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FloatingGlassPill(
      visible: visible,
      label: L.s.today,
      accent: accent,
      onNavRow: true,
      onTap: onTap,
    );
  }
}
