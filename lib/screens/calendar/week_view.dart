part of '../calendar_screen.dart';

// ---------------------------------------------------------------------------
// Week view
// ---------------------------------------------------------------------------

class _WeekView extends ConsumerStatefulWidget {
  final CalendarScreenState state;
  final Color accent;

  const _WeekView({required this.state, required this.accent});

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
class _WeekViewState extends ConsumerState<_WeekView> {
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

  /// Leftmost fully-visible day, driven by the strip's scroll position. The
  /// month/year header follows this rather than the selected day: on a strip
  /// you can scroll freely without selecting, a header pinned to the selection
  /// would sit there naming a month that's nowhere on screen.
  DateTime _stripAnchor = calToday();

  /// Whether today is currently on screen in the strip — drives the "Heute"
  /// button, which now tracks the strip rather than the selected week.
  bool _todayVisible = true;

  CalSelectedDay? _lastSelected;

  @override
  void initState() {
    super.initState();
    _stripController.addListener(_onStripScroll);
    _lastSelected = widget.state.selected;
  }

  @override
  void dispose() {
    _stripController.dispose();
    super.dispose();
  }

  void _onStripScroll() {
    if (_stripItemExtent <= 0 || !_stripController.hasClients) return;
    final firstIndex = (_stripController.offset / _stripItemExtent).round().clamp(0, _stripDayCount - 1);
    final anchor = _stripDate(firstIndex);
    final todayIndex = _stripIndexOf(calToday());
    final todayVisible = todayIndex >= firstIndex && todayIndex < firstIndex + 7;
    if (anchor != _stripAnchor || todayVisible != _todayVisible) {
      setState(() {
        _stripAnchor = anchor;
        _todayVisible = todayVisible;
      });
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
    // Land the day third-from-left so there's context on both sides of it.
    final target = ((index - 2) * _stripItemExtent).clamp(0.0, _stripController.position.maxScrollExtent);
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
  // 16 top + 40 toggle row + 14 + 40 chip row + 12 + the strip + 4 bottom,
  // rounded up so a font-metric wobble leaves slack rather than clipping.
  static const _extraHeaderHeight = 240.0;
  static const _expandedHeaderHeight = _collapsedHeaderHeight + _extraHeaderHeight;

  Widget _buildHeader(BuildContext context, double t, CalendarScreenState state, Color accent, String monthLabel) {
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
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 16, AppSpacing.screenPad, 0),
                          child: _ToggleAndChipsRow(state: state, accent: accent, monthLabel: monthLabel),
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

  // Weekday letter + gap + the rounded day tile (dots, gap, 34pt day circle).
  static const _stripHeight = 110.0;

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
    final headingIsToday = _isToday(sel.y, sel.m, sel.d);
    final headingText = headingIsToday
        ? L.s.todayWithDate(sel.d, sel.m)
        : L.s.weekdayWithDate(selDate.weekday % 7, sel.d, sel.m);
    // The header names whatever month the strip is actually showing, not the
    // selected day's — see _stripAnchor.
    final monthLabel = L.s.monthYear(_stripAnchor.month, _stripAnchor.year);
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
                builder: (context, t) => _buildHeader(context, t, state, accent, monthLabel),
              ),
            ),
          ],
          body: _AgendaGrayBody(
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
                key: ValueKey('${sel.y}-${sel.m}-${sel.d}-${state.calendarFilter}'),
                // The Feiertag sits above the agenda rather than in it — it is
                // something about the day, not an appointment on it. A day off
                // with nothing planned is still worth saying, so it shows over
                // the empty state too.
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (holiday != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _HolidayChip(holiday: holiday, accent: accent),
                      ),
                    Expanded(
                      child: events.isEmpty
                          ? Padding(
                              padding: EdgeInsets.only(bottom: navContentInset(context)),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(L.s.noEventsThisDay, style: AppText.body.copyWith(color: AppColors.inkTertiary)),
                                    const SizedBox(height: 18),
                                    const _EmptyDayActions(),
                                  ],
                                ),
                              ),
                            )
                          : ListView(
                              padding: EdgeInsets.only(bottom: navContentInset(context)),
                              children: [
                                for (var i = 0; i < events.length; i++)
                                  _EventAgendaRow(
                                    event: events[i],
                                    isFirst: i == 0,
                                    headingText: headingText,
                                    accent: accent,
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: navContentInset(context, pill: 106, gap: 36),
          child: Center(
            child: _JumpToTodayButton(
              visible: !_todayVisible,
              accent: accent,
              onTap: _jumpToToday,
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
        icon: LucideIcons.calendarPlus,
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

/// Full-width, top-rounded gray body used below the fixed header on both the
/// week view (day strip above the agenda) — kept as its own widget so the
/// gray body treatment can't visually drift from the rest of the screen.
class _AgendaGrayBody extends StatelessWidget {
  final Widget child;

  const _AgendaGrayBody({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.screenBg, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      padding: const EdgeInsets.fromLTRB(14, 20, 16, 0),
      child: child,
    );
  }
}

class _DayStripCell extends ConsumerWidget {
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

    return GestureDetector(
      onTap: () => ref.read(calendarProvider.notifier).selectDay(date.year, date.month, date.day),
      child: Column(
        children: [
          Text(letter, style: AppText.rowTitle.copyWith(color: isSel ? AppColors.ink : AppColors.muted)),
          const SizedBox(height: 9),
          Container(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
            decoration: BoxDecoration(color: isSel ? tint(accent, .9) : AppColors.screenBg, borderRadius: BorderRadius.circular(22)),
            child: Column(
              children: [
                SizedBox(
                  height: 8,
                  child: Center(child: EventDots(colors: dots, overflowCount: overflowCount)),
                ),
                const SizedBox(height: 14),
                DaySelectorCircle(day: date.day, selected: isSel, today: today, highlight: highlight, accent: accent),
              ],
            ),
          ),
        ],
      ),
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
                  borderRadius: BorderRadius.circular(compact ? 16 : 20),
                  onTap: () {
                    ref.read(calendarProvider.notifier).openEvent(event, headingText);
                    _showEventDetailSheet(context, ref);
                  },
                  actions: [
                    if (editable) ...[
                      SwipeAction(
                        icon: LucideIcons.pencil,
                        color: accent,
                        // No need to open the event first: the edit sheet is
                        // seeded from the row it was swiped on.
                        onTap: () => _openEditEventSheet(context, ref, event),
                      ),
                      SwipeAction(
                        icon: LucideIcons.trash,
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

  const _EventCard({required this.event, this.compact = false, this.weather});

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

/// Floating liquid-glass "Heute" pill shown above the bottom nav whenever
/// today's date has scrolled out of view (week view: today isn't in the
/// displayed week; month view: today's day cell isn't in the viewport).
/// Tapping it re-selects today and (in month view) scrolls back to it.
///
/// Nothing but a labelled [FloatingGlassPill] — the shape and its come-and-go
/// are shared with Board's and Listen's "Rückgängig".
class _JumpToTodayButton extends StatelessWidget {
  final bool visible;
  final Color accent;
  final VoidCallback onTap;

  const _JumpToTodayButton({required this.visible, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FloatingGlassPill(
      visible: visible,
      icon: LucideIcons.calendarCheck,
      label: L.s.today,
      accent: accent,
      onTap: onTap,
    );
  }
}
