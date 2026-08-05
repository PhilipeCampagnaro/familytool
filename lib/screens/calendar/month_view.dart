part of '../calendar_screen.dart';

// ---------------------------------------------------------------------------
// Month view
// ---------------------------------------------------------------------------

/// Infinite, bidirectionally-scrolling month view (Apple Calendar-style): the
/// legend + weekday header stay fixed, and each visible month is a lazily
/// built [_MonthBlock] below/above a stable `center` sliver anchored on the
/// real "today" month — scrolling never runs out in either direction.
class _MonthView extends ConsumerStatefulWidget {
  final CalendarScreenState state;
  final Color accent;

  const _MonthView({required this.state, required this.accent});

  @override
  ConsumerState<_MonthView> createState() => _MonthViewState();
}

class _MonthViewState extends ConsumerState<_MonthView> {
  final Key _centerKey = UniqueKey();
  final GlobalKey _todayCellKey = GlobalKey();
  final GlobalKey _viewportKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  bool _todayVisible = true;

  // The month/year + view-toggle row and the calendar chip row (see
  // _buildHeader) — the part of the header that fades away as the grid
  // scrolls, leaving just the title (shrunk + centered) and the filter
  // dropdown that stands in for the chips + the add button. 16 top padding +
  // 40 toggle row + 14 gap + 40 chip row + 16 bottom padding. Driven directly
  // off `_scrollController.offset` (rather than a NestedScrollView sliver, as
  // the week view uses) since this scroll view already needs its own
  // controller for the "Heute" visibility check below, and a
  // `center:`-anchored CustomScrollView doesn't compose with
  // NestedScrollView's overlap-injection contract.
  static const _extraHeaderHeight = 126.0;
  double _headerT = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _scheduleVisibilityCheck();
  }

  void _onScroll() {
    final next = (_scrollController.offset / _extraHeaderHeight).clamp(0.0, 1.0);
    if (next != _headerT) setState(() => _headerT = next);
    _scheduleVisibilityCheck();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // The scroll listener fires the instant `.offset` changes, before that
  // frame's layout/paint has run — reading render-box positions right then
  // would see last frame's (stale) geometry. Defer to a post-frame callback
  // so the check runs once the new scroll position has actually been laid out.
  void _scheduleVisibilityCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateTodayVisibility();
    });
  }

  /// Checks whether today's day cell (keyed via [_todayCellKey], only ever
  /// attached to the one cell in the `monthOffset == 0` block) currently
  /// intersects the scroll viewport — driving the floating "Heute" button.
  void _updateTodayVisibility() {
    final todayCtx = _todayCellKey.currentContext;
    final viewportCtx = _viewportKey.currentContext;
    bool visible;
    if (todayCtx == null || viewportCtx == null) {
      visible = false;
    } else {
      final todayBox = todayCtx.findRenderObject() as RenderBox;
      final viewportBox = viewportCtx.findRenderObject() as RenderBox;
      final offset = todayBox.localToGlobal(Offset.zero, ancestor: viewportBox);
      visible = offset.dy + todayBox.size.height > 0 && offset.dy < viewportBox.size.height;
    }
    if (visible != _todayVisible) setState(() => _todayVisible = visible);
  }

  void _jumpToToday() {
    ref.read(calendarProvider.notifier).selectDayToday();
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
    }
  }

  /// The collapsing part of the header: title (shrinking + centering via
  /// [_TitleRow], same as the week view), with the month/year + toggle row
  /// and the calendar chips fading away underneath as [_headerT] goes 0 (top
  /// of the grid) to 1 (scrolled in) — at which point the filter dropdown
  /// fades into the title row to stand in for the chips.
  Widget _buildHeader(BuildContext context, CalendarScreenState state, Color accent, String monthLabel) {
    final t = _headerT;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 8, AppSpacing.screenPad, 0),
          child: _TitleRow(
            t: t,
            onAdd: () => _openNewEventSheet(context, ref),
            leading: _CalendarFilterButton(state: state),
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
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 16, AppSpacing.screenPad, 16),
                  child: _ToggleAndChipsRow(state: state, accent: accent, monthLabel: monthLabel),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final accent = widget.accent;
    final monthLabel = L.s.monthYear(state.selected.m, state.selected.y);
    // Each key appears only once the thing it explains can: Feiertage need a
    // household we have reason to place in Germany, Ferien need the feed to be
    // subscribed. A key to a wash that never shows up is worse than no key.
    final marksHolidays = ref.watch(germanHolidaysProvider).enabled;
    final marksFerien = state.hasFerienFeed;

    return Column(
      children: [
        _buildHeader(context, state, accent, monthLabel),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 6, AppSpacing.screenPad, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              // A Wrap, not a Row: three keys fit on one line in German and
              // don't in English ("Events per calendar / Public holiday /
              // School holidays"), and a legend that overflows its line is a
              // yellow-and-black striped bar across the calendar.
              Wrap(
                spacing: 18,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _LegendEntry(
                    label: L.s.eventsPerCalendar,
                    swatch: SizedBox(
                      width: 13,
                      height: 8,
                      child: Stack(children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.srcOutlook, shape: BoxShape.circle, border: Border.fromBorderSide(BorderSide(color: AppColors.surface, width: 1.5)))),
                        Positioned(left: 5, child: Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.srcIserv, shape: BoxShape.circle, border: Border.fromBorderSide(BorderSide(color: AppColors.surface, width: 1.5))))),
                      ]),
                    ),
                  ),
                  if (marksHolidays)
                    _LegendEntry(
                      label: L.s.publicHoliday,
                      swatch: _DayHighlightSwatch(highlight: DayHighlight.publicHoliday, accent: accent),
                    ),
                  if (marksFerien)
                    _LegendEntry(
                      label: L.s.schoolHoliday,
                      swatch: _DayHighlightSwatch(highlight: DayHighlight.schoolHoliday, accent: accent),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [for (final l in dayLetters) Expanded(child: SizedBox(height: 26, child: Center(child: Text(l, style: AppText.label.copyWith(fontWeight: FontWeight.w500)))))],
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            key: _viewportKey,
            children: [
              CustomScrollView(
                controller: _scrollController,
                center: _centerKey,
                slivers: [
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _MonthBlock(monthOffset: -i - 1, state: state, accent: accent, todayCellKey: _todayCellKey),
                    ),
                  ),
                  SliverList(
                    key: _centerKey,
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _MonthBlock(monthOffset: i, state: state, accent: accent, todayCellKey: _todayCellKey),
                    ),
                  ),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: navContentInset(context, pill: 106, gap: 36),
                child: Center(
                  child: _JumpToTodayButton(visible: !_todayVisible, accent: accent, onTap: _jumpToToday),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One month's heading, day grid, and (if its selected day lives in this
/// month and is expanded) the inline day-detail card — the same widgets
/// [_MonthView] used to render for a single fixed month, now repeated per
/// scrolled-to month so every month behaves identically to "current setup".
class _MonthBlock extends ConsumerWidget {
  final int monthOffset;
  final CalendarScreenState state;
  final Color accent;
  final GlobalKey? todayCellKey;

  const _MonthBlock({required this.monthOffset, required this.state, required this.accent, this.todayCellKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (year, month) = _monthAt(monthOffset);
    final holidays = ref.watch(germanHolidaysProvider).inMonth(year, month);
    final ferien = state.schoolHolidaysIn(year, month);
    final firstOfMonth = DateTime(year, month, 1);
    final lead = (firstOfMonth.weekday + 6) % 7;
    final len = DateTime(year, month + 1, 0).day;

    final sel = state.selected;
    final isSelectedMonth = sel.y == year && sel.m == month;
    final selDate = DateTime(sel.y, sel.m, sel.d);
    final headingText = _isToday(sel.y, sel.m, sel.d)
        ? L.s.todayWithDate(sel.d, sel.m)
        : L.s.weekdayWithDate(selDate.weekday % 7, sel.d, sel.m);
    final dayEvents = isSelectedMonth ? state.eventsFor(sel.y, sel.m, sel.d) : const <CalendarEvent>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 20, AppSpacing.screenPad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(L.s.monthYear(month, year), style: AppText.sectionHeading),
          const SizedBox(height: 10),
          for (var row = 0; row < ((lead + len) / 7).ceil(); row++)
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: _MonthCell(
                      key: (monthOffset == 0 && row * 7 + col - lead + 1 == calToday().day) ? todayCellKey : null,
                      index: row * 7 + col,
                      lead: lead,
                      len: len,
                      year: year,
                      month: month,
                      state: state,
                      accent: accent,
                      holidays: holidays,
                      ferien: ferien,
                    ),
                  ),
              ],
            ),
          if (isSelectedMonth)
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 280),
              sizeCurve: Curves.easeOutCubic,
              firstCurve: Curves.easeOut,
              secondCurve: Curves.easeIn,
              crossFadeState: state.monthDetailExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity, height: 0),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  decoration: BoxDecoration(color: AppColors.screenBg, borderRadius: BorderRadius.all(Radius.circular(20))),
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(child: Text(headingText, overflow: TextOverflow.ellipsis, style: AppText.itemTitle)),
                          const SizedBox(width: 8),
                          Text(L.s.eventCount(dayEvents.length), style: AppText.label),
                        ],
                      ),
                      if (isSelectedMonth && holidays[sel.d] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _HolidayChip(holiday: holidays[sel.d]!, accent: accent),
                        ),
                      const SizedBox(height: 10),
                      if (dayEvents.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Column(
                            children: [
                              Text(L.s.noEventsThisDay, style: AppText.body.copyWith(color: AppColors.inkTertiary)),
                              const SizedBox(height: 14),
                              const _EmptyDayActions(),
                            ],
                          ),
                        )
                      else
                        for (var i = 0; i < dayEvents.length; i++)
                          _EventAgendaRow(
                            event: dayEvents[i],
                            isFirst: i == 0,
                            headingText: headingText,
                            accent: accent,
                            compact: true,
                          ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small source-colour dots under a day, overlapping by 0.5px like the
/// reference design (Flutter disallows negative padding/margin, so the
/// overlap is done via Stack + Positioned offsets instead).
class _MonthCell extends ConsumerWidget {
  final int index;
  final int lead;
  final int len;
  final int year;
  final int month;
  final CalendarScreenState state;
  final Color accent;

  /// This month's Feiertage, keyed by day of the month — see
  /// [germanHolidaysProvider].
  final Map<int, GermanHoliday> holidays;

  /// This month's Schulferien days, from the subscribed Ferien feed.
  final Set<int> ferien;

  const _MonthCell({super.key, required this.index, required this.lead, required this.len, required this.year, required this.month, required this.state, required this.accent, required this.holidays, required this.ferien});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (index < lead || index - lead >= len) return const SizedBox(height: 50);
    final n = index - lead + 1;
    final isSel = _sameDay(state.selected, year, month, n);
    final isToday = _isToday(year, month, n);
    final highlight = _dayHighlight(publicHoliday: holidays.containsKey(n), schoolHoliday: ferien.contains(n));
    final colors = state.dayColors(year, month, n);
    final dots = colors.take(3).toList();
    final overflowCount = colors.length - 3;

    return GestureDetector(
      onTap: () => ref.read(calendarProvider.notifier).selectDay(year, month, n),
      child: SizedBox(
        height: 50,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DaySelectorCircle(
              day: n,
              selected: isSel,
              today: isToday,
              highlight: highlight,
              accent: accent,
              size: 38,
              fontSize: 15,
              unselectedFill: Colors.transparent,
              unselectedTextColor: AppColors.ink,
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 8,
              child: Center(child: EventDots(colors: dots, overflowCount: overflowCount)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one place the two day-off marks are ranked, so the month grid and the
/// week strip can't disagree. Karfreitag falls inside the Osterferien and the
/// 25th inside the Weihnachtsferien: on those days the Feiertag is the more
/// specific fact, so it takes the circle.
DayHighlight _dayHighlight({required bool publicHoliday, required bool schoolHoliday}) => publicHoliday
    ? DayHighlight.publicHoliday
    : (schoolHoliday ? DayHighlight.schoolHoliday : DayHighlight.none);

/// One "swatch — label" pair in the month grid's legend.
class _LegendEntry extends StatelessWidget {
  final Widget swatch;
  final String label;

  const _LegendEntry({required this.swatch, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        swatch,
        const SizedBox(width: 7),
        Text(label, style: AppText.label.copyWith(color: AppColors.inkTertiary)),
      ],
    );
  }
}

/// A miniature of a day circle in one of its day-off states, painted by the
/// same rules [DaySelectorCircle] uses — including the hatch, so the Feiertag
/// key looks like a Feiertag rather than like the flatter Ferien wash next to
/// it. The two differ by texture first and shade second; a flat swatch for both
/// would have made the legend the one place they were indistinguishable.
class _DayHighlightSwatch extends StatelessWidget {
  final DayHighlight highlight;
  final Color accent;

  const _DayHighlightSwatch({required this.highlight, required this.accent});

  @override
  Widget build(BuildContext context) {
    final fill = highlight == DayHighlight.publicHoliday ? tint(accent, .86) : tint(accent, .93);
    return Container(
      width: 13,
      height: 13,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      child: highlight == DayHighlight.publicHoliday
          ? ClipOval(
              child: CustomPaint(
                painter: DiagonalStripePainter(color: AppColors.holidayNumber.withValues(alpha: 0.16)),
                size: const Size.square(13),
              ),
            )
          : null,
    );
  }
}

/// Names the Feiertag a striped day circle stands for — "Tag der Deutschen
/// Einheit" rather than a tint the family has to guess at. Used by both the
/// month view's day-detail card and the week view's agenda, so the answer is in
/// the same place whichever way the day was reached.
///
/// A chip rather than an agenda row on purpose: a Feiertag is a property of the
/// day, not an appointment in it, and putting it in the timeline would give it
/// a time it doesn't have and a swipe-to-edit it can't honour.
class _HolidayChip extends StatelessWidget {
  final GermanHoliday holiday;
  final Color accent;

  const _HolidayChip({required this.holiday, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
      decoration: BoxDecoration(color: tint(accent, .86), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.partyPopper, size: 14, color: AppColors.holidayNumber),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              L.s.germanHolidayName(holiday),
              overflow: TextOverflow.ellipsis,
              style: AppText.label.copyWith(color: AppColors.holidayNumber, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
