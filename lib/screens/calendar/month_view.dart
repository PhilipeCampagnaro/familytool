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

    return Column(
      children: [
        _buildHeader(context, state, accent, monthLabel),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 6, AppSpacing.screenPad, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 13,
                    height: 8,
                    child: Stack(children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.srcOutlook, shape: BoxShape.circle, border: Border.fromBorderSide(BorderSide(color: AppColors.surface, width: 1.5)))),
                      Positioned(left: 5, child: Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.srcIserv, shape: BoxShape.circle, border: Border.fromBorderSide(BorderSide(color: AppColors.surface, width: 1.5))))),
                    ]),
                  ),
                  const SizedBox(width: 7),
                  Text(L.s.eventsPerCalendar, style: AppText.label.copyWith(color: AppColors.inkTertiary)),
                  const SizedBox(width: 18),
                  Container(width: 13, height: 13, decoration: BoxDecoration(color: tint(accent, .86), shape: BoxShape.circle)),
                  const SizedBox(width: 7),
                  Text(L.s.holiday, style: AppText.label.copyWith(color: AppColors.inkTertiary)),
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
class _MonthBlock extends StatelessWidget {
  final int monthOffset;
  final CalendarScreenState state;
  final Color accent;
  final GlobalKey? todayCellKey;

  const _MonthBlock({required this.monthOffset, required this.state, required this.accent, this.todayCellKey});

  @override
  Widget build(BuildContext context) {
    final (year, month) = _monthAt(monthOffset);
    final holidays = state.holidaysIn(year, month);
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
  final Set<int> holidays;

  const _MonthCell({super.key, required this.index, required this.lead, required this.len, required this.year, required this.month, required this.state, required this.accent, required this.holidays});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (index < lead || index - lead >= len) return const SizedBox(height: 50);
    final n = index - lead + 1;
    final isSel = _sameDay(state.selected, year, month, n);
    final isToday = _isToday(year, month, n);
    final holiday = holidays.contains(n);
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
              holiday: holiday,
              accent: accent,
              size: 38,
              fontSize: 15,
              unselectedFill: Colors.transparent,
              unselectedTextColor: AppColors.ink,
              holidayFill: tint(accent, .86),
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
